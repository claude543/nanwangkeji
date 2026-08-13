function [mode,dP_raw,dP_request,agc_update_allowed, ...
    reconstruction_request,recovery_active,reason, ...
    trust1,trust2,trust3,trust4,trust5,trust6,recovery_alpha_used, ...
    isolated1,isolated2,isolated3,isolated4,isolated5,isolated6] = ...
    Strategy7_Coordination_Recovery_V03_ISOLATION_SCALAR( ...
    t,enable,Ptarget,Ppcc,cmd_valid,meas_valid, ...
    state1,state2,state3,state4,state5,state6, ...
    reconstruction_done,recovery_done,recovery_alpha_external)
% Strategy7_Coordination_Recovery_V03_ISOLATION_SCALAR
%
% 策略7 V0.3：持续执行失配资源隔离 + 剩余资源恢复协调
%
% 论文分层：
%   Strategy2：
%       识别逐设备执行状态
%
%   Strategy7：
%       NORMAL / HOLD / RECONSTRUCTION / RECOVERY
%       对“持续执行失配资源”做监督层隔离
%       形成trust1~6和dP_request
%
%   Improved AGC：
%       在trust=1的剩余资源中按当前有效能力重新分配dP_request
%
% 模式：
%   0 INACTIVE
%   1 NORMAL
%   2 HOLD
%   3 RECONSTRUCTION
%   4 RECOVERY
%
% V0.3新增：
%   1) 某非隔离资源持续state=3达到T_ISOLATE_CONFIRM后，
%      Strategy7将其isolation_latch置1；
%   2) 已隔离资源不再阻止系统从HOLD进入RECONSTRUCTION；
%   3) 已隔离资源的trust永久置0（本次运行期间）；
%   4) 其余可信资源可在RECOVERY/NORMAL继续承担dP_request；
%   5) 当前V5前本地版不实现“隔离资源重新加入”。
%      isolation只在enable关闭/模型重启时清除。
%
% 注意：
%   T_ISOLATE_CONFIRM及恢复时间均为V5前候选参数。
%   V5后需根据真实通信与设备恢复机制重新冻结。
%
%#codegen

MODE_INACTIVE = 0.0;
MODE_NORMAL   = 1.0;
MODE_HOLD     = 2.0;
MODE_RECON    = 3.0;
MODE_RECOVERY = 4.0;

% V5前候选参数
T_CLEAR_CONFIRM    = 0.50;
T_ISOLATE_CONFIRM  = 0.50;
T_RECON_MIN        = 0.05;
T_RECOVERY_RAMP    = 2.00;
T_RECOVERY_CONFIRM = 0.50;

states = [state1;state2;state3;state4;state5;state6];

persistent mode_i clear_timer recon_timer recovery_timer ...
           recovery_confirm_timer isolate_timer isolate_latch ...
           hold_reason last_t

if isempty(last_t)
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    recon_timer = 0.0;
    recovery_timer = 0.0;
    recovery_confirm_timer = 0.0;
    isolate_timer = zeros(6,1);
    isolate_latch = false(6,1);
    hold_reason = 0.0;
    last_t = t;
end

if t < last_t
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    recon_timer = 0.0;
    recovery_timer = 0.0;
    recovery_confirm_timer = 0.0;
    isolate_timer = zeros(6,1);
    isolate_latch = false(6,1);
    hold_reason = 0.0;
    last_t = t;
end

dt = max(t-last_t,0.0);

cmd_ok  = (cmd_valid > 0.5);
meas_ok = (meas_valid > 0.5);

% -------------------------------------------------------------------------
% 计算“未被隔离、仍需要阻断系统”的异常
% -------------------------------------------------------------------------
blocking_mismatch = false;
blocking_untrusted = false;

for i = 1:6
    if ~isolate_latch(i)
        if states(i) >= 2.5
            blocking_mismatch = true;
        end

        if states(i) < 0.5
            blocking_untrusted = true;
        end
    end
end

global_data_invalid = ~(cmd_ok && meas_ok);

current_abnormal_reason = 0.0;

if ~cmd_ok && ~meas_ok
    current_abnormal_reason = 5.0;
elseif ~cmd_ok
    current_abnormal_reason = 3.0;
elseif ~meas_ok
    current_abnormal_reason = 4.0;
elseif blocking_mismatch
    current_abnormal_reason = 2.0;
elseif blocking_untrusted
    current_abnormal_reason = 8.0;
end

abnormal_now = (current_abnormal_reason > 0.5);

% -------------------------------------------------------------------------
% 状态机
% -------------------------------------------------------------------------
if enable <= 0.5

    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    recon_timer = 0.0;
    recovery_timer = 0.0;
    recovery_confirm_timer = 0.0;
    isolate_timer(:) = 0.0;
    isolate_latch(:) = false;
    hold_reason = 0.0;

else

    if mode_i < 0.5
        % INACTIVE -> NORMAL/HOLD
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
        else
            mode_i = MODE_NORMAL;
            hold_reason = 0.0;
        end

        clear_timer = 0.0;
        recon_timer = 0.0;
        recovery_timer = 0.0;
        recovery_confirm_timer = 0.0;

    elseif mode_i < 1.5
        % ================================================================
        % NORMAL
        % ================================================================
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;
            isolate_timer(:) = 0.0;
        end

    elseif mode_i < 2.5
        % ================================================================
        % HOLD
        % ================================================================

        % 全局命令/测量数据不可信：
        % 当前本地版不能做资源隔离判断，只能继续HOLD。
        if global_data_invalid
            clear_timer = 0.0;
            isolate_timer(:) = 0.0;
            hold_reason = current_abnormal_reason;

        else
            % ------------------------------------------------------------
            % 对尚未隔离且state=3的资源累计“持续失配”时间
            % ------------------------------------------------------------
            for i = 1:6
                if ~isolate_latch(i) && states(i) >= 2.5
                    isolate_timer(i) = isolate_timer(i) + dt;
                else
                    isolate_timer(i) = 0.0;
                end
            end

            % 达到持续失配确认时间 -> 隔离
            new_isolation = false;

            for i = 1:6
                if ~isolate_latch(i) && ...
                        isolate_timer(i) >= T_ISOLATE_CONFIRM

                    isolate_latch(i) = true;
                    isolate_timer(i) = 0.0;
                    new_isolation = true;
                end
            end

            % 隔离后重新计算是否仍存在“未管理”的异常
            blocking_mismatch_after = false;
            blocking_untrusted_after = false;

            for i = 1:6
                if ~isolate_latch(i)

                    if states(i) >= 2.5
                        blocking_mismatch_after = true;
                    end

                    if states(i) < 0.5
                        blocking_untrusted_after = true;
                    end
                end
            end

            % ------------------------------------------------------------
            % 情况A：持续故障资源已经被隔离，且无其他阻断异常
            % -> 进入RECONSTRUCTION
            % ------------------------------------------------------------
            if new_isolation && ...
                    ~blocking_mismatch_after && ...
                    ~blocking_untrusted_after

                mode_i = MODE_RECON;
                clear_timer = 0.0;
                recon_timer = 0.0;
                recovery_timer = 0.0;
                recovery_confirm_timer = 0.0;

            % ------------------------------------------------------------
            % 情况B：异常自己恢复（没有发生隔离）
            % -> 保留原有连续清除确认，再进入RECONSTRUCTION
            % ------------------------------------------------------------
            elseif ~blocking_mismatch_after && ...
                    ~blocking_untrusted_after

                clear_timer = clear_timer + dt;

                if clear_timer >= T_CLEAR_CONFIRM
                    mode_i = MODE_RECON;
                    clear_timer = 0.0;
                    recon_timer = 0.0;
                    recovery_timer = 0.0;
                    recovery_confirm_timer = 0.0;
                end

            else
                clear_timer = 0.0;
                hold_reason = current_abnormal_reason;
            end
        end

    elseif mode_i < 3.5
        % ================================================================
        % RECONSTRUCTION
        % 已隔离资源的state=3不再阻断；
        % 新出现的非隔离资源异常仍然重新HOLD。
        % ================================================================
        blocking_after = false;

        if global_data_invalid
            blocking_after = true;
        else
            for i = 1:6
                if ~isolate_latch(i) && ...
                        (states(i) >= 2.5 || states(i) < 0.5)
                    blocking_after = true;
                end
            end
        end

        if blocking_after
            mode_i = MODE_HOLD;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;

        else
            recon_timer = recon_timer + dt;

            if reconstruction_done > 0.5 && ...
                    recon_timer >= T_RECON_MIN

                mode_i = MODE_RECOVERY;
                recovery_timer = 0.0;
                recovery_confirm_timer = 0.0;
            end
        end

    else
        % ================================================================
        % RECOVERY
        % ================================================================
        blocking_after = false;

        if global_data_invalid
            blocking_after = true;
        else
            for i = 1:6
                if ~isolate_latch(i) && ...
                        (states(i) >= 2.5 || states(i) < 0.5)
                    blocking_after = true;
                end
            end
        end

        if blocking_after
            mode_i = MODE_HOLD;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;

        else
            recovery_timer = recovery_timer + dt;

            if recovery_timer >= T_RECOVERY_RAMP
                recovery_confirm_timer = recovery_confirm_timer + dt;
            else
                recovery_confirm_timer = 0.0;
            end

            if recovery_done > 0.5 || ...
                    recovery_confirm_timer >= T_RECOVERY_CONFIRM

                mode_i = MODE_NORMAL;
                hold_reason = 0.0;
                clear_timer = 0.0;
                recon_timer = 0.0;
                recovery_timer = 0.0;
                recovery_confirm_timer = 0.0;
            end
        end
    end
end

% -------------------------------------------------------------------------
% PCC偏差
% -------------------------------------------------------------------------
dP_raw_i = Ptarget - Ppcc;

% -------------------------------------------------------------------------
% RECOVERY alpha
% -------------------------------------------------------------------------
alpha_internal = 0.0;

if mode_i > 3.5
    alpha_internal = min( ...
        max(recovery_timer/max(T_RECOVERY_RAMP,1e-6),0.0),1.0);
end

alpha_external = min(max(recovery_alpha_external,0.0),1.0);

if alpha_external > 0.0
    alpha_used = min(alpha_internal,alpha_external);
else
    alpha_used = alpha_internal;
end

% -------------------------------------------------------------------------
% dP_request / AGC update permission
% -------------------------------------------------------------------------
if mode_i > 0.5 && mode_i < 1.5
    % NORMAL
    dP_request_i = dP_raw_i;
    agc_allow_i = 1.0;

elseif mode_i > 3.5
    % RECOVERY
    dP_request_i = alpha_used*dP_raw_i;
    agc_allow_i = double(alpha_used > 0.0);

else
    % INACTIVE / HOLD / RECONSTRUCTION
    dP_request_i = 0.0;
    agc_allow_i = 0.0;
end

recon_req_i = double(mode_i > 2.5 && mode_i < 3.5);
recovery_i  = double(mode_i > 3.5);

% -------------------------------------------------------------------------
% trust：
%   只有非隔离 + state=1/2 + 全局数据可信 才为1
% -------------------------------------------------------------------------
trust = zeros(6,1);

if cmd_ok && meas_ok
    for i = 1:6
        if ~isolate_latch(i) && ...
                states(i) >= 0.5 && states(i) < 2.5

            trust(i) = 1.0;
        else
            trust(i) = 0.0;
        end
    end
end

% -------------------------------------------------------------------------
% reason
% -------------------------------------------------------------------------
any_isolated = false;
for i = 1:6
    if isolate_latch(i)
        any_isolated = true;
    end
end

if mode_i < 0.5
    reason_i = 0.0;

elseif mode_i < 1.5
    if any_isolated
        reason_i = 9.0; % 正常协调，但存在被管理隔离资源
    else
        reason_i = 1.0;
    end

elseif mode_i < 2.5
    reason_i = hold_reason;

elseif mode_i < 3.5
    reason_i = 6.0;

else
    reason_i = 7.0;
end

% -------------------------------------------------------------------------
% 输出
% -------------------------------------------------------------------------
mode = mode_i;
dP_raw = dP_raw_i;
dP_request = dP_request_i;
agc_update_allowed = agc_allow_i;
reconstruction_request = recon_req_i;
recovery_active = recovery_i;
reason = reason_i;

trust1 = trust(1);
trust2 = trust(2);
trust3 = trust(3);
trust4 = trust(4);
trust5 = trust(5);
trust6 = trust(6);

recovery_alpha_used = alpha_used;

isolated1 = double(isolate_latch(1));
isolated2 = double(isolate_latch(2));
isolated3 = double(isolate_latch(3));
isolated4 = double(isolate_latch(4));
isolated5 = double(isolate_latch(5));
isolated6 = double(isolate_latch(6));

last_t = t;
end

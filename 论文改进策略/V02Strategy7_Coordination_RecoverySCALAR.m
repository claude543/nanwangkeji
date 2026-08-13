function [mode,dP_raw,dP_request,agc_update_allowed, ...
    reconstruction_request,recovery_active,reason, ...
    trust1,trust2,trust3,trust4,trust5,trust6,recovery_alpha_used] = ...
    Strategy7_Coordination_Recovery_V02_SCALAR( ...
    t,enable,Ptarget,Ppcc,cmd_valid,meas_valid, ...
    state1,state2,state3,state4,state5,state6, ...
    reconstruction_done,recovery_done,recovery_alpha_external)
% Strategy7_Coordination_Recovery_V02_SCALAR
%
% 策略7 V0.2：联络线协调 + 状态对齐 + 受控恢复（本地冻结候选版）
%
% 当前论文职责：
%   Strategy2：识别真实执行状态
%   Strategy7：管理 NORMAL/HOLD/RECONSTRUCTION/RECOVERY，并形成dP_request
%   AGC：执行资源状态对齐和功率分配
%
% 模式：
%   0 INACTIVE
%   1 NORMAL
%   2 HOLD
%   3 RECONSTRUCTION
%   4 RECOVERY
%
% V0.2相对V0.1：
%   1) RECONSTRUCTION加入最小停留时间，保证100 Hz日志能够观测；
%   2) RECOVERY内部生成0->1恢复系数；
%   3) dP_request在RECOVERY中按恢复系数逐渐放开；
%   4) 恢复系数达到1并稳定一段时间后自动回NORMAL；
%   5) 外部recovery_done / recovery_alpha_external接口继续保留，
%      为V5以后真实板端握手预留，但当前本地版无需它们也可闭环。
%
% 注意：
%   当前时间参数是V5前本地候选值，不是最终论文冻结值。
%
%#codegen

MODE_INACTIVE = 0.0;
MODE_NORMAL   = 1.0;
MODE_HOLD     = 2.0;
MODE_RECON    = 3.0;
MODE_RECOVERY = 4.0;

% V5前候选时间参数
T_CLEAR_CONFIRM    = 0.50;  % HOLD解除证据持续时间
T_RECON_MIN        = 0.05;  % RECON最小停留50 ms，100Hz日志约5点
T_RECOVERY_RAMP    = 2.00;  % 本地候选：2 s逐步恢复dP
T_RECOVERY_CONFIRM = 0.50;  % alpha=1后再稳定0.5 s回NORMAL

states = [state1;state2;state3;state4;state5;state6];

persistent mode_i clear_timer recon_timer recovery_timer ...
           recovery_confirm_timer hold_reason last_t

if isempty(last_t)
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    recon_timer = 0.0;
    recovery_timer = 0.0;
    recovery_confirm_timer = 0.0;
    hold_reason = 0.0;
    last_t = t;
end

if t < last_t
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    recon_timer = 0.0;
    recovery_timer = 0.0;
    recovery_confirm_timer = 0.0;
    hold_reason = 0.0;
    last_t = t;
end

dt = max(t-last_t,0.0);

cmd_ok  = (cmd_valid > 0.5);
meas_ok = (meas_valid > 0.5);

any_mismatch = false;
any_untrusted = false;

for i = 1:6
    if states(i) >= 2.5
        any_mismatch = true;
    end

    if states(i) < 0.5
        any_untrusted = true;
    end
end

current_abnormal_reason = 0.0;

if ~cmd_ok && ~meas_ok
    current_abnormal_reason = 5.0;
elseif ~cmd_ok
    current_abnormal_reason = 3.0;
elseif ~meas_ok
    current_abnormal_reason = 4.0;
elseif any_mismatch
    current_abnormal_reason = 2.0;
elseif any_untrusted
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
    hold_reason = 0.0;

else

    if mode_i < 0.5
        % 初次投入
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
        % NORMAL
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;
        end

    elseif mode_i < 2.5
        % HOLD
        if abnormal_now
            clear_timer = 0.0;
            hold_reason = current_abnormal_reason;
        else
            clear_timer = clear_timer + dt;

            if clear_timer >= T_CLEAR_CONFIRM
                mode_i = MODE_RECON;
                clear_timer = 0.0;
                recon_timer = 0.0;
                recovery_timer = 0.0;
                recovery_confirm_timer = 0.0;
            end
        end

    elseif mode_i < 3.5
        % RECONSTRUCTION
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;

        else
            recon_timer = recon_timer + dt;

            % 必须同时满足：
            % AGC已经完成对齐
            % + RECON最小停留时间
            if reconstruction_done > 0.5 && recon_timer >= T_RECON_MIN
                mode_i = MODE_RECOVERY;
                recovery_timer = 0.0;
                recovery_confirm_timer = 0.0;
            end
        end

    else
        % RECOVERY
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
            recon_timer = 0.0;
            recovery_timer = 0.0;
            recovery_confirm_timer = 0.0;

        else
            recovery_timer = recovery_timer + dt;

            % 内部恢复完成判据：
            % alpha达到1后再持续稳定T_RECOVERY_CONFIRM。
            if recovery_timer >= T_RECOVERY_RAMP
                recovery_confirm_timer = recovery_confirm_timer + dt;
            else
                recovery_confirm_timer = 0.0;
            end

            % 保留外部done接口：
            % V5以后若真实板端有更严格的恢复完成握手，可直接利用。
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
% 客观PCC偏差
% -------------------------------------------------------------------------
dP_raw_i = Ptarget - Ppcc;

% -------------------------------------------------------------------------
% RECOVERY恢复系数
% 当前优先使用内部时间斜坡。
% 外部alpha > 0时允许作为更保守的上限/未来接口。
% -------------------------------------------------------------------------
alpha_internal = 0.0;

if mode_i > 3.5
    alpha_internal = min(max(recovery_timer/max(T_RECOVERY_RAMP,1e-6),0.0),1.0);
end

alpha_external = min(max(recovery_alpha_external,0.0),1.0);

if alpha_external > 0.0
    % 若未来外部提供alpha，取两者较小值，保持保守。
    alpha_used = min(alpha_internal,alpha_external);
else
    alpha_used = alpha_internal;
end

% -------------------------------------------------------------------------
% 当前状态允许AGC处理多少PCC偏差
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
% 六资源可信标志
% state 1/2可信；0/3不可信
% -------------------------------------------------------------------------
trust = zeros(6,1);

if cmd_ok && meas_ok
    for i = 1:6
        if states(i) >= 0.5 && states(i) < 2.5
            trust(i) = 1.0;
        else
            trust(i) = 0.0;
        end
    end
end

% -------------------------------------------------------------------------
% reason
% -------------------------------------------------------------------------
if mode_i < 0.5
    reason_i = 0.0;
elseif mode_i < 1.5
    reason_i = 1.0;
elseif mode_i < 2.5
    reason_i = hold_reason;
elseif mode_i < 3.5
    reason_i = 6.0;
else
    reason_i = 7.0;
end

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

last_t = t;
end

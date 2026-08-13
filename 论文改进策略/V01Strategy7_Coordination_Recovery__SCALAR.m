function [mode,dP_raw,dP_request,agc_update_allowed, ...
    reconstruction_request,recovery_active,reason, ...
    trust1,trust2,trust3,trust4,trust5,trust6] = ...
    Strategy7_Coordination_Recovery_V01_SCALAR( ...
    t,enable,Ptarget,Ppcc,cmd_valid,meas_valid, ...
    state1,state2,state3,state4,state5,state6, ...
    reconstruction_done,recovery_done,recovery_alpha)
% Strategy7_Coordination_Recovery_V01_SCALAR
%
% 策略7 V0.1：联络线协调与恢复管理（旁路/影子版）
%
% 论文职责：
%   策略2：识别“六台设备现在执行得怎么样”
%   策略7：根据执行状态与PCC偏差决定“系统现在处于什么管理阶段”
%   改进AGC：以后根据策略7允许的dP_request和可信资源重新分配
%
% 当前V0.1不直接控制AGC，仅输出候选决策并记录。
%
% 输入：
%   t, enable
%   Ptarget, Ppcc
%   cmd_valid, meas_valid
%   state1~state6：策略2六设备执行状态
%   reconstruction_done：状态对齐完成握手；当前本地第一轮固定0
%   recovery_done：恢复完成握手；当前本地第一轮固定0
%   recovery_alpha：RECOVERY阶段允许处理dP的比例；当前第一轮固定0
%
% 模式：
%   0 = INACTIVE        未投入
%   1 = NORMAL          正常协调
%   2 = HOLD            保持/暂停继续推进
%   3 = RECONSTRUCTION  状态对齐
%   4 = RECOVERY        受控恢复
%
% reason：
%   0 = inactive
%   1 = normal
%   2 = execution mismatch
%   3 = command invalid
%   4 = measurement invalid
%   5 = command & measurement invalid
%   6 = reconstruction pending
%   7 = recovery
%   8 = execution state untrusted
%
% 注意：
%   V0.1中的HOLD清除确认时间只是本地状态机验证候选值，
%   不是V5后最终论文参数。
%
%#codegen

MODE_INACTIVE = 0.0;
MODE_NORMAL   = 1.0;
MODE_HOLD     = 2.0;
MODE_RECON    = 3.0;
MODE_RECOVERY = 4.0;

T_CLEAR_CONFIRM = 0.50;  % V0.1本地候选值，V5后再冻结

states = [state1;state2;state3;state4;state5;state6];

persistent mode_i clear_timer hold_reason last_t

if isempty(last_t)
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
    hold_reason = 0.0;
    last_t = t;
end

if t < last_t
    mode_i = MODE_INACTIVE;
    clear_timer = 0.0;
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

% 当前异常原因优先级
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

    elseif mode_i < 1.5
        % NORMAL
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
        end

    elseif mode_i < 2.5
        % HOLD
        if abnormal_now
            clear_timer = 0.0;
            hold_reason = current_abnormal_reason;
        else
            clear_timer = clear_timer + dt;

            % 异常证据解除后不直接NORMAL，
            % 先进入RECONSTRUCTION。
            if clear_timer >= T_CLEAR_CONFIRM
                mode_i = MODE_RECON;
                clear_timer = 0.0;
            end
        end

    elseif mode_i < 3.5
        % RECONSTRUCTION
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
        elseif reconstruction_done > 0.5
            mode_i = MODE_RECOVERY;
            clear_timer = 0.0;
        end

    else
        % RECOVERY
        if abnormal_now
            mode_i = MODE_HOLD;
            hold_reason = current_abnormal_reason;
            clear_timer = 0.0;
        elseif recovery_done > 0.5
            mode_i = MODE_NORMAL;
            hold_reason = 0.0;
            clear_timer = 0.0;
        end
    end
end

% -------------------------------------------------------------------------
% PCC偏差
% 始终记录客观偏差：
%   dP_raw = Ptarget - Ppcc
% -------------------------------------------------------------------------
dP_raw_i = Ptarget - Ppcc;

% -------------------------------------------------------------------------
% 状态下允许送给AGC的候选调节需求
% 当前只是shadow输出，不接AGC。
% -------------------------------------------------------------------------
alpha = min(max(recovery_alpha,0.0),1.0);

if mode_i > 0.5 && mode_i < 1.5
    % NORMAL
    dP_request_i = dP_raw_i;
    agc_allow_i = 1.0;

elseif mode_i > 3.5
    % RECOVERY
    dP_request_i = alpha*dP_raw_i;
    agc_allow_i = double(alpha > 0.0);

else
    % INACTIVE / HOLD / RECONSTRUCTION
    dP_request_i = 0.0;
    agc_allow_i = 0.0;
end

recon_req_i = double(mode_i > 2.5 && mode_i < 3.5);
recovery_i  = double(mode_i > 3.5);

% -------------------------------------------------------------------------
% 逐资源可信标志
% state=1或2：当前执行证据仍可信
% state=0或3：当前不作为可信资源
% 若命令或测量全局不可信，则六资源全部置0
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
% reason输出
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

% 标量输出
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

last_t = t;
end

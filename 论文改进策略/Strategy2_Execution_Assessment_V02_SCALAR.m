function [ ...
    pexp1,pexp2,pexp3,pexp4,pexp5,pexp6, ...
    res1,res2,res3,res4,res5,res6, ...
    state1,state2,state3,state4,state5,state6,overall] = ...
    Strategy2_Execution_Assessment_V02_SCALAR( ...
    t,assess_enable,cmd_valid,meas_valid, ...
    cmd1,cmd2,cmd3,cmd4,cmd5,cmd6, ...
    meas1,meas2,meas3,meas4,meas5,meas6)
% Strategy2_Execution_Assessment_V02_SCALAR
% 策略2：逐DER执行状态评估 V0.2
%
% 论文职责边界：
%   本模块只做“执行状态识别”，不直接冻结AGC、不切换系统运行模式，
%   不决定NORMAL/HOLD/RECONSTRUCTION/RECOVERY。
%   这些属于后续策略7。
%
% 设备顺序：
%   1 PV1, 2 PV2, 3 ESS1, 4 ESS2, 5 EV1, 6 EV2
%
% 状态：
%   0 = UNTRUSTED  当前不可评估/数据不可信
%   1 = TRACKED    已稳定执行
%   2 = RESPONDING 正常响应中
%   3 = MISMATCH   已确认执行失配
%
% V0.2相对V0.1的核心变化：
%   1) 一旦MISMATCH确认，进入“失配保持”；
%   2) 后续新AGC命令不会把state=3自动清成state=2；
%   3) 只有真实执行重新进入正常允许带，并且持续满足恢复确认条件，
%      才解除MISMATCH；
%   4) cmd_valid/meas_valid任一无效时输出UNTRUSTED，但内部失配记忆不丢失。
%
%#codegen

N = 6;

Pcmd  = [cmd1;cmd2;cmd3;cmd4;cmd5;cmd6];
Pmeas = [meas1;meas2;meas3;meas4;meas5;meas6];

% ---------- 来自2026-08-12专门阶跃辨识的正常动态参数 ----------
TAU = [0.47;0.47;0.50;0.50;0.52;0.52];
TAU_MEAS = 0.10;

% ---------- V0.1已验证参数 ----------
EPS0 = 0.020;
K_DYN = 0.30;
T_BAD_CONFIRM = 0.30;
T_RESP = 1.60;
CMD_EPS = 0.005;
SETTLE_GAP = 0.030;

% ---------- V0.2新增：恢复确认 ----------
% 先作为候选参数验证，不在代码层宣称“最终冻结”
T_RECOVER_CONFIRM = 0.50;

persistent pexp pfilt last_cmd bad_timer good_timer since_cmd ...
           mismatch_latch last_t initialized

if isempty(last_t)
    pexp = zeros(N,1);
    pfilt = zeros(N,1);
    last_cmd = zeros(N,1);
    bad_timer = zeros(N,1);
    good_timer = zeros(N,1);
    since_cmd = zeros(N,1);
    mismatch_latch = false(N,1);
    last_t = t;
    initialized = false;
end

% Target时间回绕/重新开始
if t < last_t
    pexp = zeros(N,1);
    pfilt = zeros(N,1);
    last_cmd = zeros(N,1);
    bad_timer = zeros(N,1);
    good_timer = zeros(N,1);
    since_cmd = zeros(N,1);
    mismatch_latch = false(N,1);
    last_t = t;
    initialized = false;
end

dt = max(t-last_t,0.0);

cmd_finite = true;
meas_finite = true;
for i = 1:N
    if ~isfinite(Pcmd(i))
        cmd_finite = false;
    end
    if ~isfinite(Pmeas(i))
        meas_finite = false;
    end
end

cmd_ok = (cmd_valid > 0.5) && cmd_finite;
meas_ok = (meas_valid > 0.5) && meas_finite;

residual = zeros(N,1);
state = zeros(N,1);
overall_i = 0.0;

% -------------------------------------------------------------------------
% 评估未投入：
% 贴合当前物理状态，避免投入瞬间产生假残差。
% 这里代表算法真正未启用，不等同于“通信数据暂时无效”。
% -------------------------------------------------------------------------
if assess_enable <= 0.5

    if meas_ok
        for i = 1:N
            pfilt(i) = Pmeas(i);
            pexp(i) = Pmeas(i);
        end
    end

    if cmd_ok
        for i = 1:N
            last_cmd(i) = Pcmd(i);
        end
    end

    for i = 1:N
        bad_timer(i) = 0.0;
        good_timer(i) = 0.0;
        since_cmd(i) = 0.0;
        mismatch_latch(i) = false;
    end

    initialized = false;

else

    % 第一次正式投入
    if ~initialized

        if meas_ok
            for i = 1:N
                pfilt(i) = Pmeas(i);
                pexp(i) = Pmeas(i);
            end
        end

        if cmd_ok
            for i = 1:N
                last_cmd(i) = Pcmd(i);
            end
        end

        for i = 1:N
            bad_timer(i) = 0.0;
            good_timer(i) = 0.0;
            since_cmd(i) = 0.0;
            mismatch_latch(i) = false;
        end

        initialized = true;
    end

    % ---------------------------------------------------------------------
    % 最后有效命令更新
    %
    % 关键变化：
    % 如果某设备已经MISMATCH，新的AGC命令只更新“当前预期目标”，
    % 但不能清除mismatch_latch。
    % 同时清零good_timer，要求在“最新命令”下重新积累恢复证据。
    % ---------------------------------------------------------------------
    if cmd_ok
        for i = 1:N

            if abs(Pcmd(i)-last_cmd(i)) > CMD_EPS

                last_cmd(i) = Pcmd(i);
                since_cmd(i) = 0.0;

                if mismatch_latch(i)
                    % 已确认失配：
                    % 新命令不能洗掉失配，只重新开始恢复证据计时
                    good_timer(i) = 0.0;
                else
                    % 尚未确认失配：
                    % 正常新命令开始新的响应窗口
                    bad_timer(i) = 0.0;
                end

            else
                since_cmd(i) = since_cmd(i) + dt;
            end

        end
    else
        for i = 1:N
            since_cmd(i) = since_cmd(i) + dt;
        end
    end

    % ---------------------------------------------------------------------
    % 正常设备预期响应
    % ---------------------------------------------------------------------
    for i = 1:N
        a = min(dt/max(TAU(i),1e-6),1.0);
        pexp(i) = pexp(i) + a*(last_cmd(i)-pexp(i));
    end

    % ---------------------------------------------------------------------
    % Pmeas平滑
    % ---------------------------------------------------------------------
    if meas_ok
        am = min(dt/max(TAU_MEAS,1e-6),1.0);

        for i = 1:N
            pfilt(i) = pfilt(i) + am*(Pmeas(i)-pfilt(i));
        end
    end

    residual = pfilt - pexp;

    % ---------------------------------------------------------------------
    % 数据不可信：
    % 对外输出UNTRUSTED。
    % 但不清mismatch_latch，避免通信短暂无效被误认为“设备恢复”。
    % ---------------------------------------------------------------------
    if ~(cmd_ok && meas_ok)

        for i = 1:N
            bad_timer(i) = 0.0;
            good_timer(i) = 0.0;
            state(i) = 0.0;
        end

        overall_i = 0.0;

    else

        for i = 1:N

            dyn_gap = abs(last_cmd(i)-pexp(i));
            band_i = EPS0 + K_DYN*dyn_gap;

            % =============================================================
            % 已经确认MISMATCH：保持失配，直到真实恢复证据充分
            % =============================================================
            if mismatch_latch(i)

                state(i) = 3.0;

                % 恢复必须同时满足：
                % 1) 实际执行重新回到正常允许带；
                % 2) 正常预期本身已经接近当前命令，不再只是过渡巧合；
                % 3) 上述条件连续保持T_RECOVER_CONFIRM。
                if abs(residual(i)) <= band_i && dyn_gap <= SETTLE_GAP

                    good_timer(i) = good_timer(i) + dt;

                else

                    good_timer(i) = 0.0;

                end

                if good_timer(i) >= T_RECOVER_CONFIRM

                    mismatch_latch(i) = false;
                    good_timer(i) = 0.0;
                    bad_timer(i) = 0.0;

                    if since_cmd(i) < T_RESP || dyn_gap > SETTLE_GAP
                        state(i) = 2.0;
                    else
                        state(i) = 1.0;
                    end

                end

            % =============================================================
            % 尚未确认MISMATCH：执行正常检测
            % =============================================================
            else

                if abs(residual(i)) > band_i

                    bad_timer(i) = bad_timer(i) + dt;

                else

                    bad_timer(i) = 0.0;

                end

                if bad_timer(i) >= T_BAD_CONFIRM

                    mismatch_latch(i) = true;
                    good_timer(i) = 0.0;
                    state(i) = 3.0;

                elseif since_cmd(i) < T_RESP || dyn_gap > SETTLE_GAP

                    state(i) = 2.0;

                else

                    state(i) = 1.0;

                end

            end

        end

        % 六设备汇总
        overall_i = 1.0;

        for i = 1:N

            if state(i) >= 2.5
                overall_i = 3.0;

            elseif state(i) >= 1.5 && overall_i < 2.0
                overall_i = 2.0;
            end

        end

    end

end

% -------------------------------------------------------------------------
% 全标量输出，保持与V0.1完全相同的外部接口和19维日志结构
% -------------------------------------------------------------------------
pexp1 = pexp(1);
pexp2 = pexp(2);
pexp3 = pexp(3);
pexp4 = pexp(4);
pexp5 = pexp(5);
pexp6 = pexp(6);

res1 = residual(1);
res2 = residual(2);
res3 = residual(3);
res4 = residual(4);
res5 = residual(5);
res6 = residual(6);

state1 = state(1);
state2 = state(2);
state3 = state(3);
state4 = state(4);
state5 = state(5);
state6 = state(6);

overall = overall_i;

last_t = t;
end

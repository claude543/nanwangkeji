function [Ppv1_pu,Ppv2_pu,Pess1_pu,Pess2_pu,Pev1_pu,Pev2_pu, ...
    agc_status,dP,remain,reconstruction_done, ...
    eff1_kw,eff2_kw,eff3_kw,eff4_kw,eff5_kw,eff6_kw,eff_total_kw] = ...
    AGC_Controller_Effective_Reallocation_V01( ...
    t,P_target_kW,P_pcc_kW,Ppvmax1_kW,Ppvmax2_kW,SOC1,SOC2,enable, ...
    P_unit_kW,P_dead_kW,SOC_min,SOC_max,Ts_agc,PV_init_kW,EV_init_kW, ...
    supervisory_update_allowed,dP_request_kW,reconstruction_request, ...
    Pexec1_pu,Pexec2_pu,Pexec3_pu,Pexec4_pu,Pexec5_pu,Pexec6_pu, ...
    trust1,trust2,trust3,trust4,trust5,trust6)
% AGC_Controller_Effective_Reallocation_V01
%
% 改进AGC V0.1：真实执行状态对齐 + 当前有效能力重分配
%
% 保留原基础AGC的资源级优先顺序：
%   dP > 0：PV增加 -> ESS放电 -> EV减少充电
%   dP < 0：EV增加充电 -> ESS充电 -> PV降低
%
% 相对基础AGC的改进：
%   1) Strategy7决定AGC是否允许更新，并提供dP_request；
%   2) RECONSTRUCTION时使用Strategy2真实执行估计对齐Ppv/Pess/Pev；
%   3) 每次分配不再只看理论上下限，而是计算“当前有效调节余量”；
%   4) 有效余量 = 当前物理余量 × Strategy7资源可信系数；
%   5) trust=0的资源本轮有效余量为0，任务自动转移给其他资源。
%
% 当前Strategy7输出的trust是0/1。
% 本AGC按[0,1]连续值处理，为以后连续可信度/可用度接口预留空间。
%
% 输出eff1~6：
%   当前dP_request方向上的六设备有效调节余量(kW)
%   顺序：PV1 PV2 ESS1 ESS2 EV1 EV2
%
%#codegen

P_UNIT = max(abs(P_unit_kW),1e-6);
P_DEAD = max(P_dead_kW,0.0);
SOC_LOW = min(SOC_min,SOC_max);
SOC_HIGH = max(SOC_min,SOC_max);
T_UPDATE = max(Ts_agc,1e-6);

persistent Ppv Pess Pev last_t status last_dP last_remain recon_handled

if isempty(Ppv)
    pvInit = clamp(PV_init_kW,0.0,P_UNIT);
    evInit = clamp(EV_init_kW,0.0,P_UNIT);

    Ppv = [min(max(Ppvmax1_kW,0.0),pvInit), ...
           min(max(Ppvmax2_kW,0.0),pvInit)];

    Pess = [0.0,0.0];
    Pev = [evInit,evInit];

    last_t = -1.0;
    status = 0.0;
    last_dP = 0.0;
    last_remain = 0.0;
    recon_handled = false;
end

pvmax = [clamp(Ppvmax1_kW,0.0,P_UNIT), ...
         clamp(Ppvmax2_kW,0.0,P_UNIT)];

Ppv = min(max(Ppv,0.0),pvmax);
Pess = min(max(Pess,-P_UNIT),P_UNIT);
Pev = min(max(Pev,0.0),P_UNIT);

if t < last_t
    last_t = -1.0;
    recon_handled = false;
end

reconstruction_done = 0.0;

if reconstruction_request <= 0.5
    recon_handled = false;
end

Pexec = [Pexec1_pu;Pexec2_pu;Pexec3_pu; ...
         Pexec4_pu;Pexec5_pu;Pexec6_pu];

exec_ok = true;

for i = 1:6
    if ~isfinite(Pexec(i))
        exec_ok = false;
    end
end

% 策略7可信系数限制到[0,1]
trust = [clamp(trust1,0.0,1.0); ...
         clamp(trust2,0.0,1.0); ...
         clamp(trust3,0.0,1.0); ...
         clamp(trust4,0.0,1.0); ...
         clamp(trust5,0.0,1.0); ...
         clamp(trust6,0.0,1.0)];

% 当前ESS物理上下限
essUpper = [P_UNIT,P_UNIT];
essLower = [-P_UNIT,-P_UNIT];

if SOC1 <= SOC_LOW
    essUpper(1) = 0.0;
end

if SOC2 <= SOC_LOW
    essUpper(2) = 0.0;
end

if SOC1 >= SOC_HIGH
    essLower(1) = 0.0;
end

if SOC2 >= SOC_HIGH
    essLower(2) = 0.0;
end

% -------------------------------------------------------------------------
% 当前dP_request方向的有效调节余量
% -------------------------------------------------------------------------
eff = zeros(6,1);

if dP_request_kW > P_DEAD

    % 微电网净出力需要增加
    eff(1) = trust(1)*max(pvmax(1)-Ppv(1),0.0);
    eff(2) = trust(2)*max(pvmax(2)-Ppv(2),0.0);

    eff(3) = trust(3)*max(essUpper(1)-Pess(1),0.0);
    eff(4) = trust(4)*max(essUpper(2)-Pess(2),0.0);

    % EV减少充电：Pev正幅值向0下降
    eff(5) = trust(5)*max(Pev(1),0.0);
    eff(6) = trust(6)*max(Pev(2),0.0);

elseif dP_request_kW < -P_DEAD

    % 微电网净出力需要降低
    % EV增加充电
    eff(5) = trust(5)*max(P_UNIT-Pev(1),0.0);
    eff(6) = trust(6)*max(P_UNIT-Pev(2),0.0);

    % ESS向充电方向移动
    eff(3) = trust(3)*max(Pess(1)-essLower(1),0.0);
    eff(4) = trust(4)*max(Pess(2)-essLower(2),0.0);

    % PV降低
    eff(1) = trust(1)*max(Ppv(1),0.0);
    eff(2) = trust(2)*max(Ppv(2),0.0);
end

eff1_kw = eff(1);
eff2_kw = eff(2);
eff3_kw = eff(3);
eff4_kw = eff(4);
eff5_kw = eff(5);
eff6_kw = eff(6);
eff_total_kw = sum(eff);

if enable > 0.5

    % =====================================================================
    % 优先级1：状态对齐
    % =====================================================================
    if reconstruction_request > 0.5

        if exec_ok

            if ~recon_handled

                % PV
                Ppv(1) = clamp(Pexec1_pu*P_UNIT,0.0,pvmax(1));
                Ppv(2) = clamp(Pexec2_pu*P_UNIT,0.0,pvmax(2));

                % ESS：正放电、负充电
                Pess(1) = clamp(Pexec3_pu*P_UNIT,-P_UNIT,P_UNIT);
                Pess(2) = clamp(Pexec4_pu*P_UNIT,-P_UNIT,P_UNIT);

                % EV内部保存正的充电功率幅值
                Pev(1) = clamp(-Pexec5_pu*P_UNIT,0.0,P_UNIT);
                Pev(2) = clamp(-Pexec6_pu*P_UNIT,0.0,P_UNIT);

                last_t = t;
                status = 0.0;
                last_dP = 0.0;
                last_remain = 0.0;

                recon_handled = true;
            end

            reconstruction_done = 1.0;
        end

    % =====================================================================
    % 优先级2：允许时执行有效能力重分配
    % =====================================================================
    elseif supervisory_update_allowed > 0.5 && ...
            (last_t < 0.0 || (t-last_t) >= T_UPDATE)

        last_t = t;

        dPnow = dP_request_kW;
        rem = abs(dPnow);
        status = 0.0;

        if abs(dPnow) > P_DEAD

            if dPnow > 0.0
                % ---------------------------------------------------------
                % 正方向：PV -> ESS放电 -> EV减少充电
                % ---------------------------------------------------------
                status = 1.0;

                hPV = [ ...
                    trust(1)*max(pvmax(1)-Ppv(1),0.0), ...
                    trust(2)*max(pvmax(2)-Ppv(2),0.0)];

                [Ppv,used] = alloc_up_margin(Ppv,hPV,rem);
                rem = rem-used;

                hESS = [ ...
                    trust(3)*max(essUpper(1)-Pess(1),0.0), ...
                    trust(4)*max(essUpper(2)-Pess(2),0.0)];

                [Pess,used] = alloc_up_margin(Pess,hESS,rem);
                rem = rem-used;

                hEV = [ ...
                    trust(5)*max(Pev(1),0.0), ...
                    trust(6)*max(Pev(2),0.0)];

                [Pev,used] = alloc_down_margin(Pev,hEV,rem);
                rem = rem-used;

            else
                % ---------------------------------------------------------
                % 负方向：EV增加充电 -> ESS充电 -> PV降低
                % ---------------------------------------------------------
                status = -1.0;

                hEV = [ ...
                    trust(5)*max(P_UNIT-Pev(1),0.0), ...
                    trust(6)*max(P_UNIT-Pev(2),0.0)];

                [Pev,used] = alloc_up_margin(Pev,hEV,rem);
                rem = rem-used;

                hESS = [ ...
                    trust(3)*max(Pess(1)-essLower(1),0.0), ...
                    trust(4)*max(Pess(2)-essLower(2),0.0)];

                [Pess,used] = alloc_down_margin(Pess,hESS,rem);
                rem = rem-used;

                hPV = [ ...
                    trust(1)*max(Ppv(1),0.0), ...
                    trust(2)*max(Ppv(2),0.0)];

                [Ppv,used] = alloc_down_margin(Ppv,hPV,rem);
                rem = rem-used;
            end

            if rem > P_DEAD
                status = 2.0*sign(dPnow);
            end
        end

        last_dP = dPnow;
        last_remain = max(rem,0.0);
    end
end

Ppv1_pu = Ppv(1)/P_UNIT;
Ppv2_pu = Ppv(2)/P_UNIT;

Pess1_pu = Pess(1)/P_UNIT;
Pess2_pu = Pess(2)/P_UNIT;

Pev1_pu = -Pev(1)/P_UNIT;
Pev2_pu = -Pev(2)/P_UNIT;

agc_status = status;
dP = last_dP;
remain = last_remain;

end

function [x,used] = alloc_up_margin(x,margin,req)

total = max(margin(1),0.0)+max(margin(2),0.0);
used = 0.0;

if req > 0.0 && total > 0.0
    used = min(req,total);

    x(1) = x(1)+used*max(margin(1),0.0)/total;
    x(2) = x(2)+used*max(margin(2),0.0)/total;
end
end

function [x,used] = alloc_down_margin(x,margin,req)

total = max(margin(1),0.0)+max(margin(2),0.0);
used = 0.0;

if req > 0.0 && total > 0.0
    used = min(req,total);

    x(1) = x(1)-used*max(margin(1),0.0)/total;
    x(2) = x(2)-used*max(margin(2),0.0)/total;
end
end

function y = clamp(x,lo,hi)
y = min(max(x,lo),hi);
end

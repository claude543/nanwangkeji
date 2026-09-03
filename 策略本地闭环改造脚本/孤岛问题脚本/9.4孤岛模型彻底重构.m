%% PATCH_K26_V5_FINAL_PLANNED_ISLAND_V3_4.m
% K26_V5 — 第一版完整六设备计划离岛工程重构
%
% 目标
% ----
% 在当前 V2 正式模型基础上，一次性完成：
%   1) ESS1 继续作为唯一 GFM，F21/F24/F25 及已冻结 GFM 内环不改；
%   2) 五台 GFL 不再使用 V2 “Stage2 极端隔离 / Stage3 恢复旧P/Q”哲学；
%   3) SM_Master 新增统一系统阶段 + 中央岛态有功协调；
%   4) 复用原 24 维三组任务向量，不扩宽 OpComm：
%        Fref  -> 五台岛态下承载中央校验 + 一拍延迟后的 ESS1 Fout；
%        Vref  -> 五台岛态下承载统一慢速电压恢复目标；
%        Droop -> 仅对五台 GFL 改作统一系统阶段；
%        Pref  -> 五台岛态下一次P-f + 慢速协调后的最终中央有功命令；
%        Qref/GridOn 保留现有意义；
%   5) 五台 AA15_ISLAND_GFL_SUPPORT_MANAGER 全部重写：
%        two-band VFF / 本地电压支撑 / EV欠压减充电 /
%        执行比例 anti-windup / 最终矢量限流 / FrameHold request；
%   6) 五台 FrameHold 重写：
%        健康 -> 本机 PLL；
%        hold请求必须来自UnitDelay状态；
%        低压/hold -> 最后有效本机角 + 中央一拍延迟ESS1 Fout推进；
%        恢复 -> 相位连续重新捕获本机 PLL；
%   7) G26/G27/G28 仍保持每台 41 路；
%   8) G29 重映射为中央协调/资源/系统证据，宽度仍 38；
%   9) G30 保持当前 ESS1/F21/F22/F24/F25 128 路，不修改；
%  10) 正常并网 stage=0 时新控制 exact bypass；
%  11) 所有第一 Build 参数运行时可调。
%
% 统一阶段（AA15_FINAL_SYSTEM_STAGE）
% -----------------------------------
%   0 GRID_NORMAL
%   1 ISLAND_PREPARE
%   2 ISLAND_PRIMARY
%   3 ISLAND_SECONDARY
%   4 RESYNC_HOLD
%   5 GRID_RECOVERY
%
% V3.1修正
% ---------
% - 修复V3.0中把J2_PCC_Measurements内部Gain/Gain1/Gain3/Saturation1
%   跨层直接连接到SM_Master新模块的错误。
% - 最终统一使用J2子系统顶层Outport：1频率/2P/3Q/4Vab RMS。
% - 保存前和重载后都断言J2四个输出均为标量。
%
% 重要边界
% --------
% - 本脚本不打开 J1、不运行 RT-LAB。
% - 计划离岛的 J1/F21/F24/F25 时序继续由后续统一 Supervisor 执行；
%   但五台阶段只写一个 SM_Master 参数，不再写五个本机 Stage。
% - 第一轮物理运行只验证：并网 -> 计划离岛 -> 稳定孤岛。
% - 当前 S15 重同步结构保留，但第一轮不主动请求重同步。
%
% 事务
% ----
% 当前V2结构硬预检
% -> scratch 编译三个新核心
% -> 完整SLX备份
% -> 一次结构编辑
% -> 完整模型显式 compile
% -> 五台新子系统无悬空普通端口
% -> 新 manager/frame/coordinator 无代数环
% -> 5个OpWrite宽度 82/41/82/38/128
% -> save exactly once
% -> close/reload
% -> persistence compile + postassert
% -> PASS
%
% 任意失败：
% - save 前：磁盘 SLX 不变；
% - save 后：自动恢复整个 SLX 备份。

clearvars;
clc;

MODEL='K26_V5';
AUDITED_MODEL_FILE='D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V5\models\K26_V5\K26_V5.slx';

% =========================================================================
% 第一 Build 冻结基线
% =========================================================================
DEF_TS=0.0001;

DEF_KFAST=0.0;
DEF_KSLOW=0.50;
DEF_VFF_FC=1.0;
DEF_KGAIN_SLEW=0.01;

DEF_KMAG=0.25;
DEF_VSUP_FC=1.0;
DEF_VSUP_DB=0.01;
DEF_VSUP_SLEW=0.001;
DEF_ISUP=[0.20 0.20 0.30 0.15 0.15];

DEF_IMAX=1.20;

DEF_FRAME_HOLD=0.85;
DEF_FRAME_RELEASE=0.95;

DEF_UV_START=0.95;
DEF_UV_FULL=0.85;

DEF_KPF_SUM=0.50;
DEF_PF_FC=2.0;
DEF_PF_DB_HZ=0.02;

DEF_KI_F_SECONDARY=0.80;
DEF_SEC_ENTRY_S=0.00;
DEF_SEC_SLEW_PU_S=0.20;

DEF_KI_V_SECONDARY=0.20;
% Supervisor约在J1+0.20s进入Stage3；有功慢速协调立即开始，电压慢速恢复再延迟0.30s => 约J1+0.50s。
DEF_VSEC_DELAY_STAGE3_S=0.30;
DEF_VSEC_LIMIT_PU=0.05;
DEF_VSEC_SLEW_PU_S=0.02;

DEF_VNOM=10000.0;

% 五台固定身份
NAMES={'PV1','PV2','ESS2','EV1','EV2'};
ROLES=[1 1 2 3 3];

STAMP=datestr(now,'yyyymmdd_HHMMSS');
LOG_FILE=['9.04_PATCH_K26_V5_FINAL_PLANNED_ISLAND_V3_4_' STAMP '.txt'];

fid=fopen(LOG_FILE,'w','n','UTF-8');
if fid<0,error('Cannot create patch log.');end
cleanupFid=onCleanup(@() fclose(fid));

logf(fid,repmat('=',1,190));
logf(fid,'K26_V5 FINAL PLANNED-ISLAND PATCH V3.1');
logf(fid,'[ROLE] ESS1 only GFM; PV1/PV2/ESS2/EV1/EV2 remain GFL.');
logf(fid,'[RUN TYPE] Next physical run is full planned-island control, not a single-variable diagnostic.');
logf(fid,'[COMM] Preserve existing 24-scalar PV/ESS/EV group vectors.');
logf(fid,repmat('=',1,190));

% =========================================================================
% 0. HARD INTERLOCK + loaded model baseline
% =========================================================================
if ~bdIsLoaded(MODEL),error('PATCH ABORT: open current K26_V5 first.');end
if ~strcmpi(get_param(MODEL,'SimulationStatus'),'stopped')
    error('PATCH ABORT: K26_V5 must be STOPPED.');
end
if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('PATCH ABORT: model Dirty=%s. Save/restore intended V2 first.',get_param(MODEL,'Dirty'));
end

modelFile=resolveLoadedModelFile(MODEL,AUDITED_MODEL_FILE,fid);
if isempty(modelFile)
    error('PATCH ABORT: cannot resolve current K26_V5.slx.');
end
sha0=fileSha256(modelFile);
logf(fid,'[MODEL] %s',modelFile);
logf(fid,'[SHA BEFORE] %s',sha0);

SM=[MODEL '/SM_Master'];
CTRLS={ ...
    [MODEL '/SS_Slave3/PV1_Control'], ...
    [MODEL '/SS_Slave3/PV2_Control'], ...
    [MODEL '/SS_Slave2/ESS2_Control'], ...
    [MODEL '/SS_Slave/EV1_Control'], ...
    [MODEL '/SS_Slave/Control System'] ...
};

IOMUX={ ...
    [SM '/PV1_IO_Mux12'], ...
    [SM '/PV2_IO_Mux12'], ...
    [SM '/ESS2_IO_Mux12'], ...
    [SM '/EV1_IO_Mux'], ...
    [SM '/EV2_IO_Mux'] ...
};

PMEAS_GOTO={ ...
    [SM '/V4_SRC_PV1_P_MEAS'], ...
    [SM '/V4_SRC_PV2_P_MEAS'], ...
    [SM '/V4_SRC_ESS2_P_MEAS'], ...
    [SM '/V4_SRC_EV1_P_MEAS'], ...
    [SM '/V4_SRC_EV2_P_MEAS'] ...
};

OPPATHS={ ...
    [MODEL '/SS_Slave/AA15_ROOTDIAG_EV12_OPWRITE_G26'], ...
    [MODEL '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'], ...
    [MODEL '/SS_Slave3/AA15_ROOTDIAG_PV12_OPWRITE_G28'], ...
    [SM '/AA15_FREQDIAG_SM_OPWRITE_G29'], ...
    [MODEL '/SS_Slave2/AA15_FREQDIAG_ESS1_OPWRITE_G30'] ...
};
OPNAMES={'G26','G27','G28','G29','G30'};
EXPECTED_OPWIDTHS=[82 41 82 38 128];

TAPS=[SM '/AA15_AGC_INPUT_TAPS'];
MASTER_DEMUX=[SM '/AA15_D1_FAST_DEMUX18'];
J2=[SM '/J2_PCC_Measurements'];

% =========================================================================
% 1. CURRENT V2 HARD PREFLIGHT
% =========================================================================
logf(fid,'\n--- 1. CURRENT V2 HARD PREFLIGHT ---');

requireBlock(TAPS);
requireBlock(MASTER_DEMUX);
requireBlock(J2);
% Current J2 contract: out1=Freq, out2=Ppcc_kW, out3=Qpcc_kvar, out4=Vab_rms_pcc.
% Internal blocks are checked only as a V2 fingerprint; all final wiring uses J2 top-level outputs.
requireBlock([J2 '/Gain']);
requireBlock([J2 '/Gain1']);
requireBlock([J2 '/Saturation1']);
requireBlock([J2 '/Gain3']);
requireBlock([SM '/AA15_GATEA_J1_FORCE_OPEN_SWITCH']);

for i=1:5
    dev=NAMES{i};
    ctrl=CTRLS{i};
    mgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
    meas=[ctrl '/Measurements'];
    frame=[meas '/AA15_PLL_EXEC_FRAME_HOLD'];

    requireBlock(ctrl);
    requireBlock(mgr);
    requireBlock(meas);
    requireBlock(frame);
    requireBlock([ctrl '/AA15_ENG_STAGE']);
    requireBlock([ctrl '/AA15_ENG_DIAG_MUX']);
    requireBlock([ctrl '/AA15_ENG_DIAG_OUT41']);
    requireBlock([ctrl '/Power Control Loop']);
    requireBlock([ctrl '/Current Regulator']);
    requireBlock([ctrl '/Droop Control']);
    requireBlock([ctrl '/Droop_On']);
    requireBlock([ctrl '/Fref']);
    requireBlock([ctrl '/Vref']);
    requireBlock([ctrl '/Pref']);
    requireBlock([ctrl '/Qref']);
    requireBlock([ctrl '/From26']);
    requireBlock([ctrl '/From28']);
    requireBlock([ctrl '/From21']);
    requireBlock([ctrl '/From51']);
    requireBlock([ctrl '/Goto18']);

    % 当前V2外部合同
    assertSource(mgr,1,[ctrl '/From26'],1,[dev ' rawV']);
    assertSource(mgr,2,[ctrl '/Power Control Loop'],1,[dev ' rawIpq']);
    assertSource(mgr,3,[ctrl '/From21'],1,[dev ' Pmeas']);
    assertSource(mgr,4,[ctrl '/From51'],1,[dev ' Qmeas']);
    assertSource(mgr,5,[ctrl '/Pref'],1,[dev ' Pref']);
    assertSource(mgr,6,[ctrl '/Qref'],1,[dev ' Qref']);
    assertSource(mgr,7,[ctrl '/From28'],1,[dev ' IdIq measured']);
    assertSource(mgr,8,[ctrl '/AA15_ENG_STAGE'],1,[dev ' old local stage']);

    assertSource([ctrl '/Current Regulator'],1,mgr,1,[dev ' VFF']);
    assertSource([ctrl '/Goto18'],1,mgr,2,[dev ' final Iref']);
    assertSource([ctrl '/Power Control Loop'],3,mgr,3,[dev ' PrefEff']);
    assertSource([ctrl '/Power Control Loop'],6,mgr,4,[dev ' QrefEff']);
    assertSource(meas,5,mgr,18,[dev ' frame hold request']);

    % 当前V2 manager fingerprint
    v2req={ ...
        [mgr '/AA15_P_VFF_FC_HZ'], ...
        [mgr '/AA15_P_KSLOW_STABILIZE'], ...
        [mgr '/AA15_P_KSLOW_RECOVERY'], ...
        [mgr '/AA15_P_KFAST_ISLAND'], ...
        [mgr '/AA15_P_KMAG'], ...
        [mgr '/AA15_P_IMAX'], ...
        [mgr '/AA15_P_ROLE'], ...
        [mgr '/AA15_ENG_STATE_CORE'], ...
        [mgr '/AA15_ENG_LIMIT_CORE'] ...
    };
    for k=1:numel(v2req),requireBlock(v2req{k});end

    % FrameHold current external contract = 3 in / 2 out
    assertSource(frame,1,[meas '/AA15_PLL_NATIVE_FREQ_TO_EXEC'],1,[dev ' native F']);
    assertSource(frame,2,[meas '/AA15_PLL_NATIVE_THETA_TO_EXEC'],1,[dev ' native theta']);
    assertSource(frame,3,[meas '/AA15_B1_HOLD_REQ'],1,[dev ' hold req']);

    requireBlock(IOMUX{i});
    requireBlock(PMEAS_GOTO{i});
    logf(fid,'[V2 DEVICE PASS] %s',dev);
end

% 五组命令向量保持24，不做接口扩宽。
requireBlock([SM '/PV_Group_Mux24']);
requireBlock([SM '/ESS_Group_Mux24']);
requireBlock([SM '/EV_Group_Mux24']);

% 五个OpWrite
opw=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*');
if numel(opw)~=5,error('Expected exactly 5 OpWrite; found %d.',numel(opw));end
for i=1:5,requireBlock(OPPATHS{i});end

% ESS1关键链冻结
ESS1=[MODEL '/SS_Slave2/ESS1_Control'];
ESS_KEEP={ ...
    [ESS1 '/AA15_F24_REFERENCE_HANDOVER_MANAGER'], ...
    [ESS1 '/AA15_F8_VOLTAGE_LOOP_FEEDFORWARD/AA15_F25_IOUT_HANDOVER_MANAGER'], ...
    [ESS1 '/Current Regulator'], ...
    [ESS1 '/Voltage Regulators'], ...
    [ESS1 '/Droop Control'], ...
    [ESS1 '/Switch5'], ...
    [ESS1 '/Vref Generation'] ...
};
for k=1:numel(ESS_KEEP),requireBlock(ESS_KEEP{k});end

% 新名字必须不存在，防止重复Patch。
collisions={ ...
    [SM '/AA15_FINAL_SYSTEM_STAGE'], ...
    [SM '/AA15_FINAL_MASTER_F_DELAY_Z1'], ...
    [SM '/AA15_FINAL_ISLAND_COORDINATOR'], ...
    [SM '/AA15_FINAL_G29_MUX38'] ...
};
for k=1:numel(collisions)
    if blockExists(collisions{k}),error('Patch collision: %s already exists.',collisions{k});end
end

% Strict baseline diagnostic before any formal edit.
% Do not use LEGACY_LOOP_QUERY_API: this RT-LAB/MATLAB environment does not expose
% reliable loop metadata for temporary/compiled diagrams.
logf(fid,'[BASELINE STRICT COMPILE] Temporarily set AlgebraicLoopMsg=error.');
strictCompileWithLoopError(MODEL,fid,'BASELINE-V2');

% Changing a diagnostic can mark the loaded diagram Dirty even after restoring it.
% Reload the untouched disk V2 before starting the actual transaction.
close_system(MODEL,0);
load_system(modelFile);
if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('BASELINE strict diagnostic reload did not return Dirty=off.');
end
logf(fid,'[BASELINE STRICT COMPILE PASS] original V2 passed AlgebraicLoopMsg=error.');

% =========================================================================
% 2. CAPTURE CURRENT SM SOURCE ENDPOINTS BEFORE EDIT
% =========================================================================
logf(fid,'\n--- 2. CAPTURE CURRENT SM SOURCE ENDPOINTS ---');

legacyPref=cell(5,1);
legacyVref=cell(5,1);
legacyFref=cell(5,1);
legacyDroop=cell(5,1);
pmeasEP=cell(5,1);

for i=1:5
    legacyFref{i}=inputSourceEndpoint(IOMUX{i},3);
    legacyVref{i}=inputSourceEndpoint(IOMUX{i},4);
    legacyDroop{i}=inputSourceEndpoint(IOMUX{i},5);
    legacyPref{i}=inputSourceEndpoint(IOMUX{i},6);
    pmeasEP{i}=inputSourceEndpoint(PMEAS_GOTO{i},1);

    logf(fid,'[%s] legacy Fref=%s|out%d',NAMES{i},legacyFref{i}.Block,legacyFref{i}.Port);
    logf(fid,'[%s] legacy Vref=%s|out%d',NAMES{i},legacyVref{i}.Block,legacyVref{i}.Port);
    logf(fid,'[%s] legacy Droop=%s|out%d',NAMES{i},legacyDroop{i}.Block,legacyDroop{i}.Port);
    logf(fid,'[%s] legacy Pref=%s|out%d',NAMES{i},legacyPref{i}.Block,legacyPref{i}.Port);
    logf(fid,'[%s] Pmeas=%s|out%d',NAMES{i},pmeasEP{i}.Block,pmeasEP{i}.Port);
end

% AGC能力源，全部从当前TAPS父端输入线上分支，不复制旧AGC算法。
tapPpv1=inputSourceEndpoint(TAPS,4);
tapPpv2=inputSourceEndpoint(TAPS,5);
tapSOC1=inputSourceEndpoint(TAPS,6);
tapSOC2=inputSourceEndpoint(TAPS,7);
tapPunit=inputSourceEndpoint(TAPS,9);
tapSOCmin=inputSourceEndpoint(TAPS,11);
tapSOCmax=inputSourceEndpoint(TAPS,12);

% =========================================================================
% 3. SCRATCH COMPILE NEW CORES — no real-model edit
% =========================================================================
logf(fid,'\n--- 3. SCRATCH COMPILE NEW CORES ---');
scratchPreflightFinal( ...
    DEF_TS,DEF_KFAST,DEF_KSLOW,DEF_VFF_FC,DEF_KGAIN_SLEW, ...
    DEF_KMAG,DEF_VSUP_FC,DEF_VSUP_DB,DEF_VSUP_SLEW,DEF_ISUP(1),DEF_IMAX, ...
    DEF_FRAME_HOLD,DEF_FRAME_RELEASE,DEF_UV_START,DEF_UV_FULL, ...
    DEF_KPF_SUM,DEF_PF_FC,DEF_PF_DB_HZ,DEF_KI_F_SECONDARY,DEF_SEC_ENTRY_S, ...
    DEF_SEC_SLEW_PU_S,DEF_KI_V_SECONDARY,DEF_VSEC_DELAY_STAGE3_S, ...
    DEF_VSEC_LIMIT_PU,DEF_VSEC_SLEW_PU_S,DEF_VNOM);
logf(fid,'[SCRATCH PASS] final coordinator + GFL manager + master-frequency FrameHold compile.');

% =========================================================================
% 4. FULL SLX BACKUP
% =========================================================================
modelDir=fileparts(modelFile);
backupFile=fullfile(modelDir,['K26_V5__PRE_FINAL_PLANNED_ISLAND_V3_4_' STAMP '.slx']);
[ok,msg]=copyfile(modelFile,backupFile);
if ~ok,error('Full SLX backup failed: %s',msg);end
logf(fid,'[BACKUP PASS] %s',backupFile);

savedToDisk=false;
compiled=false;

try
    % =====================================================================
    % 5. ADD SM FINAL SYSTEM STAGE + CENTRAL COORDINATOR
    % =====================================================================
    logf(fid,'\n--- 5. ADD SM FINAL COORDINATOR ---');

    STAGE=[SM '/AA15_FINAL_SYSTEM_STAGE'];
    add_block('built-in/Constant',STAGE, ...
        'Value','0','SampleTime',num2str(DEF_TS,17), ...
        'Position',[4720 260 4860 290]);

    MASTER_F_Z1=[SM '/AA15_FINAL_MASTER_F_DELAY_Z1'];
    add_block('built-in/UnitDelay',MASTER_F_Z1, ...
        'InitialCondition','50', ...
        'SampleTime',num2str(DEF_TS,17), ...
        'Position',[4720 315 4860 345]);
    connectAbsToInput(MASTER_DEMUX,17,MASTER_F_Z1,1);

    COORD=[SM '/AA15_FINAL_ISLAND_COORDINATOR'];
    addFinalCoordinator(COORD,[4900 200 5700 1050], ...
        DEF_TS,DEF_KPF_SUM,DEF_PF_FC,DEF_PF_DB_HZ, ...
        DEF_KI_F_SECONDARY,DEF_SEC_ENTRY_S,DEF_SEC_SLEW_PU_S, ...
        DEF_KI_V_SECONDARY,DEF_VSEC_DELAY_STAGE3_S,DEF_VSEC_LIMIT_PU, ...
        DEF_VSEC_SLEW_PU_S,DEF_VNOM);

    % Coordinator inputs:
    %  1 stage
    %  2 masterFout
    %  3-7 legacy Pref PV1 PV2 ESS2 EV1 EV2
    %  8-12 Pmeas same order
    % 13 Ppvmax1 kW
    % 14 Ppvmax2 kW
    % 15 SOC1
    % 16 SOC2
    % 17 SOCmin
    % 18 SOCmax
    % 19 Punit kW
    % 20 PCC Vab RMS [V]
    % 21-25 legacy Vref same order
    % 26-30 legacy Fref same order

    connectAbsToInput(STAGE,1,COORD,1);
    connectAbsToInput(MASTER_F_Z1,1,COORD,2);

    for i=1:5
        connectAbsToInput(legacyPref{i}.Block,legacyPref{i}.Port,COORD,2+i);
        connectAbsToInput(pmeasEP{i}.Block,pmeasEP{i}.Port,COORD,7+i);
    end

    connectAbsToInput(tapPpv1.Block,tapPpv1.Port,COORD,13);
    connectAbsToInput(tapPpv2.Block,tapPpv2.Port,COORD,14);
    connectAbsToInput(tapSOC1.Block,tapSOC1.Port,COORD,15);
    connectAbsToInput(tapSOC2.Block,tapSOC2.Port,COORD,16);
    connectAbsToInput(tapSOCmin.Block,tapSOCmin.Port,COORD,17);
    connectAbsToInput(tapSOCmax.Block,tapSOCmax.Port,COORD,18);
    connectAbsToInput(tapPunit.Block,tapPunit.Port,COORD,19);
    connectAbsToInput(J2,4,COORD,20);  % Vab RMS top-level output

    for i=1:5
        connectAbsToInput(legacyVref{i}.Block,legacyVref{i}.Port,COORD,20+i);
        connectAbsToInput(legacyFref{i}.Block,legacyFref{i}.Port,COORD,25+i);
    end

    % Coordinator outputs:
    %  1-5 Pref final
    %  6-10 Vref final
    % 11-15 Fref final
    % 16 master valid
    % 17 dP primary total
    % 18 dP secondary total
    % 19 dV secondary
    % 20-24 up headroom
    % 25-29 down headroom
    % 30 stage echo
    % 31 fail code

    for i=1:5
        connectAbsToInput(COORD,i,IOMUX{i},6);      % Pref
        connectAbsToInput(COORD,5+i,IOMUX{i},4);    % Vref
        connectAbsToInput(COORD,10+i,IOMUX{i},3);   % Fref = validated Fout in island
        connectAbsToInput(COORD,30,IOMUX{i},5);     % Droop field reused as unified GFL stage
    end
    logf(fid,'[SM ROUTE PASS] Existing 24-wide group vectors reused; no width expansion.');

    % =====================================================================
    % 6. REPLACE FIVE GFL MANAGERS + FRAMEHOLD + DIAG41
    % =====================================================================
    logf(fid,'\n--- 6. REPLACE FIVE GFL MANAGERS + FRAMEHOLD + DIAG41 ---');

    for i=1:5
        dev=NAMES{i};
        ctrl=CTRLS{i};
        meas=[ctrl '/Measurements'];
        oldMgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
        oldDiag=[ctrl '/AA15_ENG_DIAG_MUX'];
        oldFrame=[meas '/AA15_PLL_EXEC_FRAME_HOLD'];

        posMgr=get_param(oldMgr,'Position');
        posDiag=get_param(oldDiag,'Position');
        posFrame=get_param(oldFrame,'Position');

        delete_block(oldMgr);
        delete_block(oldDiag);
        delete_block(oldFrame);

        % Old local stage remains only as a harmless runtime artifact; it is no longer used.
        set_param([ctrl '/AA15_ENG_STAGE'],'Value','0');
        if ~blockExists([ctrl '/AA15_OLD_STAGE_TERM'])
            add_block('built-in/Terminator',[ctrl '/AA15_OLD_STAGE_TERM'], ...
                'Position',[1680 1230 1700 1250]);
        end
        connectReplacingInput(ctrl,'AA15_ENG_STAGE/1','AA15_OLD_STAGE_TERM/1','autorouting','on');

        % 五台旧 Droop Control 在GFL角色不参与执行；将其 enable 固定为0，
        % 避免复用 Droop_On 根输入作为SystemStage后污染旧Droop内部。
        if ~blockExists([ctrl '/AA15_FINAL_GFL_DROOP_DISABLED'])
            add_block('built-in/Constant',[ctrl '/AA15_FINAL_GFL_DROOP_DISABLED'], ...
                'Value','0','SampleTime',num2str(DEF_TS,17), ...
                'Position',[1040 1210 1100 1240]);
        end
        connectReplacingInput(ctrl,'AA15_FINAL_GFL_DROOP_DISABLED/1','Droop Control/5','autorouting','on');

        % Measurements增加第6输入：岛态公共MasterF。
        if blockExists([meas '/AA15_MASTER_F_IN'])
            error('[%s] AA15_MASTER_F_IN collision.',dev);
        end
        add_block('built-in/Inport',[meas '/AA15_MASTER_F_IN'], ...
            'Port','6','Position',[55 390 85 410]);

        addMasterFrequencyFrameHold([meas '/AA15_PLL_EXEC_FRAME_HOLD'],posFrame,DEF_TS);

        connectReplacingInput(meas,'AA15_PLL_NATIVE_FREQ_TO_EXEC/1','AA15_PLL_EXEC_FRAME_HOLD/1','autorouting','on');
        connectReplacingInput(meas,'AA15_PLL_NATIVE_THETA_TO_EXEC/1','AA15_PLL_EXEC_FRAME_HOLD/2','autorouting','on');
        connectReplacingInput(meas,'AA15_B1_HOLD_REQ/1','AA15_PLL_EXEC_FRAME_HOLD/3','autorouting','on');
        connectReplacingInput(meas,'AA15_MASTER_F_IN/1','AA15_PLL_EXEC_FRAME_HOLD/4','autorouting','on');
        connectReplacingInput(meas,'AA15_PLL_EXEC_FRAME_HOLD/1','Goto1/1','autorouting','on');
        connectReplacingInput(meas,'AA15_PLL_EXEC_FRAME_HOLD/2','Goto2/1','autorouting','on');

        % 根Fref由SM在岛态送Fout；同一份Fout进入FrameHold。
        connectReplacingInput(ctrl,'Fref/1','Measurements/6','autorouting','on');

        % Final GFL manager: 10 inputs / 22 outputs.
        addFinalGFLManager([ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'],posMgr, ...
            ROLES(i),DEF_ISUP(i),DEF_TS, ...
            DEF_VFF_FC,DEF_KSLOW,DEF_KFAST,DEF_KGAIN_SLEW, ...
            DEF_KMAG,DEF_VSUP_FC,DEF_VSUP_DB,DEF_VSUP_SLEW, ...
            DEF_FRAME_HOLD,DEF_FRAME_RELEASE,DEF_UV_START,DEF_UV_FULL,DEF_IMAX,DEF_VNOM);

        % inputs:
        connectReplacingInput(ctrl,'From26/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/1','autorouting','on');
        connectReplacingInput(ctrl,'Power Control Loop/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/2','autorouting','on');
        connectReplacingInput(ctrl,'From21/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/3','autorouting','on');
        connectReplacingInput(ctrl,'From51/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/4','autorouting','on');
        connectReplacingInput(ctrl,'Pref/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/5','autorouting','on');
        connectReplacingInput(ctrl,'Qref/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/6','autorouting','on');
        connectReplacingInput(ctrl,'From28/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/7','autorouting','on');
        connectReplacingInput(ctrl,'Droop_On/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/8','autorouting','on');
        connectReplacingInput(ctrl,'Fref/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/9','autorouting','on');
        connectReplacingInput(ctrl,'Vref/1','AA15_ISLAND_GFL_SUPPORT_MANAGER/10','autorouting','on');

        % functional outputs:
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/1','Current Regulator/1','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/2','Goto18/1','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/3','Power Control Loop/3','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/4','Power Control Loop/6','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/16','Measurements/5','autorouting','on');

        % diag41: 33 Mux inputs -> 41 scalar rows.
        add_block('built-in/Mux',[ctrl '/AA15_ENG_DIAG_MUX'], ...
            'Inputs','33','Position',posDiag);

        % 01-02 raw Ipq[2]
        connectReplacingInput(ctrl,'Power Control Loop/1','AA15_ENG_DIAG_MUX/1','autorouting','on');
        % 03-04 final Iref[2]
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/2','AA15_ENG_DIAG_MUX/2','autorouting','on');
        % 05-06 measured IdIq[2]
        connectReplacingInput(ctrl,'From28/1','AA15_ENG_DIAG_MUX/3','autorouting','on');
        % 07-08 raw Vdq[2]
        connectReplacingInput(ctrl,'From26/1','AA15_ENG_DIAG_MUX/4','autorouting','on');
        % 09-10 final VFF[2]
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/1','AA15_ENG_DIAG_MUX/5','autorouting','on');
        % 11-12 current PI[2]
        connectReplacingInput(ctrl,'Current Regulator/2','AA15_ENG_DIAG_MUX/6','autorouting','on');
        % 13-14 Vconv[2]
        connectReplacingInput(ctrl,'Current Regulator/1','AA15_ENG_DIAG_MUX/7','autorouting','on');
        % 15 ModIndex
        connectReplacingInput(ctrl,'From/1','AA15_ENG_DIAG_MUX/8','autorouting','on');
        % 16 Pmeas
        connectReplacingInput(ctrl,'From21/1','AA15_ENG_DIAG_MUX/9','autorouting','on');
        % 17 Qmeas
        connectReplacingInput(ctrl,'From51/1','AA15_ENG_DIAG_MUX/10','autorouting','on');
        % 18 exec frequency
        connectReplacingInput(ctrl,'Switch7/1','AA15_ENG_DIAG_MUX/11','autorouting','on');
        % 19 native PLL frequency
        connectReplacingInput(ctrl,'Measurements/10','AA15_ENG_DIAG_MUX/12','autorouting','on');
        % 20 StageEcho
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/17','AA15_ENG_DIAG_MUX/13','autorouting','on');
        % 21 Vpu
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/5','AA15_ENG_DIAG_MUX/14','autorouting','on');
        % 22 VsupportRef
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/6','AA15_ENG_DIAG_MUX/15','autorouting','on');
        % 23 Pbase
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/7','AA15_ENG_DIAG_MUX/16','autorouting','on');
        % 24 Pref command from SM
        connectReplacingInput(ctrl,'Pref/1','AA15_ENG_DIAG_MUX/17','autorouting','on');
        % 25 Pref after local undervoltage relief
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/8','AA15_ENG_DIAG_MUX/18','autorouting','on');
        % 26 PrefEff to Power Control
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/3','AA15_ENG_DIAG_MUX/19','autorouting','on');
        % 27 Qref command
        connectReplacingInput(ctrl,'Qref/1','AA15_ENG_DIAG_MUX/20','autorouting','on');
        % 28 QrefEff
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/4','AA15_ENG_DIAG_MUX/21','autorouting','on');
        % 29-30 actual support IdIq[2]
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/10','AA15_ENG_DIAG_MUX/22','autorouting','on');
        % 31 Kslow
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/11','AA15_ENG_DIAG_MUX/23','autorouting','on');
        % 32 Kfast
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/12','AA15_ENG_DIAG_MUX/24','autorouting','on');
        % 33 gP
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/13','AA15_ENG_DIAG_MUX/25','autorouting','on');
        % 34 gQ
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/14','AA15_ENG_DIAG_MUX/26','autorouting','on');
        % 35 current limit active
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/15','AA15_ENG_DIAG_MUX/27','autorouting','on');
        % 36 FrameHold request
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/16','AA15_ENG_DIAG_MUX/28','autorouting','on');
        % 37 MasterF
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/18','AA15_ENG_DIAG_MUX/29','autorouting','on');
        % 38 Vref command from SM
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/19','AA15_ENG_DIAG_MUX/30','autorouting','on');
        % 39 Imax
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/20','AA15_ENG_DIAG_MUX/31','autorouting','on');
        % 40 Role
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/21','AA15_ENG_DIAG_MUX/32','autorouting','on');
        % 41 IsupMax
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/22','AA15_ENG_DIAG_MUX/33','autorouting','on');

        connectReplacingInput(ctrl,'AA15_ENG_DIAG_MUX/1','AA15_ENG_DIAG_OUT41/1','autorouting','on');

        logf(fid,'[GFL REBUILD PASS] %s',dev);
    end

    % =====================================================================
    % 7. REBUILD G29 AS FINAL CENTRAL/SYSTEM DIAGNOSTIC, WIDTH STILL 38
    % =====================================================================
    logf(fid,'\n--- 7. REBUILD G29 MAP ---');

    G29MUX=[SM '/AA15_FINAL_G29_MUX38'];
    add_block('built-in/Mux',G29MUX,'Inputs','38','Position',[5800 1120 5960 1820]);

    % rows 1-16: coordinator outputs 16..31
    for k=1:16
        connectAbsToInput(COORD,15+k,G29MUX,k);
    end
    % rows17-21: final Pref five devices
    for k=1:5
        connectAbsToInput(COORD,k,G29MUX,16+k);
    end
    % rows22-26: five actual Pmeas
    for k=1:5
        connectAbsToInput(pmeasEP{k}.Block,pmeasEP{k}.Port,G29MUX,21+k);
    end
    % row27 J1 applied close
    connectAbsToInput([SM '/AA15_GATEA_J1_FORCE_OPEN_SWITCH'],1,G29MUX,27);
    % row28 PCC P
    connectAbsToInput(J2,2,G29MUX,28);  % Ppcc kW
    % row29 PCC Q
    connectAbsToInput(J2,3,G29MUX,29);  % Qpcc kvar
    % row30 PCC online frequency (may saturate; use only while voltage valid)
    connectAbsToInput(J2,1,G29MUX,30);  % PCC online frequency
    % row31 PCC Vab RMS
    connectAbsToInput(J2,4,G29MUX,31);  % PCC Vab RMS
    % row32 ESS1 Fout
    connectAbsToInput(MASTER_DEMUX,17,G29MUX,32);
    % row33 ESS1 Vout
    connectAbsToInput(MASTER_DEMUX,18,G29MUX,33);
    % rows34-35 Ppvmax1/2 source values
    connectAbsToInput(tapPpv1.Block,tapPpv1.Port,G29MUX,34);
    connectAbsToInput(tapPpv2.Block,tapPpv2.Port,G29MUX,35);
    % rows36-37 SOC1/SOC2
    connectAbsToInput(tapSOC1.Block,tapSOC1.Port,G29MUX,36);
    connectAbsToInput(tapSOC2.Block,tapSOC2.Port,G29MUX,37);
    % row38 Punit
    connectAbsToInput(tapPunit.Block,tapPunit.Port,G29MUX,38);

    connectAbsToInput(G29MUX,1,OPPATHS{4},1);
    logf(fid,'[G29 MAP PASS] central coordinator/system evidence -> 38 scalars.');

    % =====================================================================
    % 8. IMMEDIATE STRUCTURAL ASSERTS
    % =====================================================================
    logf(fid,'\n--- 8. IMMEDIATE STRUCTURAL ASSERTS ---');

    for i=1:5
        dev=NAMES{i};
        ctrl=CTRLS{i};
        mgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
        meas=[ctrl '/Measurements'];
        frame=[meas '/AA15_PLL_EXEC_FRAME_HOLD'];

        assertSource(mgr,8,[ctrl '/Droop_On'],1,[dev ' unified stage']);
        assertSource(mgr,9,[ctrl '/Fref'],1,[dev ' MasterF']);
        assertSource(mgr,10,[ctrl '/Vref'],1,[dev ' Vref']);
        assertSource([ctrl '/Droop Control'],5,[ctrl '/AA15_FINAL_GFL_DROOP_DISABLED'],1,[dev ' old droop disabled']);
        assertSource(meas,6,[ctrl '/Fref'],1,[dev ' Measurements MasterF']);
        assertSource(frame,4,[meas '/AA15_MASTER_F_IN'],1,[dev ' FrameHold MasterF']);

        % Hard causality assertion: manager FrameHoldReq outport input must
        % come from AA15_STATE_FRAME/1 (UnitDelay), not the MATLAB Function core.
        assertSource([mgr '/FrameHoldReq'],1,[mgr '/AA15_STATE_FRAME'],1,[dev ' delayed FrameHoldReq']);

        assertSource([ctrl '/Current Regulator'],1,mgr,1,[dev ' final VFF']);
        assertSource([ctrl '/Goto18'],1,mgr,2,[dev ' final Iref']);
        assertSource([ctrl '/Power Control Loop'],3,mgr,3,[dev ' PrefEff']);
        assertSource([ctrl '/Power Control Loop'],6,mgr,4,[dev ' QrefEff']);
        assertSource(meas,5,mgr,16,[dev ' frame req']);
    end

    % Master-frequency transport is explicitly causal and shared by all five GFLs.
    assertSource(MASTER_F_Z1,1,MASTER_DEMUX,17,'master Fout delay input');
    assertSource(COORD,2,MASTER_F_Z1,1,'coordinator delayed MasterF');

    % ESS1 frozen blocks still exist.
    for k=1:numel(ESS_KEEP),requireBlock(ESS_KEEP{k});end

    % Group mux interfaces were not structurally widened.
    if str2double(safeParam([SM '/PV_Group_Mux24'],'Inputs'))~=2
        error('PV_Group_Mux24 input-port count changed.');
    end
    if str2double(safeParam([SM '/ESS_Group_Mux24'],'Inputs'))~=2
        error('ESS_Group_Mux24 input-port count changed.');
    end
    if str2double(safeParam([SM '/EV_Group_Mux24'],'Inputs'))~=2
        error('EV_Group_Mux24 input-port count changed.');
    end

    % =====================================================================
    % 9. FULL MODEL COMPILE + WIDTH CONTRACT
    % =====================================================================
    logf(fid,'\n--- 9. FULL MODEL COMPILE + WIDTH CONTRACT ---');

    oldAlgFormal=safeParam(MODEL,'AlgebraicLoopMsg');
    set_param(MODEL,'AlgebraicLoopMsg','error');
    feval(MODEL,[],[],[],'compile');
    compiled=true;

    wj2=compiledWidths(J2);
    requireWidthVec(wj2.Outport,[1 1 1 1],'J2 PCC measurement outputs');
    wc=compiledWidths(COORD);
    requireWidthVec(wc.Inport,ones(1,30),'central coordinator inputs');
    requireWidthVec(wc.Outport,ones(1,31),'central coordinator outputs');

    wstage=compiledWidths(STAGE);
    requireWidthAt(wstage.Outport,1,1,'system stage');

    wmfz=compiledWidths(MASTER_F_Z1);
    requireWidthVec(wmfz.Inport,[1],'master Fout delay input');
    requireWidthVec(wmfz.Outport,[1],'master Fout delay output');

    for i=1:5
        dev=NAMES{i};
        ctrl=CTRLS{i};
        wm=compiledWidths([ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER']);
        wf=compiledWidths([ctrl '/Measurements/AA15_PLL_EXEC_FRAME_HOLD']);
        wmeas=compiledWidths([ctrl '/Measurements']);
        wd=compiledWidths([ctrl '/AA15_ENG_DIAG_MUX']);

        requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],[dev ' manager inputs']);
        requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],[dev ' manager outputs']);
        requireWidthVec(wf.Inport,[1 1 1 1],[dev ' frame inputs']);
        requireWidthVec(wf.Outport,[1 1],[dev ' frame outputs']);
        requireWidthAt(wmeas.Inport,6,1,[dev ' Measurements MasterF']);
        requireWidthAt(wd.Outport,1,41,[dev ' diag41']);
    end

    % 三组仍为24宽。
    wpvg=compiledWidths([SM '/PV_Group_Mux24']);
    wessg=compiledWidths([SM '/ESS_Group_Mux24']);
    wevg=compiledWidths([SM '/EV_Group_Mux24']);
    requireWidthAt(wpvg.Outport,1,24,'PV group width');
    requireWidthAt(wessg.Outport,1,24,'ESS group width');
    requireWidthAt(wevg.Outport,1,24,'EV group width');

    for i=1:5
        w=compiledWidths(OPPATHS{i});
        requireWidthAt(w.Inport,1,EXPECTED_OPWIDTHS(i),[OPNAMES{i} ' width']);
        logf(fid,'[%s] width=%d',OPNAMES{i},w.Inport(1));
    end

    feval(MODEL,[],[],[],'term');
    compiled=false;
    set_param(MODEL,'AlgebraicLoopMsg',oldAlgFormal);
    logf(fid,'[COMPILE PASS] final planned-island structure; AlgebraicLoopMsg=error produced no loop error.');

    % =====================================================================
    % 10. UNCONNECTED + ALGEBRAIC LOOP HEALTH
    % =====================================================================
    logf(fid,'\n--- 10. HEALTH AUDIT BEFORE SAVE ---');

    rootsToAudit={COORD};
    for i=1:5
        rootsToAudit{end+1}=[CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER']; %#ok<AGROW>
        rootsToAudit{end+1}=[CTRLS{i} '/Measurements/AA15_PLL_EXEC_FRAME_HOLD']; %#ok<AGROW>
    end

    for r=1:numel(rootsToAudit)
        [unIn,unOut]=findUnconnectedOrdinaryPorts(rootsToAudit{r});
        if height(unIn)>0
            dumpUnconnected(fid,unIn,'INPUT');
            error('Unconnected input(s) inside %s',rootsToAudit{r});
        end
        if height(unOut)>0
            dumpUnconnected(fid,unOut,'OUTPUT');
            error('Unconnected output(s) inside %s',rootsToAudit{r});
        end
    end

    strictCompileWithLoopError(MODEL,fid,'PRE-SAVE');
    logf(fid,'[HEALTH PASS] PRE-SAVE strict loop diagnostic passed.');

    % =====================================================================
    % 11. SAVE EXACTLY ONCE
    % =====================================================================
    logf(fid,'\n--- 11. SAVE EXACTLY ONCE ---');

    set_param(STAGE,'Value','0');
    save_system(MODEL);
    savedToDisk=true;
    shaSaved=fileSha256(modelFile);
    logf(fid,'[SAVE PASS] SHA=%s',shaSaved);

    % =====================================================================
    % 12. CLOSE / RELOAD / PERSISTENCE COMPILE
    % =====================================================================
    logf(fid,'\n--- 12. CLOSE / RELOAD / PERSISTENCE AUDIT ---');

    close_system(MODEL,0);
    load_system(modelFile);

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Reloaded final model Dirty is not off.');
    end

    requireBlock(STAGE);
    requireBlock(MASTER_F_Z1);
    requireBlock(COORD);
    requireBlock(G29MUX);

    if abs(str2double(safeParam(STAGE,'Value')))>1e-12
        error('Persisted AA15_FINAL_SYSTEM_STAGE must be 0.');
    end

    oldAlgPersist=safeParam(MODEL,'AlgebraicLoopMsg');
    set_param(MODEL,'AlgebraicLoopMsg','error');
    feval(MODEL,[],[],[],'compile');
    compiled=true;

    wj2=compiledWidths(J2);
    requireWidthVec(wj2.Outport,[1 1 1 1],'persisted J2 PCC measurement outputs');
    wc=compiledWidths(COORD);
    requireWidthVec(wc.Inport,ones(1,30),'persisted coordinator inputs');
    requireWidthVec(wc.Outport,ones(1,31),'persisted coordinator outputs');

    wmfz=compiledWidths(MASTER_F_Z1);
    requireWidthVec(wmfz.Inport,[1],'persisted master Fout delay input');
    requireWidthVec(wmfz.Outport,[1],'persisted master Fout delay output');

    for i=1:5
        wm=compiledWidths([CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER']);
        wf=compiledWidths([CTRLS{i} '/Measurements/AA15_PLL_EXEC_FRAME_HOLD']);
        wd=compiledWidths([CTRLS{i} '/AA15_ENG_DIAG_MUX']);
        requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],[NAMES{i} ' persisted manager inputs']);
        requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],[NAMES{i} ' persisted manager outputs']);
        requireWidthVec(wf.Inport,[1 1 1 1],[NAMES{i} ' persisted frame inputs']);
        requireWidthAt(wd.Outport,1,41,[NAMES{i} ' persisted diag']);
    end
    for i=1:5
        w=compiledWidths(OPPATHS{i});
        requireWidthAt(w.Inport,1,EXPECTED_OPWIDTHS(i),[OPNAMES{i} ' persisted width']);
    end

    feval(MODEL,[],[],[],'term');
    compiled=false;
    set_param(MODEL,'AlgebraicLoopMsg',oldAlgPersist);

    for r=1:numel(rootsToAudit)
        [unIn,unOut]=findUnconnectedOrdinaryPorts(rootsToAudit{r});
        if height(unIn)>0||height(unOut)>0
            error('Persisted new subsystem has unconnected ordinary port: %s',rootsToAudit{r});
        end
    end

    for i=1:5
        mgr=[CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
        assertSource([mgr '/FrameHoldReq'],1,[mgr '/AA15_STATE_FRAME'],1,[NAMES{i} ' persisted delayed FrameHoldReq']);
    end
    assertSource(MASTER_F_Z1,1,MASTER_DEMUX,17,'persisted master Fout delay input');
    assertSource(COORD,2,MASTER_F_Z1,1,'persisted coordinator delayed MasterF');

    % The temporary diagnostic change may mark the diagram Dirty.
    % Discard only that diagnostic change and reload the already-saved SLX.
    close_system(MODEL,0);
    load_system(modelFile);
    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Post-persistence strict diagnostic reload did not return Dirty=off.');
    end

    shaFinal=fileSha256(modelFile);

    logf(fid,'\n%s',repmat('=',1,190));
    logf(fid,'PATCH PASS — K26_V5 FINAL PLANNED ISLAND V3.4');
    logf(fid,'[SYSTEM STAGE] one SM_Master runtime value; five local stage constants retired.');
    logf(fid,'[COMM] PV/ESS/EV group vectors remain 24/24/24.');
    logf(fid,'[P-F] centralized Fout-based primary + one slow frequency-restoration state.');
    logf(fid,'[PVmax/SOC] original capability signals reused; original PCC objective not reused in island.');
    logf(fid,'[VFF] Kfast=0; Kslow=.5; fc=1Hz first-Build baseline.');
    logf(fid,'[V SUPPORT] local captured voltage target + shared slow voltage restoration.');
    logf(fid,'[FRAME] local PLL healthy; low-voltage FrameHold request is UnitDelay-state causal and uses delayed ESS1 Fout-assisted phase advance.');
    logf(fid,'[MASTER F] ESS1 Fout is centrally delayed exactly one 100us sample before P-f/FrameHold broadcast.');
    logf(fid,'[LIMIT] vector Imax=1.2 + one-step gP/gQ execution feedback.');
    logf(fid,'[G29] remapped to final central/system evidence; width38.');
    logf(fid,'[OPWRITE] widths 82/41/82/38/128 preserved.');
    logf(fid,'[ESS1] F21/F24/F25 and GFM inner loops untouched.');
    logf(fid,'[FINAL SHA] %s',shaFinal);
    logf(fid,'[BACKUP] %s',backupFile);
    logf(fid,'[NEXT] Rebuild All, then use FINAL V3.3 planned-island supervisor. Do not use V2 five-stage supervisor.');
    logf(fid,'%s',repmat('=',1,190));

catch ME
    if compiled
        try,feval(MODEL,[],[],[],'term');catch,end
    end
    try
        if bdIsLoaded(MODEL)
            if exist('oldAlgPersist','var')
                set_param(MODEL,'AlgebraicLoopMsg',oldAlgPersist);
            elseif exist('oldAlgFormal','var')
                set_param(MODEL,'AlgebraicLoopMsg',oldAlgFormal);
            end
        end
    catch
    end

    logf(fid,'\n%s',repmat('!',1,190));
    logf(fid,'PATCH FAILURE');
    logf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));

    try
        if bdIsLoaded(MODEL),close_system(MODEL,0);end
    catch
    end

    if savedToDisk
        try
            [okr,msgr]=copyfile(backupFile,modelFile,'f');
            if okr
                logf(fid,'[FULL ROLLBACK PASS] pre-final V2 SLX restored.');
            else
                logf(fid,'[FULL ROLLBACK FAIL] %s',msgr);
            end
        catch MEr
            logf(fid,'[ROLLBACK EXCEPTION] %s',MEr.message);
        end
    else
        logf(fid,'[ROLLBACK] save_system never occurred; disk SLX remains current V2.');
    end

    try
        load_system(modelFile);
        logf(fid,'[ROLLBACK RELOAD] disk model reloaded.');
    catch MEr
        logf(fid,'[ROLLBACK RELOAD WARN] %s',MEr.message);
    end

    logf(fid,'%s',repmat('!',1,190));
    rethrow(ME);
end

fprintf('\nFinal planned-island patch V3.4 finished. Log: %s\n',LOG_FILE);

%% =========================================================================
%% Scratch preflight
%% =========================================================================
function scratchPreflightFinal(Ts,kfast,kslow,vffFc,kSlew,kMag,vsFc,vsDb,vsSlew, ...
    isupMax,iMax,frameHold,frameRelease,uvStart,uvFull, ...
    kpf,pfFc,pfDb,kiSec,secEntry,secSlew,kiV,vDelay,vLim,vSlew,vNom)

tmp=matlab.lang.makeValidName(['AA15_FINAL_PREFLIGHT_' datestr(now,'HHMMSSFFF')]);
new_system(tmp);
cleaner=onCleanup(@()closeScratch(tmp));
load_system(tmp);

% manager vectors
for k=1:6
    add_block('built-in/Constant',[tmp sprintf('/C%d',k)],'Value','0');
end
add_block('built-in/Constant',[tmp '/VD'],'Value','1');
add_block('built-in/Constant',[tmp '/VQ'],'Value','0');
add_block('built-in/Mux',[tmp '/VMUX'],'Inputs','2');
connectReplacingInput(tmp,'VD/1','VMUX/1');
connectReplacingInput(tmp,'VQ/1','VMUX/2');

add_block('built-in/Constant',[tmp '/ID'],'Value','0.5');
add_block('built-in/Constant',[tmp '/IQ'],'Value','0');
add_block('built-in/Mux',[tmp '/IMUX'],'Inputs','2');
connectReplacingInput(tmp,'ID/1','IMUX/1');
connectReplacingInput(tmp,'IQ/1','IMUX/2');

mgr=[tmp '/MGR'];
addFinalGFLManager(mgr,[300 100 850 700],1,isupMax,Ts,vffFc,kslow,kfast,kSlew, ...
    kMag,vsFc,vsDb,vsSlew,frameHold,frameRelease,uvStart,uvFull,iMax,vNom);

mSrc={'VMUX/1','IMUX/1','C1/1','C2/1','C3/1','C4/1','IMUX/1','C5/1','C6/1','C6/1'};
for k=1:10,connectReplacingInput(tmp,mSrc{k},sprintf('MGR/%d',k));end
for k=1:22
    add_block('built-in/Terminator',[tmp sprintf('/TM%02d',k)]);
    connectReplacingInput(tmp,sprintf('MGR/%d',k),sprintf('TM%02d/1',k));
end

% frame
frame=[tmp '/FRAME'];
addMasterFrequencyFrameHold(frame,[900 100 1250 420],Ts);
frameSrc={'C1/1','C2/1','C3/1','C4/1'};
for k=1:4,connectReplacingInput(tmp,frameSrc{k},sprintf('FRAME/%d',k));end
for k=1:2
    add_block('built-in/Terminator',[tmp sprintf('/TF%d',k)]);
    connectReplacingInput(tmp,sprintf('FRAME/%d',k),sprintf('TF%d/1',k));
end

% coordinator
coord=[tmp '/COORD'];
addFinalCoordinator(coord,[300 760 1200 1500],Ts,kpf,pfFc,pfDb,kiSec,secEntry,secSlew, ...
    kiV,vDelay,vLim,vSlew,vNom);

for k=1:30
    add_block('built-in/Constant',[tmp sprintf('/CI%02d',k)],'Value','0');
    if k==2,set_param([tmp sprintf('/CI%02d',k)],'Value','50');end
    if k==19,set_param([tmp sprintf('/CI%02d',k)],'Value','100');end
    if k==20,set_param([tmp sprintf('/CI%02d',k)],'Value','10000');end
    if k>=21&&k<=25,set_param([tmp sprintf('/CI%02d',k)],'Value','10000');end
    if k>=26&&k<=30,set_param([tmp sprintf('/CI%02d',k)],'Value','50');end
    connectReplacingInput(tmp,sprintf('CI%02d/1',k),sprintf('COORD/%d',k));
end
for k=1:31
    add_block('built-in/Terminator',[tmp sprintf('/TC%02d',k)]);
    connectReplacingInput(tmp,sprintf('COORD/%d',k),sprintf('TC%02d/1',k));
end

oldAlgScratch=safeParam(tmp,'AlgebraicLoopMsg');
scratchCompiled=false;
try
    set_param(tmp,'AlgebraicLoopMsg','error');
    feval(tmp,[],[],[],'compile');
    scratchCompiled=true;

    wm=compiledWidths(mgr);
    requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],'scratch manager in');
    requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],'scratch manager out');

    wf=compiledWidths(frame);
    requireWidthVec(wf.Inport,[1 1 1 1],'scratch frame in');
    requireWidthVec(wf.Outport,[1 1],'scratch frame out');

    wc=compiledWidths(coord);
    requireWidthVec(wc.Inport,ones(1,30),'scratch coordinator in');
    requireWidthVec(wc.Outport,ones(1,31),'scratch coordinator out');

    % Catch dangling internal ports before the formal K26_V5 model is edited.
    scratchRoots={mgr,frame,coord};
    for rr=1:numel(scratchRoots)
        [uIn,uOut]=findUnconnectedOrdinaryPorts(scratchRoots{rr});
        if height(uIn)>0 || height(uOut)>0
            error('SCRATCH PREFLIGHT: unconnected ordinary port inside %s',scratchRoots{rr});
        end
    end

    feval(tmp,[],[],[],'term');
    scratchCompiled=false;
    set_param(tmp,'AlgebraicLoopMsg',oldAlgScratch);
catch ME
    if scratchCompiled
        try,feval(tmp,[],[],[],'term');catch,end
    end
    try,set_param(tmp,'AlgebraicLoopMsg',oldAlgScratch);catch,end
    rethrow(ME);
end
end

function closeScratch(tmp)
try
    if bdIsLoaded(tmp),close_system(tmp,0);end
catch
end
end

%% =========================================================================
%% Central coordinator builder
%% =========================================================================
function addFinalCoordinator(sub,pos,Ts,kpf,pfFc,pfDb,kiSec,secEntry,secSlew, ...
    kiV,vDelay,vLim,vSlew,vNom)

add_block('built-in/SubSystem',sub,'Position',pos);

ins={ ...
    'Stage','MasterF', ...
    'PrefLegacyPV1','PrefLegacyPV2','PrefLegacyESS2','PrefLegacyEV1','PrefLegacyEV2', ...
    'PmeasPV1','PmeasPV2','PmeasESS2','PmeasEV1','PmeasEV2', ...
    'Ppvmax1_kW','Ppvmax2_kW','SOC1','SOC2','SOCmin','SOCmax','Punit_kW','PCC_Vab_RMS', ...
    'VrefLegacyPV1','VrefLegacyPV2','VrefLegacyESS2','VrefLegacyEV1','VrefLegacyEV2', ...
    'FrefLegacyPV1','FrefLegacyPV2','FrefLegacyESS2','FrefLegacyEV1','FrefLegacyEV2' ...
};
for k=1:numel(ins)
    add_block('built-in/Inport',[sub '/' ins{k}],'Port',num2str(k));
end

% Explicit state
stateNames={ ...
    'PBASE1','PBASE2','PBASE3','PBASE4','PBASE5', ...
    'VBASE1','VBASE2','VBASE3','VBASE4','VBASE5', ...
    'EFILT','PSEC','VPCC_BASE','VSEC','PREV_STAGE','STAGE_TIMER','REC_BLEND' ...
};
stateInit={ ...
    '0','0','0','0','0', ...
    '10000','10000','10000','10000','10000', ...
    '0','0','10000','0','0','0','0' ...
};
for k=1:numel(stateNames)
    add_block('built-in/UnitDelay',[sub '/AA15_STATE_' stateNames{k}], ...
        'InitialCondition',stateInit{k},'SampleTime',num2str(Ts,17));
end

addParam(sub,'AA15_P_TS',Ts);
addParam(sub,'AA15_P_KPF_SUM',kpf);
addParam(sub,'AA15_P_PF_FC_HZ',pfFc);
addParam(sub,'AA15_P_PF_DB_HZ',pfDb);
addParam(sub,'AA15_P_KI_F_SECONDARY',kiSec);
addParam(sub,'AA15_P_SECONDARY_ENTRY_S',secEntry);
addParam(sub,'AA15_P_SECONDARY_SLEW_PU_S',secSlew);
addParam(sub,'AA15_P_KI_V_SECONDARY',kiV);
addParam(sub,'AA15_P_VSEC_DELAY_STAGE3_S',vDelay);
addParam(sub,'AA15_P_VSEC_LIMIT_PU',vLim);
addParam(sub,'AA15_P_VSEC_SLEW_PU_S',vSlew);
addParam(sub,'AA15_P_VNOM',vNom);

fn=[sub '/AA15_FINAL_COORD_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',fn);
setMatlabFunctionScript(fn,coordinatorCoreScript());

src={ ...
    'Stage/1','MasterF/1', ...
    'PrefLegacyPV1/1','PrefLegacyPV2/1','PrefLegacyESS2/1','PrefLegacyEV1/1','PrefLegacyEV2/1', ...
    'PmeasPV1/1','PmeasPV2/1','PmeasESS2/1','PmeasEV1/1','PmeasEV2/1', ...
    'Ppvmax1_kW/1','Ppvmax2_kW/1','SOC1/1','SOC2/1','SOCmin/1','SOCmax/1','Punit_kW/1','PCC_Vab_RMS/1', ...
    'VrefLegacyPV1/1','VrefLegacyPV2/1','VrefLegacyESS2/1','VrefLegacyEV1/1','VrefLegacyEV2/1', ...
    'FrefLegacyPV1/1','FrefLegacyPV2/1','FrefLegacyESS2/1','FrefLegacyEV1/1','FrefLegacyEV2/1', ...
    'AA15_STATE_PBASE1/1','AA15_STATE_PBASE2/1','AA15_STATE_PBASE3/1','AA15_STATE_PBASE4/1','AA15_STATE_PBASE5/1', ...
    'AA15_STATE_VBASE1/1','AA15_STATE_VBASE2/1','AA15_STATE_VBASE3/1','AA15_STATE_VBASE4/1','AA15_STATE_VBASE5/1', ...
    'AA15_STATE_EFILT/1','AA15_STATE_PSEC/1','AA15_STATE_VPCC_BASE/1','AA15_STATE_VSEC/1', ...
    'AA15_STATE_PREV_STAGE/1','AA15_STATE_STAGE_TIMER/1','AA15_STATE_REC_BLEND/1', ...
    'AA15_P_TS/1','AA15_P_KPF_SUM/1','AA15_P_PF_FC_HZ/1','AA15_P_PF_DB_HZ/1', ...
    'AA15_P_KI_F_SECONDARY/1','AA15_P_SECONDARY_ENTRY_S/1','AA15_P_SECONDARY_SLEW_PU_S/1', ...
    'AA15_P_KI_V_SECONDARY/1','AA15_P_VSEC_DELAY_STAGE3_S/1','AA15_P_VSEC_LIMIT_PU/1', ...
    'AA15_P_VSEC_SLEW_PU_S/1','AA15_P_VNOM/1' ...
};
for k=1:numel(src)
    connectReplacingInput(sub,src{k},sprintf('AA15_FINAL_COORD_CORE/%d',k),'autorouting','on');
end

% Function outputs:
% 1-31 external signals
% 32-48 next state values in same order as stateNames
for k=1:numel(stateNames)
    connectReplacingInput(sub,sprintf('AA15_FINAL_COORD_CORE/%d',31+k), ...
        ['AA15_STATE_' stateNames{k} '/1'],'autorouting','on');
end

outNames={ ...
    'PrefPV1','PrefPV2','PrefESS2','PrefEV1','PrefEV2', ...
    'VrefPV1','VrefPV2','VrefESS2','VrefEV1','VrefEV2', ...
    'FrefPV1','FrefPV2','FrefESS2','FrefEV1','FrefEV2', ...
    'MasterValid','dPPrimaryTotal','dPSecondaryTotal','dVSecondary', ...
    'UpPV1','UpPV2','UpESS2','UpEV1','UpEV2', ...
    'DownPV1','DownPV2','DownESS2','DownEV1','DownEV2', ...
    'StageEcho','FailCode' ...
};
for k=1:numel(outNames)
    add_block('built-in/Outport',[sub '/' outNames{k}],'Port',num2str(k));
    connectReplacingInput(sub,sprintf('AA15_FINAL_COORD_CORE/%d',k), ...
        [outNames{k} '/1'],'autorouting','on');
end
end

function s=coordinatorCoreScript()
L={ ...
'function [po1,po2,po3,po4,po5,vo1,vo2,vo3,vo4,vo5,fo1,fo2,fo3,fo4,fo5,master_valid,dp_primary,dp_secondary,dv_secondary,up1,up2,up3,up4,up5,dn1,dn2,dn3,dn4,dn5,stage_echo,fail_code,pb1n,pb2n,pb3n,pb4n,pb5n,vb1n,vb2n,vb3n,vb4n,vb5n,efn,psecn,vpccn,vsecn,prevn,timern,recn] = fcn(stage,master_f,lp1,lp2,lp3,lp4,lp5,pm1,pm2,pm3,pm4,pm5,pvmax1_kw,pvmax2_kw,soc1,soc2,socmin,socmax,punit_kw,pcc_v,lv1,lv2,lv3,lv4,lv5,lf1,lf2,lf3,lf4,lf5,pb1,pb2,pb3,pb4,pb5,vb1,vb2,vb3,vb4,vb5,efz,psecz,vpccz,vsecz,prev_stage,stage_timer,rec_blend,Ts,kpf,pf_fc,pf_db,ki_sec,sec_entry,sec_slew,ki_v,vsec_delay,vsec_lim,vsec_slew,vnom)'; ...
'%#codegen'; ...
'piC=4.0*atan(1.0);'; ...
's=min(max(round(stage),0.0),5.0);'; ...
'stage_echo=s;'; ...
'TsS=max(Ts,1e-9);'; ...
'master_valid=double(finite1(master_f) && master_f>45.0 && master_f<55.0);'; ...
'fail_code=0.0;'; ...
'if s>=2.0 && s<=4.0 && master_valid<0.5'; ...
'    fail_code=1.0;'; ...
'end'; ...
''; ...
'% stage timer'; ...
'if abs(s-prev_stage)>0.5'; ...
'    stage_timer_n=0.0;'; ...
'else'; ...
'    stage_timer_n=stage_timer+TsS;'; ...
'end'; ...
'timern=stage_timer_n;'; ...
'prevn=s;'; ...
''; ...
'% capture final strong-grid operating point continuously in PREPARE'; ...
'pb1n=pb1;pb2n=pb2;pb3n=pb3;pb4n=pb4;pb5n=pb5;'; ...
'vb1n=vb1;vb2n=vb2;vb3n=vb3;vb4n=vb4;vb5n=vb5;'; ...
'vpccn=vpccz;'; ...
'if s==0.0'; ...
'    pb1n=pm1;pb2n=pm2;pb3n=pm3;pb4n=pm4;pb5n=pm5;'; ...
'    vb1n=lv1;vb2n=lv2;vb3n=lv3;vb4n=lv4;vb5n=lv5;'; ...
'    vpccn=pcc_v;'; ...
'elseif s==1.0'; ...
'    pb1n=pm1;pb2n=pm2;pb3n=pm3;pb4n=pm4;pb5n=pm5;'; ...
'    vb1n=lv1;vb2n=lv2;vb3n=lv3;vb4n=lv4;vb5n=lv5;'; ...
'    vpccn=pcc_v;'; ...
'end'; ...
''; ...
'% capability contract'; ...
'punit=abs(punit_kw);'; ...
'if ~finite1(punit) || punit<1e-6'; ...
'    punit=100.0;'; ...
'    fail_code=max(fail_code,2.0);'; ...
'end'; ...
'pvmax1=pb1;pvmax2=pb2;'; ...
'if finite1(pvmax1_kw)'; ...
'    pvmax1=max(pb1,max(pvmax1_kw,0.0)/punit);'; ...
'end'; ...
'if finite1(pvmax2_kw)'; ...
'    pvmax2=max(pb2,max(pvmax2_kw,0.0)/punit);'; ...
'end'; ...
'pmin1=0.0;pmax1=max(pvmax1,0.0);'; ...
'pmin2=0.0;pmax2=max(pvmax2,0.0);'; ...
'pmin3=-1.0;pmax3=1.0;'; ...
'if finite1(soc2) && finite1(socmin) && finite1(socmax)'; ...
'    slo=min(socmin,socmax);shi=max(socmin,socmax);'; ...
'    if soc2<=slo'; ...
'        pmax3=max(pb3,0.0);'; ...
'    elseif soc2>=shi'; ...
'        pmin3=min(pb3,0.0);'; ...
'    end'; ...
'else'; ...
'    pmin3=pb3;pmax3=pb3;'; ...
'    fail_code=max(fail_code,3.0);'; ...
'end'; ...
'% EV current contract: charging only [-1,0].'; ...
'pmin4=-1.0;pmax4=0.0;'; ...
'pmin5=-1.0;pmax5=0.0;'; ...
''; ...
'up1=max(pmax1-pb1,0.0);up2=max(pmax2-pb2,0.0);up3=max(pmax3-pb3,0.0);up4=max(pmax4-pb4,0.0);up5=max(pmax5-pb5,0.0);'; ...
'dn1=max(pb1-pmin1,0.0);dn2=max(pb2-pmin2,0.0);dn3=max(pb3-pmin3,0.0);dn4=max(pb4-pmin4,0.0);dn5=max(pb5-pmin5,0.0);'; ...
'upT=up1+up2+up3+up4+up5;dnT=dn1+dn2+dn3+dn4+dn5;'; ...
''; ...
'% common frequency filter / primary P-f'; ...
'alphaF=1.0-exp(-2.0*piC*max(pf_fc,0.0)*TsS);'; ...
'alphaF=min(max(alphaF,0.0),1.0);'; ...
'efRaw=0.0;'; ...
'if s==2.0 || s==3.0'; ...
'    if master_valid>0.5'; ...
'        efRaw=50.0-master_f;'; ...
'    end'; ...
'end'; ...
'efn=efz+alphaF*(efRaw-efz);'; ...
'efDb=deadband(efn,abs(pf_db));'; ...
'dp_primary=0.0;'; ...
'if s==2.0 || s==3.0'; ...
'    dp_primary=kpf*efDb;'; ...
'end'; ...
''; ...
'% one secondary frequency-restoration integrator'; ...
'psecn=psecz;'; ...
'if s==0.0 || s==1.0 || s==2.0'; ...
'    psecn=0.0;'; ...
'elseif s==3.0 && master_valid>0.5 && stage_timer_n>=max(sec_entry,0.0)'; ...
'    rawNext=psecz+ki_sec*efn*TsS;'; ...
'    dmax=abs(sec_slew)*TsS;'; ...
'    psecn=psecz+clamp1(rawNext-psecz,-dmax,dmax);'; ...
'end'; ...
'psecn=clamp1(psecn,-dnT,upT);'; ...
'dp_secondary=psecz;'; ...
''; ...
'% shared slow voltage restoration, starts after additional delay in Stage3'; ...
'vsecn=vsecz;'; ...
'if s==0.0 || s==1.0 || s==2.0'; ...
'    vsecn=0.0;'; ...
'elseif s==3.0 && stage_timer_n>=max(vsec_delay,0.0) && finite1(pcc_v) && finite1(vpccz)'; ...
'    ev=(vpccz-pcc_v)/max(abs(vnom),1.0);'; ...
'    rawV=vsecz+ki_v*ev*TsS;'; ...
'    dVmax=abs(vsec_slew)*TsS;'; ...
'    vsecn=vsecz+clamp1(rawV-vsecz,-dVmax,dVmax);'; ...
'    vsecn=clamp1(vsecn,-abs(vsec_lim),abs(vsec_lim));'; ...
'end'; ...
'dv_secondary=vsecz;'; ...
''; ...
'% grid-recovery blend'; ...
'recn=rec_blend;'; ...
'if s==5.0'; ...
'    recn=min(rec_blend+0.0002,1.0);'; ...
'else'; ...
'    recn=0.0;'; ...
'end'; ...
''; ...
'% dispatch total and capability-proportional allocation'; ...
'dpt=0.0;'; ...
'if s==2.0'; ...
'    dpt=dp_primary;'; ...
'elseif s==3.0'; ...
'    dpt=dp_primary+psecz;'; ...
'elseif s==4.0'; ...
'    dpt=psecz;'; ...
'end'; ...
'dpt=clamp1(dpt,-dnT,upT);'; ...
'd1=0.0;d2=0.0;d3=0.0;d4=0.0;d5=0.0;'; ...
'if dpt>=0.0 && upT>1e-12'; ...
'    d1=dpt*up1/upT;d2=dpt*up2/upT;d3=dpt*up3/upT;d4=dpt*up4/upT;d5=dpt*up5/upT;'; ...
'elseif dpt<0.0 && dnT>1e-12'; ...
'    a=-dpt;d1=-a*dn1/dnT;d2=-a*dn2/dnT;d3=-a*dn3/dnT;d4=-a*dn4/dnT;d5=-a*dn5/dnT;'; ...
'end'; ...
'is1=clamp1(pb1+d1,pmin1,pmax1);'; ...
'is2=clamp1(pb2+d2,pmin2,pmax2);'; ...
'is3=clamp1(pb3+d3,pmin3,pmax3);'; ...
'is4=clamp1(pb4+d4,pmin4,pmax4);'; ...
'is5=clamp1(pb5+d5,pmin5,pmax5);'; ...
''; ...
'% exact bypass on grid; capture/hold legacy in prepare; island commands after J1'; ...
'if s==0.0 || s==1.0'; ...
'    po1=lp1;po2=lp2;po3=lp3;po4=lp4;po5=lp5;'; ...
'elseif s>=2.0 && s<=4.0'; ...
'    po1=is1;po2=is2;po3=is3;po4=is4;po5=is5;'; ...
'else'; ...
'    po1=(1.0-rec_blend)*is1+rec_blend*lp1;'; ...
'    po2=(1.0-rec_blend)*is2+rec_blend*lp2;'; ...
'    po3=(1.0-rec_blend)*is3+rec_blend*lp3;'; ...
'    po4=(1.0-rec_blend)*is4+rec_blend*lp4;'; ...
'    po5=(1.0-rec_blend)*is5+rec_blend*lp5;'; ...
'end'; ...
''; ...
'% voltage references: exact legacy on grid/prepare; common slow offset in island'; ...
'if s>=2.0 && s<=4.0'; ...
'    dvV=vsecz*vnom;'; ...
'    vo1=vb1+dvV;vo2=vb2+dvV;vo3=vb3+dvV;vo4=vb4+dvV;vo5=vb5+dvV;'; ...
'elseif s==5.0'; ...
'    vo1=(1.0-rec_blend)*(vb1+vsecz*vnom)+rec_blend*lv1;'; ...
'    vo2=(1.0-rec_blend)*(vb2+vsecz*vnom)+rec_blend*lv2;'; ...
'    vo3=(1.0-rec_blend)*(vb3+vsecz*vnom)+rec_blend*lv3;'; ...
'    vo4=(1.0-rec_blend)*(vb4+vsecz*vnom)+rec_blend*lv4;'; ...
'    vo5=(1.0-rec_blend)*(vb5+vsecz*vnom)+rec_blend*lv5;'; ...
'else'; ...
'    vo1=lv1;vo2=lv2;vo3=lv3;vo4=lv4;vo5=lv5;'; ...
'end'; ...
''; ...
'% GFL Fref transport: MasterF in island; original Fref otherwise.'; ...
'if s>=1.0 && s<=4.0 && master_valid>0.5'; ...
'    fo1=master_f;fo2=master_f;fo3=master_f;fo4=master_f;fo5=master_f;'; ...
'else'; ...
'    fo1=lf1;fo2=lf2;fo3=lf3;fo4=lf4;fo5=lf5;'; ...
'end'; ...
'end'; ...
''; ...
'function y=deadband(x,db)'; ...
'if abs(x)<=db'; ...
'    y=0.0;'; ...
'else'; ...
'    y=x-sign(x)*db;'; ...
'end'; ...
'end'; ...
''; ...
'function y=clamp1(x,lo,hi)'; ...
'y=min(max(x,lo),hi);'; ...
'end'; ...
''; ...
'function ok=finite1(x)'; ...
'ok=~(isnan(x)||isinf(x));'; ...
'end' ...
};
s=strjoin(L,newline);
end

%% =========================================================================
%% Final GFL manager builder
%% =========================================================================
function addFinalGFLManager(sub,pos,role,iSupMax,Ts,vffFc,kSlow,kFast,kSlew, ...
    kMag,vsFc,vsDb,vsSlew,frameHold,frameRelease,uvStart,uvFull,iMax,vNom)

add_block('built-in/SubSystem',sub,'Position',pos);

ins={'RawVdq','RawIpq','Pmeas','Qmeas','PrefCmd','QrefCmd','MeasuredIdIq','SystemStage','MasterF','VrefCmd'};
for k=1:numel(ins)
    add_block('built-in/Inport',[sub '/' ins{k}],'Port',num2str(k));
end

add_block('built-in/Demux',[sub '/AA15_RAWV_DEMUX'],'Outputs','2');
add_block('built-in/Demux',[sub '/AA15_RAWI_DEMUX'],'Outputs','2');
add_block('built-in/Demux',[sub '/AA15_MEASI_DEMUX'],'Outputs','2');
connectReplacingInput(sub,'RawVdq/1','AA15_RAWV_DEMUX/1');
connectReplacingInput(sub,'RawIpq/1','AA15_RAWI_DEMUX/1');
connectReplacingInput(sub,'MeasuredIdIq/1','AA15_MEASI_DEMUX/1');

stateNames={ ...
    'ANCH_D','ANCH_Q','VSLOW_D','VSLOW_Q','VSUP_BASE','VREF_BASE','PBASE', ...
    'KSLOW','KFAST','EV_FILTER','ISUP_Q','GP','GQ','VPU','FRAME','PREV_STAGE' ...
};
stateInit={'0','0','0','0','1','10000','0','1','1','0','0','1','1','1','0','0'};
for k=1:numel(stateNames)
    add_block('built-in/UnitDelay',[sub '/AA15_STATE_' stateNames{k}], ...
        'InitialCondition',stateInit{k},'SampleTime',num2str(Ts,17));
end

addParam(sub,'AA15_P_TS',Ts);
addParam(sub,'AA15_P_VFF_FC_HZ',vffFc);
addParam(sub,'AA15_P_KSLOW_ISLAND',kSlow);
addParam(sub,'AA15_P_KFAST_ISLAND',kFast);
addParam(sub,'AA15_P_KGAIN_SLEW',kSlew);
addParam(sub,'AA15_P_KMAG',kMag);
addParam(sub,'AA15_P_VSUP_FC_HZ',vsFc);
addParam(sub,'AA15_P_VSUP_DB',vsDb);
addParam(sub,'AA15_P_SUPPORT_SLEW',vsSlew);
addParam(sub,'AA15_P_FRAME_HOLD_V',frameHold);
addParam(sub,'AA15_P_FRAME_RELEASE_V',frameRelease);
addParam(sub,'AA15_P_UV_START_V',uvStart);
addParam(sub,'AA15_P_UV_FULL_V',uvFull);
addParam(sub,'AA15_P_IMAX',iMax);
addParam(sub,'AA15_P_ISUP_MAX',iSupMax);
addParam(sub,'AA15_P_ROLE',role);
addParam(sub,'AA15_P_VNOM',vNom);

core=[sub '/AA15_FINAL_GFL_STATE_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',core);
setMatlabFunctionScript(core,gflStateCoreScript());

src={ ...
    'AA15_RAWV_DEMUX/1','AA15_RAWV_DEMUX/2','Pmeas/1','Qmeas/1','PrefCmd/1','QrefCmd/1', ...
    'AA15_MEASI_DEMUX/1','AA15_MEASI_DEMUX/2','SystemStage/1','MasterF/1','VrefCmd/1', ...
    'AA15_STATE_ANCH_D/1','AA15_STATE_ANCH_Q/1','AA15_STATE_VSLOW_D/1','AA15_STATE_VSLOW_Q/1', ...
    'AA15_STATE_VSUP_BASE/1','AA15_STATE_VREF_BASE/1','AA15_STATE_PBASE/1', ...
    'AA15_STATE_KSLOW/1','AA15_STATE_KFAST/1','AA15_STATE_EV_FILTER/1','AA15_STATE_ISUP_Q/1', ...
    'AA15_STATE_GP/1','AA15_STATE_GQ/1','AA15_STATE_VPU/1','AA15_STATE_FRAME/1','AA15_STATE_PREV_STAGE/1', ...
    'AA15_P_TS/1','AA15_P_VFF_FC_HZ/1','AA15_P_KSLOW_ISLAND/1','AA15_P_KFAST_ISLAND/1','AA15_P_KGAIN_SLEW/1', ...
    'AA15_P_KMAG/1','AA15_P_VSUP_FC_HZ/1','AA15_P_VSUP_DB/1','AA15_P_SUPPORT_SLEW/1', ...
    'AA15_P_FRAME_HOLD_V/1','AA15_P_FRAME_RELEASE_V/1','AA15_P_UV_START_V/1','AA15_P_UV_FULL_V/1', ...
    'AA15_P_ISUP_MAX/1','AA15_P_VNOM/1','AA15_P_ROLE/1' ...
};
for k=1:numel(src)
    connectReplacingInput(sub,src{k},sprintf('AA15_FINAL_GFL_STATE_CORE/%d',k),'autorouting','on');
end

% State core outputs:
%  1 vff_d
%  2 vff_q
%  3 pref_eff
%  4 qref_eff
%  5 vpu
%  6 vsup_ref
%  7 pbase
%  8 pref_after_uv
%  9 uv_relief
% 10 isup_q_request
% 11 frame_req
% 12-25 next states except GP/GQ:
%     anchd,anchq,vslowd,vslowq,vsupbase,vrefbase,pbase,kslow,kfast,ev,isupq,vpu,frame,prevstage

stateMap={ ...
    12,'ANCH_D';13,'ANCH_Q';14,'VSLOW_D';15,'VSLOW_Q';16,'VSUP_BASE';17,'VREF_BASE';18,'PBASE'; ...
    19,'KSLOW';20,'KFAST';21,'EV_FILTER';22,'ISUP_Q';23,'VPU';24,'FRAME';25,'PREV_STAGE' ...
};
for k=1:size(stateMap,1)
    connectReplacingInput(sub,sprintf('AA15_FINAL_GFL_STATE_CORE/%d',stateMap{k,1}), ...
        ['AA15_STATE_' stateMap{k,2} '/1'],'autorouting','on');
end

% output10 duplicates the delayed support request used by the limiter.
% Keep it explicit for code contract, but terminate it so the subsystem has no dangling output.
add_block('built-in/Terminator',[sub '/AA15_UNUSED_ISUP_Q_REQ_TERM']);
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/10','AA15_UNUSED_ISUP_Q_REQ_TERM/1');

limit=[sub '/AA15_FINAL_GFL_LIMIT_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',limit);
setMatlabFunctionScript(limit,gflLimitCoreScript());

% limit inputs: rawId rawIq supportQ Imax stage role prefAfterUV pmeas masterF
lSrc={ ...
    'AA15_RAWI_DEMUX/1','AA15_RAWI_DEMUX/2','AA15_STATE_ISUP_Q/1','AA15_P_IMAX/1', ...
    'SystemStage/1','AA15_P_ROLE/1','AA15_FINAL_GFL_STATE_CORE/8','Pmeas/1','MasterF/1' ...
};
for k=1:numel(lSrc)
    connectReplacingInput(sub,lSrc{k},sprintf('AA15_FINAL_GFL_LIMIT_CORE/%d',k),'autorouting','on');
end

% limit outputs: finald finalq gp gq active supd supq
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/3','AA15_STATE_GP/1','autorouting','on');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/4','AA15_STATE_GQ/1','autorouting','on');

% vector muxes
add_block('built-in/Mux',[sub '/AA15_VFF_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/1','AA15_VFF_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/2','AA15_VFF_MUX/2');

add_block('built-in/Mux',[sub '/AA15_IFINAL_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/1','AA15_IFINAL_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/2','AA15_IFINAL_MUX/2');

add_block('built-in/Mux',[sub '/AA15_ISUP_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/6','AA15_ISUP_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/7','AA15_ISUP_MUX/2');

outNames={ ...
    'VffFinal','IrefFinal','PrefEff','QrefEff','Vpu','VsupportRef','Pbase','PrefAfterUV','UVRelief', ...
    'Isup','Kslow','Kfast','gP','gQ','CurrentLimitActive','FrameHoldReq','StageEcho','MasterFDiag','VrefCmdDiag', ...
    'Imax','Role','IsupMax' ...
};
for k=1:numel(outNames)
    add_block('built-in/Outport',[sub '/' outNames{k}],'Port',num2str(k));
end

connectReplacingInput(sub,'AA15_VFF_MUX/1','VffFinal/1');
connectReplacingInput(sub,'AA15_IFINAL_MUX/1','IrefFinal/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/3','PrefEff/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/4','QrefEff/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/5','Vpu/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/6','VsupportRef/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/7','Pbase/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/8','PrefAfterUV/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/9','UVRelief/1');
connectReplacingInput(sub,'AA15_ISUP_MUX/1','Isup/1');
connectReplacingInput(sub,'AA15_STATE_KSLOW/1','Kslow/1');
connectReplacingInput(sub,'AA15_STATE_KFAST/1','Kfast/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/3','gP/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/4','gQ/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/5','CurrentLimitActive/1');

% CRITICAL CAUSAL BOUNDARY:
% FrameHoldReq must be sourced directly from the UnitDelay state, never from
% AA15_FINAL_GFL_STATE_CORE.  MATLAB Function blocks are direct-feedthrough
% at block level; sourcing the request from the state core would close
% theta_exec -> dq/PQ measurement -> state core -> FrameHold -> theta_exec.
connectReplacingInput(sub,'AA15_STATE_FRAME/1','FrameHoldReq/1');

% State-core output11 is only a duplicate of framez; terminate it explicitly.
add_block('built-in/Terminator',[sub '/AA15_UNUSED_FRAME_REQ_CORE_TERM']);
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/11','AA15_UNUSED_FRAME_REQ_CORE_TERM/1');

connectReplacingInput(sub,'SystemStage/1','StageEcho/1');
connectReplacingInput(sub,'MasterF/1','MasterFDiag/1');
connectReplacingInput(sub,'VrefCmd/1','VrefCmdDiag/1');
connectReplacingInput(sub,'AA15_P_IMAX/1','Imax/1');
connectReplacingInput(sub,'AA15_P_ROLE/1','Role/1');
connectReplacingInput(sub,'AA15_P_ISUP_MAX/1','IsupMax/1');
end

function s=gflStateCoreScript()
L={ ...
'function [vff_d,vff_q,pref_eff,qref_eff,vpu,vsup_ref,pbase_out,pref_uv,uv_relief,isup_q_req,frame_req,anchdn,anchqn,vslowdn,vslowqn,vsupbasen,vrefbasen,pbasen,kslown,kfastn,evn,isupqn,vpun,framen,prevn] = fcn(vd,vq,pmeas,qmeas,pref,qref,idm,iqm,stage,master_f,vref_cmd,anchd,anchq,vslowd,vslowq,vsupbase,vrefbase,pbase,kslow,kfast,evz,isupqz,gpz,gqz,vpuz,framez,prevstage,Ts,vff_fc,kslow_target,kfast_target,kgain_slew,k_mag,vs_fc,vs_db,vs_slew,frame_hold_v,frame_release_v,uv_start,uv_full,isup_max,vnom,role)'; ...
'%#codegen'; ...
'piC=4.0*atan(1.0);'; ...
's=min(max(round(stage),0.0),5.0);'; ...
'TsS=max(Ts,1e-9);'; ...
'vpu=hypot(vd,vq);'; ...
'vpun=vpu;'; ...
'vpu_ctrl=vpuz;'; ...
'if ~finite1(vpu_ctrl) || vpu_ctrl<0.0 || vpu_ctrl>2.5'; ...
'    vpu_ctrl=vpu;'; ...
'end'; ...
'alphaV=1.0-exp(-2.0*piC*max(vff_fc,0.0)*TsS);'; ...
'alphaV=min(max(alphaV,0.0),1.0);'; ...
'alphaS=1.0-exp(-2.0*piC*max(vs_fc,0.0)*TsS);'; ...
'alphaS=min(max(alphaS,0.0),1.0);'; ...
''; ...
'% work-point capture'; ...
'anchdn=anchd;anchqn=anchq;vslowdn=vslowd;vslowqn=vslowq;'; ...
'vsupbasen=vsupbase;vrefbasen=vrefbase;pbasen=pbase;'; ...
'if s==0.0'; ...
'    anchdn=vd;anchqn=vq;vslowdn=vd;vslowqn=vq;'; ...
'    vsupbasen=vpu;vrefbasen=vref_cmd;pbasen=pmeas;'; ...
'elseif s==1.0'; ...
'    if prevstage<0.5'; ...
'        anchdn=vd;anchqn=vq;'; ...
'    end'; ...
'    vslowdn=vslowd+alphaV*(vd-vslowd);'; ...
'    vslowqn=vslowq+alphaV*(vq-vslowq);'; ...
'    vsupbasen=vpu;vrefbasen=vref_cmd;pbasen=pmeas;'; ...
'else'; ...
'    vslowdn=vslowd+alphaV*(vd-vslowd);'; ...
'    vslowqn=vslowq+alphaV*(vq-vslowq);'; ...
'end'; ...
'pbase_out=pbasen;'; ...
''; ...
'% VFF gain transition'; ...
'if s==0.0'; ...
'    ksTar=1.0;kfTar=1.0;'; ...
'elseif s>=1.0 && s<=4.0'; ...
'    ksTar=clamp1(kslow_target,0.0,1.0);'; ...
'    kfTar=clamp1(kfast_target,0.0,1.0);'; ...
'else'; ...
'    ksTar=1.0;kfTar=1.0;'; ...
'end'; ...
'kslown=slew1(kslow,ksTar,abs(kgain_slew));'; ...
'kfastn=slew1(kfast,kfTar,abs(kgain_slew));'; ...
'if s==0.0'; ...
'    vff_d=vd;vff_q=vq;'; ...
'else'; ...
'    vff_d=anchd+kslow*(vslowd-anchd)+kfast*(vd-vslowd);'; ...
'    vff_q=anchq+kslow*(vslowq-anchq)+kfast*(vq-vslowq);'; ...
'end'; ...
''; ...
'% local voltage reference = captured local V + common slow Vref delta'; ...
'vsup_ref=vsupbase;'; ...
'if s>=2.0 && s<=4.0'; ...
'    vsup_ref=vsupbase+(vref_cmd-vrefbase)/max(abs(vnom),1.0);'; ...
'end'; ...
''; ...
'% role-specific local undervoltage relief'; ...
'pref_uv=pref;uv_relief=0.0;'; ...
'if s>=2.0 && s<=4.0 && round(role)==3'; ...
'    hi=max(uv_start,uv_full);lo=min(uv_start,uv_full);'; ...
'    if vpu_ctrl>=hi'; ...
'        fac=1.0;'; ...
'    elseif vpu_ctrl<=lo'; ...
'        fac=0.0;'; ...
'    else'; ...
'        fac=(vpu_ctrl-lo)/max(hi-lo,1e-9);'; ...
'    end'; ...
'    pref0=clamp1(pref,-1.0,0.0);'; ...
'    pref_uv=pref0*fac;'; ...
'    uv_relief=pref_uv-pref0;'; ...
'end'; ...
''; ...
'% execution-aware upper P/Q references; previous-step gP/gQ breaks direct loop'; ...
'if s==0.0 || s==1.0 || s==5.0'; ...
'    pref_eff=pref_uv;qref_eff=qref;'; ...
'else'; ...
'    gp=clamp1(gpz,0.0,1.0);gq=clamp1(gqz,0.0,1.0);'; ...
'    pref_eff=pmeas+gp*(pref_uv-pmeas);'; ...
'    qref_eff=qmeas+gq*(qref-qmeas);'; ...
'end'; ...
''; ...
'% low-bandwidth local voltage support'; ...
'evn=evz;isupqn=isupqz;'; ...
'if s>=2.0 && s<=4.0'; ...
'    e=vsup_ref-vpu;'; ...
'    db=abs(vs_db);'; ...
'    if abs(e)<=db'; ...
'        edb=0.0;'; ...
'    else'; ...
'        edb=e-sign(e)*db;'; ...
'    end'; ...
'    evTrial=evz+alphaS*(edb-evz);'; ...
'    isMax=max(abs(isup_max),0.0);'; ...
'    target=clamp1(-k_mag*evTrial,-isMax,isMax);'; ...
'    if abs(k_mag)>1e-12 && abs(-k_mag*evTrial)>isMax+1e-12'; ...
'        evn=-target/k_mag;'; ...
'    else'; ...
'        evn=evTrial;'; ...
'    end'; ...
'    isupqn=slew1(isupqz,target,abs(vs_slew));'; ...
'else'; ...
'    evn=0.0;isupqn=slew1(isupqz,0.0,abs(vs_slew));'; ...
'end'; ...
'isup_q_req=isupqz;'; ...
''; ...
'% FrameHold request. The frame subsystem itself decides MasterF fallback/reacquire.'; ...
'framen=framez;'; ...
'if s>=2.0 && s<=4.0'; ...
'    if framez>0.5'; ...
'        if vpu>=frame_release_v'; ...
'            framen=0.0;'; ...
'        else'; ...
'            framen=1.0;'; ...
'        end'; ...
'    else'; ...
'        if vpu<frame_hold_v'; ...
'            framen=1.0;'; ...
'        else'; ...
'            framen=0.0;'; ...
'        end'; ...
'    end'; ...
'else'; ...
'    framen=0.0;'; ...
'end'; ...
'frame_req=framez;'; ...
'prevn=s;'; ...
'end'; ...
''; ...
'function y=slew1(x,t,r)'; ...
'd=t-x;'; ...
'if d>r'; ...
'    y=x+r;'; ...
'elseif d<-r'; ...
'    y=x-r;'; ...
'else'; ...
'    y=t;'; ...
'end'; ...
'end'; ...
''; ...
'function y=clamp1(x,lo,hi)'; ...
'y=min(max(x,lo),hi);'; ...
'end'; ...
''; ...
'function ok=finite1(x)'; ...
'ok=~(isnan(x)||isinf(x));'; ...
'end' ...
};
s=strjoin(L,newline);
end

function s=gflLimitCoreScript()
L={ ...
'function [fd,fq,gp,gq,active,supd,supq] = fcn(rawd,rawq,supq_req,imax,stage,role,pref_cmd,pmeas,master_f)'; ...
'%#codegen'; ...
's=min(max(round(stage),0.0),5.0);'; ...
'I=max(abs(imax),1e-9);'; ...
'if s==0.0 || s==1.0'; ...
'    fd=rawd;fq=rawq;gp=1.0;gq=1.0;active=0.0;supd=0.0;supq=0.0;return;'; ...
'end'; ...
''; ...
'% ESS2 under-frequency P-priority: preserve base P/Q current first, then add support.'; ...
'pPriority=(round(role)==2) && (master_f<49.98) && (pref_cmd>pmeas+0.002);'; ...
'if pPriority'; ...
'    mag=hypot(rawd,rawq);'; ...
'    if mag>I'; ...
'        lam=I/max(mag,1e-12);'; ...
'    else'; ...
'        lam=1.0;'; ...
'    end'; ...
'    bd=rawd*lam;bq=rawq*lam;'; ...
'    qcap=sqrt(max(I*I-bd*bd,0.0));'; ...
'    qtot=clamp1(bq+supq_req,-qcap,qcap);'; ...
'    fd=bd;fq=qtot;supd=0.0;supq=qtot-bq;'; ...
'    gp=lam;gq=lam;'; ...
'else'; ...
'    % PV/EV/default: voltage support request first, remaining vector capacity for raw P/Q current.'; ...
'    supq=clamp1(supq_req,-I,I);supd=0.0;'; ...
'    rem=sqrt(max(I*I-supq*supq,0.0));'; ...
'    mag=hypot(rawd,rawq);'; ...
'    if mag>rem && mag>1e-12'; ...
'        lam=rem/mag;'; ...
'    else'; ...
'        lam=1.0;'; ...
'    end'; ...
'    fd=rawd*lam;fq=rawq*lam+supq;gp=lam;gq=lam;'; ...
'end'; ...
'active=double(gp<0.999999 || gq<0.999999 || abs(supq-supq_req)>1e-9);'; ...
'end'; ...
''; ...
'function y=clamp1(x,lo,hi)'; ...
'y=min(max(x,lo),hi);'; ...
'end' ...
};
s=strjoin(L,newline);
end

%% =========================================================================
%% Master-frequency assisted FrameHold
%% =========================================================================
function addMasterFrequencyFrameHold(sub,pos,Ts)
add_block('built-in/SubSystem',sub,'Position',pos);
ins={'Freq_native','Theta_native','HoldReq','MasterF'};
for k=1:4,add_block('built-in/Inport',[sub '/' ins{k}],'Port',num2str(k));end

add_block('built-in/UnitDelay',[sub '/Freq_State'],'InitialCondition','50','SampleTime',num2str(Ts,17));
add_block('built-in/UnitDelay',[sub '/Theta_State'],'InitialCondition','0','SampleTime',num2str(Ts,17));
add_block('built-in/UnitDelay',[sub '/Mode_State'],'InitialCondition','0','SampleTime',num2str(Ts,17));

addParam(sub,'AA15_P_TS',Ts);

fn=[sub '/AA15_MASTER_FREQ_FRAME_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',fn);
setMatlabFunctionScript(fn,frameCoreScript());

src={'Freq_native/1','Theta_native/1','HoldReq/1','MasterF/1','Freq_State/1','Theta_State/1','Mode_State/1','AA15_P_TS/1'};
for k=1:numel(src),connectReplacingInput(sub,src{k},sprintf('AA15_MASTER_FREQ_FRAME_CORE/%d',k));end

% outputs: fexec thetaexec fnext tnext modenext
connectReplacingInput(sub,'AA15_MASTER_FREQ_FRAME_CORE/3','Freq_State/1');
connectReplacingInput(sub,'AA15_MASTER_FREQ_FRAME_CORE/4','Theta_State/1');
connectReplacingInput(sub,'AA15_MASTER_FREQ_FRAME_CORE/5','Mode_State/1');

add_block('built-in/Outport',[sub '/Freq_exec'],'Port','1');
add_block('built-in/Outport',[sub '/Theta_exec'],'Port','2');
connectReplacingInput(sub,'AA15_MASTER_FREQ_FRAME_CORE/1','Freq_exec/1');
connectReplacingInput(sub,'AA15_MASTER_FREQ_FRAME_CORE/2','Theta_exec/1');
end

function s=frameCoreScript()
L={ ...
'function [fexec,thetaexec,fnext,thetanext,modenext] = fcn(fnative,tnative,holdreq,fmaster,fz,tz,modez,Ts)'; ...
'%#codegen'; ...
'piC=4.0*atan(1.0);'; ...
'TsS=max(Ts,1e-9);'; ...
'masterOk=finite1(fmaster) && fmaster>45.0 && fmaster<55.0;'; ...
'nativeOk=finite1(fnative) && fnative>45.0 && fnative<55.0 && finite1(tnative);'; ...
'if holdreq>0.5'; ...
'    modenext=1.0;'; ...
'    if masterOk'; ...
'        fexec=fmaster;'; ...
'    else'; ...
'        fexec=fz;'; ...
'    end'; ...
'    thetaexec=wrap2pi(tz+2.0*piC*fexec*TsS);'; ...
'elseif modez>0.5 && nativeOk'; ...
'    % bumpless reacquire: advance from current state with bounded phase-frequency correction'; ...
'    d=wrapPi(tnative-tz);'; ...
'    if abs(d)<0.003'; ...
'        modenext=0.0;fexec=fnative;thetaexec=tnative;'; ...
'    else'; ...
'        modenext=2.0;'; ...
'        if masterOk'; ...
'            fbase=fmaster;'; ...
'        else'; ...
'            fbase=fnative;'; ...
'        end'; ...
'        corr=clamp1(2.0*d,-0.5,0.5);'; ...
'        fexec=fbase+corr;'; ...
'        thetaexec=wrap2pi(tz+2.0*piC*fexec*TsS);'; ...
'    end'; ...
'elseif nativeOk'; ...
'    modenext=0.0;fexec=fnative;thetaexec=tnative;'; ...
'else'; ...
'    modenext=1.0;fexec=fz;thetaexec=wrap2pi(tz+2.0*piC*fexec*TsS);'; ...
'end'; ...
'fnext=fexec;thetanext=thetaexec;'; ...
'end'; ...
''; ...
'function y=wrapPi(x)'; ...
'piC=4.0*atan(1.0);'; ...
'y=mod(x+piC,2.0*piC)-piC;'; ...
'end'; ...
''; ...
'function y=wrap2pi(x)'; ...
'piC=4.0*atan(1.0);'; ...
'y=mod(x,2.0*piC);'; ...
'if y<0.0,y=y+2.0*piC;end'; ...
'end'; ...
''; ...
'function y=clamp1(x,lo,hi)'; ...
'y=min(max(x,lo),hi);'; ...
'end'; ...
''; ...
'function ok=finite1(x)'; ...
'ok=~(isnan(x)||isinf(x));'; ...
'end' ...
};
s=strjoin(L,newline);
end

%% =========================================================================
%% Common block helpers
%% =========================================================================
function addParam(sub,name,value)
add_block('built-in/Constant',[sub '/' name], ...
    'Value',num2str(value,17),'SampleTime','0.0001');
end

function ep=inputSourceEndpoint(blockPath,inPort)
requireBlock(blockPath);
ph=get_param(blockPath,'PortHandles');
if inPort<1||inPort>numel(ph.Inport)
    error('Invalid input port %d for %s',inPort,blockPath);
end
lh=get_param(ph.Inport(inPort),'Line');
if isempty(lh)||lh<0,error('Input %d of %s is unconnected.',inPort,blockPath);end
sb=get_param(lh,'SrcBlockHandle');
sp=get_param(lh,'SrcPortHandle');
if sb<0||sp<0,error('Cannot resolve input source: %s in%d',blockPath,inPort);end
ep=struct('Block',getfullname(sb),'Port',get_param(sp,'PortNumber'));
end

function lh=connectAbsToInput(srcBlock,srcPort,dstBlock,dstPort)
requireBlock(srcBlock);
requireBlock(dstBlock);
phs=get_param(srcBlock,'PortHandles');
phd=get_param(dstBlock,'PortHandles');
if srcPort<1||srcPort>numel(phs.Outport),error('Bad source port %s/%d',srcBlock,srcPort);end
if dstPort<1||dstPort>numel(phd.Inport),error('Bad destination port %s/%d',dstBlock,dstPort);end
srcPH=phs.Outport(srcPort);
dstPH=phd.Inport(dstPort);
oldLine=get_param(dstPH,'Line');
if oldLine>=0
    oldSrc=get_param(oldLine,'SrcPortHandle');
    if oldSrc==srcPH,lh=oldLine;return;end
    delete_line(oldLine);
end
parent=get_param(dstBlock,'Parent');
if ~strcmp(parent,get_param(srcBlock,'Parent'))
    error('connectAbsToInput requires same parent. src=%s dst=%s',srcBlock,dstBlock);
end
lh=add_line(parent,srcPH,dstPH,'autorouting','on');
end

function lh=connectReplacingInput(parent,srcRel,dstRel,varargin)
[srcName,sp]=parseRelativePortToken(srcRel);
[dstName,dp]=parseRelativePortToken(dstRel);
src=[parent '/' srcName];
dst=[parent '/' dstName];
if getSimulinkBlockHandle(src)<=0,error('Source block missing: %s',src);end
if getSimulinkBlockHandle(dst)<=0,error('Destination block missing: %s',dst);end
phs=get_param(src,'PortHandles');
phd=get_param(dst,'PortHandles');
if sp<1||sp>numel(phs.Outport),error('Invalid source port: %s',srcRel);end
if dp<1||dp>numel(phd.Inport),error('Invalid destination port: %s',dstRel);end
srcPH=phs.Outport(sp);
dstPH=phd.Inport(dp);
oldLine=get_param(dstPH,'Line');
if oldLine>=0
    oldSrcPH=get_param(oldLine,'SrcPortHandle');
    if oldSrcPH==srcPH,lh=oldLine;return;end
    delete_line(oldLine);
end
if nargin>3
    lh=add_line(parent,srcRel,dstRel,varargin{:});
else
    lh=add_line(parent,srcRel,dstRel);
end
end

function [blockName,portNum]=parseRelativePortToken(tok)
if isstring(tok),tok=char(tok);end
slash=find(tok=='/',1,'last');
if isempty(slash)||slash==1||slash==numel(tok),error('Invalid relative token: %s',tok);end
blockName=tok(1:slash-1);
portNum=str2double(tok(slash+1:end));
if ~isfinite(portNum)||portNum<1||abs(portNum-round(portNum))>0,error('Bad port token: %s',tok);end
portNum=round(portNum);
end

function setMatlabFunctionScript(blockPath,scriptText)
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart','Path',blockPath);
if isempty(charts),error('Cannot locate MATLAB Function chart: %s',blockPath);end
charts(1).Script=scriptText;
end

function tf=blockExists(p)
tf=getSimulinkBlockHandle(p)>0;
end

function requireBlock(p)
if ~blockExists(p),error('Required block missing: %s',p);end
end

function s=safeParam(b,p)
s='<N/A>';
try
    v=get_param(b,p);
    if isnumeric(v)||islogical(v)
        s=mat2str(v,16);
    elseif ischar(v)
        s=v;
    else
        s=char(string(v));
    end
catch
end
end

function d=inportSourceDesc(b,n)
d='<none>';
ph=get_param(b,'PortHandles');
lh=get_param(ph.Inport(n),'Line');
if lh<0,return;end
sb=get_param(lh,'SrcBlockHandle');
sp=get_param(lh,'SrcPortHandle');
if sb<0||sp<0,return;end
d=sprintf('%s|out%d',getfullname(sb),get_param(sp,'PortNumber'));
end

function assertSource(dst,i,src,o,label)
actual=inportSourceDesc(dst,i);
want=sprintf('%s|out%d',src,o);
if ~strcmp(actual,want)
    error('%s source mismatch. want=%s actual=%s',label,want,actual);
end
end

function w=compiledWidths(b)
w=struct('Inport',[],'Outport',[]);
x=get_param(b,'CompiledPortWidths');
try,w.Inport=double(x.Inport(:).');catch,end
try,w.Outport=double(x.Outport(:).');catch,end
end

function requireWidthAt(a,i,w,label)
if numel(a)<i||a(i)~=w
    error('%s expected width%d at index%d actual=%s',label,w,i,mat2str(a));
end
end

function requireWidthVec(a,w,label)
if ~isequal(double(a(:).'),double(w(:).'))
    error('%s expected=%s actual=%s',label,mat2str(w),mat2str(a));
end
end

function [unIn,unOut]=findUnconnectedOrdinaryPorts(root)
inBlock={};inPort=[];inType={};
outBlock={};outPort=[];outType={};
blocks=find_system(root,'LookUnderMasks','all','FollowLinks','on','Type','Block');
for idx=1:numel(blocks)
    b=blocks{idx};
    if strcmp(b,root),continue;end
    bt=safeParam(b,'BlockType');
    try,ph=get_param(b,'PortHandles');catch,continue;end
    if ~strcmp(bt,'Inport') && isfield(ph,'Inport')
        for p=1:numel(ph.Inport)
            lh=-1;try,lh=get_param(ph.Inport(p),'Line');catch,end
            if isempty(lh)||lh<0
                inBlock{end+1,1}=b;inPort(end+1,1)=p;inType{end+1,1}=bt; %#ok<AGROW>
            end
        end
    end
    if ~strcmp(bt,'Outport') && isfield(ph,'Outport')
        for p=1:numel(ph.Outport)
            lh=-1;try,lh=get_param(ph.Outport(p),'Line');catch,end
            if isempty(lh)||lh<0||strcmp(destinationsOfOutputPort(ph.Outport(p)),'<none>')
                outBlock{end+1,1}=b;outPort(end+1,1)=p;outType{end+1,1}=bt; %#ok<AGROW>
            end
        end
    end
end
unIn=table(inBlock,inPort,inType,'VariableNames',{'Block','Port','BlockType'});
unOut=table(outBlock,outPort,outType,'VariableNames',{'Block','Port','BlockType'});
end

function dumpUnconnected(fid,T,kind)
for r=1:height(T)
    logf(fid,'  [UNCONNECTED %s] %s | port%d | type=%s',kind,T.Block{r},T.Port(r),T.BlockType{r});
end
end

function s=destinationsOfOutputPort(ph)
s='<none>';
try
    lh=get_param(ph,'Line');
    if isempty(lh)||lh<0,return;end
    db=get_param(lh,'DstBlockHandle');
    dp=get_param(lh,'DstPortHandle');
    db=db(:);dp=dp(:);
    parts={};
    for idx=1:min(numel(db),numel(dp))
        if db(idx)>=0&&dp(idx)>=0
            parts{end+1}=[getfullname(db(idx)) '|in' num2str(get_param(dp(idx),'PortNumber'))]; %#ok<AGROW>
        end
    end
    if ~isempty(parts),s=strjoin(parts,' ; ');end
catch
end
end

function strictCompileWithLoopError(model,fid,label)
% Strict loop gate using Simulink's own diagnostic.
% LEGACY_LOOP_QUERY_API is intentionally not used because it is unavailable in
% this MATLAB/RT-LAB environment for some compiled diagrams.
oldAlg=safeParam(model,'AlgebraicLoopMsg');
didCompile=false;
try
    set_param(model,'AlgebraicLoopMsg','error');
    feval(model,[],[],[],'compile');
    didCompile=true;
    feval(model,[],[],[],'term');
    didCompile=false;
    set_param(model,'AlgebraicLoopMsg',oldAlg);
    logf(fid,'[%s STRICT LOOP PASS] AlgebraicLoopMsg=error compile succeeded.',label);
catch ME
    if didCompile
        try,feval(model,[],[],[],'term');catch,end
    end
    try,set_param(model,'AlgebraicLoopMsg',oldAlg);catch,end
    error('[%s STRICT LOOP FAIL] %s',label,ME.message);
end
end

function f=resolveLoadedModelFile(model,auditedPath,fid)
f='';
cands={};
try,cands{end+1}=get_param(model,'FileName');catch,end %#ok<AGROW>
try,cands{end+1}=which([model '.slx']);catch,end %#ok<AGROW>
try,cands{end+1}=which(model);catch,end %#ok<AGROW>
try,cands{end+1}=fullfile(pwd,[model '.slx']);catch,end %#ok<AGROW>
cands{end+1}=auditedPath;
for idx=1:numel(cands)
    x=cands{idx};
    if isstring(x),x=char(x);end
    if isempty(x),continue;end
    valid=false;try,valid=isfile(x);catch,end
    logf(fid,'[MODEL CANDIDATE %d] %s | isfile=%d',idx,x,valid);
    if isempty(f)&&valid
        try,f=char(java.io.File(x).getCanonicalPath());catch,f=x;end
    end
end
end

function h=fileSha256(fn)
f=fopen(fn,'rb');
if f<0,error('Cannot open %s for SHA.',fn);end
c=onCleanup(@()fclose(f)); %#ok<NASGU>
b=fread(f,Inf,'*uint8');
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(b);
d=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(d,2).',1,[]));
end

function logf(fid,fmt,varargin)
s=sprintf(fmt,varargin{:});
fprintf('%s\n',s);
fprintf(fid,'%s\n',s);
end

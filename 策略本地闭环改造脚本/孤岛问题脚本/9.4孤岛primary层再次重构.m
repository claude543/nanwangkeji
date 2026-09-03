%% PATCH_K26_V5_V34_PORT_RECONSTRUCTION_V4_5.m
% K26_V5 V3.4 -> 五GFL孤岛端口重构 V4.5
%
% PURPOSE
% -------
% 只替换五台 GFL 的：
%   1) AA15_ISLAND_GFL_SUPPORT_MANAGER
%   2) AA15_ENG_DIAG_MUX
%
% 不修改：
%   - ESS1 GFM / F21 / F24 / F25
%   - SM_Master final coordinator / G29 / MasterF delay
%   - Frame subsystem本体
%   - Power Control / Current Regulator / Rff / Lff
%   - Kslow=.5 / Kfast=0 / 原物理网络 / OpComm / OpWrite数量
%
% 新增：
%   - 5~20Hz causal dq active damping
%   - role-aware d-axis damping (PV/ESS2/EV)
%   - support-aware P/Q anti-cancellation release
%   - strict 2-D current-circle limiter
%   - slow-q downstream anti-windup
%   - Stage2~4 permanent MasterF-assisted FrameHold request
%   - Vbp/gamma/support-clip high-rate diagnostics
%
% HARD SAFETY
% -----------
% - MATLAB R2023b compatible; no fflush.
% - Current audited disk SHA must match exactly.
% - RT-LAB/model-function PAUSED is not auto-stopped by MATLAB.
% - Structural patching requires the user to Reset/stop in RT-LAB first.
% - Once STOPPED, patch reloads the exact disk model before any structural edit.
% - Numeric self-test + scratch compile happen before real-model edit.
% - Full SLX backup before real edit.
% - save_system exactly once.
% - Any failure after save restores the whole SLX backup.
% - Strict compile uses AlgebraicLoopMsg=error.
%
% AFTER PASS
% ----------
% Run VERIFY_K26_V5_V34_PORT_RECONSTRUCTION_V4_0.m.
% Do NOT Rebuild until verifier prints:
%   PORT RECONSTRUCTION V4.5 POSTPATCH HEALTH PASS
%
% 2026-09-04

clearvars;
clc;

MODEL='K26_V5';
AUDITED_MODEL_FILE='D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V5\models\K26_V5\K26_V5.slx';
EXPECTED_SHA256='e2bfebe52de02215bb38cd0597dc382abe0c51c783d222b38aaef0f2ef1d138b';
EXPECTED_V34_COORD_SCRIPT_SHA='544f9d97ea8bff7692bb9caf09b1ac908ed14d29706fff81591205bab06632bd';
EXPECTED_V34_STATE_SCRIPT_SHA='695c15890b42230a40be46cb5b7202e974253f8a5153a587644e8894abd5daa9';
EXPECTED_V34_LIMIT_SCRIPT_SHA='5f0bbaabd1df66a1f80acbdc20ef2b6710c2804831f89dff2733c3bc8dc21413';
EXPECTED_V34_FRAME_SCRIPT_SHA='c1c4eca8c8de9e7e617ea25d7980b77314c90079c2d5b1ba0c09265c0e88d2d7';

% SOURCE OF TRUTH:
% Formal V3.4 persisted SAVE PASS / FINAL SHA.
% Do not replace this with a SHA copied from a later design/audit note.

% -------------------------------------------------------------------------
% Frozen V4.5 first-run parameters
% -------------------------------------------------------------------------
DEF_TS=0.0001;

% Existing VFF / slow voltage support kept.
DEF_VFF_FC=1.0;
DEF_KSLOW=0.50;
DEF_KFAST=0.0;
DEF_KGAIN_SLEW=0.01;
DEF_KMAG=0.25;
DEF_VSUP_FC=1.0;
DEF_VSUP_DB=0.01;
DEF_VSUP_SLEW=0.001;
DEF_UV_START=0.95;
DEF_UV_FULL=0.85;
DEF_IMAX=1.20;
DEF_ISUP=[0.20 0.20 0.30 0.15 0.15];
DEF_VNOM=10000.0;
ROLES=[1 1 2 3 3]; % 1 PV, 2 ESS2, 3 EV

% New explicit active damping.
DEF_DAMP_ENABLE=1.0;
DEF_DAMP_HP_HZ=5.0;
DEF_DAMP_LP_HZ=20.0;
DEF_GDAMP=1.0;

% New support-aware P/Q release.
DEF_RELEASE_ENABLE=1.0;
DEF_RELEASE_FC_HZ=2.0;
DEF_I_RELEASE_FULL=0.05;
DEF_GAMMA_P_MIN=0.70;
DEF_GAMMA_Q_MIN=0.20;

NAMES={'PV1','PV2','ESS2','EV1','EV2'};
CTRLS={ ...
    [MODEL '/SS_Slave3/PV1_Control'], ...
    [MODEL '/SS_Slave3/PV2_Control'], ...
    [MODEL '/SS_Slave2/ESS2_Control'], ...
    [MODEL '/SS_Slave/EV1_Control'], ...
    [MODEL '/SS_Slave/Control System'] ...
};
SM=[MODEL '/SM_Master'];

OPPATHS={ ...
    [MODEL '/SS_Slave/AA15_ROOTDIAG_EV12_OPWRITE_G26'], ...
    [MODEL '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'], ...
    [MODEL '/SS_Slave3/AA15_ROOTDIAG_PV12_OPWRITE_G28'], ...
    [SM '/AA15_FREQDIAG_SM_OPWRITE_G29'], ...
    [MODEL '/SS_Slave2/AA15_FREQDIAG_ESS1_OPWRITE_G30'] ...
};
OPNAMES={'G26','G27','G28','G29','G30'};
EXPECTED_OPWIDTHS=[82 41 82 38 128];

STAMP=datestr(now,'yyyymmdd_HHMMSS');
LOG_FILE=['9.04_PATCH_K26_V5_V34_PORT_RECONSTRUCTION_V4_5_' STAMP '.txt'];

fid=fopen(LOG_FILE,'w','n','UTF-8');
if fid<0,error('Cannot create patch log: %s',LOG_FILE);end
cleanupFid=onCleanup(@() fclose(fid)); %#ok<NASGU>

logf(fid,repmat('=',1,190));
logf(fid,'K26_V5 V3.4 -> FIVE-GFL PORT RECONSTRUCTION V4.5');
logf(fid,'[SCOPE] replace five GFL managers + diag muxes only.');
logf(fid,'[ROOT] explicit 5~20Hz dq damping + P/Q anti-cancellation + strict current circle.');
logf(fid,repmat('=',1,190));

%% =========================================================================
%% 0. MATLAB compatibility + pure numerical self-test
%% =========================================================================
runPatchCompatibilitySelfTest(fid);
runPortMathSelfTest(fid,DEF_TS,DEF_DAMP_HP_HZ,DEF_DAMP_LP_HZ,DEF_GDAMP, ...
    DEF_IMAX,DEF_ISUP,ROLES);

%% =========================================================================
%% 1. Resolve loaded/disk model and normalize to exact STOPPED disk baseline
%% =========================================================================
if ~bdIsLoaded(MODEL)
    if ~isfile(AUDITED_MODEL_FILE)
        error('PATCH ABORT: audited model file missing: %s',AUDITED_MODEL_FILE);
    end
    load_system(AUDITED_MODEL_FILE);
end

status=lower(strtrim(safeParam(MODEL,'SimulationStatus')));
if strcmp(status,'paused')
    error([ ...
        'PATCH ABORT BEFORE EDIT: K26_V5 is PAUSED under an RT-LAB/model-function compiled context. ' ...
        'MATLAB automatic stop is intentionally NOT attempted because SimulationCommand is unsupported for this context. ' ...
        'MANUAL ACTION REQUIRED: in RT-LAB, Reset/stop the model until ' ...
        'get_param(''K26_V5'',''SimulationStatus'') returns ''stopped'', then rerun V4.5. ' ...
        'No structural edit, backup replacement, or save_system has occurred.' ...
    ]);
elseif ~strcmp(status,'stopped')
    error('PATCH ABORT BEFORE EDIT: SimulationStatus must be stopped; current=%s. No model edit/save has occurred.',status);
end

if ~strcmpi(safeParam(MODEL,'Dirty'),'off')
    error('PATCH ABORT: model Dirty=%s before disk normalization.',safeParam(MODEL,'Dirty'));
end

modelFile=resolveLoadedModelFile(MODEL,AUDITED_MODEL_FILE,fid);
if isempty(modelFile)
    error('PATCH ABORT: cannot resolve current K26_V5.slx.');
end

% Reload exact disk image. This prevents any target/runtime A/B state from
% becoming an accidental patch baseline.
close_system(MODEL,0);
load_system(modelFile);

if ~strcmpi(safeParam(MODEL,'SimulationStatus'),'stopped')
    error('PATCH ABORT: reloaded disk model is not STOPPED.');
end
if ~strcmpi(safeParam(MODEL,'Dirty'),'off')
    error('PATCH ABORT: reloaded disk model Dirty is not off.');
end

sha0=fileSha256(modelFile);
logf(fid,'[MODEL FILE] %s',modelFile);
logf(fid,'[SHA BEFORE] %s',sha0);
if ~strcmpi(sha0,EXPECTED_SHA256)
    error(['PATCH ABORT BEFORE EDIT: SHA mismatch. expected=%s actual=%s. ' ...
           'Only the persisted formal V3.4 baseline is accepted. No structural edit/save has occurred.'], ...
           EXPECTED_SHA256,sha0);
end
logf(fid,'[V3.4 AUDITED SHA PASS] %s',sha0);

%% =========================================================================
%% 2. Exact V3.4 hard preflight
%% =========================================================================
logf(fid,'\n--- 2. V3.4 HARD PREFLIGHT ---');
logf(fid,'[FINGERPRINT RULE] Power Control = two scalar PI channels; Current Regulator = one width-2 vector PI channel.');
logf(fid,'[FINGERPRINT RULE] Exact audited block paths/expressions are checked; no Kp/Ki count search is used.');
logf(fid,'[SCRIPT SHA RULE] Hash MATLAB Function BODY only; device block path is excluded.');
logf(fid,'[SCRIPT SHA SOURCE] V1.3 audit: state=%s limit=%s frame=%s coord=%s', ...
    EXPECTED_V34_STATE_SCRIPT_SHA,EXPECTED_V34_LIMIT_SCRIPT_SHA, ...
    EXPECTED_V34_FRAME_SCRIPT_SHA,EXPECTED_V34_COORD_SCRIPT_SHA);

requireBlock([SM '/AA15_FINAL_SYSTEM_STAGE']);
requireBlock([SM '/AA15_FINAL_ISLAND_COORDINATOR']);
requireBlock([SM '/AA15_FINAL_MASTER_F_DELAY_Z1']);

% Exact MATLAB Function body hashes from completed V1.3 read-only audit.
% Hashes intentionally exclude block paths. Different device paths must never
% make identical Frame scripts look different.
assertEmChartContentHash([SM '/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE'], ...
    EXPECTED_V34_COORD_SCRIPT_SHA,'V3.4 central coordinator');
logf(fid,'[V3.4 COORDINATOR CONTENT SHA PASS] %s',EXPECTED_V34_COORD_SCRIPT_SHA);
for i=1:5
    dev=NAMES{i};ctrl=CTRLS{i};
    mgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
    diag=[ctrl '/AA15_ENG_DIAG_MUX'];
    frame=[ctrl '/Measurements/AA15_PLL_EXEC_FRAME_HOLD'];

    requireBlock(mgr);requireBlock(diag);requireBlock(frame);
    requireBlock([mgr '/AA15_FINAL_GFL_STATE_CORE']);
    requireBlock([mgr '/AA15_FINAL_GFL_LIMIT_CORE']);
    requireBlock([ctrl '/Power Control Loop']);
    requireBlock([ctrl '/Current Regulator']);
    requireBlock([ctrl '/AA15_ENG_DIAG_OUT41']);

    % Current V3.4 external manager contract.
    assertSource(mgr,1,[ctrl '/From26'],1,[dev ' raw Vdq']);
    assertSource(mgr,2,[ctrl '/Power Control Loop'],1,[dev ' raw Ipq']);
    assertSource(mgr,3,[ctrl '/From21'],1,[dev ' Pmeas']);
    assertSource(mgr,4,[ctrl '/From51'],1,[dev ' Qmeas']);
    assertSource(mgr,5,[ctrl '/Pref'],1,[dev ' Pref']);
    assertSource(mgr,6,[ctrl '/Qref'],1,[dev ' Qref']);
    assertSource(mgr,7,[ctrl '/From28'],1,[dev ' measured IdIq']);
    assertSource(mgr,8,[ctrl '/Droop_On'],1,[dev ' system stage']);
    assertSource(mgr,9,[ctrl '/Fref'],1,[dev ' MasterF']);
    assertSource(mgr,10,[ctrl '/Vref'],1,[dev ' Vref']);

    assertSource([ctrl '/Current Regulator'],1,mgr,1,[dev ' VFF']);
    assertSource([ctrl '/Goto18'],1,mgr,2,[dev ' final Iref']);
    assertSource([ctrl '/Power Control Loop'],3,mgr,3,[dev ' PrefEff']);
    assertSource([ctrl '/Power Control Loop'],6,mgr,4,[dev ' QrefEff']);
    assertSource([ctrl '/Measurements'],5,mgr,16,[dev ' frame request']);

    % V3.4 proven algebraic-loop break: external FrameHoldReq is the direct
    % UnitDelay state output, NOT a MATLAB Function output.
    assertSource([mgr '/FrameHoldReq'],1,[mgr '/AA15_STATE_FRAME'],1,[dev ' V3.4 delayed FrameHoldReq']);
    requireBlock([mgr '/AA15_UNUSED_FRAME_REQ_CORE_TERM']);
    assertSource([mgr '/AA15_UNUSED_FRAME_REQ_CORE_TERM'],1,[mgr '/AA15_FINAL_GFL_STATE_CORE'],11, ...
        [dev ' V3.4 unused core frame output terminator']);

    % Exact current V3.4 manager baseline.
    assertScalarValue([mgr '/AA15_P_TS'],DEF_TS,[dev ' Ts']);
    assertScalarValue([mgr '/AA15_P_VFF_FC_HZ'],DEF_VFF_FC,[dev ' VFF fc']);
    assertScalarValue([mgr '/AA15_P_KSLOW_ISLAND'],DEF_KSLOW,[dev ' Kslow']);
    assertScalarValue([mgr '/AA15_P_KFAST_ISLAND'],DEF_KFAST,[dev ' Kfast']);
    assertScalarValue([mgr '/AA15_P_KGAIN_SLEW'],DEF_KGAIN_SLEW,[dev ' K gain slew']);
    assertScalarValue([mgr '/AA15_P_KMAG'],DEF_KMAG,[dev ' Kmag']);
    assertScalarValue([mgr '/AA15_P_VSUP_FC_HZ'],DEF_VSUP_FC,[dev ' Vsup fc']);
    assertScalarValue([mgr '/AA15_P_VSUP_DB'],DEF_VSUP_DB,[dev ' Vsup db']);
    assertScalarValue([mgr '/AA15_P_SUPPORT_SLEW'],DEF_VSUP_SLEW,[dev ' Vsup slew']);
    assertScalarValue([mgr '/AA15_P_UV_START_V'],DEF_UV_START,[dev ' UV start']);
    assertScalarValue([mgr '/AA15_P_UV_FULL_V'],DEF_UV_FULL,[dev ' UV full']);
    assertScalarValue([mgr '/AA15_P_IMAX'],DEF_IMAX,[dev ' Imax']);
    assertScalarValue([mgr '/AA15_P_ISUP_MAX'],DEF_ISUP(i),[dev ' Isup']);
    assertScalarValue([mgr '/AA15_P_ROLE'],ROLES(i),[dev ' role']);
    assertScalarValue([mgr '/AA15_P_VNOM'],DEF_VNOM,[dev ' Vnom']);

    % Freeze existing Power / Current control internals.
    assertOriginalGFLControllerFingerprint(ctrl,dev);

    % Exact current V3.4 MATLAB Function bodies.
    assertEmChartContentHash([mgr '/AA15_FINAL_GFL_STATE_CORE'], ...
        EXPECTED_V34_STATE_SCRIPT_SHA,[dev ' V3.4 state core']);
    assertEmChartContentHash([mgr '/AA15_FINAL_GFL_LIMIT_CORE'], ...
        EXPECTED_V34_LIMIT_SCRIPT_SHA,[dev ' V3.4 limit core']);
    assertEmChartContentHash([frame '/AA15_MASTER_FREQ_FRAME_CORE'], ...
        EXPECTED_V34_FRAME_SCRIPT_SHA,[dev ' V3.4 frame core']);

    logf(fid,'[V3.4 DEVICE PREFLIGHT PASS] %s | state/limit/frame content SHA exact',dev);
end

if numel(find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*'))~=5
    error('Expected exactly five OpWrite blocks before patch.');
end
for i=1:5,requireBlock(OPPATHS{i});end

% ESS1 frozen-chain existence.
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

%% =========================================================================
%% 3. Scratch compile NEW manager before touching K26_V5
%% =========================================================================
logf(fid,'\n--- 3. SCRATCH COMPILE NEW V4 MANAGER ---');
scratchPreflightPortV4(DEF_TS,DEF_VFF_FC,DEF_KSLOW,DEF_KFAST,DEF_KGAIN_SLEW, ...
    DEF_KMAG,DEF_VSUP_FC,DEF_VSUP_DB,DEF_VSUP_SLEW,DEF_UV_START,DEF_UV_FULL, ...
    DEF_IMAX,DEF_ISUP(1),ROLES(1),DEF_VNOM,DEF_DAMP_ENABLE,DEF_DAMP_HP_HZ, ...
    DEF_DAMP_LP_HZ,DEF_GDAMP,DEF_RELEASE_ENABLE,DEF_RELEASE_FC_HZ, ...
    DEF_I_RELEASE_FULL,DEF_GAMMA_P_MIN,DEF_GAMMA_Q_MIN);
logf(fid,'[SCRATCH PASS] V4 manager compiles with strict algebraic-loop setting.');

%% =========================================================================
%% 3B. RECONFIRM DISK SHA BEFORE ANY REAL-MODEL EDIT
%% =========================================================================
shaPreEdit=fileSha256(modelFile);
if ~strcmpi(shaPreEdit,EXPECTED_SHA256)
    error(['PATCH ABORT BEFORE EDIT: disk SHA changed during preflight. expected=%s actual=%s. ' ...
           'No real-model structural edit has started.'],EXPECTED_SHA256,shaPreEdit);
end
logf(fid,'[PRE-EDIT SHA RECONFIRM PASS] %s',shaPreEdit);

%% =========================================================================
%% 4. Full SLX backup
%% =========================================================================
modelDir=fileparts(modelFile);
backupFile=fullfile(modelDir,['K26_V5__PRE_V4_PORT_RECONSTRUCTION_' STAMP '.slx']);
[ok,msg]=copyfile(modelFile,backupFile);
if ~ok,error('Full SLX backup failed: %s',msg);end
logf(fid,'[BACKUP PASS] %s',backupFile);

savedToDisk=false;
compileOwned=false;
loopOrigCurrent='';

try
    %% =====================================================================
    %% 5. Replace only five managers + diag muxes
    %% =====================================================================
    logf(fid,'\n--- 5. REPLACE FIVE MANAGERS + DIAG MUXES ---');

    for i=1:5
        dev=NAMES{i};ctrl=CTRLS{i};
        oldMgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
        oldDiag=[ctrl '/AA15_ENG_DIAG_MUX'];

        posMgr=get_param(oldMgr,'Position');
        posDiag=get_param(oldDiag,'Position');

        delete_block(oldMgr);
        delete_block(oldDiag);

        addPortReconstructionManagerV4([ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'],posMgr, ...
            ROLES(i),DEF_ISUP(i),DEF_TS,DEF_VFF_FC,DEF_KSLOW,DEF_KFAST,DEF_KGAIN_SLEW, ...
            DEF_KMAG,DEF_VSUP_FC,DEF_VSUP_DB,DEF_VSUP_SLEW,DEF_UV_START,DEF_UV_FULL, ...
            DEF_IMAX,DEF_VNOM,DEF_DAMP_ENABLE,DEF_DAMP_HP_HZ,DEF_DAMP_LP_HZ,DEF_GDAMP, ...
            DEF_RELEASE_ENABLE,DEF_RELEASE_FC_HZ,DEF_I_RELEASE_FULL, ...
            DEF_GAMMA_P_MIN,DEF_GAMMA_Q_MIN);

        mgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];

        % Same 10-input external contract.
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

        % Same functional parent connections.
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/1','Current Regulator/1','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/2','Goto18/1','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/3','Power Control Loop/3','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/4','Power Control Loop/6','autorouting','on');
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/16','Measurements/5','autorouting','on');

        % Keep 33 Mux inputs = 41 scalar rows.
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
        % 11-12 Current PI[2]
        connectReplacingInput(ctrl,'Current Regulator/2','AA15_ENG_DIAG_MUX/6','autorouting','on');
        % 13-14 Vconv[2]
        connectReplacingInput(ctrl,'Current Regulator/1','AA15_ENG_DIAG_MUX/7','autorouting','on');
        % 15 ModIndex
        connectReplacingInput(ctrl,'From/1','AA15_ENG_DIAG_MUX/8','autorouting','on');
        % 16 Pmeas
        connectReplacingInput(ctrl,'From21/1','AA15_ENG_DIAG_MUX/9','autorouting','on');
        % 17 Qmeas
        connectReplacingInput(ctrl,'From51/1','AA15_ENG_DIAG_MUX/10','autorouting','on');
        % 18 GammaP
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/19','AA15_ENG_DIAG_MUX/11','autorouting','on');
        % 19 native PLL frequency (existing reliable diagnostic)
        connectReplacingInput(ctrl,'Measurements/10','AA15_ENG_DIAG_MUX/12','autorouting','on');
        % 20 Stage
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/17','AA15_ENG_DIAG_MUX/13','autorouting','on');
        % 21 Vpu
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/5','AA15_ENG_DIAG_MUX/14','autorouting','on');
        % 22 VsupportRef
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/6','AA15_ENG_DIAG_MUX/15','autorouting','on');
        % 23 GammaQ
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/7','AA15_ENG_DIAG_MUX/16','autorouting','on');
        % 24 Pref command
        connectReplacingInput(ctrl,'Pref/1','AA15_ENG_DIAG_MUX/17','autorouting','on');
        % 25 Pref after UV relief
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/8','AA15_ENG_DIAG_MUX/18','autorouting','on');
        % 26 PrefEff
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/3','AA15_ENG_DIAG_MUX/19','autorouting','on');
        % 27 Qref command
        connectReplacingInput(ctrl,'Qref/1','AA15_ENG_DIAG_MUX/20','autorouting','on');
        % 28 QrefEff
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/4','AA15_ENG_DIAG_MUX/21','autorouting','on');
        % 29-30 actual TOTAL support current [d q]
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/10','AA15_ENG_DIAG_MUX/22','autorouting','on');
        % 31 Kslow
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/11','AA15_ENG_DIAG_MUX/23','autorouting','on');
        % 32 Kfast
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/12','AA15_ENG_DIAG_MUX/24','autorouting','on');
        % 33 gP_limit
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/13','AA15_ENG_DIAG_MUX/25','autorouting','on');
        % 34 gQ_limit
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/14','AA15_ENG_DIAG_MUX/26','autorouting','on');
        % 35 CurrentCapabilityActive
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/15','AA15_ENG_DIAG_MUX/27','autorouting','on');
        % 36 FrameHold request
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/16','AA15_ENG_DIAG_MUX/28','autorouting','on');
        % 37 MasterF
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/18','AA15_ENG_DIAG_MUX/29','autorouting','on');
        % 38 Vref command (direct root input; manager port no longer spent on this diagnostic)
        connectReplacingInput(ctrl,'Vref/1','AA15_ENG_DIAG_MUX/30','autorouting','on');
        % 39 Vbp_d
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/20','AA15_ENG_DIAG_MUX/31','autorouting','on');
        % 40 Vbp_q
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/21','AA15_ENG_DIAG_MUX/32','autorouting','on');
        % 41 SupportClipActive
        connectReplacingInput(ctrl,'AA15_ISLAND_GFL_SUPPORT_MANAGER/22','AA15_ENG_DIAG_MUX/33','autorouting','on');

        connectReplacingInput(ctrl,'AA15_ENG_DIAG_MUX/1','AA15_ENG_DIAG_OUT41/1','autorouting','on');

        immediatePostassertV4(ctrl,dev,ROLES(i),DEF_ISUP(i));
        logf(fid,'[V4 DEVICE EDIT PASS] %s',dev);
    end

    %% =====================================================================
    %% 6. Frozen subsystem checks before compile
    %% =====================================================================
    assertEmChartContentHash([SM '/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE'], ...
        EXPECTED_V34_COORD_SCRIPT_SHA,'presave central coordinator');
    for i=1:5
        ctrl=CTRLS{i};
        assertEmChartContentHash([ctrl '/Measurements/AA15_PLL_EXEC_FRAME_HOLD/AA15_MASTER_FREQ_FRAME_CORE'], ...
            EXPECTED_V34_FRAME_SCRIPT_SHA,[NAMES{i} ' presave frame core']);
        assertOriginalGFLControllerFingerprint(ctrl,NAMES{i});
    end
    for k=1:numel(ESS_KEEP),requireBlock(ESS_KEEP{k});end

    %% =====================================================================
    %% 7. Strict full-model compile + width/loop/port contract
    %% =====================================================================
    logf(fid,'\n--- 7. STRICT FULL MODEL COMPILE ---');
    logf(fid,'[CAUSAL LOOP BREAK] FrameHoldReq = AA15_STATE_FRAME UnitDelay direct output on all five GFLs.');
    logf(fid,'[CAUSAL LOOP BREAK] AA15_FINAL_GFL_STATE_CORE output11 is terminated and cannot drive FrameHoldReq.');
    loopOrigCurrent=beginStrictCompile(MODEL,fid,'PRE-SAVE');
    compileOwned=true;

    for i=1:5
        wm=compiledWidths([CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER']);
        wd=compiledWidths([CTRLS{i} '/AA15_ENG_DIAG_MUX']);
        requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],[NAMES{i} ' manager inputs']);
        requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],[NAMES{i} ' manager outputs']);
        requireWidthAt(wd.Outport,1,41,[NAMES{i} ' diag41']);
    end

    for i=1:5
        w=compiledWidths(OPPATHS{i});
        requireWidthAt(w.Inport,1,EXPECTED_OPWIDTHS(i),[OPNAMES{i} ' width']);
        logf(fid,'[%s] width=%d',OPNAMES{i},w.Inport(1));
    end

    endStrictCompile(MODEL,loopOrigCurrent);
    compileOwned=false;
    loopOrigCurrent='';

    rootsToAudit={};
    for i=1:5
        rootsToAudit{end+1}=[CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER']; %#ok<AGROW>
    end
    for r=1:numel(rootsToAudit)
        [unIn,unOut]=findUnconnectedOrdinaryPorts(rootsToAudit{r});
        if height(unIn)>0,dumpUnconnected(fid,unIn,'INPUT');end
        if height(unOut)>0,dumpUnconnected(fid,unOut,'OUTPUT');end
        if height(unIn)>0||height(unOut)>0
            error('Unconnected ordinary port inside %s',rootsToAudit{r});
        end
    end

    if numel(find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*'))~=5
        error('OpWrite count changed from five.');
    end

    %% =====================================================================
    %% 8. Save exactly once
    %% =====================================================================
    logf(fid,'\n--- 8. SAVE EXACTLY ONCE ---');
    save_system(MODEL);
    savedToDisk=true;
    shaSaved=fileSha256(modelFile);
    logf(fid,'[SAVE PASS] SHA=%s',shaSaved);

    %% =====================================================================
    %% 9. Close/reload persistence audit
    %% =====================================================================
    close_system(MODEL,0);
    load_system(modelFile);
    if ~strcmpi(safeParam(MODEL,'Dirty'),'off')
        error('Reloaded V4 model Dirty is not off.');
    end

    for i=1:5
        immediatePostassertV4(CTRLS{i},NAMES{i},ROLES(i),DEF_ISUP(i));
        assertOriginalGFLControllerFingerprint(CTRLS{i},NAMES{i});
    end
    assertEmChartContentHash([SM '/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE'], ...
        EXPECTED_V34_COORD_SCRIPT_SHA,'persisted central coordinator');
    for i=1:5
        assertEmChartContentHash([CTRLS{i} '/Measurements/AA15_PLL_EXEC_FRAME_HOLD/AA15_MASTER_FREQ_FRAME_CORE'], ...
            EXPECTED_V34_FRAME_SCRIPT_SHA,[NAMES{i} ' persisted frame core']);
    end

    loopOrigCurrent=beginStrictCompile(MODEL,fid,'PERSISTED');
    compileOwned=true;

    for i=1:5
        wm=compiledWidths([CTRLS{i} '/AA15_ISLAND_GFL_SUPPORT_MANAGER']);
        wd=compiledWidths([CTRLS{i} '/AA15_ENG_DIAG_MUX']);
        requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],[NAMES{i} ' persisted manager inputs']);
        requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],[NAMES{i} ' persisted manager outputs']);
        requireWidthAt(wd.Outport,1,41,[NAMES{i} ' persisted diag41']);
    end
    for i=1:5
        w=compiledWidths(OPPATHS{i});
        requireWidthAt(w.Inport,1,EXPECTED_OPWIDTHS(i),[OPNAMES{i} ' persisted width']);
    end

    endStrictCompile(MODEL,loopOrigCurrent);
    compileOwned=false;
    loopOrigCurrent='';

    % Strict compile temporarily changes model config. Reload once
    % more to guarantee final Dirty=off without a second save.
    close_system(MODEL,0);
    load_system(modelFile);

    if ~strcmpi(safeParam(MODEL,'Dirty'),'off')
        error('Final reloaded V4 model Dirty is not off.');
    end

    shaFinal=fileSha256(modelFile);

    logf(fid,'\n%s',repmat('=',1,190));
    logf(fid,'PATCH PASS — K26_V5 V3.4 PORT RECONSTRUCTION V4.5');
    logf(fid,'[DAMP] HP=5Hz LP=20Hz Gdamp=1; role-aware d-axis gating.');
    logf(fid,'[P/Q RELEASE] fc=2Hz full@0.05pu gammaPmin=.70 gammaQmin=.20.');
    logf(fid,'[LIMIT] strict 2-D current circle + ESS2 P-priority + slow-q downstream anti-windup.');
    logf(fid,'[FRAME] Frame subsystem untouched; Stage2~4 manager request is permanently asserted with 1-sample delay.');
    logf(fid,'[VFF] Kslow=.5 Kfast=0 retained.');
    logf(fid,'[CONTROLLERS] original Power Control / Current Regulator / Rff / Lff retained.');
    logf(fid,'[DIAG] 41 rows retained; GammaP/GammaQ/VbpD/VbpQ/SupportClip added.');
    logf(fid,'[OPWRITE] exactly five; widths 82/41/82/38/128.');
    logf(fid,'[ESS1/SM] ESS1 + coordinator + G29/G30 untouched.');
    logf(fid,'[FINAL SHA] %s',shaFinal);
    logf(fid,'[BACKUP] %s',backupFile);
    logf(fid,'[NEXT] Run VERIFY_K26_V5_V34_PORT_RECONSTRUCTION_V4_0.m. Do NOT Rebuild before verifier PASS.');
    logf(fid,'%s',repmat('=',1,190));

catch ME
    logf(fid,'\n%s',repmat('!',1,190));
    logf(fid,'PATCH FAILURE');
    logf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));

    try
        if bdIsLoaded(MODEL)
            if compileOwned
                try,feval(MODEL,[],[],[],'term');catch,end
                try
                    if ~isempty(loopOrigCurrent),set_param(MODEL,'AlgebraicLoopMsg',loopOrigCurrent);end
                catch
                end
            end
            close_system(MODEL,0);
        end
    catch
    end

    if savedToDisk
        try
            [okr,msgr]=copyfile(backupFile,modelFile,'f');
            if okr
                logf(fid,'[FULL ROLLBACK PASS] pre-V4 SLX restored.');
            else
                logf(fid,'[FULL ROLLBACK FAIL] %s',msgr);
            end
        catch MEr
            logf(fid,'[ROLLBACK EXCEPTION] %s',MEr.message);
        end
    else
        logf(fid,'[ROLLBACK] save_system never occurred; persisted V3.4 disk SLX remained unchanged.');
    end

    try
        load_system(modelFile);
        logf(fid,'[ROLLBACK RELOAD] disk model loaded.');
    catch MEr
        logf(fid,'[ROLLBACK RELOAD WARN] %s',MEr.message);
    end
    logf(fid,'%s',repmat('!',1,190));
    rethrow(ME);
end

fprintf('\nV4.5 patch finished. Log: %s\n',LOG_FILE);

%% =========================================================================
%% New V4 manager builder
%% =========================================================================
function addPortReconstructionManagerV4(sub,pos,role,isupMax,Ts,vffFc,kSlow,kFast,kSlew, ...
    kMag,vsFc,vsDb,vsSlew,uvStart,uvFull,iMax,vNom, ...
    dampEnable,dampHp,dampLp,gDamp,releaseEnable,releaseFc,releaseFull,gammaPMin,gammaQMin)

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

% Explicit 100-us states. No persistent state in MATLAB Functions.
stateNames={ ...
    'ANCH_D','ANCH_Q','VSLOW_D','VSLOW_Q','VSUP_BASE','VREF_BASE', ...
    'KSLOW','KFAST','EV_FILTER','ISUP_Q','GP','GQ','VPU','FRAME','PREV_STAGE', ...
    'VLOW5_D','VLOW5_Q','VBP_D','VBP_Q','SUP_D','SUP_Q','SUP_ENV','SLOWQ_ACT','SLOWQ_CLIP' ...
};
stateInit={ ...
    '0','0','0','0','1','10000', ...
    '1','1','0','0','1','1','1','0','0', ...
    '0','0','0','0','0','0','0','0','0' ...
};
for k=1:numel(stateNames)
    add_block('built-in/UnitDelay',[sub '/AA15_STATE_' stateNames{k}], ...
        'InitialCondition',stateInit{k},'SampleTime',num2str(Ts,17));
end

% Existing parameters retained.
addParam(sub,'AA15_P_TS',Ts);
addParam(sub,'AA15_P_VFF_FC_HZ',vffFc);
addParam(sub,'AA15_P_KSLOW_ISLAND',kSlow);
addParam(sub,'AA15_P_KFAST_ISLAND',kFast);
addParam(sub,'AA15_P_KGAIN_SLEW',kSlew);
addParam(sub,'AA15_P_KMAG',kMag);
addParam(sub,'AA15_P_VSUP_FC_HZ',vsFc);
addParam(sub,'AA15_P_VSUP_DB',vsDb);
addParam(sub,'AA15_P_SUPPORT_SLEW',vsSlew);
addParam(sub,'AA15_P_UV_START_V',uvStart);
addParam(sub,'AA15_P_UV_FULL_V',uvFull);
addParam(sub,'AA15_P_IMAX',iMax);
addParam(sub,'AA15_P_ISUP_MAX',isupMax);
addParam(sub,'AA15_P_ROLE',role);
addParam(sub,'AA15_P_VNOM',vNom);

% New runtime-tunable parameters.
addParam(sub,'AA15_P_DAMP_ENABLE',dampEnable);
addParam(sub,'AA15_P_DAMP_HP_HZ',dampHp);
addParam(sub,'AA15_P_DAMP_LP_HZ',dampLp);
addParam(sub,'AA15_P_GDAMP',gDamp);
addParam(sub,'AA15_P_RELEASE_ENABLE',releaseEnable);
addParam(sub,'AA15_P_RELEASE_FC_HZ',releaseFc);
addParam(sub,'AA15_P_I_RELEASE_FULL',releaseFull);
addParam(sub,'AA15_P_GAMMA_P_MIN',gammaPMin);
addParam(sub,'AA15_P_GAMMA_Q_MIN',gammaQMin);

stateCore=[sub '/AA15_FINAL_GFL_STATE_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',stateCore);
setMatlabFunctionScriptRobust(stateCore,gflStateCoreScriptV4());

% State-core 58 scalar inputs.
src={ ...
    'AA15_RAWV_DEMUX/1','AA15_RAWV_DEMUX/2','Pmeas/1','Qmeas/1','PrefCmd/1','QrefCmd/1', ...
    'AA15_MEASI_DEMUX/1','AA15_MEASI_DEMUX/2','SystemStage/1','MasterF/1','VrefCmd/1', ...
    'AA15_STATE_ANCH_D/1','AA15_STATE_ANCH_Q/1','AA15_STATE_VSLOW_D/1','AA15_STATE_VSLOW_Q/1', ...
    'AA15_STATE_VSUP_BASE/1','AA15_STATE_VREF_BASE/1','AA15_STATE_KSLOW/1','AA15_STATE_KFAST/1', ...
    'AA15_STATE_EV_FILTER/1','AA15_STATE_ISUP_Q/1','AA15_STATE_GP/1','AA15_STATE_GQ/1', ...
    'AA15_STATE_VPU/1','AA15_STATE_FRAME/1','AA15_STATE_PREV_STAGE/1', ...
    'AA15_STATE_VLOW5_D/1','AA15_STATE_VLOW5_Q/1','AA15_STATE_VBP_D/1','AA15_STATE_VBP_Q/1', ...
    'AA15_STATE_SUP_D/1','AA15_STATE_SUP_Q/1','AA15_STATE_SUP_ENV/1', ...
    'AA15_STATE_SLOWQ_ACT/1','AA15_STATE_SLOWQ_CLIP/1', ...
    'AA15_P_TS/1','AA15_P_VFF_FC_HZ/1','AA15_P_KSLOW_ISLAND/1','AA15_P_KFAST_ISLAND/1', ...
    'AA15_P_KGAIN_SLEW/1','AA15_P_KMAG/1','AA15_P_VSUP_FC_HZ/1','AA15_P_VSUP_DB/1', ...
    'AA15_P_SUPPORT_SLEW/1','AA15_P_UV_START_V/1','AA15_P_UV_FULL_V/1','AA15_P_ISUP_MAX/1', ...
    'AA15_P_VNOM/1','AA15_P_ROLE/1','AA15_P_DAMP_ENABLE/1','AA15_P_DAMP_HP_HZ/1', ...
    'AA15_P_DAMP_LP_HZ/1','AA15_P_GDAMP/1','AA15_P_RELEASE_ENABLE/1','AA15_P_RELEASE_FC_HZ/1', ...
    'AA15_P_I_RELEASE_FULL/1','AA15_P_GAMMA_P_MIN/1','AA15_P_GAMMA_Q_MIN/1' ...
};
for k=1:numel(src)
    connectReplacingInput(sub,src{k},sprintf('AA15_FINAL_GFL_STATE_CORE/%d',k),'autorouting','on');
end

% State-core next-state outputs 17..34.
stateMap={ ...
    17,'ANCH_D';18,'ANCH_Q';19,'VSLOW_D';20,'VSLOW_Q';21,'VSUP_BASE';22,'VREF_BASE'; ...
    23,'KSLOW';24,'KFAST';25,'EV_FILTER';26,'ISUP_Q';27,'VPU';28,'FRAME';29,'PREV_STAGE'; ...
    30,'VLOW5_D';31,'VLOW5_Q';32,'VBP_D';33,'VBP_Q';34,'SUP_ENV' ...
};
for k=1:size(stateMap,1)
    connectReplacingInput(sub,sprintf('AA15_FINAL_GFL_STATE_CORE/%d',stateMap{k,1}), ...
        ['AA15_STATE_' stateMap{k,2} '/1'],'autorouting','on');
end

% CRITICAL V3.4 causal contract:
% MATLAB Function block-level direct-feedthrough must never sit on the
% FrameHoldReq -> Frame -> Measurements -> Manager feedback path.
% Keep core output11 for code/port stability, but terminate it.
add_block('built-in/Terminator',[sub '/AA15_UNUSED_FRAME_REQ_CORE_TERM']);
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/11','AA15_UNUSED_FRAME_REQ_CORE_TERM/1');

limitCore=[sub '/AA15_FINAL_GFL_LIMIT_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',limitCore);
setMatlabFunctionScriptRobust(limitCore,gflLimitCoreScriptV4());

% Limit inputs: rawId/rawIq, damping d/q request, slow-q request,
% Imax, IsupMax, stage, role, PrefAfterUV, Pmeas, MasterF.
lSrc={ ...
    'AA15_RAWI_DEMUX/1','AA15_RAWI_DEMUX/2', ...
    'AA15_FINAL_GFL_STATE_CORE/12','AA15_FINAL_GFL_STATE_CORE/13','AA15_FINAL_GFL_STATE_CORE/10', ...
    'AA15_P_IMAX/1','AA15_P_ISUP_MAX/1','SystemStage/1','AA15_P_ROLE/1', ...
    'AA15_FINAL_GFL_STATE_CORE/8','Pmeas/1','MasterF/1' ...
};
for k=1:numel(lSrc)
    connectReplacingInput(sub,lSrc{k},sprintf('AA15_FINAL_GFL_LIMIT_CORE/%d',k),'autorouting','on');
end

% Limit outputs:
% 1 fd 2 fq 3 gp 4 gq 5 active 6 supd 7 supq
% 8 supportclip 9 slowqactual 10 slowqclip
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/3','AA15_STATE_GP/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/4','AA15_STATE_GQ/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/6','AA15_STATE_SUP_D/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/7','AA15_STATE_SUP_Q/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/9','AA15_STATE_SLOWQ_ACT/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/10','AA15_STATE_SLOWQ_CLIP/1');

% Vector outputs.
add_block('built-in/Mux',[sub '/AA15_VFF_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/1','AA15_VFF_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/2','AA15_VFF_MUX/2');

add_block('built-in/Mux',[sub '/AA15_IFINAL_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/1','AA15_IFINAL_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/2','AA15_IFINAL_MUX/2');

add_block('built-in/Mux',[sub '/AA15_ISUP_MUX'],'Inputs','2');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/6','AA15_ISUP_MUX/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/7','AA15_ISUP_MUX/2');

% Keep 22 external output ports and width contract.
outNames={ ...
    'VffFinal','IrefFinal','PrefEff','QrefEff','Vpu','VsupportRef','GammaQ','PrefAfterUV','UVRelief', ...
    'Isup','Kslow','Kfast','gP','gQ','CurrentLimitActive','FrameHoldReq','StageEcho','MasterFDiag', ...
    'GammaP','VbpD','VbpQ','SupportClipActive' ...
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
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/7','GammaQ/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/8','PrefAfterUV/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/9','UVRelief/1');
connectReplacingInput(sub,'AA15_ISUP_MUX/1','Isup/1');
connectReplacingInput(sub,'AA15_STATE_KSLOW/1','Kslow/1');
connectReplacingInput(sub,'AA15_STATE_KFAST/1','Kfast/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/3','gP/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/4','gQ/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/5','CurrentLimitActive/1');
% External request is DIRECT UnitDelay output, preserving V3.4 loop break.
connectReplacingInput(sub,'AA15_STATE_FRAME/1','FrameHoldReq/1');
connectReplacingInput(sub,'SystemStage/1','StageEcho/1');
connectReplacingInput(sub,'MasterF/1','MasterFDiag/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/14','GammaP/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/15','VbpD/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_STATE_CORE/16','VbpQ/1');
connectReplacingInput(sub,'AA15_FINAL_GFL_LIMIT_CORE/8','SupportClipActive/1');
end

%% =========================================================================
%% V4 state core
%% =========================================================================
function s=gflStateCoreScriptV4()
L={ ...
'function [vff_d,vff_q,pref_eff,qref_eff,vpu,vsup_ref,gamma_q,pref_uv,uv_relief,slowq_req,frame_req,damp_d_req,damp_q_req,gamma_p,vbp_d_out,vbp_q_out,anchdn,anchqn,vslowdn,vslowqn,vsupbasen,vrefbasen,kslown,kfastn,evn,isupqn,vpun,framen,prevn,vlow5dn,vlow5qn,vbpdn,vbpqn,supenvn] = fcn(vd,vq,pmeas,qmeas,pref,qref,idm,iqm,stage,master_f,vref_cmd,anchd,anchq,vslowd,vslowq,vsupbase,vrefbase,kslow,kfast,evz,isupqz,gpz,gqz,vpuz,framez,prevstage,vlow5d,vlow5q,vbpd,vbpq,supdz,supqz,supenvz,slowqactualz,slowqclipz,Ts,vff_fc,kslow_target,kfast_target,kgain_slew,k_mag,vs_fc,vs_db,vs_slew,uv_start,uv_full,isup_max,vnom,role,damp_enable,damp_hp,damp_lp,gdamp,release_enable,release_fc,release_full,gamma_p_min,gamma_q_min)'; ...
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
'alphaV=clamp1(1.0-exp(-2.0*piC*max(vff_fc,0.0)*TsS),0.0,1.0);'; ...
'alphaS=clamp1(1.0-exp(-2.0*piC*max(vs_fc,0.0)*TsS),0.0,1.0);'; ...
'alpha5=clamp1(1.0-exp(-2.0*piC*max(damp_hp,0.0)*TsS),0.0,1.0);'; ...
'alpha20=clamp1(1.0-exp(-2.0*piC*max(damp_lp,0.0)*TsS),0.0,1.0);'; ...
'alphaR=clamp1(1.0-exp(-2.0*piC*max(release_fc,0.0)*TsS),0.0,1.0);'; ...
''; ...
'% Work-point capture and existing VFF slow state.'; ...
'anchdn=anchd;anchqn=anchq;vslowdn=vslowd;vslowqn=vslowq;'; ...
'vsupbasen=vsupbase;vrefbasen=vrefbase;'; ...
'if s==0.0'; ...
'    anchdn=vd;anchqn=vq;vslowdn=vd;vslowqn=vq;'; ...
'    vsupbasen=vpu;vrefbasen=vref_cmd;'; ...
'elseif s==1.0'; ...
'    if prevstage<0.5'; ...
'        anchdn=vd;anchqn=vq;'; ...
'    end'; ...
'    vslowdn=vslowd+alphaV*(vd-vslowd);'; ...
'    vslowqn=vslowq+alphaV*(vq-vslowq);'; ...
'    vsupbasen=vpu;vrefbasen=vref_cmd;'; ...
'else'; ...
'    vslowdn=vslowd+alphaV*(vd-vslowd);'; ...
'    vslowqn=vslowq+alphaV*(vq-vslowq);'; ...
'end'; ...
''; ...
'% Existing two-band VFF retained.'; ...
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
'% Local slow voltage reference.'; ...
'vsup_ref=vsupbase;'; ...
'if s>=2.0 && s<=4.0'; ...
'    vsup_ref=vsupbase+(vref_cmd-vrefbase)/max(abs(vnom),1.0);'; ...
'end'; ...
''; ...
'% EV undervoltage relief: charging only, no V2G.'; ...
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
'% Causal 5~20Hz band-pass states. Stage0/1/5 explicitly clean the BP state.'; ...
'vbp_d_out=vbpd;vbp_q_out=vbpq;'; ...
'vlow5dn=vlow5d;vlow5qn=vlow5q;vbpdn=vbpd;vbpqn=vbpq;'; ...
'damp_d_req=0.0;damp_q_req=0.0;'; ...
'if s>=2.0 && s<=4.0'; ...
'    hp_d=vd-vlow5d;hp_q=vq-vlow5q;'; ...
'    vlow5dn=vlow5d+alpha5*(vd-vlow5d);'; ...
'    vlow5qn=vlow5q+alpha5*(vq-vlow5q);'; ...
'    vbpdn=vbpd+alpha20*(hp_d-vbpd);'; ...
'    vbpqn=vbpq+alpha20*(hp_q-vbpq);'; ...
'    if damp_enable>0.5'; ...
'        dd=-gdamp*vbpd;'; ...
'        dq=-gdamp*vbpq;'; ...
'        rr=round(role);'; ...
'        if rr==1'; ...
'            dd=min(dd,0.0); % PV: damping may curtail, never demand unknown upward PV headroom'; ...
'        elseif rr==3'; ...
'            dd=max(dd,0.0); % EV: damping may reduce charging, never deepen charging or create V2G'; ...
'        end'; ...
'        damp_d_req=dd;damp_q_req=dq;'; ...
'    end'; ...
'else'; ...
'    vlow5dn=vd;vlow5qn=vq;vbpdn=0.0;vbpqn=0.0;'; ...
'    vbp_d_out=0.0;vbp_q_out=0.0;'; ...
'end'; ...
''; ...
'% Slow-q voltage support with downstream anti-windup.'; ...
'evBase=evz;qBase=isupqz;'; ...
'if slowqclipz>0.5 && abs(k_mag)>1e-12'; ...
'    qBase=slowqactualz;'; ...
'    evBase=-slowqactualz/k_mag;'; ...
'end'; ...
'evn=evBase;isupqn=qBase;slowq_req=0.0;'; ...
'if s>=2.0 && s<=4.0'; ...
'    e=vsup_ref-vpu;'; ...
'    db=abs(vs_db);'; ...
'    if abs(e)<=db'; ...
'        edb=0.0;'; ...
'    else'; ...
'        edb=e-sign(e)*db;'; ...
'    end'; ...
'    evTrial=evBase+alphaS*(edb-evBase);'; ...
'    isMax=max(abs(isup_max),0.0);'; ...
'    target=clamp1(-k_mag*evTrial,-isMax,isMax);'; ...
'    if abs(k_mag)>1e-12 && abs(-k_mag*evTrial)>isMax+1e-12'; ...
'        evn=-target/k_mag;'; ...
'    else'; ...
'        evn=evTrial;'; ...
'    end'; ...
'    isupqn=slew1(qBase,target,abs(vs_slew));'; ...
'    slowq_req=qBase;'; ...
'else'; ...
'    evn=0.0;isupqn=0.0;slowq_req=0.0;'; ...
'end'; ...
''; ...
'% Support activity envelope uses previous-step ACTUAL total support.'; ...
'supenvn=supenvz;'; ...
'gamma_p=1.0;gamma_q=1.0;'; ...
'if s>=2.0 && s<=4.0'; ...
'    den=max(abs(release_full),1e-9);'; ...
'    actRaw=min(hypot(supdz,supqz)/den,1.0);'; ...
'    supenvn=clamp1(supenvz+alphaR*(actRaw-supenvz),0.0,1.0);'; ...
'    if release_enable>0.5'; ...
'        gpmin=clamp1(gamma_p_min,0.0,1.0);'; ...
'        gqmin=clamp1(gamma_q_min,0.0,1.0);'; ...
'        gamma_p=1.0-(1.0-gpmin)*clamp1(supenvz,0.0,1.0);'; ...
'        gamma_q=1.0-(1.0-gqmin)*clamp1(supenvz,0.0,1.0);'; ...
'    end'; ...
'else'; ...
'    supenvn=0.0;'; ...
'end'; ...
''; ...
'% Combine support-aware release with previous-step physical current limiter.'; ...
'if s==0.0 || s==1.0 || s==5.0'; ...
'    pref_eff=pref_uv;qref_eff=qref;'; ...
'else'; ...
'    gpEff=min(clamp1(gpz,0.0,1.0),gamma_p);'; ...
'    gqEff=min(clamp1(gqz,0.0,1.0),gamma_q);'; ...
'    pref_eff=pmeas+gpEff*(pref_uv-pmeas);'; ...
'    qref_eff=qmeas+gqEff*(qref-qmeas);'; ...
'end'; ...
''; ...
'% Permanent island frame authority is stage-based, not a voltage-threshold hack.'; ...
'if s>=2.0 && s<=4.0'; ...
'    framen=1.0;'; ...
'else'; ...
'    framen=0.0;'; ...
'end'; ...
'frame_req=framez;'; ...
'prevn=s;'; ...
''; ...
'% idm/iqm remain contract inputs; V4 first build does not add another health loop.'; ...
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

%% =========================================================================
%% V4 strict limiter core
%% =========================================================================
function s=gflLimitCoreScriptV4()
L={ ...
'function [fd,fq,gp,gq,active,supd,supq,supportclip,slowqactual,slowqclip] = fcn(rawd,rawq,dampd_req,dampq_req,slowq_req,imax,isupmax,stage,role,pref_cmd,pmeas,master_f)'; ...
'%#codegen'; ...
's=min(max(round(stage),0.0),5.0);'; ...
'I=max(abs(imax),1e-9);'; ...
'S=min(max(abs(isupmax),0.0),I);'; ...
'if s==0.0 || s==1.0 || s==5.0'; ...
'    fd=rawd;fq=rawq;gp=1.0;gq=1.0;active=0.0;'; ...
'    supd=0.0;supq=0.0;supportclip=0.0;slowqactual=0.0;slowqclip=0.0;return;'; ...
'end'; ...
''; ...
'% Damping has first support priority. Radial clipping preserves direction/passivity.'; ...
'dd=dampd_req;dq=dampq_req;'; ...
'dmag=hypot(dd,dq);'; ...
'dampClip=0.0;'; ...
'if dmag>S && dmag>1e-12'; ...
'    sc=S/dmag;dd=dd*sc;dq=dq*sc;dampClip=1.0;'; ...
'end'; ...
''; ...
'pPriority=(round(role)==2) && (master_f<49.98) && (pref_cmd>pmeas+0.002);'; ...
'if pPriority && hypot(rawd+dd,rawq+dq)<=I+1e-12'; ...
'    % ESS2: damping > base P/Q/P-f > slow-q support.'; ...
'    lam=1.0;'; ...
'    rS=sqrt(max(S*S-dd*dd,0.0));'; ...
'    loS=-rS-dq;hiS=rS-dq;'; ...
'    rI=sqrt(max(I*I-(rawd+dd)*(rawd+dd),0.0));'; ...
'    loI=-rI-(rawq+dq);hiI=rI-(rawq+dq);'; ...
'    lo=max(loS,loI);hi=min(hiS,hiI);'; ...
'    if lo>hi'; ...
'        % x=0 must be feasible under the branch condition; numerical guard only.'; ...
'        x=0.0;slowClip=1.0;'; ...
'    else'; ...
'        x=clamp1(slowq_req,lo,hi);'; ...
'        slowClip=double(abs(x-slowq_req)>1e-9);'; ...
'    end'; ...
'    sd=dd;sq=dq+x;'; ...
'    fd=rawd+sd;fq=rawq+sq;'; ...
'else'; ...
'    % PV/EV/default, or ESS2 when base+damping already exceeds Imax:'; ...
'    % damping > slow-q support > base P/Q.'; ...
'    if pPriority'; ...
'        x=0.0;slowClip=double(abs(slowq_req)>1e-9);'; ...
'    else'; ...
'        rS=sqrt(max(S*S-dd*dd,0.0));'; ...
'        loS=-rS-dq;hiS=rS-dq;'; ...
'        x=clamp1(slowq_req,loS,hiS);'; ...
'        slowClip=double(abs(x-slowq_req)>1e-9);'; ...
'    end'; ...
'    sd=dd;sq=dq+x;'; ...
'    lam=maxBaseLambda(rawd,rawq,sd,sq,I);'; ...
'    fd=sd+lam*rawd;fq=sq+lam*rawq;'; ...
'end'; ...
''; ...
'% Final active-direction safety in the established dq convention:'; ...
'% PV must not cross into active absorption; EV must not cross into V2G.'; ...
'dirClip=0.0;'; ...
'rr=round(role);'; ...
'if rr==1 && fd<0.0'; ...
'    fd=0.0;dirClip=1.0;'; ...
'elseif rr==3 && fd>0.0'; ...
'    fd=0.0;dirClip=1.0;'; ...
'end'; ...
'% Direction clipping moves fd toward zero, so the current circle remains safe.'; ...
'% Recompute ACTUAL support relative to the lambda-scaled base current.'; ...
'sd=fd-lam*rawd;'; ...
'sq=fq-lam*rawq;'; ...
'gp=lam;gq=lam;'; ...
'supd=sd;supq=sq;slowqactual=x;slowqclip=slowClip;'; ...
'supportclip=double(dampClip>0.5 || slowClip>0.5 || dirClip>0.5);'; ...
'active=double(lam<0.999999 || supportclip>0.5);'; ...
'end'; ...
''; ...
'function lam=maxBaseLambda(bd,bq,sd,sq,I)'; ...
'a=bd*bd+bq*bq;'; ...
'if a<=1e-18'; ...
'    lam=1.0;return;'; ...
'end'; ...
'm=sd*bd+sq*bq;'; ...
'c=sd*sd+sq*sq-I*I;'; ...
'disc=max(m*m-a*c,0.0);'; ...
'lam=(-m+sqrt(disc))/a;'; ...
'lam=min(max(lam,0.0),1.0);'; ...
'end'; ...
''; ...
'function y=clamp1(x,lo,hi)'; ...
'y=min(max(x,lo),hi);'; ...
'end' ...
};
s=strjoin(L,newline);
end

%% =========================================================================
%% Immediate postassert
%% =========================================================================
function immediatePostassertV4(ctrl,dev,role,isup)
mgr=[ctrl '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
diag=[ctrl '/AA15_ENG_DIAG_MUX'];

requireBlock(mgr);requireBlock(diag);requireBlock([ctrl '/AA15_ENG_DIAG_OUT41']);

assertSource(mgr,1,[ctrl '/From26'],1,[dev ' raw Vdq']);
assertSource(mgr,2,[ctrl '/Power Control Loop'],1,[dev ' raw Ipq']);
assertSource(mgr,3,[ctrl '/From21'],1,[dev ' Pmeas']);
assertSource(mgr,4,[ctrl '/From51'],1,[dev ' Qmeas']);
assertSource(mgr,5,[ctrl '/Pref'],1,[dev ' Pref']);
assertSource(mgr,6,[ctrl '/Qref'],1,[dev ' Qref']);
assertSource(mgr,7,[ctrl '/From28'],1,[dev ' measured IdIq']);
assertSource(mgr,8,[ctrl '/Droop_On'],1,[dev ' stage']);
assertSource(mgr,9,[ctrl '/Fref'],1,[dev ' MasterF']);
assertSource(mgr,10,[ctrl '/Vref'],1,[dev ' Vref']);

assertSource([ctrl '/Current Regulator'],1,mgr,1,[dev ' VFF']);
assertSource([ctrl '/Goto18'],1,mgr,2,[dev ' final Iref']);
assertSource([ctrl '/Power Control Loop'],3,mgr,3,[dev ' PrefEff']);
assertSource([ctrl '/Power Control Loop'],6,mgr,4,[dev ' QrefEff']);
assertSource([ctrl '/Measurements'],5,mgr,16,[dev ' FrameHoldReq']);
% HARD CAUSAL GATE: manager external FrameHoldReq must bypass MATLAB Function.
assertSource([mgr '/FrameHoldReq'],1,[mgr '/AA15_STATE_FRAME'],1,[dev ' delayed FrameHoldReq source']);
requireBlock([mgr '/AA15_UNUSED_FRAME_REQ_CORE_TERM']);
assertSource([mgr '/AA15_UNUSED_FRAME_REQ_CORE_TERM'],1,[mgr '/AA15_FINAL_GFL_STATE_CORE'],11, ...
    [dev ' terminated core frame output']);
assertSource([ctrl '/AA15_ENG_DIAG_OUT41'],1,diag,1,[dev ' diag41']);

if str2double(safeParam(diag,'Inputs'))~=33
    error('[%s] diag mux input count must remain33.',dev);
end

assertScalarValue([mgr '/AA15_P_KSLOW_ISLAND'],0.50,[dev ' Kslow']);
assertScalarValue([mgr '/AA15_P_KFAST_ISLAND'],0.0,[dev ' Kfast']);
assertScalarValue([mgr '/AA15_P_DAMP_ENABLE'],1.0,[dev ' damp enable']);
assertScalarValue([mgr '/AA15_P_DAMP_HP_HZ'],5.0,[dev ' damp HP']);
assertScalarValue([mgr '/AA15_P_DAMP_LP_HZ'],20.0,[dev ' damp LP']);
assertScalarValue([mgr '/AA15_P_GDAMP'],1.0,[dev ' Gdamp']);
assertScalarValue([mgr '/AA15_P_RELEASE_ENABLE'],1.0,[dev ' release enable']);
assertScalarValue([mgr '/AA15_P_RELEASE_FC_HZ'],2.0,[dev ' release fc']);
assertScalarValue([mgr '/AA15_P_I_RELEASE_FULL'],0.05,[dev ' release full']);
assertScalarValue([mgr '/AA15_P_GAMMA_P_MIN'],0.70,[dev ' gammaP min']);
assertScalarValue([mgr '/AA15_P_GAMMA_Q_MIN'],0.20,[dev ' gammaQ min']);
assertScalarValue([mgr '/AA15_P_IMAX'],1.20,[dev ' Imax']);
assertScalarValue([mgr '/AA15_P_ISUP_MAX'],isup,[dev ' Isup']);
assertScalarValue([mgr '/AA15_P_ROLE'],role,[dev ' Role']);

mustStates={'VLOW5_D','VLOW5_Q','VBP_D','VBP_Q','SUP_D','SUP_Q','SUP_ENV','SLOWQ_ACT','SLOWQ_CLIP','GP','GQ','FRAME'};
for k=1:numel(mustStates)
    b=[mgr '/AA15_STATE_' mustStates{k}];
    requireBlock(b);
    if ~strcmpi(safeParam(b,'BlockType'),'UnitDelay')
        error('[%s] %s must be UnitDelay.',dev,b);
    end
    assertScalarParamValue(b,'SampleTime',0.0001,[dev ' state Ts']);
end

assertScriptEquals([mgr '/AA15_FINAL_GFL_STATE_CORE'],gflStateCoreScriptV4(),[dev ' state core']);
assertScriptEquals([mgr '/AA15_FINAL_GFL_LIMIT_CORE'],gflLimitCoreScriptV4(),[dev ' limit core']);
end

%% =========================================================================
%% Scratch compile
%% =========================================================================
function scratchPreflightPortV4(Ts,vffFc,kSlow,kFast,kSlew,kMag,vsFc,vsDb,vsSlew, ...
    uvStart,uvFull,iMax,isupMax,role,vNom,dampEnable,dampHp,dampLp,gDamp, ...
    releaseEnable,releaseFc,releaseFull,gammaPMin,gammaQMin)

tmp=matlab.lang.makeValidName(['AA15_PORTV4_PREFLIGHT_' datestr(now,'HHMMSSFFF')]);
new_system(tmp);
cleaner=onCleanup(@() closeScratch(tmp)); %#ok<NASGU>
load_system(tmp);

% Vector inputs.
add_block('built-in/Constant',[tmp '/VD'],'Value','1');
add_block('built-in/Constant',[tmp '/VQ'],'Value','0');
add_block('built-in/Mux',[tmp '/VMUX'],'Inputs','2');
connectReplacingInput(tmp,'VD/1','VMUX/1');
connectReplacingInput(tmp,'VQ/1','VMUX/2');

add_block('built-in/Constant',[tmp '/ID'],'Value','0.2');
add_block('built-in/Constant',[tmp '/IQ'],'Value','0');
add_block('built-in/Mux',[tmp '/IMUX'],'Inputs','2');
connectReplacingInput(tmp,'ID/1','IMUX/1');
connectReplacingInput(tmp,'IQ/1','IMUX/2');

for k=1:8
    add_block('built-in/Constant',[tmp sprintf('/C%d',k)],'Value','0');
end
set_param([tmp '/C5'],'Value','50');
set_param([tmp '/C6'],'Value','10000');

mgr=[tmp '/MGR'];
addPortReconstructionManagerV4(mgr,[300 100 1050 850], ...
    role,isupMax,Ts,vffFc,kSlow,kFast,kSlew,kMag,vsFc,vsDb,vsSlew,uvStart,uvFull, ...
    iMax,vNom,dampEnable,dampHp,dampLp,gDamp,releaseEnable,releaseFc,releaseFull,gammaPMin,gammaQMin);

mSrc={'VMUX/1','IMUX/1','C1/1','C2/1','C3/1','C4/1','IMUX/1','C1/1','C5/1','C6/1'};
for k=1:10,connectReplacingInput(tmp,mSrc{k},sprintf('MGR/%d',k));end
for k=1:22
    add_block('built-in/Terminator',[tmp sprintf('/T%02d',k)]);
    connectReplacingInput(tmp,sprintf('MGR/%d',k),sprintf('T%02d/1',k));
end

set_param(tmp,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep',num2str(Ts,17));
origLoop=safeParam(tmp,'AlgebraicLoopMsg');
set_param(tmp,'AlgebraicLoopMsg','error');
feval(tmp,[],[],[],'compile');

wm=compiledWidths(mgr);
requireWidthVec(wm.Inport,[2 2 1 1 1 1 2 1 1 1],'scratch manager inputs');
requireWidthVec(wm.Outport,[2 2 ones(1,7) 2 ones(1,12)],'scratch manager outputs');

% Structural causality check even in scratch model.
assertSource([mgr '/FrameHoldReq'],1,[mgr '/AA15_STATE_FRAME'],1,'scratch delayed FrameHoldReq');
assertSource([mgr '/AA15_UNUSED_FRAME_REQ_CORE_TERM'],1,[mgr '/AA15_FINAL_GFL_STATE_CORE'],11, ...
    'scratch terminated core frame output');

feval(tmp,[],[],[],'term');
set_param(tmp,'AlgebraicLoopMsg',origLoop);
end

function closeScratch(tmp)
try
    if bdIsLoaded(tmp)
        try,feval(tmp,[],[],[],'term');catch,end
        close_system(tmp,0);
    end
catch
end
end

%% =========================================================================
%% Numerical reference self-test
%% =========================================================================
function runPortMathSelfTest(fid,Ts,hpHz,lpHz,gDamp,iMax,isup,roles)
piC=4.0*atan(1.0);
a5=1.0-exp(-2.0*piC*hpHz*Ts);
a20=1.0-exp(-2.0*piC*lpHz*Ts);

% Exact discrete transfer from V -> Vbp for the implemented delayed-state filters.
f0=10.0;
z=exp(1i*2*piC*f0*Ts);
Hlow=a5/(z-(1.0-a5));
Hhp=1-Hlow;
Hbp=a20/(z-(1.0-a20))*Hhp;
if real(Hbp)<0.75 || abs(angle(Hbp))*180/piC>3.0
    error('PORT MATH SELFTEST: 10Hz band-pass is not sufficiently real/positive.');
end

rng(240904,'twister');
maxViol=0.0;
for n=1:20000
    role=roles(randi(numel(roles)));
    S=isup(randi(numel(isup)));
    bd=1.4*rand;
    if role==3,bd=-bd;end
    bq=2.8*(rand-0.5);
    vbd=0.5*(rand-0.5);
    vbq=0.5*(rand-0.5);
    slow=0.7*(rand-0.5);

    dd=-gDamp*vbd;
    dq=-gDamp*vbq;
    if role==1,dd=min(dd,0.0);elseif role==3,dd=max(dd,0.0);end

    if vbd*dd+vbq*dq>1e-12
        error('PORT MATH SELFTEST: role-gated damping violates passive sign.');
    end

    pref=2.0*(rand-0.5);
    pmeas=2.0*(rand-0.5);
    mf=49.7+0.6*rand;
    [fd,fq,sd,sq,lam]=limitReferenceV4(bd,bq,dd,dq,slow,iMax,S,role,pref,pmeas,mf);

    viol=hypot(fd,fq)-iMax;
    maxViol=max(maxViol,viol);
    if hypot(sd,sq)>min(S,iMax)+1e-10
        error('PORT MATH SELFTEST: support-vector limit violated.');
    end
    if lam<-1e-12 || lam>1+1e-12
        error('PORT MATH SELFTEST: lambda outside [0,1].');
    end
    if role==1 && fd<-1e-12
        error('PORT MATH SELFTEST: PV crossed into active absorption.');
    end
    if role==3 && fd>1e-12
        error('PORT MATH SELFTEST: EV crossed into V2G.');
    end
end
if maxViol>1e-10
    error('PORT MATH SELFTEST: current-circle violation %.12g',maxViol);
end

logf(fid,'[PATCH SELFTEST PASS] R2023b functions + 10Hz dissipative response + 20k current-circle/passivity/resource-direction Monte-Carlo.');
end

function [fd,fq,sd,sq,lam]=limitReferenceV4(bd,bq,dd,dq,slow,I,S,role,pref,pmeas,mf)
I=max(abs(I),1e-9);S=min(max(abs(S),0),I);
dm=hypot(dd,dq);
if dm>S && dm>1e-12,sc=S/dm;dd=dd*sc;dq=dq*sc;end
pPriority=(role==2)&&(mf<49.98)&&(pref>pmeas+0.002);
if pPriority && hypot(bd+dd,bq+dq)<=I+1e-12
    lam=1;
    rS=sqrt(max(S*S-dd*dd,0));loS=-rS-dq;hiS=rS-dq;
    rI=sqrt(max(I*I-(bd+dd)^2,0));loI=-rI-(bq+dq);hiI=rI-(bq+dq);
    lo=max(loS,loI);hi=min(hiS,hiI);
    if lo>hi,x=0;else,x=min(max(slow,lo),hi);end
    sd=dd;sq=dq+x;fd=bd+sd;fq=bq+sq;
else
    if pPriority
        x=0;
    else
        rS=sqrt(max(S*S-dd*dd,0));x=min(max(slow,-rS-dq),rS-dq);
    end
    sd=dd;sq=dq+x;
    lam=maxBaseLambdaRef(bd,bq,sd,sq,I);
    fd=sd+lam*bd;fq=sq+lam*bq;
end
if role==1 && fd<0
    fd=0;
elseif role==3 && fd>0
    fd=0;
end
sd=fd-lam*bd;
sq=fq-lam*bq;
end

function lam=maxBaseLambdaRef(bd,bq,sd,sq,I)
a=bd*bd+bq*bq;
if a<=1e-18,lam=1;return;end
m=sd*bd+sq*bq;
c=sd*sd+sq*sq-I*I;
lam=(-m+sqrt(max(m*m-a*c,0)))/a;
lam=min(max(lam,0),1);
end

%% =========================================================================
%% Compatibility and frozen-controller fingerprint
%% =========================================================================
function runPatchCompatibilitySelfTest(fid)
req={'contains','startsWith','endsWith','slResolve','sfroot','matlab.lang.makeValidName'};
for k=1:numel(req)
    nm=req{k};
    if contains(nm,'.')
        % dotted MATLAB package function
        try
            if isempty(which(nm)),error('missing');end
        catch
            error('PATCH compatibility preflight: required function "%s" unavailable.',nm);
        end
    else
        if exist(nm,'file')==0 && exist(nm,'builtin')==0
            error('PATCH compatibility preflight: required function "%s" unavailable.',nm);
        end
    end
end
logf(fid,'[COMPATIBILITY SELFTEST PASS] required R2023b functions available; no fflush dependency.');
end

function assertOriginalGFLControllerFingerprint(ctrl,dev)
% Exact fingerprint from the completed V1.3 read-only audit.
%
% IMPORTANT:
% - Power Control has TWO scalar PI subsystems (P and Q) -> two Kp/two Ki.
% - Current Regulator has ONE width-2 vector PI subsystem -> one Kp/one Ki.
% Do NOT replace this exact-path audit with expression-count assumptions.

% Exact outer-loop error signs.
assertTextParamExact([ctrl '/Power Control Loop/Add'],'Inputs','+-',[dev ' Power Add']);
assertTextParamExact([ctrl '/Power Control Loop/Add1'],'Inputs','-+',[dev ' Power Add1']);
assertTextParamExact([ctrl '/Power Control Loop/Add2'],'Inputs','+-',[dev ' Power Add2']);

% Exact current-regulator feedforward sum signs.
assertTextParamExact([ctrl '/Current Regulator/Add1'],'Inputs','++-',[dev ' Current Add1']);
assertTextParamExact([ctrl '/Current Regulator/Add2'],'Inputs','++',[dev ' Current Add2']);
assertTextParamExact([ctrl '/Current Regulator/Add3'],'Inputs','+++',[dev ' Current Add3']);

% Exact audited PI block names. These block names contain a real newline.
pcPI1=[ctrl '/Power Control Loop/' sprintf('PI regulator\nwith anti-windup D')];
pcPI2=[ctrl '/Power Control Loop/' sprintf('PI regulator\nwith anti-windup D1')];
curPI=[ctrl '/Current Regulator/' sprintf('PI regulator\nwith anti-windup D')];

% Power P/Q PI: two independent scalar PI channels.
assertGainBlockExact([pcPI1 '/Kp4'],'Kp',0.06,[dev ' Power P Kp']);
assertGainBlockExact([pcPI1 '/Kp5'],'Ki',2.0,[dev ' Power P Ki']);
assertGainBlockExact([pcPI2 '/Kp4'],'Kp',0.06,[dev ' Power Q Kp']);
assertGainBlockExact([pcPI2 '/Kp5'],'Ki',2.0,[dev ' Power Q Ki']);

% Current regulator: ONE width-2 vector PI block, hence one Kp and one Ki Gain.
assertGainBlockExact([curPI '/Kp4'],'Kp',0.30,[dev ' Current vector Kp']);
assertGainBlockExact([curPI '/Kp5'],'Ki',20.0,[dev ' Current vector Ki']);

% Exact audited decoupling/feedforward gains.
assertGainBlockExact([ctrl '/Current Regulator/Rtot_pu1'],'Rff',0.004,[dev ' Rff d']);
assertGainBlockExact([ctrl '/Current Regulator/Rtot_pu5'],'Rff',0.004,[dev ' Rff q']);
assertGainBlockExact([ctrl '/Current Regulator/Ltot_pu1'],'Lff',0.21,[dev ' Lff d/q1']);
assertGainBlockExact([ctrl '/Current Regulator/Ltot_pu2'],'Lff',0.21,[dev ' Lff d/q2']);
end

function assertTextParamExact(block,param,expected,label)
requireBlock(block);
actual=strtrim(safeParam(block,param));
if ~strcmp(actual,expected)
    error('%s mismatch at %s. expected "%s" actual "%s".',label,block,expected,actual);
end
end

function assertGainBlockExact(block,expectedExpr,expectedValue,label)
requireBlock(block);
if ~strcmpi(strtrim(safeParam(block,'BlockType')),'Gain')
    error('%s expected Gain block at %s; actual BlockType=%s.',label,block,safeParam(block,'BlockType'));
end
actualExpr=strtrim(safeParam(block,'Gain'));
if ~strcmp(actualExpr,expectedExpr)
    error('%s gain expression mismatch at %s. expected=%s actual=%s.', ...
        label,block,expectedExpr,actualExpr);
end
val=resolveNumericExpression(actualExpr,block);
if abs(val-expectedValue)>1e-12
    error('%s resolved value mismatch at %s. expected=%.17g actual=%.17g.', ...
        label,block,expectedValue,val);
end
end

function v=resolveNumericExpression(expr,b)
try
    v=slResolve(expr,b);
catch ME
    error('Cannot resolve "%s" at %s: %s',expr,b,ME.message);
end
if ~isnumeric(v)||~isscalar(v)||~isfinite(v)
    error('Resolved value of "%s" at %s is not finite scalar.',expr,b);
end
v=double(v);
end

%% =========================================================================
%% Strict compile
%% =========================================================================
function orig=beginStrictCompile(model,fid,label)
orig=safeParam(model,'AlgebraicLoopMsg');
try
    set_param(model,'AlgebraicLoopMsg','error');
    feval(model,[],[],[],'compile');
    logf(fid,'[%s STRICT COMPILE PASS] AlgebraicLoopMsg=error; compiled context held for width audit.',label);
catch ME
    try,set_param(model,'AlgebraicLoopMsg',orig);catch,end
    rethrow(ME);
end
end

function endStrictCompile(model,orig)
try
    feval(model,[],[],[],'term');
catch ME
    try,set_param(model,'AlgebraicLoopMsg',orig);catch,end
    rethrow(ME);
end
set_param(model,'AlgebraicLoopMsg',orig);
end

%% =========================================================================
%% Common Simulink helpers
%% =========================================================================
function addParam(sub,name,value)
add_block('built-in/Constant',[sub '/' name], ...
    'Value',num2str(value,17),'SampleTime','0.0001');
end

function lh=connectReplacingInput(parent,srcRel,dstRel,varargin)
[srcName,sp]=parseRelativePortToken(srcRel);
[dstName,dp]=parseRelativePortToken(dstRel);
src=[parent '/' srcName];dst=[parent '/' dstName];
requireBlock(src);requireBlock(dst);
phs=get_param(src,'PortHandles');phd=get_param(dst,'PortHandles');
if sp<1||sp>numel(phs.Outport),error('Invalid source port: %s',srcRel);end
if dp<1||dp>numel(phd.Inport),error('Invalid destination port: %s',dstRel);end
srcPH=phs.Outport(sp);dstPH=phd.Inport(dp);
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

function setMatlabFunctionScriptRobust(blockPath,scriptText)
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart');
hits=[];
for k=1:numel(charts)
    p='';n='';
    try,p=char(charts(k).Path);catch,end
    try,n=char(charts(k).Name);catch,end
    cand={p};
    if ~isempty(p)&&~isempty(n)
        if endsWith(p,['/' n])||strcmp(p,n),cand{end+1}=p;else,cand{end+1}=[p '/' n];end %#ok<AGROW>
    end
    for j=1:numel(cand)
        if strcmp(cand{j},blockPath)
            hits(end+1)=k; %#ok<AGROW>
            break;
        end
    end
end
if numel(hits)~=1
    error('Cannot uniquely resolve MATLAB Function chart: %s (hits=%d)',blockPath,numel(hits));
end
charts(hits(1)).Script=scriptText;
end

function txt=getMatlabFunctionScriptRobust(blockPath)
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart');
txt='';
hits=0;
for k=1:numel(charts)
    p='';n='';
    try,p=char(charts(k).Path);catch,end
    try,n=char(charts(k).Name);catch,end
    cand={p};
    if ~isempty(p)&&~isempty(n)
        if endsWith(p,['/' n])||strcmp(p,n),cand{end+1}=p;else,cand{end+1}=[p '/' n];end %#ok<AGROW>
    end
    for j=1:numel(cand)
        if strcmp(cand{j},blockPath)
            hits=hits+1;txt=char(charts(k).Script);break;
        end
    end
end
if hits~=1,error('Cannot uniquely read MATLAB Function chart: %s (hits=%d)',blockPath,hits);end
end

function assertScriptEquals(blockPath,expected,label)
actual=normalizeText(getMatlabFunctionScriptRobust(blockPath));
want=normalizeText(expected);
if ~strcmp(actual,want)
    error('%s MATLAB Function script mismatch.',label);
end
end

function h=emChartContentSha256(blockPath)
% Hash ONLY normalized MATLAB Function Script content.
% Never include block path, because identical scripts live under five
% different device paths.
txt=getMatlabFunctionScriptRobust(blockPath);
h=textSha256(normalizeText(txt));
end

function assertEmChartContentHash(blockPath,expected,label)
actual=emChartContentSha256(blockPath);
if ~strcmpi(actual,expected)
    error('%s content SHA mismatch at %s. expected=%s actual=%s', ...
        label,blockPath,expected,actual);
end
end

function s=normalizeText(s)
if isstring(s),s=char(s);end
s=strrep(s,sprintf('\r\n'),sprintf('\n'));
s=strrep(s,sprintf('\r'),sprintf('\n'));
s=strtrim(s);
end

function h=textSha256(s)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(unicode2native(s,'UTF-8')));
d=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(d,2).',1,[]));
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

function assertScalarValue(b,expected,label)
requireBlock(b);
x=str2double(strtrim(safeParam(b,'Value')));
if ~isfinite(x)||abs(x-expected)>1e-12
    error('%s expected %.17g actual %s',label,expected,safeParam(b,'Value'));
end
end

function assertScalarParamValue(b,p,expected,label)
x=str2double(strtrim(safeParam(b,p)));
if ~isfinite(x)||abs(x-expected)>1e-12
    error('%s expected %.17g actual %s',label,expected,safeParam(b,p));
end
end

function d=inportSourceDesc(b,n)
d='<none>';
ph=get_param(b,'PortHandles');
lh=get_param(ph.Inport(n),'Line');
if lh<0,return;end
sb=get_param(lh,'SrcBlockHandle');sp=get_param(lh,'SrcPortHandle');
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

function s=destinationsOfOutputPort(ph)
s='<none>';
try
    lh=get_param(ph,'Line');
    if isempty(lh)||lh<0,return;end
    db=get_param(lh,'DstBlockHandle');dp=get_param(lh,'DstPortHandle');
    db=db(:);dp=dp(:);parts={};
    for idx=1:min(numel(db),numel(dp))
        if db(idx)>=0&&dp(idx)>=0
            parts{end+1}=[getfullname(db(idx)) '|in' num2str(get_param(dp(idx),'PortNumber'))]; %#ok<AGROW>
        end
    end
    if ~isempty(parts),s=strjoin(parts,' ; ');end
catch
end
end

function dumpUnconnected(fid,T,kind)
for r=1:height(T)
    logf(fid,'  [UNCONNECTED %s] %s | port%d | type=%s',kind,T.Block{r},T.Port(r),T.BlockType{r});
end
end

function f=resolveLoadedModelFile(model,auditedPath,fid)
f='';cands={};
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

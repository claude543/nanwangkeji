%% PATCH_K26_V5_LAYER2_SLOW_COLLAPSE_CAUSAL_HARNESS_V1_2.m
% K26_V5 Layer-2 slow-voltage-collapse causal harness
% ONE-BUILD root-cause platform, V1.2
%
% SCIENTIFIC SCOPE
% ----------------
% This patch intentionally does NOT add:
%   - work-point reacquisition / post-island center tracking;
%   - new PLL/frame intervention;
%   - ESS1 controller tuning;
%   - new OpWrite blocks;
%   - PI/droop/F25/network parameter changes.
%
% It adds only two ACTIVE causal dimensions on the five GFLs:
%
% A) Slow terminal-voltage feedforward participation
%       Vff =
%          Vanchor
%        + Kslow*(Vslow - Vanchor)
%        + Kfast*(Vraw - Vslow)
%
%    Kfast remains the already-proven Mode7 mechanism.
%    Layer-2 tests change only Kslow.
%
% B) P/Q-loop current-reference dynamics
%       Iout =
%          Ianchor
%        + Kpq*(Iselected - Ianchor)
%
%    The old C2 block is preserved. Layer-2 is inserted AFTER old C2
%    and BEFORE Goto18.
%
% Separate Layer-2 mode:
%   L2_MODE=0 : current Mode7 exact-equivalent baseline
%   L2_MODE=1 : slow-VFF test only
%   L2_MODE=2 : P/Q-current-reference test only
%   L2_MODE=3 : both
%
% Runtime test parameters, per GFL:
%   AA15_L2_KSLOW_TARGET default 0.5
%   AA15_L2_KSLOW_SLEW   default 0.01/sample
%   AA15_L2_KPQ_TARGET   default 0.5
%   AA15_L2_KPQ_SLEW     default 0.01/sample
%
% IMPORTANT:
%   No K=0 extreme is forced by the model. Python may choose 0 only after
%   evidence justifies the stronger necessity test.
%
% EXACT-BYPASS CONTRACT
% ---------------------
% CAUSAL_MODE ~= 7:
%   Layer-2 cannot affect either Vdq or IdIq reference.
%
% CAUSAL_MODE = 7, L2_MODE = 0:
%   voltage path uses the current Mode7 final output exactly;
%   Iref path uses the old C2 output exactly.
%
% This means the new Build contains an exact Mode7 baseline for same-Build
% reproduction before any Layer-2 causal result is accepted.
%
% ESS1:
%   instrumentation only. Append missing local signals to existing G30 using
%   local global Goto/From; do not add OpComm and do not modify control.
%
% DATA:
%   GFL diag30 -> diag41:
%     31 Vanchor_d
%     32 Vanchor_q
%     33 Kslow_eff
%     34 Kslow_target
%     35 Ianchor_d
%     36 Ianchor_q
%     37 L2_Iref_out_d
%     38 L2_Iref_out_q
%     39 Kpq_eff
%     40 Kpq_target
%     41 L2_MODE
%
%   G30 appends 13 scalars:
%     raw Voltage-Regulator output dq                [2]
%     pre-saturation final current-reference dq      [2]
%     post-saturation final current-reference dq     [2]
%     actual Id/Iq used by Current Regulator         [2]
%     Current-Regulator converter-voltage command dq [2]
%     voltage-loop Vq_meas                           [1]
%     voltage-loop Vq_ref                            [1]
%     voltage-loop Vd_meas                           [1]
%
% OpWrite count and decimation remain:
%   G26/27/28/29 = 4
%   G30          = 10
%
% Expected compiled OpWrite input widths after patch:
%   G26 82
%   G27 41
%   G28 82
%   G29 38 (unchanged)
%   G30 128
%
% RUN LENGTH:
%   Do not change logger decimation. For Layer-2 formal runs, the supervisor
%   must run beyond the 12.0 s common full-block boundary, e.g. pause at
%   12.02 s. With J1 ~8.209 s this gives >3.7 s post-island evidence.

clearvars;
clc;

MODEL='K26_V5';
EXPECTED_SHA256='93c3b3ac955003a1ee366df6c9cb524b4367a44316448eb330f869a374f65954';

DEFAULT_KSLOW=0.5;
DEFAULT_KSLOW_SLEW=0.01;
DEFAULT_KPQ=0.5;
DEFAULT_KPQ_SLEW=0.01;

STAMP=datestr(now,'yyyymmdd_HHMMSS');
LOG_FILE=['9.02_PATCH_K26_V5_LAYER2_CAUSAL_HARNESS_V1_2_' STAMP '.txt'];

fid=fopen(LOG_FILE,'w','n','UTF-8');
if fid<0,error('Cannot create patch log.');end
cleanupFid=onCleanup(@() fclose(fid));

logf(fid,repmat('=',1,168));
logf(fid,'K26_V5 LAYER-2 SLOW-COLLAPSE CAUSAL HARNESS PATCH V1.2');
logf(fid,'[SCOPE] two GFL causal dimensions only; ESS1 instrumentation only; no work-point reacquisition.');
logf(fid,repmat('=',1,168));

%% 0. HARD INTERLOCK
if ~bdIsLoaded(MODEL),error('PATCH ABORT: K26_V5 must be open.');end
if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('PATCH ABORT: Dirty=%s; require off.',get_param(MODEL,'Dirty'));
end
if ~strcmpi(get_param(MODEL,'SimulationStatus'),'stopped')
    error('PATCH ABORT: model must be stopped.');
end

raw='';
try,raw=get_param(MODEL,'FileName');catch,end
modelFile=firstExistingFile({raw,which([MODEL '.slx']),which(MODEL),fullfile(pwd,[MODEL '.slx'])});
if isempty(modelFile),error('PATCH ABORT: cannot resolve model file.');end
sha0=fileSha256(modelFile);
logf(fid,'[MODEL FILE] %s',modelFile);
logf(fid,'[SHA BEFORE] %s',sha0);
if ~strcmpi(sha0,EXPECTED_SHA256)
    error('PATCH ABORT: SHA mismatch. Expected %s actual %s',EXPECTED_SHA256,sha0);
end
logf(fid,'[HASH PASS] exact audited post-Mode7 model.');

names={'PV1','PV2','ESS2','EV1','EV2'};
ctrls={ ...
    [MODEL '/SS_Slave3/PV1_Control'], ...
    [MODEL '/SS_Slave3/PV2_Control'], ...
    [MODEL '/SS_Slave2/ESS2_Control'], ...
    [MODEL '/SS_Slave/EV1_Control'], ...
    [MODEL '/SS_Slave/Control System'] ...
};

opPaths={ ...
    [MODEL '/SS_Slave/AA15_ROOTDIAG_EV12_OPWRITE_G26'], ...
    [MODEL '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'], ...
    [MODEL '/SS_Slave3/AA15_ROOTDIAG_PV12_OPWRITE_G28'], ...
    [MODEL '/SM_Master/AA15_FREQDIAG_SM_OPWRITE_G29'], ...
    [MODEL '/SS_Slave2/AA15_FREQDIAG_ESS1_OPWRITE_G30'] ...
};
opNames={'G26','G27','G28','G29','G30'};

%% 1. SCRATCH COMPILE BEFORE TOUCHING REAL MODEL
logf(fid,'\n--- 1. SCRATCH FUNCTION/STATE PREFLIGHT ---');
protoMode7=[MODEL '/SS_Slave3/PV1_Control/AA15_VFF_DQ_SHAPER'];
requireBlock(protoMode7);
scratchPreflight(protoMode7);
logf(fid,'[SCRATCH PASS] copied trusted Mode7 subsystem + scalar-only L2 VFF/Iref wrappers compile.');

%% 2. STRICT PREPATCH STRUCTURE ASSERT
logf(fid,'\n--- 2. STRICT PREPATCH STRUCTURE ASSERT ---');
for i=1:5
    dev=names{i};ctrl=ctrls{i};
    req={ ...
        [ctrl '/AA15_CAUSAL_MODE'],[ctrl '/AA15_MODE_EQ_7'], ...
        [ctrl '/AA15_C_HOLD_STEP'], ...
        [ctrl '/AA15_C1_AXIS_TRACK_HOLD'], ...
        [ctrl '/AA15_VFF_DQ_SHAPER'], ...
        [ctrl '/AA15_C2_IREF_TRACK_HOLD'], ...
        [ctrl '/Goto18'], ...
        [ctrl '/Current Regulator'], ...
        [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'] ...
    };
    for k=1:numel(req),requireBlock(req{k});end

    lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];
    sh=[ctrl '/AA15_VFF_DQ_SHAPER'];

    assertSource(sh,1,[ctrl '/AA15_C1_AXIS_TRACK_HOLD'],1,[dev ' trusted Mode7 raw V source']);
    assertSource([ctrl '/Current Regulator'],1,sh,1,[dev ' CurrentReg V source']);
    assertSource(lg,5,sh,1,[dev ' logger applied V source']);
    assertSource([ctrl '/AA15_C2_IREF_TRACK_HOLD'],1,[ctrl '/Power Control Loop'],1,[dev ' C2 raw source']);
    assertSource([ctrl '/Goto18'],1,[ctrl '/AA15_C2_IREF_TRACK_HOLD'],1,[dev ' C2 -> Goto18']);

    if str2double(safeParam(lg,'Inputs'))~=22
        error('[%s] logger physical Inputs must be22 prepatch.',dev);
    end
    verifyCurrentMode7Shaper(sh,dev);

    planned={ ...
        'AA15_L2_MODE','AA15_L2_KSLOW_TARGET','AA15_L2_KSLOW_SLEW', ...
        'AA15_L2_KPQ_TARGET','AA15_L2_KPQ_SLEW', ...
        'AA15_L2_VFF_WRAPPER','AA15_L2_IREF_SHAPER' ...
    };
    for k=1:numel(planned)
        if blockExists([ctrl '/' planned{k}])
            error('[%s] planned name collision: %s',dev,planned{k});
        end
    end
    logf(fid,'[PREPATCH PASS] %s',dev);
end

% ESS1 logging tags/blocks must be free BEFORE any edit.
essTapTags={ ...
    'AA15_L2_ESS1_VPI_RAW', ...
    'AA15_L2_ESS1_IREF_PRESAT', ...
    'AA15_L2_ESS1_IREF_FINAL', ...
    'AA15_L2_ESS1_IDIQ_MEAS', ...
    'AA15_L2_ESS1_VCONV_DQ', ...
    'AA15_L2_ESS1_VQ_MEAS', ...
    'AA15_L2_ESS1_VQ_REF', ...
    'AA15_L2_ESS1_VD_MEAS'};
for kk=1:numel(essTapTags)
    gHits=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on', ...
        'BlockType','Goto','GotoTag',essTapTags{kk});
    fHits=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on', ...
        'BlockType','From','GotoTag',essTapTags{kk});
    if ~isempty(gHits)||~isempty(fHits)
        error('ESS1 planned global tag collision: %s',essTapTags{kk});
    end
    if blockExists([MODEL '/SS_Slave2/' essTapTags{kk} '_FROM'])
        error('ESS1 planned From block collision: %s',essTapTags{kk});
    end
end
logf(fid,'[PREPATCH PASS] all ESS1 Layer-2 tap tags free.');

expectedDec={'4','4','4','4','10'};
for k=1:5
    requireBlock(opPaths{k});
    if ~strcmp(strtrim(safeParam(opPaths{k},'Decimation')),expectedDec{k})
        error('%s Decimation changed from audited contract.',opNames{k});
    end
end
g30mux=[MODEL '/SS_Slave2/AA15_FREQDIAG_ESS1_MUX'];
requireBlock(g30mux);
if str2double(safeParam(g30mux,'Inputs'))~=63
    error('G30 mux prepatch physical Inputs must be63.');
end

% ESS1 exact source blocks needed for instrumentation.
ess=[MODEL '/SS_Slave2/ESS1_Control'];
essReq={ ...
    [ess '/Voltage Regulators'], ...
    [ess '/AA15_F8_VOLTAGE_LOOP_FEEDFORWARD'], ...
    [ess '/AA15_F8_VOLTAGE_LOOP_FEEDFORWARD/AA15_F22_SUPPORT_ROUTER'], ...
    [ess '/F10_IREG_IDQ_RAW_SWITCH'], ...
    [ess '/Current Regulator'], ...
    [ess '/Selector11'],[ess '/From17'],[ess '/Selector10'] ...
};
for k=1:numel(essReq),requireBlock(essReq{k});end

%% 3. FULL BACKUP
modelDir=fileparts(modelFile);
backupFile=fullfile(modelDir,['K26_V5__PRE_LAYER2_CAUSAL_V1_2_' STAMP '.slx']);
[ok,msg]=copyfile(modelFile,backupFile);
if ~ok,error('Backup failed: %s',msg);end
logf(fid,'[BACKUP PASS] %s',backupFile);

savedToDisk=false;
compiled=false;

try
    %% 4. FIVE-GFL LAYER-2 INSERTION
    logf(fid,'\n--- 4. FIVE-GFL LAYER-2 INSERTION ---');
    for i=1:5
        dev=names{i};ctrl=ctrls{i};
        x0=topLevelMaxRight(ctrl)+120;
        y0=430;

        % Runtime parameters.
        add_block('built-in/Constant',[ctrl '/AA15_L2_MODE'], ...
            'Value','0','SampleTime','Ts','Position',[x0 y0 x0+75 y0+26]);
        add_block('built-in/Constant',[ctrl '/AA15_L2_KSLOW_TARGET'], ...
            'Value',num2str(DEFAULT_KSLOW,17),'SampleTime','Ts','Position',[x0 y0+45 x0+110 y0+71]);
        add_block('built-in/Constant',[ctrl '/AA15_L2_KSLOW_SLEW'], ...
            'Value',num2str(DEFAULT_KSLOW_SLEW,17),'SampleTime','Ts','Position',[x0 y0+90 x0+110 y0+116]);
        add_block('built-in/Constant',[ctrl '/AA15_L2_KPQ_TARGET'], ...
            'Value',num2str(DEFAULT_KPQ,17),'SampleTime','Ts','Position',[x0 y0+135 x0+110 y0+161]);
        add_block('built-in/Constant',[ctrl '/AA15_L2_KPQ_SLEW'], ...
            'Value',num2str(DEFAULT_KPQ_SLEW,17),'SampleTime','Ts','Position',[x0 y0+180 x0+110 y0+206]);

        % IMPORTANT V1.2:
        % Do NOT modify the trusted current Mode7 subsystem at all.
        % Add a scalar-only Layer-2 wrapper AFTER it.
        sh=[ctrl '/AA15_VFF_DQ_SHAPER'];
        vwrap=[ctrl '/AA15_L2_VFF_WRAPPER'];
        addL2VffWrapper(vwrap,[x0+180 y0-120 x0+530 y0+145]);

        add_line(ctrl,'AA15_VFF_DQ_SHAPER/1','AA15_L2_VFF_WRAPPER/1','autorouting','on');
        add_line(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','AA15_L2_VFF_WRAPPER/2','autorouting','on');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/2','AA15_L2_VFF_WRAPPER/3','autorouting','on');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/3','AA15_L2_VFF_WRAPPER/4','autorouting','on');
        add_line(ctrl,'AA15_MODE_EQ_7/1','AA15_L2_VFF_WRAPPER/5','autorouting','on');
        add_line(ctrl,'AA15_C_HOLD_STEP/1','AA15_L2_VFF_WRAPPER/6','autorouting','on');
        add_line(ctrl,'AA15_L2_MODE/1','AA15_L2_VFF_WRAPPER/7','autorouting','on');
        add_line(ctrl,'AA15_L2_KSLOW_TARGET/1','AA15_L2_VFF_WRAPPER/8','autorouting','on');
        add_line(ctrl,'AA15_L2_KSLOW_SLEW/1','AA15_L2_VFF_WRAPPER/9','autorouting','on');

        % Reroute only the two consumers of current Mode7 FinalVdq.
        deleteSpecificLine(ctrl,'AA15_VFF_DQ_SHAPER/1','Current Regulator/1');
        deleteSpecificLine(ctrl,'AA15_VFF_DQ_SHAPER/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5');
        add_line(ctrl,'AA15_L2_VFF_WRAPPER/1','Current Regulator/1','autorouting','on');
        add_line(ctrl,'AA15_L2_VFF_WRAPPER/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5','autorouting','on');

        % New scalar-only Layer-2 Iref shaper after old C2 and before Goto18.
        ish=[ctrl '/AA15_L2_IREF_SHAPER'];
        addL2IrefShaper(ish,[x0+200 y0+230 x0+500 y0+465]);

        deleteSpecificLine(ctrl,'AA15_C2_IREF_TRACK_HOLD/1','Goto18/1');
        add_line(ctrl,'AA15_C2_IREF_TRACK_HOLD/1','AA15_L2_IREF_SHAPER/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_EQ_7/1','AA15_L2_IREF_SHAPER/2','autorouting','on');
        add_line(ctrl,'AA15_C_HOLD_STEP/1','AA15_L2_IREF_SHAPER/3','autorouting','on');
        add_line(ctrl,'AA15_L2_MODE/1','AA15_L2_IREF_SHAPER/4','autorouting','on');
        add_line(ctrl,'AA15_L2_KPQ_TARGET/1','AA15_L2_IREF_SHAPER/5','autorouting','on');
        add_line(ctrl,'AA15_L2_KPQ_SLEW/1','AA15_L2_IREF_SHAPER/6','autorouting','on');
        add_line(ctrl,'AA15_L2_IREF_SHAPER/1','Goto18/1','autorouting','on');

        % Extend diag30 -> diag41. Existing first 30 scalar semantics remain unchanged.
        lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];
        set_param(lg,'Inputs','30');
        add_line(ctrl,'AA15_L2_VFF_WRAPPER/2','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/23','autorouting','on');
        add_line(ctrl,'AA15_L2_VFF_WRAPPER/3','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/24','autorouting','on');
        add_line(ctrl,'AA15_L2_VFF_WRAPPER/4','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/25','autorouting','on');
        add_line(ctrl,'AA15_L2_IREF_SHAPER/2','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/26','autorouting','on');
        add_line(ctrl,'AA15_L2_IREF_SHAPER/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/27','autorouting','on');
        add_line(ctrl,'AA15_L2_IREF_SHAPER/3','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/28','autorouting','on');
        add_line(ctrl,'AA15_L2_IREF_SHAPER/4','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/29','autorouting','on');
        add_line(ctrl,'AA15_L2_MODE/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/30','autorouting','on');

        immediateGflPostassert(ctrl,dev);
        logf(fid,'[INSERT PASS] %s',dev);
    end

    %% 5. ESS1 INSTRUMENTATION-ONLY APPEND TO G30
    logf(fid,'\n--- 5. ESS1 INSTRUMENTATION-ONLY APPEND TO G30 ---');
    tags={ ...
        'AA15_L2_ESS1_VPI_RAW', ...
        'AA15_L2_ESS1_IREF_PRESAT', ...
        'AA15_L2_ESS1_IREF_FINAL', ...
        'AA15_L2_ESS1_IDIQ_MEAS', ...
        'AA15_L2_ESS1_VCONV_DQ', ...
        'AA15_L2_ESS1_VQ_MEAS', ...
        'AA15_L2_ESS1_VQ_REF', ...
        'AA15_L2_ESS1_VD_MEAS' ...
    };
    srcBlocks={ ...
        [ess '/Voltage Regulators'], ...
        [ess '/AA15_F8_VOLTAGE_LOOP_FEEDFORWARD/AA15_F22_SUPPORT_ROUTER'], ...
        [ess '/AA15_F8_VOLTAGE_LOOP_FEEDFORWARD'], ...
        [ess '/F10_IREG_IDQ_RAW_SWITCH'], ...
        [ess '/Current Regulator'], ...
        [ess '/Selector11'], ...
        [ess '/From17'], ...
        [ess '/Selector10'] ...
    };
    srcPorts=[1 1 1 1 1 1 1 1];

    for k=1:numel(tags)
        addGlobalTap(MODEL,ess,srcBlocks{k},srcPorts(k),tags{k},k);
    end

    set_param(g30mux,'Inputs','71');
    for k=1:numel(tags)
        from=[MODEL '/SS_Slave2/' tags{k} '_FROM'];
        add_line([MODEL '/SS_Slave2'], ...
            [get_param(from,'Name') '/1'], ...
            sprintf('AA15_FREQDIAG_ESS1_MUX/%d',63+k), ...
            'autorouting','on');
    end

    %% 6. GLOBAL STRUCTURAL POSTASSERT
    logf(fid,'\n--- 6. GLOBAL STRUCTURAL POSTASSERT ---');
    for i=1:5
        immediateGflPostassert(ctrls{i},names{i});
    end
    if str2double(safeParam(g30mux,'Inputs'))~=71
        error('G30 mux Inputs must be71 postpatch.');
    end
    for k=1:5
        if ~strcmp(strtrim(safeParam(opPaths{k},'Decimation')),expectedDec{k})
            error('%s Decimation changed unexpectedly.',opNames{k});
        end
    end
    opw=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*');
    if numel(opw)~=5,error('OpWrite count changed; expected exactly5.');end

    %% 7. EXPLICIT COMPILE BEFORE SAVE
    logf(fid,'\n--- 7. EXPLICIT COMPILE BEFORE SAVE ---');
    feval(MODEL,[],[],[],'compile');
    compiled=true;

    for i=1:5
        ctrl=ctrls{i};dev=names{i};
        wv0=compiledWidths([ctrl '/AA15_VFF_DQ_SHAPER']);
        wv=compiledWidths([ctrl '/AA15_L2_VFF_WRAPPER']);
        wi=compiledWidths([ctrl '/AA15_L2_IREF_SHAPER']);
        wl=compiledWidths([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR']);
        wc=compiledWidths([ctrl '/Current Regulator']);

        logf(fid,'[%s] trustedVFF in=%s out=%s | L2VFF in=%s out=%s | IREF in=%s out=%s | diag=%s | CRin=%s', ...
            dev,mat2str(wv0.Inport),mat2str(wv0.Outport), ...
            mat2str(wv.Inport),mat2str(wv.Outport), ...
            mat2str(wi.Inport),mat2str(wi.Outport), ...
            mat2str(wl.Outport),mat2str(wc.Inport));

        requireWidthVec(wv0.Inport,[2 1 1 1 1 1],[dev ' trusted VFF inputs']);
        requireWidthVec(wv0.Outport,[2 2 1 1],[dev ' trusted VFF outputs']);
        requireWidthVec(wv.Inport,[2 2 2 1 1 1 1 1 1],[dev ' L2 VFF inputs']);
        requireWidthVec(wv.Outport,[2 2 1 1],[dev ' L2 VFF outputs']);
        requireWidthVec(wi.Inport,[2 1 1 1 1 1],[dev ' IREF inputs']);
        requireWidthVec(wi.Outport,[2 2 1 1],[dev ' IREF outputs']);
        requireWidthAt(wl.Outport,1,41,[dev ' diag41']);
        requireWidthVec(wc.Inport,[2 2 2],[dev ' CurrentReg inputs']);
    end

    expectedOp=[82 41 82 38 128];
    for k=1:5
        w=compiledWidths(opPaths{k});
        logf(fid,'[%s] compiled input=%s',opNames{k},mat2str(w.Inport));
        requireWidthAt(w.Inport,1,expectedOp(k),[opNames{k} ' width']);
    end

    feval(MODEL,[],[],[],'term');
    compiled=false;
    logf(fid,'[COMPILE PASS] all frozen widths confirmed.');

    %% 8. DEFAULTS + SAVE ONCE
    logf(fid,'\n--- 8. SAVE ONCE ---');
    for i=1:5
        set_param([ctrls{i} '/AA15_CAUSAL_MODE'],'Value','0');
        set_param([ctrls{i} '/AA15_L2_MODE'],'Value','0');
    end
    save_system(MODEL);
    savedToDisk=true;
    sha1=fileSha256(modelFile);
    logf(fid,'[SAVE PASS]');
    logf(fid,'[SHA AFTER] %s',sha1);

    %% 9. CLOSE / RELOAD / PERSISTENCE COMPILE
    logf(fid,'\n--- 9. CLOSE / RELOAD / PERSISTENCE COMPILE ---');
    close_system(MODEL,0);
    load_system(modelFile);
    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Reloaded model Dirty is not off.');
    end

    for i=1:5
        immediateGflPostassert(ctrls{i},names{i});
        if ~strcmp(strtrim(safeParam([ctrls{i} '/AA15_CAUSAL_MODE'],'Value')),'0')
            error('%s persisted causal mode not0.',names{i});
        end
        if ~strcmp(strtrim(safeParam([ctrls{i} '/AA15_L2_MODE'],'Value')),'0')
            error('%s persisted L2 mode not0.',names{i});
        end
    end

    feval(MODEL,[],[],[],'compile');
    compiled=true;
    expectedOp=[82 41 82 38 128];
    for k=1:5
        w=compiledWidths(opPaths{k});
        requireWidthAt(w.Inport,1,expectedOp(k),[opNames{k} ' persisted width']);
    end
    feval(MODEL,[],[],[],'term');
    compiled=false;

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Final model Dirty is not off.');
    end

    logf(fid,'\n%s',repmat('=',1,168));
    logf(fid,'PATCH PASS');
    logf(fid,'[NO WORK-POINT REACQUISITION] confirmed by design.');
    logf(fid,'[L2 MODES] 0 baseline; 1 slow-VFF; 2 P/Q-Iref; 3 combined.');
    logf(fid,'[DEFAULT TEST STRENGTHS] Kslow=%.3f Kpq=%.3f; both runtime tunable.',DEFAULT_KSLOW,DEFAULT_KPQ);
    logf(fid,'[OPWRITE] count5, decimation unchanged 4/4/4/4/10.');
    logf(fid,'[NEXT] Run independent verifier before RT-LAB Rebuild All.');
    logf(fid,'Backup: %s',backupFile);
    logf(fid,'%s',repmat('=',1,168));

catch ME
    if compiled
        try,feval(MODEL,[],[],[],'term');catch,end
    end
    logf(fid,'\n%s',repmat('!',1,168));
    logf(fid,'PATCH FAILURE');
    logf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));

    try
        if bdIsLoaded(MODEL),close_system(MODEL,0);end
    catch
    end

    if savedToDisk
        try
            [okr,msgr]=copyfile(backupFile,modelFile,'f');
            if okr,logf(fid,'[ROLLBACK DISK PASS] backup restored.');
            else,logf(fid,'[ROLLBACK DISK FAIL] %s',msgr);end
        catch MEr
            logf(fid,'[ROLLBACK EXCEPTION] %s',MEr.message);
        end
    else
        logf(fid,'[ROLLBACK] save_system had not occurred; audited disk model unchanged.');
    end

    try
        load_system(modelFile);
        logf(fid,'[ROLLBACK RELOAD] model reloaded.');
    catch MEr
        logf(fid,'[ROLLBACK RELOAD WARN] %s',MEr.message);
    end
    logf(fid,'%s',repmat('!',1,168));
    rethrow(ME);
end

fprintf('\nPatch finished. Log: %s\n',LOG_FILE);

%% =========================================================================
%% Scratch
%% =========================================================================
function scratchPreflight(protoMode7)
% V1.2 preflight copies the ACTUAL trusted current Mode7 subsystem.
% New MATLAB Functions receive scalar d/q only; no MATLAB Function sees a
% width-2 vector. This eliminates 1-D-vector/2-D-column inference ambiguity.
tmp=matlab.lang.makeValidName(['AA15_L2_PREFLIGHT_' datestr(now,'HHMMSSFFF')]);
new_system(tmp);
c=onCleanup(@() closeScratch(tmp));
set_param(tmp,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','0.0001');
mw=get_param(tmp,'ModelWorkspace');assignin(mw,'Ts',0.0001);

% Copy the already-compiled real Mode7 subsystem verbatim.
add_block(protoMode7,[tmp '/Mode7Shaper'],'Position',[250 60 600 300]);
vwrap=[tmp '/L2VFF'];
addL2VffWrapper(vwrap,[700 40 1040 320]);
ish=[tmp '/IREF'];
addL2IrefShaper(ish,[700 390 1040 650]);

% Scalar -> Mux reproduces real 1-D width-2 signal shape.
vals={ ...
    'Vd','1.0';'Vq','0.0';'Id','0.2';'Iq','0.1'; ...
    'Mode7','1';'Hold','0';'Alpha','0.00062812117996513539'; ...
    'KfastIsland','0';'KfastSlew','0.01';'L2Mode','1'; ...
    'Kslow','0.5';'KslowSlew','0.01';'Kpq','0.5';'KpqSlew','0.01'};
for k=1:size(vals,1)
    add_block('built-in/Constant',[tmp '/' vals{k,1}],'Value',vals{k,2});
end
add_block('built-in/Mux',[tmp '/RawV_Mux'],'Inputs','2');
add_block('built-in/Mux',[tmp '/RawI_Mux'],'Inputs','2');
add_line(tmp,'Vd/1','RawV_Mux/1');add_line(tmp,'Vq/1','RawV_Mux/2');
add_line(tmp,'Id/1','RawI_Mux/1');add_line(tmp,'Iq/1','RawI_Mux/2');

% Trusted Mode7.
add_line(tmp,'RawV_Mux/1','Mode7Shaper/1');
add_line(tmp,'Mode7/1','Mode7Shaper/2');
add_line(tmp,'Hold/1','Mode7Shaper/3');
add_line(tmp,'Alpha/1','Mode7Shaper/4');
add_line(tmp,'KfastIsland/1','Mode7Shaper/5');
add_line(tmp,'KfastSlew/1','Mode7Shaper/6');

% New Layer-2 VFF wrapper.
add_line(tmp,'Mode7Shaper/1','L2VFF/1');
add_line(tmp,'RawV_Mux/1','L2VFF/2');
add_line(tmp,'Mode7Shaper/2','L2VFF/3');
add_line(tmp,'Mode7Shaper/3','L2VFF/4');
add_line(tmp,'Mode7/1','L2VFF/5');
add_line(tmp,'Hold/1','L2VFF/6');
add_line(tmp,'L2Mode/1','L2VFF/7');
add_line(tmp,'Kslow/1','L2VFF/8');
add_line(tmp,'KslowSlew/1','L2VFF/9');

% New Iref wrapper.
add_line(tmp,'RawI_Mux/1','IREF/1');
add_line(tmp,'Mode7/1','IREF/2');
add_line(tmp,'Hold/1','IREF/3');
add_line(tmp,'L2Mode/1','IREF/4');
add_line(tmp,'Kpq/1','IREF/5');
add_line(tmp,'KpqSlew/1','IREF/6');

for k=1:4
    add_block('built-in/Terminator',[tmp sprintf('/TV%d',k)]);
    add_line(tmp,sprintf('L2VFF/%d',k),sprintf('TV%d/1',k));
end
for k=1:4
    add_block('built-in/Terminator',[tmp sprintf('/TI%d',k)]);
    add_line(tmp,sprintf('IREF/%d',k),sprintf('TI%d/1',k));
end

feval(tmp,[],[],[],'compile');
w0=compiledWidths([tmp '/Mode7Shaper']);
wv=compiledWidths(vwrap);
wi=compiledWidths(ish);
requireWidthVec(w0.Inport,[2 1 1 1 1 1],'scratch trusted Mode7 in');
requireWidthVec(w0.Outport,[2 2 1 1],'scratch trusted Mode7 out');
requireWidthVec(wv.Inport,[2 2 2 1 1 1 1 1 1],'scratch L2 VFF in');
requireWidthVec(wv.Outport,[2 2 1 1],'scratch L2 VFF out');
requireWidthVec(wi.Inport,[2 1 1 1 1 1],'scratch IREF in');
requireWidthVec(wi.Outport,[2 2 1 1],'scratch IREF out');
feval(tmp,[],[],[],'term');
end

function closeScratch(tmp)
try
    if bdIsLoaded(tmp),close_system(tmp,0);end
catch
end
end

%% =========================================================================
%% Scalar-only Layer-2 VFF wrapper AFTER trusted Mode7
%% =========================================================================
function addL2VffWrapper(sub,pos)
add_block('built-in/SubSystem',sub,'Position',pos);
ins={'Mode7Final','RawVdq','Vslow','Kfast','Mode7Enable','HoldStep','L2Mode','KslowTarget','KslowSlew'};
for k=1:9
    add_block('built-in/Inport',[sub '/' ins{k}],'Port',num2str(k));
end

add_block('built-in/Demux',[sub '/AA15_L2_RAW_DEMUX'],'Outputs','2');
add_block('built-in/Demux',[sub '/AA15_L2_VSLOW_DEMUX'],'Outputs','2');
add_block('built-in/UnitDelay',[sub '/AA15_L2_VANCHOR_D_STATE'],'InitialCondition','0','SampleTime','Ts');
add_block('built-in/UnitDelay',[sub '/AA15_L2_VANCHOR_Q_STATE'],'InitialCondition','0','SampleTime','Ts');
add_block('built-in/UnitDelay',[sub '/AA15_L2_KSLOW_STATE'],'InitialCondition','1','SampleTime','Ts');

fn=[sub '/AA15_L2_VFF_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',fn);
setMatlabFunctionScript(fn,vffWrapperScalarScript());

add_block('built-in/Mux',[sub '/AA15_L2_VCANDIDATE_MUX'],'Inputs','2');
add_block('built-in/Mux',[sub '/AA15_L2_VANCHOR_MUX'],'Inputs','2');
add_block('built-in/Switch',[sub '/AA15_L2_VFF_FINAL_SWITCH'], ...
    'Criteria','u2 > Threshold','Threshold','0.5');

outs={'FinalVdq','Vanchor','Kslow_eff','Kslow_target'};
for k=1:4
    add_block('built-in/Outport',[sub '/' outs{k}],'Port',num2str(k));
end

add_line(sub,'RawVdq/1','AA15_L2_RAW_DEMUX/1','autorouting','on');
add_line(sub,'Vslow/1','AA15_L2_VSLOW_DEMUX/1','autorouting','on');

% Function inputs are ALL SCALAR:
% raw_d,raw_q,vslow_d,vslow_q,kfast,anchor_d_z1,anchor_q_z1,kslow_z1,
% mode7,hold,l2mode,kslowtest,kslowslew.
srcs={ ...
    'AA15_L2_RAW_DEMUX/1','AA15_L2_RAW_DEMUX/2', ...
    'AA15_L2_VSLOW_DEMUX/1','AA15_L2_VSLOW_DEMUX/2','Kfast/1', ...
    'AA15_L2_VANCHOR_D_STATE/1','AA15_L2_VANCHOR_Q_STATE/1','AA15_L2_KSLOW_STATE/1', ...
    'Mode7Enable/1','HoldStep/1','L2Mode/1','KslowTarget/1','KslowSlew/1'};
for k=1:numel(srcs)
    add_line(sub,srcs{k},sprintf('AA15_L2_VFF_CORE/%d',k),'autorouting','on');
end

% Function outputs all scalar:
% cand_d,cand_q,anchor_d_next,anchor_q_next,kslow_next,target,active.
add_line(sub,'AA15_L2_VFF_CORE/3','AA15_L2_VANCHOR_D_STATE/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/4','AA15_L2_VANCHOR_Q_STATE/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/5','AA15_L2_KSLOW_STATE/1','autorouting','on');

add_line(sub,'AA15_L2_VFF_CORE/1','AA15_L2_VCANDIDATE_MUX/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/2','AA15_L2_VCANDIDATE_MUX/2','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/3','AA15_L2_VANCHOR_MUX/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/4','AA15_L2_VANCHOR_MUX/2','autorouting','on');

% Exact bypass to trusted current Mode7Final when Layer-2 slow intervention inactive.
add_line(sub,'AA15_L2_VCANDIDATE_MUX/1','AA15_L2_VFF_FINAL_SWITCH/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/7','AA15_L2_VFF_FINAL_SWITCH/2','autorouting','on');
add_line(sub,'Mode7Final/1','AA15_L2_VFF_FINAL_SWITCH/3','autorouting','on');

add_line(sub,'AA15_L2_VFF_FINAL_SWITCH/1','FinalVdq/1','autorouting','on');
add_line(sub,'AA15_L2_VANCHOR_MUX/1','Vanchor/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/5','Kslow_eff/1','autorouting','on');
add_line(sub,'AA15_L2_VFF_CORE/6','Kslow_target/1','autorouting','on');
end

function s=vffWrapperScalarScript()
s=sprintf([ ...
'function [cand_d,cand_q,anchor_d_next,anchor_q_next,kslow_next,kslow_target,active] = fcn(raw_d,raw_q,vslow_d,vslow_q,kfast,anchor_d_z1,anchor_q_z1,kslow_z1,mode7_enable,hold_step,l2_mode,kslow_test,kslow_slew)\n' ...
'%%#codegen\n' ...
'ks_test=min(max(kslow_test,0.0),1.0);\n' ...
'slew=abs(kslow_slew);\n' ...
'post=(mode7_enable>0.5)&&(hold_step<0.5);\n' ...
'if post\n' ...
'    anchor_d_next=anchor_d_z1;\n' ...
'    anchor_q_next=anchor_q_z1;\n' ...
'else\n' ...
'    anchor_d_next=vslow_d;\n' ...
'    anchor_q_next=vslow_q;\n' ...
'end\n' ...
'm=floor(min(max(l2_mode,0.0),3.0)+0.5);\n' ...
'active=post&&((m==1.0)||(m==3.0));\n' ...
'if active\n' ...
'    kslow_target=ks_test;\n' ...
'else\n' ...
'    kslow_target=1.0;\n' ...
'end\n' ...
'd=kslow_target-kslow_z1;\n' ...
'if d>slew\n' ...
'    dl=slew;\n' ...
'elseif d<-slew\n' ...
'    dl=-slew;\n' ...
'else\n' ...
'    dl=d;\n' ...
'end\n' ...
'kslow_next=min(max(kslow_z1+dl,0.0),1.0);\n' ...
'cand_d=anchor_d_next+kslow_next*(vslow_d-anchor_d_next)+kfast*(raw_d-vslow_d);\n' ...
'cand_q=anchor_q_next+kslow_next*(vslow_q-anchor_q_next)+kfast*(raw_q-vslow_q);\n' ...
'end\n' ...
]);
end

%% =========================================================================
%% Iref shaper
%% =========================================================================
function addL2IrefShaper(sub,pos)
% External contract stays width-2, but all MATLAB Function calculations are
% scalar d/q. This eliminates the 1-D-vector vs 2-D-column ambiguity that
% caused V1.0 to fail on the real C2 output.
add_block('built-in/SubSystem',sub,'Position',pos);
ins={'Iselected','Mode7Enable','HoldStep','L2Mode','KpqTarget','KpqSlew'};
for k=1:6,add_block('built-in/Inport',[sub '/' ins{k}],'Port',num2str(k));end

add_block('built-in/Demux',[sub '/AA15_L2_ISELECTED_DEMUX'],'Outputs','2');
add_block('built-in/UnitDelay',[sub '/AA15_L2_IANCHOR_D_STATE'],'InitialCondition','0','SampleTime','Ts');
add_block('built-in/UnitDelay',[sub '/AA15_L2_IANCHOR_Q_STATE'],'InitialCondition','0','SampleTime','Ts');
add_block('built-in/UnitDelay',[sub '/AA15_L2_KPQ_STATE'],'InitialCondition','1','SampleTime','Ts');

fn=[sub '/AA15_L2_IREF_CORE'];
add_block('simulink/User-Defined Functions/MATLAB Function',fn);
setMatlabFunctionScript(fn,irefLayer2Script());

add_block('built-in/Mux',[sub '/AA15_L2_ICANDIDATE_MUX'],'Inputs','2');
add_block('built-in/Mux',[sub '/AA15_L2_IANCHOR_MUX'],'Inputs','2');
add_block('built-in/Switch',[sub '/AA15_L2_IREF_FINAL_SWITCH'],'Criteria','u2 > Threshold','Threshold','0.5');

outs={'Ifinal','Ianchor','Kpq_eff','Kpq_target'};
for k=1:4,add_block('built-in/Outport',[sub '/' outs{k}],'Port',num2str(k));end

add_line(sub,'Iselected/1','AA15_L2_ISELECTED_DEMUX/1','autorouting','on');
% Function inputs are all scalar:
% 1 isel_d, 2 isel_q, 3 anchor_d_z1, 4 anchor_q_z1, 5 kpq_z1,
% 6 mode7, 7 hold, 8 l2mode, 9 kpqtest, 10 kpqslew.
srcs={ ...
    'AA15_L2_ISELECTED_DEMUX/1','AA15_L2_ISELECTED_DEMUX/2', ...
    'AA15_L2_IANCHOR_D_STATE/1','AA15_L2_IANCHOR_Q_STATE/1','AA15_L2_KPQ_STATE/1', ...
    'Mode7Enable/1','HoldStep/1','L2Mode/1','KpqTarget/1','KpqSlew/1'};
for k=1:numel(srcs),add_line(sub,srcs{k},sprintf('AA15_L2_IREF_CORE/%d',k),'autorouting','on');end

% Function outputs are all scalar:
% 1 cand_d,2 cand_q,3 anchor_d_next,4 anchor_q_next,
% 5 kpq_next,6 target,7 active.
add_line(sub,'AA15_L2_IREF_CORE/3','AA15_L2_IANCHOR_D_STATE/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/4','AA15_L2_IANCHOR_Q_STATE/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/5','AA15_L2_KPQ_STATE/1','autorouting','on');

add_line(sub,'AA15_L2_IREF_CORE/1','AA15_L2_ICANDIDATE_MUX/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/2','AA15_L2_ICANDIDATE_MUX/2','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/3','AA15_L2_IANCHOR_MUX/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/4','AA15_L2_IANCHOR_MUX/2','autorouting','on');

add_line(sub,'AA15_L2_ICANDIDATE_MUX/1','AA15_L2_IREF_FINAL_SWITCH/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/7','AA15_L2_IREF_FINAL_SWITCH/2','autorouting','on');
add_line(sub,'Iselected/1','AA15_L2_IREF_FINAL_SWITCH/3','autorouting','on');

add_line(sub,'AA15_L2_IREF_FINAL_SWITCH/1','Ifinal/1','autorouting','on');
add_line(sub,'AA15_L2_IANCHOR_MUX/1','Ianchor/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/5','Kpq_eff/1','autorouting','on');
add_line(sub,'AA15_L2_IREF_CORE/6','Kpq_target/1','autorouting','on');
end

function s=irefLayer2Script()
s=sprintf([ ...
'function [cand_d,cand_q,anchor_d_next,anchor_q_next,kpq_next,kpq_target,active] = fcn(isel_d,isel_q,anchor_d_z1,anchor_q_z1,kpq_z1,mode7_enable,hold_step,l2_mode,kpq_test,kpq_slew)\n' ...
'%%#codegen\n' ...
'kp_test=min(max(kpq_test,0.0),1.0);\n' ...
'slew=abs(kpq_slew);\n' ...
'post=(mode7_enable>0.5)&&(hold_step<0.5);\n' ...
'if post\n' ...
'    anchor_d_next=anchor_d_z1;\n' ...
'    anchor_q_next=anchor_q_z1;\n' ...
'else\n' ...
'    anchor_d_next=isel_d;\n' ...
'    anchor_q_next=isel_q;\n' ...
'end\n' ...
'm=floor(min(max(l2_mode,0.0),3.0)+0.5);\n' ...
'active=post&&((m==2.0)||(m==3.0));\n' ...
'if active\n' ...
'    kpq_target=kp_test;\n' ...
'else\n' ...
'    kpq_target=1.0;\n' ...
'end\n' ...
'd=kpq_target-kpq_z1;\n' ...
'if d>slew\n' ...
'    dl=slew;\n' ...
'elseif d<-slew\n' ...
'    dl=-slew;\n' ...
'else\n' ...
'    dl=d;\n' ...
'end\n' ...
'kpq_next=min(max(kpq_z1+dl,0.0),1.0);\n' ...
'cand_d=anchor_d_next+kpq_next*(isel_d-anchor_d_next);\n' ...
'cand_q=anchor_q_next+kpq_next*(isel_q-anchor_q_next);\n' ...
'end\n' ...
]);
end

%% =========================================================================
%% ESS1 taps
%% =========================================================================
function addGlobalTap(MODEL,ess,srcBlock,srcPort,tag,index)
% Goto lives in the nearest subsystem that owns the source block.
parent=get_param(srcBlock,'Parent');
goto=[parent '/' tag '_GOTO'];
if blockExists(goto),error('ESS1 tap name collision: %s',goto);end
add_block('built-in/Goto',goto,'GotoTag',tag,'TagVisibility','global');
add_line(parent, ...
    [get_param(srcBlock,'Name') '/' num2str(srcPort)], ...
    [get_param(goto,'Name') '/1'],'autorouting','on');

from=[MODEL '/SS_Slave2/' tag '_FROM'];
if blockExists(from),error('ESS1 From name collision: %s',from);end
add_block('built-in/From',from,'GotoTag',tag, ...
    'Position',[1700 1100+35*index 1850 1120+35*index]);
end

%% =========================================================================
%% Verification helpers
%% =========================================================================
function verifyCurrentMode7Shaper(sh,dev)
req={ ...
    [sh '/RawVdq'],[sh '/Mode7Enable'],[sh '/HoldStep'],[sh '/Alpha'], ...
    [sh '/KfastIsland'],[sh '/KfastSlew'], ...
    [sh '/AA15_VFF_SLOW_STATE'],[sh '/AA15_VFF_KFAST_STATE'], ...
    [sh '/AA15_VFF_CORE'],[sh '/AA15_VFF_FINAL_SWITCH'], ...
    [sh '/FinalVdq'],[sh '/Vslow'],[sh '/Kfast_eff'],[sh '/Kfast_target']};
for k=1:numel(req),requireBlock(req{k});end
rt=sfroot;charts=rt.find('-isa','Stateflow.EMChart','Path',[sh '/AA15_VFF_CORE']);
if isempty(charts)||numel(charts)~=1,error('[%s] Mode7 MATLAB Function not uniquely found.',dev);end
code=char(charts.Script);
must={ ...
    'vslow_next = vslow_z1 + alpha_eff .* (raw_vdq - vslow_z1);', ...
    'shape_active = (mode7_enable > 0.5) && (hold_step < 0.5);', ...
    'vshaped = vslow_next + kfast_next .* (raw_vdq - vslow_next);'};
for k=1:numel(must)
    if ~contains(normalizeText(code),normalizeText(must{k}))
        error('[%s] current Mode7 script does not match audited V1.2 core.',dev);
    end
end
end

function immediateGflPostassert(ctrl,dev)
sh=[ctrl '/AA15_VFF_DQ_SHAPER'];
vwrap=[ctrl '/AA15_L2_VFF_WRAPPER'];
ish=[ctrl '/AA15_L2_IREF_SHAPER'];
lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

req={ ...
    [ctrl '/AA15_L2_MODE'],[ctrl '/AA15_L2_KSLOW_TARGET'],[ctrl '/AA15_L2_KSLOW_SLEW'], ...
    [ctrl '/AA15_L2_KPQ_TARGET'],[ctrl '/AA15_L2_KPQ_SLEW'],sh,vwrap,ish,lg};
for k=1:numel(req),requireBlock(req{k});end

% Trusted Mode7 subsystem is still the original audited structure.
verifyCurrentMode7Shaper(sh,dev);
assertSource(sh,1,[ctrl '/AA15_C1_AXIS_TRACK_HOLD'],1,[dev ' trusted Mode7 raw']);
assertSource(vwrap,1,sh,1,[dev ' L2 VFF trusted baseline']);
assertSource(vwrap,2,[ctrl '/AA15_C1_AXIS_TRACK_HOLD'],1,[dev ' L2 VFF raw']);
assertSource(vwrap,3,sh,2,[dev ' L2 VFF slow']);
assertSource(vwrap,4,sh,3,[dev ' L2 VFF kfast']);
assertSource(vwrap,5,[ctrl '/AA15_MODE_EQ_7'],1,[dev ' L2 VFF mode7']);
assertSource(vwrap,6,[ctrl '/AA15_C_HOLD_STEP'],1,[dev ' L2 VFF edge']);
assertSource(vwrap,7,[ctrl '/AA15_L2_MODE'],1,[dev ' L2 VFF mode']);
assertSource(vwrap,8,[ctrl '/AA15_L2_KSLOW_TARGET'],1,[dev ' L2 VFF Kslow']);
assertSource(vwrap,9,[ctrl '/AA15_L2_KSLOW_SLEW'],1,[dev ' L2 VFF Kslow slew']);

assertSource([ctrl '/Current Regulator'],1,vwrap,1,[dev ' final V -> CurrentReg']);
assertSource(lg,5,vwrap,1,[dev ' final applied V -> logger']);

assertSource(ish,1,[ctrl '/AA15_C2_IREF_TRACK_HOLD'],1,[dev ' IREF selected']);
assertSource(ish,2,[ctrl '/AA15_MODE_EQ_7'],1,[dev ' IREF mode7']);
assertSource(ish,3,[ctrl '/AA15_C_HOLD_STEP'],1,[dev ' IREF holdstep']);
assertSource(ish,4,[ctrl '/AA15_L2_MODE'],1,[dev ' IREF L2 mode']);
assertSource(ish,5,[ctrl '/AA15_L2_KPQ_TARGET'],1,[dev ' IREF Kpq']);
assertSource(ish,6,[ctrl '/AA15_L2_KPQ_SLEW'],1,[dev ' IREF Kpq slew']);
assertSource([ctrl '/Goto18'],1,ish,1,[dev ' IREF final to Goto18']);

if str2double(safeParam(lg,'Inputs'))~=30,error('[%s] logger Inputs !=30.',dev);end
assertSource(lg,23,vwrap,2,[dev ' log Vanchor']);
assertSource(lg,24,vwrap,3,[dev ' log Kslow']);
assertSource(lg,25,vwrap,4,[dev ' log Kslow target']);
assertSource(lg,26,ish,2,[dev ' log Ianchor']);
assertSource(lg,27,ish,1,[dev ' log L2 Iout']);
assertSource(lg,28,ish,3,[dev ' log Kpq']);
assertSource(lg,29,ish,4,[dev ' log Kpq target']);
assertSource(lg,30,[ctrl '/AA15_L2_MODE'],1,[dev ' log L2 mode']);

verifyNoHiddenState([vwrap '/AA15_L2_VFF_CORE'],dev);
verifyNoHiddenState([ish '/AA15_L2_IREF_CORE'],dev);
end

function verifyNoHiddenState(fn,dev)
rt=sfroot;charts=rt.find('-isa','Stateflow.EMChart','Path',fn);
if isempty(charts)||numel(charts)~=1,error('[%s] EMChart missing: %s',dev,fn);end
low=lower(char(charts.Script));
for s={'persistent ','global ','coder.extrinsic','assignin(','evalin('}
    if contains(low,s{1}),error('[%s] hidden/dynamic construct in %s',dev,fn);end
end
end

function setMatlabFunctionScript(blockPath,scriptText)
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart','Path',blockPath);
if isempty(charts),error('Cannot locate EMChart: %s',blockPath);end
if numel(charts)~=1,error('Expected one EMChart: %s',blockPath);end
charts.Script=scriptText;
end

function deleteSpecificLine(parent,srcRel,dstRel)
try,delete_line(parent,srcRel,dstRel);
catch ME,error('Exact line delete failed %s -> %s | %s',srcRel,dstRel,ME.message);end
end

function x=topLevelMaxRight(sys)
b=find_system(sys,'SearchDepth',1,'Type','Block');b=b(~strcmp(b,sys));r=[];
for k=1:numel(b)
    try,p=get_param(b{k},'Position');if isnumeric(p)&&numel(p)==4,r(end+1)=p(3);end;catch,end %#ok<AGROW>
end
if isempty(r),x=1200;else,x=max(r);end
end

function tf=blockExists(p)
try,get_param(p,'Handle');tf=true;catch,tf=false;end
end
function requireBlock(p)
if ~blockExists(p),error('Required block missing: %s',p);end
end
function s=safeParam(b,p)
try
    v=get_param(b,p);
    if isnumeric(v),s=mat2str(v);
    elseif ischar(v),s=v;
    elseif isstring(v),s=char(v);
    else,s=char(string(v));end
catch,s='<N/A>';end
end
function f=firstExistingFile(c)
f='';
for k=1:numel(c)
    x=c{k};if isempty(x),continue;end
    if isstring(x),x=char(x);end;x=strtrim(x);
    if exist(x,'file')==2,f=x;return;end
    if ispc
        x2=strrep(x,'\','\\');
        if exist(x2,'file')==2,f=x2;return;end
    end
end
end
function h=fileSha256(fn)
f=fopen(fn,'rb');if f<0,error('Cannot open file for SHA.');end
c=onCleanup(@() fclose(f));b=fread(f,Inf,'*uint8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(b);
d=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(d,2).',1,[]));
end
function d=inportSourceDesc(b,n)
ph=get_param(b,'PortHandles');if numel(ph.Inport)<n,d='<NO>';return;end
l=get_param(ph.Inport(n),'Line');if isempty(l)||l==-1,d='<UNCONNECTED>';return;end
h=get_param(l,'SrcPortHandle');if isempty(h)||h==-1,d='<NO SOURCE>';return;end
d=sprintf('%s|out%d',get_param(h,'Parent'),get_param(h,'PortNumber'));
end
function assertSource(dst,i,src,o,label)
a=inportSourceDesc(dst,i);e=sprintf('%s|out%d',src,o);
if ~strcmp(a,e),error('%s source mismatch expected %s actual %s',label,e,a);end
end
function w=compiledWidths(b)
w=struct('Inport',[],'Outport',[]);
try
    x=get_param(b,'CompiledPortWidths');
    if isfield(x,'Inport'),w.Inport=x.Inport;end
    if isfield(x,'Outport'),w.Outport=x.Outport;end
catch
end
if isempty(w.Inport)||isempty(w.Outport)
    ph=get_param(b,'PortHandles');
    if isempty(w.Inport)&&~isempty(ph.Inport)
        a=zeros(1,numel(ph.Inport));
        for k=1:numel(ph.Inport),a(k)=get_param(ph.Inport(k),'CompiledPortWidth');end
        w.Inport=a;
    end
    if isempty(w.Outport)&&~isempty(ph.Outport)
        a=zeros(1,numel(ph.Outport));
        for k=1:numel(ph.Outport),a(k)=get_param(ph.Outport(k),'CompiledPortWidth');end
        w.Outport=a;
    end
end
end
function requireWidthAt(a,i,w,label)
if numel(a)<i||a(i)~=w,error('%s expected width%d got%s',label,w,mat2str(a));end
end
function requireWidthVec(a,w,label)
if ~isequal(a,w),error('%s expected%s got%s',label,mat2str(w),mat2str(a));end
end
function s=normalizeText(s)
s=strrep(char(s),sprintf('\r\n'),sprintf('\n'));
s=strrep(s,sprintf('\r'),sprintf('\n'));
s=strtrim(s);
end
function logf(fid,fmt,varargin)
s=sprintf(fmt,varargin{:});fprintf('%s\n',s);fprintf(fid,'%s\n',s);
end

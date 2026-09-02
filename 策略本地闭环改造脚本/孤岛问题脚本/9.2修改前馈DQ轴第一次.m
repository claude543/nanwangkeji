%% PATCH_K26_V5_VFF_DQ_SHAPER_MODE7_FUNCTION_V1_2.m
% K26_V5 - Mode7 dq terminal-voltage VFF slow/fast shaper
% FINAL IMPLEMENTATION: MATLAB Function Core + explicit Unit Delay states
%
% WHY THIS IMPLEMENTATION
% -----------------------
% - MATLAB Function blocks are allowed for this project/current platform.
% - Function is COMBINATIONAL ONLY: no persistent state.
% - All states remain explicit outside the function:
%       Vslow_z1  : Unit Delay, vector width2
%       Kfast_z1  : Unit Delay, scalar
% - Runtime-tunable values are top-level Constant blocks in each GFL
%   controller so RT-LAB parameter discovery has stable explicit paths.
% - Final exact bypass is a physical Simulink Switch OUTSIDE the Function:
%       Mode0..6 -> RawVdq
%       Mode7 before 8.1894s -> RawVdq
%       Mode7 after 8.1894s -> shaped Vdq
%
% ROOT SCOPE
% ----------
% The post-Mode6 read-only audit proved Current Regulator/in1 is used ONLY:
%   Vd -> Add1/in1 with '+'
%   Vq -> Add3/in1 with '+'
% i.e. only the dynamic terminal-voltage direct-feedforward terms.
%
% This patch DOES NOT change:
%   Current PI, Rff/Lff, P/Q loop, PLL, PWM, network, topology, ESS1 GFM.
%
% SHAPER CORE
% -----------
% Vslow_next = Vslow_z1 + alpha*(Vraw - Vslow_z1)
% Kfast_target =
%       Kfast_island, if Mode7 && HoldStep<0.5
%       1,            otherwise
% Kfast_next = bounded slew from Kfast_z1 toward target
% Vshaped = Vslow_next + Kfast_next*(Vraw - Vslow_next)
%
% First engineering run defaults:
%   fc = 1 Hz
%   alpha = 0.00062812117996513539
%   Kfast_island = 0
%   Kfast_slew_per_sample = 0.01
%
% diag26 preserved; append:
%   27 Vslow_d
%   28 Vslow_q
%   29 Kfast_eff
%   30 Kfast_target
%
% OpWrite:
%   G26/G27/G28/G29 Decimation 2->4
%   G30             Decimation 5->10
%   count remains exactly5
%
% CRITICAL EXECUTION ORDER
% ------------------------
% 1) This patch first compiles the exact shaper in a scratch model.
% 2) Only if scratch compile PASS does it edit K26_V5.
% 3) Real model compile PASS is required before save.
% 4) After save: close/reload/compile again.
% 5) Then run independent:
%       VERIFY_K26_V5_VFF_DQ_SHAPER_PREBUILD_FUNCTION_V1_2.m
% 6) Only after verifier PASS -> RT-LAB Rebuild All.

clearvars;
clc;

MODEL='K26_V5';
EXPECTED_SHA256='4812ad1f1acca23173576ee92a926ce8727dc65fa2b3ee62debcd5c44801d36b';

DEFAULT_ALPHA=0.00062812117996513539;
DEFAULT_KFAST_ISLAND=0.0;
DEFAULT_KFAST_SLEW=0.01;

STAMP=datestr(now,'yyyymmdd_HHMMSS');
LOG_FILE=['9.02_PATCH_K26_V5_VFF_DQ_SHAPER_FUNCTION_V1_2_' STAMP '.txt'];

fid=fopen(LOG_FILE,'w','n','UTF-8');
if fid<0,error('Cannot create patch log.');end
cleanupFid=onCleanup(@() fclose(fid));

logf(fid,repmat('=',1,156));
logf(fid,'K26_V5 MODE7 dq-VFF SHAPER — MATLAB FUNCTION CORE V1.2');
logf(fid,'[DEFAULT] alpha=%.17g KfastIsland=%.6f KfastSlew=%.6f/sample', ...
    DEFAULT_ALPHA,DEFAULT_KFAST_ISLAND,DEFAULT_KFAST_SLEW);
logf(fid,repmat('=',1,156));

%% 0. HARD INTERLOCKS
if ~bdIsLoaded(MODEL)
    error('PATCH ABORT: K26_V5 must already be open.');
end
if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('PATCH ABORT: K26_V5 Dirty=%s. Require audited disk model Dirty=off.',get_param(MODEL,'Dirty'));
end
if ~strcmpi(get_param(MODEL,'SimulationStatus'),'stopped')
    error('PATCH ABORT: model must be stopped.');
end

raw='';
try,raw=get_param(MODEL,'FileName');catch,end
modelFile=firstExistingFile({raw,which([MODEL '.slx']),which(MODEL),fullfile(pwd,[MODEL '.slx'])});
if isempty(modelFile),error('PATCH ABORT: cannot resolve current model file.');end

sha0=fileSha256(modelFile);
logf(fid,'[MODEL FILE] %s',modelFile);
logf(fid,'[SHA256 BEFORE] %s',sha0);
if ~strcmpi(sha0,EXPECTED_SHA256)
    error('PATCH ABORT: SHA mismatch. Expected %s actual %s.',EXPECTED_SHA256,sha0);
end
logf(fid,'[HASH PASS] exact audited post-Mode6 model.');

names={'PV1','PV2','ESS2','EV1','EV2'};
ctrls={ ...
    [MODEL '/SS_Slave3/PV1_Control'], ...
    [MODEL '/SS_Slave3/PV2_Control'], ...
    [MODEL '/SS_Slave2/ESS2_Control'], ...
    [MODEL '/SS_Slave/EV1_Control'], ...
    [MODEL '/SS_Slave/Control System'] ...
};

opNames={'G26','G27','G28','G29','G30'};
opPaths={ ...
    [MODEL '/SS_Slave/AA15_ROOTDIAG_EV12_OPWRITE_G26'], ...
    [MODEL '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'], ...
    [MODEL '/SS_Slave3/AA15_ROOTDIAG_PV12_OPWRITE_G28'], ...
    [MODEL '/SM_Master/AA15_FREQDIAG_SM_OPWRITE_G29'], ...
    [MODEL '/SS_Slave2/AA15_FREQDIAG_ESS1_OPWRITE_G30'] ...
};
oldDec={'2','2','2','2','5'};
newDec={'4','4','4','4','10'};

%% 1. SCRATCH MODEL: EXACT IMPLEMENTATION COMPILE BEFORE REAL EDIT
logf(fid,'\n--- 1. SCRATCH MATLAB-FUNCTION SHAPER COMPILE PREFLIGHT ---');
scratchCompilePreflight(DEFAULT_ALPHA,DEFAULT_KFAST_ISLAND,DEFAULT_KFAST_SLEW);
logf(fid,'[SCRATCH COMPILE PASS] MATLAB Function creation, script, ports, UnitDelay states and exact-bypass Switch all compile.');

%% 2. FULL BACKUP ONLY AFTER SCRATCH PASS
modelDir=fileparts(modelFile);
backupFile=fullfile(modelDir,['K26_V5__PRE_VFF_DQ_FUNCTION_V1_2_' STAMP '.slx']);
[ok,msg]=copyfile(modelFile,backupFile);
if ~ok,error('PATCH ABORT: backup failed: %s',msg);end
logf(fid,'[FULL BACKUP PASS] %s',backupFile);

savedToDisk=false;
patchSucceeded=false;

try
    %% 3. STRICT PREPATCH RE-AUDIT
    logf(fid,'\n--- 3. STRICT PREPATCH RE-AUDIT ---');
    for i=1:5
        dev=names{i};ctrl=ctrls{i};

        req={ ...
            ctrl, ...
            [ctrl '/AA15_CAUSAL_MODE'], ...
            [ctrl '/AA15_C_HOLD_STEP'], ...
            [ctrl '/AA15_C1_VDQ_TRACK_HOLD'], ...
            [ctrl '/AA15_C1_AXIS_TRACK_HOLD'], ...
            [ctrl '/AA15_C2_IREF_TRACK_HOLD'], ...
            [ctrl '/AA15_C1D_AXIS_TRACK_GATE'], ...
            [ctrl '/AA15_C1Q_AXIS_TRACK_GATE'], ...
            [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'], ...
            [ctrl '/Current Regulator'], ...
            [ctrl '/From26'] ...
        };
        for k=1:numel(req),requireBlock(req{k});end
        for mm=1:6
            requireBlock([ctrl sprintf('/AA15_MODE_CONST_%d',mm)]);
            requireBlock([ctrl sprintf('/AA15_MODE_EQ_%d',mm)]);
        end

        newNames={ ...
            'AA15_MODE_CONST_7','AA15_MODE_EQ_7','AA15_VFF_DQ_SHAPER', ...
            'AA15_VFF_SLOW_ALPHA','AA15_VFF_KFAST_ISLAND','AA15_VFF_KFAST_SLEW' ...
        };
        for k=1:numel(newNames)
            if blockExists([ctrl '/' newNames{k}])
                error('[%s] new-name collision: %s',dev,newNames{k});
            end
        end

        assertNum(safeParam([ctrl '/AA15_CAUSAL_MODE'],'Value'),0,[dev ' default mode']);
        assertNum(safeParam([ctrl '/AA15_C_HOLD_STEP'],'Time'),8.1894,[dev ' hold-step Time']);
        assertNum(safeParam([ctrl '/AA15_C_HOLD_STEP'],'Before'),1,[dev ' hold-step Before']);
        assertNum(safeParam([ctrl '/AA15_C_HOLD_STEP'],'After'),0,[dev ' hold-step After']);

        axis=[ctrl '/AA15_C1_AXIS_TRACK_HOLD'];
        cr=[ctrl '/Current Regulator'];
        lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        assertDestSet(axis,1,{portDesc(cr,1,'in'),portDesc(lg,5,'in')},[dev ' prepatch axis fanout']);
        assertSource(cr,1,axis,1,[dev ' prepatch CR source']);
        assertSource(lg,5,axis,1,[dev ' prepatch logger applied source']);

        if str2double(safeParam(lg,'Inputs'))~=19
            error('[%s] prepatch logger Inputs must be19.',dev);
        end
        if ~isCurrentRegIn1DirectOnly(cr)
            error('[%s] CurrentReg/in1 direct-only root-path proof failed.',dev);
        end

        logf(fid,'[PREPATCH PASS] %s',dev);
    end

    for k=1:5
        requireBlock(opPaths{k});
        if ~strcmp(strtrim(safeParam(opPaths{k},'Decimation')),oldDec{k})
            error('%s prepatch Decimation expected%s got%s',opNames{k},oldDec{k},safeParam(opPaths{k},'Decimation'));
        end
    end
    opw=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*');
    if numel(opw)~=5,error('Prepatch OpWrite count must be exactly5.');end

    %% 4. INSERT MODE7, PARAMETERS, FUNCTION SHAPER
    logf(fid,'\n--- 4. INSERT MODE7 + PARAMETER BLOCKS + FUNCTION SHAPER ---');
    for i=1:5
        dev=names{i};ctrl=ctrls{i};
        x0=topLevelMaxRight(ctrl)+120;
        y0=260;

        mode7=[ctrl '/AA15_MODE_CONST_7'];
        eq7=[ctrl '/AA15_MODE_EQ_7'];
        pAlpha=[ctrl '/AA15_VFF_SLOW_ALPHA'];
        pIsland=[ctrl '/AA15_VFF_KFAST_ISLAND'];
        pSlew=[ctrl '/AA15_VFF_KFAST_SLEW'];
        sh=[ctrl '/AA15_VFF_DQ_SHAPER'];

        add_block('built-in/Constant',mode7,'Value','7','Position',[x0 y0 x0+45 y0+26]);
        add_block('built-in/RelationalOperator',eq7,'Operator','==','Position',[x0+80 y0-3 x0+130 y0+31]);

        add_block('built-in/Constant',pAlpha,'Value',sprintf('%.17g',DEFAULT_ALPHA), ...
            'Position',[x0 y0+70 x0+90 y0+96]);
        add_block('built-in/Constant',pIsland,'Value',sprintf('%.17g',DEFAULT_KFAST_ISLAND), ...
            'Position',[x0 y0+115 x0+90 y0+141]);
        add_block('built-in/Constant',pSlew,'Value',sprintf('%.17g',DEFAULT_KFAST_SLEW), ...
            'Position',[x0 y0+160 x0+90 y0+186]);

        add_line(ctrl,'AA15_CAUSAL_MODE/1','AA15_MODE_EQ_7/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_CONST_7/1','AA15_MODE_EQ_7/2','autorouting','on');

        addFunctionShaperSubsystem(sh,[x0+230 y0-80 x0+530 y0+190]);

        axis=[ctrl '/AA15_C1_AXIS_TRACK_HOLD'];
        cr=[ctrl '/Current Regulator'];
        lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        deleteSpecificLine(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','Current Regulator/1');
        deleteSpecificLine(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5');

        % shaper inputs:
        % 1 RawVdq, 2 Mode7Enable, 3 HoldStep, 4 alpha, 5 KfastIsland, 6 KfastSlew
        add_line(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','AA15_VFF_DQ_SHAPER/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_EQ_7/1','AA15_VFF_DQ_SHAPER/2','autorouting','on');
        add_line(ctrl,'AA15_C_HOLD_STEP/1','AA15_VFF_DQ_SHAPER/3','autorouting','on');
        add_line(ctrl,'AA15_VFF_SLOW_ALPHA/1','AA15_VFF_DQ_SHAPER/4','autorouting','on');
        add_line(ctrl,'AA15_VFF_KFAST_ISLAND/1','AA15_VFF_DQ_SHAPER/5','autorouting','on');
        add_line(ctrl,'AA15_VFF_KFAST_SLEW/1','AA15_VFF_DQ_SHAPER/6','autorouting','on');

        add_line(ctrl,'AA15_VFF_DQ_SHAPER/1','Current Regulator/1','autorouting','on');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5','autorouting','on');

        % diag26 -> diag30
        set_param(lg,'Inputs','22');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/2','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/20','autorouting','on');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/3','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/21','autorouting','on');
        add_line(ctrl,'AA15_VFF_DQ_SHAPER/4','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/22','autorouting','on');

        logf(fid,'[INSERT PASS] %s',dev);
    end

    %% 5. EXTEND DATA COVERAGE
    logf(fid,'\n--- 5. OPWRITE DECIMATION FOR >=0.5s POST-J1 COVERAGE ---');
    for k=1:5
        set_param(opPaths{k},'Decimation',newDec{k});
        if ~strcmp(strtrim(safeParam(opPaths{k},'Decimation')),newDec{k})
            error('%s Decimation write/readback failed.',opNames{k});
        end
        logf(fid,'[%s] Decimation %s -> %s',opNames{k},oldDec{k},newDec{k});
    end

    %% 6. EXACT STRUCTURAL/ALGORITHM POSTASSERT
    logf(fid,'\n--- 6. EXACT STRUCTURAL / ALGORITHM POSTASSERT ---');
    for i=1:5
        dev=names{i};ctrl=ctrls{i};
        sh=[ctrl '/AA15_VFF_DQ_SHAPER'];
        eq7=[ctrl '/AA15_MODE_EQ_7'];
        axis=[ctrl '/AA15_C1_AXIS_TRACK_HOLD'];
        cr=[ctrl '/Current Regulator'];
        lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        assertNum(safeParam([ctrl '/AA15_MODE_CONST_7'],'Value'),7,[dev ' Mode7 constant']);
        assertNum(safeParam([ctrl '/AA15_VFF_SLOW_ALPHA'],'Value'),DEFAULT_ALPHA,[dev ' alpha']);
        assertNum(safeParam([ctrl '/AA15_VFF_KFAST_ISLAND'],'Value'),DEFAULT_KFAST_ISLAND,[dev ' KfastIsland']);
        assertNum(safeParam([ctrl '/AA15_VFF_KFAST_SLEW'],'Value'),DEFAULT_KFAST_SLEW,[dev ' KfastSlew']);

        assertSource(eq7,1,[ctrl '/AA15_CAUSAL_MODE'],1,[dev ' Eq7 mode']);
        assertSource(eq7,2,[ctrl '/AA15_MODE_CONST_7'],1,[dev ' Eq7 const']);
        assertDestSet(eq7,1,{portDesc(sh,2,'in')},[dev ' Eq7 sole dest']);

        assertDestSet(axis,1,{portDesc(sh,1,'in')},[dev ' axis sole dest']);
        assertSource(sh,1,axis,1,[dev ' raw input']);
        assertSource(sh,2,eq7,1,[dev ' mode input']);
        assertSource(sh,3,[ctrl '/AA15_C_HOLD_STEP'],1,[dev ' hold input']);
        assertSource(sh,4,[ctrl '/AA15_VFF_SLOW_ALPHA'],1,[dev ' alpha input']);
        assertSource(sh,5,[ctrl '/AA15_VFF_KFAST_ISLAND'],1,[dev ' island input']);
        assertSource(sh,6,[ctrl '/AA15_VFF_KFAST_SLEW'],1,[dev ' slew input']);

        assertDestSet(sh,1,{portDesc(cr,1,'in'),portDesc(lg,5,'in')},[dev ' final output dest']);
        assertSource(cr,1,sh,1,[dev ' CR final source']);
        assertSource(lg,5,sh,1,[dev ' logger final source']);
        assertSource(lg,20,sh,2,[dev ' logger Vslow']);
        assertSource(lg,21,sh,3,[dev ' logger KfastEff']);
        assertSource(lg,22,sh,4,[dev ' logger KfastTarget']);

        if str2double(safeParam(lg,'Inputs'))~=22
            error('[%s] logger Inputs must be22.',dev);
        end

        verifyFunctionShaper(sh,dev);

        if ~isCurrentRegIn1DirectOnly(cr)
            error('[%s] CurrentReg internal root path changed.',dev);
        end

        logf(fid,'[POSTASSERT PASS] %s',dev);
    end

    %% 7. REAL MODEL COMPILE BEFORE SAVE
    logf(fid,'\n--- 7. REAL MODEL COMPILE BEFORE SAVE ---');
    compiled=false;
    try
        feval(MODEL,[],[],[],'compile');
        compiled=true;
        logf(fid,'[COMPILE ENTER PASS]');

        for i=1:5
            dev=names{i};ctrl=ctrls{i};
            ws=compiledWidths([ctrl '/AA15_VFF_DQ_SHAPER']);
            wl=compiledWidths([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR']);
            wc=compiledWidths([ctrl '/Current Regulator']);
            logf(fid,'[%s] shaper in=%s out=%s logger=%s CRin=%s', ...
                dev,mat2str(ws.Inport),mat2str(ws.Outport),mat2str(wl.Outport),mat2str(wc.Inport));

            requireWidthVec(ws.Inport,[2 1 1 1 1 1],[dev ' shaper input widths']);
            requireWidthVec(ws.Outport,[2 2 1 1],[dev ' shaper output widths']);
            requireWidthAt(wl.Outport,1,30,[dev ' diag30']);
            requireWidthAt(wc.Inport,1,2,[dev ' CurrentReg/in1']);
        end

        expectedW=[60 30 60 38 115];
        for k=1:5
            w=compiledWidths(opPaths{k});
            requireWidthAt(w.Inport,1,expectedW(k),[opNames{k} ' input width']);
            logf(fid,'[%s] width=%s Decimation=%s',opNames{k},mat2str(w.Inport),safeParam(opPaths{k},'Decimation'));
        end

        opw=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','.*OPWRITE.*');
        if numel(opw)~=5,error('Postpatch OpWrite count must remain exactly5.');end

    catch MEc
        if compiled
            try,feval(MODEL,[],[],[],'term');catch,end
        end
        rethrow(MEc);
    end
    if compiled
        feval(MODEL,[],[],[],'term');
        logf(fid,'[COMPILE TERM PASS]');
    end

    %% 8. SAVE ONLY AFTER ALL PRE-SAVE CHECKS PASS
    logf(fid,'\n--- 8. SAVE ---');
    for i=1:5
        set_param([ctrls{i} '/AA15_CAUSAL_MODE'],'Value','0');
    end
    save_system(MODEL);
    savedToDisk=true;
    sha1=fileSha256(modelFile);
    logf(fid,'[SAVE PASS]');
    logf(fid,'[SHA256 AFTER] %s',sha1);

    %% 9. CLOSE/RELOAD/PERSISTENCE COMPILE
    logf(fid,'\n--- 9. CLOSE / RELOAD / PERSISTENCE VERIFY ---');
    close_system(MODEL,0);
    load_system(modelFile);

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Reloaded model Dirty is not off.');
    end

    for i=1:5
        dev=names{i};ctrl=ctrls{i};sh=[ctrl '/AA15_VFF_DQ_SHAPER'];
        lg=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        requireBlock([ctrl '/AA15_MODE_CONST_7']);
        requireBlock([ctrl '/AA15_MODE_EQ_7']);
        requireBlock([ctrl '/AA15_VFF_SLOW_ALPHA']);
        requireBlock([ctrl '/AA15_VFF_KFAST_ISLAND']);
        requireBlock([ctrl '/AA15_VFF_KFAST_SLEW']);
        requireBlock(sh);

        assertNum(safeParam([ctrl '/AA15_CAUSAL_MODE'],'Value'),0,[dev ' persisted Mode0']);
        assertSource([ctrl '/Current Regulator'],1,sh,1,[dev ' persisted CR source']);
        assertSource(lg,5,sh,1,[dev ' persisted final logger']);
        assertSource(lg,20,sh,2,[dev ' persisted Vslow']);
        assertSource(lg,21,sh,3,[dev ' persisted KfastEff']);
        assertSource(lg,22,sh,4,[dev ' persisted KfastTarget']);

        verifyFunctionShaper(sh,dev);
    end

    for k=1:5
        if ~strcmp(strtrim(safeParam(opPaths{k},'Decimation')),newDec{k})
            error('%s persisted Decimation mismatch.',opNames{k});
        end
    end

    compiled2=false;
    try
        feval(MODEL,[],[],[],'compile');
        compiled2=true;
        expectedW=[60 30 60 38 115];

        for i=1:5
            ws=compiledWidths([ctrls{i} '/AA15_VFF_DQ_SHAPER']);
            wl=compiledWidths([ctrls{i} '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR']);
            requireWidthVec(ws.Inport,[2 1 1 1 1 1],[names{i} ' persisted shaper input']);
            requireWidthVec(ws.Outport,[2 2 1 1],[names{i} ' persisted shaper output']);
            requireWidthAt(wl.Outport,1,30,[names{i} ' persisted diag30']);
        end
        for k=1:5
            w=compiledWidths(opPaths{k});
            requireWidthAt(w.Inport,1,expectedW(k),[opNames{k} ' persisted width']);
        end
        logf(fid,'[PERSISTENCE COMPILE PASS]');
    catch ME2
        if compiled2
            try,feval(MODEL,[],[],[],'term');catch,end
        end
        rethrow(ME2);
    end
    if compiled2,feval(MODEL,[],[],[],'term');end

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Final model Dirty is not off.');
    end

    patchSucceeded=true;

    logf(fid,'\n--- 10. FINAL CONTRACT ---');
    logf(fid,'[Mode0..6] external Switch exact raw bypass.');
    logf(fid,'[Mode7 pre-8.1894] exact raw bypass; Vslow/Kfast states warm continuously.');
    logf(fid,'[Mode7 post-8.1894] shaped path selected.');
    logf(fid,'[Runtime parameter paths] per GFL: AA15_VFF_SLOW_ALPHA, AA15_VFF_KFAST_ISLAND, AA15_VFF_KFAST_SLEW.');
    logf(fid,'[diag30] 27/28=Vslow_d/q 29=Kfast_eff 30=Kfast_target.');
    logf(fid,'[OpWrite] exactly5 Decimation=4/4/4/4/10.');
    logf(fid,'[NEXT] Run independent FUNCTION V1.2 prebuild verifier. Do not Build yet.');

    logf(fid,'\n%s',repmat('=',1,156));
    logf(fid,'PATCH PASS');
    logf(fid,'Backup: %s',backupFile);
    logf(fid,'Current: %s',modelFile);
    logf(fid,'%s',repmat('=',1,156));

catch ME
    logf(fid,'\n%s',repmat('!',1,156));
    logf(fid,'PATCH FAILURE');
    logf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));

    try,feval(MODEL,[],[],[],'term');catch,end
    try
        if bdIsLoaded(MODEL),close_system(MODEL,0);end
    catch
    end

    if savedToDisk
        try
            [okr,msgr]=copyfile(backupFile,modelFile,'f');
            if okr
                logf(fid,'[ROLLBACK DISK PASS] audited prepatch model restored.');
            else
                logf(fid,'[ROLLBACK DISK FAIL] %s',msgr);
            end
        catch MEr
            logf(fid,'[ROLLBACK EXCEPTION] %s',MEr.message);
        end
    else
        logf(fid,'[ROLLBACK] save_system had not occurred; audited disk model unchanged.');
    end

    try
        load_system(modelFile);
        logf(fid,'[ROLLBACK RELOAD] model reloaded.');
    catch MEr2
        logf(fid,'[ROLLBACK RELOAD WARN] %s',MEr2.message);
    end
    logf(fid,'%s',repmat('!',1,156));
    rethrow(ME);
end

if patchSucceeded
    fprintf('\nPATCH PASS.\nLog: %s\nBackup: %s\n',LOG_FILE,backupFile);
    fprintf('DO NOT BUILD YET. Run VERIFY_K26_V5_VFF_DQ_SHAPER_PREBUILD_FUNCTION_V1_2.m.\n');
end

%% =========================================================================
%% Scratch preflight
%% =========================================================================
function scratchCompilePreflight(alpha0,k0,slew0)
    tmp=matlab.lang.makeValidName(['AA15_VFF_FUNC_PREFLIGHT_' datestr(now,'HHMMSSFFF')]);
    new_system(tmp);
    c=onCleanup(@() closeScratch(tmp));

    set_param(tmp,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','0.0001');
    mw=get_param(tmp,'ModelWorkspace');
    assignin(mw,'Ts',0.0001);

    sh=[tmp '/AA15_VFF_DQ_SHAPER'];
    addFunctionShaperSubsystem(sh,[300 100 620 380]);

    add_block('built-in/Constant',[tmp '/Raw'],'Value','[1;0]','Position',[40 80 100 110]);
    add_block('built-in/Constant',[tmp '/Mode'],'Value','0','Position',[40 130 100 160]);
    add_block('built-in/Constant',[tmp '/Hold'],'Value','1','Position',[40 180 100 210]);
    add_block('built-in/Constant',[tmp '/Alpha'],'Value',sprintf('%.17g',alpha0),'Position',[40 230 100 260]);
    add_block('built-in/Constant',[tmp '/KIsland'],'Value',sprintf('%.17g',k0),'Position',[40 280 100 310]);
    add_block('built-in/Constant',[tmp '/Slew'],'Value',sprintf('%.17g',slew0),'Position',[40 330 100 360]);

    add_line(tmp,'Raw/1','AA15_VFF_DQ_SHAPER/1','autorouting','on');
    add_line(tmp,'Mode/1','AA15_VFF_DQ_SHAPER/2','autorouting','on');
    add_line(tmp,'Hold/1','AA15_VFF_DQ_SHAPER/3','autorouting','on');
    add_line(tmp,'Alpha/1','AA15_VFF_DQ_SHAPER/4','autorouting','on');
    add_line(tmp,'KIsland/1','AA15_VFF_DQ_SHAPER/5','autorouting','on');
    add_line(tmp,'Slew/1','AA15_VFF_DQ_SHAPER/6','autorouting','on');

    for k=1:4
        add_block('built-in/Terminator',[tmp sprintf('/Term%d',k)], ...
            'Position',[700 70+60*k 720 90+60*k]);
        add_line(tmp,sprintf('AA15_VFF_DQ_SHAPER/%d',k),sprintf('Term%d/1',k),'autorouting','on');
    end

    compiled=false;
    try
        feval(tmp,[],[],[],'compile');
        compiled=true;
    catch ME
        if compiled
            try,feval(tmp,[],[],[],'term');catch,end
        end
        rethrow(ME);
    end
    if compiled,feval(tmp,[],[],[],'term');end

    ws=compiledWidthsAfterUpdate(tmp,sh);
    if ~isequal(ws.Inport,[2 1 1 1 1 1]) || ~isequal(ws.Outport,[2 2 1 1])
        error('Scratch shaper width contract failed: in=%s out=%s',mat2str(ws.Inport),mat2str(ws.Outport));
    end
end

function closeScratch(tmp)
    try
        if bdIsLoaded(tmp),close_system(tmp,0);end
    catch
    end
end

%% =========================================================================
%% Shaper subsystem
%% =========================================================================
function addFunctionShaperSubsystem(sub,pos)
    add_block('built-in/SubSystem',sub,'Position',pos);

    % 6 inputs
    add_block('built-in/Inport',[sub '/RawVdq'],'Port','1','Position',[20 35 50 49]);
    add_block('built-in/Inport',[sub '/Mode7Enable'],'Port','2','Position',[20 80 50 94]);
    add_block('built-in/Inport',[sub '/HoldStep'],'Port','3','Position',[20 120 50 134]);
    add_block('built-in/Inport',[sub '/Alpha'],'Port','4','Position',[20 160 50 174]);
    add_block('built-in/Inport',[sub '/KfastIsland'],'Port','5','Position',[20 200 50 214]);
    add_block('built-in/Inport',[sub '/KfastSlew'],'Port','6','Position',[20 240 50 254]);

    % explicit states
    add_block('built-in/UnitDelay',[sub '/AA15_VFF_SLOW_STATE'], ...
        'InitialCondition','[0;0]','SampleTime','Ts','Position',[100 300 155 335]);
    add_block('built-in/UnitDelay',[sub '/AA15_VFF_KFAST_STATE'], ...
        'InitialCondition','1','SampleTime','Ts','Position',[100 350 155 385]);

    % direct MATLAB Function block
    fn=[sub '/AA15_VFF_CORE'];
    add_block('simulink/User-Defined Functions/MATLAB Function',fn, ...
        'Position',[245 80 455 285]);
    setMatlabFunctionScript(fn,vffCoreScript());

    % exact-bypass switch outside function
    add_block('built-in/Switch',[sub '/AA15_VFF_FINAL_SWITCH'], ...
        'Criteria','u2 > Threshold','Threshold','0.5','Position',[515 75 575 135]);

    % 4 outputs
    add_block('built-in/Outport',[sub '/FinalVdq'],'Port','1','Position',[640 90 670 104]);
    add_block('built-in/Outport',[sub '/Vslow'],'Port','2','Position',[640 180 670 194]);
    add_block('built-in/Outport',[sub '/Kfast_eff'],'Port','3','Position',[640 225 670 239]);
    add_block('built-in/Outport',[sub '/Kfast_target'],'Port','4','Position',[640 270 670 284]);

    % MATLAB Function inputs:
    % 1 raw, 2 vslow_z1, 3 kfast_z1, 4 mode7, 5 hold, 6 alpha, 7 island, 8 slew
    add_line(sub,'RawVdq/1','AA15_VFF_CORE/1','autorouting','on');
    add_line(sub,'AA15_VFF_SLOW_STATE/1','AA15_VFF_CORE/2','autorouting','on');
    add_line(sub,'AA15_VFF_KFAST_STATE/1','AA15_VFF_CORE/3','autorouting','on');
    add_line(sub,'Mode7Enable/1','AA15_VFF_CORE/4','autorouting','on');
    add_line(sub,'HoldStep/1','AA15_VFF_CORE/5','autorouting','on');
    add_line(sub,'Alpha/1','AA15_VFF_CORE/6','autorouting','on');
    add_line(sub,'KfastIsland/1','AA15_VFF_CORE/7','autorouting','on');
    add_line(sub,'KfastSlew/1','AA15_VFF_CORE/8','autorouting','on');

    % Function outputs:
    % 1 shaped, 2 vslow_next, 3 kfast_next, 4 target, 5 active
    add_line(sub,'AA15_VFF_CORE/2','AA15_VFF_SLOW_STATE/1','autorouting','on');
    add_line(sub,'AA15_VFF_CORE/3','AA15_VFF_KFAST_STATE/1','autorouting','on');

    % exact bypass
    add_line(sub,'AA15_VFF_CORE/1','AA15_VFF_FINAL_SWITCH/1','autorouting','on');
    add_line(sub,'AA15_VFF_CORE/5','AA15_VFF_FINAL_SWITCH/2','autorouting','on');
    add_line(sub,'RawVdq/1','AA15_VFF_FINAL_SWITCH/3','autorouting','on');

    add_line(sub,'AA15_VFF_FINAL_SWITCH/1','FinalVdq/1','autorouting','on');
    add_line(sub,'AA15_VFF_CORE/2','Vslow/1','autorouting','on');
    add_line(sub,'AA15_VFF_CORE/3','Kfast_eff/1','autorouting','on');
    add_line(sub,'AA15_VFF_CORE/4','Kfast_target/1','autorouting','on');
end

function s=vffCoreScript()
    s=sprintf([ ...
'function [vshaped, vslow_next, kfast_next, kfast_target, shape_active] = fcn(raw_vdq, vslow_z1, kfast_z1, mode7_enable, hold_step, alpha, kfast_island, kfast_slew)\n' ...
'%%#codegen\n' ...
'\n' ...
'%% Clamp runtime design parameters to safe ranges.\n' ...
'alpha_eff = min(max(alpha, 0.0), 1.0);\n' ...
'k_island  = min(max(kfast_island, 0.0), 1.0);\n' ...
'slew      = abs(kfast_slew);\n' ...
'\n' ...
'%% Slow terminal-voltage tracker. State itself lives in external Unit Delay.\n' ...
'vslow_next = vslow_z1 + alpha_eff .* (raw_vdq - vslow_z1);\n' ...
'\n' ...
'%% Shaper becomes active only for Mode7 after the established intervention edge.\n' ...
'shape_active = (mode7_enable > 0.5) && (hold_step < 0.5);\n' ...
'if shape_active\n' ...
'    kfast_target = k_island;\n' ...
'else\n' ...
'    kfast_target = 1.0;\n' ...
'end\n' ...
'\n' ...
'%% Slew Kfast without hidden state.\n' ...
'delta = kfast_target - kfast_z1;\n' ...
'if delta > slew\n' ...
'    delta_lim = slew;\n' ...
'elseif delta < -slew\n' ...
'    delta_lim = -slew;\n' ...
'else\n' ...
'    delta_lim = delta;\n' ...
'end\n' ...
'kfast_next = min(max(kfast_z1 + delta_lim, 0.0), 1.0);\n' ...
'\n' ...
'%% Slow/fast split: DC/slow gain remains unity; fast gain tends to Kfast.\n' ...
'vshaped = vslow_next + kfast_next .* (raw_vdq - vslow_next);\n' ...
'end\n' ...
    ]);
end

function setMatlabFunctionScript(blockPath,scriptText)
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart','Path',blockPath);
    if isempty(charts)
        error('Cannot locate Stateflow.EMChart for MATLAB Function block: %s',blockPath);
    end
    if numel(charts)~=1
        error('Expected exactly one EMChart for %s, got %d.',blockPath,numel(charts));
    end
    charts.Script=scriptText;
end

function verifyFunctionShaper(sh,dev)
    req={ ...
        [sh '/RawVdq'],[sh '/Mode7Enable'],[sh '/HoldStep'], ...
        [sh '/Alpha'],[sh '/KfastIsland'],[sh '/KfastSlew'], ...
        [sh '/AA15_VFF_SLOW_STATE'],[sh '/AA15_VFF_KFAST_STATE'], ...
        [sh '/AA15_VFF_CORE'],[sh '/AA15_VFF_FINAL_SWITCH'], ...
        [sh '/FinalVdq'],[sh '/Vslow'],[sh '/Kfast_eff'],[sh '/Kfast_target'] ...
    };
    for k=1:numel(req),requireBlock(req{k});end

    assertNum(safeParam([sh '/AA15_VFF_SLOW_STATE'],'InitialCondition'),0,[dev ' slow IC scalar-equivalence']);
    assertNum(safeParam([sh '/AA15_VFF_KFAST_STATE'],'InitialCondition'),1,[dev ' Kfast IC']);
    if ~strcmp(safeParam([sh '/AA15_VFF_SLOW_STATE'],'SampleTime'),'Ts') || ...
       ~strcmp(safeParam([sh '/AA15_VFF_KFAST_STATE'],'SampleTime'),'Ts')
        error('[%s] shaper UnitDelay sample time must be Ts.',dev);
    end

    % Core input wiring
    core=[sh '/AA15_VFF_CORE'];
    assertSource(core,1,[sh '/RawVdq'],1,[dev ' core raw']);
    assertSource(core,2,[sh '/AA15_VFF_SLOW_STATE'],1,[dev ' core slow state']);
    assertSource(core,3,[sh '/AA15_VFF_KFAST_STATE'],1,[dev ' core Kfast state']);
    assertSource(core,4,[sh '/Mode7Enable'],1,[dev ' core mode']);
    assertSource(core,5,[sh '/HoldStep'],1,[dev ' core hold']);
    assertSource(core,6,[sh '/Alpha'],1,[dev ' core alpha']);
    assertSource(core,7,[sh '/KfastIsland'],1,[dev ' core island']);
    assertSource(core,8,[sh '/KfastSlew'],1,[dev ' core slew']);

    % Explicit state feedback
    assertSource([sh '/AA15_VFF_SLOW_STATE'],1,core,2,[dev ' slow state feedback']);
    assertSource([sh '/AA15_VFF_KFAST_STATE'],1,core,3,[dev ' Kfast state feedback']);

    % Exact bypass switch outside Function
    assertSource([sh '/AA15_VFF_FINAL_SWITCH'],1,core,1,[dev ' switch shaped']);
    assertSource([sh '/AA15_VFF_FINAL_SWITCH'],2,core,5,[dev ' switch active']);
    assertSource([sh '/AA15_VFF_FINAL_SWITCH'],3,[sh '/RawVdq'],1,[dev ' switch exact raw bypass']);

    assertSource([sh '/FinalVdq'],1,[sh '/AA15_VFF_FINAL_SWITCH'],1,[dev ' final output']);
    assertSource([sh '/Vslow'],1,core,2,[dev ' Vslow output']);
    assertSource([sh '/Kfast_eff'],1,core,3,[dev ' Kfast output']);
    assertSource([sh '/Kfast_target'],1,core,4,[dev ' target output']);

    % Exact MATLAB Function source contract
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart','Path',core);
    if isempty(charts)||numel(charts)~=1
        error('[%s] MATLAB Function EMChart not uniquely found.',dev);
    end
    actual=normalizeText(charts.Script);
    expected=normalizeText(vffCoreScript());
    if ~strcmp(actual,expected)
        error('[%s] MATLAB Function script differs from frozen V1.2 algorithm.',dev);
    end
end

function s=normalizeText(s)
    s=strrep(char(s),sprintf('\r\n'),sprintf('\n'));
    s=strrep(s,sprintf('\r'),sprintf('\n'));
    s=strtrim(s);
end

%% =========================================================================
%% Existing root-path proof
%% =========================================================================
function tf=isCurrentRegIn1DirectOnly(cr)
    tf=false;
    ins=find_system(cr,'SearchDepth',1,'BlockType','Inport');
    in1='';
    for k=1:numel(ins)
        if numEq(safeParam(ins{k},'Port'),1),in1=ins{k};break;end
    end
    if isempty(in1),return;end
    ds=outportDestDescs(in1,1);
    if numel(ds)~=1,return;end
    z=split(ds{1},'|in');
    dm=z{1};
    if ~strcmpi(get_param(dm,'BlockType'),'Demux'),return;end
    ph=get_param(dm,'PortHandles');
    if numel(ph.Outport)~=2,return;end
    for ax=1:2
        d=outportDestDetails(dm,ax);
        if numel(d.blocks)~=1,return;end
        sb=d.blocks{1};
        if ~strcmpi(get_param(sb,'BlockType'),'Sum'),return;end
        if ~strcmp(sumSignAt(safeParam(sb,'Inputs'),d.inports(1)),'+'),return;end
    end
    tf=true;
end

%% =========================================================================
%% Generic helpers
%% =========================================================================
function deleteSpecificLine(parent,srcRel,dstRel)
    try,delete_line(parent,srcRel,dstRel);
    catch ME,error('Exact branch delete failed %s -> %s | %s',srcRel,dstRel,ME.message);end
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
        else,s=char(string(v));
        end
    catch,s='<N/A>';end
end
function assertNum(s,w,label)
    v=str2double(strtrim(s));
    % Allow scalar 0 equivalence for IC '[0;0]' only via explicit fallback.
    if ~isfinite(v)
        if w==0 && (strcmp(strtrim(s),'[0;0]') || strcmp(strtrim(s),'[0 0]'))
            return;
        end
        error('%s expected %.17g got %s',label,w,s);
    end
    if abs(v-w)>max(1e-12,1e-10*max(1,abs(w)))
        error('%s expected %.17g got %s',label,w,s);
    end
end
function tf=numEq(s,w)
    v=str2double(strtrim(s));tf=isfinite(v)&&abs(v-w)<=1e-12;
end
function logf(fid,fmt,varargin)
    s=sprintf(fmt,varargin{:});fprintf('%s\n',s);fprintf(fid,'%s\n',s);
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
    f=fopen(fn,'rb');if f<0,error('Cannot open file for SHA256.');end
    c=onCleanup(@() fclose(f));b=fread(f,Inf,'*uint8');
    md=java.security.MessageDigest.getInstance('SHA-256');md.update(b);
    d=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(d,2).',1,[]));
end
function d=portDesc(b,n,k)
    if strcmpi(k,'in'),d=sprintf('%s|in%d',b,n);else,d=sprintf('%s|out%d',b,n);end
end
function d=inportSourceDesc(b,n)
    ph=get_param(b,'PortHandles');if numel(ph.Inport)<n,d='<NO>';return;end
    l=get_param(ph.Inport(n),'Line');if isempty(l)||l==-1,d='<UNCONNECTED>';return;end
    h=get_param(l,'SrcPortHandle');if isempty(h)||h==-1,d='<NO SOURCE>';return;end
    d=sprintf('%s|out%d',get_param(h,'Parent'),get_param(h,'PortNumber'));
end
function ds=outportDestDescs(b,n)
    ph=get_param(b,'PortHandles');ds={};if numel(ph.Outport)<n,return;end
    l=get_param(ph.Outport(n),'Line');if isempty(l)||l==-1,return;end
    h=get_param(l,'DstPortHandle');if isempty(h),return;end
    h=h(:)';
    for q=h
        if q==-1,continue;end
        ds{end+1}=sprintf('%s|in%d',get_param(q,'Parent'),get_param(q,'PortNumber')); %#ok<AGROW>
    end
    ds=unique(ds);
end
function assertSource(dst,i,src,o,label)
    a=inportSourceDesc(dst,i);e=portDesc(src,o,'out');
    if ~strcmp(a,e),error('%s source mismatch expected %s actual %s',label,e,a);end
end
function assertDestSet(src,o,e,label)
    a=sort(outportDestDescs(src,o));e=sort(e);
    if ~isequal(a,e),error('%s destination mismatch.',label);end
end
function d=outportDestDetails(b,n)
    d=struct('blocks',{{}},'inports',[]);
    ph=get_param(b,'PortHandles');if numel(ph.Outport)<n,return;end
    l=get_param(ph.Outport(n),'Line');if isempty(l)||l==-1,return;end
    h=get_param(l,'DstPortHandle');if isempty(h),return;end
    h=h(:)';
    for q=h
        if q==-1,continue;end
        d.blocks{end+1}=get_param(q,'Parent');d.inports(end+1)=get_param(q,'PortNumber'); %#ok<AGROW>
    end
end
function s=sumSignAt(inp,n)
    c=char(inp);c=c(c=='+'|c=='-');
    if n>=1&&n<=numel(c),s=c(n);else,s='?';end
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
        try
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
        catch
        end
    end
end
function w=compiledWidthsAfterUpdate(mdl,b)
    compiled=false;
    try
        feval(mdl,[],[],[],'compile');compiled=true;
        w=compiledWidths(b);
    catch ME
        if compiled,try,feval(mdl,[],[],[],'term');catch,end,end
        rethrow(ME);
    end
    if compiled,feval(mdl,[],[],[],'term');end
end
function requireWidthAt(a,i,w,label)
    if numel(a)<i||a(i)~=w,error('%s expected width%d got%s',label,w,mat2str(a));end
end
function requireWidthVec(a,w,label)
    if ~isequal(a,w),error('%s expected%s got%s',label,mat2str(w),mat2str(a));end
end

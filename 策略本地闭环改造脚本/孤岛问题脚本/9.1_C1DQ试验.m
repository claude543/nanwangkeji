%% PATCH_K26_V5_C1_AXIS_QD_CAUSAL_V1_1.m
% K26_V5 - C1 axis-split causal harness V1.1
%
% SCIENTIFIC PURPOSE
% ------------------
% Existing evidence:
%   B1: native PLL active-frame dynamics removed -> low-frequency positive-growth mode remains.
%   C1: dynamic VdVq direct feedforward removed -> original mode is strongly suppressed.
%   C2: dynamic applied IdIq_ref removed -> positive-growth mode remains (~17.17 Hz, sigma~+25.33/s).
%
% This patch DOES NOT implement an engineering fix.
% It only adds two minimal orthogonal diagnostic modes:
%
%   Mode5 = C1-Q
%       old C1 vector path = TRACK
%       C2 = TRACK
%       d-axis direct Vd = TRACK
%       q-axis direct Vq = TRACK -> HOLD at 8.1894 s
%
%   Mode6 = C1-D
%       old C1 vector path = TRACK
%       C2 = TRACK
%       d-axis direct Vd = TRACK -> HOLD at 8.1894 s
%       q-axis direct Vq = TRACK
%
% CRITICAL DESIGN RULES
% ---------------------
% 1) Preserve existing AA15_C1_VDQ_TRACK_HOLD unchanged.
% 2) Preserve existing Mode0..4 semantics unchanged.
% 3) Insert NEW AA15_C1_AXIS_TRACK_HOLD downstream of old C1 and upstream
%    of Current Regulator/in1.
% 4) Causal logger scalar01..24 semantics remain unchanged.
%    Append:
%       scalar25 = C1_D_AXIS_TRACK_ENABLE
%       scalar26 = C1_Q_AXIS_TRACK_ENABLE
% 5) No change to PLL, P/Q loop, Current PI, Rff/Lff, PWM, network,
%    ESS1 F21/F22/F24/F25, OpWrite count, or physical topology.
% 6) Do NOT modify slow-slip control. Existing passive diagnostics remain.
%
% SAFETY / TRANSACTION
% --------------------
% - Requires the exact model hash audited on 2026-09-01:
%   5a154a99eb4d6877d0a9b70edc5810676bf3b62e3d391cc4748f51a416a611ec
% - Requires K26_V5 already loaded, Dirty=off, SimulationStatus=stopped.
% - Creates a full .slx backup BEFORE any edit.
% - Performs structural assertions + explicit compile BEFORE save.
% - Saves only after all pre-save assertions pass.
% - Closes/reloads and performs persistence assertions.
% - On any failure after save, restores the backup automatically.
%
% AFTER SUCCESS
% -------------
% DO NOT manually edit AA15_CAUSAL_MODE.
% RT-LAB -> Rebuild All.
% Do not Execute a diagnostic run until the Build result is reviewed.

clearvars;
clc;

MODEL = 'K26_V5';
EXPECTED_SHA256 = '5a154a99eb4d6877d0a9b70edc5810676bf3b62e3d391cc4748f51a416a611ec';
PATCH_VERSION = 'C1_AXIS_QD_CAUSAL_V1_1_20260901';
AUDITED_MODEL_FILE = 'D:\\Users\\linjj\\OPAL-RT\\RT-LABv2024.1_Workspace\\yanshou_V5\\models\\K26_V5\\K26_V5.slx';
STAMP = datestr(now,'yyyymmdd_HHMMSS');
LOG_FILE = ['9.01_PATCH_K26_V5_C1_AXIS_QD_CAUSAL_V1_1_' STAMP '.txt'];

fid = fopen(LOG_FILE,'w','n','UTF-8');
if fid < 0
    error('Cannot create patch log: %s',LOG_FILE);
end
cleanupFid = onCleanup(@() fclose(fid));

logf(fid,repmat('=',1,140));
logf(fid,'K26_V5 C1 AXIS Q/D CAUSAL HARNESS PATCH V1.1');
logf(fid,'[PATCH VERSION] %s',PATCH_VERSION);
logf(fid,'[ONLY PURPOSE] Add Mode5 C1-Q and Mode6 C1-D; preserve Mode0..4; no slow-slip control fix.');
logf(fid,repmat('=',1,140));

%% 0. Hard interlocks
if ~bdIsLoaded(MODEL)
    error(['K26_V5 is not loaded. This patch intentionally refuses automatic load_system ' ...
           'to avoid project callback ambiguity. Open the audited K26_V5.slx first.']);
end

dirty0 = get_param(MODEL,'Dirty');
if ~strcmpi(dirty0,'off')
    error('PATCH ABORT: model Dirty=%s. Require audited canonical model with Dirty=off.',dirty0);
end

simStatus = get_param(MODEL,'SimulationStatus');
if ~strcmpi(simStatus,'stopped')
    error('PATCH ABORT: SimulationStatus=%s. Require stopped.',simStatus);
end

% Robust file resolution.
% Some RT-LAB / Simulink project sessions can keep the model loaded while
% get_param(MODEL,'FileName') is empty or not directly resolvable by exist().
% This is a path-resolution issue, not permission to weaken the safety lock.
rawModelFile = '';
try
    rawModelFile = get_param(MODEL,'FileName');
catch
end

whichSlx = which([MODEL '.slx']);
whichModel = which(MODEL);
pwdCandidate = fullfile(pwd,[MODEL '.slx']);

logf(fid,'[PATH RAW FileName] %s',emptyAsToken(rawModelFile));
logf(fid,'[PATH which(K26_V5.slx)] %s',emptyAsToken(whichSlx));
logf(fid,'[PATH which(K26_V5)] %s',emptyAsToken(whichModel));
logf(fid,'[PATH pwd candidate] %s',pwdCandidate);
logf(fid,'[PATH audited absolute candidate] %s',AUDITED_MODEL_FILE);

candidates = {rawModelFile, whichSlx, whichModel, pwdCandidate, AUDITED_MODEL_FILE};
candidateLabels = {'get_param FileName','which .slx','which model','pwd','audited absolute'};
modelFile = '';
modelFileSource = '';

for kk = 1:numel(candidates)
    c = candidates{kk};
    if isempty(c), continue; end
    if isstring(c), c = char(c); end
    c = strtrim(c);
    if isempty(c), continue; end
    if exist(c,'file') == 2
        try
            hc = fileSha256(c);
            logf(fid,'[PATH CANDIDATE EXISTS] %-16s | %s | sha=%s',candidateLabels{kk},c,hc);
            if strcmpi(hc,EXPECTED_SHA256)
                modelFile = c;
                modelFileSource = candidateLabels{kk};
                break;
            end
        catch MEpath
            logf(fid,'[PATH CANDIDATE HASH WARN] %-16s | %s | %s',candidateLabels{kk},c,MEpath.message);
        end
    else
        logf(fid,'[PATH CANDIDATE MISSING] %-16s | %s',candidateLabels{kk},c);
    end
end

if isempty(modelFile)
    error(['PATCH ABORT: model is loaded but no resolvable disk candidate matches the audited SHA256.\n' ...
           'This is a file-resolution/safety-interlock failure, not a model-structure failure.\n' ...
           'Upload this TXT; do not disable the hash lock.']);
end

sha0 = fileSha256(modelFile);
logf(fid,'[MODEL FILE RESOLVED BY] %s',modelFileSource);
logf(fid,'[MODEL FILE] %s',modelFile);
logf(fid,'[DIRTY] %s',dirty0);
logf(fid,'[SIM STATUS] %s',simStatus);
logf(fid,'[SHA256 BEFORE] %s',sha0);

if ~strcmpi(sha0,EXPECTED_SHA256)
    error(['PATCH ABORT: model SHA256 does not match the audited post-C2 canonical model.\n' ...
           'Expected: %s\nActual:   %s\nDo not patch an unknown model.'],EXPECTED_SHA256,sha0);
end
logf(fid,'[HASH INTERLOCK PASS] exact audited model confirmed.');

modelDir = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    ['K26_V5__PRE_C1_AXIS_QD_CAUSAL_V1_0_' STAMP '.slx']);
[ok,msg] = copyfile(modelFile,backupFile);
if ~ok
    error('PATCH ABORT: full backup failed: %s',msg);
end
logf(fid,'[FULL BACKUP PASS] %s',backupFile);

savedToDisk = false;
patchSucceeded = false;

try
    %% 1. Frozen five-GFL targets
    T = struct( ...
        'name', {'PV1','PV2','ESS2','EV1','EV2'}, ...
        'ctrl', { ...
            [MODEL '/SS_Slave3/PV1_Control'], ...
            [MODEL '/SS_Slave3/PV2_Control'], ...
            [MODEL '/SS_Slave2/ESS2_Control'], ...
            [MODEL '/SS_Slave/EV1_Control'], ...
            [MODEL '/SS_Slave/Control System'] ...
        });

    logf(fid,'\n--- 1. STRICT PREPATCH PREFLIGHT ---');

    for i = 1:numel(T)
        ctrl = T(i).ctrl;
        dev = T(i).name;
        requireBlock(ctrl);

        required = { ...
            [ctrl '/AA15_CAUSAL_MODE'], ...
            [ctrl '/AA15_C_HOLD_STEP'], ...
            [ctrl '/AA15_C_TRACK_ONE'], ...
            [ctrl '/AA15_C1_VDQ_TRACK_HOLD'], ...
            [ctrl '/AA15_C2_IREF_TRACK_HOLD'], ...
            [ctrl '/AA15_C1_TRACK_GATE'], ...
            [ctrl '/AA15_C2_TRACK_GATE'], ...
            [ctrl '/AA15_C1_HOLD_REQ_OR'], ...
            [ctrl '/AA15_C2_HOLD_REQ_OR'], ...
            [ctrl '/AA15_MODE_CONST_1'], ...
            [ctrl '/AA15_MODE_CONST_2'], ...
            [ctrl '/AA15_MODE_CONST_3'], ...
            [ctrl '/AA15_MODE_CONST_4'], ...
            [ctrl '/AA15_MODE_EQ_1'], ...
            [ctrl '/AA15_MODE_EQ_2'], ...
            [ctrl '/AA15_MODE_EQ_3'], ...
            [ctrl '/AA15_MODE_EQ_4'], ...
            [ctrl '/Current Regulator'], ...
            [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'], ...
            [ctrl '/From26'] ...
        };
        for k = 1:numel(required)
            requireBlock(required{k});
        end

        forbidden = { ...
            [ctrl '/AA15_MODE_CONST_5'], ...
            [ctrl '/AA15_MODE_CONST_6'], ...
            [ctrl '/AA15_MODE_EQ_5'], ...
            [ctrl '/AA15_MODE_EQ_6'], ...
            [ctrl '/AA15_C1D_AXIS_TRACK_GATE'], ...
            [ctrl '/AA15_C1Q_AXIS_TRACK_GATE'], ...
            [ctrl '/AA15_C1_AXIS_TRACK_HOLD'] ...
        };
        for k = 1:numel(forbidden)
            if blockExists(forbidden{k})
                error('[%s] name collision: %s already exists.',dev,forbidden{k});
            end
        end

        modeVal = safeParam([ctrl '/AA15_CAUSAL_MODE'],'Value');
        assertNumeric(modeVal,0,sprintf('%s saved AA15_CAUSAL_MODE',dev));

        assertNumeric(safeParam([ctrl '/AA15_C_HOLD_STEP'],'Time'),8.1894,sprintf('%s hold step time',dev));
        assertNumeric(safeParam([ctrl '/AA15_C_HOLD_STEP'],'Before'),1,sprintf('%s hold step before',dev));
        assertNumeric(safeParam([ctrl '/AA15_C_HOLD_STEP'],'After'),0,sprintf('%s hold step after',dev));

        if ~strcmp(safeParam([ctrl '/From26'],'GotoTag'),'VdVqs')
            error('[%s] From26 GotoTag drifted: %s',dev,safeParam([ctrl '/From26'],'GotoTag'));
        end

        c1 = [ctrl '/AA15_C1_VDQ_TRACK_HOLD'];
        c2 = [ctrl '/AA15_C2_IREF_TRACK_HOLD'];
        cr = [ctrl '/Current Regulator'];
        lg = [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        assertSource(c1,1,[ctrl '/From26'],1,sprintf('%s C1 raw source',dev));
        assertSource(c1,2,[ctrl '/AA15_C1_TRACK_GATE'],1,sprintf('%s C1 track source',dev));
        assertDestSet(c1,1,{portDesc(cr,1,'in'),portDesc(lg,5,'in')},sprintf('%s C1 prepatch destinations',dev));

        assertSource(c2,1,[ctrl '/Power Control Loop'],1,sprintf('%s C2 raw source',dev));
        assertSource(c2,2,[ctrl '/AA15_C2_TRACK_GATE'],1,sprintf('%s C2 track source',dev));
        assertDestSet(c2,1,{portDesc([ctrl '/Goto18'],1,'in')},sprintf('%s C2 destination',dev));

        assertSource(cr,1,c1,1,sprintf('%s CurrentReg/in1 prepatch source',dev));

        % Old logger physical contract: 17 physical inputs / 24 compiled scalars.
        nInputs = str2double(safeParam(lg,'Inputs'));
        if ~(isfinite(nInputs) && nInputs == 17)
            error('[%s] logger Inputs expected 17, got %s',dev,safeParam(lg,'Inputs'));
        end

        logf(fid,'[PREFLIGHT PASS] %s',dev);
    end

    %% 2. Apply per-GFL axis harness
    logf(fid,'\n--- 2. INSERT MODE5/MODE6 + AXIS WRAPPER ---');

    for i = 1:numel(T)
        ctrl = T(i).ctrl;
        dev = T(i).name;
        logf(fid,'\n[%s] patching %s',dev,ctrl);

        % Allocate a clean area to the far right of existing top-level blocks.
        x0 = topLevelMaxRight(ctrl) + 120;
        y0 = 80;

        mode5 = [ctrl '/AA15_MODE_CONST_5'];
        mode6 = [ctrl '/AA15_MODE_CONST_6'];
        eq5 = [ctrl '/AA15_MODE_EQ_5'];
        eq6 = [ctrl '/AA15_MODE_EQ_6'];
        dGate = [ctrl '/AA15_C1D_AXIS_TRACK_GATE'];
        qGate = [ctrl '/AA15_C1Q_AXIS_TRACK_GATE'];
        axis = [ctrl '/AA15_C1_AXIS_TRACK_HOLD'];

        add_block('built-in/Constant',mode5, ...
            'Value','5','Position',[x0 y0 x0+45 y0+26]);
        add_block('built-in/Constant',mode6, ...
            'Value','6','Position',[x0 y0+50 x0+45 y0+76]);

        add_block('built-in/RelationalOperator',eq5, ...
            'Operator','==','Position',[x0+100 y0-2 x0+145 y0+30]);
        add_block('built-in/RelationalOperator',eq6, ...
            'Operator','==','Position',[x0+100 y0+48 x0+145 y0+80]);

        add_block('built-in/Switch',qGate, ...
            'Criteria','u2 > Threshold','Threshold','0.5', ...
            'Position',[x0+215 y0-10 x0+265 y0+36]);
        add_block('built-in/Switch',dGate, ...
            'Criteria','u2 > Threshold','Threshold','0.5', ...
            'Position',[x0+215 y0+55 x0+265 y0+101]);

        addAxisHoldSubsystem(axis,[x0+350 y0-5 x0+540 y0+115]);

        % New mode comparisons.
        add_line(ctrl,'AA15_CAUSAL_MODE/1','AA15_MODE_EQ_5/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_CONST_5/1','AA15_MODE_EQ_5/2','autorouting','on');
        add_line(ctrl,'AA15_CAUSAL_MODE/1','AA15_MODE_EQ_6/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_CONST_6/1','AA15_MODE_EQ_6/2','autorouting','on');

        % Axis track-gate contract:
        % switch u1 = shared 8.1894s TRACK->HOLD step
        % switch u2 = mode-specific request
        % switch u3 = constant 1
        %
        % q holds only in Mode5; d holds only in Mode6.
        add_line(ctrl,'AA15_C_HOLD_STEP/1','AA15_C1Q_AXIS_TRACK_GATE/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_EQ_5/1','AA15_C1Q_AXIS_TRACK_GATE/2','autorouting','on');
        add_line(ctrl,'AA15_C_TRACK_ONE/1','AA15_C1Q_AXIS_TRACK_GATE/3','autorouting','on');

        add_line(ctrl,'AA15_C_HOLD_STEP/1','AA15_C1D_AXIS_TRACK_GATE/1','autorouting','on');
        add_line(ctrl,'AA15_MODE_EQ_6/1','AA15_C1D_AXIS_TRACK_GATE/2','autorouting','on');
        add_line(ctrl,'AA15_C_TRACK_ONE/1','AA15_C1D_AXIS_TRACK_GATE/3','autorouting','on');

        % Interpose axis wrapper between OLD C1 output and real consumer.
        c1 = [ctrl '/AA15_C1_VDQ_TRACK_HOLD'];
        cr = [ctrl '/Current Regulator'];
        lg = [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        % Branch-safe destination deletion: do not delete the entire C1 line.
        deleteSpecificLine(ctrl,'AA15_C1_VDQ_TRACK_HOLD/1','Current Regulator/1');
        deleteSpecificLine(ctrl,'AA15_C1_VDQ_TRACK_HOLD/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5');

        add_line(ctrl,'AA15_C1_VDQ_TRACK_HOLD/1','AA15_C1_AXIS_TRACK_HOLD/1','autorouting','on');
        add_line(ctrl,'AA15_C1D_AXIS_TRACK_GATE/1','AA15_C1_AXIS_TRACK_HOLD/2','autorouting','on');
        add_line(ctrl,'AA15_C1Q_AXIS_TRACK_GATE/1','AA15_C1_AXIS_TRACK_HOLD/3','autorouting','on');

        add_line(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','Current Regulator/1','autorouting','on');
        add_line(ctrl,'AA15_C1_AXIS_TRACK_HOLD/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/5','autorouting','on');

        % Extend logger 17 physical inputs -> 19.
        % First 17 inputs are untouched, therefore old scalar01..24 semantics stay frozen.
        set_param(lg,'Inputs','19');
        add_line(ctrl,'AA15_C1D_AXIS_TRACK_GATE/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/18','autorouting','on');
        add_line(ctrl,'AA15_C1Q_AXIS_TRACK_GATE/1','AA15_CAUSALDIAG_MUX17PORT_24SCALAR/19','autorouting','on');

        logf(fid,'[INSERTED] %s Mode5/Mode6 + axis wrapper + logger scalar25/26',dev);
    end

    %% 3. Structural postassert before compile
    logf(fid,'\n--- 3. STRUCTURAL POSTASSERT BEFORE COMPILE ---');
    for i = 1:numel(T)
        ctrl = T(i).ctrl;
        dev = T(i).name;

        c1 = [ctrl '/AA15_C1_VDQ_TRACK_HOLD'];
        c2 = [ctrl '/AA15_C2_IREF_TRACK_HOLD'];
        cr = [ctrl '/Current Regulator'];
        lg = [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];
        axis = [ctrl '/AA15_C1_AXIS_TRACK_HOLD'];
        dGate = [ctrl '/AA15_C1D_AXIS_TRACK_GATE'];
        qGate = [ctrl '/AA15_C1Q_AXIS_TRACK_GATE'];
        eq5 = [ctrl '/AA15_MODE_EQ_5'];
        eq6 = [ctrl '/AA15_MODE_EQ_6'];

        assertNumeric(safeParam([ctrl '/AA15_MODE_CONST_5'],'Value'),5,[dev ' Mode5 value']);
        assertNumeric(safeParam([ctrl '/AA15_MODE_CONST_6'],'Value'),6,[dev ' Mode6 value']);

        assertSource(eq5,1,[ctrl '/AA15_CAUSAL_MODE'],1,[dev ' eq5 mode source']);
        assertSource(eq5,2,[ctrl '/AA15_MODE_CONST_5'],1,[dev ' eq5 const source']);
        assertSource(eq6,1,[ctrl '/AA15_CAUSAL_MODE'],1,[dev ' eq6 mode source']);
        assertSource(eq6,2,[ctrl '/AA15_MODE_CONST_6'],1,[dev ' eq6 const source']);

        assertSource(qGate,1,[ctrl '/AA15_C_HOLD_STEP'],1,[dev ' qGate step']);
        assertSource(qGate,2,eq5,1,[dev ' qGate Mode5 request']);
        assertSource(qGate,3,[ctrl '/AA15_C_TRACK_ONE'],1,[dev ' qGate bypass one']);

        assertSource(dGate,1,[ctrl '/AA15_C_HOLD_STEP'],1,[dev ' dGate step']);
        assertSource(dGate,2,eq6,1,[dev ' dGate Mode6 request']);
        assertSource(dGate,3,[ctrl '/AA15_C_TRACK_ONE'],1,[dev ' dGate bypass one']);

        % Old C1 must now have only one new destination.
        assertDestSet(c1,1,{portDesc(axis,1,'in')},[dev ' old C1 postpatch destinations']);

        % Axis wrapper has exactly two intended consumers.
        assertSource(axis,1,c1,1,[dev ' axis raw']);
        assertSource(axis,2,dGate,1,[dev ' axis D track']);
        assertSource(axis,3,qGate,1,[dev ' axis Q track']);
        assertDestSet(axis,1,{portDesc(cr,1,'in'),portDesc(lg,5,'in')},[dev ' axis applied destinations']);
        assertSource(cr,1,axis,1,[dev ' CurrentReg/in1 final source']);
        assertSource(lg,5,axis,1,[dev ' logger final applied Vdq']);

        assertSource(lg,18,dGate,1,[dev ' logger input18 D track']);
        assertSource(lg,19,qGate,1,[dev ' logger input19 Q track']);

        % C2 must remain exactly unchanged.
        assertSource(c2,1,[ctrl '/Power Control Loop'],1,[dev ' C2 raw unchanged']);
        assertSource(c2,2,[ctrl '/AA15_C2_TRACK_GATE'],1,[dev ' C2 track unchanged']);
        assertDestSet(c2,1,{portDesc([ctrl '/Goto18'],1,'in')},[dev ' C2 destination unchanged']);

        % New eq5/eq6 may ONLY drive their new axis gates.
        assertDestSet(eq5,1,{portDesc(qGate,2,'in')},[dev ' eq5 exact destination']);
        assertDestSet(eq6,1,{portDesc(dGate,2,'in')},[dev ' eq6 exact destination']);

        % Existing C1/C2 hold request OR sources are not touched by Mode5/6.
        oldC1ORsrc = allInportSources([ctrl '/AA15_C1_HOLD_REQ_OR']);
        oldC2ORsrc = allInportSources([ctrl '/AA15_C2_HOLD_REQ_OR']);
        if any(contains(oldC1ORsrc,'AA15_MODE_EQ_5')) || any(contains(oldC1ORsrc,'AA15_MODE_EQ_6')) || ...
           any(contains(oldC2ORsrc,'AA15_MODE_EQ_5')) || any(contains(oldC2ORsrc,'AA15_MODE_EQ_6'))
            error('[%s] Mode5/6 contaminated old C1/C2 hold request logic.',dev);
        end

        if str2double(safeParam(lg,'Inputs')) ~= 19
            error('[%s] logger Inputs expected 19 after patch.',dev);
        end

        assertAxisSubsystem(fid,axis,dev);
        logf(fid,'[STRUCTURAL POSTASSERT PASS] %s',dev);
    end

    %% 4. Explicit compile-state validation
    logf(fid,'\n--- 4. EXPLICIT COMPILE-STATE VALIDATION ---');
    compiled = false;
    try
        feval(MODEL,[],[],[],'compile');
        compiled = true;
        logf(fid,'[COMPILE ENTER PASS]');

        expectedGroup = struct( ...
            'block',{ ...
                [MODEL '/SS_Slave/AA15_ROOTDIAG_EV12_OPWRITE_G26'], ...
                [MODEL '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'], ...
                [MODEL '/SS_Slave3/AA15_ROOTDIAG_PV12_OPWRITE_G28']}, ...
            'width',{52,26,52}, ...
            'name',{'G26','G27','G28'});

        for i = 1:numel(T)
            ctrl = T(i).ctrl;
            dev = T(i).name;
            c1 = [ctrl '/AA15_C1_VDQ_TRACK_HOLD'];
            axis = [ctrl '/AA15_C1_AXIS_TRACK_HOLD'];
            c2 = [ctrl '/AA15_C2_IREF_TRACK_HOLD'];
            cr = [ctrl '/Current Regulator'];
            lg = [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

            wC1 = compiledWidths(c1);
            wAX = compiledWidths(axis);
            wC2 = compiledWidths(c2);
            wCR = compiledWidths(cr);
            wLG = compiledWidths(lg);
            wDG = compiledWidths([ctrl '/AA15_C1D_AXIS_TRACK_GATE']);
            wQG = compiledWidths([ctrl '/AA15_C1Q_AXIS_TRACK_GATE']);

            logf(fid,['[%s WIDTH] oldC1 in=%s out=%s | axis in=%s out=%s | C2 in=%s out=%s | ' ...
                      'CurrentReg in=%s out=%s | logger in=%s out=%s | Dgate out=%s Qgate out=%s'], ...
                dev,mat2str(wC1.Inport),mat2str(wC1.Outport), ...
                mat2str(wAX.Inport),mat2str(wAX.Outport), ...
                mat2str(wC2.Inport),mat2str(wC2.Outport), ...
                mat2str(wCR.Inport),mat2str(wCR.Outport), ...
                mat2str(wLG.Inport),mat2str(wLG.Outport), ...
                mat2str(wDG.Outport),mat2str(wQG.Outport));

            requireWidth(wC1.Outport,1,2,[dev ' old C1 out']);
            requireWidth(wAX.Inport,1,2,[dev ' axis in1']);
            requireWidth(wAX.Inport,2,1,[dev ' axis in2']);
            requireWidth(wAX.Inport,3,1,[dev ' axis in3']);
            requireWidth(wAX.Outport,1,2,[dev ' axis out']);
            requireWidth(wCR.Inport,1,2,[dev ' CurrentReg in1']);
            requireWidth(wLG.Outport,1,26,[dev ' logger out']);
            requireWidth(wDG.Outport,1,1,[dev ' Dgate out']);
            requireWidth(wQG.Outport,1,1,[dev ' Qgate out']);
        end

        for k = 1:numel(expectedGroup)
            requireBlock(expectedGroup(k).block);
            wg = compiledWidths(expectedGroup(k).block);
            logf(fid,'[%s OPWRITE WIDTH] in=%s out=%s', ...
                expectedGroup(k).name,mat2str(wg.Inport),mat2str(wg.Outport));
            requireWidth(wg.Inport,1,expectedGroup(k).width,[expectedGroup(k).name ' input width']);
        end

        % Exactly five OpWrite blocks remain.
        opwNamed = find_system(MODEL,'LookUnderMasks','all','FollowLinks','on', ...
            'RegExp','on','Name','.*OPWRITE.*');
        logf(fid,'[OPWRITE NAMED COUNT] %d',numel(opwNamed));
        if numel(opwNamed) ~= 5
            error('Expected exactly five OPWRITE-named blocks, got %d.',numel(opwNamed));
        end

    catch MEc
        if compiled
            try, feval(MODEL,[],[],[],'term'); catch, end
        end
        rethrow(MEc);
    end

    if compiled
        feval(MODEL,[],[],[],'term');
        logf(fid,'[COMPILE TERM PASS]');
    end

    %% 5. Save only after all pre-save checks pass
    logf(fid,'\n--- 5. SAVE ---');

    % Disk default MUST remain Mode0.
    for i = 1:numel(T)
        set_param([T(i).ctrl '/AA15_CAUSAL_MODE'],'Value','0');
    end

    save_system(MODEL);
    savedToDisk = true;
    sha1 = fileSha256(modelFile);
    logf(fid,'[SAVE PASS]');
    logf(fid,'[SHA256 AFTER] %s',sha1);

    %% 6. Close/reload persistence audit
    logf(fid,'\n--- 6. CLOSE/RELOAD PERSISTENCE AUDIT ---');
    close_system(MODEL,0);
    load_system(modelFile);

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Persistence audit: reloaded model Dirty is not off.');
    end

    for i = 1:numel(T)
        ctrl = T(i).ctrl;
        dev = T(i).name;
        requireBlock([ctrl '/AA15_MODE_CONST_5']);
        requireBlock([ctrl '/AA15_MODE_CONST_6']);
        requireBlock([ctrl '/AA15_MODE_EQ_5']);
        requireBlock([ctrl '/AA15_MODE_EQ_6']);
        requireBlock([ctrl '/AA15_C1D_AXIS_TRACK_GATE']);
        requireBlock([ctrl '/AA15_C1Q_AXIS_TRACK_GATE']);
        requireBlock([ctrl '/AA15_C1_AXIS_TRACK_HOLD']);

        assertNumeric(safeParam([ctrl '/AA15_CAUSAL_MODE'],'Value'),0,[dev ' persisted Mode0']);
        assertSource([ctrl '/Current Regulator'],1,[ctrl '/AA15_C1_AXIS_TRACK_HOLD'],1,[dev ' persisted CurrentReg source']);
        assertSource([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'],5,[ctrl '/AA15_C1_AXIS_TRACK_HOLD'],1,[dev ' persisted logger applied']);
        assertSource([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'],18,[ctrl '/AA15_C1D_AXIS_TRACK_GATE'],1,[dev ' persisted D track diag']);
        assertSource([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'],19,[ctrl '/AA15_C1Q_AXIS_TRACK_GATE'],1,[dev ' persisted Q track diag']);

        logf(fid,'[PERSISTENCE STRUCTURE PASS] %s',dev);
    end

    % Compile once more after reload.
    compiled2 = false;
    try
        feval(MODEL,[],[],[],'compile');
        compiled2 = true;
        for i = 1:numel(T)
            lg = [T(i).ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];
            wLG = compiledWidths(lg);
            requireWidth(wLG.Outport,1,26,[T(i).name ' persisted logger width']);
        end
        logf(fid,'[PERSISTENCE COMPILE PASS]');
    catch ME2
        if compiled2
            try, feval(MODEL,[],[],[],'term'); catch, end
        end
        rethrow(ME2);
    end
    if compiled2
        feval(MODEL,[],[],[],'term');
    end

    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('Final model Dirty is not off after persistence audit.');
    end

    patchSucceeded = true;

    %% 7. Final frozen contract
    logf(fid,'\n--- 7. FINAL PATCH CONTRACT ---');
    logf(fid,'[Mode0] baseline: old C1 TRACK; C2 TRACK; D/Q axis wrapper TRACK.');
    logf(fid,'[Mode1] B1 repro: old C1 TRACK; C2 TRACK; D/Q axis wrapper TRACK.');
    logf(fid,'[Mode2] old C1 D+Q HOLD; axis wrapper TRACK => old C1 semantics preserved.');
    logf(fid,'[Mode3] C2 HOLD; old C1 TRACK; axis wrapper TRACK => old C2 semantics preserved.');
    logf(fid,'[Mode4] old C1 D+Q HOLD + C2 HOLD; axis wrapper TRACK => old C3 semantics preserved.');
    logf(fid,'[Mode5] C1-Q: old C1 TRACK; C2 TRACK; D TRACK; Q TRACK->HOLD @8.1894s.');
    logf(fid,'[Mode6] C1-D: old C1 TRACK; C2 TRACK; D TRACK->HOLD @8.1894s; Q TRACK.');
    logf(fid,'[diag scalar25] C1_D_AXIS_TRACK_ENABLE');
    logf(fid,'[diag scalar26] C1_Q_AXIS_TRACK_ENABLE');
    logf(fid,'[G26/G27/G28 compiled widths] 52 / 26 / 52 expected.');
    logf(fid,'[OpWrite] exactly five; no new writer.');
    logf(fid,'[SLOW-SLIP] control untouched.');
    logf(fid,'[NEXT] RT-LAB Rebuild All. Do not run Mode5 until Build result is reviewed.');

    logf(fid,'\n%s',repmat('=',1,140));
    logf(fid,'C1 AXIS Q/D CAUSAL HARNESS PATCH PASS');
    logf(fid,'Backup: %s',backupFile);
    logf(fid,'Current: %s',modelFile);
    logf(fid,'%s',repmat('=',1,140));

catch ME
    logf(fid,'\n%s',repmat('!',1,140));
    logf(fid,'PATCH FAILURE');
    logf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));

    % Make sure compile state is terminated.
    try
        feval(MODEL,[],[],[],'term');
    catch
    end

    % Discard in-memory edits.
    try
        if bdIsLoaded(MODEL)
            close_system(MODEL,0);
        end
    catch
    end

    % If save had already occurred, restore exact prepatch backup.
    if savedToDisk
        try
            [okr,msgr] = copyfile(backupFile,modelFile,'f');
            if okr
                logf(fid,'[ROLLBACK DISK PASS] restored backup over current model.');
            else
                logf(fid,'[ROLLBACK DISK FAIL] %s',msgr);
            end
        catch MEr
            logf(fid,'[ROLLBACK EXCEPTION] %s',MEr.message);
        end
    else
        logf(fid,'[ROLLBACK] save_system had not occurred; audited disk model was never changed.');
    end

    try
        load_system(modelFile);
        logf(fid,'[ROLLBACK RELOAD] model reloaded.');
    catch MEr2
        logf(fid,'[ROLLBACK RELOAD WARN] %s',MEr2.message);
    end

    logf(fid,'%s',repmat('!',1,140));
    rethrow(ME);
end

if patchSucceeded
    fprintf('\nPATCH PASS.\nLog: %s\nBackup: %s\n',LOG_FILE,backupFile);
    fprintf('Next action: RT-LAB Rebuild All only. Do not Execute Mode5 yet.\n');
end

%% =========================================================================
%% Local functions
%% =========================================================================

function addAxisHoldSubsystem(sub,pos)
    add_block('built-in/SubSystem',sub,'Position',pos);

    % Ports
    add_block('built-in/Inport',[sub '/RawVdq'], ...
        'Port','1','Position',[25 35 55 49]);
    add_block('built-in/Inport',[sub '/D_TRACK_ENABLE'], ...
        'Port','2','Position',[25 90 55 104]);
    add_block('built-in/Inport',[sub '/Q_TRACK_ENABLE'], ...
        'Port','3','Position',[25 145 55 159]);

    add_block('built-in/Demux',[sub '/DemuxVdq'], ...
        'Outputs','2','Position',[90 34 95 80]);

    % D-axis hold
    add_block('built-in/UnitDelay',[sub '/D_Held_State'], ...
        'InitialCondition','0','SampleTime','Ts', ...
        'Position',[190 80 240 110]);
    add_block('built-in/Switch',[sub '/D_TrackOrHold'], ...
        'Criteria','u2 > Threshold','Threshold','0.5', ...
        'Position',[180 20 230 65]);

    % Q-axis hold
    add_block('built-in/UnitDelay',[sub '/Q_Held_State'], ...
        'InitialCondition','0','SampleTime','Ts', ...
        'Position',[190 185 240 215]);
    add_block('built-in/Switch',[sub '/Q_TrackOrHold'], ...
        'Criteria','u2 > Threshold','Threshold','0.5', ...
        'Position',[180 125 230 170]);

    add_block('built-in/Mux',[sub '/MuxAppliedVdq'], ...
        'Inputs','2','Position',[300 73 305 137]);
    add_block('built-in/Outport',[sub '/AppliedVdq'], ...
        'Port','1','Position',[355 98 385 112]);

    % Raw vector split
    add_line(sub,'RawVdq/1','DemuxVdq/1','autorouting','on');

    % D: raw -> switch top; track enable -> control; previous applied -> bottom
    add_line(sub,'DemuxVdq/1','D_TrackOrHold/1','autorouting','on');
    add_line(sub,'D_TRACK_ENABLE/1','D_TrackOrHold/2','autorouting','on');
    add_line(sub,'D_Held_State/1','D_TrackOrHold/3','autorouting','on');
    add_line(sub,'D_TrackOrHold/1','MuxAppliedVdq/1','autorouting','on');
    add_line(sub,'D_TrackOrHold/1','D_Held_State/1','autorouting','on');

    % Q
    add_line(sub,'DemuxVdq/2','Q_TrackOrHold/1','autorouting','on');
    add_line(sub,'Q_TRACK_ENABLE/1','Q_TrackOrHold/2','autorouting','on');
    add_line(sub,'Q_Held_State/1','Q_TrackOrHold/3','autorouting','on');
    add_line(sub,'Q_TrackOrHold/1','MuxAppliedVdq/2','autorouting','on');
    add_line(sub,'Q_TrackOrHold/1','Q_Held_State/1','autorouting','on');

    add_line(sub,'MuxAppliedVdq/1','AppliedVdq/1','autorouting','on');
end

function assertAxisSubsystem(fid,axis,dev)
    requireBlock(axis);
    req = { ...
        [axis '/RawVdq'],[axis '/D_TRACK_ENABLE'],[axis '/Q_TRACK_ENABLE'], ...
        [axis '/DemuxVdq'],[axis '/D_Held_State'],[axis '/D_TrackOrHold'], ...
        [axis '/Q_Held_State'],[axis '/Q_TrackOrHold'], ...
        [axis '/MuxAppliedVdq'],[axis '/AppliedVdq']};
    for k = 1:numel(req), requireBlock(req{k}); end

    assertSource([axis '/DemuxVdq'],1,[axis '/RawVdq'],1,[dev ' axis demux']);
    assertSource([axis '/D_TrackOrHold'],1,[axis '/DemuxVdq'],1,[dev ' D raw']);
    assertSource([axis '/D_TrackOrHold'],2,[axis '/D_TRACK_ENABLE'],1,[dev ' D track ctl']);
    assertSource([axis '/D_TrackOrHold'],3,[axis '/D_Held_State'],1,[dev ' D held']);
    assertSource([axis '/D_Held_State'],1,[axis '/D_TrackOrHold'],1,[dev ' D state update']);

    assertSource([axis '/Q_TrackOrHold'],1,[axis '/DemuxVdq'],2,[dev ' Q raw']);
    assertSource([axis '/Q_TrackOrHold'],2,[axis '/Q_TRACK_ENABLE'],1,[dev ' Q track ctl']);
    assertSource([axis '/Q_TrackOrHold'],3,[axis '/Q_Held_State'],1,[dev ' Q held']);
    assertSource([axis '/Q_Held_State'],1,[axis '/Q_TrackOrHold'],1,[dev ' Q state update']);

    assertSource([axis '/MuxAppliedVdq'],1,[axis '/D_TrackOrHold'],1,[dev ' applied D']);
    assertSource([axis '/MuxAppliedVdq'],2,[axis '/Q_TrackOrHold'],1,[dev ' applied Q']);
    assertSource([axis '/AppliedVdq'],1,[axis '/MuxAppliedVdq'],1,[dev ' axis output']);

    assertNumeric(safeParam([axis '/D_Held_State'],'InitialCondition'),0,[dev ' D IC']);
    assertNumeric(safeParam([axis '/Q_Held_State'],'InitialCondition'),0,[dev ' Q IC']);
    if ~strcmp(safeParam([axis '/D_Held_State'],'SampleTime'),'Ts') || ...
       ~strcmp(safeParam([axis '/Q_Held_State'],'SampleTime'),'Ts')
        error('[%s] axis UnitDelay sample time must be Ts.',dev);
    end

    logf(fid,'[AXIS SUBSYSTEM PASS] %s bumpless per-axis held-state topology exact.',dev);
end

function deleteSpecificLine(parent,srcRel,dstRel)
    try
        delete_line(parent,srcRel,dstRel);
    catch ME
        error('Failed branch-specific delete %s : %s -> %s | %s', ...
            parent,srcRel,dstRel,ME.message);
    end
end

function x = topLevelMaxRight(sys)
    blks = find_system(sys,'SearchDepth',1,'Type','Block');
    blks = blks(~strcmp(blks,sys));
    r = [];
    for k = 1:numel(blks)
        try
            p = get_param(blks{k},'Position');
            if isnumeric(p) && numel(p)==4
                r(end+1) = p(3); %#ok<AGROW>
            end
        catch
        end
    end
    if isempty(r), x = 1100; else, x = max(r); end
end

function logf(fid,fmt,varargin)
    s = sprintf(fmt,varargin{:});
    fprintf('%s\n',s);
    fprintf(fid,'%s\n',s);
end

function tf = blockExists(p)
    try
        get_param(p,'Handle');
        tf = true;
    catch
        tf = false;
    end
end

function requireBlock(p)
    if ~blockExists(p)
        error('Required block missing: %s',p);
    end
end

function s = safeParam(block,param)
    try
        v = get_param(block,param);
        if isnumeric(v)
            s = mat2str(v);
        elseif ischar(v)
            s = v;
        elseif isstring(v)
            s = char(v);
        else
            s = char(string(v));
        end
    catch
        s = '<N/A>';
    end
end

function assertNumeric(s,wanted,label)
    v = str2double(strtrim(s));
    if ~(isfinite(v) && abs(v-wanted) <= 1e-12)
        error('%s expected %.15g, got %s',label,wanted,s);
    end
end

function d = portDesc(block,portNo,kind)
    if strcmpi(kind,'in')
        d = sprintf('%s|in%d',block,portNo);
    else
        d = sprintf('%s|out%d',block,portNo);
    end
end

function assertSource(dstBlock,inIdx,srcBlock,outIdx,label)
    a = inportSourceDesc(dstBlock,inIdx);
    e = portDesc(srcBlock,outIdx,'out');
    if ~strcmp(a,e)
        error('%s source mismatch.\nExpected: %s\nActual:   %s',label,e,a);
    end
end

function assertDestSet(srcBlock,outIdx,expected,label)
    actual = sort(outportDestDescs(srcBlock,outIdx));
    expected = sort(expected);
    if ~isequal(actual,expected)
        error('%s destination mismatch.\nExpected: %s\nActual:   %s', ...
            label,strjoin(expected,' ; '),strjoin(actual,' ; '));
    end
end

function d = inportSourceDesc(block,inIdx)
    ph = get_param(block,'PortHandles');
    if numel(ph.Inport) < inIdx
        d = '<NO SUCH INPORT>'; return;
    end
    lh = get_param(ph.Inport(inIdx),'Line');
    if isempty(lh) || lh == -1
        d = '<UNCONNECTED>'; return;
    end
    sh = get_param(lh,'SrcPortHandle');
    if isempty(sh) || sh == -1
        d = '<NO SOURCE>'; return;
    end
    d = sprintf('%s|out%d',get_param(sh,'Parent'),get_param(sh,'PortNumber'));
end

function ds = outportDestDescs(block,outIdx)
    ph = get_param(block,'PortHandles');
    ds = {};
    if numel(ph.Outport) < outIdx, return; end
    lh = get_param(ph.Outport(outIdx),'Line');
    if isempty(lh) || lh == -1, return; end
    dh = get_param(lh,'DstPortHandle');
    if isempty(dh), return; end
    dh = dh(:)';
    for h = dh
        if h == -1, continue; end
        ds{end+1} = sprintf('%s|in%d',get_param(h,'Parent'),get_param(h,'PortNumber')); %#ok<AGROW>
    end
    ds = unique(ds);
end

function srcs = allInportSources(block)
    ph = get_param(block,'PortHandles');
    srcs = cell(1,numel(ph.Inport));
    for i = 1:numel(ph.Inport)
        srcs{i} = inportSourceDesc(block,i);
    end
end

function w = compiledWidths(block)
    w = struct('Inport',[],'Outport',[]);
    try
        x = get_param(block,'CompiledPortWidths');
        if isstruct(x)
            if isfield(x,'Inport'), w.Inport=x.Inport; end
            if isfield(x,'Outport'),w.Outport=x.Outport;end
        end
    catch
    end
    if isempty(w.Inport) || isempty(w.Outport)
        try
            ph = get_param(block,'PortHandles');
            if isempty(w.Inport) && ~isempty(ph.Inport)
                a=zeros(1,numel(ph.Inport));
                for i=1:numel(ph.Inport)
                    a(i)=get_param(ph.Inport(i),'CompiledPortWidth');
                end
                w.Inport=a;
            end
            if isempty(w.Outport) && ~isempty(ph.Outport)
                a=zeros(1,numel(ph.Outport));
                for i=1:numel(ph.Outport)
                    a(i)=get_param(ph.Outport(i),'CompiledPortWidth');
                end
                w.Outport=a;
            end
        catch
        end
    end
end

function requireWidth(arr,idx,wanted,label)
    if numel(arr)<idx || arr(idx)~=wanted
        error('%s expected width %d, got %s',label,wanted,mat2str(arr));
    end
end

function s = emptyAsToken(v)
    if isempty(v)
        s = '<EMPTY>';
    elseif isstring(v)
        s = char(v);
    elseif ischar(v)
        s = v;
    else
        s = char(string(v));
    end
end

function h = fileSha256(fileName)
    f=fopen(fileName,'rb');
    if f<0, error('Cannot open file for SHA256: %s',fileName); end
    c=onCleanup(@() fclose(f));
    b=fread(f,Inf,'*uint8');
    md=java.security.MessageDigest.getInstance('SHA-256');
    md.update(b);
    d=typecast(md.digest(),'uint8');
    h=lower(reshape(dec2hex(d,2).',1,[]));
end

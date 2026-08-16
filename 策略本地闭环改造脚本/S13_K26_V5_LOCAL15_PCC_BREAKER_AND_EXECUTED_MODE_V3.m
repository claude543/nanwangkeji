function S13_K26_V5_LOCAL15_PCC_BREAKER_AND_EXECUTED_MODE_V3
% S13_K26_V5_LOCAL15_PCC_BREAKER_AND_EXECUTED_MODE_V3
%
% LOCAL15 Stage 13 V3
%
% ROOT CAUSE FIX
% --------------
% V2 created this direct logical feedback:
%
%   S13 executed_mode
%       -> S12 Device_Mode_Router input13
%       -> S12 selected_master / override_active / route_valid
%       -> S13 Execution_Core inputs9/10/11
%       -> S13 executed_mode
%
% That is an algebraic loop.
%
% In addition, the V2 Execution_Core used persistent variables. A MATLAB
% Function that updates persistent/state variables cannot legally sit inside
% an algebraic loop, so model update stopped.
%
% V3 removes the feedback by architecture, not by suppressing diagnostics:
%
%   S11 raw requests/evidence
%        -> 1-sample input delays (100 us)
%        -> S13 combinational execution core
%              ^                    |
%              |                    v
%          Unit Delay <--- next island/black latch
%                                   |
%                                   +--> EXECUTED_SYSTEM_MODE
%                                   |         |
%                                   |         +--> S12 Device_Mode_Router
%                                   |
%                                   +--> breaker request
%                                             |
%                                             v
%                                 PCC Breaker Command Router
%                                             |
%                                             v
%                                    Three-Phase Breaker
%
% There is NO path from current S12 outputs back into current S13 logic.
% Only AA15_MODE_ROUTE_VALID is used through a Unit Delay, so it can never
% recreate an algebraic loop.
%
% V3 also removes all persistent variables from the MATLAB Function.
% Island/black-start latches are explicit Unit Delay blocks.
%
% A second protection is added:
% all plant-dependent S11 signals used by S13 are delayed one 100-us sample:
%   raw_mode, raw_reason, s5_exec, s15_req, s14_req,
%   electrical_bad, comm_bad, emergency_active.
% This prevents a hidden same-step breaker -> electrical measurement ->
% S11 -> S13 -> breaker direct-feedthrough loop from becoming the next error.
%
% CURRENT PCC BREAKER BASELINE
% ----------------------------
% The current K26_V5 breaker is already External=on and is driven by:
%   SM_Master/Pulse Generator
%
% V3 preserves that exact legacy command:
%   Pulse Generator
%       -> AA15_S13_BREAKER_LEGACY_TAP
%       -> AA15_LEGACY_PCC_BREAKER_CMD
%       -> AA15_PCC_Breaker_Command_Router
%       -> AA15_PCC_BREAKER_CLOSE_CMD
%       -> Three-Phase Breaker
%
% With CFG15_PCC_BREAKER_ACTUATION_ENABLE=0:
%   FINAL breaker cmd == exact legacy Pulse Generator command.
%
% SAFETY
% ------
% Real LOCAL15 mode execution requires BOTH:
%   CFG15_MODE_ACTUATION_ENABLE = 1
%   CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1
%
% Communication loss alone cannot trip PCC because the real trip request
% still comes through S11 AA15_S5_EXECUTE_REQUEST (electrical V/f qualifier).
%
% S13 V3 does NOT automatically reclose after a real island/black-start latch.
% S14 will add controlled recovery / final test harness.
%
% REPAIR SAFETY
% -------------
% V3 can start from:
%   - clean S12,
%   - partial S13 V2 before retarget,
%   - partial S13 V2 after S12 retarget,
%   - partial S13 V2 after breaker final-From takeover.
%
% Before rebuilding S13, V3 restores:
%   - S12 mode source -> AA15_SYSTEM_MODE
%   - PCC breaker input -> exact recovered legacy source
% then removes all partial S13 calculation/logging blocks.
%
% GROUP28
% -------
% S12 = 202 scalar signals.
% S13 V3 appends 27:
%   203 raw_system_mode
%   204 executed_system_mode
%   205 legacy_breaker_cmd
%   206 requested_breaker_close
%   207 final_breaker_cmd
%   208 breaker_actuation_enable
%   209 device_mode_actuation_enable
%   210 execution_armed
%   211 island_latch
%   212 blackstart_latch
%   213 reclose_blocked
%   214 trip_reason
%   215 s5_execute_request
%   216 s15_transition_request
%   217 s14_blackstart_request
%   218 s5_electrical_bad
%   219 s5_comm_bad
%   220 selected_master
%   221 device_mode_override_active
%   222 mode_route_valid_raw
%   223 execution_route_valid
%   224 raw_mode_reason
%   225 emergency_active
%   226 breaker_override_active
%   227 breaker_route_valid
%   228 breaker_legacy_echo
%   229 breaker_request_echo
%
% Final Group28 = 229 scalar signals.
% Expected MAT = 230 rows including Target Time.
%
% BUILD POLICY
% ------------
% After STAGE13 V3 COMPLETE:
%   RT-LAB Rebuild All
% This is the strategic build for S11 + S12 + S13.
%
% FIRST Load after Build:
%   CFG15_MODE_ACTUATION_ENABLE = 0
%   CFG15_PCC_BREAKER_ACTUATION_ENABLE = 0
% and verify transparent baseline before any real breaker trip.
%
% Project rule:
%   mdl = bdroot(gcs)

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 13 V3 - Algebraic Loop Removed by Architecture\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S13V3:NoActiveModel', ...
        'Open K26_V5 and click inside the model before running S13 V3.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
panel = [sm '/AA15_CFG15_PANEL'];
group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

requiredTop = {sm,stack,panel,group28Mux,op28};
for i = 1:numel(requiredTop)
    if getSimulinkBlockHandle(requiredTop{i}) < 0
        error('S13V3:MissingTop','Missing required block: %s',requiredTop{i});
    end
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S13V3:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE13_V3_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S13V3:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify S12 foundation.
% =========================================================================
fprintf('\n--- Verify S12 foundation ---\n');

diagNames = {
    'AA15_STAGE03_DIAGNOSTICS'
    'AA15_STAGE04_AGC_DIAGNOSTICS'
    'AA15_STAGE05_ROUTER_DIAGNOSTICS'
    'AA15_STAGE06_EXECFAULT_DIAGNOSTICS'
    'AA15_STAGE07_TAKEOVER_DIAGNOSTICS'
    'AA15_STAGE08_P_DIAGNOSTICS'
    'AA15_STAGE09_Q_DIAGNOSTICS'
    'AA15_STAGE10_P_AUX_DIAGNOSTICS'
    'AA15_STAGE11_MODE_DIAGNOSTICS'
    'AA15_STAGE12_MODE_ACTUATOR_DIAGNOSTICS'
};

diagBlocks = cell(10,1);
for i = 1:10
    diagBlocks{i} = [sm '/' diagNames{i}];
    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S13V3:MissingPrerequisite', ...
            'Missing S12 prerequisite: %s',diagBlocks{i});
    end
end

requiredS12 = {
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_Device_Mode_Router']
    [sm '/AA15_S12_MODE_LEGACY_TAPS']
    [stack '/AA15_P_Auxiliary_Executor']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Q_Allocator_Router']
};

for i = 1:numel(requiredS12)
    if getSimulinkBlockHandle(requiredS12{i}) < 0
        error('S13V3:MissingPrerequisite', ...
            'Missing S12 prerequisite: %s',requiredS12{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if ~(n28 == 10 || n28 == 11)
    error('S13V3:Group28Inputs', ...
        'Expected Group28 Inputs=10 or partial S13=11, found %g.',n28);
end

for i = 1:10
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S13V3:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

requiredTags = {
    'AA15_SYSTEM_MODE'
    'AA15_MODE_REASON'
    'AA15_S5_EXECUTE_REQUEST'
    'AA15_S15_TRANSITION_REQUEST'
    'AA15_S14_BLACKSTART_REQUEST'
    'AA15_S5_ELECTRICAL_BAD'
    'AA15_S5_COMM_BAD'
    'AA15_MODE_EMERGENCY_ACTIVE'
    'AA15_MODE_SELECTED_MASTER'
    'AA15_MODE_OVERRIDE_ACTIVE'
    'AA15_MODE_ROUTE_VALID'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_MODE_ACTUATION_ENABLE'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotosByTag(mdl,requiredTags{i}))
        error('S13V3:MissingTag','Missing prerequisite GotoTag: %s',requiredTags{i});
    end
end

s12Router = [stack '/AA15_Device_Mode_Router'];
s12ModeFrom = [s12Router '/FROM_MODE_13'];

if getSimulinkBlockHandle(s12ModeFrom) < 0 || ...
        ~strcmp(get_param(s12ModeFrom,'BlockType'),'From')
    error('S13V3:S12ModeFrom','Missing expected S12 mode From.');
end

s12ModeTagAtEntry = get_param(s12ModeFrom,'GotoTag');

if ~any(strcmp(s12ModeTagAtEntry, ...
        {'AA15_SYSTEM_MODE','AA15_EXECUTED_SYSTEM_MODE'}))
    error('S13V3:S12ModeTag', ...
        'Unexpected S12 mode source tag: %s',s12ModeTagAtEntry);
end

fprintf('[OK] S12 Device Mode Router source at entry = %s\n',s12ModeTagAtEntry);

% =========================================================================
% 2. Protect six real device routes.
% =========================================================================
fprintf('\n--- Protect six real device routes ---\n');

dev = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
muxNames = {
    'PV1_IO_Mux12'
    'PV2_IO_Mux12'
    'ESS1_IO_Mux12'
    'ESS2_IO_Mux12'
    'EV1_IO_Mux'
    'EV2_IO_Mux'
};

prefTags = {
    'AA15_FINAL_APPLIED_PV1'
    'AA15_FINAL_APPLIED_PV2'
    'AA15_FINAL_APPLIED_ESS1'
    'AA15_FINAL_APPLIED_ESS2'
    'AA15_FINAL_APPLIED_EV1'
    'AA15_FINAL_APPLIED_EV2'
};

qTags = {
    'AA15_FINAL_QREF_PV1'
    'AA15_FINAL_QREF_PV2'
    'AA15_FINAL_QREF_ESS1'
    'AA15_FINAL_QREF_ESS2'
    'AA15_FINAL_QREF_EV1'
    'AA15_FINAL_QREF_EV2'
};

muxPaths = cell(6,1);
protectFref = cell(6,1);
protectVref = cell(6,1);
protectPref = cell(6,1);
protectQref = cell(6,1);
droopTags = cell(6,1);
gridTags = cell(6,1);

for i = 1:6
    droopTags{i} = ['AA15_FINAL_DROOP_' dev{i}];
    gridTags{i} = ['AA15_FINAL_GRIDON_' dev{i}];

    muxPaths{i} = localFindUniqueNamedBlock(sm,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 8
        error('S13V3:MuxPorts','%s has fewer than 8 inputs.',muxPaths{i});
    end

    [protectFref{i},~] = localGetDestinationSource(ph.Inport(3));
    [protectVref{i},~] = localGetDestinationSource(ph.Inport(4));
    [droopSrc,~] = localGetDestinationSource(ph.Inport(5));
    [protectPref{i},~] = localGetDestinationSource(ph.Inport(6));
    [protectQref{i},~] = localGetDestinationSource(ph.Inport(7));
    [gridSrc,~] = localGetDestinationSource(ph.Inport(8));

    if ~strcmp(get_param(protectPref{i},'BlockType'),'From') || ...
            ~strcmp(get_param(protectPref{i},'GotoTag'),prefTags{i})
        error('S13V3:PrefFoundation','%s Pref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(protectQref{i},'BlockType'),'From') || ...
            ~strcmp(get_param(protectQref{i},'GotoTag'),qTags{i})
        error('S13V3:QFoundation','%s Qref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(droopSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(droopSrc,'GotoTag'),droopTags{i})
        error('S13V3:DroopFoundation','%s Droop route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(gridSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(gridSrc,'GotoTag'),gridTags{i})
        error('S13V3:GridFoundation','%s GridOn route is unexpected.',muxPaths{i});
    end
end

fprintf('[OK] Six physical device routes protected.\n');

% =========================================================================
% 3. Discover current PCC breaker and recover exact legacy source.
% =========================================================================
fprintf('\n--- Recover exact legacy PCC breaker source ---\n');

breaker = localDiscoverPCCBreaker(sm);
fprintf('PCC breaker : %s\n',breaker);

dp = get_param(breaker,'DialogParameters');

if ~isstruct(dp) || ~isfield(dp,'External')
    error('S13V3:BreakerExternalParam', ...
        'Discovered breaker has no External parameter.');
end

if ~strcmpi(get_param(breaker,'External'),'on')
    error('S13V3:BreakerNotExternal', ...
        'Expected current PCC breaker External=on.');
end

bph = get_param(breaker,'PortHandles');
if isempty(bph.Inport)
    error('S13V3:BreakerInput','External PCC breaker has no control input.');
end

breakerFrom = [sm '/AA15_S13_FINAL_BREAKER_TO_PCC'];
legacyTap = [sm '/AA15_S13_BREAKER_LEGACY_TAP'];
legacyTag = 'AA15_LEGACY_PCC_BREAKER_CMD';

[currentBreakerSrcPath,currentBreakerSrcPort] = ...
    localGetDestinationSource(bph.Inport(1));

legacySrcPath = '';
legacySrcPort = -1;

if strcmp(currentBreakerSrcPath,breakerFrom) && ...
        strcmp(get_param(currentBreakerSrcPath,'BlockType'),'From') && ...
        strcmp(get_param(currentBreakerSrcPath,'GotoTag'),'AA15_PCC_BREAKER_CLOSE_CMD')

    if getSimulinkBlockHandle(legacyTap) < 0
        error('S13V3:LegacyTapMissing', ...
            ['Breaker already uses partial S13 final command but legacy tap is missing. ' ...
             'Restore PRE_STAGE13 backup.']);
    end

    lph = get_param(legacyTap,'PortHandles');

    if numel(lph.Inport) ~= 1
        error('S13V3:LegacyTapPorts','Legacy breaker tap must have one input.');
    end

    legacySrcPort = localGetLineSourcePort(lph.Inport(1));
    legacySrcPath = getfullname(get_param(legacySrcPort,'Parent'));

    fprintf('[RECOVER] Breaker current source is partial S13 final route.\n');
    fprintf('[RECOVER] Exact legacy source from tap = %s\n',legacySrcPath);
else
    legacySrcPort = currentBreakerSrcPort;
    legacySrcPath = currentBreakerSrcPath;

    fprintf('[CAPTURE] Current breaker source is legacy source = %s\n',legacySrcPath);
end

fprintf('Legacy breaker block type = %s\n',get_param(legacySrcPath,'BlockType'));

% =========================================================================
% 4. FULL REPAIR to clean S12 baseline before rebuilding S13.
% =========================================================================
fprintf('\n--- Repair partial S13 back to clean S12 baseline ---\n');

% 4a. Restore S12 mode source to RAW before deleting executed-mode publisher.
set_param(s12ModeFrom,'GotoTag','AA15_SYSTEM_MODE');

if ~strcmp(get_param(s12ModeFrom,'GotoTag'),'AA15_SYSTEM_MODE')
    error('S13V3:RepairS12Mode','Could not restore S12 mode source to raw mode.');
end

fprintf('[RESTORE] S12 Device Mode Router <- AA15_SYSTEM_MODE\n');

% 4b. Restore PCC breaker direct legacy source before deleting S13 final route.
bph = get_param(breaker,'PortHandles');
localForcePortConnection(sm,legacySrcPort,bph.Inport(1), ...
    'restore exact legacy PCC breaker source');

[currentBreakerSrcPath,~] = localGetDestinationSource(bph.Inport(1));

if ~strcmp(currentBreakerSrcPath,legacySrcPath)
    error('S13V3:RepairBreaker','Failed to restore exact legacy breaker source.');
end

fprintf('[RESTORE] PCC breaker <- %s\n',legacySrcPath);

% 4c. Clean S13 Group28 slot / diagnostics.
s13Diag = [sm '/AA15_STAGE13_GRID_MODE_DIAGNOSTICS'];

oldDiagPort = localFindExistingLogPort(s13Diag,group28Mux);

if oldDiagPort > 0
    if oldDiagPort ~= 11
        error('S13V3:OldDiagPort', ...
            'Existing S13 diagnostics on unexpected Group28 input%d.',oldDiagPort);
    end
    localDisconnectLogInput(group28Mux,11);
end

if getSimulinkBlockHandle(s13Diag) >= 0
    localDeleteBlockIfExists(s13Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 11
    ph28 = get_param(group28Mux,'PortHandles');

    if numel(ph28.Inport) < 11
        error('S13V3:Group28RepairPort','Cannot inspect Group28 input11.');
    end

    if ~isequal(get_param(ph28.Inport(11),'Line'),-1)
        error('S13V3:Group28RepairBusy','Group28 input11 still connected.');
    end

    set_param(group28Mux,'Inputs','10');
end

% 4d. Delete S13 final breaker From after direct legacy route is restored.
if getSimulinkBlockHandle(breakerFrom) >= 0
    localDeleteBlockIfExists(breakerFrom);
end

% 4e. Delete partial S13 managers and publishers.
execMgr = [stack '/AA15_Grid_Mode_Execution_Manager'];
breakerRouter = [stack '/AA15_PCC_Breaker_Command_Router'];

for i = 1:12
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S13_EXEC_%02d',i)]);
end

for i = 1:8
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S13_BREAKER_%02d',i)]);
end

if getSimulinkBlockHandle(breakerRouter) >= 0
    localDeleteBlockIfExists(breakerRouter);
end

if getSimulinkBlockHandle(execMgr) >= 0
    localDeleteBlockIfExists(execMgr);
end

fprintf('[OK] Partial S13 removed. Model is back to S12 physical baseline.\n');

% =========================================================================
% 5. Create/verify PCC breaker actuation enable.
% =========================================================================
fprintf('\n--- Create/verify CFG15_PCC_BREAKER_ACTUATION_ENABLE ---\n');

breakerEnableTag = 'CFG15_PCC_BREAKER_ACTUATION_ENABLE';
breakerEnableConst = [panel '/' breakerEnableTag];
breakerEnableGoto = [panel '/GOTO_' breakerEnableTag];

localAssertNoForeignGotoTag(mdl,breakerEnableTag,breakerEnableGoto);

if getSimulinkBlockHandle(breakerEnableConst) < 0
    [px,py] = localFindFreePosition(panel,280,40,50);

    add_block('simulink/Sources/Constant',breakerEnableConst, ...
        'Value','0', ...
        'SampleTime','inf', ...
        'OutDataTypeStr','double', ...
        'Position',[px py px+240 py+25]);
else
    if ~strcmp(get_param(breakerEnableConst,'BlockType'),'Constant')
        error('S13V3:BreakerEnableType', ...
            '%s exists but is not Constant.',breakerEnableConst);
    end
    set_param(breakerEnableConst,'SampleTime','inf');
end

if getSimulinkBlockHandle(breakerEnableGoto) < 0
    pos = get_param(breakerEnableConst,'Position');

    add_block('simulink/Signal Routing/Goto',breakerEnableGoto, ...
        'GotoTag',breakerEnableTag, ...
        'TagVisibility','global', ...
        'Position',[pos(3)+40 pos(2) pos(3)+295 pos(2)+24]);
else
    set_param(breakerEnableGoto, ...
        'GotoTag',breakerEnableTag, ...
        'TagVisibility','global');
end

localForceOwnedLine(panel, ...
    [breakerEnableTag '/1'], ...
    ['GOTO_' breakerEnableTag '/1']);

% =========================================================================
% 6. Create/verify legacy breaker tap.
% =========================================================================
fprintf('\n--- Create/verify exact legacy breaker tap ---\n');

if getSimulinkBlockHandle(legacyTap) < 0
    [tx,ty] = localFindFreePosition(sm,350,110,330);

    add_block('simulink/Ports & Subsystems/Subsystem',legacyTap, ...
        'Position',[tx ty tx+350 ty+110]);
    localDeleteSubsystemContents(legacyTap);

    add_block('simulink/Ports & Subsystems/In1', ...
        [legacyTap '/legacy_breaker_cmd'], ...
        'Port','1', ...
        'Position',[20 45 50 61]);

    add_block('simulink/Signal Routing/Goto', ...
        [legacyTap '/GOTO_LEGACY_BREAKER'], ...
        'GotoTag',legacyTag, ...
        'TagVisibility','global', ...
        'Position',[105 42 315 66]);

    localEnsureLine(legacyTap, ...
        'legacy_breaker_cmd/1', ...
        'GOTO_LEGACY_BREAKER/1');

    lph = get_param(legacyTap,'PortHandles');

    localEnsureTopLevelSourceConnection(sm, ...
        legacySrcPort,lph.Inport(1), ...
        'legacy PCC breaker source -> legacy tap');
else
    lph = get_param(legacyTap,'PortHandles');

    if numel(lph.Inport) ~= 1
        error('S13V3:LegacyTapPortCount', ...
            'Existing legacy breaker tap must have exactly one input.');
    end

    if localGetLineSourcePort(lph.Inport(1)) ~= legacySrcPort
        error('S13V3:LegacyTapSourceMismatch', ...
            'Existing legacy breaker tap source differs from recovered legacy source.');
    end

    gotoLegacy = [legacyTap '/GOTO_LEGACY_BREAKER'];

    if getSimulinkBlockHandle(gotoLegacy) < 0
        error('S13V3:LegacyTapIncomplete','Legacy breaker tap is incomplete.');
    end

    set_param(gotoLegacy,'GotoTag',legacyTag,'TagVisibility','global');
end

fprintf('[OK] Legacy breaker command preserved from %s\n',legacySrcPath);

% =========================================================================
% 7. Build LOOP-FREE execution manager.
% =========================================================================
fprintf('\n--- Build loop-free AA15_Grid_Mode_Execution_Manager ---\n');

xExec = localNextRightX(stack,150);

add_block('simulink/Ports & Subsystems/Subsystem',execMgr, ...
    'Position',[xExec 2720 xExec+760 3440]);
localDeleteSubsystemContents(execMgr);

% External inputs.
execInputTags = {
    'AA15_SYSTEM_MODE'                         % 1 dynamic -> z^-1
    'AA15_MODE_REASON'                         % 2 dynamic -> z^-1
    'AA15_S5_EXECUTE_REQUEST'                 % 3 dynamic -> z^-1
    'AA15_S15_TRANSITION_REQUEST'             % 4 dynamic -> z^-1
    'AA15_S14_BLACKSTART_REQUEST'             % 5 dynamic -> z^-1
    'AA15_S5_ELECTRICAL_BAD'                  % 6 dynamic -> z^-1
    'AA15_S5_COMM_BAD'                        % 7 dynamic -> z^-1
    'AA15_MODE_EMERGENCY_ACTIVE'              % 8 dynamic -> z^-1
    'CFG15_MASTER_ENABLE'                     % 9 direct config
    'CFG15_CONTROL_SOURCE'                    % 10 direct config
    'CFG15_MODE_ACTUATION_ENABLE'             % 11 direct config
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'      % 12 direct config
    'AA15_MODE_ROUTE_VALID'                   % 13 downstream diag -> z^-1
};

for i = 1:13
    col = floor((i-1)/7);
    row = mod(i-1,7);
    x = 20 + col*270;
    y = 25 + row*72;

    add_block('simulink/Signal Routing/From', ...
        [execMgr '/' sprintf('FROM_EXEC_%02d',i)], ...
        'GotoTag',execInputTags{i}, ...
        'Position',[x y x+245 y+20]);
end

% Delay all dynamic plant/mode evidence and the downstream S12 route-valid.
delayInputIdx = [1 2 3 4 5 6 7 8 13];
delayIC = {'0','0','0','0','0','0','0','0','1'};

for k = 1:numel(delayInputIdx)
    idx = delayInputIdx(k);
    y = 25 + mod(idx-1,7)*72;
    col = floor((idx-1)/7);
    x = 295 + col*270;

    add_block('simulink/Discrete/Unit Delay', ...
        [execMgr '/' sprintf('DYN_Z1_%02d',idx)], ...
        'InitialCondition',delayIC{k}, ...
        'SampleTime','1e-4', ...
        'Position',[x y x+55 y+28]);

    localEnsureLine(execMgr, ...
        sprintf('FROM_EXEC_%02d/1',idx), ...
        sprintf('DYN_Z1_%02d/1',idx));
end

% Explicit latch states. NO persistent variables inside MATLAB Function.
add_block('simulink/Discrete/Unit Delay', ...
    [execMgr '/ISLAND_LATCH_Z1'], ...
    'InitialCondition','0', ...
    'SampleTime','1e-4', ...
    'Position',[555 555 620 585]);

add_block('simulink/Discrete/Unit Delay', ...
    [execMgr '/BLACK_LATCH_Z1'], ...
    'InitialCondition','0', ...
    'SampleTime','1e-4', ...
    'Position',[555 615 620 645]);

execMF = [execMgr '/AA15_Grid_Mode_Execution_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',execMF, ...
    'Position',[690 125 1195 630]);

chart = localGetEMChartByPath(execMF);
chart.Script = localExecutionManagerScript();

% Core input map:
%  1 raw_mode_z1
%  2 raw_reason_z1
%  3 s5_exec_z1
%  4 s15_req_z1
%  5 s14_req_z1
%  6 electrical_bad_z1
%  7 comm_bad_z1
%  8 emergency_z1
%  9 master_enable direct
% 10 control_source direct
% 11 mode_act_enable direct
% 12 breaker_act_enable direct
% 13 mode_route_valid_z1
% 14 island_latch_prev
% 15 black_latch_prev

for i = 1:8
    localEnsureLine(execMgr, ...
        sprintf('DYN_Z1_%02d/1',i), ...
        sprintf('AA15_Grid_Mode_Execution_Core/%d',i));
end

for i = 9:12
    localEnsureLine(execMgr, ...
        sprintf('FROM_EXEC_%02d/1',i), ...
        sprintf('AA15_Grid_Mode_Execution_Core/%d',i));
end

localEnsureLine(execMgr, ...
    'DYN_Z1_13/1', ...
    'AA15_Grid_Mode_Execution_Core/13');

localEnsureLine(execMgr, ...
    'ISLAND_LATCH_Z1/1', ...
    'AA15_Grid_Mode_Execution_Core/14');

localEnsureLine(execMgr, ...
    'BLACK_LATCH_Z1/1', ...
    'AA15_Grid_Mode_Execution_Core/15');

execOutNames = {
    'executed_system_mode'      % 1
    'requested_breaker_close'  % 2
    'execution_armed'          % 3
    'island_latch_next'        % 4
    'blackstart_latch_next'    % 5
    'reclose_blocked'          % 6
    'trip_reason'              % 7
    'execution_route_valid'    % 8
    'raw_system_mode_echo'     % 9
    'raw_mode_reason_echo'     % 10
};

for i = 1:10
    y = 40 + (i-1)*55;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [execMgr '/' execOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1325 y 1355 y+16]);
end

for i = 1:10
    localEnsureLine(execMgr, ...
        sprintf('AA15_Grid_Mode_Execution_Core/%d',i), ...
        [execOutNames{i} '/1']);
end

% State update feedback goes through Unit Delay, therefore not algebraic.
localEnsureLine(execMgr, ...
    'AA15_Grid_Mode_Execution_Core/4', ...
    'ISLAND_LATCH_Z1/1');

localEnsureLine(execMgr, ...
    'AA15_Grid_Mode_Execution_Core/5', ...
    'BLACK_LATCH_Z1/1');

execTags = {
    'AA15_EXECUTED_SYSTEM_MODE'
    'AA15_PCC_BREAKER_REQUEST_CLOSE'
    'AA15_PCC_BREAKER_EXEC_ARMED'
    'AA15_PCC_ISLAND_LATCH'
    'AA15_PCC_BLACKSTART_LATCH'
    'AA15_PCC_RECLOSE_BLOCKED'
    'AA15_PCC_TRIP_REASON'
    'AA15_PCC_EXECUTION_ROUTE_VALID'
    'AA15_RAW_SYSTEM_MODE_ECHO'
    'AA15_RAW_MODE_REASON_ECHO'
};

execPos = get_param(execMgr,'Position');

for i = 1:10
    gotoName = sprintf('GOTO_S13_EXEC_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',execTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/5);
    row = mod(i-1,5);
    x = execPos(3)+45+col*285;
    y = execPos(2)+35+row*64;

    set_param(p,'Position',[x y x+255 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_Grid_Mode_Execution_Manager/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 8. Build transparent breaker command router.
% =========================================================================
fprintf('\n--- Build transparent PCC breaker command router ---\n');

breakerRouter = [stack '/AA15_PCC_Breaker_Command_Router'];

xBr = execPos(3)+650;

add_block('simulink/Ports & Subsystems/Subsystem',breakerRouter, ...
    'Position',[xBr 2760 xBr+590 3200]);
localDeleteSubsystemContents(breakerRouter);

breakerRouterTags = {
    'AA15_LEGACY_PCC_BREAKER_CMD'
    'AA15_PCC_BREAKER_REQUEST_CLOSE'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_MODE_ACTUATION_ENABLE'
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'
    'AA15_PCC_EXECUTION_ROUTE_VALID'
};

for i = 1:7
    y = 35 + (i-1)*50;

    add_block('simulink/Signal Routing/From', ...
        [breakerRouter '/' sprintf('FROM_BREAKER_%02d',i)], ...
        'GotoTag',breakerRouterTags{i}, ...
        'Position',[20 y 265 y+20]);
end

brMF = [breakerRouter '/AA15_PCC_Breaker_Command_Router_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',brMF, ...
    'Position',[330 85 770 390]);

brChart = localGetEMChartByPath(brMF);
brChart.Script = localBreakerRouterScript();

brOutNames = {
    'final_breaker_close_cmd'
    'legacy_cmd_echo'
    'request_cmd_echo'
    'override_active'
    'route_valid'
};

for i = 1:5
    y = 55 + (i-1)*60;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [breakerRouter '/' brOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[850 y 880 y+16]);
end

for i = 1:7
    localEnsureLine(breakerRouter, ...
        sprintf('FROM_BREAKER_%02d/1',i), ...
        sprintf('AA15_PCC_Breaker_Command_Router_Core/%d',i));
end

for i = 1:5
    localEnsureLine(breakerRouter, ...
        sprintf('AA15_PCC_Breaker_Command_Router_Core/%d',i), ...
        [brOutNames{i} '/1']);
end

breakerTags = {
    'AA15_PCC_BREAKER_CLOSE_CMD'
    'AA15_PCC_BREAKER_LEGACY_ECHO'
    'AA15_PCC_BREAKER_REQUEST_ECHO'
    'AA15_PCC_BREAKER_OVERRIDE_ACTIVE'
    'AA15_PCC_BREAKER_ROUTE_VALID'
};

brPos = get_param(breakerRouter,'Position');

for i = 1:5
    gotoName = sprintf('GOTO_S13_BREAKER_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',breakerTags{i}, ...
        'TagVisibility','global');

    x = brPos(3)+45;
    y = brPos(2)+35+(i-1)*62;

    set_param(p,'Position',[x y x+255 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_PCC_Breaker_Command_Router/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 9. Build diagnostics BEFORE first update.
% =========================================================================
fprintf('\n--- Build S13 V3 diag27 ---\n');

[dx,dy] = localFindFreePosition(sm,565,565,430);

add_block('simulink/Ports & Subsystems/Subsystem',s13Diag, ...
    'Position',[dx dy dx+565 dy+565]);
localDeleteSubsystemContents(s13Diag);

diagTags = {
    'AA15_SYSTEM_MODE'                         % 203
    'AA15_EXECUTED_SYSTEM_MODE'               % 204
    'AA15_LEGACY_PCC_BREAKER_CMD'             % 205
    'AA15_PCC_BREAKER_REQUEST_CLOSE'          % 206
    'AA15_PCC_BREAKER_CLOSE_CMD'              % 207
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'      % 208
    'CFG15_MODE_ACTUATION_ENABLE'             % 209
    'AA15_PCC_BREAKER_EXEC_ARMED'             % 210
    'AA15_PCC_ISLAND_LATCH'                   % 211
    'AA15_PCC_BLACKSTART_LATCH'               % 212
    'AA15_PCC_RECLOSE_BLOCKED'                % 213
    'AA15_PCC_TRIP_REASON'                    % 214
    'AA15_S5_EXECUTE_REQUEST'                 % 215
    'AA15_S15_TRANSITION_REQUEST'             % 216
    'AA15_S14_BLACKSTART_REQUEST'             % 217
    'AA15_S5_ELECTRICAL_BAD'                  % 218
    'AA15_S5_COMM_BAD'                        % 219
    'AA15_MODE_SELECTED_MASTER'               % 220
    'AA15_MODE_OVERRIDE_ACTIVE'               % 221
    'AA15_MODE_ROUTE_VALID'                   % 222
    'AA15_PCC_EXECUTION_ROUTE_VALID'          % 223
    'AA15_MODE_REASON'                        % 224
    'AA15_MODE_EMERGENCY_ACTIVE'              % 225
    'AA15_PCC_BREAKER_OVERRIDE_ACTIVE'        % 226
    'AA15_PCC_BREAKER_ROUTE_VALID'            % 227
    'AA15_PCC_BREAKER_LEGACY_ECHO'            % 228
    'AA15_PCC_BREAKER_REQUEST_ECHO'           % 229
};

for i = 1:27
    col = floor((i-1)/14);
    row = mod(i-1,14);
    x = 20 + col*255;
    y = 18 + row*34;

    add_block('simulink/Signal Routing/From', ...
        [s13Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+230 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s13Diag '/AA15_STAGE13_DIAG27'], ...
    'Inputs','27', ...
    'Position',[580 30 615 525]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s13Diag '/diag27'], ...
    'Port','1', ...
    'Position',[680 270 710 286]);

for i = 1:27
    localEnsureLine(s13Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE13_DIAG27/%d',i));
end

localEnsureLine(s13Diag,'AA15_STAGE13_DIAG27/1','diag27/1');

% =========================================================================
% 10. FIRST UPDATE: complete loop-free calculation structure only.
% =========================================================================
fprintf('\n--- First update: prove algebraic-loop removal BEFORE real takeover ---\n');

set_param(mdl,'SimulationCommand','update');

execPorts = get_param(execMF,'Ports');

if execPorts(1) ~= 15 || execPorts(2) ~= 10
    error('S13V3:ExecPorts', ...
        'Execution core expected 15-in/10-out, found %d/%d.', ...
        execPorts(1),execPorts(2));
end

brPorts = get_param(brMF,'Ports');

if brPorts(1) ~= 7 || brPorts(2) ~= 5
    error('S13V3:BreakerRouterPorts', ...
        'Breaker router expected 7-in/5-out, found %d/%d.', ...
        brPorts(1),brPorts(2));
end

fprintf('[PASS] Model update succeeded with explicit Unit Delay state architecture.\n');
fprintf('[PASS] No S12<->S13 direct algebraic feedback remains.\n');

% =========================================================================
% 11. Retarget S12 to executed mode AFTER loop-free update passes.
% =========================================================================
fprintf('\n--- Retarget S12 Device Mode Router to executed mode ---\n');

set_param(s12ModeFrom,'GotoTag','AA15_EXECUTED_SYSTEM_MODE');

set_param(mdl,'SimulationCommand','update');

if ~strcmp(get_param(s12ModeFrom,'GotoTag'),'AA15_EXECUTED_SYSTEM_MODE')
    error('S13V3:S12Retarget','Failed to retarget S12 mode source.');
end

fprintf('[PASS] Update succeeds with S12 reading executed mode.\n');

% =========================================================================
% 12. Real breaker destination takeover, transparent by default.
% =========================================================================
fprintf('\n--- Real PCC breaker destination takeover ---\n');

bph = get_param(breaker,'PortHandles');

if isempty(bph.Inport)
    error('S13V3:BreakerInputMissing','PCC breaker external input is missing.');
end

if getSimulinkBlockHandle(breakerFrom) < 0
    bpos = get_param(breaker,'Position');

    add_block('simulink/Signal Routing/From',breakerFrom, ...
        'GotoTag','AA15_PCC_BREAKER_CLOSE_CMD', ...
        'Position',[max(20,bpos(1)-310) bpos(2)+45 ...
                    max(20,bpos(1)-80) bpos(2)+67]);
else
    set_param(breakerFrom,'GotoTag','AA15_PCC_BREAKER_CLOSE_CMD');
end

bfPH = get_param(breakerFrom,'PortHandles');

localForcePortConnection(sm,bfPH.Outport(1),bph.Inport(1), ...
    'S13 V3 final breaker command -> PCC breaker');

set_param(mdl,'SimulationCommand','update');

fprintf('[PASS] Breaker final route update succeeds.\n');

% =========================================================================
% 13. Append S13 diag27 to Group28 input11.
% =========================================================================
fprintf('\n--- Append S13 V3 diag27 to Group28 input11 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 10
    error('S13V3:Group28BeforeAppend', ...
        'Expected Group28 Inputs=10 before S13 append.');
end

set_param(group28Mux,'Inputs','11');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s13Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S13V3:DiagPort','S13 diagnostics expected exactly one output.');
end

if numel(muxPH28.Inport) < 11
    error('S13V3:Group28Input11','Group28 input11 did not materialize.');
end

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(11), ...
    'S13 V3 diag27 -> Group28 input11');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 14. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S13 V3 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 11
    error('S13V3:Group28Final','Group28 must have 11 physical inputs.');
end

for i = 1:10
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);

    if p ~= i
        error('S13V3:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.', ...
            diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s13Diag,group28Mux) ~= 11
    error('S13V3:S13DiagSlot','S13 diagnostics is not Group28 input11.');
end

% Legacy source still preserved in parallel tap.
lph = get_param(legacyTap,'PortHandles');

if localGetLineSourcePort(lph.Inport(1)) ~= legacySrcPort
    error('S13V3:LegacySourceChanged', ...
        'Legacy PCC breaker source changed unexpectedly.');
end

% Breaker final source.
bph = get_param(breaker,'PortHandles');
[bFinalSrc,~] = localGetDestinationSource(bph.Inport(1));

if ~strcmp(bFinalSrc,breakerFrom) || ...
        ~strcmp(get_param(bFinalSrc,'GotoTag'),'AA15_PCC_BREAKER_CLOSE_CMD')
    error('S13V3:BreakerRouteFinal', ...
        'PCC breaker does not use S13 V3 final breaker command.');
end

% S12 uses executed mode.
if ~strcmp(get_param(s12ModeFrom,'GotoTag'),'AA15_EXECUTED_SYSTEM_MODE')
    error('S13V3:S12ModeFinal', ...
        'S12 Device Mode Router is not reading executed mode.');
end

% Verify Unit Delay state architecture exists.
requiredDelays = {
    [execMgr '/DYN_Z1_01']
    [execMgr '/DYN_Z1_02']
    [execMgr '/DYN_Z1_03']
    [execMgr '/DYN_Z1_04']
    [execMgr '/DYN_Z1_05']
    [execMgr '/DYN_Z1_06']
    [execMgr '/DYN_Z1_07']
    [execMgr '/DYN_Z1_08']
    [execMgr '/DYN_Z1_13']
    [execMgr '/ISLAND_LATCH_Z1']
    [execMgr '/BLACK_LATCH_Z1']
};

for i = 1:numel(requiredDelays)
    if getSimulinkBlockHandle(requiredDelays{i}) < 0 || ...
            ~strcmp(get_param(requiredDelays{i},'BlockType'),'UnitDelay')
        error('S13V3:DelayMissing', ...
            'Missing expected Unit Delay: %s',requiredDelays{i});
    end
end

% No persistent state in the execution MATLAB Function.
execChart = localGetEMChartByPath(execMF);
if contains(lower(execChart.Script),'persistent')
    error('S13V3:PersistentStillPresent', ...
        'Execution Core still contains persistent state.');
end

% Six device routes stay protected.
for i = 1:6
    ph = get_param(muxPaths{i},'PortHandles');

    [f3,~] = localGetDestinationSource(ph.Inport(3));
    [f4,~] = localGetDestinationSource(ph.Inport(4));
    [f5,~] = localGetDestinationSource(ph.Inport(5));
    [f6,~] = localGetDestinationSource(ph.Inport(6));
    [f7,~] = localGetDestinationSource(ph.Inport(7));
    [f8,~] = localGetDestinationSource(ph.Inport(8));

    if ~strcmp(f3,protectFref{i})
        error('S13V3:FrefChanged','%s Fref input3 changed.',muxPaths{i});
    end

    if ~strcmp(f4,protectVref{i})
        error('S13V3:VrefChanged','%s Vref input4 changed.',muxPaths{i});
    end

    if ~strcmp(f6,protectPref{i}) || ...
            ~strcmp(get_param(f6,'GotoTag'),prefTags{i})
        error('S13V3:PrefChanged','%s Pref input6 changed.',muxPaths{i});
    end

    if ~strcmp(f7,protectQref{i}) || ...
            ~strcmp(get_param(f7,'GotoTag'),qTags{i})
        error('S13V3:QrefChanged','%s Qref input7 changed.',muxPaths{i});
    end

    if ~strcmp(get_param(f5,'BlockType'),'From') || ...
            ~strcmp(get_param(f5,'GotoTag'),droopTags{i})
        error('S13V3:DroopChanged','%s Droop input5 changed.',muxPaths{i});
    end

    if ~strcmp(get_param(f8,'BlockType'),'From') || ...
            ~strcmp(get_param(f8,'GotoTag'),gridTags{i})
        error('S13V3:GridChanged','%s GridOn input8 changed.',muxPaths{i});
    end
end

% Safe saved defaults.
set_param(breakerEnableConst,'Value','0');

modeActConst = [panel '/CFG15_MODE_ACTUATION_ENABLE'];

if getSimulinkBlockHandle(modeActConst) >= 0 && ...
        strcmp(get_param(modeActConst,'BlockType'),'Constant')
    set_param(modeActConst,'Value','0');
end

allNewTags = [
    {
    breakerEnableTag
    legacyTag
    }
    execTags
    breakerTags
];

for i = 1:numel(allNewTags)
    localAssertSingleGlobalGoto(mdl,allNewTags{i});
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE13 V3 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Root algebraic feedback             : REMOVED\n');
fprintf('Persistent state in MATLAB Function : REMOVED\n');
fprintf('Dynamic S11 evidence delay          : 1 sample = 100 us\n');
fprintf('S12 route-valid feedback            : delayed 1 sample\n');
fprintf('Island latch state                  : explicit Unit Delay\n');
fprintf('Black-start latch state             : explicit Unit Delay\n');
fprintf('PCC breaker legacy source           : %s\n',legacySrcPath);
fprintf('Default breaker behavior            : exact legacy passthrough\n');
fprintf('S12 mode source                     : AA15_EXECUTED_SYSTEM_MODE\n');
fprintf('Communication-only trip             : BLOCKED\n');
fprintf('Automatic LOCAL15 reclose           : DISABLED in S13\n');
fprintf('CFG15_MODE_ACTUATION_ENABLE         : saved default 0\n');
fprintf('CFG15_PCC_BREAKER_ACTUATION_ENABLE : saved default 0\n');
fprintf('Six Pref/Qref/Fref/Vref             : UNCHANGED\n');
fprintf('Six Droop/GridOn                    : S12 final routes preserved\n');
fprintf('Group28 scalar signals              : 229\n');
fprintf('Expected MAT rows                   : 230 incl. Target Time\n');
fprintf('Backup                              : %s\n',backupFile);
fprintf('\nNEXT: RT-LAB Rebuild All now for S11 + S12 + S13 V3.\n');
fprintf('FIRST Load test keeps BOTH actuation enables = 0.\n');

end


% =========================================================================
% LOOP-FREE execution core
% =========================================================================
function txt = localExecutionManagerScript()

L = {};
L{end+1} = ['function [exec_mode,request_close,armed,island_next,black_next,' ...
    'reclose_blocked,trip_reason,route_valid,raw_mode_echo,raw_reason_echo] = ' ...
    'AA15_Grid_Mode_Execution_Core(' ...
    'raw_mode_z1,raw_reason_z1,s5_exec_z1,s15_req_z1,s14_req_z1,' ...
    'electrical_bad_z1,comm_bad_z1,emergency_z1,' ...
    'master_enable,control_source,mode_act_enable,breaker_act_enable,' ...
    'mode_route_valid_z1,island_prev,black_prev)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'raw_mode_echo = raw_mode_z1;';
L{end+1} = 'raw_reason_echo = raw_reason_z1;';
L{end+1} = 'request_close = 1.0;';
L{end+1} = 'armed = 0.0;';
L{end+1} = 'route_valid = 1.0;';
L{end+1} = 'reclose_blocked = 0.0;';
L{end+1} = 'trip_reason = 0.0;';
L{end+1} = 'island_next = double(island_prev > 0.5);';
L{end+1} = 'black_next = double(black_prev > 0.5);';
L{end+1} = '';
L{end+1} = 'if finite1(raw_mode_z1) && round(raw_mode_z1)==1';
L{end+1} = '    exec_mode = 1.0;';
L{end+1} = 'else';
L{end+1} = '    exec_mode = 0.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if ~finite1(raw_mode_z1)||~finite1(raw_reason_z1)||...';
L{end+1} = '   ~finite1(s5_exec_z1)||~finite1(s15_req_z1)||...';
L{end+1} = '   ~finite1(s14_req_z1)||~finite1(electrical_bad_z1)||...';
L{end+1} = '   ~finite1(comm_bad_z1)||~finite1(emergency_z1)||...';
L{end+1} = '   ~finite1(mode_route_valid_z1)||...';
L{end+1} = '   ~finite1(island_prev)||~finite1(black_prev)';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    exec_mode = 6.0;';
L{end+1} = '    request_close = 1.0;';
L{end+1} = '    island_next = 0.0;';
L{end+1} = '    black_next = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'framework_on = (master_enable>0.5) && (round(control_source)==1);';
L{end+1} = 'both_act = (mode_act_enable>0.5) && (breaker_act_enable>0.5);';
L{end+1} = 'armed = double(framework_on && both_act && mode_route_valid_z1>0.5);';
L{end+1} = '';
L{end+1} = '% If coordinated physical execution is not armed, clear real latches.';
L{end+1} = 'if armed < 0.5';
L{end+1} = '    island_next = 0.0;';
L{end+1} = '    black_next = 0.0;';
L{end+1} = '    request_close = 1.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Existing S14 black-start request has highest priority.';
L{end+1} = 'if s14_req_z1 > 0.5';
L{end+1} = '    black_next = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Existing S5 electrical qualifier + existing S15 transition request.';
L{end+1} = 'if black_next < 0.5 && s5_exec_z1 > 0.5 && s15_req_z1 > 0.5';
L{end+1} = '    island_next = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if black_next > 0.5';
L{end+1} = '    exec_mode = 4.0;';
L{end+1} = '    request_close = 0.0;';
L{end+1} = '    reclose_blocked = 1.0;';
L{end+1} = '    trip_reason = 14.0;';
L{end+1} = 'elseif island_next > 0.5';
L{end+1} = '    exec_mode = 3.0;';
L{end+1} = '    request_close = 0.0;';
L{end+1} = '    reclose_blocked = 1.0;';
L{end+1} = '    trip_reason = 15.0;';
L{end+1} = 'else';
L{end+1} = '    if round(raw_mode_z1)==1';
L{end+1} = '        exec_mode = 1.0;';
L{end+1} = '    else';
L{end+1} = '        exec_mode = 0.0;';
L{end+1} = '    end';
L{end+1} = '    request_close = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Communication-only abnormality can never open PCC by itself.';
L{end+1} = 'if electrical_bad_z1 < 0.5 && comm_bad_z1 > 0.5 && ...';
L{end+1} = '   black_next < 0.5 && island_next < 0.5';
L{end+1} = '    request_close = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'dummy = emergency_z1 + raw_reason_z1;';
L{end+1} = 'if dummy > 1e300, trip_reason = trip_reason + 0.0; end';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function ok = finite1(x)';
L{end+1} = 'ok = ~(isnan(x) || isinf(x));';
L{end+1} = 'end';

txt = strjoin(L,newline);

end


% =========================================================================
% Breaker router source
% =========================================================================
function txt = localBreakerRouterScript()

L = {};
L{end+1} = ['function [final_cmd,legacy_echo,request_echo,override_active,' ...
    'route_valid] = AA15_PCC_Breaker_Command_Router_Core(' ...
    'legacy_cmd,request_close,master_enable,control_source,' ...
    'mode_act_enable,breaker_act_enable,exec_route_valid)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'legacy_echo = legacy_cmd;';
L{end+1} = 'request_echo = request_close;';
L{end+1} = 'final_cmd = legacy_cmd;';
L{end+1} = 'override_active = 0.0;';
L{end+1} = 'route_valid = 1.0;';
L{end+1} = '';
L{end+1} = 'if ~finite1(legacy_cmd)||~finite1(request_close)||~finite1(exec_route_valid)';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'armed = (master_enable>0.5) && (round(control_source)==1) && ...';
L{end+1} = '        (mode_act_enable>0.5) && (breaker_act_enable>0.5) && ...';
L{end+1} = '        (exec_route_valid>0.5);';
L{end+1} = '';
L{end+1} = 'if armed';
L{end+1} = '    final_cmd = double(request_close>0.5);';
L{end+1} = '    override_active = 1.0;';
L{end+1} = 'else';
L{end+1} = '    final_cmd = legacy_cmd;';
L{end+1} = 'end';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function ok = finite1(x)';
L{end+1} = 'ok = ~(isnan(x) || isinf(x));';
L{end+1} = 'end';

txt = strjoin(L,newline);

end


% =========================================================================
% Helpers
% =========================================================================
function breaker = localDiscoverPCCBreaker(sm)

exact = [sm '/Three-Phase Breaker'];

if getSimulinkBlockHandle(exact) >= 0
    breaker = exact;
    return;
end

try
    blocks = find_system(sm, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block');
catch
    blocks = find_system(sm, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'Type','Block');
end

hits = {};

for i = 1:numel(blocks)
    if strcmp(blocks{i},sm)
        continue;
    end

    nm = lower(get_param(blocks{i},'Name'));

    if ~contains(nm,'breaker')
        continue;
    end

    try
        dp = get_param(blocks{i},'DialogParameters');
    catch
        dp = struct();
    end

    if isstruct(dp) && isfield(dp,'External')
        hits{end+1,1} = blocks{i}; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    fprintf('Candidate PCC breakers found: %d\n',numel(hits));
    for i = 1:numel(hits)
        fprintf('  %s\n',hits{i});
    end
    error('S13V3:BreakerAmbiguous', ...
        'Could not uniquely identify the PCC Three-Phase Breaker.');
end

breaker = hits{1};

end


function chart = localGetEMChartByPath(blockPath)

rt = sfroot;
charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);

if isempty(charts)
    drawnow;
    rt = sfroot;
    charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);
end

if numel(charts) ~= 1
    error('S13V3:EMChartPath', ...
        'Expected one Stateflow.EMChart at %s, found %d.', ...
        blockPath,numel(charts));
end

chart = charts(1);

end


function hits = localFindBlocksByName(root,name)

try
    hits = find_system(root, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block', ...
        'Name',name);
catch
    hits = find_system(root, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'Variants','AllVariants', ...
        'Type','Block', ...
        'Name',name);
end

end


function blockPath = localFindUniqueNamedBlock(root,name)

hits = localFindBlocksByName(root,name);

if numel(hits) ~= 1
    error('S13V3:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S13V3:UndrivenDestination','Protected destination is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isempty(srcPort) || srcPort < 0
    error('S13V3:NoSourcePort','Could not resolve source port.');
end

srcPath = getfullname(get_param(srcPort,'Parent'));

end


function srcPort = localGetLineSourcePort(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S13V3:TapInputUndriven','Tap input is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isempty(srcPort) || srcPort < 0
    error('S13V3:TapInputNoSource','Cannot resolve tap input source.');
end

end


function localEnsureLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S13V3:LinePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

srcPort = srcPH.Outport(srcIdx);
dstPort = dstPH.Inport(dstIdx);
ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

if get_param(ln,'SrcPortHandle') ~= srcPort
    error('S13V3:LineDriven','Destination %s already has another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S13V3:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

localForcePortConnection(parent, ...
    srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));

end


function [path,idx] = localParseRelativePort(parent,spec)

slash = find(spec=='/',1,'last');

if isempty(slash)
    error('S13V3:PortSpec','Port spec must be block/port: %s',spec);
end

blockRel = spec(1:slash-1);
idx = str2double(spec(slash+1:end));

if isnan(idx) || idx < 1
    error('S13V3:PortSpec','Invalid port index in %s.',spec);
end

path = [parent '/' blockRel];

if getSimulinkBlockHandle(path) < 0
    error('S13V3:PortBlockMissing','Missing block: %s',path);
end

end


function localEnsureTopLevelSourceConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

if get_param(ln,'SrcPortHandle') ~= srcPort
    error('S13V3:TopConnection', ...
        'Destination for %s already has another source.',desc);
end

end


function localForcePortConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if ~isequal(ln,-1)
    existingSrc = get_param(ln,'SrcPortHandle');

    if existingSrc == srcPort
        return;
    end

    localDisconnectDestinationBranch(parent,dstPort);
end

add_line(parent,srcPort,dstPort,'autorouting','on');

ln = get_param(dstPort,'Line');

if isequal(ln,-1) || get_param(ln,'SrcPortHandle') ~= srcPort
    error('S13V3:ForceConnection','Post-assert failed for %s.',desc);
end

end


function localDisconnectDestinationBranch(parent,dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    return;
end

srcPort = get_param(ln,'SrcPortHandle');
dstPorts = get_param(ln,'DstPortHandle');
dstPorts = dstPorts(dstPorts >= 0);

if numel(dstPorts) <= 1
    delete_line(ln);
    return;
end

try
    delete_line(parent,srcPort,dstPort);
catch ME
    error('S13V3:BranchDelete', ...
        ['Could not remove only requested branch. Whole shared-trunk deletion ' ...
         'is forbidden. %s'],ME.message);
end

end


function localDisconnectLogInput(groupMux,portNo)

ph = get_param(groupMux,'PortHandles');

if numel(ph.Inport) < portNo
    return;
end

if isequal(get_param(ph.Inport(portNo),'Line'),-1)
    return;
end

parent = get_param(groupMux,'Parent');
localDisconnectDestinationBranch(parent,ph.Inport(portNo));

end


function localDeleteBlockIfExists(blockPath)

if getSimulinkBlockHandle(blockPath) < 0
    return;
end

parent = get_param(blockPath,'Parent');

try
    ph = get_param(blockPath,'PortHandles');
    incomingFields = {'Inport','Enable','Trigger','Ifaction','Reset'};

    for i = 1:numel(incomingFields)
        fld = incomingFields{i};

        if ~isfield(ph,fld)
            continue;
        end

        ports = ph.(fld);

        for j = 1:numel(ports)
            localDisconnectDestinationBranch(parent,ports(j));
        end
    end

    if isfield(ph,'Outport')
        lines = [];

        for j = 1:numel(ph.Outport)
            ln = get_param(ph.Outport(j),'Line');

            if ~isequal(ln,-1)
                lines(end+1) = ln; %#ok<AGROW>
            end
        end

        lines = unique(lines(lines >= 0));

        for j = 1:numel(lines)
            try
                delete_line(lines(j));
            catch
            end
        end
    end
catch ME
    if startsWith(ME.identifier,'S13V3:')
        rethrow(ME);
    end
end

delete_block(blockPath);

end


function localDeleteSubsystemContents(subsys)

if getSimulinkBlockHandle(subsys) < 0
    return;
end

try
    Simulink.SubSystem.deleteContents(subsys);
    return;
catch
end

try
    try
        lines = find_system(subsys, ...
            'FindAll','on', ...
            'SearchDepth',1, ...
            'MatchFilter',@Simulink.match.allVariants, ...
            'Type','line');
    catch
        lines = find_system(subsys, ...
            'FindAll','on', ...
            'SearchDepth',1, ...
            'Variants','AllVariants', ...
            'Type','line');
    end

    lines = unique(lines(lines >= 0));

    for i = 1:numel(lines)
        try
            delete_line(lines(i));
        catch
        end
    end
catch
end

try
    blocks = find_system(subsys, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block');
catch
    blocks = find_system(subsys, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'Type','Block');
end

for i = 1:numel(blocks)
    if strcmp(blocks{i},subsys)
        continue;
    end

    try
        delete_block(blocks{i});
    catch
    end
end

end


function p = localFindExistingLogPort(sourceBlock,logMux)

p = 0;

if getSimulinkBlockHandle(sourceBlock) < 0 || ...
        getSimulinkBlockHandle(logMux) < 0
    return;
end

srcPH = get_param(sourceBlock,'PortHandles');

if isempty(srcPH.Outport)
    return;
end

ln = get_param(srcPH.Outport(1),'Line');

if isequal(ln,-1)
    return;
end

try
    dst = get_param(ln,'DstPortHandle');
catch
    dst = [];
end

dst = dst(dst >= 0);
muxPH = get_param(logMux,'PortHandles');

for i = 1:numel(dst)
    hit = find(muxPH.Inport == dst(i),1,'first');

    if ~isempty(hit)
        p = hit;
        return;
    end
end

end


function gotos = localFindGotosByTag(mdl,tag)

try
    allg = find_system(mdl, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'BlockType','Goto');
catch
    allg = find_system(mdl, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'Variants','AllVariants', ...
        'BlockType','Goto');
end

gotos = {};

for i = 1:numel(allg)
    try
        if strcmp(get_param(allg{i},'GotoTag'),tag)
            gotos{end+1,1} = allg{i}; %#ok<AGROW>
        end
    catch
    end
end

end


function localAssertNoForeignGotoTag(mdl,tag,expectedPath)

g = localFindGotosByTag(mdl,tag);

for i = 1:numel(g)
    if ~strcmp(g{i},expectedPath)
        error('S13V3:ForeignGoto', ...
            'GotoTag %s already exists at unexpected path %s.',tag,g{i});
    end
end

end


function localAssertSingleGlobalGoto(mdl,tag)

g = localFindGotosByTag(mdl,tag);

if numel(g) ~= 1
    error('S13V3:GlobalGotoCount', ...
        'Expected exactly one Goto for tag %s, found %d.',tag,numel(g));
end

end


function x = localNextRightX(parent,margin)

try
    blocks = find_system(parent, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block');
catch
    blocks = find_system(parent, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'Type','Block');
end

maxRight = 0;

for i = 1:numel(blocks)
    if strcmp(blocks{i},parent)
        continue;
    end

    try
        pos = get_param(blocks{i},'Position');
        maxRight = max(maxRight,pos(3));
    catch
    end
end

x = maxRight + margin;

end


function [x,y] = localFindFreePosition(parent,w,h,margin)

try
    blocks = find_system(parent, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block');
catch
    blocks = find_system(parent, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'Type','Block');
end

rects = [];

for i = 1:numel(blocks)
    if strcmp(blocks{i},parent)
        continue;
    end

    try
        p = get_param(blocks{i},'Position');

        if numel(p) == 4
            rects(end+1,:) = p; %#ok<AGROW>
        end
    catch
    end
end

if isempty(rects)
    x = 50;
    y = 50;
    return;
end

x = max(rects(:,3)) + margin;
y = 80;

if localRectOverlaps([x y x+w y+h],rects)
    y = max(rects(:,4)) + margin;
end

end


function tf = localRectOverlaps(r,rects)

tf = false;

for i = 1:size(rects,1)
    q = rects(i,:);

    separated = r(3) < q(1) || r(1) > q(3) || ...
                r(4) < q(2) || r(2) > q(4);

    if ~separated
        tf = true;
        return;
    end
end

end

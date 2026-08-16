function S14_K26_V5_LOCAL15_BLACKSTART_PREF_SEQUENCE_AND_FINAL_INTEGRATION
% S14_K26_V5_LOCAL15_BLACKSTART_PREF_SEQUENCE_AND_FINAL_INTEGRATION
%
% LOCAL15 Stage 14 - final model-side integration stage
%
% PURPOSE
% -------
% Complete the EXISTING Strategy 14 black-start execution path without
% modifying the original Advanced_Microgrid_15_Strategies algorithm.
%
% Existing chain before S14:
%
%   Original S14 black_state/cmd
%       -> S11 S14_blackstart_request
%       -> S13 black-start latch
%       -> executed_system_mode = 4
%       -> PCC breaker OPEN
%       -> S12 selected ESS master becomes GFM
%
% Missing before S14:
%   The six active-power commands were still the normal LOCAL15 commands.
%   Therefore the original S14 stages did not yet control the DER/load
%   restoration sequence.
%
% S14 inserts:
%
%   S10 P Auxiliary Executor
%        -> AA15_Black_Start_Pref_Gate
%        -> S05 Command Source Router LOCAL15 inputs7..13
%
% Normal/non-black-start behavior is EXACT passthrough.
%
% Black-start staged behavior, using the existing S14 stage:
%
%   stage 1:
%       all six Pref = 0
%       PCC is open and selected ESS master is already GFM through S13/S12
%       -> establish island voltage/frequency with zero active-power reference
%
%   stage 2:
%       master ESS Pref remains 0
%       non-master ESS may restore its pre-gate LOCAL15 Pref
%       PV = 0
%       EV = 0
%
%   stage 3:
%       ESS as above
%       PV1/PV2 restore their pre-gate LOCAL15 Pref, clamped to [0,1]
%       EV remains 0
%
%   stage 4:
%       ESS + PV remain restored
%       EV1/EV2 restore their pre-gate LOCAL15 charging Pref, clamped [-1,0]
%
% This is execution infrastructure for the EXISTING S14 stage machine.
% No new strategy number is introduced.
%
% IMPORTANT CURRENT-MODEL LIMIT
% -----------------------------
% The present six-device control vector has no independent DeviceEnable input.
% Therefore "device restoration" in S14 is implemented as staged Pref release,
% together with the already-existing S12 GridOn/Droop mode control.
% It is NOT an electrical contactor-level device disconnect/reconnect.
%
% S14 also repairs one execution-semantic issue in S11:
%
%   old:
%       abs(S14_cmd) > 0.5
%
%   problem:
%       original S14 uses black_state = -1 when SOC is too low.
%       -1 means black-start failure/abort, not a valid start request.
%       abs(-1)>0.5 incorrectly qualified it as a black-start request.
%
%   new execution qualifier:
%       S14_cmd > 0.5
%
% The ORIGINAL Strategy 14 algorithm itself is unchanged.
%
% NEW TUNABLE PARAMETER
% ---------------------
%   CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE
%
%   0 = transparent passthrough (saved default)
%   1 = allow staged S14 Pref execution when executed_mode=BLACK_START
%
% Real black-start execution therefore requires:
%
%   CFG15_MASTER_ENABLE = 1
%   CFG15_CONTROL_SOURCE = 1
%   CFG15_EXEC_S14 = 1
%   original S14 bs input = 1
%   CFG15_MODE_ACTUATION_ENABLE = 1
%   CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1
%   CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE = 1
%
% GROUP28
% -------
% S13 V3 total = 229 scalar signals.
% S14 appends 32:
%
%   230 S14_status
%   231 S14_alarm
%   232 S14_metric
%   233 S14_cmd_raw
%   234 blackstart_pref_sequence_enable
%   235 blackstart_pref_sequence_active
%   236 blackstart_stage_echo
%   237 selected_master_echo
%   238..243 aux Pref input [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   244 aux_valid_input
%   245..250 gated Pref [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   251 gated_valid
%   252 executed_system_mode
%   253 final_breaker_cmd
%   254 device_mode_override_active
%   255 breaker_override_active
%   256 final_gridon_ESS1
%   257 final_gridon_ESS2
%   258 final_droop_ESS1
%   259 final_droop_ESS2
%   260 blackstart_latch
%   261 blackstart_pref_gate_route_valid
%
% Final Group28 = 261 scalar signals.
% Expected MAT = 262 rows including Target Time.
%
% FINAL BUILD POLICY
% ------------------
% S14 changes the REAL LOCAL15 Pref route.
% After STAGE14 COMPLETE:
%   RT-LAB Rebuild All is REQUIRED.
%
% First post-build run:
%   keep CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE = 0
%   keep the two mode/breaker actuation enables = 0
%   verify transparent regression first.
%
% SCRIPT SAFETY
% -------------
% - mdl = bdroot(gcs)
% - backup first
% - verifies S13 V3 foundation
% - repairs a partial S14 by restoring Router inputs7..13 to S10 aux first
% - never deletes shared source trunks
% - fixes only the S11 execution qualifier; original 15-strategy core untouched
% - completes full S14 structure before first model update
% - exact post-assertions on Pref/Qref/Fref/Vref/Droop/GridOn and breaker route
% - Variant-aware find_system

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 14 - Black Start Pref Sequence + Final Integration\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S14:NoActiveModel', ...
        'Open K26_V5 and click inside it before running S14.');
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
        error('S14:MissingTop','Missing required block: %s',requiredTop{i});
    end
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S14:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE14_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S14:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify S13 V3 foundation and Group28.
% =========================================================================
fprintf('\n--- Verify S13 V3 foundation ---\n');

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
    'AA15_STAGE13_GRID_MODE_DIAGNOSTICS'
};

diagBlocks = cell(11,1);
for i = 1:11
    diagBlocks{i} = [sm '/' diagNames{i}];
    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S14:MissingPrerequisite', ...
            'Missing S13 prerequisite: %s',diagBlocks{i});
    end
end

requiredS13 = {
    [stack '/AA15_P_Auxiliary_Executor']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_Device_Mode_Router']
    [stack '/AA15_Grid_Mode_Execution_Manager']
    [stack '/AA15_PCC_Breaker_Command_Router']
    [sm '/AA15_S13_BREAKER_LEGACY_TAP']
    [sm '/AA15_S13_FINAL_BREAKER_TO_PCC']
};

for i = 1:numel(requiredS13)
    if getSimulinkBlockHandle(requiredS13{i}) < 0
        error('S14:MissingPrerequisite', ...
            'Missing S13 prerequisite: %s',requiredS13{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if ~(n28 == 11 || n28 == 12)
    error('S14:Group28Inputs', ...
        'Expected Group28 Inputs=11 (S13) or 12 (partial S14), found %g.',n28);
end

for i = 1:11
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S14:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

requiredTags = {
    'AA15_S14_STATUS'
    'AA15_S14_ALARM'
    'AA15_S14_METRIC'
    'AA15_S14_CMD_RAW'
    'AA15_EXECUTED_SYSTEM_MODE'
    'AA15_MODE_SELECTED_MASTER'
    'AA15_PCC_BREAKER_CLOSE_CMD'
    'AA15_MODE_OVERRIDE_ACTIVE'
    'AA15_PCC_BREAKER_OVERRIDE_ACTIVE'
    'AA15_FINAL_GRIDON_ESS1'
    'AA15_FINAL_GRIDON_ESS2'
    'AA15_FINAL_DROOP_ESS1'
    'AA15_FINAL_DROOP_ESS2'
    'AA15_PCC_BLACKSTART_LATCH'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_EXEC_S14'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotosByTag(mdl,requiredTags{i}))
        error('S14:MissingTag','Missing required tag: %s',requiredTags{i});
    end
end

fprintf('[OK] S13 V3 prerequisite blocks/tags/Group28 verified.\n');

% =========================================================================
% 2. Protect all six physical device Mux routes and breaker route.
% =========================================================================
fprintf('\n--- Protect physical device and breaker routes ---\n');

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

droopTags = cell(6,1);
gridTags = cell(6,1);
muxPaths = cell(6,1);

protectFref = cell(6,1);
protectVref = cell(6,1);
protectPref = cell(6,1);
protectQref = cell(6,1);

for i = 1:6
    droopTags{i} = ['AA15_FINAL_DROOP_' dev{i}];
    gridTags{i} = ['AA15_FINAL_GRIDON_' dev{i}];

    muxPaths{i} = localFindUniqueNamedBlock(sm,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 8
        error('S14:MuxPorts','%s has fewer than 8 inputs.',muxPaths{i});
    end

    [protectFref{i},~] = localGetDestinationSource(ph.Inport(3));
    [protectVref{i},~] = localGetDestinationSource(ph.Inport(4));
    [droopSrc,~] = localGetDestinationSource(ph.Inport(5));
    [protectPref{i},~] = localGetDestinationSource(ph.Inport(6));
    [protectQref{i},~] = localGetDestinationSource(ph.Inport(7));
    [gridSrc,~] = localGetDestinationSource(ph.Inport(8));

    if ~strcmp(get_param(protectPref{i},'BlockType'),'From') || ...
            ~strcmp(get_param(protectPref{i},'GotoTag'),prefTags{i})
        error('S14:PrefFoundation','%s Pref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(protectQref{i},'BlockType'),'From') || ...
            ~strcmp(get_param(protectQref{i},'GotoTag'),qTags{i})
        error('S14:QFoundation','%s Qref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(droopSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(droopSrc,'GotoTag'),droopTags{i})
        error('S14:DroopFoundation','%s Droop route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(gridSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(gridSrc,'GotoTag'),gridTags{i})
        error('S14:GridFoundation','%s GridOn route is unexpected.',muxPaths{i});
    end
end

breaker = localDiscoverPCCBreaker(sm);
bph = get_param(breaker,'PortHandles');
if isempty(bph.Inport)
    error('S14:BreakerInput','PCC breaker has no external input.');
end

[breakerSrcBefore,~] = localGetDestinationSource(bph.Inport(1));
expectedBreakerFrom = [sm '/AA15_S13_FINAL_BREAKER_TO_PCC'];

if ~strcmp(breakerSrcBefore,expectedBreakerFrom) || ...
        ~strcmp(get_param(breakerSrcBefore,'GotoTag'),'AA15_PCC_BREAKER_CLOSE_CMD')
    error('S14:BreakerFoundation', ...
        'PCC breaker is not using S13 final breaker command.');
end

fprintf('[OK] Six Mux routes and PCC breaker route protected.\n');

% =========================================================================
% 3. Repair-safe cleanup of a partial S14.
%    Restore Router LOCAL15 inputs7..13 to S10 auxiliary executor first.
% =========================================================================
fprintf('\n--- Repair partial S14 back to S13 baseline ---\n');

aux = [stack '/AA15_P_Auxiliary_Executor'];
router = [stack '/AA15_Command_Source_Router'];
gate = [stack '/AA15_Black_Start_Pref_Gate'];
s14Diag = [sm '/AA15_STAGE14_BLACKSTART_DIAGNOSTICS'];

auxPH = get_param(aux,'PortHandles');
routerPH = get_param(router,'PortHandles');

if numel(auxPH.Outport) < 7 || numel(routerPH.Inport) < 13
    error('S14:RouterPorts','S10 aux/S05 Router ports are unexpected.');
end

for i = 1:7
    dst = routerPH.Inport(6+i);
    ln = get_param(dst,'Line');

    if isequal(ln,-1)
        error('S14:RouterLocalUndriven', ...
            'Router LOCAL15 input%d is undriven.',6+i);
    end

    src = get_param(ln,'SrcPortHandle');
    srcParent = getfullname(get_param(src,'Parent'));

    if ~strcmp(srcParent,aux) && ~strcmp(srcParent,gate)
        error('S14:RouterUnexpectedSource', ...
            'Router LOCAL15 input%d unexpected source: %s',6+i,srcParent);
    end
end

% Restore S13 baseline before deleting/rebuilding gate.
for i = 1:7
    localForcePortConnection(stack, ...
        auxPH.Outport(i),routerPH.Inport(6+i), ...
        sprintf('restore Router input%d to S10 auxiliary',6+i));
end

fprintf('[RESTORE] Router LOCAL15 inputs7..13 -> S10 auxiliary executor.\n');

oldDiagPort = localFindExistingLogPort(s14Diag,group28Mux);
if oldDiagPort > 0
    if oldDiagPort ~= 12
        error('S14:OldDiagPort', ...
            'Existing S14 diagnostics is on Group28 input%d, expected 12.', ...
            oldDiagPort);
    end
    localDisconnectLogInput(group28Mux,12);
end

if getSimulinkBlockHandle(s14Diag) >= 0
    localDeleteBlockIfExists(s14Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 12
    ph28 = get_param(group28Mux,'PortHandles');

    if numel(ph28.Inport) < 12
        error('S14:Group28RepairPort','Cannot inspect Group28 input12.');
    end

    if ~isequal(get_param(ph28.Inport(12),'Line'),-1)
        error('S14:Group28RepairBusy','Group28 input12 is still connected.');
    end

    set_param(group28Mux,'Inputs','11');
end

for i = 1:11
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S14_BS_%02d',i)]);
end

if getSimulinkBlockHandle(gate) >= 0
    localDeleteBlockIfExists(gate);
end

fprintf('[OK] Partial S14 artifacts removed before first update.\n');

% =========================================================================
% 4. Repair S11 S14 execution qualifier: -1 must NOT request black start.
% =========================================================================
fprintf('\n--- Repair S11 S14 execution qualifier ---\n');

modeMF = [stack '/AA15_Mode_Manager/AA15_Mode_Manager_Core'];

if getSimulinkBlockHandle(modeMF) < 0
    error('S14:ModeMF','Missing S11 Mode Manager core.');
end

modeChart = localGetEMChartByPath(modeMF);
oldScript = modeChart.Script;

oldExpr = 'exec_s14 > 0.5 && abs(s14cmd) > 0.5';
newExpr = 'exec_s14 > 0.5 && s14cmd > 0.5';

if contains(oldScript,oldExpr)
    modeChart.Script = strrep(oldScript,oldExpr,newExpr);
    fprintf('[FIX] S14 execution qualifier: abs(cmd14)>0.5 -> cmd14>0.5\n');
elseif contains(oldScript,newExpr)
    fprintf('[KEEP] S14 execution qualifier already uses cmd14>0.5.\n');
else
    error('S14:ModeQualifierUnexpected', ...
        ['Could not find the expected S14 execution qualifier in S11 Mode Manager. ' ...
         'No blind text edit performed.']);
end

% =========================================================================
% 5. Create/verify tunable black-start Pref sequence enable.
% =========================================================================
fprintf('\n--- Create/verify CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE ---\n');

seqTag = 'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE';
seqConst = [panel '/' seqTag];
seqGoto = [panel '/GOTO_' seqTag];

localAssertNoForeignGotoTag(mdl,seqTag,seqGoto);

if getSimulinkBlockHandle(seqConst) < 0
    [px,py] = localFindFreePosition(panel,300,40,50);

    add_block('simulink/Sources/Constant',seqConst, ...
        'Value','0', ...
        'SampleTime','inf', ...
        'OutDataTypeStr','double', ...
        'Position',[px py px+255 py+25]);
else
    if ~strcmp(get_param(seqConst,'BlockType'),'Constant')
        error('S14:SeqConstType','%s exists but is not Constant.',seqConst);
    end
    set_param(seqConst,'SampleTime','inf');
end

if getSimulinkBlockHandle(seqGoto) < 0
    pos = get_param(seqConst,'Position');

    add_block('simulink/Signal Routing/Goto',seqGoto, ...
        'GotoTag',seqTag, ...
        'TagVisibility','global', ...
        'Position',[pos(3)+40 pos(2) pos(3)+310 pos(2)+24]);
else
    if ~strcmp(get_param(seqGoto,'BlockType'),'Goto')
        error('S14:SeqGotoType','%s exists but is not Goto.',seqGoto);
    end
    set_param(seqGoto,'GotoTag',seqTag,'TagVisibility','global');
end

localForceOwnedLine(panel,[seqTag '/1'],['GOTO_' seqTag '/1']);

% =========================================================================
% 6. Build AA15_Black_Start_Pref_Gate.
% =========================================================================
fprintf('\n--- Build AA15_Black_Start_Pref_Gate ---\n');

xGate = localNextRightX(stack,150);

add_block('simulink/Ports & Subsystems/Subsystem',gate, ...
    'Position',[xGate 3480 xGate+690 4070]);
localDeleteSubsystemContents(gate);

gateInputTags = {
    'AA15_AUX_PV1_PREF'
    'AA15_AUX_PV2_PREF'
    'AA15_AUX_ESS1_PREF'
    'AA15_AUX_ESS2_PREF'
    'AA15_AUX_EV1_PREF'
    'AA15_AUX_EV2_PREF'
    'AA15_AUX_ACTIVE_VALID'
    'AA15_EXECUTED_SYSTEM_MODE'
    'AA15_S14_STATUS'
    'AA15_MODE_SELECTED_MASTER'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_EXEC_S14'
    'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE'
};

for i = 1:14
    col = floor((i-1)/7);
    row = mod(i-1,7);
    x = 20 + col*270;
    y = 25 + row*67;

    add_block('simulink/Signal Routing/From', ...
        [gate '/' sprintf('FROM_GATE_%02d',i)], ...
        'GotoTag',gateInputTags{i}, ...
        'Position',[x y x+245 y+20]);
end

gateMF = [gate '/AA15_Black_Start_Pref_Gate_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',gateMF, ...
    'Position',[570 95 1065 520]);

gateChart = localGetEMChartByPath(gateMF);
gateChart.Script = localBlackStartGateScript();

gateOutNames = {
    'pv1_pref_out'
    'pv2_pref_out'
    'ess1_pref_out'
    'ess2_pref_out'
    'ev1_pref_out'
    'ev2_pref_out'
    'pref_valid_out'
    'sequence_active'
    'stage_echo'
    'master_echo'
    'route_valid'
};

for i = 1:11
    y = 35 + (i-1)*44;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [gate '/' gateOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1160 y 1190 y+16]);
end

for i = 1:14
    localEnsureLine(gate, ...
        sprintf('FROM_GATE_%02d/1',i), ...
        sprintf('AA15_Black_Start_Pref_Gate_Core/%d',i));
end

for i = 1:11
    localEnsureLine(gate, ...
        sprintf('AA15_Black_Start_Pref_Gate_Core/%d',i), ...
        [gateOutNames{i} '/1']);
end

gateTags = {
    'AA15_BS_PREF_PV1'
    'AA15_BS_PREF_PV2'
    'AA15_BS_PREF_ESS1'
    'AA15_BS_PREF_ESS2'
    'AA15_BS_PREF_EV1'
    'AA15_BS_PREF_EV2'
    'AA15_BS_PREF_VALID'
    'AA15_BS_PREF_SEQUENCE_ACTIVE'
    'AA15_BS_STAGE_ECHO'
    'AA15_BS_MASTER_ECHO'
    'AA15_BS_PREF_GATE_ROUTE_VALID'
};

gatePos = get_param(gate,'Position');

for i = 1:11
    gotoName = sprintf('GOTO_S14_BS_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',gateTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/6);
    row = mod(i-1,6);
    x = gatePos(3)+45+col*275;
    y = gatePos(2)+25+row*55;

    set_param(p,'Position',[x y x+250 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_Black_Start_Pref_Gate/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 7. Build S14 diag32 BEFORE first update.
% =========================================================================
fprintf('\n--- Build S14 diag32 ---\n');

[dx,dy] = localFindFreePosition(sm,575,650,450);

add_block('simulink/Ports & Subsystems/Subsystem',s14Diag, ...
    'Position',[dx dy dx+575 dy+650]);
localDeleteSubsystemContents(s14Diag);

diagTags = {
    'AA15_S14_STATUS'                         % 230
    'AA15_S14_ALARM'                          % 231
    'AA15_S14_METRIC'                         % 232
    'AA15_S14_CMD_RAW'                        % 233
    'CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE'   % 234
    'AA15_BS_PREF_SEQUENCE_ACTIVE'            % 235
    'AA15_BS_STAGE_ECHO'                      % 236
    'AA15_BS_MASTER_ECHO'                     % 237
    'AA15_AUX_PV1_PREF'                       % 238
    'AA15_AUX_PV2_PREF'                       % 239
    'AA15_AUX_ESS1_PREF'                      % 240
    'AA15_AUX_ESS2_PREF'                      % 241
    'AA15_AUX_EV1_PREF'                       % 242
    'AA15_AUX_EV2_PREF'                       % 243
    'AA15_AUX_ACTIVE_VALID'                   % 244
    'AA15_BS_PREF_PV1'                        % 245
    'AA15_BS_PREF_PV2'                        % 246
    'AA15_BS_PREF_ESS1'                       % 247
    'AA15_BS_PREF_ESS2'                       % 248
    'AA15_BS_PREF_EV1'                        % 249
    'AA15_BS_PREF_EV2'                        % 250
    'AA15_BS_PREF_VALID'                      % 251
    'AA15_EXECUTED_SYSTEM_MODE'               % 252
    'AA15_PCC_BREAKER_CLOSE_CMD'              % 253
    'AA15_MODE_OVERRIDE_ACTIVE'               % 254
    'AA15_PCC_BREAKER_OVERRIDE_ACTIVE'        % 255
    'AA15_FINAL_GRIDON_ESS1'                  % 256
    'AA15_FINAL_GRIDON_ESS2'                  % 257
    'AA15_FINAL_DROOP_ESS1'                   % 258
    'AA15_FINAL_DROOP_ESS2'                   % 259
    'AA15_PCC_BLACKSTART_LATCH'               % 260
    'AA15_BS_PREF_GATE_ROUTE_VALID'           % 261
};

for i = 1:32
    col = floor((i-1)/16);
    row = mod(i-1,16);
    x = 20 + col*260;
    y = 18 + row*35;

    add_block('simulink/Signal Routing/From', ...
        [s14Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+235 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s14Diag '/AA15_STAGE14_DIAG32'], ...
    'Inputs','32', ...
    'Position',[590 30 625 605]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s14Diag '/diag32'], ...
    'Port','1', ...
    'Position',[690 315 720 331]);

for i = 1:32
    localEnsureLine(s14Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE14_DIAG32/%d',i));
end

localEnsureLine(s14Diag,'AA15_STAGE14_DIAG32/1','diag32/1');

% =========================================================================
% 8. FIRST model update after COMPLETE S14 structure exists.
% =========================================================================
fprintf('\n--- First update after COMPLETE S14 structure ---\n');

set_param(mdl,'SimulationCommand','update');

gatePorts = get_param(gateMF,'Ports');

if gatePorts(1) ~= 14 || gatePorts(2) ~= 11
    error('S14:GatePorts', ...
        'Black-start Pref gate expected 14-in/11-out, found %d/%d.', ...
        gatePorts(1),gatePorts(2));
end

% Re-check execution qualifier compiled successfully.
modeChart = localGetEMChartByPath(modeMF);
if ~contains(modeChart.Script,newExpr)
    error('S14:QualifierPostUpdate', ...
        'S11 S14 execution qualifier did not retain cmd14>0.5.');
end

fprintf('[PASS] S14 gate compiled 14 inputs / 11 outputs.\n');
fprintf('[PASS] S11 S14 failure-state qualifier repaired.\n');

% =========================================================================
% 9. REAL route integration: S14 gate -> Router LOCAL15 inputs7..13.
% =========================================================================
fprintf('\n--- Route S14 black-start Pref gate into LOCAL15 source Router ---\n');

gatePH = get_param(gate,'PortHandles');
routerPH = get_param(router,'PortHandles');

if numel(gatePH.Outport) < 7 || numel(routerPH.Inport) < 13
    error('S14:RoutePorts','Cannot materialize S14 gate -> Router ports.');
end

for i = 1:7
    localForcePortConnection(stack, ...
        gatePH.Outport(i),routerPH.Inport(6+i), ...
        sprintf('S14 gate output%d -> Router input%d',i,6+i));
end

set_param(mdl,'SimulationCommand','update');

fprintf('[ROUTE] Router LOCAL15 inputs7..13 now use S14 black-start Pref gate.\n');

% =========================================================================
% 10. Append S14 diag32 to Group28 input12.
% =========================================================================
fprintf('\n--- Append S14 diag32 to Group28 input12 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 11
    error('S14:Group28BeforeAppend', ...
        'Expected Group28 Inputs=11 before S14 append.');
end

set_param(group28Mux,'Inputs','12');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s14Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S14:DiagPort','S14 diagnostics expected exactly one output.');
end

if numel(muxPH28.Inport) < 12
    error('S14:Group28Input12','Group28 input12 did not materialize.');
end

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(12), ...
    'S14 diag32 -> Group28 input12');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 11. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S14 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 12
    error('S14:Group28Final','Group28 must have 12 physical inputs.');
end

for i = 1:11
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);

    if p ~= i
        error('S14:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.', ...
            diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s14Diag,group28Mux) ~= 12
    error('S14:S14DiagSlot','S14 diagnostics is not Group28 input12.');
end

% Router local inputs7..13 must now be S14 gate outputs1..7.
gatePH = get_param(gate,'PortHandles');
routerPH = get_param(router,'PortHandles');

for i = 1:7
    ln = get_param(routerPH.Inport(6+i),'Line');

    if isequal(ln,-1) || get_param(ln,'SrcPortHandle') ~= gatePH.Outport(i)
        error('S14:RouterPostAssert', ...
            'Router LOCAL15 input%d is not driven by S14 gate output%d.', ...
            6+i,i);
    end
end

% Physical device routes must be unchanged from S13.
for i = 1:6
    ph = get_param(muxPaths{i},'PortHandles');

    [f3,~] = localGetDestinationSource(ph.Inport(3));
    [f4,~] = localGetDestinationSource(ph.Inport(4));
    [f5,~] = localGetDestinationSource(ph.Inport(5));
    [f6,~] = localGetDestinationSource(ph.Inport(6));
    [f7,~] = localGetDestinationSource(ph.Inport(7));
    [f8,~] = localGetDestinationSource(ph.Inport(8));

    if ~strcmp(f3,protectFref{i})
        error('S14:FrefChanged','%s Fref input3 changed.',muxPaths{i});
    end

    if ~strcmp(f4,protectVref{i})
        error('S14:VrefChanged','%s Vref input4 changed.',muxPaths{i});
    end

    if ~strcmp(f6,protectPref{i}) || ...
            ~strcmp(get_param(f6,'GotoTag'),prefTags{i})
        error('S14:PrefChanged','%s final Pref physical route changed.',muxPaths{i});
    end

    if ~strcmp(f7,protectQref{i}) || ...
            ~strcmp(get_param(f7,'GotoTag'),qTags{i})
        error('S14:QrefChanged','%s final Qref physical route changed.',muxPaths{i});
    end

    if ~strcmp(get_param(f5,'BlockType'),'From') || ...
            ~strcmp(get_param(f5,'GotoTag'),droopTags{i})
        error('S14:DroopChanged','%s final Droop route changed.',muxPaths{i});
    end

    if ~strcmp(get_param(f8,'BlockType'),'From') || ...
            ~strcmp(get_param(f8,'GotoTag'),gridTags{i})
        error('S14:GridChanged','%s final GridOn route changed.',muxPaths{i});
    end
end

% PCC breaker remains exactly on S13 final command.
bph = get_param(breaker,'PortHandles');
[bFinal,~] = localGetDestinationSource(bph.Inport(1));

if ~strcmp(bFinal,expectedBreakerFrom) || ...
        ~strcmp(get_param(bFinal,'GotoTag'),'AA15_PCC_BREAKER_CLOSE_CMD')
    error('S14:BreakerChanged','PCC breaker route changed during S14.');
end

% Safe saved default.
set_param(seqConst,'Value','0');

allNewTags = [{seqTag}; gateTags];

for i = 1:numel(allNewTags)
    localAssertSingleGlobalGoto(mdl,allNewTags{i});
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE14 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Original Strategy 14 algorithm      : UNCHANGED\n');
fprintf('S14 -1 failure execution qualifier  : FIXED (cmd14 > 0.5 only)\n');
fprintf('Black-start Pref sequence gate      : PASS\n');
fprintf('Normal/non-black Pref behavior      : EXACT PASSTHROUGH by design\n');
fprintf('Stage1                              : all Pref = 0\n');
fprintf('Stage2                              : ESS restoration; master ESS Pref=0\n');
fprintf('Stage3                              : PV + ESS restoration; EV=0\n');
fprintf('Stage4                              : PV + ESS + EV restoration\n');
fprintf('PCC breaker route                   : S13 route preserved\n');
fprintf('GFM/Droop route                     : S12 route preserved\n');
fprintf('Fref/Vref physical routes           : UNCHANGED\n');
fprintf('Qref physical route                 : UNCHANGED\n');
fprintf('CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE saved default : 0\n');
fprintf('Group28 scalar signals              : 261\n');
fprintf('Expected MAT rows                   : 262 incl. Target Time\n');
fprintf('Backup                              : %s\n',backupFile);
fprintf('\nNEXT: RT-LAB Rebuild All (FINAL LOCAL15 model-side structural build).\n');
fprintf('FIRST post-build run must keep all three real mode/black-start enables at 0.\n');

end


% =========================================================================
% Black-start Pref gate MATLAB Function
% =========================================================================
function txt = localBlackStartGateScript()

L = {};
L{end+1} = ['function [pv1o,pv2o,e1o,e2o,ev1o,ev2o,valid_o,' ...
    'seq_active,stage_echo,master_echo,route_valid] = ' ...
    'AA15_Black_Start_Pref_Gate_Core(' ...
    'pv1,pv2,e1,e2,ev1,ev2,valid_i,exec_mode,s14_stage,' ...
    'selected_master,master_enable,control_source,exec_s14,seq_enable)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = '% Exact passthrough is the default behavior.';
L{end+1} = 'pv1o=pv1; pv2o=pv2; e1o=e1; e2o=e2; ev1o=ev1; ev2o=ev2;';
L{end+1} = 'valid_o=valid_i;';
L{end+1} = 'seq_active=0.0;';
L{end+1} = 'stage_echo=s14_stage;';
L{end+1} = 'master_echo=selected_master;';
L{end+1} = 'route_valid=1.0;';
L{end+1} = '';
L{end+1} = 'if ~finite1(pv1)||~finite1(pv2)||~finite1(e1)||~finite1(e2)||...';
L{end+1} = '   ~finite1(ev1)||~finite1(ev2)||~finite1(valid_i)||...';
L{end+1} = '   ~finite1(exec_mode)||~finite1(s14_stage)||...';
L{end+1} = '   ~finite1(selected_master)';
L{end+1} = '    route_valid=0.0;';
L{end+1} = '    valid_o=0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'armed = (master_enable>0.5) && (round(control_source)==1) && ...';
L{end+1} = '        (exec_s14>0.5) && (seq_enable>0.5) && ...';
L{end+1} = '        (round(exec_mode)==4) && (s14_stage>0.5);';
L{end+1} = '';
L{end+1} = 'if ~armed';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'm = round(selected_master);';
L{end+1} = 'if m~=1 && m~=2';
L{end+1} = '    route_valid=0.0;';
L{end+1} = '    valid_o=0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'st = floor(max(s14_stage,1.0));';
L{end+1} = 'seq_active=1.0;';
L{end+1} = '';
L{end+1} = '% Stage 1: master ESS establishes island with zero active-power ref.';
L{end+1} = 'pv1o=0.0; pv2o=0.0; e1o=0.0; e2o=0.0; ev1o=0.0; ev2o=0.0;';
L{end+1} = '';
L{end+1} = '% Stage 2: restore only the non-master ESS active-power command.';
L{end+1} = '% Master ESS remains P_ref=0 while GFM/droop owns voltage/frequency.';
L{end+1} = 'if st>=2.0';
L{end+1} = '    if m==1';
L{end+1} = '        e1o=0.0;';
L{end+1} = '        e2o=clamp1(e2,-1.0,1.0);';
L{end+1} = '    else';
L{end+1} = '        e1o=clamp1(e1,-1.0,1.0);';
L{end+1} = '        e2o=0.0;';
L{end+1} = '    end';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Stage 3: restore PV generation, still no EV charging load.';
L{end+1} = 'if st>=3.0';
L{end+1} = '    pv1o=clamp1(pv1,0.0,1.0);';
L{end+1} = '    pv2o=clamp1(pv2,0.0,1.0);';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Stage 4: finally restore EV charging load.';
L{end+1} = 'if st>=4.0';
L{end+1} = '    ev1o=clamp1(ev1,-1.0,0.0);';
L{end+1} = '    ev2o=clamp1(ev2,-1.0,0.0);';
L{end+1} = 'end';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function y=clamp1(x,lo,hi)';
L{end+1} = 'y=min(max(x,lo),hi);';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function ok=finite1(x)';
L{end+1} = 'ok=~(isnan(x)||isinf(x));';
L{end+1} = 'end';

txt = strjoin(L,newline);

end


% =========================================================================
% Helpers
% =========================================================================
function chart = localGetEMChartByPath(blockPath)

rt = sfroot;
charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);

if isempty(charts)
    drawnow;
    rt = sfroot;
    charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);
end

if numel(charts) ~= 1
    error('S14:EMChartPath', ...
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
    error('S14:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


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
    error('S14:BreakerAmbiguous', ...
        'Could not uniquely identify the PCC Three-Phase Breaker.');
end

breaker = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S14:UndrivenDestination','Protected destination is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isempty(srcPort) || srcPort < 0
    error('S14:NoSourcePort','Could not resolve source port.');
end

srcPath = getfullname(get_param(srcPort,'Parent'));

end


function localEnsureLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S14:LinePortRange', ...
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
    error('S14:LineDriven','Destination %s already has another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S14:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

localForcePortConnection(parent, ...
    srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));

end


function [path,idx] = localParseRelativePort(parent,spec)

slash = find(spec=='/',1,'last');

if isempty(slash)
    error('S14:PortSpec','Port spec must be block/port: %s',spec);
end

blockRel = spec(1:slash-1);
idx = str2double(spec(slash+1:end));

if isnan(idx) || idx < 1
    error('S14:PortSpec','Invalid port index in %s.',spec);
end

path = [parent '/' blockRel];

if getSimulinkBlockHandle(path) < 0
    error('S14:PortBlockMissing','Missing block: %s',path);
end

end


function localEnsureTopLevelSourceConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

if get_param(ln,'SrcPortHandle') ~= srcPort
    error('S14:TopConnection', ...
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
    error('S14:ForceConnection','Post-assert failed for %s.',desc);
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
    error('S14:BranchDelete', ...
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
    if startsWith(ME.identifier,'S14:')
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
        error('S14:ForeignGoto', ...
            'GotoTag %s already exists at unexpected path %s.',tag,g{i});
    end
end

end


function localAssertSingleGlobalGoto(mdl,tag)

g = localFindGotosByTag(mdl,tag);

if numel(g) ~= 1
    error('S14:GlobalGotoCount', ...
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

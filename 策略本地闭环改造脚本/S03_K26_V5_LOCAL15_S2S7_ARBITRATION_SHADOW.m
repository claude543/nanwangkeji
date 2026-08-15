function S03_K26_V5_LOCAL15_S2S7_ARBITRATION_SHADOW
% S03_K26_V5_LOCAL15_S2S7_ARBITRATION_SHADOW
%
% LOCAL15 Stage 03
%
% Purpose
% -------
% Build the FIRST strategy-arbitration layer, still in SHADOW mode:
%
%   Original 15-strategy outputs
%          |
%          v
%   AA15_Request_Normalizer
%          |
%          v
%   AA15_P_Objective_Arbiter
%          |
%          v
%   AA15_ARB_DPREQ_SHADOW
%
% Stage-03 scope is deliberately limited to S2 and S7:
%
%   S2 = AGC/PCC tracking strategy
%   S7 = Tie-line power control
%
% Current original S2 and S7 both produce an active-power request with the
% same traditional form. They MUST NOT be added together.
%
% Arbitration rule:
%   - MASTER_ENABLE = 0:
%       use traditional baseline dP as shadow request.
%
%   - P_OBJECTIVE_MODE = 0 (TIE_LINE):
%       S7 enabled -> S7 is the primary active-power request.
%       S2 + S7 enabled -> S7 executes; S2 becomes monitor-only.
%       S2 enabled alone -> S2 may execute for the dedicated S2 test.
%       neither enabled -> traditional baseline dP fallback.
%
%   - P_OBJECTIVE_MODE = 1..4:
%       RESERVED in Stage 03.
%       No raw S9/S10/S12/S13 cmd is used yet.
%       request_valid = 0 and dP falls back to baseline for diagnostics.
%
% IMPORTANT
% ---------
% This stage does NOT:
%   - change V5-A device Pref routes;
%   - change the S02 baseline AGC;
%   - connect the arbiter to any device;
%   - implement S9/S10/S12/S13 normalization;
%   - implement Mode Manager / Execution Mapper / Source Router.
%
% It only establishes and logs the S2/S7 normalized request and arbitration
% semantics so they can be verified before any real takeover.
%
% Stage-03 Group-26 diagnostic segment (16 signals):
%   1  S2_status
%   2  S2_alarm
%   3  S2_metric
%   4  S2_dP_request_kW
%   5  S7_status
%   6  S7_alarm
%   7  S7_metric
%   8  S7_dP_request_kW
%   9  baseline_dP_request_kW
%   10 arbiter_dP_request_kW
%   11 selected_source
%   12 request_valid
%   13 duplicate_guard
%   14 s2_monitor_only
%   15 P_OBJECTIVE_MODE
%   16 MASTER_ENABLE
%
% Existing Group-26 signal order is preserved. This diag16 is appended only
% at the end.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 03 - S2/S7 Request Normalizer + Arbiter\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S03:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S03:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S03:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE03_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

% -------------------------------------------------------------------------
% Freeze the same tunability policy used by S00/S01/S02.
% -------------------------------------------------------------------------
set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S03:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% -------------------------------------------------------------------------
% S02 prerequisites. Fail before any structural edit if the expected
% foundation is missing.
% -------------------------------------------------------------------------
fprintf('\n--- Verify Stage-02 foundation ---\n');

requiredBlocks = {
    [sm '/AA15_CFG15_PANEL']
    [sm '/AA15_AGC_INPUT_TAPS']
    [sm '/AA15_BASELINE_AGC_SHADOW']
    [sm '/AA15_CFG15_TUNABILITY_MONITOR']
    [sm '/AA15_BASELINE_AGC_SHADOW/AGC_Baseline_dPRequest']
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S03:MissingPrerequisite', ...
            'Missing Stage-02 prerequisite: %s',requiredBlocks{i});
    end
    fprintf('[OK] %s\n',requiredBlocks{i});
end

shadowAGC = [sm '/AA15_BASELINE_AGC_SHADOW/AGC_Baseline_dPRequest'];
shadowPorts = get_param(shadowAGC,'Ports');
if shadowPorts(1) ~= 16 || shadowPorts(2) ~= 9
    error('S03:ShadowAGCPorts', ...
        'S02 shadow AGC is not 16-in / 9-out.');
end

requiredGlobalTags = {
    'CFG15_MASTER_ENABLE'
    'CFG15_EXEC_S02'
    'CFG15_EXEC_S07'
    'CFG15_P_OBJECTIVE_MODE'
    'AA15_BASELINE_DPREQ'
};

for i = 1:numel(requiredGlobalTags)
    g = localFindGotoByTag(mdl,requiredGlobalTags{i});
    if isempty(g)
        error('S03:MissingTag', ...
            'Required Goto tag not found: %s',requiredGlobalTags{i});
    end
    fprintf('[OK] tag %s\n',requiredGlobalTags{i});
end

strategyTags = {
    'SIG_AA_STATUS15'
    'SIG_AA_ALARM15'
    'SIG_AA_METRIC15'
    'SIG_AA_CMD15'
};

for i = 1:numel(strategyTags)
    g = localFindGotoByTag(mdl,strategyTags{i});
    if isempty(g)
        error('S03:MissingStrategyTag', ...
            'Required 15-strategy Goto tag not found: %s',strategyTags{i});
    end
end

% -------------------------------------------------------------------------
% Discover Group-26 before rebuilding any Stage-03 diagnostics, so reruns
% can reuse the same logging input instead of growing the Mux repeatedly.
% -------------------------------------------------------------------------
[opWrite,logMux] = localDiscoverGroup26(sm);

fprintf('\n[OK] Group-26 OpWrite : %s\n',opWrite);
fprintf('[OK] Group-26 log Mux : %s\n',logMux);

diagTop = [sm '/AA15_STAGE03_DIAGNOSTICS'];
existingLogPort = localFindExistingLogPort(diagTop,logMux);

if existingLogPort > 0
    fprintf('[KEEP] Existing Stage-03 log slot = Mux input %d\n',existingLogPort);
end

% -------------------------------------------------------------------------
% Create/rebuild the final LOCAL15 top-level container.
% Only its internals are Stage-03 at this point. Future S04+ modules will be
% added into this same container instead of creating scattered top blocks.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_LOCAL_CONTROL_STACK ---\n');

stack = [sm '/AA15_LOCAL_CONTROL_STACK'];

if getSimulinkBlockHandle(stack) < 0
    [sx,sy] = localFindFreeTopLevelPosition(sm,430,250,420);
    add_block('simulink/Ports & Subsystems/Subsystem',stack, ...
        'Position',[sx sy sx+430 sy+250]);
    fprintf('[CREATE] %s\n',stack);
else
    if ~strcmp(get_param(stack,'BlockType'),'SubSystem')
        error('S03:StackConflict','%s exists but is not a SubSystem.',stack);
    end

    futureBlocks = {
        [stack '/AA15_Mode_Manager']
        [stack '/AA15_Execution_Mapper']
        [stack '/AA15_Command_Source_Router']
        [stack '/AA15_Q_Allocator']
        [stack '/AA15_BlackStart_Executor']
    };

    for fb = 1:numel(futureBlocks)
        if getSimulinkBlockHandle(futureBlocks{fb}) >= 0
            error('S03:FutureStageDetected', ...
                ['A later-stage block already exists: %s. ' ...
                 'Do not rerun S03 because it would erase later work.'], ...
                futureBlocks{fb});
        end
    end

    fprintf('[REBUILD] %s Stage-03 internals\n',stack);
end

localDeleteSubsystemContents(stack);

try
    set_param(stack,'AttributesFormatString', ...
        sprintf(['LOCAL15 control stack\\n' ...
                 'S03: S2/S7 arbitration SHADOW\\n' ...
                 'NO device takeover']));
catch
end

% Four explicit vector inputs from the original 15-strategy layer.
stackInputNames = {
    'status15'
    'alarm15'
    'metric15'
    'cmd15'
};

for i = 1:4
    y = 55 + (i-1)*48;
    add_block('simulink/Ports & Subsystems/In1', ...
        [stack '/' stackInputNames{i}], ...
        'Port',num2str(i), ...
        'Position',[25 y 55 y+16]);
end

% -------------------------------------------------------------------------
% Nested Request Normalizer.
% Stage03 only extracts S2(index 2) and S7(index 7) from the four 15-vectors.
% No unit conversion is performed because current S2/S7 cmd already share
% the same active-power request semantics used by the traditional baseline.
% -------------------------------------------------------------------------
normalizer = [stack '/AA15_Request_Normalizer'];
add_block('simulink/Ports & Subsystems/Subsystem',normalizer, ...
    'Position',[110 40 370 225]);
localDeleteSubsystemContents(normalizer);

try
    set_param(normalizer,'AttributesFormatString', ...
        sprintf('Stage03\\nS2/S7 vector extraction\\n15-vector -> named scalars'));
catch
end

normIn = {'status15','alarm15','metric15','cmd15'};
for i = 1:4
    y = 40 + (i-1)*65;
    add_block('simulink/Ports & Subsystems/In1', ...
        [normalizer '/' normIn{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);
end

demuxNames = {
    'DEMUX_STATUS15'
    'DEMUX_ALARM15'
    'DEMUX_METRIC15'
    'DEMUX_CMD15'
};

for i = 1:4
    y = 30 + (i-1)*90;
    add_block('simulink/Signal Routing/Demux', ...
        [normalizer '/' demuxNames{i}], ...
        'Outputs','15', ...
        'Position',[90 y 95 y+70]);
    localEnsureLine(normalizer,[normIn{i} '/1'],[demuxNames{i} '/1']);
end

normOutNames = {
    'S2_STATUS'
    'S2_ALARM'
    'S2_METRIC'
    'S2_DPREQ_KW'
    'S7_STATUS'
    'S7_ALARM'
    'S7_METRIC'
    'S7_DPREQ_KW'
};

for i = 1:8
    col = floor((i-1)/4);
    row = mod(i-1,4);
    x = 220 + col*145;
    y = 35 + row*75;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [normalizer '/' normOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[x y x+30 y+16]);
end

% S2 is vector index 2; S7 is vector index 7.
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_STATUS15'],2), ...
    localInPort([normalizer '/S2_STATUS'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_ALARM15'],2), ...
    localInPort([normalizer '/S2_ALARM'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_METRIC15'],2), ...
    localInPort([normalizer '/S2_METRIC'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_CMD15'],2), ...
    localInPort([normalizer '/S2_DPREQ_KW'],1));

localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_STATUS15'],7), ...
    localInPort([normalizer '/S7_STATUS'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_ALARM15'],7), ...
    localInPort([normalizer '/S7_ALARM'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_METRIC15'],7), ...
    localInPort([normalizer '/S7_METRIC'],1));
localEnsureLineByHandles(normalizer, ...
    localOutPort([normalizer '/DEMUX_CMD15'],7), ...
    localInPort([normalizer '/S7_DPREQ_KW'],1));

% Connect stack inputs -> normalizer.
for i = 1:4
    localEnsureLine(stack,[stackInputNames{i} '/1'], ...
        sprintf('AA15_Request_Normalizer/%d',i));
end

% -------------------------------------------------------------------------
% Create global named scalar outputs from the normalizer.
% -------------------------------------------------------------------------
normTags = {
    'AA15_NORM_S2_STATUS'
    'AA15_NORM_S2_ALARM'
    'AA15_NORM_S2_METRIC'
    'AA15_NORM_S2_DPREQ_KW'
    'AA15_NORM_S7_STATUS'
    'AA15_NORM_S7_ALARM'
    'AA15_NORM_S7_METRIC'
    'AA15_NORM_S7_DPREQ_KW'
};

for i = 1:8
    y = 35 + (i-1)*35;
    gotoName = sprintf('GOTO_NORM_%02d',i);
    gotoPath = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',gotoPath, ...
        'GotoTag',normTags{i}, ...
        'TagVisibility','global', ...
        'Position',[420 y 620 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Request_Normalizer/%d',i), ...
        [gotoName '/1']);
end

% -------------------------------------------------------------------------
% Create Stage-03 P-objective arbiter.
% -------------------------------------------------------------------------
arbiter = [stack '/AA15_P_Objective_Arbiter'];
add_block('simulink/User-Defined Functions/MATLAB Function',arbiter, ...
    'Position',[690 75 1040 330]);

arbScript = localArbiterScript();
arbChart = localGetEMChartByPath(arbiter);
arbChart.Script = arbScript;

% Config/baseline From blocks inside the stack.
arbFrom = {
    'FROM_BASELINE_DPREQ',       'AA15_BASELINE_DPREQ'
    'FROM_CFG_MASTER_ENABLE',    'CFG15_MASTER_ENABLE'
    'FROM_CFG_EXEC_S02',         'CFG15_EXEC_S02'
    'FROM_CFG_EXEC_S07',         'CFG15_EXEC_S07'
    'FROM_CFG_P_OBJECTIVE_MODE', 'CFG15_P_OBJECTIVE_MODE'
};

for i = 1:size(arbFrom,1)
    y = 365 + (i-1)*38;
    add_block('simulink/Signal Routing/From', ...
        [stack '/' arbFrom{i,1}], ...
        'GotoTag',arbFrom{i,2}, ...
        'Position',[430 y 650 y+22]);
end

% -------------------------------------------------------------------------
% Top-level bridges from the existing 15-strategy output tags.
%
% These From blocks are intentionally at SM_Master level so they work even
% if the original SIG_AA_* Goto tags are local/scoped rather than global.
% -------------------------------------------------------------------------
fprintf('\n--- Connect original 15-strategy vectors to LOCAL control stack ---\n');

bridgeNames = {
    'AA15_S03_FROM_SIG_AA_STATUS15'
    'AA15_S03_FROM_SIG_AA_ALARM15'
    'AA15_S03_FROM_SIG_AA_METRIC15'
    'AA15_S03_FROM_SIG_AA_CMD15'
};

stackPos = get_param(stack,'Position');

for i = 1:4
    bridgePath = [sm '/' bridgeNames{i}];

    bx = max(20,stackPos(1)-260);
    by = stackPos(2)+25+(i-1)*50;

    if getSimulinkBlockHandle(bridgePath) < 0
        add_block('simulink/Signal Routing/From',bridgePath, ...
            'GotoTag',strategyTags{i}, ...
            'Position',[bx by bx+210 by+22]);
        fprintf('[CREATE] %s -> stack input %d\n',bridgeNames{i},i);
    else
        if ~strcmp(get_param(bridgePath,'BlockType'),'From')
            error('S03:BridgeConflict','Unexpected block at %s.',bridgePath);
        end
        set_param(bridgePath,'GotoTag',strategyTags{i});
        fprintf('[KEEP]   %s\n',bridgeNames{i});
    end
end

% After the stack has 4 compiled input ports, wire the top-level bridges.
stackPH = get_param(stack,'PortHandles');
if numel(stackPH.Inport) ~= 4
    error('S03:StackTopPorts','Stack does not expose 4 input ports.');
end

for i = 1:4
    bridgePH = get_param([sm '/' bridgeNames{i}],'PortHandles');
    localEnsureTopLevelConnection(sm,bridgePH.Outport(1),stackPH.Inport(i), ...
        sprintf('%s -> AA15_LOCAL_CONTROL_STACK input %d',bridgeNames{i},i));
end


% First update materializes the MATLAB Function ports and validates that
% the four source vectors are truly width 15 through the Demux blocks.
fprintf('\n--- First diagram update: validate vector widths and arbiter ports ---\n');
set_param(mdl,'SimulationCommand','update');

stackPorts = get_param(stack,'Ports');
if stackPorts(1) ~= 4
    error('S03:StackPorts', ...
        'AA15_LOCAL_CONTROL_STACK expected 4 inputs, found %d.',stackPorts(1));
end

normPorts = get_param(normalizer,'Ports');
if normPorts(1) ~= 4 || normPorts(2) ~= 8
    error('S03:NormalizerPorts', ...
        'Request Normalizer expected 4-in/8-out, found %d/%d.', ...
        normPorts(1),normPorts(2));
end

arbPorts = get_param(arbiter,'Ports');
if arbPorts(1) ~= 7 || arbPorts(2) ~= 5
    error('S03:ArbiterPorts', ...
        'P Objective Arbiter expected 7-in/5-out, found %d/%d.', ...
        arbPorts(1),arbPorts(2));
end

fprintf('[OK] Request Normalizer = 4 in / 8 out\n');
fprintf('[OK] P Objective Arbiter = 7 in / 5 out\n');

% Arbiter inputs:
% 1 baseline_dP
% 2 S2_dP
% 3 S7_dP
% 4 master_enable
% 5 exec_s02
% 6 exec_s07
% 7 objective_mode
localEnsureLine(stack,'FROM_BASELINE_DPREQ/1','AA15_P_Objective_Arbiter/1');
localEnsureLine(stack,'AA15_Request_Normalizer/4','AA15_P_Objective_Arbiter/2');
localEnsureLine(stack,'AA15_Request_Normalizer/8','AA15_P_Objective_Arbiter/3');
localEnsureLine(stack,'FROM_CFG_MASTER_ENABLE/1','AA15_P_Objective_Arbiter/4');
localEnsureLine(stack,'FROM_CFG_EXEC_S02/1','AA15_P_Objective_Arbiter/5');
localEnsureLine(stack,'FROM_CFG_EXEC_S07/1','AA15_P_Objective_Arbiter/6');
localEnsureLine(stack,'FROM_CFG_P_OBJECTIVE_MODE/1','AA15_P_Objective_Arbiter/7');

arbTags = {
    'AA15_ARB_DPREQ_SHADOW'
    'AA15_ARB_SELECTED_SOURCE'
    'AA15_ARB_REQUEST_VALID'
    'AA15_ARB_DUPLICATE_GUARD'
    'AA15_S2_MONITOR_ONLY'
};

for i = 1:5
    y = 90 + (i-1)*48;
    gotoName = sprintf('GOTO_ARB_%02d',i);
    gotoPath = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',gotoPath, ...
        'GotoTag',arbTags{i}, ...
        'TagVisibility','global', ...
        'Position',[1090 y 1290 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_P_Objective_Arbiter/%d',i), ...
        [gotoName '/1']);
end

% -------------------------------------------------------------------------
% Stage-03 diagnostics subsystem. This is separate from the control stack:
% diagnostics never become part of the control path.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_STAGE03_DIAGNOSTICS ---\n');

diag = diagTop;

if getSimulinkBlockHandle(diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,360,230,420);
    add_block('simulink/Ports & Subsystems/Subsystem',diag, ...
        'Position',[dx dy dx+360 dy+230]);
    fprintf('[CREATE] %s\n',diag);
else
    if ~strcmp(get_param(diag,'BlockType'),'SubSystem')
        error('S03:DiagConflict','%s exists but is not a SubSystem.',diag);
    end
    fprintf('[REBUILD] %s\n',diag);
end

localDeleteSubsystemContents(diag);

try
    set_param(diag,'AttributesFormatString', ...
        sprintf('S03 diagnostics only\\n16 signals\\nAppended to Group26'));
catch
end

diagTags = {
    'AA15_NORM_S2_STATUS'
    'AA15_NORM_S2_ALARM'
    'AA15_NORM_S2_METRIC'
    'AA15_NORM_S2_DPREQ_KW'
    'AA15_NORM_S7_STATUS'
    'AA15_NORM_S7_ALARM'
    'AA15_NORM_S7_METRIC'
    'AA15_NORM_S7_DPREQ_KW'
    'AA15_BASELINE_DPREQ'
    'AA15_ARB_DPREQ_SHADOW'
    'AA15_ARB_SELECTED_SOURCE'
    'AA15_ARB_REQUEST_VALID'
    'AA15_ARB_DUPLICATE_GUARD'
    'AA15_S2_MONITOR_ONLY'
    'CFG15_P_OBJECTIVE_MODE'
    'CFG15_MASTER_ENABLE'
};

for i = 1:16
    col = floor((i-1)/8);
    row = mod(i-1,8);
    x = 25 + col*210;
    y = 30 + row*45;

    fromName = sprintf('FROM_DIAG_%02d',i);
    add_block('simulink/Signal Routing/From', ...
        [diag '/' fromName], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+180 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [diag '/AA15_STAGE03_DIAG16'], ...
    'Inputs','16', ...
    'Position',[500 45 535 390]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [diag '/diag16'], ...
    'Port','1', ...
    'Position',[590 210 620 226]);

for i = 1:16
    localEnsureLine(diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE03_DIAG16/%d',i));
end

localEnsureLine(diag,'AA15_STAGE03_DIAG16/1','diag16/1');

% -------------------------------------------------------------------------
% Append diag16 to the existing Group-26 Mux without changing any previous
% signal ordering.
% -------------------------------------------------------------------------
fprintf('\n--- Append Stage-03 diag16 to Group-26 ---\n');

set_param(mdl,'SimulationCommand','update');

diagPH = get_param(diag,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S03:DiagTopPort','Stage-03 diagnostics expected one output.');
end

if existingLogPort > 0
    logPH = get_param(logMux,'PortHandles');

    if existingLogPort > numel(logPH.Inport)
        error('S03:StoredLogPort', ...
            'Stored Stage-03 log port no longer exists.');
    end

    localEnsureTopLevelConnection(sm,diagPH.Outport(1), ...
        logPH.Inport(existingLogPort), ...
        sprintf('Stage03 diag16 -> existing log input %d',existingLogPort));

    fprintf('[REUSE] Group-26 Mux input %d\n',existingLogPort);
else
    currentConnectedPort = localFindExistingLogPort(diag,logMux);

    if currentConnectedPort > 0
        fprintf('[KEEP] Stage-03 diagnostics already on Mux input %d\n', ...
            currentConnectedPort);
    else
        oldN = str2double(get_param(logMux,'Inputs'));
        if isnan(oldN) || oldN < 1
            error('S03:LogMuxInputs','Cannot parse Group-26 Mux Inputs.');
        end

        set_param(logMux,'Inputs',num2str(oldN+1));
        logPH = get_param(logMux,'PortHandles');

        localEnsureTopLevelConnection(sm,diagPH.Outport(1), ...
            logPH.Inport(oldN+1), ...
            sprintf('Stage03 diag16 -> new log input %d',oldN+1));

        fprintf('[APPEND] Stage-03 diag16 added as Group-26 Mux input %d\n', ...
            oldN+1);
    end
end

% -------------------------------------------------------------------------
% Final update and assertions.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / assertions ---\n');
set_param(mdl,'SimulationCommand','update');

% The original S02 baseline shadow AGC must remain untouched at 16/9.
shadowPortsAfter = get_param(shadowAGC,'Ports');
if shadowPortsAfter(1) ~= 16 || shadowPortsAfter(2) ~= 9
    error('S03:S02ShadowChanged', ...
        'S02 baseline shadow AGC port structure changed unexpectedly.');
end

% V5-A actual device routes must still exist.
devices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
for i = 1:numel(devices)
    tag = ['V5A_FINAL_' devices{i}];
    f = localFindFromByTag(mdl,tag);
    if isempty(f)
        error('S03:V5ARouteLost','Missing V5-A From tag %s.',tag);
    end
end

% Check all new global tags exist exactly once.
allNewTags = [normTags; arbTags];
for i = 1:numel(allNewTags)
    g = localFindGotoByTag(mdl,allNewTags{i});
    if numel(g) ~= 1
        error('S03:NewTagCount', ...
            'Expected exactly one Goto for %s, found %d.', ...
            allNewTags{i},numel(g));
    end
end

% Confirm each new top-level strategy bridge is connected.
for i = 1:4
    ph = get_param([sm '/' bridgeNames{i}],'PortHandles');
    ln = get_param(ph.Outport(1),'Line');
    if isequal(ln,-1)
        error('S03:BridgeUnconnected','Bridge is unconnected: %s',bridgeNames{i});
    end
end

% -------------------------------------------------------------------------
% Export a Stage-03 mapping file.
% -------------------------------------------------------------------------
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE03_S2S7_ARBITRATION_MAP_%s.txt', ...
    modelBase,stamp));

fid = fopen(mapFile,'w');
if fid >= 0
    fprintf(fid,'LOCAL15 Stage 03 - S2/S7 Request Normalizer + Arbiter\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'Top-level added/used blocks:\n');
    fprintf(fid,'  %s\n',stack);
    fprintf(fid,'  %s\n\n',diag);

    fprintf(fid,'AA15_LOCAL_CONTROL_STACK inputs:\n');
    fprintf(fid,'  1 status15\n');
    fprintf(fid,'  2 alarm15\n');
    fprintf(fid,'  3 metric15\n');
    fprintf(fid,'  4 cmd15\n\n');

    fprintf(fid,'Request Normalizer outputs:\n');
    for i = 1:8
        fprintf(fid,'  %d %s -> %s\n',i,normOutNames{i},normTags{i});
    end

    fprintf(fid,'\nArbiter outputs:\n');
    fprintf(fid,'  1 dP_request_kW     -> AA15_ARB_DPREQ_SHADOW\n');
    fprintf(fid,'  2 selected_source   -> AA15_ARB_SELECTED_SOURCE\n');
    fprintf(fid,'  3 request_valid     -> AA15_ARB_REQUEST_VALID\n');
    fprintf(fid,'  4 duplicate_guard   -> AA15_ARB_DUPLICATE_GUARD\n');
    fprintf(fid,'  5 s2_monitor_only   -> AA15_S2_MONITOR_ONLY\n\n');

    fprintf(fid,'Arbiter source encoding:\n');
    fprintf(fid,'  0   = traditional baseline fallback\n');
    fprintf(fid,'  2   = S2 active-power request\n');
    fprintf(fid,'  7   = S7 tie-line request\n');
    fprintf(fid,'  -2  = invalid/nonfinite S2 request\n');
    fprintf(fid,'  -7  = invalid/nonfinite S7 request\n');
    fprintf(fid,'  101 = mode1 Peak-Valley reserved/not normalized in S03\n');
    fprintf(fid,'  102 = mode2 Periodic Plan reserved/not normalized in S03\n');
    fprintf(fid,'  103 = mode3 Renewable reserved/not normalized in S03\n');
    fprintf(fid,'  104 = mode4 Multi-objective reserved/not normalized in S03\n\n');

    fprintf(fid,'Stage03 diag16 appended to Group26:\n');
    for i = 1:16
        fprintf(fid,'  %2d %s\n',i,diagTags{i});
    end

    fprintf(fid,'\nNo V5-A Pref route was changed.\n');
    fprintf(fid,'No S02 baseline AGC connection was changed.\n');
    fprintf(fid,'No raw S9/S10/S12/S13 cmd is executed in S03.\n');

    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 03 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Request Normalizer          : S2/S7 created\n');
fprintf('P Objective Arbiter         : created\n');
fprintf('S2+S7 duplicate protection  : implemented\n');
fprintf('Other P objective modes     : reserved / safe fallback\n');
fprintf('V5-A actual device control  : UNCHANGED\n');
fprintf('S02 baseline shadow AGC     : UNCHANGED\n');
fprintf('Group-26                    : +16 Stage-03 diagnostics\n');
fprintf('Expected signal width       : 109 + 16 = 125\n');
fprintf('Expected MAT rows           : 126 (Target Time + 125 signals)\n');
fprintf('Mapping TXT                 : %s\n',mapFile);
fprintf('\nRecommended Stage-03 validation after Build/Load:\n');
fprintf('  CFG15_MASTER_ENABLE    = 1\n');
fprintf('  CFG15_P_OBJECTIVE_MODE = 0\n');
fprintf('  CFG15_EXEC_S02         = 1\n');
fprintf('  CFG15_EXEC_S07         = 1\n');
fprintf('\nExpected:\n');
fprintf('  selected_source = 7\n');
fprintf('  request_valid   = 1\n');
fprintf('  duplicate_guard = 1\n');
fprintf('  s2_monitor_only = 1\n');
fprintf('  arbiter_dP      = S7_dP\n');
fprintf('  S2_dP           = S7_dP = baseline_dP (current original logic)\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% Local helpers
% =========================================================================

function scriptText = localArbiterScript()

lines = {};
lines{end+1} = ['function [dP_request_kW,selected_source,request_valid,' ...
                'duplicate_guard,s2_monitor_only] = ' ...
                'AA15_P_Objective_Arbiter(' ...
                'baseline_dP_kW,s2_dP_kW,s7_dP_kW,' ...
                'master_enable,exec_s02,exec_s07,objective_mode)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = '% Safe defaults: traditional baseline.';
lines{end+1} = 'dP_request_kW = baseline_dP_kW;';
lines{end+1} = 'selected_source = 0.0;';
lines{end+1} = 'request_valid = 1.0;';
lines{end+1} = 'duplicate_guard = 0.0;';
lines{end+1} = 's2_monitor_only = 0.0;';
lines{end+1} = '';
lines{end+1} = 'if master_enable <= 0.5';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'mode = round(objective_mode);';
lines{end+1} = '';
lines{end+1} = '% Stage03 only implements active objective mode 0 = TIE_LINE.';
lines{end+1} = 'if mode ~= 0';
lines{end+1} = '    request_valid = 0.0;';
lines{end+1} = '    selected_source = 100.0 + mode;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'useS2 = exec_s02 > 0.5;';
lines{end+1} = 'useS7 = exec_s07 > 0.5;';
lines{end+1} = '';
lines{end+1} = '% Combined S2+S7: S7 executes, S2 is monitor-only.';
lines{end+1} = 'if useS7';
lines{end+1} = '    if useS2';
lines{end+1} = '        duplicate_guard = 1.0;';
lines{end+1} = '        s2_monitor_only = 1.0;';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = '    if ~isnan(s7_dP_kW) && ~isinf(s7_dP_kW)';
lines{end+1} = '        dP_request_kW = s7_dP_kW;';
lines{end+1} = '        selected_source = 7.0;';
lines{end+1} = '        request_valid = 1.0;';
lines{end+1} = '    else';
lines{end+1} = '        dP_request_kW = baseline_dP_kW;';
lines{end+1} = '        selected_source = -7.0;';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '    end';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% Dedicated S2 test: S2 may be the active request when S7 is disabled.';
lines{end+1} = 'if useS2';
lines{end+1} = '    if ~isnan(s2_dP_kW) && ~isinf(s2_dP_kW)';
lines{end+1} = '        dP_request_kW = s2_dP_kW;';
lines{end+1} = '        selected_source = 2.0;';
lines{end+1} = '        request_valid = 1.0;';
lines{end+1} = '    else';
lines{end+1} = '        dP_request_kW = baseline_dP_kW;';
lines{end+1} = '        selected_source = -2.0;';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '    end';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'end';

scriptText = strjoin(lines,newline);

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
    error('S03:EMChartPath', ...
        'Expected exactly one Stateflow.EMChart at %s, found %d.', ...
        blockPath,numel(charts));
end

chart = charts(1);

end


function blocks = localFindGotoByTag(mdl,tag)

blocks = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'MatchFilter',@Simulink.match.allVariants, ...
    'BlockType','Goto', ...
    'GotoTag',tag);

end


function blocks = localFindFromByTag(mdl,tag)

blocks = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'MatchFilter',@Simulink.match.allVariants, ...
    'BlockType','From', ...
    'GotoTag',tag);

end


function [opWrite,logMux] = localDiscoverGroup26(sm)

opWrite = [sm '/OpWriteFile'];

if getSimulinkBlockHandle(opWrite) < 0
    error('S03:Group26', ...
        'Known Group-26 path is missing: %s',opWrite);
end

ph = get_param(opWrite,'PortHandles');
if isempty(ph.Inport)
    error('S03:Group26','Group-26 OpWriteFile has no input.');
end

ln = get_param(ph.Inport(1),'Line');
if isequal(ln,-1)
    error('S03:Group26','Group-26 OpWriteFile is unconnected.');
end

srcBlock = get_param(ln,'SrcBlockHandle');
if isempty(srcBlock) || srcBlock < 0
    error('S03:Group26','Cannot resolve Group-26 upstream block.');
end

logMux = getfullname(srcBlock);

if ~strcmp(get_param(logMux,'BlockType'),'Mux')
    error('S03:Group26', ...
        'Expected a Mux before Group-26 OpWriteFile, found %s.', ...
        get_param(logMux,'BlockType'));
end

end


function idx = localFindExistingLogPort(sourceBlock,logMux)

idx = 0;

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

dst = get_param(ln,'DstPortHandle');
dst = dst(dst >= 0);

logPH = get_param(logMux,'PortHandles');

for i = 1:numel(dst)
    hit = find(logPH.Inport == dst(i),1,'first');
    if ~isempty(hit)
        idx = hit;
        return;
    end
end

end


function localEnsureTopLevelConnection(parent,srcPort,dstPort,desc)

dstLine = get_param(dstPort,'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPort
        error('S03:UnexpectedTopLine', ...
            'Destination for "%s" is already driven by another source.',desc);
    end
end

end


function localEnsureLine(parent,src,dst)

srcBlock = strtok(src,'/');
dstBlock = strtok(dst,'/');

srcPortStr = extractAfter(src,'/');
dstPortStr = extractAfter(dst,'/');

srcPath = [parent '/' srcBlock];
dstPath = [parent '/' dstBlock];

if getSimulinkBlockHandle(srcPath) < 0
    error('S03:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S03:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S03:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S03:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S03:UnexpectedExistingLine', ...
            'Destination %s is already driven by a different source.',dst);
    end
end

end


function localEnsureLineByHandles(parent,srcPort,dstPort)

dstLine = get_param(dstPort,'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');
    if existingSrc ~= srcPort
        error('S03:UnexpectedHandleLine', ...
            'A destination port is already driven by another source.');
    end
end

end


function p = localOutPort(blockPath,index)

ph = get_param(blockPath,'PortHandles');

if index > numel(ph.Outport)
    error('S03:OutPortRange', ...
        'Outport %d does not exist on %s.',index,blockPath);
end

p = ph.Outport(index);

end


function p = localInPort(blockPath,index)

ph = get_param(blockPath,'PortHandles');

if index > numel(ph.Inport)
    error('S03:InPortRange', ...
        'Inport %d does not exist on %s.',index,blockPath);
end

p = ph.Inport(index);

end


function localDeleteSubsystemContents(subsys)

try
    Simulink.SubSystem.deleteContents(subsys);
    return;
catch
end

inside = find_system(subsys, ...
    'SearchDepth',1, ...
    'Type','Block');

for k = 1:numel(inside)
    if strcmp(inside{k},subsys)
        continue;
    end

    try
        delete_block(inside{k});
    catch
    end
end

end


function [x,y] = localFindFreeTopLevelPosition(parent,w,h,margin)

blocks = find_system(parent,'SearchDepth',1,'Type','Block');

maxRight = 0;
minTop = inf;

for k = 1:numel(blocks)
    if strcmp(blocks{k},parent)
        continue;
    end

    try
        p = get_param(blocks{k},'Position');
        if isnumeric(p) && numel(p)==4
            maxRight = max(maxRight,p(3));
            minTop = min(minTop,p(2));
        end
    catch
    end
end

if isinf(minTop)
    minTop = 100;
end

x = maxRight + margin;
y = max(80,minTop);

unused = w+h; %#ok<NASGU>

end

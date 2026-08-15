function S05_K26_V5_LOCAL15_EXECUTION_MAPPER_ROUTER_SHADOW
% S05_K26_V5_LOCAL15_EXECUTION_MAPPER_ROUTER_SHADOW
%
% LOCAL15 Stage 05
%
% Purpose
% -------
% Complete the first end-to-end LOCAL15 ACTIVE-POWER SHADOW chain:
%
%   Strategy outputs
%      -> S03 Normalizer / Arbiter
%      -> S04 Arbitrated Baseline AGC
%      -> S05 Active-P Execution Mapper
%      -> S05 Command Source Router
%      -> u_commit SHADOW
%
% The actual six device Pref routes remain V5-A and are NOT changed.
%
% Execution Mapper
% ----------------
% Inputs:
%   1..6  LOCAL15 AGC candidate Prefs
%   7     CFG15_MASTER_ENABLE
%   8     AA15_ARB_REQUEST_VALID
%
% Outputs:
%   1..6  mapped LOCAL15 Prefs
%   7     local_active_valid
%
% Current Stage-05 mapping:
%   PV  : clamp to [0, 1]
%   ESS : clamp to [-1, 1]
%   EV  : clamp to [-1, 0]
%
% The mapper does not yet combine S6/S8/Q/mode/protection commands.
% It only establishes the active-P execution-domain boundary.
%
% Command Source Router
% ---------------------
% Inputs:
%   1..6   LEGACY_V5A Prefs
%   7..12  mapped LOCAL15 Prefs
%   13     local_active_valid
%   14     CFG15_CONTROL_SOURCE
%
% CONTROL_SOURCE:
%   0 = LEGACY_V5A
%   1 = LOCAL15
%   2 = BOARD15 (reserved, not available yet)
%
% Outputs:
%   1..6   u_commit shadow Prefs
%   7      selected_source
%   8      route_valid
%
% The router is SHADOW ONLY in S05. Its outputs are logged but do not drive
% the six device Mux input-6 Pref ports.
%
% Group-28
% --------
% Existing S03+S04 = 28 signals.
% S05 appends 22 signals:
%   29..34 mapped LOCAL15 Prefs
%   35     local_active_valid
%   36..41 LEGACY_V5A Prefs
%   42..47 routed u_commit shadow Prefs
%   48     router_selected_source
%   49     router_valid
%   50     CFG15_CONTROL_SOURCE
%
% Expected Group-28 MAT:
%   51 rows = Target Time + 50 signals.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 05 - Execution Mapper + Source Router SHADOW\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S05:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S05:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S05:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE05_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S05:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% -------------------------------------------------------------------------
% Verify S04 foundation before any structural edit.
% -------------------------------------------------------------------------
fprintf('\n--- Verify S04 foundation ---\n');

stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
arbAGC = [stack '/AA15_Arbitrated_Baseline_AGC'];
group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];
s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];

requiredBlocks = {
    stack
    [stack '/AA15_Request_Normalizer']
    [stack '/AA15_P_Objective_Arbiter']
    arbAGC
    [arbAGC '/AGC_Arbitrated_dPRequest']
    group28Mux
    op28
    s03Diag
    s04Diag
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S05:MissingPrerequisite', ...
            'Missing S04 prerequisite: %s',requiredBlocks{i});
    end
    fprintf('[OK] %s\n',requiredBlocks{i});
end

requiredTags = {
    'AA15_LOCAL_PV1_PREF_CANDIDATE'
    'AA15_LOCAL_PV2_PREF_CANDIDATE'
    'AA15_LOCAL_ESS1_PREF_CANDIDATE'
    'AA15_LOCAL_ESS2_PREF_CANDIDATE'
    'AA15_LOCAL_EV1_PREF_CANDIDATE'
    'AA15_LOCAL_EV2_PREF_CANDIDATE'
    'AA15_ARB_REQUEST_VALID'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotoByTag(mdl,requiredTags{i}))
        error('S05:MissingTag','Missing required Goto tag: %s',requiredTags{i});
    end
end

% Verify Group28 is still exactly the S04 2-input structure.
n28 = str2double(get_param(group28Mux,'Inputs'));
if isnan(n28)
    error('S05:Group28Inputs','Cannot parse Group28 Mux Inputs.');
end

existingS05Diag = [sm '/AA15_STAGE05_ROUTER_DIAGNOSTICS'];
existingS05Port = localFindExistingLogPort(existingS05Diag,group28Mux);

if n28 > 3
    error('S05:LaterStageDetected', ...
        ['Group28 already has %d inputs. Later-stage diagnostics appear ' ...
         'to exist. Do not rerun S05.'],n28);
end

if n28 == 3 && existingS05Port == 0
    error('S05:UnexpectedGroup28Input', ...
        'Group28 has 3 inputs but Stage05 diagnostics are not the third input.');
end

% Guard against rerunning S05 after later-stage real takeover exists.
futureBlocks = {
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_Q_Allocator']
    [stack '/AA15_BlackStart_Executor']
    [sm '/AA15_STAGE06_DIAGNOSTICS']
};

for i = 1:numel(futureBlocks)
    if getSimulinkBlockHandle(futureBlocks{i}) >= 0
        error('S05:FutureStageDetected', ...
            'Later-stage block exists: %s. Refusing destructive S05 rerun.', ...
            futureBlocks{i});
    end
end

% -------------------------------------------------------------------------
% Add six new stack inputs for the exact existing V5-A final Pref signals.
% Ports 1..4 are the S03 strategy vectors and must remain unchanged.
% -------------------------------------------------------------------------
fprintf('\n--- Add LEGACY_V5A Pref inputs to LOCAL control stack ---\n');

legacyDevices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
legacyInNames = {
    'legacy_pv1_pref'
    'legacy_pv2_pref'
    'legacy_ess1_pref'
    'legacy_ess2_pref'
    'legacy_ev1_pref'
    'legacy_ev2_pref'
};

for i = 1:6
    inPath = [stack '/' legacyInNames{i}];
    portNo = 4 + i;
    y = 300 + (i-1)*42;

    if getSimulinkBlockHandle(inPath) < 0
        add_block('simulink/Ports & Subsystems/In1',inPath, ...
            'Port',num2str(portNo), ...
            'Position',[25 y 55 y+16]);
    else
        if ~strcmp(get_param(inPath,'BlockType'),'Inport')
            error('S05:LegacyInConflict','Unexpected block at %s.',inPath);
        end
        set_param(inPath,'Port',num2str(portNo));
    end
end

% Materialize top-level stack ports.
set_param(mdl,'SimulationCommand','update');

stackPorts = get_param(stack,'Ports');
if stackPorts(1) ~= 10
    error('S05:StackPorts', ...
        'AA15_LOCAL_CONTROL_STACK expected 10 inputs after S05, found %d.', ...
        stackPorts(1));
end

fprintf('[OK] AA15_LOCAL_CONTROL_STACK now has 10 inputs.\n');

% -------------------------------------------------------------------------
% Create/reuse top-level From bridges from V5A_FINAL_* tags.
% These are deliberately at SM_Master level so local/scoped V5A Goto tags
% are consumed at the same hierarchy level.
% -------------------------------------------------------------------------
stackPos = get_param(stack,'Position');

bridgeNames = cell(6,1);
legacyTags = cell(6,1);

for i = 1:6
    bridgeNames{i} = ['AA15_S05_FROM_V5A_FINAL_' legacyDevices{i}];
    legacyTags{i} = ['V5A_FINAL_' legacyDevices{i}];

    bridgePath = [sm '/' bridgeNames{i}];

    bx = max(20,stackPos(1)-265);
    by = stackPos(2)+260+(i-1)*42;

    if getSimulinkBlockHandle(bridgePath) < 0
        add_block('simulink/Signal Routing/From',bridgePath, ...
            'GotoTag',legacyTags{i}, ...
            'Position',[bx by bx+220 by+22]);
        fprintf('[CREATE] %s\n',bridgeNames{i});
    else
        if ~strcmp(get_param(bridgePath,'BlockType'),'From')
            error('S05:BridgeConflict','Unexpected block at %s.',bridgePath);
        end
        set_param(bridgePath,'GotoTag',legacyTags{i});
        fprintf('[KEEP]   %s\n',bridgeNames{i});
    end
end

set_param(mdl,'SimulationCommand','update');

stackPH = get_param(stack,'PortHandles');
if numel(stackPH.Inport) ~= 10
    error('S05:StackPortHandles','Stack does not expose 10 input ports.');
end

for i = 1:6
    bridgePH = get_param([sm '/' bridgeNames{i}],'PortHandles');

    localEnsureTopLevelConnection(sm, ...
        bridgePH.Outport(1), ...
        stackPH.Inport(4+i), ...
        sprintf('%s -> stack input %d',bridgeNames{i},4+i));
end

% -------------------------------------------------------------------------
% Publish the six exact legacy inputs globally for diagnostics and later
% router/takeover comparison.
% -------------------------------------------------------------------------
legacyGlobalTags = {
    'AA15_LEGACY_PV1_PREF'
    'AA15_LEGACY_PV2_PREF'
    'AA15_LEGACY_ESS1_PREF'
    'AA15_LEGACY_ESS2_PREF'
    'AA15_LEGACY_EV1_PREF'
    'AA15_LEGACY_EV2_PREF'
};

legacyGotoNames = cell(6,1);

for i = 1:6
    legacyGotoNames{i} = sprintf('GOTO_LEGACY_PREF_%02d',i);
    p = [stack '/' legacyGotoNames{i}];

    localDeleteBlockIfExists(p);

    y = 300 + (i-1)*42;
    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',legacyGlobalTags{i}, ...
        'TagVisibility','global', ...
        'Position',[95 y 300 y+22]);

    localEnsureLine(stack, ...
        [legacyInNames{i} '/1'], ...
        [legacyGotoNames{i} '/1']);
end

% -------------------------------------------------------------------------
% Build/rebuild AA15_Execution_Mapper.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_Execution_Mapper ---\n');

execMap = [stack '/AA15_Execution_Mapper'];

if getSimulinkBlockHandle(execMap) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',execMap, ...
        'Position',[1810 60 2160 330]);
    fprintf('[CREATE] %s\n',execMap);
else
    if ~strcmp(get_param(execMap,'BlockType'),'SubSystem')
        error('S05:ExecMapConflict','%s exists but is not a SubSystem.',execMap);
    end
    fprintf('[REBUILD] %s\n',execMap);
end

localDeleteSubsystemContents(execMap);

try
    set_param(execMap,'AttributesFormatString', ...
        sprintf(['S05 Active-P domain\\n' ...
                 'candidate -> mapped command\\n' ...
                 'SHADOW only']));
catch
end

execInNames = {
    'pv1_candidate'
    'pv2_candidate'
    'ess1_candidate'
    'ess2_candidate'
    'ev1_candidate'
    'ev2_candidate'
    'master_enable'
    'request_valid'
};

for i = 1:8
    y = 35 + (i-1)*44;
    add_block('simulink/Ports & Subsystems/In1', ...
        [execMap '/' execInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);
end

execMF = [execMap '/AA15_Active_P_Execution_Mapper'];
add_block('simulink/User-Defined Functions/MATLAB Function',execMF, ...
    'Position',[180 75 520 390]);

execChart = localGetEMChartByPath(execMF);
execChart.Script = localExecutionMapperScript();

execOutNames = {
    'pv1_exec'
    'pv2_exec'
    'ess1_exec'
    'ess2_exec'
    'ev1_exec'
    'ev2_exec'
    'local_active_valid'
};

for i = 1:7
    y = 45 + (i-1)*48;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [execMap '/' execOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[610 y 640 y+16]);
end

set_param(mdl,'SimulationCommand','update');

execPorts = get_param(execMF,'Ports');
if execPorts(1) ~= 8 || execPorts(2) ~= 7
    error('S05:ExecMapPorts', ...
        'Execution Mapper expected 8-in/7-out, found %d/%d.', ...
        execPorts(1),execPorts(2));
end

for i = 1:8
    localEnsureLine(execMap, ...
        [execInNames{i} '/1'], ...
        sprintf('AA15_Active_P_Execution_Mapper/%d',i));
end

for i = 1:7
    localEnsureLine(execMap, ...
        sprintf('AA15_Active_P_Execution_Mapper/%d',i), ...
        [execOutNames{i} '/1']);
end

fprintf('[OK] Execution Mapper = 8 inputs / 7 outputs.\n');

% -------------------------------------------------------------------------
% Stack-level candidate/config Froms feeding the Execution Mapper.
% -------------------------------------------------------------------------
execSourceTags = {
    'AA15_LOCAL_PV1_PREF_CANDIDATE'
    'AA15_LOCAL_PV2_PREF_CANDIDATE'
    'AA15_LOCAL_ESS1_PREF_CANDIDATE'
    'AA15_LOCAL_ESS2_PREF_CANDIDATE'
    'AA15_LOCAL_EV1_PREF_CANDIDATE'
    'AA15_LOCAL_EV2_PREF_CANDIDATE'
    'CFG15_MASTER_ENABLE'
    'AA15_ARB_REQUEST_VALID'
};

execFromNames = cell(8,1);

for i = 1:8
    execFromNames{i} = sprintf('FROM_EXEC_SRC_%02d',i);
    p = [stack '/' execFromNames{i}];

    localDeleteBlockIfExists(p);

    y = 70 + (i-1)*36;
    add_block('simulink/Signal Routing/From',p, ...
        'GotoTag',execSourceTags{i}, ...
        'Position',[1400 y 1605 y+22]);

    localEnsureLine(stack, ...
        [execFromNames{i} '/1'], ...
        sprintf('AA15_Execution_Mapper/%d',i));
end

% Publish Execution Mapper outputs.
execTags = {
    'AA15_EXEC_PV1_PREF'
    'AA15_EXEC_PV2_PREF'
    'AA15_EXEC_ESS1_PREF'
    'AA15_EXEC_ESS2_PREF'
    'AA15_EXEC_EV1_PREF'
    'AA15_EXEC_EV2_PREF'
    'AA15_EXEC_ACTIVE_VALID'
};

execGotoNames = cell(7,1);

for i = 1:7
    execGotoNames{i} = sprintf('GOTO_EXEC_OUT_%02d',i);
    p = [stack '/' execGotoNames{i}];

    localDeleteBlockIfExists(p);

    y = 75 + (i-1)*42;
    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',execTags{i}, ...
        'TagVisibility','global', ...
        'Position',[2220 y 2425 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Execution_Mapper/%d',i), ...
        [execGotoNames{i} '/1']);
end

% -------------------------------------------------------------------------
% Build/rebuild AA15_Command_Source_Router.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_Command_Source_Router ---\n');

router = [stack '/AA15_Command_Source_Router'];

if getSimulinkBlockHandle(router) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',router, ...
        'Position',[2490 55 2860 405]);
    fprintf('[CREATE] %s\n',router);
else
    if ~strcmp(get_param(router,'BlockType'),'SubSystem')
        error('S05:RouterConflict','%s exists but is not a SubSystem.',router);
    end
    fprintf('[REBUILD] %s\n',router);
end

localDeleteSubsystemContents(router);

try
    set_param(router,'AttributesFormatString', ...
        sprintf(['S05 source selection\\n' ...
                 '0=V5A 1=LOCAL15 2=BOARD15(reserved)\\n' ...
                 'SHADOW only']));
catch
end

routerInNames = {
    'legacy_pv1'
    'legacy_pv2'
    'legacy_ess1'
    'legacy_ess2'
    'legacy_ev1'
    'legacy_ev2'
    'local_pv1'
    'local_pv2'
    'local_ess1'
    'local_ess2'
    'local_ev1'
    'local_ev2'
    'local_valid'
    'control_source'
};

for i = 1:14
    col = floor((i-1)/7);
    row = mod(i-1,7);

    x = 20 + col*140;
    y = 25 + row*46;

    add_block('simulink/Ports & Subsystems/In1', ...
        [router '/' routerInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[x y x+30 y+16]);
end

routerMF = [router '/AA15_Command_Source_Router_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',routerMF, ...
    'Position',[390 70 760 470]);

routerChart = localGetEMChartByPath(routerMF);
routerChart.Script = localRouterScript();

routerOutNames = {
    'ucommit_pv1'
    'ucommit_pv2'
    'ucommit_ess1'
    'ucommit_ess2'
    'ucommit_ev1'
    'ucommit_ev2'
    'selected_source'
    'route_valid'
};

for i = 1:8
    y = 50 + (i-1)*48;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [router '/' routerOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[850 y 880 y+16]);
end

set_param(mdl,'SimulationCommand','update');

routerPorts = get_param(routerMF,'Ports');

if routerPorts(1) ~= 14 || routerPorts(2) ~= 8
    error('S05:RouterPorts', ...
        'Source Router expected 14-in/8-out, found %d/%d.', ...
        routerPorts(1),routerPorts(2));
end

for i = 1:14
    localEnsureLine(router, ...
        [routerInNames{i} '/1'], ...
        sprintf('AA15_Command_Source_Router_Core/%d',i));
end

for i = 1:8
    localEnsureLine(router, ...
        sprintf('AA15_Command_Source_Router_Core/%d',i), ...
        [routerOutNames{i} '/1']);
end

fprintf('[OK] Command Source Router = 14 inputs / 8 outputs.\n');

% -------------------------------------------------------------------------
% Connect router inputs at stack level:
%   1..6  legacy stack inputs
%   7..13 Execution Mapper outputs
%   14    CFG15_CONTROL_SOURCE
% -------------------------------------------------------------------------
for i = 1:6
    localEnsureLine(stack, ...
        [legacyInNames{i} '/1'], ...
        sprintf('AA15_Command_Source_Router/%d',i));
end

for i = 1:7
    localEnsureLine(stack, ...
        sprintf('AA15_Execution_Mapper/%d',i), ...
        sprintf('AA15_Command_Source_Router/%d',6+i));
end

controlFrom = [stack '/FROM_CFG15_CONTROL_SOURCE'];
localDeleteBlockIfExists(controlFrom);

add_block('simulink/Signal Routing/From',controlFrom, ...
    'GotoTag','CFG15_CONTROL_SOURCE', ...
    'Position',[2260 420 2460 442]);

localEnsureLine(stack, ...
    'FROM_CFG15_CONTROL_SOURCE/1', ...
    'AA15_Command_Source_Router/14');

% Publish router outputs.
routerTags = {
    'AA15_U_COMMIT_PV1_SHADOW'
    'AA15_U_COMMIT_PV2_SHADOW'
    'AA15_U_COMMIT_ESS1_SHADOW'
    'AA15_U_COMMIT_ESS2_SHADOW'
    'AA15_U_COMMIT_EV1_SHADOW'
    'AA15_U_COMMIT_EV2_SHADOW'
    'AA15_ROUTER_SELECTED_SOURCE'
    'AA15_ROUTER_VALID'
};

routerGotoNames = cell(8,1);

for i = 1:8
    routerGotoNames{i} = sprintf('GOTO_ROUTER_OUT_%02d',i);
    p = [stack '/' routerGotoNames{i}];

    localDeleteBlockIfExists(p);

    y = 70 + (i-1)*42;

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',routerTags{i}, ...
        'TagVisibility','global', ...
        'Position',[2920 y 3155 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Command_Source_Router/%d',i), ...
        [routerGotoNames{i} '/1']);
end

% -------------------------------------------------------------------------
% Build S05 diagnostics and append to Group28.
% -------------------------------------------------------------------------
fprintf('\n--- Build Stage05 diagnostics ---\n');

s05Diag = existingS05Diag;

if getSimulinkBlockHandle(s05Diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,400,260,420);
    add_block('simulink/Ports & Subsystems/Subsystem',s05Diag, ...
        'Position',[dx dy dx+400 dy+260]);
    fprintf('[CREATE] %s\n',s05Diag);
else
    if ~strcmp(get_param(s05Diag,'BlockType'),'SubSystem')
        error('S05:DiagConflict','%s exists but is not a SubSystem.',s05Diag);
    end
    fprintf('[REBUILD] %s\n',s05Diag);
end

localDeleteSubsystemContents(s05Diag);

try
    set_param(s05Diag,'AttributesFormatString', ...
        sprintf('S05 diagnostics only\\n22 signals\\nGroup28'));
catch
end

diagTags = {
    'AA15_EXEC_PV1_PREF'
    'AA15_EXEC_PV2_PREF'
    'AA15_EXEC_ESS1_PREF'
    'AA15_EXEC_ESS2_PREF'
    'AA15_EXEC_EV1_PREF'
    'AA15_EXEC_EV2_PREF'
    'AA15_EXEC_ACTIVE_VALID'
    'AA15_LEGACY_PV1_PREF'
    'AA15_LEGACY_PV2_PREF'
    'AA15_LEGACY_ESS1_PREF'
    'AA15_LEGACY_ESS2_PREF'
    'AA15_LEGACY_EV1_PREF'
    'AA15_LEGACY_EV2_PREF'
    'AA15_U_COMMIT_PV1_SHADOW'
    'AA15_U_COMMIT_PV2_SHADOW'
    'AA15_U_COMMIT_ESS1_SHADOW'
    'AA15_U_COMMIT_ESS2_SHADOW'
    'AA15_U_COMMIT_EV1_SHADOW'
    'AA15_U_COMMIT_EV2_SHADOW'
    'AA15_ROUTER_SELECTED_SOURCE'
    'AA15_ROUTER_VALID'
    'CFG15_CONTROL_SOURCE'
};

for i = 1:22
    col = floor((i-1)/11);
    row = mod(i-1,11);

    x = 25 + col*230;
    y = 25 + row*35;

    fromName = sprintf('FROM_DIAG_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [s05Diag '/' fromName], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+200 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s05Diag '/AA15_STAGE05_DIAG22'], ...
    'Inputs','22', ...
    'Position',[520 45 555 420]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s05Diag '/diag22'], ...
    'Port','1', ...
    'Position',[615 225 645 241]);

for i = 1:22
    localEnsureLine(s05Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE05_DIAG22/%d',i));
end

localEnsureLine(s05Diag,'AA15_STAGE05_DIAG22/1','diag22/1');

set_param(mdl,'SimulationCommand','update');

s05PH = get_param(s05Diag,'PortHandles');

if numel(s05PH.Outport) ~= 1
    error('S05:DiagPort','Stage05 diagnostics expected one output.');
end

% Reuse existing input3 on a repair rerun; otherwise append input3.
currentS05Port = localFindExistingLogPort(s05Diag,group28Mux);

if currentS05Port > 0
    if currentS05Port ~= 3
        error('S05:Group28S05Port', ...
            'Stage05 diagnostics found on unexpected Group28 input %d.', ...
            currentS05Port);
    end
    fprintf('[KEEP] Stage05 diag22 already on Group28 input3.\n');
else
    n28 = str2double(get_param(group28Mux,'Inputs'));

    if n28 == 2
        set_param(group28Mux,'Inputs','3');
    elseif n28 ~= 3
        error('S05:Group28InputCount', ...
            'Unexpected Group28 input count: %d.',n28);
    end

    mux28PH = get_param(group28Mux,'PortHandles');

    localEnsureTopLevelConnection(sm, ...
        s05PH.Outport(1), ...
        mux28PH.Inport(3), ...
        'Stage05 diag22 -> Group28 input3');

    fprintf('[APPEND] Stage05 diag22 -> Group28 input3.\n');
end

% -------------------------------------------------------------------------
% Final assertions.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / safety assertions ---\n');

set_param(mdl,'SimulationCommand','update');

% Group28 should now be 3 physical Mux inputs:
%   S03 diag16 + S04 diag12 + S05 diag22
n28 = str2double(get_param(group28Mux,'Inputs'));
if n28 ~= 3
    error('S05:Group28Final','Group28 Mux expected 3 inputs, found %d.',n28);
end

if localFindExistingLogPort(s03Diag,group28Mux) ~= 1
    error('S05:Group28S03','S03 diagnostics not on Group28 input1.');
end

if localFindExistingLogPort(s04Diag,group28Mux) ~= 2
    error('S05:Group28S04','S04 diagnostics not on Group28 input2.');
end

if localFindExistingLogPort(s05Diag,group28Mux) ~= 3
    error('S05:Group28S05','S05 diagnostics not on Group28 input3.');
end

% New tags exactly once.
allNewTags = [legacyGlobalTags; execTags; routerTags];

for i = 1:numel(allNewTags)
    g = localFindGotoByTag(mdl,allNewTags{i});

    if numel(g) ~= 1
        error('S05:NewTagCount', ...
            'Expected one Goto for %s, found %d.', ...
            allNewTags{i},numel(g));
    end
end

% V5-A actual route still exists and has not been replaced.
for i = 1:6
    f = localFindFromByTag(mdl,legacyTags{i});

    if isempty(f)
        error('S05:V5ARouteLost','Missing V5-A From tag %s.',legacyTags{i});
    end
end

% S04 arbitrated AGC remains 16/9.
arbMF = [arbAGC '/AGC_Arbitrated_dPRequest'];
arbPorts = get_param(arbMF,'Ports');

if arbPorts(1) ~= 16 || arbPorts(2) ~= 9
    error('S05:ArbAGCChanged', ...
        'S04 arbitrated AGC port structure changed unexpectedly.');
end

% -------------------------------------------------------------------------
% Export map.
% -------------------------------------------------------------------------
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE05_EXEC_ROUTER_MAP_%s.txt',modelBase,stamp));

fid = fopen(mapFile,'w');

if fid >= 0
    fprintf(fid,'LOCAL15 Stage05 - Execution Mapper + Source Router SHADOW\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'AA15_LOCAL_CONTROL_STACK inputs after S05:\n');
    fprintf(fid,'  1 status15\n');
    fprintf(fid,'  2 alarm15\n');
    fprintf(fid,'  3 metric15\n');
    fprintf(fid,'  4 cmd15\n');
    fprintf(fid,'  5 legacy PV1 Pref\n');
    fprintf(fid,'  6 legacy PV2 Pref\n');
    fprintf(fid,'  7 legacy ESS1 Pref\n');
    fprintf(fid,'  8 legacy ESS2 Pref\n');
    fprintf(fid,'  9 legacy EV1 Pref\n');
    fprintf(fid,' 10 legacy EV2 Pref\n\n');

    fprintf(fid,'Execution Mapper outputs:\n');
    for i = 1:numel(execTags)
        fprintf(fid,'  %d %s\n',i,execTags{i});
    end

    fprintf(fid,'\nRouter outputs:\n');
    for i = 1:numel(routerTags)
        fprintf(fid,'  %d %s\n',i,routerTags{i});
    end

    fprintf(fid,'\nCONTROL_SOURCE:\n');
    fprintf(fid,'  0 = LEGACY_V5A\n');
    fprintf(fid,'  1 = LOCAL15\n');
    fprintf(fid,'  2 = BOARD15 reserved; fallback to legacy in S05\n\n');

    fprintf(fid,'Group28 total signals after S05 = 50\n');
    fprintf(fid,'Expected MAT rows = 51 (Target Time + 50 signals)\n\n');

    fprintf(fid,'S05 appended signal order (Group28 positions 29..50):\n');
    for i = 1:22
        fprintf(fid,'  %2d  %s\n',28+i,diagTags{i});
    end

    fprintf(fid,'\nNo device Pref route changed in S05.\n');
    fprintf(fid,'Router output remains SHADOW-only.\n');

    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 05 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Execution Mapper               : created / verified\n');
fprintf('Command Source Router          : created / verified\n');
fprintf('LOCAL15 mapped Prefs           : 6 created\n');
fprintf('Router u_commit SHADOW Prefs   : 6 created\n');
fprintf('CONTROL_SOURCE 0               : LEGACY_V5A\n');
fprintf('CONTROL_SOURCE 1               : LOCAL15 when valid\n');
fprintf('CONTROL_SOURCE 2               : BOARD15 reserved / legacy fallback\n');
fprintf('Group28                        : 50 signals total\n');
fprintf('Expected Group28 MAT rows      : 51\n');
fprintf('V5-A actual device control     : UNCHANGED\n');
fprintf('Mapping TXT                    : %s\n',mapFile);
fprintf('\nNEXT = strategic Build checkpoint.\n');
fprintf('Reason: S03+S04+S05 now form one complete SHADOW chain from\n');
fprintf('strategy request -> arbitration -> AGC -> execution mapping -> router.\n');
fprintf('Build now validates the whole chain before any real takeover.\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% MATLAB Function scripts
% =========================================================================

function scriptText = localExecutionMapperScript()

lines = {};
lines{end+1} = ['function [pv1_exec,pv2_exec,ess1_exec,ess2_exec,' ...
                'ev1_exec,ev2_exec,local_active_valid] = ' ...
                'AA15_Active_P_Execution_Mapper(' ...
                'pv1_c,pv2_c,ess1_c,ess2_c,ev1_c,ev2_c,' ...
                'master_enable,request_valid)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = ['allFinite = isfinite_scalar(pv1_c) && isfinite_scalar(pv2_c) && ' ...
                'isfinite_scalar(ess1_c) && isfinite_scalar(ess2_c) && ' ...
                'isfinite_scalar(ev1_c) && isfinite_scalar(ev2_c);'];
lines{end+1} = '';
lines{end+1} = 'pv1_exec  = clamp_finite(pv1_c,  0.0, 1.0);';
lines{end+1} = 'pv2_exec  = clamp_finite(pv2_c,  0.0, 1.0);';
lines{end+1} = 'ess1_exec = clamp_finite(ess1_c, -1.0, 1.0);';
lines{end+1} = 'ess2_exec = clamp_finite(ess2_c, -1.0, 1.0);';
lines{end+1} = 'ev1_exec  = clamp_finite(ev1_c,  -1.0, 0.0);';
lines{end+1} = 'ev2_exec  = clamp_finite(ev2_c,  -1.0, 0.0);';
lines{end+1} = '';
lines{end+1} = ['local_active_valid = double(master_enable > 0.5 && ' ...
                'request_valid > 0.5 && allFinite);'];
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function y = clamp_finite(x,lo,hi)';
lines{end+1} = 'if isnan(x) || isinf(x)';
lines{end+1} = '    y = 0.0;';
lines{end+1} = 'else';
lines{end+1} = '    y = min(max(x,lo),hi);';
lines{end+1} = 'end';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = isfinite_scalar(x)';
lines{end+1} = 'ok = ~(isnan(x) || isinf(x));';
lines{end+1} = 'end';

scriptText = strjoin(lines,newline);

end


function scriptText = localRouterScript()

lines = {};
lines{end+1} = ['function [u1,u2,u3,u4,u5,u6,selected_source,route_valid] = ' ...
                'AA15_Command_Source_Router_Core(' ...
                'l1,l2,l3,l4,l5,l6,' ...
                'p1,p2,p3,p4,p5,p6,local_valid,control_source)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = '% Default route is the proven LEGACY_V5A source.';
lines{end+1} = 'u1 = l1; u2 = l2; u3 = l3; u4 = l4; u5 = l5; u6 = l6;';
lines{end+1} = 'selected_source = 0.0;';
lines{end+1} = ['legacyFinite = finite6(l1,l2,l3,l4,l5,l6);'];
lines{end+1} = 'route_valid = double(legacyFinite);';
lines{end+1} = '';
lines{end+1} = 'mode = round(control_source);';
lines{end+1} = '';
lines{end+1} = 'if mode == 0';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if mode == 1';
lines{end+1} = '    localFinite = finite6(p1,p2,p3,p4,p5,p6);';
lines{end+1} = '    if local_valid > 0.5 && localFinite';
lines{end+1} = '        u1 = p1; u2 = p2; u3 = p3; u4 = p4; u5 = p5; u6 = p6;';
lines{end+1} = '        selected_source = 1.0;';
lines{end+1} = '        route_valid = 1.0;';
lines{end+1} = '    else';
lines{end+1} = '        selected_source = -1.0;';
lines{end+1} = '        route_valid = 0.0;';
lines{end+1} = '    end';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% BOARD15 is intentionally not available in Stage05.';
lines{end+1} = 'if mode == 2';
lines{end+1} = '    selected_source = -2.0;';
lines{end+1} = '    route_valid = 0.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% Unknown source selection -> legacy fallback but invalid status.';
lines{end+1} = 'selected_source = -99.0;';
lines{end+1} = 'route_valid = 0.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = finite6(a,b,c,d,e,f)';
lines{end+1} = ['ok = ~(isnan(a)||isinf(a)||isnan(b)||isinf(b)||' ...
                'isnan(c)||isinf(c)||isnan(d)||isinf(d)||' ...
                'isnan(e)||isinf(e)||isnan(f)||isinf(f));'];
lines{end+1} = 'end';

scriptText = strjoin(lines,newline);

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
    error('S05:EMChartPath', ...
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
        error('S05:UnexpectedTopLine', ...
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
    error('S05:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S05:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S05:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S05:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S05:UnexpectedExistingLine', ...
            'Destination %s is already driven by a different source.',dst);
    end
end

end


function localDeleteSubsystemContents(subsys)

try
    Simulink.SubSystem.deleteContents(subsys);
    return;
catch
end

inside = find_system(subsys,'SearchDepth',1,'Type','Block');

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


function localDeleteBlockIfExists(blockPath)

if getSimulinkBlockHandle(blockPath) >= 0
    delete_block(blockPath);
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

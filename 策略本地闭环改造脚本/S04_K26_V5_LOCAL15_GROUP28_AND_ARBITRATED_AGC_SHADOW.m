function S04_K26_V5_LOCAL15_GROUP28_AND_ARBITRATED_AGC_SHADOW
% S04_K26_V5_LOCAL15_GROUP28_AND_ARBITRATED_AGC_SHADOW
%
% LOCAL15 Stage 04
%
% Goals
% -----
% 1) Stop expanding Group-26 beyond the already validated S02 width.
%    Move the S03 diag16 away from Group-26.
%
% 2) Create a dedicated acquisition/logging domain:
%
%       Group 28
%       variable: aa15_strategy_data
%
%    Group-26 remains the AGC/resource baseline log.
%    Group-27 remains the Modbus/communication log.
%    Group-28 becomes the LOCAL15/strategy-coordination log.
%
% 3) Create a SECOND baseline AGC instance driven by the S03 arbitrated
%    dP request:
%
%       AA15_ARB_DPREQ_SHADOW
%                 |
%                 v
%       AA15_Arbitrated_Baseline_AGC
%                 |
%                 v
%       six LOCAL15 active-power candidates
%
%    This AGC remains SHADOW ONLY. It does not control PV/ESS/EV.
%
% 4) Log:
%       S03 diag16
%       +
%       S04 AGC diag12
%       =
%       28 Group-28 signals
%
% IMPORTANT
% ---------
% This stage does NOT:
%   - modify any V5-A FINAL_APPLIED route;
%   - modify the S02 validated baseline AGC;
%   - connect LOCAL15 candidates to device Pref;
%   - create the final Execution Mapper;
%   - create the final Command Source Router.
%
% Stage-04 candidate tags:
%   AA15_LOCAL_PV1_PREF_CANDIDATE
%   AA15_LOCAL_PV2_PREF_CANDIDATE
%   AA15_LOCAL_ESS1_PREF_CANDIDATE
%   AA15_LOCAL_ESS2_PREF_CANDIDATE
%   AA15_LOCAL_EV1_PREF_CANDIDATE
%   AA15_LOCAL_EV2_PREF_CANDIDATE
%   AA15_LOCAL_AGC_STATUS
%   AA15_LOCAL_AGC_DP
%   AA15_LOCAL_AGC_REMAIN
%
% Group-28 signal order
% ---------------------
% First 16 = existing S03 diag16:
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
% Next 12 = S04 AGC diag12:
%   17 LOCAL_PV1_candidate_pu
%   18 LOCAL_PV2_candidate_pu
%   19 LOCAL_ESS1_candidate_pu
%   20 LOCAL_ESS2_candidate_pu
%   21 LOCAL_EV1_candidate_pu
%   22 LOCAL_EV2_candidate_pu
%   23 LOCAL_AGC_status
%   24 LOCAL_AGC_dP
%   25 LOCAL_AGC_remain
%   26 arbiter_dP_request_kW
%   27 baseline_dP_request_kW
%   28 arbiter_minus_baseline_dP_kW
%
% Expected Group-28 MAT:
%   row 1  = Target Time
%   row 2..29 = 28 signals above
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 04 - Group28 + Arbitrated AGC Shadow\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S04:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S04:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S04:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE04_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S04:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% -------------------------------------------------------------------------
% Verify S03 foundation before any structural edit.
% -------------------------------------------------------------------------
fprintf('\n--- Verify S03 foundation ---\n');

stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s02AGC = [sm '/AA15_BASELINE_AGC_SHADOW/AGC_Baseline_dPRequest'];

requiredBlocks = {
    stack
    [stack '/AA15_Request_Normalizer']
    [stack '/AA15_P_Objective_Arbiter']
    s03Diag
    s02AGC
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S04:MissingPrerequisite', ...
            'Missing prerequisite: %s',requiredBlocks{i});
    end
    fprintf('[OK] %s\n',requiredBlocks{i});
end

requiredTags = {
    'AA15_ARB_DPREQ_SHADOW'
    'AA15_BASELINE_DPREQ'
    'AA15_AGC_IN_01_T'
    'AA15_AGC_IN_02_P_TARGET_KW'
    'AA15_AGC_IN_03_P_PCC_KW'
    'AA15_AGC_IN_04_PPVMAX1_KW'
    'AA15_AGC_IN_05_PPVMAX2_KW'
    'AA15_AGC_IN_06_SOC1'
    'AA15_AGC_IN_07_SOC2'
    'AA15_AGC_IN_08_ENABLE'
    'AA15_AGC_IN_09_P_UNIT_KW'
    'AA15_AGC_IN_10_P_DEAD_KW'
    'AA15_AGC_IN_11_SOC_MIN'
    'AA15_AGC_IN_12_SOC_MAX'
    'AA15_AGC_IN_13_TS_AGC'
    'AA15_AGC_IN_14_PV_INIT_KW'
    'AA15_AGC_IN_15_EV_INIT_KW'
};

for i = 1:numel(requiredTags)
    g = localFindGotoByTag(mdl,requiredTags{i});
    if isempty(g)
        error('S04:MissingTag','Missing required Goto tag: %s',requiredTags{i});
    end
end

fprintf('[OK] Required S02/S03 global tags found.\n');

% Prevent destructive S04 rerun after later-stage work exists.
futureBlocks = {
    [stack '/AA15_Execution_Mapper']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_Q_Allocator']
    [sm '/AA15_STAGE05_DIAGNOSTICS']
};

for i = 1:numel(futureBlocks)
    if getSimulinkBlockHandle(futureBlocks{i}) >= 0
        error('S04:FutureStageDetected', ...
            ['Later-stage block already exists: %s. ' ...
             'Do not rerun S04 because it could invalidate later work.'], ...
             futureBlocks{i});
    end
end

% -------------------------------------------------------------------------
% Discover Group-26 and detach S03 diag16 if S03 appended it there.
% Group-26 must return to the S02 state: original 97 + S02 diag12 = 109.
% -------------------------------------------------------------------------
fprintf('\n--- Restore Group26 to S02 logging scope ---\n');

[op26,mux26] = localDiscoverGroup26(sm);

fprintf('[OK] Group26 OpWrite : %s\n',op26);
fprintf('[OK] Group26 Mux     : %s\n',mux26);

s03PortOn26 = localFindExistingLogPort(s03Diag,mux26);

if s03PortOn26 > 0
    oldN = str2double(get_param(mux26,'Inputs'));
    if isnan(oldN)
        error('S04:Group26MuxInputs','Cannot parse Group26 Mux Inputs.');
    end

    if s03PortOn26 ~= oldN
        error('S04:Group26Order', ...
            ['S03 diag16 is connected to Group26 Mux input %d, but the ' ...
             'last input is %d. Refusing to reorder unknown later signals.'], ...
             s03PortOn26,oldN);
    end

    s03PH = get_param(s03Diag,'PortHandles');
    ln = get_param(s03PH.Outport(1),'Line');

    if isequal(ln,-1)
        error('S04:S03DiagLine','Expected S03 diagnostic line is missing.');
    end

    dst = get_param(ln,'DstPortHandle');
    dst = dst(dst >= 0);

    if numel(dst) ~= 1
        error('S04:S03DiagBranch', ...
            ['S03 diag16 currently has %d destinations. ' ...
             'Refusing automatic deletion of a branched line.'],numel(dst));
    end

    delete_line(ln);
    set_param(mux26,'Inputs',num2str(oldN-1));

    fprintf('[REMOVE] S03 diag16 removed from Group26 input %d.\n',s03PortOn26);
    fprintf('[RESTORE] Group26 physical Mux inputs: %d -> %d\n',oldN,oldN-1);
else
    fprintf('[KEEP] S03 diag16 is already not connected to Group26.\n');
end

% -------------------------------------------------------------------------
% Build/rebuild the arbitrated baseline AGC inside LOCAL control stack.
% It copies the already validated S02 AGC implementation exactly and only
% changes the MATLAB Function name. Input 16 is AA15_ARB_DPREQ_SHADOW.
% -------------------------------------------------------------------------
fprintf('\n--- Build arbitrated baseline AGC shadow ---\n');

arbAGCSub = [stack '/AA15_Arbitrated_Baseline_AGC'];

if getSimulinkBlockHandle(arbAGCSub) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',arbAGCSub, ...
        'Position',[1380 65 1760 350]);
    fprintf('[CREATE] %s\n',arbAGCSub);
else
    if ~strcmp(get_param(arbAGCSub,'BlockType'),'SubSystem')
        error('S04:ArbAGCConflict','%s exists but is not a SubSystem.',arbAGCSub);
    end
    fprintf('[REBUILD] %s\n',arbAGCSub);
end

localDeleteSubsystemContents(arbAGCSub);

try
    set_param(arbAGCSub,'AttributesFormatString', ...
        sprintf(['S04 SHADOW AGC\\n' ...
                 'Input16 = arbitrated dP\\n' ...
                 'NO device takeover']));
catch
end

agcInputTags = {
    'AA15_AGC_IN_01_T'
    'AA15_AGC_IN_02_P_TARGET_KW'
    'AA15_AGC_IN_03_P_PCC_KW'
    'AA15_AGC_IN_04_PPVMAX1_KW'
    'AA15_AGC_IN_05_PPVMAX2_KW'
    'AA15_AGC_IN_06_SOC1'
    'AA15_AGC_IN_07_SOC2'
    'AA15_AGC_IN_08_ENABLE'
    'AA15_AGC_IN_09_P_UNIT_KW'
    'AA15_AGC_IN_10_P_DEAD_KW'
    'AA15_AGC_IN_11_SOC_MIN'
    'AA15_AGC_IN_12_SOC_MAX'
    'AA15_AGC_IN_13_TS_AGC'
    'AA15_AGC_IN_14_PV_INIT_KW'
    'AA15_AGC_IN_15_EV_INIT_KW'
    'AA15_ARB_DPREQ_SHADOW'
};

for i = 1:16
    col = floor((i-1)/8);
    row = mod(i-1,8);

    x = 25 + col*250;
    y = 35 + row*54;

    fromName = sprintf('FROM_AGC_IN_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [arbAGCSub '/' fromName], ...
        'GotoTag',agcInputTags{i}, ...
        'Position',[x y x+215 y+22]);
end

% Copy the exact S02 validated MATLAB Function code.
s02Chart = localGetEMChartByPath(s02AGC);
newScript = s02Chart.Script;

if ~contains(newScript,'AGC_Baseline_dPRequest(')
    error('S04:S02AGCSource', ...
        'S02 AGC source does not contain expected function name.');
end

newScript = strrep(newScript, ...
    'AGC_Baseline_dPRequest(', ...
    'AGC_Arbitrated_dPRequest(');

arbMF = [arbAGCSub '/AGC_Arbitrated_dPRequest'];

add_block('simulink/User-Defined Functions/MATLAB Function',arbMF, ...
    'Position',[590 90 930 520]);

arbChart = localGetEMChartByPath(arbMF);
arbChart.Script = newScript;

fprintf('[CREATE] %s from exact S02 validated AGC source.\n',arbMF);

% Materialize 16/9 ports.
set_param(mdl,'SimulationCommand','update');

arbPorts = get_param(arbMF,'Ports');

if arbPorts(1) ~= 16 || arbPorts(2) ~= 9
    error('S04:ArbAGCPorts', ...
        'Arbitrated AGC expected 16-in/9-out, found %d/%d.', ...
        arbPorts(1),arbPorts(2));
end

fprintf('[OK] Arbitrated AGC = 16 inputs / 9 outputs.\n');

% Connect 16 From blocks to MATLAB Function.
for i = 1:16
    localEnsureLine(arbAGCSub, ...
        sprintf('FROM_AGC_IN_%02d/1',i), ...
        sprintf('AGC_Arbitrated_dPRequest/%d',i));
end

candidateTags = {
    'AA15_LOCAL_PV1_PREF_CANDIDATE'
    'AA15_LOCAL_PV2_PREF_CANDIDATE'
    'AA15_LOCAL_ESS1_PREF_CANDIDATE'
    'AA15_LOCAL_ESS2_PREF_CANDIDATE'
    'AA15_LOCAL_EV1_PREF_CANDIDATE'
    'AA15_LOCAL_EV2_PREF_CANDIDATE'
    'AA15_LOCAL_AGC_STATUS'
    'AA15_LOCAL_AGC_DP'
    'AA15_LOCAL_AGC_REMAIN'
};

for i = 1:9
    y = 55 + (i-1)*46;
    gotoName = sprintf('GOTO_LOCAL_AGC_OUT_%02d',i);

    add_block('simulink/Signal Routing/Goto', ...
        [arbAGCSub '/' gotoName], ...
        'GotoTag',candidateTags{i}, ...
        'TagVisibility','global', ...
        'Position',[1010 y 1250 y+22]);

    localEnsureLine(arbAGCSub, ...
        sprintf('AGC_Arbitrated_dPRequest/%d',i), ...
        [gotoName '/1']);
end

% -------------------------------------------------------------------------
% Build Stage-04 AGC diagnostics (12 signals).
% -------------------------------------------------------------------------
fprintf('\n--- Build Stage04 AGC diagnostics ---\n');

s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];

if getSimulinkBlockHandle(s04Diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,390,250,420);
    add_block('simulink/Ports & Subsystems/Subsystem',s04Diag, ...
        'Position',[dx dy dx+390 dy+250]);
    fprintf('[CREATE] %s\n',s04Diag);
else
    if ~strcmp(get_param(s04Diag,'BlockType'),'SubSystem')
        error('S04:DiagConflict','%s exists but is not a SubSystem.',s04Diag);
    end
    fprintf('[REBUILD] %s\n',s04Diag);
end

localDeleteSubsystemContents(s04Diag);

try
    set_param(s04Diag,'AttributesFormatString', ...
        sprintf('S04 diagnostics only\\n12 signals\\nGroup28'));
catch
end

s04DiagFromTags = {
    'AA15_LOCAL_PV1_PREF_CANDIDATE'
    'AA15_LOCAL_PV2_PREF_CANDIDATE'
    'AA15_LOCAL_ESS1_PREF_CANDIDATE'
    'AA15_LOCAL_ESS2_PREF_CANDIDATE'
    'AA15_LOCAL_EV1_PREF_CANDIDATE'
    'AA15_LOCAL_EV2_PREF_CANDIDATE'
    'AA15_LOCAL_AGC_STATUS'
    'AA15_LOCAL_AGC_DP'
    'AA15_LOCAL_AGC_REMAIN'
    'AA15_ARB_DPREQ_SHADOW'
    'AA15_BASELINE_DPREQ'
};

for i = 1:11
    col = floor((i-1)/6);
    row = mod(i-1,6);

    x = 25 + col*230;
    y = 30 + row*52;

    fromName = sprintf('FROM_DIAG_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [s04Diag '/' fromName], ...
        'GotoTag',s04DiagFromTags{i}, ...
        'Position',[x y x+200 y+22]);
end

% Difference = arbitrated request - traditional baseline request.
add_block('simulink/Math Operations/Sum', ...
    [s04Diag '/ARB_MINUS_BASELINE_DPREQ'], ...
    'Inputs','+-', ...
    'Position',[515 325 565 365]);

localEnsureLine(s04Diag,'FROM_DIAG_10/1','ARB_MINUS_BASELINE_DPREQ/1');
localEnsureLine(s04Diag,'FROM_DIAG_11/1','ARB_MINUS_BASELINE_DPREQ/2');

add_block('simulink/Signal Routing/Mux', ...
    [s04Diag '/AA15_STAGE04_AGC_DIAG12'], ...
    'Inputs','12', ...
    'Position',[650 45 685 390]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s04Diag '/diag12'], ...
    'Port','1', ...
    'Position',[745 215 775 231]);

for i = 1:11
    localEnsureLine(s04Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE04_AGC_DIAG12/%d',i));
end

localEnsureLine(s04Diag, ...
    'ARB_MINUS_BASELINE_DPREQ/1', ...
    'AA15_STAGE04_AGC_DIAG12/12');

localEnsureLine(s04Diag, ...
    'AA15_STAGE04_AGC_DIAG12/1', ...
    'diag12/1');

% -------------------------------------------------------------------------
% Create/reuse Group-28 logging blocks.
% We clone Group-26 OpWriteFile to preserve proven RT-LAB mask/buffer
% settings, then change only the logging identity:
%   Acquisition group = 28
%   Variable name     = aa15_strategy_data
%   Filename          = aa15_strategy_data.mat
% -------------------------------------------------------------------------
fprintf('\n--- Create/reuse Group28 logging domain ---\n');

group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

if getSimulinkBlockHandle(group28Mux) < 0
    [gx,gy] = localFindFreeTopLevelPosition(sm,40,190,420);

    add_block('simulink/Signal Routing/Mux',group28Mux, ...
        'Inputs','2', ...
        'Position',[gx gy gx+35 gy+170]);

    fprintf('[CREATE] %s\n',group28Mux);
else
    if ~strcmp(get_param(group28Mux,'BlockType'),'Mux')
        error('S04:Group28MuxConflict','%s exists but is not a Mux.',group28Mux);
    end

    existingN = str2double(get_param(group28Mux,'Inputs'));

    if isnan(existingN)
        error('S04:Group28MuxInputs','Cannot parse Group28 Mux Inputs.');
    end

    if existingN > 2
        error('S04:LaterGroup28Data', ...
            ['Group28 Mux already has %d inputs. This suggests later-stage ' ...
             'diagnostics exist. Refusing to rebuild Stage04.'],existingN);
    end

    set_param(group28Mux,'Inputs','2');
    fprintf('[KEEP] %s\n',group28Mux);
end

mux28Pos = get_param(group28Mux,'Position');

if getSimulinkBlockHandle(op28) < 0
    add_block(op26,op28, ...
        'Position',[mux28Pos(3)+110 mux28Pos(2)+40 ...
                    mux28Pos(3)+310 mux28Pos(2)+125]);
    fprintf('[CREATE] %s cloned from proven Group26 OpWriteFile.\n',op28);
else
    fprintf('[KEEP] %s\n',op28);
end

% Set unique logging identity robustly across RT-LAB mask implementations.
localSetDialogOrMaskParameter(op28,'Acq_Group','28',true);
localSetDialogOrMaskParameter(op28,'varname','aa15_strategy_data',true);
localSetDialogOrMaskParameter(op28,'Filename','aa15_strategy_data.mat',true);

% Print useful inherited settings without forcing mask names to exist.
fprintf('\nGroup28 OpWrite settings:\n');
logParams = {
    'Acq_Group'
    'varname'
    'Filename'
    'Nb_Samples'
    'Buffer_size'
    'file_size'
    'Decimation'
};

for i = 1:numel(logParams)
    [ok,val] = localReadDialogOrMaskParameter(op28,logParams{i});

    if ok
        fprintf('  %-12s = %s\n',logParams{i},localToChar(val));
    else
        fprintf('  %-12s = <not exposed by current mask API>\n',logParams{i});
    end
end

% Group28 Mux -> OpWrite.
mux28PH = get_param(group28Mux,'PortHandles');
op28PH = get_param(op28,'PortHandles');

if isempty(mux28PH.Outport) || isempty(op28PH.Inport)
    error('S04:Group28Ports','Group28 Mux or OpWriteFile port is missing.');
end

localEnsureTopLevelConnection(sm,mux28PH.Outport(1),op28PH.Inport(1), ...
    'Group28 Mux -> Group28 OpWriteFile');

% Connect S03 diag16 and S04 diag12.
set_param(mdl,'SimulationCommand','update');

s03PH = get_param(s03Diag,'PortHandles');
s04PH = get_param(s04Diag,'PortHandles');
mux28PH = get_param(group28Mux,'PortHandles');

if numel(mux28PH.Inport) ~= 2
    error('S04:Group28MuxPorts','Group28 Mux expected 2 physical inputs.');
end

localEnsureTopLevelConnection(sm,s03PH.Outport(1),mux28PH.Inport(1), ...
    'S03 diag16 -> Group28 input1');

localEnsureTopLevelConnection(sm,s04PH.Outport(1),mux28PH.Inport(2), ...
    'S04 diag12 -> Group28 input2');

fprintf('[CONNECT] Group28 input1 = S03 diag16\n');
fprintf('[CONNECT] Group28 input2 = S04 AGC diag12\n');

% -------------------------------------------------------------------------
% Final update / assertions.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / safety assertions ---\n');

set_param(mdl,'SimulationCommand','update');

% Group26 must no longer receive S03 diag.
if localFindExistingLogPort(s03Diag,mux26) > 0
    error('S04:Group26StillHasS03', ...
        'S03 diag16 is still connected to Group26.');
end

% S03 and S04 diagnostics must both feed Group28.
if localFindExistingLogPort(s03Diag,group28Mux) ~= 1
    error('S04:Group28S03','S03 diag16 is not on Group28 input1.');
end

if localFindExistingLogPort(s04Diag,group28Mux) ~= 2
    error('S04:Group28S04','S04 diag12 is not on Group28 input2.');
end

% Validate Group28 identity when readable.
[okGroup,groupVal] = localReadDialogOrMaskParameter(op28,'Acq_Group');
if okGroup
    if str2double(strtrim(localToChar(groupVal))) ~= 28
        error('S04:Group28ID','Group28 OpWriteFile does not report group 28.');
    end
end

[okVar,varVal] = localReadDialogOrMaskParameter(op28,'varname');
if okVar
    if ~strcmp(strtrim(localToChar(varVal)),'aa15_strategy_data')
        error('S04:Group28Var', ...
            'Group28 variable name is not aa15_strategy_data.');
    end
end

% All candidate tags must exist exactly once.
for i = 1:numel(candidateTags)
    g = localFindGotoByTag(mdl,candidateTags{i});

    if numel(g) ~= 1
        error('S04:CandidateTagCount', ...
            'Expected exactly one Goto for %s, found %d.', ...
            candidateTags{i},numel(g));
    end
end

% S02 baseline AGC remains 16/9.
s02PortsAfter = get_param(s02AGC,'Ports');

if s02PortsAfter(1) ~= 16 || s02PortsAfter(2) ~= 9
    error('S04:S02AGCChanged', ...
        'S02 baseline AGC port structure changed unexpectedly.');
end

% V5-A actual device routes still exist.
devices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};

for i = 1:numel(devices)
    tag = ['V5A_FINAL_' devices{i}];
    f = localFindFromByTag(mdl,tag);

    if isempty(f)
        error('S04:V5ARouteLost','Missing V5-A From tag %s.',tag);
    end
end

% -------------------------------------------------------------------------
% Export mapping.
% -------------------------------------------------------------------------
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE04_GROUP28_AGC_MAP_%s.txt',modelBase,stamp));

fid = fopen(mapFile,'w');

if fid >= 0
    fprintf(fid,'LOCAL15 Stage04 - Group28 + Arbitrated AGC Shadow\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'Logging domains after S04:\n');
    fprintf(fid,'  Group26: agc_target_data, S02 scope, expected 109 signals\n');
    fprintf(fid,'  Group27: existing communication log, unchanged\n');
    fprintf(fid,'  Group28: aa15_strategy_data, 28 signals\n\n');

    fprintf(fid,'Arbitrated AGC input16:\n');
    fprintf(fid,'  AA15_ARB_DPREQ_SHADOW\n\n');

    fprintf(fid,'Candidate output tags:\n');
    for i = 1:numel(candidateTags)
        fprintf(fid,'  %d %s\n',i,candidateTags{i});
    end

    fprintf(fid,'\nGroup28 signal order:\n');
    s03Names = {
        'S2_status'
        'S2_alarm'
        'S2_metric'
        'S2_dP_request_kW'
        'S7_status'
        'S7_alarm'
        'S7_metric'
        'S7_dP_request_kW'
        'baseline_dP_request_kW'
        'arbiter_dP_request_kW'
        'selected_source'
        'request_valid'
        'duplicate_guard'
        's2_monitor_only'
        'P_OBJECTIVE_MODE'
        'MASTER_ENABLE'
    };

    s04Names = {
        'LOCAL_PV1_candidate_pu'
        'LOCAL_PV2_candidate_pu'
        'LOCAL_ESS1_candidate_pu'
        'LOCAL_ESS2_candidate_pu'
        'LOCAL_EV1_candidate_pu'
        'LOCAL_EV2_candidate_pu'
        'LOCAL_AGC_status'
        'LOCAL_AGC_dP'
        'LOCAL_AGC_remain'
        'arbiter_dP_request_kW'
        'baseline_dP_request_kW'
        'arbiter_minus_baseline_dP_kW'
    };

    for i = 1:16
        fprintf(fid,'  %2d %s\n',i,s03Names{i});
    end

    for i = 1:12
        fprintf(fid,'  %2d %s\n',16+i,s04Names{i});
    end

    fprintf(fid,'\nExpected Group28 MAT rows:\n');
    fprintf(fid,'  row 1 = Target Time\n');
    fprintf(fid,'  row 2..29 = 28 logged signals\n\n');

    fprintf(fid,'No V5-A device Pref route changed.\n');
    fprintf(fid,'No S02 baseline AGC code or input changed.\n');
    fprintf(fid,'LOCAL15 candidate outputs remain shadow-only.\n');

    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 04 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Group26                      : restored to S02 scope\n');
fprintf('Group27                      : unchanged\n');
fprintf('Group28                      : created / verified\n');
fprintf('Group28 variable             : aa15_strategy_data\n');
fprintf('Group28 signals              : 16 (S03) + 12 (S04) = 28\n');
fprintf('Expected Group28 MAT rows    : 29\n');
fprintf('Arbitrated Baseline AGC      : created, 16 in / 9 out\n');
fprintf('LOCAL15 six Pref candidates  : created\n');
fprintf('V5-A actual device control   : UNCHANGED\n');
fprintf('S02 validated baseline AGC   : UNCHANGED\n');
fprintf('Mapping TXT                  : %s\n',mapFile);
fprintf('\nDO NOT BUILD YET.\n');
fprintf('Proceed to Stage05 Execution Mapper + Source Router SHADOW,\n');
fprintf('then perform the next strategic Build.\n');
fprintf('============================================================\n\n');

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
    error('S04:EMChartPath', ...
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
    error('S04:Group26','Known Group26 OpWriteFile is missing: %s',opWrite);
end

ph = get_param(opWrite,'PortHandles');

if isempty(ph.Inport)
    error('S04:Group26','Group26 OpWriteFile has no input.');
end

ln = get_param(ph.Inport(1),'Line');

if isequal(ln,-1)
    error('S04:Group26','Group26 OpWriteFile is unconnected.');
end

srcBlock = get_param(ln,'SrcBlockHandle');

if isempty(srcBlock) || srcBlock < 0
    error('S04:Group26','Cannot resolve Group26 upstream block.');
end

logMux = getfullname(srcBlock);

if ~strcmp(get_param(logMux,'BlockType'),'Mux')
    error('S04:Group26','Group26 upstream block is not a Mux: %s',logMux);
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
        error('S04:UnexpectedTopLine', ...
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
    error('S04:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S04:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S04:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S04:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S04:UnexpectedExistingLine', ...
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


function [ok,val] = localReadDialogOrMaskParameter(block,paramName)

ok = false;
val = '';

try
    val = get_param(block,paramName);
    ok = true;
    return;
catch
end

try
    obj = get_param(block,'ObjectParameters');
    fields = fieldnames(obj);
    hit = find(strcmpi(fields,paramName),1,'first');

    if ~isempty(hit)
        val = get_param(block,fields{hit});
        ok = true;
        return;
    end
catch
end

try
    names = get_param(block,'MaskNames');
    values = get_param(block,'MaskValues');

    if ischar(names)
        names = cellstr(names);
    end

    hit = find(strcmpi(names,paramName),1,'first');

    if ~isempty(hit) && numel(values) >= hit
        val = values{hit};
        ok = true;
        return;
    end
catch
end

try
    dp = get_param(block,'DialogParameters');

    if isstruct(dp)
        fields = fieldnames(dp);
        hit = find(strcmpi(fields,paramName),1,'first');

        if ~isempty(hit)
            val = get_param(block,fields{hit});
            ok = true;
            return;
        end
    end
catch
end

end


function localSetDialogOrMaskParameter(block,paramName,newValue,required)

if nargin < 4
    required = true;
end

done = false;

% Direct parameter.
try
    set_param(block,paramName,newValue);
    done = true;
catch
end

% Case-insensitive ObjectParameters.
if ~done
    try
        obj = get_param(block,'ObjectParameters');
        fields = fieldnames(obj);
        hit = find(strcmpi(fields,paramName),1,'first');

        if ~isempty(hit)
            set_param(block,fields{hit},newValue);
            done = true;
        end
    catch
    end
end

% MaskNames/MaskValues fallback.
if ~done
    try
        names = get_param(block,'MaskNames');
        values = get_param(block,'MaskValues');

        if ischar(names)
            names = cellstr(names);
        end

        hit = find(strcmpi(names,paramName),1,'first');

        if ~isempty(hit)
            values{hit} = newValue;
            set_param(block,'MaskValues',values);
            done = true;
        end
    catch
    end
end

% DialogParameters fallback.
if ~done
    try
        dp = get_param(block,'DialogParameters');

        if isstruct(dp)
            fields = fieldnames(dp);
            hit = find(strcmpi(fields,paramName),1,'first');

            if ~isempty(hit)
                set_param(block,fields{hit},newValue);
                done = true;
            end
        end
    catch
    end
end

if ~done && required
    error('S04:MaskSet', ...
        'Could not set required parameter %s on %s.',paramName,block);
elseif ~done
    warning('S04:MaskSet', ...
        'Could not set optional parameter %s on %s.',paramName,block);
end

end


function s = localToChar(v)

if ischar(v)
    s = v;
elseif isstring(v)
    if isscalar(v)
        s = char(v);
    else
        s = strjoin(cellstr(v),',');
    end
elseif isnumeric(v) || islogical(v)
    s = mat2str(v);
else
    try
        s = char(string(v));
    catch
        s = '<unprintable>';
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

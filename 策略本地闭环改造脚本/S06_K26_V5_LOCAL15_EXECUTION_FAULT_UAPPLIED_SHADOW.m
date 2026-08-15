function S06_K26_V5_LOCAL15_EXECUTION_FAULT_UAPPLIED_SHADOW
% S06_K26_V5_LOCAL15_EXECUTION_FAULT_UAPPLIED_SHADOW
%
% LOCAL15 Stage 06
%
% Purpose
% -------
% Complete the paper/project execution-state chain in SHADOW form:
%
%   S04 AGC candidate
%      -> S05 Execution Mapper
%      -> S05 Source Router
%      -> u_commit SHADOW
%      -> S06 Execution Fault Injector
%      -> u_applied SHADOW
%
% This stage still does NOT connect u_applied to the six device Pref ports.
%
% Execution fault model
% ---------------------
% Current V0.1 is a safe gain-degradation model:
%
%   u_applied(device) = gain * u_commit(device)
%
% during:
%
%   fault_enable = 1
%   start_s <= t < end_s
%
% Device mapping:
%   1 = PV1
%   2 = PV2
%   3 = ESS1
%   4 = ESS2
%   5 = EV1
%   6 = EV2
%
% For safety, gain is clamped to [0,1].
%   1.0 = no degradation
%   0.3 = only 30% of committed command is actually applied
%   0.0 = complete loss of commanded actuation
%
% Inputs of AA15_Execution_Fault_Injector:
%   1..6  u_commit SHADOW
%   7     simulation time t
%   8     CFG15_EXEC_FAULT_ENABLE
%   9     CFG15_EXEC_FAULT_DEVICE
%   10    CFG15_EXEC_FAULT_GAIN
%   11    CFG15_EXEC_FAULT_START_S
%   12    CFG15_EXEC_FAULT_END_S
%
% Outputs:
%   1..6  u_applied SHADOW
%   7     fault_active
%   8     fault_device_active
%   9     fault_gain_active
%   10    max_abs(u_commit-u_applied)
%
% New global tags:
%   AA15_U_APPLIED_PV1_SHADOW
%   AA15_U_APPLIED_PV2_SHADOW
%   AA15_U_APPLIED_ESS1_SHADOW
%   AA15_U_APPLIED_ESS2_SHADOW
%   AA15_U_APPLIED_EV1_SHADOW
%   AA15_U_APPLIED_EV2_SHADOW
%   AA15_EXEC_FAULT_ACTIVE
%   AA15_EXEC_FAULT_DEVICE_ACTIVE
%   AA15_EXEC_FAULT_GAIN_ACTIVE
%   AA15_COMMIT_APPLIED_MAX_DELTA
%
% Group-28
% --------
% S05 total = 50 signals.
% S06 appends 10 signals:
%   51 u_applied PV1
%   52 u_applied PV2
%   53 u_applied ESS1
%   54 u_applied ESS2
%   55 u_applied EV1
%   56 u_applied EV2
%   57 fault_active
%   58 fault_device_active
%   59 fault_gain_active
%   60 max_abs(commit-applied)
%
% Expected Group-28 MAT:
%   61 rows = Target Time + 60 signals.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 06 - Execution Fault + u_applied SHADOW\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S06:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S06:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S06:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE06_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S06:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% -------------------------------------------------------------------------
% Verify S05 foundation.
% -------------------------------------------------------------------------
fprintf('\n--- Verify S05 foundation ---\n');

stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
router = [stack '/AA15_Command_Source_Router'];
execMap = [stack '/AA15_Execution_Mapper'];

group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];
s05Diag = [sm '/AA15_STAGE05_ROUTER_DIAGNOSTICS'];

requiredBlocks = {
    stack
    router
    execMap
    group28Mux
    op28
    s03Diag
    s04Diag
    s05Diag
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S06:MissingPrerequisite', ...
            'Missing S05 prerequisite: %s',requiredBlocks{i});
    end
    fprintf('[OK] %s\n',requiredBlocks{i});
end

requiredTags = {
    'AA15_U_COMMIT_PV1_SHADOW'
    'AA15_U_COMMIT_PV2_SHADOW'
    'AA15_U_COMMIT_ESS1_SHADOW'
    'AA15_U_COMMIT_ESS2_SHADOW'
    'AA15_U_COMMIT_EV1_SHADOW'
    'AA15_U_COMMIT_EV2_SHADOW'
    'AA15_AGC_IN_01_T'
    'CFG15_EXEC_FAULT_ENABLE'
    'CFG15_EXEC_FAULT_DEVICE'
    'CFG15_EXEC_FAULT_GAIN'
    'CFG15_EXEC_FAULT_START_S'
    'CFG15_EXEC_FAULT_END_S'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotoByTag(mdl,requiredTags{i}))
        error('S06:MissingTag','Missing required Goto tag: %s',requiredTags{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if isnan(n28)
    error('S06:Group28Inputs','Cannot parse Group28 Mux Inputs.');
end

s06Diag = [sm '/AA15_STAGE06_EXECFAULT_DIAGNOSTICS'];
existingS06Port = localFindExistingLogPort(s06Diag,group28Mux);

if n28 > 4
    error('S06:LaterStageDetected', ...
        ['Group28 already has %d physical inputs. Later-stage diagnostics ' ...
         'appear to exist. Do not rerun S06.'],n28);
end

if n28 == 4 && existingS06Port == 0
    error('S06:UnexpectedGroup28Input', ...
        'Group28 has 4 inputs but Stage06 diagnostics are not input4.');
end

futureBlocks = {
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_Q_Allocator']
    [stack '/AA15_BlackStart_Executor']
    [sm '/AA15_STAGE07_DIAGNOSTICS']
};

for i = 1:numel(futureBlocks)
    if getSimulinkBlockHandle(futureBlocks{i}) >= 0
        error('S06:FutureStageDetected', ...
            'Later-stage block exists: %s. Refusing destructive S06 rerun.', ...
            futureBlocks{i});
    end
end

fprintf('[OK] S05 foundation verified.\n');

% -------------------------------------------------------------------------
% Build/rebuild the Execution Fault Injector inside the LOCAL control stack.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_Execution_Fault_Injector ---\n');

injector = [stack '/AA15_Execution_Fault_Injector'];

if getSimulinkBlockHandle(injector) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',injector, ...
        'Position',[3220 55 3630 410]);
    fprintf('[CREATE] %s\n',injector);
else
    if ~strcmp(get_param(injector,'BlockType'),'SubSystem')
        error('S06:InjectorConflict','%s exists but is not a SubSystem.',injector);
    end
    fprintf('[REBUILD] %s\n',injector);
end

localDeleteSubsystemContents(injector);

try
    set_param(injector,'AttributesFormatString', ...
        sprintf(['S06 execution fault\\n' ...
                 'u_commit -> u_applied\\n' ...
                 'gain degradation SHADOW']));
catch
end

inNames = {
    'ucommit_pv1'
    'ucommit_pv2'
    'ucommit_ess1'
    'ucommit_ess2'
    'ucommit_ev1'
    'ucommit_ev2'
    't'
    'fault_enable'
    'fault_device'
    'fault_gain'
    'fault_start_s'
    'fault_end_s'
};

for i = 1:12
    col = floor((i-1)/6);
    row = mod(i-1,6);

    x = 20 + col*170;
    y = 30 + row*50;

    add_block('simulink/Ports & Subsystems/In1', ...
        [injector '/' inNames{i}], ...
        'Port',num2str(i), ...
        'Position',[x y x+30 y+16]);
end

core = [injector '/AA15_Execution_Fault_Injector_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',core, ...
    'Position',[430 75 830 500]);

chart = localGetEMChartByPath(core);
chart.Script = localFaultInjectorScript();

outNames = {
    'uapplied_pv1'
    'uapplied_pv2'
    'uapplied_ess1'
    'uapplied_ess2'
    'uapplied_ev1'
    'uapplied_ev2'
    'fault_active'
    'fault_device_active'
    'fault_gain_active'
    'max_commit_applied_delta'
};

for i = 1:10
    y = 45 + (i-1)*44;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [injector '/' outNames{i}], ...
        'Port',num2str(i), ...
        'Position',[930 y 960 y+16]);
end

set_param(mdl,'SimulationCommand','update');

corePorts = get_param(core,'Ports');

if corePorts(1) ~= 12 || corePorts(2) ~= 10
    error('S06:InjectorPorts', ...
        'Execution Fault Injector expected 12-in/10-out, found %d/%d.', ...
        corePorts(1),corePorts(2));
end

for i = 1:12
    localEnsureLine(injector, ...
        [inNames{i} '/1'], ...
        sprintf('AA15_Execution_Fault_Injector_Core/%d',i));
end

for i = 1:10
    localEnsureLine(injector, ...
        sprintf('AA15_Execution_Fault_Injector_Core/%d',i), ...
        [outNames{i} '/1']);
end

fprintf('[OK] Execution Fault Injector = 12 inputs / 10 outputs.\n');

% -------------------------------------------------------------------------
% Feed injector from S05 router outputs + existing CFG/time tags.
% -------------------------------------------------------------------------
injectorInputTags = {
    'AA15_U_COMMIT_PV1_SHADOW'
    'AA15_U_COMMIT_PV2_SHADOW'
    'AA15_U_COMMIT_ESS1_SHADOW'
    'AA15_U_COMMIT_ESS2_SHADOW'
    'AA15_U_COMMIT_EV1_SHADOW'
    'AA15_U_COMMIT_EV2_SHADOW'
    'AA15_AGC_IN_01_T'
    'CFG15_EXEC_FAULT_ENABLE'
    'CFG15_EXEC_FAULT_DEVICE'
    'CFG15_EXEC_FAULT_GAIN'
    'CFG15_EXEC_FAULT_START_S'
    'CFG15_EXEC_FAULT_END_S'
};

for i = 1:12
    fromName = sprintf('FROM_FAULT_SRC_%02d',i);
    p = [stack '/' fromName];

    localDeleteBlockIfExists(p);

    col = floor((i-1)/6);
    row = mod(i-1,6);

    x = 2890 + col*165;
    y = 430 + row*34;

    add_block('simulink/Signal Routing/From',p, ...
        'GotoTag',injectorInputTags{i}, ...
        'Position',[x y x+150 y+20]);

    localEnsureLine(stack, ...
        [fromName '/1'], ...
        sprintf('AA15_Execution_Fault_Injector/%d',i));
end

% -------------------------------------------------------------------------
% Publish u_applied and fault state globally.
% -------------------------------------------------------------------------
outTags = {
    'AA15_U_APPLIED_PV1_SHADOW'
    'AA15_U_APPLIED_PV2_SHADOW'
    'AA15_U_APPLIED_ESS1_SHADOW'
    'AA15_U_APPLIED_ESS2_SHADOW'
    'AA15_U_APPLIED_EV1_SHADOW'
    'AA15_U_APPLIED_EV2_SHADOW'
    'AA15_EXEC_FAULT_ACTIVE'
    'AA15_EXEC_FAULT_DEVICE_ACTIVE'
    'AA15_EXEC_FAULT_GAIN_ACTIVE'
    'AA15_COMMIT_APPLIED_MAX_DELTA'
};

for i = 1:10
    gotoName = sprintf('GOTO_UAPPLIED_OUT_%02d',i);
    p = [stack '/' gotoName];

    localDeleteBlockIfExists(p);

    y = 70 + (i-1)*38;

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',outTags{i}, ...
        'TagVisibility','global', ...
        'Position',[3690 y 3940 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Execution_Fault_Injector/%d',i), ...
        [gotoName '/1']);
end

% -------------------------------------------------------------------------
% Stage06 diagnostics: only new information, 10 signals.
% Existing S05 already logs u_commit, so do not duplicate it here.
% -------------------------------------------------------------------------
fprintf('\n--- Build Stage06 diagnostics ---\n');

if getSimulinkBlockHandle(s06Diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,400,240,420);
    add_block('simulink/Ports & Subsystems/Subsystem',s06Diag, ...
        'Position',[dx dy dx+400 dy+240]);
    fprintf('[CREATE] %s\n',s06Diag);
else
    if ~strcmp(get_param(s06Diag,'BlockType'),'SubSystem')
        error('S06:DiagConflict','%s exists but is not a SubSystem.',s06Diag);
    end
    fprintf('[REBUILD] %s\n',s06Diag);
end

localDeleteSubsystemContents(s06Diag);

try
    set_param(s06Diag,'AttributesFormatString', ...
        sprintf('S06 diagnostics only\\n10 signals\\nGroup28'));
catch
end

for i = 1:10
    col = floor((i-1)/5);
    row = mod(i-1,5);

    x = 25 + col*235;
    y = 30 + row*55;

    fromName = sprintf('FROM_DIAG_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [s06Diag '/' fromName], ...
        'GotoTag',outTags{i}, ...
        'Position',[x y x+205 y+22]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s06Diag '/AA15_STAGE06_DIAG10'], ...
    'Inputs','10', ...
    'Position',[535 50 570 350]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s06Diag '/diag10'], ...
    'Port','1', ...
    'Position',[630 190 660 206]);

for i = 1:10
    localEnsureLine(s06Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE06_DIAG10/%d',i));
end

localEnsureLine(s06Diag,'AA15_STAGE06_DIAG10/1','diag10/1');

set_param(mdl,'SimulationCommand','update');

s06PH = get_param(s06Diag,'PortHandles');
if numel(s06PH.Outport) ~= 1
    error('S06:DiagPort','Stage06 diagnostics expected one output.');
end

% Append as Group28 physical input4.
currentPort = localFindExistingLogPort(s06Diag,group28Mux);

if currentPort > 0
    if currentPort ~= 4
        error('S06:Group28Port', ...
            'Stage06 diagnostics found on unexpected Group28 input %d.', ...
            currentPort);
    end

    fprintf('[KEEP] Stage06 diag10 already on Group28 input4.\n');
else
    n28 = str2double(get_param(group28Mux,'Inputs'));

    if n28 == 3
        set_param(group28Mux,'Inputs','4');
    elseif n28 ~= 4
        error('S06:Group28InputCount', ...
            'Unexpected Group28 input count: %d.',n28);
    end

    muxPH = get_param(group28Mux,'PortHandles');

    localEnsureTopLevelConnection(sm, ...
        s06PH.Outport(1), ...
        muxPH.Inport(4), ...
        'Stage06 diag10 -> Group28 input4');

    fprintf('[APPEND] Stage06 diag10 -> Group28 input4.\n');
end

% -------------------------------------------------------------------------
% Final assertions.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / safety assertions ---\n');

set_param(mdl,'SimulationCommand','update');

n28 = str2double(get_param(group28Mux,'Inputs'));
if n28 ~= 4
    error('S06:Group28Final','Group28 Mux expected 4 inputs, found %d.',n28);
end

if localFindExistingLogPort(s03Diag,group28Mux) ~= 1
    error('S06:Group28S03','S03 diagnostics not on Group28 input1.');
end

if localFindExistingLogPort(s04Diag,group28Mux) ~= 2
    error('S06:Group28S04','S04 diagnostics not on Group28 input2.');
end

if localFindExistingLogPort(s05Diag,group28Mux) ~= 3
    error('S06:Group28S05','S05 diagnostics not on Group28 input3.');
end

if localFindExistingLogPort(s06Diag,group28Mux) ~= 4
    error('S06:Group28S06','S06 diagnostics not on Group28 input4.');
end

for i = 1:numel(outTags)
    g = localFindGotoByTag(mdl,outTags{i});
    if numel(g) ~= 1
        error('S06:TagCount', ...
            'Expected one Goto for %s, found %d.',outTags{i},numel(g));
    end
end

% V5-A device routes must still exist.
devices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};

for i = 1:numel(devices)
    tag = ['V5A_FINAL_' devices{i}];

    if isempty(localFindFromByTag(mdl,tag))
        error('S06:V5ARouteLost','Missing V5-A From tag %s.',tag);
    end
end

% -------------------------------------------------------------------------
% Export map.
% -------------------------------------------------------------------------
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE06_EXECFAULT_MAP_%s.txt',modelBase,stamp));

fid = fopen(mapFile,'w');

if fid >= 0
    fprintf(fid,'LOCAL15 Stage06 - Execution Fault + u_applied SHADOW\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'Execution chain:\n');
    fprintf(fid,'  S05 u_commit SHADOW\n');
    fprintf(fid,'    -> AA15_Execution_Fault_Injector\n');
    fprintf(fid,'    -> S06 u_applied SHADOW\n\n');

    fprintf(fid,'Fault device mapping:\n');
    fprintf(fid,'  1 PV1\n');
    fprintf(fid,'  2 PV2\n');
    fprintf(fid,'  3 ESS1\n');
    fprintf(fid,'  4 ESS2\n');
    fprintf(fid,'  5 EV1\n');
    fprintf(fid,'  6 EV2\n\n');

    fprintf(fid,'Fault model:\n');
    fprintf(fid,'  u_applied = gain*u_commit on selected device\n');
    fprintf(fid,'  gain is clamped to [0,1]\n');
    fprintf(fid,'  active window = [start_s,end_s)\n\n');

    fprintf(fid,'Group28 total signals after S06 = 60\n');
    fprintf(fid,'Expected MAT rows = 61\n\n');

    fprintf(fid,'S06 appended Group28 positions 51..60:\n');
    for i = 1:10
        fprintf(fid,'  %2d %s\n',50+i,outTags{i});
    end

    fprintf(fid,'\nNo device Pref route changed in S06.\n');
    fprintf(fid,'u_applied remains SHADOW-only.\n');

    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 06 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Execution Fault Injector      : created / verified\n');
fprintf('u_commit -> u_applied SHADOW  : established\n');
fprintf('Fault model                   : single-device gain degradation\n');
fprintf('Fault gain                    : safely clamped to [0,1]\n');
fprintf('Group28                       : 60 signals total\n');
fprintf('Expected Group28 MAT rows     : 61\n');
fprintf('V5-A actual device control    : UNCHANGED\n');
fprintf('Mapping TXT                   : %s\n',mapFile);
fprintf('\nNo immediate Build is required solely for S06.\n');
fprintf('Before real LOCAL15 takeover, rerun the S05 CONTROL_SOURCE=1\n');
fprintf('shadow test with MASTER_ENABLE=1, then validate S06 fault logic.\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% MATLAB Function source
% =========================================================================

function scriptText = localFaultInjectorScript()

lines = {};
lines{end+1} = ['function [y1,y2,y3,y4,y5,y6,fault_active,' ...
                'fault_device_active,fault_gain_active,max_delta] = ' ...
                'AA15_Execution_Fault_Injector_Core(' ...
                'u1,u2,u3,u4,u5,u6,t,fault_enable,fault_device,' ...
                'fault_gain,fault_start_s,fault_end_s)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = 'y1=u1; y2=u2; y3=u3; y4=u4; y5=u5; y6=u6;';
lines{end+1} = 'fault_active = 0.0;';
lines{end+1} = 'fault_device_active = 0.0;';
lines{end+1} = 'fault_gain_active = 1.0;';
lines{end+1} = 'max_delta = 0.0;';
lines{end+1} = '';
lines{end+1} = ['cfgFinite = finite_scalar(t) && finite_scalar(fault_device) && ' ...
                'finite_scalar(fault_gain) && finite_scalar(fault_start_s) && ' ...
                'finite_scalar(fault_end_s);'];
lines{end+1} = '';
lines{end+1} = 'if fault_enable <= 0.5 || ~cfgFinite';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if fault_end_s <= fault_start_s';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if t < fault_start_s || t >= fault_end_s';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'dev = round(fault_device);';
lines{end+1} = 'g = min(max(fault_gain,0.0),1.0);';
lines{end+1} = '';
lines{end+1} = 'if dev == 1';
lines{end+1} = '    y1 = g*u1;';
lines{end+1} = 'elseif dev == 2';
lines{end+1} = '    y2 = g*u2;';
lines{end+1} = 'elseif dev == 3';
lines{end+1} = '    y3 = g*u3;';
lines{end+1} = 'elseif dev == 4';
lines{end+1} = '    y4 = g*u4;';
lines{end+1} = 'elseif dev == 5';
lines{end+1} = '    y5 = g*u5;';
lines{end+1} = 'elseif dev == 6';
lines{end+1} = '    y6 = g*u6;';
lines{end+1} = 'else';
lines{end+1} = '    fault_device_active = -1.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'fault_active = 1.0;';
lines{end+1} = 'fault_device_active = double(dev);';
lines{end+1} = 'fault_gain_active = g;';
lines{end+1} = '';
lines{end+1} = ['max_delta = max(max(max(abs(y1-u1),abs(y2-u2)),' ...
                'max(abs(y3-u3),abs(y4-u4))),' ...
                'max(abs(y5-u5),abs(y6-u6)));'];
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = finite_scalar(x)';
lines{end+1} = 'ok = ~(isnan(x) || isinf(x));';
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
    error('S06:EMChartPath', ...
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
        error('S06:UnexpectedTopLine', ...
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
    error('S06:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S06:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S06:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S06:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S06:UnexpectedExistingLine', ...
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

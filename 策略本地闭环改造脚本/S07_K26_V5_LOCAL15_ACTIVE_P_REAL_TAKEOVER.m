function S07_K26_V5_LOCAL15_ACTIVE_P_REAL_TAKEOVER
% S07_K26_V5_LOCAL15_ACTIVE_P_REAL_TAKEOVER
%
% LOCAL15 Stage 07
%
% PURPOSE
% -------
% This is the FIRST stage that changes the six devices' ACTUAL Pref source.
%
% Final active-P path after S07:
%
%   LEGACY_V5A / LOCAL15 / BOARD15-reserved
%           -> S05 Source Router
%           -> u_commit
%           -> S06 Execution Fault Injector
%           -> proposed u_applied
%           -> S07 Final Applied Safety Interface
%           -> AA15_FINAL_APPLIED_*
%           -> six device control Mux physical input 6 (Pref)
%
% The V5-A source is NOT deleted. It remains available to the S05 Router.
%
% CONTROL_SOURCE behavior after S07:
%   0 = LEGACY_V5A
%       Actual device Pref passes through the new unified chain but is
%       numerically the proven V5-A command when fault injection is off.
%
%   1 = LOCAL15
%       Actual device Pref can come from the LOCAL15 chain when valid.
%
%   2 = BOARD15
%       Still reserved in S05 Router; current behavior safely falls back to
%       legacy values with invalid status.
%
% S07 Final Applied Safety Interface
% ----------------------------------
% Inputs:
%   1..6   S06 proposed u_applied
%   7..12  exact LEGACY_V5A Prefs
%
% Outputs:
%   1..6   actual final applied Prefs
%   7      final_safety_fallback_active
%   8      final_applied_valid
%
% Rule:
%   If a proposed u_applied value is finite, pass it.
%   If it is NaN/Inf, fall back to the corresponding LEGACY_V5A value.
%
% This final finite-value guard is intentionally separate from the fault
% injector. A valid finite execution degradation (e.g. gain=0.3) must pass
% through unchanged and therefore becomes a REAL plant input after S07.
%
% Physical device Pref destinations verified/reconnected:
%   PV1  : PV1_IO_Mux12 input 6
%   PV2  : PV2_IO_Mux12 input 6
%   ESS1 : ESS1_IO_Mux12 input 6
%   ESS2 : ESS2_IO_Mux12 input 6
%   EV1  : EV1_IO_Mux input 6
%   EV2  : EV2_IO_Mux input 6
%
% Group-28
% --------
% S06 total = 60 signals.
% S07 appends 8 signals:
%   61 final applied PV1
%   62 final applied PV2
%   63 final applied ESS1
%   64 final applied ESS2
%   65 final applied EV1
%   66 final applied EV2
%   67 final safety fallback active
%   68 final applied valid
%
% Expected Group-28 MAT:
%   69 rows = Target Time + 68 signals.
%
% IMPORTANT
% ---------
% After S07, a strategic Build + runtime validation is MANDATORY before
% proceeding, because the real plant Pref route has changed for the first
% time.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 07 - ACTIVE-P REAL TAKEOVER\n');
fprintf('============================================================\n');
fprintf('WARNING: This stage changes the ACTUAL six-device Pref route.\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S07:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S07:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S07:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE07_REAL_TAKEOVER_%s%s', ...
    modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S07:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% -------------------------------------------------------------------------
% Verify S06 foundation BEFORE touching any physical Pref source.
% -------------------------------------------------------------------------
fprintf('\n--- Verify S06 foundation ---\n');

stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
injector = [stack '/AA15_Execution_Fault_Injector'];
router = [stack '/AA15_Command_Source_Router'];

group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];
s05Diag = [sm '/AA15_STAGE05_ROUTER_DIAGNOSTICS'];
s06Diag = [sm '/AA15_STAGE06_EXECFAULT_DIAGNOSTICS'];

requiredBlocks = {
    stack
    router
    injector
    group28Mux
    op28
    s03Diag
    s04Diag
    s05Diag
    s06Diag
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S07:MissingPrerequisite', ...
            'Missing S06 prerequisite: %s',requiredBlocks{i});
    end
    fprintf('[OK] %s\n',requiredBlocks{i});
end

uAppliedTags = {
    'AA15_U_APPLIED_PV1_SHADOW'
    'AA15_U_APPLIED_PV2_SHADOW'
    'AA15_U_APPLIED_ESS1_SHADOW'
    'AA15_U_APPLIED_ESS2_SHADOW'
    'AA15_U_APPLIED_EV1_SHADOW'
    'AA15_U_APPLIED_EV2_SHADOW'
};

legacyTags = {
    'AA15_LEGACY_PV1_PREF'
    'AA15_LEGACY_PV2_PREF'
    'AA15_LEGACY_ESS1_PREF'
    'AA15_LEGACY_ESS2_PREF'
    'AA15_LEGACY_EV1_PREF'
    'AA15_LEGACY_EV2_PREF'
};

for i = 1:6
    if isempty(localFindGotoByTag(mdl,uAppliedTags{i}))
        error('S07:MissingUApplied','Missing tag: %s',uAppliedTags{i});
    end

    if isempty(localFindGotoByTag(mdl,legacyTags{i}))
        error('S07:MissingLegacy','Missing tag: %s',legacyTags{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if isnan(n28)
    error('S07:Group28Inputs','Cannot parse Group28 Mux Inputs.');
end

s07Diag = [sm '/AA15_STAGE07_TAKEOVER_DIAGNOSTICS'];
existingS07Port = localFindExistingLogPort(s07Diag,group28Mux);

if n28 > 5
    error('S07:LaterStageDetected', ...
        ['Group28 already has %d physical inputs. Later-stage diagnostics ' ...
         'appear to exist. Do not rerun S07.'],n28);
end

if n28 == 5 && existingS07Port == 0
    error('S07:UnexpectedGroup28Input', ...
        'Group28 has 5 inputs but Stage07 diagnostics are not input5.');
end

fprintf('[OK] S06 foundation verified.\n');

% -------------------------------------------------------------------------
% Verify all six ACTUAL Pref destinations before modifying anything.
% We only permit the known V5-A source or an already-completed S07 source.
% -------------------------------------------------------------------------
fprintf('\n--- Preflight actual six-device Pref destinations ---\n');

deviceNames = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};

muxNames = {
    'PV1_IO_Mux12'
    'PV2_IO_Mux12'
    'ESS1_IO_Mux12'
    'ESS2_IO_Mux12'
    'EV1_IO_Mux'
    'EV2_IO_Mux'
};

oldV5Tags = {
    'V5A_FINAL_PV1'
    'V5A_FINAL_PV2'
    'V5A_FINAL_ESS1'
    'V5A_FINAL_ESS2'
    'V5A_FINAL_EV1'
    'V5A_FINAL_EV2'
};

finalTags = {
    'AA15_FINAL_APPLIED_PV1'
    'AA15_FINAL_APPLIED_PV2'
    'AA15_FINAL_APPLIED_ESS1'
    'AA15_FINAL_APPLIED_ESS2'
    'AA15_FINAL_APPLIED_EV1'
    'AA15_FINAL_APPLIED_EV2'
};

prefSourceBlocks = cell(6,1);

for i = 1:6
    muxPath = [sm '/' muxNames{i}];

    if getSimulinkBlockHandle(muxPath) < 0
        error('S07:MissingMux','Missing verified device Mux: %s',muxPath);
    end

    if ~strcmp(get_param(muxPath,'BlockType'),'Mux')
        error('S07:MuxType','Expected Mux at %s.',muxPath);
    end

    ph = get_param(muxPath,'PortHandles');

    if numel(ph.Inport) < 6
        error('S07:MuxPorts','%s has fewer than 6 physical inputs.',muxPath);
    end

    ln = get_param(ph.Inport(6),'Line');

    if isequal(ln,-1)
        error('S07:PrefUnconnected', ...
            '%s physical input 6 (Pref) is unconnected.',muxPath);
    end

    srcBlockH = get_param(ln,'SrcBlockHandle');

    if isempty(srcBlockH) || srcBlockH < 0
        error('S07:PrefSource','Cannot resolve Pref source for %s.',muxPath);
    end

    srcPath = getfullname(srcBlockH);

    if ~strcmp(get_param(srcPath,'BlockType'),'From')
        error('S07:PrefSourceType', ...
            ['Expected the current Pref source of %s to be a From block. ' ...
             'Found %s at %s.'], ...
            muxPath,get_param(srcPath,'BlockType'),srcPath);
    end

    tag = get_param(srcPath,'GotoTag');

    if ~(strcmp(tag,oldV5Tags{i}) || strcmp(tag,finalTags{i}))
        error('S07:UnexpectedPrefTag', ...
            ['%s input6 is driven by From tag "%s". Expected "%s" ' ...
             'or already-completed "%s". Refusing takeover.'], ...
             muxPath,tag,oldV5Tags{i},finalTags{i});
    end

    % The specific device-Pref From must not fan out to other destinations.
    dst = get_param(ln,'DstPortHandle');
    dst = dst(dst >= 0);

    if numel(dst) ~= 1
        error('S07:PrefBranch', ...
            ['Pref source %s has %d destinations. Refusing automatic tag ' ...
             'replacement because this specific From is not device-local.'], ...
             srcPath,numel(dst));
    end

    prefSourceBlocks{i} = srcPath;

    fprintf('[OK] %-4s Pref = %s -> %s input6\n', ...
        deviceNames{i},tag,muxNames{i});
end

fprintf('[OK] All six physical Pref routes passed preflight.\n');

% -------------------------------------------------------------------------
% Build/rebuild final applied safety interface in LOCAL control stack.
% -------------------------------------------------------------------------
fprintf('\n--- Build AA15_Active_P_Takeover ---\n');

takeover = [stack '/AA15_Active_P_Takeover'];

if getSimulinkBlockHandle(takeover) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',takeover, ...
        'Position',[4010 55 4430 415]);
    fprintf('[CREATE] %s\n',takeover);
else
    if ~strcmp(get_param(takeover,'BlockType'),'SubSystem')
        error('S07:TakeoverConflict','%s exists but is not a SubSystem.',takeover);
    end
    fprintf('[REBUILD] %s\n',takeover);
end

localDeleteSubsystemContents(takeover);

try
    set_param(takeover,'AttributesFormatString', ...
        sprintf(['S07 REAL active-P interface\\n' ...
                 'u_applied -> device Pref\\n' ...
                 'finite-value legacy fallback']));
catch
end

takeInNames = {
    'proposed_pv1'
    'proposed_pv2'
    'proposed_ess1'
    'proposed_ess2'
    'proposed_ev1'
    'proposed_ev2'
    'legacy_pv1'
    'legacy_pv2'
    'legacy_ess1'
    'legacy_ess2'
    'legacy_ev1'
    'legacy_ev2'
};

for i = 1:12
    col = floor((i-1)/6);
    row = mod(i-1,6);

    x = 20 + col*175;
    y = 30 + row*50;

    add_block('simulink/Ports & Subsystems/In1', ...
        [takeover '/' takeInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[x y x+30 y+16]);
end

core = [takeover '/AA15_Final_Applied_Safety_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',core, ...
    'Position',[430 75 820 500]);

chart = localGetEMChartByPath(core);
chart.Script = localFinalAppliedScript();

takeOutNames = {
    'final_pv1'
    'final_pv2'
    'final_ess1'
    'final_ess2'
    'final_ev1'
    'final_ev2'
    'safety_fallback_active'
    'final_applied_valid'
};

for i = 1:8
    y = 50 + (i-1)*48;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [takeover '/' takeOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[920 y 950 y+16]);
end

set_param(mdl,'SimulationCommand','update');

corePorts = get_param(core,'Ports');

if corePorts(1) ~= 12 || corePorts(2) ~= 8
    error('S07:TakeoverPorts', ...
        'Final Applied Safety Core expected 12-in/8-out, found %d/%d.', ...
        corePorts(1),corePorts(2));
end

for i = 1:12
    localEnsureLine(takeover, ...
        [takeInNames{i} '/1'], ...
        sprintf('AA15_Final_Applied_Safety_Core/%d',i));
end

for i = 1:8
    localEnsureLine(takeover, ...
        sprintf('AA15_Final_Applied_Safety_Core/%d',i), ...
        [takeOutNames{i} '/1']);
end

fprintf('[OK] Final Applied Safety Core = 12 inputs / 8 outputs.\n');

% -------------------------------------------------------------------------
% Feed takeover from global S06 u_applied + exact legacy values.
% -------------------------------------------------------------------------
takeInputTags = [uAppliedTags; legacyTags];

for i = 1:12
    fromName = sprintf('FROM_TAKEOVER_SRC_%02d',i);
    p = [stack '/' fromName];

    localDeleteBlockIfExists(p);

    col = floor((i-1)/6);
    row = mod(i-1,6);

    x = 3660 + col*175;
    y = 440 + row*34;

    add_block('simulink/Signal Routing/From',p, ...
        'GotoTag',takeInputTags{i}, ...
        'Position',[x y x+160 y+20]);

    localEnsureLine(stack, ...
        [fromName '/1'], ...
        sprintf('AA15_Active_P_Takeover/%d',i));
end

finalOutputTags = [
    finalTags
    {
    'AA15_FINAL_SAFETY_FALLBACK'
    'AA15_FINAL_APPLIED_VALID'
    }
];

for i = 1:8
    gotoName = sprintf('GOTO_FINAL_APPLIED_%02d',i);
    p = [stack '/' gotoName];

    localDeleteBlockIfExists(p);

    y = 70 + (i-1)*42;

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',finalOutputTags{i}, ...
        'TagVisibility','global', ...
        'Position',[4490 y 4735 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Active_P_Takeover/%d',i), ...
        [gotoName '/1']);
end

% Update before physical route change so all final tags are resolvable.
set_param(mdl,'SimulationCommand','update');

% -------------------------------------------------------------------------
% REAL TAKEOVER:
% Retag ONLY the already-verified device-local Pref From blocks.
% The existing line and Mux destination are preserved.
% -------------------------------------------------------------------------
fprintf('\n--- REAL TAKEOVER: retag six device Pref From blocks ---\n');

for i = 1:6
    currentTag = get_param(prefSourceBlocks{i},'GotoTag');

    if strcmp(currentTag,oldV5Tags{i})
        set_param(prefSourceBlocks{i},'GotoTag',finalTags{i});

        fprintf('[TAKEOVER] %-4s : %s -> %s\n', ...
            deviceNames{i},oldV5Tags{i},finalTags{i});
    elseif strcmp(currentTag,finalTags{i})
        fprintf('[KEEP]     %-4s already uses %s\n', ...
            deviceNames{i},finalTags{i});
    else
        error('S07:RetagRace', ...
            'Unexpected tag changed before takeover: %s',currentTag);
    end
end

% -------------------------------------------------------------------------
% Stage07 diagnostics -> Group28 input5.
% -------------------------------------------------------------------------
fprintf('\n--- Build Stage07 diagnostics ---\n');

if getSimulinkBlockHandle(s07Diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,390,230,420);

    add_block('simulink/Ports & Subsystems/Subsystem',s07Diag, ...
        'Position',[dx dy dx+390 dy+230]);

    fprintf('[CREATE] %s\n',s07Diag);
else
    if ~strcmp(get_param(s07Diag,'BlockType'),'SubSystem')
        error('S07:DiagConflict','%s exists but is not a SubSystem.',s07Diag);
    end
    fprintf('[REBUILD] %s\n',s07Diag);
end

localDeleteSubsystemContents(s07Diag);

try
    set_param(s07Diag,'AttributesFormatString', ...
        sprintf('S07 REAL takeover diagnostics\\n8 signals\\nGroup28'));
catch
end

for i = 1:8
    col = floor((i-1)/4);
    row = mod(i-1,4);

    x = 25 + col*230;
    y = 30 + row*62;

    fromName = sprintf('FROM_DIAG_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [s07Diag '/' fromName], ...
        'GotoTag',finalOutputTags{i}, ...
        'Position',[x y x+205 y+22]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s07Diag '/AA15_STAGE07_DIAG8'], ...
    'Inputs','8', ...
    'Position',[520 50 555 315]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s07Diag '/diag8'], ...
    'Port','1', ...
    'Position',[615 175 645 191]);

for i = 1:8
    localEnsureLine(s07Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE07_DIAG8/%d',i));
end

localEnsureLine(s07Diag,'AA15_STAGE07_DIAG8/1','diag8/1');

set_param(mdl,'SimulationCommand','update');

s07PH = get_param(s07Diag,'PortHandles');

if numel(s07PH.Outport) ~= 1
    error('S07:DiagPort','Stage07 diagnostics expected one output.');
end

currentPort = localFindExistingLogPort(s07Diag,group28Mux);

if currentPort > 0
    if currentPort ~= 5
        error('S07:Group28Port', ...
            'Stage07 diagnostics found on unexpected Group28 input %d.', ...
            currentPort);
    end
    fprintf('[KEEP] Stage07 diag8 already on Group28 input5.\n');
else
    n28 = str2double(get_param(group28Mux,'Inputs'));

    if n28 == 4
        set_param(group28Mux,'Inputs','5');
    elseif n28 ~= 5
        error('S07:Group28InputCount', ...
            'Unexpected Group28 input count: %d.',n28);
    end

    muxPH = get_param(group28Mux,'PortHandles');

    localEnsureTopLevelConnection(sm, ...
        s07PH.Outport(1), ...
        muxPH.Inport(5), ...
        'Stage07 diag8 -> Group28 input5');

    fprintf('[APPEND] Stage07 diag8 -> Group28 input5.\n');
end

% -------------------------------------------------------------------------
% Final assertions after REAL route change.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / REAL route assertions ---\n');

set_param(mdl,'SimulationCommand','update');

n28 = str2double(get_param(group28Mux,'Inputs'));
if n28 ~= 5
    error('S07:Group28Final','Group28 Mux expected 5 inputs, found %d.',n28);
end

if localFindExistingLogPort(s03Diag,group28Mux) ~= 1
    error('S07:Group28S03','S03 diagnostics not on Group28 input1.');
end
if localFindExistingLogPort(s04Diag,group28Mux) ~= 2
    error('S07:Group28S04','S04 diagnostics not on Group28 input2.');
end
if localFindExistingLogPort(s05Diag,group28Mux) ~= 3
    error('S07:Group28S05','S05 diagnostics not on Group28 input3.');
end
if localFindExistingLogPort(s06Diag,group28Mux) ~= 4
    error('S07:Group28S06','S06 diagnostics not on Group28 input4.');
end
if localFindExistingLogPort(s07Diag,group28Mux) ~= 5
    error('S07:Group28S07','S07 diagnostics not on Group28 input5.');
end

% Assert every physical device Mux input6 now resolves from the FINAL tag.
for i = 1:6
    muxPath = [sm '/' muxNames{i}];
    ph = get_param(muxPath,'PortHandles');
    ln = get_param(ph.Inport(6),'Line');

    if isequal(ln,-1)
        error('S07:FinalPrefLost','%s Pref became unconnected.',muxPath);
    end

    srcH = get_param(ln,'SrcBlockHandle');
    srcPath = getfullname(srcH);

    if ~strcmp(get_param(srcPath,'BlockType'),'From')
        error('S07:FinalPrefSource','%s Pref source is no longer a From.',muxPath);
    end

    actualTag = get_param(srcPath,'GotoTag');

    if ~strcmp(actualTag,finalTags{i})
        error('S07:FinalPrefTag', ...
            '%s input6 expected %s, found %s.', ...
            muxPath,finalTags{i},actualTag);
    end

    fprintf('[ASSERT] %-4s actual Pref <- %s\n', ...
        deviceNames{i},actualTag);
end

% Legacy V5-A tags must still be available to the Router.
for i = 1:6
    if isempty(localFindGotoByTag(mdl,oldV5Tags{i}))
        error('S07:LegacyGotoLost','Legacy V5-A Goto lost: %s',oldV5Tags{i});
    end

    if isempty(localFindFromByTag(mdl,oldV5Tags{i}))
        error('S07:LegacyRouterReadLost', ...
            ['No remaining From reads legacy tag %s. ' ...
             'The Source Router would lose the regression source.'], ...
             oldV5Tags{i});
    end
end

for i = 1:8
    g = localFindGotoByTag(mdl,finalOutputTags{i});
    if numel(g) ~= 1
        error('S07:FinalTagCount', ...
            'Expected one Goto for %s, found %d.', ...
            finalOutputTags{i},numel(g));
    end
end

% -------------------------------------------------------------------------
% Export map.
% -------------------------------------------------------------------------
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE07_REAL_TAKEOVER_MAP_%s.txt', ...
    modelBase,stamp));

fid = fopen(mapFile,'w');

if fid >= 0
    fprintf(fid,'LOCAL15 Stage07 - ACTIVE-P REAL TAKEOVER\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'Actual device Pref route after S07:\n');
    for i = 1:6
        fprintf(fid,'  %-4s %s input6 <- %s\n', ...
            deviceNames{i},muxNames{i},finalTags{i});
    end

    fprintf(fid,'\nUnified path:\n');
    fprintf(fid,'  Source Router -> u_commit -> Fault Injector -> proposed u_applied\n');
    fprintf(fid,'  -> Final Applied Safety -> device Pref\n\n');

    fprintf(fid,'CONTROL_SOURCE:\n');
    fprintf(fid,'  0 LEGACY_V5A through unified path\n');
    fprintf(fid,'  1 LOCAL15 through unified path when valid\n');
    fprintf(fid,'  2 BOARD15 reserved; current router fallback remains legacy\n\n');

    fprintf(fid,'Group28 total signals after S07 = 68\n');
    fprintf(fid,'Expected MAT rows = 69\n\n');

    fprintf(fid,'S07 appended Group28 positions 61..68:\n');
    for i = 1:8
        fprintf(fid,'  %2d %s\n',60+i,finalOutputTags{i});
    end

    fprintf(fid,'\nThis is the first stage that changes actual six-device Pref routing.\n');

    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 07 COMPLETE - REAL ACTIVE-P TAKEOVER ESTABLISHED\n');
fprintf('============================================================\n');
fprintf('Final Applied Safety Interface : created / verified\n');
fprintf('Six actual Pref routes          : changed to AA15_FINAL_APPLIED_*\n');
fprintf('LEGACY_V5A source               : preserved inside Source Router\n');
fprintf('LOCAL15 actual takeover         : now possible with CONTROL_SOURCE=1\n');
fprintf('Execution fault actual effect   : now possible when enabled\n');
fprintf('BOARD15                         : still reserved / legacy fallback\n');
fprintf('Group28                         : 68 signals total\n');
fprintf('Expected Group28 MAT rows       : 69\n');
fprintf('Mapping TXT                     : %s\n',mapFile);
fprintf('\nMANDATORY NEXT STEP = BUILD + RUNTIME VALIDATION.\n');
fprintf('Do NOT proceed to S08 before validating CONTROL_SOURCE=0 first.\n');
fprintf('Reason: S07 is the first stage that changed the real plant Pref path.\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% MATLAB Function source
% =========================================================================

function scriptText = localFinalAppliedScript()

lines = {};
lines{end+1} = ['function [y1,y2,y3,y4,y5,y6,' ...
                'fallback_active,final_valid] = ' ...
                'AA15_Final_Applied_Safety_Core(' ...
                'p1,p2,p3,p4,p5,p6,l1,l2,l3,l4,l5,l6)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = '[y1,f1] = pick_finite(p1,l1);';
lines{end+1} = '[y2,f2] = pick_finite(p2,l2);';
lines{end+1} = '[y3,f3] = pick_finite(p3,l3);';
lines{end+1} = '[y4,f4] = pick_finite(p4,l4);';
lines{end+1} = '[y5,f5] = pick_finite(p5,l5);';
lines{end+1} = '[y6,f6] = pick_finite(p6,l6);';
lines{end+1} = '';
lines{end+1} = 'fallback_active = double(f1||f2||f3||f4||f5||f6);';
lines{end+1} = ['final_valid = double(isfinite_scalar(y1) && isfinite_scalar(y2) && ' ...
                'isfinite_scalar(y3) && isfinite_scalar(y4) && ' ...
                'isfinite_scalar(y5) && isfinite_scalar(y6));'];
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function [y,usedFallback] = pick_finite(proposed,legacy)';
lines{end+1} = 'if isfinite_scalar(proposed)';
lines{end+1} = '    y = proposed;';
lines{end+1} = '    usedFallback = false;';
lines{end+1} = 'else';
lines{end+1} = '    y = legacy;';
lines{end+1} = '    usedFallback = true;';
lines{end+1} = 'end';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = isfinite_scalar(x)';
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
    error('S07:EMChartPath', ...
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
        error('S07:UnexpectedTopLine', ...
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
    error('S07:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S07:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S07:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S07:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S07:UnexpectedExistingLine', ...
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

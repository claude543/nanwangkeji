function S09_K26_V5_LOCAL15_S3_AVC_QREF_REAL_TAKEOVER
% S09_K26_V5_LOCAL15_S3_AVC_QREF_REAL_TAKEOVER
%
% LOCAL15 Stage 09
%
% Purpose:
%   1) Keep the existing teacher-tested Strategy 3 (AVC) algorithm unchanged.
%   2) Extract status/alarm/metric/cmd(3) from the existing 15-strategy bus.
%   3) Convert cmd(3) [kvar-like engineering unit used by current strategy]
%      into a total per-unit Q request using the proven P-unit base.
%   4) Allocate total Q across six converters by remaining apparent-power
%      capability:
%
%          Qcap_i = sqrt(max(1 - Pref_i^2, 0))
%
%          Qref_i = Qrequest * Qcap_i / sum(Qcap_i)
%
%   5) Gate real Q takeover with:
%          CFG15_MASTER_ENABLE
%          CFG15_EXEC_S03
%          CFG15_CONTROL_SOURCE == 1
%
%   6) Preserve exact legacy Qref=0 whenever S3 is not executing.
%   7) Add one tunable sign calibration parameter:
%          CFG15_Q_SIGN_GAIN = +1 or -1
%
%      This exists because the current project plan explicitly requires the
%      real K26 Qref/Qmeas voltage-direction sign to be calibrated from the
%      plant instead of guessed from memory.
%
%   8) Retarget ONLY physical Mux input 7 (Qref) for the six devices.
%      Existing Pref input 6 and all S07/S08 active-P paths are protected.
%
% Group28:
%   S08 total = 92 signals.
%   S09 appends 21 signals.
%   Final = 113 signals.
%   Expected aa15_strategy_data MAT = 114 rows including Target Time.
%
% IMPORTANT SCRIPT-SAFETY RULES IMPLEMENTED HERE:
%   - mdl = bdroot(gcs)
%   - backup first
%   - verify S08 foundation before destructive edits
%   - cleanup/rebuild is repair-safe after a failed prior S09 run
%   - no model update while Stage09 is half-built
%   - new Subsystems are always fully cleared before construction
%   - vector signals use explicit Demux15, not MATLAB Function inference
%   - Stage09-owned Goto destinations use repair-safe forced connections
%   - physical Qref paths are changed only after exact source verification
%   - post-assert all six Mux input 6 Pref paths remain unchanged
%
% Scope boundary:
%   This script adds execution infrastructure only for the EXISTING S3 AVC.
%   It does not add a new strategy or modify Advanced_Microgrid_15_Strategies.

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 09 - S3 AVC Qref Real Takeover\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S09:NoActiveModel', ...
        'No active model. Open K26_V5 and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
panel = [sm '/AA15_CFG15_PANEL'];

if getSimulinkBlockHandle(sm) < 0
    error('S09:MissingSM','Missing SM_Master.');
end
if getSimulinkBlockHandle(stack) < 0
    error('S09:MissingStack','Missing AA15_LOCAL_CONTROL_STACK.');
end
if getSimulinkBlockHandle(panel) < 0
    error('S09:MissingPanel','Missing AA15_CFG15_PANEL.');
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S09:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE09_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S09:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify frozen S08 foundation.
% =========================================================================
fprintf('\n--- Verify S08 foundation ---\n');

group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];
s05Diag = [sm '/AA15_STAGE05_ROUTER_DIAGNOSTICS'];
s06Diag = [sm '/AA15_STAGE06_EXECFAULT_DIAGNOSTICS'];
s07Diag = [sm '/AA15_STAGE07_TAKEOVER_DIAGNOSTICS'];
s08Diag = [sm '/AA15_STAGE08_P_DIAGNOSTICS'];

requiredBlocks = {
    group28Mux
    op28
    s03Diag
    s04Diag
    s05Diag
    s06Diag
    s07Diag
    s08Diag
    [stack '/AA15_Request_Normalizer']
    [stack '/AA15_P_Objective_Arbiter']
    [stack '/AA15_Arbitrated_Baseline_AGC']
    [stack '/AA15_Execution_Mapper']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Execution_Fault_Injector']
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Request_Normalizer_P_Extension']
    [stack '/AA15_P_Objective_Constraint_Manager']
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S09:MissingPrerequisite', ...
            'Missing S08 prerequisite: %s',requiredBlocks{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if n28 ~= 6 && n28 ~= 7
    error('S09:Group28Unexpected', ...
        'Expected Group28 physical Inputs=6 (S08) or 7 (partial S09), found %g.',n28);
end

expectedPorts = [1 2 3 4 5 6];
diagBlocks = {s03Diag,s04Diag,s05Diag,s06Diag,s07Diag,s08Diag};

for i = 1:numel(diagBlocks)
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= expectedPorts(i)
        error('S09:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},expectedPorts(i),p);
    end
end

% S08 real active-P route must still be in force.
arbAGCIn16 = [stack '/AA15_Arbitrated_Baseline_AGC/FROM_AGC_IN_16'];
execValidFrom = [stack '/FROM_EXEC_SRC_08'];

if ~strcmp(get_param(arbAGCIn16,'GotoTag'),'AA15_P_DPREQ_EFFECTIVE')
    error('S09:S08DPRoute', ...
        'S08 AGC input16 is no longer AA15_P_DPREQ_EFFECTIVE.');
end

if ~strcmp(get_param(execValidFrom,'GotoTag'),'AA15_P_REQUEST_VALID_EFFECTIVE')
    error('S09:S08ValidRoute', ...
        'S08 Execution Mapper valid route is unexpected.');
end

fprintf('[OK] S08 active-P foundation and Group28 inputs1..6 verified.\n');

% =========================================================================
% 2. Discover and preflight the six REAL device control Mux blocks.
%    We protect Pref input6 and only permit Qref input7 edits.
% =========================================================================
fprintf('\n--- Preflight six device Qref paths ---\n');

devNames = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
muxNames = {'PV1_IO_Mux12','PV2_IO_Mux12', ...
            'ESS1_IO_Mux12','ESS2_IO_Mux12', ...
            'EV1_IO_Mux','EV2_IO_Mux'};

finalPrefTags = {
    'AA15_FINAL_APPLIED_PV1'
    'AA15_FINAL_APPLIED_PV2'
    'AA15_FINAL_APPLIED_ESS1'
    'AA15_FINAL_APPLIED_ESS2'
    'AA15_FINAL_APPLIED_EV1'
    'AA15_FINAL_APPLIED_EV2'
};

finalQTags = {
    'AA15_FINAL_QREF_PV1'
    'AA15_FINAL_QREF_PV2'
    'AA15_FINAL_QREF_ESS1'
    'AA15_FINAL_QREF_ESS2'
    'AA15_FINAL_QREF_EV1'
    'AA15_FINAL_QREF_EV2'
};

qLocalFromNames = {
    'AA15_S09_FINAL_QREF_PV1_TO_MUX'
    'AA15_S09_FINAL_QREF_PV2_TO_MUX'
    'AA15_S09_FINAL_QREF_ESS1_TO_MUX'
    'AA15_S09_FINAL_QREF_ESS2_TO_MUX'
    'AA15_S09_FINAL_QREF_EV1_TO_MUX'
    'AA15_S09_FINAL_QREF_EV2_TO_MUX'
};

muxPaths = cell(6,1);
prefInput6SrcPaths = cell(6,1);
qInput7OriginalSrcPaths = cell(6,1);
qInput7State = cell(6,1);

for i = 1:6
    muxPaths{i} = localFindUniqueNamedBlock(mdl,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 7
        error('S09:MuxPorts', ...
            '%s has only %d physical input ports; expected at least 7.', ...
            muxPaths{i},numel(ph.Inport));
    end

    % Protect Pref physical input6.
    [prefSrcPath,prefSrcPort] = localGetDestinationSource(ph.Inport(6)); %#ok<ASGLU>
    prefInput6SrcPaths{i} = prefSrcPath;

    if ~strcmp(get_param(prefSrcPath,'BlockType'),'From')
        error('S09:PrefSourceType', ...
            '%s input6 is not driven by a From block.',muxPaths{i});
    end

    prefTag = get_param(prefSrcPath,'GotoTag');
    if ~strcmp(prefTag,finalPrefTags{i})
        error('S09:PrefSourceTag', ...
            '%s input6 tag=%s, expected %s.', ...
            muxPaths{i},prefTag,finalPrefTags{i});
    end

    % Qref physical input7 may be:
    %   A) untouched legacy Constant=0; or
    %   B) an already-applied Stage09 From with the exact expected tag.
    [qSrcPath,qSrcPort] = localGetDestinationSource(ph.Inport(7)); %#ok<ASGLU>
    qInput7OriginalSrcPaths{i} = qSrcPath;
    qType = get_param(qSrcPath,'BlockType');

    if strcmp(qType,'Constant')
        qVal = localResolveScalarConstant(qSrcPath);
        if ~isfinite(qVal) || abs(qVal) > 1e-12
            error('S09:LegacyQNotZero', ...
                '%s input7 legacy source %s is not scalar zero.', ...
                muxPaths{i},qSrcPath);
        end
        qInput7State{i} = 'LEGACY_ZERO';
        fprintf('[OK] %-4s Qref input7 <- legacy Constant 0 (%s)\n', ...
            devNames{i},qSrcPath);

    elseif strcmp(qType,'From')
        qTag = get_param(qSrcPath,'GotoTag');
        if ~strcmp(qTag,finalQTags{i})
            error('S09:UnexpectedQFrom', ...
                '%s input7 From tag=%s, expected %s.', ...
                muxPaths{i},qTag,finalQTags{i});
        end
        qInput7State{i} = 'S09_ALREADY';
        fprintf('[KEEP] %-4s Qref input7 already <- %s\n', ...
            devNames{i},finalQTags{i});

    else
        error('S09:UnexpectedQSource', ...
            '%s input7 source %s has BlockType=%s. No edit performed.', ...
            muxPaths{i},qSrcPath,qType);
    end
end

fprintf('[OK] All six Pref input6 paths protected and all Qref input7 sources verified.\n');

% =========================================================================
% 3. Clean only Stage09 diagnostic leftovers BEFORE any model update.
%    Core Stage09 blocks are rebuilt in place later without a half-built
%    update, so an earlier failed run remains recoverable.
% =========================================================================
fprintf('\n--- Clean stale partial S09 diagnostics ---\n');

s09Diag = [sm '/AA15_STAGE09_Q_DIAGNOSTICS'];

existingS09Port = localFindExistingLogPort(s09Diag,group28Mux);

if existingS09Port > 0
    if existingS09Port ~= 7
        error('S09:OldDiagPort', ...
            'Existing S09 diagnostics is connected to unexpected Group28 input%d.', ...
            existingS09Port);
    end

    localDisconnectLogInput(group28Mux,7);
    fprintf('[DISCONNECT] stale S09 diagnostics from Group28 input7.\n');
end

if getSimulinkBlockHandle(s09Diag) >= 0
    localDeleteBlockIfExists(s09Diag);
    fprintf('[DELETE] stale %s\n',s09Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 7
    ph28 = get_param(group28Mux,'PortHandles');
    if numel(ph28.Inport) < 7
        error('S09:Group28PortMaterialization','Could not inspect Group28 input7.');
    end

    ln7 = get_param(ph28.Inport(7),'Line');
    if ~isequal(ln7,-1)
        error('S09:Group28Input7Busy', ...
            'Group28 input7 is still driven after S09 diagnostic cleanup.');
    end

    set_param(group28Mux,'Inputs','6');
    fprintf('[RESTORE] Group28 physical inputs: 7 -> 6.\n');
end

fprintf('[OK] Stage09 diagnostic leftovers removed without model update.\n');

% =========================================================================
% 4. Add/verify one tunable Q sign calibration parameter.
% =========================================================================
fprintf('\n--- Create/verify CFG15_Q_SIGN_GAIN ---\n');

qSignTag = 'CFG15_Q_SIGN_GAIN';
qSignConst = [panel '/' qSignTag];
qSignGoto = [panel '/GOTO_' qSignTag];

localAssertNoForeignGlobalGoto(mdl,qSignTag,panel,qSignGoto);

if getSimulinkBlockHandle(qSignConst) < 0
    add_block('simulink/Sources/Constant',qSignConst, ...
        'Value','1', ...
        'SampleTime','inf', ...
        'OutDataTypeStr','double', ...
        'Position',[1010 597 1230 627]);
    fprintf('[CREATE] CFG15_Q_SIGN_GAIN = 1\n');
else
    if ~strcmp(get_param(qSignConst,'BlockType'),'Constant')
        error('S09:QSignConstType','%s is not Constant.',qSignConst);
    end
    set_param(qSignConst,'SampleTime','inf');
    try
        set_param(qSignConst,'OutDataTypeStr','double');
    catch
    end
    fprintf('[KEEP] CFG15_Q_SIGN_GAIN = %s\n',get_param(qSignConst,'Value'));
end

if getSimulinkBlockHandle(qSignGoto) < 0
    add_block('simulink/Signal Routing/Goto',qSignGoto, ...
        'GotoTag',qSignTag, ...
        'TagVisibility','global', ...
        'Position',[1265 600 1450 624]);
else
    if ~strcmp(get_param(qSignGoto,'BlockType'),'Goto')
        error('S09:QSignGotoType','%s is not Goto.',qSignGoto);
    end
    if ~strcmp(get_param(qSignGoto,'GotoTag'),qSignTag)
        error('S09:QSignGotoTag','Unexpected GotoTag at %s.',qSignGoto);
    end
    set_param(qSignGoto,'TagVisibility','global');
end

localForceOwnedLine(panel,[qSignTag '/1'],['GOTO_' qSignTag '/1']);

% =========================================================================
% 5. Build S3 normalizer with explicit four Demux15 blocks.
%    NO model update is allowed until the normalizer, Q allocator/router,
%    publication Gotos and diagnostics are all complete.
% =========================================================================
fprintf('\n--- Build S3 AVC normalizer ---\n');

s3Norm = [stack '/AA15_S3_AVC_Normalizer'];

if getSimulinkBlockHandle(s3Norm) < 0
    x0 = localNextRightX(stack,120);
    add_block('simulink/Ports & Subsystems/Subsystem',s3Norm, ...
        'Position',[x0 500 x0+390 855]);
    fprintf('[CREATE] %s\n',s3Norm);
else
    if ~strcmp(get_param(s3Norm,'BlockType'),'SubSystem')
        error('S09:S3NormConflict','%s exists but is not SubSystem.',s3Norm);
    end
    fprintf('[REBUILD] %s\n',s3Norm);
end

localDeleteSubsystemContents(s3Norm);

normInNames = {'status15','alarm15','metric15','cmd15'};
for i = 1:4
    y = 55 + (i-1)*72;
    add_block('simulink/Ports & Subsystems/In1', ...
        [s3Norm '/' normInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[25 y 55 y+16]);

    demuxName = sprintf('DEMUX_%s',upper(normInNames{i}));
    add_block('simulink/Signal Routing/Demux', ...
        [s3Norm '/' demuxName], ...
        'Outputs','15', ...
        'Position',[110 y-15 140 y+45]);

    localEnsureLine(s3Norm, ...
        [normInNames{i} '/1'], ...
        [demuxName '/1']);
end

normOutNames = {'s3_status','s3_alarm','s3_metric','s3_qcmd_kvar'};
demuxOutNames = {'DEMUX_STATUS15','DEMUX_ALARM15','DEMUX_METRIC15','DEMUX_CMD15'};

for i = 1:4
    y = 55 + (i-1)*72;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [s3Norm '/' normOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[300 y 330 y+16]);

    localEnsureLine(s3Norm, ...
        [demuxOutNames{i} '/3'], ...
        [normOutNames{i} '/1']);
end

% Connect proven stack inputs1..4 to S3 normalizer before first update.
for i = 1:4
    stackIn = localFindStackInportByNumber(stack,i);
    srcPH = get_param(stackIn,'PortHandles');
    dstPH = get_param(s3Norm,'PortHandles');

    if isempty(srcPH.Outport) || numel(dstPH.Inport) < i
        error('S09:S3NormStructuralPort', ...
            'Could not materialize stack input%d -> S3 normalizer input%d.',i,i);
    end

    localEnsureTopLevelConnection(stack, ...
        srcPH.Outport(1),dstPH.Inport(i), ...
        sprintf('stack input%d -> S3 normalizer input%d',i,i));
end

s3Tags = {
    'AA15_S3_STATUS'
    'AA15_S3_ALARM'
    'AA15_S3_METRIC'
    'AA15_S3_Q_REQUEST_KVAR'
};

for i = 1:4
    localAssertNoForeignGlobalGoto(mdl,s3Tags{i},stack, ...
        [stack '/' sprintf('GOTO_S3NORM_S09_%02d',i)]);
end

for i = 1:4
    gotoName = sprintf('GOTO_S3NORM_S09_%02d',i);
    p = [stack '/' gotoName];

    if getSimulinkBlockHandle(p) < 0
        add_block('simulink/Signal Routing/Goto',p, ...
            'GotoTag',s3Tags{i}, ...
            'TagVisibility','global');
    else
        if ~strcmp(get_param(p,'BlockType'),'Goto')
            error('S09:S3GotoType','%s is not Goto.',p);
        end
        set_param(p,'GotoTag',s3Tags{i},'TagVisibility','global');
    end
end

% MATLAB does not permit arithmetic directly inside a Position expression
% as used above on all releases. Reposition the four Gotos explicitly.
normPos = get_param(s3Norm,'Position');
for i = 1:4
    p = [stack '/' sprintf('GOTO_S3NORM_S09_%02d',i)];
    y = normPos(2) + 25 + (i-1)*55;
    set_param(p,'Position',[normPos(3)+45 y normPos(3)+260 y+22]);
    localForceOwnedLine(stack, ...
        sprintf('AA15_S3_AVC_Normalizer/%d',i), ...
        sprintf('GOTO_S3NORM_S09_%02d/1',i));
end

% =========================================================================
% 6. Build Q allocator + source router.
% =========================================================================
fprintf('\n--- Build Q capability allocator/router ---\n');

qCore = [stack '/AA15_Q_Allocator_Router'];

if getSimulinkBlockHandle(qCore) < 0
    normPos = get_param(s3Norm,'Position');
    x0 = normPos(3) + 330;
    add_block('simulink/Ports & Subsystems/Subsystem',qCore, ...
        'Position',[x0 485 x0+500 930]);
    fprintf('[CREATE] %s\n',qCore);
else
    if ~strcmp(get_param(qCore,'BlockType'),'SubSystem')
        error('S09:QCoreConflict','%s exists but is not SubSystem.',qCore);
    end
    fprintf('[REBUILD] %s\n',qCore);
end

localDeleteSubsystemContents(qCore);

qInputTags = {
    'AA15_S3_Q_REQUEST_KVAR'
    'AA15_FINAL_APPLIED_PV1'
    'AA15_FINAL_APPLIED_PV2'
    'AA15_FINAL_APPLIED_ESS1'
    'AA15_FINAL_APPLIED_ESS2'
    'AA15_FINAL_APPLIED_EV1'
    'AA15_FINAL_APPLIED_EV2'
    'AA15_AGC_IN_09_P_UNIT_KW'
    'CFG15_MASTER_ENABLE'
    'CFG15_EXEC_S03'
    'CFG15_CONTROL_SOURCE'
    'CFG15_Q_SIGN_GAIN'
};

for i = 1:12
    col = floor((i-1)/6);
    row = mod(i-1,6);
    x = 20 + col*245;
    y = 25 + row*58;

    add_block('simulink/Signal Routing/From', ...
        [qCore '/' sprintf('FROM_QSRC_%02d',i)], ...
        'GotoTag',qInputTags{i}, ...
        'Position',[x y x+215 y+20]);
end

qMF = [qCore '/AA15_Q_Capability_Allocator_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',qMF, ...
    'Position',[535 80 980 500]);

qChart = localGetEMChartByPath(qMF);
qChart.Script = localQAllocatorScript();

qOutNames = {
    'qref_pv1'
    'qref_pv2'
    'qref_ess1'
    'qref_ess2'
    'qref_ev1'
    'qref_ev2'
    'q_request_pu'
    'q_applied_pu'
    'q_cap_total_pu'
    'q_valid'
    'q_selected_source'
    'q_saturated'
};

for i = 1:12
    y = 45 + (i-1)*34;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [qCore '/' qOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1080 y 1110 y+16]);
end

for i = 1:12
    localEnsureLine(qCore, ...
        sprintf('FROM_QSRC_%02d/1',i), ...
        sprintf('AA15_Q_Capability_Allocator_Core/%d',i));

    localEnsureLine(qCore, ...
        sprintf('AA15_Q_Capability_Allocator_Core/%d',i), ...
        [qOutNames{i} '/1']);
end

qOutTags = {
    'AA15_FINAL_QREF_PV1'
    'AA15_FINAL_QREF_PV2'
    'AA15_FINAL_QREF_ESS1'
    'AA15_FINAL_QREF_ESS2'
    'AA15_FINAL_QREF_EV1'
    'AA15_FINAL_QREF_EV2'
    'AA15_Q_TOTAL_REQUEST_PU'
    'AA15_Q_TOTAL_APPLIED_PU'
    'AA15_Q_CAP_TOTAL_PU'
    'AA15_Q_ALLOCATOR_VALID'
    'AA15_Q_ROUTER_SELECTED_SOURCE'
    'AA15_Q_SATURATED'
};

for i = 1:12
    localAssertNoForeignGlobalGoto(mdl,qOutTags{i},stack, ...
        [stack '/' sprintf('GOTO_QOUT_S09_%02d',i)]);
end

qPos = get_param(qCore,'Position');

for i = 1:12
    gotoName = sprintf('GOTO_QOUT_S09_%02d',i);
    p = [stack '/' gotoName];

    if getSimulinkBlockHandle(p) < 0
        add_block('simulink/Signal Routing/Goto',p, ...
            'GotoTag',qOutTags{i}, ...
            'TagVisibility','global');
    else
        if ~strcmp(get_param(p,'BlockType'),'Goto')
            error('S09:QGotoType','%s is not Goto.',p);
        end
        set_param(p,'GotoTag',qOutTags{i},'TagVisibility','global');
    end

    col = floor((i-1)/6);
    row = mod(i-1,6);
    x = qPos(3) + 45 + col*250;
    y = qPos(2) + 20 + row*52;

    set_param(p,'Position',[x y x+220 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_Q_Allocator_Router/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 7. Build S09 diagnostics BEFORE first model update.
% =========================================================================
fprintf('\n--- Build S09 diagnostics ---\n');

[dx,dy] = localFindFreeTopLevelPosition(sm,470,430,420);
add_block('simulink/Ports & Subsystems/Subsystem',s09Diag, ...
    'Position',[dx dy dx+470 dy+430]);
localDeleteSubsystemContents(s09Diag);

diagTags = {
    'AA15_S3_STATUS'
    'AA15_S3_ALARM'
    'AA15_S3_METRIC'
    'AA15_S3_Q_REQUEST_KVAR'
    'AA15_Q_TOTAL_REQUEST_PU'
    'AA15_Q_TOTAL_APPLIED_PU'
    'AA15_Q_CAP_TOTAL_PU'
    'AA15_Q_ALLOCATOR_VALID'
    'AA15_Q_ROUTER_SELECTED_SOURCE'
    'AA15_Q_SATURATED'
    'AA15_FINAL_QREF_PV1'
    'AA15_FINAL_QREF_PV2'
    'AA15_FINAL_QREF_ESS1'
    'AA15_FINAL_QREF_ESS2'
    'AA15_FINAL_QREF_EV1'
    'AA15_FINAL_QREF_EV2'
    'CFG15_MASTER_ENABLE'
    'CFG15_EXEC_S03'
    'CFG15_CONTROL_SOURCE'
    'AA15_AGC_IN_09_P_UNIT_KW'
    'CFG15_Q_SIGN_GAIN'
};

for i = 1:21
    col = floor((i-1)/11);
    row = mod(i-1,11);
    x = 20 + col*230;
    y = 25 + row*34;

    add_block('simulink/Signal Routing/From', ...
        [s09Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+205 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s09Diag '/AA15_STAGE09_DIAG21'], ...
    'Inputs','21', ...
    'Position',[515 45 550 390]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s09Diag '/diag21'], ...
    'Port','1', ...
    'Position',[615 205 645 221]);

for i = 1:21
    localEnsureLine(s09Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE09_DIAG21/%d',i));
end

localEnsureLine(s09Diag,'AA15_STAGE09_DIAG21/1','diag21/1');

% =========================================================================
% 8. FIRST model update: all Stage09 control structures are now complete.
% =========================================================================
fprintf('\n--- First compile/update after COMPLETE Stage09 structure ---\n');

set_param(mdl,'SimulationCommand','update');

% Explicit vector-width assertions.
for i = 1:4
    demuxPH = get_param([s3Norm '/' demuxOutNames{i}],'PortHandles');
    if numel(demuxPH.Outport) ~= 15
        error('S09:DemuxWidth', ...
            '%s expected 15 outputs, found %d.', ...
            [s3Norm '/' demuxOutNames{i}],numel(demuxPH.Outport));
    end
end

qPorts = get_param(qMF,'Ports');
if qPorts(1) ~= 12 || qPorts(2) ~= 12
    error('S09:QCorePorts', ...
        'Q allocator expected 12-in/12-out, found %d/%d.', ...
        qPorts(1),qPorts(2));
end

fprintf('[OK] Four strategy vectors proven as 15-wide via Demux15.\n');
fprintf('[OK] Q allocator/router compiled as 12 inputs / 12 outputs.\n');

% =========================================================================
% 9. REAL Qref takeover: replace ONLY six Mux input7 destinations.
% =========================================================================
fprintf('\n--- REAL Qref takeover on six device Mux input7 ports ---\n');

for i = 1:6
    muxPath = muxPaths{i};
    muxPH = get_param(muxPath,'PortHandles');

    % Re-check protected Pref input6 immediately before physical Q edit.
    [prefSrcNow,~] = localGetDestinationSource(muxPH.Inport(6));
    if ~strcmp(prefSrcNow,prefInput6SrcPaths{i})
        error('S09:PrefChangedBeforeQ', ...
            '%s input6 source changed unexpectedly before Q takeover.',muxPath);
    end

    [qSrcNow,~] = localGetDestinationSource(muxPH.Inport(7));
    qType = get_param(qSrcNow,'BlockType');

    if strcmp(qType,'From')
        qTag = get_param(qSrcNow,'GotoTag');
        if ~strcmp(qTag,finalQTags{i})
            error('S09:QFromChanged', ...
                '%s input7 From tag=%s, expected %s.', ...
                muxPath,qTag,finalQTags{i});
        end
        fprintf('[KEEP] %-4s input7 already uses %s\n',devNames{i},finalQTags{i});
        continue;
    end

    if ~strcmp(qType,'Constant')
        error('S09:QSourceChanged', ...
            '%s input7 source became unexpected type %s.',muxPath,qType);
    end

    qVal = localResolveScalarConstant(qSrcNow);
    if ~isfinite(qVal) || abs(qVal) > 1e-12
        error('S09:QSourceNotZeroNow', ...
            '%s input7 source is no longer legacy zero.',muxPath);
    end

    parent = get_param(muxPath,'Parent');
    fromPath = [parent '/' qLocalFromNames{i}];

    if getSimulinkBlockHandle(fromPath) >= 0
        localDeleteBlockIfExists(fromPath);
    end

    muxPos = get_param(muxPath,'Position');
    x = max(20,muxPos(1)-250);
    y = muxPos(2)+95;

    add_block('simulink/Signal Routing/From',fromPath, ...
        'GotoTag',finalQTags{i}, ...
        'Position',[x y x+215 y+20]);

    fromPH = get_param(fromPath,'PortHandles');

    % Disconnect ONLY this destination branch. Legacy Constant is preserved.
    localDisconnectDestinationBranch(parent,muxPH.Inport(7));

    % Refresh Mux port handle after branch edit.
    muxPH = get_param(muxPath,'PortHandles');
    add_line(parent,fromPH.Outport(1),muxPH.Inport(7),'autorouting','on');

    fprintf('[ROUTE] %-4s Qref input7 <- %s\n',devNames{i},finalQTags{i});
end

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 10. Append S09 diag21 to Group28 input7.
% =========================================================================
fprintf('\n--- Append S09 diag21 to Group28 input7 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 6
    error('S09:Group28BeforeAppend', ...
        'Expected Group28 Inputs=6 before S09 append.');
end

set_param(group28Mux,'Inputs','7');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s09Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S09:DiagPort','S09 diagnostics expected exactly one output.');
end
if numel(muxPH28.Inport) < 7
    error('S09:Group28Input7Missing','Group28 input7 did not materialize.');
end

ln7 = get_param(muxPH28.Inport(7),'Line');

if isequal(ln7,-1)
    add_line(sm,diagPH.Outport(1),muxPH28.Inport(7),'autorouting','on');
else
    src7 = get_param(ln7,'SrcPortHandle');
    if src7 ~= diagPH.Outport(1)
        error('S09:Group28Input7Driven', ...
            'Group28 input7 is already driven by another source.');
    end
end

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 11. Final post-assertions.
% =========================================================================
fprintf('\n--- Final Stage09 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 7
    error('S09:Group28FinalInputs', ...
        'Group28 must have 7 physical inputs after S09.');
end

for i = 1:6
    muxPH = get_param(muxPaths{i},'PortHandles');

    % Pref input6 MUST be unchanged.
    [prefSrcNow,~] = localGetDestinationSource(muxPH.Inport(6));
    if ~strcmp(prefSrcNow,prefInput6SrcPaths{i})
        error('S09:PrefPostAssert', ...
            '%s input6 source changed during S09.',muxPaths{i});
    end

    if ~strcmp(get_param(prefSrcNow,'GotoTag'),finalPrefTags{i})
        error('S09:PrefPostTag', ...
            '%s input6 no longer reads %s.',muxPaths{i},finalPrefTags{i});
    end

    % Q input7 MUST now use Stage09 final Q tag.
    [qSrcNow,~] = localGetDestinationSource(muxPH.Inport(7));

    if ~strcmp(get_param(qSrcNow,'BlockType'),'From')
        error('S09:QPostType', ...
            '%s input7 is not From after S09.',muxPaths{i});
    end

    if ~strcmp(get_param(qSrcNow,'GotoTag'),finalQTags{i})
        error('S09:QPostTag', ...
            '%s input7 tag=%s, expected %s.', ...
            muxPaths{i},get_param(qSrcNow,'GotoTag'),finalQTags{i});
    end
end

% Group28 frozen order.
for i = 1:numel(diagBlocks)
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= expectedPorts(i)
        error('S09:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.', ...
            diagBlocks{i},expectedPorts(i),p);
    end
end

if localFindExistingLogPort(s09Diag,group28Mux) ~= 7
    error('S09:S09DiagNot7','S09 diagnostics is not on Group28 input7.');
end

% Confirm global tags are unique.
allStage09Tags = [s3Tags; qOutTags; {qSignTag}];

for i = 1:numel(allStage09Tags)
    localAssertSingleGlobalGoto(mdl,allStage09Tags{i});
end

% Save only after all assertions pass.
save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE09 COMPLETE\n');
fprintf('============================================================\n');
fprintf('S3 raw strategy algorithm       : UNCHANGED\n');
fprintf('S3 normalizer                   : PASS\n');
fprintf('Q capability allocator          : PASS\n');
fprintf('Q source router                 : PASS\n');
fprintf('Six real Qref input7 takeovers  : PASS\n');
fprintf('Six Pref input6 protections     : PASS\n');
fprintf('CFG15_Q_SIGN_GAIN               : created/verified (default +1)\n');
fprintf('Group28                         : 7 physical inputs\n');
fprintf('Group28 total signals           : 113\n');
fprintf('Expected MAT rows               : 114 (incl. Target Time)\n');
fprintf('Backup                          : %s\n',backupFile);
fprintf('\nNEXT: Build is required because six REAL Qref plant paths changed.\n');

end


% =========================================================================
% Local code-generation script for Q allocator.
% =========================================================================
function txt = localQAllocatorScript()

lines = {};
lines{end+1} = ['function [q1,q2,q3,q4,q5,q6,q_request_pu,q_applied_pu,' ...
    'q_cap_total_pu,q_valid,q_selected_source,q_saturated] = ' ...
    'AA15_Q_Capability_Allocator_Core(' ...
    'qcmd_kvar,p1,p2,p3,p4,p5,p6,p_unit_kw,' ...
    'master_enable,exec_s03,control_source,q_sign_gain)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = 'q1 = 0.0; q2 = 0.0; q3 = 0.0;';
lines{end+1} = 'q4 = 0.0; q5 = 0.0; q6 = 0.0;';
lines{end+1} = 'q_request_pu = 0.0;';
lines{end+1} = 'q_applied_pu = 0.0;';
lines{end+1} = 'q_cap_total_pu = 0.0;';
lines{end+1} = 'q_valid = 1.0;';
lines{end+1} = 'q_selected_source = 0.0;';
lines{end+1} = 'q_saturated = 0.0;';
lines{end+1} = '';
lines{end+1} = '% Validate active-power operating points first.';
lines{end+1} = 'if ~finite1(p1) || ~finite1(p2) || ~finite1(p3) || ...';
lines{end+1} = '   ~finite1(p4) || ~finite1(p5) || ~finite1(p6)';
lines{end+1} = '    q_valid = 0.0;';
lines{end+1} = '    q_selected_source = -90.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% Remaining per-unit apparent-power capability.';
lines{end+1} = 'c1 = sqrt(max(1.0 - min(abs(p1),1.0)^2,0.0));';
lines{end+1} = 'c2 = sqrt(max(1.0 - min(abs(p2),1.0)^2,0.0));';
lines{end+1} = 'c3 = sqrt(max(1.0 - min(abs(p3),1.0)^2,0.0));';
lines{end+1} = 'c4 = sqrt(max(1.0 - min(abs(p4),1.0)^2,0.0));';
lines{end+1} = 'c5 = sqrt(max(1.0 - min(abs(p5),1.0)^2,0.0));';
lines{end+1} = 'c6 = sqrt(max(1.0 - min(abs(p6),1.0)^2,0.0));';
lines{end+1} = 'q_cap_total_pu = c1+c2+c3+c4+c5+c6;';
lines{end+1} = '';
lines{end+1} = 'src = round(control_source);';
lines{end+1} = '';
lines{end+1} = '% Source 0 = exact legacy Qref=0.';
lines{end+1} = 'if src == 0';
lines{end+1} = '    q_selected_source = 0.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% Source 2 BOARD15 Q path is intentionally reserved, not invented here.';
lines{end+1} = 'if src == 2';
lines{end+1} = '    q_valid = 0.0;';
lines{end+1} = '    q_selected_source = -2.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if src ~= 1';
lines{end+1} = '    q_valid = 0.0;';
lines{end+1} = '    q_selected_source = -99.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% LOCAL15 selected, but S3 not executing: preserve legacy Qref=0.';
lines{end+1} = 'if master_enable <= 0.5 || exec_s03 <= 0.5';
lines{end+1} = '    q_selected_source = 0.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if ~finite1(qcmd_kvar) || ~finite1(p_unit_kw) || abs(p_unit_kw) < 1e-9';
lines{end+1} = '    q_valid = 0.0;';
lines{end+1} = '    q_selected_source = -3.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = '% Tunable sign calibration: only the sign is used.';
lines{end+1} = 'sgn = 1.0;';
lines{end+1} = 'if finite1(q_sign_gain) && q_sign_gain < 0.0';
lines{end+1} = '    sgn = -1.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'q_request_pu = sgn*qcmd_kvar/abs(p_unit_kw);';
lines{end+1} = 'q_selected_source = 3.0;';
lines{end+1} = '';
lines{end+1} = 'if q_cap_total_pu <= 1e-9';
lines{end+1} = '    q_applied_pu = 0.0;';
lines{end+1} = '    if abs(q_request_pu) > 1e-9';
lines{end+1} = '        q_saturated = 1.0;';
lines{end+1} = '    end';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'q_applied_pu = min(max(q_request_pu,-q_cap_total_pu),q_cap_total_pu);';
lines{end+1} = 'if abs(q_applied_pu-q_request_pu) > 1e-9';
lines{end+1} = '    q_saturated = 1.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'q1 = q_applied_pu*c1/q_cap_total_pu;';
lines{end+1} = 'q2 = q_applied_pu*c2/q_cap_total_pu;';
lines{end+1} = 'q3 = q_applied_pu*c3/q_cap_total_pu;';
lines{end+1} = 'q4 = q_applied_pu*c4/q_cap_total_pu;';
lines{end+1} = 'q5 = q_applied_pu*c5/q_cap_total_pu;';
lines{end+1} = 'q6 = q_applied_pu*c6/q_cap_total_pu;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = finite1(x)';
lines{end+1} = 'ok = ~(isnan(x) || isinf(x));';
lines{end+1} = 'end';

txt = strjoin(lines,newline);

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
    error('S09:EMChartPath', ...
        'Expected one Stateflow.EMChart at %s, found %d.', ...
        blockPath,numel(charts));
end

chart = charts(1);

end


function blockPath = localFindUniqueNamedBlock(mdl,name)

hits = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'Type','Block', ...
    'Name',name);

if numel(hits) ~= 1
    error('S09:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S09:UndrivenDestination','A protected destination port is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isequal(srcPort,-1)
    error('S09:NoSourcePort','Could not resolve source port.');
end

srcBlock = get_param(srcPort,'Parent');
srcPath = getfullname(srcBlock);

end


function val = localResolveScalarConstant(blockPath)

expr = get_param(blockPath,'Value');
val = str2double(expr);

if ~(isscalar(val) && isfinite(val))
    try
        tmp = slResolve(expr,blockPath);
        if isnumeric(tmp) && isscalar(tmp)
            val = double(tmp);
        end
    catch
    end
end

if ~(isscalar(val) && isfinite(val))
    try
        tmp = evalin('base',expr);
        if isnumeric(tmp) && isscalar(tmp)
            val = double(tmp);
        end
    catch
    end
end

if ~(isscalar(val) && isfinite(val))
    val = NaN;
end

end


function inPath = localFindStackInportByNumber(stack,portNo)

cands = find_system(stack,'SearchDepth',1,'BlockType','Inport');
hits = {};

for i = 1:numel(cands)
    if strcmp(get_param(cands{i},'Port'),num2str(portNo))
        hits{end+1,1} = cands{i}; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    error('S09:StackInport', ...
        'Expected one stack Inport with Port=%d, found %d.', ...
        portNo,numel(hits));
end

inPath = hits{1};

end


function localEnsureTopLevelConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

existingSrc = get_param(ln,'SrcPortHandle');

if existingSrc ~= srcPort
    error('S09:TopConnection', ...
        'Destination for %s is already driven by another source.',desc);
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
    error('S09:LineSourceMissing','Missing source block: %s',srcPath);
end
if getSimulinkBlockHandle(dstPath) < 0
    error('S09:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx) || ...
        srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S09:LinePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

srcPort = srcPH.Outport(srcIdx);
dstPort = dstPH.Inport(dstIdx);
ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

existingSrc = get_param(ln,'SrcPortHandle');

if existingSrc ~= srcPort
    error('S09:LineAlreadyDriven', ...
        'Destination %s is already driven by another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)
% Repair-safe connection for a destination fully owned by Stage09.

srcBlock = strtok(src,'/');
dstBlock = strtok(dst,'/');

srcPortStr = extractAfter(src,'/');
dstPortStr = extractAfter(dst,'/');

srcPath = [parent '/' srcBlock];
dstPath = [parent '/' dstBlock];

if getSimulinkBlockHandle(srcPath) < 0
    error('S09:ForceSourceMissing','Missing source block: %s',srcPath);
end
if getSimulinkBlockHandle(dstPath) < 0
    error('S09:ForceDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx) || ...
        srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S09:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

expectedSrc = srcPH.Outport(srcIdx);
dstPort = dstPH.Inport(dstIdx);
ln = get_param(dstPort,'Line');

if ~isequal(ln,-1)
    existingSrc = get_param(ln,'SrcPortHandle');

    if existingSrc == expectedSrc
        return;
    end

    try
        localDisconnectDestinationBranch(parent,dstPort);
    catch ME
        error('S09:ForceDelete', ...
            'Could not remove stale line feeding %s: %s',dst,ME.message);
    end
end

add_line(parent,expectedSrc,dstPort,'autorouting','on');

ln = get_param(dstPort,'Line');

if isequal(ln,-1) || get_param(ln,'SrcPortHandle') ~= expectedSrc
    error('S09:ForcePostAssert', ...
        'Failed post-assert for %s -> %s.',src,dst);
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

% Branch-safe removal. Never delete the whole multi-destination line.
try
    delete_line(parent,srcPort,dstPort);
catch ME
    error('S09:BranchDelete', ...
        ['Could not remove only the requested branch from a shared line. ' ...
         'Whole-line deletion is intentionally forbidden. %s'],ME.message);
end

end


function localDisconnectLogInput(groupMux,portNo)

ph = get_param(groupMux,'PortHandles');

if numel(ph.Inport) < portNo
    return;
end

ln = get_param(ph.Inport(portNo),'Line');

if isequal(ln,-1)
    return;
end

parent = get_param(groupMux,'Parent');
localDisconnectDestinationBranch(parent,ph.Inport(portNo));

end


function localDeleteBlockIfExists(blockPath)
% Delete a Stage09-owned block and all directly attached lines.

if getSimulinkBlockHandle(blockPath) < 0
    return;
end

try
    ph = get_param(blockPath,'PortHandles');
    lineHandles = [];
    fields = {'Inport','Outport','Enable','Trigger','Ifaction','Reset'};

    for i = 1:numel(fields)
        fld = fields{i};

        if ~isfield(ph,fld)
            continue;
        end

        ports = ph.(fld);

        for j = 1:numel(ports)
            try
                ln = get_param(ports(j),'Line');
            catch
                ln = -1;
            end

            if ~isequal(ln,-1)
                lineHandles(end+1) = ln; %#ok<AGROW>
            end
        end
    end

    lineHandles = unique(lineHandles(lineHandles >= 0));

    for i = 1:numel(lineHandles)
        try
            delete_line(lineHandles(i));
        catch
        end
    end
catch
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

% Fallback: lines first, then blocks.
try
    allLines = find_system(subsys, ...
        'FindAll','on', ...
        'SearchDepth',1, ...
        'Type','line');

    allLines = unique(allLines(allLines >= 0));

    for i = 1:numel(allLines)
        try
            delete_line(allLines(i));
        catch
        end
    end
catch
end

inside = find_system(subsys,'SearchDepth',1,'Type','Block');

for i = 1:numel(inside)
    if strcmp(inside{i},subsys)
        continue;
    end

    try
        delete_block(inside{i});
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


function localAssertNoForeignGlobalGoto(mdl,tag,panel,expectedPath)

gotos = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'BlockType','Goto');

for i = 1:numel(gotos)
    try
        if strcmp(get_param(gotos{i},'GotoTag'),tag)
            if ~strcmp(gotos{i},expectedPath) && ...
                    ~startsWith(gotos{i},[panel '/'])
                error('S09:ForeignGoto', ...
                    'Global tag %s already exists at %s.',tag,gotos{i});
            end
        end
    catch ME
        if strcmp(ME.identifier,'S09:ForeignGoto')
            rethrow(ME);
        end
    end
end

end


function localAssertSingleGlobalGoto(mdl,tag)

gotos = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'BlockType','Goto');

hits = {};

for i = 1:numel(gotos)
    try
        if strcmp(get_param(gotos{i},'GotoTag'),tag)
            hits{end+1,1} = gotos{i}; %#ok<AGROW>
        end
    catch
    end
end

if numel(hits) ~= 1
    error('S09:GlobalGotoCount', ...
        'Expected exactly one Goto for tag %s, found %d.',tag,numel(hits));
end

end


function x = localNextRightX(parent,margin)

blocks = find_system(parent,'SearchDepth',1,'Type','Block');
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


function [x,y] = localFindFreeTopLevelPosition(parent,w,h,margin)

blocks = find_system(parent,'SearchDepth',1,'Type','Block');

if isempty(blocks)
    x = 50;
    y = 50;
    return;
end

rects = [];

for i = 1:numel(blocks)
    if strcmp(blocks{i},parent)
        continue;
    end

    try
        pos = get_param(blocks{i},'Position');
        if numel(pos) == 4
            rects(end+1,:) = pos; %#ok<AGROW>
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
y = max(50,min(rects(:,2)));

% Keep a compact vertical location if the far-right region is free.
candidateY = 80;

if ~localRectOverlaps([x candidateY x+w candidateY+h],rects)
    y = candidateY;
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

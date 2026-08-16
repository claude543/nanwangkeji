function S08_K26_V5_LOCAL15_SOC_SYNC_AND_ACTIVE_P_OBJECTIVES
% S08_K26_V5_LOCAL15_SOC_SYNC_AND_ACTIVE_P_OBJECTIVES
%
% LOCAL15 Stage 08
%
% Scope is intentionally limited to the CURRENT 15 strategies already
% present in Advanced_Microgrid_15_Strategies. This script does NOT add
% project-book-only functions such as dynamic expansion, extra MPC layers,
% V2G, or new strategy numbers.
%
% Stage08 has two jobs:
%
%   A) S07B repair:
%      ESS1/ESS2 SOC update inputs must follow the same FINAL_APPLIED Pref
%      that now drives the real ESS plant after S07.
%
%   B) Complete the CURRENT active-P strategy objective set:
%
%      S1  Demand control             -> import-relief constraint request
%      S2  AGC                        -> dedicated test / monitor
%      S4  Anti-reverse               -> export-relief constraint request
%      S7  Tie-line                   -> P objective mode 0
%      S9  Peak-valley                -> P objective mode 1
%      S10 Periodic plan              -> P objective mode 2
%      S11 Self-use/export limit      -> export-relief constraint request
%      S12 Renewable absorption       -> P objective mode 3
%      S13 Multi-objective            -> P objective mode 4
%
% IMPORTANT:
% The raw strategy algorithms are NOT changed. Stage08 only translates the
% already-tested cmd semantics into the unified LOCAL15 active-P execution
% chain.
%
% P_OBJECTIVE_MODE:
%   0 = S7 tie-line (S2 may execute only when S7 is disabled)
%   1 = S9 peak-valley
%   2 = S10 periodic plan
%   3 = S12 renewable absorption
%   4 = S13 multi-objective
%
% Constraint translation follows the CURRENT strategy code:
%
%   S1 cmd > 0  = import needs to be reduced
%               => require positive dP correction
%
%   S4 cmd > 0  = export exceeds anti-reverse allowance
%               => require negative dP correction
%
%   S11 cmd > 0 = export exceeds policy allowance
%               => require negative dP correction
%
% These are CURRENT corrective guards based on the existing teacher-tested
% strategy outputs. Stage08 does NOT invent new static project-book limits.
%
% S9 cmd  = direct signed dP request
% S10 cmd = PCC target, normalized as cmd10 - Ppcc
% S12 cmd = absorption amount (>0), normalized as negative dP
% S13 cmd = existing signed strategy command, used directly
%
% Real execution chain after Stage08:
%
%   Current 15-strategy outputs
%       -> S03 S2/S7 Normalizer
%       -> S08 P-extension Normalizer
%       -> S08 P Objective + Constraint Manager
%       -> AA15_P_DPREQ_EFFECTIVE
%       -> S04 validated baseline AGC allocator
%       -> S05 Execution Mapper
%       -> S05 Source Router
%       -> u_commit
%       -> S06 execution fault
%       -> u_applied
%       -> S07 Final Applied Safety
%       -> real six-device Pref
%
% Group28:
%   S07 total = 68 signals.
%   S08 appends 24 signals.
%   Final = 92 signals.
%   Expected aa15_strategy_data MAT = 93 rows including Target Time.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 08 - SOC Sync + Active-P Objectives\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S08:NoActiveModel', ...
        'No active model. Open K26_V5 and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
stack = [sm '/AA15_LOCAL_CONTROL_STACK'];

if getSimulinkBlockHandle(sm) < 0
    error('S08:MissingSM','Missing SM_Master.');
end
if getSimulinkBlockHandle(stack) < 0
    error('S08:MissingStack','Missing AA15_LOCAL_CONTROL_STACK.');
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S08:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE08_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S08:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify S07 foundation.
% =========================================================================
fprintf('\n--- Verify S07 foundation ---\n');

normalizer03 = [stack '/AA15_Request_Normalizer'];
arbiter03 = [stack '/AA15_P_Objective_Arbiter'];
arbAGC = [stack '/AA15_Arbitrated_Baseline_AGC'];
arbAGCIn16 = [arbAGC '/FROM_AGC_IN_16'];
execMap = [stack '/AA15_Execution_Mapper'];
execValidFrom = [stack '/FROM_EXEC_SRC_08'];
router = [stack '/AA15_Command_Source_Router'];
faultInjector = [stack '/AA15_Execution_Fault_Injector'];
takeover = [stack '/AA15_Active_P_Takeover'];

group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

s03Diag = [sm '/AA15_STAGE03_DIAGNOSTICS'];
s04Diag = [sm '/AA15_STAGE04_AGC_DIAGNOSTICS'];
s05Diag = [sm '/AA15_STAGE05_ROUTER_DIAGNOSTICS'];
s06Diag = [sm '/AA15_STAGE06_EXECFAULT_DIAGNOSTICS'];
s07Diag = [sm '/AA15_STAGE07_TAKEOVER_DIAGNOSTICS'];

requiredBlocks = {
    normalizer03
    arbiter03
    arbAGC
    arbAGCIn16
    execMap
    execValidFrom
    router
    faultInjector
    takeover
    group28Mux
    op28
    s03Diag
    s04Diag
    s05Diag
    s06Diag
    s07Diag
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S08:MissingPrerequisite', ...
            'Missing S07 prerequisite: %s',requiredBlocks{i});
    end
end

requiredTags = {
    'AA15_BASELINE_DPREQ'
    'AA15_AGC_IN_03_P_PCC_KW'
    'AA15_NORM_S2_DPREQ_KW'
    'AA15_NORM_S7_DPREQ_KW'
    'CFG15_MASTER_ENABLE'
    'CFG15_P_OBJECTIVE_MODE'
    'CFG15_EXEC_S01'
    'CFG15_EXEC_S02'
    'CFG15_EXEC_S04'
    'CFG15_EXEC_S07'
    'CFG15_EXEC_S09'
    'CFG15_EXEC_S10'
    'CFG15_EXEC_S11'
    'CFG15_EXEC_S12'
    'CFG15_EXEC_S13'
    'AA15_FINAL_APPLIED_ESS1'
    'AA15_FINAL_APPLIED_ESS2'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotoByTag(mdl,requiredTags{i}))
        error('S08:MissingTag','Missing required Goto tag: %s',requiredTags{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if isnan(n28)
    error('S08:Group28Inputs','Cannot parse Group28 Mux Inputs.');
end

s08Diag = [sm '/AA15_STAGE08_P_DIAGNOSTICS'];
existingS08Port = localFindExistingLogPort(s08Diag,group28Mux);

if n28 > 6
    error('S08:LaterStageDetected', ...
        ['Group28 already has %d physical inputs. Later-stage diagnostics ' ...
         'appear to exist. Refusing S08 rerun.'],n28);
end

if n28 == 6 && existingS08Port == 0
    error('S08:UnexpectedGroup28Input', ...
        'Group28 has 6 inputs but S08 diagnostics are not input6.');
end

fprintf('[OK] S07 foundation verified.\n');

% =========================================================================
% 2. S07B: synchronize ESS SOC input with FINAL_APPLIED.
% =========================================================================
fprintf('\n--- S07B: synchronize ESS SOC with FINAL_APPLIED ---\n');

essNames = {'ESS1','ESS2'};
oldEssTags = {'V5A_FINAL_ESS1','V5A_FINAL_ESS2'};
finalEssTags = {'AA15_FINAL_APPLIED_ESS1','AA15_FINAL_APPLIED_ESS2'};
legacyBridgeNames = {
    [sm '/AA15_S05_FROM_V5A_FINAL_ESS1']
    [sm '/AA15_S05_FROM_V5A_FINAL_ESS2']
};

socSyncBlocks = cell(2,1);

for i = 1:2
    oldFroms = localFindFromByTag(mdl,oldEssTags{i});
    finalFroms = localFindFromByTag(mdl,finalEssTags{i});

    oldSoc = localFindSocFeedingFrom(oldFroms,legacyBridgeNames{i});
    finalSoc = localFindSocFeedingFrom(finalFroms,'');

    if numel(finalSoc) == 1
        socSyncBlocks{i} = finalSoc{1};
        fprintf('[KEEP] %s SOC already reads %s via %s\n', ...
            essNames{i},finalEssTags{i},finalSoc{1});

    elseif isempty(finalSoc) && numel(oldSoc) == 1
        socSyncBlocks{i} = oldSoc{1};

        fprintf('[SYNC] %s SOC From:\n',essNames{i});
        fprintf('       %s\n',oldSoc{1});
        fprintf('       %s -> %s\n',oldEssTags{i},finalEssTags{i});

        set_param(oldSoc{1},'GotoTag',finalEssTags{i});

    else
        error('S08:SOCSyncAmbiguous', ...
            ['Could not uniquely identify %s SOC command From. ' ...
             'old-SOC candidates=%d, final-SOC candidates=%d.'], ...
             essNames{i},numel(oldSoc),numel(finalSoc));
    end
end

set_param(mdl,'SimulationCommand','update');

% Legacy bridges MUST remain on V5A tags because Router source0 needs them.
for i = 1:2
    if getSimulinkBlockHandle(legacyBridgeNames{i}) < 0
        error('S08:LegacyBridgeMissing','Missing %s.',legacyBridgeNames{i});
    end

    if ~strcmp(get_param(legacyBridgeNames{i},'GotoTag'),oldEssTags{i})
        error('S08:LegacyBridgeChanged', ...
            '%s must remain on %s.',legacyBridgeNames{i},oldEssTags{i});
    end
end

% Re-assert SOC final source after update.
for i = 1:2
    if ~strcmp(get_param(socSyncBlocks{i},'GotoTag'),finalEssTags{i})
        error('S08:SOCSyncFailed', ...
            '%s SOC source did not retain %s.',essNames{i},finalEssTags{i});
    end
end

fprintf('[OK] ESS1/ESS2 SOC command sources now follow FINAL_APPLIED.\n');

% =========================================================================
% 3. Build P-extension Request Normalizer using CURRENT raw cmd15.
% =========================================================================
fprintf('\n--- Build active-P Request Normalizer extension ---\n');

pNorm = [stack '/AA15_Request_Normalizer_P_Extension'];

if getSimulinkBlockHandle(pNorm) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',pNorm, ...
        'Position',[650 520 1010 865]);
    fprintf('[CREATE] %s\n',pNorm);
else
    if ~strcmp(get_param(pNorm,'BlockType'),'SubSystem')
        error('S08:PNormConflict','%s exists but is not a SubSystem.',pNorm);
    end
    localDeleteSubsystemContents(pNorm);
    fprintf('[REBUILD] %s\n',pNorm);
end

try
    set_param(pNorm,'AttributesFormatString', ...
        sprintf(['S08 current-strategy P normalization\\n' ...
                 'S1/S4/S9/S10/S11/S12/S13']));
catch
end

add_block('simulink/Ports & Subsystems/In1',[pNorm '/cmd15'], ...
    'Port','1','Position',[20 150 50 166]);

normMF = [pNorm '/AA15_Normalize_Current_ActiveP_Requests'];
add_block('simulink/User-Defined Functions/MATLAB Function',normMF, ...
    'Position',[135 70 500 315]);

normChart = localGetEMChartByPath(normMF);
normChart.Script = localPNormalizerScript();

normOutNames = {
    's1_import_relief_kw'
    's4_export_relief_kw'
    's9_dp_kw'
    's10_target_kw'
    's11_export_relief_kw'
    's12_dp_kw'
    's13_dp_kw'
};

normTags = {
    'AA15_NORM_S01_IMPORT_RELIEF_KW'
    'AA15_NORM_S04_EXPORT_RELIEF_KW'
    'AA15_NORM_S09_DPREQ_KW'
    'AA15_NORM_S10_TARGET_KW'
    'AA15_NORM_S11_EXPORT_RELIEF_KW'
    'AA15_NORM_S12_DPREQ_KW'
    'AA15_NORM_S13_DPREQ_KW'
};

for i = 1:7
    y = 45 + (i-1)*44;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [pNorm '/' normOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[590 y 620 y+16]);

    localEnsureLine(pNorm, ...
        sprintf('AA15_Normalize_Current_ActiveP_Requests/%d',i), ...
        [normOutNames{i} '/1']);
end

localEnsureLine(pNorm,'cmd15/1','AA15_Normalize_Current_ActiveP_Requests/1');

set_param(mdl,'SimulationCommand','update');

normPorts = get_param(normMF,'Ports');
if normPorts(1) ~= 1 || normPorts(2) ~= 7
    error('S08:PNormPorts', ...
        'P normalizer expected 1-in/7-out, found %d/%d.', ...
        normPorts(1),normPorts(2));
end

% Branch existing stack input4 (cmd15) to the extension normalizer.
cmd15In = localFindStackInportByNumber(stack,4);
cmdPH = get_param(cmd15In,'PortHandles');
pNormPH = get_param(pNorm,'PortHandles');

localEnsureTopLevelConnection(stack, ...
    cmdPH.Outport(1),pNormPH.Inport(1), ...
    'stack cmd15 -> P-extension normalizer');

% Publish normalized requests globally.
for i = 1:7
    gotoName = sprintf('GOTO_PNORM_S08_%02d',i);
    p = [stack '/' gotoName];

    localDeleteBlockIfExists(p);

    y = 535 + (i-1)*38;

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',normTags{i}, ...
        'TagVisibility','global', ...
        'Position',[1045 y 1285 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_Request_Normalizer_P_Extension/%d',i), ...
        [gotoName '/1']);
end

fprintf('[OK] Current S1/S4/S9/S10/S11/S12/S13 cmd semantics normalized.\n');

% =========================================================================
% 4. Build full CURRENT active-P objective + constraint manager.
% =========================================================================
fprintf('\n--- Build P Objective + Constraint Manager ---\n');

pMgr = [stack '/AA15_P_Objective_Constraint_Manager'];

if getSimulinkBlockHandle(pMgr) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',pMgr, ...
        'Position',[1335 500 1755 930]);
    fprintf('[CREATE] %s\n',pMgr);
else
    if ~strcmp(get_param(pMgr,'BlockType'),'SubSystem')
        error('S08:PMgrConflict','%s exists but is not a SubSystem.',pMgr);
    end
    localDeleteSubsystemContents(pMgr);
    fprintf('[REBUILD] %s\n',pMgr);
end

try
    set_param(pMgr,'AttributesFormatString', ...
        sprintf(['S08 CURRENT active-P arbitration\\n' ...
                 'Objectives S7/S9/S10/S12/S13\\n' ...
                 'Constraints S1/S4/S11']));
catch
end

mgrInputTags = {
    'AA15_BASELINE_DPREQ'
    'AA15_AGC_IN_03_P_PCC_KW'
    'AA15_NORM_S2_DPREQ_KW'
    'AA15_NORM_S7_DPREQ_KW'
    'AA15_NORM_S01_IMPORT_RELIEF_KW'
    'AA15_NORM_S04_EXPORT_RELIEF_KW'
    'AA15_NORM_S09_DPREQ_KW'
    'AA15_NORM_S10_TARGET_KW'
    'AA15_NORM_S11_EXPORT_RELIEF_KW'
    'AA15_NORM_S12_DPREQ_KW'
    'AA15_NORM_S13_DPREQ_KW'
    'CFG15_MASTER_ENABLE'
    'CFG15_P_OBJECTIVE_MODE'
    'CFG15_EXEC_S01'
    'CFG15_EXEC_S02'
    'CFG15_EXEC_S04'
    'CFG15_EXEC_S07'
    'CFG15_EXEC_S09'
    'CFG15_EXEC_S10'
    'CFG15_EXEC_S11'
    'CFG15_EXEC_S12'
    'CFG15_EXEC_S13'
};

for i = 1:numel(mgrInputTags)
    col = floor((i-1)/11);
    row = mod(i-1,11);

    x = 20 + col*245;
    y = 25 + row*34;

    fromName = sprintf('FROM_PMGR_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [pMgr '/' fromName], ...
        'GotoTag',mgrInputTags{i}, ...
        'Position',[x y x+215 y+20]);
end

mgrMF = [pMgr '/AA15_Current_P_Objective_Constraint_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',mgrMF, ...
    'Position',[555 80 1010 500]);

mgrChart = localGetEMChartByPath(mgrMF);
mgrChart.Script = localPManagerScript();

mgrOutNames = {
    'objective_dp_kw'
    'effective_dp_kw'
    'objective_source'
    'request_valid'
    's1_active'
    's4_active'
    's11_active'
    'constraint_mask'
    'constraint_conflict'
};

mgrOutTags = {
    'AA15_P_OBJECTIVE_DPREQ'
    'AA15_P_DPREQ_EFFECTIVE'
    'AA15_P_OBJECTIVE_SOURCE'
    'AA15_P_REQUEST_VALID_EFFECTIVE'
    'AA15_P_S01_CONSTRAINT_ACTIVE'
    'AA15_P_S04_CONSTRAINT_ACTIVE'
    'AA15_P_S11_CONSTRAINT_ACTIVE'
    'AA15_P_CONSTRAINT_MASK'
    'AA15_P_CONSTRAINT_CONFLICT'
};

for i = 1:9
    y = 50 + (i-1)*44;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [pMgr '/' mgrOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1110 y 1140 y+16]);
end

set_param(mdl,'SimulationCommand','update');

mgrPorts = get_param(mgrMF,'Ports');
if mgrPorts(1) ~= 22 || mgrPorts(2) ~= 9
    error('S08:PMgrPorts', ...
        'P manager expected 22-in/9-out, found %d/%d.', ...
        mgrPorts(1),mgrPorts(2));
end

for i = 1:22
    localEnsureLine(pMgr, ...
        sprintf('FROM_PMGR_%02d/1',i), ...
        sprintf('AA15_Current_P_Objective_Constraint_Core/%d',i));
end

for i = 1:9
    localEnsureLine(pMgr, ...
        sprintf('AA15_Current_P_Objective_Constraint_Core/%d',i), ...
        [mgrOutNames{i} '/1']);
end

% Publish P manager outputs globally at stack level.
for i = 1:9
    gotoName = sprintf('GOTO_PMGR_S08_%02d',i);
    p = [stack '/' gotoName];

    localDeleteBlockIfExists(p);

    y = 510 + (i-1)*36;

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',mgrOutTags{i}, ...
        'TagVisibility','global', ...
        'Position',[1810 y 2055 y+22]);

    localEnsureLine(stack, ...
        sprintf('AA15_P_Objective_Constraint_Manager/%d',i), ...
        [gotoName '/1']);
end

fprintf('[OK] Objective modes 0..4 and S1/S4/S11 corrective guards created.\n');

% =========================================================================
% 5. Route the new effective request into the already-validated AGC and
%    route the new validity into the existing Execution Mapper.
% =========================================================================
fprintf('\n--- Connect S08 effective request to existing real LOCAL15 chain ---\n');

if ~strcmp(get_param(arbAGCIn16,'BlockType'),'From')
    error('S08:AGCInput16Type','Expected From at %s.',arbAGCIn16);
end

oldTag = get_param(arbAGCIn16,'GotoTag');
if ~(strcmp(oldTag,'AA15_ARB_DPREQ_SHADOW') || ...
        strcmp(oldTag,'AA15_P_DPREQ_EFFECTIVE'))
    error('S08:AGCInput16Unexpected', ...
        'Unexpected S04 AGC input16 tag: %s',oldTag);
end

set_param(arbAGCIn16,'GotoTag','AA15_P_DPREQ_EFFECTIVE');

if ~strcmp(get_param(execValidFrom,'BlockType'),'From')
    error('S08:ExecValidType','Expected From at %s.',execValidFrom);
end

oldValidTag = get_param(execValidFrom,'GotoTag');
if ~(strcmp(oldValidTag,'AA15_ARB_REQUEST_VALID') || ...
        strcmp(oldValidTag,'AA15_P_REQUEST_VALID_EFFECTIVE'))
    error('S08:ExecValidUnexpected', ...
        'Unexpected S05 valid source tag: %s',oldValidTag);
end

set_param(execValidFrom,'GotoTag','AA15_P_REQUEST_VALID_EFFECTIVE');

set_param(mdl,'SimulationCommand','update');

fprintf('[ROUTE] S04 AGC input16 <- AA15_P_DPREQ_EFFECTIVE\n');
fprintf('[ROUTE] S05 Execution Mapper valid <- AA15_P_REQUEST_VALID_EFFECTIVE\n');

% =========================================================================
% 6. Build S08 diagnostics and append Group28 input6.
% =========================================================================
fprintf('\n--- Build S08 diagnostics ---\n');

if getSimulinkBlockHandle(s08Diag) < 0
    [dx,dy] = localFindFreeTopLevelPosition(sm,430,390,420);

    add_block('simulink/Ports & Subsystems/Subsystem',s08Diag, ...
        'Position',[dx dy dx+430 dy+390]);

    fprintf('[CREATE] %s\n',s08Diag);
else
    if ~strcmp(get_param(s08Diag,'BlockType'),'SubSystem')
        error('S08:DiagConflict','%s exists but is not a SubSystem.',s08Diag);
    end
    localDeleteSubsystemContents(s08Diag);
    fprintf('[REBUILD] %s\n',s08Diag);
end

diagTags = {
    'AA15_NORM_S01_IMPORT_RELIEF_KW'
    'AA15_NORM_S04_EXPORT_RELIEF_KW'
    'AA15_NORM_S09_DPREQ_KW'
    'AA15_NORM_S10_TARGET_KW'
    'AA15_NORM_S11_EXPORT_RELIEF_KW'
    'AA15_NORM_S12_DPREQ_KW'
    'AA15_NORM_S13_DPREQ_KW'
    'AA15_P_OBJECTIVE_DPREQ'
    'AA15_P_DPREQ_EFFECTIVE'
    'AA15_P_OBJECTIVE_SOURCE'
    'AA15_P_REQUEST_VALID_EFFECTIVE'
    'AA15_P_S01_CONSTRAINT_ACTIVE'
    'AA15_P_S04_CONSTRAINT_ACTIVE'
    'AA15_P_S11_CONSTRAINT_ACTIVE'
    'AA15_P_CONSTRAINT_MASK'
    'AA15_P_CONSTRAINT_CONFLICT'
    'CFG15_P_OBJECTIVE_MODE'
    'CFG15_EXEC_S01'
    'CFG15_EXEC_S04'
    'CFG15_EXEC_S09'
    'CFG15_EXEC_S10'
    'CFG15_EXEC_S11'
    'CFG15_EXEC_S12'
    'CFG15_EXEC_S13'
};

for i = 1:24
    col = floor((i-1)/12);
    row = mod(i-1,12);

    x = 20 + col*240;
    y = 25 + row*29;

    fromName = sprintf('FROM_DIAG_%02d',i);

    add_block('simulink/Signal Routing/From', ...
        [s08Diag '/' fromName], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+215 y+18]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s08Diag '/AA15_STAGE08_DIAG24'], ...
    'Inputs','24', ...
    'Position',[525 35 560 370]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s08Diag '/diag24'], ...
    'Port','1', ...
    'Position',[620 195 650 211]);

for i = 1:24
    localEnsureLine(s08Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE08_DIAG24/%d',i));
end

localEnsureLine(s08Diag,'AA15_STAGE08_DIAG24/1','diag24/1');

set_param(mdl,'SimulationCommand','update');

s08PH = get_param(s08Diag,'PortHandles');

if numel(s08PH.Outport) ~= 1
    error('S08:DiagPort','S08 diagnostics expected one output.');
end

currentPort = localFindExistingLogPort(s08Diag,group28Mux);

if currentPort > 0
    if currentPort ~= 6
        error('S08:Group28Port', ...
            'S08 diagnostics found on unexpected Group28 input %d.',currentPort);
    end
    fprintf('[KEEP] S08 diag24 already on Group28 input6.\n');
else
    n28 = str2double(get_param(group28Mux,'Inputs'));

    if n28 == 5
        set_param(group28Mux,'Inputs','6');
    elseif n28 ~= 6
        error('S08:Group28InputCount', ...
            'Unexpected Group28 input count: %d.',n28);
    end

    muxPH = get_param(group28Mux,'PortHandles');

    localEnsureTopLevelConnection(sm, ...
        s08PH.Outport(1), ...
        muxPH.Inport(6), ...
        'S08 diag24 -> Group28 input6');

    fprintf('[APPEND] S08 diag24 -> Group28 input6.\n');
end

% =========================================================================
% 7. Final assertions.
% =========================================================================
fprintf('\n--- Final S08 assertions ---\n');

set_param(mdl,'SimulationCommand','update');

if ~strcmp(get_param(arbAGCIn16,'GotoTag'),'AA15_P_DPREQ_EFFECTIVE')
    error('S08:AGCRouteAssert','S04 AGC input16 is not on effective dP.');
end

if ~strcmp(get_param(execValidFrom,'GotoTag'), ...
        'AA15_P_REQUEST_VALID_EFFECTIVE')
    error('S08:ExecValidAssert', ...
        'Execution Mapper validity is not on S08 effective validity.');
end

if str2double(get_param(group28Mux,'Inputs')) ~= 6
    error('S08:Group28Final','Group28 must have 6 physical inputs after S08.');
end

if localFindExistingLogPort(s03Diag,group28Mux) ~= 1
    error('S08:G28S03','S03 diagnostics not on Group28 input1.');
end
if localFindExistingLogPort(s04Diag,group28Mux) ~= 2
    error('S08:G28S04','S04 diagnostics not on Group28 input2.');
end
if localFindExistingLogPort(s05Diag,group28Mux) ~= 3
    error('S08:G28S05','S05 diagnostics not on Group28 input3.');
end
if localFindExistingLogPort(s06Diag,group28Mux) ~= 4
    error('S08:G28S06','S06 diagnostics not on Group28 input4.');
end
if localFindExistingLogPort(s07Diag,group28Mux) ~= 5
    error('S08:G28S07','S07 diagnostics not on Group28 input5.');
end
if localFindExistingLogPort(s08Diag,group28Mux) ~= 6
    error('S08:G28S08','S08 diagnostics not on Group28 input6.');
end

% Real six-device Pref route must remain S07 FINAL_APPLIED.
deviceMuxes = {
    'PV1_IO_Mux12','AA15_FINAL_APPLIED_PV1'
    'PV2_IO_Mux12','AA15_FINAL_APPLIED_PV2'
    'ESS1_IO_Mux12','AA15_FINAL_APPLIED_ESS1'
    'ESS2_IO_Mux12','AA15_FINAL_APPLIED_ESS2'
    'EV1_IO_Mux','AA15_FINAL_APPLIED_EV1'
    'EV2_IO_Mux','AA15_FINAL_APPLIED_EV2'
};

for i = 1:size(deviceMuxes,1)
    muxPath = [sm '/' deviceMuxes{i,1}];
    ph = get_param(muxPath,'PortHandles');

    if numel(ph.Inport) < 6
        error('S08:DeviceMuxPort','%s has no Pref input6.',muxPath);
    end

    ln = get_param(ph.Inport(6),'Line');
    if isequal(ln,-1)
        error('S08:DevicePrefLost','%s Pref is unconnected.',muxPath);
    end

    srcH = get_param(ln,'SrcBlockHandle');
    srcPath = getfullname(srcH);

    if ~strcmp(get_param(srcPath,'BlockType'),'From')
        error('S08:DevicePrefType','%s Pref source is not From.',muxPath);
    end

    tag = get_param(srcPath,'GotoTag');
    if ~strcmp(tag,deviceMuxes{i,2})
        error('S08:DevicePrefTag', ...
            '%s Pref expected %s, found %s.', ...
            muxPath,deviceMuxes{i,2},tag);
    end
end

% Reassert SOC sync and legacy bridge preservation.
for i = 1:2
    if ~strcmp(get_param(socSyncBlocks{i},'GotoTag'),finalEssTags{i})
        error('S08:FinalSOCAssert', ...
            '%s SOC is not on final-applied tag.',essNames{i});
    end

    if ~strcmp(get_param(legacyBridgeNames{i},'GotoTag'),oldEssTags{i})
        error('S08:FinalLegacyAssert', ...
            '%s legacy bridge was modified.',essNames{i});
    end
end

% All new manager output tags must have exactly one Goto.
for i = 1:numel(mgrOutTags)
    g = localFindGotoByTag(mdl,mgrOutTags{i});
    if numel(g) ~= 1
        error('S08:ManagerGotoCount', ...
            'Expected one Goto for %s, found %d.',mgrOutTags{i},numel(g));
    end
end

% =========================================================================
% 8. Mapping file.
% =========================================================================
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE08_MAP_%s.txt',modelBase,stamp));

fid = fopen(mapFile,'w');
if fid >= 0
    fprintf(fid,'LOCAL15 Stage08 - SOC Sync + Current Active-P Objectives\n');
    fprintf(fid,'Model: %s\n\n',mdl);

    fprintf(fid,'S07B SOC sync:\n');
    fprintf(fid,'  ESS1 SOC <- AA15_FINAL_APPLIED_ESS1 via %s\n',socSyncBlocks{1});
    fprintf(fid,'  ESS2 SOC <- AA15_FINAL_APPLIED_ESS2 via %s\n\n',socSyncBlocks{2});

    fprintf(fid,'P objective modes:\n');
    fprintf(fid,'  0 S7 tie-line; S2 dedicated fallback/test\n');
    fprintf(fid,'  1 S9 peak-valley\n');
    fprintf(fid,'  2 S10 periodic plan target\n');
    fprintf(fid,'  3 S12 renewable absorption\n');
    fprintf(fid,'  4 S13 current multi-objective cmd\n\n');

    fprintf(fid,'Corrective guards:\n');
    fprintf(fid,'  S1 import relief -> positive dP lower correction\n');
    fprintf(fid,'  S4 export relief -> negative dP upper correction\n');
    fprintf(fid,'  S11 export relief -> negative dP upper correction\n\n');

    fprintf(fid,'Execution route changes:\n');
    fprintf(fid,'  S04 AGC input16 <- AA15_P_DPREQ_EFFECTIVE\n');
    fprintf(fid,'  S05 valid input <- AA15_P_REQUEST_VALID_EFFECTIVE\n\n');

    fprintf(fid,'Group28 = 92 signals total; expected MAT rows = 93.\n');
    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 08 COMPLETE\n');
fprintf('============================================================\n');
fprintf('ESS1/ESS2 SOC source     : FINAL_APPLIED synchronized\n');
fprintf('Current P strategies     : S1/S2/S4/S7/S9/S10/S11/S12/S13\n');
fprintf('P objective modes        : 0..4 implemented\n');
fprintf('S1/S4/S11 guards         : implemented from current strategy cmd\n');
fprintf('Original strategy core   : UNCHANGED\n');
fprintf('Extra project-book funcs : NOT ADDED\n');
fprintf('Real LOCAL15 chain       : now uses AA15_P_DPREQ_EFFECTIVE\n');
fprintf('Group28 signals          : 92\n');
fprintf('Expected MAT rows        : 93\n');
fprintf('Mapping TXT              : %s\n',mapFile);
fprintf('\nA Build is REQUIRED after S08 because the real LOCAL15 P request\n');
fprintf('feeding the already-taken-over plant has changed.\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% S08 MATLAB Function sources
% =========================================================================

function txt = localPNormalizerScript()

lines = {};
lines{end+1} = ['function [s1_import_relief_kw,s4_export_relief_kw,' ...
    's9_dp_kw,s10_target_kw,s11_export_relief_kw,' ...
    's12_dp_kw,s13_dp_kw] = ' ...
    'AA15_Normalize_Current_ActiveP_Requests(cmd15)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = '% Preserve CURRENT teacher-tested strategy cmd semantics.';
lines{end+1} = 's1_import_relief_kw = max(cmd15(1),0.0);';
lines{end+1} = 's4_export_relief_kw = max(cmd15(4),0.0);';
lines{end+1} = 's9_dp_kw = cmd15(9);';
lines{end+1} = 's10_target_kw = cmd15(10);';
lines{end+1} = 's11_export_relief_kw = max(cmd15(11),0.0);';
lines{end+1} = '% S12 positive cmd means more internal absorption is needed.';
lines{end+1} = '% Current PCC sign: negative dP increases charging/import.';
lines{end+1} = 's12_dp_kw = -max(cmd15(12),0.0);';
lines{end+1} = '% S13 keeps the CURRENT strategy-supplied signed command.';
lines{end+1} = 's13_dp_kw = cmd15(13);';
lines{end+1} = 'end';

txt = strjoin(lines,newline);

end


function txt = localPManagerScript()

lines = {};
lines{end+1} = ['function [objective_dp_kw,effective_dp_kw,' ...
    'objective_source,request_valid,s1_active,s4_active,s11_active,' ...
    'constraint_mask,constraint_conflict] = ' ...
    'AA15_Current_P_Objective_Constraint_Core(' ...
    'baseline_dp,pcc_kw,s2_dp,s7_dp,s1_relief,s4_relief,' ...
    's9_dp,s10_target,s11_relief,s12_dp,s13_dp,' ...
    'master_enable,objective_mode,' ...
    'exec_s01,exec_s02,exec_s04,exec_s07,' ...
    'exec_s09,exec_s10,exec_s11,exec_s12,exec_s13)'];
lines{end+1} = '%#codegen';
lines{end+1} = '';
lines{end+1} = '% Safe defaults preserve the validated baseline.';
lines{end+1} = 'objective_dp_kw = baseline_dp;';
lines{end+1} = 'effective_dp_kw = baseline_dp;';
lines{end+1} = 'objective_source = 0.0;';
lines{end+1} = 'request_valid = 1.0;';
lines{end+1} = 's1_active = 0.0;';
lines{end+1} = 's4_active = 0.0;';
lines{end+1} = 's11_active = 0.0;';
lines{end+1} = 'constraint_mask = 0.0;';
lines{end+1} = 'constraint_conflict = 0.0;';
lines{end+1} = '';
lines{end+1} = 'if master_enable <= 0.5';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'mode = round(objective_mode);';
lines{end+1} = '';
lines{end+1} = '% ------------------------------------------------------------';
lines{end+1} = '% Select exactly ONE current active-P objective.';
lines{end+1} = '% ------------------------------------------------------------';
lines{end+1} = 'if mode == 0';
lines{end+1} = '    if exec_s07 > 0.5';
lines{end+1} = '        if isfinite_scalar(s7_dp)';
lines{end+1} = '            objective_dp_kw = s7_dp;';
lines{end+1} = '            objective_source = 7.0;';
lines{end+1} = '        else';
lines{end+1} = '            request_valid = 0.0;';
lines{end+1} = '            objective_source = -7.0;';
lines{end+1} = '        end';
lines{end+1} = '    elseif exec_s02 > 0.5';
lines{end+1} = '        if isfinite_scalar(s2_dp)';
lines{end+1} = '            objective_dp_kw = s2_dp;';
lines{end+1} = '            objective_source = 2.0;';
lines{end+1} = '        else';
lines{end+1} = '            request_valid = 0.0;';
lines{end+1} = '            objective_source = -2.0;';
lines{end+1} = '        end';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = 'elseif mode == 1';
lines{end+1} = '    if exec_s09 > 0.5 && isfinite_scalar(s9_dp)';
lines{end+1} = '        objective_dp_kw = s9_dp;';
lines{end+1} = '        objective_source = 9.0;';
lines{end+1} = '    else';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '        objective_source = -9.0;';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = 'elseif mode == 2';
lines{end+1} = '    if exec_s10 > 0.5 && isfinite_scalar(s10_target) && isfinite_scalar(pcc_kw)';
lines{end+1} = '        objective_dp_kw = s10_target - pcc_kw;';
lines{end+1} = '        objective_source = 10.0;';
lines{end+1} = '    else';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '        objective_source = -10.0;';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = 'elseif mode == 3';
lines{end+1} = '    if exec_s12 > 0.5 && isfinite_scalar(s12_dp)';
lines{end+1} = '        objective_dp_kw = s12_dp;';
lines{end+1} = '        objective_source = 12.0;';
lines{end+1} = '    else';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '        objective_source = -12.0;';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = 'elseif mode == 4';
lines{end+1} = '    if exec_s13 > 0.5 && isfinite_scalar(s13_dp)';
lines{end+1} = '        objective_dp_kw = s13_dp;';
lines{end+1} = '        objective_source = 13.0;';
lines{end+1} = '    else';
lines{end+1} = '        request_valid = 0.0;';
lines{end+1} = '        objective_source = -13.0;';
lines{end+1} = '    end';
lines{end+1} = '';
lines{end+1} = 'else';
lines{end+1} = '    request_valid = 0.0;';
lines{end+1} = '    objective_source = -99.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if ~isfinite_scalar(objective_dp_kw)';
lines{end+1} = '    objective_dp_kw = baseline_dp;';
lines{end+1} = '    effective_dp_kw = baseline_dp;';
lines{end+1} = '    request_valid = 0.0;';
lines{end+1} = '    return;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'effective_dp_kw = objective_dp_kw;';
lines{end+1} = '';
lines{end+1} = '% ------------------------------------------------------------';
lines{end+1} = '% CURRENT strategy corrective guards.';
lines{end+1} = '% S1 wants positive dP when import demand is excessive.';
lines{end+1} = '% S4/S11 want negative dP when export is excessive.';
lines{end+1} = '% ------------------------------------------------------------';
lines{end+1} = 's1corr = 0.0;';
lines{end+1} = 's4corr = 0.0;';
lines{end+1} = 's11corr = 0.0;';
lines{end+1} = '';
lines{end+1} = 'if exec_s01 > 0.5 && isfinite_scalar(s1_relief) && s1_relief > 0.0';
lines{end+1} = '    s1corr = s1_relief;';
lines{end+1} = '    s1_active = 1.0;';
lines{end+1} = '    constraint_mask = constraint_mask + 1.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if exec_s04 > 0.5 && isfinite_scalar(s4_relief) && s4_relief > 0.0';
lines{end+1} = '    s4corr = s4_relief;';
lines{end+1} = '    s4_active = 1.0;';
lines{end+1} = '    constraint_mask = constraint_mask + 2.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if exec_s11 > 0.5 && isfinite_scalar(s11_relief) && s11_relief > 0.0';
lines{end+1} = '    s11corr = s11_relief;';
lines{end+1} = '    s11_active = 1.0;';
lines{end+1} = '    constraint_mask = constraint_mask + 4.0;';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'exportCorr = max(s4corr,s11corr);';
lines{end+1} = '';
lines{end+1} = 'if s1corr > 0.0 && exportCorr > 0.0';
lines{end+1} = '    constraint_conflict = 1.0;';
lines{end+1} = '    % The present physical PCC direction decides which current';
lines{end+1} = '    % violation gets immediate correction. The conflict is logged.';
lines{end+1} = '    if pcc_kw >= 0.0';
lines{end+1} = '        effective_dp_kw = min(effective_dp_kw,-exportCorr);';
lines{end+1} = '    else';
lines{end+1} = '        effective_dp_kw = max(effective_dp_kw,s1corr);';
lines{end+1} = '    end';
lines{end+1} = 'else';
lines{end+1} = '    if s1corr > 0.0';
lines{end+1} = '        effective_dp_kw = max(effective_dp_kw,s1corr);';
lines{end+1} = '    end';
lines{end+1} = '    if exportCorr > 0.0';
lines{end+1} = '        effective_dp_kw = min(effective_dp_kw,-exportCorr);';
lines{end+1} = '    end';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'if ~isfinite_scalar(effective_dp_kw)';
lines{end+1} = '    effective_dp_kw = baseline_dp;';
lines{end+1} = '    request_valid = 0.0;';
lines{end+1} = 'end';
lines{end+1} = 'end';
lines{end+1} = '';
lines{end+1} = 'function ok = isfinite_scalar(x)';
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
    error('S08:EMChartPath', ...
        'Expected one Stateflow.EMChart at %s, found %d.', ...
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


function socBlocks = localFindSocFeedingFrom(fromBlocks,excludeBlock)

socBlocks = {};

for i = 1:numel(fromBlocks)
    p = fromBlocks{i};

    if ~isempty(excludeBlock) && strcmp(p,excludeBlock)
        continue;
    end

    up = upper(p);

    if contains(up,'SOC')
        socBlocks{end+1,1} = p; %#ok<AGROW>
        continue;
    end

    if localDownstreamContainsSOC(p,8)
        socBlocks{end+1,1} = p; %#ok<AGROW>
    end
end

end


function tf = localDownstreamContainsSOC(startBlock,maxDepth)

tf = false;
queueBlocks = {startBlock};
queueDepth = 0;
visited = {};

while ~isempty(queueBlocks)
    b = queueBlocks{1};
    d = queueDepth(1);

    queueBlocks(1) = [];
    queueDepth(1) = [];

    if any(strcmp(visited,b))
        continue;
    end
    visited{end+1} = b; %#ok<AGROW>

    if d > 0 && contains(upper(b),'SOC')
        tf = true;
        return;
    end

    if d >= maxDepth
        continue;
    end

    try
        ph = get_param(b,'PortHandles');
    catch
        continue;
    end

    if ~isfield(ph,'Outport')
        continue;
    end

    for k = 1:numel(ph.Outport)
        ln = get_param(ph.Outport(k),'Line');

        if isequal(ln,-1)
            continue;
        end

        try
            dstH = get_param(ln,'DstBlockHandle');
        catch
            dstH = [];
        end

        dstH = dstH(dstH >= 0);

        for j = 1:numel(dstH)
            try
                dp = getfullname(dstH(j));
            catch
                continue;
            end

            if contains(upper(dp),'SOC')
                tf = true;
                return;
            end

            if ~any(strcmp(visited,dp))
                queueBlocks{end+1} = dp; %#ok<AGROW>
                queueDepth(end+1) = d+1; %#ok<AGROW>
            end
        end
    end
end

end


function inPath = localFindStackInportByNumber(stack,portNo)

cands = find_system(stack, ...
    'SearchDepth',1, ...
    'BlockType','Inport');

hits = {};

for i = 1:numel(cands)
    if strcmp(get_param(cands{i},'Port'),num2str(portNo))
        hits{end+1,1} = cands{i}; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    error('S08:StackInport', ...
        'Expected one stack Inport with Port=%d, found %d.', ...
        portNo,numel(hits));
end

inPath = hits{1};

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
        error('S08:UnexpectedTopLine', ...
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
    error('S08:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S08:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S08:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S08:PortRange', ...
        'Port out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S08:UnexpectedExistingLine', ...
            'Destination %s is already driven by another source.',dst);
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
        pos = get_param(blocks{k},'Position');

        if isnumeric(pos) && numel(pos)==4
            maxRight = max(maxRight,pos(3));
            minTop = min(minTop,pos(2));
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

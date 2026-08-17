function S15_K26_V5_LOCAL15_GRID_RESYNC_RECLOSE_RECOVERY_V2
% S15_K26_V5_LOCAL15_GRID_RESYNC_RECLOSE_RECOVERY_V2
%
% FINAL LOCAL15 Strategy-15 recovery execution patch.
%
% This script completes the EXISTING Strategy 15 execution path:
%
%   GRID_CONNECTED
%       -> electrical island request (already verified in S13)
%       -> ISLANDED, PCC open, selected ESS master GFM
%       -> explicit S15 recovery request
%       -> RESYNCHRONIZATION
%       -> check DeltaV / DeltaF / DeltaTheta
%       -> trim selected ESS-master Fref
%       -> stable sync window
%       -> PCC reclose while master remains GFM
%       -> short reclose hold
%       -> clear S13 island latch
%       -> return selected ESS to GFL
%       -> GRID_CONNECTED_NORMAL
%
% IMPORTANT:
% - Original Advanced_Microgrid_15_Strategies is NOT modified.
% - Existing S5/S15 islanding direction remains unchanged.
% - Existing S14 black-start execution remains unchanged.
% - Communication-only abnormality still cannot trip PCC.
% - Grid/PCC Freq and Vab_rms are taken from EXISTING J2 measurement outputs.
% - The J2 measurement subsystems are linked-library blocks, so S15 DOES NOT
%   edit inside them. Instead S15 branches the existing Grid/PCC Vabc signals
%   at SM_Master level and computes matched three-phase voltage-vector phase
%   in a new top-level AA15_S15_SYNC_PHASE_ESTIMATOR.
% - The phase estimator output is in degrees and is delayed one 100-us sample.
% - ESS1/ESS2 legacy Fref comes from existing K1B_Fref_Sup.
% - Vref is NOT modified by this patch. Voltage mismatch is a hard reclose
%   qualification. This avoids inventing a Vref-unit conversion not present
%   in the current model.
%
% NEW PARAMETERS (saved defaults):
%   CFG15_S15_RECOVERY_REQUEST             = 0
%   CFG15_S15_SYNC_DV_MAX_PU               = 0.10
%   CFG15_S15_SYNC_DF_MAX_HZ               = 0.20
%   CFG15_S15_SYNC_DTHETA_MAX_DEG          = 10
%   CFG15_S15_SYNC_STABLE_S                = 0.50
%   CFG15_S15_RECLOSE_HOLD_S               = 0.20
%   CFG15_S15_FREF_KTHETA_HZ_PER_DEG       = 0.005
%   CFG15_S15_FREF_KDF                      = 0.50
%   CFG15_S15_FREF_TRIM_MAX_HZ             = 0.20
%
% Recovery state:
%   0 IDLE
%   1 RESYNCHRONIZATION
%   2 RECLOSE_HOLD
%   3 CLEAR_ISLAND_LATCH_WAIT
%
% LOOP SAFETY:
% - S13 island latch is an explicit Unit Delay state.
% - S15 recovery state/timers are explicit Unit Delay states.
% - S15 clear-island request is delayed one sample inside S13.
% Therefore no current-step S13<->S15 algebraic loop is created.
%
% GROUP28:
%   S14 total = 261 scalar signals.
%   S15 appends 31:
%
%   262 recovery_request
%   263 raw_s13_mode
%   264 final_executed_mode
%   265 raw_s13_breaker_request
%   266 final_breaker_request
%   267 recovery_state
%   268 recovery_active
%   269 sync_ok
%   270 grid_freq_hz
%   271 pcc_freq_hz
%   272 delta_f_hz
%   273 grid_vab_rms
%   274 pcc_vab_rms
%   275 delta_v_pu
%   276 grid_phase_deg
%   277 pcc_phase_deg
%   278 delta_theta_deg
%   279 sync_stable_timer_s
%   280 reclose_hold_timer_s
%   281 reclose_commanded
%   282 clear_island_request
%   283 s13_island_latch
%   284 s13_black_latch
%   285 legacy_fref
%   286 fref_trim_hz
%   287 final_fref_ess1
%   288 final_fref_ess2
%   289 island_master
%   290 mode_actuation_enable
%   291 breaker_actuation_enable
%   292 s15_recovery_route_valid
%
% Final Group28 = 292 scalar signals.
% Expected MAT = 293 rows including Target Time.
%
% Project rule:
%   mdl = bdroot(gcs)

fprintf('\n============================================================\n');
fprintf(' LOCAL15 S15 - Grid Resynchronization / Reclose / GFL Return\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S15R:NoActiveModel', ...
        'Open K26_V5 and click inside the model before running S15 recovery patch.');
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
        error('S15R:MissingTop','Missing required block: %s',requiredTop{i});
    end
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S15R:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_S15_RECOVERY_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S15R:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify S14 foundation.
% =========================================================================
fprintf('\n--- Verify S14 foundation ---\n');

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
    'AA15_STAGE14_BLACKSTART_DIAGNOSTICS'
};

diagBlocks = cell(12,1);
for i = 1:12
    diagBlocks{i} = [sm '/' diagNames{i}];
    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S15R:MissingPrerequisite', ...
            'Missing S14 prerequisite: %s',diagBlocks{i});
    end
end

requiredBlocks = {
    [stack '/AA15_Device_Mode_Router']
    [stack '/AA15_Grid_Mode_Execution_Manager']
    [stack '/AA15_PCC_Breaker_Command_Router']
    [stack '/AA15_Black_Start_Pref_Gate']
    [sm '/J2_Grid_Measurements']
    [sm '/J2_PCC_Measurements']
    [sm '/Three-Phase Breaker']
    [sm '/ESS1_IO_Mux12']
    [sm '/ESS2_IO_Mux12']
    [sm '/K1B_Fref_Sup_Goto']
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S15R:MissingPrerequisite', ...
            'Missing required current-model block: %s',requiredBlocks{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if ~(n28 == 12 || n28 == 13)
    error('S15R:Group28Inputs', ...
        'Expected Group28 Inputs=12 (S14) or 13 (partial S15), found %g.',n28);
end

for i = 1:12
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S15R:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

requiredTags = {
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_EXEC_S15'
    'CFG15_MODE_ACTUATION_ENABLE'
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'
    'CFG15_ISLAND_MASTER'
    'AA15_PCC_ISLAND_LATCH'
    'AA15_PCC_BLACKSTART_LATCH'
    'AA15_PCC_EXECUTION_ROUTE_VALID'
};

for i = 1:numel(requiredTags)
    if isempty(localFindGotosByTag(mdl,requiredTags{i}))
        error('S15R:MissingTag','Missing prerequisite GotoTag: %s',requiredTags{i});
    end
end

fprintf('[OK] S14 foundation verified.\n');

% =========================================================================
% 2. Verify exact Grid/PCC measurement interfaces WITHOUT editing library links.
% =========================================================================
fprintf('\n--- Verify Grid/PCC measurement interfaces (library-safe) ---\n');

gridMeas = [sm '/J2_Grid_Measurements'];
pccMeas  = [sm '/J2_PCC_Measurements'];

gridPH = get_param(gridMeas,'PortHandles');
pccPH  = get_param(pccMeas,'PortHandles');

% Exact diagnostic proved:
%   input1 = current vector
%   input2 = Vabc vector
%   output1 = Freq
%   output4 = Vab_rms
if numel(gridPH.Inport) < 2 || numel(pccPH.Inport) < 2 || ...
        numel(gridPH.Outport) < 4 || numel(pccPH.Outport) < 4
    error('S15R:MeasPorts', ...
        'Grid/PCC measurement interfaces do not match the audited 2-in/4-out structure.');
end

gridVabcSrcPort = localGetLineSourcePort(gridPH.Inport(2));
pccVabcSrcPort  = localGetLineSourcePort(pccPH.Inport(2));

gridVabcSrcPath = getfullname(get_param(gridVabcSrcPort,'Parent'));
pccVabcSrcPath  = getfullname(get_param(pccVabcSrcPort,'Parent'));

fprintf('[OK] Grid Vabc source: %s\n',gridVabcSrcPath);
fprintf('[OK] PCC  Vabc source: %s\n',pccVabcSrcPath);
fprintf('[OK] Grid/PCC Freq = measurement output1; Vab_rms = output4.\n');
fprintf('[INFO] Linked-library internals will NOT be modified.\n');

% =========================================================================
% 3. Protect physical Fref/Vref/Pref/Qref/Droop/GridOn and breaker.
% =========================================================================
fprintf('\n--- Protect physical routes ---\n');

essMux = {[sm '/ESS1_IO_Mux12']; [sm '/ESS2_IO_Mux12']};
legacyFrefBlocks = {[sm '/ESS1_Fref_From_Sup']; [sm '/ESS2_Fref_From_Sup']};

protectVref = cell(2,1);
protectPref = cell(2,1);
protectQref = cell(2,1);
protectDroop = cell(2,1);
protectGrid = cell(2,1);

for i = 1:2
    ph = get_param(essMux{i},'PortHandles');

    [frefSrc,~] = localGetDestinationSource(ph.Inport(3));
    [protectVref{i},~] = localGetDestinationSource(ph.Inport(4));
    [protectDroop{i},~] = localGetDestinationSource(ph.Inport(5));
    [protectPref{i},~] = localGetDestinationSource(ph.Inport(6));
    [protectQref{i},~] = localGetDestinationSource(ph.Inport(7));
    [protectGrid{i},~] = localGetDestinationSource(ph.Inport(8));

    allowedFinalFref = [sm '/' sprintf('AA15_S15_FINAL_FREF_ESS%d_TO_MUX',i)];

    if ~strcmp(frefSrc,legacyFrefBlocks{i}) && ~strcmp(frefSrc,allowedFinalFref)
        error('S15R:FrefUnexpected', ...
            'ESS%d Fref input3 unexpected source: %s',i,frefSrc);
    end
end

breaker = [sm '/Three-Phase Breaker'];
bph = get_param(breaker,'PortHandles');
[breakerSrc,~] = localGetDestinationSource(bph.Inport(1));

if ~strcmp(breakerSrc,[sm '/AA15_S13_FINAL_BREAKER_TO_PCC'])
    error('S15R:BreakerFoundation', ...
        'PCC breaker is not driven by S13 final breaker From.');
end

fprintf('[OK] Physical ESS and PCC breaker routes protected.\n');

% =========================================================================
% 4. Repair-safe cleanup of partial S15.
% =========================================================================
fprintf('\n--- Repair partial S15 before rebuilding ---\n');

s15Diag = [sm '/AA15_STAGE15_RECOVERY_DIAGNOSTICS'];
recoveryMgr = [stack '/AA15_S15_Recovery_Manager'];
frefRouter  = [stack '/AA15_S15_Master_Fref_Router'];

% 4a. Restore ESS Fref physical inputs to original Supervisor From blocks.
for i = 1:2
    if getSimulinkBlockHandle(legacyFrefBlocks{i}) < 0
        error('S15R:LegacyFrefMissing','Missing %s',legacyFrefBlocks{i});
    end

    mph = get_param(essMux{i},'PortHandles');
    lph = get_param(legacyFrefBlocks{i},'PortHandles');

    localForcePortConnection(sm,lph.Outport(1),mph.Inport(3), ...
        sprintf('restore ESS%d legacy Fref',i));
end

% Delete final Fref From blocks after restoring legacy.
for i = 1:2
    localDeleteBlockIfExists([sm '/' sprintf('AA15_S15_FINAL_FREF_ESS%d_TO_MUX',i)]);
end

% 4b. Remove old S15 diag slot.
oldDiagPort = localFindExistingLogPort(s15Diag,group28Mux);
if oldDiagPort > 0
    if oldDiagPort ~= 13
        error('S15R:OldDiagPort', ...
            'Existing S15 diagnostics on Group28 input%d, expected 13.',oldDiagPort);
    end
    localDisconnectLogInput(group28Mux,13);
end

localDeleteBlockIfExists(s15Diag);

if str2double(get_param(group28Mux,'Inputs')) == 13
    ph28 = get_param(group28Mux,'PortHandles');
    if ~isequal(get_param(ph28.Inport(13),'Line'),-1)
        error('S15R:Group28RepairBusy','Group28 input13 still connected.');
    end
    set_param(group28Mux,'Inputs','12');
end

% 4c. Delete S15 stack publishers/managers/routers.
cleanupStackNames = {
    'GOTO_S15_FINAL_MODE'
    'GOTO_S15_FINAL_BREAKER_REQ'
    'GOTO_S15_CLEAR_ISLAND'
    'GOTO_S15_REC_STATE'
    'GOTO_S15_REC_ACTIVE'
    'GOTO_S15_SYNC_OK'
    'GOTO_S15_DV_PU'
    'GOTO_S15_DF_HZ'
    'GOTO_S15_DTHETA_DEG'
    'GOTO_S15_SYNC_TIMER'
    'GOTO_S15_RECLOSE_TIMER'
    'GOTO_S15_RECLOSE_CMD'
    'GOTO_S15_FREF_TRIM'
    'GOTO_S15_REC_ROUTE_VALID'
    'GOTO_S15_SELECTED_MASTER'
    'GOTO_S15_FINAL_FREF_ESS1'
    'GOTO_S15_FINAL_FREF_ESS2'
    'GOTO_S15_LEGACY_FREF_ECHO'
    'GOTO_S15_FREF_ROUTE_VALID'
};

for i = 1:numel(cleanupStackNames)
    localDeleteBlockIfExists([stack '/' cleanupStackNames{i}]);
end

localDeleteBlockIfExists(frefRouter);
localDeleteBlockIfExists(recoveryMgr);

% 4d. Remove measurement taps/publishers.
cleanupTopNames = {
    'AA15_S15_GRID_FREQ_GOTO'
    'AA15_S15_GRID_V_GOTO'
    'AA15_S15_PCC_FREQ_GOTO'
    'AA15_S15_PCC_V_GOTO'
    'AA15_S15_GRID_PHASE_GOTO'
    'AA15_S15_PCC_PHASE_GOTO'
    'AA15_S15_PHASE_VALID_GOTO'
    'AA15_S15_LEGACY_FREF_GOTO'
    'AA15_S15_SYNC_PHASE_ESTIMATOR'
};

for i = 1:numel(cleanupTopNames)
    localDeleteBlockIfExists([sm '/' cleanupTopNames{i}]);
end

% 4e. Restore S13 publishers to original final tags if this was a partial run.
s13GotoMode = [stack '/GOTO_S13_EXEC_01'];
s13GotoBreak = [stack '/GOTO_S13_EXEC_02'];

if getSimulinkBlockHandle(s13GotoMode) < 0 || getSimulinkBlockHandle(s13GotoBreak) < 0
    error('S15R:S13GotoMissing','Missing S13 execution publishers.');
end

% No S15 final publisher exists now, so original tags are safe to restore.
set_param(s13GotoMode,'GotoTag','AA15_EXECUTED_SYSTEM_MODE','TagVisibility','global');
set_param(s13GotoBreak,'GotoTag','AA15_PCC_BREAKER_REQUEST_CLOSE','TagVisibility','global');

fprintf('[OK] Partial S15 artifacts repaired to S14-facing behavior.\n');

% =========================================================================
% 5. Create S15 parameters.
% =========================================================================
fprintf('\n--- Create/verify S15 recovery parameters ---\n');

defs = {
'CFG15_S15_RECOVERY_REQUEST',        '0';
'CFG15_S15_SYNC_DV_MAX_PU',          '0.10';
'CFG15_S15_SYNC_DF_MAX_HZ',          '0.20';
'CFG15_S15_SYNC_DTHETA_MAX_DEG',     '10';
'CFG15_S15_SYNC_STABLE_S',           '0.50';
'CFG15_S15_RECLOSE_HOLD_S',          '0.20';
'CFG15_S15_FREF_KTHETA_HZ_PER_DEG',  '0.005';
'CFG15_S15_FREF_KDF',                 '0.50';
'CFG15_S15_FREF_TRIM_MAX_HZ',        '0.20';
};

for i = 1:size(defs,1)
    tag = defs{i,1};
    val = defs{i,2};

    c = [panel '/' tag];
    g = [panel '/GOTO_' tag];

    localAssertNoForeignGotoTag(mdl,tag,g);

    if getSimulinkBlockHandle(c) < 0
        [px,py] = localFindFreePosition(panel,310,38,45);
        add_block('simulink/Sources/Constant',c, ...
            'Value',val, ...
            'SampleTime','inf', ...
            'OutDataTypeStr','double', ...
            'Position',[px py px+280 py+25]);
    else
        if ~strcmp(get_param(c,'BlockType'),'Constant')
            error('S15R:ParamType','%s exists but is not Constant.',c);
        end
        set_param(c,'SampleTime','inf');
    end

    if getSimulinkBlockHandle(g) < 0
        pos = get_param(c,'Position');
        add_block('simulink/Signal Routing/Goto',g, ...
            'GotoTag',tag, ...
            'TagVisibility','global', ...
            'Position',[pos(3)+35 pos(2) pos(3)+300 pos(2)+24]);
    else
        set_param(g,'GotoTag',tag,'TagVisibility','global');
    end

    localForceOwnedLine(panel,[tag '/1'],['GOTO_' tag '/1']);
end

% Safe saved recovery request default.
set_param([panel '/CFG15_S15_RECOVERY_REQUEST'],'Value','0');

% =========================================================================
% 6. Publish Grid/PCC F/V and build a LIBRARY-SAFE matched phase estimator.
% =========================================================================
fprintf('\n--- Publish sync signals using top-level branches only ---\n');

% 6a. Top-level Grid/PCC Freq/Vab_rms taps.
tapDefs = {
    [sm '/AA15_S15_GRID_FREQ_GOTO'], 'AA15_S15_GRID_FREQ_HZ', gridPH.Outport(1);
    [sm '/AA15_S15_GRID_V_GOTO'],    'AA15_S15_GRID_VAB_RMS', gridPH.Outport(4);
    [sm '/AA15_S15_PCC_FREQ_GOTO'],  'AA15_S15_PCC_FREQ_HZ',  pccPH.Outport(1);
    [sm '/AA15_S15_PCC_V_GOTO'],     'AA15_S15_PCC_VAB_RMS',  pccPH.Outport(4);
};

for i = 1:size(tapDefs,1)
    p = tapDefs{i,1};
    tag = tapDefs{i,2};
    srcPort = tapDefs{i,3};

    localAssertNoForeignGotoTag(mdl,tag,p);

    [tx,ty] = localFindFreePosition(sm,270,28,35);
    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',tag, ...
        'TagVisibility','global', ...
        'Position',[tx ty tx+250 ty+22]);

    tph = get_param(p,'PortHandles');
    localEnsureTopLevelSourceConnection(sm,srcPort,tph.Inport(1),tag);
end

% 6b. Do NOT modify J2_Grid_Measurements or J2_PCC_Measurements internals.
% They are linked-library blocks. Branch their EXISTING Vabc sources at
% SM_Master level into a new local estimator instead.
phaseEstimator = [sm '/AA15_S15_SYNC_PHASE_ESTIMATOR'];

[px,py] = localFindFreePosition(sm,520,250,45);
add_block('simulink/Ports & Subsystems/Subsystem',phaseEstimator, ...
    'Position',[px py px+520 py+250]);
localDeleteSubsystemContents(phaseEstimator);

add_block('simulink/Ports & Subsystems/In1', ...
    [phaseEstimator '/grid_vabc'], ...
    'Port','1', ...
    'Position',[20 55 50 71]);

add_block('simulink/Ports & Subsystems/In1', ...
    [phaseEstimator '/pcc_vabc'], ...
    'Port','2', ...
    'Position',[20 135 50 151]);

% One-sample delay explicitly prevents a direct same-step
% phase -> Fref -> plant -> phase feedback path.
add_block('simulink/Discrete/Unit Delay', ...
    [phaseEstimator '/GRID_VABC_Z1'], ...
    'InitialCondition','[0 0 0]', ...
    'SampleTime','1e-4', ...
    'Position',[90 45 150 80]);

add_block('simulink/Discrete/Unit Delay', ...
    [phaseEstimator '/PCC_VABC_Z1'], ...
    'InitialCondition','[0 0 0]', ...
    'SampleTime','1e-4', ...
    'Position',[90 125 150 160]);

add_block('simulink/Signal Routing/Demux', ...
    [phaseEstimator '/GRID_DEMUX3'], ...
    'Outputs','3', ...
    'Position',[195 35 225 90]);

add_block('simulink/Signal Routing/Demux', ...
    [phaseEstimator '/PCC_DEMUX3'], ...
    'Outputs','3', ...
    'Position',[195 115 225 170]);

phaseMF = [phaseEstimator '/AA15_S15_Phase_From_Vabc_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',phaseMF, ...
    'Position',[285 55 610 185]);

phaseChart = localGetEMChartByPath(phaseMF);
phaseChart.Script = localPhaseEstimatorScript();

add_block('simulink/Ports & Subsystems/Out1', ...
    [phaseEstimator '/grid_phase_deg'], ...
    'Port','1', ...
    'Position',[670 65 700 81]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [phaseEstimator '/pcc_phase_deg'], ...
    'Port','2', ...
    'Position',[670 115 700 131]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [phaseEstimator '/phase_valid'], ...
    'Port','3', ...
    'Position',[670 165 700 181]);

localEnsureLine(phaseEstimator,'grid_vabc/1','GRID_VABC_Z1/1');
localEnsureLine(phaseEstimator,'pcc_vabc/1','PCC_VABC_Z1/1');
localEnsureLine(phaseEstimator,'GRID_VABC_Z1/1','GRID_DEMUX3/1');
localEnsureLine(phaseEstimator,'PCC_VABC_Z1/1','PCC_DEMUX3/1');

for k = 1:3
    localEnsureLine(phaseEstimator, ...
        sprintf('GRID_DEMUX3/%d',k), ...
        sprintf('AA15_S15_Phase_From_Vabc_Core/%d',k));
end
for k = 1:3
    localEnsureLine(phaseEstimator, ...
        sprintf('PCC_DEMUX3/%d',k), ...
        sprintf('AA15_S15_Phase_From_Vabc_Core/%d',k+3));
end

localEnsureLine(phaseEstimator, ...
    'AA15_S15_Phase_From_Vabc_Core/1','grid_phase_deg/1');
localEnsureLine(phaseEstimator, ...
    'AA15_S15_Phase_From_Vabc_Core/2','pcc_phase_deg/1');
localEnsureLine(phaseEstimator, ...
    'AA15_S15_Phase_From_Vabc_Core/3','phase_valid/1');

% Top-level physical branches: existing source -> J2 measurement remains
% untouched, and an additional branch feeds the S15 estimator.
estPH = get_param(phaseEstimator,'PortHandles');
localEnsureTopLevelSourceConnection(sm, ...
    gridVabcSrcPort,estPH.Inport(1),'Grid Vabc -> S15 phase estimator');
localEnsureTopLevelSourceConnection(sm, ...
    pccVabcSrcPort,estPH.Inport(2),'PCC Vabc -> S15 phase estimator');

phaseTapDefs = {
    [sm '/AA15_S15_GRID_PHASE_GOTO'], 'AA15_S15_GRID_PHASE_DEG', 1;
    [sm '/AA15_S15_PCC_PHASE_GOTO'],  'AA15_S15_PCC_PHASE_DEG',  2;
    [sm '/AA15_S15_PHASE_VALID_GOTO'], 'AA15_S15_PHASE_VALID',    3;
};

estPH = get_param(phaseEstimator,'PortHandles');
for i = 1:size(phaseTapDefs,1)
    p = phaseTapDefs{i,1};
    tag = phaseTapDefs{i,2};
    outIdx = phaseTapDefs{i,3};

    localAssertNoForeignGotoTag(mdl,tag,p);
    [gx,gy] = localFindFreePosition(sm,270,28,35);

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',tag, ...
        'TagVisibility','global', ...
        'Position',[gx gy gx+250 gy+22]);

    gph = get_param(p,'PortHandles');
    localEnsureTopLevelSourceConnection(sm, ...
        estPH.Outport(outIdx),gph.Inport(1),tag);
end

% 6c. Legacy Supervisor Fref global tap.
legacyFrefGoto = [sm '/K1B_Fref_Sup_Goto'];
lfgPH = get_param(legacyFrefGoto,'PortHandles');
legacyFrefSrc = localGetLineSourcePort(lfgPH.Inport(1));

legacyFrefTap = [sm '/AA15_S15_LEGACY_FREF_GOTO'];
legacyFrefTag = 'AA15_S15_LEGACY_FREF_SUP';

localAssertNoForeignGotoTag(mdl,legacyFrefTag,legacyFrefTap);

[fx,fy] = localFindFreePosition(sm,280,30,35);
add_block('simulink/Signal Routing/Goto',legacyFrefTap, ...
    'GotoTag',legacyFrefTag, ...
    'TagVisibility','global', ...
    'Position',[fx fy fx+260 fy+22]);

lfPH = get_param(legacyFrefTap,'PortHandles');
localEnsureTopLevelSourceConnection(sm,legacyFrefSrc,lfPH.Inport(1),legacyFrefTag);

% =========================================================================
% 7. Extend S13 execution manager with delayed S15 clear-island input.
% =========================================================================
fprintf('\n--- Extend S13 latch manager with recovery-clear input ---\n');

execMgr = [stack '/AA15_Grid_Mode_Execution_Manager'];
execMF = [execMgr '/AA15_Grid_Mode_Execution_Core'];
execChart = localGetEMChartByPath(execMF);

fromClear = [execMgr '/FROM_EXEC_14'];
delayClear = [execMgr '/DYN_Z1_14'];

if getSimulinkBlockHandle(fromClear) < 0
    add_block('simulink/Signal Routing/From',fromClear, ...
        'GotoTag','AA15_S15_CLEAR_ISLAND_LATCH', ...
        'Position',[565 455 815 475]);
else
    set_param(fromClear,'GotoTag','AA15_S15_CLEAR_ISLAND_LATCH');
end

if getSimulinkBlockHandle(delayClear) < 0
    add_block('simulink/Discrete/Unit Delay',delayClear, ...
        'InitialCondition','0', ...
        'SampleTime','1e-4', ...
        'Position',[845 450 900 478]);
end

localForceOwnedLine(execMgr,'FROM_EXEC_14/1','DYN_Z1_14/1');

execChart.Script = localS13ExecutionCoreWithRecoveryClear();

% Core gets input16 from delayed clear.
localForceOwnedLine(execMgr,'DYN_Z1_14/1','AA15_Grid_Mode_Execution_Core/16');

% =========================================================================
% 8. Build S15 Recovery Manager with explicit Unit Delay states.
% =========================================================================
fprintf('\n--- Build AA15_S15_Recovery_Manager ---\n');

xRec = localNextRightX(stack,150);
add_block('simulink/Ports & Subsystems/Subsystem',recoveryMgr, ...
    'Position',[xRec 4200 xRec+790 5010]);
localDeleteSubsystemContents(recoveryMgr);

recInputTags = {
    'AA15_S13_EXECUTED_SYSTEM_MODE_RAW'       % 1
    'AA15_S13_BREAKER_REQUEST_CLOSE_RAW'      % 2
    'AA15_PCC_ISLAND_LATCH'                   % 3
    'AA15_PCC_BLACKSTART_LATCH'               % 4
    'AA15_S15_GRID_FREQ_HZ'                   % 5
    'AA15_S15_PCC_FREQ_HZ'                    % 6
    'AA15_S15_GRID_VAB_RMS'                   % 7
    'AA15_S15_PCC_VAB_RMS'                    % 8
    'AA15_S15_GRID_PHASE_DEG'                 % 9
    'AA15_S15_PCC_PHASE_DEG'                  % 10
    'CFG15_S15_RECOVERY_REQUEST'              % 11
    'CFG15_MASTER_ENABLE'                     % 12
    'CFG15_CONTROL_SOURCE'                    % 13
    'CFG15_EXEC_S15'                          % 14
    'CFG15_MODE_ACTUATION_ENABLE'             % 15
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'      % 16
    'CFG15_ISLAND_MASTER'                     % 17
    'CFG15_S15_SYNC_DV_MAX_PU'                % 18
    'CFG15_S15_SYNC_DF_MAX_HZ'                % 19
    'CFG15_S15_SYNC_DTHETA_MAX_DEG'           % 20
    'CFG15_S15_SYNC_STABLE_S'                 % 21
    'CFG15_S15_RECLOSE_HOLD_S'                % 22
    'CFG15_S15_FREF_KTHETA_HZ_PER_DEG'        % 23
    'CFG15_S15_FREF_KDF'                      % 24
    'CFG15_S15_FREF_TRIM_MAX_HZ'              % 25
    'AA15_PCC_EXECUTION_ROUTE_VALID'           % 26
    'AA15_S15_PHASE_VALID'                     % 27
};

for i = 1:27
    col = floor((i-1)/9);
    row = mod(i-1,9);
    x = 20 + col*255;
    y = 25 + row*55;

    add_block('simulink/Signal Routing/From', ...
        [recoveryMgr '/' sprintf('FROM_REC_%02d',i)], ...
        'GotoTag',recInputTags{i}, ...
        'Position',[x y x+230 y+20]);
end

% Explicit state/timer delays.
stateBlocks = {
    'RECOVERY_STATE_Z1','0',[790 535 860 565];
    'SYNC_TIMER_Z1','0',[790 590 860 620];
    'RECLOSE_TIMER_Z1','0',[790 645 860 675];
};

for i = 1:size(stateBlocks,1)
    add_block('simulink/Discrete/Unit Delay', ...
        [recoveryMgr '/' stateBlocks{i,1}], ...
        'InitialCondition',stateBlocks{i,2}, ...
        'SampleTime','1e-4', ...
        'Position',stateBlocks{i,3});
end

recMF = [recoveryMgr '/AA15_S15_Recovery_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',recMF, ...
    'Position',[930 115 1515 720]);

recChart = localGetEMChartByPath(recMF);
recChart.Script = localRecoveryCoreScript();

% Inputs1..26 from Froms.
for i = 1:26
    localEnsureLine(recoveryMgr, ...
        sprintf('FROM_REC_%02d/1',i), ...
        sprintf('AA15_S15_Recovery_Core/%d',i));
end

% State inputs28..30.
localEnsureLine(recoveryMgr,'RECOVERY_STATE_Z1/1','AA15_S15_Recovery_Core/28');
localEnsureLine(recoveryMgr,'SYNC_TIMER_Z1/1','AA15_S15_Recovery_Core/29');
localEnsureLine(recoveryMgr,'RECLOSE_TIMER_Z1/1','AA15_S15_Recovery_Core/30');

% Core outputs4..6 update explicit state.
localEnsureLine(recoveryMgr,'AA15_S15_Recovery_Core/4','RECOVERY_STATE_Z1/1');
localEnsureLine(recoveryMgr,'AA15_S15_Recovery_Core/5','SYNC_TIMER_Z1/1');
localEnsureLine(recoveryMgr,'AA15_S15_Recovery_Core/6','RECLOSE_TIMER_Z1/1');

recOutNames = {
    'final_mode'              % 1
    'final_breaker_request'   % 2
    'clear_island_request'    % 3
    'state_next'              % 4
    'sync_timer_next'         % 5
    'reclose_timer_next'      % 6
    'recovery_state_echo'     % 7
    'sync_timer_echo'         % 8
    'reclose_timer_echo'      % 9
    'sync_ok'                 % 10
    'delta_v_pu'              % 11
    'delta_f_hz'              % 12
    'delta_theta_deg'         % 13
    'fref_trim_hz'            % 14
    'recovery_active'         % 15
    'reclose_commanded'       % 16
    'route_valid'             % 17
    'selected_master_echo'    % 18
};

for i = 1:18
    y = 35 + (i-1)*38;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [recoveryMgr '/' recOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1615 y 1645 y+16]);
    localEnsureLine(recoveryMgr, ...
        sprintf('AA15_S15_Recovery_Core/%d',i), ...
        [recOutNames{i} '/1']);
end

% =========================================================================
% 9. Retag S13 outputs RAW, publish S15 final mode/breaker and recovery tags.
% =========================================================================
fprintf('\n--- Insert S15 between S13 raw state and downstream final state ---\n');

% Retag S13 existing Gotos to RAW names.
set_param(s13GotoMode, ...
    'GotoTag','AA15_S13_EXECUTED_SYSTEM_MODE_RAW', ...
    'TagVisibility','global');
set_param(s13GotoBreak, ...
    'GotoTag','AA15_S13_BREAKER_REQUEST_CLOSE_RAW', ...
    'TagVisibility','global');

recTags = {
    'AA15_EXECUTED_SYSTEM_MODE'        % out1
    'AA15_PCC_BREAKER_REQUEST_CLOSE'   % out2
    'AA15_S15_CLEAR_ISLAND_LATCH'      % out3
    'AA15_S15_RECOVERY_STATE'          % out7
    'AA15_S15_SYNC_TIMER_S'            % out8
    'AA15_S15_RECLOSE_TIMER_S'         % out9
    'AA15_S15_SYNC_OK'                 % out10
    'AA15_S15_DV_PU'                   % out11
    'AA15_S15_DF_HZ'                   % out12
    'AA15_S15_DTHETA_DEG'              % out13
    'AA15_S15_FREF_TRIM_HZ'            % out14
    'AA15_S15_RECOVERY_ACTIVE'         % out15
    'AA15_S15_RECLOSE_COMMANDED'       % out16
    'AA15_S15_RECOVERY_ROUTE_VALID'    % out17
    'AA15_S15_SELECTED_MASTER'         % out18
};

recOutIdx = [1 2 3 7 8 9 10 11 12 13 14 15 16 17 18];
recGotoNames = {
    'GOTO_S15_FINAL_MODE'
    'GOTO_S15_FINAL_BREAKER_REQ'
    'GOTO_S15_CLEAR_ISLAND'
    'GOTO_S15_REC_STATE'
    'GOTO_S15_SYNC_TIMER'
    'GOTO_S15_RECLOSE_TIMER'
    'GOTO_S15_SYNC_OK'
    'GOTO_S15_DV_PU'
    'GOTO_S15_DF_HZ'
    'GOTO_S15_DTHETA_DEG'
    'GOTO_S15_FREF_TRIM'
    'GOTO_S15_REC_ACTIVE'
    'GOTO_S15_RECLOSE_CMD'
    'GOTO_S15_REC_ROUTE_VALID'
    'GOTO_S15_SELECTED_MASTER'
};

recPos = get_param(recoveryMgr,'Position');

for i = 1:numel(recTags)
    p = [stack '/' recGotoNames{i}];
    localAssertNoForeignGotoTag(mdl,recTags{i},p);

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',recTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/8);
    row = mod(i-1,8);
    x = recPos(3)+45+col*285;
    y = recPos(2)+25+row*50;
    set_param(p,'Position',[x y x+260 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_S15_Recovery_Manager/%d',recOutIdx(i)), ...
        [recGotoNames{i} '/1']);
end

% =========================================================================
% 10. Build selected-master Fref trim router and real ESS Fref takeover.
% =========================================================================
fprintf('\n--- Build S15 selected-master Fref trim router ---\n');

xFr = localNextRightX(stack,150);
add_block('simulink/Ports & Subsystems/Subsystem',frefRouter, ...
    'Position',[xFr 4230 xFr+560 4620]);
localDeleteSubsystemContents(frefRouter);

frefInputTags = {
    'AA15_S15_LEGACY_FREF_SUP'
    'AA15_S15_FREF_TRIM_HZ'
    'AA15_S15_RECOVERY_ACTIVE'
    'AA15_S15_SELECTED_MASTER'
    'AA15_S15_RECOVERY_ROUTE_VALID'
};

for i = 1:5
    y = 35 + (i-1)*55;
    add_block('simulink/Signal Routing/From', ...
        [frefRouter '/' sprintf('FROM_FREF_%02d',i)], ...
        'GotoTag',frefInputTags{i}, ...
        'Position',[20 y 245 y+20]);
end

frMF = [frefRouter '/AA15_S15_Master_Fref_Router_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',frMF, ...
    'Position',[310 75 710 310]);

frChart = localGetEMChartByPath(frMF);
frChart.Script = localFrefRouterScript();

frOutNames = {'fref_ess1','fref_ess2','legacy_echo','route_valid'};
for i = 1:4
    y = 55 + (i-1)*60;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [frefRouter '/' frOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[790 y 820 y+16]);
end

for i = 1:5
    localEnsureLine(frefRouter, ...
        sprintf('FROM_FREF_%02d/1',i), ...
        sprintf('AA15_S15_Master_Fref_Router_Core/%d',i));
end

for i = 1:4
    localEnsureLine(frefRouter, ...
        sprintf('AA15_S15_Master_Fref_Router_Core/%d',i), ...
        [frOutNames{i} '/1']);
end

frTags = {
    'AA15_S15_FINAL_FREF_ESS1'
    'AA15_S15_FINAL_FREF_ESS2'
    'AA15_S15_LEGACY_FREF_ECHO'
    'AA15_S15_FREF_ROUTE_VALID'
};

frGotoNames = {
    'GOTO_S15_FINAL_FREF_ESS1'
    'GOTO_S15_FINAL_FREF_ESS2'
    'GOTO_S15_LEGACY_FREF_ECHO'
    'GOTO_S15_FREF_ROUTE_VALID'
};

frPos = get_param(frefRouter,'Position');
for i = 1:4
    p = [stack '/' frGotoNames{i}];
    localAssertNoForeignGotoTag(mdl,frTags{i},p);

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',frTags{i}, ...
        'TagVisibility','global', ...
        'Position',[frPos(3)+45 frPos(2)+35+(i-1)*55 ...
                    frPos(3)+300 frPos(2)+57+(i-1)*55]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_S15_Master_Fref_Router/%d',i), ...
        [frGotoNames{i} '/1']);
end

% Real physical ESS Fref reroute.
for i = 1:2
    finalFrom = [sm '/' sprintf('AA15_S15_FINAL_FREF_ESS%d_TO_MUX',i)];
    tag = sprintf('AA15_S15_FINAL_FREF_ESS%d',i);
    mpos = get_param(essMux{i},'Position');

    add_block('simulink/Signal Routing/From',finalFrom, ...
        'GotoTag',tag, ...
        'Position',[max(20,mpos(1)-285) mpos(2)+50 ...
                    max(20,mpos(1)-55) mpos(2)+72]);

    fph = get_param(finalFrom,'PortHandles');
    mph = get_param(essMux{i},'PortHandles');

    localForcePortConnection(sm,fph.Outport(1),mph.Inport(3), ...
        sprintf('S15 final Fref -> ESS%d input3',i));
end

% =========================================================================
% 11. Build S15 diag31 before first update.
% =========================================================================
fprintf('\n--- Build S15 recovery diag31 ---\n');

[dx,dy] = localFindFreePosition(sm,590,650,450);
add_block('simulink/Ports & Subsystems/Subsystem',s15Diag, ...
    'Position',[dx dy dx+590 dy+650]);
localDeleteSubsystemContents(s15Diag);

diagTags = {
    'CFG15_S15_RECOVERY_REQUEST'              % 262
    'AA15_S13_EXECUTED_SYSTEM_MODE_RAW'       % 263
    'AA15_EXECUTED_SYSTEM_MODE'               % 264
    'AA15_S13_BREAKER_REQUEST_CLOSE_RAW'      % 265
    'AA15_PCC_BREAKER_REQUEST_CLOSE'          % 266
    'AA15_S15_RECOVERY_STATE'                 % 267
    'AA15_S15_RECOVERY_ACTIVE'                % 268
    'AA15_S15_SYNC_OK'                        % 269
    'AA15_S15_GRID_FREQ_HZ'                   % 270
    'AA15_S15_PCC_FREQ_HZ'                    % 271
    'AA15_S15_DF_HZ'                          % 272
    'AA15_S15_GRID_VAB_RMS'                   % 273
    'AA15_S15_PCC_VAB_RMS'                    % 274
    'AA15_S15_DV_PU'                          % 275
    'AA15_S15_GRID_PHASE_DEG'                 % 276
    'AA15_S15_PCC_PHASE_DEG'                  % 277
    'AA15_S15_DTHETA_DEG'                     % 278
    'AA15_S15_SYNC_TIMER_S'                   % 279
    'AA15_S15_RECLOSE_TIMER_S'                % 280
    'AA15_S15_RECLOSE_COMMANDED'              % 281
    'AA15_S15_CLEAR_ISLAND_LATCH'             % 282
    'AA15_PCC_ISLAND_LATCH'                   % 283
    'AA15_PCC_BLACKSTART_LATCH'               % 284
    'AA15_S15_LEGACY_FREF_ECHO'               % 285
    'AA15_S15_FREF_TRIM_HZ'                   % 286
    'AA15_S15_FINAL_FREF_ESS1'                % 287
    'AA15_S15_FINAL_FREF_ESS2'                % 288
    'CFG15_ISLAND_MASTER'                     % 289
    'CFG15_MODE_ACTUATION_ENABLE'             % 290
    'CFG15_PCC_BREAKER_ACTUATION_ENABLE'      % 291
    'AA15_S15_RECOVERY_ROUTE_VALID'           % 292
};

for i = 1:31
    col = floor((i-1)/16);
    row = mod(i-1,16);
    x = 20 + col*265;
    y = 18 + row*35;

    add_block('simulink/Signal Routing/From', ...
        [s15Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+240 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s15Diag '/AA15_STAGE15_DIAG31'], ...
    'Inputs','31', ...
    'Position',[600 30 635 610]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s15Diag '/diag31'], ...
    'Port','1', ...
    'Position',[700 320 730 336]);

for i = 1:31
    localEnsureLine(s15Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE15_DIAG31/%d',i));
end

localEnsureLine(s15Diag,'AA15_STAGE15_DIAG31/1','diag31/1');

% =========================================================================
% 12. First model update only after complete S15 structure exists.
% =========================================================================
fprintf('\n--- First complete-structure model update ---\n');

set_param(mdl,'SimulationCommand','update');

execPorts = get_param(execMF,'Ports');
if execPorts(1) ~= 16 || execPorts(2) ~= 10
    error('S15R:S13Ports', ...
        'S13 core expected 16-in/10-out after recovery-clear extension, found %d/%d.', ...
        execPorts(1),execPorts(2));
end

recPorts = get_param(recMF,'Ports');
if recPorts(1) ~= 30 || recPorts(2) ~= 18
    error('S15R:RecoveryPorts', ...
        'S15 recovery core expected 30-in/18-out, found %d/%d.', ...
        recPorts(1),recPorts(2));
end

frPorts = get_param(frMF,'Ports');
if frPorts(1) ~= 5 || frPorts(2) ~= 4
    error('S15R:FrefPorts', ...
        'S15 Fref router expected 5-in/4-out, found %d/%d.', ...
        frPorts(1),frPorts(2));
end

fprintf('[PASS] Complete S15 structure updates with no algebraic-loop error.\n');

% =========================================================================
% 13. Append S15 diag31 to Group28 input13.
% =========================================================================
fprintf('\n--- Append S15 diag31 to Group28 input13 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 12
    error('S15R:Group28BeforeAppend','Expected Group28 Inputs=12 before append.');
end

set_param(group28Mux,'Inputs','13');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s15Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(13), ...
    'S15 diag31 -> Group28 input13');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 14. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S15 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 13
    error('S15R:Group28Final','Group28 must have 13 inputs.');
end

for i = 1:12
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S15R:OldDiagMoved', ...
            '%s moved from input%d to input%d.',diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s15Diag,group28Mux) ~= 13
    error('S15R:S15DiagSlot','S15 diagnostics is not Group28 input13.');
end

% S13 must publish RAW tags.
if ~strcmp(get_param(s13GotoMode,'GotoTag'),'AA15_S13_EXECUTED_SYSTEM_MODE_RAW')
    error('S15R:S13RawMode','S13 mode publisher is not RAW.');
end
if ~strcmp(get_param(s13GotoBreak,'GotoTag'),'AA15_S13_BREAKER_REQUEST_CLOSE_RAW')
    error('S15R:S13RawBreaker','S13 breaker publisher is not RAW.');
end

% Exactly one final publisher for original downstream tags.
localAssertSingleGlobalGoto(mdl,'AA15_EXECUTED_SYSTEM_MODE');
localAssertSingleGlobalGoto(mdl,'AA15_PCC_BREAKER_REQUEST_CLOSE');
localAssertSingleGlobalGoto(mdl,'AA15_S15_CLEAR_ISLAND_LATCH');

% ESS physical routes.
for i = 1:2
    ph = get_param(essMux{i},'PortHandles');

    [f3,~] = localGetDestinationSource(ph.Inport(3));
    [f4,~] = localGetDestinationSource(ph.Inport(4));
    [f5,~] = localGetDestinationSource(ph.Inport(5));
    [f6,~] = localGetDestinationSource(ph.Inport(6));
    [f7,~] = localGetDestinationSource(ph.Inport(7));
    [f8,~] = localGetDestinationSource(ph.Inport(8));

    expectedF3 = [sm '/' sprintf('AA15_S15_FINAL_FREF_ESS%d_TO_MUX',i)];

    if ~strcmp(f3,expectedF3)
        error('S15R:FrefFinal','ESS%d Fref is not S15 final route.',i);
    end
    if ~strcmp(f4,protectVref{i})
        error('S15R:VrefChanged','ESS%d Vref route changed.',i);
    end
    if ~strcmp(f5,protectDroop{i})
        error('S15R:DroopChanged','ESS%d Droop route changed.',i);
    end
    if ~strcmp(f6,protectPref{i})
        error('S15R:PrefChanged','ESS%d Pref route changed.',i);
    end
    if ~strcmp(f7,protectQref{i})
        error('S15R:QrefChanged','ESS%d Qref route changed.',i);
    end
    if ~strcmp(f8,protectGrid{i})
        error('S15R:GridChanged','ESS%d GridOn route changed.',i);
    end
end

% Breaker final physical route stays S13 final From -> Router output tag.
bph = get_param(breaker,'PortHandles');
[bFinal,~] = localGetDestinationSource(bph.Inport(1));
if ~strcmp(bFinal,[sm '/AA15_S13_FINAL_BREAKER_TO_PCC'])
    error('S15R:BreakerChanged','PCC breaker physical source changed.');
end

% Original 15-strategy algorithm untouched.
origStrategy = [sm '/Advanced_Microgrid_15_Strategies'];
if getSimulinkBlockHandle(origStrategy) < 0
    error('S15R:OriginalStrategyMissing','Original strategy block missing.');
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 S15 RECOVERY PATCH COMPLETE\n');
fprintf('============================================================\n');
fprintf('Original Strategy-15 algorithm      : UNCHANGED\n');
fprintf('Grid/PCC Freq measurements          : EXISTING sources reused\n');
fprintf('Grid/PCC voltage measurements       : EXISTING sources reused\n');
fprintf('Grid/PCC phase                      : top-level matched Vabc estimator, 100 us delayed\n');
fprintf('S13 island latch clear              : delayed 100 us input added\n');
fprintf('Recovery mode                       : 5 RESYNCHRONIZATION\n');
fprintf('Sync criteria                       : DeltaV / DeltaF / DeltaTheta\n');
fprintf('Master synchronization actuator     : selected ESS Fref trim only\n');
fprintf('Vref                                : UNCHANGED\n');
fprintf('PCC reclose                         : after stable sync window\n');
fprintf('Post-close action                   : clear S13 island latch\n');
fprintf('Final device-mode action            : selected ESS returns GFL\n');
fprintf('CFG15_S15_RECOVERY_REQUEST default  : 0\n');
fprintf('Group28 scalar signals              : 292\n');
fprintf('Expected MAT rows                   : 293 incl. Target Time\n');
fprintf('Backup                              : %s\n',backupFile);
fprintf('\nNEXT: RT-LAB Rebuild All is REQUIRED.\n');
fprintf('FIRST post-build run: recovery request=0 for transparent regression.\n');

end


% =========================================================================
% Matched three-phase Vabc phase estimator, degrees.
% Both Grid and PCC use the same transform, so DeltaTheta is consistent.
% =========================================================================
function txt = localPhaseEstimatorScript()

L = {};
L{end+1} = 'function [gdeg,pdeg,valid] = AA15_S15_Phase_From_Vabc_Core(ga,gb,gc,pa,pb,pc)';
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'galpha = (2.0/3.0)*(ga - 0.5*gb - 0.5*gc);';
L{end+1} = 'gbeta  = (2.0/3.0)*(0.8660254037844386*(gb-gc));';
L{end+1} = 'palpha = (2.0/3.0)*(pa - 0.5*pb - 0.5*pc);';
L{end+1} = 'pbeta  = (2.0/3.0)*(0.8660254037844386*(pb-pc));';
L{end+1} = '';
L{end+1} = 'gmag2 = galpha*galpha + gbeta*gbeta;';
L{end+1} = 'pmag2 = palpha*palpha + pbeta*pbeta;';
L{end+1} = '';
L{end+1} = 'gdeg = atan2(gbeta,galpha)*180.0/pi;';
L{end+1} = 'pdeg = atan2(pbeta,palpha)*180.0/pi;';
L{end+1} = 'valid = double(gmag2>1.0 && pmag2>1.0);';
L{end+1} = 'end';

txt = strjoin(L,newline);
end


% =========================================================================
% S13 core with delayed recovery-clear input16
% =========================================================================
function txt = localS13ExecutionCoreWithRecoveryClear()

L = {};
L{end+1} = ['function [exec_mode,request_close,armed,island_next,black_next,' ...
    'reclose_blocked,trip_reason,route_valid,raw_mode_echo,raw_reason_echo] = ' ...
    'AA15_Grid_Mode_Execution_Core(' ...
    'raw_mode_z1,raw_reason_z1,s5_exec_z1,s15_req_z1,s14_req_z1,' ...
    'electrical_bad_z1,comm_bad_z1,emergency_z1,' ...
    'master_enable,control_source,mode_act_enable,breaker_act_enable,' ...
    'mode_route_valid_z1,island_prev,black_prev,clear_island_z1)'];
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
L{end+1} = '   ~finite1(island_prev)||~finite1(black_prev)||...';
L{end+1} = '   ~finite1(clear_island_z1)';
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
L{end+1} = 'if armed < 0.5';
L{end+1} = '    island_next = 0.0;';
L{end+1} = '    black_next = 0.0;';
L{end+1} = '    request_close = 1.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% S15 recovery clear is only allowed for an island latch, never black start.';
L{end+1} = 'if clear_island_z1 > 0.5 && black_next < 0.5';
L{end+1} = '    island_next = 0.0;';
L{end+1} = '    exec_mode = 0.0;';
L{end+1} = '    request_close = 1.0;';
L{end+1} = '    reclose_blocked = 0.0;';
L{end+1} = '    trip_reason = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if s14_req_z1 > 0.5';
L{end+1} = '    black_next = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
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
% S15 recovery core
% =========================================================================
function txt = localRecoveryCoreScript()

L = {};
L{end+1} = ['function [final_mode,final_breaker,clear_island,' ...
    'state_next,sync_timer_next,reclose_timer_next,' ...
    'state_echo,sync_timer_echo,reclose_timer_echo,' ...
    'sync_ok,dv_pu,df_hz,dtheta_deg,fref_trim,' ...
    'recovery_active,reclose_commanded,route_valid,master_echo] = ' ...
    'AA15_S15_Recovery_Core(' ...
    'raw_mode,raw_breaker,island_latch,black_latch,' ...
    'grid_f,pcc_f,grid_v,pcc_v,grid_phase,pcc_phase,' ...
    'recovery_request,master_enable,control_source,exec_s15,' ...
    'mode_act_enable,breaker_act_enable,island_master,' ...
    'dv_max_pu,df_max_hz,dtheta_max_deg,stable_s,reclose_hold_s,' ...
    'ktheta,kdf,trim_max,exec_route_valid,phase_valid,' ...
    'state_prev,sync_timer_prev,reclose_timer_prev)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'Ts = 1e-4;';
L{end+1} = 'final_mode = raw_mode;';
L{end+1} = 'final_breaker = raw_breaker;';
L{end+1} = 'clear_island = 0.0;';
L{end+1} = 'state_next = max(min(round(state_prev),3.0),0.0);';
L{end+1} = 'sync_timer_next = max(sync_timer_prev,0.0);';
L{end+1} = 'reclose_timer_next = max(reclose_timer_prev,0.0);';
L{end+1} = 'state_echo = state_prev;';
L{end+1} = 'sync_timer_echo = sync_timer_prev;';
L{end+1} = 'reclose_timer_echo = reclose_timer_prev;';
L{end+1} = 'sync_ok = 0.0;';
L{end+1} = 'dv_pu = 1e6;';
L{end+1} = 'df_hz = 0.0;';
L{end+1} = 'dtheta_deg = 0.0;';
L{end+1} = 'fref_trim = 0.0;';
L{end+1} = 'recovery_active = 0.0;';
L{end+1} = 'reclose_commanded = 0.0;';
L{end+1} = 'route_valid = 1.0;';
L{end+1} = 'master_echo = island_master;';
L{end+1} = '';
L{end+1} = 'allfinite = finite1(raw_mode)&&finite1(raw_breaker)&&...';
L{end+1} = '    finite1(island_latch)&&finite1(black_latch)&&...';
L{end+1} = '    finite1(grid_f)&&finite1(pcc_f)&&finite1(grid_v)&&finite1(pcc_v)&&...';
L{end+1} = '    finite1(grid_phase)&&finite1(pcc_phase)&&...';
L{end+1} = '    finite1(recovery_request)&&finite1(island_master)&&finite1(phase_valid)&&...';
L{end+1} = '    finite1(state_prev)&&finite1(sync_timer_prev)&&finite1(reclose_timer_prev);';
L{end+1} = '';
L{end+1} = 'if ~allfinite';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    state_next = 0.0;';
L{end+1} = '    sync_timer_next = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'm = round(island_master);';
L{end+1} = 'if m~=1 && m~=2';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    state_next = 0.0;';
L{end+1} = '    sync_timer_next = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'df_hz = grid_f - pcc_f;';
L{end+1} = 'dv_pu = abs(pcc_v-grid_v)/max(abs(grid_v),1.0);';
L{end+1} = 'dtheta_deg = wrap180(grid_phase-pcc_phase);';
L{end+1} = '';
L{end+1} = 'grid_valid = (grid_v>1.0) && (grid_f>45.0) && (grid_f<55.0);';
L{end+1} = 'pcc_valid = (pcc_v>1.0) && (pcc_f>45.0) && (pcc_f<55.0);';
L{end+1} = '';
L{end+1} = 'sync_ok = double(phase_valid>0.5 && grid_valid && pcc_valid && ...';
L{end+1} = '    dv_pu <= max(dv_max_pu,0.0) && ...';
L{end+1} = '    abs(df_hz) <= max(df_max_hz,0.0) && ...';
L{end+1} = '    abs(dtheta_deg) <= max(dtheta_max_deg,0.0));';
L{end+1} = '';
L{end+1} = 'trim_lim = abs(trim_max);';
L{end+1} = 'fref_trim = clamp1(ktheta*dtheta_deg + kdf*df_hz,-trim_lim,trim_lim);';
L{end+1} = '';
L{end+1} = 'armed = (master_enable>0.5) && (round(control_source)==1) && ...';
L{end+1} = '        (exec_s15>0.5) && (mode_act_enable>0.5) && ...';
L{end+1} = '        (breaker_act_enable>0.5) && (exec_route_valid>0.5) && ...';
L{end+1} = '        (black_latch<0.5);';
L{end+1} = '';
L{end+1} = 'if ~armed';
L{end+1} = '    state_next = 0.0;';
L{end+1} = '    sync_timer_next = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = '    fref_trim = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'st = round(state_prev);';
L{end+1} = '';
L{end+1} = 'if st==0';
L{end+1} = '    sync_timer_next = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = '    fref_trim = 0.0;';
L{end+1} = '    if island_latch>0.5 && recovery_request>0.5';
L{end+1} = '        state_next = 1.0;';
L{end+1} = '        final_mode = 5.0;';
L{end+1} = '        final_breaker = 0.0;';
L{end+1} = '        recovery_active = 1.0;';
L{end+1} = '        fref_trim = clamp1(ktheta*dtheta_deg + kdf*df_hz,-trim_lim,trim_lim);';
L{end+1} = '    end';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if st==1';
L{end+1} = '    recovery_active = 1.0;';
L{end+1} = '    final_mode = 5.0;';
L{end+1} = '    final_breaker = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = '';
L{end+1} = '    if island_latch<0.5';
L{end+1} = '        state_next = 0.0;';
L{end+1} = '        sync_timer_next = 0.0;';
L{end+1} = '        fref_trim = 0.0;';
L{end+1} = '        final_mode = raw_mode;';
L{end+1} = '        final_breaker = raw_breaker;';
L{end+1} = '        return;';
L{end+1} = '    end';
L{end+1} = '';
L{end+1} = '    if recovery_request<=0.5';
L{end+1} = '        state_next = 0.0;';
L{end+1} = '        sync_timer_next = 0.0;';
L{end+1} = '        fref_trim = 0.0;';
L{end+1} = '        final_mode = raw_mode;';
L{end+1} = '        final_breaker = raw_breaker;';
L{end+1} = '        return;';
L{end+1} = '    end';
L{end+1} = '';
L{end+1} = '    if sync_ok>0.5';
L{end+1} = '        sync_timer_next = sync_timer_prev + Ts;';
L{end+1} = '    else';
L{end+1} = '        sync_timer_next = 0.0;';
L{end+1} = '    end';
L{end+1} = '';
L{end+1} = '    if sync_timer_next >= max(stable_s,Ts)';
L{end+1} = '        state_next = 2.0;';
L{end+1} = '        final_breaker = 1.0;';
L{end+1} = '        reclose_commanded = 1.0;';
L{end+1} = '        reclose_timer_next = 0.0;';
L{end+1} = '    end';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if st==2';
L{end+1} = '    recovery_active = 1.0;';
L{end+1} = '    final_mode = 5.0;';
L{end+1} = '    final_breaker = 1.0;';
L{end+1} = '    reclose_commanded = 1.0;';
L{end+1} = '    reclose_timer_next = reclose_timer_prev + Ts;';
L{end+1} = '    if reclose_timer_next >= max(reclose_hold_s,Ts)';
L{end+1} = '        state_next = 3.0;';
L{end+1} = '    end';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% state 3: command normal mode/closed PCC and hold clear until S13 latch resets.';
L{end+1} = 'recovery_active = 1.0;';
L{end+1} = 'final_mode = 0.0;';
L{end+1} = 'final_breaker = 1.0;';
L{end+1} = 'reclose_commanded = 1.0;';
L{end+1} = 'fref_trim = 0.0;';
L{end+1} = 'clear_island = 1.0;';
L{end+1} = '';
L{end+1} = 'if island_latch<0.5';
L{end+1} = '    state_next = 0.0;';
L{end+1} = '    sync_timer_next = 0.0;';
L{end+1} = '    reclose_timer_next = 0.0;';
L{end+1} = 'end';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function y=clamp1(x,lo,hi)';
L{end+1} = 'y=min(max(x,lo),hi);';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function y=wrap180(x)';
L{end+1} = 'y=mod(x+180.0,360.0)-180.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function ok=finite1(x)';
L{end+1} = 'ok=~(isnan(x)||isinf(x));';
L{end+1} = 'end';

txt = strjoin(L,newline);
end


% =========================================================================
% ESS Fref router
% =========================================================================
function txt = localFrefRouterScript()

L = {};
L{end+1} = ['function [f1,f2,legacy_echo,route_valid] = ' ...
    'AA15_S15_Master_Fref_Router_Core(' ...
    'legacy_fref,trim_hz,recovery_active,selected_master,recovery_route_valid)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'f1=legacy_fref;';
L{end+1} = 'f2=legacy_fref;';
L{end+1} = 'legacy_echo=legacy_fref;';
L{end+1} = 'route_valid=1.0;';
L{end+1} = '';
L{end+1} = 'if ~finite1(legacy_fref)||~finite1(trim_hz)||~finite1(selected_master)';
L{end+1} = '    route_valid=0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if recovery_active<=0.5';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if recovery_route_valid<=0.5';
L{end+1} = '    route_valid=0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'm=round(selected_master);';
L{end+1} = 'if m==1';
L{end+1} = '    f1=legacy_fref+trim_hz;';
L{end+1} = 'elseif m==2';
L{end+1} = '    f2=legacy_fref+trim_hz;';
L{end+1} = 'else';
L{end+1} = '    route_valid=0.0;';
L{end+1} = 'end';
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
    error('S15R:EMChartPath', ...
        'Expected one Stateflow.EMChart at %s, found %d.',blockPath,numel(charts));
end
chart = charts(1);
end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)
ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    error('S15R:UndrivenDestination','Protected destination is undriven.');
end
srcPort = get_param(ln,'SrcPortHandle');
if isempty(srcPort) || srcPort < 0
    error('S15R:NoSourcePort','Could not resolve source port.');
end
srcPath = getfullname(get_param(srcPort,'Parent'));
end


function srcPort = localGetLineSourcePort(dstPort)
ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    error('S15R:UndrivenInput','Expected driven input is undriven.');
end
srcPort = get_param(ln,'SrcPortHandle');
if isempty(srcPort) || srcPort < 0
    error('S15R:NoSource','Cannot resolve input source.');
end
end


function localEnsureLine(parent,src,dst)
[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);
srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcPort = srcPH.Outport(srcIdx);
dstPort = dstPH.Inport(dstIdx);
ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
elseif get_param(ln,'SrcPortHandle') ~= srcPort
    error('S15R:LineDriven','Destination %s already has another source.',dst);
end
end


function localForceOwnedLine(parent,src,dst)
[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);
srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');
localForcePortConnection(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));
end


function [path,idx] = localParseRelativePort(parent,spec)
slash = find(spec=='/',1,'last');
if isempty(slash)
    error('S15R:PortSpec','Invalid port spec: %s',spec);
end
path = [parent '/' spec(1:slash-1)];
idx = str2double(spec(slash+1:end));
if isnan(idx) || idx<1 || getSimulinkBlockHandle(path)<0
    error('S15R:PortSpec','Invalid port spec: %s',spec);
end
end


function localEnsureTopLevelSourceConnection(parent,srcPort,dstPort,desc)
ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
elseif get_param(ln,'SrcPortHandle') ~= srcPort
    error('S15R:TopConnection', ...
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
    error('S15R:ForceConnection','Post-assert failed for %s.',desc);
end
end


function localDisconnectDestinationBranch(parent,dstPort)
ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    return;
end

srcPort = get_param(ln,'SrcPortHandle');
dstPorts = get_param(ln,'DstPortHandle');
dstPorts = dstPorts(dstPorts>=0);

if numel(dstPorts)<=1
    delete_line(ln);
    return;
end

try
    delete_line(parent,srcPort,dstPort);
catch ME
    error('S15R:BranchDelete', ...
        ['Could not remove only requested branch. Whole shared-trunk deletion ' ...
         'is forbidden. %s'],ME.message);
end
end


function localDisconnectLogInput(groupMux,portNo)
ph = get_param(groupMux,'PortHandles');
if numel(ph.Inport)<portNo
    return;
end
if isequal(get_param(ph.Inport(portNo),'Line'),-1)
    return;
end
parent = get_param(groupMux,'Parent');
localDisconnectDestinationBranch(parent,ph.Inport(portNo));
end


function localDeleteBlockIfExists(blockPath)
if getSimulinkBlockHandle(blockPath)<0
    return;
end

parent = get_param(blockPath,'Parent');
try
    ph = get_param(blockPath,'PortHandles');
    incoming = {'Inport','Enable','Trigger','Ifaction','Reset'};

    for i = 1:numel(incoming)
        fld = incoming{i};
        if isfield(ph,fld)
            ports = ph.(fld);
            for j = 1:numel(ports)
                localDisconnectDestinationBranch(parent,ports(j));
            end
        end
    end

    if isfield(ph,'Outport')
        lines = [];
        for j = 1:numel(ph.Outport)
            ln = get_param(ph.Outport(j),'Line');
            if ~isequal(ln,-1)
                lines(end+1)=ln; %#ok<AGROW>
            end
        end
        lines = unique(lines(lines>=0));
        for j = 1:numel(lines)
            try
                delete_line(lines(j));
            catch
            end
        end
    end
catch ME
    if startsWith(ME.identifier,'S15R:')
        rethrow(ME);
    end
end

delete_block(blockPath);
end


function localDeleteSubsystemContents(subsys)
if getSimulinkBlockHandle(subsys)<0
    return;
end

try
    Simulink.SubSystem.deleteContents(subsys);
    return;
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
    if strcmp(blocks{i},subsys), continue; end
    try delete_block(blocks{i}); catch, end
end
end


function p = localFindExistingLogPort(sourceBlock,logMux)
p = 0;
if getSimulinkBlockHandle(sourceBlock)<0 || getSimulinkBlockHandle(logMux)<0
    return;
end

srcPH = get_param(sourceBlock,'PortHandles');
if isempty(srcPH.Outport), return; end

ln = get_param(srcPH.Outport(1),'Line');
if isequal(ln,-1), return; end

try
    dst = get_param(ln,'DstPortHandle');
catch
    dst = [];
end

dst = dst(dst>=0);
muxPH = get_param(logMux,'PortHandles');

for i = 1:numel(dst)
    hit = find(muxPH.Inport==dst(i),1,'first');
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
            gotos{end+1,1}=allg{i}; %#ok<AGROW>
        end
    catch
    end
end
end


function localAssertNoForeignGotoTag(mdl,tag,expectedPath)
g = localFindGotosByTag(mdl,tag);
for i = 1:numel(g)
    if ~strcmp(g{i},expectedPath)
        error('S15R:ForeignGoto', ...
            'GotoTag %s already exists at unexpected path %s.',tag,g{i});
    end
end
end


function localAssertSingleGlobalGoto(mdl,tag)
g = localFindGotosByTag(mdl,tag);
if numel(g)~=1
    error('S15R:GlobalGotoCount', ...
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

maxRight=0;
for i = 1:numel(blocks)
    if strcmp(blocks{i},parent), continue; end
    try
        pos=get_param(blocks{i},'Position');
        maxRight=max(maxRight,pos(3));
    catch
    end
end
x=maxRight+margin;
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

rects=[];
for i = 1:numel(blocks)
    if strcmp(blocks{i},parent), continue; end
    try
        p=get_param(blocks{i},'Position');
        if numel(p)==4
            rects(end+1,:)=p; %#ok<AGROW>
        end
    catch
    end
end

if isempty(rects)
    x=50; y=50; return;
end

x=max(rects(:,3))+margin;
y=80;

if localRectOverlaps([x y x+w y+h],rects)
    y=max(rects(:,4))+margin;
end
end


function tf = localRectOverlaps(r,rects)
tf=false;
for i = 1:size(rects,1)
    q=rects(i,:);
    separated = r(3)<q(1) || r(1)>q(3) || r(4)<q(2) || r(2)>q(4);
    if ~separated
        tf=true; return;
    end
end
end

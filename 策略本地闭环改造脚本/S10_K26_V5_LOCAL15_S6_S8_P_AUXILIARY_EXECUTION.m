function S10_K26_V5_LOCAL15_S6_S8_P_AUXILIARY_EXECUTION
% S10_K26_V5_LOCAL15_S6_S8_P_AUXILIARY_EXECUTION
%
% LOCAL15 Stage 10
%
% Purpose
% -------
% Close the loop for TWO EXISTING teacher-tested strategies without changing
% Advanced_Microgrid_15_Strategies:
%
%   S6  PV smoothing
%   S8  UV/UF load shedding
%
% Final LOCAL15 active-P path after S10:
%
%   S08 active-P objective/constraints
%       -> baseline AGC
%       -> S05 Execution Mapper
%       -> S10 P Auxiliary Executor
%            * S6 modifies ESS1/ESS2 only
%            * S8 reduces EV charging only
%       -> S05 Command Source Router
%       -> u_commit
%       -> S06 execution fault injector
%       -> u_applied
%       -> S07 final safety interface
%       -> AA15_FINAL_APPLIED_*
%       -> six real device Pref ports
%
% This placement is intentional:
%   - S6/S8 become part of LOCAL15 BEFORE u_commit.
%   - paper execution-fault injection still acts on the complete command.
%   - ESS SOC still follows AA15_FINAL_APPLIED_ESS1/2.
%   - LEGACY_V5A and future BOARD15 source semantics are not changed.
%
% S6 execution
% ------------
% The original S6 strategy output is NOT a signed power command. It reports
% ramp-rate excess magnitude. Therefore this executor:
%   1) taps the EXACT existing strategy inputs t, PV1, PV2, P_unit and srl;
%   2) uses cmd(6) as the teacher-tested S6 trigger;
%   3) maintains a ramp-limited PV reference using the SAME srl parameter;
%   4) commands ESS compensation:
%
%        Pess_smooth = Ppv_smoothed - Ppv_actual
%
%      PV rise  -> negative ESS correction (charge)
%      PV fall  -> positive ESS correction (discharge)
%
%   5) splits the correction by available ESS directional headroom.
%
% No MPC/PSO/new smoothing strategy is added.
%
% S8 execution
% ------------
% The original strategy already outputs:
%
%        status(8) = shed stage
%        cmd(8)    = requested shed kW
%
% Current 2PV+2ESS+2EV platform executes flexible load shedding through EVs:
%
%        priority EV2 -> EV1
%
% Charging Pref is negative, so shedding moves EV Pref TOWARD zero.
% If the two EVs cannot satisfy the requested shed amount, the residual is
% logged as unserved_kW. Existing connected fixed Load1/Load2 are not altered
% in this stage.
%
% Group28
% -------
% S09 total = 113 signals.
% S10 appends 28 signals:
%
%   114 S6_status
%   115 S6_alarm
%   116 S6_metric
%   117 S6_cmd_rate_excess
%   118 S8_status_stage
%   119 S8_alarm
%   120 S8_metric
%   121 S8_cmd_shed_kW
%   122 strategy_PV1_kW
%   123 strategy_PV2_kW
%   124 strategy_srl_pct_per_min
%   125 strategy_P_unit_kW
%   126 aux_local_PV1
%   127 aux_local_PV2
%   128 aux_local_ESS1
%   129 aux_local_ESS2
%   130 aux_local_EV1
%   131 aux_local_EV2
%   132 aux_local_valid
%   133 S6_smoothed_PV_ref_kW
%   134 S6_comp_request_pu
%   135 S6_comp_applied_pu
%   136 S6_unserved_pu
%   137 S6_active
%   138 S8_shed_request_kW
%   139 S8_shed_applied_kW
%   140 S8_shed_unserved_kW
%   141 S8_active
%
% Expected aa15_strategy_data:
%   142 rows = Target Time + 141 signals.
%
% Script safety rules learned from S08
% ------------------------------------
%   - mdl = bdroot(gcs)
%   - backup first
%   - accept/repair a partially failed prior S10 run
%   - restore Router local inputs to S05 mapper BEFORE rebuilding S10 core
%   - remove Stage10-owned lines before Stage10-owned blocks
%   - NEVER update/compile a known half-built Stage10 structure
%   - new Subsystems are always cleared immediately, including first create
%   - strategy vectors use explicit Demux15
%   - exact source/destination post-assertions before save
%   - Variant searches use MatchFilter when available to avoid R2023b warnings

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 10 - S6/S8 P Auxiliary Real Execution\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S10:NoActiveModel', ...
        'No active model. Open K26_V5 and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

if getSimulinkBlockHandle(sm) < 0
    error('S10:MissingSM','Missing SM_Master.');
end
if getSimulinkBlockHandle(stack) < 0
    error('S10:MissingStack','Missing AA15_LOCAL_CONTROL_STACK.');
end
if getSimulinkBlockHandle(group28Mux) < 0
    error('S10:MissingGroup28','Missing AA15_GROUP28_MUX.');
end
if getSimulinkBlockHandle(op28) < 0
    error('S10:MissingOp28','Missing AA15_OpWriteFile_Group28.');
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S10:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE10_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S10:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify frozen S09 foundation.
% =========================================================================
fprintf('\n--- Verify S09 foundation ---\n');

diagNames = {
    'AA15_STAGE03_DIAGNOSTICS'
    'AA15_STAGE04_AGC_DIAGNOSTICS'
    'AA15_STAGE05_ROUTER_DIAGNOSTICS'
    'AA15_STAGE06_EXECFAULT_DIAGNOSTICS'
    'AA15_STAGE07_TAKEOVER_DIAGNOSTICS'
    'AA15_STAGE08_P_DIAGNOSTICS'
    'AA15_STAGE09_Q_DIAGNOSTICS'
};

diagBlocks = cell(7,1);

for i = 1:7
    diagBlocks{i} = [sm '/' diagNames{i}];
    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S10:MissingPrerequisite', ...
            'Missing S09 prerequisite: %s',diagBlocks{i});
    end
end

requiredBlocks = {
    [stack '/AA15_Execution_Mapper']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Execution_Fault_Injector']
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Q_Allocator_Router']
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S10:MissingPrerequisite', ...
            'Missing S09 prerequisite: %s',requiredBlocks{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));

if ~(n28 == 7 || n28 == 8)
    error('S10:Group28Inputs', ...
        'Expected Group28 Inputs=7 (S09) or 8 (partial S10), found %g.',n28);
end

for i = 1:7
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S10:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

% Protect S09 real Q route.
qTags = {
    'AA15_FINAL_QREF_PV1'
    'AA15_FINAL_QREF_PV2'
    'AA15_FINAL_QREF_ESS1'
    'AA15_FINAL_QREF_ESS2'
    'AA15_FINAL_QREF_EV1'
    'AA15_FINAL_QREF_EV2'
};

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

muxPaths = cell(6,1);
prefInput6Source = cell(6,1);
qInput7Source = cell(6,1);

for i = 1:6
    muxPaths{i} = localFindUniqueNamedBlock(sm,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 7
        error('S10:MuxPorts','%s has fewer than 7 inputs.',muxPaths{i});
    end

    [p6,~] = localGetDestinationSource(ph.Inport(6));
    [p7,~] = localGetDestinationSource(ph.Inport(7));

    if ~strcmp(get_param(p6,'BlockType'),'From') || ...
            ~strcmp(get_param(p6,'GotoTag'),prefTags{i})
        error('S10:PrefFoundation', ...
            '%s input6 is not the frozen S07/S08 final Pref route.',muxPaths{i});
    end

    if ~strcmp(get_param(p7,'BlockType'),'From') || ...
            ~strcmp(get_param(p7,'GotoTag'),qTags{i})
        error('S10:QFoundation', ...
            '%s input7 is not the frozen S09 final Qref route.',muxPaths{i});
    end

    prefInput6Source{i} = p6;
    qInput7Source{i} = p7;
end

fprintf('[OK] Group28 inputs1..7 verified.\n');
fprintf('[OK] Six Pref input6 and six Qref input7 routes protected.\n');

% =========================================================================
% 2. Discover exact current strategy block and exact S6 inputs.
% =========================================================================
fprintf('\n--- Discover exact 15-strategy input sources ---\n');

strategyBlock = [sm '/Advanced_Microgrid_15_Strategies'];

if getSimulinkBlockHandle(strategyBlock) < 0
    hits = localFindBlocksByName(sm,'Advanced_Microgrid_15_Strategies');
    if numel(hits) ~= 1
        error('S10:StrategyBlock', ...
            'Expected one Advanced_Microgrid_15_Strategies block, found %d.', ...
            numel(hits));
    end
    strategyBlock = hits{1};
end

strategyPH = get_param(strategyBlock,'PortHandles');

if numel(strategyPH.Inport) < 40
    error('S10:StrategyPorts', ...
        'Advanced_Microgrid_15_Strategies exposes only %d inputs; expected 40.', ...
        numel(strategyPH.Inport));
end

% Frozen current algorithm input order:
%   1=t, 8=PV1, 9=PV2, 12=P_unit, 23=srl.
tapIdx = [1 8 9 12 23];
tapMeaning = {'t','PV1','PV2','P_unit','srl'};
strategySrcPorts = zeros(1,5);

for i = 1:5
    ln = get_param(strategyPH.Inport(tapIdx(i)),'Line');

    if isequal(ln,-1)
        error('S10:StrategyInputUnconnected', ...
            'Strategy input%d (%s) is unconnected.',tapIdx(i),tapMeaning{i});
    end

    src = get_param(ln,'SrcPortHandle');

    if isempty(src) || src < 0
        error('S10:StrategyInputSource', ...
            'Cannot resolve strategy input%d (%s) source.', ...
            tapIdx(i),tapMeaning{i});
    end

    strategySrcPorts(i) = src;
    fprintf('[OK] Strategy input%02d %-7s exact source = %s\n', ...
        tapIdx(i),tapMeaning{i},getfullname(get_param(src,'Parent')));
end

strategyParent = get_param(strategyBlock,'Parent');

% =========================================================================
% 3. Repair-safe cleanup BEFORE any update.
% =========================================================================
fprintf('\n--- Clean/repair stale partial S10 BEFORE model update ---\n');

execMap = [stack '/AA15_Execution_Mapper'];
router = [stack '/AA15_Command_Source_Router'];
aux = [stack '/AA15_P_Auxiliary_Executor'];
norm = [stack '/AA15_S6_S8_Normalizer'];
tap = [strategyParent '/AA15_S10_STRATEGY_INPUT_TAPS'];
s10Diag = [sm '/AA15_STAGE10_P_AUX_DIAGNOSTICS'];

execPH = get_param(execMap,'PortHandles');
routerPH = get_param(router,'PortHandles');

if numel(execPH.Outport) < 7 || numel(routerPH.Inport) < 13
    error('S10:RouterFoundation','S05 mapper/router ports are unexpected.');
end

% Router inputs7..13 must be either the original Execution Mapper or a
% partially applied S10 Auxiliary Executor. Anything else is unsafe.
for i = 1:7
    dst = routerPH.Inport(6+i);
    ln = get_param(dst,'Line');

    if isequal(ln,-1)
        error('S10:RouterLocalUndriven', ...
            'Router local input%d is undriven.',6+i);
    end

    src = get_param(ln,'SrcPortHandle');
    srcParent = getfullname(get_param(src,'Parent'));

    if strcmp(srcParent,execMap)
        % already pre-S10 compatible
    elseif strcmp(srcParent,aux)
        % partial S10: restore below
    else
        error('S10:RouterUnexpectedSource', ...
            'Router local input%d source is unexpected: %s',6+i,srcParent);
    end
end

% Restore all Router LOCAL15 inputs to the known S05 mapper BEFORE deleting
% or rebuilding any S10 core block.
for i = 1:7
    localForcePortConnection(stack, ...
        execPH.Outport(i),routerPH.Inport(6+i), ...
        sprintf('restore Router input%d to S05 Execution Mapper',6+i));
end

fprintf('[RESTORE] Router local inputs7..13 -> S05 Execution Mapper.\n');

% Remove stale S10 diagnostics and restore Group28 8 -> 7.
oldDiagPort = localFindExistingLogPort(s10Diag,group28Mux);

if oldDiagPort > 0
    if oldDiagPort ~= 8
        error('S10:OldDiagPort', ...
            'Existing S10 diagnostics is on unexpected Group28 input%d.', ...
            oldDiagPort);
    end
    localDisconnectLogInput(group28Mux,8);
end

if getSimulinkBlockHandle(s10Diag) >= 0
    localDeleteBlockIfExists(s10Diag);
    fprintf('[DELETE] stale %s\n',s10Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 8
    ph28 = get_param(group28Mux,'PortHandles');
    if numel(ph28.Inport) < 8
        error('S10:Group28RepairPort','Cannot inspect Group28 input8.');
    end

    ln8 = get_param(ph28.Inport(8),'Line');
    if ~isequal(ln8,-1)
        error('S10:Group28RepairBusy', ...
            'Group28 input8 is still connected during repair.');
    end

    set_param(group28Mux,'Inputs','7');
    fprintf('[RESTORE] Group28 Inputs: 8 -> 7.\n');
end

% Delete Stage10-owned publication Gotos BEFORE Stage10-owned core blocks.
for i = 1:8
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S10_NORM_%02d',i)]);
end

for i = 1:16
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S10_AUX_%02d',i)]);
end

% Delete/rebuild Stage10 core blocks and exact-input tap.
if getSimulinkBlockHandle(aux) >= 0
    localDeleteBlockIfExists(aux);
    fprintf('[DELETE] stale %s\n',aux);
end

if getSimulinkBlockHandle(norm) >= 0
    localDeleteBlockIfExists(norm);
    fprintf('[DELETE] stale %s\n',norm);
end

if getSimulinkBlockHandle(tap) >= 0
    localDeleteBlockIfExists(tap);
    fprintf('[DELETE] stale %s\n',tap);
end

fprintf('[OK] Partial S10 artifacts removed. No model update performed yet.\n');

% =========================================================================
% 4. Rebuild exact strategy input tap.
% =========================================================================
fprintf('\n--- Build exact strategy input tap ---\n');

[xTap,yTap] = localFindFreePosition(strategyParent,330,240,260);

add_block('simulink/Ports & Subsystems/Subsystem',tap, ...
    'Position',[xTap yTap xTap+330 yTap+240]);
localDeleteSubsystemContents(tap);

tapInNames = {'t','pv1','pv2','p_unit','srl'};
tapTags = {
    'AA15_S10_STRAT_TIME_S'
    'AA15_S10_STRAT_PV1_KW'
    'AA15_S10_STRAT_PV2_KW'
    'AA15_S10_STRAT_PUNIT_KW'
    'AA15_S10_STRAT_SRL_PCT_PER_MIN'
};

for i = 1:5
    y = 35 + (i-1)*40;

    add_block('simulink/Ports & Subsystems/In1', ...
        [tap '/' tapInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);

    add_block('simulink/Signal Routing/Goto', ...
        [tap '/' sprintf('GOTO_TAP_%02d',i)], ...
        'GotoTag',tapTags{i}, ...
        'TagVisibility','global', ...
        'Position',[105 y-3 300 y+19]);

    localEnsureLine(tap, ...
        [tapInNames{i} '/1'], ...
        sprintf('GOTO_TAP_%02d/1',i));
end

tapPH = get_param(tap,'PortHandles');

if numel(tapPH.Inport) ~= 5
    error('S10:TapPorts','S10 strategy tap expected 5 inputs.');
end

for i = 1:5
    localEnsureTopLevelSourceConnection(strategyParent, ...
        strategySrcPorts(i),tapPH.Inport(i), ...
        sprintf('strategy %s tap',tapMeaning{i}));
end

fprintf('[OK] Exact t/PV1/PV2/P_unit/srl sources tapped.\n');

% =========================================================================
% 5. Build S6/S8 normalizer using explicit Demux15.
% =========================================================================
fprintf('\n--- Build S6/S8 strategy normalizer ---\n');

xNorm = localNextRightX(stack,120);

add_block('simulink/Ports & Subsystems/Subsystem',norm, ...
    'Position',[xNorm 965 xNorm+410 1325]);
localDeleteSubsystemContents(norm);

normIn = {'status15','alarm15','metric15','cmd15'};
demuxNames = {'DEMUX_STATUS15','DEMUX_ALARM15','DEMUX_METRIC15','DEMUX_CMD15'};

for i = 1:4
    y = 45 + (i-1)*72;

    add_block('simulink/Ports & Subsystems/In1', ...
        [norm '/' normIn{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);

    add_block('simulink/Signal Routing/Demux', ...
        [norm '/' demuxNames{i}], ...
        'Outputs','15', ...
        'Position',[110 y-20 140 y+45]);

    localEnsureLine(norm,[normIn{i} '/1'],[demuxNames{i} '/1']);
end

normOut = {
    's6_status'
    's6_alarm'
    's6_metric'
    's6_cmd'
    's8_stage'
    's8_alarm'
    's8_metric'
    's8_cmd_shed_kw'
};

normSrc = {
    'DEMUX_STATUS15/6'
    'DEMUX_ALARM15/6'
    'DEMUX_METRIC15/6'
    'DEMUX_CMD15/6'
    'DEMUX_STATUS15/8'
    'DEMUX_ALARM15/8'
    'DEMUX_METRIC15/8'
    'DEMUX_CMD15/8'
};

for i = 1:8
    y = 35 + (i-1)*38;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [norm '/' normOut{i}], ...
        'Port',num2str(i), ...
        'Position',[320 y 350 y+16]);

    localEnsureLine(norm,normSrc{i},[normOut{i} '/1']);
end

% Connect the existing stack vector inputs1..4 to this normalizer.
for i = 1:4
    stackIn = localFindStackInportByNumber(stack,i);
    srcPH = get_param(stackIn,'PortHandles');
    dstPH = get_param(norm,'PortHandles');

    if isempty(srcPH.Outport) || numel(dstPH.Inport) < i
        error('S10:NormTopPorts', ...
            'Could not materialize stack input%d -> S10 normalizer input%d.',i,i);
    end

    localEnsureTopLevelSourceConnection(stack, ...
        srcPH.Outport(1),dstPH.Inport(i), ...
        sprintf('stack vector input%d -> S10 normalizer',i));
end

normTags = {
    'AA15_S6_STATUS'
    'AA15_S6_ALARM'
    'AA15_S6_METRIC'
    'AA15_S6_CMD_RATE_EXCESS'
    'AA15_S8_STATUS_STAGE'
    'AA15_S8_ALARM'
    'AA15_S8_METRIC'
    'AA15_S8_CMD_SHED_KW'
};

normPos = get_param(norm,'Position');

for i = 1:8
    gotoName = sprintf('GOTO_S10_NORM_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',normTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/4);
    row = mod(i-1,4);
    x = normPos(3) + 45 + col*225;
    y = normPos(2) + 20 + row*44;
    set_param(p,'Position',[x y x+200 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_S6_S8_Normalizer/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 6. Build combined LOCAL15 P auxiliary executor.
% =========================================================================
fprintf('\n--- Build S6/S8 P Auxiliary Executor ---\n');

xAux = normPos(3) + 520;

add_block('simulink/Ports & Subsystems/Subsystem',aux, ...
    'Position',[xAux 900 xAux+560 1435]);
localDeleteSubsystemContents(aux);

auxInputTags = {
    'AA15_EXEC_PV1_PREF'
    'AA15_EXEC_PV2_PREF'
    'AA15_EXEC_ESS1_PREF'
    'AA15_EXEC_ESS2_PREF'
    'AA15_EXEC_EV1_PREF'
    'AA15_EXEC_EV2_PREF'
    'AA15_EXEC_ACTIVE_VALID'
    'AA15_S10_STRAT_TIME_S'
    'AA15_S10_STRAT_PV1_KW'
    'AA15_S10_STRAT_PV2_KW'
    'AA15_S10_STRAT_PUNIT_KW'
    'AA15_S10_STRAT_SRL_PCT_PER_MIN'
    'AA15_S6_CMD_RATE_EXCESS'
    'AA15_S8_STATUS_STAGE'
    'AA15_S8_CMD_SHED_KW'
    'CFG15_MASTER_ENABLE'
    'CFG15_EXEC_S06'
    'CFG15_EXEC_S08'
};

for i = 1:18
    col = floor((i-1)/9);
    row = mod(i-1,9);
    x = 20 + col*230;
    y = 25 + row*42;

    add_block('simulink/Signal Routing/From', ...
        [aux '/' sprintf('FROM_AUX_%02d',i)], ...
        'GotoTag',auxInputTags{i}, ...
        'Position',[x y x+205 y+20]);
end

auxMF = [aux '/AA15_S6_S8_P_Auxiliary_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',auxMF, ...
    'Position',[505 80 990 565]);

auxChart = localGetEMChartByPath(auxMF);
auxChart.Script = localAuxiliaryCoreScript();

auxOut = {
    'pv1_aux'
    'pv2_aux'
    'ess1_aux'
    'ess2_aux'
    'ev1_aux'
    'ev2_aux'
    'aux_valid'
    's6_smooth_ref_kw'
    's6_comp_request_pu'
    's6_comp_applied_pu'
    's6_unserved_pu'
    's6_active'
    's8_request_kw'
    's8_applied_kw'
    's8_unserved_kw'
    's8_active'
};

for i = 1:16
    y = 35 + (i-1)*30;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [aux '/' auxOut{i}], ...
        'Port',num2str(i), ...
        'Position',[1085 y 1115 y+16]);
end

for i = 1:18
    localEnsureLine(aux, ...
        sprintf('FROM_AUX_%02d/1',i), ...
        sprintf('AA15_S6_S8_P_Auxiliary_Core/%d',i));
end

for i = 1:16
    localEnsureLine(aux, ...
        sprintf('AA15_S6_S8_P_Auxiliary_Core/%d',i), ...
        [auxOut{i} '/1']);
end

auxTags = {
    'AA15_AUX_PV1_PREF'
    'AA15_AUX_PV2_PREF'
    'AA15_AUX_ESS1_PREF'
    'AA15_AUX_ESS2_PREF'
    'AA15_AUX_EV1_PREF'
    'AA15_AUX_EV2_PREF'
    'AA15_AUX_ACTIVE_VALID'
    'AA15_S6_SMOOTH_REF_KW'
    'AA15_S6_COMP_REQUEST_PU'
    'AA15_S6_COMP_APPLIED_PU'
    'AA15_S6_UNSERVED_PU'
    'AA15_S6_EXEC_ACTIVE'
    'AA15_S8_SHED_REQUEST_KW'
    'AA15_S8_SHED_APPLIED_KW'
    'AA15_S8_SHED_UNSERVED_KW'
    'AA15_S8_EXEC_ACTIVE'
};

auxPos = get_param(aux,'Position');

for i = 1:16
    gotoName = sprintf('GOTO_S10_AUX_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',auxTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/8);
    row = mod(i-1,8);
    x = auxPos(3) + 45 + col*230;
    y = auxPos(2) + 20 + row*45;
    set_param(p,'Position',[x y x+205 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_P_Auxiliary_Executor/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 7. Build S10 diagnostics BEFORE first update.
% =========================================================================
fprintf('\n--- Build S10 diagnostics ---\n');

[dx,dy] = localFindFreePosition(sm,500,520,420);

add_block('simulink/Ports & Subsystems/Subsystem',s10Diag, ...
    'Position',[dx dy dx+500 dy+520]);
localDeleteSubsystemContents(s10Diag);

diagTags = {
    'AA15_S6_STATUS'
    'AA15_S6_ALARM'
    'AA15_S6_METRIC'
    'AA15_S6_CMD_RATE_EXCESS'
    'AA15_S8_STATUS_STAGE'
    'AA15_S8_ALARM'
    'AA15_S8_METRIC'
    'AA15_S8_CMD_SHED_KW'
    'AA15_S10_STRAT_PV1_KW'
    'AA15_S10_STRAT_PV2_KW'
    'AA15_S10_STRAT_SRL_PCT_PER_MIN'
    'AA15_S10_STRAT_PUNIT_KW'
    'AA15_AUX_PV1_PREF'
    'AA15_AUX_PV2_PREF'
    'AA15_AUX_ESS1_PREF'
    'AA15_AUX_ESS2_PREF'
    'AA15_AUX_EV1_PREF'
    'AA15_AUX_EV2_PREF'
    'AA15_AUX_ACTIVE_VALID'
    'AA15_S6_SMOOTH_REF_KW'
    'AA15_S6_COMP_REQUEST_PU'
    'AA15_S6_COMP_APPLIED_PU'
    'AA15_S6_UNSERVED_PU'
    'AA15_S6_EXEC_ACTIVE'
    'AA15_S8_SHED_REQUEST_KW'
    'AA15_S8_SHED_APPLIED_KW'
    'AA15_S8_SHED_UNSERVED_KW'
    'AA15_S8_EXEC_ACTIVE'
};

for i = 1:28
    col = floor((i-1)/14);
    row = mod(i-1,14);
    x = 20 + col*230;
    y = 20 + row*32;

    add_block('simulink/Signal Routing/From', ...
        [s10Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+205 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s10Diag '/AA15_STAGE10_DIAG28'], ...
    'Inputs','28', ...
    'Position',[520 35 555 485]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s10Diag '/diag28'], ...
    'Port','1', ...
    'Position',[620 245 650 261]);

for i = 1:28
    localEnsureLine(s10Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE10_DIAG28/%d',i));
end

localEnsureLine(s10Diag,'AA15_STAGE10_DIAG28/1','diag28/1');

% =========================================================================
% 8. FIRST update only after complete S10 structures exist.
% =========================================================================
fprintf('\n--- First compile/update after COMPLETE S10 structure ---\n');

set_param(mdl,'SimulationCommand','update');

for i = 1:4
    phD = get_param([norm '/' demuxNames{i}],'PortHandles');
    if numel(phD.Outport) ~= 15
        error('S10:DemuxWidth', ...
            '%s expected 15 outputs, found %d.', ...
            [norm '/' demuxNames{i}],numel(phD.Outport));
    end
end

mfPorts = get_param(auxMF,'Ports');
if mfPorts(1) ~= 18 || mfPorts(2) ~= 16
    error('S10:AuxPorts', ...
        'S10 auxiliary core expected 18-in/16-out, found %d/%d.', ...
        mfPorts(1),mfPorts(2));
end

fprintf('[OK] Four strategy vectors compiled as Demux15.\n');
fprintf('[OK] S10 auxiliary core compiled 18 inputs / 16 outputs.\n');

% =========================================================================
% 9. REAL route integration: Router LOCAL15 inputs7..13 now come from S10.
% =========================================================================
fprintf('\n--- Route S10 auxiliary LOCAL15 commands into source Router ---\n');

auxPH = get_param(aux,'PortHandles');
routerPH = get_param(router,'PortHandles');

if numel(auxPH.Outport) < 7 || numel(routerPH.Inport) < 13
    error('S10:RoutePorts','Cannot materialize S10 -> Router ports.');
end

for i = 1:7
    localForcePortConnection(stack, ...
        auxPH.Outport(i),routerPH.Inport(6+i), ...
        sprintf('S10 aux output%d -> Router input%d',i,6+i));
end

set_param(mdl,'SimulationCommand','update');

fprintf('[ROUTE] Router LOCAL15 inputs7..13 now use S10 auxiliary executor.\n');

% =========================================================================
% 10. Append S10 diag28 to Group28 input8.
% =========================================================================
fprintf('\n--- Append S10 diag28 to Group28 input8 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 7
    error('S10:Group28BeforeAppend', ...
        'Expected Group28 Inputs=7 before S10 append.');
end

set_param(group28Mux,'Inputs','8');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s10Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S10:DiagPort','S10 diagnostics expected exactly one output.');
end
if numel(muxPH28.Inport) < 8
    error('S10:Group28Input8','Group28 input8 did not materialize.');
end

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(8), ...
    'S10 diag28 -> Group28 input8');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 11. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S10 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 8
    error('S10:Group28Final','Group28 must have 8 inputs after S10.');
end

for i = 1:7
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S10:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.', ...
            diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s10Diag,group28Mux) ~= 8
    error('S10:S10DiagSlot','S10 diagnostics is not Group28 input8.');
end

% Router local inputs7..13 must now be exact S10 outputs1..7.
auxPH = get_param(aux,'PortHandles');
routerPH = get_param(router,'PortHandles');

for i = 1:7
    ln = get_param(routerPH.Inport(6+i),'Line');

    if isequal(ln,-1)
        error('S10:RouterPostUndriven','Router input%d is undriven.',6+i);
    end

    src = get_param(ln,'SrcPortHandle');

    if src ~= auxPH.Outport(i)
        error('S10:RouterPostSource', ...
            'Router input%d is not driven by S10 aux output%d.',6+i,i);
    end
end

% Physical real plant routes MUST remain unchanged by S10.
for i = 1:6
    ph = get_param(muxPaths{i},'PortHandles');

    [p6,~] = localGetDestinationSource(ph.Inport(6));
    [p7,~] = localGetDestinationSource(ph.Inport(7));

    if ~strcmp(p6,prefInput6Source{i}) || ...
            ~strcmp(get_param(p6,'GotoTag'),prefTags{i})
        error('S10:PrefPostAssert', ...
            '%s input6 Pref physical source changed.',muxPaths{i});
    end

    if ~strcmp(p7,qInput7Source{i}) || ...
            ~strcmp(get_param(p7,'GotoTag'),qTags{i})
        error('S10:QPostAssert', ...
            '%s input7 Qref physical source changed.',muxPaths{i});
    end
end

% Check all Stage10 global publication tags are unique.
allTags = [tapTags; normTags; auxTags];

for i = 1:numel(allTags)
    localAssertSingleGlobalGoto(mdl,allTags{i});
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE10 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Original S6/S8 strategy core       : UNCHANGED\n');
fprintf('Exact strategy input taps          : PASS\n');
fprintf('S6/S8 Demux15 normalizer           : PASS\n');
fprintf('S6 ESS smoothing executor          : PASS\n');
fprintf('S8 EV2->EV1 shed executor          : PASS\n');
fprintf('Router LOCAL15 reroute             : PASS\n');
fprintf('Pref physical input6 protection    : PASS\n');
fprintf('Qref physical input7 protection    : PASS\n');
fprintf('Group28                            : 8 physical inputs\n');
fprintf('Group28 total signals              : 141\n');
fprintf('Expected MAT rows                  : 142 (incl. Target Time)\n');
fprintf('Backup                             : %s\n',backupFile);
fprintf('\nNEXT: Build is required because the REAL LOCAL15 active-P route changed.\n');

end


% =========================================================================
% MATLAB Function source: S6/S8 combined P auxiliary executor
% =========================================================================
function txt = localAuxiliaryCoreScript()

L = {};
L{end+1} = ['function [pv1o,pv2o,e1o,e2o,ev1o,ev2o,valid,' ...
    'smooth_ref_kw,s6_req_pu,s6_applied_pu,s6_unserved_pu,s6_active,' ...
    's8_request_kw,s8_applied_kw,s8_unserved_kw,s8_active] = ' ...
    'AA15_S6_S8_P_Auxiliary_Core(' ...
    'pv1b,pv2b,e1b,e2b,ev1b,ev2b,base_valid,' ...
    't,pv1kw,pv2kw,punit,srl,s6cmd,s8stage,s8cmd,' ...
    'master_enable,exec_s06,exec_s08)'];
L{end+1} = '%#codegen';
L{end+1} = 'persistent last_t smooth_ref initialized';
L{end+1} = '';
L{end+1} = 'pv1o = pv1b; pv2o = pv2b;';
L{end+1} = 'e1o = e1b; e2o = e2b;';
L{end+1} = 'ev1o = ev1b; ev2o = ev2b;';
L{end+1} = 'valid = 0.0;';
L{end+1} = 'smooth_ref_kw = 0.0;';
L{end+1} = 's6_req_pu = 0.0;';
L{end+1} = 's6_applied_pu = 0.0;';
L{end+1} = 's6_unserved_pu = 0.0;';
L{end+1} = 's6_active = 0.0;';
L{end+1} = 's8_request_kw = 0.0;';
L{end+1} = 's8_applied_kw = 0.0;';
L{end+1} = 's8_unserved_kw = 0.0;';
L{end+1} = 's8_active = 0.0;';
L{end+1} = '';
L{end+1} = 'pv_now = max(pv1kw,0.0) + max(pv2kw,0.0);';
L{end+1} = '';
L{end+1} = 'if isempty(initialized)';
L{end+1} = '    initialized = 1.0;';
L{end+1} = '    last_t = t;';
L{end+1} = '    smooth_ref = pv_now;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if ~finite1(t) || ~finite1(pv_now)';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if t < last_t';
L{end+1} = '    last_t = t;';
L{end+1} = '    smooth_ref = pv_now;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'dt = max(t-last_t,0.0);';
L{end+1} = '';
L{end+1} = 'if ~finite1(pv1b) || ~finite1(pv2b) || ...';
L{end+1} = '   ~finite1(e1b) || ~finite1(e2b) || ...';
L{end+1} = '   ~finite1(ev1b) || ~finite1(ev2b) || ...';
L{end+1} = '   ~finite1(punit) || abs(punit) < 1e-9';
L{end+1} = '    last_t = t;';
L{end+1} = '    smooth_ref = pv_now;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'pbase = abs(punit);';
L{end+1} = '';
L{end+1} = '% Preserve the S05 device domains before adding auxiliary actions.';
L{end+1} = 'pv1o = clamp1(pv1b,0.0,1.0);';
L{end+1} = 'pv2o = clamp1(pv2b,0.0,1.0);';
L{end+1} = 'e1o = clamp1(e1b,-1.0,1.0);';
L{end+1} = 'e2o = clamp1(e2b,-1.0,1.0);';
L{end+1} = 'ev1o = clamp1(ev1b,-1.0,0.0);';
L{end+1} = 'ev2o = clamp1(ev2b,-1.0,0.0);';
L{end+1} = '';
L{end+1} = 'if base_valid <= 0.5';
L{end+1} = '    last_t = t;';
L{end+1} = '    smooth_ref = pv_now;';
L{end+1} = '    smooth_ref_kw = smooth_ref;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'valid = 1.0;';
L{end+1} = '';
L{end+1} = '% ------------------------------------------------------------';
L{end+1} = '% S6: teacher-tested cmd6 is the ramp-excess trigger.';
L{end+1} = '% The same strategy srl parameter defines the ramp-limited PV reference.';
L{end+1} = '% ------------------------------------------------------------';
L{end+1} = 'if master_enable > 0.5 && exec_s06 > 0.5';
L{end+1} = '    srl_use = max(srl,0.0);';
L{end+1} = '    rated_kw = 2.0*pbase;';
L{end+1} = '    allowed = srl_use/100.0*rated_kw*dt/60.0;';
L{end+1} = '';
L{end+1} = '    residual = pv_now-smooth_ref;';
L{end+1} = '    need_smooth = (s6cmd > 0.0) || (abs(residual) > 1e-9);';
L{end+1} = '';
L{end+1} = '    if need_smooth && dt > 0.0';
L{end+1} = '        step = clamp1(residual,-allowed,allowed);';
L{end+1} = '        smooth_ref = smooth_ref + step;';
L{end+1} = '    else';
L{end+1} = '        smooth_ref = pv_now;';
L{end+1} = '    end';
L{end+1} = '';
L{end+1} = '    s6_req_pu = (smooth_ref-pv_now)/pbase;';
L{end+1} = '';
L{end+1} = '    if abs(s6_req_pu) > 1e-12';
L{end+1} = '        s6_active = 1.0;';
L{end+1} = '';
L{end+1} = '        if s6_req_pu > 0.0';
L{end+1} = '            room1 = max(1.0-e1o,0.0);';
L{end+1} = '            room2 = max(1.0-e2o,0.0);';
L{end+1} = '            room = room1+room2;';
L{end+1} = '            usemag = min(s6_req_pu,room);';
L{end+1} = '';
L{end+1} = '            if room > 1e-12';
L{end+1} = '                a1 = usemag*room1/room;';
L{end+1} = '                a2 = usemag*room2/room;';
L{end+1} = '            else';
L{end+1} = '                a1 = 0.0; a2 = 0.0;';
L{end+1} = '            end';
L{end+1} = '';
L{end+1} = '            e1o = e1o+a1;';
L{end+1} = '            e2o = e2o+a2;';
L{end+1} = '            s6_applied_pu = a1+a2;';
L{end+1} = '            s6_unserved_pu = max(s6_req_pu-s6_applied_pu,0.0);';
L{end+1} = '        else';
L{end+1} = '            reqmag = -s6_req_pu;';
L{end+1} = '            room1 = max(e1o+1.0,0.0);';
L{end+1} = '            room2 = max(e2o+1.0,0.0);';
L{end+1} = '            room = room1+room2;';
L{end+1} = '            usemag = min(reqmag,room);';
L{end+1} = '';
L{end+1} = '            if room > 1e-12';
L{end+1} = '                a1 = usemag*room1/room;';
L{end+1} = '                a2 = usemag*room2/room;';
L{end+1} = '            else';
L{end+1} = '                a1 = 0.0; a2 = 0.0;';
L{end+1} = '            end';
L{end+1} = '';
L{end+1} = '            e1o = e1o-a1;';
L{end+1} = '            e2o = e2o-a2;';
L{end+1} = '            s6_applied_pu = -(a1+a2);';
L{end+1} = '            s6_unserved_pu = max(reqmag-(a1+a2),0.0);';
L{end+1} = '        end';
L{end+1} = '    end';
L{end+1} = 'else';
L{end+1} = '    smooth_ref = pv_now;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'smooth_ref_kw = smooth_ref;';
L{end+1} = '';
L{end+1} = '% ------------------------------------------------------------';
L{end+1} = '% S8: cmd8 is requested load shed kW. EV2 is first, then EV1.';
L{end+1} = '% EV charging is negative; shedding moves Pref toward zero.';
L{end+1} = '% ------------------------------------------------------------';
L{end+1} = 'if master_enable > 0.5 && exec_s08 > 0.5 && ...';
L{end+1} = '        s8stage > 0.0 && s8cmd > 0.0';
L{end+1} = '';
L{end+1} = '    s8_active = 1.0;';
L{end+1} = '    s8_request_kw = max(s8cmd,0.0);';
L{end+1} = '    req_pu = s8_request_kw/pbase;';
L{end+1} = '';
L{end+1} = '    avail2 = max(-ev2o,0.0);';
L{end+1} = '    take2 = min(req_pu,avail2);';
L{end+1} = '    ev2o = ev2o+take2;';
L{end+1} = '';
L{end+1} = '    remain = max(req_pu-take2,0.0);';
L{end+1} = '    avail1 = max(-ev1o,0.0);';
L{end+1} = '    take1 = min(remain,avail1);';
L{end+1} = '    ev1o = ev1o+take1;';
L{end+1} = '';
L{end+1} = '    applied_pu = take1+take2;';
L{end+1} = '    s8_applied_kw = applied_pu*pbase;';
L{end+1} = '    s8_unserved_kw = max(s8_request_kw-s8_applied_kw,0.0);';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Final domain guards.';
L{end+1} = 'pv1o = clamp1(pv1o,0.0,1.0);';
L{end+1} = 'pv2o = clamp1(pv2o,0.0,1.0);';
L{end+1} = 'e1o = clamp1(e1o,-1.0,1.0);';
L{end+1} = 'e2o = clamp1(e2o,-1.0,1.0);';
L{end+1} = 'ev1o = clamp1(ev1o,-1.0,0.0);';
L{end+1} = 'ev2o = clamp1(ev2o,-1.0,0.0);';
L{end+1} = '';
L{end+1} = 'last_t = t;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'function y = clamp1(x,lo,hi)';
L{end+1} = 'y = min(max(x,lo),hi);';
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
function chart = localGetEMChartByPath(blockPath)

rt = sfroot;
charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);

if isempty(charts)
    drawnow;
    rt = sfroot;
    charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);
end

if numel(charts) ~= 1
    error('S10:EMChartPath', ...
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
    error('S10:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S10:UndrivenDestination','Protected destination is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isempty(srcPort) || srcPort < 0
    error('S10:NoSourcePort','Could not resolve source port.');
end

srcPath = getfullname(get_param(srcPort,'Parent'));

end


function inPath = localFindStackInportByNumber(stack,portNo)

try
    cands = find_system(stack, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'BlockType','Inport');
catch
    cands = find_system(stack, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'BlockType','Inport');
end

hits = {};

for i = 1:numel(cands)
    if strcmp(get_param(cands{i},'Port'),num2str(portNo))
        hits{end+1,1} = cands{i}; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    error('S10:StackInport', ...
        'Expected one stack Inport with Port=%d, found %d.', ...
        portNo,numel(hits));
end

inPath = hits{1};

end


function localEnsureLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S10:LinePortRange', ...
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
    error('S10:LineDriven', ...
        'Destination %s is already driven by another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S10:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

localForcePortConnection(parent, ...
    srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));

end


function [path,idx] = localParseRelativePort(parent,spec)

slash = find(spec=='/',1,'last');

if isempty(slash)
    error('S10:PortSpec','Port spec must be block/port: %s',spec);
end

blockRel = spec(1:slash-1);
idx = str2double(spec(slash+1:end));

if isnan(idx) || idx < 1
    error('S10:PortSpec','Invalid port index in %s.',spec);
end

path = [parent '/' blockRel];

if getSimulinkBlockHandle(path) < 0
    error('S10:PortBlockMissing','Missing block: %s',path);
end

end


function localEnsureTopLevelSourceConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

existingSrc = get_param(ln,'SrcPortHandle');

if existingSrc ~= srcPort
    error('S10:TopConnection', ...
        'Destination for %s is already driven by another source.',desc);
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
    error('S10:ForceConnection', ...
        'Post-assert failed for %s.',desc);
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
    error('S10:BranchDelete', ...
        ['Could not remove only the requested branch. Whole-line deletion ' ...
         'is intentionally forbidden. %s'],ME.message);
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
% Delete a Stage10-owned block without ever deleting a shared SOURCE line.
% Incoming ports are disconnected branch-by-branch. Outgoing lines may be
% removed as whole lines because this Stage10-owned block is their source.

if getSimulinkBlockHandle(blockPath) < 0
    return;
end

parent = get_param(blockPath,'Parent');

try
    ph = get_param(blockPath,'PortHandles');

    % Incoming connections: branch-safe only.
    incomingFields = {'Inport','Enable','Trigger','Ifaction','Reset'};

    for i = 1:numel(incomingFields)
        fld = incomingFields{i};

        if ~isfield(ph,fld)
            continue;
        end

        ports = ph.(fld);

        for j = 1:numel(ports)
            try
                localDisconnectDestinationBranch(parent,ports(j));
            catch ME
                error('S10:OwnedBlockIncomingDelete', ...
                    'Could not safely disconnect %s incoming port: %s', ...
                    blockPath,ME.message);
            end
        end
    end

    % Outgoing connections: the Stage10-owned block is the source, so all
    % these lines disappear with it anyway.
    if isfield(ph,'Outport')
        outLines = [];

        for j = 1:numel(ph.Outport)
            try
                ln = get_param(ph.Outport(j),'Line');
            catch
                ln = -1;
            end

            if ~isequal(ln,-1)
                outLines(end+1) = ln; %#ok<AGROW>
            end
        end

        outLines = unique(outLines(outLines >= 0));

        for j = 1:numel(outLines)
            try
                delete_line(outLines(j));
            catch
            end
        end
    end
catch ME
    if startsWith(ME.identifier,'S10:')
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
        allLines = find_system(subsys, ...
            'FindAll','on', ...
            'SearchDepth',1, ...
            'MatchFilter',@Simulink.match.allVariants, ...
            'Type','line');
    catch
        allLines = find_system(subsys, ...
            'FindAll','on', ...
            'SearchDepth',1, ...
            'Variants','AllVariants', ...
            'Type','line');
    end

    allLines = unique(allLines(allLines >= 0));

    for i = 1:numel(allLines)
        try
            delete_line(allLines(i));
        catch
        end
    end
catch
end

try
    inside = find_system(subsys, ...
        'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'Type','Block');
catch
    inside = find_system(subsys, ...
        'SearchDepth',1, ...
        'Variants','AllVariants', ...
        'Type','Block');
end

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


function localAssertSingleGlobalGoto(mdl,tag)

try
    gotos = find_system(mdl, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'MatchFilter',@Simulink.match.allVariants, ...
        'BlockType','Goto');
catch
    gotos = find_system(mdl, ...
        'LookUnderMasks','all', ...
        'FollowLinks','on', ...
        'Variants','AllVariants', ...
        'BlockType','Goto');
end

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
    error('S10:GlobalGotoCount', ...
        'Expected exactly one Goto for tag %s, found %d.',tag,numel(hits));
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
y = 80;

candidate = [x y x+w y+h];

if localRectOverlaps(candidate,rects)
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

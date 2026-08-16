function S11_K26_V5_LOCAL15_S5_MODE_MANAGER_SHADOW
% S11_K26_V5_LOCAL15_S5_MODE_MANAGER_SHADOW
%
% LOCAL15 Stage 11
%
% PURPOSE
% -------
% Build the mode/safety decision FOUNDATION for the EXISTING strategies:
%
%   S5  Anti-islanding
%   S14 Black start
%   S15 Grid/island seamless transition
%
% This stage is deliberately SHADOW ONLY.
% It does NOT open the PCC breaker, does NOT change GridOn/Droop/Fref/Vref,
% and does NOT modify the already-validated P/Q physical control routes.
%
% The most important S11 rule is:
%
%   Original S5 raw result is preserved exactly for status/alarm/metric/cmd
%   BUT actual electrical islanding qualification EXCLUDES communication.
%
% Original S5:
%   islandScore =
%       abs(F-50)>ifd
%       OR abs(V/Vn-1)>ivd
%       OR comm<0.5
%
% S11 execution qualifier:
%   electrical_bad =
%       abs(F-50)>ifd
%       OR abs(V/Vn-1)>ivd
%
% Therefore:
%   communication loss alone may still make raw S5/S15 report risk,
%   but it MUST NOT create an electrical island-transition request.
%
% This is essential for the paper communication-outage case, where the
% microgrid remains physically connected while communication is abnormal.
%
% S11 also creates AA15_Mode_Manager with the frozen mode encoding:
%   0 GRID_CONNECTED_NORMAL
%   1 GRID_CONNECTED_EMERGENCY
%   2 ISLANDING
%   3 ISLANDED              (reserved for later physical executor)
%   4 BLACK_START
%   5 RESYNCHRONIZATION     (reserved for later physical executor)
%   6 FAULT_SAFE            (reserved for later physical executor)
%
% Current S11 shadow priority:
%   BLACK_START request
%       >
%   qualified S5 + enabled/raw S15 transition request
%       >
%   S8 emergency stage
%       >
%   GRID_CONNECTED_NORMAL
%
% S11 outputs mode permissions for future executors:
%   allow_normal_p
%   allow_normal_q
%   allow_s6
%
% IMPORTANT:
%   These permission signals are NOT connected into S10/S09/S04 yet.
%   S11 is only a verified decision layer. S12+ will use them when real
%   breaker/GFM/GFL execution is implemented.
%
% GROUP28
% -------
% S10 total = 141 scalar signals.
% S11 appends 32 scalar signals.
% Final total = 173 scalar signals.
% Expected aa15_strategy_data MAT after a future Build:
%   174 rows = Target Time + 173 signals.
%
% S11 diag32 order (Group28 scalar positions 142..173):
%   142 S5_status
%   143 S5_alarm
%   144 S5_metric
%   145 S5_cmd_raw
%   146 S14_status
%   147 S14_alarm
%   148 S14_metric
%   149 S14_cmd_raw
%   150 S15_status
%   151 S15_alarm
%   152 S15_metric
%   153 S15_cmd_raw
%   154 strategy_V
%   155 strategy_F
%   156 strategy_comm
%   157 strategy_Vn
%   158 strategy_ifd
%   159 strategy_ivd
%   160 system_mode
%   161 mode_reason
%   162 s5_v_bad
%   163 s5_f_bad
%   164 s5_electrical_bad
%   165 s5_comm_bad
%   166 s5_comm_only_raw
%   167 s5_execute_request
%   168 s15_transition_request
%   169 s14_blackstart_request
%   170 allow_normal_p
%   171 allow_normal_q
%   172 allow_s6
%   173 emergency_active
%
% SCRIPT SAFETY
% -------------
% - mdl = bdroot(gcs)
% - backup first
% - verifies frozen S10 foundation
% - repair-safe cleanup of partial S11 before first update
% - shared source branches are never deleted as whole lines
% - strategy vectors use explicit Demux15
% - exact electrical evidence taps are branched from the REAL strategy inputs
% - no physical plant route is modified
% - Variant-aware find_system searches are used
%
% BUILD POLICY
% ------------
% S11 is SHADOW ONLY. After S11 structural success, DO NOT Build yet.
% Proceed directly to S12, then perform the next strategic Build after S12
% introduces real mode/black-start execution changes.

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 11 - S5 Qualifier + Mode Manager SHADOW\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S11:NoActiveModel', ...
        'No active model. Open K26_V5 and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
stack = [sm '/AA15_LOCAL_CONTROL_STACK'];
group28Mux = [sm '/AA15_GROUP28_MUX'];
op28 = [sm '/AA15_OpWriteFile_Group28'];

if getSimulinkBlockHandle(sm) < 0
    error('S11:MissingSM','Missing SM_Master.');
end
if getSimulinkBlockHandle(stack) < 0
    error('S11:MissingStack','Missing AA15_LOCAL_CONTROL_STACK.');
end
if getSimulinkBlockHandle(group28Mux) < 0
    error('S11:MissingGroup28','Missing AA15_GROUP28_MUX.');
end
if getSimulinkBlockHandle(op28) < 0
    error('S11:MissingOp28','Missing AA15_OpWriteFile_Group28.');
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S11:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE11_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S11:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify frozen S10 foundation.
% =========================================================================
fprintf('\n--- Verify S10 foundation ---\n');

diagNames = {
    'AA15_STAGE03_DIAGNOSTICS'
    'AA15_STAGE04_AGC_DIAGNOSTICS'
    'AA15_STAGE05_ROUTER_DIAGNOSTICS'
    'AA15_STAGE06_EXECFAULT_DIAGNOSTICS'
    'AA15_STAGE07_TAKEOVER_DIAGNOSTICS'
    'AA15_STAGE08_P_DIAGNOSTICS'
    'AA15_STAGE09_Q_DIAGNOSTICS'
    'AA15_STAGE10_P_AUX_DIAGNOSTICS'
};

diagBlocks = cell(8,1);

for i = 1:8
    diagBlocks{i} = [sm '/' diagNames{i}];

    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S11:MissingPrerequisite', ...
            'Missing S10 prerequisite: %s',diagBlocks{i});
    end
end

requiredBlocks = {
    [stack '/AA15_Request_Normalizer']
    [stack '/AA15_Request_Normalizer_P_Extension']
    [stack '/AA15_P_Objective_Constraint_Manager']
    [stack '/AA15_Arbitrated_Baseline_AGC']
    [stack '/AA15_Execution_Mapper']
    [stack '/AA15_P_Auxiliary_Executor']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Execution_Fault_Injector']
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_S3_AVC_Normalizer']
    [stack '/AA15_Q_Allocator_Router']
};

for i = 1:numel(requiredBlocks)
    if getSimulinkBlockHandle(requiredBlocks{i}) < 0
        error('S11:MissingPrerequisite', ...
            'Missing S10 prerequisite: %s',requiredBlocks{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));

if ~(n28 == 8 || n28 == 9)
    error('S11:Group28Inputs', ...
        'Expected Group28 Inputs=8 (S10) or 9 (partial S11), found %g.',n28);
end

for i = 1:8
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);

    if p ~= i
        error('S11:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

% Protect the real P/Q plant interfaces from any S11 edit.
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

muxPaths = cell(6,1);
prefSrcBefore = cell(6,1);
qSrcBefore = cell(6,1);

for i = 1:6
    muxPaths{i} = localFindUniqueNamedBlock(sm,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 7
        error('S11:MuxPorts','%s has fewer than 7 inputs.',muxPaths{i});
    end

    [p6,~] = localGetDestinationSource(ph.Inport(6));
    [p7,~] = localGetDestinationSource(ph.Inport(7));

    if ~strcmp(get_param(p6,'BlockType'),'From') || ...
            ~strcmp(get_param(p6,'GotoTag'),prefTags{i})
        error('S11:PrefFoundation', ...
            '%s input6 Pref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(p7,'BlockType'),'From') || ...
            ~strcmp(get_param(p7,'GotoTag'),qTags{i})
        error('S11:QFoundation', ...
            '%s input7 Qref route is unexpected.',muxPaths{i});
    end

    prefSrcBefore{i} = p6;
    qSrcBefore{i} = p7;
end

% Protect S10 real LOCAL15 insertion into Router inputs7..13.
execMap = [stack '/AA15_Execution_Mapper'];
aux = [stack '/AA15_P_Auxiliary_Executor'];
router = [stack '/AA15_Command_Source_Router'];

auxPH = get_param(aux,'PortHandles');
routerPH = get_param(router,'PortHandles');

if numel(auxPH.Outport) < 7 || numel(routerPH.Inport) < 13
    error('S11:S10RouterPorts','S10 auxiliary/router ports are unexpected.');
end

for i = 1:7
    ln = get_param(routerPH.Inport(6+i),'Line');

    if isequal(ln,-1) || get_param(ln,'SrcPortHandle') ~= auxPH.Outport(i)
        error('S11:S10RouterRoute', ...
            'Router local input%d is not driven by S10 auxiliary output%d.', ...
            6+i,i);
    end
end

fprintf('[OK] S10 Group28, P route, Q route and Router insertion verified.\n');

% =========================================================================
% 2. Discover exact current strategy block and exact electrical evidence
%    inputs used by the original S5.
% =========================================================================
fprintf('\n--- Discover exact S5 electrical evidence sources ---\n');

strategy = [sm '/Advanced_Microgrid_15_Strategies'];

if getSimulinkBlockHandle(strategy) < 0
    hits = localFindBlocksByName(sm,'Advanced_Microgrid_15_Strategies');

    if numel(hits) ~= 1
        error('S11:StrategyBlock', ...
            'Expected one Advanced_Microgrid_15_Strategies, found %d.', ...
            numel(hits));
    end

    strategy = hits{1};
end

sph = get_param(strategy,'PortHandles');

if numel(sph.Inport) < 22
    error('S11:StrategyPorts', ...
        'Strategy block exposes only %d inputs; expected at least 22.', ...
        numel(sph.Inport));
end

% Current frozen Advanced_Strategy_Core input order:
% 4=V, 5=F, 10=comm, 16=Vn, 21=ifd, 22=ivd.
tapIdx = [4 5 10 16 21 22];
tapMeaning = {'V','F','comm','Vn','ifd','ivd'};
strategySrcPorts = zeros(1,6);

for i = 1:6
    ln = get_param(sph.Inport(tapIdx(i)),'Line');

    if isequal(ln,-1)
        error('S11:StrategyInputUnconnected', ...
            'Strategy input%d (%s) is unconnected.', ...
            tapIdx(i),tapMeaning{i});
    end

    src = get_param(ln,'SrcPortHandle');

    if isempty(src) || src < 0
        error('S11:StrategyInputSource', ...
            'Cannot resolve strategy input%d (%s) source.', ...
            tapIdx(i),tapMeaning{i});
    end

    strategySrcPorts(i) = src;

    fprintf('[OK] input%02d %-5s <- %s\n', ...
        tapIdx(i),tapMeaning{i}, ...
        getfullname(get_param(src,'Parent')));
end

strategyParent = get_param(strategy,'Parent');

% =========================================================================
% 3. Repair-safe cleanup of a partial S11 BEFORE first model update.
% =========================================================================
fprintf('\n--- Clean stale partial S11 BEFORE model update ---\n');

tap = [strategyParent '/AA15_S11_STRATEGY_MODE_TAPS'];
norm = [stack '/AA15_S5_S14_S15_Normalizer'];
modeMgr = [stack '/AA15_Mode_Manager'];
s11Diag = [sm '/AA15_STAGE11_MODE_DIAGNOSTICS'];

oldDiagPort = localFindExistingLogPort(s11Diag,group28Mux);

if oldDiagPort > 0
    if oldDiagPort ~= 9
        error('S11:OldDiagPort', ...
            'Existing S11 diagnostics is on unexpected Group28 input%d.', ...
            oldDiagPort);
    end

    localDisconnectLogInput(group28Mux,9);
end

if getSimulinkBlockHandle(s11Diag) >= 0
    localDeleteBlockIfExists(s11Diag);
    fprintf('[DELETE] stale %s\n',s11Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 9
    ph28 = get_param(group28Mux,'PortHandles');

    if numel(ph28.Inport) < 9
        error('S11:Group28RepairPort','Cannot inspect Group28 input9.');
    end

    ln9 = get_param(ph28.Inport(9),'Line');

    if ~isequal(ln9,-1)
        error('S11:Group28RepairBusy', ...
            'Group28 input9 is still connected during repair.');
    end

    set_param(group28Mux,'Inputs','8');
    fprintf('[RESTORE] Group28 Inputs: 9 -> 8.\n');
end

for i = 1:12
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S11_NORM_%02d',i)]);
end

for i = 1:14
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S11_MODE_%02d',i)]);
end

if getSimulinkBlockHandle(modeMgr) >= 0
    localDeleteBlockIfExists(modeMgr);
    fprintf('[DELETE] stale %s\n',modeMgr);
end

if getSimulinkBlockHandle(norm) >= 0
    localDeleteBlockIfExists(norm);
    fprintf('[DELETE] stale %s\n',norm);
end

if getSimulinkBlockHandle(tap) >= 0
    localDeleteBlockIfExists(tap);
    fprintf('[DELETE] stale %s\n',tap);
end

fprintf('[OK] Partial S11 artifacts removed. No model update performed yet.\n');

% =========================================================================
% 4. Build exact electrical evidence tap from the REAL S5 input sources.
% =========================================================================
fprintf('\n--- Build exact S5 electrical evidence tap ---\n');

[xTap,yTap] = localFindFreePosition(strategyParent,360,260,260);

add_block('simulink/Ports & Subsystems/Subsystem',tap, ...
    'Position',[xTap yTap xTap+360 yTap+260]);
localDeleteSubsystemContents(tap);

tapInNames = {'V','F','comm','Vn','ifd','ivd'};
tapTags = {
    'AA15_S11_STRAT_V'
    'AA15_S11_STRAT_F'
    'AA15_S11_STRAT_COMM'
    'AA15_S11_STRAT_VN'
    'AA15_S11_STRAT_IFD'
    'AA15_S11_STRAT_IVD'
};

for i = 1:6
    y = 35 + (i-1)*38;

    add_block('simulink/Ports & Subsystems/In1', ...
        [tap '/' tapInNames{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);

    add_block('simulink/Signal Routing/Goto', ...
        [tap '/' sprintf('GOTO_TAP_%02d',i)], ...
        'GotoTag',tapTags{i}, ...
        'TagVisibility','global', ...
        'Position',[105 y-3 325 y+19]);

    localEnsureLine(tap, ...
        [tapInNames{i} '/1'], ...
        sprintf('GOTO_TAP_%02d/1',i));
end

tapPH = get_param(tap,'PortHandles');

if numel(tapPH.Inport) ~= 6
    error('S11:TapPorts','S11 electrical tap expected 6 inputs.');
end

for i = 1:6
    localEnsureTopLevelSourceConnection(strategyParent, ...
        strategySrcPorts(i),tapPH.Inport(i), ...
        sprintf('strategy %s evidence tap',tapMeaning{i}));
end

% =========================================================================
% 5. Build S5/S14/S15 normalizer from explicit Demux15 signals.
% =========================================================================
fprintf('\n--- Build S5/S14/S15 normalizer ---\n');

xNorm = localNextRightX(stack,120);

add_block('simulink/Ports & Subsystems/Subsystem',norm, ...
    'Position',[xNorm 1490 xNorm+440 1870]);
localDeleteSubsystemContents(norm);

normIn = {'status15','alarm15','metric15','cmd15'};
demuxNames = {'DEMUX_STATUS15','DEMUX_ALARM15','DEMUX_METRIC15','DEMUX_CMD15'};

for i = 1:4
    y = 45 + (i-1)*75;

    add_block('simulink/Ports & Subsystems/In1', ...
        [norm '/' normIn{i}], ...
        'Port',num2str(i), ...
        'Position',[20 y 50 y+16]);

    add_block('simulink/Signal Routing/Demux', ...
        [norm '/' demuxNames{i}], ...
        'Outputs','15', ...
        'Position',[110 y-20 140 y+48]);

    localEnsureLine(norm,[normIn{i} '/1'],[demuxNames{i} '/1']);
end

normOut = {
    's5_status'
    's5_alarm'
    's5_metric'
    's5_cmd'
    's14_status'
    's14_alarm'
    's14_metric'
    's14_cmd'
    's15_status'
    's15_alarm'
    's15_metric'
    's15_cmd'
};

normSrc = {
    'DEMUX_STATUS15/5'
    'DEMUX_ALARM15/5'
    'DEMUX_METRIC15/5'
    'DEMUX_CMD15/5'
    'DEMUX_STATUS15/14'
    'DEMUX_ALARM15/14'
    'DEMUX_METRIC15/14'
    'DEMUX_CMD15/14'
    'DEMUX_STATUS15/15'
    'DEMUX_ALARM15/15'
    'DEMUX_METRIC15/15'
    'DEMUX_CMD15/15'
};

for i = 1:12
    col = floor((i-1)/6);
    row = mod(i-1,6);
    x = 300 + col*90;
    y = 30 + row*52;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [norm '/' normOut{i}], ...
        'Port',num2str(i), ...
        'Position',[x y x+30 y+16]);

    localEnsureLine(norm,normSrc{i},[normOut{i} '/1']);
end

% Branch existing stack vector inputs1..4.
for i = 1:4
    stackIn = localFindStackInportByNumber(stack,i);
    srcPH = get_param(stackIn,'PortHandles');
    dstPH = get_param(norm,'PortHandles');

    if isempty(srcPH.Outport) || numel(dstPH.Inport) < i
        error('S11:NormTopPorts', ...
            'Could not materialize stack input%d -> S11 normalizer input%d.', ...
            i,i);
    end

    localEnsureTopLevelSourceConnection(stack, ...
        srcPH.Outport(1),dstPH.Inport(i), ...
        sprintf('stack vector input%d -> S11 normalizer',i));
end

normTags = {
    'AA15_S5_STATUS'
    'AA15_S5_ALARM'
    'AA15_S5_METRIC'
    'AA15_S5_CMD_RAW'
    'AA15_S14_STATUS'
    'AA15_S14_ALARM'
    'AA15_S14_METRIC'
    'AA15_S14_CMD_RAW'
    'AA15_S15_STATUS'
    'AA15_S15_ALARM'
    'AA15_S15_METRIC'
    'AA15_S15_CMD_RAW'
};

normPos = get_param(norm,'Position');

for i = 1:12
    gotoName = sprintf('GOTO_S11_NORM_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',normTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/6);
    row = mod(i-1,6);
    x = normPos(3)+45+col*225;
    y = normPos(2)+20+row*45;

    set_param(p,'Position',[x y x+205 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_S5_S14_S15_Normalizer/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 6. Build AA15_Mode_Manager (shadow decision layer).
% =========================================================================
fprintf('\n--- Build AA15_Mode_Manager SHADOW ---\n');

xMode = normPos(3)+555;

add_block('simulink/Ports & Subsystems/Subsystem',modeMgr, ...
    'Position',[xMode 1435 xMode+610 2000]);
localDeleteSubsystemContents(modeMgr);

modeInputTags = {
    'AA15_S5_STATUS'
    'AA15_S5_ALARM'
    'AA15_S5_METRIC'
    'AA15_S5_CMD_RAW'
    'AA15_S8_STATUS_STAGE'
    'AA15_S14_STATUS'
    'AA15_S14_ALARM'
    'AA15_S14_METRIC'
    'AA15_S14_CMD_RAW'
    'AA15_S15_STATUS'
    'AA15_S15_ALARM'
    'AA15_S15_METRIC'
    'AA15_S15_CMD_RAW'
    'AA15_S11_STRAT_V'
    'AA15_S11_STRAT_F'
    'AA15_S11_STRAT_COMM'
    'AA15_S11_STRAT_VN'
    'AA15_S11_STRAT_IFD'
    'AA15_S11_STRAT_IVD'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_EXEC_S05'
    'CFG15_EXEC_S08'
    'CFG15_EXEC_S14'
    'CFG15_EXEC_S15'
};

for i = 1:25
    col = floor((i-1)/13);
    row = mod(i-1,13);
    x = 20 + col*235;
    y = 20 + row*37;

    add_block('simulink/Signal Routing/From', ...
        [modeMgr '/' sprintf('FROM_MODE_%02d',i)], ...
        'GotoTag',modeInputTags{i}, ...
        'Position',[x y x+210 y+20]);
end

modeMF = [modeMgr '/AA15_Mode_Manager_Core'];

add_block('simulink/User-Defined Functions/MATLAB Function',modeMF, ...
    'Position',[500 75 1015 585]);

modeChart = localGetEMChartByPath(modeMF);
modeChart.Script = localModeManagerScript();

modeOut = {
    'system_mode'
    'mode_reason'
    's5_v_bad'
    's5_f_bad'
    's5_electrical_bad'
    's5_comm_bad'
    's5_comm_only_raw'
    's5_execute_request'
    's15_transition_request'
    's14_blackstart_request'
    'allow_normal_p'
    'allow_normal_q'
    'allow_s6'
    'emergency_active'
};

for i = 1:14
    y = 35 + (i-1)*34;

    add_block('simulink/Ports & Subsystems/Out1', ...
        [modeMgr '/' modeOut{i}], ...
        'Port',num2str(i), ...
        'Position',[1110 y 1140 y+16]);
end

for i = 1:25
    localEnsureLine(modeMgr, ...
        sprintf('FROM_MODE_%02d/1',i), ...
        sprintf('AA15_Mode_Manager_Core/%d',i));
end

for i = 1:14
    localEnsureLine(modeMgr, ...
        sprintf('AA15_Mode_Manager_Core/%d',i), ...
        [modeOut{i} '/1']);
end

modeTags = {
    'AA15_SYSTEM_MODE'
    'AA15_MODE_REASON'
    'AA15_S5_V_BAD'
    'AA15_S5_F_BAD'
    'AA15_S5_ELECTRICAL_BAD'
    'AA15_S5_COMM_BAD'
    'AA15_S5_COMM_ONLY_RAW'
    'AA15_S5_EXECUTE_REQUEST'
    'AA15_S15_TRANSITION_REQUEST'
    'AA15_S14_BLACKSTART_REQUEST'
    'AA15_MODE_ALLOW_NORMAL_P'
    'AA15_MODE_ALLOW_NORMAL_Q'
    'AA15_MODE_ALLOW_S6'
    'AA15_MODE_EMERGENCY_ACTIVE'
};

modePos = get_param(modeMgr,'Position');

for i = 1:14
    gotoName = sprintf('GOTO_S11_MODE_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',modeTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/7);
    row = mod(i-1,7);
    x = modePos(3)+45+col*250;
    y = modePos(2)+20+row*48;

    set_param(p,'Position',[x y x+225 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_Mode_Manager/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 7. Build S11 diagnostics BEFORE first update.
% =========================================================================
fprintf('\n--- Build S11 diag32 ---\n');

[dx,dy] = localFindFreePosition(sm,520,560,420);

add_block('simulink/Ports & Subsystems/Subsystem',s11Diag, ...
    'Position',[dx dy dx+520 dy+560]);
localDeleteSubsystemContents(s11Diag);

diagTags = {
    'AA15_S5_STATUS'
    'AA15_S5_ALARM'
    'AA15_S5_METRIC'
    'AA15_S5_CMD_RAW'
    'AA15_S14_STATUS'
    'AA15_S14_ALARM'
    'AA15_S14_METRIC'
    'AA15_S14_CMD_RAW'
    'AA15_S15_STATUS'
    'AA15_S15_ALARM'
    'AA15_S15_METRIC'
    'AA15_S15_CMD_RAW'
    'AA15_S11_STRAT_V'
    'AA15_S11_STRAT_F'
    'AA15_S11_STRAT_COMM'
    'AA15_S11_STRAT_VN'
    'AA15_S11_STRAT_IFD'
    'AA15_S11_STRAT_IVD'
    'AA15_SYSTEM_MODE'
    'AA15_MODE_REASON'
    'AA15_S5_V_BAD'
    'AA15_S5_F_BAD'
    'AA15_S5_ELECTRICAL_BAD'
    'AA15_S5_COMM_BAD'
    'AA15_S5_COMM_ONLY_RAW'
    'AA15_S5_EXECUTE_REQUEST'
    'AA15_S15_TRANSITION_REQUEST'
    'AA15_S14_BLACKSTART_REQUEST'
    'AA15_MODE_ALLOW_NORMAL_P'
    'AA15_MODE_ALLOW_NORMAL_Q'
    'AA15_MODE_ALLOW_S6'
    'AA15_MODE_EMERGENCY_ACTIVE'
};

for i = 1:32
    col = floor((i-1)/16);
    row = mod(i-1,16);
    x = 20 + col*235;
    y = 18 + row*30;

    add_block('simulink/Signal Routing/From', ...
        [s11Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+210 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s11Diag '/AA15_STAGE11_DIAG32'], ...
    'Inputs','32', ...
    'Position',[535 30 570 525]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s11Diag '/diag32'], ...
    'Port','1', ...
    'Position',[635 265 665 281]);

for i = 1:32
    localEnsureLine(s11Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE11_DIAG32/%d',i));
end

localEnsureLine(s11Diag,'AA15_STAGE11_DIAG32/1','diag32/1');

% =========================================================================
% 8. FIRST model update after the COMPLETE S11 shadow structure exists.
% =========================================================================
fprintf('\n--- First compile/update after COMPLETE S11 structure ---\n');

set_param(mdl,'SimulationCommand','update');

for i = 1:4
    dph = get_param([norm '/' demuxNames{i}],'PortHandles');

    if numel(dph.Outport) ~= 15
        error('S11:DemuxWidth', ...
            '%s expected 15 outputs, found %d.', ...
            [norm '/' demuxNames{i}],numel(dph.Outport));
    end
end

mfPorts = get_param(modeMF,'Ports');

if mfPorts(1) ~= 25 || mfPorts(2) ~= 14
    error('S11:ModePorts', ...
        'Mode Manager expected 25-in/14-out, found %d/%d.', ...
        mfPorts(1),mfPorts(2));
end

fprintf('[OK] Strategy vectors compiled as Demux15.\n');
fprintf('[OK] Mode Manager compiled 25 inputs / 14 outputs.\n');

% =========================================================================
% 9. Append S11 diag32 to Group28 input9.
% =========================================================================
fprintf('\n--- Append S11 diag32 to Group28 input9 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 8
    error('S11:Group28BeforeAppend', ...
        'Expected Group28 Inputs=8 before S11 append.');
end

set_param(group28Mux,'Inputs','9');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s11Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S11:DiagPort','S11 diagnostics expected exactly one output.');
end
if numel(muxPH28.Inport) < 9
    error('S11:Group28Input9','Group28 input9 did not materialize.');
end

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(9), ...
    'S11 diag32 -> Group28 input9');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 10. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S11 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 9
    error('S11:Group28Final','Group28 must have 9 inputs after S11.');
end

for i = 1:8
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);

    if p ~= i
        error('S11:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.', ...
            diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s11Diag,group28Mux) ~= 9
    error('S11:S11DiagSlot','S11 diagnostics is not Group28 input9.');
end

% Verify S10 Router path remains untouched.
auxPH = get_param(aux,'PortHandles');
routerPH = get_param(router,'PortHandles');

for i = 1:7
    ln = get_param(routerPH.Inport(6+i),'Line');

    if isequal(ln,-1) || get_param(ln,'SrcPortHandle') ~= auxPH.Outport(i)
        error('S11:RouterPostAssert', ...
            'Router local input%d changed during S11.',6+i);
    end
end

% Verify all real physical P/Q routes remain unchanged.
for i = 1:6
    ph = get_param(muxPaths{i},'PortHandles');
    [p6,~] = localGetDestinationSource(ph.Inport(6));
    [p7,~] = localGetDestinationSource(ph.Inport(7));

    if ~strcmp(p6,prefSrcBefore{i}) || ...
            ~strcmp(get_param(p6,'GotoTag'),prefTags{i})
        error('S11:PrefPostAssert', ...
            '%s input6 Pref route changed during S11.',muxPaths{i});
    end

    if ~strcmp(p7,qSrcBefore{i}) || ...
            ~strcmp(get_param(p7,'GotoTag'),qTags{i})
        error('S11:QPostAssert', ...
            '%s input7 Qref route changed during S11.',muxPaths{i});
    end
end

allTags = [tapTags; normTags; modeTags];

for i = 1:numel(allTags)
    localAssertSingleGlobalGoto(mdl,allTags{i});
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE11 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Original S5/S14/S15 strategy core : UNCHANGED\n');
fprintf('S5 electrical evidence tap         : PASS\n');
fprintf('S5 communication-only separation   : PASS (structure)\n');
fprintf('S5/S14/S15 Demux15 normalizer      : PASS\n');
fprintf('AA15_Mode_Manager shadow            : PASS\n');
fprintf('Real Pref physical route            : UNCHANGED\n');
fprintf('Real Qref physical route            : UNCHANGED\n');
fprintf('S10 Router insertion                : UNCHANGED\n');
fprintf('Group28                             : 9 physical inputs\n');
fprintf('Group28 total scalar signals        : 173\n');
fprintf('Expected future MAT rows            : 174 (incl. Target Time)\n');
fprintf('Backup                              : %s\n',backupFile);
fprintf('\nNO BUILD NOW: S11 is shadow only.\n');
fprintf('NEXT: proceed directly to S12, then perform the next strategic Build.\n');

end


% =========================================================================
% MATLAB Function source: Mode Manager shadow
% =========================================================================
function txt = localModeManagerScript()

L = {};
L{end+1} = ['function [system_mode,mode_reason,v_bad,f_bad,electrical_bad,' ...
    'comm_bad,comm_only_raw,s5_execute,s15_transition,s14_blackstart,' ...
    'allow_p,allow_q,allow_s6,emergency_active] = ' ...
    'AA15_Mode_Manager_Core(' ...
    's5st,s5al,s5mt,s5cmd,s8stage,' ...
    's14st,s14al,s14mt,s14cmd,' ...
    's15st,s15al,s15mt,s15cmd,' ...
    'V,F,comm,Vn,ifd,ivd,' ...
    'master_enable,control_source,exec_s05,exec_s08,exec_s14,exec_s15)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'system_mode = 0.0;';
L{end+1} = 'mode_reason = 0.0;';
L{end+1} = 'v_bad = 0.0;';
L{end+1} = 'f_bad = 0.0;';
L{end+1} = 'electrical_bad = 0.0;';
L{end+1} = 'comm_bad = 0.0;';
L{end+1} = 'comm_only_raw = 0.0;';
L{end+1} = 's5_execute = 0.0;';
L{end+1} = 's15_transition = 0.0;';
L{end+1} = 's14_blackstart = 0.0;';
L{end+1} = 'allow_p = 1.0;';
L{end+1} = 'allow_q = 1.0;';
L{end+1} = 'allow_s6 = 1.0;';
L{end+1} = 'emergency_active = 0.0;';
L{end+1} = '';
L{end+1} = '% Silence codegen warnings for currently diagnostic-only raw fields.';
L{end+1} = 'dummy = s5st+s5al+s5mt+s14st+s14al+s14mt+s15st+s15al+s15mt;';
L{end+1} = 'if ~finite1(dummy)';
L{end+1} = '    dummy = 0.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Non-finite electrical evidence enters SHADOW fault-safe state.';
L{end+1} = 'if ~finite1(V) || ~finite1(F) || ~finite1(Vn) || ...';
L{end+1} = '   ~finite1(ifd) || ~finite1(ivd) || abs(Vn) < 1e-9';
L{end+1} = '    system_mode = 6.0;';
L{end+1} = '    mode_reason = 90.0;';
L{end+1} = '    allow_p = 0.0;';
L{end+1} = '    allow_q = 0.0;';
L{end+1} = '    allow_s6 = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'vpu = V/max(abs(Vn),1e-9);';
L{end+1} = 'v_bad = double(abs(vpu-1.0) > max(ivd,0.0));';
L{end+1} = 'f_bad = double(abs(F-50.0) > max(ifd,0.0));';
L{end+1} = 'electrical_bad = double((v_bad > 0.5) || (f_bad > 0.5));';
L{end+1} = '';
L{end+1} = 'if finite1(comm)';
L{end+1} = '    comm_bad = double(comm < 0.5);';
L{end+1} = 'else';
L{end+1} = '    comm_bad = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'raw_s5 = double(s5cmd > 0.5);';
L{end+1} = 'comm_only_raw = double(raw_s5 > 0.5 && ...';
L{end+1} = '    comm_bad > 0.5 && electrical_bad < 0.5);';
L{end+1} = '';
L{end+1} = 'local_selected = double(round(control_source) == 1);';
L{end+1} = 'framework_on = double(master_enable > 0.5 && local_selected > 0.5);';
L{end+1} = '';
L{end+1} = '% S5 electrical execute request explicitly excludes communication.';
L{end+1} = 's5_execute = double(framework_on > 0.5 && ...';
L{end+1} = '    exec_s05 > 0.5 && electrical_bad > 0.5);';
L{end+1} = '';
L{end+1} = '% S15 raw strategy arm is still respected, but communication-only';
L{end+1} = '% raw S15 can never pass this electrical qualifier.';
L{end+1} = 's15_transition = double(framework_on > 0.5 && ...';
L{end+1} = '    exec_s15 > 0.5 && s15cmd > 0.5 && s5_execute > 0.5);';
L{end+1} = '';
L{end+1} = '% S14 request remains based on the existing teacher-tested S14 cmd.';
L{end+1} = 's14_blackstart = double(framework_on > 0.5 && ...';
L{end+1} = '    exec_s14 > 0.5 && abs(s14cmd) > 0.5);';
L{end+1} = '';
L{end+1} = '% Shadow priority: BLACK_START > ISLANDING > EMERGENCY > NORMAL.';
L{end+1} = 'if s14_blackstart > 0.5';
L{end+1} = '    system_mode = 4.0;';
L{end+1} = '    mode_reason = 14.0;';
L{end+1} = 'elseif s15_transition > 0.5';
L{end+1} = '    system_mode = 2.0;';
L{end+1} = '    mode_reason = 15.0;';
L{end+1} = 'elseif framework_on > 0.5 && exec_s08 > 0.5 && s8stage > 0.0';
L{end+1} = '    system_mode = 1.0;';
L{end+1} = '    mode_reason = 8.0;';
L{end+1} = '    emergency_active = 1.0;';
L{end+1} = 'else';
L{end+1} = '    system_mode = 0.0;';
L{end+1} = '    mode_reason = 0.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Permissions are advisory in S11; no existing executor reads them yet.';
L{end+1} = 'if system_mode == 0.0';
L{end+1} = '    allow_p = 1.0;';
L{end+1} = '    allow_q = 1.0;';
L{end+1} = '    allow_s6 = 1.0;';
L{end+1} = 'elseif system_mode == 1.0';
L{end+1} = '    allow_p = 1.0;';
L{end+1} = '    allow_q = 1.0;';
L{end+1} = '    allow_s6 = 0.0;';
L{end+1} = 'else';
L{end+1} = '    allow_p = 0.0;';
L{end+1} = '    allow_q = 0.0;';
L{end+1} = '    allow_s6 = 0.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if dummy > 1e300';
L{end+1} = '    mode_reason = mode_reason + 0.0;';
L{end+1} = 'end';
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
    error('S11:EMChartPath', ...
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
    error('S11:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    error('S11:UndrivenDestination','Protected destination is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');

if isempty(srcPort) || srcPort < 0
    error('S11:NoSourcePort','Could not resolve source port.');
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
    error('S11:StackInport', ...
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
    error('S11:LinePortRange', ...
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
    error('S11:LineDriven', ...
        'Destination %s is already driven by another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S11:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

localForcePortConnection(parent, ...
    srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));

end


function [path,idx] = localParseRelativePort(parent,spec)

slash = find(spec=='/',1,'last');

if isempty(slash)
    error('S11:PortSpec','Port spec must be block/port: %s',spec);
end

blockRel = spec(1:slash-1);
idx = str2double(spec(slash+1:end));

if isnan(idx) || idx < 1
    error('S11:PortSpec','Invalid port index in %s.',spec);
end

path = [parent '/' blockRel];

if getSimulinkBlockHandle(path) < 0
    error('S11:PortBlockMissing','Missing block: %s',path);
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
    error('S11:TopConnection', ...
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
    error('S11:ForceConnection', ...
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
    error('S11:BranchDelete', ...
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
% Delete a Stage11-owned block without deleting shared source trunks.

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
            try
                localDisconnectDestinationBranch(parent,ports(j));
            catch ME
                error('S11:OwnedBlockIncomingDelete', ...
                    'Could not safely disconnect %s incoming port: %s', ...
                    blockPath,ME.message);
            end
        end
    end

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
    if startsWith(ME.identifier,'S11:')
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
    error('S11:GlobalGotoCount', ...
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

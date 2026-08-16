function S12_K26_V5_LOCAL15_MODE_ACTUATOR_ROUTER_TRANSPARENT_TAKEOVER
% S12_K26_V5_LOCAL15_MODE_ACTUATOR_ROUTER_TRANSPARENT_TAKEOVER
%
% LOCAL15 Stage 12
%
% PURPOSE
% -------
% Insert a REAL but TRANSPARENT device-mode execution interface into the
% six existing converter control vectors.
%
% S12 changes ONLY:
%   physical input5 = Droop_On
%   physical input8 = GridOn
%
% It deliberately does NOT change:
%   input3 Fref
%   input4 Vref
%   input6 Pref
%   input7 Qref
%   PCC breaker
%
% Why this stage exists:
%   S11 already computes system_mode / S5 electrical qualification in SHADOW.
%   Before S13 can perform real islanding/black-start execution, the six
%   device mode inputs need a unified, reversible execution interface.
%
% S12 therefore:
%
%   exact current legacy Droop/GridOn sources
%        -> AA15_S12_MODE_LEGACY_TAPS
%        -> global LEGACY mode tags
%        -> AA15_Device_Mode_Router
%        -> FINAL_DROOP_* / FINAL_GRIDON_*
%        -> six real device Mux input5 / input8
%
% IMPORTANT:
%   New parameter CFG15_MODE_ACTUATION_ENABLE defaults to 0.
%
%   With CFG15_MODE_ACTUATION_ENABLE = 0:
%       FINAL_DROOP  == exact legacy Droop source
%       FINAL_GRIDON == exact legacy GridOn source
%
%   Therefore immediately after S12 the physical model is numerically
%   transparent even though the real routes pass through the new interface.
%
% Future active semantics (used by S13/S14):
%   when:
%       MASTER_ENABLE=1
%       CONTROL_SOURCE=1
%       CFG15_MODE_ACTUATION_ENABLE=1
%       system_mode in {2,3,4,5}
%
%   exactly one ESS is selected as GFM master:
%       GridOn(master) = 0    (GFM)
%       Droop(master)  = 1
%
%   all other devices:
%       GridOn = 1            (GFL)
%       Droop  = legacy value
%
% Master selection:
%   mode 4 BLACK_START -> CFG15_BLACKSTART_MASTER
%   modes 2/3/5        -> CFG15_ISLAND_MASTER
%
% Existing model semantics:
%   GridOn = 1 -> GFL
%   GridOn = 0 -> GFM
%
% S12 does NOT open the PCC breaker. Therefore leave
% CFG15_MODE_ACTUATION_ENABLE=0 until S13 installs the breaker/state-machine
% execution layer and a coordinated test is performed.
%
% GROUP28
% -------
% S11 total scalar signals = 173.
% S12 appends 29:
%   174..179 legacy Droop [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   180..185 legacy GridOn [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   186..191 final Droop [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   192..197 final GridOn [PV1 PV2 ESS1 ESS2 EV1 EV2]
%   198      CFG15_MODE_ACTUATION_ENABLE
%   199      selected_master (0 none, 1 ESS1, 2 ESS2)
%   200      system_mode
%   201      override_active
%   202      route_valid
%
% Final Group28 = 202 scalar signals.
% Expected MAT after Build = 203 rows including Target Time.
%
% SCRIPT SAFETY
% -------------
% - mdl = bdroot(gcs)
% - backup first
% - verifies S11 foundation and all real P/Q routes
% - captures exact legacy source PORTS before any real mode edit
% - retains legacy sources; nothing is deleted
% - uses branch-safe destination reconnection only
% - repair-safe when a previous S12 run partially inserted FINAL mode Froms
% - no SimulationCommand='update' while a known half-built router exists
% - default actuation enable = 0
% - exact post-assertions on Mux inputs3/4/5/6/7/8
% - Variant-aware find_system
%
% BUILD POLICY
% ------------
% S12 changes REAL physical Droop/GridOn routes.
% After STAGE12 COMPLETE:
%   Build -> Load -> baseline transparent regression is REQUIRED.
%
% Do not test actual islanding/GFM override yet; S13 will add the coordinated
% PCC-breaker/state-machine layer.

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 12 - Mode Actuator Router Transparent Takeover\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S12:NoActiveModel', ...
        'No active model. Open K26_V5 and click inside it first.');
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
        error('S12:MissingTop','Missing required block: %s',requiredTop{i});
    end
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S12:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE12_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Backup       : %s\n',backupFile);

set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S12:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

% =========================================================================
% 1. Verify frozen S11 foundation.
% =========================================================================
fprintf('\n--- Verify S11 foundation ---\n');

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
};

diagBlocks = cell(9,1);
for i = 1:9
    diagBlocks{i} = [sm '/' diagNames{i}];
    if getSimulinkBlockHandle(diagBlocks{i}) < 0
        error('S12:MissingPrerequisite', ...
            'Missing S11 prerequisite: %s',diagBlocks{i});
    end
end

requiredS11 = {
    [stack '/AA15_Mode_Manager']
    [stack '/AA15_S5_S14_S15_Normalizer']
    [stack '/AA15_P_Auxiliary_Executor']
    [stack '/AA15_Command_Source_Router']
    [stack '/AA15_Active_P_Takeover']
    [stack '/AA15_Q_Allocator_Router']
};

for i = 1:numel(requiredS11)
    if getSimulinkBlockHandle(requiredS11{i}) < 0
        error('S12:MissingPrerequisite', ...
            'Missing S11 prerequisite: %s',requiredS11{i});
    end
end

n28 = str2double(get_param(group28Mux,'Inputs'));
if ~(n28 == 9 || n28 == 10)
    error('S12:Group28Inputs', ...
        'Expected Group28 Inputs=9 (S11) or 10 (partial S12), found %g.',n28);
end

for i = 1:9
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S12:Group28Foundation', ...
            'Expected %s on Group28 input%d, found input%d.', ...
            diagBlocks{i},i,p);
    end
end

requiredModeTags = {
    'AA15_SYSTEM_MODE'
    'AA15_MODE_ALLOW_NORMAL_P'
    'AA15_MODE_ALLOW_NORMAL_Q'
    'AA15_MODE_ALLOW_S6'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_BLACKSTART_MASTER'
    'CFG15_ISLAND_MASTER'
};

for i = 1:numel(requiredModeTags)
    if isempty(localFindGotosByTag(mdl,requiredModeTags{i}))
        error('S12:MissingModeTag','Missing required tag: %s',requiredModeTags{i});
    end
end

fprintf('[OK] S11 mode decision foundation verified.\n');

% =========================================================================
% 2. Discover all six device Muxes and capture/protect ports.
% =========================================================================
fprintf('\n--- Discover and protect six device mode routes ---\n');

dev = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
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

finalDroopTags = cell(6,1);
finalGridTags = cell(6,1);
legacyDroopTags = cell(6,1);
legacyGridTags = cell(6,1);

for i = 1:6
    finalDroopTags{i} = ['AA15_FINAL_DROOP_' dev{i}];
    finalGridTags{i} = ['AA15_FINAL_GRIDON_' dev{i}];
    legacyDroopTags{i} = ['AA15_LEGACY_DROOP_' dev{i}];
    legacyGridTags{i} = ['AA15_LEGACY_GRIDON_' dev{i}];
end

muxPaths = cell(6,1);

% Protected source block paths for inputs 3/4/6/7.
protectedFrefSrc = cell(6,1);
protectedVrefSrc = cell(6,1);
protectedPrefSrc = cell(6,1);
protectedQrefSrc = cell(6,1);

% Exact legacy source PORT HANDLES for input5/input8.
legacyDroopSrcPort = zeros(6,1);
legacyGridSrcPort = zeros(6,1);

tap = [sm '/AA15_S12_MODE_LEGACY_TAPS'];
tapExists = getSimulinkBlockHandle(tap) >= 0;

if tapExists
    tapPHold = get_param(tap,'PortHandles');
    if numel(tapPHold.Inport) ~= 12
        error('S12:TapPartialInvalid', ...
            ['Existing S12 legacy tap has %d inputs, expected 12. ' ...
             'Restore the automatic PRE_STAGE12 backup before retrying.'], ...
             numel(tapPHold.Inport));
    end
else
    tapPHold = [];
end

for i = 1:6
    muxPaths{i} = localFindUniqueNamedBlock(sm,muxNames{i});
    ph = get_param(muxPaths{i},'PortHandles');

    if numel(ph.Inport) < 8
        error('S12:MuxPorts','%s has fewer than 8 physical inputs.',muxPaths{i});
    end

    [frefSrc,~] = localGetDestinationSource(ph.Inport(3));
    [vrefSrc,~] = localGetDestinationSource(ph.Inport(4));
    [prefSrc,~] = localGetDestinationSource(ph.Inport(6));
    [qrefSrc,~] = localGetDestinationSource(ph.Inport(7));

    protectedFrefSrc{i} = frefSrc;
    protectedVrefSrc{i} = vrefSrc;
    protectedPrefSrc{i} = prefSrc;
    protectedQrefSrc{i} = qrefSrc;

    if ~strcmp(get_param(prefSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(prefSrc,'GotoTag'),prefTags{i})
        error('S12:PrefFoundation', ...
            '%s input6 Pref route is unexpected.',muxPaths{i});
    end

    if ~strcmp(get_param(qrefSrc,'BlockType'),'From') || ...
            ~strcmp(get_param(qrefSrc,'GotoTag'),qTags{i})
        error('S12:QFoundation', ...
            '%s input7 Qref route is unexpected.',muxPaths{i});
    end

    % Capture legacy Droop source.
    [droopSrcPath,droopSrcPortNow] = localGetDestinationSource(ph.Inport(5));
    if strcmp(get_param(droopSrcPath,'BlockType'),'From') && ...
            strcmp(get_param(droopSrcPath,'GotoTag'),finalDroopTags{i})
        if ~tapExists
            error('S12:LostLegacyDroop', ...
                ['%s input5 already uses S12 final tag but the legacy tap ' ...
                 'does not exist. Restore PRE_STAGE12 backup.'],muxPaths{i});
        end
        legacyDroopSrcPort(i) = localGetLineSourcePort(tapPHold.Inport(i));
        fprintf('[REPAIR] %-4s Droop legacy source recovered from existing tap.\n',dev{i});
    else
        legacyDroopSrcPort(i) = droopSrcPortNow;
        fprintf('[CAPTURE] %-4s legacy Droop <- %s\n',dev{i},droopSrcPath);
    end

    % Capture legacy GridOn source.
    [gridSrcPath,gridSrcPortNow] = localGetDestinationSource(ph.Inport(8));
    if strcmp(get_param(gridSrcPath,'BlockType'),'From') && ...
            strcmp(get_param(gridSrcPath,'GotoTag'),finalGridTags{i})
        if ~tapExists
            error('S12:LostLegacyGrid', ...
                ['%s input8 already uses S12 final tag but the legacy tap ' ...
                 'does not exist. Restore PRE_STAGE12 backup.'],muxPaths{i});
        end
        legacyGridSrcPort(i) = localGetLineSourcePort(tapPHold.Inport(6+i));
        fprintf('[REPAIR] %-4s GridOn legacy source recovered from existing tap.\n',dev{i});
    else
        legacyGridSrcPort(i) = gridSrcPortNow;
        fprintf('[CAPTURE] %-4s legacy GridOn <- %s\n',dev{i},gridSrcPath);
    end
end

fprintf('[OK] Protected Fref/Vref/Pref/Qref and captured exact legacy Droop/GridOn.\n');

% =========================================================================
% 3. Repair-safe cleanup of partial S12 diagnostic/router publications.
%    Keep an existing valid legacy tap because it is the recovery anchor.
% =========================================================================
fprintf('\n--- Clean stale partial S12 artifacts BEFORE model update ---\n');

modeRouter = [stack '/AA15_Device_Mode_Router'];
s12Diag = [sm '/AA15_STAGE12_MODE_ACTUATOR_DIAGNOSTICS'];

oldDiagPort = localFindExistingLogPort(s12Diag,group28Mux);
if oldDiagPort > 0
    if oldDiagPort ~= 10
        error('S12:OldDiagPort', ...
            'Existing S12 diagnostics is on unexpected Group28 input%d.',oldDiagPort);
    end
    localDisconnectLogInput(group28Mux,10);
end

if getSimulinkBlockHandle(s12Diag) >= 0
    localDeleteBlockIfExists(s12Diag);
    fprintf('[DELETE] stale %s\n',s12Diag);
end

if str2double(get_param(group28Mux,'Inputs')) == 10
    ph28 = get_param(group28Mux,'PortHandles');
    if numel(ph28.Inport) < 10
        error('S12:Group28RepairPort','Cannot inspect Group28 input10.');
    end
    if ~isequal(get_param(ph28.Inport(10),'Line'),-1)
        error('S12:Group28RepairBusy', ...
            'Group28 input10 is still connected during repair.');
    end
    set_param(group28Mux,'Inputs','9');
    fprintf('[RESTORE] Group28 Inputs: 10 -> 9.\n');
end

for i = 1:29
    localDeleteBlockIfExists([stack '/' sprintf('GOTO_S12_MODE_%02d',i)]);
end

if getSimulinkBlockHandle(modeRouter) >= 0
    localDeleteBlockIfExists(modeRouter);
    fprintf('[DELETE] stale %s\n',modeRouter);
end

fprintf('[OK] S12 router/diagnostic partial artifacts removed; no update yet.\n');

% =========================================================================
% 4. Add/verify tunable CFG15_MODE_ACTUATION_ENABLE (default 0).
% =========================================================================
fprintf('\n--- Create/verify CFG15_MODE_ACTUATION_ENABLE ---\n');

actTag = 'CFG15_MODE_ACTUATION_ENABLE';
actConst = [panel '/' actTag];
actGoto = [panel '/GOTO_' actTag];

localAssertNoForeignGotoTag(mdl,actTag,actGoto);

if getSimulinkBlockHandle(actConst) < 0
    [px,py] = localFindFreePosition(panel,250,40,50);
    add_block('simulink/Sources/Constant',actConst, ...
        'Value','0', ...
        'SampleTime','inf', ...
        'OutDataTypeStr','double', ...
        'Position',[px py px+210 py+25]);
    fprintf('[CREATE] CFG15_MODE_ACTUATION_ENABLE = 0\n');
else
    if ~strcmp(get_param(actConst,'BlockType'),'Constant')
        error('S12:ActConstType','%s exists but is not Constant.',actConst);
    end
    set_param(actConst,'SampleTime','inf');
    fprintf('[KEEP] CFG15_MODE_ACTUATION_ENABLE = %s\n',get_param(actConst,'Value'));
end

if getSimulinkBlockHandle(actGoto) < 0
    pos = get_param(actConst,'Position');
    add_block('simulink/Signal Routing/Goto',actGoto, ...
        'GotoTag',actTag, ...
        'TagVisibility','global', ...
        'Position',[pos(3)+40 pos(2) pos(3)+260 pos(2)+24]);
else
    if ~strcmp(get_param(actGoto,'BlockType'),'Goto')
        error('S12:ActGotoType','%s exists but is not Goto.',actGoto);
    end
    set_param(actGoto,'GotoTag',actTag,'TagVisibility','global');
end

localForceOwnedLine(panel,[actTag '/1'],['GOTO_' actTag '/1']);

% =========================================================================
% 5. Create/verify exact legacy-mode tap.
%    If it already exists from a partial run, keep its external connections.
% =========================================================================
fprintf('\n--- Create/verify exact legacy Droop/GridOn tap ---\n');

if ~tapExists
    [tx,ty] = localFindFreePosition(sm,420,470,360);
    add_block('simulink/Ports & Subsystems/Subsystem',tap, ...
        'Position',[tx ty tx+420 ty+470]);
    localDeleteSubsystemContents(tap);

    inNames = cell(12,1);
    allLegacyTags = [legacyDroopTags; legacyGridTags];

    for i = 1:6
        inNames{i} = ['droop_' lower(dev{i})];
        inNames{6+i} = ['gridon_' lower(dev{i})];
    end

    for i = 1:12
        col = floor((i-1)/6);
        row = mod(i-1,6);
        x = 20 + col*190;
        y = 30 + row*62;

        add_block('simulink/Ports & Subsystems/In1', ...
            [tap '/' inNames{i}], ...
            'Port',num2str(i), ...
            'Position',[x y x+30 y+16]);

        add_block('simulink/Signal Routing/Goto', ...
            [tap '/' sprintf('GOTO_LEGACY_%02d',i)], ...
            'GotoTag',allLegacyTags{i}, ...
            'TagVisibility','global', ...
            'Position',[x+70 y-3 x+180 y+21]);

        localEnsureLine(tap, ...
            [inNames{i} '/1'], ...
            sprintf('GOTO_LEGACY_%02d/1',i));
    end

    tapPH = get_param(tap,'PortHandles');
    if numel(tapPH.Inport) ~= 12
        error('S12:TapCreatePorts','New legacy tap expected 12 inputs.');
    end

    for i = 1:6
        localEnsureTopLevelSourceConnection(sm, ...
            legacyDroopSrcPort(i),tapPH.Inport(i), ...
            sprintf('%s legacy Droop tap',dev{i}));
        localEnsureTopLevelSourceConnection(sm, ...
            legacyGridSrcPort(i),tapPH.Inport(6+i), ...
            sprintf('%s legacy GridOn tap',dev{i}));
    end

    fprintf('[CREATE] exact 12-channel legacy mode tap.\n');
else
    tapPH = get_param(tap,'PortHandles');
    if numel(tapPH.Inport) ~= 12
        error('S12:TapKeepPorts','Existing legacy tap expected 12 inputs.');
    end

    for i = 1:6
        if localGetLineSourcePort(tapPH.Inport(i)) ~= legacyDroopSrcPort(i)
            error('S12:TapDroopMismatch', ...
                'Existing legacy tap Droop input%d source mismatch.',i);
        end
        if localGetLineSourcePort(tapPH.Inport(6+i)) ~= legacyGridSrcPort(i)
            error('S12:TapGridMismatch', ...
                'Existing legacy tap GridOn input%d source mismatch.',i);
        end
    end

    fprintf('[KEEP] existing exact legacy mode tap verified.\n');
end

% =========================================================================
% 6. Build AA15_Device_Mode_Router.
% =========================================================================
fprintf('\n--- Build AA15_Device_Mode_Router ---\n');

xRouter = localNextRightX(stack,140);
add_block('simulink/Ports & Subsystems/Subsystem',modeRouter, ...
    'Position',[xRouter 2050 xRouter+620 2670]);
localDeleteSubsystemContents(modeRouter);

routerInputTags = [
    legacyDroopTags
    legacyGridTags
    {
    'AA15_SYSTEM_MODE'
    'CFG15_MASTER_ENABLE'
    'CFG15_CONTROL_SOURCE'
    'CFG15_MODE_ACTUATION_ENABLE'
    'CFG15_BLACKSTART_MASTER'
    'CFG15_ISLAND_MASTER'
    }
];

% 18 inputs total: 6 legacy droop + 6 legacy grid + 6 control/config.
for i = 1:18
    col = floor((i-1)/9);
    row = mod(i-1,9);
    x = 20 + col*255;
    y = 25 + row*52;

    add_block('simulink/Signal Routing/From', ...
        [modeRouter '/' sprintf('FROM_MODE_%02d',i)], ...
        'GotoTag',routerInputTags{i}, ...
        'Position',[x y x+230 y+20]);
end

routerMF = [modeRouter '/AA15_Device_Mode_Router_Core'];
add_block('simulink/User-Defined Functions/MATLAB Function',routerMF, ...
    'Position',[540 100 1030 610]);

chart = localGetEMChartByPath(routerMF);
chart.Script = localModeRouterScript();

routerOutNames = cell(16,1);
for i = 1:6
    routerOutNames{i} = ['final_droop_' lower(dev{i})];
    routerOutNames{6+i} = ['final_gridon_' lower(dev{i})];
end
routerOutNames{13} = 'mode_actuation_enable';
routerOutNames{14} = 'selected_master';
routerOutNames{15} = 'system_mode_echo';
routerOutNames{16} = 'override_active';
% route_valid will be output17.
routerOutNames{17} = 'route_valid';

for i = 1:17
    y = 30 + (i-1)*31;
    add_block('simulink/Ports & Subsystems/Out1', ...
        [modeRouter '/' routerOutNames{i}], ...
        'Port',num2str(i), ...
        'Position',[1115 y 1145 y+16]);
end

for i = 1:18
    localEnsureLine(modeRouter, ...
        sprintf('FROM_MODE_%02d/1',i), ...
        sprintf('AA15_Device_Mode_Router_Core/%d',i));
end

for i = 1:17
    localEnsureLine(modeRouter, ...
        sprintf('AA15_Device_Mode_Router_Core/%d',i), ...
        [routerOutNames{i} '/1']);
end

modeTags = [
    finalDroopTags
    finalGridTags
    {
    'AA15_MODE_ACTUATION_ENABLE_ECHO'
    'AA15_MODE_SELECTED_MASTER'
    'AA15_MODE_SYSTEM_MODE_ECHO'
    'AA15_MODE_OVERRIDE_ACTIVE'
    'AA15_MODE_ROUTE_VALID'
    }
];

routerPos = get_param(modeRouter,'Position');

for i = 1:17
    gotoName = sprintf('GOTO_S12_MODE_%02d',i);
    p = [stack '/' gotoName];

    add_block('simulink/Signal Routing/Goto',p, ...
        'GotoTag',modeTags{i}, ...
        'TagVisibility','global');

    col = floor((i-1)/9);
    row = mod(i-1,9);
    x = routerPos(3)+45+col*250;
    y = routerPos(2)+20+row*48;

    set_param(p,'Position',[x y x+225 y+22]);

    localForceOwnedLine(stack, ...
        sprintf('AA15_Device_Mode_Router/%d',i), ...
        [gotoName '/1']);
end

% =========================================================================
% 7. Build S12 diagnostics BEFORE first model update.
% =========================================================================
fprintf('\n--- Build S12 diag29 ---\n');

[dx,dy] = localFindFreePosition(sm,520,520,420);
add_block('simulink/Ports & Subsystems/Subsystem',s12Diag, ...
    'Position',[dx dy dx+520 dy+520]);
localDeleteSubsystemContents(s12Diag);

diagTags = [
    legacyDroopTags
    legacyGridTags
    finalDroopTags
    finalGridTags
    {
    'CFG15_MODE_ACTUATION_ENABLE'
    'AA15_MODE_SELECTED_MASTER'
    'AA15_SYSTEM_MODE'
    'AA15_MODE_OVERRIDE_ACTIVE'
    'AA15_MODE_ROUTE_VALID'
    }
];

if numel(diagTags) ~= 29
    error('S12:DiagTagCount','S12 diag tag count expected 29.');
end

for i = 1:29
    col = floor((i-1)/15);
    row = mod(i-1,15);
    x = 20 + col*235;
    y = 18 + row*31;

    add_block('simulink/Signal Routing/From', ...
        [s12Diag '/' sprintf('FROM_DIAG_%02d',i)], ...
        'GotoTag',diagTags{i}, ...
        'Position',[x y x+210 y+20]);
end

add_block('simulink/Signal Routing/Mux', ...
    [s12Diag '/AA15_STAGE12_DIAG29'], ...
    'Inputs','29', ...
    'Position',[535 30 570 485]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [s12Diag '/diag29'], ...
    'Port','1', ...
    'Position',[635 250 665 266]);

for i = 1:29
    localEnsureLine(s12Diag, ...
        sprintf('FROM_DIAG_%02d/1',i), ...
        sprintf('AA15_STAGE12_DIAG29/%d',i));
end
localEnsureLine(s12Diag,'AA15_STAGE12_DIAG29/1','diag29/1');

% =========================================================================
% 8. FIRST update only after complete S12 calculation structure exists.
% =========================================================================
fprintf('\n--- First update after COMPLETE S12 calculation structure ---\n');

set_param(mdl,'SimulationCommand','update');

ports = get_param(routerMF,'Ports');
if ports(1) ~= 18 || ports(2) ~= 17
    error('S12:RouterPorts', ...
        'Mode Router expected 18-in/17-out, found %d/%d.',ports(1),ports(2));
end

fprintf('[OK] Mode Router compiled 18 inputs / 17 outputs.\n');

% =========================================================================
% 9. REAL physical takeover of Droop input5 and GridOn input8.
% =========================================================================
fprintf('\n--- REAL transparent takeover: Mux input5 / input8 ---\n');

finalDroopFromNames = cell(6,1);
finalGridFromNames = cell(6,1);

for i = 1:6
    parent = get_param(muxPaths{i},'Parent');
    muxPos = get_param(muxPaths{i},'Position');

    finalDroopFromNames{i} = ['AA15_S12_FINAL_DROOP_' dev{i} '_TO_MUX'];
    finalGridFromNames{i} = ['AA15_S12_FINAL_GRIDON_' dev{i} '_TO_MUX'];

    fd = [parent '/' finalDroopFromNames{i}];
    fg = [parent '/' finalGridFromNames{i}];

    if getSimulinkBlockHandle(fd) < 0
        add_block('simulink/Signal Routing/From',fd, ...
            'GotoTag',finalDroopTags{i}, ...
            'Position',[max(20,muxPos(1)-285) muxPos(2)+55 ...
                        max(20,muxPos(1)-70) muxPos(2)+75]);
    else
        if ~strcmp(get_param(fd,'BlockType'),'From')
            error('S12:FinalDroopFromType','Unexpected block at %s.',fd);
        end
        set_param(fd,'GotoTag',finalDroopTags{i});
    end

    if getSimulinkBlockHandle(fg) < 0
        add_block('simulink/Signal Routing/From',fg, ...
            'GotoTag',finalGridTags{i}, ...
            'Position',[max(20,muxPos(1)-285) muxPos(2)+125 ...
                        max(20,muxPos(1)-70) muxPos(2)+145]);
    else
        if ~strcmp(get_param(fg,'BlockType'),'From')
            error('S12:FinalGridFromType','Unexpected block at %s.',fg);
        end
        set_param(fg,'GotoTag',finalGridTags{i});
    end

    ph = get_param(muxPaths{i},'PortHandles');

    fdPH = get_param(fd,'PortHandles');
    fgPH = get_param(fg,'PortHandles');

    localForcePortConnection(parent,fdPH.Outport(1),ph.Inport(5), ...
        sprintf('%s final Droop -> Mux input5',dev{i}));

    ph = get_param(muxPaths{i},'PortHandles');
    localForcePortConnection(parent,fgPH.Outport(1),ph.Inport(8), ...
        sprintf('%s final GridOn -> Mux input8',dev{i}));

    fprintf('[ROUTE] %-4s input5=Droop final, input8=GridOn final\n',dev{i});
end

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 10. Append S12 diag29 to Group28 input10.
% =========================================================================
fprintf('\n--- Append S12 diag29 to Group28 input10 ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 9
    error('S12:Group28BeforeAppend', ...
        'Expected Group28 Inputs=9 before S12 append.');
end

set_param(group28Mux,'Inputs','10');
set_param(mdl,'SimulationCommand','update');

diagPH = get_param(s12Diag,'PortHandles');
muxPH28 = get_param(group28Mux,'PortHandles');

if numel(diagPH.Outport) ~= 1
    error('S12:DiagPort','S12 diagnostics expected exactly one output.');
end
if numel(muxPH28.Inport) < 10
    error('S12:Group28Input10','Group28 input10 did not materialize.');
end

localEnsureTopLevelSourceConnection(sm, ...
    diagPH.Outport(1),muxPH28.Inport(10), ...
    'S12 diag29 -> Group28 input10');

set_param(mdl,'SimulationCommand','update');

% =========================================================================
% 11. Final post-assertions.
% =========================================================================
fprintf('\n--- Final S12 post-assertions ---\n');

if str2double(get_param(group28Mux,'Inputs')) ~= 10
    error('S12:Group28Final','Group28 must have 10 inputs after S12.');
end

for i = 1:9
    p = localFindExistingLogPort(diagBlocks{i},group28Mux);
    if p ~= i
        error('S12:OldDiagMoved', ...
            '%s moved from Group28 input%d to input%d.',diagBlocks{i},i,p);
    end
end

if localFindExistingLogPort(s12Diag,group28Mux) ~= 10
    error('S12:S12DiagSlot','S12 diagnostics is not Group28 input10.');
end

% Check all six physical routes.
for i = 1:6
    ph = get_param(muxPaths{i},'PortHandles');

    [f3,~] = localGetDestinationSource(ph.Inport(3));
    [f4,~] = localGetDestinationSource(ph.Inport(4));
    [f5,~] = localGetDestinationSource(ph.Inport(5));
    [f6,~] = localGetDestinationSource(ph.Inport(6));
    [f7,~] = localGetDestinationSource(ph.Inport(7));
    [f8,~] = localGetDestinationSource(ph.Inport(8));

    if ~strcmp(f3,protectedFrefSrc{i})
        error('S12:FrefChanged','%s input3 Fref changed.',muxPaths{i});
    end
    if ~strcmp(f4,protectedVrefSrc{i})
        error('S12:VrefChanged','%s input4 Vref changed.',muxPaths{i});
    end
    if ~strcmp(f6,protectedPrefSrc{i}) || ...
            ~strcmp(get_param(f6,'GotoTag'),prefTags{i})
        error('S12:PrefChanged','%s input6 Pref changed.',muxPaths{i});
    end
    if ~strcmp(f7,protectedQrefSrc{i}) || ...
            ~strcmp(get_param(f7,'GotoTag'),qTags{i})
        error('S12:QrefChanged','%s input7 Qref changed.',muxPaths{i});
    end

    if ~strcmp(get_param(f5,'BlockType'),'From') || ...
            ~strcmp(get_param(f5,'GotoTag'),finalDroopTags{i})
        error('S12:DroopPostAssert', ...
            '%s input5 does not use expected final Droop tag.',muxPaths{i});
    end

    if ~strcmp(get_param(f8,'BlockType'),'From') || ...
            ~strcmp(get_param(f8,'GotoTag'),finalGridTags{i})
        error('S12:GridPostAssert', ...
            '%s input8 does not use expected final GridOn tag.',muxPaths{i});
    end
end

% Default must remain OFF in the saved model unless user deliberately changed
% it before running the script. To avoid accidentally saving an active mode
% actuator after development, force the design default to zero here.
set_param(actConst,'Value','0');

allNewTags = [
    legacyDroopTags
    legacyGridTags
    finalDroopTags
    finalGridTags
    {
    actTag
    'AA15_MODE_ACTUATION_ENABLE_ECHO'
    'AA15_MODE_SELECTED_MASTER'
    'AA15_MODE_SYSTEM_MODE_ECHO'
    'AA15_MODE_OVERRIDE_ACTIVE'
    'AA15_MODE_ROUTE_VALID'
    }
];

for i = 1:numel(allNewTags)
    localAssertSingleGlobalGoto(mdl,allNewTags{i});
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 STAGE12 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Exact legacy Droop/GridOn taps      : PASS\n');
fprintf('Device Mode Router                  : PASS\n');
fprintf('Real Mux input5 Droop takeover      : PASS\n');
fprintf('Real Mux input8 GridOn takeover     : PASS\n');
fprintf('Fref input3                         : UNCHANGED\n');
fprintf('Vref input4                         : UNCHANGED\n');
fprintf('Pref input6                         : UNCHANGED\n');
fprintf('Qref input7                         : UNCHANGED\n');
fprintf('CFG15_MODE_ACTUATION_ENABLE default : 0 (transparent)\n');
fprintf('Group28                             : 10 physical inputs\n');
fprintf('Group28 total scalar signals        : 202\n');
fprintf('Expected MAT rows                   : 203 (incl. Target Time)\n');
fprintf('Backup                              : %s\n',backupFile);
fprintf('\nNEXT: Build + Load + transparent regression is REQUIRED.\n');
fprintf('Do NOT set CFG15_MODE_ACTUATION_ENABLE=1 before S13.\n');

end


% =========================================================================
% Mode Router MATLAB Function
% =========================================================================
function txt = localModeRouterScript()

L = {};
L{end+1} = ['function [d1,d2,d3,d4,d5,d6,g1,g2,g3,g4,g5,g6,' ...
    'act_echo,selected_master,mode_echo,override_active,route_valid] = ' ...
    'AA15_Device_Mode_Router_Core(' ...
    'ld1,ld2,ld3,ld4,ld5,ld6,' ...
    'lg1,lg2,lg3,lg4,lg5,lg6,' ...
    'system_mode,master_enable,control_source,act_enable,' ...
    'black_master,island_master)'];
L{end+1} = '%#codegen';
L{end+1} = '';
L{end+1} = 'd1=ld1; d2=ld2; d3=ld3; d4=ld4; d5=ld5; d6=ld6;';
L{end+1} = 'g1=lg1; g2=lg2; g3=lg3; g4=lg4; g5=lg5; g6=lg6;';
L{end+1} = 'act_echo = act_enable;';
L{end+1} = 'selected_master = 0.0;';
L{end+1} = 'mode_echo = system_mode;';
L{end+1} = 'override_active = 0.0;';
L{end+1} = 'route_valid = 1.0;';
L{end+1} = '';
L{end+1} = '% Exact legacy passthrough requires finite legacy mode signals.';
L{end+1} = 'if ~finite1(ld1)||~finite1(ld2)||~finite1(ld3)||...';
L{end+1} = '   ~finite1(ld4)||~finite1(ld5)||~finite1(ld6)||...';
L{end+1} = '   ~finite1(lg1)||~finite1(lg2)||~finite1(lg3)||...';
L{end+1} = '   ~finite1(lg4)||~finite1(lg5)||~finite1(lg6)';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'src = round(control_source);';
L{end+1} = 'mode = round(system_mode);';
L{end+1} = '';
L{end+1} = '% S12 only actuates LOCAL15 and only with explicit safety enable.';
L{end+1} = 'armed = (master_enable > 0.5) && (src == 1) && (act_enable > 0.5);';
L{end+1} = 'mode_needs_gfm = (mode==2)||(mode==3)||(mode==4)||(mode==5);';
L{end+1} = '';
L{end+1} = 'if ~(armed && mode_needs_gfm)';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Select ESS master. Configuration 1=ESS1, 2=ESS2.';
L{end+1} = 'if mode == 4';
L{end+1} = '    m = round(black_master);';
L{end+1} = 'else';
L{end+1} = '    m = round(island_master);';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'if m ~= 1 && m ~= 2';
L{end+1} = '    route_valid = 0.0;';
L{end+1} = '    return;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = 'selected_master = double(m);';
L{end+1} = 'override_active = 1.0;';
L{end+1} = '';
L{end+1} = '% Device order: PV1 PV2 ESS1 ESS2 EV1 EV2.';
L{end+1} = '% GridOn 0=GFM, 1=GFL. Only master ESS becomes GFM.';
L{end+1} = 'g1=1.0; g2=1.0; g5=1.0; g6=1.0;';
L{end+1} = '';
L{end+1} = 'if m == 1';
L{end+1} = '    g3 = 0.0;';
L{end+1} = '    g4 = 1.0;';
L{end+1} = '    d3 = 1.0;';
L{end+1} = 'else';
L{end+1} = '    g3 = 1.0;';
L{end+1} = '    g4 = 0.0;';
L{end+1} = '    d4 = 1.0;';
L{end+1} = 'end';
L{end+1} = '';
L{end+1} = '% Other Droop signals remain exact legacy values.';
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
    error('S12:EMChartPath', ...
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
    error('S12:UniqueBlock', ...
        'Expected exactly one block named %s, found %d.',name,numel(hits));
end

blockPath = hits{1};

end


function [srcPath,srcPort] = localGetDestinationSource(dstPort)

ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    error('S12:UndrivenDestination','Protected destination is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');
if isempty(srcPort) || srcPort < 0
    error('S12:NoSourcePort','Could not resolve source port.');
end

srcPath = getfullname(get_param(srcPort,'Parent'));

end


function srcPort = localGetLineSourcePort(dstPort)

ln = get_param(dstPort,'Line');
if isequal(ln,-1)
    error('S12:TapInputUndriven','A legacy tap input is undriven.');
end

srcPort = get_param(ln,'SrcPortHandle');
if isempty(srcPort) || srcPort < 0
    error('S12:TapInputNoSource','Cannot resolve legacy tap source.');
end

end


function localEnsureLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S12:LinePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

srcPort = srcPH.Outport(srcIdx);
dstPort = dstPH.Inport(dstIdx);
ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

if get_param(ln,'SrcPortHandle') ~= srcPort
    error('S12:LineDriven','Destination %s already has another source.',dst);
end

end


function localForceOwnedLine(parent,src,dst)

[srcPath,srcIdx] = localParseRelativePort(parent,src);
[dstPath,dstIdx] = localParseRelativePort(parent,dst);

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S12:ForcePortRange', ...
        'Invalid port while connecting %s -> %s.',src,dst);
end

localForcePortConnection(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
    sprintf('%s -> %s',src,dst));

end


function [path,idx] = localParseRelativePort(parent,spec)

slash = find(spec=='/',1,'last');
if isempty(slash)
    error('S12:PortSpec','Port spec must be block/port: %s',spec);
end

blockRel = spec(1:slash-1);
idx = str2double(spec(slash+1:end));

if isnan(idx) || idx < 1
    error('S12:PortSpec','Invalid port index in %s.',spec);
end

path = [parent '/' blockRel];
if getSimulinkBlockHandle(path) < 0
    error('S12:PortBlockMissing','Missing block: %s',path);
end

end


function localEnsureTopLevelSourceConnection(parent,srcPort,dstPort,desc)

ln = get_param(dstPort,'Line');

if isequal(ln,-1)
    add_line(parent,srcPort,dstPort,'autorouting','on');
    return;
end

if get_param(ln,'SrcPortHandle') ~= srcPort
    error('S12:TopConnection', ...
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
    error('S12:ForceConnection','Post-assert failed for %s.',desc);
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
    error('S12:BranchDelete', ...
        ['Could not remove only requested branch; shared-trunk deletion is ' ...
         'forbidden. %s'],ME.message);
end

end


function localDisconnectLogInput(groupMux,portNo)

ph = get_param(groupMux,'PortHandles');
if numel(ph.Inport) < portNo
    return;
end

if isequal(get_param(ph.Inport(portNo),'Line'),-1)
    return;
end

parent = get_param(groupMux,'Parent');
localDisconnectDestinationBranch(parent,ph.Inport(portNo));

end


function localDeleteBlockIfExists(blockPath)
% Delete S12-owned blocks without deleting shared source trunks.

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

        for j = 1:numel(ph.(fld))
            try
                localDisconnectDestinationBranch(parent,ph.(fld)(j));
            catch ME
                error('S12:OwnedBlockIncomingDelete', ...
                    'Could not safely disconnect %s: %s',blockPath,ME.message);
            end
        end
    end

    if isfield(ph,'Outport')
        lines = [];
        for j = 1:numel(ph.Outport)
            try
                ln = get_param(ph.Outport(j),'Line');
            catch
                ln = -1;
            end
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
    if startsWith(ME.identifier,'S12:')
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
        lines = find_system(subsys,'FindAll','on','SearchDepth',1, ...
            'MatchFilter',@Simulink.match.allVariants,'Type','line');
    catch
        lines = find_system(subsys,'FindAll','on','SearchDepth',1, ...
            'Variants','AllVariants','Type','line');
    end
    lines = unique(lines(lines>=0));
    for i = 1:numel(lines)
        try
            delete_line(lines(i));
        catch
        end
    end
catch
end

try
    blocks = find_system(subsys,'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants,'Type','Block');
catch
    blocks = find_system(subsys,'SearchDepth',1, ...
        'Variants','AllVariants','Type','Block');
end

for i = 1:numel(blocks)
    if strcmp(blocks{i},subsys)
        continue;
    end
    try
        delete_block(blocks{i});
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

dst = dst(dst>=0);
muxPH = get_param(logMux,'PortHandles');

for i = 1:numel(dst)
    hit = find(muxPH.Inport==dst(i),1,'first');
    if ~isempty(hit)
        p=hit;
        return;
    end
end

end


function gotos = localFindGotosByTag(mdl,tag)

try
    allg = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
        'MatchFilter',@Simulink.match.allVariants,'BlockType','Goto');
catch
    allg = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
        'Variants','AllVariants','BlockType','Goto');
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
        error('S12:ForeignGoto', ...
            'GotoTag %s already exists at unexpected path %s.',tag,g{i});
    end
end

end


function localAssertSingleGlobalGoto(mdl,tag)

g = localFindGotosByTag(mdl,tag);
if numel(g) ~= 1
    error('S12:GlobalGotoCount', ...
        'Expected exactly one Goto for tag %s, found %d.',tag,numel(g));
end

end


function x = localNextRightX(parent,margin)

try
    blocks = find_system(parent,'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants,'Type','Block');
catch
    blocks = find_system(parent,'SearchDepth',1, ...
        'Variants','AllVariants','Type','Block');
end

maxRight=0;
for i=1:numel(blocks)
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
    blocks = find_system(parent,'SearchDepth',1, ...
        'MatchFilter',@Simulink.match.allVariants,'Type','Block');
catch
    blocks = find_system(parent,'SearchDepth',1, ...
        'Variants','AllVariants','Type','Block');
end

rects=[];
for i=1:numel(blocks)
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
for i=1:size(rects,1)
    q=rects(i,:);
    separated = r(3)<q(1) || r(1)>q(3) || r(4)<q(2) || r(2)>q(4);
    if ~separated
        tf=true;
        return;
    end
end

end

function S02_K26_V5_BASELINE_AGC_SHADOW_EQUIVALENCE_V4
% S02_K26_V5_BASELINE_AGC_SHADOW_EQUIVALENCE_V4
%
% LOCAL15 Stage 02 V2
%
% Goal:
%   Build a SHADOW baseline AGC that is algorithmically identical to the
%   current 15-in / 9-out AGC, except that the AGC receives dP_request_kW
%   explicitly instead of calculating P_target_kW - P_pcc_kW internally.
%
% This stage DOES NOT control any device.
% Existing V5-A control routes remain untouched.
%
% It also creates a CFG15 tunability checksum so every CFG15_* scalar
% created by Stage 01 is actually consumed by generated code. This makes
% the later RT-LAB tunability acceptance test meaningful.
%
% Logged shadow diagnostic segment (12 signals, in this exact order):
%   1  shadow_PV1_pu
%   2  shadow_PV2_pu
%   3  shadow_ESS1_pu
%   4  shadow_ESS2_pu
%   5  shadow_EV1_pu
%   6  shadow_EV2_pu
%   7  shadow_agc_status
%   8  shadow_dP
%   9  shadow_remain
%   10 baseline_dP_request_kW
%   11 CFG15_PARAM_PROBE
%   12 CFG15_parameter_checksum
%
% The 12-signal segment is appended to the existing Group-26
% agc_target_data OpWrite path. No existing signal order is changed.
%
% Project rule:
%   mdl = bdroot(gcs);

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 02 V4 - Baseline AGC Shadow Equivalence\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S02:NoActiveModel', ...
        'No active model. Open the RT-LAB Simulink model and click inside it first.');
end

load_system(mdl);

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) < 0
    error('S02:MissingSM','Missing required subsystem: %s',sm);
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S02:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_LOCAL15_STAGE02_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Active model : %s\n',mdl);
fprintf('Model file   : %s\n',modelFile);
fprintf('Backup       : %s\n',backupFile);

% -------------------------------------------------------------------------
% Policy assertions.
% -------------------------------------------------------------------------
set_param(mdl,'DefaultParameterBehavior','Tunable');
try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('S02:TunabilityDiagnostic', ...
        'Could not set ParameterTunabilityLossMsg=error: %s',ME.message);
end

panel = [sm '/AA15_CFG15_PANEL'];
if getSimulinkBlockHandle(panel) < 0
    error('S02:MissingStage01', ...
        'AA15_CFG15_PANEL is missing. Run Stage 01 V2 first.');
end

% -------------------------------------------------------------------------
% Discover the EXISTING baseline AGC from actual model structure.
% Criteria:
%   top-level MATLAB Function block under SM_Master
%   Ports = 15 inputs / 9 outputs
% -------------------------------------------------------------------------
fprintf('\n--- Discover existing baseline AGC ---\n');

agcOld = localDiscoverCurrentAGC(sm);

fprintf('[OK] Existing AGC: %s\n',agcOld);
fprintf('     Ports       : %s\n',mat2str(get_param(agcOld,'Ports')));

% Read the actual current MATLAB Function script from the EXACT Simulink block.
oldChart = localGetEMChartByPath(agcOld);
oldScript = oldChart.Script;

if ~contains(oldScript,'dPnow = P_target_kW - P_pcc_kW')
    % allow arbitrary whitespace
    matchDP = regexp(oldScript, ...
        'dPnow\s*=\s*P_target_kW\s*-\s*P_pcc_kW\s*;','match');
    if numel(matchDP) ~= 1
        error('S02:AGCSourceUnexpected', ...
            ['Expected exactly one internal dP calculation ' ...
             'P_target_kW - P_pcc_kW. Found %d.'],numel(matchDP));
    end
end

fprintf('[OK] Existing AGC source located from active model Stateflow chart.\n');

% -------------------------------------------------------------------------
% Create 15 input taps without altering the existing AGC route.
% A compact subsystem receives BRANCHES of the exact same 15 input signals
% and publishes them as global Goto tags.
% -------------------------------------------------------------------------
fprintf('\n--- Create/verify exact AGC input taps ---\n');

tapName = 'AA15_AGC_INPUT_TAPS';
tap = [sm '/' tapName];

if getSimulinkBlockHandle(tap) < 0
    oldPos = get_param(agcOld,'Position');
    [tx,ty] = localFindFreeAroundAnchor(sm,oldPos,270,620);

    add_block('simulink/Ports & Subsystems/Subsystem',tap, ...
        'Position',[tx ty tx+270 ty+620]);
    localDeleteSubsystemContents(tap);

    try
        set_param(tap,'AttributesFormatString', ...
            'SHADOW ONLY\nExact branches of current AGC inputs');
    catch
    end

    fprintf('[CREATE] %s\n',tap);
else
    if ~strcmp(get_param(tap,'BlockType'),'SubSystem')
        error('S02:TapConflict','%s exists but is not a SubSystem.',tap);
    end
    fprintf('[KEEP]   %s\n',tap);
end

inputNames = {
    't'
    'P_target_kW'
    'P_pcc_kW'
    'Ppvmax1_kW'
    'Ppvmax2_kW'
    'SOC1'
    'SOC2'
    'enable'
    'P_unit_kW'
    'P_dead_kW'
    'SOC_min'
    'SOC_max'
    'Ts_agc'
    'PV_init_kW'
    'EV_init_kW'
};

tapTags = cell(15,1);

for i = 1:15
    tapTags{i} = sprintf('AA15_AGC_IN_%02d_%s',i,upper(inputNames{i}));

    inName = sprintf('IN_%02d_%s',i,inputNames{i});
    gotoName = sprintf('GOTO_%02d_%s',i,inputNames{i});

    inPath = [tap '/' inName];
    gotoPath = [tap '/' gotoName];

    y = 45 + (i-1)*36;

    if getSimulinkBlockHandle(inPath) < 0
        add_block('simulink/Ports & Subsystems/In1',inPath, ...
            'Port',num2str(i), ...
            'Position',[25 y 55 y+14]);
    else
        set_param(inPath,'Port',num2str(i));
    end

    if getSimulinkBlockHandle(gotoPath) < 0
        add_block('simulink/Signal Routing/Goto',gotoPath, ...
            'GotoTag',tapTags{i}, ...
            'TagVisibility','global', ...
            'Position',[105 y-5 245 y+19]);
    else
        if ~strcmp(get_param(gotoPath,'BlockType'),'Goto')
            error('S02:TapGotoConflict','Unexpected block at %s',gotoPath);
        end
        set_param(gotoPath,'GotoTag',tapTags{i},'TagVisibility','global');
    end

    localEnsureLine(tap,[inName '/1'],[gotoName '/1']);
end

% Branch the exact sources feeding the current AGC into tap subsystem.
oldPH = get_param(agcOld,'PortHandles');
tapPH = get_param(tap,'PortHandles');

if numel(oldPH.Inport) ~= 15 || numel(tapPH.Inport) ~= 15
    error('S02:TapPortCount', ...
        'Expected 15 AGC inputs and 15 tap inputs.');
end

for i = 1:15
    oldLine = get_param(oldPH.Inport(i),'Line');
    if isequal(oldLine,-1)
        error('S02:AGCInputUnconnected', ...
            'Existing AGC input %d is unconnected.',i);
    end

    srcPort = get_param(oldLine,'SrcPortHandle');
    if isempty(srcPort) || srcPort < 0
        error('S02:AGCInputSource', ...
            'Cannot resolve source port for existing AGC input %d.',i);
    end

    tapLine = get_param(tapPH.Inport(i),'Line');

    if isequal(tapLine,-1)
        add_line(sm,srcPort,tapPH.Inport(i),'autorouting','on');
        fprintf('[TAP] input %02d %-15s <- exact existing source\n', ...
            i,inputNames{i});
    else
        tapSrc = get_param(tapLine,'SrcPortHandle');
        if tapSrc ~= srcPort
            error('S02:TapSourceMismatch', ...
                'Tap input %d is driven by a different source.',i);
        end
        fprintf('[KEEP] input %02d %-15s tap already correct\n', ...
            i,inputNames{i});
    end
end

% -------------------------------------------------------------------------
% Build the new AGC source code from the ACTUAL current AGC source.
% Only two semantic edits are allowed:
%   1) function name / add dP_request_kW as input 16
%   2) dPnow = dP_request_kW
% -------------------------------------------------------------------------
[newScript,replaceCount] = localBuildExternalDPAGCScript(oldScript);

if replaceCount ~= 1
    error('S02:AGCTransform', ...
        'Expected one dP substitution, got %d.',replaceCount);
end

% -------------------------------------------------------------------------
% Create compact shadow subsystem.
% -------------------------------------------------------------------------
fprintf('\n--- Create/verify shadow baseline AGC ---\n');

shadowName = 'AA15_BASELINE_AGC_SHADOW';
shadow = [sm '/' shadowName];

if getSimulinkBlockHandle(shadow) < 0
    [sx,sy] = localFindFreeTopLevelPosition(sm,420,330,420);
    add_block('simulink/Ports & Subsystems/Subsystem',shadow, ...
        'Position',[sx sy sx+420 sy+330]);
    localDeleteSubsystemContents(shadow);

    try
        set_param(shadow,'AttributesFormatString', ...
            'SHADOW ONLY\nExternal dP_request baseline AGC\nNO plant control');
    catch
    end

    fprintf('[CREATE] %s\n',shadow);
else
    if ~strcmp(get_param(shadow,'BlockType'),'SubSystem')
        error('S02:ShadowConflict','%s exists but is not a SubSystem.',shadow);
    end
    fprintf('[KEEP]   %s\n',shadow);
end

mfName = 'AGC_Baseline_dPRequest';
mfPath = [shadow '/' mfName];

if getSimulinkBlockHandle(mfPath) < 0
    add_block('simulink/User-Defined Functions/MATLAB Function',mfPath, ...
        'Position',[520 110 870 590]);
    createdShadowMF = true;
else
    if ~strcmp(get_param(mfPath,'SFBlockType'),'MATLAB Function')
        error('S02:MFConflict','%s is not a MATLAB Function block.',mfPath);
    end
    createdShadowMF = false;
end

% IMPORTANT: resolve the Stateflow.EMChart by its exact Simulink Path.
% This is repair-safe even if a previous S02 run stopped after creating the block.
shadowChart = localGetEMChartByPath(mfPath);
shadowChart.Script = newScript;

if createdShadowMF
    fprintf('[CREATE] MATLAB Function %s from active AGC source\n',mfPath);
else
    fprintf('[REPAIR] MATLAB Function %s source set by exact block Path\n',mfPath);
end

% Add From blocks for the 15 exact input taps.
for i = 1:15
    fromName = sprintf('FROM_%02d_%s',i,inputNames{i});
    fromPath = [shadow '/' fromName];

    col = floor((i-1)/8);
    row = mod(i-1,8);

    x = 35 + col*230;
    y = 45 + row*62;

    if getSimulinkBlockHandle(fromPath) < 0
        add_block('simulink/Signal Routing/From',fromPath, ...
            'GotoTag',tapTags{i}, ...
            'Position',[x y x+185 y+22]);
    else
        set_param(fromPath,'GotoTag',tapTags{i});
    end
end

% Sum block produces the explicit baseline dP_request.
sumPath = [shadow '/BASELINE_DPREQ_PTARGET_MINUS_PPCC'];
if getSimulinkBlockHandle(sumPath) < 0
    add_block('simulink/Math Operations/Sum',sumPath, ...
        'Inputs','+-', ...
        'Position',[340 555 390 600]);
else
    set_param(sumPath,'Inputs','+-');
end

% Direct parameter probe.
probeFrom = [shadow '/FROM_CFG15_PARAM_PROBE'];
if getSimulinkBlockHandle(probeFrom) < 0
    add_block('simulink/Signal Routing/From',probeFrom, ...
        'GotoTag','CFG15_PARAM_PROBE', ...
        'Position',[35 590 220 612]);
else
    set_param(probeFrom,'GotoTag','CFG15_PARAM_PROBE');
end

% -------------------------------------------------------------------------
% Create a compact checksum monitor that consumes every CFG15 parameter.
% This is deliberately diagnostic-only.
% -------------------------------------------------------------------------
fprintf('\n--- Create CFG15 tunability checksum monitor ---\n');

cfgNames = localCFG15Names();

monName = 'AA15_CFG15_TUNABILITY_MONITOR';
mon = [sm '/' monName];

if getSimulinkBlockHandle(mon) < 0
    [mx,my] = localFindFreeTopLevelPosition(sm,330,220,420);
    add_block('simulink/Ports & Subsystems/Subsystem',mon, ...
        'Position',[mx my mx+330 my+220]);
    localDeleteSubsystemContents(mon);
    try
        set_param(mon,'AttributesFormatString', ...
            'DIAGNOSTIC ONLY\nConsumes all CFG15 parameters');
    catch
    end
    fprintf('[CREATE] %s\n',mon);
else
    if ~strcmp(get_param(mon,'BlockType'),'SubSystem')
        error('S02:MonitorConflict','%s exists but is not a SubSystem.',mon);
    end
    fprintf('[KEEP]   %s\n',mon);
end

checksumMF = [mon '/CFG15_Checksum'];
checksumScript = localBuildChecksumScript(cfgNames);

if getSimulinkBlockHandle(checksumMF) < 0
    add_block('simulink/User-Defined Functions/MATLAB Function',checksumMF, ...
        'Position',[520 90 850 500]);
    createdChecksumMF = true;
else
    if ~strcmp(get_param(checksumMF,'SFBlockType'),'MATLAB Function')
        error('S02:ChecksumConflict','%s is not a MATLAB Function block.',checksumMF);
    end
    createdChecksumMF = false;
end

checksumChart = localGetEMChartByPath(checksumMF);
checksumChart.Script = checksumScript;

if createdChecksumMF
    fprintf('[CREATE] MATLAB Function %s\n',checksumMF);
else
    fprintf('[REPAIR] MATLAB Function %s source set by exact block Path\n',checksumMF);
end

% Add one From per CFG15 parameter.
for i = 1:numel(cfgNames)
    name = cfgNames{i};
    fromName = sprintf('FROM_%02d_%s',i,name);
    fromPath = [mon '/' fromName];

    col = floor((i-1)/10);
    row = mod(i-1,10);

    x = 25 + col*170;
    y = 35 + row*48;

    if getSimulinkBlockHandle(fromPath) < 0
        add_block('simulink/Signal Routing/From',fromPath, ...
            'GotoTag',name, ...
            'Position',[x y x+145 y+20]);
    else
        set_param(fromPath,'GotoTag',name);
    end
end

checksumGoto = [mon '/GOTO_AA15_CFG15_CHECKSUM'];
if getSimulinkBlockHandle(checksumGoto) < 0
    add_block('simulink/Signal Routing/Goto',checksumGoto, ...
        'GotoTag','AA15_CFG15_CHECKSUM', ...
        'TagVisibility','global', ...
        'Position',[900 260 1080 284]);
else
    set_param(checksumGoto, ...
        'GotoTag','AA15_CFG15_CHECKSUM', ...
        'TagVisibility','global');
end

% -------------------------------------------------------------------------
% First update: materialize MATLAB Function ports after setting scripts.
% -------------------------------------------------------------------------
fprintf('\n--- First model update to materialize MATLAB Function ports ---\n');
set_param(mdl,'SimulationCommand','update');

mfPorts = get_param(mfPath,'Ports');
if mfPorts(1) ~= 16 || mfPorts(2) ~= 9
    error('S02:ShadowPorts', ...
        'Shadow AGC expected 16 inputs / 9 outputs, found %d / %d.', ...
        mfPorts(1),mfPorts(2));
end

checksumPorts = get_param(checksumMF,'Ports');
if checksumPorts(1) ~= numel(cfgNames) || checksumPorts(2) ~= 1
    error('S02:ChecksumPorts', ...
        'Checksum expected %d inputs / 1 output, found %d / %d.', ...
        numel(cfgNames),checksumPorts(1),checksumPorts(2));
end

fprintf('[OK] Shadow AGC ports   : 16 in / 9 out\n');
fprintf('[OK] CFG15 checksum ports: %d in / 1 out\n',numel(cfgNames));

% -------------------------------------------------------------------------
% Wire shadow AGC.
% -------------------------------------------------------------------------
fprintf('\n--- Wire shadow AGC ---\n');

for i = 1:15
    fromName = sprintf('FROM_%02d_%s',i,inputNames{i});

    localEnsureLine(shadow,[fromName '/1'], ...
        sprintf('%s/%d',mfName,i));
end

% P_target and P_pcc branches into explicit dP request.
localEnsureLine(shadow,'FROM_02_P_target_kW/1', ...
    'BASELINE_DPREQ_PTARGET_MINUS_PPCC/1');
localEnsureLine(shadow,'FROM_03_P_pcc_kW/1', ...
    'BASELINE_DPREQ_PTARGET_MINUS_PPCC/2');
localEnsureLine(shadow,'BASELINE_DPREQ_PTARGET_MINUS_PPCC/1', ...
    [mfName '/16']);

% Publish the explicit baseline dP request for future LOCAL15 use.
dPGoto = [shadow '/GOTO_AA15_BASELINE_DPREQ'];
if getSimulinkBlockHandle(dPGoto) < 0
    add_block('simulink/Signal Routing/Goto',dPGoto, ...
        'GotoTag','AA15_BASELINE_DPREQ', ...
        'TagVisibility','global', ...
        'Position',[910 545 1095 569]);
else
    set_param(dPGoto, ...
        'GotoTag','AA15_BASELINE_DPREQ', ...
        'TagVisibility','global');
end
localEnsureLine(shadow,'BASELINE_DPREQ_PTARGET_MINUS_PPCC/1', ...
    'GOTO_AA15_BASELINE_DPREQ/1');

% Shadow outputs -> global tags for later local-control integration.
outNames = {
    'PV1_PU'
    'PV2_PU'
    'ESS1_PU'
    'ESS2_PU'
    'EV1_PU'
    'EV2_PU'
    'STATUS'
    'DP'
    'REMAIN'
};

for i = 1:9
    gotoName = sprintf('GOTO_SHADOW_%02d_%s',i,outNames{i});
    gotoPath = [shadow '/' gotoName];
    tag = ['AA15_BASE_AGC_' outNames{i}];

    y = 40 + (i-1)*48;

    if getSimulinkBlockHandle(gotoPath) < 0
        add_block('simulink/Signal Routing/Goto',gotoPath, ...
            'GotoTag',tag, ...
            'TagVisibility','global', ...
            'Position',[930 y 1110 y+22]);
    else
        set_param(gotoPath,'GotoTag',tag,'TagVisibility','global');
    end

    localEnsureLine(shadow,sprintf('%s/%d',mfName,i), ...
        [gotoName '/1']);
end

% Checksum monitor wiring.
for i = 1:numel(cfgNames)
    fromName = sprintf('FROM_%02d_%s',i,cfgNames{i});
    localEnsureLine(mon,[fromName '/1'], ...
        sprintf('CFG15_Checksum/%d',i));
end
localEnsureLine(mon,'CFG15_Checksum/1', ...
    'GOTO_AA15_CFG15_CHECKSUM/1');

% -------------------------------------------------------------------------
% Create diagnostic Mux12 and one subsystem Outport.
% -------------------------------------------------------------------------
checksumFrom = [shadow '/FROM_AA15_CFG15_CHECKSUM'];
if getSimulinkBlockHandle(checksumFrom) < 0
    add_block('simulink/Signal Routing/From',checksumFrom, ...
        'GotoTag','AA15_CFG15_CHECKSUM', ...
        'Position',[35 625 220 647]);
else
    set_param(checksumFrom,'GotoTag','AA15_CFG15_CHECKSUM');
end

diagMux = [shadow '/AA15_AGC_SHADOW_DIAG12'];
if getSimulinkBlockHandle(diagMux) < 0
    add_block('simulink/Signal Routing/Mux',diagMux, ...
        'Inputs','12', ...
        'Position',[1160 80 1195 650]);
else
    set_param(diagMux,'Inputs','12');
end

diagOut = [shadow '/diag12'];
if getSimulinkBlockHandle(diagOut) < 0
    add_block('simulink/Ports & Subsystems/Out1',diagOut, ...
        'Port','1', ...
        'Position',[1250 350 1280 364]);
else
    set_param(diagOut,'Port','1');
end

for i = 1:9
    localEnsureLine(shadow,sprintf('%s/%d',mfName,i), ...
        sprintf('AA15_AGC_SHADOW_DIAG12/%d',i));
end

localEnsureLine(shadow,'BASELINE_DPREQ_PTARGET_MINUS_PPCC/1', ...
    'AA15_AGC_SHADOW_DIAG12/10');
localEnsureLine(shadow,'FROM_CFG15_PARAM_PROBE/1', ...
    'AA15_AGC_SHADOW_DIAG12/11');
localEnsureLine(shadow,'FROM_AA15_CFG15_CHECKSUM/1', ...
    'AA15_AGC_SHADOW_DIAG12/12');
localEnsureLine(shadow,'AA15_AGC_SHADOW_DIAG12/1','diag12/1');

% -------------------------------------------------------------------------
% Append the 12-signal shadow diagnostic to the EXISTING Group-26
% agc_target_data logging mux. Existing signal ordering remains unchanged.
% -------------------------------------------------------------------------
fprintf('\n--- Append shadow diagnostics to existing Group-26 log ---\n');

[opWrite,logMux] = localDiscoverAGCLogPath(sm);

fprintf('[OK] Group-26 OpWrite : %s\n',opWrite);
fprintf('[OK] Existing log Mux : %s\n',logMux);

shadowPH = get_param(shadow,'PortHandles');
logMuxPH = get_param(logMux,'PortHandles');

% Is the shadow output already connected to this Mux?
alreadyConnected = false;
shadowLine = get_param(shadowPH.Outport(1),'Line');

if ~isequal(shadowLine,-1)
    dstPorts = get_param(shadowLine,'DstPortHandle');
    dstPorts = dstPorts(dstPorts >= 0);

    logMuxHandle = get_param(logMux,'Handle');
    for k = 1:numel(dstPorts)
        dstParent = get_param(dstPorts(k),'Parent');

        if isnumeric(dstParent)
            isSameParent = isequal(dstParent,logMuxHandle);
        else
            isSameParent = strcmp(dstParent,logMux);
        end

        if isSameParent
            alreadyConnected = true;
            break;
        end
    end
end

if ~alreadyConnected
    oldN = str2double(get_param(logMux,'Inputs'));
    set_param(logMux,'Inputs',num2str(oldN+1));

    logMuxPH = get_param(logMux,'PortHandles');
    add_line(sm,shadowPH.Outport(1),logMuxPH.Inport(oldN+1), ...
        'autorouting','on');

    fprintf('[APPEND] diag12 added as log Mux input %d\n',oldN+1);
else
    fprintf('[KEEP]   diag12 already connected to Group-26 log\n');
end

% Report RT-LAB logging settings but do not change them.
fprintf('\nGroup-26 logging settings:\n');
logParamNames = {'varname','Acq_Group','Filename','Decimation', ...
                 'Nb_Samples','Buffer_size','file_size'};

for lp = 1:numel(logParamNames)
    [ok,val] = localReadDialogOrMaskParameter(opWrite,logParamNames{lp});

    if ok
        fprintf('  %-11s = %s\n',logParamNames{lp},localToChar(val));
    else
        fprintf('  %-11s = <unreadable via Simulink API>\n',logParamNames{lp});
    end
end

% -------------------------------------------------------------------------
% Final update and safety assertions.
% -------------------------------------------------------------------------
fprintf('\n--- Final update / safety assertions ---\n');
set_param(mdl,'SimulationCommand','update');

% Existing AGC still 15/9 and untouched.
oldPortsAfter = get_param(agcOld,'Ports');
if oldPortsAfter(1) ~= 15 || oldPortsAfter(2) ~= 9
    error('S02:OriginalAGCChanged', ...
        'Existing AGC port structure changed unexpectedly.');
end

% Existing V5-A device Pref destinations still intact.
devices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
for i = 1:numel(devices)
    tag = ['V5A_FINAL_' devices{i}];
    f = localFindBlocksByTag(mdl,'From',tag);

    if isempty(f)
        error('S02:V5ATagLost','Missing V5-A From for %s.',tag);
    end
end

% Export a mapping document for later analysis.
mapFile = fullfile(modelDir, ...
    sprintf('%s__LOCAL15_STAGE02_SHADOW_MAP_%s.txt',modelBase,stamp));

fid = fopen(mapFile,'w');
if fid >= 0
    fprintf(fid,'LOCAL15 Stage 02 shadow mapping\n');
    fprintf(fid,'Model: %s\n\n',mdl);
    fprintf(fid,'Existing AGC: %s\n',agcOld);
    fprintf(fid,'Shadow AGC  : %s\n\n',mfPath);
    fprintf(fid,'Shadow diagnostic segment appended to Group-26 log:\n');
    fprintf(fid,'  1  shadow_PV1_pu\n');
    fprintf(fid,'  2  shadow_PV2_pu\n');
    fprintf(fid,'  3  shadow_ESS1_pu\n');
    fprintf(fid,'  4  shadow_ESS2_pu\n');
    fprintf(fid,'  5  shadow_EV1_pu\n');
    fprintf(fid,'  6  shadow_EV2_pu\n');
    fprintf(fid,'  7  shadow_agc_status\n');
    fprintf(fid,'  8  shadow_dP\n');
    fprintf(fid,'  9  shadow_remain\n');
    fprintf(fid,'  10 baseline_dP_request_kW\n');
    fprintf(fid,'  11 CFG15_PARAM_PROBE\n');
    fprintf(fid,'  12 CFG15_parameter_checksum\n');
    fprintf(fid,'\nNo plant command route changed in Stage 02.\n');
    fclose(fid);
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' STAGE 02 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Existing AGC control path : UNCHANGED\n');
fprintf('V5-A device routes        : UNCHANGED\n');
fprintf('Shadow AGC                : CREATED / VERIFIED\n');
fprintf('CFG15 checksum monitor    : CREATED / VERIFIED\n');
fprintf('Group-26 log              : +12 diagnostic signals appended\n');
fprintf('Mapping TXT               : %s\n',mapFile);
fprintf('\nNEXT GATE:\n');
fprintf('  Build once, Load, then verify CFG15_* parameters are editable.\n');
fprintf('  Change CFG15_PARAM_PROBE in RT-LAB without rebuilding.\n');
fprintf('  Run a short V5-A case and confirm the logged probe/checksum changed.\n');
fprintf('  Then compare current AGC outputs vs the final 9 shadow outputs.\n');
fprintf('============================================================\n\n');

end


% =========================================================================
% Helpers
% =========================================================================

function agc = localDiscoverCurrentAGC(sm)

blocks = find_system(sm, ...
    'SearchDepth',1, ...
    'MatchFilter',@Simulink.match.allVariants, ...
    'BlockType','SubSystem');

hits = {};

for i = 1:numel(blocks)
    b = blocks{i};

    try
        sfType = get_param(b,'SFBlockType');
    catch
        sfType = '';
    end

    if ~strcmp(sfType,'MATLAB Function')
        continue;
    end

    ports = get_param(b,'Ports');

    if numel(ports) >= 2 && ports(1)==15 && ports(2)==9
        hits{end+1} = b; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    error('S02:AGCDiscovery', ...
        'Expected exactly one top-level 15-in/9-out MATLAB Function AGC, found %d.', ...
        numel(hits));
end

agc = hits{1};

end


function chart = localGetEMChartByPath(blockPath)
% Exact mapping from one Simulink MATLAB Function block to its EMChart.
% MathWorks documents Stateflow.EMChart.Path as the block location.

rt = sfroot;
charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);

if isempty(charts)
    % One retry after UI/stateflow object refresh.
    drawnow;
    rt = sfroot;
    charts = find(rt,'-isa','Stateflow.EMChart','Path',blockPath);
end

if numel(charts) ~= 1
    error('S02:EMChartPath', ...
        'Expected exactly one Stateflow.EMChart at path %s, found %d.', ...
        blockPath,numel(charts));
end

chart = charts(1);

end


function [newScript,count] = localBuildExternalDPAGCScript(oldScript)

newScript = oldScript;

% Replace only the primary function declaration.
lineBreak = regexp(newScript,'\r\n|\n|\r','once');

if isempty(lineBreak)
    error('S02:AGCSourceFormat','AGC source has no line break.');
end

firstLine = newScript(1:lineBreak-1);

if ~contains(firstLine,'AGC_Controller(')
    error('S02:AGCSignature', ...
        'First AGC source line does not contain AGC_Controller(.');
end

firstLine = strrep(firstLine, ...
    'AGC_Controller(', ...
    'AGC_Baseline_dPRequest(');

closeIdx = find(firstLine==')',1,'last');

if isempty(closeIdx)
    error('S02:AGCSignature','Cannot find closing parenthesis in AGC signature.');
end

firstLine = [firstLine(1:closeIdx-1) ...
             ',dP_request_kW' ...
             firstLine(closeIdx:end)];

newScript = [firstLine newScript(lineBreak:end)];

pattern = 'dPnow\s*=\s*P_target_kW\s*-\s*P_pcc_kW\s*;';
matches = regexp(newScript,pattern,'match');
count = numel(matches);

if count ~= 1
    return;
end

newScript = regexprep(newScript,pattern, ...
    'dPnow = dP_request_kW;','once');

end


function cfgNames = localCFG15Names()

cfgNames = {
'CFG15_MASTER_ENABLE'
'CFG15_CONTROL_SOURCE'
'CFG15_SYSTEM_PROFILE'
'CFG15_TEST_CASE_ID'
'CFG15_TEST_ENABLE'
'CFG15_P_OBJECTIVE_MODE'

'CFG15_EXEC_S01'
'CFG15_EXEC_S02'
'CFG15_EXEC_S03'
'CFG15_EXEC_S04'
'CFG15_EXEC_S05'
'CFG15_EXEC_S06'
'CFG15_EXEC_S07'
'CFG15_EXEC_S08'
'CFG15_EXEC_S09'
'CFG15_EXEC_S10'
'CFG15_EXEC_S11'
'CFG15_EXEC_S12'
'CFG15_EXEC_S13'
'CFG15_EXEC_S14'
'CFG15_EXEC_S15'

'CFG15_EXEC_FAULT_ENABLE'
'CFG15_EXEC_FAULT_DEVICE'
'CFG15_EXEC_FAULT_GAIN'
'CFG15_EXEC_FAULT_START_S'
'CFG15_EXEC_FAULT_END_S'

'CFG15_BLACKSTART_MASTER'
'CFG15_ISLAND_MASTER'

'CFG15_PARAM_PROBE'
};

end


function scriptText = localBuildChecksumScript(cfgNames)

n = numel(cfgNames);

argList = cell(1,n);
for i = 1:n
    argList{i} = sprintf('p%d',i);
end

lines = {};
lines{end+1} = sprintf( ...
    'function checksum = CFG15_Checksum(%s)', ...
    strjoin(argList,','));
lines{end+1} = '%#codegen';
lines{end+1} = 'checksum = 0.0;';

for i = 1:n
    lines{end+1} = sprintf( ...
        'checksum = checksum + %.1f*p%d;',double(i),i);
end

lines{end+1} = 'end';

scriptText = strjoin(lines,newline);

end


function [opWrite,logMux] = localDiscoverAGCLogPath(sm)
% Robust discovery of the existing Group-26 AGC OpWrite path.
%
% Why this helper is deliberately defensive:
% RT-LAB library-linked Reference blocks may expose mask parameters
% differently through get_param depending on link/mask state. Therefore
% discovery must NOT rely only on get_param(block,'varname').
%
% Selection order:
%   A) exact historical path SM_Master/OpWriteFile, if it is an RT-LAB
%      OpWriteFile Reference block and is connected.
%   B) among all top-level RT-LAB OpWriteFile Reference blocks, prefer
%      Acq_Group == 26 when that parameter is readable.
%   C) otherwise prefer varname == agc_target_data when readable.
%   D) otherwise, if exactly two historical OpWriteFile candidates exist,
%      prefer the one named exactly OpWriteFile over OpWriteFile1.
%
% After selection we ALWAYS verify that its input is connected and that the
% upstream source is a Mux. Therefore a wrong selection cannot silently pass.

opWrite = '';
logMux = '';

candidates = {};

blocks = find_system(sm, ...
    'SearchDepth',1, ...
    'MatchFilter',@Simulink.match.allVariants, ...
    'Type','Block');

for i = 1:numel(blocks)
    b = blocks{i};

    bt = '';
    src = '';
    st = '';

    try
        bt = get_param(b,'BlockType');
    catch
    end

    try
        src = get_param(b,'SourceBlock');
    catch
    end

    try
        st = get_param(b,'SourceType');
    catch
    end

    isOpWrite = false;

    if strcmp(bt,'Reference')
        if contains(src,'rtlab/DataLogging/OpWriteFile') || strcmp(st,'OpWriteFile')
            isOpWrite = true;
        end
    end

    if isOpWrite
        candidates{end+1} = b; %#ok<AGROW>
    end
end

fprintf('\n  OpWrite candidates discovered: %d\n',numel(candidates));

for i = 1:numel(candidates)
    b = candidates{i};

    [okGroup,groupVal] = localReadDialogOrMaskParameter(b,'Acq_Group');
    [okVar,varVal] = localReadDialogOrMaskParameter(b,'varname');
    [okFile,fileVal] = localReadDialogOrMaskParameter(b,'Filename');

    if ~okGroup
        groupVal = '<unreadable>';
    end
    if ~okVar
        varVal = '<unreadable>';
    end
    if ~okFile
        fileVal = '<unreadable>';
    end

    fprintf('    [%d] %s | Acq_Group=%s | varname=%s | Filename=%s\n', ...
        i,b,localToChar(groupVal),localToChar(varVal),localToChar(fileVal));
end

if isempty(candidates) && getSimulinkBlockHandle([sm '/OpWriteFile']) < 0
    error('S02:OpWriteDiscovery', ...
        ['No top-level RT-LAB OpWriteFile candidates were found and the ' ...
         'known exact path %s/OpWriteFile does not exist.'],sm);
end

% A) Exact historical path first.
% The uploaded K14/V5 source model contains the Group-26 block at the
% exact path SM_Master/OpWriteFile. Do NOT require mask metadata to be
% readable before selecting it: RT-LAB Reference blocks can expose mask
% parameters inconsistently through get_param. We verify the selected
% block structurally below by checking its connected input and upstream Mux.
exactPath = [sm '/OpWriteFile'];

if getSimulinkBlockHandle(exactPath) >= 0
    opWrite = exactPath;
    fprintf('  [SELECT-A] Exact existing path: %s\n',opWrite);
end

% B) Prefer Acq_Group == 26.
if isempty(opWrite)
    groupHits = {};

    for i = 1:numel(candidates)
        [ok,val] = localReadDialogOrMaskParameter(candidates{i},'Acq_Group');

        if ok
            numVal = str2double(localToChar(val));

            if ~isnan(numVal) && numVal == 26
                groupHits{end+1} = candidates{i}; %#ok<AGROW>
            end
        end
    end

    if numel(groupHits) == 1
        opWrite = groupHits{1};
        fprintf('  [SELECT-B] Unique Acq_Group=26: %s\n',opWrite);
    elseif numel(groupHits) > 1
        error('S02:OpWriteAmbiguous', ...
            'Multiple OpWriteFile blocks report Acq_Group=26.');
    end
end

% C) Prefer varname == agc_target_data.
if isempty(opWrite)
    varHits = {};

    for i = 1:numel(candidates)
        [ok,val] = localReadDialogOrMaskParameter(candidates{i},'varname');

        if ok && strcmp(strtrim(localToChar(val)),'agc_target_data')
            varHits{end+1} = candidates{i}; %#ok<AGROW>
        end
    end

    if numel(varHits) == 1
        opWrite = varHits{1};
        fprintf('  [SELECT-C] Unique varname=agc_target_data: %s\n',opWrite);
    elseif numel(varHits) > 1
        error('S02:OpWriteAmbiguous', ...
            'Multiple OpWriteFile blocks report varname=agc_target_data.');
    end
end

% D) Historical naming fallback.
if isempty(opWrite)
    exactNameHits = {};

    for i = 1:numel(candidates)
        [~,nm] = fileparts(candidates{i});

        if strcmp(nm,'OpWriteFile')
            exactNameHits{end+1} = candidates{i}; %#ok<AGROW>
        end
    end

    if numel(exactNameHits) == 1
        opWrite = exactNameHits{1};
        fprintf('  [SELECT-D] Historical block name fallback: %s\n',opWrite);
    end
end

if isempty(opWrite)
    error('S02:OpWriteDiscovery', ...
        ['Could not uniquely select Group-26 AGC OpWriteFile. ' ...
         'Candidates were printed above; no topology change was made.']);
end

% Verify selected block has one connected input.
ph = get_param(opWrite,'PortHandles');

if isempty(ph.Inport)
    error('S02:OpWriteInput','Selected OpWriteFile has no input port: %s',opWrite);
end

ln = get_param(ph.Inport(1),'Line');

if isequal(ln,-1)
    error('S02:OpWriteUnconnected', ...
        'Selected OpWriteFile input is unconnected: %s',opWrite);
end

srcBlock = get_param(ln,'SrcBlockHandle');

if isempty(srcBlock) || srcBlock < 0
    error('S02:LogMuxSource', ...
        'Cannot resolve source block feeding selected OpWriteFile: %s',opWrite);
end

logMux = getfullname(srcBlock);

if ~strcmp(get_param(logMux,'BlockType'),'Mux')
    error('S02:LogMuxType', ...
        'Expected a Mux feeding %s, found %s at %s.', ...
        opWrite,get_param(logMux,'BlockType'),logMux);
end

% Optional sanity print of selected group/varname.
[okGroup,groupVal] = localReadDialogOrMaskParameter(opWrite,'Acq_Group');
[okVar,varVal] = localReadDialogOrMaskParameter(opWrite,'varname');

if okGroup
    fprintf('  Selected Acq_Group = %s\n',localToChar(groupVal));
end

if okVar
    fprintf('  Selected varname   = %s\n',localToChar(varVal));
end

fprintf('  Upstream log Mux   = %s (Inputs=%s)\n', ...
    logMux,get_param(logMux,'Inputs'));

end


function [ok,val] = localReadDialogOrMaskParameter(block,paramName)
% Read a block parameter robustly across ordinary blocks and masked
% RT-LAB library-linked Reference blocks.

ok = false;
val = '';

% 1) Direct get_param.
try
    val = get_param(block,paramName);
    ok = true;
    return;
catch
end

% 2) ObjectParameters may expose a case-sensitive actual field name.
try
    obj = get_param(block,'ObjectParameters');
    fields = fieldnames(obj);

    hit = find(strcmpi(fields,paramName),1,'first');

    if ~isempty(hit)
        actualName = fields{hit};

        try
            val = get_param(block,actualName);
            ok = true;
            return;
        catch
        end
    end
catch
end

% 3) MaskNames / MaskValues.
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

% 4) DialogParameters can expose mask/dialog names.
try
    dp = get_param(block,'DialogParameters');

    if isstruct(dp)
        fields = fieldnames(dp);
        hit = find(strcmpi(fields,paramName),1,'first');

        if ~isempty(hit)
            actualName = fields{hit};

            try
                val = get_param(block,actualName);
                ok = true;
                return;
            catch
            end
        end
    end
catch
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


function blocks = localFindBlocksByTag(mdl,blockType,tag)

blocks = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'MatchFilter',@Simulink.match.allVariants, ...
    'BlockType',blockType, ...
    'GotoTag',tag);

end


function localEnsureLine(parent,src,dst)

srcBlock = strtok(src,'/');
dstBlock = strtok(dst,'/');

srcPortStr = extractAfter(src,'/');
dstPortStr = extractAfter(dst,'/');

srcPath = [parent '/' srcBlock];
dstPath = [parent '/' dstBlock];

if getSimulinkBlockHandle(srcPath) < 0
    error('S02:LineSourceMissing','Missing source block: %s',srcPath);
end

if getSimulinkBlockHandle(dstPath) < 0
    error('S02:LineDestMissing','Missing destination block: %s',dstPath);
end

srcPH = get_param(srcPath,'PortHandles');
dstPH = get_param(dstPath,'PortHandles');

srcIdx = str2double(srcPortStr);
dstIdx = str2double(dstPortStr);

if isnan(srcIdx) || isnan(dstIdx)
    error('S02:PortSyntax','Port syntax must be Block/number.');
end

if srcIdx > numel(srcPH.Outport) || dstIdx > numel(dstPH.Inport)
    error('S02:PortRange', ...
        'Port index out of range while connecting %s -> %s.',src,dst);
end

dstLine = get_param(dstPH.Inport(dstIdx),'Line');

if isequal(dstLine,-1)
    add_line(parent,srcPH.Outport(srcIdx),dstPH.Inport(dstIdx), ...
        'autorouting','on');
else
    existingSrc = get_param(dstLine,'SrcPortHandle');

    if existingSrc ~= srcPH.Outport(srcIdx)
        error('S02:UnexpectedExistingLine', ...
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


function [x,y] = localFindFreeAroundAnchor(parent,anchor,w,h)

blocks = find_system(parent,'SearchDepth',1,'Type','Block');
rects = [];

for k = 1:numel(blocks)
    if strcmp(blocks{k},parent)
        continue;
    end

    try
        p = get_param(blocks{k},'Position');
        if isnumeric(p) && numel(p)==4
            rects(end+1,:) = p; %#ok<AGROW>
        end
    catch
    end
end

candidates = [
    anchor(1),           anchor(2)-h-80
    anchor(3)+60,        anchor(2)
    anchor(1),           anchor(4)+80
    anchor(1)-w-80,      anchor(2)
];

for i = 1:size(candidates,1)
    xx = candidates(i,1);
    yy = candidates(i,2);
    testRect = [xx yy xx+w yy+h];

    if ~localAnyOverlap(testRect,rects,20)
        x = xx;
        y = yy;
        return;
    end
end

[x,y] = localFindFreeTopLevelPosition(parent,w,h,420);

end


function tf = localAnyOverlap(a,rects,margin)

tf = false;

a2 = [a(1)-margin a(2)-margin a(3)+margin a(4)+margin];

for i = 1:size(rects,1)
    b = rects(i,:);

    separated = ...
        a2(3) < b(1) || ...
        a2(1) > b(3) || ...
        a2(4) < b(2) || ...
        a2(2) > b(4);

    if ~separated
        tf = true;
        return;
    end
end

end

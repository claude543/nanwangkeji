%% S00_K26_V5_LOCAL15_AUDIT_AND_TUNABILITY_LOCK_V3.m
% LOCAL15 Stage 00 V3
% Purpose:
%   1) Audit the ACTIVE model using mdl = bdroot(gcs).
%   2) Do not assume exact device Mux block names.
%   3) Discover each device control Mux from the V5A_FINAL_<DEVICE> Pref route.
%   4) Verify the current V5-A route without changing topology/wiring.
%   5) Lock the model to tunable parameter code-generation behavior.
%   6) Export an audit TXT and CFG Constant CSV beside the model file.
%
% Model changes made by this script:
%   - DefaultParameterBehavior -> Tunable (if available)
%   - ParameterTunabilityLossMsg -> error (if available)
%   - NO block/line/port/topology changes.
%
% IMPORTANT:
%   - Run with the intended Simulink model open and click inside that model.
%   - This script is discovery-first. Nonessential naming differences are reported,
%     not treated as fatal errors.

fprintf('\n============================================================\n');
fprintf(' LOCAL15 Stage 00 V3 - Discovery Audit + Tunability Lock\n');
fprintf('============================================================\n');

%% 0. Resolve active model
mdl = bdroot(gcs);
if isempty(mdl) || strcmp(mdl,'0')
    error('No active Simulink model detected. Open the intended model and click inside it, then rerun.');
end
load_system(mdl);

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('The active model has no valid .slx file path. Save the model first, then rerun.');
end
modelDir = fileparts(modelFile);
stamp = datestr(now,'yyyymmdd_HHMMSS');
[~,baseName,ext] = fileparts(modelFile);

fprintf('Active model : %s\n', mdl);
fprintf('Model file   : %s\n', modelFile);

%% 1. Backup before any configuration change
backupFile = fullfile(modelDir, sprintf('%s__PRE_LOCAL15_STAGE00_V3_%s%s', baseName, stamp, ext));
copyfile(modelFile, backupFile, 'f');
fprintf('Backup       : %s\n', backupFile);

%% 2. Tunability policy
oldDPB  = localGetParamSafe(mdl,'DefaultParameterBehavior','<UNAVAILABLE>');
oldLoss = localGetParamSafe(mdl,'ParameterTunabilityLossMsg','<UNAVAILABLE>');

fprintf('\n--- Tunability configuration BEFORE ---\n');
fprintf('DefaultParameterBehavior  : %s\n', char(string(oldDPB)));
fprintf('ParameterTunabilityLossMsg: %s\n', char(string(oldLoss)));

try
    if ~strcmpi(string(oldDPB),'Tunable')
        set_param(mdl,'DefaultParameterBehavior','Tunable');
    end
catch ME
    warning('Could not set DefaultParameterBehavior=Tunable: %s', ME.message);
end

try
    set_param(mdl,'ParameterTunabilityLossMsg','error');
catch ME
    warning('Could not set ParameterTunabilityLossMsg=error: %s', ME.message);
end

newDPB  = localGetParamSafe(mdl,'DefaultParameterBehavior','<UNAVAILABLE>');
newLoss = localGetParamSafe(mdl,'ParameterTunabilityLossMsg','<UNAVAILABLE>');

fprintf('\n--- Tunability configuration AFTER ---\n');
fprintf('DefaultParameterBehavior  : %s\n', char(string(newDPB)));
fprintf('ParameterTunabilityLossMsg: %s\n', char(string(newLoss)));

if ~strcmpi(string(newDPB),'Tunable')
    error('FAIL: DefaultParameterBehavior is not Tunable. Do not continue LOCAL15 work.');
end

%% 3. RT-LAB subsystem discovery
fprintf('\n--- Top-level subsystem discovery ---\n');
requiredTop = {'SM_Master','SS_Slave','SS_Slave2','SS_Slave3','SC_Console'};
for k = 1:numel(requiredTop)
    p = [mdl '/' requiredTop{k}];
    if getSimulinkBlockHandle(p) > 0
        fprintf('[OK]   %s\n', p);
    else
        fprintf('[MISS] %s\n', p);
    end
end

sm = [mdl '/SM_Master'];
if getSimulinkBlockHandle(sm) <= 0
    error('FAIL: SM_Master was not found. Stage 00 cannot continue.');
end

%% 4. 15-strategy layer
fprintf('\n--- 15-strategy layer ---\n');
aa = [sm '/Advanced_Microgrid_15_Strategies'];
if getSimulinkBlockHandle(aa) > 0
    portsAA = get_param(aa,'Ports');
    fprintf('[OK] %s\n', aa);
    fprintf('     Ports = %s\n', mat2str(portsAA));
else
    fprintf('[MISS] %s\n', aa);
end

requiredAATags = {'SIG_AA_STATUS15','SIG_AA_ALARM15','SIG_AA_METRIC15','SIG_AA_CMD15'};
for k = 1:numel(requiredAATags)
    tag = requiredAATags{k};
    g = find_system(sm,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto','GotoTag',tag);
    f = find_system(sm,'LookUnderMasks','all','FollowLinks','on','BlockType','From','GotoTag',tag);
    fprintf('%-20s : Goto=%d, From=%d\n', tag, numel(g), numel(f));
end

%% 5. V5-A final Pref tag audit
fprintf('\n--- V5-A final Pref tags ---\n');
devices = {'PV1','PV2','ESS1','ESS2','EV1','EV2'};
for d = 1:numel(devices)
    tag = ['V5A_FINAL_' devices{d}];
    g = find_system(sm,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto','GotoTag',tag);
    f = find_system(sm,'LookUnderMasks','all','FollowLinks','on','BlockType','From','GotoTag',tag);
    fprintf('%-20s : Goto=%d, From=%d\n', tag, numel(g), numel(f));
end

v5DiagHits = find_system(sm,'SearchDepth',1,'RegExp','on','Name','^V5A_DIAG_MUX.*$');
if isempty(v5DiagHits)
    fprintf('[WARN] No top-level V5A_DIAG_MUX* block found.\n');
else
    for k = 1:numel(v5DiagHits)
        fprintf('[OK] V5 diagnostic block: %s\n', v5DiagHits{k});
    end
end

%% 6. Discover each device control Mux from its actual V5A Pref route
% This deliberately avoids hard-coded names such as EV1_IO_Mux12.
% The current uploaded K14 family contains mixed names (e.g. EV1_IO_Mux,
% EV2_IO_Mux, PV1_IO_Mux12, ...), so the Pref route is the source of truth.

fprintf('\n--- Device control-vector discovery from V5A Pref route ---\n');
semanticNames = {'Vabc[3]','Iabc[3]','Fref','Vref','Droop_On','Pref','Qref','GridOn'};
expectedPhysicalInputs = 8;

deviceAudit = struct();
for d = 1:numel(devices)
    dev = devices{d};
    tag = ['V5A_FINAL_' dev];

    froms = find_system(sm,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
        'BlockType','From','GotoTag',tag);

    muxCandidates = {};
    prefFromCandidates = {};
    prefDstPorts = [];

    for i = 1:numel(froms)
        [dstBlocks,dstPorts] = localGetOutDestinations(froms{i});
        for j = 1:numel(dstBlocks)
            if getSimulinkBlockHandle(dstBlocks{j}) > 0 && strcmp(get_param(dstBlocks{j},'BlockType'),'Mux')
                muxCandidates{end+1} = dstBlocks{j}; %#ok<AGROW>
                prefFromCandidates{end+1} = froms{i}; %#ok<AGROW>
                prefDstPorts(end+1) = dstPorts(j); %#ok<AGROW>
            end
        end
    end

    muxCandidates = unique(muxCandidates,'stable');

    % Fallback discovery only if the route-based search found nothing.
    if isempty(muxCandidates)
        allTopMux = find_system(sm,'SearchDepth',1,'BlockType','Mux');
        names = get_param(allTopMux,'Name');
        if ischar(names), names = {names}; end
        idx = find(startsWith(names,[dev '_IO_Mux'],'IgnoreCase',false));
        muxCandidates = allTopMux(idx);
    end

    fprintf('\n%s\n', dev);
    fprintf('  V5 tag From blocks : %d\n', numel(froms));

    if isempty(muxCandidates)
        fprintf('  [FAIL] No device control Mux could be discovered for %s.\n', dev);
        deviceAudit.(dev).Mux = '<NOT_FOUND>';
        continue;
    elseif numel(muxCandidates) > 1
        fprintf('  [WARN] Multiple Mux candidates discovered:\n');
        for i = 1:numel(muxCandidates)
            fprintf('         %s\n', muxCandidates{i});
        end
        fprintf('  Stage 00 will audit the first route-connected candidate only.\n');
    end

    muxPath = muxCandidates{1};
    deviceAudit.(dev).Mux = muxPath;
    fprintf('  Control Mux        : %s\n', muxPath);
    fprintf('  Mux block name     : %s\n', get_param(muxPath,'Name'));

    ph = get_param(muxPath,'PortHandles');
    nIn = numel(ph.Inport);
    fprintf('  Physical inputs    : %d\n', nIn);
    if nIn ~= expectedPhysicalInputs
        fprintf('  [FAIL] Expected %d physical inputs for [Vabc,Iabc,Fref,Vref,Droop,Pref,Qref,GridOn].\n', expectedPhysicalInputs);
    else
        fprintf('  [OK] Physical input count is 8; semantic vector width is 3+3+6=12.\n');
    end

    srcInfo = localGetInputSourceInfo(muxPath);
    for pidx = 1:numel(srcInfo)
        if pidx <= numel(semanticNames)
            sem = semanticNames{pidx};
        else
            sem = sprintf('Input%d',pidx);
        end
        fprintf('    in:%d %-10s <- %s\n', pidx, sem, srcInfo{pidx});
    end

    % Confirm which Mux input receives V5A_FINAL_<device>.
    prefPortFound = 0;
    for pidx = 1:numel(ph.Inport)
        lineH = get_param(ph.Inport(pidx),'Line');
        if lineH == -1, continue; end
        srcPortH = get_param(lineH,'SrcPortHandle');
        if isempty(srcPortH) || srcPortH == -1, continue; end
        srcBlockH = get_param(srcPortH,'Parent');
        srcPath = getfullname(srcBlockH);
        if strcmp(get_param(srcPath,'BlockType'),'From')
            gt = localGetParamSafe(srcPath,'GotoTag','');
            if strcmp(gt,tag)
                prefPortFound = pidx;
                fprintf('  [OK] %s enters Mux physical input %d.\n', tag, pidx);
            end
        end
    end
    if prefPortFound == 0
        fprintf('  [WARN] Could not confirm %s at a Mux input by GotoTag inspection.\n', tag);
    elseif prefPortFound ~= 6
        fprintf('  [WARN] Pref is at input %d, not the expected semantic input 6. Record actual model as source of truth.\n', prefPortFound);
    end
end

%% 7. Report all top-level device IO Mux names (for human review)
fprintf('\n--- All top-level *_IO_Mux* blocks ---\n');
allTopMux = find_system(sm,'SearchDepth',1,'BlockType','Mux');
for i = 1:numel(allTopMux)
    nm = get_param(allTopMux{i},'Name');
    if contains(nm,'_IO_Mux')
        fprintf('  %s   Inputs=%s\n', allTopMux{i}, localGetParamSafe(allTopMux{i},'Inputs','<NA>'));
    end
end

%% 8. PCC breaker / load / related block discovery (no naming assumptions)
fprintf('\n--- PCC / Breaker / Load discovery ---\n');
allTopBlocks = find_system(sm,'SearchDepth',1,'Type','Block');
for i = 1:numel(allTopBlocks)
    nm = get_param(allTopBlocks{i},'Name');
    if contains(lower(nm),'load') || contains(lower(nm),'breaker') || contains(lower(nm),'pcc')
        bt = get_param(allTopBlocks{i},'BlockType');
        commented = localGetParamSafe(allTopBlocks{i},'Commented','<NA>');
        fprintf('  %-70s Type=%-12s Commented=%s\n', allTopBlocks{i}, bt, char(string(commented)));
    end
end

%% 9. CFG Constant inventory
fprintf('\n--- CFG Constant inventory ---\n');
allConst = find_system(sm,'LookUnderMasks','all','FollowLinks','on','BlockType','Constant');
rows = {};
for i = 1:numel(allConst)
    nm = get_param(allConst{i},'Name');
    if startsWith(nm,'CFG_') || startsWith(nm,'CFG15_')
        val = localGetParamSafe(allConst{i},'Value','<NA>');
        st  = localGetParamSafe(allConst{i},'SampleTime','<NA>');
        rows(end+1,:) = {allConst{i}, nm, char(string(val)), char(string(st))}; %#ok<AGROW>
    end
end
fprintf('CFG/CFG15 Constant count: %d\n', size(rows,1));

csvFile = fullfile(modelDir, sprintf('%s__LOCAL15_CFG_CONSTANTS_%s.csv',baseName,stamp));
if isempty(rows)
    T = cell2table(cell(0,4),'VariableNames',{'BlockPath','Name','Value','SampleTime'});
else
    T = cell2table(rows,'VariableNames',{'BlockPath','Name','Value','SampleTime'});
end
writetable(T,csvFile);
fprintf('CFG CSV : %s\n', csvFile);

%% 10. Core model configuration report
fprintf('\n--- Core model configuration ---\n');
cfgFields = {'SolverType','Solver','FixedStep','DefaultParameterBehavior', ...
    'ParameterTunabilityLossMsg','BlockReduction','ExpressionFolding','OptimizeBlockIOStorage'};
for k = 1:numel(cfgFields)
    fprintf('%-30s : %s\n', cfgFields{k}, char(string(localGetParamSafe(mdl,cfgFields{k},'<UNAVAILABLE>'))));
end

%% 11. Save configuration-only change
save_system(mdl);

%% 12. Write text report by replaying key discovered facts
reportFile = fullfile(modelDir, sprintf('%s__LOCAL15_STAGE00_V3_AUDIT_%s.txt',baseName,stamp));
fid = fopen(reportFile,'w');
if fid < 0
    warning('Could not create audit TXT file: %s', reportFile);
else
    fprintf(fid,'LOCAL15 Stage 00 V3 Audit\n');
    fprintf(fid,'Model: %s\n', mdl);
    fprintf(fid,'File : %s\n', modelFile);
    fprintf(fid,'Backup: %s\n\n', backupFile);
    fprintf(fid,'DefaultParameterBehavior=%s\n', char(string(newDPB)));
    fprintf(fid,'ParameterTunabilityLossMsg=%s\n\n', char(string(newLoss)));

    fprintf(fid,'Device control Mux discovery:\n');
    for d = 1:numel(devices)
        dev = devices{d};
        if isfield(deviceAudit,dev) && isfield(deviceAudit.(dev),'Mux')
            fprintf(fid,'%s -> %s\n', dev, deviceAudit.(dev).Mux);
        end
    end
    fprintf(fid,'\nCFG Constant count=%d\n',size(rows,1));
    fclose(fid);
end
fprintf('Audit TXT: %s\n', reportFile);

fprintf('\n============================================================\n');
fprintf(' STAGE 00 V3 COMPLETE\n');
fprintf(' - No topology/wiring changes were made.\n');
fprintf(' - Device Muxes were discovered from actual V5A Pref routes.\n');
fprintf(' - Tunability policy is locked to Tunable.\n');
fprintf('============================================================\n\n');

%% Local functions
function v = localGetParamSafe(obj,paramName,defaultValue)
try
    v = get_param(obj,paramName);
catch
    v = defaultValue;
end
end

function [dstBlocks,dstPortNumbers] = localGetOutDestinations(blockPath)
dstBlocks = {};
dstPortNumbers = [];
try
    ph = get_param(blockPath,'PortHandles');
    if ~isfield(ph,'Outport') || isempty(ph.Outport)
        return;
    end
    for op = 1:numel(ph.Outport)
        lineH = get_param(ph.Outport(op),'Line');
        if isempty(lineH) || lineH == -1
            continue;
        end
        dstBH = get_param(lineH,'DstBlockHandle');
        dstPH = get_param(lineH,'DstPortHandle');
        if isempty(dstBH), continue; end
        dstBH = dstBH(:)';
        dstPH = dstPH(:)';
        for k = 1:numel(dstBH)
            if dstBH(k) == -1, continue; end
            dstBlocks{end+1} = getfullname(dstBH(k)); %#ok<AGROW>
            if k <= numel(dstPH) && dstPH(k) ~= -1
                dstPortNumbers(end+1) = str2double(get_param(dstPH(k),'PortNumber')); %#ok<AGROW>
            else
                dstPortNumbers(end+1) = NaN; %#ok<AGROW>
            end
        end
    end
catch
    % Discovery helper: return what was found, do not make Stage 00 brittle.
end
end

function srcInfo = localGetInputSourceInfo(blockPath)
ph = get_param(blockPath,'PortHandles');
srcInfo = cell(1,numel(ph.Inport));
for k = 1:numel(ph.Inport)
    lineH = get_param(ph.Inport(k),'Line');
    if isempty(lineH) || lineH == -1
        srcInfo{k} = '<UNCONNECTED>';
        continue;
    end
    srcPortH = get_param(lineH,'SrcPortHandle');
    if isempty(srcPortH) || srcPortH == -1
        srcInfo{k} = '<NO_SOURCE>';
        continue;
    end
    srcBlockH = get_param(srcPortH,'Parent');
    srcPath = getfullname(srcBlockH);
    srcType = get_param(srcPath,'BlockType');
    extra = '';
    if strcmp(srcType,'From')
        extra = [' tag=' char(string(localGetParamSafe(srcPath,'GotoTag','')))];
    elseif strcmp(srcType,'Constant')
        extra = [' value=' char(string(localGetParamSafe(srcPath,'Value','')))];
    elseif strcmp(srcType,'Step')
        extra = sprintf(' time=%s initial=%s final=%s', ...
            char(string(localGetParamSafe(srcPath,'Time',''))), ...
            char(string(localGetParamSafe(srcPath,'Before',''))), ...
            char(string(localGetParamSafe(srcPath,'After',''))));
    end
    srcInfo{k} = sprintf('%s [%s]%s',srcPath,srcType,extra);
end
end

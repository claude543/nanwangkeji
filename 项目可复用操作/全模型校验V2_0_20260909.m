% K26_FULL_MODEL_READONLY_AUDIT_V2_0_20260909.m
% Full read-only structural/connectivity audit for the currently active Simulink model.
%
% DESIGN RULES
%   1) No add_block / delete_block / add_line / delete_line.
%   2) No set_param / save_system / close_system.
%   3) FollowLinks='off': audit model-owned structure first; linked-library internals
%      are not treated as editable model-owned content.
%   4) Static audit is always executed.
%   5) Compiled audit is implemented but OFF by default because compile/update can
%      invoke model callbacks and RT-LAB/ARTEMiS-specific compile behavior.
%
% OUTPUT
%   A time-stamped AUDIT_<model>_<time> folder beside the .slx file, plus ZIP.
%   The ZIP is intended to be uploaded for downstream explanation / cleanup planning.
%
% MATLAB target: R2023b

function K26_FULL_MODEL_READONLY_AUDIT_V2_0_20260909()

AUDIT_VERSION = 'K26_FULL_MODEL_READONLY_AUDIT_V2_0_20260909';
EXPECTED_BASELINE_SHA256 = '23fc0cd10c8dc12da8e58541d3b137d0f950d9f364ad4556296f83973bcee4e3';
REQUIRE_EXPECTED_HASH = true;
MIN_EXPECTED_BLOCKS = 5000;
MIN_EXPECTED_FUNCTIONS = 80;
MIN_EXPECTED_SPECIAL_BLOCKS = 50;
MIN_EXPECTED_RTLAB_BLOCKS = 10;
REQUIRE_STOPPED = true;
REQUIRE_CLEAN_MODEL = true;
RUN_COMPILED_PHASE = false;   % Keep FALSE for the first run.
MAX_PARAM_CHARS = 4000;
MAX_LIST_CHARS = 12000;

TOKENS = { ...
    'AA15_','CFG15_','ISLAND','GFM','GFL', ...
    'F20','F21','F22','F23','F24','F25', ...
    'V47','V48','V49','QBIAS','LFQ','DAMP','VFF', ...
    'PLL','RESYNC','RECOVERY','BLACKSTART','BLACK_START', ...
    'BREAKER','DROOP','COMMIT','HOLD','BYPASS','SHADOW','LEGACY', ...
    'DIAG','OPCOMM','OPWRITE','OPINPUT','OPOUTPUT', ...
    'CURRENT_EXECUTION','FINALIZER','COORDINATOR','MANAGER','ROUTER', ...
    'CURRENT REGULATOR','VOLTAGE REGULATOR','POWER CONTROL LOOP', ...
    'VREF GENERATION','PCC','J1'};

fprintf('\n============================================================\n');
fprintf(' FULL MODEL READ-ONLY AUDIT\n');
fprintf(' Version: %s\n', AUDIT_VERSION);
fprintf('============================================================\n');

target = localResolveTargetModelFromScript();
mdl = target.ModelName;
modelFile = string(target.TargetFile);
loadedModelFile = string(target.LoadedFile);
simStatus = string(get_param(mdl,'SimulationStatus'));
dirty = string(get_param(mdl,'Dirty'));

if REQUIRE_STOPPED && ~strcmpi(simStatus,'stopped')
    error('AUDIT:ModelNotStopped', ...
        'Target model "%s" is not STOPPED. Current SimulationStatus=%s.', mdl, simStatus);
end

if REQUIRE_CLEAN_MODEL && ~strcmpi(dirty,'off')
    error('AUDIT:DirtyModel', ...
        ['Target model "%s" is Dirty=ON. This audit is intended to create a canonical ' ...
         'read-only baseline. Save/revert the model first, then run again.'], mdl);
end

modelHash = string(localFileSha256(char(modelFile)));
if REQUIRE_EXPECTED_HASH && ~strcmpi(modelHash,EXPECTED_BASELINE_SHA256)
    error('AUDIT:BaselineHashMismatch', ...
        ['Target file is in the correct script/model folder, but SHA256 does not match the frozen ' ...
         '2026-09-09 baseline. Expected=%s, Actual=%s, File=%s. ' ...
         'Do not continue until model identity is confirmed.'], ...
         EXPECTED_BASELINE_SHA256,char(modelHash),char(modelFile));
end
stamp = datestr(now,'yyyymmdd_HHMMSS');
modelFolder = fileparts(char(modelFile));
outDir = fullfile(modelFolder, ['AUDIT_' localSafeFileName(mdl) '_' stamp]);
mkdir(outDir);
funcDir = fullfile(outDir,'matlab_functions');
mkdir(funcDir);

diaryFile = fullfile(outDir,'00_console_log.txt');
diary(diaryFile);
diaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('Target model      : %s\n', mdl);
fprintf('Model file        : %s\n', modelFile);
fprintf('Loaded model file : %s\n', loadedModelFile);
fprintf('SHA256            : %s\n', modelHash);
fprintf('SimulationStatus  : %s\n', simStatus);
fprintf('Dirty             : %s\n', dirty);
fprintf('Output folder     : %s\n', outDir);
fprintf('Compiled phase    : %d\n\n', RUN_COMPILED_PHASE);

%% ------------------------------------------------------------------------
%  1. MODEL METADATA / CALLBACKS
%  ------------------------------------------------------------------------
metaNames = { ...
    'Name','FileName','SimulationStatus','Dirty','BlockDiagramType', ...
    'SolverType','Solver','FixedStep','StartTime','StopTime', ...
    'DefaultParameterBehavior','ParameterTunabilityLossMsg', ...
    'SignalLogging','SaveOutput','SaveTime','ReturnWorkspaceOutputs', ...
    'PreLoadFcn','PostLoadFcn','InitFcn','StartFcn','PauseFcn', ...
    'ContinueFcn','StopFcn','CloseFcn','PreSaveFcn','PostSaveFcn'};

metaRows = cell(numel(metaNames)+7,2);
metaRows(1,:) = {'AUDIT_VERSION',AUDIT_VERSION};
metaRows(2,:) = {'AUDIT_TIME',datestr(now,31)};
metaRows(3,:) = {'MODEL_SHA256',char(modelHash)};
metaRows(4,:) = {'CANONICAL_FILE',char(modelFile)};
metaRows(5,:) = {'LOADED_FILE',char(loadedModelFile)};
metaRows(6,:) = {'SCRIPT_FILE',target.ScriptFile};
metaRows(7,:) = {'EXPECTED_BASELINE_SHA256',EXPECTED_BASELINE_SHA256};
for i = 1:numel(metaNames)
    metaRows{i+7,1} = metaNames{i};
    metaRows{i+7,2} = char(localSafeGetParam(mdl,metaNames{i},MAX_LIST_CHARS));
end
metaTable = cell2table(metaRows,'VariableNames',{'Property','Value'});
writetable(metaTable,fullfile(outDir,'01_model_metadata.csv'));

pathShadowTable = localBuildPathShadowTable(mdl,char(modelFile));
writetable(pathShadowTable,fullfile(outDir,'01B_model_path_shadowing.csv'));

%% ------------------------------------------------------------------------
%  2. ALL MODEL-OWNED BLOCKS + DIALOG PARAMETERS
%  ------------------------------------------------------------------------
fprintf('[1/12] Reading all model-owned blocks...\n');

blockPaths = find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','off', ...
    'Type','block');
blockPaths = blockPaths(:);
nBlocks = numel(blockPaths);
if nBlocks < MIN_EXPECTED_BLOCKS
    error('AUDIT:BlockEnumerationIncomplete', ...
        ['find_system returned only %d model-owned blocks; expected at least %d for this model. ' ...
         'Audit is aborted rather than producing a misleading partial package.'], ...
         nBlocks,MIN_EXPECTED_BLOCKS);
end

blockTable = table('Size',[nBlocks 25], ...
    'VariableTypes', { ...
        'string','string','string','double','string','string','string','string', ...
        'string','double','string','string','string','string','string','string', ...
        'double','double','double','double','double','double','double','double','string'}, ...
    'VariableNames', { ...
        'Path','Name','Parent','Depth','BlockType','MaskType','SFBlockType','LinkStatus', ...
        'ReferenceBlock','Handle','SID','Commented','Description','Tag','SampleTime','PortParam', ...
        'NumIn','NumOut','NumEnable','NumTrigger','NumState','NumLConn','NumRConn', ...
        'DialogParameterCount','MatchedTokens'});

paramRows = cell(0,4);
auditErrorRows = cell(0,3);

for i = 1:nBlocks
    b = blockPaths{i};
    try
        h = get_param(b,'Handle');
        [nin,nout,nen,ntrg,nstate,nlc,nrc] = localPortCounts(b);

        blockTable.Path(i) = string(b);
        blockTable.Name(i) = localSafeGetParam(b,'Name',MAX_LIST_CHARS);
        blockTable.Parent(i) = localSafeGetParam(b,'Parent',MAX_LIST_CHARS);
        blockTable.Depth(i) = localPathDepth(b,mdl);
        blockTable.BlockType(i) = localSafeGetParam(b,'BlockType',MAX_LIST_CHARS);
        blockTable.MaskType(i) = localSafeGetParam(b,'MaskType',MAX_LIST_CHARS);
        blockTable.SFBlockType(i) = localSafeGetParam(b,'SFBlockType',MAX_LIST_CHARS);
        blockTable.LinkStatus(i) = localSafeGetParam(b,'LinkStatus',MAX_LIST_CHARS);
        blockTable.ReferenceBlock(i) = localSafeGetParam(b,'ReferenceBlock',MAX_LIST_CHARS);
        blockTable.Handle(i) = double(h);
        blockTable.SID(i) = localSafeSID(b);
        blockTable.Commented(i) = localSafeGetParam(b,'Commented',MAX_LIST_CHARS);
        blockTable.Description(i) = localSafeGetParam(b,'Description',MAX_LIST_CHARS);
        blockTable.Tag(i) = localSafeGetParam(b,'Tag',MAX_LIST_CHARS);
        blockTable.SampleTime(i) = localSafeGetParam(b,'SampleTime',MAX_LIST_CHARS);
        blockTable.PortParam(i) = localSafeGetParam(b,'Port',MAX_LIST_CHARS);
        blockTable.NumIn(i) = nin;
        blockTable.NumOut(i) = nout;
        blockTable.NumEnable(i) = nen;
        blockTable.NumTrigger(i) = ntrg;
        blockTable.NumState(i) = nstate;
        blockTable.NumLConn(i) = nlc;
        blockTable.NumRConn(i) = nrc;

        combined = strjoin([ ...
            blockTable.Path(i),blockTable.BlockType(i),blockTable.MaskType(i), ...
            blockTable.SFBlockType(i),blockTable.ReferenceBlock(i)]," ");
        blockTable.MatchedTokens(i) = localMatchedTokens(combined,TOKENS);

        dp = [];
        try
            dp = get_param(b,'DialogParameters');
        catch
        end
        pcount = 0;
        if isstruct(dp)
            pnames = fieldnames(dp);
            for j = 1:numel(pnames)
                pval = localSafeGetParam(b,pnames{j},MAX_PARAM_CHARS);
                if strlength(pval)>0
                    pcount = pcount + 1;
                    paramRows(end+1,:) = {b, char(blockTable.BlockType(i)), ...
                        pnames{j}, char(pval)}; %#ok<SAGROW>
                end
            end
        end
        blockTable.DialogParameterCount(i) = pcount;

    catch ME
        auditErrorRows(end+1,:) = {'BLOCK',b,localOneLine(ME.message)}; %#ok<SAGROW>
    end

    if mod(i,500)==0 || i==nBlocks
        fprintf('  Blocks: %d / %d\n',i,nBlocks);
    end
end

writetable(blockTable,fullfile(outDir,'02_blocks_all.csv'));

if isempty(paramRows)
    paramTable = cell2table(cell(0,4), ...
        'VariableNames',{'Path','BlockType','Parameter','Value'});
else
    paramTable = cell2table(paramRows, ...
        'VariableNames',{'Path','BlockType','Parameter','Value'});
end
writetable(paramTable,fullfile(outDir,'03_block_dialog_parameters.csv'));

%% ------------------------------------------------------------------------
%  3. ALL LINE OBJECTS -> POINT-TO-POINT EDGES
%  ------------------------------------------------------------------------
fprintf('[2/12] Reading all line objects and expanded destinations...\n');

lineHandles = find_system(mdl,'FindAll','on','Type','line');
lineHandles = lineHandles(:);
edgeRows = repmat(localEmptyEdgeRow(),0,1);

for i = 1:numel(lineHandles)
    lh = lineHandles(i);
    try
        parentSystem = localSafeGetHandleParam(lh,'Parent',MAX_LIST_CHARS);
        lineName = localSafeGetHandleParam(lh,'Name',MAX_LIST_CHARS);
        srcBH = get_param(lh,'SrcBlockHandle');
        srcPH = get_param(lh,'SrcPortHandle');
        dstBH = get_param(lh,'DstBlockHandle');
        dstPH = get_param(lh,'DstPortHandle');

        srcPath = localBlockHandleToPath(srcBH);
        srcType = localSafeGetParam(char(srcPath),'BlockType',MAX_LIST_CHARS);
        srcPort = localPortNumber(srcPH);
        srcPortType = localPortType(srcPH);

        validDst = [];
        if isnumeric(dstBH)
            validDst = find(dstBH>0);
        end

        if isempty(validDst)
            r = localEmptyEdgeRow();
            r.ParentSystem = parentSystem;
            r.LineHandle = double(lh);
            r.LineName = lineName;
            r.SrcBlock = srcPath;
            r.SrcBlockType = srcType;
            r.SrcPort = srcPort;
            r.SrcPortType = srcPortType;
            edgeRows(end+1,1) = r; %#ok<SAGROW>
        else
            for jj = 1:numel(validDst)
                k = validDst(jj);
                dbh = dstBH(k);
                dph = localNthNumeric(dstPH,k);
                dstPath = localBlockHandleToPath(dbh);
                dstType = localSafeGetParam(char(dstPath),'BlockType',MAX_LIST_CHARS);

                r = localEmptyEdgeRow();
                r.ParentSystem = parentSystem;
                r.LineHandle = double(lh);
                r.LineName = lineName;
                r.SrcBlock = srcPath;
                r.SrcBlockType = srcType;
                r.SrcPort = srcPort;
                r.SrcPortType = srcPortType;
                r.DstBlock = dstPath;
                r.DstBlockType = dstType;
                r.DstPort = localPortNumber(dph);
                r.DstPortType = localPortType(dph);
                edgeRows(end+1,1) = r; %#ok<SAGROW>
            end
        end
    catch ME
        auditErrorRows(end+1,:) = {'LINE',num2str(lh),localOneLine(ME.message)}; %#ok<SAGROW>
    end
end

if isempty(edgeRows)
    edgeTable = struct2table(localEmptyEdgeRow(),'AsArray',true);
    edgeTable(1,:) = [];
else
    edgeTable = struct2table(edgeRows);
end
writetable(edgeTable,fullfile(outDir,'04_edges_point_to_point.csv'));

linePropertyTable = localBuildLinePropertyTable(edgeTable,MAX_LIST_CHARS);
writetable(linePropertyTable,fullfile(outDir,'04B_line_signal_properties.csv'));

%% ------------------------------------------------------------------------
%  4. FAN-IN / FAN-OUT COUNTS
%  ------------------------------------------------------------------------
fprintf('[3/12] Computing fan-in / fan-out...\n');

fanInMap = containers.Map('KeyType','char','ValueType','double');
fanOutMap = containers.Map('KeyType','char','ValueType','double');

for i = 1:height(edgeTable)
    s = char(edgeTable.SrcBlock(i));
    d = char(edgeTable.DstBlock(i));
    if ~isempty(s)
        fanOutMap = localMapIncrement(fanOutMap,s);
    end
    if ~isempty(d)
        fanInMap = localMapIncrement(fanInMap,d);
    end
end

blockTable.FanIn = zeros(height(blockTable),1);
blockTable.FanOut = zeros(height(blockTable),1);
for i = 1:height(blockTable)
    p = char(blockTable.Path(i));
    if isKey(fanInMap,p), blockTable.FanIn(i) = fanInMap(p); end
    if isKey(fanOutMap,p), blockTable.FanOut(i) = fanOutMap(p); end
end
writetable(blockTable,fullfile(outDir,'02_blocks_all.csv')); % overwrite with fan counts

%% ------------------------------------------------------------------------
%  5. PORT CONNECTIVITY (SECOND INDEPENDENT CONNECTIVITY VIEW)
%  ------------------------------------------------------------------------
fprintf('[4/12] Reading PortConnectivity for every block...\n');

pcRows = cell(0,8);
unconnRows = cell(0,5);

for i = 1:nBlocks
    b = blockPaths{i};
    try
        pc = get_param(b,'PortConnectivity');
        if isempty(pc), continue; end
        for k = 1:numel(pc)
            ptype = localStructFieldText(pc(k),'Type',MAX_LIST_CHARS);
            srcBlocks = localConnectivityBlocks(pc(k),'SrcBlock',MAX_LIST_CHARS);
            srcPorts  = localConnectivityPorts(pc(k),'SrcPort',MAX_LIST_CHARS);
            dstBlocks = localConnectivityBlocks(pc(k),'DstBlock',MAX_LIST_CHARS);
            dstPorts  = localConnectivityPorts(pc(k),'DstPort',MAX_LIST_CHARS);

            pcRows(end+1,:) = { ...
                b,char(blockTable.BlockType(i)),k,char(ptype), ...
                char(srcBlocks),char(srcPorts),char(dstBlocks),char(dstPorts)}; %#ok<SAGROW>

            if strlength(srcBlocks)==0 && strlength(dstBlocks)==0
                unconnRows(end+1,:) = { ...
                    b,char(blockTable.BlockType(i)),k,char(ptype), ...
                    'UNCONNECTED_PORT_CANDIDATE_ONLY'}; %#ok<SAGROW>
            end
        end
    catch ME
        auditErrorRows(end+1,:) = {'PORTCONNECTIVITY',b,localOneLine(ME.message)}; %#ok<SAGROW>
    end

    if mod(i,750)==0 || i==nBlocks
        fprintf('  PortConnectivity: %d / %d\n',i,nBlocks);
    end
end

pcTable = localCellTable(pcRows, ...
    {'BlockPath','BlockType','PortRecordIndex','PortType','SrcBlocks','SrcPorts','DstBlocks','DstPorts'}, ...
    [3]);
writetable(pcTable,fullfile(outDir,'05_port_connectivity.csv'));

unconnTable = localCellTable(unconnRows, ...
    {'BlockPath','BlockType','PortRecordIndex','PortType','Note'},[3]);
writetable(unconnTable,fullfile(outDir,'06_unconnected_ports_candidates.csv'));

%% ------------------------------------------------------------------------
%  6. GOTO/FROM AND DATA STORE VIRTUAL DEPENDENCIES
%  ------------------------------------------------------------------------
fprintf('[5/12] Auditing Goto/From and Data Store dependencies...\n');

gfRows = cell(0,5);
gfMask = ismember(blockTable.BlockType,["Goto","From","GotoTagVisibility"]);
gfPaths = blockTable.Path(gfMask);

for i = 1:numel(gfPaths)
    b = char(gfPaths(i));
    kind = char(localSafeGetParam(b,'BlockType',MAX_LIST_CHARS));
    tag = char(localSafeGetParam(b,'GotoTag',MAX_LIST_CHARS));
    vis = char(localSafeGetParam(b,'TagVisibility',MAX_LIST_CHARS));
    if isempty(vis)
        vis = char(localSafeGetParam(b,'GotoTagVisibility',MAX_LIST_CHARS));
    end
    gfRows(end+1,:) = {b,kind,tag,vis,char(localSafeGetParam(b,'Parent',MAX_LIST_CHARS))}; %#ok<SAGROW>
end
gfTable = localCellTable(gfRows,{'Path','Kind','Tag','Visibility','Parent'},[]);
writetable(gfTable,fullfile(outDir,'07_goto_from_blocks.csv'));

[tagGroupTable,virtualEdgeTable] = localBuildGotoGroups(gfTable,MAX_LIST_CHARS);
writetable(tagGroupTable,fullfile(outDir,'08_goto_from_tag_groups.csv'));
writetable(virtualEdgeTable,fullfile(outDir,'09_virtual_edges_goto_from_candidates.csv'));

dsRows = cell(0,4);
dsMask = ismember(blockTable.BlockType,["DataStoreMemory","DataStoreRead","DataStoreWrite"]);
dsPaths = blockTable.Path(dsMask);
for i = 1:numel(dsPaths)
    b = char(dsPaths(i));
    dsRows(end+1,:) = { ...
        b,char(localSafeGetParam(b,'BlockType',MAX_LIST_CHARS)), ...
        char(localSafeGetParam(b,'DataStoreName',MAX_LIST_CHARS)), ...
        char(localSafeGetParam(b,'Parent',MAX_LIST_CHARS))}; %#ok<SAGROW>
end
dsTable = localCellTable(dsRows,{'Path','Kind','DataStoreName','Parent'},[]);
writetable(dsTable,fullfile(outDir,'10_data_store_blocks.csv'));
dsGroupTable = localBuildDataStoreGroups(dsTable,MAX_LIST_CHARS);
writetable(dsGroupTable,fullfile(outDir,'11_data_store_groups.csv'));

%% ------------------------------------------------------------------------
%  7. MATLAB FUNCTION / STATEFLOW EMCHART SOURCE CODE
%  ------------------------------------------------------------------------
fprintf('[6/12] Extracting MATLAB Function (Stateflow.EMChart) source...\n');

funcRows = cell(0,18);
try
    rt = sfroot;
    charts = rt.find('-isa','Stateflow.EMChart');
    fidx = 0;
    for i = 1:numel(charts)
        c = charts(i);

        cPath = string(localObjectProp(c,'Path'));
        cName = string(localObjectProp(c,'Name'));
        chartPath = cPath;
        if strlength(cName)>0
            if strlength(cPath)>0
                chartPath = cPath + "/" + cName;
            else
                chartPath = cName;
            end
        end

        if ~(cPath==string(mdl) || startsWith(cPath,string(mdl)+"/") || ...
             chartPath==string(mdl) || startsWith(chartPath,string(mdl)+"/"))
            continue;
        end

        % IMPORTANT: read raw Script text directly. Do NOT pass it through
        % localToText(), otherwise real newline characters become literal "\n"
        % and every function incorrectly appears to have one line.
        scriptText = "";
        try
            scriptText = string(c.Script);
        catch
            scriptText = "";
        end

        fidx = fidx + 1;
        exactHash = localTextSha256(char(scriptText));
        [lineCount,nonEmptyCount,persistentCount,ifCount,switchCount,forCount,whileCount] = ...
            localCodeMetrics(char(scriptText));
        firstLine = localFirstNonEmptyLine(char(scriptText));
        matched = localMatchedTokens(chartPath + " " + scriptText,TOKENS);
        [fcnName,outArgs,inArgs] = localParseFunctionSignature(char(scriptText));

        codeFile = sprintf('%04d_%s_%s.m.txt', ...
            fidx,localSafeFileName(char(cName)),localHashPrefix(exactHash,10));
        codePath = fullfile(funcDir,codeFile);
        localWriteText(codePath,char(scriptText));

        funcRows(end+1,:) = { ...
            char(cPath),char(chartPath),char(cName),exactHash, ...
            lineCount,nonEmptyCount,persistentCount,ifCount,switchCount,forCount,whileCount, ...
            char(fcnName),char(outArgs),char(inArgs),char(firstLine),char(matched), ...
            codeFile,char(localSafeGetParam(char(cPath),'SFBlockType',MAX_LIST_CHARS))}; %#ok<SAGROW>
    end
catch ME
    auditErrorRows(end+1,:) = {'STATEFLOW','sfroot/EMChart',localOneLine(ME.message)}; %#ok<SAGROW>
end

functionTable = localCellTable(funcRows, ...
    {'BlockPath','ChartPath','Name','ExactSHA256','LineCount','NonEmptyLineCount', ...
     'PersistentCount','IfCount','SwitchCount','ForCount','WhileCount','FunctionName', ...
     'OutputArgs','InputArgs','FirstLine','MatchedTokens','CodeFile','SFBlockType'}, ...
    [5 6 7 8 9 10 11]);
writetable(functionTable,fullfile(outDir,'12_matlab_function_manifest.csv'));

if height(functionTable) < MIN_EXPECTED_FUNCTIONS
    error('AUDIT:FunctionEnumerationIncomplete', ...
        'Only %d MATLAB Function charts were extracted; expected at least %d.', ...
        height(functionTable),MIN_EXPECTED_FUNCTIONS);
end

dupFunctionTable = localDuplicateFunctionGroups(functionTable,MAX_LIST_CHARS);
writetable(dupFunctionTable,fullfile(outDir,'13_duplicate_matlab_function_groups.csv'));

functionIOMapTable = localBuildFunctionIOMap(functionTable,edgeTable,MAX_LIST_CHARS);
writetable(functionIOMapTable,fullfile(outDir,'13B_matlab_function_IO_connections.csv'));

stateflowSummary = localBuildStateflowSummary(mdl,MAX_LIST_CHARS);
writetable(stateflowSummary.Charts,fullfile(outDir,'13C_stateflow_charts.csv'));
writetable(stateflowSummary.States,fullfile(outDir,'13D_stateflow_states.csv'));
writetable(stateflowSummary.Transitions,fullfile(outDir,'13E_stateflow_transitions.csv'));

%% ------------------------------------------------------------------------
%  8. SUBSYSTEM HIERARCHY + INTERFACES
%  ------------------------------------------------------------------------
fprintf('[7/12] Building subsystem hierarchy and interfaces...\n');

subPaths = [string(mdl); blockTable.Path(blockTable.BlockType=="SubSystem")];
subPaths = unique(subPaths,'stable');

subRows = cell(0,12);
for i = 1:numel(subPaths)
    s = subPaths(i);
    if s==string(mdl)
        par = "";
        dep = 0;
    else
        par = localSafeGetParam(char(s),'Parent',MAX_LIST_CHARS);
        dep = localPathDepth(char(s),mdl);
    end

    directChild = sum(blockTable.Parent==s);
    descMask = blockTable.Path~=s & ...
        (startsWith(blockTable.Path,s+"/"));
    descCount = sum(descMask);
    directLines = sum(edgeTable.ParentSystem==s);
    descLines = sum(edgeTable.ParentSystem==s | startsWith(edgeTable.ParentSystem,s+"/"));
    inCount = sum(blockTable.Parent==s & blockTable.BlockType=="Inport");
    outCount = sum(blockTable.Parent==s & blockTable.BlockType=="Outport");
    aaCount = sum(descMask & contains(upper(blockTable.Path),'AA15_'));
    specialCount = sum(descMask & strlength(blockTable.MatchedTokens)>0);

    subRows(end+1,:) = { ...
        char(s),char(par),dep,directChild,descCount,directLines,descLines, ...
        inCount,outCount,aaCount,specialCount,char(localMatchedTokens(s,TOKENS))}; %#ok<SAGROW>
end

subsystemTable = localCellTable(subRows, ...
    {'Path','Parent','Depth','DirectChildBlocks','DescendantBlocks','DirectEdges', ...
     'DescendantEdges','DirectInports','DirectOutports','AA15Descendants', ...
     'SpecialInterestDescendants','MatchedTokens'}, ...
    [3 4 5 6 7 8 9 10 11]);
writetable(subsystemTable,fullfile(outDir,'14_subsystem_hierarchy.csv'));

interfaceTable = localBuildSubsystemInterfaces(blockTable,edgeTable,MAX_LIST_CHARS);
writetable(interfaceTable,fullfile(outDir,'15_subsystem_interfaces.csv'));

%% ------------------------------------------------------------------------
%  9. ANNOTATIONS, LIBRARY LINKS, MODEL VARIABLES
%  ------------------------------------------------------------------------
fprintf('[8/12] Reading annotations, library links, and variables...\n');

annRows = cell(0,5);
try
    anns = find_system(mdl,'FindAll','on','Type','annotation');
    anns = anns(:);
    for i = 1:numel(anns)
        ah = anns(i);
        annRows(end+1,:) = { ...
            num2str(double(ah)), ...
            char(localSafeGetHandleParam(ah,'Parent',MAX_LIST_CHARS)), ...
            char(localFirstNonEmpty({ ...
                localSafeGetHandleParam(ah,'PlainText',MAX_LIST_CHARS), ...
                localSafeGetHandleParam(ah,'Text',MAX_LIST_CHARS), ...
                localSafeGetHandleParam(ah,'Name',MAX_LIST_CHARS)})), ...
            char(localSafeGetHandleParam(ah,'Position',MAX_LIST_CHARS)), ...
            'ANNOTATION'}; %#ok<SAGROW>
    end
catch ME
    auditErrorRows(end+1,:) = {'ANNOTATION',mdl,localOneLine(ME.message)}; %#ok<SAGROW>
end
annotationTable = localCellTable(annRows,{'Handle','Parent','Text','Position','Kind'},[]);
writetable(annotationTable,fullfile(outDir,'16_annotations.csv'));

libraryLinkTable = blockTable(strlength(blockTable.ReferenceBlock)>0 | ...
    (~strcmpi(blockTable.LinkStatus,'none') & strlength(blockTable.LinkStatus)>0),:);
writetable(libraryLinkTable,fullfile(outDir,'17_library_link_blocks.csv'));

maskInventoryTable = localBuildMaskInventory(blockTable,MAX_PARAM_CHARS);
writetable(maskInventoryTable,fullfile(outDir,'17B_mask_initialization_and_callbacks.csv'));

varRows = cell(0,4);
try
    vars = Simulink.findVars(mdl);
    for i = 1:numel(vars)
        varRows(end+1,:) = { ...
            localObjectProp(vars(i),'Name'), ...
            localObjectProp(vars(i),'SourceType'), ...
            localObjectProp(vars(i),'Source'), ...
            localToText(localObjectPropRaw(vars(i),'Users'),MAX_LIST_CHARS)}; %#ok<SAGROW>
    end
catch ME
    auditErrorRows(end+1,:) = {'VARIABLES','Simulink.findVars',localOneLine(ME.message)}; %#ok<SAGROW>
end
variableUsageTable = localCellTable(varRows,{'Name','SourceType','Source','Users'},[]);
writetable(variableUsageTable,fullfile(outDir,'18_model_variable_usage.csv'));

mwsRows = cell(0,5);
try
    mws = get_param(mdl,'ModelWorkspace');
    w = whos(mws);
    for i = 1:numel(w)
        preview = '';
        try
            val = getVariable(mws,w(i).name);
            preview = char(localValuePreview(val,500));
        catch
        end
        mwsRows(end+1,:) = { ...
            w(i).name,w(i).class,mat2str(w(i).size),w(i).bytes,preview}; %#ok<SAGROW>
    end
catch ME
    auditErrorRows(end+1,:) = {'MODELWORKSPACE',mdl,localOneLine(ME.message)}; %#ok<SAGROW>
end
modelWorkspaceTable = localCellTable(mwsRows, ...
    {'Name','Class','Size','Bytes','ValuePreview'},[4]);
writetable(modelWorkspaceTable,fullfile(outDir,'19_model_workspace.csv'));

%% ------------------------------------------------------------------------
%  10. SPECIAL-INTEREST / RT-LAB / CLEANUP-CANDIDATE INVENTORIES
%  ------------------------------------------------------------------------
fprintf('[9/12] Building island/AA15/RT-LAB/special-interest inventories...\n');

specialMask = strlength(blockTable.MatchedTokens)>0;
specialTable = blockTable(specialMask,:);
writetable(specialTable,fullfile(outDir,'20_special_interest_blocks.csv'));

specialPaths = specialTable.Path;
neighborMask = ismember(edgeTable.SrcBlock,specialPaths) | ismember(edgeTable.DstBlock,specialPaths);
specialNeighborTable = edgeTable(neighborMask,:);
writetable(specialNeighborTable,fullfile(outDir,'21_special_interest_direct_neighbors.csv'));

rtlabMask = contains(upper(blockTable.Path),'OPCOMM') | ...
            contains(upper(blockTable.Path),'OPINPUT') | ...
            contains(upper(blockTable.Path),'OPOUTPUT') | ...
            contains(upper(blockTable.Path),'OPWRITE') | ...
            contains(upper(blockTable.MaskType),'OPCOMM') | ...
            contains(upper(blockTable.MaskType),'OPINPUT') | ...
            contains(upper(blockTable.MaskType),'OPOUTPUT') | ...
            contains(upper(blockTable.MaskType),'OPWRITE') | ...
            contains(upper(blockTable.ReferenceBlock),'OPCOMM') | ...
            contains(upper(blockTable.ReferenceBlock),'OPINPUT') | ...
            contains(upper(blockTable.ReferenceBlock),'OPOUTPUT') | ...
            contains(upper(blockTable.ReferenceBlock),'OPWRITE') | ...
            contains(upper(blockTable.ReferenceBlock),'OPAL') | ...
            contains(upper(blockTable.ReferenceBlock),'ARTEMIS');
rtlabTable = blockTable(rtlabMask,:);
writetable(rtlabTable,fullfile(outDir,'22_rtlab_blocks.csv'));

tokenRows = cell(numel(TOKENS),2);
for i = 1:numel(TOKENS)
    tokenRows{i,1} = TOKENS{i};
    tokenRows{i,2} = sum(contains(upper(blockTable.Path),upper(TOKENS{i})));
end
tokenCountTable = localCellTable(tokenRows,{'Token','BlockPathMatchCount'},[2]);
writetable(tokenCountTable,fullfile(outDir,'23_token_counts.csv'));

cleanupCandidateTable = localBuildCleanupCandidates( ...
    blockTable,unconnTable,tagGroupTable,dsGroupTable,dupFunctionTable);
writetable(cleanupCandidateTable,fullfile(outDir,'24_cleanup_candidates_DO_NOT_DELETE.csv'));

%% ------------------------------------------------------------------------
%  11. COMPLEXITY HOTSPOTS
%  ------------------------------------------------------------------------
fprintf('[10/12] Building complexity hotspot tables...\n');

hotspotRows = cell(0,7);

if ~isempty(subsystemTable)
    tmp = sortrows(subsystemTable,'DescendantBlocks','descend');
    n = min(50,height(tmp));
    for i = 1:n
        hotspotRows(end+1,:) = { ...
            'SUBSYSTEM_DESCENDANTS',char(tmp.Path(i)),tmp.DescendantBlocks(i), ...
            tmp.DirectChildBlocks(i),tmp.DescendantEdges(i), ...
            tmp.SpecialInterestDescendants(i),'Structural size'}; %#ok<SAGROW>
    end
end

if ~isempty(functionTable)
    tmp = sortrows(functionTable,'LineCount','descend');
    n = min(50,height(tmp));
    for i = 1:n
        hotspotRows(end+1,:) = { ...
            'MATLAB_FUNCTION_LINES',char(tmp.BlockPath(i)),tmp.LineCount(i), ...
            tmp.PersistentCount(i),tmp.IfCount(i)+tmp.SwitchCount(i), ...
            tmp.ForCount(i)+tmp.WhileCount(i),'Code size/state/control-flow proxy'}; %#ok<SAGROW>
    end
end

tmp = sortrows(blockTable,'FanOut','descend');
n = min(50,height(tmp));
for i = 1:n
    hotspotRows(end+1,:) = { ...
        'FANOUT',char(tmp.Path(i)),tmp.FanOut(i),tmp.FanIn(i),0,0,'Direct line fan-out'}; %#ok<SAGROW>
end

complexityTable = localCellTable(hotspotRows, ...
    {'Metric','Path','PrimaryValue','SecondaryValue','TertiaryValue','FourthValue','Note'}, ...
    [3 4 5 6]);
writetable(complexityTable,fullfile(outDir,'25_complexity_hotspots.csv'
%% ------------------------------------------------------------------------
%  11B. SECOND-GENERATION EXPLANATION / CLEANUP INDEXES
%  ------------------------------------------------------------------------
fprintf('[10B] Building explanation-grade indexes...\n');

blockTypeCountTable = localCountStrings(blockTable.BlockType,'BlockType');
writetable(blockTypeCountTable,fullfile(outDir,'25B_block_type_counts.csv'));

parentBlockCountTable = localCountStrings(blockTable.Parent,'ParentSystem');
writetable(parentBlockCountTable,fullfile(outDir,'25C_parent_system_block_counts.csv'));

specialParamTable = paramTable(ismember(paramTable.Path,specialTable.Path),:);
writetable(specialParamTable,fullfile(outDir,'25D_special_interest_parameters.csv'));

gotoFlowTable = localBuildGotoFlow(gfTable,edgeTable,MAX_LIST_CHARS);
writetable(gotoFlowTable,fullfile(outDir,'25E_goto_from_flow_index.csv'));

dependencyGraphTable = localBuildDependencyGraph( ...
    edgeTable,interfaceTable,virtualEdgeTable,dsTable);
writetable(dependencyGraphTable,fullfile(outDir,'25F_unified_dependency_graph_edges.csv'));

switchRouterTable = localBuildSwitchRouterInventory(blockTable,edgeTable,paramTable,MAX_LIST_CHARS);
writetable(switchRouterTable,fullfile(outDir,'25G_switch_router_control_map.csv'));

bundleTable = localBuildBundleInventory(blockTable,edgeTable,paramTable,MAX_LIST_CHARS);
writetable(bundleTable,fullfile(outDir,'25H_mux_bus_bundle_map.csv'));

statefulTable = localBuildStatefulInventory(blockTable,edgeTable,paramTable,MAX_LIST_CHARS);
writetable(statefulTable,fullfile(outDir,'25I_stateful_delay_integrator_rate_transition_map.csv'));

keyModuleTable = localBuildKeyModuleContracts(blockTable,edgeTable,paramTable,MAX_LIST_CHARS);
writetable(keyModuleTable,fullfile(outDir,'25J_key_module_contracts.csv'));

stageConfigTable = localBuildStageConfigConsumerIndex( ...
    blockTable,edgeTable,paramTable,gfTable,gotoFlowTable,MAX_LIST_CHARS);
writetable(stageConfigTable,fullfile(outDir,'25K_stage_config_Fxx_consumer_index.csv'));

physicalBlockTable = blockTable((blockTable.NumLConn + blockTable.NumRConn)>0,:);
writetable(physicalBlockTable,fullfile(outDir,'25L_physical_connection_blocks.csv'));

physicalConnectivityTable = localBuildPhysicalConnectivity(pcTable,physicalBlockTable);
writetable(physicalConnectivityTable,fullfile(outDir,'25M_physical_connectivity.csv'));

rtlabContractTable = localBuildTransportContract(rtlabTable,edgeTable,paramTable,MAX_LIST_CHARS);
writetable(rtlabContractTable,fullfile(outDir,'25N_rtlab_transport_contract.csv'));

[loggerInputTable,loggerTraceTable] = localBuildLoggerMaps( ...
    rtlabTable,edgeTable,blockTable,MAX_LIST_CHARS);
writetable(loggerInputTable,fullfile(outDir,'25O_opwrite_direct_input_map.csv'));
writetable(loggerTraceTable,fullfile(outDir,'25P_opwrite_bundle_provenance_trace.csv'));

taskSummaryTable = localBuildTaskSummary(mdl,blockTable,edgeTable,functionTable,specialTable);
writetable(taskSummaryTable,fullfile(outDir,'25Q_rt_task_summary.csv'));

deviceSummaryTable = localBuildDeviceSummary(mdl,blockTable,edgeTable,functionTable, ...
    specialTable,switchRouterTable,statefulTable);
writetable(deviceSummaryTable,fullfile(outDir,'25R_six_device_controller_summary.csv'));

archiveCrosscheckTable = localArchiveCrosscheck(char(modelFile),outDir);
writetable(archiveCrosscheckTable,fullfile(outDir,'25S_slx_archive_crosscheck.csv'));

% Fail closed if the high-value indexes are implausibly empty.  This specifically
% prevents a repeat of V1.0, which produced Blocks=0 while still exporting some
% Stateflow charts and line handles.
if height(specialTable) < MIN_EXPECTED_SPECIAL_BLOCKS
    error('AUDIT:SpecialInterestEnumerationIncomplete', ...
        'Only %d special-interest blocks found; expected at least %d.', ...
        height(specialTable),MIN_EXPECTED_SPECIAL_BLOCKS);
end
if height(rtlabTable) < MIN_EXPECTED_RTLAB_BLOCKS
    error('AUDIT:RTLABEnumerationIncomplete', ...
        'Only %d RT-LAB/OPAL-related blocks found; expected at least %d.', ...
        height(rtlabTable),MIN_EXPECTED_RTLAB_BLOCKS);
end

));

%% ------------------------------------------------------------------------
%  12. OPTIONAL COMPILED-PROPERTY AUDIT
%  ------------------------------------------------------------------------
fprintf('[11/12] Compiled-property phase...\n');

compiledStatus = 'NOT_RUN_BY_DEFAULT';
compiledPortTable = table();

if RUN_COMPILED_PHASE
    [compiledPortTable,compiledStatus] = localRunCompiledAudit(mdl,blockTable,MAX_LIST_CHARS);
    writetable(compiledPortTable,fullfile(outDir,'26_compiled_port_properties.csv'));
else
    localWriteText(fullfile(outDir,'26_compiled_phase_status.txt'), ...
        ['NOT RUN. RUN_COMPILED_PHASE=false by design.' newline ...
         'Reason: compile/update can invoke callbacks and RT-LAB/ARTEMiS-specific behavior.' newline ...
         'Static audit remains read-only and does not compile the model.' newline]);
end

%% ------------------------------------------------------------------------
%  13. ERROR LOG, MAT SNAPSHOT, SUMMARY, ZIP
%  ------------------------------------------------------------------------
fprintf('[12/12] Writing summary package...\n');

auditErrorTable = localCellTable(auditErrorRows,{'Stage','Object','Message'},[]);
writetable(auditErrorTable,fullfile(outDir,'27_audit_errors.csv'));

postModelHash = string(localFileSha256(char(modelFile)));
postDirty = string(get_param(mdl,'Dirty'));
if ~strcmpi(postModelHash,modelHash)
    error('AUDIT:FileMutationDetected', ...
        'Model file SHA256 changed during audit. Before=%s After=%s', ...
        char(modelHash),char(postModelHash));
end
if ~strcmpi(postDirty,'off')
    error('AUDIT:DirtyMutationDetected', ...
        'Model Dirty changed to ON during audit. Audit aborted.');
end

auditInfo = struct();
auditInfo.Version = AUDIT_VERSION;
auditInfo.Time = datestr(now,31);
auditInfo.Model = mdl;
auditInfo.ModelFile = char(modelFile);
auditInfo.LoadedModelFile = char(loadedModelFile);
auditInfo.ScriptFile = target.ScriptFile;
auditInfo.ModelSHA256 = char(modelHash);
auditInfo.PostModelSHA256 = char(postModelHash);
auditInfo.ExpectedBaselineSHA256 = EXPECTED_BASELINE_SHA256;
auditInfo.SimulationStatus = char(simStatus);
auditInfo.Dirty = char(dirty);
auditInfo.PostDirty = char(postDirty);
auditInfo.RunCompiledPhase = RUN_COMPILED_PHASE;
auditInfo.CompiledStatus = compiledStatus;
auditInfo.FollowLinks = 'off';
auditInfo.LookUnderMasks = 'all';
auditInfo.Note = ['Static audit only claims saved/in-memory model structure and connectivity. ' ...
    'No deletion recommendation is authorized by candidate tables alone.'];

save(fullfile(outDir,'28_AUDIT_DATA.mat'), ...
    'auditInfo','metaTable','pathShadowTable','blockTable','paramTable','edgeTable','linePropertyTable','pcTable', ...
    'unconnTable','gfTable','tagGroupTable','virtualEdgeTable','dsTable','dsGroupTable', ...
    'functionTable','dupFunctionTable','subsystemTable','interfaceTable', ...
    'annotationTable','libraryLinkTable','maskInventoryTable','variableUsageTable','modelWorkspaceTable', ...
    'specialTable','specialNeighborTable','rtlabTable','tokenCountTable', ...
    'cleanupCandidateTable','complexityTable','auditErrorTable','compiledPortTable', ...
    'functionIOMapTable','stateflowSummary','blockTypeCountTable','parentBlockCountTable', ...
    'specialParamTable','gotoFlowTable','dependencyGraphTable','switchRouterTable', ...
    'bundleTable','statefulTable','keyModuleTable','stageConfigTable', ...
    'physicalBlockTable','physicalConnectivityTable','rtlabContractTable', ...
    'loggerInputTable','loggerTraceTable','taskSummaryTable','deviceSummaryTable', ...
    'archiveCrosscheckTable','-v7.3');

summaryPath = fullfile(outDir,'29_AUDIT_SUMMARY.md');
localWriteSummary(summaryPath,auditInfo,blockTable,edgeTable,pcTable, ...
    functionTable,dupFunctionTable,subsystemTable,specialTable,rtlabTable, ...
    unconnTable,cleanupCandidateTable,complexityTable,auditErrorTable,tokenCountTable);

nextPath = fullfile(outDir,'30_NEXT_STEP_README.txt');
nextText = sprintf([ ...
    '1. Keep the model unchanged after this audit if possible.\n' ...
    '2. Upload the generated ZIP to the analysis window.\n' ...
    '3. The ZIP contains exact block names, hierarchy, point-to-point edges, subsystem interfaces,\n' ...
    '   Goto/From flow, unified dependency graph, raw MATLAB Function source + I/O map,\n' ...
    '   switches/routers, stateful blocks, stage/config consumers, physical connectivity,\n' ...
    '   RT-LAB transport contracts, OpWrite provenance, task/device summaries, complexity hotspots,\n' ...
    '   SLX archive cross-check, and cleanup candidates.\n' ...
    '4. Cleanup candidates are NOT deletion instructions. Deletion requires downstream consumer review.\n' ...
    '5. Compiled properties were %s.\n' ...
    '6. Model SHA256 remained unchanged during the audit.\n'],compiledStatus);
localWriteText(nextPath,nextText);

zipPath = [outDir '.zip'];
try
    zip(zipPath,outDir);
    fprintf('\nAUDIT COMPLETE\n');
    fprintf('Folder: %s\n',outDir);
    fprintf('ZIP   : %s\n',zipPath);
catch ME
    fprintf('\nAUDIT COMPLETE, but ZIP creation failed:\n%s\n',ME.message);
    fprintf('Folder: %s\n',outDir);
end

fprintf('\nIMPORTANT: This script did not save or edit the model.\n');
fprintf('Upload the generated ZIP for the next analysis step.\n\n');

end

%% ========================================================================
%  LOCAL FUNCTIONS
%  ========================================================================

function target = localResolveTargetModelFromScript()
    % Fail-closed identity resolution.
    % The audit script must sit in the same model folder as the target .slx.
    % If the folder is named exactly like the model, use <folder>/<folder>.slx.
    % Otherwise require exactly one .slx in the script folder.
    scriptFile = mfilename('fullpath');
    scriptDir = fileparts(scriptFile);
    [~,folderName] = fileparts(scriptDir);

    preferred = fullfile(scriptDir,[folderName '.slx']);
    if exist(preferred,'file')
        targetFile = preferred;
    else
        dd = dir(fullfile(scriptDir,'*.slx'));
        if numel(dd)~=1
            names = strjoin({dd.name},', ');
            error('AUDIT:TargetFileAmbiguous', ...
                ['Audit script folder must contain <foldername>.slx or exactly one .slx file. ' ...
                 'ScriptFolder=%s; Found=%d; Files=%s'], ...
                 scriptDir,numel(dd),names);
        end
        targetFile = fullfile(dd(1).folder,dd(1).name);
    end

    targetFile = localCanonicalPath(targetFile);
    [~,modelName] = fileparts(targetFile);

    if bdIsLoaded(modelName)
        loadedFile = get_param(modelName,'FileName');
        if isempty(loadedFile)
            error('AUDIT:LoadedModelUnsaved', ...
                'Loaded model "%s" has no FileName.',modelName);
        end
        loadedFile = localCanonicalPath(loadedFile);
        if ~strcmpi(loadedFile,targetFile)
            error('AUDIT:ShadowedWrongModel', ...
                ['A same-name model is already loaded from a DIFFERENT folder. ' ...
                 'This is exactly the dangerous V5/V6 shadowing case and the audit is aborted.\n' ...
                 'Script target : %s\nLoaded model : %s\n' ...
                 'Close the wrong same-name model / correct the MATLAB path, open the target model ' ...
                 'from the audit project, then rerun.'],targetFile,loadedFile);
        end
    else
        load_system(targetFile);
        loadedFile = localCanonicalPath(get_param(modelName,'FileName'));
        if ~strcmpi(loadedFile,targetFile)
            error('AUDIT:LoadedPathMismatch', ...
                'load_system resolved an unexpected file. Target=%s; Loaded=%s', ...
                targetFile,loadedFile);
        end
    end

    target = struct();
    target.ModelName = modelName;
    target.TargetFile = targetFile;
    target.LoadedFile = loadedFile;
    target.ScriptFile = localCanonicalPath(scriptFile);
    target.ScriptDir = localCanonicalPath(scriptDir);
end

function p = localCanonicalPath(p)
    try
        p = char(java.io.File(p).getCanonicalPath());
    catch
        p = char(string(p));
    end
end

function h = localFileSha256(filePath)
    h = '';
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        fid = fopen(filePath,'rb');
        if fid<0, return; end
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        while true
            data = fread(fid,1024*1024,'*uint8');
            if isempty(data), break; end
            md.update(typecast(data,'int8'));
        end
        dig = typecast(md.digest(),'uint8');
        h = lower(reshape(dec2hex(dig,2).',1,[]));
    catch
        h = '';
    end
end

function h = localTextSha256(txt)
    h = '';
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        bytes = unicode2native(txt,'UTF-8');
        md.update(typecast(uint8(bytes),'int8'));
        dig = typecast(md.digest(),'uint8');
        h = lower(reshape(dec2hex(dig,2).',1,[]));
    catch
        h = '';
    end
end

function s = localHashPrefix(h,n)
    if isempty(h)
        s = 'nohash';
    else
        s = h(1:min(n,numel(h)));
    end
end

function s = localSafeFileName(s)
    s = regexprep(char(s),'[^A-Za-z0-9_\-]+','_');
    if isempty(s), s = 'unnamed'; end
    if numel(s)>120, s = s(1:120); end
end

function d = localPathDepth(path,mdl)
    path = char(path);
    mdl = char(mdl);
    if strcmp(path,mdl)
        d = 0;
        return;
    end
    if startsWith(path,[mdl '/'])
        rel = path(numel(mdl)+2:end);
        d = 1 + sum(rel=='/');
    else
        d = sum(path=='/');
    end
end

function s = localSafeSID(b)
    s = "";
    try
        s = string(Simulink.ID.getSID(b));
    catch
    end
end

function s = localSafeGetParam(obj,prop,maxChars)
    if nargin<3, maxChars = 4000; end
    s = "";
    if isempty(obj), return; end
    try
        v = get_param(obj,prop);
        s = localToText(v,maxChars);
    catch
        s = "";
    end
end

function s = localSafeGetHandleParam(h,prop,maxChars)
    if nargin<3, maxChars = 4000; end
    s = "";
    try
        v = get_param(h,prop);
        s = localToText(v,maxChars);
    catch
    end
end

function s = localToText(v,maxChars)
    if nargin<2, maxChars = 4000; end
    try
        if isstring(v)
            if isempty(v)
                s = "";
            else
                s = strjoin(v(:).'," | ");
            end
        elseif ischar(v)
            s = string(v);
        elseif isnumeric(v) || islogical(v)
            if isempty(v)
                s = "";
            elseif numel(v)<=300
                s = string(mat2str(v));
            else
                s = "NUMERIC " + string(mat2str(size(v))) + " " + string(class(v));
            end
        elseif iscell(v) || isstruct(v)
            try
                s = string(jsonencode(v));
            catch
                s = string(class(v)) + " " + string(mat2str(size(v)));
            end
        elseif isa(v,'function_handle')
            s = string(func2str(v));
        else
            try
                s = string(char(v));
            catch
                s = string(class(v)) + " " + string(mat2str(size(v)));
            end
        end
    catch
        s = "";
    end

    if numel(s)>1
        s = strjoin(s(:).'," | ");
    end
    s = replace(s,char(13),"");
    s = replace(s,newline,"\n");
    s = replace(s,char(9),"\t");
    if strlength(s)>maxChars
        s = extractBefore(s,maxChars+1) + "...<truncated>";
    end
end

function [nin,nout,nen,ntrg,nstate,nlc,nrc] = localPortCounts(b)
    nin=0; nout=0; nen=0; ntrg=0; nstate=0; nlc=0; nrc=0;
    try
        ph = get_param(b,'PortHandles');
        nin = localCountPositiveField(ph,'Inport');
        nout = localCountPositiveField(ph,'Outport');
        nen = localCountPositiveField(ph,'Enable');
        ntrg = localCountPositiveField(ph,'Trigger');
        nstate = localCountPositiveField(ph,'State');
        nlc = localCountPositiveField(ph,'LConn');
        nrc = localCountPositiveField(ph,'RConn');
    catch
    end
end

function n = localCountPositiveField(s,f)
    n = 0;
    if isstruct(s) && isfield(s,f)
        v = s.(f);
        if isnumeric(v)
            n = sum(v>0);
        elseif ~isempty(v)
            n = numel(v);
        end
    end
end

function tokens = localMatchedTokens(text,tokensList)
    u = upper(string(text));
    hit = strings(0,1);
    for k = 1:numel(tokensList)
        t = upper(string(tokensList{k}));
        if contains(u,t)
            hit(end+1,1) = string(tokensList{k}); %#ok<AGROW>
        end
    end
    if isempty(hit)
        tokens = "";
    else
        tokens = strjoin(unique(hit,'stable'),"|");
    end
end

function r = localEmptyEdgeRow()
    r = struct( ...
        'ParentSystem',"", ...
        'LineHandle',NaN, ...
        'LineName',"", ...
        'SrcBlock',"", ...
        'SrcBlockType',"", ...
        'SrcPort',NaN, ...
        'SrcPortType',"", ...
        'DstBlock',"", ...
        'DstBlockType',"", ...
        'DstPort',NaN, ...
        'DstPortType',"");
end

function p = localBlockHandleToPath(h)
    p = "";
    try
        if isnumeric(h) && isscalar(h) && h>0
            p = string(getfullname(h));
        end
    catch
    end
end

function x = localNthNumeric(v,k)
    x = -1;
    try
        if isnumeric(v) && numel(v)>=k
            x = v(k);
        end
    catch
    end
end

function n = localPortNumber(ph)
    n = NaN;
    try
        if isnumeric(ph) && isscalar(ph) && ph>0
            v = get_param(ph,'PortNumber');
            if isnumeric(v)
                n = double(v);
            else
                n = str2double(v);
            end
        end
    catch
    end
end

function s = localPortType(ph)
    s = "";
    try
        if isnumeric(ph) && isscalar(ph) && ph>0
            s = string(get_param(ph,'PortType'));
        end
    catch
    end
end

function m = localMapIncrement(m,key)
    if isempty(key), return; end
    if isKey(m,key)
        m(key) = m(key)+1;
    else
        m(key) = 1;
    end
end

function s = localStructFieldText(st,field,maxChars)
    s = "";
    try
        if isfield(st,field)
            s = localToText(st.(field),maxChars);
        end
    catch
    end
end

function s = localConnectivityBlocks(st,field,maxChars)
    s = "";
    try
        if ~isfield(st,field), return; end
        v = st.(field);
        if isempty(v), return; end
        if isnumeric(v)
            paths = strings(0,1);
            for i = 1:numel(v)
                if v(i)>0
                    try
                        paths(end+1,1) = string(getfullname(v(i))); %#ok<AGROW>
                    catch
                    end
                end
            end
            s = localToText(strjoin(paths," | "),maxChars);
        else
            s = localToText(v,maxChars);
        end
    catch
    end
end

function s = localConnectivityPorts(st,field,maxChars)
    s = "";
    try
        if isfield(st,field)
            s = localToText(st.(field),maxChars);
        end
    catch
    end
end

function T = localCellTable(rows,varNames,numericCols)
    nvar = numel(varNames);
    if isempty(rows)
        T = cell2table(cell(0,nvar),'VariableNames',varNames);
        for k = 1:nvar
            if any(k==numericCols)
                T.(varNames{k}) = zeros(0,1);
            else
                T.(varNames{k}) = strings(0,1);
            end
        end
        return;
    end
    T = cell2table(rows,'VariableNames',varNames);
    for k = 1:nvar
        if any(k==numericCols)
            try
                T.(varNames{k}) = cell2mat(T.(varNames{k}));
            catch
                T.(varNames{k}) = str2double(string(T.(varNames{k})));
            end
        else
            T.(varNames{k}) = string(T.(varNames{k}));
        end
    end
end

function [groupT,virtualT] = localBuildGotoGroups(gfTable,maxChars)
    groupRows = cell(0,7);
    virtualRows = cell(0,4);

    if isempty(gfTable) || height(gfTable)==0
        groupT = localCellTable(groupRows, ...
            {'Tag','GotoCount','FromCount','VisibilityCount','GotoPaths','FromPaths','VisibilityPaths'}, ...
            [2 3 4]);
        virtualT = localCellTable(virtualRows, ...
            {'GotoCandidate','FromBlock','Tag','ResolutionStatus'},[]);
        return;
    end

    tags = unique(gfTable.Tag(strlength(gfTable.Tag)>0),'stable');
    for i = 1:numel(tags)
        tag = tags(i);
        g = gfTable(gfTable.Tag==tag & gfTable.Kind=="Goto",:);
        f = gfTable(gfTable.Tag==tag & gfTable.Kind=="From",:);
        v = gfTable(gfTable.Tag==tag & gfTable.Kind=="GotoTagVisibility",:);

        gp = localClipJoin(g.Path,maxChars);
        fp = localClipJoin(f.Path,maxChars);
        vp = localClipJoin(v.Path,maxChars);

        groupRows(end+1,:) = {char(tag),height(g),height(f),height(v),char(gp),char(fp),char(vp)}; %#ok<SAGROW>

        if height(g)==1
            for j = 1:height(f)
                virtualRows(end+1,:) = {char(g.Path(1)),char(f.Path(j)),char(tag), ...
                    'UNIQUE_TAG_STATIC_CANDIDATE'}; %#ok<SAGROW>
            end
        elseif height(g)>1
            for gg = 1:height(g)
                for ff = 1:height(f)
                    virtualRows(end+1,:) = {char(g.Path(gg)),char(f.Path(ff)),char(tag), ...
                        'AMBIGUOUS_SCOPE_STATIC_CANDIDATE'}; %#ok<SAGROW>
                end
            end
        elseif height(f)>0
            for ff = 1:height(f)
                virtualRows(end+1,:) = {'',char(f.Path(ff)),char(tag), ...
                    'NO_GOTO_FOUND_STATIC'}; %#ok<SAGROW>
            end
        end
    end

    groupT = localCellTable(groupRows, ...
        {'Tag','GotoCount','FromCount','VisibilityCount','GotoPaths','FromPaths','VisibilityPaths'}, ...
        [2 3 4]);
    virtualT = localCellTable(virtualRows, ...
        {'GotoCandidate','FromBlock','Tag','ResolutionStatus'},[]);
end

function T = localBuildDataStoreGroups(dsTable,maxChars)
    rows = cell(0,7);
    if isempty(dsTable) || height(dsTable)==0
        T = localCellTable(rows, ...
            {'DataStoreName','MemoryCount','ReadCount','WriteCount','MemoryPaths','ReadPaths','WritePaths'}, ...
            [2 3 4]);
        return;
    end
    names = unique(dsTable.DataStoreName(strlength(dsTable.DataStoreName)>0),'stable');
    for i = 1:numel(names)
        nm = names(i);
        m = dsTable(dsTable.DataStoreName==nm & dsTable.Kind=="DataStoreMemory",:);
        r = dsTable(dsTable.DataStoreName==nm & dsTable.Kind=="DataStoreRead",:);
        w = dsTable(dsTable.DataStoreName==nm & dsTable.Kind=="DataStoreWrite",:);
        rows(end+1,:) = { ...
            char(nm),height(m),height(r),height(w), ...
            char(localClipJoin(m.ChartPath,maxChars)),char(localClipJoin(r.Path,maxChars)), ...
            char(localClipJoin(w.Path,maxChars))}; %#ok<SAGROW>
    end
    T = localCellTable(rows, ...
        {'DataStoreName','MemoryCount','ReadCount','WriteCount','MemoryPaths','ReadPaths','WritePaths'}, ...
        [2 3 4]);
end

function s = localClipJoin(v,maxChars)
    if isempty(v)
        s = "";
        return;
    end
    s = strjoin(string(v)," | ");
    if strlength(s)>maxChars
        s = extractBefore(s,maxChars+1) + "...<truncated>";
    end
end

function v = localObjectPropRaw(obj,prop)
    v = [];
    try
        v = obj.(prop);
    catch
    end
end

function s = localObjectProp(obj,prop)
    s = "";
    try
        s = localToText(obj.(prop),12000);
    catch
    end
end

function [lineCount,nonEmptyCount,persistentCount,ifCount,switchCount,forCount,whileCount] = localCodeMetrics(txt)
    lines = regexp(txt,'\r\n|\n|\r','split');
    lineCount = numel(lines);
    nonEmptyCount = sum(~cellfun(@(x) isempty(strtrim(x)),lines));
    persistentCount = numel(regexp(txt,'(?m)^\s*persistent\b','match'));
    ifCount = numel(regexp(txt,'(?m)^\s*if\b','match')) + ...
              numel(regexp(txt,'(?m)^\s*elseif\b','match'));
    switchCount = numel(regexp(txt,'(?m)^\s*switch\b','match'));
    forCount = numel(regexp(txt,'(?m)^\s*for\b','match'));
    whileCount = numel(regexp(txt,'(?m)^\s*while\b','match'));
end

function s = localFirstNonEmptyLine(txt)
    s = "";
    lines = regexp(txt,'\r\n|\n|\r','split');
    for i = 1:numel(lines)
        t = strtrim(lines{i});
        if ~isempty(t)
            s = localToText(t,500);
            return;
        end
    end
end

function localWriteText(path,txt)
    fid = fopen(path,'w','n','UTF-8');
    if fid<0
        error('AUDIT:WriteFailed','Cannot write file: %s',path);
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid,txt,'char');
end

function T = localDuplicateFunctionGroups(functionTable,maxChars)
    rows = cell(0,4);
    if isempty(functionTable) || height(functionTable)==0
        T = localCellTable(rows,{'ExactSHA256','Count','Paths','Note'},[2]);
        return;
    end

    hashes = unique(functionTable.ExactSHA256(strlength(functionTable.ExactSHA256)>0),'stable');
    for i = 1:numel(hashes)
        h = hashes(i);
        m = functionTable(functionTable.ExactSHA256==h,:);
        if height(m)>1
            rows(end+1,:) = {char(h),height(m),char(localClipJoin(m.Path,maxChars)), ...
                'EXACT_SOURCE_DUPLICATE_REVIEW_ONLY'}; %#ok<SAGROW>
        end
    end
    T = localCellTable(rows,{'ExactSHA256','Count','Paths','Note'},[2]);
end

function T = localBuildSubsystemInterfaces(blockTable,edgeTable,maxChars)
    rows = cell(0,9);
    ioMask = ismember(blockTable.BlockType,["Inport","Outport"]);
    io = blockTable(ioMask,:);

    for i = 1:height(io)
        portBlock = io.Path(i);
        subsystem = io.Parent(i);
        direction = io.BlockType(i);
        pn = str2double(io.PortParam(i));
        if isnan(pn), pn = 1; end

        externalNeighbors = "";
        internalNeighbors = "";
        externalLines = "";
        internalLines = "";

        if direction=="Inport"
            ext = edgeTable(edgeTable.DstBlock==subsystem & edgeTable.DstPort==pn,:);
            inte = edgeTable(edgeTable.SrcBlock==portBlock,:);
            externalNeighbors = localClipJoin(ext.SrcBlock,maxChars);
            internalNeighbors = localClipJoin(inte.DstBlock,maxChars);
            externalLines = localClipJoin(ext.LineName,maxChars);
            internalLines = localClipJoin(inte.LineName,maxChars);
        else
            ext = edgeTable(edgeTable.SrcBlock==subsystem & edgeTable.SrcPort==pn,:);
            inte = edgeTable(edgeTable.DstBlock==portBlock,:);
            externalNeighbors = localClipJoin(ext.DstBlock,maxChars);
            internalNeighbors = localClipJoin(inte.SrcBlock,maxChars);
            externalLines = localClipJoin(ext.LineName,maxChars);
            internalLines = localClipJoin(inte.LineName,maxChars);
        end

        rows(end+1,:) = { ...
            char(subsystem),char(direction),pn,char(portBlock),char(io.Name(i)), ...
            char(externalNeighbors),char(internalNeighbors),char(externalLines),char(internalLines)}; %#ok<SAGROW>
    end

    T = localCellTable(rows, ...
        {'Subsystem','Direction','PortNumber','PortBlock','PortBlockName', ...
         'ExternalNeighbors','InternalNeighbors','ExternalLineNames','InternalLineNames'},[3]);
end

function s = localFirstNonEmpty(vals)
    s = "";
    for i = 1:numel(vals)
        v = string(vals{i});
        if strlength(v)>0
            s = v;
            return;
        end
    end
end

function s = localValuePreview(v,maxChars)
    if nargin<2, maxChars=500; end
    try
        if isnumeric(v) || islogical(v)
            if numel(v)<=50
                s = localToText(v,maxChars);
            else
                s = string(class(v)) + " " + string(mat2str(size(v)));
            end
        elseif ischar(v) || isstring(v)
            s = localToText(v,maxChars);
        else
            s = string(class(v)) + " " + string(mat2str(size(v)));
        end
    catch
        s = "";
    end
end

function T = localBuildCleanupCandidates(blockTable,unconnTable,tagGroupTable,dsGroupTable,dupFunctionTable)
    rows = cell(0,4);

    for i = 1:height(blockTable)
        reasons = strings(0,1);
        p = upper(blockTable.Path(i));
        bt = blockTable.BlockType(i);

        if bt=="Terminator"
            reasons(end+1) = "TERMINATOR_REVIEW"; %#ok<AGROW>
        end
        if strlength(blockTable.Commented(i))>0 && ~strcmpi(blockTable.Commented(i),'off')
            reasons(end+1) = "COMMENTED_BLOCK_REVIEW"; %#ok<AGROW>
        end
        nameMarkers = {'OLD','PREVIOUS','LEGACY','SHADOW','DIAG','TEST','BYPASS','UNUSED','OBSOLETE'};
        for k = 1:numel(nameMarkers)
            if contains(p,nameMarkers{k})
                reasons(end+1) = "NAME_MARKER_" + string(nameMarkers{k}); %#ok<AGROW>
            end
        end
        if ~isempty(reasons)
            rows(end+1,:) = { ...
                char(blockTable.Path(i)),char(strjoin(unique(reasons,'stable'),'|')), ...
                blockTable.FanIn(i)+blockTable.FanOut(i), ...
                'CANDIDATE_ONLY__DO_NOT_DELETE_WITHOUT_CONSUMER_AUDIT'}; %#ok<SAGROW>
        end
    end

    if ~isempty(unconnTable)
        for i = 1:height(unconnTable)
            rows(end+1,:) = { ...
                char(unconnTable.BlockPath(i)), ...
                ['UNCONNECTED_PORT_RECORD_' num2str(unconnTable.PortRecordIndex(i))], ...
                0,'PORT_LEVEL_REVIEW_ONLY'}; %#ok<SAGROW>
        end
    end

    if ~isempty(tagGroupTable)
        for i = 1:height(tagGroupTable)
            if tagGroupTable.GotoCount(i)>0 && tagGroupTable.FromCount(i)==0
                rows(end+1,:) = { ...
                    char(tagGroupTable.GotoPaths(i)), ...
                    ['GOTO_TAG_WITHOUT_FROM:' char(tagGroupTable.Tag(i))], ...
                    tagGroupTable.GotoCount(i),'VIRTUAL_DEPENDENCY_REVIEW_ONLY'}; %#ok<SAGROW>
            elseif tagGroupTable.FromCount(i)>0 && tagGroupTable.GotoCount(i)==0
                rows(end+1,:) = { ...
                    char(tagGroupTable.FromPaths(i)), ...
                    ['FROM_TAG_WITHOUT_GOTO:' char(tagGroupTable.Tag(i))], ...
                    tagGroupTable.FromCount(i),'VIRTUAL_DEPENDENCY_REVIEW_ONLY'}; %#ok<SAGROW>
            end
        end
    end

    if ~isempty(dsGroupTable)
        for i = 1:height(dsGroupTable)
            if dsGroupTable.MemoryCount(i)>0 && dsGroupTable.ReadCount(i)==0 && dsGroupTable.WriteCount(i)==0
                rows(end+1,:) = { ...
                    char(dsGroupTable.MemoryPaths(i)), ...
                    ['DATASTORE_NO_READ_WRITE:' char(dsGroupTable.DataStoreName(i))], ...
                    dsGroupTable.MemoryCount(i),'DATA_STORE_REVIEW_ONLY'}; %#ok<SAGROW>
            end
        end
    end

    if ~isempty(dupFunctionTable)
        for i = 1:height(dupFunctionTable)
            rows(end+1,:) = { ...
                char(dupFunctionTable.Paths(i)), ...
                ['EXACT_DUPLICATE_FUNCTION_SHA:' char(dupFunctionTable.ExactSHA256(i))], ...
                dupFunctionTable.Count(i),'DUPLICATION_REVIEW_ONLY__MAY_BE_INTENTIONAL'}; %#ok<SAGROW>
        end
    end

    T = localCellTable(rows,{'ObjectOrPaths','Reason','EvidenceCount','SafetyNote'},[3]);
end





function T = localBuildPathShadowTable(mdl,canonicalModelFile)
    rows=cell(0,3);
    try
        q=which([char(mdl) '.slx'],'-all');
        if ischar(q)
            qq=string({q});
        elseif iscell(q)
            qq=string(q);
        else
            qq=string(q);
        end
        for i=1:numel(qq)
            if strlength(qq(i))==0, continue; end
            cp=string(localCanonicalPath(char(qq(i))));
            isTarget=double(strcmpi(cp,string(canonicalModelFile)));
            rows(end+1,:)={char(cp),isTarget,i}; %#ok<SAGROW>
        end
    catch ME
        rows(end+1,:)={['ERROR:' localOneLine(ME.message)],0,NaN}; %#ok<SAGROW>
    end
    T=localCellTable(rows,{'ResolvedPath','IsAuditTarget','PathOrder'},[2 3]);
end

function T = localBuildMaskInventory(blockTable,maxChars)
    rows=cell(0,8);
    mask = strlength(blockTable.MaskType)>0;
    paths=blockTable.Path(mask);
    for i=1:numel(paths)
        b=paths(i);
        r=blockTable(blockTable.Path==b,:);
        rows(end+1,:)={ ...
            char(b),char(r.MaskType(1)),char(r.LinkStatus(1)),char(r.ReferenceBlock(1)), ...
            char(localSafeGetParam(char(b),'MaskInitialization',maxChars)), ...
            char(localSafeGetParam(char(b),'MaskDisplay',maxChars)), ...
            char(localSafeGetParam(char(b),'MaskHelp',maxChars)), ...
            char(localSafeGetParam(char(b),'MaskCallbacks',maxChars))}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Path','MaskType','LinkStatus','ReferenceBlock','MaskInitialization','MaskDisplay','MaskHelp','MaskCallbacks'},[]);
end

function T = localBuildLinePropertyTable(edgeTable,maxChars)
    rows=cell(0,11);
    if isempty(edgeTable) || height(edgeTable)==0
        T=localCellTable(rows, ...
            {'LineHandle','ParentSystem','Name','DataLogging','TestPoint', ...
             'MustResolveToSignalObject','SignalObject','LoggingNameMode', ...
             'UserSpecifiedLogName','SignalPropagation','DestinationCount'},[1 11]);
        return;
    end
    handles=unique(edgeTable.LineHandle(~isnan(edgeTable.LineHandle)),'stable');
    for i=1:numel(handles)
        h=handles(i);
        m=edgeTable.LineHandle==h;
        parent="";
        nm="";
        if any(m)
            ix=find(m,1,'first');
            parent=edgeTable.ParentSystem(ix);
            nm=edgeTable.LineName(ix);
        end
        rows(end+1,:)={ ...
            h,char(parent),char(nm), ...
            char(localSafeGetHandleParam(h,'DataLogging',maxChars)), ...
            char(localSafeGetHandleParam(h,'TestPoint',maxChars)), ...
            char(localSafeGetHandleParam(h,'MustResolveToSignalObject',maxChars)), ...
            char(localSafeGetHandleParam(h,'SignalObject',maxChars)), ...
            char(localSafeGetHandleParam(h,'LoggingNameMode',maxChars)), ...
            char(localSafeGetHandleParam(h,'UserSpecifiedLogName',maxChars)), ...
            char(localSafeGetHandleParam(h,'SignalPropagation',maxChars)), ...
            sum(m)}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'LineHandle','ParentSystem','Name','DataLogging','TestPoint', ...
         'MustResolveToSignalObject','SignalObject','LoggingNameMode', ...
         'UserSpecifiedLogName','SignalPropagation','DestinationCount'},[1 11]);
end

function [fcnName,outArgs,inArgs] = localParseFunctionSignature(txt)
    fcnName = "";
    outArgs = "";
    inArgs = "";
    try
        t = regexprep(txt,'\.\.\.\s*(\r\n|\n|\r)',' ');
        % Standard form: function [a,b] = name(x,y) or function a = name(x)
        m = regexp(t,'function\s+(?<lhs>\[[^\]]*\]|[A-Za-z]\w*)\s*=\s*(?<name>[A-Za-z]\w*)\s*\((?<args>[^\)]*)\)', ...
            'names','once');
        if ~isempty(m)
            fcnName = string(m.name);
            outArgs = strtrim(string(m.lhs));
            inArgs = strtrim(string(m.args));
            return;
        end
        % No explicit output assignment.
        m = regexp(t,'function\s+(?<name>[A-Za-z]\w*)\s*\((?<args>[^\)]*)\)', ...
            'names','once');
        if ~isempty(m)
            fcnName = string(m.name);
            inArgs = strtrim(string(m.args));
        end
    catch
    end
end

function T = localBuildFunctionIOMap(functionTable,edgeTable,maxChars)
    rows = cell(0,8);
    if isempty(functionTable) || height(functionTable)==0
        T = localCellTable(rows, ...
            {'BlockPath','FunctionName','Direction','FunctionPort','PeerBlock', ...
             'PeerBlockType','PeerPort','LineName'},[4 7]);
        return;
    end
    for i = 1:height(functionTable)
        b = functionTable.BlockPath(i);
        fn = functionTable.FunctionName(i);

        ins = edgeTable(edgeTable.DstBlock==b,:);
        for j = 1:height(ins)
            rows(end+1,:) = { ...
                char(b),char(fn),'INPUT',ins.DstPort(j),char(ins.SrcBlock(j)), ...
                char(ins.SrcBlockType(j)),ins.SrcPort(j),char(ins.LineName(j))}; %#ok<SAGROW>
        end

        outs = edgeTable(edgeTable.SrcBlock==b,:);
        for j = 1:height(outs)
            rows(end+1,:) = { ...
                char(b),char(fn),'OUTPUT',outs.SrcPort(j),char(outs.DstBlock(j)), ...
                char(outs.DstBlockType(j)),outs.DstPort(j),char(outs.LineName(j))}; %#ok<SAGROW>
        end
    end
    T = localCellTable(rows, ...
        {'BlockPath','FunctionName','Direction','FunctionPort','PeerBlock', ...
         'PeerBlockType','PeerPort','LineName'},[4 7]);
end

function out = localBuildStateflowSummary(mdl,maxChars)
    chartRows = cell(0,6);
    stateRows = cell(0,6);
    transRows = cell(0,7);
    try
        rt = sfroot;

        charts = rt.find('-isa','Stateflow.Chart');
        for i = 1:numel(charts)
            p = string(localObjectProp(charts(i),'Path'));
            nm = string(localObjectProp(charts(i),'Name'));
            fp = p;
            if strlength(nm)>0
                if strlength(p)>0, fp = p + "/" + nm; else, fp = nm; end
            end
            if ~(p==string(mdl) || startsWith(p,string(mdl)+"/") || ...
                 fp==string(mdl) || startsWith(fp,string(mdl)+"/"))
                continue;
            end
            chartRows(end+1,:) = { ...
                char(p),char(fp),char(nm),class(charts(i)), ...
                char(localObjectProp(charts(i),'Description')), ...
                char(localObjectProp(charts(i),'Document'))}; %#ok<SAGROW>
        end

        states = rt.find('-isa','Stateflow.State');
        for i = 1:numel(states)
            p = string(localObjectProp(states(i),'Path'));
            nm = string(localObjectProp(states(i),'Name'));
            if ~(p==string(mdl) || startsWith(p,string(mdl)+"/")), continue; end
            stateRows(end+1,:) = { ...
                char(p),char(nm),class(states(i)), ...
                char(localObjectProp(states(i),'LabelString')), ...
                char(localObjectProp(states(i),'Description')), ...
                char(localObjectProp(states(i),'Tag'))}; %#ok<SAGROW>
        end

        trs = rt.find('-isa','Stateflow.Transition');
        for i = 1:numel(trs)
            p = string(localObjectProp(trs(i),'Path'));
            if ~(p==string(mdl) || startsWith(p,string(mdl)+"/")), continue; end
            src = localObjectRefPath(localObjectPropRaw(trs(i),'Source'));
            dst = localObjectRefPath(localObjectPropRaw(trs(i),'Destination'));
            transRows(end+1,:) = { ...
                char(p),class(trs(i)),char(src),char(dst), ...
                char(localObjectProp(trs(i),'LabelString')), ...
                char(localObjectProp(trs(i),'Description')), ...
                char(localObjectProp(trs(i),'Tag'))}; %#ok<SAGROW>
        end
    catch
    end

    out = struct();
    out.Charts = localCellTable(chartRows, ...
        {'ParentPath','ChartPath','Name','Class','Description','Document'},[]);
    out.States = localCellTable(stateRows, ...
        {'Path','Name','Class','LabelString','Description','Tag'},[]);
    out.Transitions = localCellTable(transRows, ...
        {'Path','Class','Source','Destination','LabelString','Description','Tag'},[]);
end

function s = localObjectRefPath(obj)
    s = "";
    try
        if isempty(obj), return; end
        p = string(localObjectProp(obj,'Path'));
        n = string(localObjectProp(obj,'Name'));
        if strlength(n)>0
            if strlength(p)>0, s = p + "/" + n; else, s = n; end
        else
            s = p;
        end
    catch
    end
end

function T = localCountStrings(v,varName)
    rows = cell(0,2);
    if isempty(v)
        T = localCellTable(rows,{varName,'Count'},[2]);
        return;
    end
    v = string(v);
    vals = unique(v,'stable');
    for i = 1:numel(vals)
        rows(end+1,:) = {char(vals(i)),sum(v==vals(i))}; %#ok<SAGROW>
    end
    T = localCellTable(rows,{varName,'Count'},[2]);
    if height(T)>0
        T = sortrows(T,'Count','descend');
    end
end

function T = localBuildGotoFlow(gfTable,edgeTable,maxChars)
    rows = cell(0,8);
    if isempty(gfTable) || height(gfTable)==0
        T = localCellTable(rows, ...
            {'Tag','GotoPath','GotoUpstream','GotoUpstreamPort','FromPath', ...
             'FromDownstream','FromDownstreamPort','ResolutionStatus'},[4 7]);
        return;
    end
    tags = unique(gfTable.Tag(strlength(gfTable.Tag)>0),'stable');
    for i = 1:numel(tags)
        tag = tags(i);
        gs = gfTable(gfTable.Tag==tag & gfTable.Kind=="Goto",:);
        fs = gfTable(gfTable.Tag==tag & gfTable.Kind=="From",:);
        if height(gs)==1
            status = 'UNIQUE_TAG_STATIC_CANDIDATE';
        elseif height(gs)>1
            status = 'MULTIPLE_GOTO_SCOPE_REQUIRES_SCOPE_REVIEW';
        else
            status = 'NO_GOTO_FOUND';
        end
        if height(fs)==0
            if height(gs)>0
                for g = 1:height(gs)
                    up = edgeTable(edgeTable.DstBlock==gs.Path(g),:);
                    if isempty(up)
                        rows(end+1,:) = {char(tag),char(gs.Path(g)),'',NaN,'','',NaN,'NO_FROM_FOUND'}; %#ok<SAGROW>
                    else
                        for u = 1:height(up)
                            rows(end+1,:) = {char(tag),char(gs.Path(g)),char(up.SrcBlock(u)), ...
                                up.SrcPort(u),'','',NaN,'NO_FROM_FOUND'}; %#ok<SAGROW>
                        end
                    end
                end
            end
            continue;
        end
        if height(gs)==0
            for f = 1:height(fs)
                dn = edgeTable(edgeTable.SrcBlock==fs.Path(f),:);
                if isempty(dn)
                    rows(end+1,:) = {char(tag),'','',NaN,char(fs.Path(f)),'',NaN,status}; %#ok<SAGROW>
                else
                    for d = 1:height(dn)
                        rows(end+1,:) = {char(tag),'','',NaN,char(fs.Path(f)), ...
                            char(dn.DstBlock(d)),dn.DstPort(d),status}; %#ok<SAGROW>
                    end
                end
            end
            continue;
        end
        for g = 1:height(gs)
            up = edgeTable(edgeTable.DstBlock==gs.Path(g),:);
            if isempty(up)
                upSrc = ""; upPort = NaN;
            else
                upSrc = up.SrcBlock(1); upPort = up.SrcPort(1);
            end
            for f = 1:height(fs)
                dn = edgeTable(edgeTable.SrcBlock==fs.Path(f),:);
                if isempty(dn)
                    rows(end+1,:) = {char(tag),char(gs.Path(g)),char(upSrc),upPort, ...
                        char(fs.Path(f)),'',NaN,status}; %#ok<SAGROW>
                else
                    for d = 1:height(dn)
                        rows(end+1,:) = {char(tag),char(gs.Path(g)),char(upSrc),upPort, ...
                            char(fs.Path(f)),char(dn.DstBlock(d)),dn.DstPort(d),status}; %#ok<SAGROW>
                    end
                end
            end
        end
    end
    T = localCellTable(rows, ...
        {'Tag','GotoPath','GotoUpstream','GotoUpstreamPort','FromPath', ...
         'FromDownstream','FromDownstreamPort','ResolutionStatus'},[4 7]);
end

function T = localBuildDependencyGraph(edgeTable,interfaceTable,virtualEdgeTable,dsTable)
    rows = cell(0,4);
    for i = 1:height(edgeTable)
        if strlength(edgeTable.SrcBlock(i))>0 && strlength(edgeTable.DstBlock(i))>0
            detail = sprintf('srcPort=%g;dstPort=%g;line=%s', ...
                edgeTable.SrcPort(i),edgeTable.DstPort(i),char(edgeTable.LineName(i)));
            rows(end+1,:) = {char(edgeTable.SrcBlock(i)),char(edgeTable.DstBlock(i)), ...
                'LINE',detail}; %#ok<SAGROW>
        end
    end

    for i = 1:height(interfaceTable)
        if interfaceTable.Direction(i)=="Inport"
            rows(end+1,:) = {char(interfaceTable.Subsystem(i)),char(interfaceTable.PortBlock(i)), ...
                'SUBSYSTEM_INPUT_BRIDGE',sprintf('port=%g',interfaceTable.PortNumber(i))}; %#ok<SAGROW>
        else
            rows(end+1,:) = {char(interfaceTable.PortBlock(i)),char(interfaceTable.Subsystem(i)), ...
                'SUBSYSTEM_OUTPUT_BRIDGE',sprintf('port=%g',interfaceTable.PortNumber(i))}; %#ok<SAGROW>
        end
    end

    for i = 1:height(virtualEdgeTable)
        if strlength(virtualEdgeTable.GotoCandidate(i))>0 && strlength(virtualEdgeTable.FromBlock(i))>0
            rows(end+1,:) = {char(virtualEdgeTable.GotoCandidate(i)),char(virtualEdgeTable.FromBlock(i)), ...
                'GOTO_FROM_CANDIDATE', ...
                [char(virtualEdgeTable.Tag(i)) '|' char(virtualEdgeTable.ResolutionStatus(i))]}; %#ok<SAGROW>
        end
    end

    if ~isempty(dsTable) && height(dsTable)>0
        names = unique(dsTable.DataStoreName(strlength(dsTable.DataStoreName)>0),'stable');
        for i = 1:numel(names)
            nm = names(i);
            ws = dsTable(dsTable.DataStoreName==nm & dsTable.Kind=="DataStoreWrite",:);
            rs = dsTable(dsTable.DataStoreName==nm & dsTable.Kind=="DataStoreRead",:);
            for w = 1:height(ws)
                for r = 1:height(rs)
                    rows(end+1,:) = {char(ws.Path(w)),char(rs.Path(r)), ...
                        'DATASTORE_WRITE_READ_CANDIDATE',char(nm)}; %#ok<SAGROW>
                end
            end
        end
    end

    T = localCellTable(rows,{'SrcNode','DstNode','EdgeKind','Detail'},[]);
end

function T = localBuildSwitchRouterInventory(blockTable,edgeTable,paramTable,maxChars)
    types = ["Switch","MultiPortSwitch","ManualSwitch","Merge","If","SwitchCase", ...
             "VariantSource","VariantSink"];
    paths = blockTable.Path(ismember(blockTable.BlockType,types));
    rows = cell(0,9);
    for i = 1:numel(paths)
        b = paths(i);
        bt = blockTable.BlockType(blockTable.Path==b);
        bt = bt(1);
        ps = localParamSummary(b,paramTable,maxChars);

        ins = edgeTable(edgeTable.DstBlock==b,:);
        for j = 1:height(ins)
            role = localSwitchPortRole(bt,ins.DstPort(j));
            rows(end+1,:) = {char(b),char(bt),'INPUT',ins.DstPort(j),char(role), ...
                char(ins.SrcBlock(j)),ins.SrcPort(j),char(ins.LineName(j)),char(ps)}; %#ok<SAGROW>
        end
        outs = edgeTable(edgeTable.SrcBlock==b,:);
        for j = 1:height(outs)
            rows(end+1,:) = {char(b),char(bt),'OUTPUT',outs.SrcPort(j),'OUTPUT', ...
                char(outs.DstBlock(j)),outs.DstPort(j),char(outs.LineName(j)),char(ps)}; %#ok<SAGROW>
        end
    end
    T = localCellTable(rows, ...
        {'Path','BlockType','Direction','LocalPort','PortRole','PeerBlock','PeerPort','LineName','ParameterSummary'}, ...
        [4 7]);
end

function r = localSwitchPortRole(bt,port)
    r = "DATA_OR_UNKNOWN";
    if bt=="Switch"
        if port==2, r="CONTROL"; else, r="DATA"; end
    elseif bt=="ManualSwitch"
        r = "DATA";
    elseif bt=="MultiPortSwitch"
        if port==1, r="CONTROL_INDEX"; else, r="DATA"; end
    elseif bt=="Merge"
        r = "MERGE_DATA";
    elseif bt=="If"
        r = "CONDITION_INPUT";
    elseif bt=="SwitchCase"
        if port==1, r="CASE_CONTROL"; else, r="INPUT"; end
    end
end

function T = localBuildBundleInventory(blockTable,edgeTable,paramTable,maxChars)
    types = ["Mux","Demux","BusCreator","BusSelector","VectorConcatenate", ...
             "Concatenate","Reshape","SignalConversion","Selector","Assignment"];
    paths = blockTable.Path(ismember(blockTable.BlockType,types));
    rows = cell(0,8);
    for i = 1:numel(paths)
        b = paths(i);
        bt = blockTable.BlockType(blockTable.Path==b); bt=bt(1);
        ps = localParamSummary(b,paramTable,maxChars);
        ins = edgeTable(edgeTable.DstBlock==b,:);
        for j=1:height(ins)
            rows(end+1,:) = {char(b),char(bt),'INPUT',ins.DstPort(j), ...
                char(ins.SrcBlock(j)),ins.SrcPort(j),char(ins.LineName(j)),char(ps)}; %#ok<SAGROW>
        end
        outs = edgeTable(edgeTable.SrcBlock==b,:);
        for j=1:height(outs)
            rows(end+1,:) = {char(b),char(bt),'OUTPUT',outs.SrcPort(j), ...
                char(outs.DstBlock(j)),outs.DstPort(j),char(outs.LineName(j)),char(ps)}; %#ok<SAGROW>
        end
    end
    T=localCellTable(rows, ...
        {'Path','BlockType','Direction','LocalPort','PeerBlock','PeerPort','LineName','ParameterSummary'}, ...
        [4 6]);
end

function T = localBuildStatefulInventory(blockTable,edgeTable,paramTable,maxChars)
    types = ["UnitDelay","Delay","Memory","Integrator","DiscreteIntegrator", ...
             "TransferFcn","DiscreteTransferFcn","StateSpace","DiscreteStateSpace", ...
             "RateTransition","ZeroOrderHold","TappedDelay","TransportDelay"];
    mask = ismember(blockTable.BlockType,types) | ...
           contains(upper(blockTable.Path),'UNIT DELAY') | ...
           contains(upper(blockTable.Path),'MEMORY') | ...
           contains(upper(blockTable.Path),'INTEGRATOR') | ...
           contains(upper(blockTable.Path),'RATE TRANSITION');
    paths = blockTable.Path(mask);
    rows = cell(0,9);
    for i=1:numel(paths)
        b=paths(i);
        row = blockTable(blockTable.Path==b,:);
        up = localClipJoin(edgeTable.SrcBlock(edgeTable.DstBlock==b),maxChars);
        dn = localClipJoin(edgeTable.DstBlock(edgeTable.SrcBlock==b),maxChars);
        rows(end+1,:) = {char(b),char(row.BlockType(1)),char(row.MatchedTokens(1)), ...
            row.NumIn(1),row.NumOut(1),char(up),char(dn), ...
            char(localParamSummary(b,paramTable,maxChars)), ...
            'STATE_CONTINUITY_REVIEW'}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Path','BlockType','MatchedTokens','NumIn','NumOut','Upstream','Downstream','ParameterSummary','ReviewClass'}, ...
        [4 5]);
end

function T = localBuildKeyModuleContracts(blockTable,edgeTable,paramTable,maxChars)
    keyTypes = ["SubSystem","Constant","Goto","From","Switch","MultiPortSwitch","Gain", ...
                "Sum","UnitDelay","Delay","Memory","DiscreteIntegrator","RateTransition"];
    mask = strlength(blockTable.MatchedTokens)>0 & ...
           (ismember(blockTable.BlockType,keyTypes) | strlength(blockTable.SFBlockType)>0);
    paths = blockTable.Path(mask);
    rows = cell(0,12);
    for i=1:numel(paths)
        b=paths(i);
        r=blockTable(blockTable.Path==b,:);
        childCount=sum(blockTable.Parent==b);
        descCount=sum(startsWith(blockTable.Path,b+"/"));
        up=localClipJoin(edgeTable.SrcBlock(edgeTable.DstBlock==b),maxChars);
        dn=localClipJoin(edgeTable.DstBlock(edgeTable.SrcBlock==b),maxChars);
        rows(end+1,:)={char(b),char(r.Name(1)),char(r.BlockType(1)),char(r.SFBlockType(1)), ...
            char(r.MatchedTokens(1)),r.NumIn(1),r.NumOut(1),childCount,descCount, ...
            char(up),char(dn),char(localParamSummary(b,paramTable,maxChars))}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Path','Name','BlockType','SFBlockType','MatchedTokens','NumIn','NumOut', ...
         'DirectChildBlocks','DescendantBlocks','DirectUpstream','DirectDownstream','ParameterSummary'}, ...
        [6 7 8 9]);
end

function T = localBuildStageConfigConsumerIndex(blockTable,edgeTable,paramTable,gfTable,gotoFlowTable,maxChars)
    pat = '(CFG15_|FINAL_SYSTEM_STAGE|ENG_STAGE|CONTROL_SOURCE|MASTER_ENABLE|EXEC_S\d+|F2[0-5]|V4[789]|QBIAS|SYSTEM_STAGE|P_OBJECTIVE)';
    mask = false(height(blockTable),1);
    for i=1:height(blockTable)
        txt = char(blockTable.Path(i) + " " + blockTable.Name(i) + " " + blockTable.Tag(i));
        mask(i)=~isempty(regexpi(txt,pat,'once'));
    end
    paths=blockTable.Path(mask);
    rows=cell(0,10);
    for i=1:numel(paths)
        b=paths(i);
        r=blockTable(blockTable.Path==b,:);
        up=localClipJoin(edgeTable.SrcBlock(edgeTable.DstBlock==b),maxChars);
        dn=localClipJoin(edgeTable.DstBlock(edgeTable.SrcBlock==b),maxChars);
        virt="";
        if ~isempty(gotoFlowTable) && height(gotoFlowTable)>0
            m=gotoFlowTable(gotoFlowTable.GotoPath==b | gotoFlowTable.FromPath==b,:);
            if height(m)>0
                virt=localClipJoin(m.FromDownstream,maxChars);
            end
        end
        gt="";
        gm=gfTable(gfTable.Path==b,:);
        if height(gm)>0, gt=gm.Tag(1); end
        rows(end+1,:)={char(b),char(r.BlockType(1)),char(r.MatchedTokens(1)),char(gt), ...
            char(localParamSummary(b,paramTable,maxChars)),char(up),char(dn),char(virt), ...
            r.FanIn(1),r.FanOut(1)}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Path','BlockType','MatchedTokens','GotoFromTag','ParameterSummary', ...
         'DirectUpstream','DirectDownstream','VirtualConsumers','FanIn','FanOut'},[9 10]);
end

function T = localBuildPhysicalConnectivity(pcTable,physicalBlockTable)
    if isempty(pcTable) || height(pcTable)==0
        T=pcTable;
        return;
    end
    mask = ismember(pcTable.BlockPath,physicalBlockTable.Path) | ...
           contains(upper(pcTable.PortType),'LCONN') | contains(upper(pcTable.PortType),'RCONN');
    T=pcTable(mask,:);
end

function T = localBuildTransportContract(rtlabTable,edgeTable,paramTable,maxChars)
    rows=cell(0,10);
    for i=1:height(rtlabTable)
        b=rtlabTable.Path(i);
        up=localClipJoin(edgeTable.SrcBlock(edgeTable.DstBlock==b),maxChars);
        dn=localClipJoin(edgeTable.DstBlock(edgeTable.SrcBlock==b),maxChars);
        rows(end+1,:)={char(b),char(rtlabTable.Name(i)),char(rtlabTable.BlockType(i)), ...
            char(rtlabTable.MaskType(i)),char(rtlabTable.ReferenceBlock(i)), ...
            char(localTaskRoot(b)),rtlabTable.NumIn(i),rtlabTable.NumOut(i), ...
            char(up),[char(dn) ' | PARAM=' char(localParamSummary(b,paramTable,maxChars))]}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Path','Name','BlockType','MaskType','ReferenceBlock','TaskRoot','NumIn','NumOut','Upstream','DownstreamAndParameters'}, ...
        [7 8]);
end

function [inputT,traceT] = localBuildLoggerMaps(rtlabTable,edgeTable,blockTable,maxChars)
    mask = contains(upper(rtlabTable.Path),'OPWRITE') | ...
           contains(upper(rtlabTable.MaskType),'OPWRITE') | ...
           contains(upper(rtlabTable.ReferenceBlock),'OPWRITE');
    logs=rtlabTable(mask,:);
    inRows=cell(0,8);
    trRows=cell(0,9);
    passTypes=["Mux","BusCreator","VectorConcatenate","Concatenate","SignalConversion", ...
               "Reshape","DataTypeConversion","RateTransition","Selector"];
    maxDepth=5;

    for i=1:height(logs)
        lg=logs.Path(i);
        ins=edgeTable(edgeTable.DstBlock==lg,:);
        for j=1:height(ins)
            src=ins.SrcBlock(j);
            inRows(end+1,:)={char(lg),ins.DstPort(j),char(src),char(ins.SrcBlockType(j)), ...
                ins.SrcPort(j),char(ins.LineName(j)),char(localTaskRoot(lg)),'DIRECT'}; %#ok<SAGROW>

            queueBlock = string(src);
            queueDepth = 1;
            queueLoggerPort = ins.DstPort(j);
            q=1;
            visited = strings(0,1);
            while q<=numel(queueBlock)
                cur=queueBlock(q);
                dep=queueDepth(q);
                lp=queueLoggerPort(q);
                q=q+1;
                key=cur+"#"+string(dep)+"#"+string(lp);
                if any(visited==key), continue; end
                visited(end+1,1)=key; %#ok<AGROW>
                br=blockTable(blockTable.Path==cur,:);
                if height(br)==0
                    bt="";
                else
                    bt=br.BlockType(1);
                end
                ups=edgeTable(edgeTable.DstBlock==cur,:);
                if dep>=maxDepth || ~ismember(bt,passTypes) || isempty(ups)
                    trRows(end+1,:)={char(lg),lp,dep,char(cur),char(bt),'',NaN,'','TERMINAL_OR_DEPTH_LIMIT'}; %#ok<SAGROW>
                    continue;
                end
                for u=1:height(ups)
                    trRows(end+1,:)={char(lg),lp,dep,char(cur),char(bt), ...
                        char(ups.SrcBlock(u)),ups.SrcPort(u),char(ups.LineName(u)),'EXPANDED_BUNDLE_SOURCE'}; %#ok<SAGROW>
                    queueBlock(end+1)=ups.SrcBlock(u); %#ok<AGROW>
                    queueDepth(end+1)=dep+1; %#ok<AGROW>
                    queueLoggerPort(end+1)=lp; %#ok<AGROW>
                end
            end
        end
    end
    inputT=localCellTable(inRows, ...
        {'LoggerPath','LoggerPort','SourceBlock','SourceBlockType','SourcePort','LineName','TaskRoot','MapKind'}, ...
        [2 5]);
    traceT=localCellTable(trRows, ...
        {'LoggerPath','LoggerPort','Depth','CurrentBlock','CurrentBlockType','UpstreamBlock','UpstreamPort','LineName','TraceStatus'}, ...
        [2 3 7]);
    if height(traceT)>0
        traceT.CurrentBlock=arrayfun(@(x)localToText(x,maxChars),traceT.CurrentBlock);
    end
end

function T = localBuildTaskSummary(mdl,blockTable,edgeTable,functionTable,specialTable)
    rels=["SC_Console","SM_Master","SS_Slave","SS_Slave2","SS_Slave3"];
    rows=cell(0,7);
    for i=1:numel(rels)
        root=string(mdl)+"/"+rels(i);
        exists=any(blockTable.Path==root);
        if ~exists
            rows(end+1,:)={char(root),0,0,0,0,0,'NOT_FOUND'}; %#ok<SAGROW>
            continue;
        end
        dm=blockTable.Path==root | startsWith(blockTable.Path,root+"/");
        em=edgeTable.ParentSystem==root | startsWith(edgeTable.ParentSystem,root+"/");
        fm=functionTable.BlockPath==root | startsWith(functionTable.BlockPath,root+"/");
        sm=specialTable.Path==root | startsWith(specialTable.Path,root+"/");
        rows(end+1,:)={char(root),sum(dm),sum(em),sum(fm),sum(sm), ...
            sum(blockTable.Path(dm)~=""),'FOUND'}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'TaskRoot','Blocks','Edges','MATLABFunctions','SpecialInterestBlocks','InventoryCheck','Status'}, ...
        [2 3 4 5 6]);
end

function T = localBuildDeviceSummary(mdl,blockTable,edgeTable,functionTable,specialTable,switchTable,statefulTable)
    rels = { ...
        'SS_Slave3/PV1_Control','PV1'; ...
        'SS_Slave3/PV2_Control','PV2'; ...
        'SS_Slave2/ESS1_Control','ESS1'; ...
        'SS_Slave2/ESS2_Control','ESS2'; ...
        'SS_Slave/EV1_Control','EV1'; ...
        'SS_Slave/Control System','EV2'};
    rows=cell(0,9);
    for i=1:size(rels,1)
        root=string(mdl)+"/"+string(rels{i,1});
        dev=rels{i,2};
        exists=any(blockTable.Path==root);
        if ~exists
            rows(end+1,:)={dev,char(root),0,0,0,0,0,0,'NOT_FOUND'}; %#ok<SAGROW>
            continue;
        end
        bm=blockTable.Path==root | startsWith(blockTable.Path,root+"/");
        em=edgeTable.ParentSystem==root | startsWith(edgeTable.ParentSystem,root+"/");
        fm=functionTable.BlockPath==root | startsWith(functionTable.BlockPath,root+"/");
        sm=specialTable.Path==root | startsWith(specialTable.Path,root+"/");
        sw=switchTable.Path==root | startsWith(switchTable.Path,root+"/");
        st=statefulTable.Path==root | startsWith(statefulTable.Path,root+"/");
        rows(end+1,:)={dev,char(root),sum(bm),sum(em),sum(fm),sum(sm),sum(sw),sum(st),'FOUND'}; %#ok<SAGROW>
    end
    T=localCellTable(rows, ...
        {'Device','ControllerRoot','Blocks','Edges','MATLABFunctions','SpecialInterestBlocks','SwitchMapRows','StatefulBlocks','Status'}, ...
        [3 4 5 6 7 8]);
end

function T = localArchiveCrosscheck(modelFile,outDir)
    rows=cell(0,3);
    tmp=fullfile(outDir,'_slx_archive_crosscheck_tmp');
    try
        if exist(tmp,'dir'), rmdir(tmp,'s'); end
        mkdir(tmp);
        unzip(modelFile,tmp);
        xmls=dir(fullfile(tmp,'**','*.xml'));
        blockTags=0;
        lineTags=0;
        systemXml=0;
        stateflowXml=0;
        for i=1:numel(xmls)
            p=fullfile(xmls(i).folder,xmls(i).name);
            rel=erase(p,[tmp filesep]);
            if contains(strrep(rel,'\','/'),'/systems/')
                systemXml=systemXml+1;
            end
            if contains(lower(strrep(rel,'\','/')),'stateflow')
                stateflowXml=stateflowXml+1;
            end
            try
                txt=fileread(p);
                blockTags=blockTags+numel(regexp(txt,'<Block\b','match'));
                lineTags=lineTags+numel(regexp(txt,'<Line\b','match'));
            catch
            end
        end
        rows(end+1,:)={'XML_FILE_COUNT',numel(xmls),'SLX ZIP archive XML files'}; %#ok<SAGROW>
        rows(end+1,:)={'SYSTEM_XML_COUNT',systemXml,'Files under */systems/*'}; %#ok<SAGROW>
        rows(end+1,:)={'STATEFLOW_XML_COUNT',stateflowXml,'Files whose path contains stateflow'}; %#ok<SAGROW>
        rows(end+1,:)={'BLOCK_TAG_COUNT',blockTags,'Raw XML <Block> tag cross-check'}; %#ok<SAGROW>
        rows(end+1,:)={'LINE_TAG_COUNT',lineTags,'Raw XML <Line> tag cross-check'}; %#ok<SAGROW>
    catch ME
        rows(end+1,:)={'ARCHIVE_CROSSCHECK_ERROR',NaN,localOneLine(ME.message)}; %#ok<SAGROW>
    end
    try
        if exist(tmp,'dir'), rmdir(tmp,'s'); end
    catch
    end
    T=localCellTable(rows,{'Metric','Value','Note'},[2]);
end

function s = localParamSummary(path,paramTable,maxChars)
    s="";
    if isempty(paramTable) || height(paramTable)==0, return; end
    m=paramTable(paramTable.Path==string(path),:);
    if height(m)==0, return; end
    parts=strings(height(m),1);
    for i=1:height(m)
        parts(i)=m.Parameter(i)+"="+m.Value(i);
    end
    s=strjoin(parts," | ");
    if strlength(s)>maxChars
        s=extractBefore(s,maxChars+1)+"...<truncated>";
    end
end

function s = localTaskRoot(path)
    path=string(path);
    s="";
    try
        parts=split(path,"/");
        if numel(parts)>=2
            s=parts(1)+"/"+parts(2);
        else
            s=path;
        end
    catch
    end
end

function [T,status] = localRunCompiledAudit(mdl,blockTable,maxChars)
    rows = cell(0,10);
    status = 'FAILED_BEFORE_COMPILE';
    compiled = false;
    try
        feval(mdl,[],[],[],'compile');
        compiled = true;
        status = 'COMPILED_AUDIT_RUNNING';

        for i = 1:height(blockTable)
            b = char(blockTable.Path(i));
            try
                ph = get_param(b,'PortHandles');
                f = fieldnames(ph);
                for j = 1:numel(f)
                    handles = ph.(f{j});
                    if ~isnumeric(handles), continue; end
                    handles = handles(handles>0);
                    for k = 1:numel(handles)
                        p = handles(k);
                        rows(end+1,:) = { ...
                            b,f{j},localPortNumber(p), ...
                            char(localSafeGetHandleParam(p,'CompiledPortWidth',maxChars)), ...
                            char(localSafeGetHandleParam(p,'CompiledPortDimensions',maxChars)), ...
                            char(localSafeGetHandleParam(p,'CompiledPortDataType',maxChars)), ...
                            char(localSafeGetHandleParam(p,'CompiledPortComplexSignal',maxChars)), ...
                            char(localSafeGetHandleParam(p,'CompiledPortFrameData',maxChars)), ...
                            char(localSafeGetHandleParam(p,'CompiledPortSampleTime',maxChars)), ...
                            char(localSafeGetParam(b,'CompiledSampleTime',maxChars))}; %#ok<SAGROW>
                    end
                end
            catch
            end
        end
        status = 'PASS_COMPILED_PROPERTIES_EXTRACTED';
    catch ME
        status = ['COMPILE_OR_EXTRACTION_FAILED: ' localOneLine(ME.message)];
    end

    if compiled
        try
            feval(mdl,[],[],[],'term');
        catch
        end
    end

    T = localCellTable(rows, ...
        {'BlockPath','PortKind','PortNumber','CompiledWidth','CompiledDimensions', ...
         'CompiledDataType','CompiledComplex','CompiledFrame','CompiledPortSampleTime', ...
         'CompiledBlockSampleTime'},[3]);
end

function localWriteSummary(path,auditInfo,blockTable,edgeTable,pcTable, ...
    functionTable,dupFunctionTable,subsystemTable,specialTable,rtlabTable, ...
    unconnTable,cleanupTable,complexityTable,errorTable,tokenCountTable)

    fid = fopen(path,'w','n','UTF-8');
    if fid<0, return; end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid,'# Full model read-only audit summary\n\n');
    fprintf(fid,'- Audit version: `%s`\n',auditInfo.Version);
    fprintf(fid,'- Time: `%s`\n',auditInfo.Time);
    fprintf(fid,'- Model: `%s`\n',auditInfo.Model);
    fprintf(fid,'- File: `%s`\n',auditInfo.ModelFile);
    fprintf(fid,'- SHA256: `%s`\n',auditInfo.ModelSHA256);
    fprintf(fid,'- SimulationStatus: `%s`\n',auditInfo.SimulationStatus);
    fprintf(fid,'- Dirty: `%s`\n',auditInfo.Dirty);
    fprintf(fid,'- FollowLinks: `%s`\n',auditInfo.FollowLinks);
    fprintf(fid,'- Compiled phase: `%s`\n\n',auditInfo.CompiledStatus);

    fprintf(fid,'## Scale\n\n');
    fprintf(fid,'- Blocks: %d\n',height(blockTable));
    fprintf(fid,'- Point-to-point line edges: %d\n',height(edgeTable));
    fprintf(fid,'- PortConnectivity records: %d\n',height(pcTable));
    fprintf(fid,'- Subsystems including root: %d\n',height(subsystemTable));
    fprintf(fid,'- MATLAB Function charts: %d\n',height(functionTable));
    fprintf(fid,'- Exact duplicate MATLAB Function groups: %d\n',height(dupFunctionTable));
    fprintf(fid,'- Special-interest blocks: %d\n',height(specialTable));
    fprintf(fid,'- RT-LAB / OPAL-related blocks: %d\n',height(rtlabTable));
    fprintf(fid,'- Unconnected-port candidates: %d\n',height(unconnTable));
    fprintf(fid,'- Cleanup review candidates: %d\n',height(cleanupTable));
    fprintf(fid,'- Audit extraction errors: %d\n\n',height(errorTable));

    fprintf(fid,'## Token counts in block paths\n\n');
    fprintf(fid,'| Token | Count |\n|---|---:|\n');
    for i = 1:height(tokenCountTable)
        if tokenCountTable.BlockPathMatchCount(i)>0
            fprintf(fid,'| `%s` | %d |\n', ...
                char(tokenCountTable.Token(i)),tokenCountTable.BlockPathMatchCount(i));
        end
    end

    fprintf(fid,'\n## Largest subsystems by descendant block count\n\n');
    if ~isempty(subsystemTable)
        tmp = sortrows(subsystemTable,'DescendantBlocks','descend');
        n = min(30,height(tmp));
        fprintf(fid,'| Path | Descendant blocks | Descendant edges | AA15 descendants | Special-interest descendants |\n');
        fprintf(fid,'|---|---:|---:|---:|---:|\n');
        for i = 1:n
            fprintf(fid,'| `%s` | %d | %d | %d | %d |\n', ...
                char(tmp.Path(i)),tmp.DescendantBlocks(i),tmp.DescendantEdges(i), ...
                tmp.AA15Descendants(i),tmp.SpecialInterestDescendants(i));
        end
    end

    fprintf(fid,'\n## Largest MATLAB Function blocks\n\n');
    if ~isempty(functionTable)
        tmp = sortrows(functionTable,'LineCount','descend');
        n = min(30,height(tmp));
        fprintf(fid,'| Path | Lines | Persistent | If | Switch | For | While |\n');
        fprintf(fid,'|---|---:|---:|---:|---:|---:|---:|\n');
        for i = 1:n
            fprintf(fid,'| `%s` | %d | %d | %d | %d | %d | %d |\n', ...
                char(tmp.BlockPath(i)),tmp.LineCount(i),tmp.PersistentCount(i),tmp.IfCount(i), ...
                tmp.SwitchCount(i),tmp.ForCount(i),tmp.WhileCount(i));
        end
    end

    fprintf(fid,'\n## Highest direct fan-out blocks\n\n');
    tmp = sortrows(blockTable,'FanOut','descend');
    n = min(30,height(tmp));
    fprintf(fid,'| Path | FanOut | FanIn | Type |\n|---|---:|---:|---|\n');
    for i = 1:n
        fprintf(fid,'| `%s` | %d | %d | `%s` |\n', ...
            char(tmp.Path(i)),tmp.FanOut(i),tmp.FanIn(i),char(tmp.BlockType(i)));
    end

    fprintf(fid,'\n## Interpretation boundary\n\n');
    fprintf(fid,['This package is evidence collection, not an automatic deletion verdict. ' ...
        'A Terminator, old-looking name, duplicate function, shadow path, diagnostic path, or ' ...
        'unconnected port is only a review candidate until source/destination/consumer semantics ' ...
        'are checked. Static Goto/From matching is explicitly marked as candidate resolution when ' ...
        'scope cannot be proven without compile-time semantics.\n']);
end

function s = localOneLine(s)
    s = char(string(s));
    s = strrep(s,sprintf('\r'),' ');
    s = strrep(s,sprintf('\n'),' ');
    if numel(s)>1000, s = [s(1:1000) '...']; end
end

function result = AUDIT_K26_K50_ESS2_RECONNECT_FINAL_PREFLIGHT_R6(modelRoot)
% AUDIT_K26_K50_ESS2_RECONNECT_FINAL_PREFLIGHT_R6
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 黑启动并回 —— 最终改模前完整只读审计 R6
%
% 审计目标：
% A. 把 ESS2 物理支路从 converter -> EV1_inv -> L2 -> C2-node ->
%    breaker -> EV1_LV_Meas -> task boundary 的三相拓扑审清；
% B. 把 ESS2_Control 真正使用的 Vabc / Iabc 来源、跨任务链、dq 变换、
%    滤波、ConnectMode 选择链审清；
% C. 把 Current Adapter 的 hold / alpha / match / state / PI 方程审清，
%    特别验证“breaker 已闭合但 state4/5 仍 hold=1”的当前事实；
% D. 把 RestoreAlpha 在 Power Loop 和 Current Adapter 中的双重作用、
%    P/Q PI 当前状态语义、未来功率恢复链审清；
% E. 把 breaker command 的 executor -> router -> SPS breaker 实际链审清；
% F. 把 G27 当前 56 通道、OpWrite 五组边界、未来必须记录而当前缺失的量审清；
% G. 输出改模设计前的 Blocker / Design-Question 矩阵，不修改模型。
%
% 模型身份规则（继承仓库永久经验）：
% - 整个 SLX raw SHA 只记录，不作为语义硬门；
% - 用户整理连线、布局、重新保存都可能改变 SLX ZIP 容器 SHA；
% - 真正硬门使用：模型名 + 关键块 + 关键当前源码语义 + 关键连接 + 接口结构。
% - 历史第四轮 SHA 只作为 provenance（来源记录）对照：
%   55b5ea9933317048ecb71fd9c60b608750f34b34edec7956ca350d9086224826
%
% 永久边界：
% - READ ONLY：不 set_param / add_block / delete_block / add_line / delete_line；
% - 不 update / compile / save_system；
% - 不连接 RT-LAB，不 Execute / Reset / Load；
% - 当前 SLX 图结构 > 历史文件；
% - UNKNOWN 保持 UNKNOWN，不猜；
% - 物理拓扑只使用 conserving PortConnectivity；
% - 普通信号只使用当前图中的真实 Src/Dst 与 Goto/From；
% - Dirty 只记录；只读审计不因用户布局整理产生的 Dirty=on 假失败；
% - 审计结束只要求 Dirty 状态与开始时完全一致。
%
% MATLAB R2023b
%
% R6 anti-rework source QA before delivery:
% - full-file physical-line char-vector scan;
% - fprintf/error/sprintf/warning call-string scan;
% - (), [], {} balance scan outside comments/char vectors;
% - bare && / || physical-line continuation scan;
% - entry function == file name;
% - duplicate local-function-name scan;
% - READ ONLY mutation-token scan;
% - raw-SHA hard-gate regression scan;
% - repository-proven OpWrite discovery regression scan.
% =========================================================================

VERSION = 'K26_K50_ESS2_RECONNECT_FINAL_PREFLIGHT_R6_20260914';
MODEL = 'K26_K50_CLEAN_P1';
HISTORICAL_R4_SHA = '55b5ea9933317048ecb71fd9c60b608750f34b34edec7956ca350d9086224826';
SHA_POLICY = 'RECORD_ONLY_NOT_A_SEMANTIC_HARD_GATE';

if nargin < 1 || isempty(modelRoot)
    modelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot = canonicalPath(char(modelRoot));
modelFile = fullfile(modelRoot,[MODEL '.slx']);

if ~isfile(modelFile)
    error('E2AUD6:ModelMissing','Current model file missing: %s',modelFile);
end

sourceSha = sha256File(modelFile);
rawShaMatchesHistoricalR4 = strcmpi(sourceSha,HISTORICAL_R4_SHA);
% IMPORTANT:
% raw SHA mismatch is NOT a blocker. The project has already proven that
% harmless save/layout/repack operations can change the SLX ZIP-container SHA.
% Semantic identity is established below from the actual current graph/code.

stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
outDir = fullfile(modelRoot,['AUDIT_ESS2_RECONNECT_FINAL_PREFLIGHT_R6_' stamp]);
mkdir(outDir);
summaryFile = fullfile(outDir,'00_READ_FIRST.txt');
fid = fopen(summaryFile,'w','n','UTF-8');
if fid < 0
    error('E2AUD6:Output','Cannot create summary: %s',summaryFile);
end
fidCleanup = onCleanup(@()safeClose(fid)); %#ok<NASGU>

result = struct();
result.version = VERSION;
result.modelFile = modelFile;
result.sourceSha256 = sourceSha;
result.historicalR4Sha256 = HISTORICAL_R4_SHA;
result.rawShaMatchesHistoricalR4 = rawShaMatchesHistoricalR4;
result.shaPolicy = SHA_POLICY;
result.outputDirectory = outDir;
result.status = 'STARTED';

fprintf(fid,'ESS2 黑启动并回：控制 / 功率恢复最终改模前完整只读审计 R6\n');
fprintf(fid,'Version : %s\n',VERSION);
fprintf(fid,'Model   : %s\n',modelFile);
fprintf(fid,'当前 raw SHA256 : %s\n',sourceSha);
fprintf(fid,'历史 R4 raw SHA  : %s\n',HISTORICAL_R4_SHA);
fprintf(fid,'raw SHA 是否一致 : %s\n',yesno(rawShaMatchesHistoricalR4));
fprintf(fid,'SHA策略           : %s\n',SHA_POLICY);
fprintf(fid,'说明：raw SHA 仅作来源记录；真正身份门由后续当前模型语义/连接审计承担。\n\n');

wasLoaded = bdIsLoaded(MODEL);
loadedFile='';
if wasLoaded
    try
        rawLoadedFile=get_param(MODEL,'FileName');
        if ~isempty(rawLoadedFile),loadedFile=canonicalPath(rawLoadedFile);end
    catch
    end
    % Read-only audit follows the CURRENT loaded semantic graph. Different raw
    % path is recorded, not treated as an automatic failure; semantic preflight
    % below is the real identity gate.
else
    load_system(modelFile);
    loadedFile=canonicalPath(get_param(MODEL,'FileName'));
end
closeCleanup = onCleanup(@()closeIfOwned(MODEL,wasLoaded)); %#ok<NASGU>

dirtyAtStart=get_param(MODEL,'Dirty');
fprintf(fid,'Loaded model file : %s\n',ternary(isempty(loadedFile),'UNRESOLVED',loadedFile));
fprintf(fid,'Dirty at start    : %s（只记录；只读审计不会修改）\n\n',dirtyAtStart);

% =========================================================================
% 0. Exact path inventory
% =========================================================================
SM = [MODEL '/SM_Master'];
SS2 = [MODEL '/SS_Slave2'];
control = [SS2 '/ESS2_Control'];
meas = [control '/Measurements'];
power = [control '/Power Control Loop'];
wrapper = [control '/AA15_GFL_ISLAND_SUPPORT'];
adapter = [wrapper '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];
adapterCore = [adapter '/CORE'];

cfgSub = [SS2 '/AA15_ESS2_RESTORE_CONFIG'];
executor = [SS2 '/AA15_ESS2_RESTORE_EXECUTOR'];
executorCore = [executor '/CORE'];
executorDemux = [SS2 '/AA15_ESS2_RESTORE_EXECUTOR_DEMUX'];
router = [SS2 '/AA15_ESS2_RESTORE_BREAKER_ROUTER'];
breaker = [SS2 '/AA15_DIAG_AC_BREAKER_ESS2'];

converter = [SS2 '/ESS2_Converter'];
mInv = [SS2 '/EV1_inv'];
L2 = [SS2 '/L2'];
C2 = [SS2 '/C2'];
mBus = [SS2 '/EV1_LV_Meas'];

prim = [SM '/prim_ESS2'];
essMux = [SM '/ESS2_IO_Mux12'];
essGroupMux = [SM '/ESS_Group_Mux24'];
essMem = [SM '/ESS_IO_Memory24'];
opComm = [SS2 '/OpComm_ESS_Group'];
essGroupDemux = [SS2 '/ESS_Group_Demux'];
ess2Demux = [SS2 '/ESS2_IO_Demux'];

g27 = [SS2 '/AA15_ROOTDIAG_ESS2_OPWRITE_G27'];
g27Repack = [SS2 '/AA15_ESS2_RESTORE_G27_REPACK'];
g27Norm = [SS2 '/AA15_ESS2_RESTORE_G27_VECTOR_NORMALIZER'];

critical = {SM,SS2,control,meas,power,wrapper,adapter,adapterCore, ...
    cfgSub,executor,executorCore,executorDemux,router,breaker, ...
    converter,mInv,L2,C2,mBus,prim,essMux,essGroupMux,essMem,opComm, ...
    essGroupDemux,ess2Demux,g27,g27Repack,g27Norm};

for k=1:numel(critical),mustBlock(critical{k});end

% -------------------------------------------------------------------------
% 当前模型语义身份硬门
% 不依赖 whole-SLX raw SHA；直接核对当前黑启动恢复样机的关键结构。
% -------------------------------------------------------------------------
semanticIdentityRows = {
    'ModelName',strcmp(get_param(MODEL,'Name'),MODEL),get_param(MODEL,'Name'),'K26_K50_CLEAN_P1';
    'ESS2RestoreExecutorPresent',getSimulinkBlockHandle(executor)>0,executor,'must exist';
    'ESS2RestoreRouterPresent',getSimulinkBlockHandle(router)>0,router,'must exist';
    'ESS2CurrentAdapterPresent',getSimulinkBlockHandle(adapterCore)>0,adapterCore,'must exist';
    'G27RepackPresent',getSimulinkBlockHandle(g27Repack)>0,g27Repack,'must exist';
    'G27VectorNormalizerPresent',getSimulinkBlockHandle(g27Norm)>0,g27Norm,'must exist';
    };

semOut=cell(size(semanticIdentityRows,1),5);
for k=1:size(semanticIdentityRows,1)
    semOut(k,:)={semanticIdentityRows{k,1},semanticIdentityRows{k,2}, ...
        semanticIdentityRows{k,3},semanticIdentityRows{k,4}, ...
        passFail(logical(semanticIdentityRows{k,2}))};
end
writeMixedCsv(fullfile(outDir,'00A_SEMANTIC_IDENTITY_PREFLIGHT.csv'), ...
    {'Item','Observed','PathOrValue','Expected','Status'},semOut);

if ~all(cell2mat(semanticIdentityRows(:,2)))
    error('E2AUD6:SemanticIdentity', ...
        '当前模型缺少 ESS2 恢复样机关键结构；这才是身份硬门，审计停止。');
end

identityRows = {
    'ModelFile',modelFile,'当前用户指定 K26_K50_CLEAN_P1','PASS';
    'CurrentRawSHA256',sourceSha,'仅记录，不作语义硬门','INFO';
    'HistoricalR4RawSHA256',HISTORICAL_R4_SHA,'仅作历史来源对照','INFO';
    'RawSHAMatchesHistoricalR4',yesno(rawShaMatchesHistoricalR4), ...
        '不同也不阻止审计','INFO';
    'SHAIdentityPolicy',SHA_POLICY,'语义结构才是硬门','PASS';
    'MATLABVersion',version,'R2023b expected','INFO';
    'ModelDirtyAtStart',dirtyAtStart,'record only; must be unchanged at end','INFO';
    'FixedStep',safeGet(MODEL,'FixedStep'),'100 us project baseline','INFO';
    'SolverType',safeGet(MODEL,'SolverType'),'fixed-step project baseline','INFO';
    };
writeMixedCsv(fullfile(outDir,'01_IDENTITY_AND_MODEL_BOUNDARY.csv'), ...
    {'Item','Observed','ExpectedOrMeaning','Status'},identityRows);

% =========================================================================
% 1. Physical branch graph: conserving ports only
% =========================================================================
phys = {converter,mInv,L2,C2,breaker,mBus};
physRows = cell(0,9);
for k=1:numel(phys)
    b=phys{k};
    ph=get_param(b,'PortHandles');
    physRows(end+1,:)={ ...
        b,safeGet(b,'SourceType'),safeGet(b,'ReferenceBlock'), ...
        numel(ph.LConn),numel(ph.RConn), ...
        safeGet(b,'Measurements'),safeGet(b,'Position'), ...
        conservingConnectivityText(b),blockConnectivityText(b)}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'02_ESS2_PHYSICAL_BRANCH_GRAPH.csv'), ...
    {'Block','SourceType','ReferenceBlock','LConn','RConn','Measurements', ...
     'Position','ConservingConnectivity','AllPortConnectivity'},physRows);

% Hard current-source topology facts. These are based on the exact saved model.
cConv = conservingConnectivityText(converter);
cInv = conservingConnectivityText(mInv);
cL2 = conservingConnectivityText(L2);
cC2 = conservingConnectivityText(C2);
cBr = conservingConnectivityText(breaker);
cBus = conservingConnectivityText(mBus);

topologyFacts = {
    'Converter_to_EV1inv',contains(cConv,mInv),[converter ' <-> ' mInv];
    'EV1inv_to_L2',contains(cInv,L2),[mInv ' <-> ' L2];
    'L2_to_C2node',contains(cL2,C2),[L2 ' shares C2 external node'];
    'C2node_to_Breaker',contains(cC2,breaker),[C2 ' shares breaker one side'];
    'Breaker_to_EV1LVMeas',contains(cBr,mBus),[breaker ' <-> ' mBus];
    'EV1inv_not_C2node',~contains(cInv,C2),'first sensor is converter/L2-before sensor';
    'EV1LVMeas_not_C2node_direct',~contains(cBus,C2),'second sensor is opposite side of breaker';
    };
physicalOK = all(cell2mat(topologyFacts(:,2)));
topRows=cell(size(topologyFacts,1),5);
for k=1:size(topologyFacts,1)
    topRows(k,:)={topologyFacts{k,1},topologyFacts{k,2},true, ...
        passFail(logical(topologyFacts{k,2})),topologyFacts{k,3}};
end
writeMixedCsv(fullfile(outDir,'03_PHYSICAL_NODE_ASSERTIONS.csv'), ...
    {'Fact','Observed','Expected','Status','Meaning'},topRows);

% C2 measurement capability and all dialog parameters for branch blocks.
paramBlocks={prim,breaker,L2,C2,mInv,mBus,opComm,g27};
for k=1:numel(paramBlocks)
    writeDialogParameters(fullfile(outDir,sprintf('PARAMS_%02d_%s.csv',k,sanitizeName(get_param(paramBlocks{k},'Name')))), ...
        paramBlocks{k});
end

c2Meas = strtrim(safeGet(C2,'Measurements'));
c2Direct = ~(isempty(c2Meas) || strcmpi(c2Meas,'None') || strcmpi(c2Meas,'off') || strcmpi(c2Meas,'UNKNOWN'));

fprintf(fid,'[1] ESS2 physical branch conserving topology:\n');
fprintf(fid,'    Converter -> EV1_inv -> L2 -> C2 external node -> Breaker -> EV1_LV_Meas.\n');
fprintf(fid,'    C2 Measurements = %s; direct C2-node signal available now? %s\n\n',c2Meas,yesno(c2Direct));

% =========================================================================
% 2. SM -> SS2 measurement/control transport chain
% =========================================================================
% ESS2_IO_Mux12 input 1/2 must resolve to prim_ESS2 Vabc/Iabc.
muxRows=cell(0,9);
phMux=get_param(essMux,'PortHandles');
for k=1:numel(phMux.Inport)
    [src,srcPort]=portSource(phMux.Inport(k));
    tag=''; upstream=''; upstreamPort=NaN;
    if getSimulinkBlockHandle(src)>=0 && strcmp(safeGet(src,'BlockType'),'From')
        tag=safeGet(src,'GotoTag');
        [upstream,upstreamPort]=resolveFromUltimateSource(src,SM);
    end
    muxRows(end+1,:)={k,src,srcPort,tag,upstream,upstreamPort, ...
        ess2MuxMeaningCurrent(k),safeGet(src,'BlockType'),safeGet(src,'Position')}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'04_ESS2_SM_IO12_EXACT_MAPPING.csv'), ...
    {'MuxInput','DirectSource','DirectSourcePort','GotoTag','ResolvedUltimateSource', ...
     'UltimateSourcePort','Meaning','SourceBlockType','Position'},muxRows);

if size(muxRows,1)<2 || ~strcmp(muxRows{1,5},prim) || muxRows{1,6}~=1 || ...
        ~strcmp(muxRows{2,5},prim) || muxRows{2,6}~=2
    error('E2AUD6:PrimRoute', ...
        'ESS2_IO_Mux12 Vabc/Iabc inputs do not resolve exactly to prim_ESS2 outputs 1/2.');
end

% ESS2_Control parent-port contract.
% Do NOT search Inport blocks by display Name. Repository experience showed
% names/layout can drift while the actual subsystem port contract remains exact.
% Audit by Port number + current SrcBlock/SrcPort, then list the internal
% Inport block (if any) only as descriptive metadata.
phControl=get_param(control,'PortHandles');
controlPortCountOK=(numel(phControl.Inport)==10);

controlExpected = {
    1,'Vabc',ess2Demux,1,'SM prim_ESS2 Vabc via ESS2_IO_Demux';
    2,'Iabc',ess2Demux,2,'SM prim_ESS2 Iabc via ESS2_IO_Demux';
    3,'Fref',ess2Demux,3,'Fref / master-frequency transport';
    4,'Vref',ess2Demux,4,'Vref transport';
    5,'统一阶段_经原Droop端口',ess2Demux,5,'S14 stage echo carried on legacy scalar port';
    6,'Pref',ess2Demux,6,'active-power request';
    7,'Qref',ess2Demux,7,'reactive-power request';
    8,'GRIDON',ess2Demux,8,'GFL/GFM execution-mode command';
    9,'恢复系数_RestoreAlpha',executorDemux,3,'restore alpha from executor y3';
    10,'恢复保持_RestoreHold',executorDemux,2,'restore hold from executor y2';
    };

controlRows=cell(0,10);
controlPortFacts=false(10,1);
for k=1:10
    if k>numel(phControl.Inport)
        controlRows(end+1,:)={k,controlExpected{k,2},'MISSING_PARENT_PORT','', ...
            'MISSING_PARENT_PORT',NaN,controlExpected{k,3},controlExpected{k,4}, ...
            'FAIL',controlExpected{k,5}}; %#ok<AGROW>
        continue;
    end
    [srcBlock,srcPort]=portSource(phControl.Inport(k));
    ib=findTopPortBlock(control,'Inport',k);
    if isempty(ib)
        inName='NO_TOPLEVEL_INPORT_BLOCK';
        inPath='NO_TOPLEVEL_INPORT_BLOCK';
    else
        inName=get_param(ib,'Name');
        inPath=ib;
    end
    expSrc=controlExpected{k,3};
    expPort=controlExpected{k,4};
    ok=strcmp(srcBlock,expSrc) && isequaln(srcPort,expPort);
    controlPortFacts(k)=ok;
    controlRows(end+1,:)={ ...
        k,controlExpected{k,2},inName,inPath, ...
        srcBlock,srcPort,expSrc,expPort,passFail(ok),controlExpected{k,5}}; %#ok<AGROW>
end

writeMixedCsv(fullfile(outDir,'05_ESS2_CONTROL_PARENT_PORT_CONTRACT.csv'), ...
    {'Port','Semantic_CN','InternalInportName','InternalInportPath', ...
     'ObservedSource','ObservedSourcePort','ExpectedSource','ExpectedSourcePort', ...
     'Status','Meaning'},controlRows);

if ~controlPortCountOK || ~all(controlPortFacts)
    fprintf(fid,'[WARN] ESS2_Control parent-port contract has unresolved/mismatched items. See 05_ESS2_CONTROL_PARENT_PORT_CONTRACT.csv.\n');
end

% Cross-task chain blocks and their current widths/sample-related properties.
transportRows = {
    essGroupMux,safeGet(essGroupMux,'Inputs'),safeGet(essGroupMux,'SampleTime'),'SM group pack';
    essMem,safeGet(essMem,'InitialCondition'),safeGet(essMem,'SampleTime'),'SM boundary Memory';
    opComm,safeGet(opComm,'Threshold'),safeGet(opComm,'SampleTime'),'RT-LAB OpComm';
    essGroupDemux,safeGet(essGroupDemux,'Outputs'),safeGet(essGroupDemux,'SampleTime'),'SS2 group unpack';
    ess2Demux,safeGet(ess2Demux,'Outputs'),safeGet(ess2Demux,'SampleTime'),'ESS2 IO unpack';
    };
writeMixedCsv(fullfile(outDir,'06_SM_TO_SS2_TRANSPORT_BLOCKS.csv'), ...
    {'Block','WidthOrKeyValue','SampleTime','Role'},transportRows);

% prim_ESS2 physical side.
primRows = {
    'prim_ESS2',prim,safeGet(prim,'VoltageMeasurement'),safeGet(prim,'CurrentMeasurement'), ...
        safeGet(prim,'Vpu'),safeGet(prim,'Ipu'),blockConnectivityText(prim), ...
        'lconn connects E5_TrA/B/C; rconn connects ESS2_Line in current saved model';
    };
writeMixedCsv(fullfile(outDir,'07_PRIM_ESS2_MEASUREMENT_POINT.csv'), ...
    {'Item','Path','VoltageMeasurement','CurrentMeasurement','Vpu','Ipu','Connectivity','Meaning'},primRows);

% =========================================================================
% 3. Measurements -> dq -> Goto/From -> selector -> Current Adapter
% =========================================================================
% This section closes the R3 gaps. It reuses the repository's successful
% PLL/frame audit philosophy:
%   - print REAL Goto/From tags from the current graph;
%   - print REAL top-level Switch sources/criteria;
%   - do not infer a selected path from a block name;
%   - From is never treated as an ultimate source.

measOutNames={'VdVq_meas','IdIq_meas','P_meas','Q_meas', ...
    'VdVq_measPLL','IdIq_measPLL','P_meas_PLL','Q_meas_PLL', ...
    'wt_PLL','Freq_PLL','wt_PLL_EXEC','Freq_PLL_EXEC'};

measRows=cell(0,10);
for k=1:numel(measOutNames)
    nm=measOutNames{k};
    ob=find_system(meas,'SearchDepth',1,'BlockType','Outport','Name',nm);
    if numel(ob)~=1
        measRows(end+1,:)={nm,'NOT_UNIQUE',numel(ob),'','','','','','',''}; %#ok<AGROW>
        continue;
    end
    ph=get_param(ob{1},'PortHandles');
    [srcBlock,srcPort]=portSource(ph.Inport(1));
    measRows(end+1,:)={nm,ob{1},str2double(safeGet(ob{1},'Port')), ...
        srcBlock,srcPort,safeGet(srcBlock,'SourceType'), ...
        safeGet(srcBlock,'FilterType'),safeGet(srcBlock,'Fo'), ...
        safeGet(srcBlock,'Ts'),blockConnectivityText(srcBlock)}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'08_MEASUREMENT_OUTPUT_SOURCE_CHAIN.csv'), ...
    {'OutputName','OutportBlock','Port','DirectSource','SourcePort','SourceType', ...
     'FilterType','Fo','Ts','Connectivity'},measRows);

% Exact filter settings for native/current dq measurements.
idOut=find_system(meas,'SearchDepth',1,'BlockType','Outport','Name','IdIq_meas');
idPLL=find_system(meas,'SearchDepth',1,'BlockType','Outport','Name','IdIq_measPLL');
if numel(idOut)~=1 || numel(idPLL)~=1
    error('E2AUD6:IdIqOutputs','IdIq_meas / IdIq_measPLL Outports are not unique.');
end
phId=get_param(idOut{1},'PortHandles');
phIdPLL=get_param(idPLL{1},'PortHandles');
[srcId,~]=portSource(phId.Inport(1));
[srcIdPLL,~]=portSource(phIdPLL.Inport(1));

filterRows = {
    'IdIq_meas',srcId,safeGet(srcId,'FilterType'),safeGet(srcId,'Fo'), ...
        resolveScalar(MODEL,safeGet(srcId,'Fo')),safeGet(srcId,'Zeta'), ...
        safeGet(srcId,'Ts'),resolveScalar(MODEL,safeGet(srcId,'Ts'));
    'IdIq_measPLL',srcIdPLL,safeGet(srcIdPLL,'FilterType'),safeGet(srcIdPLL,'Fo'), ...
        resolveScalar(MODEL,safeGet(srcIdPLL,'Fo')),safeGet(srcIdPLL,'Zeta'), ...
        safeGet(srcIdPLL,'Ts'),resolveScalar(MODEL,safeGet(srcIdPLL,'Ts'));
    };
writeMixedCsv(fullfile(outDir,'09_CURRENT_DQ_FILTER_SETTINGS.csv'), ...
    {'Signal','FilterBlock','FilterType','FoRaw','FoResolvedHz','Zeta','TsRaw','TsResolvedS'},filterRows);

% Current control wrapper source contract: R3 found From24/From26/From28.
% R4 resolves every From to its unique Goto and recursively walks upstream.
routeSpecs = {
    '电流实际反馈_CURRENT_FEEDBACK',[control '/From28'];
    '电流参考_CURRENT_REFERENCE',[control '/From24'];
    '电压前馈_VOLTAGE_FEEDFORWARD',[control '/From26'];
    };

routeSummary=cell(0,10);
routeClosed=false(size(routeSpecs,1),1);
routeTraceFiles=cell(size(routeSpecs,1),1);

for k=1:size(routeSpecs,1)
    label=routeSpecs{k,1};
    fromBlock=routeSpecs{k,2};
    mustBlock(fromBlock);
    [route,traceRows,routeIssues]=auditFromRoute(fromBlock,control,20);
    routeClosed(k)=isempty(routeIssues) && route.uniqueGoto && route.traceHasTerminal;
    routeSummary(end+1,:)={ ...
        label,fromBlock,route.tag,route.gotoPath,route.gotoInputSource, ...
        route.gotoInputSourcePort,route.firstSemanticAnchor, ...
        strjoin(routeIssues,' | '),passFail(routeClosed(k)), ...
        route.traceTerminalSummary}; %#ok<AGROW>
    fn=fullfile(outDir,sprintf('10%c_%s_TRACE.csv',char('A'+k-1),sanitizeName(label)));
    writeMixedCsv(fn,traceHeaders(),traceRows);
    routeTraceFiles{k}=fn;
end

writeMixedCsv(fullfile(outDir,'10_ROUTE_SUMMARY_From28_From24_From26.csv'), ...
    {'Route','FromBlock','GotoTag','ResolvedGoto','GotoInputSource','GotoInputSourcePort', ...
     'FirstSemanticAnchor','Issues','Status','TerminalSummary'},routeSummary);

% Full top-level Goto/From map, following the proven PLL/frame audit style.
allGoto=find_system(control,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
allFrom=find_system(control,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','BlockType','From');
tagSet={};
for k=1:numel(allGoto),tagSet{end+1}=safeGet(allGoto{k},'GotoTag');end %#ok<AGROW>
for k=1:numel(allFrom),tagSet{end+1}=safeGet(allFrom{k},'GotoTag');end %#ok<AGROW>
tagSet=unique(tagSet,'stable');
tagRows=cell(0,8);
for k=1:numel(tagSet)
    tag=tagSet{k};
    if isempty(tag),continue;end
    gs=findByGotoTag(allGoto,tag);
    fs=findByGotoTag(allFrom,tag);
    gsrc='';
    if numel(gs)==1
        phg=get_param(gs{1},'PortHandles');
        [sb,sp]=portSource(phg.Inport(1));
        gsrc=sprintf('%s#out:%s',sb,valueText(sp));
    end
    ftxt=strjoin(fs,' | ');
    gtxt=strjoin(gs,' | ');
    tagRows(end+1,:)={tag,numel(gs),gtxt,gsrc,numel(fs),ftxt, ...
        ternary(numel(gs)==1,'UNIQUE_GOTO','NONUNIQUE_OR_MISSING'), ...
        ternary(numel(gs)==1,'current graph resolvable','inspect candidates')}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'10E_TOPLEVEL_GOTO_FROM_MAP.csv'), ...
    {'GotoTag','GotoCount','GotoPaths','GotoInputSource','FromCount','FromPaths','Status','Meaning'},tagRows);

% Top-level Switch map. This is the exact ConnectMode/GRIDON selector evidence.
switches=find_system(control,'SearchDepth',1,'BlockType','Switch');
switchRows=cell(0,12);
for k=1:numel(switches)
    b=switches{k};
    ph=get_param(b,'PortHandles');
    if numel(ph.Inport)<3,continue;end
    [u1,p1]=portSource(ph.Inport(1));
    [u2,p2]=portSource(ph.Inport(2));
    [u3,p3]=portSource(ph.Inport(3));
    switchRows(end+1,:)={ ...
        b,safeGet(b,'Criteria'),safeGet(b,'Threshold'), ...
        u1,p1,signalSemanticAtOutput(u1,p1), ...
        u2,p2,signalSemanticAtOutput(u2,p2), ...
        u3,p3,signalSemanticAtOutput(u3,p3)}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'10F_TOPLEVEL_SWITCH_SELECTOR_MAP.csv'), ...
    {'Switch','Criteria','Threshold','U1Source','U1Port','U1Semantic', ...
     'U2ControlSource','U2Port','U2Semantic','U3Source','U3Port','U3Semantic'},switchRows);

% Wrapper parent input sources, then exact adapter parent/core maps are audited below.
wrapperMeasSource = sourceToWrapperInput(wrapper,'IdIq_meas');
wrapperRefSource = sourceToWrapperInput(wrapper,'IdIq_ref');
wrapperVffSource = sourceToWrapperInput(wrapper,'RawVdq');
feedbackRows = {
    'Wrapper_IdIq_meas',wrapperMeasSource,'must correspond to the resolved From28 route';
    'Wrapper_IdIq_ref',wrapperRefSource,'must correspond to the resolved From24 route';
    'Wrapper_RawVdq',wrapperVffSource,'must correspond to the resolved From26 route';
    };
writeMixedCsv(fullfile(outDir,'11_CURRENT_ADAPTER_EXTERNAL_SOURCES.csv'), ...
    {'Item','ObservedSource','Meaning'},feedbackRows);

wrapperInterfaceRows=auditSubsystemInterface(wrapper);
writeMixedCsv(fullfile(outDir,'11A_GFL_WRAPPER_INTERFACE.csv'), ...
    {'Direction','Port','InternalPortBlock','PortName','ExternalBlock','ExternalPort', ...
     'ExternalSemantic','Status'},wrapperInterfaceRows);

if ~all(routeClosed)
    % Do not abort here. Repository anti-rework rule: collect every remaining
    % audit blocker in the same run; final readiness will report all of them.
    fprintf(fid,'[WARN] One or more key Goto/From routes are not fully closed. All trace files were still generated.\n');
end

% =========================================================================
% 4. Current Adapter exact code, state and match semantics
% =========================================================================
adapterScript=emChartScript(adapterCore);
writeText(fullfile(outDir,'12_CURRENT_ADAPTER_CORE_CURRENT_SOURCE.mtxt'),adapterScript);
adapterHash=hashText(adapterScript);

tokens = {
    'hold=double(hold>0.5)',containsNoSpace(adapterScript,'hold=double(hold>0.5)');
    'iref_used=zeros(2,1)',containsNoSpace(adapterScript,'iref_used=zeros(2,1)');
    'imeas_used=zeros(2,1)',containsNoSpace(adapterScript,'imeas_used=zeros(2,1)');
    'match=1.0 in hold',containsNoSpace(adapterScript,'match=1.0');
    'matchTarget=zeros(2,1)',containsNoSpace(adapterScript,'matchTarget=zeros(2,1)');
    'iref_used=a*iref',containsNoSpace(adapterScript,'iref_used=a*iref');
    'imeas_used=imeas',containsNoSpace(adapterScript,'imeas_used=imeas');
    'match=double(z(4)<0.5)',containsNoSpace(adapterScript,'match=double(z(4)<0.5)');
    'iref-imeas',containsNoSpace(adapterScript,'iref-imeas');
    'xunc=matchOutput-kp*error',containsNoSpace(adapterScript,'xunc=matchOutput-kp*error');
    'normal integration branch',containsNoSpace(adapterScript,'xunc=w+h');
    };

tokenRows=cell(size(tokens,1),5);
for k=1:size(tokens,1)
    tokenRows(k,:)={tokens{k,1},tokens{k,2},true,passFail(tokens{k,2}), ...
        ternary(tokens{k,2},'current source contains expected audited semantic','missing semantic token')};
end
writeMixedCsv(fullfile(outDir,'13_CURRENT_ADAPTER_SEMANTIC_TOKENS.csv'), ...
    {'Semantic','Observed','Expected','Status','Note'},tokenRows);

if ~all(cell2mat(tokens(:,2)))
    error('E2AUD6:AdapterSemantic','Current Adapter semantic tokens are not all present.');
end

% Adapter state block / ports.
stateBlock=[adapter '/STATE'];
mustBlock(stateBlock);
stateRows = {
    stateBlock,safeGet(stateBlock,'BlockType'),safeGet(stateBlock,'InitialCondition'), ...
        safeGet(stateBlock,'SampleTime'),blockConnectivityText(stateBlock);
    };
writeMixedCsv(fullfile(outDir,'14_CURRENT_ADAPTER_STATE_BLOCK.csv'), ...
    {'Block','BlockType','InitialCondition','SampleTime','Connectivity'},stateRows);

% Closed-zero theoretical semantics using EXISTING code:
% hold=0, alpha=0 -> iref_used=0, imeas_used=real, match only if z(4)<0.5.
closedZeroFacts = {
    '断开待并_OPEN_STANDBY_hold1_irefUsedZero',true,'hold=1 => iref_used=0';
    '断开待并_OPEN_STANDBY_hold1_imeasUsedZero',true,'hold=1 => imeas_used=0';
    '断开待并_OPEN_STANDBY_hold1_matchEveryStep',true,'hold=1 => match=1 each call';
    '闭合后零电流主动调节_CLOSED_ZERO_CURRENT_ACTIVE_irefUsedZero',true,'else branch a=0 => iref_used=0';
    '闭合后零电流主动调节_CLOSED_ZERO_CURRENT_ACTIVE_imeasReal',true,'else branch => imeas_used=imeas';
    '闭合后零电流主动调节_CLOSED_ZERO_CURRENT_ACTIVE_matchNotPersistent',true,'else branch match only if z(4)<0.5';
    };
closedRows=cell(size(closedZeroFacts,1),5);
for k=1:size(closedZeroFacts,1)
    closedRows(k,:)={closedZeroFacts{k,1},closedZeroFacts{k,2},true,'PASS',closedZeroFacts{k,3}};
end
writeMixedCsv(fullfile(outDir,'15_EXISTING_CODE_CLOSED_ZERO_CAPABILITY.csv'), ...
    {'Fact','Observed','Expected','Status','Meaning'},closedRows);

% -------------------------------------------------------------------------
% 4B. Current Adapter exact parent/core port map + oldpi + state loop
% -------------------------------------------------------------------------
% CORE signature is current source truth:
%   fcn(vff,imeas,iref,vdc,oldpi,z,hold,alpha)
adapterCoreSem={'vff','imeas','iref','vdc','oldpi','z_state','hold','alpha'};
corePortRows=cell(0,9);
phCore=get_param(adapterCore,'PortHandles');
if numel(phCore.Inport)~=8
    error('E2AUD6:AdapterCorePortCount','Current Adapter CORE expected 8 inports, got %d.',numel(phCore.Inport));
end
for k=1:8
    [sb,sp]=portSource(phCore.Inport(k));
    corePortRows(end+1,:)={k,adapterCoreSem{k},sb,sp, ...
        safeGet(sb,'BlockType'),safeGet(sb,'GotoTag'), ...
        signalSemanticAtOutput(sb,sp),safeGet(sb,'Position'), ...
        blockConnectivityText(sb)}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'15A_CURRENT_ADAPTER_CORE_INPUT_MAP.csv'), ...
    {'CoreInput','Semantic','Source','SourcePort','SourceBlockType','GotoTag', ...
     'SourceSemantic','Position','Connectivity'},corePortRows);

% Adapter subsystem parent inports, including oldpi.
adapterParentRows=cell(0,9);
phAdapter=get_param(adapter,'PortHandles');
adapterInBlocks=find_system(adapter,'SearchDepth',1,'BlockType','Inport');
for k=1:numel(phAdapter.Inport)
    ib=findTopPortBlock(adapter,'Inport',k);
    if isempty(ib),inName='NO_TOPLEVEL_INPORT_BLOCK';else,inName=get_param(ib,'Name');end
    [sb,sp]=portSource(phAdapter.Inport(k));
    adapterParentRows(end+1,:)={k,inName,sb,sp,safeGet(sb,'BlockType'), ...
        safeGet(sb,'GotoTag'),signalSemanticAtOutput(sb,sp),safeGet(sb,'Position'), ...
        blockConnectivityText(sb)}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'15B_CURRENT_ADAPTER_PARENT_INPUT_MAP.csv'), ...
    {'AdapterInput','InternalInportName','ParentSource','SourcePort','SourceBlockType', ...
     'GotoTag','SourceSemantic','Position','Connectivity'},adapterParentRows);

% Resolve oldpi route from adapter input5, independent of display name.
oldpiSource='UNRESOLVED'; oldpiSourcePort=NaN;
if numel(phAdapter.Inport)>=5
    [oldpiSource,oldpiSourcePort]=portSource(phAdapter.Inport(5));
end
[oldpiTrace,oldpiIssues]=traceOutputUpstream(oldpiSource,oldpiSourcePort,control,20);
writeMixedCsv(fullfile(outDir,'15C_OLDPI_UPSTREAM_TRACE.csv'),traceHeaders(),oldpiTrace);

% Exact state feedback loop.
stateLoopA=directConnectionExists(adapterCore,2,stateBlock,1);
stateLoopB=directConnectionExists(stateBlock,1,adapterCore,6);
stateLoopRows = {
    adapterCore,2,stateBlock,1,stateLoopA,passFail(stateLoopA),'CORE zn output2 -> STATE UnitDelay input';
    stateBlock,1,adapterCore,6,stateLoopB,passFail(stateLoopB),'STATE UnitDelay output -> CORE z input6';
    };
writeMixedCsv(fullfile(outDir,'15D_CURRENT_ADAPTER_STATE_LOOP.csv'), ...
    {'Source','SourcePort','Destination','DestinationPort','ObservedDirect','Status','Meaning'},stateLoopRows);

% Parse the exact cfg vector from current Adapter source and derive the first
% sample after leaving hold. This is math from the saved source, not a guess.
[cfgVec,cfgParseIssue]=parseAdapterCfgVector(adapterScript);
handoverRows=cell(0,6);
if isempty(cfgParseIssue)
    TsA=cfgVec(1); KpA=cfgVec(2); KiA=cfgVec(3); TtrackA=cfgVec(8);
    halfKiTs=0.5*KiA*TsA;
    trackAlpha=1-exp(-TsA/TtrackA);
    handoverRows(end+1,:)={'Ts',TsA,'s','','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'Kp',KpA,'','','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'Ki',KiA,'1/s','','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'TrackAlphaPerSample',trackAlpha,'', ...
        '1-exp(-Ts/Ttrack)','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'HalfKiTs',halfKiTs,'', ...
        '0.5*Ki*Ts','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'HoldSteadyState','zI=0,z4=1', ...
        'from match=1,target=0,error=0 each valid hold sample', ...
        'oldpi is NOT used on hold exit because z4 already initialized','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'FirstClosedZeroError','error=-imeas', ...
        'hold=0,alpha=0 => iref_used=0, imeas_used=real', ...
        'current PI immediately regains correction authority','',''}; %#ok<AGROW>
    handoverRows(end+1,:)={'FirstClosedZeroRawPI', ...
        sprintf('raw ≈ %.6g*(-Imeas) + %.6g*residualPrev (before limits, zI≈0)', ...
        KpA+halfKiTs,trackAlpha), ...
        'exact source equation includes residual tracking and limits', ...
        'this quantifies the first-sample takeover step','',''}; %#ok<AGROW>
else
    handoverRows(end+1,:)={'CFG_PARSE_FAILED','NaN','',cfgParseIssue,'',''}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'15E_HOLD_EXIT_FIRST_SAMPLE_MATH.csv'), ...
    {'Item','ObservedOrDerived','Unit','EquationOrMeaning','Extra1','Extra2'},handoverRows);

adapterHandoverClosed = isempty(cfgParseIssue) && isempty(oldpiIssues) && ...
    stateLoopA && stateLoopB;

% =========================================================================
% 5. Restore Executor exact state/hold/breaker semantics
% =========================================================================
execScript=emChartScript(executorCore);
writeText(fullfile(outDir,'16_RESTORE_EXECUTOR_CORE_CURRENT_SOURCE.mtxt'),execScript);
execHash=hashText(execScript);

execTokens = {
    'state3_to_state4_on_commit',containsNoSpace(execScript,'state=4;postCount=0');
    'state4_breaker_closed',containsNoSpace(execScript,'elseifstate==4') && containsNoSpace(execScript,'breakerCmd=1');
    'state4_waits_postOK',containsNoSpace(execScript,'ifpostOK>0.5');
    'state5_connected_zero',containsNoSpace(execScript,'elseifstate==5');
    'state6_release',containsNoSpace(execScript,'elseifstate==6');
    'state7_restored',containsNoSpace(execScript,'elseifstate==7');
    'hold_on_states_le_5',containsNoSpace(execScript,'ifstate<=5||state==9,hold=1');
    'hold_off_states_6_7',containsNoSpace(execScript,'ifstate==6||state==7,hold=0');
    'alpha_zero_states_le_5',containsNoSpace(execScript,'ifstate<=5||state==9,releaseAlpha=0');
    };
execRows=cell(size(execTokens,1),5);
for k=1:size(execTokens,1)
    execRows(k,:)={execTokens{k,1},execTokens{k,2},true,passFail(execTokens{k,2}), ...
        ternary(execTokens{k,2},'current executor source confirmed','missing token')};
end
writeMixedCsv(fullfile(outDir,'17_RESTORE_EXECUTOR_STATE_SEMANTICS.csv'), ...
    {'Semantic','Observed','Expected','Status','Note'},execRows);

if ~all(cell2mat(execTokens(:,2)))
    error('E2AUD6:ExecutorSemantic','Restore Executor semantic tokens are not all present.');
end

% Exact wiring of executor y -> control hold/alpha -> adapter.
wiringRows=cell(0,7);
wiringRows(end+1,:)=connectionFact(executorDemux,2,control,10,'Executor y2 RestoreHold -> ESS2_Control input10'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact(executorDemux,3,control,9,'Executor y3 RestoreAlpha -> ESS2_Control input9'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([control '/RestoreHold'],1,wrapper,19,'Control hold -> GFL wrapper input19'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([control '/RestoreAlpha'],1,wrapper,20,'Control alpha -> GFL wrapper input20'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([wrapper '/RestoreHold'],1,adapter,6,'Wrapper hold -> adapter input6'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([wrapper '/RestoreAlpha'],1,adapter,7,'Wrapper alpha -> adapter input7'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([adapter '/RestoreHold'],1,adapterCore,7,'Adapter hold -> CORE input7'); %#ok<AGROW>
wiringRows(end+1,:)=connectionFact([adapter '/RestoreAlpha'],1,adapterCore,8,'Adapter alpha -> CORE input8'); %#ok<AGROW>
writeMixedCsv(fullfile(outDir,'18_RESTORE_CONTROL_WIRING.csv'), ...
    {'Source','SourcePort','Destination','DestinationPort','ObservedDirect','Status','Meaning'},wiringRows);

% =========================================================================
% 6. Power Loop + power recovery chain
% =========================================================================
pSum=[power '/Add'];
qSum=[power '/Add2'];
pProd=[power '/AA15_RESTORE_PERR_ALPHA'];
qProd=[power '/AA15_RESTORE_QERR_ALPHA'];
for p={pSum,qSum,pProd,qProd,[power '/RestoreAlpha']},mustBlock(p{1});end

pPI=uniqueDstFrom(pProd,power,'P alpha-scaled error PI');
qPI=uniqueDstFrom(qProd,power,'Q alpha-scaled error PI');

pInts=find_system(pPI,'LookUnderMasks','all','FollowLinks','on','BlockType','DiscreteIntegrator');
qInts=find_system(qPI,'LookUnderMasks','all','FollowLinks','on','BlockType','DiscreteIntegrator');
if numel(pInts)~=1 || numel(qInts)~=1
    error('E2AUD6:PowerPIIntegrator','P/Q PI discrete-integrator count is not 1/1.');
end

powerRows = {
    'P_error',pSum,safeGet(pSum,'Inputs'),'Pref - Pmeas','before alpha';
    'Q_error',qSum,safeGet(qSum,'Inputs'),'Qmeas - Qref','before alpha';
    'P_alpha_product',pProd,safeGet(pProd,'Inputs'),safeGet([power '/RestoreAlpha'],'Port'),'alpha-scaled error';
    'Q_alpha_product',qProd,safeGet(qProd,'Inputs'),safeGet([power '/RestoreAlpha'],'Port'),'alpha-scaled error';
    'P_PI',pPI,maskOrDialogParam(pPI,'Kp'),maskOrDialogParam(pPI,'Ki'),maskOrDialogParam(pPI,'Par_Limits');
    'Q_PI',qPI,maskOrDialogParam(qPI,'Kp'),maskOrDialogParam(qPI,'Ki'),maskOrDialogParam(qPI,'Par_Limits');
    'P_PI_integrator',pInts{1},safeGet(pInts{1},'InitialCondition'),safeGet(pInts{1},'ExternalReset'),safeGet(pInts{1},'IntegratorMethod');
    'Q_PI_integrator',qInts{1},safeGet(qInts{1},'InitialCondition'),safeGet(qInts{1},'ExternalReset'),safeGet(qInts{1},'IntegratorMethod');
    };
writeMixedCsv(fullfile(outDir,'19_POWER_LOOP_ALPHA_AND_PI_STATE.csv'), ...
    {'Item','Path','Field1','Field2','Field3'},powerRows);

% Prove alpha is used both in power-loop error path and current-adapter iref path.
doubleAlpha = containsNoSpace(adapterScript,'iref_used=a*iref') && ...
    directConnectionExists([power '/RestoreAlpha'],1,pProd,2) && ...
    directConnectionExists([power '/RestoreAlpha'],1,qProd,2);

alphaRows = {
    'PowerLoop_PErrorAlpha',directConnectionExists([power '/RestoreAlpha'],1,pProd,2), ...
        'RestoreAlpha multiplies P error before P PI';
    'PowerLoop_QErrorAlpha',directConnectionExists([power '/RestoreAlpha'],1,qProd,2), ...
        'RestoreAlpha multiplies Q error before Q PI';
    'CurrentAdapter_IrefAlpha',containsNoSpace(adapterScript,'iref_used=a*iref'), ...
        'RestoreAlpha also multiplies Current Adapter iref_used';
    'DoubleAlphaExists',doubleAlpha, ...
        'Current design applies alpha at power-error generation AND final current-adapter reference';
    };
alphaOut=cell(size(alphaRows,1),5);
for k=1:size(alphaRows,1)
    alphaOut(k,:)={alphaRows{k,1},alphaRows{k,2},'current saved design', ...
        ternary(alphaRows{k,2},'CONFIRMED','NOT_CONFIRMED'),alphaRows{k,3}};
end
writeMixedCsv(fullfile(outDir,'20_POWER_RECOVERY_DOUBLE_ALPHA_FACTS.csv'), ...
    {'Item','Observed','ExpectedOrMeaning','Status','Note'},alphaOut);

% Current release-ramp config.
cfgNames=restoreCfgNames();
cfgRows=cell(0,4);
for k=1:numel(cfgNames)
    p=[cfgSub '/' cfgNames{k}];
    if getSimulinkBlockHandle(p)>0
        cfgRows(end+1,:)={cfgNames{k},safeGet(p,'Value'),p, ...
            ternary(contains(cfgNames{k},'RELEASE')||contains(cfgNames{k},'POWER'), ...
                'POWER_RECOVERY_RELEVANT','OTHER_RESTORE_CONFIG')}; %#ok<AGROW>
    end
end
writeMixedCsv(fullfile(outDir,'21_RESTORE_CONFIG_CURRENT_VALUES.csv'), ...
    {'Parameter','SavedValue','Path','Class'},cfgRows);


% -------------------------------------------------------------------------
% 6B. Resolve Power PI numeric values, subsystem interface and output route.
% -------------------------------------------------------------------------
pKpRaw=maskOrDialogParam(pPI,'Kp');
pKiRaw=maskOrDialogParam(pPI,'Ki');
qKpRaw=maskOrDialogParam(qPI,'Kp');
qKiRaw=maskOrDialogParam(qPI,'Ki');
pInitRaw=maskOrDialogParam(pPI,'Init');
qInitRaw=maskOrDialogParam(qPI,'Init');

[pKp,pKpOK]=resolveNumericExpr(MODEL,pKpRaw);
[pKi,pKiOK]=resolveNumericExpr(MODEL,pKiRaw);
[qKp,qKpOK]=resolveNumericExpr(MODEL,qKpRaw);
[qKi,qKiOK]=resolveNumericExpr(MODEL,qKiRaw);
[pInit,pInitOK]=resolveNumericExpr(MODEL,pInitRaw);
[qInit,qInitOK]=resolveNumericExpr(MODEL,qInitRaw);

powerNumericRows = {
    'P_Kp',pKpRaw,valueText(pKp),pKpOK;
    'P_Ki',pKiRaw,valueText(pKi),pKiOK;
    'Q_Kp',qKpRaw,valueText(qKp),qKpOK;
    'Q_Ki',qKiRaw,valueText(qKi),qKiOK;
    'P_Init',pInitRaw,valueText(pInit),pInitOK;
    'Q_Init',qInitRaw,valueText(qInit),qInitOK;
    };
writeMixedCsv(fullfile(outDir,'20A_POWER_PI_NUMERIC_RESOLUTION.csv'), ...
    {'Parameter','RawExpression','ResolvedValue','Resolved'},powerNumericRows);

powerPortRows=auditSubsystemInterface(power);
writeMixedCsv(fullfile(outDir,'20B_POWER_LOOP_INTERFACE.csv'), ...
    {'Direction','Port','InternalPortBlock','PortName','ExternalBlock','ExternalPort', ...
     'ExternalSemantic','Status'},powerPortRows);

% Trace every Power Control Loop output back to its internal source.
pOuts=find_system(power,'SearchDepth',1,'BlockType','Outport');
pOutTraceSummary=cell(0,7);
for k=1:numel(pOuts)
    pn=str2double(safeGet(pOuts{k},'Port'));
    ph=get_param(pOuts{k},'PortHandles');
    [sb,sp]=portSource(ph.Inport(1));
    [tr,iss]=traceOutputUpstream(sb,sp,power,18);
    fn=fullfile(outDir,sprintf('20C_POWER_OUT%d_%s_TRACE.csv',pn,sanitizeName(get_param(pOuts{k},'Name'))));
    writeMixedCsv(fn,traceHeaders(),tr);
    pOutTraceSummary(end+1,:)={pn,get_param(pOuts{k},'Name'),sb,sp, ...
        signalSemanticAtOutput(sb,sp),strjoin(iss,' | '),passFail(isempty(iss))}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'20C_POWER_OUTPUT_TRACE_SUMMARY.csv'), ...
    {'Port','OutportName','InternalSource','SourcePort','SourceSemantic','Issues','Status'},pOutTraceSummary);

% Structural release-law consequence.
powerStateFacts = {
    'P/Q PI ExternalReset',strcmpi(safeGet(pInts{1},'ExternalReset'),'none') && ...
        strcmpi(safeGet(qInts{1},'ExternalReset'),'none'), ...
        'no explicit reset on either PI integrator';
    'All PI numeric parameters resolved',all([pKpOK pKiOK qKpOK qKiOK pInitOK qInitOK]), ...
        'required before freezing power-recovery law';
    'Double alpha structurally confirmed',doubleAlpha, ...
        'P/Q error is alpha-gated and Current Adapter iref is alpha-gated again';
    };
stateFactRows=cell(size(powerStateFacts,1),5);
for k=1:size(powerStateFacts,1)
    stateFactRows(k,:)={powerStateFacts{k,1},powerStateFacts{k,2},true, ...
        passFail(powerStateFacts{k,2}),powerStateFacts{k,3}};
end
writeMixedCsv(fullfile(outDir,'20D_POWER_RECOVERY_STATE_FACTS.csv'), ...
    {'Fact','Observed','Expected','Status','Meaning'},stateFactRows);

powerRecoveryFactsClosed = all([pKpOK pKiOK qKpOK qKiOK pInitOK qInitOK]) && doubleAlpha;

% =========================================================================
% 7. Breaker command/control path
% =========================================================================
breakerRows=cell(0,7);
breakerRows(end+1,:)=connectionFact(executorDemux,5,router,1,'Executor breaker command -> router data1'); %#ok<AGROW>
breakerRows(end+1,:)=connectionFact(cfgSub,2,router,2,'Restore config output2 MasterEnable -> router selector'); %#ok<AGROW>
legacyCfg=[SS2 '/CFG_DIAG_AC_CONNECT_ESS2'];mustBlock(legacyCfg);
breakerRows(end+1,:)=connectionFact(legacyCfg,1,router,3,'Legacy breaker cfg -> router data3'); %#ok<AGROW>
breakerRows(end+1,:)=connectionFact(router,1,breaker,1,'Router -> SPS breaker external command'); %#ok<AGROW>
writeMixedCsv(fullfile(outDir,'22_BREAKER_COMMAND_CHAIN.csv'), ...
    {'Source','SourcePort','Destination','DestinationPort','ObservedDirect','Status','Meaning'},breakerRows);

breakerParamRows = {
    'External',safeGet(breaker,'External');
    'InitialState',safeGet(breaker,'InitialState');
    'BreakerResistance',safeGet(breaker,'BreakerResistance');
    'SnubberResistance',safeGet(breaker,'SnubberResistance');
    'SnubberCapacitance',safeGet(breaker,'SnubberCapacitance');
    'Measurements',safeGet(breaker,'Measurements');
    };
writeMixedCsv(fullfile(outDir,'23_BREAKER_ELECTRICAL_PARAMETERS.csv'), ...
    {'Parameter','Value'},breakerParamRows);


% -------------------------------------------------------------------------
% 7B. Executor inputs + READY/COMMIT + master-frequency evidence
% -------------------------------------------------------------------------
execPortRows=auditSubsystemInterface(executor);
writeMixedCsv(fullfile(outDir,'23A_EXECUTOR_INTERFACE.csv'), ...
    {'Direction','Port','InternalPortBlock','PortName','ExternalBlock','ExternalPort', ...
     'ExternalSemantic','Status'},execPortRows);

phExec=get_param(executor,'PortHandles');
execInputLabels={'恢复配置_cfg','统一阶段_stage','48维诊断_diag','并入侧代理电压_vinner','母线侧代理电压_vbus'};
execTraceClosed=false(5,1);
for k=1:min(5,numel(phExec.Inport))
    [sb,sp]=portSource(phExec.Inport(k));
    [tr,iss]=traceOutputUpstream(sb,sp,SS2,20);
    fn=fullfile(outDir,sprintf('23B_EXEC_IN%d_%s_TRACE.csv',k,sanitizeName(execInputLabels{k})));
    writeMixedCsv(fn,traceHeaders(),tr);
    execTraceClosed(k)=isempty(iss);
end

readyFacts = {
    'READY uses pllHz-masterF',containsNoSpace(execScript,'abs(pllHz-masterF)<=dfMax'), ...
        'current model READY frequency predicate';
    'READY uses diag19 PLL_Hz',containsNoSpace(execScript,'pllHz=diag(19)'), ...
        'diag19 is executor PLL frequency';
    'READY uses diag37 MasterF',containsNoSpace(execScript,'masterF=diag(37)'), ...
        'diag37 is the current master-frequency quantity';
    'state3 COMMIT does not recheck ready', ...
        containsNoSpace(execScript,'elseifstate==3') && ...
        containsNoSpace(execScript,'elseifbreakerAct>0.5&&((autoSeq>0.5)||(manualCommit>0.5))state=4'), ...
        'historical READY can remain latched before COMMIT';
    'phase gate parameter exists',containsNoSpace(execScript,'phaseGate=double(cfg(19)>0.5)'), ...
        'pre-connect phase qualification available but may be disabled';
    'voltage-match gate parameter exists',containsNoSpace(execScript,'vmatchGate=double(cfg(21)>0.5)'), ...
        'pre-connect voltage-ratio qualification available but may be disabled';
    };
readyRows=cell(size(readyFacts,1),5);
for k=1:size(readyFacts,1)
    readyRows(k,:)={readyFacts{k,1},readyFacts{k,2},true, ...
        passFail(readyFacts{k,2}),readyFacts{k,3}};
end
writeMixedCsv(fullfile(outDir,'23C_READY_COMMIT_SEMANTICS.csv'), ...
    {'Fact','Observed','Expected','Status','Meaning'},readyRows);

% Search current ESS2-control MATLAB Function sources and current block/tag
% names for master-frequency evidence. This collects all candidates in ONE run.
[masterCodeRows,masterScriptFiles]=searchEMChartsForPatterns(control, ...
    {'masterF','diag(37)','Fref','MasterF','master frequency'},outDir,'23D_MASTERF');
writeMixedCsv(fullfile(outDir,'23D_MASTERF_CODE_SEARCH.csv'), ...
    {'Chart','MatchedPattern','Snippet','ScriptFile'},masterCodeRows);

masterBlockRows=searchBlocksByKeywords(control,{'MasterF','MASTER_F','Fref','ESS1_Fout','Freq'});
writeMixedCsv(fullfile(outDir,'23E_MASTERF_BLOCK_CANDIDATES.csv'), ...
    {'Block','BlockType','Name','GotoTag','Value','Connectivity'},masterBlockRows);

% C2/breaker-inner observability: current structural fact, not a guessed issue.
c2NodeRows=findPhysicalNodeNeighbors(SS2,C2);
writeMixedCsv(fullfile(outDir,'23F_C2_BREAKER_INNER_NODE_NEIGHBORS.csv'), ...
    {'Block','BlockType','SourceType','ReferenceBlock','Measurements','Connectivity'},c2NodeRows);

c2ObservabilityFactKnown = true; % topology + Measurements=None are directly audited facts.
readySemanticsClosed = all(cell2mat(readyFacts(:,2))) && all(execTraceClosed);

% =========================================================================
% 8. OpWrite inventory + current G27 schema
% =========================================================================
% IMPORTANT:
% Do NOT assume OpWriteFile blocks have BlockType='Reference'.
% The repository's proven causal-harness scripts scan ALL blocks and classify
% OpWriteFile by the concatenation of ReferenceBlock + SourceBlock + MaskType.
% This exact detection rule is reused here instead of inventing a new one.
ops = findAllOpWritesProven(MODEL);
opCount = numel(ops);

opRows=cell(0,13);
opGroups=nan(1,opCount);
opByGroup=cell(1,31);

for k=1:opCount
    b=ops{k};
    g=readNumericMaskProven(b,'Acq_Group');
    d=readNumericMaskProven(b,'Decimation');
    opGroups(k)=g;

    if isfinite(g) && g>=1 && g<=30 && abs(g-round(g))<1e-12
        gi=round(g);
        if ~isempty(opByGroup{gi})
            error('E2AUD6:DuplicateOpWriteGroup', ...
                'Duplicate OpWrite acquisition group %d: %s | %s', ...
                gi,opByGroup{gi},b);
        end
        opByGroup{gi}=b;
    end

    ph=get_param(b,'PortHandles');
    if isempty(ph.Inport)
        src='NO_INPORT'; sp=NaN;
    else
        [src,sp]=portSource(ph.Inport(1));
    end

    opRows(end+1,:)={ ...
        b,g,d,readMaskValueProven(b,'varname'), ...
        readMaskValueOptional(b,'Filename'), ...
        readMaskValueOptional(b,'file_size'), ...
        readMaskValueOptional(b,'Nb_Samples'), ...
        src,sp,safeGet(src,'BlockType'), ...
        safeGet(b,'ReferenceBlock'),safeGet(b,'SourceBlock'),safeGet(b,'MaskType')}; %#ok<AGROW>
end

writeMixedCsv(fullfile(outDir,'24_OPWRITE_INVENTORY.csv'), ...
    {'Block','AcqGroup','Decimation','VarName','Filename','FileSize','NbSamples', ...
     'InputSource','InputSourcePort','InputSourceType', ...
     'ReferenceBlock','SourceBlock','MaskType'},opRows);

% Current platform contract. Following the repository anti-rework rule,
% collect ALL OpWrite contract problems first and raise only once.
opIssues={};

if opCount~=5
    opIssues{end+1}=sprintf('OpWriteFile count expected 5, got %d',opCount); %#ok<AGROW>
end

if any(~isfinite(opGroups))
    opIssues{end+1}=sprintf('one or more Acq_Group values are non-finite: %s', ...
        mat2str(opGroups)); %#ok<AGROW>
elseif ~isequal(sort(round(opGroups)),26:30)
    opIssues{end+1}=sprintf('Acq_Group set expected 26:30, got %s', ...
        mat2str(opGroups)); %#ok<AGROW>
end

for g=26:30
    if isempty(opByGroup{g})
        opIssues{end+1}=sprintf('missing acquisition group %d',g); %#ok<AGROW>
    end
end

if isempty(opByGroup{27})
    opIssues{end+1}='cannot resolve acquisition group 27 path'; %#ok<AGROW>
elseif ~strcmp(opByGroup{27},g27)
    opIssues{end+1}=sprintf('G27 path mismatch: discovered=%s expected=%s', ...
        opByGroup{27},g27); %#ok<AGROW>
end

% Read exact G27 contract independently from its known current block.
g27Group = readNumericMaskProven(g27,'Acq_Group');
g27Decimation = readNumericMaskProven(g27,'Decimation');
g27VarName = readMaskValueProven(g27,'varname');

if abs(g27Group-27)>1e-12
    opIssues{end+1}=sprintf('G27 Acq_Group expected 27, got %.17g',g27Group); %#ok<AGROW>
end
if abs(g27Decimation-4)>1e-12
    opIssues{end+1}=sprintf('G27 Decimation expected 4, got %.17g',g27Decimation); %#ok<AGROW>
end
if ~strcmp(strtrim(g27VarName),'rootdiag_ess2_data')
    opIssues{end+1}=sprintf('G27 varname expected rootdiag_ess2_data, got %s', ...
        g27VarName); %#ok<AGROW>
end

% G27 current 56-channel vector normalization contract.
demux56=[g27Norm '/Demux56'];
mux56=[g27Norm '/Mux56'];
for p={demux56,mux56},mustBlock(p{1});end

g27RowsContract = {
    'G27_AcqGroup',g27Group,'27';
    'G27_Decimation',g27Decimation,'4';
    'G27_VarName',g27VarName,'rootdiag_ess2_data';
    'Normalizer_DemuxOutputs',safeGet(demux56,'Outputs'),'56 scalars expected';
    'Normalizer_MuxInputs',safeGet(mux56,'Inputs'),'56';
    };
writeMixedCsv(fullfile(outDir,'25_G27_BOUNDARY_CONTRACT.csv'), ...
    {'Item','Observed','ExpectedOrMeaning'},g27RowsContract);

if ~isempty(opIssues)
    writeText(fullfile(outDir,'24A_OPWRITE_CONTRACT_ISSUES.txt'), ...
        strjoin(opIssues,newline));
    error('E2AUD6:OpWriteContract', ...
        ['OpWrite contract has %d issue(s). All issues were collected in one pass.\n' ...
         '%s\nSee 24_OPWRITE_INVENTORY.csv and 24A_OPWRITE_CONTRACT_ISSUES.txt.'], ...
        numel(opIssues),strjoin(opIssues,' | '));
else
    writeText(fullfile(outDir,'24A_OPWRITE_CONTRACT_ISSUES.txt'), ...
        'NONE - repository-proven OpWrite discovery and G26..G30 contract PASS.');
end

repackScript=emChartScript(g27Repack);
writeText(fullfile(outDir,'26_G27_REPACK_CURRENT_SOURCE.mtxt'),repackScript);

diagNames = currentG27Schema56();
schemaRows=cell(56,4);
for k=1:56
    schemaRows(k,:)={k,k+1,diagNames{k}, ...
        ternary(k<=48,'existing diag48 / overwritten restore slot','reconnect extension')};
end
writeMixedCsv(fullfile(outDir,'27_G27_CURRENT_SCHEMA56.csv'), ...
    {'DeviceChannel','MATRow','Signal','Class'},schemaRows);

% =========================================================================
% 9. Final logging evidence inventory for the future patch
% =========================================================================
% Current G27 is kept as the only ESS2 high-rate recorder. No G31.
% The audit distinguishes:
%   - already recorded evidence;
%   - local variables that REQUIRE explicit export if we want direct proof;
%   - quantities already equivalent to an existing recorded channel.

% Determine whether Power Control Loop/out1 is already the raw current-reference
% route used by From24. This prevents wasting G27 slots on duplicate evidence.
powerOut1ToCurrentRef=false;
try
    routeRef=routeSummary(strcmp(routeSummary(:,1),'电流参考_CURRENT_REFERENCE'),:);
    if ~isempty(routeRef)
        txt=[routeRef{1,5} ' ' routeRef{1,10}];
        powerOut1ToCurrentRef=contains(txt,'Power Control Loop');
    end
catch
end

futureLog = {
    '恢复状态_RestoreState','EXISTING','G27 ch20','保留';
    '恢复保持_RestoreHold','EXISTING','G27 ch31','保留';
    '并入就绪_ReconnectReady','EXISTING','G27 ch32','保留';
    '恢复系数_RestoreAlpha','EXISTING','G27 ch33','保留';
    '最终断路器命令_FinalBreakerCmd','EXISTING','G27 ch34','保留';
    '故障码_FailCode','EXISTING','G27 ch38','保留';
    '实际dq电流_Actual_IdIq','EXISTING','G27 ch5-6','保留';
    '原始/最终电流参考_Raw_Final_Iref','EXISTING','G27 ch1-4','保留';
    '电流PI输出_CurrentPI_dq','EXISTING','G27 ch11-12','保留';
    '电压前馈_Vff_dq','EXISTING','G27 ch9-10','保留';
    '变流器dq命令_Vconv_dq','EXISTING','G27 ch13-14','保留';
    '调制度/限流/余量','EXISTING','G27 ch15/35/43','保留';
    'P/Q实测','EXISTING','G27 ch16-17','保留';
    'PrefCmd/PrefEff/QrefEff','EXISTING','G27 ch24/26/28','保留';
    '变流器端代理Vabc','EXISTING','G27 ch49-51','代理测量';
    '母线侧代理Vabc','EXISTING','G27 ch52-54','代理测量';
    '断路器内侧C2节点Vabc','NOT_DIRECTLY_AVAILABLE', ...
        'C2 Measurements=None; neither current proxy is that node','设计时决定是否增加同节点观测';
    '实际送入PI的IrefUsed_dq','LOCAL_VARIABLE_NOT_EXPORTED', ...
        'Current Adapter local iref_used','正式改模后建议直接记录';
    '实际送入PI的ImeasUsed_dq','LOCAL_VARIABLE_NOT_EXPORTED', ...
        'Current Adapter local imeas_used','正式改模后建议直接记录';
    'PI输出匹配是否激活_MatchActive','LOCAL_VARIABLE_NOT_EXPORTED', ...
        'Current Adapter local match','正式改模后建议直接记录';
    '显式电流控制阶段_CurrentMode','NOT_EXPLICIT', ...
        'currently inferred from executor state/hold','正式改模后建议直接记录';
    'PowerPI输出','STRUCTURALLY_AUDITED', ...
        ternary(powerOut1ToCurrentRef,'equivalent route already reaches current-reference chain', ...
        'see 20C_POWER_OUTPUT_TRACE_SUMMARY.csv'), ...
        ternary(powerOut1ToCurrentRef,'无需重复占槽','设计前结合trace决定');
    '实际断路器状态','NOT_MEASURED', ...
        'SPS breaker Measurements=None; command is recorded','仿真中可选，非当前首要阻碍';
    };
writeMixedCsv(fullfile(outDir,'28_FINAL_LOGGING_EVIDENCE_INVENTORY.csv'), ...
    {'Signal_CN','CurrentAvailability','CurrentEvidence','DesignUse'},futureLog);

% =========================================================================
% 10. Final fact-closure matrix -- this is the authoritative readiness result
% =========================================================================
% R3's readiness matrix was too optimistic. R4 only reports READY_FOR_DESIGN
% when every FACT required to design the patch has been closed by current
% graph/code evidence. A missing measurement can be a known design constraint
% and does not equal an unknown fact.

controlInterfaceClosed=controlPortCountOK && all(controlPortFacts);
currentFeedbackRouteClosed=routeClosed(1);
currentReferenceRouteClosed=routeClosed(2);
voltageFeedforwardRouteClosed=routeClosed(3);

wrapperPortContractClosed = ...
    numel(get_param(wrapper,'PortHandles').Inport)==20;
adapterParentPortContractClosed = ...
    numel(phAdapter.Inport)==7;
adapterCoreMapClosed = ...
    size(corePortRows,1)==8 && numel(phCore.Inport)==8 && ...
    all(~strcmp(corePortRows(:,3),'UNCONNECTED')) && ...
    all(~cellfun(@(x) startsWith(char(string(x)),'UNKNOWN'),corePortRows(:,3)));
powerPortContractClosed = ...
    numel(get_param(power,'PortHandles').Inport)==7;
executorPortContractClosed = ...
    numel(phExec.Inport)==5;

oldpiRouteClosed=isempty(oldpiIssues) && ...
    ~strcmp(oldpiSource,'UNRESOLVED') && ...
    ~strcmp(oldpiSource,'UNCONNECTED') && ...
    ~startsWith(oldpiSource,'UNKNOWN');
adapterStateClosed=stateLoopA && stateLoopB;
handoverMathClosed=adapterHandoverClosed;
powerNumericClosed=all([pKpOK pKiOK qKpOK qKiOK pInitOK qInitOK]);
powerOutputTraceClosed=~isempty(pOutTraceSummary) && all(strcmp(pOutTraceSummary(:,7),'PASS'));
executorInputsClosed=all(execTraceClosed);
opwriteClosed=opCount==5 && isequal(sort(round(opGroups)),26:30) && ...
    abs(g27Group-27)<1e-12 && abs(g27Decimation-4)<1e-12 && ...
    strcmp(strtrim(g27VarName),'rootdiag_ess2_data');

% MasterF origin is considered fact-closed if the executor diag route is
% closed AND this single run captured all matching code/block candidates.
% It need not already be a desirable design; we only need enough evidence
% to decide the redesign without another audit.
masterEvidenceCaptured=executorInputsClosed && (~isempty(masterCodeRows) || ~isempty(masterBlockRows));
masterRowsSpecific=false(size(masterCodeRows,1),1);
for k=1:size(masterCodeRows,1)
    pat=lower(masterCodeRows{k,2});
    masterRowsSpecific(k)=contains(pat,'masterf') || contains(pat,'diag(37)');
end
if any(masterRowsSpecific)
    masterCharts=unique(masterCodeRows(masterRowsSpecific,1),'stable');
else
    masterCharts={};
end
masterFOriginClosed=executorInputsClosed && numel(masterCharts)==1;

closureRows = {
    'ESS2物理支路拓扑','physicalOK',physicalOK, ...
        'Converter -> EV1_inv -> L2 -> C2节点 -> Breaker -> EV1_LV_Meas 七项物理断言全部成立';
    'ESS2父端口与跨任务输入','controlInterfaceClosed',controlInterfaceClosed, ...
        '10个父端口按端口号和真实Source全部核对';
    '实际电流反馈最终路径','currentFeedbackRouteClosed',currentFeedbackRouteClosed, ...
        'From28已解析唯一Goto并递归追溯';
    '电流参考最终路径','currentReferenceRouteClosed',currentReferenceRouteClosed, ...
        'From24已解析唯一Goto并递归追溯';
    '电压前馈最终路径','voltageFeedforwardRouteClosed',voltageFeedforwardRouteClosed, ...
        'From26已解析唯一Goto并递归追溯';
    'GFL Wrapper父接口20输入','wrapperPortContractClosed',wrapperPortContractClosed, ...
        '沿用已Build成功的R3恢复结构接口合同';
    'Current Adapter父接口7输入','adapterParentPortContractClosed',adapterParentPortContractClosed, ...
        '沿用已Build成功的R3恢复结构接口合同';
    'Current Adapter八输入语义','adapterCoreMapClosed',adapterCoreMapClosed, ...
        'vff/imeas/iref/vdc/oldpi/z/hold/alpha全部已连接';
    'Power Loop父接口7输入','powerPortContractClosed',powerPortContractClosed, ...
        '含RestoreAlpha第7输入；沿用已Build成功接口合同';
    'Restore Executor父接口5输入','executorPortContractClosed',executorPortContractClosed, ...
        'cfg/stage/diag/vinner/vbus五路输入';
    'oldpi来源','oldpiRouteClosed',oldpiRouteClosed, ...
        'adapter input5已追溯并输出完整trace';
    'Current Adapter状态反馈环','adapterStateClosed',adapterStateClosed, ...
        'CORE zn -> STATE -> CORE z';
    'hold退出首拍数学关系','handoverMathClosed',handoverMathClosed, ...
        '当前源码cfg已解析并计算首拍纠偏系数';
    'P/Q PI数值参数','powerNumericClosed',powerNumericClosed, ...
        'Kp/Ki/Init全部从当前workspace解析为数值';
    'Power Loop输出追溯','powerOutputTraceClosed',powerOutputTraceClosed, ...
        '每个Power Loop Outport均已生成内部trace';
    '双RestoreAlpha事实','doubleAlpha',doubleAlpha, ...
        'P/Q误差与Current Adapter参考均受alpha作用';
    'Executor输入来源','executorInputsClosed',executorInputsClosed, ...
        'cfg/stage/diag/vinner/vbus全部递归追溯';
    'READY/COMMIT当前语义','readySemanticsClosed',readySemanticsClosed, ...
        'masterF判据、state3 commit不复核ready等源码事实';
    'MasterF相关证据一次性采集','masterEvidenceCaptured',masterEvidenceCaptured, ...
        '所有相关MATLAB Function代码和候选块已随ZIP输出';
    'MasterF精确代码来源唯一性','masterFOriginClosed',masterFOriginClosed, ...
        '必须唯一定位到使用MasterF/diag37的当前MATLAB Function；若未自动唯一，本ZIP已含全部候选供人工封板';
    'C2/断路器内侧拓扑事实','c2ObservabilityFactKnown',c2ObservabilityFactKnown, ...
        '节点已知且C2 Measurements=None；这是设计约束而非未知';
    '断路器命令链','breakerChain',all(cell2mat(breakerRows(:,5))), ...
        'Executor -> Router -> SPS breaker';
    '五个OpWrite与G27边界','opwriteClosed',opwriteClosed, ...
        'G26~G30完整；G27=group27/decimation4/56ch';
    '未来G27所需内部证据','loggingNeedsCaptured',true, ...
        'IrefUsed/ImeasUsed/MatchActive/CurrentMode等已明确可用性';
    };

writeMixedCsv(fullfile(outDir,'29_FINAL_FACT_CLOSURE_MATRIX.csv'), ...
    {'AuditDomain','BooleanName','ObservedClosed','Meaning'},closureRows);

closedVector=cell2mat(closureRows(:,3));
factBlockers={};
for k=1:size(closureRows,1)
    if ~logical(closureRows{k,3})
        factBlockers{end+1}=sprintf('%s :: %s',closureRows{k,1},closureRows{k,4}); %#ok<AGROW>
    end
end

% Design decisions are intentionally separated from fact blockers.
% They are NOT reasons for another audit if all facts above are closed.
designDecisions = {
    '断开待并与闭合后零电流主动调节如何切换', ...
        '事实已齐：state4/5持续hold是缺陷；hold0+alpha0已有真实闭环能力；首拍数学已输出';
    '断路器内侧C2节点是否增加直接Vabc观测', ...
        '事实已齐：当前没有直接测量；由最终并入资格设计决定';
    'READY频率参考改用什么真实量', ...
        '事实已齐：当前用diag37 MasterF；相关来源/候选一次性采集；Runner历史已暴露其问题';
    'state3 COMMIT是否必须当拍重新验证READY', ...
        '事实已齐：当前不会；最终状态机设计时决定';
    'RestoreAlpha保留双层还是改为唯一功率恢复权', ...
        '事实已齐：double-alpha已证明；PI参数/状态/输出trace已采集';
    '正式G27如何放入IrefUsed/ImeasUsed/MatchActive/CurrentMode', ...
        '事实已齐：现有与缺失通道已列清；不新增G31';
    };
writeMixedCsv(fullfile(outDir,'30_DESIGN_DECISIONS_AFTER_FACT_AUDIT.csv'), ...
    {'DesignDecision_CN','CurrentFactBasis'},designDecisions);

if isempty(factBlockers)
    finalStatus='事实审计封板_可以开始正式改模方案设计';
else
    finalStatus='事实审计已一次性完成_仍有事实阻碍需用本ZIP分析';
end

writeText(fullfile(outDir,'31_ALL_FACT_BLOCKERS.txt'), ...
    ternary(isempty(factBlockers), ...
        'NONE - 所有正式改模所需事实均已在本轮审计关闭。', ...
        strjoin(factBlockers,newline)));

% Modification anchors only, still NO EDIT.
anchors = {
    '恢复执行器保持逻辑',executorCore, ...
        'state4/state5 hold output semantics', ...
        '断开待并 与 闭合后零电流主动调节 必须分阶段';
    '现有电流适配器模式',adapterCore, ...
        'hold/alpha/match wrapper around existing V4.9 helper', ...
        '优先复用现有电流PI，不默认新增第二套控制器';
    '功率平滑恢复',power, ...
        'P/Q error alpha + adapter alpha + PI state', ...
        '依据20A~20D事实冻结唯一恢复权';
    '并入前电气资格',C2, ...
        'breaker-inner node observability', ...
        '决定是否增加同节点Vabc观测以及READY条件';
    'G27取证',g27Repack, ...
        '56-channel ESS2 evidence pack', ...
        '同一个G27内补内部控制事实；禁止新增G31';
    '断路器仲裁',router, ...
        'executor vs legacy CFG arbitration', ...
        '除非事实要求，不改现有物理breaker路由';
    };
writeMixedCsv(fullfile(outDir,'32_MODIFICATION_ANCHORS_NO_EDIT.csv'), ...
    {'Area_CN','ExactPath','Anchor','DesignConstraint_CN'},anchors);

% =========================================================================
% 11. Final safeguards / authoritative result
% =========================================================================
dirtyAtEnd=get_param(MODEL,'Dirty');
if ~strcmp(dirtyAtEnd,dirtyAtStart)
    error('E2AUD6:DirtyChanged', ...
        'Read-only audit changed model Dirty state: start=%s end=%s.', ...
        dirtyAtStart,dirtyAtEnd);
end

result.status=finalStatus;
result.factBlockers=factBlockers;
result.allFactsClosed=isempty(factBlockers);
result.adapterSourceSha256=adapterHash;
result.executorSourceSha256=execHash;
result.opWriteCount=opCount;
result.opWriteGroups=sort(round(opGroups));
result.c2DirectMeasurement=c2Direct;
result.physicalBranchResolved=physicalOK;
result.currentFeedbackRouteClosed=currentFeedbackRouteClosed;
result.currentReferenceRouteClosed=currentReferenceRouteClosed;
result.voltageFeedforwardRouteClosed=voltageFeedforwardRouteClosed;
result.wrapperPortContractClosed=wrapperPortContractClosed;
result.adapterParentPortContractClosed=adapterParentPortContractClosed;
result.adapterCoreMapClosed=adapterCoreMapClosed;
result.powerPortContractClosed=powerPortContractClosed;
result.executorPortContractClosed=executorPortContractClosed;
result.oldpiRouteClosed=oldpiRouteClosed;
result.holdExitMathClosed=handoverMathClosed;
result.powerNumericClosed=powerNumericClosed;
result.executorInputsClosed=executorInputsClosed;
result.readySemanticsClosed=readySemanticsClosed;
result.masterEvidenceCaptured=masterEvidenceCaptured;
result.masterFOriginClosed=masterFOriginClosed;
result.dirtyAtStart=dirtyAtStart;
result.modelDirtyAtEnd=get_param(MODEL,'Dirty');

writeText(fullfile(outDir,'RESULT.json'),jsonencode(result,'PrettyPrint',true));

fprintf(fid,'\n==================== 最终审计封板摘要 ====================\n');
fprintf(fid,'当前模型关键恢复结构语义身份      : PASS\n');
fprintf(fid,'raw SHA与历史R4是否相同           : %s（仅记录，不作硬门）\n', ...
    yesno(rawShaMatchesHistoricalR4));
fprintf(fid,'ESS2物理支路                     : %s\n',yesno(physicalOK));
fprintf(fid,'ESS2父端口输入合同               : %s\n',yesno(controlInterfaceClosed));
fprintf(fid,'实际电流反馈路线                 : %s\n',yesno(currentFeedbackRouteClosed));
fprintf(fid,'电流参考路线                     : %s\n',yesno(currentReferenceRouteClosed));
fprintf(fid,'电压前馈路线                     : %s\n',yesno(voltageFeedforwardRouteClosed));
fprintf(fid,'oldpi路线                        : %s\n',yesno(oldpiRouteClosed));
fprintf(fid,'hold退出首拍数学                 : %s\n',yesno(handoverMathClosed));
fprintf(fid,'P/Q PI数值参数                   : %s\n',yesno(powerNumericClosed));
fprintf(fid,'Executor输入/READY语义           : %s / %s\n', ...
    yesno(executorInputsClosed),yesno(readySemanticsClosed));
fprintf(fid,'C2直接电压测量                   : %s（事实已知；缺失本身不是未知）\n',yesno(c2Direct));
fprintf(fid,'RestoreAlpha双重作用             : %s\n',yesno(doubleAlpha));
fprintf(fid,'OpWrite count / groups            : %d / %s\n',opCount,mat2str(sort(round(opGroups))));
fprintf(fid,'事实阻碍数量                      : %d\n',numel(factBlockers));
for k=1:numel(factBlockers)
    fprintf(fid,'  BLOCKER %02d: %s\n',k,factBlockers{k});
end
fprintf(fid,'最终状态                          : %s\n',finalStatus);
fprintf(fid,'Model Dirty at end                : %s\n',get_param(MODEL,'Dirty'));
fprintf(fid,'NO update / compile / edit / save / RT-LAB action was performed.\n');

fclose(fid);
zipPath=[outDir '.zip'];
zip(zipPath,allFiles(outDir,''),outDir);
result.evidenceZip=zipPath;

fprintf('\nESS2 并回最终改模前只读审计 R6 完成。\n');
fprintf('Output: %s\n',outDir);
fprintf('ZIP   : %s\n',zipPath);
fprintf('Status: %s\n',finalStatus);
if isempty(factBlockers)
    fprintf('结论  : 事实审计已封板，可以开始正式改模方案设计；无需再做同类结构审计。\n');
else
    fprintf('结论  : 本轮已一次性采集全部证据；请上传ZIP，用现有证据关闭列出的事实阻碍，不再另写分散审计脚本。\n');
end
fprintf('Model was NOT updated, compiled, edited, or saved.\n');

end

% =========================================================================
% Helpers
% =========================================================================
function mustBlock(p)
if getSimulinkBlockHandle(p) < 0
    error('E2AUD6:MissingBlock','Missing current block: %s',p);
end
end

function dst=uniqueDstFrom(srcBlock,parent,meaning)
ph=get_param(srcBlock,'PortHandles');
if numel(ph.Outport)~=1
    error('E2AUD6:Outport','%s has unexpected outport count.',srcBlock);
end
lh=get_param(ph.Outport(1),'Line');
if isempty(lh)||all(lh<0)
    error('E2AUD6:Unconnected','%s output unconnected.',srcBlock);
end
db=get_param(lh,'DstBlockHandle');
db=db(db>0);
cand={};
for i=1:numel(db)
    q=getfullname(db(i));
    if startsWith(q,[parent '/'])
        cand{end+1}=q; %#ok<AGROW>
    end
end
cand=unique(cand,'stable');
if numel(cand)~=1
    error('E2AUD6:DstUnique','%s -> expected one %s, got %s', ...
        srcBlock,meaning,strjoin(cand,' | '));
end
dst=cand{1};
end

function [src,port]=portSource(portHandle)
src='UNCONNECTED';port=NaN;
try
    lh=get_param(portHandle,'Line');
    if isempty(lh)||all(lh<0),return;end
    sb=get_param(lh,'SrcBlockHandle');
    sp=get_param(lh,'SrcPortHandle');
    if isempty(sb)||sb<0,src='UNKNOWN_SOURCE';return;end
    src=getfullname(sb);
    if ~isempty(sp)&&sp>0
        try port=get_param(sp,'PortNumber'); catch, port=NaN; end
    end
catch ME
    src=['UNKNOWN:' compactText(ME.message)];
end
end

function [src,port]=resolveFromUltimateSource(fromBlock,searchRoot)
src='UNRESOLVED';port=NaN;
if ~strcmp(safeGet(fromBlock,'BlockType'),'From'),return;end
tag=safeGet(fromBlock,'GotoTag');
g=find_system(searchRoot,'LookUnderMasks','all','FollowLinks','on', ...
    'BlockType','Goto','GotoTag',tag);
if numel(g)~=1
    src=sprintf('GOTO_COUNT_%d_TAG_%s',numel(g),tag);
    return;
end
ph=get_param(g{1},'PortHandles');
[src,port]=portSource(ph.Inport(1));
end

function tf=directConnectionExists(srcBlock,srcPort,dstBlock,dstPort)
tf=false;
if getSimulinkBlockHandle(srcBlock)<0 || getSimulinkBlockHandle(dstBlock)<0,return;end
try
    sph=get_param(srcBlock,'PortHandles');
    dph=get_param(dstBlock,'PortHandles');
    if srcPort>numel(sph.Outport)||dstPort>numel(dph.Inport),return;end
    lh=get_param(sph.Outport(srcPort),'Line');
    if isempty(lh)||all(lh<0),return;end
    db=get_param(lh,'DstBlockHandle');
    dp=get_param(lh,'DstPortHandle');
    for k=1:numel(db)
        if db(k)==get_param(dstBlock,'Handle') && dp(k)==dph.Inport(dstPort)
            tf=true;return;
        end
    end
catch
end
end

function row=connectionFact(srcBlock,srcPort,dstBlock,dstPort,meaning)
tf=directConnectionExists(srcBlock,srcPort,dstBlock,dstPort);
row={srcBlock,srcPort,dstBlock,dstPort,tf,passFail(tf),meaning};
if ~tf
    error('E2AUD6:Connection', ...
        'Expected direct connection missing: %s#%d -> %s#%d (%s)', ...
        srcBlock,srcPort,dstBlock,dstPort,meaning);
end
end

function s=sourceToWrapperInput(wrapper,name)
b=find_system(wrapper,'SearchDepth',1,'BlockType','Inport','Name',name);
if numel(b)~=1
    error('E2AUD6:WrapperInputUnique', ...
        '%s: expected one top-level Inport named %s, got %d.',wrapper,name,numel(b));
end
idx=str2double(get_param(b{1},'Port'));
ph=get_param(wrapper,'PortHandles');
if ~isfinite(idx)||idx<1||idx>numel(ph.Inport)
    error('E2AUD6:WrapperInputPort','%s/%s has invalid Port=%s.', ...
        wrapper,name,safeGet(b{1},'Port'));
end
[sb,sp]=portSource(ph.Inport(idx));
if strcmp(sb,'UNCONNECTED') || startsWith(sb,'UNKNOWN')
    error('E2AUD6:WrapperInputSource','%s/%s source unresolved: %s.',wrapper,name,sb);
end
s=sprintf('%s#out:%s',sb,valueText(sp));
end

function txt=conservingConnectivityText(block)
txt='UNKNOWN';
try
    pc=get_param(block,'PortConnectivity');
    if isempty(pc),txt='EMPTY';return;end
    parts={};
    for k=1:numel(pc)
        typ='';
        try typ=char(string(pc(k).Type));catch,end
        if ~(startsWith(typ,'LConn') || startsWith(typ,'RConn')),continue;end
        pos='';src='';dst='';
        try pos=mat2str(pc(k).Position);catch,end
        try src=handlesToNames(pc(k).SrcBlock);catch,end
        try dst=handlesToNames(pc(k).DstBlock);catch,end
        parts{end+1}=sprintf('type=%s pos=%s src=%s dst=%s', ...
            typ,pos,src,dst); %#ok<AGROW>
    end
    if isempty(parts),txt='NO_CONSERVING_PORTS';else,txt=strjoin(parts,' || ');end
catch ME
    txt=['UNKNOWN:' compactText(ME.message)];
end
end

function txt=blockConnectivityText(block)
txt='UNKNOWN';
try
    pc=get_param(block,'PortConnectivity');
    if isempty(pc),txt='EMPTY';return;end
    parts=cell(1,numel(pc));
    for k=1:numel(pc)
        typ='';pos='';src='';dst='';
        try typ=char(string(pc(k).Type));catch,end
        try pos=mat2str(pc(k).Position);catch,end
        try src=handlesToNames(pc(k).SrcBlock);catch,end
        try dst=handlesToNames(pc(k).DstBlock);catch,end
        parts{k}=sprintf('port%d type=%s pos=%s src=%s dst=%s', ...
            k,typ,pos,src,dst);
    end
    txt=strjoin(parts,' || ');
catch ME
    txt=['UNKNOWN:' compactText(ME.message)];
end
end

function txt=handlesToNames(h)
txt='';
if isempty(h),return;end
if iscell(h)
    vals=[];
    for i=1:numel(h)
        if isnumeric(h{i}),vals=[vals h{i}(:).'];end %#ok<AGROW>
    end
    h=vals;
end
if ~isnumeric(h),txt=char(string(h));return;end
h=h(isfinite(h)&h>0);
names={};
for k=reshape(h,1,[])
    try names{end+1}=getfullname(k); catch, end %#ok<AGROW>
end
names=unique(names,'stable');
txt=strjoin(names,'&');
end

function v=resolveScalar(mdl,raw)
v=NaN;
s=strtrim(char(string(raw)));
x=str2double(s);
if isfinite(x),v=x;return;end
try
    mw=get_param(mdl,'ModelWorkspace');
    q=evalin(mw,s);
    if isnumeric(q)&&isscalar(q)&&isfinite(double(q)),v=double(q);return;end
catch
end
try
    q=slResolve(s,mdl);
    if isnumeric(q)&&isscalar(q)&&isfinite(double(q)),v=double(q);return;end
catch
end
try
    q=evalin('base',s);
    if isnumeric(q)&&isscalar(q)&&isfinite(double(q)),v=double(q);return;end
catch
end
error('E2AUD6:Resolve','Cannot resolve scalar parameter: %s',s);
end

function s=emChartScript(blockPath)
s='';
try
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart');
    hit=[];
    for i=1:numel(charts)
        try
            if strcmp(char(charts(i).Path),blockPath),hit=charts(i);break;end
        catch
        end
    end
    if isempty(hit),error('E2AUD6:EMChart','EMChart not found for %s',blockPath);end
    s=char(hit.Script);
catch ME
    if startsWith(ME.identifier,'E2AUD6:'),rethrow(ME);end
    error('E2AUD6:EMChartAPI','Cannot read EMChart %s: %s',blockPath,ME.message);
end
end

function tf=containsNoSpace(s,pattern)
a=regexprep(char(s),'\s+','');
b=regexprep(char(pattern),'\s+','');
tf=contains(a,b);
end

function names=currentG27Schema56()
names={ ...
    'RawIdRef','RawIqRef','FinalIdRef','FinalIqRef','IdMeas','IqMeas', ...
    'VdRaw','VqRaw','VdFF','VqFF','CurrentPI_d','CurrentPI_q', ...
    'Vconv_d','Vconv_q','ModIndex','Pmeas_pu','Qmeas_pu','GammaP', ...
    'PLL_Hz','RestoreState','Vpu','VsupportRef_pu','GammaQ','PrefCmd_pu', ...
    'PrefAfterUV_pu','PrefEff_pu','LegacyQref_pu','QrefEff_pu', ...
    'TotalSupport_d','TotalSupport_q','RestoreHold','ReconnectReady', ...
    'RestoreAlpha','FinalBreakerCmd','CurrentLimit','FrameHold', ...
    'PowerReleaseAllowed','RestoreFailCode','Vbp_d','Vbp_q','SupportClip', ...
    'RawModDemand','ModHeadroom','IqSecRequest','IqSecApplied','QsecCapPos', ...
    'QsecCapNeg','QsecClip','Vinner_a','Vinner_b','Vinner_c', ...
    'Vbus_a','Vbus_b','Vbus_c','PhaseCorr','VoltageRatio'};
if numel(names)~=56,error('E2AUD6:G27Schema','Internal schema count !=56.');end
end

function names=restoreCfgNames()
names={ ...
    'CFG_ESS2_RESTORE_TS', ...
    'CFG_ESS2_RESTORE_MASTER_ENABLE', ...
    'CFG_ESS2_RESTORE_CONTROL_SOURCE', ...
    'CFG_ESS2_RESTORE_MANUAL_REQUEST', ...
    'CFG_ESS2_RESTORE_AUTO_SEQUENCE_ENABLE', ...
    'CFG_ESS2_RESTORE_BREAKER_ACTUATION_ENABLE', ...
    'CFG_ESS2_RESTORE_MANUAL_COMMIT', ...
    'CFG_ESS2_RESTORE_POWER_RELEASE_ENABLE', ...
    'CFG_ESS2_RESTORE_MANUAL_RELEASE', ...
    'CFG_ESS2_RESTORE_V_MIN_PU', ...
    'CFG_ESS2_RESTORE_V_MAX_PU', ...
    'CFG_ESS2_RESTORE_DF_MAX_HZ', ...
    'CFG_ESS2_RESTORE_IREF_MAX_PU', ...
    'CFG_ESS2_RESTORE_IMEAS_MAX_PU', ...
    'CFG_ESS2_RESTORE_HEADROOM_MIN', ...
    'CFG_ESS2_RESTORE_READY_DWELL_S', ...
    'CFG_ESS2_RESTORE_POST_DWELL_S', ...
    'CFG_ESS2_RESTORE_RELEASE_RAMP_S', ...
    'CFG_ESS2_RESTORE_PHASE_GATE_ENABLE', ...
    'CFG_ESS2_RESTORE_PHASE_COS_MIN', ...
    'CFG_ESS2_RESTORE_VMATCH_GATE_ENABLE', ...
    'CFG_ESS2_RESTORE_VINNER_TO_BUS_GAIN', ...
    'CFG_ESS2_RESTORE_VRATIO_MIN', ...
    'CFG_ESS2_RESTORE_VRATIO_MAX', ...
    'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE', ...
    'CFG_ESS2_RESTORE_POST_I_MAX_PU', ...
    'CFG_ESS2_RESTORE_POST_V_MIN_PU', ...
    'CFG_ESS2_RESTORE_POST_V_MAX_PU', ...
    'CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN'};
end

function meaning=ess2MuxMeaningCurrent(k)
switch k
    case 1,meaning='Vabc from SM prim_ESS2 output1';
    case 2,meaning='Iabc from SM prim_ESS2 output2';
    case 3,meaning='Fref';
    case 4,meaning='Vref';
    case 5,meaning='planned-island StageEcho';
    case 6,meaning='Pref';
    case 7,meaning='Qref transport';
    case 8,meaning='GridOn';
    otherwise,meaning='additional/current-build input';
end
end

function writeDialogParameters(path,block)
rows=cell(0,3);
rows(end+1,:)={'SourceType',safeGet(block,'SourceType'),'common'}; %#ok<AGROW>
rows(end+1,:)={'ReferenceBlock',safeGet(block,'ReferenceBlock'),'common'}; %#ok<AGROW>
rows(end+1,:)={'Position',safeGet(block,'Position'),'common'}; %#ok<AGROW>
try
    dp=get_param(block,'DialogParameters');
    if isstruct(dp)
        fn=fieldnames(dp);
        for k=1:numel(fn)
            rows(end+1,:)={fn{k},safeGet(block,fn{k}),'DialogParameter'}; %#ok<AGROW>
        end
    end
catch
end
writeMixedCsv(path,{'Parameter','Value','Class'},rows);
end

function ops=findAllOpWritesProven(mdl)
% Repository-proven OpWriteFile discovery pattern.
% Source: successful K26 causal-harness scripts.
blocks=find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'Type','Block');
ops={};
for i=1:numel(blocks)
    ref=rawGetOrEmpty(blocks{i},'ReferenceBlock');
    src=rawGetOrEmpty(blocks{i},'SourceBlock');
    mtype=rawGetOrEmpty(blocks{i},'MaskType');
    txt=lower([ref ' ' src ' ' mtype]);
    if contains(txt,'opwritefile')
        ops{end+1,1}=blocks{i}; %#ok<AGROW>
    end
end
ops=unique(ops,'stable');
end

function s=rawGetOrEmpty(block,param)
s='';
try
    q=get_param(block,param);
    if isnumeric(q),s=mat2str(q);
    elseif islogical(q),s=mat2str(q);
    else,s=char(string(q));
    end
catch
    s='';
end
end

function s=readMaskValueOptional(block,param)
% Optional inventory metadata: UNKNOWN is evidence, not a reason to abort.
s='';
try
    q=get_param(block,param);
    if isnumeric(q),s=mat2str(q);
    elseif islogical(q),s=mat2str(q);
    else,s=char(string(q));
    end
catch
    try
        names=get_param(block,'MaskNames');
        vals=get_param(block,'MaskValues');
        idx=find(strcmp(names,param),1);
        if ~isempty(idx),s=char(string(vals{idx}));end
    catch
    end
end
if isempty(s),s='UNKNOWN';end
end

function s=readMaskValueProven(block,param)
% Proven pattern: direct get_param first, then MaskNames/MaskValues fallback.
s='';
try
    q=get_param(block,param);
    if isnumeric(q),s=mat2str(q);
    elseif islogical(q),s=mat2str(q);
    else,s=char(string(q));
    end
catch
    try
        names=get_param(block,'MaskNames');
        vals=get_param(block,'MaskValues');
        idx=find(strcmp(names,param),1);
        if ~isempty(idx),s=char(string(vals{idx}));end
    catch
    end
end
if isempty(s)
    error('E2AUD6:MaskValue', ...
        'Cannot read required OpWrite mask/dialog parameter %s from %s.',param,block);
end
end

function v=readNumericMaskProven(block,param)
s=readMaskValueProven(block,param);
v=str2double(strtrim(s));
if ~isfinite(v)
    % Only if a mask contains a resolvable scalar expression.
    try
        q=slResolve(strtrim(s),bdroot(block));
        if isnumeric(q)&&isscalar(q)&&isfinite(double(q))
            v=double(q);
        end
    catch
    end
end
if ~isfinite(v)
    error('E2AUD6:NumericMask', ...
        'Required numeric OpWrite parameter %s is not a finite scalar at %s: %s', ...
        param,block,s);
end
end

function p=findTopPortBlock(subsys,blockType,portNum)
p='';
cand=find_system(subsys,'SearchDepth',1,'BlockType',blockType);
hits={};
for k=1:numel(cand)
    q=str2double(safeGet(cand{k},'Port'));
    if isfinite(q) && q==portNum
        hits{end+1}=cand{k}; %#ok<AGROW>
    end
end
if numel(hits)==1,p=hits{1};end
end

function H=traceHeaders()
H={'Depth','Block','OutPort','BlockType','Name','Parent','Semantic', ...
   'GotoTag','Criteria','Threshold','Inputs','SourceSummary','Note'};
end

function [route,rows,issues]=auditFromRoute(fromBlock,scopeRoot,maxDepth)
issues={};
route=struct('tag','','gotoPath','','gotoInputSource','','gotoInputSourcePort',NaN, ...
    'uniqueGoto',false,'traceHasTerminal',false,'firstSemanticAnchor','', ...
    'traceTerminalSummary','');

if getSimulinkBlockHandle(fromBlock)<0
    issues{end+1}=['missing From block: ' fromBlock];
    rows=cell(0,numel(traceHeaders()));
    return;
end
if ~strcmp(safeGet(fromBlock,'BlockType'),'From')
    issues{end+1}=['not a From block: ' fromBlock];
end
tag=safeGet(fromBlock,'GotoTag');
route.tag=tag;
[gotoPath,cands]=resolveGotoForFrom(fromBlock,scopeRoot);
if isempty(gotoPath)
    issues{end+1}=sprintf('Goto tag %s unresolved; candidates=%s',tag,strjoin(cands,' | '));
    rows=cell(0,numel(traceHeaders()));
    return;
end
route.gotoPath=gotoPath;route.uniqueGoto=true;
ph=get_param(gotoPath,'PortHandles');
[sb,sp]=portSource(ph.Inport(1));
route.gotoInputSource=sb;route.gotoInputSourcePort=sp;
[rows,traceIssues]=traceOutputUpstream(sb,sp,scopeRoot,maxDepth);
issues=[issues traceIssues]; %#ok<AGROW>
route.traceHasTerminal=~isempty(rows);
route.firstSemanticAnchor=firstTraceAnchor(rows);
route.traceTerminalSummary=traceTerminalSummary(rows);
end

function [gotoPath,cands]=resolveGotoForFrom(fromBlock,scopeRoot)
gotoPath='';cands={};
tag=safeGet(fromBlock,'GotoTag');
parent=get_param(fromBlock,'Parent');

% Proven first choice: same subsystem level.
allSame=find_system(parent,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','BlockType','Goto');
same=findByGotoTag(allSame,tag);
if numel(same)==1,gotoPath=same{1};cands=same;return;end

% Fallback: current control subtree. Never auto-pick first.
all=find_system(scopeRoot,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
hits=findByGotoTag(all,tag);
cands=hits;
if numel(hits)==1,gotoPath=hits{1};end
end

function hits=findByGotoTag(blocks,tag)
hits={};
for k=1:numel(blocks)
    if strcmp(safeGet(blocks{k},'GotoTag'),tag)
        hits{end+1}=blocks{k}; %#ok<AGROW>
    end
end
end

function [rows,issues]=traceOutputUpstream(startBlock,startOutPort,scopeRoot,maxDepth)
rows=cell(0,numel(traceHeaders()));issues={};
if isempty(startBlock)||strcmp(startBlock,'UNCONNECTED')||startsWith(startBlock,'UNKNOWN')
    issues{end+1}=['invalid trace start: ' startBlock];
    return;
end

queue={startBlock,startOutPort,0,'START'};
visited={};

while ~isempty(queue)
    b=queue{1,1};op=queue{1,2};depth=queue{1,3};via=queue{1,4};
    queue(1,:)=[];
    if depth>maxDepth
        issues{end+1}=sprintf('trace depth exceeded at %s',b); %#ok<AGROW>
        continue;
    end
    key=sprintf('%s#%s',b,valueText(op));
    if any(strcmp(visited,key)),continue;end
    visited{end+1}=key; %#ok<AGROW>

    if getSimulinkBlockHandle(b)<0
        rows(end+1,:)={depth,b,op,'MISSING','', '', '','', '', '', '', '', via}; %#ok<AGROW>
        issues{end+1}=['trace block missing: ' b]; %#ok<AGROW>
        continue;
    end

    bt=safeGet(b,'BlockType');
    nm=get_param(b,'Name');
    parent=get_param(b,'Parent');
    sem=signalSemanticAtOutput(b,op);
    tag=safeGet(b,'GotoTag');
    criteria=safeGet(b,'Criteria');
    threshold=safeGet(b,'Threshold');
    inputs=safeGet(b,'Inputs');
    srcSummary=inputSourceSummary(b);

    rows(end+1,:)={depth,b,op,bt,nm,parent,sem,tag,criteria,threshold,inputs,srcSummary,via}; %#ok<AGROW>

    % From -> unique Goto -> Goto input source.
    if strcmp(bt,'From')
        [g,cands]=resolveGotoForFrom(b,scopeRoot);
        if isempty(g)
            issues{end+1}=sprintf('trace From unresolved tag=%s candidates=%s', ...
                safeGet(b,'GotoTag'),strjoin(cands,' | ')); %#ok<AGROW>
            continue;
        end
        phg=get_param(g,'PortHandles');
        [sb,sp]=portSource(phg.Inport(1));
        queue(end+1,:)={sb,sp,depth+1,['FromTag:' safeGet(b,'GotoTag')]}; %#ok<AGROW>
        continue;
    end

    % For key current-control semantic subsystems, the top-level Outport name
    % is already the fact we need. Stop here instead of diving into unrelated
    % filter/PI internals and creating false max-depth blockers.
    if strcmp(bt,'SubSystem') && isfiniteScalar(op)
        semLower=lower(sem);
        if contains(semLower,'measurements/') || ...
           contains(semLower,'power control loop/') || ...
           contains(semLower,'aa15_gfl_island_support/') || ...
           contains(semLower,'current regulator/')
            continue;
        end
        ob=findTopPortBlock(b,'Outport',round(op));
        if ~isempty(ob)
            pho=get_param(ob,'PortHandles');
            [sb,sp]=portSource(pho.Inport(1));
            queue(end+1,:)={sb,sp,depth+1,['SubsystemOut:' get_param(ob,'Name')]}; %#ok<AGROW>
            continue;
        end
    end

    % Inport block inside a subsystem -> source connected to parent subsystem port.
    if strcmp(bt,'Inport')
        pn=str2double(safeGet(b,'Port'));
        par=get_param(b,'Parent');
        if ~strcmp(par,bdroot(b)) && getSimulinkBlockHandle(par)>0
            php=get_param(par,'PortHandles');
            if isfinite(pn)&&pn>=1&&pn<=numel(php.Inport)
                [sb,sp]=portSource(php.Inport(round(pn)));
                if ~strcmp(sb,'UNCONNECTED')
                    queue(end+1,:)={sb,sp,depth+1,['CrossInport:' get_param(b,'Name')]}; %#ok<AGROW>
                end
            end
        end
        continue;
    end

    % Generic ordinary block: traverse every real input. This is deliberate
    % for Switch/Mux/Sum/Product because ALL candidate/control paths matter.
    try ph=get_param(b,'PortHandles');catch,ph=struct();end
    if isstruct(ph)&&isfield(ph,'Inport')
        for q=1:numel(ph.Inport)
            [sb,sp]=portSource(ph.Inport(q));
            if strcmp(sb,'UNCONNECTED'),continue;end
            queue(end+1,:)={sb,sp,depth+1,sprintf('%s/in%d',bt,q)}; %#ok<AGROW>
        end
    end
end
end

function s=firstTraceAnchor(rows)
s='';
if isempty(rows),return;end
for k=1:size(rows,1)
    sem=rows{k,7};
    if contains(sem,'Measurements/') || contains(sem,'Power Control Loop/') || ...
       contains(sem,'ESS2_IO_Demux') || contains(sem,'AA15_GFL_ISLAND_SUPPORT')
        s=sem;return;
    end
end
s=rows{end,7};
end

function s=traceTerminalSummary(rows)
if isempty(rows),s='EMPTY';return;end
maxDepth=max(cell2mat(rows(:,1)));
idx=find(cell2mat(rows(:,1))==maxDepth);
parts={};
for k=reshape(idx,1,[])
    parts{end+1}=sprintf('%s :: %s',rows{k,2},rows{k,7}); %#ok<AGROW>
end
s=strjoin(unique(parts,'stable'),' | ');
end

function s=signalSemanticAtOutput(block,outPort)
s='';
if getSimulinkBlockHandle(block)<0,s='MISSING';return;end
bt=safeGet(block,'BlockType');

if strcmp(bt,'SubSystem') && isfiniteScalar(outPort)
    ob=findTopPortBlock(block,'Outport',round(outPort));
    if ~isempty(ob)
        s=sprintf('%s/%s[out%d]',get_param(block,'Name'),get_param(ob,'Name'),round(outPort));
        return;
    end
end
if strcmp(bt,'From')||strcmp(bt,'Goto')
    s=sprintf('%s(tag=%s)',bt,safeGet(block,'GotoTag'));return;
end
if strcmp(bt,'Inport')||strcmp(bt,'Outport')
    s=sprintf('%s(port=%s,name=%s)',bt,safeGet(block,'Port'),get_param(block,'Name'));return;
end
s=sprintf('%s/%s#out%s',bt,get_param(block,'Name'),valueText(outPort));
end

function s=inputSourceSummary(block)
s='';
if getSimulinkBlockHandle(block)<0,return;end
try ph=get_param(block,'PortHandles');catch,return;end
if ~isfield(ph,'Inport')||isempty(ph.Inport),return;end
parts={};
for k=1:numel(ph.Inport)
    [sb,sp]=portSource(ph.Inport(k));
    parts{end+1}=sprintf('in%d<-%s#%s',k,sb,valueText(sp)); %#ok<AGROW>
end
s=strjoin(parts,' ; ');
end

function rows=auditSubsystemInterface(subsys)
rows=cell(0,8);
ph=get_param(subsys,'PortHandles');

for k=1:numel(ph.Inport)
    ib=findTopPortBlock(subsys,'Inport',k);
    if isempty(ib),ib='NO_TOPLEVEL_INPORT_BLOCK';nm='';else,nm=get_param(ib,'Name');end
    [sb,sp]=portSource(ph.Inport(k));
    rows(end+1,:)={'IN',k,ib,nm,sb,sp,signalSemanticAtOutput(sb,sp), ...
        ternary(~strcmp(sb,'UNCONNECTED'),'PASS','UNCONNECTED')}; %#ok<AGROW>
end

for k=1:numel(ph.Outport)
    ob=findTopPortBlock(subsys,'Outport',k);
    if isempty(ob)
        rows(end+1,:)={'OUT',k,'NO_TOPLEVEL_OUTPORT_BLOCK','',subsys,k, ...
            'parent destination only','UNKNOWN_INTERNAL_OUTPORT'}; %#ok<AGROW>
    else
        nm=get_param(ob,'Name');
        phi=get_param(ob,'PortHandles');
        [sb,sp]=portSource(phi.Inport(1));
        rows(end+1,:)={'OUT',k,ob,nm,sb,sp,signalSemanticAtOutput(sb,sp),'PASS'}; %#ok<AGROW>
    end
end
end

function [cfg,issue]=parseAdapterCfgVector(script)
cfg=[];issue='';
tok=regexp(script,'z,\[([^\]]+)\]\);','tokens','once');
if isempty(tok),issue='cannot locate K26 current-adapter cfg vector';return;end
vals=str2num(tok{1}); %#ok<ST2NM>
if isempty(vals)||numel(vals)<14
    issue=sprintf('cfg vector parse produced %d values',numel(vals));return;
end
cfg=double(vals(:).');
end

function [v,ok]=resolveNumericExpr(mdl,raw)
v=NaN;ok=false;
s=strtrim(char(string(raw)));
if isempty(s)||strcmpi(s,'UNKNOWN'),return;end
x=str2num(s); %#ok<ST2NM>
if ~isempty(x)&&isnumeric(x)&&all(isfinite(x(:)))
    v=double(x);ok=true;return;
end
try
    mw=get_param(mdl,'ModelWorkspace');
    q=evalin(mw,s);
    if isnumeric(q)&&all(isfinite(q(:))),v=double(q);ok=true;return;end
catch
end
try
    q=slResolve(s,mdl);
    if isnumeric(q)&&all(isfinite(q(:))),v=double(q);ok=true;return;end
catch
end
try
    q=evalin('base',s);
    if isnumeric(q)&&all(isfinite(q(:))),v=double(q);ok=true;return;end
catch
end
end

function [rows,files]=searchEMChartsForPatterns(root,patterns,outDir,prefix)
rows=cell(0,4);files={};
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart');
idx=0;
for k=1:numel(charts)
    try p=char(charts(k).Path);catch,continue;end
    if ~(strcmp(p,root)||startsWith(p,[root '/'])),continue;end
    try sc=char(charts(k).Script);catch,continue;end
    matched={};
    for q=1:numel(patterns)
        if contains(lower(sc),lower(patterns{q}))
            matched{end+1}=patterns{q}; %#ok<AGROW>
        end
    end
    if isempty(matched),continue;end
    idx=idx+1;
    fn=fullfile(outDir,sprintf('%s_%02d_%s.mtxt',prefix,idx,sanitizeName(get_param(p,'Name'))));
    writeText(fn,sc);
    files{end+1}=fn; %#ok<AGROW>
    snippet=scriptSnippet(sc,matched{1},180);
    for q=1:numel(matched)
        rows(end+1,:)={p,matched{q},snippet,fn}; %#ok<AGROW>
    end
end
end

function s=scriptSnippet(script,pattern,n)
i=strfind(lower(script),lower(pattern));
if isempty(i),s='';return;end
a=max(1,i(1)-n);b=min(numel(script),i(1)+numel(pattern)+n);
s=compactText(script(a:b));
end

function rows=searchBlocksByKeywords(root,keywords)
blocks=find_system(root,'LookUnderMasks','all','FollowLinks','on','Type','Block');
rows=cell(0,6);
for k=1:numel(blocks)
    b=blocks{k};
    hay=lower([get_param(b,'Name') ' ' safeGet(b,'GotoTag') ' ' ...
        safeGet(b,'Value') ' ' safeGet(b,'MaskType')]);
    hit=false;
    for q=1:numel(keywords)
        if contains(hay,lower(keywords{q})),hit=true;break;end
    end
    if ~hit,continue;end
    rows(end+1,:)={b,safeGet(b,'BlockType'),get_param(b,'Name'), ...
        safeGet(b,'GotoTag'),safeGet(b,'Value'),blockConnectivityText(b)}; %#ok<AGROW>
end
end

function rows=findPhysicalNodeNeighbors(root,anchor)
blocks=find_system(root,'LookUnderMasks','all','FollowLinks','on','Type','Block');
rows=cell(0,6);
anchorName=get_param(anchor,'Name');
for k=1:numel(blocks)
    b=blocks{k};
    txt=conservingConnectivityText(b);
    if strcmp(b,anchor)||contains(txt,anchor)||contains(txt,anchorName)
        rows(end+1,:)={b,safeGet(b,'BlockType'),safeGet(b,'SourceType'), ...
            safeGet(b,'ReferenceBlock'),safeGet(b,'Measurements'),txt}; %#ok<AGROW>
    end
end
end

function tf=isfiniteScalar(x)
tf=isnumeric(x)&&isscalar(x)&&isfinite(x);
end

function v=maskOrDialogParam(block,name)
v='UNKNOWN';
try
    v=get_param(block,name);
    if isnumeric(v),v=mat2str(v);else,v=char(string(v));end
    return;
catch
end
try
    m=get_param(block,'MaskNames');
    vals=get_param(block,'MaskValues');
    idx=find(strcmp(m,name),1);
    if ~isempty(idx)
        v=vals{idx};
        return;
    end
catch
end
end

function v=safeGet(block,param)
v='UNKNOWN';
try
    q=get_param(block,param);
    if isnumeric(q),v=mat2str(q);
    elseif islogical(q),v=mat2str(q);
    else,v=char(string(q));
    end
catch
end
end

function p=canonicalPath(p)
try p=char(java.io.File(p).getCanonicalPath());catch,p=char(p);end
end

function h=hashText(text)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
md.update(typecast(uint8(unicode2native(char(text),'UTF-8')),'int8'));
raw=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(raw,2).',1,[]));
end

function hash=sha256File(path)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
fid=fopen(path,'rb');
if fid<0,error('E2AUD6:HashRead','Cannot read: %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true
    bytes=fread(fid,1024*1024,'*uint8');
    if isempty(bytes),break;end
    md.update(typecast(bytes(:),'int8'));
end
raw=typecast(md.digest(),'uint8');
hash=lower(reshape(dec2hex(raw,2).',1,[]));
end

function s=compactText(s)
s=regexprep(char(s),'\s+',' ');
s=strtrim(s);
end

function s=valueText(x)
if isnumeric(x)
    if isscalar(x),s=sprintf('%.17g',x);else,s=mat2str(x);end
elseif islogical(x),s=mat2str(x);
else,s=char(string(x));
end
end

function s=yesno(tf)
if tf,s='YES';else,s='NO';end
end

function s=passFail(tf)
if tf,s='PASS';else,s='FAIL';end
end

function y=ternary(tf,a,b)
if tf,y=a;else,y=b;end
end

function s=sanitizeName(s)
s=regexprep(char(s),'[^A-Za-z0-9_\-]','_');
if isempty(s),s='block';end
end

function writeMixedCsv(path,headers,rows)
if isempty(rows),rows=cell(0,numel(headers));end
if size(rows,2)~=numel(headers)
    error('E2AUD6:CSVWidth','CSV width mismatch: %s headers=%d rows=%d', ...
        path,numel(headers),size(rows,2));
end
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('E2AUD6:Write','Cannot write: %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
writeCsvLine(fid,headers);
for r=1:size(rows,1),writeCsvLine(fid,rows(r,:));end
end

function writeCsvLine(fid,row)
parts=cell(1,numel(row));
for c=1:numel(row)
    x=row{c};
    if isnumeric(x)&&isscalar(x)
        if isnan(x),parts{c}='NaN';else,parts{c}=sprintf('%.17g',double(x));end
    elseif islogical(x)&&isscalar(x)
        parts{c}=sprintf('%d',x);
    else
        if isstring(x),x=char(x);end
        if ~ischar(x),x=char(string(x));end
        parts{c}=['"' strrep(x,'"','""') '"'];
    end
end
fprintf(fid,'%s\n',strjoin(parts,','));
end

function writeText(path,text)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('E2AUD6:Write','Cannot write: %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',text);
end

function safeClose(fid)
try if fid>0,fclose(fid);end,catch,end
end

function closeIfOwned(mdl,wasLoaded)
if ~wasLoaded && bdIsLoaded(mdl)
    try
        if strcmp(get_param(mdl,'Dirty'),'off'),close_system(mdl,0);end
    catch
    end
end
end

function files=allFiles(root,rel)
d=dir(fullfile(root,rel));files={};
for i=1:numel(d)
    if strcmp(d(i).name,'.')||strcmp(d(i).name,'..'),continue;end
    r=fullfile(rel,d(i).name);
    if d(i).isdir
        q=allFiles(root,r);files=[files q]; %#ok<AGROW>
    else
        files{end+1}=r; %#ok<AGROW>
    end
end
end

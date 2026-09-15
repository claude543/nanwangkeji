function result = AUDIT_K26_K50_S14_V2_ESS2_POWER_PICKUP_ARCH_R1(modelRoot)
% AUDIT_K26_K50_S14_V2_ESS2_POWER_PICKUP_ARCH_R1
% =========================================================================
% K26_K50_CLEAN_P1
% S14（策略14黑启动）V2 + ESS2（储能2）首次非零功率承担
% 正式改模前一次性、无死角、只读架构审计 R1
%
% 目的
% ----
% 这不是新的控制器，也不修改模型。本脚本只读回答下一轮正式改模前必须
% 一次性锁死的问题：
%
% A. 当前 Advanced_Microgrid_15_Strategies / Advanced_Strategy_Core 中
%    S14 的真实源码、20/40/60 s 时间推进、输入/输出以及是否已有
%    “物理恢复完成确认”输入；
%
% B. 当前 AA15_Black_Start_Pref_Gate（黑启动有功参考门）如何根据
%    S14 stage（阶段）直接释放 ESS/PV/EV Pref（有功参考），以及它是否
%    知道真实 breaker（断路器）/RESTORED（恢复完成）状态；
%
% C. 当前 S14 black-start stage（黑启动阶段）与
%    AA15_FINAL_SYSTEM_STAGE（计划孤岛统一工程阶段）是否仍是两套不同
%    语义；统一工程阶段是否同时送给五台 GFL（跟网型）；
%
% D. 当前 AA15_FINAL_ISLAND_COORDINATOR（正常孤岛协调器）真实输入、
%    输出、内部状态、二次调频积分、五资源能力分配；是否存在
%    “物理已恢复/在线/断路器闭合” availability（可用性）输入；
%
% E. 当前只有 ESS2 恢复时，正常 Coordinator 是否仍按五台 GFL 的
%    capability/headroom（能力/余量）参与分配；它是否显式看到 ESS1
%    GFM（构网型）的电流/调制/PQ 余量；严禁把设备额定能力误当黑启动
%    稳定功率能力；
%
% F. ESS2 真实 Pref 从 SM_Master 到 SS_Slave2/ESS2_Control 的端到端
%    路由、Goto/From、Switch/Product/Saturation 等仲裁；重点锁死
%    “正常 Coordinator / S14 / takeover / diagnostic override”谁最终拥有
%    ESS2 有功目标；
%
% G. ESS2 Restore Executor（恢复执行器）当前 state0~5 是否仍保持
%    已被 R6.1/R7 实验验证成功的语义；state6/7 是否仍是开放环
%    RestoreAlpha（恢复系数）时间斜坡与 alpha=1 即 RESTORED；
%
% H. ESS2 Power Loop（功率环）的 P/Q 误差、双 RestoreAlpha、PI 参数、
%    离散积分器、输出下游路径；Power PI 是否有任何来自最终实际执行
%    IrefUsed（实际电流参考）/CurrentLimit（限流）/Current Adapter
%    （电流执行适配器）的 tracking/back-calculation（执行跟踪/反算）
%    输入。找不到必须明确写 NO_DOWNSTREAM_TRACKING_FOUND，不猜。
%
% I. ESS2 restore status（恢复状态）是否已经通过 SS2->SM 返回链回到
%    SM_Master；当前 S14 策略是否真正消费这些状态，还是仍完全不知道
%    state5/7/FailCode。
%
% J. 当前五台非主设备物理连接控制 CFG_DIAG_AC_CONNECT_* 的保存值、
%    消费者，以及正常 Coordinator 是否看得到这些物理可用性。
%
% K. 当前 G27（ESS2高速诊断）62通道、G26~G30五组 OpWrite 合同；
%    下一轮固定小功率平台试验还缺哪些证据。禁止新增 G31。
%
% L. 最终输出精确 modification matrix（修改矩阵）：
%      MUST_MODIFY / MUST_MODIFY_BEFORE_HANDOVER /
%      MUST_MODIFY_BEFORE_PV_EV / REVIEW / FREEZE
%    每一项给出当前路径、当前事实、下一步职责和推荐实现方式。
%
% 用户当前冻结原则
% ----------------
% 1) 原始15策略算法代码允许且必须为了实现策略功能而修改；
% 2) 不再为了“保护原算法”在外围无限叠加状态机/Function；
% 3) S14负责系统级黑启动决策，SS本地负责设备快速执行；
% 4) ESS2彻底跑通以前不复制到PV/EV；
% 5) state0~5当前先冻结，不重做；
% 6) 下一轮先清理现有架构缺陷，再用固定小功率平台回答
%    “ESS2到底能否稳定承担非零功率”，不先堆最终复杂回退逻辑；
% 7) 只有ESS2恢复时，不能因为系统只剩ESS1+ESS2就让ESS2承担很大功率。
%    ESS1是唯一GFM，必须保留电压/频率、电流、调制及PQ余量。
%
% 永久只读边界（继承已成功R3审计模板）
% ------------------------------------
% - 不修改参数，不增删块，不增删线；
% - 不 update / compile / save；
% - 不连接 RT-LAB，不 Execute / Reset / Load；
% - whole-SLX raw SHA 只记录，不作为语义硬门；
% - 当前 SLX 真实图结构 > 历史文档；
% - UNKNOWN 保持 UNKNOWN，绝不补0；
% - SPS（专用电力系统）物理连线不使用普通Simulink信号规则；
% - 普通信号：connectivity first, name second；
% - 审计结束再次确认 Model Dirty=off；
% - 输出全部证据后再给结论，尽量一次审完，不遇到第一个可选问题就退出。
%
% MATLAB R2023b
% =========================================================================

VERSION = 'K26_K50_S14_V2_ESS2_POWER_PICKUP_ARCH_AUDIT_R1_20260914';
MODEL = 'K26_K50_CLEAN_P1';
SHA_POLICY = 'RECORD_ONLY_NOT_A_SEMANTIC_HARD_GATE';

if nargin < 1 || isempty(modelRoot)
    modelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot = canonicalPath(char(modelRoot));
modelFile = fullfile(modelRoot,[MODEL '.slx']);

if ~isfile(modelFile)
    error('S14V2AUD1:ModelMissing','Current model file missing: %s',modelFile);
end

sourceSha = sha256File(modelFile);
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
outDir = fullfile(modelRoot,['AUDIT_S14_V2_ESS2_POWER_PICKUP_R1_' stamp]);
mkdir(outDir);

summaryFile = fullfile(outDir,'00_READ_FIRST.txt');
fid = fopen(summaryFile,'w','n','UTF-8');
if fid < 0
    error('S14V2AUD1:Output','Cannot create summary: %s',summaryFile);
end
fidCleanup = onCleanup(@()safeClose(fid)); %#ok<NASGU>

result = struct();
result.version = VERSION;
result.modelFile = modelFile;
result.sourceSha256 = sourceSha;
result.shaPolicy = SHA_POLICY;
result.outputDirectory = outDir;
result.status = 'STARTED';

fprintf(fid,'S14 V2 + ESS2首次功率承担：正式改模前一次性只读架构审计 R1\n');
fprintf(fid,'Version : %s\n',VERSION);
fprintf(fid,'Model   : %s\n',modelFile);
fprintf(fid,'SHA256  : %s\n',sourceSha);
fprintf(fid,'SHA策略 : %s\n\n',SHA_POLICY);

wasLoaded = bdIsLoaded(MODEL);
if wasLoaded
    loadedFile = canonicalPath(get_param(MODEL,'FileName'));
    if ~strcmpi(loadedFile,modelFile)
        error('S14V2AUD1:WrongLoadedModel', ...
            'Same-name model loaded from another path.\nLoaded: %s\nExpected: %s', ...
            loadedFile,modelFile);
    end
else
    load_system(modelFile);
end
closeCleanup = onCleanup(@()closeIfOwned(MODEL,wasLoaded)); %#ok<NASGU>

if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('S14V2AUD1:DirtyStart','Model is Dirty at audit start. Abort.');
end

SM = [MODEL '/SM_Master'];
SS2 = [MODEL '/SS_Slave2'];
strategy = [SM '/Advanced_Microgrid_15_Strategies'];
stack = [SM '/AA15_LOCAL_CONTROL_STACK'];
bsGate = [stack '/AA15_Black_Start_Pref_Gate'];

control = [SS2 '/ESS2_Control'];
power = [control '/Power Control Loop'];
wrapper = [control '/AA15_GFL_ISLAND_SUPPORT'];
manager = [wrapper '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
adapter = [wrapper '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];
adapterCore = [adapter '/CORE'];

executor = [SS2 '/AA15_ESS2_RESTORE_EXECUTOR'];
executorCore = [executor '/CORE'];
executorDemux = [SS2 '/AA15_ESS2_RESTORE_EXECUTOR_DEMUX'];
cfgSub = [SS2 '/AA15_ESS2_RESTORE_CONFIG'];
breakerRouter = [SS2 '/AA15_ESS2_RESTORE_BREAKER_ROUTER'];

ess2Mux = [SM '/ESS2_IO_Mux12'];
essGroupMux = [SM '/ESS_Group_Mux24'];
essGroupDemux = [SS2 '/ESS_Group_Demux'];
ess2Demux = [SS2 '/ESS2_IO_Demux'];

% Current cleanup model moved planned-island coordinator under a wrapper.
islandWrap = findUniqueBlockByName(MODEL,'AA15_ISLAND_SUPERVISORY_COORDINATION');
coord = findUniqueBlockByName(MODEL,'AA15_FINAL_ISLAND_COORDINATOR');
engStage = findUniqueBlockByName(MODEL,'AA15_FINAL_SYSTEM_STAGE');

critical = {SM,SS2,strategy,stack,bsGate,control,power,wrapper,manager, ...
    adapter,adapterCore,executor,executorCore,executorDemux,cfgSub, ...
    breakerRouter,ess2Mux,essGroupMux,essGroupDemux,ess2Demux, ...
    islandWrap,coord,engStage};
for k=1:numel(critical),mustBlock(critical{k});end

issueRows = cell(0,5);

% =========================================================================
% 0. Semantic identity + read-only boundary
% =========================================================================
identityRows = {
    'ModelName',get_param(MODEL,'Name'),MODEL,strcmp(get_param(MODEL,'Name'),MODEL),'hard';
    'ModelFile',modelFile,modelFile,true,'hard';
    'CurrentRawSHA256',sourceSha,'record only',true,'provenance';
    'ModelDirtyStart',get_param(MODEL,'Dirty'),'off',strcmpi(get_param(MODEL,'Dirty'),'off'),'hard';
    'SolverType',safeGet(MODEL,'SolverType'),'project fixed-step baseline',true,'info';
    'FixedStep',safeGet(MODEL,'FixedStep'),'100 us project baseline',true,'info';
    'AdvancedStrategy',strategy,'must exist',getSimulinkBlockHandle(strategy)>0,'hard';
    'BlackStartPrefGate',bsGate,'must exist',getSimulinkBlockHandle(bsGate)>0,'hard';
    'PlannedIslandCoordinator',coord,'must exist',getSimulinkBlockHandle(coord)>0,'hard';
    'EngineeringStage',engStage,'must exist',getSimulinkBlockHandle(engStage)>0,'hard';
    'ESS2RestoreExecutor',executor,'must exist',getSimulinkBlockHandle(executor)>0,'hard';
    'ESS2PowerLoop',power,'must exist',getSimulinkBlockHandle(power)>0,'hard';
    };
idOut=cell(size(identityRows,1),6);
for k=1:size(identityRows,1)
    idOut(k,:)={identityRows{k,1},identityRows{k,2},identityRows{k,3}, ...
        identityRows{k,4},passFail(logical(identityRows{k,4})),identityRows{k,5}};
end
writeMixedCsv(fullfile(outDir,'00A_SEMANTIC_IDENTITY.csv'), ...
    {'Item','Observed','ExpectedOrMeaning','ObservedOK','Status','Class'},idOut);

% =========================================================================
% 1. CURRENT Advanced_Strategy_Core: exact S14 source / interface
% =========================================================================
strategyCore = [strategy '/Advanced_Strategy_Core'];
if ~chartExists(strategyCore)
    strategyCore = findChartUnderByTokens(strategy,{'black_state','black'});
end
if isempty(strategyCore)
    error('S14V2AUD1:StrategyCore','Cannot identify current Advanced_Strategy_Core chart.');
end

strategyScript = emChartScript(strategyCore);
strategyHash = hashText(strategyScript);
writeText(fullfile(outDir,'01_ADVANCED_STRATEGY_CORE_CURRENT_SOURCE.mtxt'),strategyScript);
writeText(fullfile(outDir,'01A_S14_BLACKSTART_SOURCE_CONTEXT.txt'), ...
    sourceContext(strategyScript,{'black_state','black_timer','blackstart','s14'},5));

strategyIn = subsystemInputRows(strategy);
strategyOut = subsystemOutputRows(strategy);
writeMixedCsv(fullfile(outDir,'02_STRATEGY_TOP_INTERFACE_INPUTS.csv'), ...
    {'Port','InportName','InportPath','ExternalSource','SourcePort','SourceType','GotoTag','Value'},strategyIn);
writeMixedCsv(fullfile(outDir,'03_STRATEGY_TOP_INTERFACE_OUTPUTS.csv'), ...
    {'Port','OutportName','OutportPath','ExternalConsumers'},strategyOut);

s14Ctx = sourceContext(strategyScript,{'black_state','black_timer','blackstart','s14'},5);
s14Compact = lower(regexprep(s14Ctx,'\s+',''));
strategyInputText = lower(strjoin(cellfun(@(x)char(string(x)),strategyIn(:),'UniformOutput',false),'|'));

hasBlackState = contains(lower(strategyScript),'black_state');
hasBlackTimer = contains(lower(strategyScript),'black_timer');
has20 = ~isempty(regexp(s14Ctx,'(^|[^0-9])20(\.0+)?([^0-9]|$)','once'));
has40 = ~isempty(regexp(s14Ctx,'(^|[^0-9])40(\.0+)?([^0-9]|$)','once'));
has60 = ~isempty(regexp(s14Ctx,'(^|[^0-9])60(\.0+)?([^0-9]|$)','once'));

ackKeywords = {'restored_ack','restore_ack','device_restored','physical_ready', ...
    'restore_state','breaker_status','device_available','resource_available'};
ackPresence = false(size(ackKeywords));
for k=1:numel(ackKeywords)
    ackPresence(k)=contains(lower(strategyScript),ackKeywords{k}) || ...
        contains(strategyInputText,ackKeywords{k});
end
hasPhysicalAckSemantics = any(ackPresence);

s14Facts = {
    'StrategyCorePath',strategyCore,'exact current chart';
    'StrategyCoreSHA256',strategyHash,'source provenance';
    'Has_black_state',hasBlackState,'current source token';
    'Has_black_timer',hasBlackTimer,'current source token';
    'S14ContextContains20s',has20,'time-stage evidence';
    'S14ContextContains40s',has40,'time-stage evidence';
    'S14ContextContains60s',has60,'time-stage evidence';
    'HasPhysicalRestoreAckSemantic',hasPhysicalAckSemantics, ...
        'search: restored/restore_ack/physical_ready/restore_state/breaker_status/device_available';
    };
writeMixedCsv(fullfile(outDir,'04_S14_CURRENT_ALGORITHM_FACTS.csv'), ...
    {'Item','Observed','Meaning'},s14Facts);

ackRows=cell(numel(ackKeywords),3);
for k=1:numel(ackKeywords)
    ackRows(k,:)={ackKeywords{k},ackPresence(k), ...
        ternary(ackPresence(k),'FOUND_IN_STRATEGY_SOURCE_OR_INPUT','NOT_FOUND')};
end
writeMixedCsv(fullfile(outDir,'04A_S14_ACK_KEYWORD_AUDIT.csv'), ...
    {'Keyword','Present','Status'},ackRows);

if has20 && has40 && has60 && ~hasPhysicalAckSemantics
    issueRows(end+1,:)={'S14_TIME_DRIVEN_RESTORE',true,'ARCHITECTURE', ...
        'S14 current black-start context contains 20/40/60 staging but no physical restore ACK semantics.', ...
        'MUST_MODIFY'}; %#ok<AGROW>
end

% =========================================================================
% 2. Current Black Start Pref Gate: direct stage -> Pref release?
% =========================================================================
bsCore = [bsGate '/AA15_Black_Start_Pref_Gate_Core'];
if ~chartExists(bsCore)
    bsCore = findChartUnderByTokens(bsGate,{'stage_echo','seq_active','pv1o'});
end
if isempty(bsCore)
    error('S14V2AUD1:BSGateCore','Cannot identify black-start Pref Gate core.');
end

bsScript=emChartScript(bsCore);
bsHash=hashText(bsScript);
writeText(fullfile(outDir,'05_BLACK_START_PREF_GATE_CURRENT_SOURCE.mtxt'),bsScript);
writeText(fullfile(outDir,'05A_BLACK_START_PREF_GATE_STAGE_CONTEXT.txt'), ...
    sourceContext(bsScript,{'st>=2','st>=3','st>=4','stage','pref'},4));

bsIn=subsystemInputRows(bsGate);
bsOut=subsystemOutputRows(bsGate);
writeMixedCsv(fullfile(outDir,'06_BLACK_START_PREF_GATE_INPUTS.csv'), ...
    {'Port','InportName','InportPath','ExternalSource','SourcePort','SourceType','GotoTag','Value'},bsIn);
writeMixedCsv(fullfile(outDir,'07_BLACK_START_PREF_GATE_OUTPUTS.csv'), ...
    {'Port','OutportName','OutportPath','ExternalConsumers'},bsOut);

bsTokens = {
    'Stage2_nonmaster_ESS_release', containsNoSpace(bsScript,'ifst>=2');
    'Stage3_PV_release', containsNoSpace(bsScript,'ifst>=3');
    'Stage4_EV_release', containsNoSpace(bsScript,'ifst>=4');
    'GateKnowsRestoreState', contains(lower(bsScript),'restore_state') || contains(lower(bsScript),'restored');
    'GateKnowsBreakerStatus', contains(lower(bsScript),'breaker_status') || contains(lower(bsScript),'breakerclosed');
    'GateKnowsAvailability', contains(lower(bsScript),'available') || contains(lower(bsScript),'availability');
    };
bsTokenRows=cell(size(bsTokens,1),4);
for k=1:size(bsTokens,1)
    bsTokenRows(k,:)={bsTokens{k,1},bsTokens{k,2},true,passFail(logical(bsTokens{k,2}))};
end
writeMixedCsv(fullfile(outDir,'08_BLACK_START_PREF_GATE_SEMANTICS.csv'), ...
    {'Semantic','Observed','Reference','Status'},bsTokenRows);

% Stage ownership / Goto-From evidence.
s14StageGotos=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on', ...
    'BlockType','Goto','GotoTag','AA15_BS_STAGE_ECHO');
s14StageFroms=find_system(MODEL,'LookUnderMasks','all','FollowLinks','on', ...
    'BlockType','From','GotoTag','AA15_BS_STAGE_ECHO');
stageOwnershipRows = {
    'LOCAL15_S14_stage','AA15_BS_STAGE_ECHO',numel(s14StageGotos),numel(s14StageFroms), ...
        'black-start requested stage';
    'PlannedIsland_EngineeringStage',engStage,'n/a','n/a', ...
        'different semantic: global GFL engineering stage';
    };
writeMixedCsv(fullfile(outDir,'09_STAGE_OWNERSHIP_SEPARATION.csv'), ...
    {'Item','TagOrPath','GotoCount','FromCount','Meaning'},stageOwnershipRows);

% =========================================================================
% 3. Normal island Coordinator exact interface/source/state/capability
% =========================================================================
coordCore=[coord '/AA15_FINAL_COORD_CORE'];
if ~chartExists(coordCore)
    coordCore=findChartUnderByTokens(coord,{'dp_primary','psecn','up1'});
end
if isempty(coordCore)
    error('S14V2AUD1:CoordCore','Cannot identify current planned-island coordinator core.');
end

coordScript=emChartScript(coordCore);
coordHash=hashText(coordScript);
writeText(fullfile(outDir,'10_COORDINATOR_CORE_CURRENT_SOURCE.mtxt'),coordScript);
writeText(fullfile(outDir,'10A_COORDINATOR_CAPABILITY_CONTEXT.txt'), ...
    sourceContext(coordScript,{'pmin3','pmax3','upT','dnT','dpt','psecn','dp_secondary'},5));

coordIn=subsystemInputRows(coord);
coordOut=subsystemOutputRows(coord);
writeMixedCsv(fullfile(outDir,'11_COORDINATOR_INPUT_INTERFACE.csv'), ...
    {'Port','InportName','InportPath','ExternalSource','SourcePort','SourceType','GotoTag','Value'},coordIn);
writeMixedCsv(fullfile(outDir,'12_COORDINATOR_OUTPUT_INTERFACE.csv'), ...
    {'Port','OutportName','OutportPath','ExternalConsumers'},coordOut);

coordInputNames=lower(strjoin(cellfun(@(x)char(string(x)),coordIn(:,2),'UniformOutput',false),'|'));
availTokens={'avail','available','restor','connected','breaker','online','deviceenable','resourceenable'};
availHit=false(size(availTokens));
for k=1:numel(availTokens),availHit(k)=contains(coordInputNames,availTokens{k});end
coordHasAvailability=any(availHit);

% Explicit GFM reserve/headroom sensing: SOC alone does NOT count.
ess1ReservePatterns={'ess1_current','ess1_id','ess1_iq','ess1_mod','ess1_headroom', ...
    'ess1_pmeas','ess1_qmeas','gfm_current','gfm_mod','gfm_headroom','master_current'};
ess1ReserveHit=false(size(ess1ReservePatterns));
for k=1:numel(ess1ReservePatterns)
    ess1ReserveHit(k)=contains(coordInputNames,ess1ReservePatterns{k});
end
coordHasExplicitGFMReserve=any(ess1ReserveHit);

coordInterfaceFacts = {
    'CoordinatorPath',coord,'current';
    'CoordinatorCoreSHA256',coordHash,'source provenance';
    'HasPhysicalAvailabilityInput',coordHasAvailability, ...
        'availability/restored/connected/breaker/online input name scan';
    'HasExplicitESS1GFMReserveInput',coordHasExplicitGFMReserve, ...
        'ESS1 current/modulation/PQ/headroom input scan; SOC does not count';
    'HasPV1Pmeas',contains(coordInputNames,'pmeaspv1'),'normal five-GFL dispatch input';
    'HasPV2Pmeas',contains(coordInputNames,'pmeaspv2'),'normal five-GFL dispatch input';
    'HasESS2Pmeas',contains(coordInputNames,'pmeasess2'),'normal five-GFL dispatch input';
    'HasEV1Pmeas',contains(coordInputNames,'pmeasev1'),'normal five-GFL dispatch input';
    'HasEV2Pmeas',contains(coordInputNames,'pmeasev2'),'normal five-GFL dispatch input';
    };
writeMixedCsv(fullfile(outDir,'13_COORDINATOR_ARCHITECTURE_FACTS.csv'), ...
    {'Item','Observed','Meaning'},coordInterfaceFacts);

availRows=cell(numel(availTokens),3);
for k=1:numel(availTokens)
    availRows(k,:)={availTokens{k},availHit(k), ...
        ternary(availHit(k),'MATCH_IN_COORDINATOR_INPUT_NAME','NO_MATCH')};
end
writeMixedCsv(fullfile(outDir,'13A_COORDINATOR_AVAILABILITY_INPUT_SCAN.csv'), ...
    {'Pattern','Present','Status'},availRows);

% Coordinator parameters and state blocks, especially secondary integrators.
coordParams=find_system(coord,'LookUnderMasks','all','FollowLinks','on', ...
    'SearchDepth',2,'RegExp','on','Name','^AA15_P_.*');
coordParamRows=cell(0,5);
for k=1:numel(coordParams)
    coordParamRows(end+1,:)={coordParams{k},get_param(coordParams{k},'Name'), ...
        safeGet(coordParams{k},'Value'),safeGet(coordParams{k},'BlockType'), ...
        safeGet(coordParams{k},'SampleTime')}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'14_COORDINATOR_PARAMETERS.csv'), ...
    {'Path','Name','Value','BlockType','SampleTime'},coordParamRows);

coordStates=find_system(coord,'LookUnderMasks','all','FollowLinks','on', ...
    'SearchDepth',2,'RegExp','on','Name','^AA15_STATE_.*');
coordStateRows=cell(0,7);
for k=1:numel(coordStates)
    ph=get_param(coordStates{k},'PortHandles');
    src='NO_INPORT';sp=NaN;
    if ~isempty(ph.Inport),[src,sp]=portSource(ph.Inport(1));end
    coordStateRows(end+1,:)={coordStates{k},get_param(coordStates{k},'Name'), ...
        safeGet(coordStates{k},'BlockType'),safeGet(coordStates{k},'InitialCondition'), ...
        safeGet(coordStates{k},'SampleTime'),src,sp}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'15_COORDINATOR_STATE_BLOCKS.csv'), ...
    {'Path','Name','BlockType','InitialCondition','SampleTime','InputSource','SourcePort'},coordStateRows);

coordCoreFacts = {
    'SourceContains_pmin3_minus1',containsNoSpace(coordScript,'pmin3=-1.0'),'ESS2 equipment lower capability';
    'SourceContains_pmax3_plus1',containsNoSpace(coordScript,'pmax3=1.0'),'ESS2 equipment upper capability';
    'SourceContains_upT_five_sum',containsNoSpace(coordScript,'upT=up1+up2+up3+up4+up5'),'five-resource headroom sum';
    'SourceContains_dnT_five_sum',containsNoSpace(coordScript,'dnT=dn1+dn2+dn3+dn4+dn5'),'five-resource down headroom sum';
    'SourceContains_Stage3_Psecondary',containsNoSpace(coordScript,'elseif s==3.0') && contains(lower(coordScript),'psecn'), ...
        'normal-island secondary frequency restoration exists';
    };
writeMixedCsv(fullfile(outDir,'16_COORDINATOR_SOURCE_FACTS.csv'), ...
    {'Item','Observed','Meaning'},coordCoreFacts);

if ~coordHasAvailability
    issueRows(end+1,:)={'COORD_NO_PHYSICAL_AVAILABILITY_MASK',true,'ARCHITECTURE', ...
        'Normal-island Coordinator has no explicit restored/connected/breaker availability input.', ...
        'MUST_MODIFY_BEFORE_HANDOVER'}; %#ok<AGROW>
end
if ~coordHasExplicitGFMReserve
    issueRows(end+1,:)={'COORD_NO_EXPLICIT_ESS1_GFM_RESERVE',true,'ARCHITECTURE', ...
        'Coordinator interface does not explicitly expose ESS1 GFM current/modulation/PQ/headroom; two-device island does not imply ESS2 may take large power.', ...
        'MUST_MODIFY_BEFORE_HANDOVER'}; %#ok<AGROW>
end

% =========================================================================
% 4. Global engineering stage reaches five GFLs?
% =========================================================================
stageValue=safeGet(engStage,'Value');
stageConsumers=consumersFromBlockOutput(engStage,1);
stageRows=cell(0,11);

D = struct( ...
    'device',{'PV1','PV2','ESS2','EV1','EV2'}, ...
    'task',{'SS_Slave3','SS_Slave3','SS_Slave2','SS_Slave','SS_Slave'}, ...
    'control',{ ...
        [MODEL '/SS_Slave3/PV1_Control'], ...
        [MODEL '/SS_Slave3/PV2_Control'], ...
        [MODEL '/SS_Slave2/ESS2_Control'], ...
        [MODEL '/SS_Slave/EV1_Control'], ...
        [MODEL '/SS_Slave/Control System']}, ...
    'smMux',{ ...
        [SM '/PV1_IO_Mux12'], ...
        [SM '/PV2_IO_Mux12'], ...
        [SM '/ESS2_IO_Mux12'], ...
        [SM '/EV1_IO_Mux'], ...
        [SM '/EV2_IO_Mux']} ...
    );

for i=1:numel(D)
    mustBlock(D(i).control);
    w=[D(i).control '/AA15_GFL_ISLAND_SUPPORT'];
    m=[w '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
    mustBlock(w);mustBlock(m);
    mgrStage=sourceToSubsystemInput(m,'SystemStage');
    ctrlDroop=sourceToSubsystemInput(D(i).control,'Droop_On');
    muxStage='MISSING_MUX';muxStagePort=NaN;muxStageSrc='UNKNOWN';muxStageUp='UNKNOWN';
    if getSimulinkBlockHandle(D(i).smMux)>0
        phm=get_param(D(i).smMux,'PortHandles');
        if numel(phm.Inport)>=5
            [muxStageSrc,muxStagePort]=portSource(phm.Inport(5));
            muxStageUp=ultimateSourceText(muxStageSrc,SM);
        end
        muxStage=D(i).smMux;
    end
    stageRows(end+1,:)={D(i).device,D(i).task,D(i).control,w,m, ...
        mgrStage,ctrlDroop,muxStage,muxStageSrc,muxStagePort,muxStageUp}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'17_GLOBAL_ENGINEERING_STAGE_TO_FIVE_GFL.csv'), ...
    {'Device','Task','Control','Wrapper','Manager','ManagerSystemStageSource', ...
     'ControlDroopOnExternalSource','SMDeviceMux','MuxInput5Source','MuxInput5SourcePort','MuxInput5UltimateSource'},stageRows);

stageGlobalFacts = {
    'EngineeringStagePath',engStage,'current';
    'EngineeringStageSavedValue',stageValue,'runtime-tunable constant';
    'EngineeringStageDirectConsumers',stageConsumers,'ordinary-signal consumers';
    'SingleGlobalStageForFiveGFL',true,'current planned-island architecture assumption';
    };
writeMixedCsv(fullfile(outDir,'18_GLOBAL_ENGINEERING_STAGE_FACTS.csv'), ...
    {'Item','Observed','Meaning'},stageGlobalFacts);

% =========================================================================
% 5. ESS2 Pref command end-to-end ownership / arbitration
% =========================================================================
phEss2Mux=get_param(ess2Mux,'PortHandles');
if numel(phEss2Mux.Inport)<8
    error('S14V2AUD1:ESS2MuxPorts','ESS2_IO_Mux12 has fewer than 8 inputs.');
end
[ess2PrefSrc,ess2PrefSrcPort]=portSource(phEss2Mux.Inport(6));
ess2PrefUltimate=ultimateSourceText(ess2PrefSrc,SM);

prefRouteRows = {
    'SM_ESS2_IO_Mux_input6',ess2Mux,6,ess2PrefSrc,ess2PrefSrcPort,ess2PrefUltimate, ...
        'actual Pref sent toward SS2';
    'SS2_ESS2_Control_Pref',control,str2double(findInportPort(control,'Pref')), ...
        sourceToSubsystemInput(control,'Pref'),NaN,'cross-task device demux route', ...
        'actual Pref entering ESS2_Control';
    };
writeMixedCsv(fullfile(outDir,'19_ESS2_PREF_ROUTE_ENDPOINTS.csv'), ...
    {'Item','Parent','Port','DirectSource','SourcePort','UltimateOrMeaning','Role'},prefRouteRows);

traceRows=traceUpstreamGraph(ess2PrefSrc,SM,14);
writeMixedCsv(fullfile(outDir,'20_ESS2_PREF_UPSTREAM_TRACE.csv'), ...
    {'Depth','Block','BlockType','Via','GotoTag','Value','InputPortCount','Note'},traceRows);

% Explicitly inventory likely arbitration blocks/tags around final ESS2 Pref.
ess2PrefRelated=findBlocksByKeyword(SM,{'ESS2','FINAL','PREF','TAKEOVER','OVERRIDE'});
writeMixedCsv(fullfile(outDir,'21_ESS2_PREF_RELATED_BLOCK_INVENTORY.csv'), ...
    {'Path','BlockType','Name','GotoTag','Value','Criteria','Threshold','InputCount','OutputCount'},ess2PrefRelated);

coordPrefOut=findOutportBlock(coord,'PrefESS2');
coordPrefConsumers='NOT_FOUND';
if ~isempty(coordPrefOut)
    pnum=str2double(safeGet(coordPrefOut,'Port'));
    phc=get_param(coord,'PortHandles');
    if isfinite(pnum) && pnum>=1 && pnum<=numel(phc.Outport)
        coordPrefConsumers=consumersOfPort(phc.Outport(pnum));
    end
end
writeMixedCsv(fullfile(outDir,'22_COORDINATOR_ESS2_PREF_OUTPUT_ROUTE.csv'), ...
    {'Item','PathOrValue','Meaning'}, {
    'Coordinator_PrefESS2_Outport',coordPrefOut,'normal-island ESS2 Pref output';
    'Coordinator_PrefESS2_Consumers',coordPrefConsumers,'actual outside consumers';
    'ESS2_Device_Pref_Source',ess2PrefSrc,'SM device mux input6 source';
    'ESS2_Device_Pref_Ultimate',ess2PrefUltimate,'Goto/From-resolved source if unique';
    });

% =========================================================================
% 6. Restore status return to SM and whether S14 consumes it
% =========================================================================
restoreBlocksSM=findBlocksByKeyword(SM,{'RESTORE','ESS2_RESTORE','RESTORED'});
writeMixedCsv(fullfile(outDir,'23_SM_RESTORE_RELATED_BLOCKS.csv'), ...
    {'Path','BlockType','Name','GotoTag','Value','Criteria','Threshold','InputCount','OutputCount'},restoreBlocksSM);

returnCandidates = {
    [SS2 '/Mux'];
    [SS2 '/AA15_V48_RETURN_APPEND_MUX'];
    [SS2 '/Memory'];
    [SS2 '/ESS_Pmeas_vec2_to_SM'];
    [SM '/ESS_Pmeas_vec2_from_SS'];
    [SM '/Demux1'];
    };
retRows=cell(0,7);
for k=1:numel(returnCandidates)
    p=returnCandidates{k};
    if getSimulinkBlockHandle(p)>0
        ph=get_param(p,'PortHandles');
        retRows(end+1,:)={p,safeGet(p,'BlockType'),safeGet(p,'Inputs'), ...
            safeGet(p,'Outputs'),safeGet(p,'InitialCondition'), ...
            numel(ph.Inport),numel(ph.Outport)}; %#ok<AGROW>
    else
        retRows(end+1,:)={p,'NOT_FOUND','','','','',''}; %#ok<AGROW>
    end
end
writeMixedCsv(fullfile(outDir,'24_ESS2_STATUS_RETURN_CHAIN_BOUNDARY.csv'), ...
    {'Path','BlockType','Inputs','Outputs','InitialCondition','InportCount','OutportCount'},retRows);

strategyRestoreConsumer = false;
for k=1:size(strategyIn,1)
    txt=lower(strjoin(cellfun(@(x)char(string(x)),strategyIn(k,:),'UniformOutput',false),'|'));
    if contains(txt,'restore') || contains(txt,'restored') || contains(txt,'ess2_restore')
        strategyRestoreConsumer=true;
    end
end
if contains(lower(strategyScript),'restore_state') || contains(lower(strategyScript),'restored_ack')
    strategyRestoreConsumer=true;
end
writeMixedCsv(fullfile(outDir,'25_S14_RESTORE_STATUS_CONSUMPTION.csv'), ...
    {'Item','Observed','Meaning'}, {
    'S14ConsumesESS2RestoreStatus',strategyRestoreConsumer, ...
        'current strategy input/source/code scan';
    'SMHasRestoreRelatedBlocks',~isempty(restoreBlocksSM), ...
        'restore status may already return to SM even if S14 does not consume it';
    });

if ~strategyRestoreConsumer
    issueRows(end+1,:)={'S14_NO_ESS2_RESTORE_ACK_CONSUMER',true,'ARCHITECTURE', ...
        'ESS2 restore status may return to SM, but current S14 strategy does not consume restore/restored semantics.', ...
        'MUST_MODIFY'}; %#ok<AGROW>
end

% =========================================================================
% 7. ESS2 Restore Executor exact current states: freeze 0~5, isolate 6~7 defect
% =========================================================================
execScript=emChartScript(executorCore);
execHash=hashText(execScript);
writeText(fullfile(outDir,'26_RESTORE_EXECUTOR_CURRENT_SOURCE.mtxt'),execScript);
writeText(fullfile(outDir,'26A_RESTORE_EXECUTOR_STATE_CONTEXT.txt'), ...
    sourceContext(execScript,{'state==3','state==4','state==5','state==6','state==7','releaseAlpha'},5));

stateFacts = {
    'state3_rechecks_ready',containsNoSpace(execScript,'elseifstate==3') && containsNoSpace(execScript,'elseifready<0.5');
    'state3_commit_to_state4',containsNoSpace(execScript,'state=4;readyCount=0;postCount=0');
    'state4_breaker_closed',containsNoSpace(execScript,'elseifstate==4') && containsNoSpace(execScript,'breakerCmd=1');
    'state4_hold0',containsNoSpace(execScript,'elseifstate==4') && containsNoSpace(sourceContext(execScript,{'elseif state==4'},12),'hold=0');
    'state4_postOK_dwell_to_state5',containsNoSpace(execScript,'ifpostOK>0.5') && containsNoSpace(execScript,'state=5;readyCount=0;postCount=0');
    'state5_breaker_closed',containsNoSpace(execScript,'elseifstate==5') && containsNoSpace(execScript,'breakerCmd=1');
    'state5_hold0',containsNoSpace(execScript,'elseifstate==5') && containsNoSpace(sourceContext(execScript,{'elseif state==5'},12),'hold=0');
    'state5_zeroStable_dwell',containsNoSpace(execScript,'zeroStableOK') && containsNoSpace(execScript,'zeroStableDwell');
    'state6_open_loop_time_alpha',containsNoSpace(execScript,'releaseAlpha=min(1,releaseAlpha+Ts/releaseRamp)');
    'state7_alpha_forced_one',containsNoSpace(execScript,'state=7;releaseAlpha=1') || ...
        (containsNoSpace(execScript,'elseifstate==7') && containsNoSpace(execScript,'releaseAlpha=1'));
    };
stateRows=cell(size(stateFacts,1),5);
for k=1:size(stateFacts,1)
    stateRows(k,:)={stateFacts{k,1},stateFacts{k,2},true,passFail(logical(stateFacts{k,2})), ...
        ternary(k<=8,'state0~5 freeze evidence','state6/7 redesign evidence')};
end
writeMixedCsv(fullfile(outDir,'27_RESTORE_EXECUTOR_STATE_FACTS.csv'), ...
    {'Semantic','Observed','ExpectedCurrent','Status','Class'},stateRows);

freeze05=all(cell2mat(stateFacts(1:8,2)));
openLoop67=stateFacts{9,2} && stateFacts{10,2};

if openLoop67
    issueRows(end+1,:)={'ESS2_STATE6_7_OPEN_LOOP_COMPLETION',true,'CONTROL_SEMANTIC', ...
        'state6 increments RestoreAlpha only by time; state7 completion is alpha=1, not physical restored verification.', ...
        'MUST_MODIFY_BEFORE_FINAL'}; %#ok<AGROW>
end

% =========================================================================
% 8. ESS2 Power Loop / double alpha / PI state / downstream tracking
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

piRows=cell(0,15);
piDefs={ 'P',pPI,pInts; 'Q',qPI,qInts };
for i=1:2
    nm=piDefs{i,1};pi=piDefs{i,2};ints=piDefs{i,3};
    ph=get_param(pi,'PortHandles');
    intPath='COUNT_NOT_1'; intIC=''; intReset=''; intMethod=''; intUpper=''; intLower='';
    if numel(ints)==1
        intPath=ints{1};
        intIC=safeGet(intPath,'InitialCondition');
        intReset=safeGet(intPath,'ExternalReset');
        intMethod=safeGet(intPath,'IntegratorMethod');
        intUpper=safeGet(intPath,'UpperSaturationLimit');
        intLower=safeGet(intPath,'LowerSaturationLimit');
    end
    froms=find_system(pi,'LookUnderMasks','all','FollowLinks','on','BlockType','From');
    fromTags=cell(1,numel(froms));
    for j=1:numel(froms),fromTags{j}=safeGet(froms{j},'GotoTag');end
    piRows(end+1,:)={nm,pi,safeGet(pi,'MaskType'),safeGet(pi,'Kp'),safeGet(pi,'Ki'), ...
        safeGet(pi,'Par_Limits'),safeGet(pi,'Init'),safeGet(pi,'Ts'), ...
        numel(ph.Inport),numel(ph.Outport),intPath,intIC,intReset,intMethod,strjoin(fromTags,'|')}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'28_POWER_PI_EXACT_STRUCTURE.csv'), ...
    {'Axis','PIPath','MaskType','Kp','Ki','Limits','Init','Ts','ExternalInports','ExternalOutports', ...
     'DiscreteIntegrator','IntegratorIC','ExternalReset','IntegratorMethod','InternalFromTags'},piRows);

pPIConsumers=consumersFromBlockOutput(pPI,1);
qPIConsumers=consumersFromBlockOutput(qPI,1);
adapterScript=emChartScript(adapterCore);
adapterHash=hashText(adapterScript);

doubleAlpha = directConnectionExists([power '/RestoreAlpha'],1,pProd,2) && ...
              directConnectionExists([power '/RestoreAlpha'],1,qProd,2) && ...
              containsNoSpace(adapterScript,'iref_used=a*iref');

% Direct external-tracking evidence. One-error-input PI with no From tag referencing
% execution/current-limit cannot know final downstream execution directly.
pHasTracking = piHasDownstreamTrackingEvidence(pPI);
qHasTracking = piHasDownstreamTrackingEvidence(qPI);
trackingStatus = ternary(pHasTracking||qHasTracking,'TRACKING_EVIDENCE_FOUND','NO_DOWNSTREAM_TRACKING_FOUND');

powerFacts = {
    'PerrorSign',safeGet(pSum,'Inputs'),'Pref - Pmeas expected';
    'QerrorSign',safeGet(qSum,'Inputs'),'Qmeas - Qref expected';
    'RestoreAlphaBeforePPI',directConnectionExists([power '/RestoreAlpha'],1,pProd,2),'alpha multiplies P error';
    'RestoreAlphaBeforeQPI',directConnectionExists([power '/RestoreAlpha'],1,qProd,2),'alpha multiplies Q error';
    'RestoreAlphaAgainInCurrentAdapter',containsNoSpace(adapterScript,'iref_used=a*iref'),'alpha multiplies final current reference';
    'DoubleAlphaCurrentDesign',doubleAlpha,'current saved architecture';
    'PPIOutputConsumers',pPIConsumers,'downstream path';
    'QPIOutputConsumers',qPIConsumers,'downstream path';
    'PPIHasDownstreamTrackingEvidence',pHasTracking,trackingStatus;
    'QPIHasDownstreamTrackingEvidence',qHasTracking,trackingStatus;
    'CurrentAdapterSHA256',adapterHash,'source provenance';
    };
writeMixedCsv(fullfile(outDir,'29_POWER_RECOVERY_AND_TRACKING_FACTS.csv'), ...
    {'Item','Observed','Meaning'},powerFacts);

if ~(pHasTracking||qHasTracking)
    issueRows(end+1,:)={'POWER_PI_NO_DOWNSTREAM_EXECUTION_TRACKING',true,'CONTROL_DESIGN', ...
        'No static evidence that Power PI receives IrefUsed/CurrentLimit/adapter execution tracking; verify before changing PI gains.', ...
        'REVIEW'}; %#ok<AGROW>
end

% =========================================================================
% 9. Physical availability / five non-master breakers vs Coordinator knowledge
% =========================================================================
devAvailNames={'PV1','PV2','ESS2','EV1','EV2'};
availCfgNames={'CFG_DIAG_AC_CONNECT_PV1','CFG_DIAG_AC_CONNECT_PV2', ...
    'CFG_DIAG_AC_CONNECT_ESS2','CFG_DIAG_AC_CONNECT_EV1','CFG_DIAG_AC_CONNECT_EV2'};
physAvailRows=cell(0,8);
for i=1:numel(availCfgNames)
    b=findUniqueBlockByNameOptional(MODEL,availCfgNames{i});
    if isempty(b)
        physAvailRows(end+1,:)={devAvailNames{i},availCfgNames{i},'NOT_FOUND','','','','',false}; %#ok<AGROW>
    else
        ph=get_param(b,'PortHandles');
        cons='NO_OUTPORT';
        if ~isempty(ph.Outport),cons=consumersOfPort(ph.Outport(1));end
        coordSees=contains(lower(coordInputNames),lower(devAvailNames{i})) && ...
            (contains(lower(coordInputNames),'avail') || contains(lower(coordInputNames),'breaker'));
        physAvailRows(end+1,:)={devAvailNames{i},availCfgNames{i},b,safeGet(b,'Value'), ...
            safeGet(b,'BlockType'),cons,'physical isolation/connection control',coordSees}; %#ok<AGROW>
    end
end
writeMixedCsv(fullfile(outDir,'30_PHYSICAL_RESOURCE_AVAILABILITY_CONTROLS.csv'), ...
    {'Device','ConfigName','Path','SavedValue','BlockType','Consumers','Meaning','CoordinatorExplicitlySeesAvailability'},physAvailRows);

% =========================================================================
% 10. "Only ESS2 restored" safe-dispatch audit
% =========================================================================
onlyEss2Rows = {
    'ESS1_is_unique_GFM',true,'project frozen fact','ESS1 must retain V/f and current/modulation/PQ reserve';
    'Only_ESS2_first_restored_GFL',true,'current black-start prototype','PV/EV remain physically isolated';
    'CoordinatorHasFiveGFLPmeasInputs', ...
        contains(coordInputNames,'pmeaspv1')&&contains(coordInputNames,'pmeaspv2')&& ...
        contains(coordInputNames,'pmeasess2')&&contains(coordInputNames,'pmeasev1')&&contains(coordInputNames,'pmeasev2'), ...
        'current normal-island architecture','five-resource dispatch assumption';
    'CoordinatorHasPhysicalAvailabilityMask',coordHasAvailability,'current interface scan', ...
        'must be true before normal handover during sequential black start';
    'CoordinatorHasExplicitESS1GFMReserve',coordHasExplicitGFMReserve,'current interface scan', ...
        'must constrain safe dispatch when only one GFL is restored';
    'ESS2EquipmentCapabilityMinus1Plus1', ...
        containsNoSpace(coordScript,'pmin3=-1.0')&&containsNoSpace(coordScript,'pmax3=1.0'), ...
        'coordinator source','equipment capability is NOT black-start stability-safe pickup bound';
    'SafeESS2PickupPowerKnownFromStaticModel',false,'NOT_KNOWN', ...
        'must be identified by clean fixed-power experiment; R7 does not prove a nonzero plateau';
    'R7FirstDiagnosticPlateauRecommendation','-0.003 to -0.005 pu','diagnostic starting range only', ...
        'not a certified stable capability';
    };
writeMixedCsv(fullfile(outDir,'31_ONLY_ESS2_RESTORED_DISPATCH_BOUNDARY.csv'), ...
    {'Item','Observed','EvidenceClass','Meaning'},onlyEss2Rows);

% =========================================================================
% 11. G26~G30 / current G27 62-channel evidence contract
% =========================================================================
ops=findAllOpWritesProven(MODEL);
opRows=cell(0,13);
opGroups=nan(1,numel(ops));
for k=1:numel(ops)
    b=ops{k};
    g=readNumericMaskProven(b,'Acq_Group');
    d=readNumericMaskProven(b,'Decimation');
    opGroups(k)=g;
    ph=get_param(b,'PortHandles');
    src='NO_INPORT';sp=NaN;
    if ~isempty(ph.Inport),[src,sp]=portSource(ph.Inport(1));end
    opRows(end+1,:)={b,g,d,readMaskValueOptional(b,'varname'), ...
        readMaskValueOptional(b,'Filename'),readMaskValueOptional(b,'file_size'), ...
        readMaskValueOptional(b,'Nb_Samples'),src,sp,safeGet(src,'BlockType'), ...
        safeGet(b,'ReferenceBlock'),safeGet(b,'SourceBlock'),safeGet(b,'MaskType')}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'32_OPWRITE_INVENTORY.csv'), ...
    {'Block','AcqGroup','Decimation','VarName','Filename','FileSize','NbSamples', ...
     'InputSource','SourcePort','InputSourceType','ReferenceBlock','SourceBlock','MaskType'},opRows);

g27=findOpWriteByGroup(ops,27);
g27Norm=findUniqueBlockByNameOptional(SS2,'AA15_ESS2_RESTORE_G27_VECTOR_NORMALIZER');
g27Repack=findUniqueBlockByNameOptional(SS2,'AA15_ESS2_RESTORE_G27_REPACK');
g27Facts=cell(0,3);
if ~isempty(g27)
    g27Facts(end+1,:)={'G27Path',g27,'current'}; %#ok<AGROW>
    g27Facts(end+1,:)={'G27Decimation',readNumericMaskProven(g27,'Decimation'),'expected current 4'}; %#ok<AGROW>
    g27Facts(end+1,:)={'G27VarName',readMaskValueOptional(g27,'varname'),'rootdiag_ess2_data'}; %#ok<AGROW>
end
if ~isempty(g27Norm)
    d62=findUniqueBlockByNameOptional(g27Norm,'Demux62');
    m62=findUniqueBlockByNameOptional(g27Norm,'Mux62');
    g27Facts(end+1,:)={'NormalizerPath',g27Norm,'current'}; %#ok<AGROW>
    g27Facts(end+1,:)={'Demux62',ternary(~isempty(d62),safeGet(d62,'Outputs'),'NOT_FOUND'),'62 scalar outputs expected'}; %#ok<AGROW>
    g27Facts(end+1,:)={'Mux62',ternary(~isempty(m62),safeGet(m62,'Inputs'),'NOT_FOUND'),'62 scalar inputs expected'}; %#ok<AGROW>
end
if ~isempty(g27Repack) && chartExists(g27Repack)
    repackScript=emChartScript(g27Repack);
    writeText(fullfile(outDir,'33_G27_REPACK_CURRENT_SOURCE.mtxt'),repackScript);
    g27Facts(end+1,:)={'RepackY62',containsNoSpace(repackScript,'y=zeros(62,1)'),'current 62-channel contract'}; %#ok<AGROW>
end
writeMixedCsv(fullfile(outDir,'34_G27_CURRENT_CONTRACT.csv'), ...
    {'Item','Observed','Meaning'},g27Facts);

diag62=currentG27Schema62();
diagRows=cell(numel(diag62),4);
for k=1:numel(diag62)
    diagRows(k,:)={k,k+1,diag62{k},ternary(k>=57,'restore execution extension','existing/core')};
end
writeMixedCsv(fullfile(outDir,'35_G27_SCHEMA62.csv'), ...
    {'DeviceChannel','MATRow','Signal','Class'},diagRows);

futureDiag = {
    'FixedPickupTarget_pu','MISSING_OR_NOT_DEDICATED','SM/S14 or ESS2 pickup command','REQUIRED_NEXT_CAUSAL_TEST';
    'PickupAuthorityOrMode','MISSING_OR_NOT_DEDICATED','state5+ power ownership','REQUIRED_NEXT_CAUSAL_TEST';
    'Perror','DERIVABLE','PrefEff-Pmeas','DERIVE_OR_LOG';
    'PowerPI_Output_dq','PARTLY_EXISTING','RawIdRef/FinalIref G27 ch1-4','CHECK_SUFFICIENCY';
    'PowerPI_IntegratorState','NOT_EXPLICIT','inside Power PI','RECOMMENDED_IF_TINY_PLATFORM_FAILS';
    'IrefUsed_dq','EXISTING','G27 ch57-58','KEEP';
    'ImeasUsed_dq','EXISTING','G27 ch59-60','KEEP';
    'MatchActive','EXISTING','G27 ch61','KEEP';
    'PostOK','EXISTING','G27 ch62','KEEP';
    'ESS1_GFM_Reserve','SYSTEM_SIDE','G29/G30 / future supervisor evidence','DO_NOT_DUPLICATE_ALL_IN_G27';
    };
writeMixedCsv(fullfile(outDir,'36_NEXT_POWER_PICKUP_DIAGNOSTIC_REQUIREMENTS.csv'), ...
    {'Signal','Availability','LocationOrDerivation','Decision'},futureDiag);

% =========================================================================
% 12. One-pass modification matrix
% =========================================================================
modifyRows = {
    'S14_BLACKSTART_ALGORITHM',strategyCore,'MUST_MODIFY', ...
        'Current S14 is time/stage oriented and lacks physical restore ACK semantics.', ...
        'Modify Strategy 14 itself: event/physical-confirmation driven advancement; time only dwell/timeout.', ...
        'Strategy core / Stateflow or existing core implementation chosen after audit; no new Strategy16';
    'BLACK_START_PREF_GATE',bsGate,'MUST_MODIFY_OR_SIMPLIFY', ...
        'Current stage gate releases Pref by stage and does not prove physical completion.', ...
        'Pref release must be subordinate to S14/device restored authority; avoid hidden early target.', ...
        'Prefer native Switch/Enable/Rate Limiter where simple; no extra state machine unless required';
    'NORMAL_ISLAND_COORD_AVAILABILITY',coord,'MUST_MODIFY_BEFORE_HANDOVER', ...
        'Normal Coordinator sees five resources but no explicit restored/connected mask.', ...
        'Add per-resource availability/restored qualification; unavailable resources contribute zero dispatch capability.', ...
        'Modify existing Coordinator, do NOT create a second long-term Coordinator';
    'NORMAL_COORD_ESS1_GFM_RESERVE',coord,'MUST_MODIFY_BEFORE_HANDOVER', ...
        'Only ESS2 restored does not mean ESS2 may take large power; ESS1 remains unique GFM.', ...
        'Add/consume explicit ESS1 GFM reserve or authority limit before assigning restored ESS2 significant power.', ...
        'Reuse existing ESS1 measurements/headroom if available; exact signal chosen after audit results';
    'COORD_HIDDEN_STATE_HANDOVER',coord,'MUST_MODIFY_BEFORE_HANDOVER', ...
        'R7 showed ESS2 target can accumulate while RestoreAlpha=0.', ...
        'Freeze/track/reset ESS2-specific target state during black-start pickup and initialize handover from actual stable operating point.', ...
        'Modify existing Coordinator state/ownership; no parallel permanent dispatcher';
    'GLOBAL_ENGINEERING_STAGE',engStage,'MUST_MODIFY_BEFORE_PV_EV', ...
        'One global stage is valid for planned island where five GFLs are already online, not sequential physical restoration.', ...
        'Do not solve now by copying PV/EV logic. Add per-device restore authority only after ESS2 prototype is complete.', ...
        'DEFER actual PV/EV implementation';
    'ESS2_RESTORE_STATE0_5',executorCore,ternary(freeze05,'FREEZE','REVIEW'), ...
        'R6.1/R7 physically validated zero-power reconnect path; current source tokens re-audited.', ...
        'Do not redesign state0~5 now.', ...
        'Existing implementation retained';
    'ESS2_RESTORE_STATE6_7',executorCore,'MUST_MODIFY_BEFORE_FINAL', ...
        'Current state6/7 are time-alpha completion, not physical restored verification.', ...
        'For next causal test bypass open-loop full release; first establish fixed small nonzero power plateau.', ...
        'Final health-gated rollback design comes AFTER causal plateau test';
    'ESS2_POWER_PI_TRACKING',pPI,'REVIEW', ...
        trackingStatus, ...
        'Do not tune Kp/Ki first. Determine whether actual downstream execution tracking/anti-windup is required.', ...
        'Prefer existing/native anti-windup/tracking structure if needed';
    'ESS2_CURRENT_ADAPTER',adapterCore,'FREEZE', ...
        'R5/R6/R7 proved real-current zero-power correction works.', ...
        'Do not add a second current controller.', ...
        'Keep current adapter/helper unless new contradictory evidence appears';
    'ESS2_FIXED_SMALL_POWER_TEST','N/A','NEXT_EXPERIMENT', ...
        'R7 did not test any fixed nonzero plateau.', ...
        'After architecture cleanup: fixed target approx -0.003~-0.005 pu, slow approach, hold 3~5 s; then decide whether nonzero equilibrium exists.', ...
        'Diagnostic test only, not final safe-capability claim';
    'PV_EV_RESTORE_COPY','N/A','FREEZE_NOT_NOW', ...
        'ESS2 prototype not yet complete at nonzero power.', ...
        'Do not replicate ESS2 restore machinery to PV/EV yet.', ...
        'Wait for ESS2 full PASS';
    };

writeMixedCsv(fullfile(outDir,'37_MODIFICATION_MATRIX.csv'), ...
    {'Area','ExactPathOrArea','Decision','CurrentFact','RequiredBehavior','ImplementationBoundary'},modifyRows);

% =========================================================================
% 13. Final issue matrix + summary
% =========================================================================
if isempty(issueRows)
    issueRows={'NONE',false,'INFO','No architecture issue automatically flagged. Review evidence tables.','INFO'};
end
writeMixedCsv(fullfile(outDir,'38_ARCHITECTURE_ISSUES.csv'), ...
    {'Issue','Observed','Class','Evidence','Decision'},issueRows);

hardEvidence = freeze05 && ~isempty(strategyCore) && ~isempty(bsCore) && ...
    ~isempty(coordCore) && getSimulinkBlockHandle(ess2Mux)>0 && ...
    getSimulinkBlockHandle(executor)>0 && getSimulinkBlockHandle(power)>0;

if hardEvidence
    finalStatus='READ_ONLY_ARCHITECTURE_AUDIT_COMPLETE_READY_FOR_S14_V2_DESIGN';
else
    finalStatus='READ_ONLY_ARCHITECTURE_AUDIT_COMPLETE_REVIEW_HARD_EVIDENCE';
end

result.status=finalStatus;
result.strategyCorePath=strategyCore;
result.strategyCoreSha256=strategyHash;
result.blackStartGateCorePath=bsCore;
result.blackStartGateCoreSha256=bsHash;
result.coordinatorPath=coord;
result.coordinatorCorePath=coordCore;
result.coordinatorCoreSha256=coordHash;
result.coordinatorHasPhysicalAvailabilityInput=coordHasAvailability;
result.coordinatorHasExplicitESS1GFMReserveInput=coordHasExplicitGFMReserve;
result.ess2RestoreExecutorSha256=execHash;
result.ess2State0to5FreezeEvidence=freeze05;
result.ess2State6to7OpenLoopEvidence=openLoop67;
result.powerRecoveryDoubleAlpha=doubleAlpha;
result.powerPITrackingStatus=trackingStatus;
result.opWriteCount=numel(ops);
result.opWriteGroups=sort(round(opGroups(isfinite(opGroups))));
result.modelDirtyAtEnd=get_param(MODEL,'Dirty');

writeText(fullfile(outDir,'RESULT.json'),jsonencode(result,'PrettyPrint',true));

fprintf(fid,'\n==================== FINAL READ-ONLY SUMMARY ====================\n');
fprintf(fid,'Current S14 source/path identified             : PASS\n');
fprintf(fid,'S14 20/40/60 evidence                          : %s/%s/%s\n',yesno(has20),yesno(has40),yesno(has60));
fprintf(fid,'S14 physical restore ACK semantics present     : %s\n',yesno(hasPhysicalAckSemantics));
fprintf(fid,'Black Start Pref Gate source identified        : PASS\n');
fprintf(fid,'Coordinator physical availability input        : %s\n',yesno(coordHasAvailability));
fprintf(fid,'Coordinator explicit ESS1 GFM reserve input    : %s\n',yesno(coordHasExplicitGFMReserve));
fprintf(fid,'ESS2 state0~5 freeze evidence                  : %s\n',yesno(freeze05));
fprintf(fid,'ESS2 state6/7 open-loop completion evidence    : %s\n',yesno(openLoop67));
fprintf(fid,'Power recovery double-alpha                    : %s\n',yesno(doubleAlpha));
fprintf(fid,'Power PI downstream tracking                   : %s\n',trackingStatus);
fprintf(fid,'Current OpWrite count/groups                   : %d / %s\n', ...
    numel(ops),mat2str(sort(round(opGroups(isfinite(opGroups))))));
fprintf(fid,'Only-ESS2-restored safe power                  : NOT inferred from static capability.\n');
fprintf(fid,'Next causal plateau                            : approx -0.003~-0.005 pu, diagnostic only, after architecture cleanup.\n');
fprintf(fid,'Final audit status                             : %s\n',finalStatus);
fprintf(fid,'Model Dirty at end                             : %s\n',get_param(MODEL,'Dirty'));
fprintf(fid,'NO update / compile / edit / save / RT-LAB action was performed.\n');

if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('S14V2AUD1:DirtyEnd','Read-only audit unexpectedly dirtied the model.');
end

fclose(fid);
zipPath=[outDir '.zip'];
zip(zipPath,allFiles(outDir,''),outDir);
result.evidenceZip=zipPath;

fprintf('\nS14 V2 + ESS2 power-pickup architecture audit R1 complete.\n');
fprintf('Output: %s\n',outDir);
fprintf('ZIP   : %s\n',zipPath);
fprintf('Status: %s\n',finalStatus);
fprintf('Model was NOT updated, compiled, edited, or saved.\n');

end

% =========================================================================
% Helpers -- reused/adapted from project-proven R3 read-only audits
% =========================================================================
function mustBlock(p)
if getSimulinkBlockHandle(p) < 0
    error('S14V2AUD1:MissingBlock','Missing current block: %s',p);
end
end

function p=findUniqueBlockByName(root,name)
hits=find_system(root,'LookUnderMasks','all','FollowLinks','on', ...
    'Type','Block','Name',name);
if numel(hits)~=1
    error('S14V2AUD1:UniqueName', ...
        'Expected exactly one block named %s under %s, found %d.',name,root,numel(hits));
end
p=hits{1};
end

function p=findUniqueBlockByNameOptional(root,name)
p='';
try
    hits=find_system(root,'LookUnderMasks','all','FollowLinks','on', ...
        'Type','Block','Name',name);
    if numel(hits)==1,p=hits{1};end
catch
    p='';
end
end

function tf=chartExists(blockPath)
tf=false;
try
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart');
    for i=1:numel(charts)
        try
            if strcmp(char(charts(i).Path),blockPath)
                tf=true;return;
            end
        catch
        end
    end
catch
end
end

function p=findChartUnderByTokens(root,tokens)
p='';
try
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart');
    hits={};
    for i=1:numel(charts)
        try
            q=char(charts(i).Path);
            if ~startsWith(q,[root '/']) && ~strcmp(q,root),continue;end
            s=lower(char(charts(i).Script));
            ok=true;
            for k=1:numel(tokens)
                if ~contains(s,lower(tokens{k})),ok=false;break;end
            end
            if ok,hits{end+1}=q;end %#ok<AGROW>
        catch
        end
    end
    if numel(hits)==1,p=hits{1};end
catch
end
end

function s=emChartScript(blockPath)
s='';
try
    rt=sfroot;
    charts=rt.find('-isa','Stateflow.EMChart');
    hit=[];
    for i=1:numel(charts)
        try
            if strcmp(char(charts(i).Path),blockPath)
                hit=charts(i);break;
            end
        catch
        end
    end
    if isempty(hit)
        error('S14V2AUD1:EMChart','EMChart not found for %s',blockPath);
    end
    s=char(hit.Script);
catch ME
    if startsWith(ME.identifier,'S14V2AUD1:'),rethrow(ME);end
    error('S14V2AUD1:EMChartAPI','Cannot read EMChart %s: %s',blockPath,ME.message);
end
end

function rows=subsystemInputRows(sub)
ins=find_system(sub,'SearchDepth',1,'BlockType','Inport');
tmp=cell(0,8);
phSub=get_param(sub,'PortHandles');
for k=1:numel(ins)
    port=str2double(safeGet(ins{k},'Port'));
    src='INVALID_PORT';sp=NaN;
    if isfinite(port)&&port>=1&&port<=numel(phSub.Inport)
        [src,sp]=portSource(phSub.Inport(port));
    end
    tmp(end+1,:)={port,get_param(ins{k},'Name'),ins{k},src,sp, ...
        safeGet(src,'BlockType'),safeGet(src,'GotoTag'),safeGet(src,'Value')}; %#ok<AGROW>
end
rows=sortRowsByNumericFirst(tmp);
end

function rows=subsystemOutputRows(sub)
outs=find_system(sub,'SearchDepth',1,'BlockType','Outport');
tmp=cell(0,4);
phSub=get_param(sub,'PortHandles');
for k=1:numel(outs)
    port=str2double(safeGet(outs{k},'Port'));
    cons='INVALID_PORT';
    if isfinite(port)&&port>=1&&port<=numel(phSub.Outport)
        cons=consumersOfPort(phSub.Outport(port));
    end
    tmp(end+1,:)={port,get_param(outs{k},'Name'),outs{k},cons}; %#ok<AGROW>
end
rows=sortRowsByNumericFirst(tmp);
end

function rows=sortRowsByNumericFirst(rows)
if isempty(rows),return;end
v=nan(size(rows,1),1);
for i=1:size(rows,1)
    try v(i)=double(rows{i,1});catch,v(i)=NaN;end
end
[~,ix]=sort(v);
rows=rows(ix,:);
end

function txt=sourceContext(script,keywords,radius)
if nargin<3,radius=3;end
lines=regexp(char(script),'\r\n|\n|\r','split');
take=false(size(lines));
for i=1:numel(lines)
    lo=lower(lines{i});
    hit=false;
    for k=1:numel(keywords)
        if contains(lo,lower(keywords{k})),hit=true;break;end
    end
    if hit
        a=max(1,i-radius);b=min(numel(lines),i+radius);
        take(a:b)=true;
    end
end
out={};
for i=1:numel(lines)
    if take(i),out{end+1}=sprintf('L%05d | %s',i,lines{i});end %#ok<AGROW>
end
txt=strjoin(out,newline);
end

function dst=uniqueDstFrom(srcBlock,parent,meaning)
ph=get_param(srcBlock,'PortHandles');
if numel(ph.Outport)~=1
    error('S14V2AUD1:Outport','%s has unexpected outport count.',srcBlock);
end
lh=get_param(ph.Outport(1),'Line');
if isempty(lh)||all(lh<0)
    error('S14V2AUD1:Unconnected','%s output unconnected.',srcBlock);
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
    error('S14V2AUD1:DstUnique','%s -> expected one %s, got %s', ...
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

function s=consumersOfPort(portHandle)
s='UNCONNECTED';
try
    lh=get_param(portHandle,'Line');
    if isempty(lh)||all(lh<0),return;end
    db=get_param(lh,'DstBlockHandle');
    dp=get_param(lh,'DstPortHandle');
    if isempty(db),s='NO_DST';return;end
    db=db(:);dp=dp(:);parts={};
    for i=1:numel(db)
        if db(i)<0,continue;end
        q=getfullname(db(i));
        if i<=numel(dp)&&dp(i)>0
            try q=[q '#in:' num2str(get_param(dp(i),'PortNumber'))]; catch, end
        end
        parts{end+1}=q; %#ok<AGROW>
    end
    if isempty(parts),s='NO_DST';else,s=strjoin(parts,' | ');end
catch ME
    s=['UNKNOWN:' compactText(ME.message)];
end
end

function s=consumersFromBlockOutput(block,idx)
s='INVALID_OUTPUT';
try
    ph=get_param(block,'PortHandles');
    if idx>=1&&idx<=numel(ph.Outport),s=consumersOfPort(ph.Outport(idx));end
catch ME
    s=['UNKNOWN:' compactText(ME.message)];
end
end

function s=sourceToSubsystemInput(sub,name)
b=find_system(sub,'SearchDepth',1,'BlockType','Inport','Name',name);
if numel(b)~=1,s=sprintf('INPUT_%s_COUNT_%d',name,numel(b));return;end
idx=str2double(safeGet(b{1},'Port'));
ph=get_param(sub,'PortHandles');
if ~isfinite(idx)||idx<1||idx>numel(ph.Inport),s='INVALID_PORT';return;end
[sb,sp]=portSource(ph.Inport(idx));
s=sprintf('%s#out:%s',sb,valueText(sp));
end

function p=findInportPort(sub,name)
p='NaN';
b=find_system(sub,'SearchDepth',1,'BlockType','Inport','Name',name);
if numel(b)==1,p=safeGet(b{1},'Port');end
end

function b=findOutportBlock(sub,name)
b='';
x=find_system(sub,'SearchDepth',1,'BlockType','Outport','Name',name);
if numel(x)==1,b=x{1};end
end

function s=ultimateSourceText(block,searchRoot)
s=block;
if isempty(block)||getSimulinkBlockHandle(block)<0,return;end
seen={};
cur=block;
for depth=1:12
    if any(strcmp(seen,cur)),s=[cur ' [CYCLE]'];return;end
    seen{end+1}=cur; %#ok<AGROW>
    bt=safeGet(cur,'BlockType');
    if strcmp(bt,'From')
        tag=safeGet(cur,'GotoTag');
        g=find_system(searchRoot,'LookUnderMasks','all','FollowLinks','on', ...
            'BlockType','Goto','GotoTag',tag);
        if numel(g)~=1
            s=sprintf('%s -> tag=%s GotoCount=%d',cur,tag,numel(g));return;
        end
        ph=get_param(g{1},'PortHandles');
        [q,~]=portSource(ph.Inport(1));
        if getSimulinkBlockHandle(q)<0,s=q;return;end
        cur=q;s=cur;continue;
    end
    if strcmp(bt,'Goto')
        ph=get_param(cur,'PortHandles');
        [q,~]=portSource(ph.Inport(1));
        if getSimulinkBlockHandle(q)<0,s=q;return;end
        cur=q;s=cur;continue;
    end
    % For ordinary single-input transparent blocks only, follow one input.
    ph=get_param(cur,'PortHandles');
    if numel(ph.Inport)==1 && any(strcmp(bt,{'Saturate','Gain','DataTypeConversion','UnitDelay','Memory'}))
        [q,~]=portSource(ph.Inport(1));
        if getSimulinkBlockHandle(q)<0,s=q;return;end
        cur=q;s=cur;continue;
    end
    s=cur;return;
end
s=[s ' [DEPTH_LIMIT]'];
end

function rows=traceUpstreamGraph(startBlock,searchRoot,maxDepth)
rows=cell(0,8);
if isempty(startBlock)||getSimulinkBlockHandle(startBlock)<0
    rows={0,startBlock,'NOT_BLOCK','START','','',0,'cannot trace'};
    return;
end
queue={startBlock,0,'START'};
seen={};
while ~isempty(queue)
    b=queue{1,1};dep=queue{1,2};via=queue{1,3};
    queue(1,:)=[];
    if dep>maxDepth,continue;end
    if any(strcmp(seen,b)),continue;end
    seen{end+1}=b; %#ok<AGROW>
    bt=safeGet(b,'BlockType');
    tag=safeGet(b,'GotoTag');
    val=safeGet(b,'Value');
    ph=get_param(b,'PortHandles');
    note='';
    rows(end+1,:)={dep,b,bt,via,tag,val,numel(ph.Inport),note}; %#ok<AGROW>

    if strcmp(bt,'From')
        gotos=find_system(searchRoot,'LookUnderMasks','all','FollowLinks','on', ...
            'BlockType','Goto','GotoTag',tag);
        if isempty(gotos)
            rows(end+1,:)={dep+1,'NO_MATCHING_GOTO','', ['tag=' tag],'','',0,'STOP'}; %#ok<AGROW>
        else
            for j=1:numel(gotos)
                queue(end+1,:)={gotos{j},dep+1,['FROM_TAG:' tag]}; %#ok<AGROW>
            end
        end
        continue;
    end

    for j=1:numel(ph.Inport)
        [q,sp]=portSource(ph.Inport(j));
        if getSimulinkBlockHandle(q)>0
            queue(end+1,:)={q,dep+1,sprintf('%s input%d <- out%s',get_param(b,'Name'),j,valueText(sp))}; %#ok<AGROW>
        elseif ~strcmp(q,'UNCONNECTED')
            rows(end+1,:)={dep+1,q,'',sprintf('%s input%d',get_param(b,'Name'),j),'','',0,'STOP'}; %#ok<AGROW>
        end
    end
end
end

function rows=findBlocksByKeyword(root,keywords)
all=find_system(root,'LookUnderMasks','all','FollowLinks','on','Type','Block');
rows=cell(0,9);
for i=1:numel(all)
    p=all{i};
    nm=safeGet(p,'Name');
    blob=lower([p ' ' nm ' ' safeGet(p,'GotoTag')]);
    hit=true;
    % OR semantics: keep if any keyword is present.
    hit=false;
    for k=1:numel(keywords)
        if contains(blob,lower(keywords{k})),hit=true;break;end
    end
    if ~hit,continue;end
    ph=get_param(p,'PortHandles');
    rows(end+1,:)={p,safeGet(p,'BlockType'),nm,safeGet(p,'GotoTag'), ...
        safeGet(p,'Value'),safeGet(p,'Criteria'),safeGet(p,'Threshold'), ...
        numel(ph.Inport),numel(ph.Outport)}; %#ok<AGROW>
end
end

function tf=directConnectionExists(srcBlock,srcPort,dstBlock,dstPort)
tf=false;
try
    phs=get_param(srcBlock,'PortHandles');
    phd=get_param(dstBlock,'PortHandles');
    if srcPort<1||srcPort>numel(phs.Outport)||dstPort<1||dstPort>numel(phd.Inport),return;end
    lh=get_param(phd.Inport(dstPort),'Line');
    if isempty(lh)||all(lh<0),return;end
    sp=get_param(lh,'SrcPortHandle');
    tf=isequal(sp,phs.Outport(srcPort));
catch
    tf=false;
end
end

function tf=piHasDownstreamTrackingEvidence(pi)
tf=false;
try
    ph=get_param(pi,'PortHandles');
    % More than one external input would be direct evidence worth inspecting.
    if numel(ph.Inport)>1
        tf=true;return;
    end
    froms=find_system(pi,'LookUnderMasks','all','FollowLinks','on','BlockType','From');
    for k=1:numel(froms)
        tag=lower(safeGet(froms{k},'GotoTag'));
        if contains(tag,'track')||contains(tag,'irefused')||contains(tag,'currentlimit')|| ...
                contains(tag,'adapter')||contains(tag,'finaliref')
            tf=true;return;
        end
    end
    ins=find_system(pi,'LookUnderMasks','all','FollowLinks','on','BlockType','Inport');
    for k=1:numel(ins)
        nm=lower(safeGet(ins{k},'Name'));
        if contains(nm,'track')||contains(nm,'actual')||contains(nm,'sat')||contains(nm,'limit')
            tf=true;return;
        end
    end
catch
    tf=false;
end
end

function names=currentG27Schema62()
names={ ...
    'RawIdRef','RawIqRef','FinalIdRef','FinalIqRef','IdMeas','IqMeas', ...
    'VdRaw','VqRaw','VdFF','VqFF','CurrentPI_d','CurrentPI_q', ...
    'Vconv_d','Vconv_q','ModIndex','Pmeas_pu','Qmeas_pu','GammaP', ...
    'PLL_Hz','RestoreState','Vpu','VsupportRef_pu','GammaQ','PrefCmd_pu', ...
    'PrefAfterUV_pu','PrefEff_pu','LegacyQref_pu','QrefEff_pu', ...
    'TotalSupport_d','TotalSupport_q','RestoreHold','ReconnectReady', ...
    'RestoreAlpha','FinalBreakerCmd','CurrentLimit','FrameHold', ...
    'PowerReleaseAllowed','FailCode','Vbp_d','Vbp_q','SupportClip', ...
    'RawModDemand','ModHeadroom','IqSecRequest','IqSecApplied', ...
    'QsecCapPos','QsecCapNeg','QsecClip', ...
    'Vinner_a','Vinner_b','Vinner_c','Vbus_a','Vbus_b','Vbus_c', ...
    'PhaseCorr','VoltageRatio','IrefUsed_d','IrefUsed_q', ...
    'ImeasUsed_d','ImeasUsed_q','MatchActive','PostOK'};
end

function ops=findAllOpWritesProven(mdl)
blocks=find_system(mdl,'LookUnderMasks','all','FollowLinks','on','Type','Block');
ops={};
for k=1:numel(blocks)
    b=blocks{k};
    ref=rawGetOrEmpty(b,'ReferenceBlock');
    src=rawGetOrEmpty(b,'SourceBlock');
    mask=rawGetOrEmpty(b,'MaskType');
    blob=lower([ref ' ' src ' ' mask]);
    if contains(blob,'opwritefile') || contains(blob,'opwrite file')
        ops{end+1}=b; %#ok<AGROW>
    end
end
ops=unique(ops,'stable');
end

function b=findOpWriteByGroup(ops,group)
b='';
for k=1:numel(ops)
    g=readNumericMaskProven(ops{k},'Acq_Group');
    if isfinite(g)&&abs(g-group)<1e-12
        if ~isempty(b)
            b='DUPLICATE';return;
        end
        b=ops{k};
    end
end
end

function s=rawGetOrEmpty(block,param)
s='';
try
    x=get_param(block,param);
    if ischar(x),s=x;
    elseif isstring(x),s=char(x);
    elseif isnumeric(x)||islogical(x),s=mat2str(x);
    else,s=char(string(x));
    end
catch
    s='';
end
end

function s=readMaskValueOptional(block,param)
s='';
try
    m=get_param(block,'DialogParameters');
    if isstruct(m)&&isfield(m,param),s=rawGetOrEmpty(block,param);return;end
catch
end
try
    s=rawGetOrEmpty(block,param);
catch
    s='';
end
end

function s=readMaskValueProven(block,param)
s=readMaskValueOptional(block,param);
if isempty(strtrim(s))
    error('S14V2AUD1:MaskValue','Cannot read %s from %s.',param,block);
end
end

function v=readNumericMaskProven(block,param)
raw=readMaskValueProven(block,param);
v=str2double(strtrim(raw));
if isfinite(v),return;end
try
    q=slResolve(strtrim(raw),bdroot(block));
    if isnumeric(q)&&isscalar(q)&&isfinite(double(q)),v=double(q);return;end
catch
end
v=NaN;
end

function v=safeGet(block,param)
v='UNKNOWN';
try
    if isempty(block)||getSimulinkBlockHandle(block)<0
        v='NOT_A_BLOCK';return;
    end
    q=get_param(block,param);
    if isnumeric(q),v=mat2str(q);
    elseif islogical(q),v=mat2str(q);
    elseif isstring(q),v=char(q);
    elseif ischar(q),v=q;
    else,v=char(string(q));
    end
catch
    v='UNKNOWN';
end
end

function tf=containsNoSpace(s,pattern)
a=regexprep(char(s),'\s+','');
b=regexprep(char(pattern),'\s+','');
tf=contains(a,b);
end

function p=canonicalPath(p)
p=char(java.io.File(p).getCanonicalPath());
end

function h=hashText(text)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(unicode2native(char(text),'UTF-8')));
h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));
end

function hash=sha256File(path)
fid=fopen(path,'r');
if fid<0,error('S14V2AUD1:HashOpen','Cannot open %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while true
    b=fread(fid,1024*1024,'*uint8');
    if isempty(b),break;end
    md.update(b);
end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));
end

function s=compactText(s)
s=regexprep(char(s),'[\r\n\t]+',' ');
s=regexprep(s,'\s+',' ');
end

function s=valueText(x)
if isnumeric(x)
    if isscalar(x)&&isfinite(x),s=num2str(x);else,s=mat2str(x);end
else
    s=char(string(x));
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

function writeMixedCsv(path,headers,rows)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('S14V2AUD1:CSV','Cannot create %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
writeCsvLine(fid,headers);
for r=1:size(rows,1),writeCsvLine(fid,rows(r,:));end
end

function writeCsvLine(fid,row)
parts=cell(1,numel(row));
for k=1:numel(row)
    x=row{k};
    if islogical(x),s=mat2str(x);
    elseif isnumeric(x),s=mat2str(x);
    elseif isstring(x),s=char(x);
    elseif ischar(x),s=x;
    else
        try s=char(string(x));catch,s='UNPRINTABLE';end
    end
    s=strrep(s,'"','""');
    parts{k}=['"' s '"'];
end
fprintf(fid,'%s\n',strjoin(parts,','));
end

function writeText(path,text)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('S14V2AUD1:Text','Cannot create %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',char(text));
end

function safeClose(fid)
try
    if fid>0,fclose(fid);end
catch
end
end

function closeIfOwned(mdl,wasLoaded)
if ~wasLoaded
    try
        if bdIsLoaded(mdl),close_system(mdl,0);end
    catch
    end
end
end

function files=allFiles(root,rel)
if nargin<2,rel='';end
files={};
d=dir(fullfile(root,rel));
for k=1:numel(d)
    if d(k).isdir
        if strcmp(d(k).name,'.')||strcmp(d(k).name,'..'),continue;end
        sub=allFiles(root,fullfile(rel,d(k).name));
        files=[files sub]; %#ok<AGROW>
    else
        files{end+1}=fullfile(rel,d(k).name); %#ok<AGROW>
    end
end
end

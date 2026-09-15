function result = AUDIT_K26_K50_ESS2_PICKUP_AUTHORITY_FULLCHAIN_R2(modelRoot)
% AUDIT_K26_K50_ESS2_PICKUP_AUTHORITY_FULLCHAIN_R2
% =========================================================================
% 只读“全链”审计：ESS2 零功率并回 -> Stage2/3 -> 小功率拾取时，
% 从功率环基础电流、孤岛支撑、最终电流参考、顶层模式选择、RestoreAlpha，
% 一直到 V4.9 电流执行适配器的真实控制权链。
%
% 本脚本专门补 R1 的盲区：
%   1) V4.9 适配器输入 iref 在父层到底选的是哪一路；
%   2) 顶层 Switch 的两条数据支路和 ConnectMode 控制源；
%   3) Support Manager 的 IrefFinal / Isup 端口语义；
%   4) FINAL_GFL_LIMIT_CORE 如何把基础功率电流与阻尼/慢无功支撑合成；
%   5) V4.8 Finalizer 到底新增什么、TotalSupport 是执行量还是诊断量；
%   6) Stage2->3 会同时改变哪些支撑/无功控制逻辑；
%   7) state5 零功率“稳定”判据漏看了哪些门后命令和动态状态；
%   8) Power Loop 状态是否在 Alpha=0 时仍自由演化（只审结构，不调 Kp/Ki）。
%
% 只读纪律：
%   - 不修改模型，不保存模型，不 Update/Compile；
%   - 不连接 RT-LAB，不执行仿真；
%   - 所有歧义均输出 BLOCKER/UNKNOWN，不猜第一个候选。
%
% MATLAB R2023b
% =========================================================================

VERSION = 'K26_K50_ESS2_PICKUP_AUTHORITY_FULLCHAIN_AUDIT_R2_20260915';
MODEL = 'K26_K50_CLEAN_P1';

if nargin < 1 || isempty(modelRoot)
    modelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot = canonicalPath(char(modelRoot));
modelFile = fullfile(modelRoot,[MODEL '.slx']);
if ~isfile(modelFile)
    error('E2AUTHR2:MissingModel','模型不存在：%s',modelFile);
end

outDir = fullfile(modelRoot,['AUDIT_ESS2_PICKUP_AUTHORITY_FULLCHAIN_R2_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
mkdir(outDir);
fid = fopen(fullfile(outDir,'00_AUDIT_SUMMARY.txt'),'w','n','UTF-8');
if fid<0,error('E2AUTHR2:File','无法创建审计输出。');end
cleanupFid=onCleanup(@()fclose(fid)); %#ok<NASGU>

openedHere=false;
if bdIsLoaded(MODEL)
    loaded=canonicalPath(get_param(MODEL,'FileName'));
    if ~strcmpi(loaded,modelFile)
        error('E2AUTHR2:WrongLoaded','同名外来模型已加载：%s',loaded);
    end
    if ~strcmp(get_param(MODEL,'Dirty'),'off')
        error('E2AUTHR2:Dirty','当前模型 Dirty=on；请先保存/关闭人工修改。');
    end
else
    load_system(modelFile);
    openedHere=true;
end
cleanupModel=onCleanup(@()closeIfOpened(MODEL,openedHere)); %#ok<NASGU>

dirty0=get_param(MODEL,'Dirty');

SS2=[MODEL '/SS_Slave2'];
E2=[SS2 '/ESS2_Control'];
GFL=[E2 '/AA15_GFL_ISLAND_SUPPORT'];
MGR=[GFL '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
LIMIT=[MGR '/AA15_FINAL_GFL_LIMIT_CORE'];
STATECORE=[MGR '/AA15_FINAL_GFL_STATE_CORE'];
IFINAL=[MGR '/AA15_IFINAL_MUX'];
ISUP=[MGR '/AA15_ISUP_MUX'];
FINALIZER=[GFL '/AA15_V48_QBIAS_FINALIZER'];
FINALCORE=[FINALIZER '/AA15_V48_FINALIZER_CORE'];
ADAPTER=[GFL '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];
ADAPTERCORE=[ADAPTER '/CORE'];
RESTORE=[SS2 '/AA15_ESS2_RESTORE_EXECUTOR'];
RESTORECORE=[RESTORE '/CORE'];
POWERLOOP=[E2 '/Power Control Loop'];

TOPSW=[E2 '/Switch'];
F_FINAL=[E2 '/From23'];      % IdIq_refF
F_RAW=[E2 '/From6'];         % IdIq_ref
F_MODE=[E2 '/From29'];       % ConnectMode
G_FINAL=[E2 '/Goto18'];      % publishes IdIq_refF
G_SELECTED=[E2 '/Goto19'];   % publishes IdIq_refs
G_MODE=[E2 '/Goto22'];       % publishes ConnectMode
F_SELECTED=[E2 '/From24'];   % reads IdIq_refs
G_RAW=[E2 '/Goto1'];         % expected publisher of IdIq_ref

critical={GFL,MGR,LIMIT,STATECORE,IFINAL,ISUP,FINALIZER,FINALCORE,ADAPTER,ADAPTERCORE, ...
    RESTORE,RESTORECORE,POWERLOOP,TOPSW,F_FINAL,F_RAW,F_MODE,G_FINAL,G_SELECTED,G_MODE,F_SELECTED,G_RAW};
missing=critical(cellfun(@(p)getSimulinkBlockHandle(p)<0,critical));

fprintf(fid,'ESS2 PICKUP AUTHORITY FULL-CHAIN READ-ONLY AUDIT R2\n');
fprintf(fid,'Version : %s\n',VERSION);
fprintf(fid,'Model   : %s\n',modelFile);
fprintf(fid,'Time    : %s\n\n',datestr(now,31));

if ~isempty(missing)
    fprintf(fid,'[BLOCKER] 关键路径缺失：\n');
    for k=1:numel(missing),fprintf(fid,'  %s\n',missing{k});end
    result=struct('version',VERSION,'status','BLOCKED_MISSING_PATH','missing',{missing},'outDir',outDir);
    writeJson(fullfile(outDir,'RESULT.json'),result);
    return;
end

% -------------------------------------------------------------------------
% 1. 顶层真正执行的电流参考选择链
% -------------------------------------------------------------------------
fs=fopen(fullfile(outDir,'01_TOPLEVEL_IREF_SELECTION_CHAIN.txt'),'w','n','UTF-8');
if fs<0,error('E2AUTHR2:Write','cannot write top-level chain');end
cs=onCleanup(@()fclose(fs)); %#ok<NASGU>
fprintf(fs,'TOP-LEVEL ESS2 CURRENT-REFERENCE SELECTION CHAIN\n\n');

dumpBlockEndpoints(MODEL,TOPSW,fs,E2);
dumpTagBlockResolution(MODEL,F_FINAL,fs,E2);
dumpTagBlockResolution(MODEL,F_RAW,fs,E2);
dumpTagBlockResolution(MODEL,F_MODE,fs,E2);
dumpTagBlockResolution(MODEL,F_SELECTED,fs,E2);
dumpGotoPublisher(G_FINAL,fs);
dumpGotoPublisher(G_RAW,fs);
dumpGotoPublisher(G_SELECTED,fs);
dumpGotoPublisher(G_MODE,fs);

% exact top-level semantic checks
checks=struct();
checks.switch_input1_is_final_from = inputIsBlock(TOPSW,1,F_FINAL);
checks.switch_input3_is_raw_from = inputIsBlock(TOPSW,3,F_RAW);
checks.switch_control_is_connectmode_from = inputIsBlock(TOPSW,2,F_MODE);
checks.switch_output_publishes_selected = gotoInputIsBlock(G_SELECTED,TOPSW);
checks.connectmode_publisher_is_gridon = gotoInputIsBlock(G_MODE,[E2 '/GRIDON']);
checks.from_final_tag = strcmp(safeGet(F_FINAL,'GotoTag'),'IdIq_refF');
checks.from_raw_tag = strcmp(safeGet(F_RAW,'GotoTag'),'IdIq_ref');
checks.from_mode_tag = strcmp(safeGet(F_MODE,'GotoTag'),'ConnectMode');
checks.from_selected_tag = strcmp(safeGet(F_SELECTED,'GotoTag'),'IdIq_refs');
checks.switch_threshold_half = strcmp(strtrim(safeGet(TOPSW,'Threshold')),'0.5');
checks.switch_selects_u1_when_control_gt_half = contains(lower(safeGet(TOPSW,'Criteria')),'u2 > threshold');

% -------------------------------------------------------------------------
% 2. 大容器接口语义图：端口号 -> 名字 -> 真正来源/消费者
% -------------------------------------------------------------------------
dumpSubsystemInterfaceMap(MGR,fullfile(outDir,'02_SUPPORT_MANAGER_PORT_MAP.csv'));
dumpSubsystemInterfaceMap(FINALIZER,fullfile(outDir,'03_FINALIZER_PORT_MAP.csv'));
dumpSubsystemInterfaceMap(ADAPTER,fullfile(outDir,'04_CURRENT_ADAPTER_PORT_MAP.csv'));
dumpSubsystemInterfaceMap(GFL,fullfile(outDir,'05_GFL_CONTAINER_PORT_MAP.csv'));

% Important named port checks.
checks.mgr_out2_is_ireffinal = childPortEquals(MGR,'IrefFinal','Outport',2);
checks.mgr_out10_is_isup = childPortEquals(MGR,'Isup','Outport',10);
checks.gfl_in9_is_idiq_ref = childPortEquals(GFL,'IdIq_ref','Inport',9);
checks.gfl_finaliref_exists = getSimulinkBlockHandle([GFL '/FinalIref'])>=0;

% -------------------------------------------------------------------------
% 3. 关键合成核心：LIMIT -> IrefFinal；FINALIZER -> FinalIref
% -------------------------------------------------------------------------
corePaths={LIMIT,STATECORE,FINALCORE,ADAPTERCORE,RESTORECORE};
coreFiles={'10_FINAL_GFL_LIMIT_CORE_SOURCE.m.txt','11_SUPPORT_STATE_CORE_SOURCE.m.txt', ...
    '12_FINALIZER_CORE_SOURCE.m.txt','13_CURRENT_ADAPTER_CORE_SOURCE.m.txt','14_RESTORE_EXECUTOR_CORE_SOURCE.m.txt'};
coreText=cell(size(corePaths));
for k=1:numel(corePaths)
    coreText{k}=emChartScript(corePaths{k});
    writeText(fullfile(outDir,coreFiles{k}),coreText{k});
end

% optional stateful Q helpers that change semantics around stage2/3
optionalCores={ [MGR '/AA15_QAUTH_BLEND_CORE_V47'], [MGR '/AA15_QBASE_TRACK_HOLD_CORE_V47'], ...
    [MGR '/AA15_QREF_SELECTOR_CORE_V47'] };
optionalNames={'15_QAUTH_BLEND_CORE_SOURCE.m.txt','16_QBASE_TRACK_HOLD_CORE_SOURCE.m.txt','17_QREF_SELECTOR_CORE_SOURCE.m.txt'};
for k=1:numel(optionalCores)
    if getSimulinkBlockHandle(optionalCores{k})>=0
        try writeText(fullfile(outDir,optionalNames{k}),emChartScript(optionalCores{k}));catch ME,writeText(fullfile(outDir,optionalNames{k}),['SOURCE_READ_FAILED: ' ME.message]);end
    else
        writeText(fullfile(outDir,optionalNames{k}),'BLOCK_NOT_PRESENT');
    end
end

checks.limit_has_stage_bypass_015 = containsNoSpace(coreText{1},'if s==0||s==1||s==5');
checks.limit_final_contains_base_plus_support = ...
    containsNoSpace(coreText{1},'fd=b1+sd') || containsNoSpace(coreText{1},'fd=sd+lam*b1');
checks.limit_support_diag_from_final_minus_base = containsNoSpace(coreText{1},'supd=fd-lam*b1');
checks.finalizer_adds_qsec_to_p0 = containsNoSpace(coreText{3},'fd=p0(1)+qsec_used*nd');
checks.finalizer_total_support_is_diag = containsNoSpace(coreText{3},'supd_total=sv(1)+qsec_used*nd');
checks.adapter_alpha_multiplies_selected_iref = containsNoSpace(coreText{4},'iref_used=a*iref');
checks.restore_state5_to6_binary_alpha = containsNoSpace(coreText{5},'state=6;releaseAlpha=1');
checks.restore_zero_stable_omits_iref = zeroStableOmissionCheck(coreText{5},'iref');
checks.restore_zero_stable_omits_freq = zeroStableOmissionCheck(coreText{5},'pllHz');
checks.restore_zero_stable_omits_settling_metric = ...
    ~(contains(lower(extractZeroStableExpr(coreText{5})),'dv') || contains(lower(extractZeroStableExpr(coreText{5})),'std') || ...
      contains(lower(extractZeroStableExpr(coreText{5})),'slope') || contains(lower(extractZeroStableExpr(coreText{5})),'deriv'));

% dump exact block endpoint maps around the two synthesis layers
fd=fopen(fullfile(outDir,'06_LIMIT_FINALIZER_ENDPOINTS.txt'),'w','n','UTF-8');
if fd<0,error('E2AUTHR2:Write','cannot write endpoints');end
cd=onCleanup(@()fclose(fd)); %#ok<NASGU>
dumpBlockEndpoints(MODEL,LIMIT,fd,MGR);
dumpBlockEndpoints(MODEL,IFINAL,fd,MGR);
dumpBlockEndpoints(MODEL,ISUP,fd,MGR);
dumpBlockEndpoints(MODEL,FINALIZER,fd,GFL);

% -------------------------------------------------------------------------
% 4. 支撑管理器的所有状态块与关键常数
% -------------------------------------------------------------------------
dumpStateBlocks(MGR,fullfile(outDir,'07_SUPPORT_STATE_BLOCKS.csv'));
dumpRelevantConstants(MGR,fullfile(outDir,'08_SUPPORT_PARAMETERS.csv'));

% -------------------------------------------------------------------------
% 5. Power Loop 只审“有没有状态、输出从哪里来”，不调参数
% -------------------------------------------------------------------------
fp=fopen(fullfile(outDir,'09_POWER_LOOP_AND_RAW_IREF_TRACE.txt'),'w','n','UTF-8');
if fp<0,error('E2AUTHR2:Write','cannot write power loop trace');end
cp=onCleanup(@()fclose(fp)); %#ok<NASGU>
fprintf(fp,'POWER LOOP / RAW IdIq_ref TRACE\n\n');
dumpGotoPublisher(G_RAW,fp);
dumpBlockEndpoints(MODEL,POWERLOOP,fp,POWERLOOP);
dumpStateBlocksToFid(POWERLOOP,fp);

% -------------------------------------------------------------------------
% 6. Stage2 -> Stage3 structural differences / simultaneous event matrix
% -------------------------------------------------------------------------
ft=fopen(fullfile(outDir,'18_STAGE2_TO_STAGE3_CHANGE_MATRIX.txt'),'w','n','UTF-8');
if ft<0,error('E2AUTHR2:Write','cannot write stage matrix');end
ct=onCleanup(@()fclose(ft)); %#ok<NASGU>
fprintf(ft,'STAGE2 -> STAGE3 STATIC CHANGE MATRIX\n\n');
fprintf(ft,'[Support state core]\n');
printStageRelevantLines(ft,coreText{2});
fprintf(ft,'\n[Final GFL limit core]\n');
printStageRelevantLines(ft,coreText{1});
fprintf(ft,'\n[V4.8 finalizer]\n');
printStageRelevantLines(ft,coreText{3});
fprintf(ft,'\n[Restore executor]\n');
printStageRelevantLines(ft,coreText{5});

% -------------------------------------------------------------------------
% 7. Static evidence matrix + remaining runtime unknowns
% -------------------------------------------------------------------------
fprintf(fid,'[1] R2 关键静态检查\n');
fn=fieldnames(checks);
for k=1:numel(fn)
    fprintf(fid,'  %-52s : %s\n',fn{k},tfstr(checks.(fn{k})));
end
fprintf(fid,'\n');

hardStatic = { ...
    'switch_input1_is_final_from','switch_input3_is_raw_from','switch_control_is_connectmode_from', ...
    'switch_output_publishes_selected','connectmode_publisher_is_gridon','from_final_tag','from_raw_tag', ...
    'from_mode_tag','from_selected_tag','switch_threshold_half','switch_selects_u1_when_control_gt_half', ...
    'mgr_out2_is_ireffinal','mgr_out10_is_isup','gfl_in9_is_idiq_ref', ...
    'limit_final_contains_base_plus_support','finalizer_adds_qsec_to_p0', ...
    'adapter_alpha_multiplies_selected_iref','restore_state5_to6_binary_alpha'};
blockers={};
for k=1:numel(hardStatic)
    if ~isfield(checks,hardStatic{k}) || ~checks.(hardStatic{k})
        blockers{end+1}=hardStatic{k}; %#ok<AGROW>
    end
end

fprintf(fid,'[2] 当前模型可画成的真实静态控制链\n');
fprintf(fid,'  raw IdIq_ref -----------\\\n');
fprintf(fid,'                            > TOP Switch -- IdIq_refs --> GFL IdIq_ref --> V4.9 Adapter --> alpha --> executed current\n');
fprintf(fid,'  FinalIref (V4.8) -------/       ^\n');
fprintf(fid,'                                  | ConnectMode = GRIDON\n\n');
fprintf(fid,'  Support Manager out2 = IrefFinal：由 FINAL_GFL_LIMIT_CORE 把基础功率电流 + 阻尼/慢Q支撑等合成。\n');
fprintf(fid,'  V4.8 Finalizer：在该 IrefFinal 上再处理允许的 qsec 偏置；TotalSupport 是支撑分量诊断，不是又独立相加一次。\n\n');

fprintf(fid,'[3] R2 仍不能仅靠静态SLX证明的运行事实\n');
fprintf(fid,'  U1. 失败瞬间 GRIDON/ConnectMode 的实际值（决定 TOP Switch 当拍选哪一路）。\n');
fprintf(fid,'      需用本轮 Runner/host sample 或下一轮在线诊断证明；静态模型只能证明控制源是 GRIDON。\n');
fprintf(fid,'  U2. 每个支撑状态在 16.33 s 前的数值与收敛速度。静态连接能说明公式，不能替代 MAT 动态证据。\n');
fprintf(fid,'  U3. ESS1 GFM 在 pickup 失败瞬间的内部余量；上轮 G30 若没有覆盖失败段，仍需下一轮补齐。\n');
fprintf(fid,'  U4. 改完结构后 -0.005 pu 是否真正存在稳定平衡点，只能靠下一轮实时试验证明。\n\n');

if isempty(blockers)
    status='PASS_STATIC_FULLCHAIN_CLOSED_RUNTIME_EVIDENCE_STILL_REQUIRED';
else
    status='BLOCKED_STATIC_FULLCHAIN_INCOMPLETE';
    fprintf(fid,'[BLOCKERS]\n');
    for k=1:numel(blockers),fprintf(fid,'  %s\n',blockers{k});end
end

if ~strcmp(get_param(MODEL,'Dirty'),dirty0) || ~strcmp(get_param(MODEL,'Dirty'),'off')
    error('E2AUTHR2:DirtyEnd','只读审计改变了模型Dirty状态。');
end

result=struct();
result.version=VERSION;
result.status=status;
result.modelFile=modelFile;
result.modelSha256=sha256File(modelFile);
result.outDir=outDir;
result.checks=checks;
result.blockers=blockers;
result.runtimeUnknowns={ ...
    'GRIDON/ConnectMode runtime branch at failure', ...
    'support state numeric trajectories before pickup', ...
    'ESS1 GFM internal margin during pickup failure', ...
    'post-fix nonzero-power electrical stability'};
writeJson(fullfile(outDir,'RESULT.json'),result);

fprintf(fid,'[4] 最终状态\n  %s\n',status);
fprintf(fid,'  输出目录：%s\n',outDir);

fprintf('\nESS2 pickup authority 全链只读审计 R2 完成。\n');
fprintf('Status: %s\n',status);
fprintf('Output: %s\n',outDir);
fprintf('请把整个 R2 输出文件夹压缩后发回。\n');
end

% =========================================================================
% Read-only helpers
% =========================================================================
function dumpBlockEndpoints(mdl,block,fid,scope)
fprintf(fid,'\n=== BLOCK ===\n%s\nType=%s\n',block,safeGet(block,'BlockType'));
ph=get_param(block,'PortHandles');
for k=1:numel(ph.Inport)
    [src,sp,detail]=inputSource(ph.Inport(k));
    fprintf(fid,'IN%d <- %s / out%s | %s\n',k,src,num2str(sp),detail);
    if getSimulinkBlockHandle(src)>=0 && strcmp(safeGet(src,'BlockType'),'From')
        dumpFromResolution(mdl,src,fid,scope);
    end
end
for k=1:numel(ph.Outport)
    D=outputConsumers(ph.Outport(k));
    if isempty(D)
        fprintf(fid,'OUT%d -> [NO NORMAL SIGNAL CONSUMER]\n',k);
    else
        for j=1:size(D,1),fprintf(fid,'OUT%d -> %s / in%s\n',k,D{j,1},num2str(D{j,2}));end
    end
end
end

function dumpTagBlockResolution(mdl,fromBlock,fid,scope)
fprintf(fid,'\n--- FROM RESOLUTION ---\n%s\n',fromBlock);
dumpFromResolution(mdl,fromBlock,fid,scope);
end

function dumpFromResolution(mdl,fromBlock,fid,scope)
if getSimulinkBlockHandle(fromBlock)<0 || ~strcmp(safeGet(fromBlock,'BlockType'),'From')
    fprintf(fid,'  NOT A FROM BLOCK\n');return;
end
tag=safeGet(fromBlock,'GotoTag');
gotos=find_system(scope,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto','GotoTag',tag);
% Prefer same-parent candidates only for local top-level tags; report all if none.
par=get_param(fromBlock,'Parent');same={};
for k=1:numel(gotos),if strcmp(get_param(gotos{k},'Parent'),par),same{end+1}=gotos{k};end,end %#ok<AGROW>
if ~isempty(same),use=same;else,use=gotos;end
fprintf(fid,'  tag=%s, candidates_in_scope=%d, candidates_used=%d\n',tag,numel(gotos),numel(use));
for k=1:numel(use)
    fprintf(fid,'  GOTO%d: %s\n',k,use{k});
    dumpGotoPublisher(use{k},fid);
end
if isempty(use),fprintf(fid,'  [UNKNOWN: no publisher resolved]\n');end
end

function dumpGotoPublisher(gotoBlock,fid)
if getSimulinkBlockHandle(gotoBlock)<0
    fprintf(fid,'  GOTO missing: %s\n',gotoBlock);return;
end
fprintf(fid,'  Publisher %s | tag=%s\n',gotoBlock,safeGet(gotoBlock,'GotoTag'));
ph=get_param(gotoBlock,'PortHandles');
if isempty(ph.Inport),fprintf(fid,'    no input port\n');return;end
[src,sp,detail]=inputSource(ph.Inport(1));
fprintf(fid,'    input <- %s / out%s | %s\n',src,num2str(sp),detail);
% One explanatory hop through simple selector/mux/switch is useful, never erase state.
if getSimulinkBlockHandle(src)>=0
    bt=safeGet(src,'BlockType');
    if any(strcmp(bt,{'Switch','Selector','Mux','Demux','Gain','Sum','Product'}))
        ph2=get_param(src,'PortHandles');
        for q=1:numel(ph2.Inport)
            [s2,p2,d2]=inputSource(ph2.Inport(q));
            fprintf(fid,'      %s IN%d <- %s / out%s | %s\n',bt,q,s2,num2str(p2),d2);
        end
    end
end
end

function tf=inputIsBlock(block,inPort,expected)
tf=false;try ph=get_param(block,'PortHandles');[src,~,~]=inputSource(ph.Inport(inPort));tf=strcmp(src,expected);catch,end
end
function tf=gotoInputIsBlock(gotoBlock,expected)
tf=false;try ph=get_param(gotoBlock,'PortHandles');[src,~,~]=inputSource(ph.Inport(1));tf=strcmp(src,expected);catch,end
end

function tf=childPortEquals(parent,name,blockType,wanted)
tf=false;b=[parent '/' name];if getSimulinkBlockHandle(b)<0,return;end
if ~strcmp(safeGet(b,'BlockType'),blockType),return;end
try tf=str2double(safeGet(b,'Port'))==wanted;catch,end
end

function dumpSubsystemInterfaceMap(sub,path)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTHR2:CSV','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Direction,Port,Name,Block,SourceOrConsumers\n');
ins=find_system(sub,'SearchDepth',1,'BlockType','Inport');outs=find_system(sub,'SearchDepth',1,'BlockType','Outport');
writePortRows(ins,'IN',fid);writePortRows(outs,'OUT',fid);
end

function writePortRows(blocks,dirn,fid)
nums=zeros(numel(blocks),1);
for k=1:numel(blocks),nums(k)=str2double(safeGet(blocks{k},'Port'));end
[~,ix]=sort(nums);blocks=blocks(ix);nums=nums(ix);
for k=1:numel(blocks)
    b=blocks{k};name=get_param(b,'Name');desc='';ph=get_param(b,'PortHandles');
    if strcmp(dirn,'IN')
        D=outputConsumers(ph.Outport(1));
        if isempty(D),desc='NO_CONSUMER';else,parts=cell(size(D,1),1);for j=1:size(D,1),parts{j}=sprintf('%s/in%s',D{j,1},num2str(D{j,2}));end,desc=strjoin(parts,' | ');end
    else
        [src,sp,~]=inputSource(ph.Inport(1));desc=sprintf('%s/out%s',src,num2str(sp));
    end
    fprintf(fid,'"%s",%g,"%s","%s","%s"\n',dirn,nums(k),csvEsc(name),csvEsc(b),csvEsc(desc));
end
end

function dumpStateBlocks(scope,path)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTHR2:CSV','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Block,Type,InitialCondition,SampleTime,InputSource,Consumers\n');
dumpStateBlocksToFid(scope,fid);
end

function dumpStateBlocksToFid(scope,fid)
all=find_system(scope,'LookUnderMasks','all','FollowLinks','on','Type','Block');
for k=1:numel(all)
    bt=safeGet(all{k},'BlockType');
    if ~(contains(bt,'Delay') || strcmp(bt,'Memory') || strcmp(bt,'DiscreteIntegrator') || strcmp(bt,'UnitDelay'))
        continue;
    end
    ic=firstExistingParam(all{k},{'InitialCondition','InitialConditionSource'});
    st=firstExistingParam(all{k},{'SampleTime'});
    ph=get_param(all{k},'PortHandles');src='';cons='';
    if ~isempty(ph.Inport),[s,p,~]=inputSource(ph.Inport(1));src=sprintf('%s/out%s',s,num2str(p));end
    if ~isempty(ph.Outport),D=outputConsumers(ph.Outport(1));parts=cell(size(D,1),1);for j=1:size(D,1),parts{j}=sprintf('%s/in%s',D{j,1},num2str(D{j,2}));end,cons=strjoin(parts,' | ');end
    fprintf(fid,'"%s","%s","%s","%s","%s","%s"\n',csvEsc(all{k}),csvEsc(bt),csvEsc(ic),csvEsc(st),csvEsc(src),csvEsc(cons));
end
end

function dumpRelevantConstants(scope,path)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTHR2:CSV','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Block,Name,Value,SampleTime,Consumers\n');
cs=find_system(scope,'LookUnderMasks','all','FollowLinks','on','BlockType','Constant');
for k=1:numel(cs)
    nm=get_param(cs{k},'Name');
    if ~(startsWith(nm,'AA15_P_') || contains(nm,'QAUTH') || contains(nm,'QBASE') || contains(nm,'RELEASE') || contains(nm,'SUPPORT'))
        continue;
    end
    val=safeGet(cs{k},'Value');st=safeGet(cs{k},'SampleTime');ph=get_param(cs{k},'PortHandles');D=outputConsumers(ph.Outport(1));
    parts=cell(size(D,1),1);for j=1:size(D,1),parts{j}=sprintf('%s/in%s',D{j,1},num2str(D{j,2}));end
    fprintf(fid,'"%s","%s","%s","%s","%s"\n',csvEsc(cs{k}),csvEsc(nm),csvEsc(val),csvEsc(st),csvEsc(strjoin(parts,' | ')));
end
end

function printStageRelevantLines(fid,src)
L=regexp(src,'\r\n|\n|\r','split');
for k=1:numel(L)
    lo=lower(L{k});
    if contains(lo,'s==2') || contains(lo,'s==3') || contains(lo,'stage') || contains(lo,'qsec') || contains(lo,'release') || contains(lo,'support') || contains(lo,'alpha')
        fprintf(fid,'%4d | %s\n',k,L{k});
    end
end
end

function tf=zeroStableOmissionCheck(src,token)
expr=extractZeroStableExpr(src);tf=~contains(lower(expr),lower(token));
end
function expr=extractZeroStableExpr(src)
expr='';
L=regexp(src,'\r\n|\n|\r','split');
for k=1:numel(L)
    if contains(L{k},'zeroStableOK=')
        a=max(1,k);b=min(numel(L),k+5);expr=strjoin(L(a:b),' ');return;
    end
end
end

function [src,srcPort,detail]=inputSource(portHandle)
src='UNCONNECTED';srcPort=NaN;detail='';
lh=get_param(portHandle,'Line');if isempty(lh)||all(lh<0),return;end
try
    sb=get_param(lh,'SrcBlockHandle');sp=get_param(lh,'SrcPortHandle');
    if numel(sb)~=1||sb<0,src='AMBIGUOUS_SOURCE';detail='SrcBlockHandle not unique';return;end
    src=getfullname(sb);try srcPort=get_param(sp,'PortNumber');catch,srcPort=NaN;end
    detail=sprintf('BlockType=%s',safeGet(src,'BlockType'));
catch ME,src='TRACE_ERROR';detail=ME.message;end
end

function D=outputConsumers(portHandle)
D={};lh=get_param(portHandle,'Line');if isempty(lh)||all(lh<0),return;end
try
    db=get_param(lh,'DstBlockHandle');dp=get_param(lh,'DstPortHandle');db=db(:);dp=dp(:);good=(db>=0 & dp>=0);db=db(good);dp=dp(good);
    for k=1:numel(db),pn=NaN;try pn=get_param(dp(k),'PortNumber');catch,end,D(end+1,:)={getfullname(db(k)),pn};end %#ok<AGROW>
catch,end
end

function s=emChartScript(path)
rt=sfroot;c=rt.find('-isa','Stateflow.EMChart');hit=[];
for k=1:numel(c),try if strcmp(char(c(k).Path),path),hit=c(k);break;end,catch,end,end
if isempty(hit),error('E2AUTHR2:EMChart','找不到MATLAB Function源码：%s',path);end
s=char(hit.Script);
end

function v=firstExistingParam(block,names)
v='';for k=1:numel(names),try q=get_param(block,names{k});v=char(string(q));return;catch,end,end
end
function tf=containsNoSpace(src,token)
a=regexprep(src,'\s+','');b=regexprep(token,'\s+','');tf=contains(a,b);
end
function v=safeGet(block,param)
v='UNKNOWN';try q=get_param(block,param);if isnumeric(q)||islogical(q),v=mat2str(q);else,v=char(string(q));end,catch,end
end
function s=csvEsc(x),s=char(string(x));s=strrep(s,'"','""');end
function p=canonicalPath(p),try p=char(java.io.File(p).getCanonicalPath());catch,p=char(p);end,end
function closeIfOpened(mdl,openedHere),if openedHere&&bdIsLoaded(mdl),try close_system(mdl,0);catch,end,end,end
function t=tfstr(tf),if tf,t='YES';else,t='NO';end,end
function h=sha256File(path)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');fid=fopen(path,'rb');if fid<0,error('E2AUTHR2:Hash','cannot read');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true,b=fread(fid,1024*1024,'*uint8');if isempty(b),break;end;md.update(typecast(b(:),'int8'));end
raw=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(raw,2).',1,[]));
end
function writeText(path,text),fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTHR2:Write','cannot write');end,c=onCleanup(@()fclose(fid));fprintf(fid,'%s',char(text));end
function writeJson(path,data),writeText(path,jsonencode(data,'PrettyPrint',true));end

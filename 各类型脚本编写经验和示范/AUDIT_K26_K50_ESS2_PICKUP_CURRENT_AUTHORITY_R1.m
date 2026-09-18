function result = AUDIT_K26_K50_ESS2_PICKUP_CURRENT_AUTHORITY_R1(modelRoot)
% AUDIT_K26_K50_ESS2_PICKUP_CURRENT_AUTHORITY_R1
% =========================================================================
% 只读审计：ESS2 从“零功率已接入”到“开始承担小功率”时，电流命令到底怎样形成、
% RestoreAlpha（恢复放行系数）到底放行了什么。
%
% 目的不是改模型，而是回答四个问题：
% 1) Power Loop（功率环）产生的基础电流请求从哪里来；
% 2) Island Support（孤岛支撑）又额外加了哪些电流请求；
% 3) FinalIref（最终电流参考）在哪里把这些量合成；
% 4) RestoreAlpha=0/1 在 Current Execution Adapter（电流执行适配器）里
%    究竟门控的是“仅小功率请求”，还是“整个最终电流参考”。
%
% 永久只读规则：
% - 不 set_param / add_block / delete_block / add_line / delete_line；
% - 不 update / compile / save_system；
% - 不连接 RT-LAB；
% - 不修改 SPS 物理线；
% - 遇到 From/Goto 只报告候选，不在歧义时猜第一个。
%
% MATLAB R2023b
% =========================================================================

VERSION = 'K26_K50_ESS2_PICKUP_CURRENT_AUTHORITY_AUDIT_R1_20260915';
MODEL   = 'K26_K50_CLEAN_P1';

if nargin < 1 || isempty(modelRoot)
    modelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot = canonicalPath(char(modelRoot));
modelFile = fullfile(modelRoot,[MODEL '.slx']);
if ~isfile(modelFile)
    error('E2AUTH:MissingModel','模型不存在：%s',modelFile);
end

outDir = fullfile(modelRoot,['AUDIT_ESS2_PICKUP_CURRENT_AUTHORITY_R1_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
mkdir(outDir);
mainTxt = fullfile(outDir,'00_AUDIT_SUMMARY.txt');
fid = fopen(mainTxt,'w','n','UTF-8');
if fid < 0, error('E2AUTH:File','无法创建输出文件。'); end
cleanupFid = onCleanup(@()fclose(fid)); %#ok<NASGU>

fprintf(fid,'ESS2 PICKUP CURRENT AUTHORITY READ-ONLY AUDIT\n');
fprintf(fid,'Version: %s\n',VERSION);
fprintf(fid,'Model: %s\n',modelFile);
fprintf(fid,'Generated: %s\n\n',datestr(now,31));

openedHere = false;
if bdIsLoaded(MODEL)
    loaded = canonicalPath(get_param(MODEL,'FileName'));
    if ~strcmpi(loaded,modelFile)
        error('E2AUTH:WrongLoaded','同名外来模型已加载：%s',loaded);
    end
    if ~strcmp(get_param(MODEL,'Dirty'),'off')
        error('E2AUTH:Dirty','模型当前 Dirty=on。请先保存/关闭人工修改后再做只读审计。');
    end
else
    load_system(modelFile);
    openedHere = true;
end
cleanupModel = onCleanup(@()closeIfOpened(MODEL,openedHere)); %#ok<NASGU>

% -------------------------------------------------------------------------
% 1. Exact paths in the current saved model
% -------------------------------------------------------------------------
SS2 = [MODEL '/SS_Slave2'];
E2  = [SS2 '/ESS2_Control'];
GFL = [E2 '/AA15_GFL_ISLAND_SUPPORT'];
MGR = [GFL '/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
STATECORE = [MGR '/AA15_FINAL_GFL_STATE_CORE'];
FINALIZER = [GFL '/AA15_V48_QBIAS_FINALIZER'];
FINALCORE = [FINALIZER '/AA15_V48_FINALIZER_CORE'];
ADAPTER   = [GFL '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];
ADAPTERCORE = [ADAPTER '/CORE'];
RESTORE   = [SS2 '/AA15_ESS2_RESTORE_EXECUTOR'];
RESTORECORE = [RESTORE '/CORE'];
POWERLOOP = [E2 '/Power Control Loop'];
CURRENTREG = [E2 '/Current Regulator'];

paths = {GFL,MGR,STATECORE,FINALIZER,FINALCORE,ADAPTER,ADAPTERCORE,RESTORE,RESTORECORE,POWERLOOP,CURRENTREG};
labels = {'ESS2 GFL孤岛支撑总容器','孤岛支撑管理器','孤岛支撑状态核心', ...
    '最终电流参考合成器(V4.8)','最终电流参考合成核心','电流执行适配器(V4.9)', ...
    '电流执行适配器核心','ESS2恢复执行器','ESS2恢复执行器核心','ESS2功率环','ESS2原电流调节器'};

fprintf(fid,'[1] 关键模块是否存在\n');
for k=1:numel(paths)
    ok = getSimulinkBlockHandle(paths{k}) >= 0;
    fprintf(fid,'  %-34s : %s\n      %s\n',labels{k},tfstr(ok),paths{k});
end
fprintf(fid,'\n');

missing = paths(cellfun(@(p)getSimulinkBlockHandle(p)<0,paths));
if ~isempty(missing)
    fprintf(fid,'BLOCKER: 以下关键块不存在，停止自动推断：\n');
    for k=1:numel(missing), fprintf(fid,'  %s\n',missing{k}); end
    result = struct('version',VERSION,'status','BLOCKED_MISSING_PATH','outDir',outDir,'missing',{missing});
    writeJson(fullfile(outDir,'RESULT.json'),result);
    return;
end

% -------------------------------------------------------------------------
% 2. Human-readable topology snapshots
% -------------------------------------------------------------------------
blocksToDump = {MGR,FINALIZER,ADAPTER,ADAPTERCORE,RESTORECORE};
blockShort = {'02_SUPPORT_MANAGER_ENDPOINTS.txt','03_FINALIZER_ENDPOINTS.txt', ...
    '04_CURRENT_ADAPTER_ENDPOINTS.txt','05_CURRENT_ADAPTER_CORE_ENDPOINTS.txt', ...
    '06_RESTORE_EXECUTOR_CORE_ENDPOINTS.txt'};
for k=1:numel(blocksToDump)
    dumpBlockEndpoints(MODEL,blocksToDump{k},fullfile(outDir,blockShort{k}));
end

% Specifically trace the two signals that matter most.
traceTargets = { ...
    [ADAPTER '/IdIq_ref'], ...
    [ADAPTER '/RestoreHold'], ...
    [ADAPTER '/RestoreAlpha'], ...
    [FINALIZER '/FinalIref'], ...
    [FINALIZER '/TotalSupport'] ...
    };
traceLabels = {'Adapter的IdIq_ref（送去执行的电流参考入口）', ...
    'Adapter的RestoreHold（断开待并保持）','Adapter的RestoreAlpha（恢复放行系数）', ...
    'FinalIref（合成后的最终电流命令）','TotalSupport（额外孤岛支撑电流）'};

traceFile = fullfile(outDir,'07_KEY_SIGNAL_TRACE.txt');
ft = fopen(traceFile,'w','n','UTF-8');
if ft<0,error('E2AUTH:TraceFile','无法写trace文件。');end
ct=onCleanup(@()fclose(ft)); %#ok<NASGU>
fprintf(ft,'KEY SIGNAL TRACE\n\n');
for k=1:numel(traceTargets)
    fprintf(ft,'=== %s ===\n%s\n',traceLabels{k},traceTargets{k});
    if getSimulinkBlockHandle(traceTargets{k})<0
        fprintf(ft,'  [NOT FOUND]\n\n');
        continue;
    end
    dumpOneBlockNeighborhood(MODEL,traceTargets{k},ft);
    fprintf(ft,'\n');
end

% -------------------------------------------------------------------------
% 3. Extract current MATLAB Function source — current saved model is judge
% -------------------------------------------------------------------------
sourceTargets = {STATECORE,FINALCORE,ADAPTERCORE,RESTORECORE};
sourceNames = {'10_SUPPORT_STATE_CORE_SOURCE.m.txt','11_FINAL_IREF_CORE_SOURCE.m.txt', ...
    '12_CURRENT_ADAPTER_CORE_SOURCE.m.txt','13_RESTORE_EXECUTOR_CORE_SOURCE.m.txt'};
sourceLabels = {'孤岛支撑状态核心','最终电流合成核心','电流执行适配器核心','恢复执行器核心'};
sourceText = cell(size(sourceTargets));
for k=1:numel(sourceTargets)
    sourceText{k} = emChartScript(sourceTargets{k});
    writeText(fullfile(outDir,sourceNames{k}),sourceText{k});
end

% -------------------------------------------------------------------------
% 4. Pull only the lines relevant to this failure
% -------------------------------------------------------------------------
keywords = { ...
    {'pref_eff','gamma_p','gpEff','supenv','damp','slowq','vref','support','release'}, ...
    {'fd=','fq=','supd_total','supq_total','qsec_used','p0','sv','id0','iq0'}, ...
    {'hold','alpha','iref_used','imeas_used','match','a*iref','iref','imeas'}, ...
    {'zeroStableOK','releaseAlpha','state==5','state==6','pickupOK','pickupSevere','postVmin','postImax'} ...
    };
kwFile = fullfile(outDir,'14_RELEVANT_SOURCE_LINES.txt');
fk = fopen(kwFile,'w','n','UTF-8');
if fk<0,error('E2AUTH:KwFile','无法写关键源码摘录。');end
ck=onCleanup(@()fclose(fk)); %#ok<NASGU>
for k=1:numel(sourceText)
    fprintf(fk,'\n\n================ %s ================\n',sourceLabels{k});
    printKeywordLines(fk,sourceText{k},keywords{k},3);
end

% -------------------------------------------------------------------------
% 5. Hard semantic checks — report, never modify
% -------------------------------------------------------------------------
checks = struct();
checks.adapter_has_hold = contains(sourceText{3},'hold');
checks.adapter_has_alpha = contains(sourceText{3},'alpha');
checks.adapter_alpha_multiplies_iref = containsNoSpace(sourceText{3},'iref_used=a*iref');
checks.adapter_hold_zeros_iref = containsNoSpace(sourceText{3},'iref_used=zeros(2,1)');
checks.adapter_hold_zeros_imeas = containsNoSpace(sourceText{3},'imeas_used=zeros(2,1)');
checks.restore_binary_release = containsNoSpace(sourceText{4},'state=6;releaseAlpha=1');
checks.restore_state6_alpha_one = containsNoSpace(sourceText{4},'state==6') && ...
    containsNoSpace(sourceText{4},'releaseAlpha=1');
checks.restore_zero_stable_checks_v = contains(sourceText{4},'zeroStableOK');
checks.restore_pickup_uses_prefeff = contains(sourceText{4},'abs(pmeas-prefEff)');
checks.finalizer_has_support_output = contains(sourceText{2},'supd_total') || contains(sourceText{2},'supq_total');
checks.support_core_has_prefeff = contains(sourceText{1},'pref_eff');

fprintf(fid,'[2] 关键语义检查（只读源码）\n');
fn=fieldnames(checks);
for k=1:numel(fn)
    fprintf(fid,'  %-42s : %s\n',fn{k},tfstr(checks.(fn{k})));
end
fprintf(fid,'\n');

% Plain-language interpretation only when exact source proves it.
fprintf(fid,'[3] 可以从当前保存源码直接证明的事情\n');
if checks.adapter_alpha_multiplies_iref
    fprintf(fid,['  A. RestoreAlpha不是只作用于外部-0.005 pu有功目标；' ...
        '它在电流执行适配器中直接乘在进入适配器的整个 iref 向量上。\n']);
else
    fprintf(fid,'  A. 当前源码未命中 iref_used=a*iref；请以12_CURRENT_ADAPTER_CORE_SOURCE为准人工复核。\n');
end
if checks.restore_binary_release
    fprintf(fid,['  B. 恢复执行器从state5进入state6时，把RestoreAlpha直接置为1；' ...
        '不是慢慢从0爬到1。\n']);
else
    fprintf(fid,'  B. 当前源码未命中二值Alpha语句；请人工复核13_RESTORE_EXECUTOR_CORE_SOURCE。\n');
end
if checks.adapter_alpha_multiplies_iref && checks.restore_binary_release
    fprintf(fid,['  C. 因此，只要适配器入口 iref 在state5期间已经不是接近0，' ...
        'state6第一拍就会把这整套已存在的电流请求一起放行。\n']);
end
fprintf(fid,'\n');

% -------------------------------------------------------------------------
% 6. Save compact CSV of selected direct endpoint contracts
% -------------------------------------------------------------------------
rows = {};
sel = {MGR,FINALIZER,ADAPTER,RESTORECORE};
for k=1:numel(sel)
    rows = [rows; collectEndpoints(sel{k})]; %#ok<AGROW>
end
writeEndpointCsv(fullfile(outDir,'20_SELECTED_ENDPOINTS.csv'),rows);

if ~strcmp(get_param(MODEL,'Dirty'),'off')
    error('E2AUTH:DirtyEnd','只读审计意外让模型Dirty=on。');
end

status = 'PASS_READ_ONLY_AUDIT_COMPLETE';
result = struct();
result.version = VERSION;
result.status = status;
result.modelFile = modelFile;
result.modelSha256 = sha256File(modelFile);
result.outDir = outDir;
result.checks = checks;
writeJson(fullfile(outDir,'RESULT.json'),result);

fprintf(fid,'[4] 最终状态\n  %s\n',status);
fprintf(fid,'  输出目录：%s\n',outDir);

fprintf('\nESS2 pickup current-authority 只读审计完成。\n');
fprintf('Status: %s\n',status);
fprintf('Output: %s\n',outDir);
fprintf('请把整个输出文件夹压缩后发回。\n');
end

% =========================================================================
% Helpers — read-only
% =========================================================================
function dumpBlockEndpoints(mdl,block,outFile)
fid=fopen(outFile,'w','n','UTF-8');if fid<0,error('E2AUTH:Dump','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'BLOCK ENDPOINT AUDIT\nBlock: %s\nType: %s\n\n',block,safeGet(block,'BlockType'));
ph=get_param(block,'PortHandles');
for k=1:numel(ph.Inport)
    [src,srcPort,detail]=inputSource(ph.Inport(k));
    fprintf(fid,'IN %d <- %s / out%d\n    %s\n',k,src,srcPort,detail);
end
fprintf(fid,'\n');
for k=1:numel(ph.Outport)
    D=outputConsumers(ph.Outport(k));
    if isempty(D)
        fprintf(fid,'OUT %d -> [NO NORMAL SIGNAL CONSUMER]\n',k);
    else
        for j=1:size(D,1)
            fprintf(fid,'OUT %d -> %s / in%d\n',k,D{j,1},D{j,2});
        end
    end
end
fprintf(fid,'\n');
% If direct source is From, list Goto candidates model-wide without guessing.
for k=1:numel(ph.Inport)
    [src,~,~]=inputSource(ph.Inport(k));
    if getSimulinkBlockHandle(src)>=0 && strcmp(safeGet(src,'BlockType'),'From')
        tag=safeGet(src,'GotoTag');
        gotos=find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto','GotoTag',tag);
        fprintf(fid,'IN %d source is From, tag=%s; Goto candidates=%d\n',k,tag,numel(gotos));
        for q=1:numel(gotos)
            fprintf(fid,'  GOTO %d: %s\n',q,gotos{q});
            try
                p=get_param(gotos{q},'PortHandles');
                [gs,gsp,gdet]=inputSource(p.Inport(1));
                fprintf(fid,'       input <- %s / out%d | %s\n',gs,gsp,gdet);
            catch ME
                fprintf(fid,'       input trace failed: %s\n',ME.message);
            end
        end
    end
end
end

function dumpOneBlockNeighborhood(mdl,block,fid)
ph=get_param(block,'PortHandles');
for k=1:numel(ph.Inport)
    [src,sp,detail]=inputSource(ph.Inport(k));
    fprintf(fid,'  IN%d <- %s / out%d\n       %s\n',k,src,sp,detail);
end
for k=1:numel(ph.Outport)
    D=outputConsumers(ph.Outport(k));
    for j=1:size(D,1)
        fprintf(fid,'  OUT%d -> %s / in%d\n',k,D{j,1},D{j,2});
    end
end
if strcmp(safeGet(block,'BlockType'),'From')
    tag=safeGet(block,'GotoTag');
    gotos=find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto','GotoTag',tag);
    fprintf(fid,'  From tag=%s; Goto candidates=%d\n',tag,numel(gotos));
end
end

function R=collectEndpoints(block)
R={};ph=get_param(block,'PortHandles');
for k=1:numel(ph.Inport)
    [src,sp,detail]=inputSource(ph.Inport(k));
    R(end+1,:)={block,'IN',k,src,sp,detail}; %#ok<AGROW>
end
for k=1:numel(ph.Outport)
    D=outputConsumers(ph.Outport(k));
    if isempty(D)
        R(end+1,:)={block,'OUT',k,'NO_NORMAL_CONSUMER',NaN,''}; %#ok<AGROW>
    else
        for j=1:size(D,1)
            R(end+1,:)={block,'OUT',k,D{j,1},D{j,2},''}; %#ok<AGROW>
        end
    end
end
end

function [src,srcPort,detail]=inputSource(portHandle)
src='UNCONNECTED';srcPort=NaN;detail='';
lh=get_param(portHandle,'Line');
if isempty(lh)||all(lh<0),return;end
try
    sb=get_param(lh,'SrcBlockHandle');sp=get_param(lh,'SrcPortHandle');
    if numel(sb)~=1||sb<0
        src='AMBIGUOUS_SOURCE';detail='SrcBlockHandle not unique';return;
    end
    src=getfullname(sb);
    try srcPort=get_param(sp,'PortNumber');catch,srcPort=NaN;end
    detail=sprintf('BlockType=%s',safeGet(src,'BlockType'));
catch ME
    src='TRACE_ERROR';detail=ME.message;
end
end

function D=outputConsumers(portHandle)
D={};lh=get_param(portHandle,'Line');
if isempty(lh)||all(lh<0),return;end
try
    db=get_param(lh,'DstBlockHandle');dp=get_param(lh,'DstPortHandle');
    db=db(:);dp=dp(:);
    good=(db>=0 & dp>=0);db=db(good);dp=dp(good);
    for k=1:numel(db)
        pn=NaN;try pn=get_param(dp(k),'PortNumber');catch,end
        D(end+1,:)={getfullname(db(k)),pn}; %#ok<AGROW>
    end
catch
end
end

function s=emChartScript(path)
rt=sfroot;c=rt.find('-isa','Stateflow.EMChart');hit=[];
for k=1:numel(c)
    try
        if strcmp(char(c(k).Path),path),hit=c(k);break;end
    catch
    end
end
if isempty(hit),error('E2AUTH:EMChart','找不到MATLAB Function源码：%s',path);end
s=char(hit.Script);
end

function printKeywordLines(fid,src,tokens,contextN)
L=regexp(src,'\r\n|\n|\r','split');hit=false(1,numel(L));
for i=1:numel(L)
    low=lower(L{i});
    for k=1:numel(tokens)
        if contains(low,lower(tokens{k})),hit(i)=true;break;end
    end
end
idx=find(hit);if isempty(idx),fprintf(fid,'[NO KEYWORD MATCH]\n');return;end
show=false(size(hit));
for x=idx
    a=max(1,x-contextN);b=min(numel(L),x+contextN);show(a:b)=true;
end
last=false;
for i=1:numel(L)
    if show(i)
        if ~last,fprintf(fid,'\n---\n');end
        fprintf(fid,'%5d | %s\n',i,L{i});last=true;
    else
        last=false;
    end
end
end

function tf=containsNoSpace(src,token)
a=regexprep(src,'\s+','');b=regexprep(token,'\s+','');tf=contains(a,b);
end

function writeEndpointCsv(path,rows)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTH:CSV','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Block,Direction,Port,OtherBlock,OtherPort,Detail\n');
for k=1:size(rows,1)
    vals=rows(k,:);
    fprintf(fid,'"%s","%s",%d,"%s",%g,"%s"\n',csvEsc(vals{1}),csvEsc(vals{2}),vals{3},csvEsc(vals{4}),vals{5},csvEsc(vals{6}));
end
end

function s=csvEsc(x)
s=char(string(x));s=strrep(s,'"','""');
end

function v=safeGet(block,param)
v='UNKNOWN';try q=get_param(block,param);if isnumeric(q)||islogical(q),v=mat2str(q);else,v=char(string(q));end,catch,end
end

function p=canonicalPath(p)
try p=char(java.io.File(p).getCanonicalPath());catch,p=char(p);end
end

function closeIfOpened(mdl,openedHere)
if openedHere && bdIsLoaded(mdl),try close_system(mdl,0);catch,end,end
end

function t=tfstr(tf)
if tf,t='YES';else,t='NO';end
end

function h=sha256File(path)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
fid=fopen(path,'rb');if fid<0,error('E2AUTH:Hash','cannot read');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true,b=fread(fid,1024*1024,'*uint8');if isempty(b),break;end;md.update(typecast(b(:),'int8'));end
raw=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(raw,2).',1,[]));
end

function writeText(path,text)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('E2AUTH:Write','cannot write');end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',char(text));
end

function writeJson(path,data)
writeText(path,jsonencode(data,'PrettyPrint',true));
end

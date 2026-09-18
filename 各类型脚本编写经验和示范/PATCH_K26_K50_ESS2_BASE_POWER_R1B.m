function result = PATCH_K26_K50_ESS2_BASE_POWER_R1B(modelRoot)
% 储能2基础小功率诊断：正式修改脚本第一版。
% 用途：隔离四路附加请求，先开放零目标基础控制，再独立施加小功率。
% 复用已成功脚本的流程：只读预检 -> 隔离自测 -> 原字节临时副本
% -> 临时副本改动/保存/重读 -> 正式整体备份 -> 正式改动/保存一次/重读。
% 不运行正式电气模型，不连接目标机，不修改功率/电流增益或物理电路。
% 重要：通过只代表保存结构就绪；不代表实时构建或电气稳定通过。

PKG=fileparts(mfilename('fullpath'));
C=jsondecode(fileread(fullfile(PKG,'ESS2_BASE_POWER_R1B_CONTRACT.json')));
MODEL=char(C.model);
if nargin<1 || isempty(modelRoot)
    if bdIsLoaded(MODEL)
        modelRoot=fileparts(get_param(MODEL,'FileName'));
    else
        modelRoot=['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
            'yanshou_V7\models\K26_K50_CLEAN_P1'];
    end
end
modelFile=canonical(fullfile(char(modelRoot),[MODEL '.slx']));
assert(isfile(modelFile),'BP1:MissingModel','找不到正式模型：%s',modelFile);
% 先确认用户模型，错误路径或未保存修改绝不自动关闭。
if bdIsLoaded(MODEL)
    assert(strcmpi(canonical(get_param(MODEL,'FileName')),modelFile), ...
        'BP1:WrongModel','同名模型从其他位置加载。');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'BP1:Dirty', ...
        '模型存在未保存修改；请先人工处理，不允许脚本代替你保存。');
    assert(strcmp(get_param(MODEL,'SimulationStatus'),'stopped'), ...
        'BP1:Running','主机模型尚未停止。');
end
out=fullfile(fileparts(modelFile),['PATCH_ESS2_BASE_POWER_R1_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
mkdir(out);
result=struct('version',C.version,'modelFile',modelFile,'outputDir',out, ...
    'status','STARTED','formalSaveAttempted',false,'matlabVersion',version, ...
    'sourceFileHash_provenanceOnly',fileHash(modelFile));
backupFile=''; backupHash=''; owned=false; formalTouched=false;
fid=fopen(fullfile(out,'PATCH_LOG.txt'),'w','n','UTF-8');
assert(fid>=0,'BP1:Log','无法创建日志。');
cleanupLog=onCleanup(@()fclose(fid)); %#ok<NASGU>
try
    checkAssets(C,PKG);
    owned=true;
    if ~bdIsLoaded(MODEL),loadExact(modelFile,MODEL);end
    % 不用原始模型哈希作控制语义硬门；仅检查具体正文/端口/连线/参数。
    if alreadyPatched(C,MODEL)
        checkModel(C,MODEL,'after',out,'ALREADY_APPLIED');
        result.status='ALREADY_APPLIED_DO_NOT_REAPPLY_RUN_INDEPENDENT_VERIFIER';
        writeJSON(fullfile(out,'RESULT.json'),result);
        fprintf('已是本版本，未重复改模。请运行独立验证脚本。\n%s\n',out);
        return;
    end
    checkModel(C,MODEL,'before',out,'FORMAL_PREFLIGHT');
    originalPhysical=physicalSignature(modelFile,fullfile(out,'PHYSICAL_BEFORE'));
    result.physicalSignatureBefore=originalPhysical;
    writeText(fullfile(out,'PHYSICAL_BEFORE_SIGNATURE.txt'),originalPhysical);
    close_system(MODEL,0);
    fprintf(fid,'正式模型只读预检查通过。\n');

    % 测试的是包内实际候选源代码；任一测试失败都不改正式文件。
    result.localTests=TEST_K26_K50_ESS2_BASE_POWER_R1B(fullfile(out,'SELFTEST'));
    assert(strcmp(result.localTests.status,'PASS_LOCAL_SOURCE_AND_ISOLATED_HARNESSES'), ...
        'BP1:Tests','本地源代码与隔离测试没有通过。');
    fprintf(fid,'本地源代码测试、标准模块与维度隔离测试通过。\n');

    scratchDir=fullfile(out,'SCRATCH');mkdir(scratchDir);
    scratchFile=fullfile(scratchDir,[MODEL '.slx']);
    mustCopy(modelFile,scratchFile);
    assert(strcmp(fileHash(modelFile),fileHash(scratchFile)),'BP1:Copy','副本字节不一致。');
    loadExact(scratchFile,MODEL);
    checkModel(C,MODEL,'before',out,'SCRATCH_PREFLIGHT');
    applyPlan(C,MODEL,PKG,fid);
    checkModel(C,MODEL,'after',out,'SCRATCH_POST_EDIT');
    save_system(MODEL); % 临时副本仅保存一次。
    close_system(MODEL,0);
    loadExact(scratchFile,MODEL);
    checkModel(C,MODEL,'after',out,'SCRATCH_RELOAD');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'BP1:ScratchDirty','临时副本重读后被回调改变。');
    close_system(MODEL,0);
    comparePhysical(originalPhysical,physicalSignature(scratchFile,fullfile(out,'PHYSICAL_SCRATCH')));
    fprintf(fid,'临时副本修改、保存一次、重读和物理连线保存签名检查通过。\n');

    backupFile=fullfile(out,[MODEL '_BEFORE_BASE_POWER_R1.slx']);
    mustCopy(modelFile,backupFile);backupHash=fileHash(backupFile);
    assert(strcmp(backupHash,fileHash(modelFile)),'BP1:Backup','备份字节不一致。');
    result.backupFile=backupFile;result.backupHash=backupHash;
    % 记录到磁盘后才触碰正式内存模型，便于任何失败均找到备份。
    writeJSON(fullfile(out,'RESULT.json'),result);
    loadExact(modelFile,MODEL);
    checkModel(C,MODEL,'before',out,'FORMAL_RE_PREFLIGHT');
    formalTouched=true;
    applyPlan(C,MODEL,PKG,fid);
    checkModel(C,MODEL,'after',out,'FORMAL_POST_EDIT');
    % 标志在保存之前置位，保存中途失败同样触发整体回滚。
    result.formalSaveAttempted=true;
    save_system(MODEL); % 正式模型仅保存一次。
    close_system(MODEL,0);
    loadExact(modelFile,MODEL);
    checkModel(C,MODEL,'after',out,'FORMAL_RELOAD');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'BP1:FormalDirty','正式模型重读后被回调改变。');
    comparePhysical(originalPhysical,physicalSignature(modelFile,fullfile(out,'PHYSICAL_AFTER')));
    result.patchedFileHash_provenanceOnly=fileHash(modelFile);
    result.status='SAVED_RELOADED_READY_FOR_INDEPENDENT_VERIFIER';
    result.requiredNext='VERIFY_K26_K50_ESS2_BASE_POWER_R1B，然后RT-LAB全部重新构建；暂不运行旧试验脚本。';
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf(fid,'正式保存、重读、受保护控制参数和物理连线检查通过。\n');
    fprintf('\n修改保存完成，正式模型保持打开。\n结果目录：%s\n',out);
    fprintf('下一步：verifyResult = VERIFY_K26_K50_ESS2_BASE_POWER_R1B;\n');
catch ME
    result.status='FAILED_NO_ELECTRICAL_VERDICT';
    result.errorIdentifier=ME.identifier;result.errorMessage=ME.message;
    result.errorReport=getReport(ME,'extended','hyperlinks','off');
    if owned && bdIsLoaded(MODEL)
        try close_system(MODEL,0);catch closeME
            result.closeError=closeME.message;
        end
    end
    if result.formalSaveAttempted && ~isempty(backupFile)
        try
            mustCopy(backupFile,modelFile);
            assert(strcmp(fileHash(modelFile),backupHash),'BP1:RestoreBytes','回滚字节验证失败。');
            result.rollback='WHOLE_FILE_RESTORED_AND_BYTE_CHECKED';
        catch rollbackME
            result.rollback=['FAILED: ' rollbackME.message];
        end
    elseif formalTouched
        result.rollback='DISCARDED_UNSAVED_FORMAL_EDITS';
    else
        result.rollback='FORMAL_MODEL_NOT_EDITED';
    end
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf(fid,'%s\n',result.errorReport);
    fprintf(2,'修改未完成；不要自行再次运行已成功阶段。结果：%s\n',out);
    rethrow(ME);
end
end

function applyPlan(C,mdl,pkg,fid)
ws=get_param(mdl,'ModelWorkspace');names=fieldnames(C.workspace);
for k=1:numel(names),assignin(ws,names{k},C.workspace.(names{k}));end
% 函数先更新固定接口；只改清单中的3个函数，不在运行时猜替换点。
for k=1:numel(C.functions)
    f=C.functions(k);
    if f.changed
        b=[mdl '/' f.path];c=chartAt(b);
        c.Script=fileread(fullfile(pkg,f.payload));drawnow;
    end
end
% 在连接文件编号前，先用当前安装记录块的正式掩膜参数切换接口。
for k=1:numel(C.sets)
    q=C.sets(k);set_param([mdl '/' q.path],q.param,q.after);
end
for k=1:numel(C.adds)
    b=C.adds(k);path=[mdl '/' b.path];par=parentOf(path);
    assert(getSimulinkBlockHandle(path)<0,'BP1:Exists','新增块已存在：%s',path);
    pos=freePosition(par,k,b.library);
    add_block(b.library,path,'Position',pos);
    if strcmp(b.library,'simulink/Ports & Subsystems/Subsystem')
        % 复用成功经验：默认子系统内容必须清空后再添加正规化连接。
        Simulink.SubSystem.deleteContents(path);
    end
    for j=1:numel(b.params)
        q=b.params(j);set_param(path,q.name,q.value);
    end
end
% 只删除清单里7根普通信号支路，按源/目标端口精确删除，不删整条分支主干。
for k=1:numel(C.rewires)
    e=C.rewires(k);s=[mdl '/' e.oldsrc];d=[mdl '/' e.dst];
    requireConnection(s,e.oldsp,d,e.dp);
    phs=get_param(s,'PortHandles');phd=get_param(d,'PortHandles');
    delete_line(get_param(d,'Parent'),phs.Outport(e.oldsp),phd.Inport(e.dp));
end
for k=1:numel(C.wires)
    e=C.wires(k);connectEmpty([mdl '/' e.src],e.sp,[mdl '/' e.dst],e.dp);
end
for k=1:numel(C.rewires)
    e=C.rewires(k);connectEmpty([mdl '/' e.src],e.sp,[mdl '/' e.dst],e.dp);
end
fprintf(fid,'本次修改：新增%d块，新增%d连接，替换%d支路；只读诊断和正规化占多数。\n', ...
    numel(C.adds),numel(C.wires),numel(C.rewires));
end

function issues=checkModel(C,mdl,phase,out,label)
issues={};after=strcmp(phase,'after');
for k=1:numel(C.functions)
    f=C.functions(k);
    try
        c=chartAt([mdl '/' f.path]);actual=hashText(char(c.Script));
        if after,expected=f.after;else,expected=f.before;end
        assert(strcmp(actual,expected),'BP1:Source','函数正文不符合%s：%s',phase,f.path);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.preserve_edges)
    e=C.preserve_edges(k);
    try requireConnection([mdl '/' e.src],e.sp,[mdl '/' e.dst],e.dp);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.native_tags)
    q=C.native_tags(k);
    try
        requireParam([mdl '/' q.from],'GotoTag',q.tag);
        actual=nativePublisher([mdl '/' q.from]);
        assert(strcmp(actual,[mdl '/' q.goto]),'BP1:TagSource','标签实际来源改变：%s',q.from);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.rewires)
    e=C.rewires(k);
    if after,s=e.src;sp=e.sp;else,s=e.oldsrc;sp=e.oldsp;end
    try requireConnection([mdl '/' s],sp,[mdl '/' e.dst],e.dp);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.adds)
    b=C.adds(k);p=[mdl '/' b.path];
    try
        if ~after
            assert(getSimulinkBlockHandle(p)<0,'BP1:Partial','修改前已存在新增块：%s',p);
        else
            assert(getSimulinkBlockHandle(p)>=0,'BP1:Missing','缺少新增块：%s',p);
            requireParam(p,'BlockType',b.expected_type);
            for j=1:numel(b.params),q=b.params(j);requireParam(p,q.name,q.value);end
        end
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
if after
    for k=1:numel(C.wires)
        e=C.wires(k);
        try requireConnection([mdl '/' e.src],e.sp,[mdl '/' e.dst],e.dp);
        catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
    end
end
for k=1:numel(C.sets)
    q=C.sets(k);if after,v=q.after;else,v=q.before;end
    try requireParam([mdl '/' q.path],q.param,v);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.frozen_parameters)
    q=C.frozen_parameters(k);
    try requireParam([mdl '/' q.path],q.param,q.value);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.frozen_ports)
    q=C.frozen_ports(k);
    if after,n=q.after_outputs;else,n=q.before_outputs;end
    try
        h=get_param([mdl '/' q.path],'PortHandles');
        assert(numel(h.Inport)==q.inputs && numel(h.Outport)==n, ...
            'BP1:Boundary','父子接口不符：%s',q.path);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
for k=1:numel(C.function_ports)
    q=C.function_ports(k);
    if after,ni=q.post_in;no=q.post_out;else,ni=q.pre_in;no=q.pre_out;end
    try
        h=get_param([mdl '/' q.path],'PortHandles');
        assert(numel(h.Inport)==ni && numel(h.Outport)==no, ...
            'BP1:FunctionBoundary','函数接口不符：%s',q.path);
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
try
    ws=get_param(mdl,'ModelWorkspace');ns=fieldnames(C.frozen_workspace);
    for k=1:numel(ns)
        v=getVariable(ws,ns{k});expected=C.frozen_workspace.(ns{k});
        assert(isa(v,'double') && isscalar(v) && isequal(v,expected), ...
            'BP1:Workspace','原有模型工作区参数不符：%s',ns{k});
    end
    ns=fieldnames(C.workspace);
    for k=1:numel(ns)
        if after
            v=getVariable(ws,ns{k});assert(isequal(v,C.workspace.(ns{k})), ...
                'BP1:DiagConfig','诊断保存配置不符：%s',ns{k});
        else
            assert(~hasVariable(ws,ns{k}),'BP1:WorkspaceConflict', ...
                '同名诊断变量已存在，不能覆盖：%s',ns{k});
        end
    end
catch ME,issues{end+1}=ME.message;end
ns=fieldnames(C.callbacks);
for k=1:numel(ns)
    try requireParam(mdl,ns{k},C.callbacks.(ns{k}));
    catch ME,issues{end+1}=ME.message;end %#ok<AGROW>
end
try checkRecorders(C,mdl,after);catch ME,issues{end+1}=ME.message;end
R=struct('phase',phase,'label',label,'unresolvedCount',numel(issues),'issues',{issues});
writeJSON(fullfile(out,[label '.json']),R);
if ~isempty(issues)
    error('BP1:SemanticCheck','%s共有%d项不符；已一次写入%s。首项：%s', ...
        label,numel(issues),out,issues{1});
end
end

function checkRecorders(C,mdl,after)
% 复用成功经验：不假设所有库块的BlockType必为Reference。
bs=find_system(mdl,'LookUnderMasks','all','FollowLinks','off','Type','Block');
found=[];paths={};
for k=1:numel(bs)
    b=bs{k};family=lower([optionalParam(b,'ReferenceBlock') ' ' ...
        optionalParam(b,'SourceBlock') ' ' optionalParam(b,'MaskType')]);
    if contains(family,'opwritefile') || contains(family,'opwrite file')
        g=str2double(get_param(b,'Acq_Group'));
        assert(isfinite(g),'BP1:RecordGroup','记录组编号不可读：%s',b);
        found(end+1)=g;paths{end+1}=b; %#ok<AGROW>
    end
end
assert(isequal(sort(found(:)),sort(C.recorder_group_set(:))), ...
    'BP1:RecordInventory','记录组数量、编号或唯一性不符。');
for k=1:numel(C.recorders)
    r=C.recorders(k);p=[mdl '/' r.path];idx=find(found==r.group);
    assert(numel(idx)==1 && strcmp(paths{idx},p),'BP1:RecordIdentity','记录组不唯一或位置改变。');
    if after
        ph=get_param(p,'PortHandles');
        assert(numel(ph.Inport)==2 && numel(ph.Outport)==2, ...
            'BP1:RecordDynamicPorts','动态文件记录块端口不是2输入2输出：%s',p);
        requireParam(p,'Static_File','off');requireParam(p,'Sim_Mode','off');
        requireParam(p,'write_offline','off');
    else
        fields=fieldnames(r.old);
        for j=1:numel(fields),requireParam(p,fields{j},r.old.(fields{j}));end
    end
end
end

function tf=alreadyPatched(C,mdl)
f=C.functions([C.functions.changed]);tf=true;
for k=1:numel(f)
    try c=chartAt([mdl '/' f(k).path]);tf=tf && strcmp(hashText(char(c.Script)),f(k).after);
    catch,tf=false;end
end
end
function checkAssets(C,pkg)
for k=1:numel(C.functions)
    f=C.functions(k);assert(strcmp(hashText(fileread(fullfile(pkg,f.reference))),f.before), ...
        'BP1:PackageReference','原始参考正文损坏：%s',f.reference);
    if f.changed
        assert(strcmp(hashText(fileread(fullfile(pkg,f.payload))),f.after), ...
            'BP1:PackagePayload','候选正文损坏：%s',f.payload);
    end
end
end
function c=chartAt(p)
r=sfroot;cs=r.find('-isa','Stateflow.EMChart');hit=[];
for k=1:numel(cs)
    if strcmp(char(cs(k).Path),p),hit(end+1)=k;end %#ok<AGROW>
end
assert(numel(hit)==1,'BP1:Chart','函数实例必须精确唯一：%s，匹配数%d',p,numel(hit));c=cs(hit);
end
function requireConnection(s,sp,d,dp)
assert(getSimulinkBlockHandle(s)>=0 && getSimulinkBlockHandle(d)>=0, ...
    'BP1:Endpoint','源或目标块不存在：%s -> %s',s,d);
ph=get_param(d,'PortHandles');sh=get_param(s,'PortHandles');
assert(dp>=1 && dp<=numel(ph.Inport) && sp>=1 && sp<=numel(sh.Outport), ...
    'BP1:Port','端口不存在：%s/%d -> %s/%d',s,sp,d,dp);
ln=get_param(ph.Inport(dp),'Line');
assert(isscalar(ln) && ln>=0,'BP1:Unconnected','未连接：%s 输入%d',d,dp);
actual=get_param(ln,'SrcPortHandle');
assert(isscalar(actual) && actual==sh.Outport(sp), ...
    'BP1:WrongSource','实际来源不符：%s 输入%d，期望%s 输出%d',d,dp,s,sp);
end
function connectEmpty(s,sp,d,dp)
assert(strcmp(get_param(s,'Parent'),get_param(d,'Parent')), ...
    'BP1:CrossHierarchy','禁止跨父层直接连线。');
ph=get_param(d,'PortHandles');sh=get_param(s,'PortHandles');
assert(dp<=numel(ph.Inport) && sp<=numel(sh.Outport),'BP1:NewPort','新增接口未建立。');
ln=get_param(ph.Inport(dp),'Line');
assert(isempty(ln)||all(ln<0),'BP1:Occupied','新增连接的目标已占用：%s 输入%d',d,dp);
add_line(get_param(d,'Parent'),sh.Outport(sp),ph.Inport(dp),'autorouting','on');
requireConnection(s,sp,d,dp);
end
function requireParam(b,k,v)
a=get_param(b,k);
if isnumeric(a),a=mat2str(a);end
if isnumeric(v),v=mat2str(v);end
a=strtrim(char(a));v=strtrim(char(v));
if strcmp(a,v),return;end
na=str2double(a);nv=str2double(v);
assert(isfinite(na)&&isfinite(nv)&&abs(na-nv)<=1e-13*max(1,abs(nv)), ...
    'BP1:Parameter','参数不符：%s [%s] 实际=%s，期望=%s',b,k,a,v);
end
function p=nativePublisher(from)
v=get_param(from,'GotoBlock');
if isstruct(v)
    assert(numel(v)==1,'BP1:TagStruct','标签来源结构不唯一。');
    if isfield(v,'handle'),v=v.handle;
    elseif isfield(v,'Handle'),v=v.Handle;
    elseif isfield(v,'name'),v=v.name;
    elseif isfield(v,'Name'),v=v.Name;
    else,error('BP1:TagStruct','无法识别标签来源结构。');end
end
if iscell(v),assert(numel(v)==1,'BP1:TagCell','标签来源不唯一。');v=v{1};end
assert(~isempty(v),'BP1:TagEmpty','标签没有发布源。');p=getfullname(v);
if iscell(p),assert(numel(p)==1,'BP1:TagPaths','标签路径不唯一。');p=p{1};end
assert(strcmp(get_param(p,'BlockType'),'Goto'),'BP1:TagType','来源不是标签发送块。');
end

function s=optionalParam(b,k)
p=get_param(b,'ObjectParameters');if isfield(p,k),s=char(get_param(b,k));else,s='';end
end
function p=freePosition(parent,serial,lib)
bs=find_system(parent,'SearchDepth',1,'Type','Block');rects=zeros(0,4);
for k=1:numel(bs)
    if ~strcmp(bs{k},parent),rects(end+1,:)=get_param(bs{k},'Position');end %#ok<AGROW>
end
w=130;h=45;
if contains(lib,'Mux') || contains(lib,'Demux'),w=12;h=150;end
if contains(lib,'Subsystem'),w=180;h=150;end
if contains(lib,'Inport') || contains(lib,'Outport'),w=35;h=22;end
% 放在父层原有图形右侧的确定网格，不移动已有控制或物理块。
x0=max([100;rects(:,3)])+50;
y0=60+mod(serial-1,6)*190;
p=round([x0 y0 x0+w y0+h]);
end
function s=physicalSignature(file,folder)
% 保存级物理连接签名：只读LConn/RConn端点成员，不按Src/Dst电流方向解释。
mkdir(folder);unzip(file,folder);fs=dir(fullfile(folder,'simulink','systems','*.xml'));rows={};
for k=1:numel(fs)
    x=xmlread(fullfile(fs(k).folder,fs(k).name));ls=x.getElementsByTagName('Line');
    for j=0:ls.getLength-1
        ln=ls.item(j);ps=ln.getElementsByTagName('P');terms={};
        for q=0:ps.getLength-1
            node=ps.item(q);nm=char(node.getAttribute('Name'));
            if strcmp(nm,'Src')||strcmp(nm,'Dst')
                v=char(node.getTextContent);
                if contains(lower(v),'#lconn')||contains(lower(v),'#rconn'),terms{end+1}=v;end %#ok<AGROW>
            end
        end
        if ~isempty(terms),rows{end+1}=[fs(k).name '|' strjoin(sort(terms),'|')];end %#ok<AGROW>
    end
end
assert(~isempty(rows),'BP1:PhysicalEmpty','没有提取到物理端点，不能将未知当作空网络。');
s=hashText(strjoin(sort(rows),newline));
end
function comparePhysical(a,b)
assert(strcmp(a,b),'BP1:PhysicalChanged','保存后的物理端点连接签名改变，停止并回滚。');
end
function loadExact(file,mdl)
if bdIsLoaded(mdl),error('BP1:Loaded','加载前同名模型仍在内存中。');end
load_system(file);
assert(bdIsLoaded(mdl) && strcmpi(canonical(get_param(mdl,'FileName')),canonical(file)), ...
    'BP1:LoadIdentity','加载的实际文件不是指定文件。');
end
function mustCopy(a,b)
[ok,msg]=copyfile(a,b,'f');assert(ok,'BP1:CopyFile','文件复制失败：%s',msg);
end
function p=canonical(p)
p=char(java.io.File(char(p)).getCanonicalPath());
end
function p=parentOf(p)
i=find(p=='/',1,'last');assert(~isempty(i),'BP1:Parent','无父层');p=p(1:i-1);
end
function h=hashText(t)
b=unicode2native(strrep(strrep(char(t),sprintf('\r\n'),sprintf('\n')),sprintf('\r'),sprintf('\n')),'UTF-8');h=hashBytes(b);
end
function h=fileHash(p)
f=fopen(p,'rb');assert(f>=0,'BP1:HashFile','文件不可读：%s',p);c=onCleanup(@()fclose(f)); %#ok<NASGU>
h=hashBytes(fread(f,Inf,'*uint8'));
end
function h=hashBytes(b)
md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(uint8(b(:)),'int8'));d=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(d,2).',1,[]));
end
function writeText(p,s)
f=fopen(p,'w','n','UTF-8');assert(f>=0,'BP1:Write','无法写入%s',p);c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',s);
end
function writeJSON(p,s)
writeText(p,jsonencode(s,'PrettyPrint',true));
end

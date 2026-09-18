function result = AUDIT_K26_K50_ESS2_LOCAL_COMPLETION_R3(outputRoot)
% 储能2本地补充只读审计。MATLAB（矩阵计算软件）R2023b。
% 同目录需有 ESS2_CURRENT_SAVED_CONTRACT.json（当前保存结构核对表）。
% 前提：当前正式模型已打开，且没有未保存修改。不要为运行本脚本重跑试验。
% 不加载、不保存、不编译、不运行模型，不连接实时目标机。
% 读取外部 fixer（初始化脚本）原文，但绝不执行它。
% 最终只报告读取完整性和结构差异，不报告电气通过。

model = 'K26_K50_CLEAN_P1';
scriptDir = fileparts(mfilename('fullpath'));
contractFile = fullfile(scriptDir,'ESS2_CURRENT_SAVED_CONTRACT.json');
if ~isfile(contractFile)
    error('ESS2READ:Contract','请将脚本和配套核对表解压到同一目录。');
end
if ~bdIsLoaded(model)
    error('ESS2READ:NotLoaded', ...
        '请使用已打开的正式模型。本脚本不代为加载，以免执行模型加载回调。');
end
if ~strcmp(get_param(model,'Dirty'),'off')
    error('ESS2READ:Unsaved','当前模型有未保存修改。先确认正式版本，不要让审计替你保存。');
end
if ~strcmp(get_param(model,'SimulationStatus'),'stopped')
    error('ESS2READ:HostRunning','主机模型并非停止状态。本脚本不会停止它，请先确认。');
end
modelFile = get_param(model,'FileName');
if ~isfile(modelFile)
    error('ESS2READ:File','无法读取当前模型对应的保存文件。');
end
if nargin<1 || isempty(outputRoot)
    outputRoot = fileparts(modelFile);
end
outputRoot = char(outputRoot);
if ~isfolder(outputRoot)
    error('ESS2READ:Output','输出父目录不存在：%s',outputRoot);
end
cfg = jsondecode(fileread(contractFile));
if ~strcmp(cfg.model,model)
    error('ESS2READ:WrongContract','核对表模型名称不匹配。');
end
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
outDir = fullfile(outputRoot,['ESS2_LOCAL_READOUT_R3_' stamp]);
mkdir(outDir);
issues = cell(0,3);
checks = cell(0,4);
beforeDirty = get_param(model,'Dirty');
beforeHash = shaFile(modelFile);
result = struct('model',model,'modelFile',modelFile,'outDir',outDir, ...
    'started',datestr(now,31),'matlabVersion',version, ...
    'savedHashBefore',beforeHash,'contractHashIsOnlyProvenance',true);

% 第一部分：外部初始化与运行环境。仅读取，绝不调用回调。
callbacks = cell(0,3);
for name = {'PreLoadFcn','PostLoadFcn','InitFcn','StartFcn','StopFcn','CloseFcn'}
    [v,ok,msg] = readParam(model,name{1});
    if ok
        callbacks(end+1,:) = {model,name{1},textValue(v)}; %#ok<AGROW>
    else
        issues(end+1,:) = {'CALLBACK_READ',name{1},msg}; %#ok<AGROW>
    end
end
writeCsv(fullfile(outDir,'01_MODEL_CALLBACKS.csv'), ...
    {'Path','Parameter','Value'},callbacks);

external = cell(0,5);
try
    paths = which('fixer','-all');
    if ischar(paths), paths = cellstr(paths); end
    if isstring(paths), paths = cellstr(paths); end
    if isempty(paths)
        issues(end+1,:) = {'EXTERNAL_DEPENDENCY','fixer', ...
            '当前搜索路径未找到 fixer。未执行、未推断其作用。'};
    end
    for k=1:numel(paths)
        p = char(paths{k});
        [~,~,ext] = fileparts(p);
        if isfile(p) && strcmpi(ext,'.m')
            bytes = readBytes(p);
            target = sprintf('02_FIXER_SOURCE_%02d.m',k);
            writeBytes(fullfile(outDir,target),bytes);
            external(end+1,:) = {k,p,shaBytes(bytes),target,'COPIED_NOT_EXECUTED'}; %#ok<AGROW>
        else
            external(end+1,:) = {k,p,'','','SOURCE_NOT_READABLE'}; %#ok<AGROW>
            issues(end+1,:) = {'EXTERNAL_SOURCE',p, ...
                '只能看到名称或加密文件，无法审阅初始化行为。'}; %#ok<AGROW>
        end
    end
    if numel(paths)>1
        checks(end+1,:) = {'FIXER_MULTIPLE_MATCHES','REVIEW','fixer', ...
            '存在多个候选，已保留搜索顺序；首选文件仍需人工核读。'};
    end
catch ME
    issues(end+1,:) = {'EXTERNAL_DISCOVERY','fixer',ME.message};
end
writeCsv(fullfile(outDir,'02_EXTERNAL_FILES.csv'), ...
    {'SearchOrder','Path','SHA256','CopiedFile','Status'},external);
try
    libraryInfo=struct('power_initmask_paths',{which('power_initmask','-all')}, ...
        'installedProducts',ver);
    writeJson(fullfile(outDir,'02_LIBRARY_ENVIRONMENT.json'),libraryInfo);
catch ME
    issues(end+1,:)={'LIBRARY_ENVIRONMENT',model,ME.message};
end


vars = cell(0,4);
try
    ws = get_param(model,'ModelWorkspace');
    names = asCell(cfg.model_variables);
    for k=1:numel(names)
        n = char(names{k});
        if hasVariable(ws,n)
            v = getVariable(ws,n);
            vars(end+1,:) = {n,class(v),textValue(v),'MODEL_WORKSPACE'}; %#ok<AGROW>
        else
            vars(end+1,:) = {n,'','NOT_IN_MODEL_WORKSPACE','NOT_ASSUMED_ZERO'}; %#ok<AGROW>
        end
    end
catch ME
    issues(end+1,:) = {'MODEL_WORKSPACE',model,ME.message};
end
writeCsv(fullfile(outDir,'03_MODEL_WORKSPACE.csv'), ...
    {'Name','Class','Value','Origin'},vars);

maskRows = cell(0,4);
maskPaths = asCell(cfg.mask_workspaces);
for k=1:numel(maskPaths)
    p = fullPath(model,maskPaths{k});
    try
        obj = Simulink.Mask.get(p);
        if isempty(obj)
            issues(end+1,:) = {'MASK_WORKSPACE',p,'预期掩膜不存在。'}; %#ok<AGROW>
            continue;
        end
        v = obj.getWorkspaceVariables;
        if isempty(v)
            issues(end+1,:) = {'MASK_WORKSPACE',p, ...
                '当前未取得已求值掩膜变量；未执行初始化来填充。'}; %#ok<AGROW>
        end
        for j=1:numel(v)
            maskRows(end+1,:) = {p,char(v(j).Name), ...
                class(v(j).Value),textValue(v(j).Value)}; %#ok<AGROW>
        end
        expectedNames=asCell(cfg.mask_required_vars(k).required_names);
        if isempty(v),readNames={};else,readNames={v.Name};end
        for j=1:numel(expectedNames)
            if ~any(strcmp(char(expectedNames{j}),readNames))
                issues(end+1,:)={'MASK_REQUIRED_VALUE',p, ...
                    ['缺少实际求值变量：' char(expectedNames{j})]}; %#ok<AGROW>
            end
        end
    catch ME
        issues(end+1,:) = {'MASK_WORKSPACE',p,ME.message}; %#ok<AGROW>
    end
end
writeCsv(fullfile(outDir,'04_MASK_WORKSPACES.csv'), ...
    {'Path','Name','Class','Value'},maskRows);

% 第二部分：逐条核对保存文件中的普通信号连接，包含状态输出。
% 不访问物理电气端口，不把物理节点当成普通源/目标线。
linkRows = cell(numel(cfg.links),9);
for k=1:numel(cfg.links)
    s = cfg.links(k);
    dp = fullPath(model,s.destination);
    expectedSource = fullPath(model,s.source);
    [src,sp,sk,ok,msg] = sourceAt(dp,s.destination_kind,s.destination_port);
    matches = ok && strcmp(src,expectedSource) && sp==s.source_port && ...
        sameKind(sk,s.source_kind);
    status = 'MATCH';
    if ~matches
        status = 'UNRESOLVED_OR_DIFFERENT';
        issues(end+1,:) = {'DIRECT_EDGE',dp, ...
            sprintf('目标端口 %s:%d；%s',s.destination_kind,s.destination_port,msg)}; %#ok<AGROW>
    end
    linkRows(k,:) = {dp,s.destination_kind,s.destination_port,expectedSource, ...
        s.source_port,src,sp,sk,status};
end
writeCsv(fullfile(outDir,'05_DIRECT_CONNECTION_COMPARISON.csv'), ...
    {'Destination','DestinationKind','DestinationPort','SavedSource', ...
     'SavedSourcePort','LoadedSource','LoadedSourcePort','LoadedSourceKind','Status'},linkRows);

% 第三部分：使用软件实际解析出的标签发布源，不再限制在错误的子系统范围。
fromRows = cell(numel(cfg.froms),5);
for k=1:numel(cfg.froms)
    r = cfg.froms(k); p = fullPath(model,r.path);
    [gp,ok,msg] = nativeGoto(p);
    state = 'NATIVE_RESOLVED';
    if ~ok
        state = 'UNRESOLVED';
        issues(end+1,:) = {'FROM_GOTO',p,msg}; %#ok<AGROW>
    else
        c = asCell(r.candidates);
        expected = cellfun(@(x)fullPath(model,x),c,'UniformOutput',false);
        if ~isempty(expected) && ~any(strcmp(gp,expected))
            state = 'RESOLVED_DIFFERENT_FROM_SAVED_CANDIDATES';
            issues(end+1,:) = {'FROM_GOTO',p,gp}; %#ok<AGROW>
        end
    end
    fromRows(k,:) = {p,r.tag,gp,state,msg};
end
writeCsv(fullfile(outDir,'06_NATIVE_FROM_GOTO.csv'), ...
    {'FromPath','SavedTag','NativeGotoPath','Status','Detail'},fromRows);

% 第四部分：核对函数正文。忽略换行编码，不忽略语句、参数或运算符。
functionRows = cell(numel(cfg.functions),5);
try
    root = sfroot;
    allCharts = root.find('-isa','Stateflow.EMChart');
catch ME
    allCharts = [];
    issues(end+1,:) = {'FUNCTION_ROOT',model,ME.message};
end
for k=1:numel(cfg.functions)
    s = cfg.functions(k); p = fullPath(model,s.path);
    ids = [];
    for j=1:numel(allCharts)
        try
            if strcmp(char(allCharts(j).Path),p),ids(end+1)=j;end %#ok<AGROW>
        catch ME
            issues(end+1,:)={'FUNCTION_OBJECT',p,ME.message}; %#ok<AGROW>
        end
    end
    fn = sprintf('07_FUNCTION_%02d.m.txt',k);
    hash = ''; status = 'UNRESOLVED';
    if numel(ids)==1
        txt = char(allCharts(ids).Script);
        txt = normalizeText(txt);
        hash = shaBytes(unicode2native(txt,'UTF-8'));
        writeText(fullfile(outDir,fn),txt);
        if strcmp(hash,s.sha256_normalized)
            status = 'MATCH';
        else
            status = 'SOURCE_DIFFERENT';
            issues(end+1,:) = {'FUNCTION_SOURCE',p,'已加载正文与上传保存文件不同。'}; %#ok<AGROW>
        end
    else
        issues(end+1,:) = {'FUNCTION_SOURCE',p, ...
            sprintf('匹配到 %d 个函数对象，没有选择第一个。',numel(ids))}; %#ok<AGROW>
    end
    functionRows(k,:) = {p,s.sha256_normalized,hash,status,fn};
end
writeCsv(fullfile(outDir,'07_FUNCTION_COMPARISON.csv'), ...
    {'Path','SavedTextHash','LoadedTextHash','Status','ExportedFile'},functionRows);

% 第五部分：读取隐含默认值、比例积分器初值/复位和恢复状态参数。
% 原始表达式如 Init/Ts 不自行当成数值；实际掩膜数值在第04项。
paramRows = cell(0,6);
baseNames = {'InitialCondition','InitialConditionSetting','ExternalReset', ...
    'ShowStatePort','LimitOutput','UpperSaturationLimit','LowerSaturationLimit', ...
    'IntegratorMethod','SampleTime','Gain','UpperLimit','LowerLimit', ...
    'Criteria','Threshold','Before','After','Time','RisingSlewLimit', ...
    'FallingSlewLimit','MaskInitialization','MaskSelfModifiable','LinkStatus', ...
    'ReferenceBlock','SourceBlock','MaskType'};
for k=1:numel(cfg.parameters)
    s=cfg.parameters(k);p=fullPath(model,s.path);
    extraNames=asCell(s.mask_parameter_names);
    names=unique([baseNames(:);extraNames(:)]);
    try
        props=get_param(p,'ObjectParameters');
        maskNames=get_param(p,'MaskNames');
        if isempty(maskNames),maskNames={};end
        names=unique([names(:);maskNames(:)]);
        for j=1:numel(names)
            n=char(names{j});
            if ~isfield(props,n) && ~any(strcmp(n,maskNames)),continue;end
            [v,ok,msg]=readParam(p,n);
            old='NOT_EXPLICIT_IN_SLX';
            if isfield(s.saved_params,n),old=textValue(s.saved_params.(n));end
            if ok
                paramRows(end+1,:)={p,n,old,class(v),textValue(v),'READ'}; %#ok<AGROW>
            else
                paramRows(end+1,:)={p,n,old,'',msg,'UNRESOLVED'}; %#ok<AGROW>
                issues(end+1,:)={'PARAMETER',p,[n ': ' msg]}; %#ok<AGROW>
            end
        end
    catch ME
        issues(end+1,:)={'PARAMETER_BLOCK',p,ME.message}; %#ok<AGROW>
    end
end
writeCsv(fullfile(outDir,'08_PARAMETERS_AND_DEFAULTS.csv'), ...
    {'Path','Parameter','SavedExpression','LoadedClass','LoadedValue','Status'},paramRows);

% 第六部分：记录块按成熟的引用/掩膜标识扫描，不假设 BlockType=Reference。
recRows=cell(0,4); recorderGroups=[];
try
    blocks=find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block');
    for k=1:numel(blocks)
        p=blocks{k};hay='';
        for field={'ReferenceBlock','SourceBlock','MaskType'}
            [v,ok,~]=readParam(p,field{1});
            if ok,hay=[hay ' ' lower(textValue(v))];end %#ok<AGROW>
        end
        if ~contains(hay,'opwritefile'),continue;end
        [group,ok,msg]=readParam(p,'Acq_Group');
        if ~ok
            issues(end+1,:)={'RECORDER_GROUP',p,msg}; %#ok<AGROW>
            continue;
        end
        ng=str2double(textValue(group));
        if ~ismember(ng,[27 29 30]),continue;end
        recorderGroups(end+1)=ng; %#ok<AGROW>
        fields={'Acq_Group','Decimation','DecimationFactor','Decim_Factor', ...
            'File_Size','FileSize','file_size','Nb_Samples','Buffer_Size', ...
            'buffer_size','Static','Static_FileName','StaticFilename', ...
            'Sim_Mode','Simulink_Mode','Filename','FileName','VariableName', ...
            'Variable','RT_Path','NRT_Path','ReferenceBlock','SourceBlock','MaskType'};
        masks=get_param(p,'MaskNames');
        props=get_param(p,'ObjectParameters');
        fields=unique([fields(:);masks(:)]);
        for j=1:numel(fields)
            n=char(fields{j});
            if ~isfield(props,n) && ~any(strcmp(n,masks)),continue;end
            [v,ok,msg]=readParam(p,n);
            if ok
                recRows(end+1,:)={ng,p,n,textValue(v)}; %#ok<AGROW>
            else
                issues(end+1,:)={'RECORDER_PARAMETER',p,[n ': ' msg]}; %#ok<AGROW>
            end
        end
        ph=get_param(p,'PortHandles');
        for j=1:numel(ph.Outport)
            recRows(end+1,:)={ng,p,sprintf('output_%d_consumers',j), ...
                consumerText(ph.Outport(j))}; %#ok<AGROW>
        end
    end
    for ng=[27 29 30]
        if sum(recorderGroups==ng)~=1
            issues(end+1,:)={'RECORDER_COUNT',num2str(ng), ...
                sprintf('匹配数量 %d；不按名称猜测记录组。',sum(recorderGroups==ng))}; %#ok<AGROW>
        end
    end
catch ME
    issues(end+1,:)={'RECORDER_SCAN',model,ME.message};
end
writeCsv(fullfile(outDir,'09_RECORDER_SETTINGS.csv'), ...
    {'Group','Path','Parameter','Value'},recRows);

% 第七部分：关键跨层输入的可读追踪。遇到运算/状态/通信即保留边界。
traceRows=cell(0,7);
for k=1:numel(cfg.trace_inputs)
    r=cfg.trace_inputs(k);p=fullPath(model,r.path);
    for port=reshape(r.ports,1,[])
        [rows,ok,msg]=traceInput(p,port,model);
        traceRows=[traceRows;rows]; %#ok<AGROW>
        if ~ok,issues(end+1,:)={'KEY_TRACE',p,sprintf('%d: %s',port,msg)};end %#ok<AGROW>
    end
end
writeCsv(fullfile(outDir,'10_KEY_SOURCE_TRACES.csv'), ...
    {'Destination','InputPort','Depth','Path','OutputPort','BlockType','Detail'},traceRows);

% 最后检查：读取过程中不得改变已保存文件或脏状态。
afterHash=shaFile(modelFile);afterDirty=get_param(model,'Dirty');
if ~strcmp(beforeHash,afterHash)
    issues(end+1,:)={'READ_ONLY_FILE',modelFile,'读取前后保存文件字节不同，需核查外部并行操作。'};
end
if ~strcmp(beforeDirty,afterDirty)
    issues(end+1,:)={'READ_ONLY_DIRTY',model,'读取前后未保存修改标志不同；本脚本未保存。'};
end
result.savedHashAfter=afterHash;
result.dirtyBefore=beforeDirty;result.dirtyAfter=afterDirty;
result.finished=datestr(now,31);
result.counts=struct('directEdges',size(linkRows,1),'froms',size(fromRows,1), ...
    'functions',size(functionRows,1),'unresolved',size(issues,1));
result.unresolved=issues;
result.additionalChecks=checks;
result.reviewRequired={ ...
    '必须核读已复制的 fixer 原文；本脚本不会因找到文件就宣布其无副作用。'; ...
    '读取的是主机已加载模型，不是实时目标机当前参数或内部状态。'; ...
    '记录尾段是否落盘/传回，仍需下一轮完整的记录结束与文件回传证据。'; ...
    '修改后的基础小功率电气稳定性仍须试验验证。'};
if isempty(issues)
    result.status='READOUT_COMPLETE_PENDING_EXTERNAL_SOURCE_REVIEW';
else
    result.status='READOUT_INCOMPLETE_REVIEW_UNRESOLVED';
end
result.archive=[outDir '.zip'];
writeCsv(fullfile(outDir,'11_UNRESOLVED.csv'),{'Category','PathOrItem','Detail'},issues);
writeJson(fullfile(outDir,'RESULT.json'),result);
summary=sprintf(['储能2本地补充只读审计\n状态：%s\n模型：%s\n' ...
    '普通连接：%d\n标签：%d\n函数：%d\n未完成项：%d\n' ...
    '外部初始化脚本只复制、不执行。此状态不表示电气稳定通过。\n'], ...
    result.status,modelFile,size(linkRows,1),size(fromRows,1),size(functionRows,1),size(issues,1));
writeText(fullfile(outDir,'00_README.txt'),summary);
try
    listing=dir(outDir);listing=listing(~[listing.isdir]);
    zip(result.archive,{listing.name},outDir);
catch ME
    result.archive='';result.archiveError=ME.message;
    writeJson(fullfile(outDir,'RESULT.json'),result);
end
fprintf('%s\n',summary);
fprintf('结果目录：%s\n',outDir);
if ~isempty(result.archive),fprintf('上传压缩包：%s\n',result.archive);end
end

function p=fullPath(model,relative)
r=char(relative);p=[model '/' r];
end
function c=asCell(x)
if isempty(x),c={};elseif iscell(x),c=x;elseif isstring(x),c=cellstr(x);else,c={char(x)};end
end
function [v,ok,msg]=readParam(p,n)
v=[];ok=false;msg='';
try,v=get_param(p,n);ok=true;catch ME,msg=ME.message;end
end
function [src,pn,kind,ok,msg]=sourceAt(block,kindIn,n)
src='';pn=NaN;kind='';ok=false;msg='';
try
    ph=get_param(block,'PortHandles');
    switch lower(char(kindIn))
        case 'in', f='Inport';
        case 'enable', f='Enable';
        case 'trigger', f='Trigger';
        otherwise, msg=['不支持的目标端口类型：' char(kindIn)];return;
    end
    if ~isfield(ph,f) || n<1 || n>numel(ph.(f))
        msg='目标端口不存在';return;
    end
    target=ph.(f);lh=get_param(target(n),'Line');
    if ~isscalar(lh) || lh<0,msg='目标端口无唯一普通输入线';return;end
    sh=get_param(lh,'SrcPortHandle');bh=get_param(lh,'SrcBlockHandle');
    if ~isscalar(sh) || sh<0 || ~isscalar(bh) || bh<0
        msg='源端口或源模块不唯一';return;
    end
    src=getfullname(bh);pn=get_param(sh,'PortNumber');
    kind=lower(char(get_param(sh,'PortType')));
    if strcmp(kind,'state'),pn=1;end % 单一状态输出用序号1记录，不混成普通输出。
    if ~isnumeric(pn),pn=str2double(char(pn));end
    ok=isscalar(pn) && isfinite(pn);
    if ~ok,msg='源端口序号不可读';end
catch ME,msg=ME.message;end
end
function tf=sameKind(a,b)
a=lower(char(a));b=lower(char(b));
if strcmp(a,'outport'),a='out';end
if strcmp(b,'outport'),b='out';end
tf=strcmp(a,b);
end
function [p,ok,msg]=nativeGoto(from)
p='';ok=false;msg='';
try
    v=get_param(from,'GotoBlock');
    if isstruct(v)
        if numel(v)~=1,msg='标签发布源结构不是唯一对象';return;end
        if isfield(v,'handle'),h=v.handle;
        elseif isfield(v,'Handle'),h=v.Handle;
        elseif isfield(v,'name'),h=v.name;
        elseif isfield(v,'Name'),h=v.Name;
        else,msg='无法识别 GotoBlock 返回结构';return;
        end
    else
        h=v;
    end
    if iscell(h)
        if numel(h)~=1,msg='标签发布源不是唯一对象';return;end
        h=h{1};
    end
    if isempty(h),msg='标签发布源为空';return;end
    p=getfullname(h);
    if iscell(p)
        if numel(p)~=1,msg='标签发布源路径不唯一';p='';return;end
        p=p{1};
    end
    ok=strcmp(get_param(p,'BlockType'),'Goto');
    if ~ok,msg='解析结果不是标签发送块';end
catch ME,msg=ME.message;end
end
function [rows,ok,msg]=traceInput(dst,port,model)
rows=cell(0,7);ok=false;msg='';
[b,n,~,good,detail]=sourceAt(dst,'in',port);
if ~good,msg=detail;return;end
seen={};
for depth=0:79
    key=sprintf('%s:%g',b,n);
    if any(strcmp(key,seen)),msg='检测到追踪循环';return;end
    seen{end+1}=key; %#ok<AGROW>
    try,typ=get_param(b,'BlockType');catch ME,msg=ME.message;return;end
    detail='';
    if strcmp(typ,'From')
        [gp,good,detail]=nativeGoto(b);
        rows(end+1,:)={dst,port,depth,b,n,typ,[detail ' -> ' gp]}; %#ok<AGROW>
        if ~good,msg=detail;return;end
        [b,n,~,good,detail]=sourceAt(gp,'in',1);
    elseif strcmp(typ,'Inport')
        parent=get_param(b,'Parent');ip=str2double(get_param(b,'Port'));
        rows(end+1,:)={dst,port,depth,b,n,typ,'穿过父层输入端口'}; %#ok<AGROW>
        if strcmp(parent,model),ok=true;return;end
        [b,n,~,good,detail]=sourceAt(parent,'in',ip);
    elseif strcmp(typ,'SubSystem')
        [sf,sfok,~]=readParam(b,'SFBlockType');
        if sfok && strcmp(sf,'MATLAB Function')
            rows(end+1,:)={dst,port,depth,b,n,typ,'函数计算边界；正文单独导出'}; %#ok<AGROW>
            ok=true;return;
        end
        op=find_system(b,'SearchDepth',1,'LookUnderMasks','all', ...
            'FollowLinks','off','BlockType','Outport');
        hits={};
        for k=1:numel(op)
            if str2double(get_param(op{k},'Port'))==n,hits{end+1}=op{k};end %#ok<AGROW>
        end
        rows(end+1,:)={dst,port,depth,b,n,typ,'穿过子系统输出端口'}; %#ok<AGROW>
        if numel(hits)~=1,msg='子系统输出端口未唯一解析';return;end
        [b,n,~,good,detail]=sourceAt(hits{1},'in',1);
    else
        rows(end+1,:)={dst,port,depth,b,n,typ, ...
            '真实运算、状态或库接口边界；不把它当成纯线消去'}; %#ok<AGROW>
        ok=true;return;
    end
    if ~good,msg=detail;return;end
end
msg='超出有限追踪深度';
end
function s=consumerText(ph)
s='UNCONNECTED';lh=get_param(ph,'Line');
if ~isscalar(lh) || lh<0,return;end
bh=get_param(lh,'DstBlockHandle');pp=get_param(lh,'DstPortHandle');a={};
for j=1:numel(bh)
    if bh(j)>=0 && pp(j)>=0
        a{end+1}=sprintf('%s/in%g',getfullname(bh(j)),get_param(pp(j),'PortNumber')); %#ok<AGROW>
    end
end
if ~isempty(a),s=strjoin(a,' | ');end
end
function s=textValue(x)
if isnumeric(x)||islogical(x)
    s=mat2str(x,17);
elseif ischar(x)
    s=x;
elseif isstring(x)
    s=strjoin(cellstr(x(:)),' | ');
elseif iscell(x)
    z=cellfun(@textValue,x,'UniformOutput',false);s=strjoin(z(:),' | ');
elseif isa(x,'Simulink.Parameter')
    s=['Simulink.Parameter Value=' textValue(x.Value)];
else
    try,s=jsonencode(x);catch,s=['UNSERIALIZED_CLASS:' class(x)];end
end
end
function s=normalizeText(s)
s=strrep(s,sprintf('\r\n'),sprintf('\n'));s=strrep(s,sprintf('\r'),sprintf('\n'));
if ~isempty(s)&&double(s(1))==65279,s=s(2:end);end
end
function b=readBytes(path)
f=fopen(path,'rb');if f<0,error('ESS2READ:Read','无法读取：%s',path);end
c=onCleanup(@()fclose(f)); %#ok<NASGU>
b=fread(f,Inf,'*uint8');
end
function h=shaFile(path)
h=shaBytes(readBytes(path));
end
function h=shaBytes(b)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
md.update(typecast(uint8(b(:)),'int8'));
r=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(r,2).',1,[]));
end
function writeBytes(path,b)
f=fopen(path,'wb');if f<0,error('ESS2READ:Write','无法写入结果：%s',path);end
c=onCleanup(@()fclose(f)); %#ok<NASGU>
fwrite(f,b,'uint8');
end
function writeText(path,text)
f=fopen(path,'w','n','UTF-8');if f<0,error('ESS2READ:Write','无法写入结果：%s',path);end
c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',char(text));
end
function writeJson(path,x)
writeText(path,jsonencode(x,'PrettyPrint',true));
end
function writeCsv(path,headers,rows)
f=fopen(path,'w','n','UTF-8');if f<0,error('ESS2READ:Write','无法写入结果：%s',path);end
c=onCleanup(@()fclose(f)); %#ok<NASGU>
writeRow(f,headers);
for k=1:size(rows,1),writeRow(f,rows(k,:));end
end
function writeRow(f,row)
s=cell(1,numel(row));
for k=1:numel(row)
    t=textValue(row{k});t=strrep(t,'"','""');
    s{k}=['"' t '"'];
end
fprintf(f,'%s\n',strjoin(s,','));
end

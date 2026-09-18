function result = AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1(outputRoot)
% 储能2完全正式恢复改模前：只读全链路审计。
% MATLAB（矩阵计算软件）R2023b。配套JSON（结构核对表）须与本文件同目录。
%
% 用法：保持当前源模型已打开且已保存，在主机停止状态运行：
% result = AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1;
%
% 继承成功审计的端口读取、原生标签解析、完整函数导出、CSV写出方法。
% 不加载模型、不执行任何初始化回调、不更新库链接、不求值参数表达式。
% 不改参数/连线/状态，不保存、编译或运行模型，不连接实时目标机。
% 文件哈希只作出处记录；不以旧哈希阻断新版本的结构读取。
% 只导出证据，不自动宣称健康门控、稳定性或接管验收通过。
%
% 输出默认位于临时目录E2_AUDIT，而不是RT-LAB（实时平台）模型目录。
% 请上传自动生成的结果ZIP（压缩包）；无需复制大型原始MAT数据。

VERSION = 'ESS2_COMPLETE_RESTORE_PREPATCH_READONLY_R1_20260918';
scriptDir = fileparts(mfilename('fullpath'));
contractFile = fullfile(scriptDir,'ESS2_COMPLETE_RESTORE_AUDIT_SCOPE_R1.json');
if ~isfile(contractFile)
    error('E2RH:Scope','请完整解压脚本包；结构核对表须与审计脚本同目录。');
end
C = jsondecode(fileread(contractFile));
model = char(C.model);
if ~bdIsLoaded(model)
    error('E2RH:NotOpen','请先打开当前模型。审计不会代为加载，避免执行加载回调。');
end
if ~strcmp(get_param(model,'SimulationStatus'),'stopped')
    error('E2RH:HostRunning','主机模型须为停止状态；审计不会停止或控制目标机。');
end
if ~strcmp(get_param(model,'Dirty'),'off')
    error('E2RH:Unsaved','当前模型存在未保存修改。请先自行处理；审计不会保存模型。');
end
modelFile = get_param(model,'FileName');
if ~isfile(modelFile)
    error('E2RH:Source','当前模型未找到对应源文件。');
end
if nargin<1 || isempty(outputRoot)
    outputRoot = fullfile(tempdir,'E2_AUDIT');
end
outputRoot = char(outputRoot);
if pathWithin(outputRoot,fileparts(modelFile))
    error('E2RH:OutputLocation','请将审计输出放在实时模型目录以外，例如D:\E2AUDIT。');
end
if ~isfolder(outputRoot), mkdir(outputRoot); end
[~,uid] = fileparts(tempname(outputRoot));
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
outDir = fullfile(outputRoot,['E2_COMPLETE_RESTORE_AUDIT_' stamp '_' uid]);
mkdir(outDir);
logFile = fullfile(outDir,'00_RUN_LOG.txt');
issues = cell(0,4);
checks = cell(0,4);
phase = 'PRECHECK';
sourceBefore = shaFile(modelFile);
dirtyBefore = get_param(model,'Dirty');
result = struct('version',VERSION,'model',model,'modelFile',modelFile, ...
    'outDir',outDir,'started',datestr(now,31),'matlabVersion',version, ...
    'status','READOUT_STARTED','sourceHashBefore',sourceBefore, ...
    'referenceHash',C.source_sha256,'referenceHashIsOnlyProvenance',true, ...
    'targetConnected',false,'electricalVerdict','NOT_EVALUATED', ...
    'nativeCompiledDimensionsRead',false,'parameterExpressionsExecuted',false);
writeJson(fullfile(outDir,'RESULT.json'),result);
writeText(fullfile(outDir,'00_SCOPE_QUESTIONS.json'),fileread(contractFile));
logLine(logFile,'开始只读审计：ESS2完全正式恢复改模前全链路。');
H=[]; P={}; types={}; selected=[]; edges=cell(0,9); chartRows=cell(0,5);
try
    %% 1. 模型环境和回调只读取，不执行。
    phase='MODEL_ENVIRONMENT';
    rows=cell(0,3);
    modelProps={'PreLoadFcn','PostLoadFcn','InitFcn','StartFcn','StopFcn', ...
        'CloseFcn','PreSaveFcn','PostSaveFcn','DataDictionary','SolverType', ...
        'Solver','FixedStep','StartTime','StopTime','SimulationMode','ModelVersion'};
    for k=1:numel(modelProps)
        [v,ok,msg]=readParam(model,modelProps{k});
        if ok, rows(end+1,:)={model,modelProps{k},valueText(v)}; %#ok<AGROW>
        else, issues(end+1,:)={'INFO','MODEL_PROPERTY',modelProps{k},msg}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'01_MODEL_PROPERTIES.csv'), ...
        {'Path','Property','RawValue'},rows);
    dependencies=cell(0,4);
    for nm={'fixer','power_initmask'}
        try
            cand=asCells(which(nm{1},'-all'));
            if isempty(cand), dependencies(end+1,:)={nm{1},'','NOT_FOUND','NOT_EXECUTED'}; end %#ok<AGROW>
            for j=1:numel(cand)
                % 受保护兼容文件只记录位置，不读取、不复制、不逆向。
                dependencies(end+1,:)={nm{1},cand{j},'PATH_ONLY','NOT_EXECUTED'}; %#ok<AGROW>
            end
        catch ME
            issues(end+1,:)={'REVIEW','DEPENDENCY',nm{1},ME.message}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'01_DEPENDENCY_LOCATIONS.csv'), ...
        {'Name','Path','Access','Execution'},dependencies);
    wsRows=cell(0,4);
    try
        ws=get_param(model,'ModelWorkspace');
        % whos（变量目录）只列当前工作区，不重新加载或执行其来源。
        wi=whos(ws); wn={};
        if ~isempty(wi)
            if isfield(wi,'name'), wn={wi.name};
            elseif isfield(wi,'Name'), wn={wi.Name}; end
        end
        requested=unique([reshape(asCells(C.model_variables),[],1);reshape(wn,[],1)],'stable');
        for nm=reshape(requested,1,[])
            n=char(nm{1});
            if hasVariable(ws,n)
                v=getVariable(ws,n);
                wsRows(end+1,:)={n,class(v),valueText(v),'MODEL_WORKSPACE'}; %#ok<AGROW>
            else
                wsRows(end+1,:)={n,'','NOT_PRESENT','NOT_ASSUMED_ZERO'}; %#ok<AGROW>
            end
        end
    catch ME
        issues(end+1,:)={'REVIEW','MODEL_WORKSPACE',model,ME.message}; %#ok<AGROW>
    end
    writeCsv(fullfile(outDir,'01_MODEL_WORKSPACE_VALUES.csv'), ...
        {'Name','Class','CurrentStoredValue','Origin'},wsRows);
    try
        ws=get_param(model,'ModelWorkspace');
        writeCsv(fullfile(outDir,'01_MODEL_WORKSPACE_SOURCE.csv'), ...
            {'Property','StoredText_NOT_Executed'}, ...
            {'DataSource',objectText(ws,'DataSource'); ...
             'FileName',objectText(ws,'FileName'); ...
             'MATLABCode',objectText(ws,'MATLABCode')});
    catch ME
        issues(end+1,:)={'REVIEW','WORKSPACE_SOURCE',model,ME.message};
    end

    %% 2. 全模型普通信号索引；不跟随或刷新库链接。
    phase='BLOCK_INDEX';
    logLine(logFile,'读取模块与普通信号索引；库内部不强制加载。');
    try
        H=find_system(model,'FindAll','on','LookUnderMasks','all', ...
            'FollowLinks','off','MatchFilter',@Simulink.match.allVariants,'Type','Block');
        result.variantSearch='ALL_VARIANTS_FILTER';
    catch ME
        issues(end+1,:)={'REVIEW','VARIANT_ENUMERATION',model,ME.message};
        H=find_system(model,'FindAll','on','LookUnderMasks','all', ...
            'FollowLinks','off','Type','Block');
        result.variantSearch='DEFAULT_VARIANTS_FALLBACK_REVIEW_REQUIRED';
    end
    H=unique(H(:),'stable'); N=numel(H);
    P=cell(N,1); types=cell(N,1); selected=false(N,1);
    nodes=cell(N,8); props=cell(N,1);
    for k=1:N
        P{k}=getfullname(H(k)); types{k}=get_param(H(k),'BlockType');
        selected(k)=inScopes(P{k},model,C.scopes);
        props{k}=get_param(H(k),'ObjectParameters');
        nodes(k,:)={P{k},types{k},safeText(H(k),'Name'), ...
            safeText(H(k),'Parent'),safeText(H(k),'StaticLinkStatus'), ...
            safeText(H(k),'ReferenceBlock'),safeText(H(k),'MaskType'),selected(k)};
    end
    writeCsv(fullfile(outDir,'02_ALL_BLOCKS.csv'), ...
        {'Path','Type','Name','Parent','StaticLinkStatus','ReferenceBlock','MaskType','InDetailedScope'},nodes);
    result.counts=struct('visibleBlocks',N,'scopedBlocks',sum(selected));
    pathIndex=containers.Map(P,num2cell(1:N));
    present=cell(numel(C.critical),5);
    for k=1:numel(C.critical)
        a=C.critical(k); p=fullPath(model,a.path);
        state='MISSING'; typ='';
        if isKey(pathIndex,p),typ=types{pathIndex(p)};state='FOUND';end
        if strcmp(state,'MISSING')
            issues(end+1,:)={'BLOCKER','CRITICAL_PATH',p,'当前已加载结构中未找到；未选相似名称代替。'}; %#ok<AGROW>
        end
        present(k,:)={a.id,a.label,p,typ,state};
    end
    writeCsv(fullfile(outDir,'02_CRITICAL_SCOPE.csv'), ...
        {'ID','ChineseRole','Path','LoadedType','ReadStatus'},present);

    %% 3. 按目标输入端遍历，完整保留分支；单列物理端口，不按单向信号猜。
    phase='EDGES';
    portRows=cell(0,7); physical=cell(0,5);
    targetFields={'Inport','Enable','Trigger','Reset','Ifaction'};
    for k=1:N
        try
            ph=get_param(H(k),'PortHandles');
            for jf=1:numel(targetFields)
                f=targetFields{jf};
                if ~isfield(ph,f),continue;end
                arr=ph.(f);
                for n=1:numel(arr)
                    [sp,sk,sn,ok,msg,lh]=sourcePort(arr(n));
                    dk=kindName(f); st='CONNECTED';if ~ok,st='UNRESOLVED_OR_UNCONNECTED';end
                    portRows(end+1,:)={P{k},dk,n,sp,sk,sn,st}; %#ok<AGROW>
                    if ok
                        edges(end+1,:)={sp,sk,sn,P{k},dk,n,safeText(lh,'Name'),selected(k),'DIRECT'}; %#ok<AGROW>
                    elseif selected(k) && ~isempty(msg)
                        % 无线端不直接判故障，可能是未使用或库/函数内部接口。
                        checks(end+1,:)={'PORT_READ',P{k},sprintf('%s:%d',dk,n),msg}; %#ok<AGROW>
                    end
                end
            end
            for f={'LConn','RConn'}
                if ~isfield(ph,f{1}),continue;end
                q=ph.(f{1});
                for n=1:numel(q)
                    physical(end+1,:)={P{k},f{1},n,safeText(q(n),'Line'),'PHYSICAL_NO_DIRECTION_INFERRED'}; %#ok<AGROW>
                end
            end
        catch ME
            issues(end+1,:)={'REVIEW','PORT_ENUMERATION',P{k},ME.message}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'03_DIRECT_EDGES.csv'), ...
        {'Source','SourceKind','SourcePort','Destination','DestinationKind','DestinationPort','SignalName','DestInScope','EdgeKind'},edges);
    writeCsv(fullfile(outDir,'03_INPUT_PORTS.csv'), ...
        {'Destination','Kind','Index','Source','SourceKind','SourcePort','Status'},portRows);
    writeCsv(fullfile(outDir,'03_PHYSICAL_PORT_INVENTORY.csv'), ...
        {'Block','Kind','Index','LineHandleSnapshot','Meaning'},physical);

    %% 4. 原生From/Goto（标签接收/发送）解析；歧义保留，不猜第一个。
    phase='TAGS';
    tagRows=cell(0,6); scopesRows=cell(0,4); tagMap=containers.Map('KeyType','char','ValueType','char');
    gotoIDs=find(strcmp(types,'Goto')); gotoTags=cell(numel(gotoIDs),1);
    for k=1:numel(gotoIDs),gotoTags{k}=safeText(H(gotoIDs(k)),'GotoTag');end
    for k=1:N
        if strcmp(types{k},'Goto') || strcmp(types{k},'GotoTagVisibility')
            scopesRows(end+1,:)={P{k},types{k},safeText(H(k),'GotoTag'),safeText(H(k),'TagVisibility')}; %#ok<AGROW>
        elseif strcmp(types{k},'From')
            tag=safeText(H(k),'GotoTag');[gp,ok,msg]=nativeGoto(H(k));
            cand=P(gotoIDs(strcmp(gotoTags,tag)));
            st='UNRESOLVED';
            if ok
                st='NATIVE_RESOLVED';tagMap(P{k})=gp;
            elseif selected(k)
                issues(end+1,:)={'REVIEW','FROM_GOTO',P{k},msg}; %#ok<AGROW>
            end
            tagRows(end+1,:)={P{k},tag,gp,st,strjoin(cand,' | '),msg}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'04_NATIVE_FROM_GOTO.csv'), ...
        {'From','Tag','NativeGoto','Status','AllSameTagCandidates_NOT_Selected','Detail'},tagRows);
    writeCsv(fullfile(outDir,'04_GOTO_VISIBILITY.csv'), ...
        {'Path','Type','Tag','Visibility'},scopesRows);

    %% 5. 读取完整函数源码及输入输出字段，不只截取某个if分支。
    phase='FUNCTIONS';
    logLine(logFile,'导出完整函数、状态字段、分支上下文和输入输出。');
    allCharts=[];
    try
        rt=sfroot; allCharts=rt.find('-isa','Stateflow.EMChart');
    catch ME
        issues(end+1,:)={'BLOCKER','FUNCTION_API',model,ME.message};
    end
    chartPaths={}; chartIDs=[];
    for k=1:numel(allCharts)
        try
            cp=char(allCharts(k).Path);
            if startsWith(cp,[model '/']),chartPaths{end+1}=cp;chartIDs(end+1)=k;end %#ok<AGROW>
        catch ME
            issues(end+1,:)={'REVIEW','FUNCTION_PATH',num2str(k),ME.message}; %#ok<AGROW>
        end
    end
    functionIO=cell(0,7); excerpts=cell(0,5); sourceTexts=containers.Map('KeyType','char','ValueType','char');
    patterns=questionPatterns();
    for k=1:numel(chartPaths)
        cp=chartPaths{k};
        if sum(strcmp(chartPaths,cp))~=1
            issues(end+1,:)={'BLOCKER','FUNCTION_MULTIPLE',cp,'函数对象路径不唯一，未选择其中一个。'}; %#ok<AGROW>
            continue;
        end
        try
            ch=allCharts(chartIDs(k));txt=normalizeText(char(ch.Script));
            f=sprintf('F%03d_SOURCE.m.txt',k);nf=sprintf('F%03d_NUMBERED.txt',k);
            writeText(fullfile(outDir,f),txt);writeNumbered(fullfile(outDir,nf),txt);
            hash=shaBytes(unicode2native(txt,'UTF-8'));old='NOT_IN_REFERENCE';
            for j=1:numel(C.functions)
                if strcmp(cp,fullPath(model,C.functions(j).path)),old=C.functions(j).sha256_normalized;break;end
            end
            st='SOURCE_DIFF_OR_NEW';if strcmp(old,hash),st='SAME_NORMALIZED_SOURCE';end
            chartRows(end+1,:)={cp,old,hash,st,f}; %#ok<AGROW>
            sourceTexts(cp)=txt;
            L=regexp(txt,'\n','split');
            for g=1:size(patterns,1)
                ix=find(~cellfun(@isempty,regexp(L,patterns{g,2},'once')));
                for j=reshape(ix,1,[])
                    a=max(1,j-2);b=min(numel(L),j+3);
                    excerpts(end+1,:)={patterns{g,1},cp,j,L{j},strjoin(L(a:b),sprintf('\n'))}; %#ok<AGROW>
                end
            end
            % 所有数据声明也导出；接口序号以软件对象为准，不猜向量分量名称。
            ds=ch.find('-isa','Stateflow.Data');
            for j=1:numel(ds)
                functionIO(end+1,:)={cp,objectText(ds(j),'Name'),objectText(ds(j),'Scope'), ...
                    objectText(ds(j),'Port'),objectText(ds(j),'DataType'), ...
                    objectNestedText(ds(j),'Props','Array','Size'), ...
                    objectNestedText(ds(j),'Props','InitialValue','')}; %#ok<AGROW>
            end
        catch ME
            issues(end+1,:)={'BLOCKER','FUNCTION_EXPORT',cp,ME.message}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'05_FUNCTION_INDEX.csv'), ...
        {'Path','ReferenceHash','LoadedHash','Comparison','FullSourceFile'},chartRows);
    writeCsv(fullfile(outDir,'05_FUNCTION_DATA_DECLARATIONS.csv'), ...
        {'Path','DataName','Scope','Port','DataType','DeclaredSize','InitialValue'},functionIO);
    writeCsv(fullfile(outDir,'05_BRANCH_CONTEXTS.csv'), ...
        {'Topic','Path','Line','MatchedLine','SurroundingSource_NOT_An_Execution_Result'},excerpts);
    for k=1:numel(C.functions)
        cp=fullPath(model,C.functions(k).path);
        if inScopes(cp,model,C.scopes) && ~isKey(sourceTexts,cp)
            issues(end+1,:)={'REVIEW','EXPECTED_SOURCE_NOT_EXPORTED',cp,'请检查原生对象或链接/变体边界；不使用旧源码代替。'}; %#ok<AGROW>
        end
    end

    %% 6. 全部相关参数、初值、持续时间、限幅、变化率和回调原文。
    phase='PARAMETERS';
    logLine(logFile,'读取恢复、接管、频率二次、电压q-bias、能力限制、ESS1余量与记录参数。');
    paramRows=cell(0,5); stateRows=cell(0,6); boundaries=cell(0,5);
    baseFields=parameterNames();
    for k=1:N
        bt=types{k};nm=safeText(H(k),'Name');
        must=selected(k) || ~isempty(regexp(nm,'^(CFG|AA15_P_)','once'));
        if ~must,continue;end
        ps=props{k};names=baseFields;
        [dp,ok,~]=readParam(H(k),'DialogParameters');
        if ok && isstruct(dp),names=[names;fieldnames(dp)];end %#ok<AGROW>
        [mn,ok,~]=readParam(H(k),'MaskNames');
        if ok,names=[names;reshape(asCells(mn),[],1)];end %#ok<AGROW>
        names=unique(names,'stable');
        maskNames={};if ok,maskNames=asCells(mn);end
        for j=1:numel(names)
            n=char(names{j});
            if ~isfield(ps,n) && ~any(strcmp(n,maskNames)),continue;end
            [v,good,msg]=readParam(H(k),n);
            if good
                paramRows(end+1,:)={P{k},bt,n,valueText(v),'RAW_READ_NO_EVALUATION'}; %#ok<AGROW>
            else
                paramRows(end+1,:)={P{k},bt,n,msg,'UNRESOLVED'}; %#ok<AGROW>
                issues(end+1,:)={'REVIEW','PARAM_READ',P{k},[n ': ' msg]}; %#ok<AGROW>
            end
        end
        if ~isempty(regexp(bt,'Delay|Memory|Integrator|RateLimiter|StateSpace|TransferFcn','once'))
            stateRows(end+1,:)={P{k},bt,safeText(H(k),'InitialCondition'), ...
                safeText(H(k),'SampleTime'),safeText(H(k),'ExternalReset'), ...
                safeText(H(k),'InitialConditionSource')}; %#ok<AGROW>
        end
        link=safeText(H(k),'StaticLinkStatus');mask=safeText(H(k),'MaskType');
        if any(strcmp(bt,{'S-Function','ModelReference','Reference'})) || ~any(strcmp(link,{'none','UNKNOWN',''}))
            boundaries(end+1,:)={P{k},bt,link,mask, ...
                'STATIC_BOUNDARY_ONLY_NO_LIBRARY_REFRESH_NO_MODEL_LOAD'}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'06_PARAMETERS.csv'), ...
        {'Path','BlockType','Parameter','RawExpressionOrStoredValue','ReadMode'},paramRows);
    writeCsv(fullfile(outDir,'06_STATES_AND_INITIALIZATION.csv'), ...
        {'Path','Type','InitialCondition','SampleTime','ExternalReset','InitialConditionSource'},stateRows);
    writeCsv(fullfile(outDir,'06_LIBRARY_AND_OPAQUE_BOUNDARIES.csv'), ...
        {'Path','Type','StaticLinkStatus','MaskType','ScopeLimit'},boundaries);

    %% 7. 比较上传源中涉及的普通连线；新模型不因哈希不同停止读取。
    phase='SAVED_EDGE_COMPARISON';
    eMap=containers.Map('KeyType','char','ValueType','double');
    for k=1:size(edges,1)
        key=portKey(edges{k,4},edges{k,5},edges{k,6});
        if isKey(eMap,key),eMap(key)=-1;else,eMap(key)=k;end
    end
    cmp=cell(numel(C.links),9);
    for k=1:numel(C.links)
        x=C.links(k);dst=fullPath(model,x.destination);src=fullPath(model,x.source);
        key=portKey(dst,kindName(x.destination_kind),x.destination_port);
        actual='';ap=NaN;ak='';st='NOT_RESOLVED_IN_READOUT';
        if isKey(eMap,key) && eMap(key)>0
            j=eMap(key);actual=edges{j,1};ak=edges{j,2};ap=edges{j,3};
            st='DIFFERENT';
            if strcmp(actual,src) && strcmp(ak,kindName(x.source_kind)) && ap==x.source_port,st='MATCH';end
        end
        cmp(k,:)={dst,x.destination_kind,x.destination_port,src,x.source_port,actual,ak,ap,st};
    end
    writeCsv(fullfile(outDir,'07_SAVED_EDGE_COMPARISON.csv'), ...
        {'Destination','Kind','Port','ReferenceSource','ReferencePort','LoadedSource','LoadedSourceKind','LoadedPort','Status'},cmp);
    result.counts.referenceEdges=numel(C.links);
    result.counts.edgeMatches=sum(strcmp(cmp(:,9),'MATCH'));
    result.counts.edgeDifferences=sum(strcmp(cmp(:,9),'DIFFERENT'));
    result.counts.edgeUnresolved=sum(strcmp(cmp(:,9),'NOT_RESOLVED_IN_READOUT'));
    if result.counts.edgeDifferences>0 || result.counts.edgeUnresolved>0
        issues(end+1,:)={'REVIEW','SAVED_EDGE_COMPARISON','07_SAVED_EDGE_COMPARISON.csv', ...
            '连线差异/未解析已逐条导出；可能含不跟随的库内部，不自动判模型错误。'};
    end

    %% 8. 所有子系统的端口语义，以及关键输入的实际上游。
    phase='INTERFACES_AND_TRACES';
    ifRows=cell(0,7);traceRows=cell(0,8);traceIndex=cell(0,5);
    for k=1:N
        if selected(k) && any(strcmp(types{k},{'Inport','Outport','EnablePort','TriggerPort','ResetPort','ActionPort'}))
            ifRows(end+1,:)={safeText(H(k),'Parent'),types{k},safeText(H(k),'Port'), ...
                safeText(H(k),'Name'),P{k},safeText(H(k),'PortDimensions'),safeText(H(k),'OutDataTypeStr')}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'08_SUBSYSTEM_PORT_NAMES.csv'), ...
        {'Parent','Direction','Port','Name','Path','DeclaredDimensions','DeclaredDataType'},ifRows);
    for k=1:numel(C.critical)
        a=C.critical(k);p=fullPath(model,a.path);
        if ~isKey(pathIndex,p),continue;end
        ph=get_param(p,'PortHandles');
        for n=1:numel(ph.Inport)
            [rr,ok,msg]=traceInput(p,n,model,tagMap);
            traceRows=[traceRows;rr]; %#ok<AGROW>
            traceIndex(end+1,:)={a.id,p,n,ok,msg}; %#ok<AGROW>
            if ~ok,issues(end+1,:)={'REVIEW','CRITICAL_INPUT_TRACE',p,sprintf('输入%d：%s',n,msg)};end %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'08_CRITICAL_INPUT_TRACES.csv'), ...
        {'Destination','Input','Depth','SourcePath','SourcePort','SourceKind','Type','ActionOrBoundary'},traceRows);
    writeCsv(fullfile(outDir,'08_TRACE_COMPLETENESS.csv'), ...
        {'Anchor','Destination','Input','ReachedExplicitBoundary','Detail'},traceIndex);
    % 输出消费者直接来自全图的逐输入扫描，因此不会漏掉输出分叉。
    fan=cell(0,8);
    for k=1:numel(C.critical)
        p=fullPath(model,C.critical(k).path);
        ix=find(strcmp(edges(:,1),p));
        for j=reshape(ix,1,[])
            fan(end+1,:)={C.critical(k).id,p,edges{j,2},edges{j,3},edges{j,4},edges{j,5},edges{j,6},edges{j,7}}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'08_CRITICAL_OUTPUT_CONSUMERS.csv'), ...
        {'Anchor','Source','Kind','Port','Destination','DestKind','DestPort','SignalName'},fan);

    %% 9. 记录与通信：读取全部设置及数据端上游布局，不猜旧通道编号。
    phase='RECORDERS_AND_COMMUNICATION';
    rec=cell(0,5);recCount=zeros(1,3);groupList=[27 29 30];
    assembly=cell(0,9);comm=cell(0,5);
    for k=1:N
        if ~selected(k),continue;end
        hay=lower(strjoin({safeText(H(k),'ReferenceBlock'),safeText(H(k),'SourceBlock'),safeText(H(k),'MaskType')},' '));
        if contains(hay,'opcomm') || strcmp(types{k},'ModelReference')
            comm(end+1,:)={P{k},types{k},safeText(H(k),'ReferenceBlock'), ...
                safeText(H(k),'MaskValues'),'BOUNDARY_EXPORTED_NOT_EXECUTED'}; %#ok<AGROW>
        end
        if ~contains(hay,'opwritefile'),continue;end
        ng=str2double(safeText(H(k),'Acq_Group'));
        if ~ismember(ng,groupList),continue;end
        gix=find(groupList==ng);recCount(gix)=recCount(gix)+1;
        pr=paramRows(strcmp(paramRows(:,1),P{k}),:);
        for j=1:size(pr,1),rec(end+1,:)={ng,P{k},pr{j,3},pr{j,4},pr{j,5}};end %#ok<AGROW>
        ph=get_param(H(k),'PortHandles');
        for n=1:numel(ph.Inport)
            [rr,ok,msg]=traceInput(P{k},n,model,tagMap);
            for j=1:size(rr,1)
                assembly(end+1,:)={ng,P{k},n,rr{j,3},rr{j,4},rr{j,5},rr{j,6},rr{j,7},rr{j,8}}; %#ok<AGROW>
            end
            if ok && ~isempty(rr)
                last=rr{end,4};
                % 展开拼接层；向量函数边界留出完整源码和声明，不擅自平铺。
                [more,notes]=recordAssembly(last,ng,P{k},n,model,tagMap,0,{});
                assembly=[assembly;more]; %#ok<AGROW>
                if ~isempty(notes),checks(end+1,:)={'RECORDER_LAYOUT',P{k},num2str(n),notes};end %#ok<AGROW>
            else
                issues(end+1,:)={'REVIEW','RECORDER_TRACE',P{k},msg}; %#ok<AGROW>
            end
        end
    end
    for k=1:numel(groupList)
        if recCount(k)~=1
            issues(end+1,:)={'REVIEW','RECORDER_COUNT',num2str(groupList(k)),sprintf('当前读到%d个记录器，未按名称猜选。',recCount(k))}; %#ok<AGROW>
        end
    end
    writeCsv(fullfile(outDir,'09_RECORDER_SETTINGS.csv'), ...
        {'Group','Writer','Parameter','Value','Mode'},rec);
    writeCsv(fullfile(outDir,'09_RECORDER_INPUT_ASSEMBLY.csv'), ...
        {'Group','Writer','WriterInput','Depth','Source','SourcePort','SourceKind','Type','LayoutOrBoundary'},assembly);
    writeCsv(fullfile(outDir,'09_COMMUNICATION_BOUNDARIES.csv'), ...
        {'Path','Type','Reference','RawMaskValues','ReadScope'},comm);

    %% 10. 完全恢复定向关键词库存：不凭相似名称做连接判断，只帮助人工快速定位现有能力。
    phase='TARGETED_PATTERN_INVENTORY';
    topicDefs={ ...
        'S14_STATES','S14|BLACK|RESTORE|HANDOVER|BETA|OWNER|PICKUP|SUBSTATE'; ...
        'P_F_SECONDARY','SECONDARY|PSEC|SEC_ENABLE|SECENTRY|SEC_ENTRY|SEC_SLEW|KI_SEC|MASTER_F|FREQUENCY'; ...
        'V_Q_QBIAS','QBIAS|QSEC|IQSEC|CAP_POS|CAPPOS|CAP_NEG|CAPNEG|VTARGET|VERR|VOLTAGE'; ...
        'ESS1_RESERVE','ESS1|GFM|MODHEAD|MODULATION|MODINDEX|RAWMOD|CURRENTLIMIT|P_MEAS|PMEAS|Q_MEAS|QMEAS|HEADROOM|RESERVE'; ...
        'ESS2_CAPABILITY','ESS2|SOC2|PMIN3|PMAX3|AUTH|AUTHORITY|CAPABILITY|HEADROOM'; ...
        'LOG_COMM','G27|G29|G30|OPWRITE|OPCOMM|MUX|DEMUX|FILEID'; ...
        'LEGACY_Q','QREF|QBASE|QAUT|VSEC|VSUPPORT|SLOW_Q|LF_Q|DAMP_Q'; ...
        'NORMAL_RESP','BASELINE|PBASE|PB3|NORMAL|DISPATCH|RESPONSIBILITY|AVAILABLE' ...
        };
    patRows=cell(0,7);
    for k=1:N
        hay=strjoin({P{k},safeText(H(k),'Name'),types{k},safeText(H(k),'MaskType'), ...
            safeText(H(k),'ReferenceBlock'),safeText(H(k),'GotoTag')},' | ');
        for t=1:size(topicDefs,1)
            if ~isempty(regexpi(hay,topicDefs{t,2},'once'))
                patRows(end+1,:)={topicDefs{t,1},P{k},types{k},safeText(H(k),'Name'), ...
                    safeText(H(k),'MaskType'),safeText(H(k),'ReferenceBlock'),safeText(H(k),'GotoTag')}; %#ok<AGROW>
            end
        end
    end
    writeCsv(fullfile(outDir,'10_TARGETED_PATTERN_INVENTORY.csv'), ...
        {'Topic','Path','BlockType','Name','MaskType','ReferenceBlock','GotoTag'},patRows);

    %% 11. 汇总改模决策必须回答的问题；只有证据定位，没有臆造答案。
    phase='DECISION_COVERAGE';
    qrows=cell(numel(C.questions),5);
    for k=1:numel(C.questions)
        q=C.questions(k);anc=asCells(q.anchors);miss={};
        for j=1:numel(anc)
            ids=find(strcmp({C.critical.id},char(anc{j})));
            if numel(ids)~=1 || ~isKey(pathIndex,fullPath(model,C.critical(ids(1)).path))
                miss{end+1}=char(anc{j}); %#ok<AGROW>
            end
        end
        st='RAW_EVIDENCE_EXPORTED_ENGINEERING_REVIEW_REQUIRED';
        if ~isempty(miss),st='MISSING_ANCHOR';end
        qrows(k,:)={q.id,q.question,strjoin(anc,' | '),st,strjoin(miss,' | ')};
    end
    writeCsv(fullfile(outDir,'11_DESIGN_QUESTIONS.csv'), ...
        {'QuestionID','QuestionChinese','AnchorIDs','EvidenceScope','MissingAnchors'},qrows);
    result.counts.directEdges=size(edges,1);result.counts.exportedFunctions=size(chartRows,1);
    result.counts.parameters=size(paramRows,1);result.counts.nativeTags=size(tagRows,1);
    result.counts.criticalInputs=size(traceIndex,1);result.counts.recorderGroups=recCount;
    result.lastCompletedPhase=phase;
catch ME
    issues(end+1,:)={'BLOCKER','AUDIT_EXECUTION',phase, ...
        getReport(ME,'extended','hyperlinks','off')};
    result.fatalError=ME.message;
    logLine(logFile,['审计工具在' phase '阶段遇到异常；保留已导出证据，不改动模型。']);
end

%% 12. 检查只读性；无论是否存在读取缺口，尽量完成结果归档。
try
    result.sourceHashAfter=shaFile(modelFile);
    result.dirtyBefore=dirtyBefore;
    result.dirtyAfter=get_param(model,'Dirty');
    result.hostSimulationStatusAfter=get_param(model,'SimulationStatus');
    result.sourceUnchanged=strcmp(sourceBefore,result.sourceHashAfter);
    result.dirtyUnchanged=strcmp(dirtyBefore,result.dirtyAfter);
    if ~result.sourceUnchanged || ~result.dirtyUnchanged
        issues(end+1,:)={'BLOCKER','READ_ONLY_IDENTITY',modelFile, ...
            '前后源文件或未保存标志有变化；审计未执行写模型操作，请核查并行操作。'};
    end
catch ME
    issues(end+1,:)={'BLOCKER','READ_ONLY_CHECK',modelFile,ME.message};
end
result.finished=datestr(now,31);
result.issueCounts=struct('blocker',sum(strcmp(issues(:,1),'BLOCKER')), ...
    'review',sum(strcmp(issues(:,1),'REVIEW')),'info',sum(strcmp(issues(:,1),'INFO')));
if result.issueCounts.blocker>0
    result.status='READOUT_PARTIAL_REVIEW_BLOCKERS';
elseif result.issueCounts.review>0
    result.status='READOUT_COMPLETE_WITH_REVIEW_ITEMS';
else
    result.status='READOUT_COMPLETE_ENGINEERING_REVIEW_REQUIRED';
end
result.scopeLimitations={ ...
    '读取的是主机模型结构与保存参数，不是实时目标机当前信号。'; ...
    '没有编译/更新，因此不声称获得全部编译维度、活动分支或实时执行顺序。'; ...
    '库、S函数、受保护初始化文件、模型引用保留为显式边界，不逆向、不执行。'; ...
    '数值阈值和健康判据有效性仍须用已有数据与后续分段试验验证。'; ...
    '输出状态表示工具读取情况，不是电气通过，也不是无遗漏保证。'};
result.archive=[outDir '.zip'];
writeCsv(fullfile(outDir,'12_ISSUES.csv'), ...
    {'Severity','Category','ItemOrPath','Detail'},issues);
writeCsv(fullfile(outDir,'12_BOUNDARY_NOTES.csv'), ...
    {'Category','ItemOrPath','PortOrKey','Detail'},checks);
writeJson(fullfile(outDir,'RESULT.json'),result);
summary=summaryText(result);
writeText(fullfile(outDir,'00_README.md'),summary);
logLine(logFile,['读取状态：' result.status '；此状态不表示电气验收通过。']);
try
    listing=dir(outDir);listing=listing(~[listing.isdir]);
    fileNames={listing.name};
    zip(result.archive,fileNames,outDir);
catch ME
    result.archive='';result.archiveError=ME.message;
    writeJson(fullfile(outDir,'RESULT.json'),result);
end
fprintf('\n%s\n',summary);
fprintf('结果目录：%s\n',outDir);
if ~isempty(result.archive)
    fprintf('请上传结果压缩包：%s\n',result.archive);
else
    fprintf('压缩失败但读取文件已保留；上传结果目录，不需要重跑物理试验。\n');
end
end

%% ======================= 只读与输出辅助函数 =======================
function rows=parameterNames()
rows={'Value';'Gain';'SampleTime';'InitialCondition';'InitialConditionSource'; ...
    'InitialConditionSetting';'ExternalReset';'ShowStatePort';'LimitOutput'; ...
    'UpperSaturationLimit';'LowerSaturationLimit';'IntegratorMethod'; ...
    'UpperLimit';'LowerLimit';'RisingSlewLimit';'FallingSlewLimit'; ...
    'InitialOutput';'Criteria';'Threshold';'Inputs';'Outputs';'Port'; ...
    'PortDimensions';'OutDataTypeStr';'OutputDimensions';'InputSignalNames'; ...
    'OutputSignalNames';'OutputSignals';'InputSignals';'IndexMode'; ...
    'IndexOptions';'Indices';'InputPortWidth';'NumberOfDimensions'; ...
    'DataPortOrder';'Numerator';'Denominator';'A';'B';'C';'D'; ...
    'MaskType';'MaskNames';'MaskValues';'MaskInitialization'; ...
    'InitFcn';'StartFcn';'StopFcn';'LoadFcn';'OpenFcn';'CopyFcn';'DeleteFcn'; ...
    'MaskSelfModifiable';'StaticLinkStatus';'ReferenceBlock';'SourceBlock'; ...
    'FunctionName';'Parameters';'ModelName';'GotoTag';'TagVisibility'; ...
    'DataStoreName';'DataStoreElements';'Commented';'TreatAsAtomicUnit'; ...
    'SystemSampleTime';'PermitHierarchicalResolution';'SFBlockType'; ...
    'Acq_Group';'Decimation';'Nb_Samples';'Nb_Signals';'MaxFiles';'Max_Size'; ...
    'File_Size';'FileSize';'Filename';'FileName';'FileID';'Static'; ...
    'VariableName';'RT_Path';'NRT_Path';'Before';'After';'Time'; ...
    'SwitchTimes';'External';'InitialState';'Measurements';'Ron';'Rs';'Cs'};
end
function p=questionPatterns()
p={ ...
'HEALTH_TASK','pickupOK|pickupSevere|zeroStableOK|postOK|prefApplied|prefEff|targetTol|pickupTarget'; ...
'STATE_TIMING','black_substate|state\s*==\s*[45679]|state\s*=\s*[45679]|Dwell|TIMEOUT|timer|Count|abortOpen'; ...
'HANDOVER','beta|owner|handover|pb3n|pb3=|corr<=|available|auth3|Pfinal'; ...
'CONTROL_GATES','baseOnly|base_diag|ess2GFLStage|coordStage|secondaryEnable|correctionEnable|s14Active|requestOn'; ...
'Q_PATH','qref|qmeas|qhold|qbase|qsec|qbias|supd|supq|slowq|lfq'; ...
'CURRENT_SAFETY','iref_used|imeas_used|headroom|currentLimit|limit|valid|failCode|fail_code'; ...
'SCHEDULE_CAPABILITY','lp3|pmin3|pmax3|soc2|dp_primary|psecn|kpf|ki_sec|master_f|dispatch'; ...
'ESS1_STATE','Fout|Vout|GridOn|Droop|Fref|Vref|iout|vC|vdc|Vdc|ModIndex|modulation'};
end
function [v,ok,msg]=readParam(p,n)
v=[];ok=false;msg='';
try,v=get_param(p,n);ok=true;catch ME,msg=ME.message;end
end
function s=safeText(p,n)
[v,ok,~]=readParam(p,n);if ok,s=valueText(v);else,s='UNKNOWN';end
end
function s=objectText(o,n)
try,s=valueText(o.(n));catch,s='UNKNOWN';end
end
function s=objectNestedText(o,a,b,c)
try
    v=o.(a);v=v.(b);if ~isempty(c),v=v.(c);end
    s=valueText(v);
catch,s='UNKNOWN';end
end
function s=valueText(x)
if isnumeric(x)||islogical(x),s=mat2str(x,17);
elseif ischar(x),s=x;
elseif isstring(x),s=strjoin(cellstr(x(:)),' | ');
elseif iscell(x)
    a=cellfun(@valueText,x,'UniformOutput',false);s=strjoin(a(:),' | ');
elseif isa(x,'Simulink.Parameter')
    s=['Simulink.Parameter（参数对象） Value（值）=' valueText(x.Value)];
elseif isstruct(x)
    try,s=jsonencode(x);catch,s='STRUCT_SERIALIZATION_UNAVAILABLE';end
else,s=['UNREAD_OBJECT_CLASS:' class(x)];
end
end
function a=asCells(x)
if isempty(x),a={};elseif iscell(x),a=x;elseif isstring(x),a=cellstr(x); ...
elseif ischar(x),a={x};else,a={valueText(x)};end
end
function p=fullPath(model,r)
p=[model '/' char(r)];
end
function tf=inScopes(p,model,scopes)
tf=false;scopes=asCells(scopes);
for k=1:numel(scopes)
    root=fullPath(model,scopes{k});
    if strcmp(p,root)||startsWith(p,[root '/']),tf=true;return;end
end
end
function p=canonical(p)
try,p=char(java.io.File(char(p)).getCanonicalPath());catch,p=char(p);end
p=strrep(p,'\','/');
if ispc,p=lower(p);end
while numel(p)>1&&p(end)=='/',p(end)=[];end
end
function tf=pathWithin(a,b)
a=canonical(a);b=canonical(b);tf=strcmp(a,b)||startsWith(a,[b '/']);
end
function s=kindName(x)
s=lower(char(x));
switch s
    case 'inport',s='in';
    case 'outport',s='out';
    case {'ifaction','action'},s='ifaction';
end
end
function k=portKey(p,t,n)
k=sprintf('%s|%s|%g',p,kindName(t),n);
end
function [src,kind,n,ok,msg,lh]=sourcePort(ph)
src='';kind='';n=NaN;ok=false;msg='';lh=-1;
try
    lh=get_param(ph,'Line');
    if ~isscalar(lh)||lh<0,msg='未连接普通输入线或该端口不是普通信号。';return;end
    sh=get_param(lh,'SrcPortHandle');bh=get_param(lh,'SrcBlockHandle');
    hops=0;
    while (~isscalar(sh)||sh<0||~isscalar(bh)||bh<0) && hops<20
        parent=get_param(lh,'LineParent');
        if ~isscalar(parent)||parent<0,break;end
        lh=parent;sh=get_param(lh,'SrcPortHandle');bh=get_param(lh,'SrcBlockHandle');hops=hops+1;
    end
    if ~isscalar(sh)||sh<0||~isscalar(bh)||bh<0,msg='普通输入线未取得唯一源。';return;end
    src=getfullname(bh);kind=kindName(get_param(sh,'PortType'));n=get_param(sh,'PortNumber');
    if ~isnumeric(n),n=str2double(char(n));end
    if any(strcmp(kind,{'state','enable','trigger','reset','ifaction'})),n=1;end
    ok=isscalar(n)&&isfinite(n);
    if ~ok,msg='源端口编号未解析。';end
catch ME,msg=ME.message;end
end
function [b,n,kind,ok,msg]=sourceAt(dst,port)
b='';n=NaN;kind='';ok=false;msg='';
try
    ph=get_param(dst,'PortHandles');
    if port<1||port>numel(ph.Inport),msg='输入端口不存在';return;end
    [b,kind,n,ok,msg]=sourcePort(ph.Inport(port));
catch ME,msg=ME.message;end
end
function [p,ok,msg]=nativeGoto(from)
p='';ok=false;msg='';
try
    v=get_param(from,'GotoBlock');
    if isstruct(v)
        if numel(v)~=1,msg='原生标签结果不是唯一结构。';return;end
        if isfield(v,'handle'),h=v.handle;
        elseif isfield(v,'Handle'),h=v.Handle;
        elseif isfield(v,'name'),h=v.name;
        elseif isfield(v,'Name'),h=v.Name;
        else,msg='未知原生标签返回结构。';return;end
    else,h=v;end
    if iscell(h)
        if numel(h)~=1,msg='原生标签结果不是唯一对象。';return;end
        h=h{1};
    end
    if isempty(h),msg='原生标签结果为空。';return;end
    p=getfullname(h);
    if iscell(p)
        if numel(p)~=1,p='';msg='原生标签路径不唯一。';return;end
        p=p{1};
    end
    p=char(p);ok=strcmp(get_param(p,'BlockType'),'Goto');
    if ~ok,msg='解析结果不是Goto（标签发送）模块。';end
catch ME,msg=ME.message;end
end
function [rows,ok,msg]=traceInput(dst,port,model,tagMap)
rows=cell(0,8);ok=false;msg='';
[b,n,kind,good,detail]=sourceAt(dst,port);
if ~good,msg=detail;return;end
seen={};
for depth=0:95
    key=portKey(b,kind,n);
    if any(strcmp(key,seen)),msg='追踪遇到重复节点；反馈闭环不自动消去。';return;end
    seen{end+1}=key; %#ok<AGROW>
    try,bt=get_param(b,'BlockType');catch ME,msg=ME.message;return;end
    if ~strcmp(kind,'out')
        rows(end+1,:)={dst,port,depth,b,n,kind,bt,'STATE_OR_SPECIAL_OUTPUT_BOUNDARY'}; %#ok<AGROW>
        ok=true;msg='已到状态或特殊输出边界';return;
    elseif strcmp(bt,'From')
        gp='';good=isKey(tagMap,b);
        if good,gp=tagMap(b);detail='NATIVE_TAG_ROUTE';else,detail='UNRESOLVED_NATIVE_TAG';end
        rows(end+1,:)={dst,port,depth,b,n,kind,bt,[detail ' -> ' gp]}; %#ok<AGROW>
        if ~good,msg=detail;return;end
        [b,n,kind,good,detail]=sourceAt(gp,1);
    elseif strcmp(bt,'Inport')
        par=get_param(b,'Parent');pn=str2double(get_param(b,'Port'));
        rows(end+1,:)={dst,port,depth,b,n,kind,bt,'CROSS_PARENT_INPUT'}; %#ok<AGROW>
        if strcmp(par,model),ok=true;msg='根输入边界';return;end
        [b,n,kind,good,detail]=sourceAt(par,pn);
    elseif strcmp(bt,'SubSystem')
        if strcmp(safeText(b,'SFBlockType'),'MATLAB Function')
            rows(end+1,:)={dst,port,depth,b,n,kind,bt,'FUNCTION_BOUNDARY_FULL_SOURCE_EXPORTED'}; %#ok<AGROW>
            ok=true;msg='函数计算边界；其全部输入及源码另有表';return;
        end
        op=find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','off','BlockType','Outport');
        hit={};
        for j=1:numel(op)
            if str2double(get_param(op{j},'Port'))==n,hit{end+1}=op{j};end %#ok<AGROW>
        end
        rows(end+1,:)={dst,port,depth,b,n,kind,bt,'CROSS_SUBSYSTEM_OUTPUT'}; %#ok<AGROW>
        if numel(hit)~=1,msg='子系统输出未唯一解析；不刷新库链接。';return;end
        [b,n,kind,good,detail]=sourceAt(hit{1},1);
    else
        rows(end+1,:)={dst,port,depth,b,n,kind,bt,'COMPUTATION_STATE_OR_LIBRARY_BOUNDARY_NOT_SKIPPED'}; %#ok<AGROW>
        ok=true;msg='到达实际计算/状态/库边界；全图保留其输入';return;
    end
    if ~good,msg=detail;return;end
end
msg='达到有限追踪深度，未宣称路径已经全部解析。';
end
function [rows,note]=recordAssembly(block,group,writer,writerInput,model,tagMap,depth,seen)
rows=cell(0,9);note='';
if depth>=18||any(strcmp(block,seen)),note='记录拼接追踪达到深度或重复边界；需复核完整图。';return;end
seen{end+1}=block;
try
    bt=get_param(block,'BlockType');
    if ~any(strcmp(bt,{'Mux','VectorConcatenate','Concatenate','BusCreator','SignalConversion'}))
        % 不将函数输出或Demux分量未经尺寸证明就解释成连续MAT行。
        rows(end+1,:)={group,writer,writerInput,depth,block,NaN,'out',bt, ...
            ['LEAF_OR_VECTOR_BOUNDARY; Inputs=' safeText(block,'Inputs') '; Outputs=' safeText(block,'Outputs')]};
        return;
    end
    ph=get_param(block,'PortHandles');
    for j=1:numel(ph.Inport)
        [rr,ok,msg]=traceInput(block,j,model,tagMap);
        for k=1:size(rr,1)
            rows(end+1,:)={group,writer,writerInput,depth,rr{k,4},rr{k,5},rr{k,6},rr{k,7}, ...
                sprintf('assembly=%s/input%d ; %s',block,j,rr{k,8})}; %#ok<AGROW>
        end
        if ok&&~isempty(rr)
            [a,n]=recordAssembly(rr{end,4},group,writer,writerInput,model,tagMap,depth+1,seen);
            rows=[rows;a]; %#ok<AGROW>
            if ~isempty(n),note=[note ' ' n];end %#ok<AGROW>
        else,note=[note ' ' msg];end %#ok<AGROW>
    end
catch ME,note=ME.message;end
end
function s=normalizeText(s)
s=strrep(s,sprintf('\r\n'),sprintf('\n'));s=strrep(s,sprintf('\r'),sprintf('\n'));
if ~isempty(s)&&double(s(1))==65279,s=s(2:end);end
end
function h=shaFile(path)
f=fopen(path,'rb');if f<0,error('E2RH:Read','无法读取文件：%s',path);end
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
while true
    b=fread(f,1024*1024,'*uint8');if isempty(b),break;end
    md.update(typecast(b(:),'int8'));
end
r=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(r,2).',1,[]));
end
function h=shaBytes(b)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
md.update(typecast(uint8(b(:)),'int8'));r=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(r,2).',1,[]));
end
function writeText(path,s)
f=fopen(path,'w','n','UTF-8');if f<0,error('E2RH:Write','无法写入结果：%s',path);end
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',char(s));
end
function writeNumbered(path,txt)
L=regexp(txt,'\n','split');f=fopen(path,'w','n','UTF-8');
if f<0,error('E2RH:Write','无法写入源码行号文件。');end
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
for k=1:numel(L),fprintf(f,'%05d | %s\n',k,L{k});end
end
function writeJson(path,x)
writeText(path,jsonencode(x,'PrettyPrint',true));
end
function writeCsv(path,head,rows)
f=fopen(path,'w','n','UTF-8');if f<0,error('E2RH:Write','无法写入CSV（逗号分隔表）：%s',path);end
clean=onCleanup(@()fclose(f)); %#ok<NASGU>
writeRow(f,head);
for k=1:size(rows,1),writeRow(f,rows(k,:));end
end
function writeRow(f,row)
a=cell(1,numel(row));
for k=1:numel(row)
    s=valueText(row{k});s=strrep(s,'"','""');a{k}=['"' s '"'];
end
fprintf(f,'%s\n',strjoin(a,','));
end
function logLine(path,s)
f=fopen(path,'a','n','UTF-8');
if f>=0,fprintf(f,'[%s] %s\n',datestr(now,31),s);fclose(f);end
fprintf('%s\n',s);
end
function s=summaryText(r)
s=sprintf(['# 储能2恢复与接管只读审计结果\n\n' ...
    '读取状态：`%s`。这不是电气验收结果。\n\n' ...
    '模型：`%s`。\n\n' ...
    '读取阻断项：%d；需人工复核项：%d。\n\n' ...
    '本轮导出健康门控、任务来源、状态推进、两路命令混合、接管后一次二次、' ...
    '正常调度入口、储能1测量与能力、无功控制权和记录布局。\n\n' ...
    '先看 `10_DESIGN_QUESTIONS.csv`（待形成改模结论的问题）和 ' ...
    '`11_ISSUES.csv`（缺失与歧义），再对应函数全文、端口与参数表。\n\n' ...
    '保存参数不是目标机运行参数；源文件哈希不同不会阻止证据读取。' ...
    '库与通信边界、未编译尺寸和运行稳定性没有被自动推定。\n\n' ...
    '本脚本未加载、修改、保存、编译、运行模型或连接实时目标机。' ...
    '若工具报错，修工具并保留结果，不重跑已成功的电气试验。\n'], ...
    r.status,r.model,r.issueCounts.blocker,r.issueCounts.review);
end

function result = ANALYZE_K26_K50_COORDPATCH_FULL30_R3_DIRECTMAT(modelRoot)
% K26_K50_CLEAN_P1 两处坐标修复后的30秒计划孤岛计算器（直接读取当前OpREDHAWKtarget MAT）。
% 对应已实际运行成功的 RUN_K26_K50_COORDPATCH_FULL30_R5.py。
% 本版不要求Python先做RAW归档；直接读取当前Build四个OpREDHAWKtarget目录中的五组MAT。
% MATLAB R2023b；只读运行证据，不连接RT-LAB、不修改模型。
%
% 重点回答：
%   1) J1真实开断后0~30s是否仍出现“早期波动→暂静→后期再振荡”；
%   2) 15~20 / 20~25 / 25~30s尾段电压、ESS1频率、P/Q、执行与限幅如何演化；
%   3) 历史约0.3~0.6Hz低频现象在当前坐标修复后是否仍有明显能量；
%   4) 五台GFL的请求/实际参考/实测响应和ESS1执行压力是否先于系统恶化。
%
% 证据原则：
%   - 直接读取当前Build的五组OpWrite MAT；每个源文件现场计算SHA256；
%   - 只接受精确任务target目录和精确变量名/当前行宽；不从备份、旧分析目录或任意MAT猜数据；
%   - 所有MAT segments先审计，再按Target Time合并；同时间不同数据直接拒绝；
%   - 缺样不补零；不以插值制造事件；频谱峰值不冒充特征值/模态；
%   - 过渡、尾段、数据完整性和执行约束分开；不自动宣布永久稳定或电气PASS。
%
% 用法：
%   result = ANALYZE_K26_K50_COORDPATCH_FULL30_R2('本轮运行目录/manifest.json/ZIP');
%   result = ANALYZE_K26_K50_COORDPATCH_FULL30_R2('selftest');
% 无参数时可选择manifest.json或本轮ZIP。
% 2026-09-10；R2只增加R5运行身份硬门和运行成功证据说明，成熟计算管线不重写。

expectedKind = 'FULL30';
if nargin < 1, modelRoot = ''; end
C = k49_config();
% 用户当前工作流：不再要求先跑selftest；直接读取当前Build的MAT。
[source, cleanupSource] = k50_resolve_direct(modelRoot, expectedKind, C); %#ok<NASGU>
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
outDir = fullfile(source.outputAnchor,['K50_COORDPATCH_R5_DIRECTMAT_CALC_' expectedKind '_' stamp]);
if isfolder(outDir), outDir = [outDir '_' k49_nonce()]; end
mkdir(outDir);
result = struct('status','STARTED','outputDirectory',outDir);
try
    [R,D] = k49_analyze(source,expectedKind,C,outDir);
    referenceA = ''; %#ok<NASGU> % FULL30-only;保留成熟比较代码但本入口不进入
    if strcmp(expectedKind,'QBIAS0_30')
        if isempty(referenceA)
            guessed = k49_get(R.manifest,'baseline_reference','');
            if ischar(guessed) && isfolder(guessed) && isfile(fullfile(guessed,'manifest.json'))
                referenceA = guessed;
            end
        end
        [aSource, cleanupA] = k49_resolve(referenceA,'FULL30'); %#ok<NASGU>
        if isempty(aSource)
            R.comparison = struct('status','A_REFERENCE_NOT_SELECTED', ...
                'meaning','本轮B已计算；尚未选择A，不得解释为同条件因果对照。');
        else
            if strcmpi(aSource.root,source.root)
                error('K49:SameRun','A与B不能指向同一运行目录。');
            end
            aOut = fullfile(outDir,'A_REFERENCE'); mkdir(aOut);
            [RA,DA] = k49_analyze(aSource,'FULL30',C,aOut);
            R.comparison = k49_compare(RA,DA,R,D,C,outDir);
            clear DA;
        end
    end
    k49_write_summary(R,outDir,C);
    result = k49_small_result(R);
    result.status = 'CALCULATION_COMPLETE_NOT_ELECTRICAL_CERTIFICATION';
    result.outputDirectory = outDir;
    result.evidenceZip = [outDir '.zip'];
    k49_json_write(fullfile(outDir,'RESULT.json'),result);
    save(fullfile(outDir,'RESULT.mat'),'result','-v7');
    k49_pack(outDir,result.evidenceZip);
    fprintf('\n计算完成；没有自动宣布整次电气验收通过。\n结果目录：%s\n压缩文件：%s\n',outDir,result.evidenceZip);
catch ME
    try
        k49_text(fullfile(outDir,'ERROR.txt'),getReport(ME,'extended','hyperlinks','off'));
    catch
        k49_text(fullfile(outDir,'ERROR.txt'),ME.message);
    end
    fprintf(2,'\n计算停止，现有输出和原始记录均保留。MATLAB后处理错误不得触发重新做物理试验；先修计算脚本/输入。\n%s\n',ME.message);
    rethrow(ME);
end
end

function C = k49_config()
C.version = 'K26_K50_COORDPATCH_30S_ANALYSIS_R3_DIRECTMAT_20260910';
C.defaultModelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
    'yanshou_V7\models\K26_K50_CLEAN_P1'];
C.defaultRunBase = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
    'yanshou_V7\scripts\K50_COORDPATCH_R1'];
C.requiredRunnerVersion = 'K26_K50_COORDPATCH_FULL30_R5_20260910';
C.requiredExperimentKind = 'K26_K50_COORDPATCH_FULL30_R1';
C.horizon = 30;
C.step = 1e-4;
C.groups = {'G26','G27','G28','G29','G30'};
C.stems = {'rootdiag_ev12_data','rootdiag_ess2_data','rootdiag_pv12_data','d1_gfm_superpack_data','freqdiag_ess1_data'};
C.taskSuffix = {'ss_slave','ss_slave2','ss_slave3','sm_master','ss_slave2'};
C.rows = [97 49 97 47 129];
C.dt = [0.0004 0.0004 0.0004 0.0004 0.001];
C.nominalV = 10000;
C.isoTol = 1e-8; % 与运行脚本的零偏置观察容差一致，不是设备保护定值。
C.compareParamTol = 1e-8;
C.timeGridTol = 1e-7;
C.duplicateAbsTol = 1e-10;
C.coverageReference = 0.99; % 数据完整性提示，不是电气验收要求。
C.maxSmallGap = 0.010;
C.displayStep = 0.010;
C.earlyEnd = 0.70;
C.windows = [-.05 -.005;0 .02;.02 .1;.1 .3;.3 .7;.7 1;1 3;3 6;6 10;10 15;12 15;15 20;20 25;25 30;0 15;0 30];
C.windowNames = {'PRE','EDGE_20MS','EDGE_100MS','ENTRY_300MS','EARLY_700MS','EARLY_1S','W1_3','W3_6','W6_10','W10_15','W12_15','W15_20','W20_25','W25_30','FIRST15','FULL30'};
C.voltageBands = [.80 .85 .90 1.10 1.15 1.20];
C.episodeReferenceDuration = .1; % 历史诊断标记，仅描述，不作整次电气否决。
C.referenceVBand = [.90 1.10];
C.referenceFBand = [49.5 50.5];
C.referenceFWarning = [49 51];
C.vdcForIllustration = 1000;
C.acLineBaseForIllustration = 480;
C.earlyVRmsReference = .002; % 仅用于提醒两次早期是否足够接近，待人工确认。
C.earlyIRmsReference = .005;
C.earlyFRmsReference = .02;
C.makePlots = true;
C.selftestMode = false;
end

function [S,guard] = k50_resolve_direct(modelRoot,kind,C)
% 直接计算当前Build生成的MAT，不再依赖RAW归档作为前置条件。
guard = [];
if isempty(modelRoot), modelRoot = C.defaultModelRoot; end
modelRoot = char(modelRoot);
if exist(modelRoot,'dir') ~= 7
    error('K50:ModelRootMissing', ...
        ['当前模型根目录不存在：\n%s\n' ...
         '本脚本默认应指向 yanshou_V7\\models\\K26_K50_CLEAN_P1。'],modelRoot);
end
modelRoot = char(java.io.File(modelRoot).getCanonicalPath());
expectedSlx = fullfile(modelRoot,'K26_K50_CLEAN_P1.slx');
if ~isfile(expectedSlx)
    error('K50:ModelSLXMissing','模型根目录中没有 K26_K50_CLEAN_P1.slx：%s',expectedSlx);
end

runBase = C.defaultRunBase;
if exist(runBase,'dir') ~= 7
    error('K50:RunBaseMissing','找不到R5运行记录目录：%s',runBase);
end
runs = dir(fullfile(runBase,'FULL30_*','manifest.json'));
valid = struct('path',{},'folder',{},'datenum',{},'manifest',{});
for i=1:numel(runs)
    p=fullfile(runs(i).folder,runs(i).name);
    try
        J=k49_json_read(p);
        if strcmp(k49_get(J,'trial_kind',''),kind) && ...
           strcmp(k49_get(J,'version',''),C.requiredRunnerVersion) && ...
           strcmp(k49_get(J,'status',''),'CAPTURE_COMPLETE_NO_ELECTRICAL_VERDICT')
            q.path=p; q.folder=runs(i).folder; q.datenum=runs(i).datenum; q.manifest=J;
            valid(end+1)=q; %#ok<AGROW>
        end
    catch
    end
end
if isempty(valid)
    error('K50:NoSuccessfulR5', ...
        ['在 %s 下没有找到已完成的 R5 FULL30 manifest。\n' ...
         '物理试验不要重跑；先确认刚才成功运行目录仍在。'],runBase);
end
[~,ix]=max([valid.datenum]); sel=valid(ix);
M=sel.manifest;
manifestModel = k49_get(M,'modelFile','');
if ~isempty(manifestModel)
    try
        manifestModel=char(java.io.File(char(manifestModel)).getCanonicalPath());
    catch
        manifestModel=char(manifestModel);
    end
    expectedCanonical=char(java.io.File(expectedSlx).getCanonicalPath());
    if ~strcmpi(manifestModel,expectedCanonical)
        error('K50:ManifestModelMismatch', ...
            '最新成功R5清单对应的模型不是当前K26_K50_CLEAN_P1：%s',manifestModel);
    end
end
fprintf('\n[直接MAT模式]\n');
fprintf('  模型根目录：%s\n',modelRoot);
fprintf('  自动关联R5成功清单：%s\n',sel.path);
fprintf('  不要求raw_archive；下面直接读取current OpREDHAWKtarget MAT。\n');
S=struct('root',sel.folder,'manifestPath',sel.path,'originalInput',modelRoot, ...
    'outputAnchor',runBase,'modelRoot',modelRoot,'dataSource','DIRECT_CURRENT_OPREDHAWKTARGET');
end

function [S,guard] = k49_resolve(inputPath,kind)
S = []; guard = [];
if isempty(inputPath)
    [name,folder] = uigetfile({'*.json;*.zip','运行清单或压缩文件（JSON/ZIP）';'*.*','全部文件'}, ...
        ['选择 ' kind ' 对应试验的 manifest.json 或压缩文件']);
    if isequal(name,0), return; end
    inputPath = fullfile(folder,name);
end
inputPath = char(inputPath);
originalInput = inputPath;
if isfolder(inputPath)
    root = inputPath; anchor = fileparts(root);
    if isempty(anchor), anchor = pwd; end
elseif isfile(inputPath)
    [anchor,~,ext] = fileparts(inputPath);
    if isempty(anchor), anchor = pwd; end
    if strcmpi(ext,'.zip')
        k49_safe_zip(inputPath);
        root = tempname; mkdir(root);
        guard = onCleanup(@()k49_remove_temp(root));
        unzip(inputPath,root);
    elseif strcmpi(ext,'.json')
        J = k49_json_read(inputPath);
        if isfield(J,'manifest') && ~isfield(J,'trial_kind')
            nextPath = char(J.manifest);
            if ~isfile(nextPath)
                error('K49:MovedPointer','索引中的运行清单已经移动；请选择实际A/B目录里的manifest.json。');
            end
            [S,guard] = k49_resolve(nextPath,kind); return;
        end
        root = fileparts(inputPath);
        if ~strcmpi(k49_basename(inputPath),'manifest.json')
            error('K49:NotRunManifest','请选择运行脚本生成的manifest.json，不是分析结果或脚本校验清单。');
        end
    else
        error('K49:InputType','输入应为单轮试验目录、manifest.json或该轮压缩文件。');
    end
else
    error('K49:InputMissing','输入路径不存在：%s',inputPath);
end
mf = fullfile(root,'manifest.json');
if ~isfile(mf)
    candidates = k49_find_named(root,'manifest.json');
    matched = {};
    for ci = 1:numel(candidates)
        try
            J = k49_json_read(candidates{ci});
            if strcmp(k49_get(J,'trial_kind',''),kind), matched{end+1} = candidates{ci}; end %#ok<AGROW>
        catch
        end
    end
    if numel(matched) ~= 1
        error('K49:AmbiguousRun','未能唯一找到%s运行清单，匹配%d份。请选择具体单轮目录，不从多轮记录里猜最新。',kind,numel(matched));
    end
    mf = matched{1}; root = fileparts(mf);
end
J = k49_json_read(mf);
if ~strcmp(k49_get(J,'trial_kind',''),kind)
    error('K49:WrongKind','入口要求%s，但清单是%s；请改选对应试验。',kind,k49_get(J,'trial_kind','未知'));
end
S = struct('root',root,'manifestPath',mf,'originalInput',originalInput,'outputAnchor',anchor);
end

function k49_safe_zip(path)
% 解压前拒绝绝对路径及父目录跳转；仅检查目录，不执行压缩包内任何程序。
if ~usejava('jvm'), error('K49:Java','ZIP路径检查和文件校验需要MATLAB自带Java；请勿使用-nojvm启动。'); end
z = javaObject('java.util.zip.ZipFile',path); closer = onCleanup(@()z.close()); %#ok<NASGU>
it = z.entries();
while it.hasMoreElements()
    entry = it.nextElement(); name = strrep(char(entry.getName()),'\','/');
    parts = strsplit(name,'/');
    if startsWith(name,'/') || ~isempty(regexp(name,'^[A-Za-z]:','once')) || any(strcmp(parts,'..'))
        error('K49:UnsafeZip','压缩文件含越界路径，拒绝解压：%s',name);
    end
end
end

function [R,D] = k49_analyze(S,kind,C,outDir)
fprintf('\n正在计算 %s；来源：%s\n',kind,S.originalInput);
if ~isfolder(outDir), mkdir(outDir); end
R = struct(); R.version = C.version; R.kind = kind; R.input = S.originalInput;
R.manifest = k49_json_read(S.manifestPath);
R.manifestSHA256 = k49_sha(S.manifestPath);
if ~C.selftestMode
    expKind = k49_get(R.manifest,'experiment_kind','');
    if ~strcmp(expKind,C.requiredExperimentKind)
        error('K49:WrongExperiment','本计算器只接受%s；当前清单experiment_kind=%s。拒绝误用旧V4.9运行。',C.requiredExperimentKind,expKind);
    end
    runnerVersion = k49_get(R.manifest,'version','');
    if ~strcmp(runnerVersion,C.requiredRunnerVersion)
        error('K49:WrongRunnerVersion', ...
            'R2只接受已实际运行成功的R5运行器：%s；当前manifest version=%s。', ...
            C.requiredRunnerVersion,runnerVersion);
    end
    if ~logical(k49_get(R.manifest,'coordinate_patch_semantic_verified',false))
        error('K49:CoordinateIdentity','运行清单没有两处坐标补丁的语义核验证明。');
    end
    srcSha = k49_get(R.manifest,'source_model_sha256','');
    if isempty(regexp(srcSha,'^[0-9a-fA-F]{64}$','once'))
        error('K49:SourceSHA','运行清单缺少有效source_model_sha256。');
    end
end
R.experimentKind = k49_get(R.manifest,'experiment_kind','');
R.runnerVersion = k49_get(R.manifest,'version','');
R.sourceModelSHA256 = k49_get(R.manifest,'source_model_sha256','');
R.warnings = {}; R.comparison = struct('status','NOT_APPLICABLE_A');
if abs(k49_number(k49_get(R.manifest,'duration_s',NaN))-C.horizon) > 1e-9
    error('K49:WrongDuration','此计算器对应离网后30秒，清单duration_s不等于30。不能用旧15秒运行冒充。');
end
if ~isfinite(k49_number(k49_get(R.manifest,'duration_s',NaN)))
    error('K49:DurationMissing','运行清单缺少有效的duration_s。');
end
R.captureComplete = strcmp(k49_get(R.manifest,'status',''),'CAPTURE_COMPLETE_NO_ELECTRICAL_VERDICT');
R.fingerprint = k49_get(R.manifest,'fingerprint','');
R.meta = struct();
metaNames = {'model_audit','intervention','prej1','stage3','telemetry_paths','raw_archive'};
for mi = 1:numel(metaNames)
    key = metaNames{mi}; file = fullfile(S.root,[key '.json']);
    if isfile(file), R.meta.(key)=k49_json_read(file); else, R.meta.(key)=struct(); end
end
paramPath = fullfile(S.root,'prej1_parameters.json');
if isfile(paramPath), R.params=k49_parameter_pairs(paramPath); else, R.params=cell(0,2); end
R.dataSource = 'DIRECT_CURRENT_OPREDHAWKTARGET';
R.modelRoot = S.modelRoot;
fprintf('[1/6] 直接读取当前Build四个OpREDHAWKtarget中的五组MAT；较大文件需要读取和计算SHA256。\n');
schema = k49_schema();
k49_write_schema(schema,outDir);
R.fileRows = cell(0,12); R.familyRows = cell(0,9); raw = cell(1,5);
for gi = 1:5
    [raw{gi},filesHere,familyHere] = k50_family_direct(S.modelRoot,gi,C);
    R.fileRows = [R.fileRows;filesHere]; %#ok<AGROW>
    R.familyRows = [R.familyRows;familyHere]; %#ok<AGROW>
    fprintf('  %s：%d个去重样本，目标时间%.6f～%.6f秒。\n',C.groups{gi},numel(raw{gi}.t),raw{gi}.t(1),raw{gi}.t(end));
end
k49_csv(fullfile(outDir,'01_DIRECT_MAT_FILE_AUDIT.csv'), ...
    {'Group','SourceFile','Bytes','SHA256','Modified','RowsIncludingTime','Samples','FirstTime_s','LastTime_s','Orientation','TaskTarget','Result'},R.fileRows);
k49_csv(fullfile(outDir,'02_FAMILY_MERGE_AUDIT.csv'),{'Group','UniqueSamples','FirstTime_s','LastTime_s','DuplicateSamplesRemoved','MedianDt_s','ExpectedDt_s','MaxGap_s','SourceDirectoryCount'},R.familyRows);
if isempty(raw{4}.t), error('K49:NoG29','系统第29组不可用，无法以目标记录定位真实开断。'); end
[tJ1,edgeInfo] = k49_j1(raw{4},R.manifest,C);
R.j1 = tJ1; R.edge = edgeInfo;
R.stage3 = k49_stage3(raw{4},tJ1);
D = k49_sources(raw,schema,tJ1,C);
R.fullRecordIsolation = k49_isolation(raw,kind,tJ1,C);
clear raw;
[R.coverage,R.gaps,R.signalQuality] = k49_quality(D,tJ1,C);
k49_derived_dictionary(D,outDir);
k49_csv(fullfile(outDir,'03_COVERAGE_BY_WINDOW.csv'),{'Source','Window','StartAfterJ1_s','EndAfterJ1_s','RecordedSamples','KnownTime_s','TimeCoverageFraction','FirstAfterJ1_s','LastAfterJ1_s','MaxGap_s','EndpointCovered'},R.coverage);
k49_csv(fullfile(outDir,'04_RAW_GAPS.csv'),{'Source','LeftAfterJ1_s','RightAfterJ1_s','Gap_s','EstimatedMissingSamples','Meaning'},R.gaps);
k49_csv(fullfile(outDir,'05_SIGNAL_FINITE_QUALITY.csv'),{'Source','Signal','Meaning','RecordedSamples','FiniteSamples','NonfiniteSamples','KnownTimeFraction','SourceInterpretation'},R.signalQuality);
R.contract = k49_contract(D,R,C);
k49_csv(fullfile(outDir,'06_RUN_CONTRACT.csv'),{'Check','Observed','Status','Meaning'},R.contract);
fprintf('[2/6] 计算全部原始字段和派生字段的分窗统计。\n');
R.metrics = k49_metrics(D,tJ1,C);
k49_csv(fullfile(outDir,'07_ALL_SIGNAL_WINDOW_METRICS.csv'),k49_metric_header(),R.metrics);
fprintf('[3/6] 计算原速率事件、尾段、中央核算与隔离有效性。\n');
[R.episodes,R.eventStats,R.catalog] = k49_events(D,tJ1,R.stage3,C);
k49_csv(fullfile(outDir,'08_NATIVE_EVENT_EPISODES.csv'),{'Source','Event','StartAfterJ1_s','EndAfterJ1_s','ConfirmedDuration_s','StartBracketLeft_s','StartBracketRight_s','LeftCensored','RightCensored','Samples','Extremum','Threshold','ReferenceOnly'},R.episodes);
k49_csv(fullfile(outDir,'09_EVENT_DURATION_SUMMARY.csv'),{'Source','Event','Episodes','FirstAfterJ1_s','ConfirmedTotal_s','LongestConfirmed_s','CountAtLeast100ms','Threshold','ReferenceOnly'},R.eventStats);
k49_csv(fullfile(outDir,'10_EVENT_CATALOG.csv'),{'EventID','Event','Source','TimeAfterJ1_s','TimeBasis'},R.catalog);
R.tail = k49_tail(R.metrics,C);
k49_csv(fullfile(outDir,'11_TAIL_15_30S.csv'),{'Window','Vmean_pu','Vmin_pu','Vmax_pu','Vstd_pu','Vslope_pu_s','Fmean_Hz','Fstd_Hz','Fslope_Hz_s','QstateFirst','QstateLast','QstateSlope_s','VmeanWithinReference','FmeanWithinReference','VKnownFraction','FKnownFraction','Scope'},R.tail);
R.returnBands = k49_return_bands(D(1),tJ1,C);
k49_csv(fullfile(outDir,'12_BAND_RETURN_AND_HOLD.csv'),{'Band','StartAfterJ1_s','FirstEntry_s','FirstContinuous1s_s','StartOfFinalKnownHold_s','KnownHoldTo_s','KnownHoldDuration_s','Meaning'},R.returnBands);
[R.bookkeeping,R.bookSeries] = k49_qbook(D,tJ1,C);
k49_csv(fullfile(outDir,'13_QBIAS_ACCOUNTING.csv'),{'Window','AlignedSamples','CandidateSamples','ValidAlignedFraction','ReferenceSumRMSE','ReferenceSumMaxAbs','RequestSumRMSEvsState','Meaning'},R.bookkeeping);
k49_numeric_csv(fullfile(outDir,'13A_QBIAS_CHAIN_10MS.csv'),R.bookSeries.names,R.bookSeries.data);
k49_csv(fullfile(outDir,'14_ISOLATION_FULL_RATE.csv'),{'Layer','Source','Signal','MaxAbs','NonfiniteSamples','Samples','FirstNonzeroAfterJ1_s','Status','Meaning'},R.fullRecordIsolation);
R.host = k49_host_observations(S.root,kind,tJ1,C);
k49_csv(fullfile(outDir,'15_HOST_OBSERVATIONS.csv'),{'Signal','FiniteSamples','NonfiniteOrMissing','MaxAbs','FirstNonzeroAfterJ1_s','Scope'},R.host);
fprintf('[4/6] 计算严格原始窗和小缺口估计频谱，单列历史关注0.25～0.70赫兹。\n');
R.spectra = k49_spectra(D,tJ1,C);
k49_csv(fullfile(outDir,'16_SPECTRA.csv'),{'Source','Signal','Window','Method','RequestedLo_Hz','RequestedHi_Hz','ActualStartAfterJ1_s','ActualEndAfterJ1_s','Duration_s','SampleRate_Hz','Resolution_Hz','NativeMaxGap_s','EstimatedFraction','Peak_Hz','CoherentPeakAmplitude','BandRMS','Status'},R.spectra);
fprintf('[5/6] 导出全量10毫秒展示、事件原速率片段与来源信息。\n');
R.series = k49_export_series(D,tJ1,C,outDir);
k49_export_events(D,R.catalog,tJ1,C,outDir);
R.identityRows = k49_identity(R,C);
k49_csv(fullfile(outDir,'19_RUNTIME_IDENTITY.csv'),{'Item','Observed','ExpectedOrMeaning','Status'},R.identityRows);
R.allRequiredDataPresent = k49_all_sources_complete(R.coverage,C);
R.tailStatus = k49_tail_status(R.tail);
R.status = 'CALCULATED_NO_AUTOMATIC_ELECTRICAL_PASS';
R.originalRoot = k49_get(R.manifest,'output_directory','');
k49_copy_metadata(S.root,outDir);
fprintf('[6/6] 生成图、摘要和结果文件；B随后还会核对A。\n');
if C.makePlots
    try
        k49_plots(R.series,R.tail,outDir);
    catch plotError
        R.warnings{end+1} = ['数值结果已保留，绘图未完成：' plotError.message];
        k49_text(fullfile(outDir,'PLOT_WARNING.txt'),plotError.message);
    end
end
k49_write_summary(R,outDir,C);
small = k49_small_result(R); %#ok<NASGU>
save(fullfile(outDir,'RUN_RESULT.mat'),'small','-v7');
k49_json_write(fullfile(outDir,'RUN_RESULT.json'),small);
fprintf('%s计算完成。数据与电气结果分别记录；开始下一项或打包。\n',kind);
end

function [F,rows,fam] = k50_family_direct(modelRoot,gi,C)
% 来自仓库已验证的BOARD15 MAT经验：
%   只在 current *_{task}/OpREDHAWKtarget 下找对应 stem*.mat；
%   一个family只能来自一个target目录；所有segment按Target Time合并；
%   同时间不同数据硬失败，不自动选择“最新文件”掩盖混跑。
group=C.groups{gi}; stem=C.stems{gi}; width=C.rows(gi); task=C.taskSuffix{gi};
pattern=[stem '*.mat'];
z=dir(fullfile(modelRoot,'**',pattern));
wantTail=lower(['_' task '\opredhawktarget']);
keep=false(size(z));
for k=1:numel(z)
    if z(k).isdir, continue; end
    folderNorm=lower(strrep(z(k).folder,'/','\'));
    keep(k)=endsWith(folderNorm,wantTail);
end
z=z(keep);
if isempty(z)
    error('K50:DirectMatMissing', ...
        '[%s] 未找到 %s；应位于当前 *_%s\\OpREDHAWKtarget。',group,pattern,task);
end
folders=unique({z.folder},'stable');
if numel(folders)~=1
    msg=sprintf('[%s] 当前模型根下出现多个匹配target目录，拒绝猜：',group);
    for i=1:numel(folders), msg=sprintf('%s\n  %s',msg,folders{i}); end
    error('K50:DirectMatAmbiguous','%s',msg);
end
[~,ord]=sort([z.datenum]); z=z(ord);
arrays={}; dirs={}; rows=cell(0,12); duplicateCount=0;
for k=1:numel(z)
    localPath=fullfile(z(k).folder,z(k).name);
    W=whos('-file',localPath); names={W.name};
    if ~any(strcmp(names,stem))
        error('K50:DirectVariable','%s中没有精确变量%s；不改用任意第一变量。',localPath,stem);
    end
    P=load(localPath,stem); a=P.(stem);
    if ~isnumeric(a)||~isreal(a)||ndims(a)>2
        error('K50:DirectMatrixType','%s不是预期实数二维矩阵。',localPath);
    end
    if size(a,1)==width && size(a,2)~=width
        orientation='CHANNELS_BY_SAMPLES';
    elseif size(a,2)==width && size(a,1)~=width
        a=a.'; orientation='TRANSPOSED_ON_READ';
    elseif size(a,1)==width && size(a,2)==width
        goodRow=all(isfinite(a(1,:)))&&all(diff(double(a(1,:)))>=0);
        goodCol=all(isfinite(a(:,1)))&&all(diff(double(a(:,1)))>=0);
        if goodRow==goodCol, error('K50:DirectSquare','方阵时间方向不唯一：%s',localPath); end
        if goodCol, a=a.'; end
        orientation='SQUARE_TIME_AXIS_VERIFIED';
    else
        error('K50:DirectWidth','%s尺寸为%s；%s必须为%d行（含Target Time）。', ...
            localPath,mat2str(size(a)),group,width);
    end
    a=double(a);
    if isempty(a)||size(a,2)<2, error('K50:DirectEmpty','记录分段无有效样本：%s',localPath); end
    tt=a(1,:);
    if any(~isfinite(tt))||any(diff(tt)<-C.timeGridTol)
        error('K50:DirectTime','%s Target Time非有限或文件内回退。',localPath);
    end
    if any(abs(tt/C.step-round(tt/C.step))*C.step>C.timeGridTol)
        error('K50:DirectTimeGrid','%s时间不在100微秒计算网格。',localPath);
    end
    sha=k49_sha(localPath); info=dir(localPath);
    rows(end+1,:)={group,localPath,info.bytes,sha,datestr(info.datenum,'yyyy-mm-dd HH:MM:SS'), ...
        size(a,1),size(a,2),tt(1),tt(end),orientation,folders{1},'DIRECT_CURRENT_TARGET_SHA256'}; %#ok<AGROW>
    arrays{end+1}=a; dirs{end+1}=folders{1}; %#ok<AGROW>
end
if isempty(arrays), error('K50:DirectFamilyEmpty','%s没有可用MAT。',group); end
uniqueDirs=unique(dirs);
if numel(uniqueDirs)~=1
    error('K50:DirectFamilyDirs','%s记录来自多个target目录。',group);
end
A=cat(2,arrays{:}); clear arrays;
[tick,ord]=sort(round(A(1,:)/C.step)); A=A(:,ord);
repeat=find(diff(tick)==0);
for ri=reshape(repeat,1,[])
    left=A(:,ri); right=A(:,ri+1);
    sameSpecial=(isnan(left)&isnan(right)) | (isinf(left)&isinf(right)&sign(left)==sign(right));
    finitePair=isfinite(left)&isfinite(right);
    consistent=sameSpecial | (finitePair & abs(left-right)<=C.duplicateAbsTol+1e-10.*max(abs(left),abs(right)));
    if ~all(consistent)
        error('K50:DirectMixedRun', ...
            '%s在Target Time %.7f秒存在不同内容重叠；当前target目录可能混入多轮segment，拒绝静默选最新。', ...
            group,A(1,ri));
    end
end
keep=[true diff(tick)>0]; duplicateCount=nnz(~keep); A=A(:,keep);
t=A(1,:).'; x=A(2:end,:).'; clear A;
if numel(t)<2, error('K50:DirectTooShort','%s合并后不足两个样本。',group); end
actualDt=median(diff(t));
if abs(actualDt-C.dt(gi))>max(C.timeGridTol,C.dt(gi)*0.02)
    error('K50:DirectSampling','%s采样间隔%.9g与预期%.9g不符。',group,actualDt,C.dt(gi));
end
F=struct('group',group,'t',t,'x',x,'dt',C.dt(gi));
fam={group,numel(t),t(1),t(end),duplicateCount,actualDt,C.dt(gi),max(diff(t)),numel(uniqueDirs)};
end

function [F,rows,fam] = k49_family(root,entries,gi,C)
group = C.groups{gi}; stem = C.stems{gi}; width = C.rows(gi);
rows = cell(0,12); arrays = {}; dirs = {}; duplicateCount = 0;
for ei = 1:numel(entries)
    E = entries{ei};
    if ~strcmp(k49_get(E,'group',''),group), continue; end
    registered = k49_get(E,'archive','');
    [localPath,rel] = k49_local_raw(root,registered,group);
    expectedHash = lower(k49_get(E,'sha256',''));
    if isempty(regexp(expectedHash,'^[0-9a-f]{64}$','once'))
        error('K49:MissingHash','%s没有有效的文件校验值，不把未知身份数据当作本次试验。',rel);
    end
    actualHash = k49_sha(localPath);
    if ~strcmp(actualHash,expectedHash)
        error('K49:HashMismatch','原始文件内容与运行归档不一致：%s。保留源文件，检查同步/复制，不重新运行试验。',rel);
    end
    W = whos('-file',localPath);
    names = {W.name};
    if ~any(strcmp(names,stem))
        error('K49:Variable','%s中没有预期变量%s；不改用任意第一变量。',rel,stem);
    end
    P = load(localPath,stem); a = P.(stem);
    if ~isnumeric(a) || ~isreal(a) || ndims(a)>2
        error('K49:MatrixType','%s不是预期的实数二维记录矩阵。',rel);
    end
    if size(a,1)==width && size(a,2)~=width
        orientation = 'CHANNELS_BY_SAMPLES';
    elseif size(a,2)==width && size(a,1)~=width
        a = a.'; orientation = 'TRANSPOSED_ON_READ';
    elseif size(a,1)==width && size(a,2)==width
        goodRow = all(isfinite(a(1,:))) && all(diff(double(a(1,:)))>=0);
        goodCol = all(isfinite(a(:,1))) && all(diff(double(a(:,1)))>=0);
        if goodRow == goodCol, error('K49:AmbiguousMatrix','方阵时间方向不唯一：%s',rel); end
        if goodCol, a=a.'; end
        orientation = 'SQUARE_TIME_AXIS_VERIFIED';
    else
        error('K49:Width','%s尺寸为%s；%s应为%d行（含目标时间）。',rel,mat2str(size(a)),group,width);
    end
    a=double(a);
    if isempty(a) || size(a,2)<2, error('K49:EmptySegment','记录分段无有效样本：%s',rel); end
    tt=a(1,:);
    if any(~isfinite(tt)) || any(diff(tt)<-C.timeGridTol)
        error('K49:ResetInsideFile','%s时间非有限或在文件内回退；不能排序掩盖多次试验/复位。',rel);
    end
    if any(abs(tt/C.step-round(tt/C.step))*C.step>C.timeGridTol)
        error('K49:TimeGrid','%s时间不在当前100微秒计算网格内。',rel);
    end
    info=dir(localPath);
    rows(end+1,:)={group,rel,info.bytes,expectedHash,actualHash,1,size(a,1),size(a,2),tt(1),tt(end),orientation,'VERIFIED'}; %#ok<AGROW>
    arrays{end+1}=a; dirs{end+1}=fileparts(rel); %#ok<AGROW>
end
if isempty(arrays)
    error('K49:MissingFamily','本轮清单缺少%s。请同步后只归档，不能混入旧试验。',group);
end
uniqueDirs=unique(dirs);
if numel(uniqueDirs)~=1
    error('K49:AmbiguousFamily','%s记录来自多个目录；拒绝自动选最新或混合。',group);
end
A=cat(2,arrays{:}); clear arrays;
[tick,ord]=sort(round(A(1,:)/C.step)); A=A(:,ord);
repeat=find(diff(tick)==0);
for ri=reshape(repeat,1,[])
    left=A(:,ri); right=A(:,ri+1);
    sameSpecial=(isnan(left)&isnan(right)) | (isinf(left)&isinf(right)&sign(left)==sign(right));
    finitePair=isfinite(left)&isfinite(right);
    consistent=sameSpecial | (finitePair & abs(left-right)<=C.duplicateAbsTol+1e-10.*max(abs(left),abs(right)));
    if ~all(consistent)
        error('K49:ConflictingOverlap','%s在目标时间%.7f秒存在不同内容的重叠样本；可能混入其他运行，拒绝静默覆盖。',group,A(1,ri));
    end
end
keep=[true diff(tick)>0]; duplicateCount=nnz(~keep); A=A(:,keep);
t=A(1,:).'; x=A(2:end,:).'; clear A;
if numel(t)<2, error('K49:TooShort','%s合并后不足两个样本。',group); end
actualDt=median(diff(t));
if abs(actualDt-C.dt(gi))>max(C.timeGridTol,C.dt(gi)*0.02)
    error('K49:Sampling','%s采样间隔%.9g与本次预期%.9g不符。禁止用错误采样率计算频谱。',group,actualDt,C.dt(gi));
end
F=struct('group',group,'t',t,'x',x,'dt',C.dt(gi));
fam={group,numel(t),t(1),t(end),duplicateCount,actualDt,C.dt(gi),max(diff(t)),numel(uniqueDirs)};
end

function [path,rel] = k49_local_raw(root,registered,group)
normalized = strrep(char(registered),'\','/');
pos = strfind(lower(normalized),'/raw/');
if isempty(pos)
    if startsWith(lower(normalized),'raw/'), rel=normalized; else
        error('K49:ArchivePath','原始清单路径不含RAW，不能推测文件位置：%s',normalized);
    end
else
    rel=normalized(pos(end)+1:end);
end
parts=strsplit(rel,'/');
if any(strcmp(parts,'..')) || numel(parts)<3 || ~strcmpi(parts{1},'RAW') || ~strcmp(parts{2},group)
    error('K49:ArchivePath','原始路径组别或层级不合法：%s',rel);
end
path=fullfile(root,parts{:});
if ~isfile(path)
    error('K49:RawMissing','本轮原始文件缺失：%s。请选择完整A/B运行目录或压缩包；不要选PREVIOUS_RAW（旧记录备份）。',path);
end
end

function [tj,E] = k49_j1(F,M,C)
y=F.x(:,27); t=F.t;
ix=find(isfinite(y(1:end-1))&isfinite(y(2:end))&y(1:end-1)>.5&y(2:end)<=.5)+1;
host=k49_number(k49_get(M,'j1_first_open_host',NaN));
if isfinite(host)
    matches=ix(abs(t(ix)-host)<=.02);
else
    matches=ix;
end
if numel(matches)~=1
    error('K49:J1','第29组无法定位唯一且与运行清单对应的断路器下降沿；不能用主机标签替代。');
end
i=matches(1); tj=t(i);
E=struct('leftSample_s',t(i-1),'rightSample_s',t(i),'bracketWidth_s',t(i)-t(i-1), ...
    'hostConfirmation_s',host,'hostMinusRightSample_s',host-tj,'allFallingEdges',t(ix).');
E.preciseAtLoggerRate=(E.bracketWidth_s<=1.5*F.dt+C.timeGridTol);
end

function ts=k49_stage3(F,tj)
i=find(F.t>=tj & isfinite(F.x(:,15)) & abs(F.x(:,15)-3)<.1,1,'first');
if isempty(i), ts=NaN; else, ts=F.t(i); end
end

function D=k49_sources(raw,S,tj,C)
% 原始列号不变。附加推导列全部列入字典，不把推导量冒充新测量。
D=repmat(struct('name','','t',[],'x',[],'names',{{}},'cn',{{}},'dt',0,'rawCount',0),1,7);
D(1)=k49_source('SYSTEM',raw{4}.t,raw{4}.x,S.gnames,S.gcn,raw{4}.dt);
D(2)=k49_source('ESS1',raw{5}.t,raw{5}.x,S.enames,S.ecn,raw{5}.dt);
devNames={'PV1','PV2','ESS2','EV1','EV2'}; gi=[3 3 2 1 1]; starts=[1 49 1 1 49];
for k=1:5
    F=raw{gi(k)};
    D(k+2)=k49_source(devNames{k},F.t,F.x(:,starts(k):starts(k)+47),S.dnames,S.dcn,F.dt);
end
% 仅裁去与本轮问题无关的早期并网原始阵列；隔离全速率核验另对未裁剪raw进行。
for si=1:numel(D)
    m=D(si).t>=tj-.25 & D(si).t<=tj+C.horizon+2*D(si).dt;
    D(si).t=D(si).t(m); D(si).x=D(si).x(m,:);
end
g=D(1); v=abs(g.x(:,31))/C.nominalV; err=g.x(:,39)-v;
g=k49_add(g,'Vpu_RMS','公共连接点线电压有效值标幺',v);
g=k49_add(g,'Verror_instant','即时目标减实测电压误差',err);
g=k49_add(g,'Qstate_rate','中央偏置状态变化率（缺口处无值）',k49_derivative(g.t,g.x(:,41),g.dt));
g=k49_add(g,'Error_direction_conflict','即时与滤波误差反向且两者超过0.01（诊断）', ...
    double(err.*g.x(:,40)<0 & abs(err)>.01 & abs(g.x(:,40))>.01));
D(1)=g;
e=D(2);
e=k49_add(e,'VPI_mapped_Id','电压环映射后d轴电流修正（负原始第二分量）',-e.x(:,117));
e=k49_add(e,'VPI_mapped_Iq','电压环映射后q轴电流修正（原始第一分量）',e.x(:,116));
e=k49_add(e,'Vq_error','电压环q电压参考减q电压实测',e.x(:,127)-e.x(:,126));
e=k49_add(e,'Vd_error_if_ref0','假设d轴参考为零时的误差；不是已记录的d轴参考',-e.x(:,128));
e=k49_add(e,'Itrack','最终电流参考与实测电流的向量误差',hypot(e.x(:,120)-e.x(:,122),e.x(:,121)-e.x(:,123)));
e=k49_add(e,'Iref_limit_residual','最终电流参考限流前后向量差',hypot(e.x(:,118)-e.x(:,120),e.x(:,119)-e.x(:,121)));
e=k49_add(e,'Iref_mag','最终电流参考幅值',hypot(e.x(:,120),e.x(:,121)));
e=k49_add(e,'Imeas_mag','实测电流幅值',hypot(e.x(:,122),e.x(:,123)));
u=hypot(e.x(:,124),e.x(:,125));
e=k49_add(e,'Vconv_mag','分量限幅后的电压命令幅值',u);
e=k49_add(e,'Vconv_component_max','电压命令最大绝对分量',max(abs(e.x(:,124:125)),[],2));
e=k49_add(e,'Mod_reconstructed_Vdc1000','按1000伏直流及480伏交流基准重构的调制需求（假设，非直接测量）', ...
    2*C.acLineBaseForIllustration*sqrt(2/3)/C.vdcForIllustration*u);
e=k49_add(e,'Vdq_mag','本地两个实测电压分量幅值',hypot(e.x(:,128),e.x(:,126)));
e=k49_add(e,'Theta_frequency_20ms','内部相角20毫秒差分频率（断点无值）',k49_phase_frequency(e.t,e.x(:,3),e.dt,.020));
a=(2/3)*(e.x(:,5)-.5*e.x(:,6)-.5*e.x(:,7)); b=(2/3)*sqrt(3)/2*(e.x(:,6)-e.x(:,7));
abcF=k49_phase_frequency(e.t,atan2(b,a),e.dt,.020);
vAt=k49_sample(D(1).t,k49_signal(D(1),'Vpu_RMS'),e.t,D(1).dt,'nearest');
badV=conv(double(~isfinite(vAt)|vAt<.7),ones(max(1,round(.020/e.dt))+1,1),'full');
abcF(badV(1:numel(vAt))>0)=NaN;
e=k49_add(e,'ABC_frequency_20ms','三相电压空间向量20毫秒差分频率（低压/缺口无效，仅交叉检查）',abcF);
D(2)=e;
for di=3:7
    d=D(di); vd=d.x(:,7); vq=d.x(:,8); vm=hypot(vd,vq);
    ud=vd./vm; uq=vq./vm; invalid=~isfinite(vm)|vm<.2; ud(invalid)=NaN; uq(invalid)=NaN;
    refP=ud.*d.x(:,3)+uq.*d.x(:,4); refR=-uq.*d.x(:,3)+ud.*d.x(:,4);
    measP=ud.*d.x(:,5)+uq.*d.x(:,6); measR=-uq.*d.x(:,5)+ud.*d.x(:,6);
    supP=ud.*d.x(:,29)+uq.*d.x(:,30); supR=-uq.*d.x(:,29)+ud.*d.x(:,30);
    lambda=d.x(:,33); baseR=(refR-supR)./lambda; baseP=(refP-supP)./lambda;
    baseR(abs(lambda)<.05)=NaN; baseP(abs(lambda)<.05)=NaN;
    pc=vd.*d.x(:,5)+vq.*d.x(:,6); qc=vq.*d.x(:,5)-vd.*d.x(:,6);
    values={ ...
        'Vdq_mag','实测电压向量幅值',vm; ...
        'Voltage_angle_deg','执行坐标中实际电压方向（度）',atan2d(vq,vd); ...
        'ud','沿实际电压方向d分量；幅值低于0.2时无效',ud; ...
        'uq','沿实际电压方向q分量；幅值低于0.2时无效',uq; ...
        'Ref_iP','最终参考沿有功方向分量',refP; ...
        'Ref_iR','最终参考沿本模型吸收无功方向分量',refR; ...
        'Meas_iP','实测电流沿有功方向分量',measP; ...
        'Meas_iR','实测电流沿吸收无功方向分量',measR; ...
        'Support_iP','记录的总支撑沿有功方向分量',supP; ...
        'Support_iR','记录的总支撑沿吸收无功方向分量',supR; ...
        'Base_iP_reconstructed','扣除支撑并除共同缩放重构的基础有功分量',baseP; ...
        'Base_iR_reconstructed','扣除支撑并除共同缩放重构的基础无功分量',baseR; ...
        'P_reconstructed','按本模型旋转坐标公式重构有功',pc; ...
        'Q_reconstructed','按本模型旋转坐标公式重构无功',qc; ...
        'P_reconstruction_error','重构有功减记录有功（不等于控制误差）',pc-d.x(:,16); ...
        'Q_reconstruction_error','重构无功减记录无功（不等于控制误差）',qc-d.x(:,17); ...
        'P_cross_vqIq','有功公式中vq乘iq的分量',vq.*d.x(:,6); ...
        'Q_cross_vqId','无功公式中vq乘id的分量',vq.*d.x(:,5); ...
        'Itrack','最终电流参考与实测电流向量差',hypot(d.x(:,3)-d.x(:,5),d.x(:,4)-d.x(:,6)); ...
        'Iref_mag','最终电流参考幅值',hypot(d.x(:,3),d.x(:,4)); ...
        'Imeas_mag','实测电流幅值',hypot(d.x(:,5),d.x(:,6)); ...
        'Vconv_mag','分量限幅后电压命令幅值',hypot(d.x(:,13),d.x(:,14)); ...
        'Vconv_component_max','电压命令最大绝对分量',max(abs(d.x(:,13:14)),[],2); ...
        'Scale_difference','最终共同缩放两个诊断输出之差',d.x(:,33)-d.x(:,34)};
    for vi=1:size(values,1), d=k49_add(d,values{vi,1},values{vi,2},values{vi,3}); end
    D(di)=d;
end
end

function s=k49_source(name,t,x,names,cn,dt)
s=struct('name',name,'t',t(:),'x',x,'names',{names},'cn',{cn},'dt',dt,'rawCount',size(x,2));
if numel(names)~=size(x,2) || numel(cn)~=numel(names)
    error('K49:Schema','%s字段字典宽度与真实数据不符。',name);
end
end

function s=k49_add(s,name,meaning,x)
if numel(x)~=numel(s.t) || any(strcmp(s.names,name)), error('K49:DerivedShape','推导量宽度或名称冲突：%s',name); end
s.x(:,end+1)=x(:); s.names{end+1}=name; s.cn{end+1}=meaning;
end

function x=k49_signal(s,name)
i=find(strcmp(s.names,name));
if numel(i)~=1, error('K49:Signal','%s中无法唯一找到字段%s。',s.name,name); end
x=s.x(:,i);
end

function [coverage,gaps,quality]=k49_quality(D,tj,C)
coverage=cell(0,11); gaps=cell(0,6); quality=cell(0,8);
for si=1:numel(D)
    s=D(si); tr=s.t-tj;
    for wi=1:size(C.windows,1)
        a=tj+C.windows(wi,1); b=tj+C.windows(wi,2);
        st=k49_stat(s.t,ones(size(s.t)),a,b,s.dt);
        selected=s.t>=a & s.t<b;
        tt=s.t(selected); maxgap=NaN;
        if numel(tt)>1, maxgap=max(diff(tt)); end
        endpoint=~isempty(tt)&&tt(1)<=a+1.5*s.dt&&tt(end)>=b-1.5*s.dt;
        coverage(end+1,:)={s.name,C.windowNames{wi},a-tj,b-tj,st.n,st.knownTime,st.coverage, ...
            k49_first(tt)-tj,k49_last(tt)-tj,maxgap,double(endpoint)}; %#ok<AGROW>
    end
    ig=find(diff(s.t)>1.5*s.dt+C.timeGridTol);
    for ii=reshape(ig,1,[])
        if tr(ii+1)<0 || tr(ii)>C.horizon, continue; end
        gaps(end+1,:)={s.name,tr(ii),tr(ii+1),s.t(ii+1)-s.t(ii),max(0,round((s.t(ii+1)-s.t(ii))/s.dt)-1),'原始记录缺口；事件持续时间不跨此处累计'}; %#ok<AGROW>
    end
    for ci=1:size(s.x,2)
        st=k49_stat(s.t,s.x(:,ci),tj,tj+C.horizon,s.dt);
        if ci<=s.rawCount, scope='记录字段；缺值保持缺值'; else, scope='推导字段；定义见字典'; end
        quality(end+1,:)={s.name,s.names{ci},s.cn{ci},st.n,st.finiteN,st.n-st.finiteN,st.coverage,scope}; %#ok<AGROW>
    end
end
end

function H=k49_metric_header()
H={'Source','Signal','Meaning','Window','StartAfterJ1_s','EndAfterJ1_s','Samples','FiniteSamples','KnownTimeFraction', ...
    'Mean','Min','Max','Std','Slope_per_s','RMS','P95Abs','FirstFinite','LastFinite','PeakToPeak'};
end

function rows=k49_metrics(D,tj,C)
rows=cell(0,19);
for si=1:numel(D)
    s=D(si);
    for wi=1:size(C.windows,1)
        a=tj+C.windows(wi,1); b=tj+C.windows(wi,2);
        for ci=1:size(s.x,2)
            z=k49_stat(s.t,s.x(:,ci),a,b,s.dt);
            rows(end+1,:)={s.name,s.names{ci},s.cn{ci},C.windowNames{wi},a-tj,b-tj,z.n,z.finiteN,z.coverage, ...
                z.mean,z.min,z.max,z.std,z.slope,z.rms,z.p95abs,z.first,z.last,z.max-z.min}; %#ok<AGROW>
        end
    end
end
end

function z=k49_stat(t,x,a,b,dt)
t=t(:); x=x(:);
if numel(t)~=numel(x) || b<=a, error('K49:StatsShape','统计输入长度或窗口不合法。'); end
m=t>=a-1e-10 & t<b-1e-10; tt=t(m); xx=x(m);
w=max(0,min(tt+dt,b)-max(tt,a));
z=struct('n',numel(xx),'finiteN',nnz(isfinite(xx)),'knownTime',0,'coverage',0,'mean',NaN,'min',NaN,'max',NaN, ...
    'std',NaN,'slope',NaN,'rms',NaN,'p95abs',NaN,'first',NaN,'last',NaN);
good=isfinite(xx)&isfinite(tt)&w>0; xx=xx(good); tt=tt(good); w=w(good);
if isempty(xx), return; end
sw=sum(w); z.knownTime=sw; z.coverage=min(1,sw/(b-a));
z.mean=sum(w.*xx)/sw; z.min=min(xx); z.max=max(xx);
z.std=sqrt(sum(w.*(xx-z.mean).^2)/sw); z.rms=sqrt(sum(w.*xx.^2)/sw);
z.first=xx(1); z.last=xx(end);
tt=tt-tt(1); mt=sum(w.*tt)/sw; den=sum(w.*(tt-mt).^2);
if den>0, z.slope=sum(w.*(tt-mt).*(xx-z.mean))/den; end
[absSorted,ord]=sort(abs(xx)); cumulative=cumsum(w(ord))/sw;
ix=find(cumulative>=.95,1,'first'); z.p95abs=absSorted(ix);
end

function rows=k49_contract(D,R,C)
rows=cell(0,4); g=D(1); e=D(2); t0=R.j1; t1=t0+C.horizon;
rows(end+1,:)={'capture_complete',R.captureComplete,k49_bool_status(R.captureComplete),'运行脚本完成状态，不是电气通过'};
rows(end+1,:)={'J1_native_time',R.j1,'OBSERVED','第29组实际下降沿右侧样本时刻'};
rows(end+1,:)={'J1_bracket_width_s',R.edge.bracketWidth_s,k49_bool_status(R.edge.preciseAtLoggerRate),'事件分辨率由记录间隔/缺口决定'};
rows(end+1,:)={'Stage3_delay_s',R.stage3-t0,k49_bool_status(isfinite(R.stage3)&&abs(R.stage3-t0-.2)<=.01),'与约0.200秒阶段进入时序比较'};
q=k49_stat(g.t,double(g.x(:,27)<=.5 & isfinite(g.x(:,27))),t0,t1,g.dt);
rawFinite=k49_stat(g.t,g.x(:,27),t0,t1,g.dt);
rows(end+1,:)={'J1_open_fraction',q.mean,k49_bool_status(q.mean>.999 && rawFinite.coverage>=C.coverageReference),'无效状态不能冒充断开'};
for si=[1 3 4 5 6 7]
    if si==1, stage=D(si).x(:,15); else, stage=D(si).x(:,20); end
    m=D(si).t>=R.stage3+.002 & D(si).t<t1;
    if ~isfinite(R.stage3), ok=false; else, ok=any(m)&&all(isfinite(stage(m)))&&all(abs(stage(m)-3)<.1); end
    rows(end+1,:)={[D(si).name '_stage3_held'],k49_fraction(abs(stage(m)-3)<.1),k49_bool_status(ok),'第三阶段记录保持，不替代全部设备实际断路器反馈'}; %#ok<AGROW>
end
m=e.t>=t0+.005 & e.t<t1;
rows(end+1,:)={'ESS1_GridOn_zero',k49_fraction(abs(e.x(m,11))<.1),k49_bool_status(any(m)&&all(isfinite(e.x(m,11)))&&all(abs(e.x(m,11))<.1)),'储能1构网模式相关记录'};
rows(end+1,:)={'ESS1_J1rx_open',k49_fraction(e.x(m,15)<.5),k49_bool_status(any(m)&&all(isfinite(e.x(m,15)))&&all(e.x(m,15)<.5)),'储能1收到的开断状态'};
rows(end+1,:)={'F25_timeout_max',k49_max(e.x(m,87)),'DESCRIPTIVE','超时记录单列；不使用失效诊断量代替实际输出'};
rows(end+1,:)={'F25_applied_finite_fraction',k49_fraction(all(isfinite(e.x(m,99:100)),2)),'DESCRIPTIVE','输出电流前馈施加量有限性'};
rows(end+1,:)={'realtime_overrun','未由本清单可靠提供','NOT_PROVEN','计算完成不证明零超时，也不证明外部板卡连续闭环通过'};
end

function rows=k49_identity(R,C)
rows=cell(0,4); M=R.manifest;
rows(end+1,:)={'run_kind',R.kind,'对应A全功能或B中央零偏置', 'OBSERVED'};
rows(end+1,:)={'fingerprint',R.fingerprint,'当前磁盘模型语义指纹；不是目标二进制校验值',k49_bool_status(~isempty(R.fingerprint))};
step=k49_number(k49_get(M,'calculation_step_s',NaN));
rows(end+1,:)={'calculation_step_s',step,C.step,k49_bool_status(isfinite(step)&&abs(step-C.step)<1e-12)};
gain=k49_number(k49_get(M,'central_gain_actual',NaN)); target=.3;
if strcmp(R.kind,'QBIAS0_30'), target=0; end
rows(end+1,:)={'central_gain_actual',gain,target,k49_bool_status(isfinite(gain)&&abs(gain-target)<=C.compareParamTol)};
pv=k49_pair_value(R.params,'final/central/ki_qbias');
rows(end+1,:)={'prej1_gain_record',pv,target,k49_bool_status(isfinite(pv)&&abs(pv-target)<=C.compareParamTol)};
iv=k49_number(k49_get(R.meta.intervention,'after',NaN));
rows(end+1,:)={'intervention_gain_readback',iv,target,k49_bool_status(isfinite(iv)&&abs(iv-target)<=C.compareParamTol)};
audit=R.meta.model_audit; mask=k49_get(audit,'ESS1_voltage_mask',struct());
kp=k49_number(k49_get(mask,'Kp_Vreg',NaN)); ki=k49_number(k49_get(mask,'Ki_Vreg',NaN));
rows(end+1,:)={'ESS1_local_Kp',kp,.02,k49_bool_status(isfinite(kp)&&abs(kp-.02)<1e-12)};
rows(end+1,:)={'ESS1_local_Ki',ki,.14,k49_bool_status(isfinite(ki)&&abs(ki-.14)<1e-12)};
rows(end+1,:)={'data_source',R.dataSource,'直接读取current *_{task}/OpREDHAWKtarget；逐文件SHA/宽度/时间已在01表记录','OBSERVED'};
end

function rows=k49_isolation(raw,kind,tj,C)
rows=cell(0,9); g=raw{4};
rows=[rows;k49_zero_row('CENTRAL','SYSTEM','QbiasState',g.t,g.x(:,41),tj,C,kind)];
rows=[rows;k49_zero_row('REFERENCE_SUM','SYSTEM','QbiasReferenceApplied',g.t,g.x(:,42),tj,C,kind)];
devs={'PV1','PV2','ESS2','EV1','EV2'}; gi=[3 3 2 1 1]; starts=[1 49 1 1 49];
for di=1:5
    F=raw{gi(di)}; base=starts(di)-1;
    rows=[rows;k49_zero_row('REQUEST',devs{di},'IqSecRequest',F.t,F.x(:,base+44),tj,C,kind)]; %#ok<AGROW>
    rows=[rows;k49_zero_row('APPLIED_REFERENCE',devs{di},'IqSecApplied',F.t,F.x(:,base+45),tj,C,kind)]; %#ok<AGROW>
end
end

function row=k49_zero_row(layer,source,name,t,x,tj,C,kind)
m=t<=tj+C.horizon+1e-10; t=t(m); x=x(m); nf=nnz(~isfinite(x)); mx=k49_max(abs(x));
i=find(isfinite(x)&abs(x)>C.isoTol,1,'first');
if isempty(i), first=NaN; else, first=t(i)-tj; end
if ~strcmp(kind,'QBIAS0_30'), status='OBSERVE_A_NO_ZERO_REQUIREMENT';
elseif isempty(x) || nf>0, status='UNKNOWN_MISSING_OR_NONFINITE';
elseif mx>C.isoTol, status='NONZERO_ISOLATION_NOT_ESTABLISHED';
elseif min(t)>max(2*max(C.dt),2*C.step), status='INITIALIZATION_NOT_COVERED_ZERO_ONLY_LATER';
else, status='ZERO_ON_ALL_RECORDED_SAMPLES'; end
row={layer,source,name,mx,nf,numel(x),first,status,'只证明已记录样本；采样间隙的短脉冲不能由这些数据排除'};
end

function rows=k49_host_observations(root,kind,tj,C) %#ok<INUSD>
keys={'QbiasState','QbiasApplied','PV1_Qreq','PV2_Qreq','ESS2_Qreq','EV1_Qreq','EV2_Qreq', ...
    'PV1_Qapplied','PV2_Qapplied','ESS2_Qapplied','EV1_Qapplied','EV2_Qapplied'};
count=zeros(numel(keys),1); missing=count; maxAbs=nan(numel(keys),1); first=maxAbs;
file=fullfile(root,'samples.jsonl');
if isfile(file)
    fid=fopen(file,'r','n','UTF-8'); guard=onCleanup(@()fclose(fid)); %#ok<NASGU>
    while true
        line=fgetl(fid); if ~ischar(line), break; end
        if isempty(strtrim(line)), continue; end
        try, J=jsondecode(line); catch, missing=missing+1; continue; end
        extra=k49_get(J,'extra',struct()); t=k49_number(k49_get(J,'target_clock_s',NaN));
        for ki=1:numel(keys)
            v=k49_number(k49_get(extra,keys{ki},NaN));
            if ~isfinite(v) || ~isfinite(t), missing(ki)=missing(ki)+1; continue; end
            count(ki)=count(ki)+1;
            if isnan(maxAbs(ki)), maxAbs(ki)=abs(v); else, maxAbs(ki)=max(maxAbs(ki),abs(v)); end
            if isnan(first(ki))&&abs(v)>C.isoTol, first(ki)=t-tj; end
        end
    end
else
    missing(:)=NaN;
end
rows=cell(numel(keys),6);
for ki=1:numel(keys)
    rows(ki,:)={keys{ki},count(ki),missing(ki),maxAbs(ki),first(ki),'主机稀疏观察，不替代目标记录，不把未暴露项当零'};
end
end

function [rows,summary,catalog]=k49_events(D,tj,ts3,C)
rows=cell(0,13); summary=cell(0,9);
catalog={1,'J1_OPEN','SYSTEM',0,'目标原始下降沿右侧样本'};
if isfinite(ts3), catalog(end+1,:)={2,'STAGE3','SYSTEM',ts3-tj,'目标阶段状态首次为3'}; end
spec=cell(0,6);
for si=1:numel(D)
    s=D(si);
    if si==1
        v=k49_signal(s,'Vpu_RMS'); f=s.x(:,32);
        for th=C.voltageBands
            if th<1, direction=-1; label=sprintf('V_LT_%.2f',th); else, direction=1; label=sprintf('V_GT_%.2f',th); end
            spec(end+1,:)={si,label,v,th,direction,'历史诊断对照，不自动否决'}; %#ok<AGROW>
        end
        spec(end+1,:)={si,'FOUT_OUT_49_51',abs(f-50),1,1,'构网频率记录，非任意低压锁相估计'};
        spec(end+1,:)={si,'QBIAS_NONZERO',abs(s.x(:,41)),C.isoTol,1,'中央新增偏置作用开始'};
        spec(end+1,:)={si,'AUTHORITY_EXHAUSTED',s.x(:,46),.5,1,'中央可用无功能力耗尽'};
        spec(end+1,:)={si,'J1_RECLOSED',s.x(:,27),.5,1,'实际重合闸后不再是纯孤岛对照'};
        spec(end+1,:)={si,'ERROR_SIGN_CONFLICT',k49_signal(s,'Error_direction_conflict'),.5,1,'滤波误差与即时误差反向，不自动归因'};
    else
        spec(end+1,:)={si,'ITRACK_GT_0.10',k49_signal(s,'Itrack'),.10,1,'实际电流跟踪误差诊断'};
        spec(end+1,:)={si,'VCOMP_GE_1.249',k49_signal(s,'Vconv_component_max'),1.249-1e-12,1,'电压命令分量贴近1.25限值'};
        if si==2
            spec(end+1,:)={si,'MREC_GT_0.98',k49_signal(s,'Mod_reconstructed_Vdc1000'),.98,1,'假设基准下重构的低调制裕度，非直接记录'};
            spec(end+1,:)={si,'F25_TIMEOUT',s.x(:,87),.5,1,'F25超时诊断'};
        else
            spec(end+1,:)={si,'MODINDEX_GT_0.98',abs(s.x(:,15)),.98,1,'调制度低裕度观察'};
            spec(end+1,:)={si,'RAWMOD_GT_1',s.x(:,42),1,1,'分量限幅后、幅值限制前的调制需求'};
            spec(end+1,:)={si,'CURRENT_LIMIT',s.x(:,35),.5,1,'参考电流限制状态'};
            spec(end+1,:)={si,'QSEC_CLIP',s.x(:,48),.5,1,'二次偏置参考受限状态'};
        end
    end
end
for si=1:size(spec,1)
    source=D(spec{si,1}); v=spec{si,3}; th=spec{si,4}; signv=spec{si,5};
    m=source.t>=tj & source.t<=tj+C.horizon;
    t=source.t(m)-tj; x=v(m);
    if signv<0, cond=x<th; else, cond=x>th; end
    E=k49_episodes(t,x,cond,source.dt);
    for ei=1:size(E,1)
        if signv<0, extreme=E(ei,11); else, extreme=E(ei,12); end
        rows(end+1,:)={source.name,spec{si,2},E(ei,1),E(ei,2),E(ei,3),E(ei,4),E(ei,5),E(ei,6),E(ei,7),E(ei,10),extreme,th,spec{si,6}}; %#ok<AGROW>
    end
    if isempty(E), first=NaN; total=0; longest=0; sustained=0;
    else, first=E(1,1); total=sum(E(:,3)); longest=max(E(:,3)); sustained=nnz(E(:,3)>=.1-1e-10); end
    summary(end+1,:)={source.name,spec{si,2},size(E,1),first,total,longest,sustained,th,spec{si,6}}; %#ok<AGROW>
    pick=strcmp(spec{si,2},'QBIAS_NONZERO')||strcmp(spec{si,2},'V_GT_1.10')||strcmp(spec{si,2},'V_GT_1.20')||strcmp(spec{si,2},'V_LT_0.90')||strcmp(spec{si,2},'AUTHORITY_EXHAUSTED')||strcmp(spec{si,2},'J1_RECLOSED')||(strcmp(source.name,'ESS1')&&strcmp(spec{si,2},'ITRACK_GT_0.10'));
    if pick && isfinite(first)
        catalog(end+1,:)={size(catalog,1)+1,spec{si,2},source.name,first,'原速率首发；阈值仅作事件标记'}; %#ok<AGROW>
    end
end
g=D(1); m=g.t>=tj & g.t<=tj+C.horizon; t=g.t(m); v=k49_signal(g,'Vpu_RMS'); v=v(m);
valid=isfinite(v);
if any(valid)
    tv=t(valid); vv=v(valid); [~,ih]=max(vv); [~,il]=min(vv);
    catalog(end+1,:)={size(catalog,1)+1,'VMAX','SYSTEM',tv(ih)-tj,'原速率电压最大值'};
    catalog(end+1,:)={size(catalog,1)+1,'VMIN','SYSTEM',tv(il)-tj,'原速率电压最小值'};
end
% 各尾段界点也导出原始近邻，便于确认15秒以后是否新生异常。
for cp=[15 20 25 29.8]
    catalog(end+1,:)={size(catalog,1)+1,sprintf('TAIL_%.1f',cp),'SYSTEM',cp,'预定观察位置，不冒充事件'}; %#ok<AGROW>
end
if ~isempty(rows), [~,ord]=sort(cell2mat(rows(:,3))); rows=rows(ord,:); end
end

function E=k49_episodes(t,x,cond,dt)
% 连续事件不跨采样缺口、不跨非有限量；输出的持续时间为已确认下界。
t=t(:); x=x(:); cond=logical(cond(:)); n=numel(t); E=zeros(0,12);
if numel(x)~=n || numel(cond)~=n, error('K49:EpisodeShape','事件向量长度不符。'); end
valid=isfinite(t)&isfinite(x); on=cond&valid;
broken=[true;diff(t)>1.5*dt+1e-10];
start=find(on & ([true;~on(1:end-1)]|broken));
finish=find(on & ([~on(2:end);true]|[broken(2:end);true]));
if numel(start)~=numel(finish), error('K49:EpisodePair','事件起止配对异常。'); end
for k=1:numel(start)
    a=start(k); b=finish(k); left=NaN; right=NaN;
    lc=(a==1 || broken(a) || ~valid(max(1,a-1)));
    rc=(b==n || (b<n && (broken(b+1)||~valid(b+1))));
    if ~lc, left=t(a-1); end
    if ~rc, right=t(b+1); end
    E(end+1,:)=[t(a),t(b),max(0,t(b)-t(a)),left,t(a),double(lc),double(rc),t(b),right,b-a+1,min(x(a:b)),max(x(a:b))]; %#ok<AGROW>
end
end

function rows=k49_tail(metrics,C)
rows=cell(0,17); wins={'W12_15','W15_20','W20_25','W25_30'};
for wi=1:numel(wins)
    w=wins{wi}; v=k49_metric(metrics,'SYSTEM','Vpu_RMS',w);
    f=k49_metric(metrics,'SYSTEM','ESS1_Fout_Hz',w);
    q=k49_metric(metrics,'SYSTEM','QbiasState',w);
    vok=v(1)>=C.referenceVBand(1)&&v(1)<=C.referenceVBand(2);
    fok=f(1)>=C.referenceFBand(1)&&f(1)<=C.referenceFBand(2);
    rows(end+1,:)={w,v(1),v(2),v(3),v(4),v(5),f(1),f(4),f(5),q(8),q(9),q(5),double(vok),double(fok),v(11),f(11), ...
        '末段范围观察；不以早期越界或慢状态未完全停止自动否决'}; %#ok<AGROW>
end
end

function z=k49_metric(rows,source,signal,win)
ix=find(strcmp(rows(:,1),source)&strcmp(rows(:,2),signal)&strcmp(rows(:,4),win));
% 输出：[均值,最小,最大,标准差,斜率,均方根,95%绝对分位,首值,末值,峰峰,有效时间比例]
if numel(ix)~=1, error('K49:MetricLookup','统计项缺失或重名：%s/%s/%s',source,signal,win); end
z=[cell2mat(rows(ix,10:19)),rows{ix,9}];
end

function status=k49_tail_status(rows)
late=rows(2:4,:);
if isempty(late) || any(cell2mat(late(:,15:16))<.99,'all')
    status='TAIL_DATA_LIMITED';
elseif all(cell2mat(late(:,13:14))==1,'all')
    status='TAIL_MEANS_WITHIN_REFERENCE_BANDS_REVIEW_DYNAMICS';
else
    status='ONE_OR_MORE_TAIL_MEANS_OUTSIDE_REFERENCE_BANDS';
end
end

function ok=k49_all_sources_complete(rows,C)
m=strcmp(rows(:,2),'FULL30');
ok=nnz(m)==7 && all(cell2mat(rows(m,7))>=C.coverageReference) && all(cell2mat(rows(m,11))==1);
end

function rows=k49_return_bands(s,tj,C)
rows=cell(0,8); t=s.t-tj; v=k49_signal(s,'Vpu_RMS'); f=s.x(:,32);
spec={sprintf('V[%.2f,%.2f]',C.referenceVBand),v,C.referenceVBand; ...
    sprintf('F[%.1f,%.1f]',C.referenceFBand),f,C.referenceFBand};
for ki=1:size(spec,1)
    m=t>=0&t<=C.horizon; tt=t(m); x=spec{ki,2}; x=x(m); band=spec{ki,3};
    E=k49_episodes(tt,x,x>=band(1)&x<=band(2),s.dt);
    first=NaN; oneSecond=NaN; finalStart=NaN; endTime=NaN; held=NaN;
    if ~isempty(E)
        first=E(1,1); i=find(E(:,3)>=1-1e-10,1,'first');
        if ~isempty(i), oneSecond=E(i,1); end
        if ~isempty(tt)&&isfinite(x(end))&&x(end)>=band(1)&&x(end)<=band(2)
            finalStart=E(end,1); endTime=E(end,2); held=E(end,3);
        end
    end
    rows(end+1,:)={spec{ki,1},0,first,oneSecond,finalStart,endTime,held, ...
        '仅为记录终点以前的连续停留；初次进入不等于此后从未离开，数据缺口会中断确认'}; %#ok<AGROW>
end
end

function [rows,series]=k49_qbook(D,tj,C)
g=D(1); t=g.t; request=nan(numel(t),5); applied=request; meas=request; ref=request;
for di=3:7
    s=D(di);
    request(:,di-2)=k49_sample(s.t,s.x(:,44),t,s.dt,'nearest');
    applied(:,di-2)=k49_sample(s.t,s.x(:,45),t,s.dt,'nearest');
    meas(:,di-2)=k49_sample(s.t,k49_signal(s,'Meas_iR'),t,s.dt,'nearest');
    ref(:,di-2)=k49_sample(s.t,k49_signal(s,'Ref_iR'),t,s.dt,'nearest');
end
validApp=all(isfinite(applied),2)&isfinite(g.x(:,42));
validReq=all(isfinite(request),2)&isfinite(g.x(:,41));
sumA=sum(applied,2); sumR=sum(request,2); errorA=g.x(:,42)-sumA; errorR=g.x(:,41)-sumR;
errorA(~validApp)=NaN; errorR(~validReq)=NaN;
rows=cell(0,8);
for wi=1:size(C.windows,1)
    a=tj+C.windows(wi,1); b=tj+C.windows(wi,2); in=t>=a&t<b;
    z=k49_stat(t,errorA,a,b,g.dt); q=k49_stat(t,errorR,a,b,g.dt);
    rows(end+1,:)={C.windowNames{wi},nnz(in&validApp),nnz(in),k49_fraction(validApp(in)),z.rms,k49_max(abs(errorA(in))),q.rms, ...
        '五台均有效对齐才合计；缺样不补零；参考核算不是实测无功执行证明'}; %#ok<AGROW>
end
qt=(tj-.05:C.displayStep:tj+C.horizon).';
x=[g.x(:,41:42),sumR,sumA,errorA,sum(ref,2),sum(meas,2),g.x(:,43:46)];
y=k49_sample(t,x,qt,C.maxSmallGap,'linear');
series=struct('names',{{'time_abs_s','after_J1_s','Qstate','CentralAppliedRef','SumTransportRequest','SumAppliedRef','AccountingResidual','SumTotalRef_iR','SumTotalMeas_iR','CapPos','CapNeg','Integrating','Exhausted'}}, ...
    'data',[qt,qt-tj,y]);
end

function rows=k49_spectra(D,tj,C)
rows=cell(0,17); bands=[.15 .5;.25 .70;.5 5;5 30;300 700];
wins=[.3 3;.3 10;10 15;15 30;25 30];
for si=1:numel(D)
    s=D(si);
    if si==1, names={'Vpu_RMS','ESS1_Fout_Hz','QbiasState'};
    elseif si==2, names={'Itrack','Vq_error','Vconv_mag','Va_V'};
    else, names={'Itrack','Qmeas_pu','Vdq_mag'}; end
    for ni=1:numel(names)
        x=k49_signal(s,names{ni});
        for wi=1:size(wins,1)
            a=tj+wins(wi,1); b=tj+wins(wi,2); windowName=sprintf('%.2f_%.2fs',wins(wi,:));
            for mi=1:2
                if mi==1, method='STRICT_NATIVE_CONTIGUOUS'; else, method='SMALL_GAP_ESTIMATE_ONLY'; end
                [tt,xx,info]=k49_spectral_data(s.t,x,a,b,s.dt,mi,C);
                f=[]; power=[]; amp=[]; df=NaN; fs=1/s.dt; dur=0;
                if numel(tt)>=20
                    fs=1/median(diff(tt)); dur=tt(end)-tt(1);
                    [f,power,amp,df]=k49_psd(tt,xx);
                end
                for bi=1:size(bands,1)
                    lo=bands(bi,1); hi=bands(bi,2); peak=NaN; pa=NaN; br=NaN;
                    status=info.status;
                    if hi>=fs/2
                        status='UNRESOLVABLE_ABOVE_NYQUIST';
                    elseif isempty(f)
                        status='NO_USABLE_WINDOW';
                    else
                        selected=f>=lo & f<=hi;
                        if any(selected)
                            br=sqrt(sum(power(selected))*df);
                            [value,ii]=max(power(selected)); fb=f(selected); ab=amp(selected);
                            if isfinite(value)&&value>1e-20, peak=fb(ii); pa=ab(ii); else, br=0; end
                        end
                        if dur<2/lo, status=[status '_LESS_THAN_TWO_CYCLES']; end
                    end
                    rows(end+1,:)={s.name,names{ni},windowName,method,lo,hi,k49_first(tt)-tj,k49_last(tt)-tj,dur,fs,df, ...
                        info.maxGap,info.estimatedFraction,peak,pa,br,status}; %#ok<AGROW>
                end
            end
        end
    end
end
rows(end+1,:)={'SYSTEM','Vpu_RMS','FULL30','NOT_COMPUTED',.04,.06,0,30,30,NaN,NaN,NaN,NaN,NaN,NaN,NaN, ...
    '0.05HZ_HAS_ONLY_1.5_CYCLES_IN_30S_NO_PRECISE_MODAL_CLAIM'};
end

function [tt,xx,info]=k49_spectral_data(t,x,a,b,dt,method,C)
selected=t>=a&t<=b; t=t(selected); x=x(selected);
info=struct('status','NO_DATA','maxGap',NaN,'estimatedFraction',NaN); tt=[]; xx=[];
if numel(t)<2, return; end
info.maxGap=max(diff(t));
if method==1
    valid=isfinite(x); breaks=[true;diff(t)>1.5*dt+C.timeGridTol];
    starts=find(valid & ([true;~valid(1:end-1)]|breaks));
    ends=find(valid & ([~valid(2:end);true]|[breaks(2:end);true]));
    if isempty(starts), return; end
    [~,ix]=max(ends-starts); ids=starts(ix):ends(ix);
    tt=t(ids); xx=x(ids); info.estimatedFraction=0; info.status='STRICT_OBSERVED_SEGMENT';
    if numel(tt)>1 && any(abs(diff(tt)-dt)>C.timeGridTol)
        tt=[];xx=[];info.status='NONUNIFORM_NATIVE_SEGMENT';
    end
else
    good=isfinite(x); goodT=t(good); goodX=x(good);
    if numel(goodT)<2, return; end
    info.maxGap=max(diff(goodT));
    if info.maxGap>C.maxSmallGap+C.timeGridTol
        info.status='GAP_EXCEEDS_10MS_NO_ESTIMATE'; return;
    end
    if goodT(1)>a+2*dt || goodT(end)<b-2*dt
        info.status='WINDOW_ENDPOINT_MISSING'; return;
    end
    tt=(goodT(1):dt:goodT(end)).'; xx=interp1(goodT,goodX,tt,'linear',NaN);
    info.estimatedFraction=max(0,1-numel(goodT)/numel(tt));
    if info.estimatedFraction>.10 || any(~isfinite(xx))
        tt=[];xx=[];info.status='EXCESS_ESTIMATION_OR_INVALID'; return;
    end
    info.status='ESTIMATED_TREND_NOT_EVENT_EVIDENCE';
end
end

function [f,P,A,df]=k49_psd(t,x)
% 自写汉宁窗及单边功率谱；不使用额外工具箱、不补零伪造频率分辨率。
t=t(:); x=x(:); n=numel(x); fs=1/median(diff(t)); df=fs/n;
y=x-mean(x); q=t-t(1); den=sum((q-mean(q)).^2);
if den>0, y=y-sum((q-mean(q)).*y)/den*(q-mean(q)); end
w=.5-.5*cos(2*(4*atan(1))*(0:n-1)'/(n-1));
Y=fft(y.*w); bins=floor(n/2)+1;
P=abs(Y(1:bins)).^2/(fs*sum(w.^2)); A=2*abs(Y(1:bins))/sum(w);
if mod(n,2)==0
    if bins>2, P(2:bins-1)=2*P(2:bins-1); end
else
    P(2:bins)=2*P(2:bins);
end
f=(0:bins-1)'*df;
end

function series=k49_export_series(D,tj,C,outDir)
folder=fullfile(outDir,'17_TIMESERIES_10MS'); mkdir(folder);
series=repmat(struct('source','','t',[],'x',[],'names',{{}},'cn',{{}}),1,numel(D));
qt=(tj-.05:C.displayStep:tj+C.horizon).';
for si=1:numel(D)
    s=D(si);
    [y,estimated,span]=k49_sample(s.t,s.x,qt,C.maxSmallGap,'linear');
    series(si)=struct('source',s.name,'t',qt-tj,'x',y,'names',{s.names},'cn',{s.cn});
    header=[{'time_abs_s','after_J1_s','small_gap_estimated','bracketing_gap_s'},s.names];
    k49_numeric_csv(fullfile(folder,[s.name '.csv']),header,[qt,qt-tj,estimated,span,y]);
end
end

function k49_export_events(D,catalog,tj,C,outDir)
folder=fullfile(outDir,'18_EVENT_NATIVE_SAMPLES'); mkdir(folder);
for si=1:numel(D)
    s=D(si); blocks=cell(size(catalog,1),1);
    for ei=1:size(catalog,1)
        rel=catalog{ei,4}; te=tj+rel;
        m=s.t>=te-.10 & s.t<=te+.20 & s.t>=tj-.25 & s.t<=tj+C.horizon;
        tt=s.t(m); n=numel(tt);
        blocks{ei}=[repmat(catalog{ei,1},n,1),tt,tt-tj,tt-te,s.x(m,:)];
    end
    data=cat(1,blocks{:});
    k49_numeric_csv(fullfile(folder,[s.name '.csv']), ...
        [{'event_id','time_abs_s','after_J1_s','after_event_s'},s.names],data);
end
end

function [y,estimated,span]=k49_sample(t,x,qt,tolerance,method)
% 批量采样：缺样保持NaN，禁止用零填缺失的设备量。
t=t(:); qt=qt(:);
if size(x,1)~=numel(t), error('K49:ResampleShape','采样输入行数不符。'); end
y=nan(numel(qt),size(x,2)); estimated=nan(numel(qt),1); span=estimated;
if numel(t)<2, return; end
if strcmp(method,'nearest')
    ix=interp1(t,(1:numel(t))',qt,'nearest',NaN); good=isfinite(ix);
    pos=find(good); ii=round(ix(good)); distances=abs(t(ii)-qt(good));
    allowed=distances<=.55*tolerance+1e-10; pos=pos(allowed); ii=ii(allowed);
    y(pos,:)=x(ii,:); estimated(pos)=0; span(pos)=abs(t(ii)-qt(pos));
else
    ix=interp1(t,(1:numel(t))',qt,'previous',NaN); good=isfinite(ix);
    pos=find(good); left=round(ix(good)); right=min(numel(t),left+1);
    width=t(right)-t(left); exact=abs(qt(pos)-t(left))<1e-10;
    allowed=exact | (width>0 & width<=tolerance+1e-10);
    pos=pos(allowed); left=left(allowed); right=right(allowed); width=width(allowed); exact=exact(allowed);
    ratio=zeros(numel(pos),1); ratio(~exact)=(qt(pos(~exact))-t(left(~exact)))./width(~exact);
    y(pos,:)=x(left,:)+(x(right,:)-x(left,:)).*ratio;
    y(pos(exact),:)=x(left(exact),:);
    span(pos)=width; span(pos(exact))=0;
    native=median(diff(t)); estimated(pos)=double(width>1.5*native+1e-10 & ~exact);
end
end

function B=k49_compare(RA,DA,RB,DB,C,outDir)
folder=fullfile(outDir,'AB_COMPARISON'); mkdir(folder);
conditions=cell(0,5);
conditions(end+1,:)={'kind',RA.kind,RB.kind,double(strcmp(RA.kind,'FULL30')&&strcmp(RB.kind,'QBIAS0_30')),'A全功能、B中央零偏置'};
identityA=k49_identity_consistent(RA);identityB=k49_identity_consistent(RB);
identityOK=identityA&&identityB;
conditions(end+1,:)={'runtime_identity_consistent',identityA,identityB,double(identityOK),'增益三处读回、步长、本地电压环参数及采集完成状态不得相互矛盾'};
fpOK=~isempty(RA.fingerprint)&&strcmp(RA.fingerprint,RB.fingerprint);
conditions(end+1,:)={'model_fingerprint',RA.fingerprint,RB.fingerprint,double(fpOK),'磁盘模型语义指纹一致；不冒充目标二进制身份'};
conditions(end+1,:)={'duration_s',k49_get(RA.manifest,'duration_s',NaN),k49_get(RB.manifest,'duration_s',NaN), ...
    double(k49_number(k49_get(RA.manifest,'duration_s',NaN))==30&&k49_number(k49_get(RB.manifest,'duration_s',NaN))==30),'两轮离网后计划长度相同'};
ash=k49_get(RA.meta.model_audit,'source_sha256',''); bsh=k49_get(RB.meta.model_audit,'source_sha256','');
sourceOK=~isempty(ash)&&strcmp(ash,bsh);
conditions(end+1,:)={'source_model_sha256',ash,bsh,double(sourceOK),'运行前审计的模型文件内容一致'};
base=k49_get(RB.manifest,'baseline_reference','');
linkOK=~isempty(base)&&strcmpi(strrep(base,'\','/'),strrep(RA.originalRoot,'\','/'));
conditions(end+1,:)={'B_recorded_A_reference',RA.originalRoot,base,double(linkOK),'用原始清单身份核对B所引用的A，允许文件包移位但不任意换对照'};
pa=RA.params; pb=RB.params; keys=unique([pa(:,1);pb(:,1)]); diffRows=cell(0,6); changed={};
paramOK=~isempty(pa)&&~isempty(pb);
for ki=1:numel(keys)
    key=keys{ki}; ia=find(strcmp(pa(:,1),key)); ib=find(strcmp(pb(:,1),key));
    va=NaN; vb=NaN;
    if numel(ia)==1, va=pa{ia,2}; end
    if numel(ib)==1, vb=pb{ib,2}; end
    equal=k49_value_equal(va,vb,C.compareParamTol);
    if numel(ia)~=1 || numel(ib)~=1, equal=false; end
    isAllowed=strcmp(key,'final/central/ki_qbias');
    if ~equal
        changed{end+1}=key; %#ok<AGROW>
        if ~isAllowed || ~k49_value_equal(va,.3,C.compareParamTol) || ~k49_value_equal(vb,0,C.compareParamTol)
            paramOK=false;
        end
    end
    diffRows(end+1,:)={key,k49_cellvalue(va),k49_cellvalue(vb),double(~equal),double(isAllowed),'保留JSON原键名，未将斜杠键转成可能冲突的结构体字段'}; %#ok<AGROW>
end
paramOK=paramOK&&numel(changed)==1&&strcmp(changed{1},'final/central/ki_qbias');
conditions(end+1,:)={'only_expected_parameter_changed',numel(pa),numel(pb),double(paramOK),'只有final/central/ki_qbias从0.30变0，其他已记录参数一致'};
zeroRows=RB.fullRecordIsolation;
zeroOK=~isempty(zeroRows)&&all(strcmp(zeroRows(:,8),'ZERO_ON_ALL_RECORDED_SAMPLES'));
conditions(end+1,:)={'recorded_zero_bias', 'A无需为零',zeroOK,double(zeroOK),'B中央状态、请求和施加参考逐记录样本验证；不把缺样当零'};
conditions(end+1,:)={'five_family_coverage',RA.allRequiredDataPresent,RB.allRequiredDataPresent,double(RA.allRequiredDataPresent&&RB.allRequiredDataPresent),'30秒数据覆盖与端点；缺口表另列'};
endA=k49_mode_comparison_end(DA,RA.j1,C);endB=k49_mode_comparison_end(DB,RB.j1,C);
conditions(end+1,:)={'unchanged_observed_island_modes_until_s',endA,endB,double(endA>=30&&endB>=30),'实际重合闸或已记录模式变化之后不再作原六机严格比较'};
k49_csv(fullfile(folder,'20_AB_CONDITIONS.csv'),{'Item','A','B','Satisfied','Meaning'},conditions);
k49_csv(fullfile(folder,'21_AB_PARAMETERS.csv'),{'OriginalKey','A','B','Changed','AllowedDifference','Meaning'},diffRows);
work=k49_workpoint_compare(RA,RB);
k49_csv(fullfile(folder,'22_AB_PREJ1_WORKPOINT.csv'),{'Field','A','B','BminusA','Meaning'},work);
[early,earlyEnd,earlyOK]=k49_early_compare(DA,DB,RA.j1,RB.j1,C);
k49_csv(fullfile(folder,'23_AB_EARLY_REPRODUCTION.csv'),{'Source','Signal','EndAfterJ1_s','ValidPairs','RequestedPairs','ValidFraction','RMS_BminusA','MaxAbs_BminusA','Amean','Bmean','ReferenceTolerance','DiagnosticScreen','Meaning'},early);
metricDiff=cell(0,17);
for ri=1:size(RA.metrics,1)
    source=RA.metrics{ri,1}; signal=RA.metrics{ri,2}; win=RA.metrics{ri,4};
    a=k49_metric(RA.metrics,source,signal,win); b=k49_metric(RB.metrics,source,signal,win);
    metricDiff(end+1,:)={source,signal,win,a(1),b(1),b(1)-a(1),a(2),b(2),a(3),b(3),a(4),b(4),a(5),b(5),a(11),b(11),'同相对时间窗口；差异本身不是根因判定'}; %#ok<AGROW>
end
k49_csv(fullfile(folder,'24_AB_ALL_WINDOW_DIFFERENCES.csv'),{'Source','Signal','Window','Amean','Bmean','DeltaMean','Amin','Bmin','Amax','Bmax','Astd','Bstd','Aslope','Bslope','AKnownFraction','BKnownFraction','Meaning'},metricDiff);
events=cell(0,12);
for ei=1:size(RA.eventStats,1)
    a=RA.eventStats(ei,:);
    ix=find(strcmp(RB.eventStats(:,1),a{1})&strcmp(RB.eventStats(:,2),a{2}));
    if numel(ix)~=1, continue; end
    b=RB.eventStats(ix,:);
    events(end+1,:)={a{1},a{2},a{4},b{4},a{5},b{5},a{6},b{6},a{3},b{3},a{7},b{7}}; %#ok<AGROW>
end
k49_csv(fullfile(folder,'25_AB_EVENT_DIFFERENCES.csv'),{'Source','Event','Afirst_s','Bfirst_s','AtotalConfirmed_s','BtotalConfirmed_s','Alongest_s','Blongest_s','Aepisodes','Bepisodes','Acount100ms','Bcount100ms'},events);
overlayDir=fullfile(folder,'26_AB_OVERLAY_10MS'); mkdir(overlayDir);
for si=1:numel(RA.series)
    a=RA.series(si); b=RB.series(si);
    if ~isequal(a.names,b.names) || numel(a.t)~=numel(b.t)||max(abs(a.t-b.t))>1e-8
        error('K49:CompareSchema','A/B比较字段或展示时间网格不一致，拒绝错位相减。');
    end
    hdr={'after_J1_s'};
    for ci=1:numel(a.names), hdr{end+1}=['A_' a.names{ci}]; end %#ok<AGROW>
    for ci=1:numel(a.names), hdr{end+1}=['B_' a.names{ci}]; end %#ok<AGROW>
    k49_numeric_csv(fullfile(overlayDir,[a.source '.csv']),hdr,[a.t,a.x,b.x]);
end
B=struct(); B.configurationMatched=fpOK&&sourceOK&&linkOK&&paramOK&&identityOK;
B.strictObservableComparisonEnd_s=min(endA,endB);B.observedModesUnchanged=(endA>=30&&endB>=30);
B.zeroOnRecordedSamples=zeroOK; B.earlyWindowEnd_s=earlyEnd; B.earlyDiagnosticMatched=earlyOK;
B.dataCovered=RA.allRequiredDataPresent&&RB.allRequiredDataPresent;
B.aManifestSHA256=RA.manifestSHA256; B.bManifestSHA256=RB.manifestSHA256;
B.aInput=RA.input; B.bInput=RB.input;
if ~B.configurationMatched, B.status='CONFIGURATION_COMPARISON_NOT_ESTABLISHED';
elseif ~zeroOK, B.status='REQUEST_OR_APPLIED_BIAS_NOT_CONFIRMED_ZERO';
elseif ~B.observedModesUnchanged, B.status='MODE_OR_TOPOLOGY_CHANGED_INTERPRET_ONLY_BEFORE_CHANGE';
elseif ~B.dataCovered, B.status='DATA_GAPS_OR_COVERAGE_LIMIT_COMPARISON';
elseif ~earlyOK, B.status='EARLY_RESPONSE_REPRODUCTION_REQUIRES_REVIEW';
else, B.status='OBSERVED_CONDITIONS_SUPPORT_COMPARISON_NOT_UNIQUE_CAUSAL_PROOF'; end
B.meaning='比较中央新增作用对过渡和尾段的总影响；取消补偿引起的稳态改变不能直接归罪储能1，过冲减小也不证明该功能应删除。';
B.parametersChanged=changed;
k49_comparison_summary(B,RA,RB,folder,C);
if C.makePlots
    try
        a=RA.series(1); b=RB.series(1); ia=find(strcmp(a.names,'Vpu_RMS'));
        f=figure('Visible','off'); guard=onCleanup(@()close(f)); %#ok<NASGU>
        plot(a.t,a.x(:,ia),b.t,b.x(:,ia)); grid on;
        xlabel('实际开断后时间（秒）');ylabel('母线电压（标幺）');
        legend({'A：全部功能','B：仅中央新增偏置为零'},'Location','best');
        title('同条件对照：过渡与后期分别评价');
        saveas(f,fullfile(folder,'AB_voltage.png')); clear guard;
    catch err
        k49_text(fullfile(folder,'PLOT_WARNING.txt'),err.message);
    end
end
end

function rows=k49_workpoint_compare(A,B)
a=k49_get(A.meta.prej1,'snapshot',struct()); b=k49_get(B.meta.prej1,'snapshot',struct());
keys={'Ppcc_kW','Qpcc_kvar','Vab_rms_true_V','Freq_Hz','F24_f_eff','F24_v_eff', ...
    'F25_pre_bias_d','F25_pre_bias_q','F25_applied_d','F25_applied_q','ESS1_final_pref'};
for di=1:6, keys{end+1}=['Pcmd_' num2str(di)]; keys{end+1}=['Qcmd_' num2str(di)]; end
keys=[keys,{'GridOn_1','GridOn_2','GridOn_3_ESS1','GridOn_4','GridOn_5','GridOn_6'}];
rows=cell(0,5);
for ki=1:numel(keys)
    x=k49_number(k49_get(a,keys{ki},NaN)); y=k49_number(k49_get(b,keys{ki},NaN));
    rows(end+1,:)={keys{ki},x,y,y-x,'开断前真实工作点；缺项为NaN，不伪装为相等'}; %#ok<AGROW>
end
end

function [rows,edge,ok]=k49_early_compare(A,B,ja,jb,C)
ag=A(1); state=abs(ag.x(:,41)); i=find(ag.t>=ja & state>C.isoTol & isfinite(state),1,'first');
edge=C.earlyEnd;
if ~isempty(i), edge=min(edge,ag.t(i)-ja-2*ag.dt); end
edge=max(0,edge); rows=cell(0,13); ok=(edge>=.2);
qt=(0:.001:edge).';
for si=1:numel(A)
    if si==1, names={'Vpu_RMS','ESS1_Fout_Hz','dPPrimary_pu','dPSecondary_pu','PV1_Pmax_kW','PV2_Pmax_kW'};
    elseif si==2, names={'Iref_Final_d','Iref_Final_q','VPI_Raw1','VPI_Raw2','F25_FF_Applied_d','F25_FF_Applied_q'};
    else, names={'FinalIref_d','FinalIref_q','Pmeas_pu','Qmeas_pu','TotalSupport_d','TotalSupport_q'}; end
    for ni=1:numel(names)
        x=k49_sample(A(si).t-ja,k49_signal(A(si),names{ni}),qt,A(si).dt,'nearest');
        y=k49_sample(B(si).t-jb,k49_signal(B(si),names{ni}),qt,B(si).dt,'nearest');
        good=isfinite(x)&isfinite(y); err=y(good)-x(good);
        tol=C.earlyIRmsReference;
        if strcmp(names{ni},'Vpu_RMS'), tol=C.earlyVRmsReference; end
        if strcmp(names{ni},'ESS1_Fout_Hz'), tol=C.earlyFRmsReference; end
        if contains(names{ni},'Pmax'), tol=.01; end
        rm=k49_rms(err); frac=nnz(good)/max(1,numel(qt));
        matched=isfinite(rm)&&rm<=tol&&frac>=C.coverageReference;
        ok=ok&&matched;
        rows(end+1,:)={A(si).name,names{ni},edge,nnz(good),numel(qt),frac,rm,k49_max(abs(err)),k49_mean(x(good)),k49_mean(y(good)),tol, ...
            k49_bool_status(matched),'工程对照接近性提示，不是正式电气保护定值；差异需要结合初始化解释'}; %#ok<AGROW>
    end
end
end

function k49_comparison_summary(B,A,R,folder,C) %#ok<INUSD>
fid=fopen(fullfile(folder,'27_AB_READ_FIRST.md'),'w','n','UTF-8');
if fid<0, error('K49:Write','无法创建对照说明。'); end
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 两轮30秒结果的对照说明\n\n');
fprintf(fid,'本文件不给某个参数自动定罪，不自动宣布物理因果闭合。\n\n');
fprintf(fid,'**配置可比：%s；B的已记录偏置量为零：%s；早期响应接近性检查：%s。**\n\n', ...
    k49_yesno(B.configurationMatched),k49_yesno(B.zeroOnRecordedSamples),k49_yesno(B.earlyDiagnosticMatched));
fprintf(fid,'早期比较截止至开断后%.6f秒；若A偏置更早变化，则自动缩短比较窗。\n\n',B.earlyWindowEnd_s);
fprintf(fid,'根据已记录拓扑与模式，可严格比较的时段最多到开断后%.6f秒；之后的曲线仍导出，但不能假装工况未改变。\n\n',B.strictObservableComparisonEnd_s);
fprintf(fid,'先查看20、21、22、23表，不满足条件时，只保留描述性差异，不将差异全部归因于中央偏置。\n\n');
fprintf(fid,'## 过渡与尾段分开看\n\n');
a=k49_metric(A.metrics,'SYSTEM','Vpu_RMS','FULL30'); b=k49_metric(R.metrics,'SYSTEM','Vpu_RMS','FULL30');
fprintf(fid,'全30秒电压范围：A为%.6f～%.6f标幺；B为%.6f～%.6f标幺。\n\n',a(2),a(3),b(2),b(3));
for w={'W12_15','W15_20','W20_25','W25_30'}
    av=k49_metric(A.metrics,'SYSTEM','Vpu_RMS',w{1}); bv=k49_metric(R.metrics,'SYSTEM','Vpu_RMS',w{1});
    fprintf(fid,'窗口%s（名称中的数字为开断后的起止秒数）：电压均值A=%.6f、B=%.6f；标准差A=%.6g、B=%.6g；趋势A=%+.6g、B=%+.6g标幺/秒。\n\n',w{1},av(1),bv(1),av(4),bv(4),av(5),bv(5));
end
fprintf(fid,['解释约束：\n\n' ...
'取消中央偏置后末段偏低，不单独证明储能1有错；过冲减小，不证明应永久删除中央功能。\n\n' ...
'若过渡改善但尾段变差，应分别研究动态速度与非零工作点恢复；若波动仍在，说明没有这项中央作用时也能出现该现象，不自动锁定0.02/0.14。\n\n' ...
'若实际拓扑、模式或资源条件变化，变化后的时间不再当作原六机同工况严格对照。\n\n' ...
'本次只给事件时序、全量指标差异和叠加曲线；具体控制修改仍需根据这些证据选择。\n']);
end

function k49_write_summary(R,outDir,C)
fid=fopen(fullfile(outDir,'00_READ_FIRST.md'),'w','n','UTF-8');
if fid<0, error('K49:Write','无法创建计算摘要。'); end
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# K26_K50两处坐标修复：30秒计划孤岛计算结果\n\n');
fprintf(fid,'运行类型：%s；experiment_kind=%s。\n\n',R.kind,R.experimentKind);
fprintf(fid,'源模型SHA256：%s。\n\n',R.sourceModelSHA256);
fprintf(fid,'本轮目标是评价两处坐标逻辑修复后的六机响应，不把结果预设为稳定，也不新增其它控制器解释。\n\n');
fprintf(fid,'**计算完成不等于整次电气通过。** 过渡、末段、执行裕度、数据完整性分开报告。\n\n');
fprintf(fid,'## 数据与事件\n\n');
fprintf(fid,'真实开断右侧样本时刻：%.7f秒；开断定位区间：%.7f～%.7f秒。\n\n',R.j1,R.edge.leftSample_s,R.edge.rightSample_s);
fprintf(fid,'第三阶段首次记录时刻：%.7f秒；相对开断延时：%.7f秒。\n\n',R.stage3,R.stage3-R.j1);
fprintf(fid,'五组在本分析数据覆盖参考下均达到30秒：%s。具体缺口和各字段非有限值见03～05表。\n\n',k49_yesno(R.allRequiredDataPresent));
fprintf(fid,'## 末段表现\n\n');
fprintf(fid,'这里沿用已讨论的电压均值%.2f～%.2f标幺、构网频率均值%.1f～%.1f赫兹作观察，不加严为±2%%。\n\n',C.referenceVBand,C.referenceFBand);
for wi=1:size(R.tail,1)
    r=R.tail(wi,:);
    fprintf(fid,'窗口%s：电压均值%.6f，范围%.6f～%.6f，标准差%.6g，趋势%+.6g标幺/秒；频率均值%.6f赫兹；中央偏置从%.6g变化到%.6g。\n\n', ...
        r{1},r{2},r{3},r{4},r{5},r{6},r{7},r{10},r{11});
end
if strcmp(R.tailStatus,'TAIL_MEANS_WITHIN_REFERENCE_BANDS_REVIEW_DYNAMICS')
    fprintf(fid,'15～30秒的三个尾段电压/频率均值都在观察范围内。仍应结合波动、趋势、实际电流和调制状态确认是否反复恶化，不据此外推永久稳定。\n\n');
elseif strcmp(R.tailStatus,'TAIL_DATA_LIMITED')
    fprintf(fid,'尾段数据有缺失或非有限，不能用剩余有限值冒充完整30秒表现。\n\n');
else
    fprintf(fid,'至少一个尾段电压/频率均值在观察范围外。请分辨偏低/偏高、振荡增长与缺少稳态补偿，不自动归因于某一增益。\n\n');
end
fprintf(fid,'## 过渡不是单点否决\n\n');
v=k49_metric(R.metrics,'SYSTEM','Vpu_RMS','FULL30');
fprintf(fid,'全30秒电压范围：%.6f～%.6f标幺。08/09表列出越界次数、持续时间与未知边界；0.80/1.20及100毫秒仅作为历史诊断对照，不输出自动电气否决。\n\n',v(2),v(3));
fprintf(fid,'12表同时列出首次进入、连续1秒进入、最后一次持续停留，避免把初次进入当作不再反复。这些时间不是承诺设备耐受能力。\n\n');
fprintf(fid,'## 执行与中央作用\n\n');
fprintf(fid,'07表覆盖所有原始字段及推导量，包括电流参考/实测、局部支撑、无功请求/参考施加、储能1电压误差、原始电压环输出、F24/F25及后期限幅。\n\n');
fprintf(fid,'13表仅在五台均有效对齐时合计；缺样不补零。14表核验从初始化开始的零偏置，不把缺样或非有限当作零。\n\n');
if strcmp(R.kind,'QBIAS0_30')
    zero=all(strcmp(R.fullRecordIsolation(:,8),'ZERO_ON_ALL_RECORDED_SAMPLES'));
    fprintf(fid,'B的中央状态、请求和施加参考在全部已记录样本上符合零偏置：%s。该结论不覆盖记录间隙内未采集的脉冲。\n\n',k49_yesno(zero));
end
fprintf(fid,'## 曲线和频谱\n\n');
fprintf(fid,'17目录为10毫秒展示表；18目录为关键事件附近原速率样本，不插值。展示表的原始采样间隙另有标志，不冒充高分辨率实测。\n\n');
fprintf(fid,'16表覆盖0.15～0.5、**0.25～0.70（本轮历史低频重点）**、0.5～5、5～30和可分辨的300～700赫兹；区分连续原始窗与小缺口估计。频率峰值仅是有限窗频谱证据，不等于系统特征值。30秒内0.05赫兹仅1.5个周期，不宣称精确模态识别。\n\n');
fprintf(fid,'## 本轮坐标修复的阅读顺序\n\n');
fprintf(fid,'先看07表中SYSTEM/Vpu_RMS与SYSTEM/ESS1_Fout_Hz的W1_3、W3_6、W6_10、W10_15、W15_20、W20_25、W25_30，再看16表0.25～0.70赫兹。若前期减弱但20～30秒重新增大，不能因中间暂静而宣布稳定。\n\n');
fprintf(fid,'随后按RAW→APPLIED→RESPONSE查看五台GFL的FinalIref/Support/Qsec与实测IdIq/PQ，并同时看ESS1 Current/Voltage执行压力；因果判断采用首次分化时刻，不采用最大峰值时刻。\n\n');
fprintf(fid,'本轮如果仍有振荡，只说明两处坐标缺陷并非全部根因；不要在同一轮结果上立即同时修改ESS1 Voltage PI、slow-q、P/f Secondary、q-bias或EV欠压逻辑。\n\n');
fprintf(fid,'## 不可观测边界\n\n');
fprintf(fid,'新电流适配器内部23维诊断、完整执行残差及积分器内部状态未在本构建完整记录，不能凭计算恢复。储能1调制需求的重构明确假定直流1000伏和交流480伏基准，不当成直接记录的调制度。\n\n');
fprintf(fid,'内部构网频率与三相电压估计频率分别报告；后者遇低压/记录缺口无效，不能用无效零交越自动定罪。实时超时和外部板卡闭环资格不由本计算器自动认定。\n\n');
if isfield(R,'comparison') && ~strcmp(R.comparison.status,'NOT_APPLICABLE_A')
    fprintf(fid,'A/B对照：见AB_COMPARISON目录。没有选择A或条件不成立时，不自动输出干净因果结论。\n\n');
end
for wi=1:numel(R.warnings), fprintf(fid,'注意：%s\n\n',R.warnings{wi}); end
end

function small=k49_small_result(R)
fields={'version','kind','experimentKind','sourceModelSHA256','input','manifestSHA256','fingerprint','dataSource','modelRoot','j1','edge','stage3','captureComplete', ...
    'allRequiredDataPresent','tailStatus','tail','identityRows','fullRecordIsolation','bookkeeping','returnBands','comparison','warnings','status'};
small=struct();
for fi=1:numel(fields)
    if isfield(R,fields{fi}), small.(fields{fi})=R.(fields{fi}); end
end
small.electricalAcceptance='NOT_AUTOMATICALLY_ASSIGNED';
small.interpretation='末段宽范围、过渡品质、执行裕度和数据可用性分开；阈值不擅自升级为项目强制标准。';
end

function pairs=k49_parameter_pairs(path)
% JSON原键含斜杠。jsondecode会改字段名，因此逐个保留原始键再解析值。
% 运行脚本产出的是扁平数值参数字典；遇到新嵌套结构明确拒绝，不默默丢键。
txt=k49_read_text(path);
jsondecode(txt); % 只验证JSON语法，不使用被改名的结构体字段。
pattern='"((?:[^"\\]|\\.)*)"\s*:\s*(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|"(?:[^"\\]|\\.)*"|\[[^\]]*\])';
tokens=regexp(txt,pattern,'tokens');
keyCount=numel(regexp(txt,'"(?:[^"\\]|\\.)*"\s*:','match'));
if numel(tokens)~=keyCount, error('K49:ParameterSchema','参数清单不是预期的扁平值字典；拒绝遗漏部分参数。'); end
pairs=cell(numel(tokens),2);
for i=1:numel(tokens)
    key=jsondecode(['"' tokens{i}{1} '"']); value=jsondecode(tokens{i}{2});
    if ~(isnumeric(value)||islogical(value)) || isempty(value) || any(~isfinite(double(value(:))))
        error('K49:ParameterValue','参数%s缺少可核验的有限数值。',key);
    end
    pairs(i,:)={key,double(value)};
end
if size(pairs,1)~=numel(unique(pairs(:,1))), error('K49:DuplicateParameter','参数原始键重名。'); end
end

function v=k49_pair_value(pairs,key)
i=find(strcmp(pairs(:,1),key));
if numel(i)==1, v=k49_number(pairs{i,2}); else, v=NaN; end
end

function ok=k49_value_equal(a,b,tol)
ok=isnumeric(a)&&isnumeric(b)&&isequal(size(a),size(b))&&~isempty(a)&&all(isfinite(a(:)))&&all(isfinite(b(:)))&&all(abs(a(:)-b(:))<=tol);
end

function v=k49_get(s,key,default)
if isstruct(s)&&isscalar(s)&&isfield(s,key)&&~isempty(s.(key)), v=s.(key); else, v=default; end
end

function v=k49_number(x)
if isnumeric(x)&&isscalar(x), v=double(x);
elseif islogical(x)&&isscalar(x), v=double(x);
elseif ischar(x)||(isstring(x)&&isscalar(x)), v=str2double(char(x));
else, v=NaN; end
end

function J=k49_json_read(path)
J=jsondecode(k49_read_text(path));
end

function txt=k49_read_text(path)
fid=fopen(path,'r','n','UTF-8');
if fid<0, error('K49:Read','无法读取：%s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
txt=fscanf(fid,'%c');
if ~isempty(txt)&&double(txt(1))==65279, txt=txt(2:end); end
end

function k49_json_write(path,value)
k49_text(path,jsonencode(value));
end

function cells=k49_cellstruct(value)
if isempty(value), cells={};
elseif isstruct(value)
    cells=cell(numel(value),1);
    for vi=1:numel(value),cells{vi}=value(vi);end
elseif iscell(value)&&all(cellfun(@isstruct,value(:))), cells=value(:);
else, error('K49:JSONRecords','记录列表必须是对象数组，不能猜测其他结构。'); end
end

function hash=k49_sha(path)
if ~usejava('jvm'), error('K49:Java','文件内容校验需要MATLAB自带Java，不能静默跳过校验。'); end
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
fid=fopen(path,'rb'); if fid<0, error('K49:HashRead','无法读取文件校验：%s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true
    bytes=fread(fid,1024*1024,'*uint8');
    if isempty(bytes), break; end
    md.update(typecast(bytes(:),'int8'));
end
raw=typecast(md.digest(),'uint8'); hash=lower(reshape(dec2hex(raw,2).',1,[]));
end

function k49_csv(path,headers,rows)
if size(rows,2)~=numel(headers), error('K49:CSVWidth','%s表头%d列，内容%d列。',path,numel(headers),size(rows,2)); end
fid=fopen(path,'w','n','UTF-8'); if fid<0, error('K49:Write','无法写文件：%s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
for ri=0:size(rows,1)
    if ri==0, row=headers; else, row=rows(ri,:); end
    parts=cell(1,numel(headers));
    for ci=1:numel(parts)
        x=row{ci};
        if isnumeric(x)&&isscalar(x), parts{ci}=sprintf('%.17g',double(x));
        elseif islogical(x)&&isscalar(x), parts{ci}=sprintf('%d',x);
        else, parts{ci}=['"' strrep(k49_cellvalue(x),'"','""') '"']; end
    end
    fprintf(fid,'%s\n',strjoin(parts,','));
end
end

function k49_numeric_csv(path,headers,X)
if size(X,2)~=numel(headers), error('K49:NumericCSV','数值表宽度不符：%s',path); end
fid=fopen(path,'w','n','UTF-8'); if fid<0, error('K49:Write','无法写文件：%s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
escaped=cellfun(@(x)['"' strrep(x,'"','""') '"'],headers,'UniformOutput',false);
fprintf(fid,'%s\n',strjoin(escaped,','));
fmt=[repmat('%.12g,',1,size(X,2)-1) '%.12g\n'];
for start=1:4000:size(X,1)
    last=min(size(X,1),start+3999); fprintf(fid,fmt,X(start:last,:).');
end
end

function txt=k49_cellvalue(x)
if ischar(x), txt=x;
elseif isstring(x), txt=char(strjoin(x,','));
elseif isnumeric(x)||islogical(x), txt=mat2str(x,17);
elseif isempty(x), txt='';
else, txt=jsonencode(x); end
end

function k49_text(path,txt)
fid=fopen(path,'w','n','UTF-8'); if fid<0, error('K49:Write','无法写文本：%s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',txt);
end

function files=k49_find_named(root,name)
files={}; list=dir(root);
for i=1:numel(list)
    n=list(i).name;
    if strcmp(n,'.')||strcmp(n,'..'), continue; end
    p=fullfile(root,n);
    if list(i).isdir
        if any(strcmpi(n,{'RAW','PREVIOUS_RAW','.git'}))||(startsWith(n,'K49_CALC_')||startsWith(n,'K50_COORDPATCH_CALC_')), continue; end
        files=[files,k49_find_named(p,name)]; %#ok<AGROW>
    elseif strcmpi(n,name)
        files{end+1}=p; %#ok<AGROW>
    end
end
end

function k49_copy_metadata(root,out)
dest=fullfile(out,'SOURCE_METADATA'); mkdir(dest);
names={'manifest.json','raw_archive.json','model_audit.json','intervention.json','prej1_parameters.json','prej1.json', ...
    'stage3.json','baseline_parameter_diff.json','baseline_workpoint_diff.json','telemetry_paths.json','host_summary.json', ...
    'samples.jsonl','pause_clock.jsonl','run.txt','failure.json'};
for i=1:numel(names)
    f=fullfile(root,names{i}); if isfile(f), copyfile(f,fullfile(dest,names{i})); end
end
end

function k49_pack(root,path)
files=k49_all_files(root,'');
if isempty(files), error('K49:EmptyOutput','没有可打包的计算结果。'); end
zip(path,files,root);
if ~isfile(path), error('K49:ZipWrite','结果压缩文件未创建：%s',path); end
end

function files=k49_all_files(root,relative)
list=dir(fullfile(root,relative)); files={};
for i=1:numel(list)
    name=list(i).name;
    if strcmp(name,'.')||strcmp(name,'..'), continue; end
    rel=fullfile(relative,name);
    if list(i).isdir, files=[files,k49_all_files(root,rel)]; else, files{end+1}=rel; end %#ok<AGROW>
end
end

function k49_remove_temp(path)
try, if isfolder(path), rmdir(path,'s'); end, catch, end
end

function b=k49_basename(path)
[~,name,ext]=fileparts(path); b=[name ext];
end

function s=k49_nonce()
[~,s]=fileparts(tempname);
end

function v=k49_first(x)
if isempty(x), v=NaN; else, v=x(1); end
end

function v=k49_last(x)
if isempty(x), v=NaN; else, v=x(end); end
end

function v=k49_max(x)
x=x(isfinite(x)); if isempty(x), v=NaN; else, v=max(x); end
end

function v=k49_mean(x)
x=x(isfinite(x)); if isempty(x), v=NaN; else, v=mean(x); end
end

function v=k49_rms(x)
x=x(isfinite(x)); if isempty(x), v=NaN; else, v=sqrt(mean(x.^2)); end
end

function v=k49_fraction(x)
if isempty(x), v=NaN; else, v=mean(double(x)); end
end

function s=k49_bool_status(b)
if b, s='SATISFIED'; else, s='NOT_CONFIRMED'; end
end

function s=k49_yesno(b)
if b, s='是'; else, s='否或证据不足'; end
end

function y=k49_derivative(t,x,dt)
t=t(:);x=x(:);y=nan(size(x));d=diff(t); v=isfinite(x(1:end-1))&isfinite(x(2:end))&d>0&d<=1.5*dt+1e-10;
q=diff(x)./d; q(~v)=NaN; y(2:end)=q;
end

function f=k49_phase_frequency(t,phase,dt,window)
t=t(:); phase=phase(:); f=nan(size(t)); valid=isfinite(phase)&isfinite(t); broken=[true;diff(t)>1.5*dt+1e-10];
a=find(valid&([true;~valid(1:end-1)]|broken)); b=find(valid&([~valid(2:end);true]|[broken(2:end);true]));
lag=max(1,round(window/dt)); piValue=4*atan(1);
for i=1:numel(a)
    ids=a(i):b(i);
    if numel(ids)<=lag, continue; end
    p=unwrap(phase(ids)); tt=t(ids);
    f(ids(lag+1:end))=(p(lag+1:end)-p(1:end-lag))./(2*piValue*(tt(lag+1:end)-tt(1:end-lag)));
end
end

function k49_plots(series,tail,outDir) %#ok<INUSD>
folder=fullfile(outDir,'FIGURES');mkdir(folder);
s=series(1);
spec={'Vpu_RMS','母线电压（标幺）','voltage';'ESS1_Fout_Hz','构网频率（赫兹）','frequency';'QbiasState','中央新增无功偏置状态','central_bias'};
for i=1:size(spec,1)
    col=find(strcmp(s.names,spec{i,1}));
    f=figure('Visible','off'); guard=onCleanup(@()close(f)); %#ok<NASGU>
    plot(s.t,s.x(:,col));grid on;xlabel('实际开断后时间（秒）');ylabel(spec{i,2});
    title('完整30秒：过渡与尾段分别观察');saveas(f,fullfile(folder,[spec{i,3} '.png']));clear guard;
end
f=figure('Visible','off');guard=onCleanup(@()close(f)); %#ok<NASGU>
hold on;labels={};
for si=2:numel(series)
    s=series(si);i=find(strcmp(s.names,'Itrack'));plot(s.t,s.x(:,i));cnLabels={'储能1','光伏1','光伏2','储能2','车辆1','车辆2'};labels{end+1}=cnLabels{si-1}; %#ok<AGROW>
end
hold off;grid on;xlabel('实际开断后时间（秒）');ylabel('最终参考与实测电流向量误差（标幺）');
legend(labels,'Location','best');title('六台电流执行误差');saveas(f,fullfile(folder,'current_tracking.png'));clear guard;
end

function S=k49_schema()
S.dnames = { ...
    'RawIdRef','RawIqRef','FinalIref_d','FinalIref_q', ...
    'IdMeas','IqMeas','VdRaw','VqRaw', ...
    'VdFF','VqFF','CurrentPI_d','CurrentPI_q', ...
    'Vconv_d','Vconv_q','ModIndex','Pmeas_pu', ...
    'Qmeas_pu','GammaP','PLL_Hz','Stage', ...
    'Vpu','VsupportRef_pu','GammaQ','PrefCmd_pu', ...
    'PrefAfterUV_pu','PrefEff_pu','QrefCmd_pu','QrefEff_pu', ...
    'TotalSupport_d','TotalSupport_q','Kslow','Kfast', ...
    'gP_commonLambda','gQ_commonLambda','CurrentLimit','FrameHold', ...
    'MasterF_Hz','VrefCmd_V','Vbp_d','Vbp_q', ...
    'SupportClip','RawModDemand','ModHeadroom','IqSecRequest_along_n', ...
    'IqSecApplied_along_n','QsecCapPos_along_n','QsecCapNeg_along_n','QsecClip'};
S.dcn = { ...
    '原功率环d电流参考','原功率环q电流参考（不等同最终基础无功状态）','实际最终d电流参考','实际最终q电流参考', ...
    '实测d电流','实测q电流','执行坐标中的d电压','执行坐标中的q电压', ...
    '最终d电压前馈','最终q电压前馈','新电流适配器d比例积分限幅输出（不是积分器状态）','新电流适配器q比例积分限幅输出（不是积分器状态）', ...
    '分量限幅后的d电压命令','分量限幅后的q电压命令','调制度记录','实测有功标幺', ...
    '实测无功标幺','上游有功渐入比例','设备原锁相环频率（非自动权威频率）','设备运行阶段回显', ...
    '本地电压幅值标幺','局部支撑电压参考标幺','上游无功渐入比例','有功命令标幺', ...
    '欠压处理后的有功参考','有效有功参考','原无功命令','有效无功参考', ...
    '总支撑d电流（含中央二次施加）','总支撑q电流（含中央二次施加）','慢前馈系数','快前馈系数', ...
    '最终基础向量共同缩放第一回显','同一个共同缩放的第二回显（非独立无功缩放）','最终电流限制状态','执行坐标保持请求', ...
    '主机频率参考','电压命令（伏）','带通d电压诊断','带通q电压诊断', ...
    '支撑限幅状态','分量限幅后且幅值限制前的调制需求','调制裕度','收到的二次无功方向请求', ...
    '实际施加的二次参考（不是实测无功电流）','正方向二次可用能力','负方向二次可用能力','二次参考限幅状态'};
S.gnames = { ...
    'MasterValid','dPPrimary_pu','dPSecondary_pu','Old_dVSecondary_pu', ...
    'HeadroomUp_PV1','HeadroomUp_PV2','HeadroomUp_ESS2','HeadroomUp_EV1', ...
    'HeadroomUp_EV2','HeadroomDown_PV1','HeadroomDown_PV2','HeadroomDown_ESS2', ...
    'HeadroomDown_EV1','HeadroomDown_EV2','Stage','FailCode', ...
    'FinalPref_PV1','FinalPref_PV2','FinalPref_ESS2','FinalPref_EV1', ...
    'FinalPref_EV2','Pmeas_PV1','Pmeas_PV2','Pmeas_ESS2', ...
    'Pmeas_EV1','Pmeas_EV2','J1Close','PCC_P_raw', ...
    'PCC_Q_raw','PCC_HostFreq_Hz','PCC_Vab_RMS_V','ESS1_Fout_Hz', ...
    'ESS1_Vout_pu','PV1_Pmax_kW','PV2_Pmax_kW','ESS1_SOC', ...
    'ESS2_SOC','Punit_kW','Vtarget_pu','FilteredVerror_pu', ...
    'QbiasState','QbiasReferenceApplied','CapPosTotal','CapNegTotal', ...
    'Integrating','AuthorityExhausted'};
S.gcn = { ...
    '中央主参考有效','一次有功调整总量','二次有功调整总量','旧二次电压调整（预期保持既有配置）', ...
    '光伏1有功上调能力','光伏2有功上调能力','储能2有功上调能力','车辆1有功上调能力', ...
    '车辆2有功上调能力','光伏1有功下调能力','光伏2有功下调能力','储能2有功下调能力', ...
    '车辆1有功下调能力','车辆2有功下调能力','系统阶段','中央失败码', ...
    '光伏1最终有功参考','光伏2最终有功参考','储能2最终有功参考','车辆1最终有功参考', ...
    '车辆2最终有功参考','光伏1实测有功','光伏2实测有功','储能2实测有功', ...
    '车辆1实测有功','车辆2实测有功','实际公共连接点断路器闭合状态','公共连接点有功（沿用原记录单位）', ...
    '公共连接点无功（沿用原记录单位）','公共连接点主机频率显示路径','公共连接点线电压有效值（伏）','储能1构网内部频率（赫兹）', ...
    '储能1内部电压目标标幺','光伏1可用有功上限（千瓦）','光伏2可用有功上限（千瓦）','储能1荷电状态', ...
    '储能2荷电状态','功率基准（千瓦）','中央电压目标标幺','滤波后的电压误差', ...
    '中央新增无功偏置状态','中央参考施加合计（不是实测无功）','正方向二次能力总量','负方向二次能力总量', ...
    '中央积分活跃状态','中央无功能力耗尽状态'};
S.enames = { ...
    'FrefInput_Hz','Fout_Hz','Theta_rad','PLL_Hz', ...
    'Va_V','Vb_V','Vc_V','P_DroopFeedback_pu', ...
    'Q_DroopFeedback_pu','DroopEnable','GridOn','Marker30030', ...
    'ThetaPLL_rad','ThetaTarget_rad','J1CloseReceived','SyncReset', ...
    'F20_Est_d','F20_Est_q','F20_Bias_d','F20_Bias_q', ...
    'F20_BiasValid','F20_Selected','F20_CaptureReq','F20_CaptureAck', ...
    'F22_ResetActive','F22_ResetAck','F22_TransferActive','F22_Blend', ...
    'F22_CapturedVPI_d','F22_CapturedVPI_q','F22_EffectiveVPI_d','F22_EffectiveVPI_q', ...
    'F22_SupportActive','F22_SupportEnvelope','F22_Support_d','F22_Support_q', ...
    'F23_Mean_d','F23_Mean_q','F23_EstStd','F23_Drift', ...
    'F23_Candidate_d','F23_Candidate_q','F23_Base_d','F23_Base_q', ...
    'F23_CandidateValid','F23_CommitActive','F23_CommitAck','F23_Applied_d', ...
    'F23_Applied_q','F23_Override','F23_Ramp','F23_Reject', ...
    'F23_Vmag','F23_WindowComplete','F24_EffectiveF_Hz','F24_EffectiveV_V', ...
    'F24_TargetF_Hz','F24_TargetV_V','F24_Ready','F24_State', ...
    'F24_ErrorF_Hz','F24_ErrorV_V','F24_Hold','F24_Release', ...
    'F24_HandoverValid','F24_Reject','F24_MeanF_Hz','F24_MeanV_V', ...
    'F24_MeanP_pu','F24_MeanQ_pu','F24_DriftF','F24_DriftV', ...
    'F24_SpanF','F24_SpanV','F24_WindowComplete','F24_CandidateValid', ...
    'F25_State','F25_PreReady','F25_PreCommitAck','F25_EdgeArmed', ...
    'F25_EdgeSeen','F25_EventMatch','F25_FastActive','F25_PostCandidateValid', ...
    'F25_CommitActive','F25_CommitAck','F25_Timeout','F25_Reject', ...
    'F25_SlewLimit','F25_MagnitudeLimit','F25_PreCandidate_d','F25_PreCandidate_q', ...
    'F25_PreBias_d','F25_PreBias_q','F25_PreStd','F25_PreDrift', ...
    'F25_FastTarget_d','F25_FastTarget_q','F25_FF_Applied_d','F25_FF_Applied_q', ...
    'F25_FastErrorMagnitude','F25_SlewLimitCopy','F25_MagnitudeLimitCopy','F25_PostMean_d', ...
    'F25_PostMean_q','F25_PostStd','F25_PostDrift','F25_PostCandidate_d', ...
    'F25_PostCandidate_q','F25_PostStableCount','F25_WindowComplete','F25_Ramp', ...
    'F25_FinalHold_d','F25_FinalHold_q','F25_PostValidCopy','VPI_Raw1', ...
    'VPI_Raw2','Iref_PreSaturation_d','Iref_PreSaturation_q','Iref_Final_d', ...
    'Iref_Final_q','Id_Meas','Iq_Meas','Vconv_d', ...
    'Vconv_q','Vq_Meas_pu','Vq_Ref_pu','Vd_Meas_pu'};
S.ecn = { ...
    '构网频率输入参考','构网内部频率','构网内部相角（弧度）','锁相显示频率', ...
    '实测A相电压','实测B相电压','实测C相电压','下垂反馈有功', ...
    '下垂反馈无功','下垂使能','跟网模式状态','第30组身份标记', ...
    '锁相相角','目标相角','本地收到的断路器闭合状态','同步复位状态', ...
    '旧前馈估计d','旧前馈估计q','旧前馈偏置d','旧前馈偏置q', ...
    '旧前馈偏置有效','旧前馈被选中','旧前馈捕获请求','旧前馈捕获确认', ...
    '电压状态交接复位活跃','电压状态交接复位确认','电压状态交接进行中','电压状态交接混合比例', ...
    '捕获的电压比例积分第一分量','捕获的电压比例积分第二分量','交接有效电压比例积分第一分量','交接有效电压比例积分第二分量', ...
    '附加支撑启用','附加支撑包络','附加支撑d','附加支撑q', ...
    '旧工作点管理均值d','旧工作点管理均值q','旧工作点管理标准差','旧工作点管理漂移', ...
    '旧候选d','旧候选q','旧基础d','旧基础q', ...
    '旧候选有效','旧提交活跃','旧提交确认','旧施加d', ...
    '旧施加q','旧覆盖状态','旧斜坡比例','旧拒绝码', ...
    '旧电压幅值','旧窗口完成','参考交接有效频率','参考交接有效电压（伏）', ...
    '参考交接目标频率','参考交接目标电压（伏）','参考交接就绪','参考交接状态', ...
    '参考频率误差','参考电压误差','参考保持状态','参考释放状态', ...
    '参考交接有效','参考交接拒绝码','参考估计平均频率','参考估计平均电压', ...
    '参考估计平均有功','参考估计平均无功','参考频率漂移','参考电压漂移', ...
    '参考频率跨度','参考电压跨度','参考窗口完成','参考候选有效', ...
    '输出电流责任交接状态','交接开断前就绪','交接准备提交确认','开断边沿已武装', ...
    '已经看到开断边沿','事件匹配','快速责任交接活跃','岛内候选有效', ...
    '平滑提交活跃','平滑提交确认','交接超时','交接拒绝码', ...
    '前馈变化率限幅','前馈幅值限幅','准备候选d','准备候选q', ...
    '准备偏置d','准备偏置q','准备标准差','准备漂移', ...
    '快速交接目标d','快速交接目标q','最终输出电流前馈d','最终输出电流前馈q', ...
    '快速交接误差幅值','变化率限幅重复回显','幅值限幅重复回显','岛内估计均值d', ...
    '岛内估计均值q','岛内估计标准差','岛内估计漂移','岛内候选d', ...
    '岛内候选q','岛内稳定计数','岛内窗口完成','最终提交斜坡', ...
    '最终保持d','最终保持q','岛内有效重复回显','电压比例积分原始第一输出（未作电流轴映射）', ...
    '电压比例积分原始第二输出（未作电流轴映射）','限流前d电流参考','限流前q电流参考','最终d电流参考', ...
    '最终q电流参考','实测d电流','实测q电流','分量限幅后d电压命令', ...
    '分量限幅后q电压命令','实测q电压标幺','q电压参考标幺','实测d电压标幺'};
end

function k49_write_schema(S,outDir)
rows=cell(0,6);
groups={'G26','G26','G27','G28','G28','G29','G30'};
devices={'EV1（车辆1）','EV2（车辆2）','ESS2（储能2）','PV1（光伏1）','PV2（光伏2）','SYSTEM（系统）','ESS1（储能1）'};
starts=[0 48 0 0 48 0 0];
for gi=1:7
    if gi==6, names=S.gnames;meanings=S.gcn;
    elseif gi==7,names=S.enames;meanings=S.ecn;
    else,names=S.dnames;meanings=S.dcn;end
    for ci=1:numel(names)
        rows(end+1,:)={groups{gi},devices{gi},ci,ci+starts(gi)+1,names{ci},meanings{ci}}; %#ok<AGROW>
    end
end
k49_csv(fullfile(outDir,'00_RAW_SCHEMA.csv'),{'Group','Device','SignalIndexWithinDevice','MatrixRowIncludingTime','Field','ChineseMeaning'},rows);
end

function report=k49_selftest(C,extended)
% 数值/文件自检明确区别于物理试验；只有调用者本机运行才产生本机通过证据。
names={};
z=k49_stat((0:.01:1)',ones(101,1),0,1,.01);
k49_test(abs(z.mean-1)<1e-12 && z.coverage>.999,'常量与时间覆盖'); names{end+1}='constant_statistics';
z=k49_stat((0:.01:1)',nan(101,1),0,1,.01);
k49_test(isnan(z.mean)&&z.finiteN==0&&z.coverage==0,'全非有限数据不得通过'); names{end+1}='nonfinite_not_zero';
t=[(0:.01:.09)';(.30:.01:.50)']; x=ones(size(t)); E=k49_episodes(t,x,x>.5,.01);
k49_test(size(E,1)==2 && max(E(:,3))<.201,'持续事件不能跨缺口'); names{end+1}='episodes_do_not_bridge_gaps';
E=k49_episodes([0;.01;.02],[0;2;0],[false;true;false],.01);
k49_test(size(E,1)==1&&E(1,3)==0,'单采样超出不是100毫秒持续'); names{end+1}='single_point_not_sustained';
E=k49_episodes((0:.01:.2)',[ones(10,1);NaN;ones(10,1)],true(21,1),.01);
k49_test(size(E,1)==2,'非有限样本打断持续事件'); names{end+1}='nonfinite_breaks_episode';
y=k49_sample([0;.001;.020;.021],[0;1;2;3],[.0005;.010;.0205],.010,'linear');
k49_test(isfinite(y(1))&&isnan(y(2))&&isfinite(y(3)),'展示不跨大缺口'); names{end+1}='large_gap_no_interpolation';
y=k49_sample([0;.001;.020;.021],[0;1;2;3],[.0004;.010],.001,'nearest');
k49_test(isfinite(y(1))&&isnan(y(2)),'近邻对齐不以远处样本填缺口'); names{end+1}='nearest_alignment_validity';
v=[.8;-.6]; u=v/norm(v); n=[-u(2);u(1)]; i=[.7;.2];
k49_test(abs(v(1)*i(1)+v(2)*i(2)-norm(v)*(u'*i))<1e-12,'有功投影符号'); names{end+1}='power_projection';
k49_test(abs(v(2)*i(1)-v(1)*i(2)+norm(v)*(n'*i))<1e-12,'无功投影符号'); names{end+1}='reactive_projection';
base=.3*u+.01*n; support=.02*u+.08*n; lambda=.8; ref=lambda*base+support;
k49_test(abs((n'*ref-n'*support)/lambda-.01)<1e-12,'扣除支撑后的独立基础方向重构'); names{end+1}='base_direction_reconstruction';
t=(0:.001:3)'; x=sin(2*(4*atan(1))*10*t); keep=~(t>1&t<1.006);
[tt,xx,info]=k49_spectral_data(t(keep),x(keep),0,3,.001,2,C);
k49_test(~isempty(tt)&&all(isfinite(xx))&&info.estimatedFraction<.01,'小缺口频谱估计'); names{end+1}='small_gap_spectrum';
keep=~(t>1&t<1.05); [tt,~,~]=k49_spectral_data(t(keep),x(keep),0,3,.001,2,C);
k49_test(isempty(tt),'频谱不得插过大缺口'); names{end+1}='large_gap_spectrum_rejected';
t=(0:.001:9.999)'; x=sin(2*(4*atan(1))*10*t); [f,P,A,df]=k49_psd(t,x);
m=f>=9.5&f<=10.5; [~,ip]=max(P); br=sqrt(sum(P(m))*df);
k49_test(abs(f(ip)-10)<.01&&abs(A(ip)-1)<.01&&abs(br-1/sqrt(2))<.01,'频谱幅值和带宽能量归一化'); names{end+1}='spectrum_normalization';
t=(0:.001:.2)'; p=mod(2*(4*atan(1))*50*t,2*(4*atan(1)));
f=k49_phase_frequency(t,p,.001,.02);
k49_test(max(abs(f(isfinite(f))-50))<1e-8,'相角差分频率'); names{end+1}='phase_frequency';
S=k49_schema();
k49_test(numel(S.dnames)==48&&numel(S.gnames)==46&&numel(S.enames)==128,'三套源字段数量'); names{end+1}='schema_dimensions';
k49_test(strcmp(S.enames{116},'VPI_Raw1')&&strcmp(S.enames{120},'Iref_Final_d')&&strcmp(S.gnames{41},'QbiasState'),'关键列号和电压环语义'); names{end+1}='schema_critical_indices';
% 不把中途1.25标幺诊断标记写成末段范围失败。
t=(0:.01:30)'; v=ones(size(t))*.935; v(t>=1&t<3)=1.25;
s=k49_source('SYSTEM',t,[v,50*ones(size(t)),.1*ones(size(t))],{'Vpu_RMS','ESS1_Fout_Hz','QbiasState'},{'电压','频率','偏置'},.01);
metrics=k49_metrics(s,0,C); tail=k49_tail(metrics,C);
k49_test(strcmp(k49_tail_status(tail),'TAIL_MEANS_WITHIN_REFERENCE_BANDS_REVIEW_DYNAMICS'),'过渡诊断不自动抹掉合格末段'); names{end+1}='transient_not_tail_veto';
if ~extended
    report=struct('status','QUICK_SELFTEST_PASS','tests',{names},'count',numel(names)); return;
end
root=tempname;mkdir(root);guard=onCleanup(@()k49_remove_temp(root)); %#ok<NASGU>
file=fullfile(root,'abc.bin');fid=fopen(file,'wb');fwrite(fid,uint8('abc'));fclose(fid);
k49_test(strcmp(k49_sha(file),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),'SHA256文件内容校验');names{end+1}='sha256_known_vector';
pfile=fullfile(root,'params.json');k49_text(pfile,'{"a/b":1,"a_b":2,"a-b":3,"final/central/ki_qbias":0.3}');
pairs=k49_parameter_pairs(pfile);
k49_test(size(pairs,1)==4&&numel(unique(pairs(:,1)))==4&&k49_pair_value(pairs,'a/b')==1,'JSON原键不被字段合法化碰撞'); names{end+1}='json_original_key_preserved';
% 完整合成读写链自检：生产配置不变，临时测试对象使用较稀采样以缩短本机自检时间。
T=C;T.step=.01;T.dt=ones(1,5)*.01;T.selftestMode=true;T.makePlots=false;
aRoot=fullfile(root,'A'); bRoot=fullfile(root,'B'); mkdir(aRoot);mkdir(bRoot);
k49_fixture(aRoot,'FULL30',T,'');k49_fixture(bRoot,'QBIAS0_30',T,'X:\K49R\A');
[aSource,ca]=k49_resolve(aRoot,'FULL30'); %#ok<NASGU>
[bSource,cb]=k49_resolve(bRoot,'QBIAS0_30'); %#ok<NASGU>
aOut=fullfile(root,'OUT_A');bOut=fullfile(root,'OUT_B');mkdir(aOut);mkdir(bOut);
[RA,DA]=k49_analyze(aSource,'FULL30',T,aOut);
k49_test(RA.allRequiredDataPresent&&abs(RA.j1-1)<1e-10,'完整A读写链、真正30秒覆盖');names{end+1}='pipeline_A_30s';
[RB,DB]=k49_analyze(bSource,'QBIAS0_30',T,bOut);
k49_test(all(strcmp(RB.fullRecordIsolation(:,8),'ZERO_ON_ALL_RECORDED_SAMPLES')),'完整B中央/请求/施加零态');names{end+1}='pipeline_B_zero_bias';
comparison=k49_compare(RA,DA,RB,DB,T,bOut);
k49_test(comparison.configurationMatched&&comparison.zeroOnRecordedSamples,'A/B唯一参数差异');names{end+1}='AB_single_configuration_difference';
RX=RB;ii=find(strcmp(RX.identityRows(:,1),'intervention_gain_readback'));RX.identityRows{ii,4}='NOT_CONFIRMED';
k49_test(~k49_identity_consistent(RX),'矛盾的实际增益记录不可冒充干净对照');names{end+1}='contradictory_readback_rejected';
k49_test(comparison.earlyDiagnosticMatched,'A/B中央未动作时的早期复现');names{end+1}='AB_early_reproduction';
k49_test(all(cell2mat(RB.bookkeeping(:,5))<1e-12|isnan(cell2mat(RB.bookkeeping(:,5)))),'无缺样补零的参考合计');names{end+1}='reference_accounting_valid_pairs';
% 缺一台的样本时不能用零替它加入总和。
DG=DB; ig=DG(3).t>RB.j1+10 & DG(3).t<RB.j1+10.02; DG(3).x(ig,45)=NaN;
[book,~]=k49_qbook(DG,RB.j1,T);
ix=find(strcmp(book(:,1),'W10_15'));k49_test(book{ix,2}<book{ix,3},'缺失施加量从共同合计中排除');names{end+1}='missing_device_excluded';
% 参数有第二处差异：比较应明确失去单变量资格。
RX=RB; ix=find(strcmp(RX.params(:,1),'final/manager/PV1/imax'));RX.params{ix,2}=9;
CX=k49_compare(RA,DA,RX,DB,T,fullfile(root,'ALTERED_COMPARE'));
k49_test(~CX.configurationMatched,'额外参数变化拒绝单变量对照');names{end+1}='extra_parameter_detected';
% 非零或缺失不是零：直接复用真实隔离核验函数。
r=k49_zero_row('REQUEST','PV1','q',[0;1;2],[0;1e-3;0],1,T,'QBIAS0_30');
k49_test(strcmp(r{8},'NONZERO_ISOLATION_NOT_ESTABLISHED'),'非零偏置检出');names{end+1}='nonzero_isolation_detected';
r=k49_zero_row('REQUEST','PV1','q',[0;1;2],[0;NaN;0],1,T,'QBIAS0_30');
k49_test(strcmp(r{8},'UNKNOWN_MISSING_OR_NONFINITE'),'缺失偏置不能通过');names{end+1}='missing_isolation_not_zero';
r=k49_zero_row('REQUEST','PV1','q',[1;2;3],[0;0;0],1,T,'QBIAS0_30');
k49_test(strcmp(r{8},'INITIALIZATION_NOT_COVERED_ZERO_ONLY_LATER'),'未记录初始化不能假装全程零态');names{end+1}='initialization_coverage_required';
% 文件哈希、尺寸、缺组、同时间不同值必须拒绝。
archive=k49_json_read(fullfile(aRoot,'raw_archive.json')); entries=k49_cellstruct(archive.files);
bad=entries;bad{1}.sha256=repmat('0',1,64);
k49_expect_error(@()k49_family(aRoot,bad,1,T),'K49:HashMismatch');names{end+1}='changed_file_hash_rejected';
bad=entries;keep=true(size(bad));for bi=1:numel(bad),keep(bi)=~strcmp(bad{bi}.group,'G30');end
k49_expect_error(@()k49_family(aRoot,bad(keep),5,T),'K49:MissingFamily');names{end+1}='missing_family_rejected';
% A来源Windows绝对路径在临时目录被正确重定位；同组重叠样本被校验去重。
k49_test(RA.familyRows{1,5}>0,'同内容重叠样本去重');names{end+1}='identical_overlap_deduplicated';
E=entries{1};[path,~]=k49_local_raw(aRoot,E.archive,E.group);S0=load(path);var=T.stems{1};arr=S0.(var);arr(2,end)=arr(2,end)+1;
S0.(var)=arr;save(path,'-struct','S0','-v7');bad=entries;bad{1}.sha256=k49_sha(path);
k49_expect_error(@()k49_family(aRoot,bad,1,T),'K49:ConflictingOverlap');names{end+1}='conflicting_overlap_rejected';
% 打包仅含计算结果；压缩后再次检查是否可解析。
zpath=fullfile(root,'analysis.zip');k49_pack(aOut,zpath);k49_safe_zip(zpath);
k49_test(isfile(zpath),'计算输出完整打包');names{end+1}='output_archive';
report=struct('status','EXTENDED_SELFTEST_PASS_ON_THIS_MATLAB','tests',{names},'count',numel(names), ...
    'meaning','本机合成数据/数值函数自检通过，不代表真实30秒试验或控制参数通过。');
fprintf('\n本机扩展自检通过，共%d项。未连接实时平台，未修改正式记录。\n',numel(names));
end

function k49_test(ok,name)
if ~ok, error('K49:Selftest','自检失败：%s',name); end
end

function k49_expect_error(fn,identifier)
received=false;
try, fn(); catch ME
    if strcmp(ME.identifier,identifier), received=true;
    else, rethrow(ME); end
end
if ~received, error('K49:Selftest','预期错误未触发：%s',identifier); end
end

function k49_fixture(root,kind,C,base)
% 合成文件用于程序回归，不是六机物理仿真结果。
t=(0:C.dt(1):32)'; n=numel(t); r=t-1; stage=ones(n,1);stage(r>=0)=2;stage(r>=.2-1e-9)=3;
z=zeros(n,1);gain=.3;
if strcmp(kind,'FULL30'),z=.01*max(0,r-.75);z=min(z,.1);else,gain=0;end
v=ones(n,1); active=r>=.75;
if strcmp(kind,'FULL30'),v(active)=1+.25*exp(-((r(active)-2)/.5).^2);v(r>=10)=.935;
else,v(active)=1+.05*exp(-((r(active)-2)/.5).^2);v(r>=10)=.945;end
G=cell(1,5); devs=cell(1,5);
for di=1:5
    X=zeros(n,48);id=.2;if di>=4,id=-.2;end
    X(:,1)=id;X(:,3)=id;X(:,4)=z/5;X(:,5)=id;X(:,6)=z/5;X(:,7)=v;X(:,9)=v;
    X(:,13)=.8;X(:,15)=.65;X(:,16)=v*id;X(:,17)=-v.*z/5;X(:,18)=1;X(:,19)=50;
    X(:,20)=stage;X(:,21)=v;X(:,22)=1;X(:,23)=1;X(:,24:26)=id;
    X(:,30)=z/5;X(:,31)=.5;X(:,33:34)=1;X(:,36)=1;X(:,37)=50;X(:,38)=10000;
    X(:,42)=.65;X(:,43)=.35;X(:,44)=z/5;X(:,45)=z/5;X(:,46:47)=.2;devs{di}=X;
end
G{1}=[devs{4},devs{5}];G{2}=devs{3};G{3}=[devs{1},devs{2}];
x=zeros(n,46);x(:,1)=1;x(:,15)=stage;x(:,27)=double(r<0);x(:,31)=10000*v;x(:,32)=50;x(:,33)=1;
x(:,34:35)=100;x(:,36:37)=.5;x(:,38)=100;x(:,39)=1;x(:,40)=1-v;x(:,41)=z;x(:,42)=z;x(:,43:44)=1;x(:,45)=double(z>0);
G{4}=x;
x=zeros(n,128);x(:,1:2)=50;x(:,3)=mod(2*(4*atan(1))*10*t,2*(4*atan(1)));x(:,4)=50;
x(:,5)=10000*v.*cos(2*(4*atan(1))*10*t);x(:,6)=10000*v.*cos(2*(4*atan(1))*10*t-2*(4*atan(1))/3);x(:,7)=10000*v.*cos(2*(4*atan(1))*10*t+2*(4*atan(1))/3);
x(:,10)=1;x(:,11)=0;x(:,12)=30030;x(:,15)=double(r<0);
x(:,55)=50;x(:,56)=10000;x(:,57)=50;x(:,58)=10000;x(:,59)=1;x(:,60)=1;
x(:,77)=2;x(r>=0,77)=4;x(r>=.08,77)=6;x(:,78:80)=1;x(:,81:82)=double(r>=0);x(:,83)=double(r>=0&r<.08);x(:,86)=double(r>=.08);
x(:,99)=.02;x(:,100)=.1;x(:,118)=.2;x(:,120)=.2;x(:,122)=.2;x(:,124)=.8;x(:,126)=v;x(:,127)=1;x(:,128)=0;G{5}=x;
entries=struct('source',{},'archive',{},'group',{},'bytes',{},'sha256',{},'time_bounds',{});
if strcmp(kind,'FULL30'), short='A'; else, short='B'; end
original=['X:\K49R\' short];
for gi=1:5
    folder=fullfile(root,'RAW',C.groups{gi},'a1b2c3d4');mkdir(folder);
    parts={1:n};if gi==1,mid=floor(n/2);parts={1:mid,mid:n};end
    for piIndex=1:numel(parts)
        ids=parts{piIndex};a=[t(ids)';G{gi}(ids,:)'];
        if gi==2,a=a.';end
        suffix='';if numel(parts)>1,suffix=['_' num2str(piIndex)];end
        file=[C.stems{gi} suffix '.mat'];path=fullfile(folder,file);
        obj=struct();obj.(C.stems{gi})=a;save(path,'-struct','obj','-v7');stat=dir(path);
        absolute=[original '\RAW\' C.groups{gi} '\a1b2c3d4\' file];
        bounds=struct('format','SYNTHETIC_MAT5','rows',C.rows(gi),'samples',numel(ids),'first_time_s',t(ids(1)),'last_time_s',t(ids(end)),'variable',C.stems{gi});
        entries(end+1)=struct('source',['X:\model\' file],'archive',absolute,'group',C.groups{gi},'bytes',stat.bytes,'sha256',k49_sha(path),'time_bounds',bounds); %#ok<AGROW>
    end
end
archive=struct('files',entries,'unresolved',[]);
M=struct('trial_kind',kind,'status','CAPTURE_COMPLETE_NO_ELECTRICAL_VERDICT','duration_s',30,'fingerprint',repmat('a',1,64), ...
    'output_directory',original,'j1_first_open_host',1,'stage3_enter_host',1.2,'calculation_step_s',C.step,'central_gain_actual',gain, ...
    'baseline_reference',base,'raw_archive_status','FIVE_FAMILIES_ARCHIVED_CONTENT_VERIFIED','raw_archive',archive);
k49_json_write(fullfile(root,'manifest.json'),M);k49_json_write(fullfile(root,'raw_archive.json'),archive);
audit=struct('source_sha256',repmat('b',1,64),'ESS1_voltage_mask',struct('Kp_Vreg','0.02','Ki_Vreg','0.14'));
k49_json_write(fullfile(root,'model_audit.json'),audit);
k49_json_write(fullfile(root,'intervention.json'),struct('before',.3,'after',gain));
k49_text(fullfile(root,'prej1_parameters.json'),sprintf('{"final/central/ki_qbias":%.17g,"final/manager/PV1/imax":1.2,"runtime/AGC_STEP_TIME":9999}',gain));
snapshot=struct('Vab_rms_true_V',10000,'Freq_Hz',50,'Ppcc_kW',1,'Qpcc_kvar',2,'F24_f_eff',50,'F24_v_eff',10000,'F25_pre_bias_d',.02,'F25_pre_bias_q',.1);
k49_json_write(fullfile(root,'prej1.json'),struct('snapshot',snapshot,'target_clock_s',.99));
end

function k49_derived_dictionary(D,outDir)
rows=cell(0,5);
for si=1:numel(D)
    s=D(si);
    for ci=1:numel(s.names)
        if ci<=s.rawCount, origin='原始记录字段';else,origin='根据原始记录计算，非新增测量';end
        rows(end+1,:)={s.name,s.names{ci},s.cn{ci},origin,ci}; %#ok<AGROW>
    end
end
k49_csv(fullfile(outDir,'00_ALL_FIELDS_DICTIONARY.csv'),{'Source','Field','ChineseMeaning','Origin','ColumnWithinData'},rows);
end

function finish=k49_mode_comparison_end(D,tj,C)
finish=C.horizon;
for si=1:numel(D)
    s=D(si); r=s.t-tj;
    if si==1
        bad=r>=.005 & (~isfinite(s.x(:,27))|s.x(:,27)>.5);
        stage=s.x(:,15);
    elseif si==2
        bad=r>=.010 & (~isfinite(s.x(:,15))|s.x(:,15)>.5|~isfinite(s.x(:,11))|s.x(:,11)>.5);
        stage=3*ones(size(r));
    else
        bad=false(size(r));stage=s.x(:,20);
    end
    bad=bad | (r>=.210 & (~isfinite(stage)|abs(stage-3)>.1));
    ix=find(bad & r<=C.horizon,1,'first');
    if ~isempty(ix),finish=min(finish,r(ix));end
end
end

function ok=k49_identity_consistent(R)
required={'calculation_step_s','central_gain_actual','prej1_gain_record','intervention_gain_readback','ESS1_local_Kp','ESS1_local_Ki'};
ok=R.captureComplete;
for ki=1:numel(required)
    ix=find(strcmp(R.identityRows(:,1),required{ki}));
    ok=ok&&numel(ix)==1;
    if numel(ix)==1,ok=ok&&strcmp(R.identityRows{ix,4},'SATISFIED');end
end
end

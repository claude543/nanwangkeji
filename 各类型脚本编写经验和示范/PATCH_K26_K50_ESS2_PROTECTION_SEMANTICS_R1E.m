function result = PATCH_K26_K50_ESS2_PROTECTION_SEMANTICS_R1E(modelRoot)
% PATCH_K26_K50_ESS2_PROTECTION_SEMANTICS_R1E
% Targeted protection-semantics fix for the base-power diagnostic only.
% - state5: transient severe excursion resets qualification; sustained severe latches failCode5.
% - state6: transient severe excursion resets pickup qualification; sustained severe latches failCode6.
% - state7: loss of pickup qualification returns to state6; sustained severe is handled there.
% Non-base-test branches are preserved. No topology, threshold, PI, recorder, or RT-LAB edits.

MODEL = 'K26_K50_CLEAN_P1';
CORE_REL = 'SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE';
ADV_REL  = 'SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core';
ADAPTER_REL = 'SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_V49_CURRENT_EXECUTION_ADAPTER/CORE';
EXPECTED_R1B = '56e5a5fc52a080fb7293f5fa76e4f04fd41027e3d9a2693b302a828edfcf69e0';
EXPECTED_R1D = 'd7c1714cd8f2889933ac2373747e2b3dda7999184eb67e3c668b665f9cb163ca';
EXPECTED_R1E = 'dc358e29805d31c3d6934fd7e44beababcb4b6c1142763690243840f0bf10d0b';
EXPECTED_ADV = 'd88414496c9dd07ec530ab926a6f92a453e36162258a113139eb565fbc3fdd53';
EXPECTED_ADAPTER = '579dff63e203dafb3df67cae8e4554e4607508d83f7014d9ce32ba175126a144';

if nargin < 1 || isempty(modelRoot)
    modelRoot = 'D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\models\K26_K50_CLEAN_P1';
end
pkg = fileparts(mfilename('fullpath'));
refB = fullfile(pkg,'reference','F099_R1B.txt');
refD = fullfile(pkg,'reference','F099_R1D.txt');
payloadFile = fullfile(pkg,'payload','F099_R1E.txt');
assert(isfile(refB) && isfile(refD) && isfile(payloadFile), 'R1E:Assets', 'reference/payload 文件缺失。');
assert(strcmp(hashText(fileread(refB)),EXPECTED_R1B),'R1E:RefBHash','R1B参考源码文件损坏。');
assert(strcmp(hashText(fileread(refD)),EXPECTED_R1D),'R1E:RefDHash','R1D参考源码文件损坏。');
assert(strcmp(hashText(fileread(payloadFile)),EXPECTED_R1E),'R1E:PayloadHash','R1E候选源码文件损坏。');

modelFile = fullfile(modelRoot,[MODEL '.slx']);
assert(isfile(modelFile),'R1E:ModelFile','找不到正式模型：%s',modelFile);
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
out = fullfile(modelRoot,['PATCH_ESS2_PROTECTION_SEMANTICS_R1E_' stamp]);
mkdir(out);
result = struct('version','ESS2_PROTECTION_SEMANTICS_R1E_20260916', ...
    'status','STARTED','modelFile',modelFile,'outputDir',out, ...
    'beforeSourceHash','', 'afterSourceHash','', 'backupFile','', ...
    'acceptedInputVersions',{{'R1B','R1D'}}, ...
    'note','Only Restore Executor CORE base-test state5/6/7 protection semantics are changed.');
writeJSON(fullfile(out,'RESULT.json'),result);

loadedHere = false; touched = false; backupFile = '';
try
    if bdIsLoaded(MODEL)
        actualFile = char(get_param(MODEL,'FileName'));
        assert(strcmpi(canonical(actualFile),canonical(modelFile)), ...
            'R1E:WrongLoadedModel','内存中同名模型不是指定正式文件。');
        assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1E:Dirty','正式模型存在未保存修改，停止。');
    else
        load_system(modelFile); loadedHere = true;
        assert(strcmpi(canonical(get_param(MODEL,'FileName')),canonical(modelFile)), ...
            'R1E:LoadIdentity','加载文件身份不符。');
        assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1E:DirtyAfterLoad','加载后模型被意外改脏。');
    end

    core = chartAt([MODEL '/' CORE_REL]);
    adv = chartAt([MODEL '/' ADV_REL]);
    adapter = chartAt([MODEL '/' ADAPTER_REL]);
    beforeScript = normalizeText(char(core.Script));
    beforeHash = hashText(beforeScript);
    result.beforeSourceHash = beforeHash;

    % Freeze the already-built surrounding control version. This patch is not
    % allowed to ride on an unknown supervisor/current-adapter version.
    assert(strcmp(hashText(char(adv.Script)),EXPECTED_ADV),'R1E:AdvancedCoreMismatch', ...
        'Advanced Strategy Core不是已构建的R1B版本，停止。');
    assert(strcmp(hashText(char(adapter.Script)),EXPECTED_ADAPTER),'R1E:AdapterMismatch', ...
        'Current Execution Adapter不是已构建的R1B版本，停止。');

    if strcmp(beforeHash,EXPECTED_R1E)
        result.status = 'ALREADY_PATCHED_READY_FOR_VERIFY';
        result.afterSourceHash = beforeHash;
        writeJSON(fullfile(out,'RESULT.json'),result);
        fprintf('R1E 已经存在，无需再次修改。\n下一步：verifyResult = VERIFY_K26_K50_ESS2_PROTECTION_SEMANTICS_R1E;\n');
        return;
    end
    assert(strcmp(beforeHash,EXPECTED_R1B) || strcmp(beforeHash,EXPECTED_R1D), ...
        'R1E:SourceMismatch', ...
        ['当前 Restore Executor CORE 既不是已验证R1B，也不是R1D。\n实际Hash=%s\n' ...
         'R1B=%s\nR1D=%s\n禁止在未知版本上套补丁。'],beforeHash,EXPECTED_R1B,EXPECTED_R1D);

    % Semantic preflight.
    assert(contains(beforeScript,'elseif state==6'),'R1E:State6Missing','找不到state6。');
    assert(contains(beforeScript,'elseif state==7'),'R1E:State7Missing','找不到state7。');
    assert(contains(beforeScript,'pickupSevere=double'),'R1E:SevereMissing','找不到pickupSevere。');
    assert(contains(beforeScript,'pickupOK=double(abs(prefApplied-pickupTarget)<=targetTol &&'), ...
        'R1E:PickupMissing','找不到基础任务pickupOK定义。');

    % Freeze thresholds/timing. R1E changes persistence semantics, not values.
    cfgRoot = [MODEL '/SS_Slave2/AA15_ESS2_RESTORE_CONFIG/'];
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_V_MIN_PU'],0.9);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_V_MAX_PU'],1.1);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_DF_MAX_HZ'],0.5);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_IREF_MAX_PU'],0.05);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_IMEAS_MAX_PU'],0.05);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_READY_DWELL_S'],0.5);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_POST_DWELL_S'],0.2);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_ABORT_OPEN_ENABLE'],0.0);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_POST_I_MAX_PU'],0.2);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_POST_V_MIN_PU'],0.8);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_POST_V_MAX_PU'],1.2);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S'],2.0);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU'],0.002);
    requireNumericBlock([cfgRoot 'CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S'],3.0);

    backupFile = fullfile(out,[MODEL '_BEFORE_PROTECTION_R1E.slx']);
    [ok,msg] = copyfile(modelFile,backupFile,'f');
    assert(ok,'R1E:Backup','备份失败：%s',msg);
    assert(strcmp(fileHash(modelFile),fileHash(backupFile)),'R1E:BackupHash','备份字节不一致。');
    result.backupFile = backupFile;
    writeJSON(fullfile(out,'RESULT.json'),result);

    payload = normalizeText(fileread(payloadFile));
    touched = true;
    core.Script = payload;
    drawnow;
    assert(strcmp(hashText(char(core.Script)),EXPECTED_R1E),'R1E:InMemoryHash','内存候选源码不符。');

    save_system(MODEL);
    close_system(MODEL,0);
    load_system(modelFile);
    core2 = chartAt([MODEL '/' CORE_REL]);
    afterScript = normalizeText(char(core2.Script));
    afterHash = hashText(afterScript);
    assert(strcmp(afterHash,EXPECTED_R1E),'R1E:ReloadHash','保存重读后源码不符。');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1E:ReloadDirty','保存重读后模型被改脏。');

    % Postconditions: base-test protection semantics only.
    assert(contains(afterScript,'state5SevereDwell=max(readyDwell,postDwell);'), ...
        'R1E:State5Dwell','state5持续异常判断缺失。');
    assert(contains(afterScript,'activeSevereDwell=max(postDwell,Ts);'), ...
        'R1E:State6Dwell','state6持续异常判断缺失。');
    assert(contains(afterScript,'elseif pickupOK<0.5'), ...
        'R1E:State7Requalify','state7资格丢失回state6逻辑缺失。');
    assert(contains(afterScript,'elseif baseOnly'), ...
        'R1E:BaseOnlyIsolation','基础诊断分支隔离缺失。');
    assert(contains(afterScript,'state=6;readyCount=1;postCount=0;'), ...
        'R1E:State7SevereRevoke','state7严重瞬态撤销资格逻辑缺失。');
    assert(contains(afterScript,'state=5;releaseAlpha=0;readyCount=0;postCount=0;'), ...
        'R1E:PersistentRollback','持续异常回退逻辑缺失。');

    result.status = 'SAVED_RELOADED_READY_FOR_INDEPENDENT_VERIFY';
    result.afterSourceHash = afterHash;
    result.requiredNext = 'VERIFY_K26_K50_ESS2_PROTECTION_SEMANTICS_R1E; then RT-LAB Rebuild All; then reuse LEAN R2 runner.';
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf('\nR1E保护语义定点修复保存成功。阈值和PI均未改，只把资格丢失与持续故障分开。\n');
    fprintf('结果目录：%s\n',out);
    fprintf('下一步：verifyResult = VERIFY_K26_K50_ESS2_PROTECTION_SEMANTICS_R1E;\n');

catch ME
    result.status = 'FAILED';
    result.errorIdentifier = ME.identifier;
    result.errorMessage = ME.message;
    try result.errorReport = getReport(ME,'extended','hyperlinks','off'); catch, end
    writeJSON(fullfile(out,'RESULT.json'),result);
    if touched && ~isempty(backupFile) && isfile(backupFile)
        try
            if bdIsLoaded(MODEL), close_system(MODEL,0); end
            [ok,msg] = copyfile(backupFile,modelFile,'f');
            if ok
                load_system(modelFile);
                result.status = 'FAILED_ROLLED_BACK_TO_FULL_BACKUP';
                result.rollback = 'PASS';
            else
                result.rollback = ['FAIL: ' msg];
            end
        catch RB
            result.rollback = ['EXCEPTION: ' RB.message];
        end
        writeJSON(fullfile(out,'RESULT.json'),result);
    end
    fprintf(2,'R1E修改未完成：%s\n结果目录：%s\n',ME.message,out);
    rethrow(ME);
end

if loadedHere %#ok<NASGU>
    % Leave successfully patched formal model open, matching existing workflow.
end
end

function c=chartAt(p)
r=sfroot; cs=r.find('-isa','Stateflow.EMChart'); hit=[];
for k=1:numel(cs)
    if strcmp(char(cs(k).Path),p), hit(end+1)=k; end %#ok<AGROW>
end
assert(numel(hit)==1,'R1E:Chart','函数实例必须精确唯一：%s，匹配%d',p,numel(hit));
c=cs(hit);
end

function requireNumericBlock(p,expected)
assert(getSimulinkBlockHandle(p)>=0,'R1E:ConfigBlock','配置块不存在：%s',p);
raw=get_param(p,'Value');
val=str2double(raw);
if ~isfinite(val)
    try val=double(slResolve(raw,p)); catch, val=NaN; end
end
assert(isfinite(val) && abs(val-expected)<=1e-12*max(1,abs(expected)), ...
    'R1E:ConfigValue','配置值不符：%s 实际=%s 期望=%.15g',p,raw,expected);
end

function s=normalizeText(s)
s=strrep(strrep(char(s),sprintf('\r\n'),sprintf('\n')),sprintf('\r'),sprintf('\n'));
end
function h=hashText(s)
h=hashBytes(unicode2native(normalizeText(s),'UTF-8'));
end
function h=fileHash(p)
f=fopen(p,'rb'); assert(f>=0,'R1E:FileRead','文件不可读：%s',p); c=onCleanup(@()fclose(f)); %#ok<NASGU>
h=hashBytes(fread(f,Inf,'*uint8'));
end
function h=hashBytes(b)
md=java.security.MessageDigest.getInstance('SHA-256'); md.update(typecast(uint8(b(:)),'int8'));
d=typecast(md.digest(),'uint8'); h=lower(reshape(dec2hex(d,2).',1,[]));
end
function p=canonical(p)
p=char(java.io.File(char(p)).getCanonicalPath());
end
function writeJSON(p,s)
f=fopen(p,'w','n','UTF-8'); assert(f>=0,'R1E:Write','无法写入：%s',p); c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',jsonencode(s,'PrettyPrint',true));
end

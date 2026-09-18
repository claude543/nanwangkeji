function result = PATCH_K26_K50_ESS2_BASETEST_OBSERVE_R1G(modelRoot)
% PATCH_K26_K50_ESS2_BASETEST_OBSERVE_R1G
% Diagnostic-observe patch for the already built ESS2 base-power design.
% R1G only repairs the R1F patch-script Stateflow handle assignment; payload/control semantics are unchanged.
%
% BASETEST only:
% 1) Preserve proven formation/synchronization/real breaker-close sequence.
% 2) After physical close, V/f/I/P health quantities remain diagnostics only.
% 3) state4 -> state5 uses fixed post-close target-time dwell.
% 4) state5 -> state6 uses fixed connected-zero target-time dwell.
% 5) state6 stays active for the formal experiment; pickupOK/state7 is not a gate.
% 6) S14 state35 observes P=0 for 5 s, then state40 runs the existing Rate Limiter,
%    waits 2.5 s for the 0 -> -0.005 pu command ramp, then records 30 s.
% 7) No recorder, PI, support-isolation switch, current-limit, physical circuit,
%    coordinator-handover, or non-BASETEST control algorithm is modified.
%
% Workflow: exact preflight -> scratch copy save/reload -> full backup ->
% formal save/reload. Does NOT run RT-LAB or electrical simulation.

MODEL='K26_K50_CLEAN_P1';
ADV_REL='SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core';
REST_REL='SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE';
ADAPTER_REL='SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_V49_CURRENT_EXECUTION_ADAPTER/CORE';
LIMIT_REL='SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_FINAL_GFL_LIMIT_CORE';

H_ADV_R1B='d88414496c9dd07ec530ab926a6f92a453e36162258a113139eb565fbc3fdd53';
H_ADV_R1F='5728b5d4c19a3e0f50c705c21ec3e8b7e4c44b065913a8b06c1f2aac78b130c0';
H_REST_R1B='56e5a5fc52a080fb7293f5fa76e4f04fd41027e3d9a2693b302a828edfcf69e0';
H_REST_R1D='d7c1714cd8f2889933ac2373747e2b3dda7999184eb67e3c668b665f9cb163ca';
H_REST_R1E='dc358e29805d31c3d6934fd7e44beababcb4b6c1142763690243840f0bf10d0b';
H_REST_R1F='59caf18045d25e6580426f9b7f2123692084e4bc25127b3ffce8cacc657e274b';
H_ADAPTER='579dff63e203dafb3df67cae8e4554e4607508d83f7014d9ce32ba175126a144';
H_LIMIT='663820bdaaaf983d1f0f9daa73353f6133c25dbfa56e6afb7f0fdc93a09fc3cb';

PKG=fileparts(mfilename('fullpath'));
advPayload=fullfile(PKG,'payload','F006_R1F.txt');
restPayload=fullfile(PKG,'payload','F099_R1F.txt');
assert(isfile(advPayload)&&isfile(restPayload),'R1F:Assets','payload文件缺失。');
assert(strcmp(hashText(fileread(advPayload)),H_ADV_R1F),'R1F:AdvPayload','F006_R1F损坏。');
assert(strcmp(hashText(fileread(restPayload)),H_REST_R1F),'R1F:RestPayload','F099_R1F损坏。');

if nargin<1 || isempty(modelRoot)
    if bdIsLoaded(MODEL)
        modelRoot=fileparts(get_param(MODEL,'FileName'));
    else
        modelRoot='D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\models\K26_K50_CLEAN_P1';
    end
end
modelFile=canonical(fullfile(char(modelRoot),[MODEL '.slx']));
assert(isfile(modelFile),'R1F:MissingModel','找不到正式模型：%s',modelFile);

if bdIsLoaded(MODEL)
    assert(strcmpi(canonical(get_param(MODEL,'FileName')),modelFile),'R1F:WrongModel','同名模型从其他位置加载。');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1F:Dirty','模型存在未保存修改。');
    assert(strcmp(get_param(MODEL,'SimulationStatus'),'stopped'),'R1F:Running','Simulink模型当前未停止。');
end

out=fullfile(fileparts(modelFile),['PATCH_ESS2_BASETEST_OBSERVE_R1G_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
mkdir(out);
result=struct('version','ESS2_BASETEST_OBSERVE_R1G_SCRIPT_FIX_20260916','status','STARTED', ...
    'modelFile',modelFile,'outputDir',out,'backupFile','', ...
    'note','Only Advanced Strategy Core and ESS2 Restore Executor CORE BASETEST semantics are changed.');
writeJSON(fullfile(out,'RESULT.json'),result);
formalSaveAttempted=false; backupFile='';

try
    if ~bdIsLoaded(MODEL),load_system(modelFile);end
    [advHash,restHash]=preflight(MODEL,H_ADV_R1B,H_ADV_R1F,H_REST_R1B,H_REST_R1D,H_REST_R1E,H_REST_R1F,H_ADAPTER,H_LIMIT);
    result.beforeAdvancedHash=advHash;
    result.beforeRestoreHash=restHash;

    if strcmp(advHash,H_ADV_R1F)&&strcmp(restHash,H_REST_R1F)
        result.status='ALREADY_PATCHED_READY_FOR_VERIFY';
        writeJSON(fullfile(out,'RESULT.json'),result);
        fprintf('R1F已经存在。不要重复改模。\n下一步：verifyResult = VERIFY_K26_K50_ESS2_BASETEST_OBSERVE_R1G;\n');
        return;
    end
    close_system(MODEL,0);

    % Scratch first: preserve the successful anti-rework workflow.
    scratchDir=fullfile(out,'SCRATCH');mkdir(scratchDir);
    scratchFile=fullfile(scratchDir,[MODEL '.slx']);
    mustCopy(modelFile,scratchFile);
    assert(strcmp(fileHash(modelFile),fileHash(scratchFile)),'R1F:ScratchCopy','临时副本字节不一致。');
    load_system(scratchFile);
    preflight(MODEL,H_ADV_R1B,H_ADV_R1F,H_REST_R1B,H_REST_R1D,H_REST_R1E,H_REST_R1F,H_ADAPTER,H_LIMIT);
    applySources(MODEL,advPayload,restPayload);
    verifyFinal(MODEL,H_ADV_R1F,H_REST_R1F,H_ADAPTER,H_LIMIT);
    save_system(MODEL);
    close_system(MODEL,0);
    load_system(scratchFile);
    verifyFinal(MODEL,H_ADV_R1F,H_REST_R1F,H_ADAPTER,H_LIMIT);
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1F:ScratchDirty','临时副本重读后Dirty。');
    close_system(MODEL,0);

    % Full formal backup before touching the official SLX.
    backupFile=fullfile(out,[MODEL '_BEFORE_OBSERVE_R1F.slx']);
    mustCopy(modelFile,backupFile);
    assert(strcmp(fileHash(modelFile),fileHash(backupFile)),'R1F:BackupHash','正式备份字节不一致。');
    result.backupFile=backupFile;
    writeJSON(fullfile(out,'RESULT.json'),result);

    load_system(modelFile);
    preflight(MODEL,H_ADV_R1B,H_ADV_R1F,H_REST_R1B,H_REST_R1D,H_REST_R1E,H_REST_R1F,H_ADAPTER,H_LIMIT);
    applySources(MODEL,advPayload,restPayload);
    verifyFinal(MODEL,H_ADV_R1F,H_REST_R1F,H_ADAPTER,H_LIMIT);
    formalSaveAttempted=true;
    save_system(MODEL);
    close_system(MODEL,0);
    load_system(modelFile);
    verifyFinal(MODEL,H_ADV_R1F,H_REST_R1F,H_ADAPTER,H_LIMIT);
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1F:FormalDirty','正式模型重读后Dirty。');

    result.afterAdvancedHash=hashText(getChartScript([MODEL '/' ADV_REL]));
    result.afterRestoreHash=hashText(getChartScript([MODEL '/' REST_REL]));
    result.status='SAVED_RELOADED_READY_FOR_INDEPENDENT_VERIFY';
    result.requiredNext='VERIFY_K26_K50_ESS2_BASETEST_OBSERVE_R1G; then RT-LAB Rebuild All; then RUN_K26_K50_ESS2_BASE_POWER_OBSERVE_R3.py';
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf('\nR1F诊断观察模式保存成功。记录器、PI、限流、四路支撑隔离均未改。\n');
    fprintf('结果目录：%s\n',out);
    fprintf('下一步：verifyResult = VERIFY_K26_K50_ESS2_BASETEST_OBSERVE_R1G;\n');

catch ME
    result.status='FAILED';
    result.errorIdentifier=ME.identifier;
    result.errorMessage=ME.message;
    try result.errorReport=getReport(ME,'extended','hyperlinks','off');catch,end
    if bdIsLoaded(MODEL)
        try close_system(MODEL,0);catch,end
    end
    if formalSaveAttempted && ~isempty(backupFile) && isfile(backupFile)
        try
            mustCopy(backupFile,modelFile);
            assert(strcmp(fileHash(modelFile),fileHash(backupFile)),'R1F:RollbackHash','回滚字节不一致。');
            load_system(modelFile);
            result.status='FAILED_ROLLED_BACK_TO_FULL_BACKUP';
            result.rollback='PASS';
        catch RB
            result.rollback=['FAIL: ' RB.message];
        end
    end
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf(2,'R1F修改未完成：%s\n结果目录：%s\n',ME.message,out);
    rethrow(ME);
end
end

function [advHash,restHash]=preflight(mdl,H_ADV_R1B,H_ADV_R1F,H_REST_R1B,H_REST_R1D,H_REST_R1E,H_REST_R1F,H_ADAPTER,H_LIMIT)
adv=chartAt([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core']);
rest=chartAt([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE']);
adapter=chartAt([mdl '/SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_V49_CURRENT_EXECUTION_ADAPTER/CORE']);
limit=chartAt([mdl '/SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_FINAL_GFL_LIMIT_CORE']);
advHash=hashText(char(adv.Script));restHash=hashText(char(rest.Script));
assert(strcmp(advHash,H_ADV_R1B)||strcmp(advHash,H_ADV_R1F),'R1F:AdvUnknown','Advanced Strategy Core不是R1B/R1F已知版本：%s',advHash);
assert(any(strcmp(restHash,{H_REST_R1B,H_REST_R1D,H_REST_R1E,H_REST_R1F})),'R1F:RestUnknown','Restore Executor不是R1B/R1D/R1E/R1F已知版本：%s',restHash);
assert(strcmp(hashText(char(adapter.Script)),H_ADAPTER),'R1F:AdapterMismatch','Current Adapter不是已构建R1B版本。');
assert(strcmp(hashText(char(limit.Script)),H_LIMIT),'R1F:LimitMismatch','FINAL_GFL_LIMIT_CORE发生未知变化。');
checkFrozenBaseTest(mdl);
end

function applySources(mdl,advPayload,restPayload)
setChartScript([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core'],fileread(advPayload));
setChartScript([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE'],fileread(restPayload));
drawnow;
end

function verifyFinal(mdl,H_ADV_R1F,H_REST_R1F,H_ADAPTER,H_LIMIT)
advScript=normalizeText(getChartScript([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core']));
restScript=normalizeText(getChartScript([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE']));
assert(strcmp(hashText(advScript),H_ADV_R1F),'R1F:AdvFinal','Advanced Strategy Core最终正文不符。');
assert(strcmp(hashText(restScript),H_REST_R1F),'R1F:RestFinal','Restore Executor最终正文不符。');
assert(strcmp(hashText(getChartScript([mdl '/SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_V49_CURRENT_EXECUTION_ADAPTER/CORE'])),H_ADAPTER), ...
    'R1F:AdapterFinal','Current Adapter被意外修改。');
assert(strcmp(hashText(getChartScript([mdl '/SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_FINAL_GFL_LIMIT_CORE'])),H_LIMIT), ...
    'R1F:LimitFinal','FINAL_GFL_LIMIT_CORE被意外修改。');

% Semantic checks: the diagnostic must not self-judge ordinary electrical quality.
mustContain(restScript,'if baseOnly');
mustContain(restScript,'postCount=postCount+1;');
mustContain(restScript,'Diagnostic connected-zero dwell.');
mustContain(restScript,'Stay in state6 for the entire formal diagnostic.');
mustContain(restScript,'pickupOK,');
mustContain(restScript,'pickupSevere');
mustContain(advScript,'BASE_RAMP_SETTLE=2.5');
mustContain(advScript,'Do not require state7/pickupOK/P tracking before');
mustContain(advScript,'black_good_timer>=BASE_PLATFORM_TIME');
assert(~contains(extractBase40(advScript),'restoreState==7.0'),'R1F:State7Gate','BASETEST state40仍被state7门控。');
assert(~contains(extractBase35(advScript),'ess2_restore(12)>0.5'),'R1F:PostOKGate','BASETEST state35仍被postOK门控。');
checkFrozenBaseTest(mdl);
end

function checkFrozenBaseTest(mdl)
% Previous base-power design must remain active.
ws=get_param(mdl,'ModelWorkspace');
en=getVariable(ws,'AA15_ESS2_BASETEST_ENABLE');
pt=getVariable(ws,'AA15_ESS2_BASETEST_TARGET_PU');
assert(abs(double(en)-1.0)<1e-12,'R1F:BaseEnable','AA15_ESS2_BASETEST_ENABLE不是1。');
assert(abs(double(pt)+0.005)<1e-12,'R1F:BaseTarget','AA15_ESS2_BASETEST_TARGET_PU不是-0.005。');

mgr=[mdl '/SS_Slave2/ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_ISLAND_GFL_SUPPORT_MANAGER'];
lim=[mgr '/AA15_FINAL_GFL_LIMIT_CORE'];
names={'AA15_BASETEST_SELECT_DAMP_D',3;'AA15_BASETEST_SELECT_DAMP_Q',4;'AA15_BASETEST_SELECT_SLOW_Q',5;'AA15_BASETEST_SELECT_LF_Q',17};
for k=1:size(names,1)
    sw=[mgr '/' names{k,1}];
    assert(getSimulinkBlockHandle(sw)>=0,'R1F:SwitchMissing','缺少支撑隔离Switch：%s',sw);
    assert(strcmp(get_param(sw,'BlockType'),'Switch'),'R1F:SwitchType','支撑隔离块类型错误：%s',sw);
    assert(strcmp(get_param(sw,'Criteria'),'u2 > Threshold') && abs(str2double(get_param(sw,'Threshold'))-0.5)<1e-12, ...
        'R1F:SwitchParam','支撑隔离Switch参数改变：%s',sw);
    requireConnection(sw,1,lim,names{k,2});
end

rate=[mdl '/SM_Master/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/PickupRateLimiter'];
requireParam(rate,'RisingSlewLimit','0.01');
requireParam(rate,'FallingSlewLimit','-0.0025');
requireParam(rate,'InitialCondition','0');

% Recorder schema/settings are frozen: no new recording change in R1F.
checkNormalizer([mdl '/SS_Slave2/AA15_BASETEST_G27_NORMALIZER'],119);
checkNormalizer([mdl '/SM_Master/AA15_BASETEST_G29_NORMALIZER'],74);
checkNormalizer([mdl '/SS_Slave2/AA15_BASETEST_G30_NORMALIZER'],144);
checkRecorder([mdl '/SS_Slave2/AA15_ROOTDIAG_ESS2_OPWRITE_G27'],'base_power_r1_g27.mat');
checkRecorder([mdl '/SM_Master/AA15_FREQDIAG_SM_OPWRITE_G29'],'base_power_r1_g29.mat');
checkRecorder([mdl '/SS_Slave2/AA15_FREQDIAG_ESS1_OPWRITE_G30'],'base_power_r1_g30.mat');
end

function checkNormalizer(p,n)
assert(getSimulinkBlockHandle(p)>=0,'R1F:Normalizer','记录正规化子系统缺失：%s',p);
assert(str2double(get_param([p '/DemuxN'],'Outputs'))==n,'R1F:RecorderWidth','%s Demux宽度错误。',p);
assert(str2double(get_param([p '/MuxN'],'Inputs'))==n,'R1F:RecorderWidth','%s Mux宽度错误。',p);
end

function checkRecorder(p,filename)
requireParam(p,'Static_File','off');
requireParam(p,'Filename',filename);
requireParam(p,'file_size','500000000');
requireParam(p,'Nb_Samples','1000');
requireParam(p,'Buffer_size','2097152');
end

function seg=extractBase35(s)
a=strfind(s,'elseif baseOnly && black_substate==35.0');b=strfind(s,'elseif baseOnly && black_substate==40.0');
assert(~isempty(a)&&~isempty(b),'R1F:Segment35','找不到BASETEST state35。');seg=s(a(1):b(1)-1);
end
function seg=extractBase40(s)
a=strfind(s,'elseif baseOnly && black_substate==40.0');b=strfind(s,'elseif baseOnly && black_substate==45.0');
assert(~isempty(a)&&~isempty(b),'R1F:Segment40','找不到BASETEST state40。');seg=s(a(1):b(1)-1);
end

function requireConnection(src,sp,dst,dp)
phs=get_param(src,'PortHandles');phd=get_param(dst,'PortHandles');
assert(sp<=numel(phs.Outport)&&dp<=numel(phd.Inport),'R1F:Ports','端口越界：%s -> %s',src,dst);
ln=get_param(phd.Inport(dp),'Line');
assert(ln~=-1,'R1F:NoLine','目标端口未连接：%s/%d',dst,dp);
actual=get_param(ln,'SrcPortHandle');
assert(actual==phs.Outport(sp),'R1F:WrongLine','连接来源不符：%s/%d -> %s/%d',src,sp,dst,dp);
end
function requireParam(p,n,v)
assert(getSimulinkBlockHandle(p)>=0,'R1F:BlockMissing','块不存在：%s',p);
a=get_param(p,n);assert(strcmp(char(a),char(v)),'R1F:Param','参数改变：%s.%s 实际=%s 期望=%s',p,n,char(a),char(v));
end
function mustContain(s,t)
assert(contains(s,t),'R1F:Semantic','缺少语义标记：%s',t);
end
function c=chartAt(p)
% R1G: return one scalar Stateflow.EMChart handle.
% Important: R2023b uses an explicit scalar EMChart handle before Script property access.
% The proven project scripts first store the handle, then access hit.Script.
rt=sfroot;allCharts=rt.find('-isa','Stateflow.EMChart');c=[];n=0;
for k=1:numel(allCharts)
    try
        if strcmp(char(allCharts(k).Path),p)
            n=n+1;
            if n==1,c=allCharts(k);end
        end
    catch
    end
end
assert(n==1,'R1G:Chart','MATLAB Function实例必须唯一：%s，匹配%d',p,n);
end
function setChartScript(p,s)
c=chartAt(p);
c.Script=s;
drawnow;
end
function s=getChartScript(p)
c=chartAt(p);
s=char(c.Script);
end
function mustCopy(a,b)
[ok,msg]=copyfile(a,b,'f');assert(ok,'R1F:Copy','复制失败：%s',msg);
end
function s=normalizeText(s)
s=strrep(strrep(char(s),sprintf('\r\n'),sprintf('\n')),sprintf('\r'),sprintf('\n'));
end
function h=hashText(s),h=hashBytes(unicode2native(normalizeText(s),'UTF-8'));end
function h=fileHash(p)
f=fopen(p,'rb');assert(f>=0,'R1F:Read','文件不可读：%s',p);c=onCleanup(@()fclose(f)); %#ok<NASGU>
h=hashBytes(fread(f,Inf,'*uint8'));
end
function h=hashBytes(b)
md=java.security.MessageDigest.getInstance('SHA-256');md.update(typecast(uint8(b(:)),'int8'));
d=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(d,2).',1,[]));
end
function p=canonical(p),p=char(java.io.File(char(p)).getCanonicalPath());end
function writeJSON(p,s)
f=fopen(p,'w','n','UTF-8');assert(f>=0,'R1F:Write','无法写入：%s',p);c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',jsonencode(s,'PrettyPrint',true));
end

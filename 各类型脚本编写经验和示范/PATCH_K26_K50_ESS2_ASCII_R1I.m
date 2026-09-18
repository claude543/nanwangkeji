function result = PATCH_K26_K50_ESS2_ASCII_R1I(modelRoot)
% PATCH_K26_K50_ESS2_ASCII_R1I
% Encoding-only compatibility patch for RT-LAB 2024.1 host pre-separation.
% It changes comments only in TWO already-frozen MATLAB Function scripts.
% Executable MATLAB code must remain exactly equivalent after comments are stripped.
% No control logic, block, connection, parameter, recorder, PI, limiter or electrical network is changed.

MODEL='K26_K50_CLEAN_P1';
ADV_REL='SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core';
REST_REL='SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE';
H_ADV_R1F='5728b5d4c19a3e0f50c705c21ec3e8b7e4c44b065913a8b06c1f2aac78b130c0';
H_ADV_R1I='f96d3d3bfba4afb7d3f12bb884cc95a4920ff3487b605c600ea4864dcae9b50d';
H_REST_R1F='59caf18045d25e6580426f9b7f2123692084e4bc25127b3ffce8cacc657e274b';
H_REST_R1I='4d285d40b6f9317fa2f6bb8214406a760c887e27421d5c4c643885d67a4bd3c8';
H_ADV_CODE='e8c8f5be529aaea09da57afecf8d876f832dfc4707c2fe001c83b58ecce2e1fc';
H_REST_CODE='bcc81c59f4e98f11b3db0965fd741ff74471c7be4f95043b90bc3e42c3740c7b';
PKG=fileparts(mfilename('fullpath'));
ADV_PAY=fullfile(PKG,'payload','F006_R1I_ASCII.txt');
REST_PAY=fullfile(PKG,'payload','F099_R1I_ASCII.txt');
assert(isfile(ADV_PAY)&&isfile(REST_PAY),'R1I:Assets','ASCII payload files are missing.');
advTarget=normalizeText(fileread(ADV_PAY));restTarget=normalizeText(fileread(REST_PAY));
assert(isASCII(advTarget)&&isASCII(restTarget),'R1I:PayloadASCII','Target payload is not ASCII-only.');
assert(strcmp(hashText(advTarget),H_ADV_R1I),'R1I:AdvPayloadHash','Advanced target payload hash mismatch.');
assert(strcmp(hashText(restTarget),H_REST_R1I),'R1I:RestPayloadHash','Restore target payload hash mismatch.');
assert(strcmp(hashText(codeProjection(advTarget)),H_ADV_CODE),'R1I:AdvCodePayload','Advanced executable code changed in target payload.');
assert(strcmp(hashText(codeProjection(restTarget)),H_REST_CODE),'R1I:RestCodePayload','Restore executable code changed in target payload.');

if nargin<1 || isempty(modelRoot)
    if bdIsLoaded(MODEL)
        modelRoot=fileparts(get_param(MODEL,'FileName'));
    else
        modelRoot='D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V7\models\K26_K50_CLEAN_P1';
    end
end
modelFile=canonical(fullfile(char(modelRoot),[MODEL '.slx']));
assert(isfile(modelFile),'R1I:MissingModel','Official model file not found: %s',modelFile);
if bdIsLoaded(MODEL)
    assert(strcmpi(canonical(get_param(MODEL,'FileName')),modelFile),'R1I:WrongModel','Loaded model is not the official model file.');
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1I:Dirty','Model has unsaved changes.');
    assert(strcmp(get_param(MODEL,'SimulationStatus'),'stopped'),'R1I:Running','Simulink model must be stopped.');
end
out=fullfile(fileparts(modelFile),['PATCH_ESS2_ASCII_R1I_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);mkdir(out);
result=struct('version','ESS2_BASETEST_ASCII_R1I_20260916','status','STARTED','modelFile',modelFile,'outputDir',out,'backupFile','');
writeJSON(fullfile(out,'RESULT.json'),result);
formalSaveAttempted=false;backupFile='';
try
    if ~bdIsLoaded(MODEL),load_system(modelFile);end
    [advBefore,restBefore]=preflight(MODEL,H_ADV_R1F,H_ADV_R1I,H_REST_R1F,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    result.beforeAdvancedHash=advBefore;result.beforeRestoreHash=restBefore;
    if strcmp(advBefore,H_ADV_R1I)&&strcmp(restBefore,H_REST_R1I)
        result.status='ALREADY_ASCII_READY_FOR_VERIFY';writeJSON(fullfile(out,'RESULT.json'),result);
        fprintf('R1I already exists. Run VERIFY_K26_K50_ESS2_ASCII_R1I.
');return;
    end
    close_system(MODEL,0);

    scratchDir=fullfile(out,'SCRATCH');mkdir(scratchDir);scratchFile=fullfile(scratchDir,[MODEL '.slx']);
    mustCopy(modelFile,scratchFile);assert(strcmp(fileHash(modelFile),fileHash(scratchFile)),'R1I:ScratchCopy','Scratch copy mismatch.');
    load_system(scratchFile);preflight(MODEL,H_ADV_R1F,H_ADV_R1I,H_REST_R1F,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    applyASCII(MODEL,advTarget,restTarget);verifyFinal(MODEL,H_ADV_R1I,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    save_system(MODEL);close_system(MODEL,0);load_system(scratchFile);verifyFinal(MODEL,H_ADV_R1I,H_REST_R1I,H_ADV_CODE,H_REST_CODE);close_system(MODEL,0);

    backupFile=fullfile(out,[MODEL '_BEFORE_ASCII_R1I.slx']);mustCopy(modelFile,backupFile);
    assert(strcmp(fileHash(modelFile),fileHash(backupFile)),'R1I:BackupHash','Backup mismatch.');
    result.backupFile=backupFile;writeJSON(fullfile(out,'RESULT.json'),result);

    load_system(modelFile);preflight(MODEL,H_ADV_R1F,H_ADV_R1I,H_REST_R1F,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    applyASCII(MODEL,advTarget,restTarget);verifyFinal(MODEL,H_ADV_R1I,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    formalSaveAttempted=true;save_system(MODEL);close_system(MODEL,0);load_system(modelFile);
    verifyFinal(MODEL,H_ADV_R1I,H_REST_R1I,H_ADV_CODE,H_REST_CODE);
    assert(strcmp(get_param(MODEL,'Dirty'),'off'),'R1I:FormalDirty','Official model is dirty after reload.');
    result.afterAdvancedHash=hashText(getChartScript([MODEL '/' ADV_REL]));
    result.afterRestoreHash=hashText(getChartScript([MODEL '/' REST_REL]));
    result.status='SAVED_RELOADED_ASCII_READY_FOR_VERIFY';
    result.next='VERIFY_K26_K50_ESS2_ASCII_R1I; then move patch packages out of model folder and RT-LAB Rebuild All';
    writeJSON(fullfile(out,'RESULT.json'),result);
    fprintf('
R1I encoding-only patch saved. Control logic is unchanged.
Result folder: %s
',out);
catch ME
    result.status='FAILED';result.errorIdentifier=ME.identifier;result.errorMessage=ME.message;
    try result.errorReport=getReport(ME,'extended','hyperlinks','off');catch,end
    if bdIsLoaded(MODEL),try close_system(MODEL,0);catch,end,end
    if formalSaveAttempted && ~isempty(backupFile) && isfile(backupFile)
        try mustCopy(backupFile,modelFile);load_system(modelFile);result.status='FAILED_ROLLED_BACK_TO_FULL_BACKUP';result.rollback='PASS';
        catch RB,result.rollback=['FAIL: ' RB.message];end
    end
    writeJSON(fullfile(out,'RESULT.json'),result);fprintf(2,'R1I patch failed: %s
Result folder: %s
',ME.message,out);rethrow(ME);
end
end

function [ha,hr]=preflight(mdl,HAF,HAI,HRF,HRI,HAC,HRC)
a=getChartScript([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core']);
r=getChartScript([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE']);
ha=hashText(a);hr=hashText(r);
assert(any(strcmp(ha,{HAF,HAI})),'R1I:AdvUnknown','Advanced Strategy Core is not the known R1F/R1I version: %s',ha);
assert(any(strcmp(hr,{HRF,HRI})),'R1I:RestUnknown','Restore Executor is not the known R1F/R1I version: %s',hr);
assert(strcmp(hashText(codeProjection(a)),HAC),'R1I:AdvCodeChanged','Advanced executable code differs from frozen R1F.');
assert(strcmp(hashText(codeProjection(r)),HRC),'R1I:RestCodeChanged','Restore executable code differs from frozen R1F.');
end
function applyASCII(mdl,a,r)
setChartScript([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core'],a);
setChartScript([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE'],r);drawnow;
end
function verifyFinal(mdl,HA,HR,HAC,HRC)
a=getChartScript([mdl '/SM_Master/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core']);
r=getChartScript([mdl '/SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE']);
assert(isASCII(a)&&isASCII(r),'R1I:NonASCII','Non-ASCII text remains in one of the two modified MATLAB Function scripts.');
assert(strcmp(hashText(a),HA),'R1I:AdvHash','Advanced ASCII script hash mismatch.');
assert(strcmp(hashText(r),HR),'R1I:RestHash','Restore ASCII script hash mismatch.');
assert(strcmp(hashText(codeProjection(a)),HAC),'R1I:AdvCodeChangedFinal','Advanced executable code changed.');
assert(strcmp(hashText(codeProjection(r)),HRC),'R1I:RestCodeChangedFinal','Restore executable code changed.');
end
function tf=isASCII(s),tf=all(double(char(s))<128);end
function s=codeProjection(s)
s=normalizeText(s);L=splitlines(string(s));O=strings(size(L));
for k=1:numel(L),x=char(L(k));p=strfind(x,'%');if ~isempty(p),x=x(1:p(1)-1);end;O(k)=string(deblank(x));end
s=char(join(O,newline));s=strtrim(s);s=[s newline];
end
function c=chartAt(p)
rt=sfroot;allCharts=rt.find('-isa','Stateflow.EMChart');c=[];n=0;
for k=1:numel(allCharts),try;if strcmp(char(allCharts(k).Path),p),n=n+1;if n==1,c=allCharts(k);end;end;catch,end;end
assert(n==1,'R1I:Chart','MATLAB Function instance must be unique: %s, matches=%d',p,n);
end
function s=getChartScript(p),c=chartAt(p);s=normalizeText(char(c.Script));end
function setChartScript(p,s),c=chartAt(p);c.Script=normalizeText(s);end
function s=normalizeText(s),s=strrep(char(s),sprintf('\r\n'),sprintf('\n'));s=strrep(s,sprintf('\r'),sprintf('\n'));end
function h=hashText(s),md=java.security.MessageDigest.getInstance('SHA-256');md.update(uint8(unicode2native(normalizeText(s),'UTF-8')));h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));end
function h=fileHash(p),md=java.security.MessageDigest.getInstance('SHA-256');fis=java.io.FileInputStream(java.io.File(p));d=java.security.DigestInputStream(fis,md);b=zeros(1,8192,'int8');while d.read(b,0,numel(b))~=-1,end;d.close();h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));end
function p=canonical(p),p=char(java.io.File(p).getCanonicalPath());end
function mustCopy(a,b),[ok,msg]=copyfile(a,b,'f');assert(ok,'R1I:Copy','Copy failed: %s',msg);end
function writeJSON(p,x),fid=fopen(p,'w');assert(fid>0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(x,'PrettyPrint',true));end

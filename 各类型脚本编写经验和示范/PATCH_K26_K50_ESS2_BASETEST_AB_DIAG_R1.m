function result = PATCH_K26_K50_ESS2_BASETEST_AB_DIAG_R1(modelRoot)
% PATCH_K26_K50_ESS2_BASETEST_AB_DIAG_R1
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 BASETEST A/B diagnostic patch R1
%
% GOAL
% ----
% Add the minimum diagnostic controls needed to separate:
%   A0) current execution only, zero direct dq-current reference;
%   A1) current execution only, small direct d-axis current reference;
%   B-P0) P power loop only, Pref = 0, Q loop disabled.
%
% IMPORTANT
% ---------
% This patch does NOT tune the controller.  It does NOT modify:
%   - ESS1 GFM;
%   - SPS electrical network / breakers / L-C / transformer;
%   - S14 sequence;
%   - Current Adapter MATLAB Function;
%   - current PI parameters;
%   - P/Q PI Kp/Ki;
%   - existing BASETEST support-isolation selectors;
%   - G27/G29/G30 recorder widths or mappings.
%
% The patch only:
%   1) brings the existing AA15_BASETEST_ENABLE into ESS2 Power Control Loop;
%   2) adds independent P/Q outer-loop enable gates (BASETEST-only);
%   3) adds a BASETEST-only direct dq-current selector at the Power Loop output;
%   4) direct current stays zero until RestoreAlpha is active, then is ramped;
%   5) direct-current mode automatically forces P/Q outer loops OFF.
%
% TRANSACTION POLICY (copied from proven project patch workflow)
% --------------------------------------------------------------
% current semantic preflight
% -> byte-identical scratch copy
% -> scratch apply / postassert / save once / close-reload / postassert
% -> whole-file formal backup
% -> formal re-preflight
% -> formal apply / postassert / save once
% -> close-reload / persistence postassert
% -> rollback whole file if any formal-stage failure occurs.
%
% Whole-SLX SHA is recorded, NOT used as semantic identity hard gate.
% MATLAB R2023b.
% =========================================================================

VERSION='K26_K50_ESS2_BASETEST_AB_DIAG_R1_20260916';
MODEL='K26_K50_CLEAN_P1';

DEF_DIRECT_SLEW=0.0025; % pu current / s, symmetric diagnostic ramp

if nargin<1 || isempty(modelRoot)
    modelRoot=['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot=canonicalPath(char(modelRoot));
modelFile=fullfile(modelRoot,[MODEL '.slx']);
if ~isfile(modelFile)
    error('E2ABR1:ModelMissing','Model missing: %s',modelFile);
end

% Keep generated reports OUTSIDE the RT-LAB model directory.  This also
% avoids repeating the previous host_preseparate encoding/path pollution.
modelsParent=fileparts(modelRoot);
logRoot=fullfile(modelsParent,'E2_PATCH_LOGS');
backupRoot=fullfile(modelsParent,'E2_PATCH_BACKUPS');
if ~isfolder(logRoot),mkdir(logRoot);end
if ~isfolder(backupRoot),mkdir(backupRoot);end

stamp=datestr(now,'yyyymmdd_HHMMSS_FFF');
workDir=fullfile(logRoot,['ESS2_BASETEST_AB_DIAG_R1_' stamp]);
mkdir(workDir);
logFile=fullfile(workDir,'PATCH_LOG.txt');
fid=fopen(logFile,'w','n','UTF-8');
if fid<0,error('E2ABR1:Log','Cannot create log: %s',logFile);end
cFid=onCleanup(@()safeClose(fid)); %#ok<NASGU>

result=struct();
result.version=VERSION;
result.modelFile=modelFile;
result.workDir=workDir;
result.sourceSha256=sha256File(modelFile);
result.status='STARTED';

fprintf(fid,'ESS2 BASETEST A/B diagnostic patch R1\n');
fprintf(fid,'Model: %s\n',modelFile);
fprintf(fid,'Source SHA256 (record only): %s\n',result.sourceSha256);
fprintf(fid,'Start: %s\n\n',datestr(now,31));

% If the formal model is already loaded, accept ONLY the exact file and
% Dirty=off.  Close it before same-name scratch work.
wasLoaded=bdIsLoaded(MODEL);
if wasLoaded
    loaded=canonicalPath(get_param(MODEL,'FileName'));
    if ~strcmpi(loaded,modelFile)
        error('E2ABR1:WrongLoaded','Same-name model loaded from foreign path: %s',loaded);
    end
    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('E2ABR1:Dirty','Formal model is Dirty=on. Resolve/save/discard manual edits first.');
    end
    close_system(MODEL,0);
end

% =========================================================================
% 1. Current semantic preflight (read-only)
% =========================================================================
loadSystemExactFile(modelFile);
base=preflightCurrentModel(MODEL);
close_system(MODEL,0);

writeModificationMap(fullfile(workDir,'MODIFICATION_MAP.csv'),base);
writePreflightSummary(fullfile(workDir,'PREFLIGHT_SUMMARY.txt'),base);

fprintf(fid,'[PASS] Current semantic preflight.\n');
fprintf(fid,'  P PI : %s | Kp=%s Ki=%s Init=%s\n',base.pPI,base.pKpRaw,base.pKiRaw,base.pInitRaw);
fprintf(fid,'  Q PI : %s | Kp=%s Ki=%s Init=%s\n',base.qPI,base.qKpRaw,base.qKiRaw,base.qInitRaw);
fprintf(fid,'  Original PowerLoop output source: %s#%d\n',base.powerOutSource,base.powerOutSourcePort);

% =========================================================================
% 2. Byte-identical scratch apply / save / persistence
% =========================================================================
scratchDir=fullfile(tempdir,['E2ABR1_' nonce8()]);
mkdir(scratchDir);
cScratch=onCleanup(@()safeRmdir(scratchDir)); %#ok<NASGU>
scratchFile=fullfile(scratchDir,[MODEL '.slx']);
[ok,msg]=copyfile(modelFile,scratchFile,'f');
if ~ok,error('E2ABR1:ScratchCopy','Scratch copy failed: %s',msg);end
if ~strcmpi(sha256File(scratchFile),sha256File(modelFile))
    error('E2ABR1:ScratchSHA','Scratch copy is not byte-identical.');
end

loadSystemExactFile(scratchFile);
scratchBase=preflightCurrentModel(MODEL);
assertBaselineEquivalent(base,scratchBase,'scratch preflight');
applyPatchToLoadedModel(MODEL,DEF_DIRECT_SLEW);
postassertPatchedModel(MODEL,scratchBase,DEF_DIRECT_SLEW);
save_system(MODEL); % scratch: exactly once
scratchSavedSha=sha256File(scratchFile);
close_system(MODEL,0);

loadSystemExactFile(scratchFile);
postassertPatchedModel(MODEL,scratchBase,DEF_DIRECT_SLEW);
if ~strcmpi(get_param(MODEL,'Dirty'),'off')
    error('E2ABR1:ScratchDirty','Scratch model Dirty after close/reload.');
end
close_system(MODEL,0);

fprintf(fid,'[PASS] Scratch apply / postassert / save-once / reload / persistence.\n');
fprintf(fid,'Scratch patched SHA256: %s\n',scratchSavedSha);

% =========================================================================
% 3. Whole-file formal backup
% =========================================================================
backupFile=fullfile(backupRoot,[MODEL '_PRE_ESS2_BASETEST_AB_DIAG_R1_' stamp '.slx']);
[ok,msg]=copyfile(modelFile,backupFile,'f');
if ~ok,error('E2ABR1:BackupCopy','Formal backup failed: %s',msg);end
backupSha=sha256File(backupFile);
if ~strcmpi(backupSha,sha256File(modelFile))
    error('E2ABR1:BackupSHA','Formal backup is not byte-identical.');
end
result.backupFile=backupFile;
result.backupSha256=backupSha;
fprintf(fid,'[PASS] Formal whole-file backup: %s\n',backupFile);

% =========================================================================
% 4. Formal apply.  Any failure -> whole-file rollback.
% =========================================================================
formalTouched=false;
try
    loadSystemExactFile(modelFile);
    formalBase=preflightCurrentModel(MODEL);
    assertBaselineEquivalent(base,formalBase,'formal re-preflight');
    fprintf(fid,'[PASS] Formal re-preflight.\n');

    applyPatchToLoadedModel(MODEL,DEF_DIRECT_SLEW);
    formalTouched=true;
    postassertPatchedModel(MODEL,formalBase,DEF_DIRECT_SLEW);

    save_system(MODEL); % formal: exactly once
    result.patchedSha256=sha256File(modelFile);
    fprintf(fid,'[PASS] Formal save exactly once. Patched SHA256: %s\n',result.patchedSha256);

    close_system(MODEL,0);
    loadSystemExactFile(modelFile);
    postassertPatchedModel(MODEL,formalBase,DEF_DIRECT_SLEW);
    if ~strcmpi(get_param(MODEL,'Dirty'),'off')
        error('E2ABR1:FormalDirty','Formal model Dirty after persistence reload.');
    end
    close_system(MODEL,0);
    fprintf(fid,'[PASS] Formal close/reload persistence postassert.\n');

catch ME
    try,closeIfLoaded(MODEL);catch,end
    if formalTouched || isfile(backupFile)
        [rbok,rbmsg]=copyfile(backupFile,modelFile,'f');
        if rbok
            fprintf(fid,'[ROLLBACK PASS] Whole-file backup restored after formal-stage error.\n');
        else
            fprintf(fid,'[ROLLBACK FAILED] %s\n',rbmsg);
        end
    end
    result.status='FAILED_ROLLED_BACK_OR_ATTEMPTED';
    result.error=getReport(ME,'extended','hyperlinks','off');
    writeJson(fullfile(workDir,'PATCH_RESULT.json'),result);
    rethrow(ME);
end

% =========================================================================
% 5. Final result
% =========================================================================
result.status='PATCH_PASS_RUN_INDEPENDENT_VERIFIER_BEFORE_RTLAB_REBUILD';
result.directSlewPuPerS=DEF_DIRECT_SLEW;
result.parameters=struct( ...
    'P_LOOP_ENABLE','CFG_E2_DIAG_P_LOOP_ENABLE', ...
    'Q_LOOP_ENABLE','CFG_E2_DIAG_Q_LOOP_ENABLE', ...
    'DIRECT_IREF_ENABLE','CFG_E2_DIAG_DIRECT_IREF_ENABLE', ...
    'DIRECT_ID_TARGET_PU','CFG_E2_DIAG_DIRECT_ID_TARGET_PU', ...
    'DIRECT_IQ_TARGET_PU','CFG_E2_DIAG_DIRECT_IQ_TARGET_PU');
result.note=['Kp/Ki are intentionally NOT modified by this patch. ' ...
    'The existing P PI path and Kp/Ki are recorded for later RT-LAB parameter discovery ' ...
    'only after A0/A1/B-P0 causal isolation.'];
writeJson(fullfile(workDir,'PATCH_RESULT.json'),result);

fprintf(fid,'\n============================================================\n');
fprintf(fid,' ESS2 BASETEST A/B DIAGNOSTIC PATCH R1 : PASS\n');
fprintf(fid,'============================================================\n');
fprintf(fid,'Next:\n');
fprintf(fid,'  1) Run VERIFY_K26_K50_ESS2_BASETEST_AB_DIAG_R1\n');
fprintf(fid,'  2) Only if verifier PASS: RT-LAB Rebuild All ONCE\n');
fprintf(fid,'  3) Do NOT reuse old Runner R3 for A/B experiments.\n');
fprintf(fid,'  4) New Python runner must be written from the rebuilt parameter/signal contract.\n');
fprintf(fid,'WorkDir: %s\n',workDir);
fprintf(fid,'Backup : %s\n',backupFile);

fprintf('\nPATCH PASS.\n');
fprintf('WorkDir: %s\n',workDir);
fprintf('Run the independent verifier BEFORE RT-LAB Rebuild.\n');
end

% =========================================================================
% Current-model preflight
% =========================================================================
function B=preflightCurrentModel(mdl)
task=[mdl '/SS_Slave2'];
SM=[mdl '/SM_Master'];
control=[task '/ESS2_Control'];
power=[control '/Power Control Loop'];
wrapper=[control '/AA15_GFL_ISLAND_SUPPORT'];
adapter=[wrapper '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];
adapterCore=[adapter '/CORE'];
executorCore=[task '/AA15_ESS2_RESTORE_EXECUTOR/CORE'];
strategyCore=[SM '/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core'];
baseEnable=[task '/AA15_BASETEST_ENABLE'];

mustBlock(task);mustBlock(SM);mustBlock(control);mustBlock(power);mustBlock(wrapper);
mustBlock(adapter);mustBlock(adapterCore);mustBlock(executorCore);mustBlock(strategyCore);
mustBlock(baseEnable);

% Current post-BASETEST model contract.
requireEq(numel(get_param(control,'PortHandles').Inport),10,'ESS2_Control inport count prepatch');
requireEq(numel(get_param(power,'PortHandles').Inport),7,'Power Control Loop inport count prepatch');
requireEq(numel(get_param(wrapper,'PortHandles').Inport),20,'GFL wrapper inport count');
requireEq(numel(get_param(adapter,'PortHandles').Inport),7,'Current Adapter inport count');

pSum=[power '/Add'];
qSum=[power '/Add2'];
pProd=[power '/AA15_RESTORE_PERR_ALPHA'];
qProd=[power '/AA15_RESTORE_QERR_ALPHA'];
pAlpha=[power '/RestoreAlpha'];
for p={pSum,qSum,pProd,qProd,pAlpha}
    mustBlock(p{1});
end
requireStr(get_param(pSum,'Inputs'),'+-','P error sign');
requireStr(get_param(qSum,'Inputs'),'+-','Q error sign');

% Exact current P/Q error source semantics.  A1 direct-d injection relies on
% the proven convention: PowerLoop Mux input1=P-PI=d-axis, input2=Q-PI=q-axis.
for b={ [power '/Pmeas'],[power '/Pref'],[power '/Qmeas'],[power '/Qref'] }
    mustBlock(b{1});
end
assertInputSource(pSum,1,[power '/Pref'],1);
assertInputSource(pSum,2,[power '/Pmeas'],1);
assertInputSource(qSum,1,[power '/Qmeas'],1);
assertInputSource(qSum,2,[power '/Qref'],1);
assertInputSource(pProd,1,pSum,1);
assertInputSource(qProd,1,qSum,1);

% Current alpha must still directly feed both error products before this patch.
if ~directConnectionExists(pAlpha,1,pProd,2) || ~directConnectionExists(pAlpha,1,qProd,2)
    error('E2ABR1:PreAlpha','Current RestoreAlpha->P/Q error-gate wiring is not the expected baseline.');
end

pPI=uniqueDstFrom(pProd,power,'P PI');
qPI=uniqueDstFrom(qProd,power,'Q PI');
[pKpRaw,pKiRaw,pInitRaw,pLimitRaw,pInt]=piContract(pPI,'P');
[qKpRaw,qKiRaw,qInitRaw,qLimitRaw,qInt]=piContract(qPI,'Q');

requireNumericNear(resolveNumeric(mdl,pKpRaw),0.06,1e-12,'P Kp');
requireNumericNear(resolveNumeric(mdl,pKiRaw),2.0,1e-12,'P Ki');
requireNumericNear(resolveNumeric(mdl,qKpRaw),0.06,1e-12,'Q Kp');
requireNumericNear(resolveNumeric(mdl,qKiRaw),2.0,1e-12,'Q Ki');
requireNumericNear(resolveNumeric(mdl,pInitRaw),0.0,1e-12,'P Init');
requireNumericNear(resolveNumeric(mdl,qInitRaw),0.0,1e-12,'Q Init');
if ~strcmpi(safeGet(pInt,'ExternalReset'),'none') || ~strcmpi(safeGet(qInt,'ExternalReset'),'none')
    error('E2ABR1:PIReset','P/Q PI ExternalReset changed; re-audit before patching.');
end

powerOut=[power '/IdIqrefF'];
mustBlock(powerOut);
[src,sp]=inputSource(powerOut,1);
if isempty(src) || ~startsWith(src,[power '/'])
    error('E2ABR1:PowerOutSource','Power output source is not uniquely local: %s',src);
end
if ~strcmp(safeGet(src,'BlockType'),'Mux') || str2double(safeGet(src,'Inputs'))~=2
    error('E2ABR1:PowerOutMux','IdIqrefF must be driven by the original 2-input PowerLoop Mux, observed %s.',src);
end
assertInputSource(src,1,pPI,1);
assertInputSource(src,2,qPI,1);

% Existing BASETEST isolation must remain installed.
supportMarkers={ ...
    [wrapper '/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_BASETEST_SELECT_DAMP_D'], ...
    [wrapper '/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_BASETEST_SELECT_DAMP_Q'], ...
    [wrapper '/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_BASETEST_SELECT_SLOW_Q'], ...
    [wrapper '/AA15_ISLAND_GFL_SUPPORT_MANAGER/AA15_BASETEST_SELECT_LF_Q']};
for k=1:numel(supportMarkers),mustBlock(supportMarkers{k});end

% New patch markers must not exist.
newMarkers={ ...
    [control '/BaseTestDiagEnable'], ...
    [power '/BaseTestDiagEnable'], ...
    [power '/CFG_E2_DIAG_P_LOOP_ENABLE'], ...
    [power '/CFG_E2_DIAG_Q_LOOP_ENABLE'], ...
    [power '/CFG_E2_DIAG_DIRECT_IREF_ENABLE'], ...
    [power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'], ...
    [power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'], ...
    [power '/AA15_DIAG_DIRECT_IREF_SELECT']};
for k=1:numel(newMarkers),mustNotBlock(newMarkers{k});end

% Capture algorithm/source identities that this patch must not touch.
B=struct();
B.task=task;B.SM=SM;B.control=control;B.power=power;B.wrapper=wrapper;
B.adapter=adapter;B.adapterCore=adapterCore;B.executorCore=executorCore;B.strategyCore=strategyCore;
B.baseEnable=baseEnable;
B.pSum=pSum;B.qSum=qSum;B.pProd=pProd;B.qProd=qProd;B.pAlpha=pAlpha;
B.pPI=pPI;B.qPI=qPI;B.pInt=pInt;B.qInt=qInt;
B.pKpRaw=pKpRaw;B.pKiRaw=pKiRaw;B.pInitRaw=pInitRaw;B.pLimitRaw=pLimitRaw;
B.qKpRaw=qKpRaw;B.qKiRaw=qKiRaw;B.qInitRaw=qInitRaw;B.qLimitRaw=qLimitRaw;
B.powerOut=powerOut;B.powerOutSource=src;B.powerOutSourcePort=sp;
B.adapterSha=hashText(emChartScript(adapterCore));
B.executorSha=hashText(emChartScript(executorCore));
B.strategySha=hashText(emChartScript(strategyCore));
B.supportMarkers=supportMarkers;

% Preserve OpWrite count/group/input endpoint contracts.
[B.opGroups,B.opSources]=captureOpWriteContracts(mdl);

% Preserve all existing Power Loop external output consumers.
B.powerParentOutConsumers=captureSubsystemOutConsumers(power);

% Existing current-adapter alpha contract remains untouched.
if ~containsNoSpace(emChartScript(adapterCore),'iref_used=a*iref')
    error('E2ABR1:AdapterSemantic','Current Adapter no longer contains iref_used=a*iref.');
end
end

function assertBaselineEquivalent(A,B,label)
requireStr(B.pPI,A.pPI,[label ' P PI path']);
requireStr(B.qPI,A.qPI,[label ' Q PI path']);
requireStr(B.powerOutSource,A.powerOutSource,[label ' power output source']);
requireEq(B.powerOutSourcePort,A.powerOutSourcePort,[label ' power output source port']);
requireStr(B.adapterSha,A.adapterSha,[label ' adapter SHA']);
requireStr(B.executorSha,A.executorSha,[label ' executor SHA']);
requireStr(B.strategySha,A.strategySha,[label ' strategy SHA']);
if ~isequal(B.opGroups,A.opGroups) || ~isequal(B.opSources,A.opSources)
    error('E2ABR1:BaselineOpWrite','%s OpWrite contract drift.',label);
end
end

% =========================================================================
% Apply patch
% =========================================================================
function applyPatchToLoadedModel(mdl,directSlew)
task=[mdl '/SS_Slave2'];
control=[task '/ESS2_Control'];
power=[control '/Power Control Loop'];
baseEnable=[task '/AA15_BASETEST_ENABLE'];

% -------------------------------------------------------------------------
% A. Bring the existing BASETEST flag into ESS2_Control and Power Loop.
% -------------------------------------------------------------------------
add_block('built-in/Inport',[control '/BaseTestDiagEnable'], ...
    'Port','11','Position',[35 515 115 529]);
addLineByPorts(task,baseEnable,1,control,11);

add_block('built-in/Inport',[power '/BaseTestDiagEnable'], ...
    'Port','8','Position',[35 405 115 419]);
addLineByPorts(control,[control '/BaseTestDiagEnable'],1,power,8);

% -------------------------------------------------------------------------
% B. Diagnostic online parameters.  All defaults preserve current behavior.
% -------------------------------------------------------------------------
posX=diagnosticBaseX(power);
addConst(power,'CFG_E2_DIAG_P_LOOP_ENABLE','1',[posX 40 posX+140 70]);
addConst(power,'CFG_E2_DIAG_Q_LOOP_ENABLE','1',[posX 85 posX+140 115]);
addConst(power,'CFG_E2_DIAG_DIRECT_IREF_ENABLE','0',[posX 130 posX+140 160]);
addConst(power,'CFG_E2_DIAG_DIRECT_ID_TARGET_PU','0',[posX 175 posX+140 205]);
addConst(power,'CFG_E2_DIAG_DIRECT_IQ_TARGET_PU','0',[posX 220 posX+140 250]);
addConst(power,'AA15_DIAG_ONE','1',[posX 280 posX+90 310]);
addConst(power,'AA15_DIAG_ZERO','0',[posX 325 posX+90 355]);

% Direct enable is hard-gated by BASETEST.
directEff=[power '/AA15_DIAG_DIRECT_ENABLE_EFF'];
add_block('built-in/Product',directEff,'Inputs','**','Position',[posX+190 125 posX+235 160]);
addLineByPorts(power,[power '/BaseTestDiagEnable'],1,directEff,1);
addLineByPorts(power,[power '/CFG_E2_DIAG_DIRECT_IREF_ENABLE'],1,directEff,2);

% Direct mode automatically forces BOTH outer loops off.  This prevents
% hidden PI state accumulation during A0/A1 even if an operator leaves the
% P/Q enable constants at their safe default 1.
pNoDirect=[power '/AA15_DIAG_P_CFG_WHEN_NOT_DIRECT'];
qNoDirect=[power '/AA15_DIAG_Q_CFG_WHEN_NOT_DIRECT'];
addSwitch(power,pNoDirect,[posX+280 35 posX+360 90]);
addSwitch(power,qNoDirect,[posX+280 95 posX+360 150]);
addLineByPorts(power,[power '/AA15_DIAG_ZERO'],1,pNoDirect,1);
addLineByPorts(power,directEff,1,pNoDirect,2);
addLineByPorts(power,[power '/CFG_E2_DIAG_P_LOOP_ENABLE'],1,pNoDirect,3);
addLineByPorts(power,[power '/AA15_DIAG_ZERO'],1,qNoDirect,1);
addLineByPorts(power,directEff,1,qNoDirect,2);
addLineByPorts(power,[power '/CFG_E2_DIAG_Q_LOOP_ENABLE'],1,qNoDirect,3);

% Outside BASETEST => P/Q enable = 1 exactly.
pEff=[power '/AA15_DIAG_P_LOOP_ENABLE_EFF'];
qEff=[power '/AA15_DIAG_Q_LOOP_ENABLE_EFF'];
addSwitch(power,pEff,[posX+410 35 posX+500 90]);
addSwitch(power,qEff,[posX+410 95 posX+500 150]);
addLineByPorts(power,pNoDirect,1,pEff,1);
addLineByPorts(power,[power '/BaseTestDiagEnable'],1,pEff,2);
addLineByPorts(power,[power '/AA15_DIAG_ONE'],1,pEff,3);
addLineByPorts(power,qNoDirect,1,qEff,1);
addLineByPorts(power,[power '/BaseTestDiagEnable'],1,qEff,2);
addLineByPorts(power,[power '/AA15_DIAG_ONE'],1,qEff,3);

% RestoreAlpha still carries the existing release timing; P/Q enable only
% decides whether the corresponding outer-loop error is allowed through.
pAlphaEff=[power '/AA15_DIAG_P_ALPHA_EFF'];
qAlphaEff=[power '/AA15_DIAG_Q_ALPHA_EFF'];
add_block('built-in/Product',pAlphaEff,'Inputs','**','Position',[posX+555 35 posX+600 70]);
add_block('built-in/Product',qAlphaEff,'Inputs','**','Position',[posX+555 100 posX+600 135]);
addLineByPorts(power,[power '/RestoreAlpha'],1,pAlphaEff,1);
addLineByPorts(power,pEff,1,pAlphaEff,2);
addLineByPorts(power,[power '/RestoreAlpha'],1,qAlphaEff,1);
addLineByPorts(power,qEff,1,qAlphaEff,2);

% Replace ONLY the alpha inputs of the already-proven P/Q error products.
connectReplacingInputAbs(power,pAlphaEff,1,[power '/AA15_RESTORE_PERR_ALPHA'],2);
connectReplacingInputAbs(power,qAlphaEff,1,[power '/AA15_RESTORE_QERR_ALPHA'],2);

% -------------------------------------------------------------------------
% C. Direct dq-current diagnostic branch.
% It stays exactly zero until RestoreAlpha > 0.5, then ramps at a fixed
% symmetric rate.  The downstream Current Adapter still applies its real
% RestoreAlpha and real measured-current feedback.
% -------------------------------------------------------------------------
alphaActive=[power '/AA15_DIAG_ALPHA_ACTIVE'];
add_block('simulink/Logic and Bit Operations/Compare To Constant',alphaActive, ...
    'relop','>','const','0.5','Position',[posX+190 285 posX+310 320]);
addLineByPorts(power,[power '/RestoreAlpha'],1,alphaActive,1);

idActive=[power '/AA15_DIAG_DIRECT_ID_ACTIVE_TARGET'];
iqActive=[power '/AA15_DIAG_DIRECT_IQ_ACTIVE_TARGET'];
add_block('built-in/Product',idActive,'Inputs','***','Position',[posX+360 190 posX+405 225]);
add_block('built-in/Product',iqActive,'Inputs','***','Position',[posX+360 245 posX+405 280]);
addLineByPorts(power,directEff,1,idActive,1);
addLineByPorts(power,alphaActive,1,idActive,2);
addLineByPorts(power,[power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'],1,idActive,3);
addLineByPorts(power,directEff,1,iqActive,1);
addLineByPorts(power,alphaActive,1,iqActive,2);
addLineByPorts(power,[power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'],1,iqActive,3);

idRate=[power '/AA15_DIAG_DIRECT_ID_RATE'];
iqRate=[power '/AA15_DIAG_DIRECT_IQ_RATE'];
add_block('simulink/Discontinuities/Rate Limiter',idRate, ...
    'RisingSlewLimit',num2str(directSlew,17), ...
    'FallingSlewLimit',num2str(-directSlew,17), ...
    'InitialCondition','0','Position',[posX+455 185 posX+575 230]);
add_block('simulink/Discontinuities/Rate Limiter',iqRate, ...
    'RisingSlewLimit',num2str(directSlew,17), ...
    'FallingSlewLimit',num2str(-directSlew,17), ...
    'InitialCondition','0','Position',[posX+455 245 posX+575 290]);
addLineByPorts(power,idActive,1,idRate,1);
addLineByPorts(power,iqActive,1,iqRate,1);

directMux=[power '/AA15_DIAG_DIRECT_IREF_MUX'];
add_block('built-in/Mux',directMux,'Inputs','2','Position',[posX+630 195 posX+635 280]);
addLineByPorts(power,idRate,1,directMux,1);
addLineByPorts(power,iqRate,1,directMux,2);

% Insert one selector immediately before the existing IdIqrefF outport.
powerOut=[power '/IdIqrefF'];
[origSrc,origPort]=inputSource(powerOut,1);
if isempty(origSrc) || ~startsWith(origSrc,[power '/'])
    error('E2ABR1:ApplyOutSource','Cannot uniquely resolve original local PowerLoop output source.');
end

directSelect=[power '/AA15_DIAG_DIRECT_IREF_SELECT'];
addSwitch(power,directSelect,[posX+700 185 posX+810 285]);
addLineByPorts(power,directMux,1,directSelect,1);
addLineByPorts(power,directEff,1,directSelect,2);
addLineByPorts(power,origSrc,origPort,directSelect,3);
connectReplacingInputAbs(power,directSelect,1,powerOut,1);
end

% =========================================================================
% Patched-model assertions
% =========================================================================
function postassertPatchedModel(mdl,B,directSlew)
task=[mdl '/SS_Slave2'];
control=[task '/ESS2_Control'];
power=[control '/Power Control Loop'];
wrapper=[control '/AA15_GFL_ISLAND_SUPPORT'];
adapter=[wrapper '/AA15_V49_CURRENT_EXECUTION_ADAPTER'];

requireEq(numel(get_param(control,'PortHandles').Inport),11,'ESS2_Control inport count postpatch');
requireEq(numel(get_param(power,'PortHandles').Inport),8,'Power Control Loop inport count postpatch');
requireEq(numel(get_param(wrapper,'PortHandles').Inport),20,'GFL wrapper inport count preserved');
requireEq(numel(get_param(adapter,'PortHandles').Inport),7,'Current Adapter inport count preserved');

for b={ ...
    [control '/BaseTestDiagEnable'], ...
    [power '/BaseTestDiagEnable'], ...
    [power '/CFG_E2_DIAG_P_LOOP_ENABLE'], ...
    [power '/CFG_E2_DIAG_Q_LOOP_ENABLE'], ...
    [power '/CFG_E2_DIAG_DIRECT_IREF_ENABLE'], ...
    [power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'], ...
    [power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'], ...
    [power '/AA15_DIAG_DIRECT_ENABLE_EFF'], ...
    [power '/AA15_DIAG_P_LOOP_ENABLE_EFF'], ...
    [power '/AA15_DIAG_Q_LOOP_ENABLE_EFF'], ...
    [power '/AA15_DIAG_P_ALPHA_EFF'], ...
    [power '/AA15_DIAG_Q_ALPHA_EFF'], ...
    [power '/AA15_DIAG_ALPHA_ACTIVE'], ...
    [power '/AA15_DIAG_DIRECT_ID_RATE'], ...
    [power '/AA15_DIAG_DIRECT_IQ_RATE'], ...
    [power '/AA15_DIAG_DIRECT_IREF_MUX'], ...
    [power '/AA15_DIAG_DIRECT_IREF_SELECT']}
    mustBlock(b{1});
end

% BASETEST flag route.
if ~directConnectionExists([task '/AA15_BASETEST_ENABLE'],1,control,11)
    error('E2ABR1:PostBaseRoute','AA15_BASETEST_ENABLE -> ESS2_Control input11 missing.');
end
if ~directConnectionExists([control '/BaseTestDiagEnable'],1,power,8)
    error('E2ABR1:PostPowerBaseRoute','BaseTestDiagEnable -> PowerLoop input8 missing.');
end

% Defaults preserve existing behavior.
requireStr(strtrim(get_param([power '/CFG_E2_DIAG_P_LOOP_ENABLE'],'Value')),'1','P loop enable default');
requireStr(strtrim(get_param([power '/CFG_E2_DIAG_Q_LOOP_ENABLE'],'Value')),'1','Q loop enable default');
requireStr(strtrim(get_param([power '/CFG_E2_DIAG_DIRECT_IREF_ENABLE'],'Value')),'0','direct Iref enable default');
requireStr(strtrim(get_param([power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'],'Value')),'0','direct Id target default');
requireStr(strtrim(get_param([power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'],'Value')),'0','direct Iq target default');

% Direct mode must force the two outer-loop configs off before BASETEST
% selection; outside BASETEST, the final effective enables are forced to 1.
assertSwitchInputs([power '/AA15_DIAG_P_CFG_WHEN_NOT_DIRECT'], ...
    [power '/AA15_DIAG_ZERO'],[power '/AA15_DIAG_DIRECT_ENABLE_EFF'], ...
    [power '/CFG_E2_DIAG_P_LOOP_ENABLE']);
assertSwitchInputs([power '/AA15_DIAG_Q_CFG_WHEN_NOT_DIRECT'], ...
    [power '/AA15_DIAG_ZERO'],[power '/AA15_DIAG_DIRECT_ENABLE_EFF'], ...
    [power '/CFG_E2_DIAG_Q_LOOP_ENABLE']);
assertSwitchInputs([power '/AA15_DIAG_P_LOOP_ENABLE_EFF'], ...
    [power '/AA15_DIAG_P_CFG_WHEN_NOT_DIRECT'],[power '/BaseTestDiagEnable'], ...
    [power '/AA15_DIAG_ONE']);
assertSwitchInputs([power '/AA15_DIAG_Q_LOOP_ENABLE_EFF'], ...
    [power '/AA15_DIAG_Q_CFG_WHEN_NOT_DIRECT'],[power '/BaseTestDiagEnable'], ...
    [power '/AA15_DIAG_ONE']);

% P/Q alpha products.
assertInputSource([power '/AA15_DIAG_P_ALPHA_EFF'],1,[power '/RestoreAlpha'],1);
assertInputSource([power '/AA15_DIAG_P_ALPHA_EFF'],2,[power '/AA15_DIAG_P_LOOP_ENABLE_EFF'],1);
assertInputSource([power '/AA15_DIAG_Q_ALPHA_EFF'],1,[power '/RestoreAlpha'],1);
assertInputSource([power '/AA15_DIAG_Q_ALPHA_EFF'],2,[power '/AA15_DIAG_Q_LOOP_ENABLE_EFF'],1);
assertInputSource(B.pProd,2,[power '/AA15_DIAG_P_ALPHA_EFF'],1);
assertInputSource(B.qProd,2,[power '/AA15_DIAG_Q_ALPHA_EFF'],1);

% Direct branch + ramp.
assertInputSource([power '/AA15_DIAG_DIRECT_ID_ACTIVE_TARGET'],1,[power '/AA15_DIAG_DIRECT_ENABLE_EFF'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_ID_ACTIVE_TARGET'],2,[power '/AA15_DIAG_ALPHA_ACTIVE'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_ID_ACTIVE_TARGET'],3,[power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_IQ_ACTIVE_TARGET'],1,[power '/AA15_DIAG_DIRECT_ENABLE_EFF'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_IQ_ACTIVE_TARGET'],2,[power '/AA15_DIAG_ALPHA_ACTIVE'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_IQ_ACTIVE_TARGET'],3,[power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'],1);

requireNumericNear(str2double(get_param([power '/AA15_DIAG_DIRECT_ID_RATE'],'RisingSlewLimit')),directSlew,1e-12,'Id rate rising');
requireNumericNear(str2double(get_param([power '/AA15_DIAG_DIRECT_ID_RATE'],'FallingSlewLimit')),-directSlew,1e-12,'Id rate falling');
requireStr(get_param([power '/AA15_DIAG_DIRECT_ID_RATE'],'InitialCondition'),'0','Id rate IC');
requireNumericNear(str2double(get_param([power '/AA15_DIAG_DIRECT_IQ_RATE'],'RisingSlewLimit')),directSlew,1e-12,'Iq rate rising');
requireNumericNear(str2double(get_param([power '/AA15_DIAG_DIRECT_IQ_RATE'],'FallingSlewLimit')),-directSlew,1e-12,'Iq rate falling');
requireStr(get_param([power '/AA15_DIAG_DIRECT_IQ_RATE'],'InitialCondition'),'0','Iq rate IC');

assertInputSource([power '/AA15_DIAG_DIRECT_IREF_MUX'],1,[power '/AA15_DIAG_DIRECT_ID_RATE'],1);
assertInputSource([power '/AA15_DIAG_DIRECT_IREF_MUX'],2,[power '/AA15_DIAG_DIRECT_IQ_RATE'],1);
assertSwitchInputs([power '/AA15_DIAG_DIRECT_IREF_SELECT'], ...
    [power '/AA15_DIAG_DIRECT_IREF_MUX'],[power '/AA15_DIAG_DIRECT_ENABLE_EFF'], ...
    B.powerOutSource);
assertInputSource(B.powerOut,1,[power '/AA15_DIAG_DIRECT_IREF_SELECT'],1);

% Original P/Q PI controller identity/numerics remain unchanged.
[pKp,pKi,pInit,pLim,pInt]=piContract(B.pPI,'P');
[qKp,qKi,qInit,qLim,qInt]=piContract(B.qPI,'Q');
requireStr(pKp,B.pKpRaw,'P Kp unchanged');
requireStr(pKi,B.pKiRaw,'P Ki unchanged');
requireStr(pInit,B.pInitRaw,'P Init unchanged');
requireStr(pLim,B.pLimitRaw,'P limits unchanged');
requireStr(qKp,B.qKpRaw,'Q Kp unchanged');
requireStr(qKi,B.qKiRaw,'Q Ki unchanged');
requireStr(qInit,B.qInitRaw,'Q Init unchanged');
requireStr(qLim,B.qLimitRaw,'Q limits unchanged');
requireStr(safeGet(pInt,'ExternalReset'),'none','P integrator ExternalReset unchanged');
requireStr(safeGet(qInt,'ExternalReset'),'none','Q integrator ExternalReset unchanged');

% Untouched algorithm sources.
requireStr(hashText(emChartScript(B.adapterCore)),B.adapterSha,'Current Adapter source unchanged');
requireStr(hashText(emChartScript(B.executorCore)),B.executorSha,'Restore Executor source unchanged');
requireStr(hashText(emChartScript(B.strategyCore)),B.strategySha,'S14 strategy source unchanged');

% Existing support isolation markers remain.
for k=1:numel(B.supportMarkers),mustBlock(B.supportMarkers{k});end

% Recorder contracts remain byte-semantically the same at their input endpoints.
[groups,sources]=captureOpWriteContracts(mdl);
if ~isequal(groups,B.opGroups) || ~isequal(sources,B.opSources)
    error('E2ABR1:PostOpWrite','OpWrite group/input endpoint contract changed.');
end

% Parent output consumers of Power Loop remain unchanged.
nowConsumers=captureSubsystemOutConsumers(power);
if ~isequal(nowConsumers,B.powerParentOutConsumers)
    error('E2ABR1:PowerConsumers','Power Loop external output consumers changed.');
end
end

% =========================================================================
% Modification map / preflight reports
% =========================================================================
function writeModificationMap(path,B)
rows={
'ADD_INPORT',[B.control '/BaseTestDiagEnable'],'Port 11','Existing SS2/AA15_BASETEST_ENABLE -> ESS2_Control input11','BASETEST-only hard gate';
'ADD_INPORT',[B.power '/BaseTestDiagEnable'],'Port 8','ESS2_Control/BaseTestDiagEnable -> PowerLoop input8','Pass BASETEST flag into local diagnostic logic';
'ADD_PARAM',[B.power '/CFG_E2_DIAG_P_LOOP_ENABLE'],'default 1','BASETEST P outer-loop enable','Direct mode automatically forces OFF';
'ADD_PARAM',[B.power '/CFG_E2_DIAG_Q_LOOP_ENABLE'],'default 1','BASETEST Q outer-loop enable','Direct mode automatically forces OFF';
'ADD_PARAM',[B.power '/CFG_E2_DIAG_DIRECT_IREF_ENABLE'],'default 0','Select direct dq-current branch','Hard-gated by BASETEST';
'ADD_PARAM',[B.power '/CFG_E2_DIAG_DIRECT_ID_TARGET_PU'],'default 0','A1 signed d-axis current target','Do not guess sign; calculate from prior MAT';
'ADD_PARAM',[B.power '/CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'],'default 0','Direct q-axis current target','Keep 0 for current P-path experiments';
'ADD_GATE',[B.power '/AA15_DIAG_P_ALPHA_EFF'],'RestoreAlpha * PEnableEff','feeds AA15_RESTORE_PERR_ALPHA input2','P PI itself untouched';
'ADD_GATE',[B.power '/AA15_DIAG_Q_ALPHA_EFF'],'RestoreAlpha * QEnableEff','feeds AA15_RESTORE_QERR_ALPHA input2','Q PI itself untouched';
'ADD_RAMP',[B.power '/AA15_DIAG_DIRECT_ID_RATE'],'+/-0.0025 pu/s, IC=0','Direct Id only starts after RestoreAlpha active','Avoid artificial current step';
'ADD_RAMP',[B.power '/AA15_DIAG_DIRECT_IQ_RATE'],'+/-0.0025 pu/s, IC=0','Direct Iq only starts after RestoreAlpha active','Keep target zero for A0/A1';
'ADD_SELECTOR',[B.power '/AA15_DIAG_DIRECT_IREF_SELECT'],'u3=original PowerLoop Mux; u1=direct dq','output -> existing IdIqrefF Outport','All downstream GFL limits/adapter/current regulator preserved';
'UNCHANGED',B.pPI,['Kp=' B.pKpRaw ', Ki=' B.pKiRaw],'No tuning in this patch','Later causal step only';
'UNCHANGED',B.qPI,['Kp=' B.qKpRaw ', Ki=' B.qKiRaw],'No tuning in this patch','Q-only test deferred';
'UNCHANGED',B.adapterCore,'source hash preserved','Current Adapter MATLAB Function untouched','Real Imeas feedback remains';
'UNCHANGED',B.executorCore,'source hash preserved','Restore state machine untouched','Current R1F/R1G observe semantics retained';
'UNCHANGED',B.strategyCore,'source hash preserved','S14 strategy untouched','Use AA15_BASETEST_TARGET_PU=0 in A/B runner';
};
writeCellCsv(path,{'Action','ExactPath','Setting','NewRouteOrMeaning','Reason'},rows);
end

function writePreflightSummary(path,B)
txt=sprintf([ ...
'ESS2 BASETEST A/B patch preflight\n\n' ...
'P PI path: %s\nP Kp=%s\nP Ki=%s\nP Init=%s\nP Limits=%s\n\n' ...
'Q PI path: %s\nQ Kp=%s\nQ Ki=%s\nQ Init=%s\nQ Limits=%s\n\n' ...
'PowerLoop existing output source: %s#%d\n' ...
'Current Adapter SHA: %s\nRestore Executor SHA: %s\nS14 Strategy SHA: %s\n'], ...
B.pPI,B.pKpRaw,B.pKiRaw,B.pInitRaw,B.pLimitRaw, ...
B.qPI,B.qKpRaw,B.qKiRaw,B.qInitRaw,B.qLimitRaw, ...
B.powerOutSource,B.powerOutSourcePort,B.adapterSha,B.executorSha,B.strategySha);
writeText(path,txt);
end

% =========================================================================
% PI / graph helpers
% =========================================================================
function [kp,ki,init,lims,intb]=piContract(piBlock,label)
mustBlock(piBlock);
kp=maskOrDialogParam(piBlock,'Kp');
ki=maskOrDialogParam(piBlock,'Ki');
init=maskOrDialogParam(piBlock,'Init');
lims=maskOrDialogParam(piBlock,'Par_Limits');
ints=find_system(piBlock,'LookUnderMasks','all','FollowLinks','on','BlockType','DiscreteIntegrator');
if numel(ints)~=1
    error('E2ABR1:PIIntegrator','%s PI expected exactly one DiscreteIntegrator, got %d.',label,numel(ints));
end
intb=ints{1};
end

function dst=uniqueDstFrom(src,parent,label)
ph=get_param(src,'PortHandles');
if isempty(ph.Outport),error('E2ABR1:NoOut','%s has no output.',src);end
lh=get_param(ph.Outport(1),'Line');
if ~isnumeric(lh) || lh<0,error('E2ABR1:NoLine','%s output unconnected.',src);end
dp=get_param(lh,'DstPortHandle');
dp=dp(dp>0);
c={};
for k=1:numel(dp)
    b=get_param(dp(k),'Parent');
    if strcmp(get_param(b,'Parent'),parent),c{end+1}=b;end %#ok<AGROW>
end
c=unique(c,'stable');
if numel(c)~=1
    error('E2ABR1:UniqueDst','%s expected one direct destination in %s, got %d.',label,parent,numel(c));
end
dst=c{1};
end

function [src,port]=inputSource(block,inNum)
src='';port=NaN;
ph=get_param(block,'PortHandles');
if numel(ph.Inport)<inNum,error('E2ABR1:InputPort','%s has no input %d.',block,inNum);end
lh=get_param(ph.Inport(inNum),'Line');
if ~isnumeric(lh) || lh<0,return;end
sph=get_param(lh,'SrcPortHandle');
if ~isnumeric(sph) || sph<=0,return;end
src=get_param(sph,'Parent');
port=get_param(sph,'PortNumber');
end

function assertInputSource(dst,dstPort,src,srcPort)
[a,b]=inputSource(dst,dstPort);
if ~strcmp(a,src) || b~=srcPort
    error('E2ABR1:InputSource','Input mismatch: %s/in%d <- %s/out%d, observed %s/out%s.', ...
        dst,dstPort,src,srcPort,a,valueText(b));
end
end

function assertSwitchInputs(sw,u1,u2,u3)
assertInputSource(sw,1,u1,1);
assertInputSource(sw,2,u2,1);
assertInputSource(sw,3,u3,1);
requireStr(get_param(sw,'Criteria'),'u2 >= Threshold',[sw ' Criteria']);
requireStr(get_param(sw,'Threshold'),'0.5',[sw ' Threshold']);
end

function tf=directConnectionExists(src,srcPort,dst,dstPort)
tf=false;
try
    phs=get_param(src,'PortHandles');phd=get_param(dst,'PortHandles');
    lh=get_param(phs.Outport(srcPort),'Line');
    if ~isnumeric(lh)||lh<0,return;end
    dp=get_param(lh,'DstPortHandle');
    tf=any(dp==phd.Inport(dstPort));
catch
    tf=false;
end
end

function connectReplacingInputAbs(parent,src,srcPort,dst,dstPort)
phd=get_param(dst,'PortHandles');
dh=phd.Inport(dstPort);
lh=get_param(dh,'Line');
if isnumeric(lh) && lh>=0
    delete_line(lh);
end
addLineByPorts(parent,src,srcPort,dst,dstPort);
end

function addLineByPorts(parent,src,srcPort,dst,dstPort)
phs=get_param(src,'PortHandles');phd=get_param(dst,'PortHandles');
add_line(parent,phs.Outport(srcPort),phd.Inport(dstPort),'autorouting','on');
end

function addConst(parent,name,val,pos)
add_block('built-in/Constant',[parent '/' name], ...
    'Value',val,'SampleTime','-1','Position',pos);
end

function addSwitch(parent,path,pos)
add_block('built-in/Switch',path, ...
    'Criteria','u2 >= Threshold','Threshold','0.5','Position',pos);
end

function x=diagnosticBaseX(sys)
blocks=find_system(sys,'SearchDepth',1,'Type','Block');
mx=900;
for k=1:numel(blocks)
    try
        p=get_param(blocks{k},'Position');
        if isnumeric(p)&&numel(p)==4,mx=max(mx,p(3));end
    catch
    end
end
x=ceil((mx+180)/50)*50;
end

% =========================================================================
% OpWrite preservation
% =========================================================================
function [groups,sources]=captureOpWriteContracts(mdl)
ops=findAllOpWritesProven(mdl);
if numel(ops)~=5
    error('E2ABR1:OpWriteCount','Expected exactly 5 OpWriteFile blocks, got %d.',numel(ops));
end
rows=cell(numel(ops),3);
for k=1:numel(ops)
    g=readNumericMaskProven(ops{k},'Acq_Group');
    [s,p]=inputSource(ops{k},1);
    rows(k,:)={g,s,p};
end
[~,ix]=sort(cell2mat(rows(:,1)));
rows=rows(ix,:);
groups=cell2mat(rows(:,1)).';
if ~isequal(round(groups),26:30)
    error('E2ABR1:OpWriteGroups','Expected acquisition groups 26:30, got %s.',mat2str(groups));
end
sources=rows(:,2:3);
end

function ops=findAllOpWritesProven(mdl)
all=find_system(mdl,'LookUnderMasks','all','FollowLinks','on','Type','Block');
ops={};
for k=1:numel(all)
    txt=lower([safeGet(all{k},'ReferenceBlock') ' ' safeGet(all{k},'SourceBlock') ' ' safeGet(all{k},'MaskType')]);
    if contains(txt,'opwritefile')
        ops{end+1}=all{k}; %#ok<AGROW>
    end
end
ops=unique(ops,'stable');
end

function v=readNumericMaskProven(b,name)
raw=readMaskValueProven(b,name);
v=str2double(strtrim(raw));
if ~isfinite(v)
    error('E2ABR1:OpWriteMask','Cannot parse %s on %s: %s',name,b,raw);
end
end

function raw=readMaskValueProven(b,name)
raw='';
try
    n=get_param(b,'MaskNames');v=get_param(b,'MaskValues');
    ix=find(strcmp(n,name),1);
    if ~isempty(ix),raw=char(v{ix});return;end
catch
end
try,raw=char(get_param(b,name));catch,end
if isempty(raw),error('E2ABR1:MaskValue','Cannot read %s on %s.',name,b);end
end

function rows=captureSubsystemOutConsumers(sub)
ph=get_param(sub,'PortHandles');
rows=cell(0,3);
for p=1:numel(ph.Outport)
    lh=get_param(ph.Outport(p),'Line');
    if ~isnumeric(lh)||lh<0
        rows(end+1,:)={p,'UNCONNECTED',NaN}; %#ok<AGROW>
        continue
    end
    dp=get_param(lh,'DstPortHandle');dp=dp(dp>0);
    if isempty(dp)
        rows(end+1,:)={p,'NO_DEST',NaN}; %#ok<AGROW>
    else
        for k=1:numel(dp)
            rows(end+1,:)={p,get_param(dp(k),'Parent'),get_param(dp(k),'PortNumber')}; %#ok<AGROW>
        end
    end
end
if ~isempty(rows)
    key=cellfun(@(a,b,c)sprintf('%03d|%s|%03d',a,b,c),rows(:,1),rows(:,2),rows(:,3),'UniformOutput',false);
    [~,ix]=sort(key);rows=rows(ix,:);
end
end

% =========================================================================
% Stateflow read-only source helper -- explicit unique handle, never comma-list
% =========================================================================
function s=emChartScript(blockPath)
rt=sfroot;
charts=rt.find('-isa','Stateflow.EMChart');
hit=[];
for i=1:numel(charts)
    try
        if strcmp(char(charts(i).Path),blockPath)
            hit=charts(i);
            break
        end
    catch
    end
end
if isempty(hit),error('E2ABR1:EMChart','EMChart not found: %s',blockPath);end
s=char(hit.Script);
end

function tf=containsNoSpace(s,pattern)
tf=contains(regexprep(char(s),'\s+',''),regexprep(char(pattern),'\s+',''));
end

% =========================================================================
% Model/file helpers
% =========================================================================
function loadSystemExactFile(file)
[folder,name,ext]=fileparts(file);
if ~strcmpi(ext,'.slx'),error('E2ABR1:FileType','Expected SLX: %s',file);end
old=pwd;c=onCleanup(@()cd(old)); %#ok<NASGU>
cd(folder);
load_system([name ext]);
loaded=canonicalPath(get_param(name,'FileName'));
wanted=canonicalPath(file);
if ~strcmpi(loaded,wanted)
    close_system(name,0);
    error('E2ABR1:LoadedFile','Loaded wrong same-name model: %s',loaded);
end
if ~strcmpi(get_param(name,'Dirty'),'off')
    close_system(name,0);
    error('E2ABR1:LoadedDirty','Model loaded Dirty unexpectedly.');
end
end

function closeIfLoaded(mdl)
if bdIsLoaded(mdl),close_system(mdl,0);end
end

function mustBlock(p)
if getSimulinkBlockHandle(p)<0,error('E2ABR1:MissingBlock','Missing block: %s',p);end
end

function mustNotBlock(p)
if getSimulinkBlockHandle(p)>=0,error('E2ABR1:AlreadyPatched','Patch marker already exists: %s',p);end
end

function v=safeGet(p,name)
try
    v=get_param(p,name);
    if isstring(v),v=char(v);end
    if isnumeric(v),v=valueText(v);end
catch
    v='';
end
end

function raw=maskOrDialogParam(b,name)
raw='';
try,raw=get_param(b,name);catch,end
if isstring(raw),raw=char(raw);end
if isnumeric(raw),raw=valueText(raw);end
if isempty(raw)
    try
        n=get_param(b,'MaskNames');v=get_param(b,'MaskValues');
        ix=find(strcmp(n,name),1);
        if ~isempty(ix),raw=char(v{ix});end
    catch
    end
end
if isempty(raw),error('E2ABR1:PIParam','Cannot read %s on %s.',name,b);end
raw=strtrim(char(raw));
end

function v=resolveNumeric(mdl,expr)
v=str2double(strtrim(char(expr)));
if isfinite(v),return;end
try
    x=slResolve(char(expr),mdl);
    if isnumeric(x)&&isscalar(x)&&isfinite(x),v=double(x);return;end
catch
end
try
    x=evalin('base',char(expr));
    if isnumeric(x)&&isscalar(x)&&isfinite(x),v=double(x);return;end
catch
end
error('E2ABR1:ResolveNumeric','Cannot resolve numeric expression: %s',expr);
end

function requireNumericNear(a,b,tol,label)
if ~(isfinite(a)&&isfinite(b)&&abs(a-b)<=tol)
    error('E2ABR1:Numeric','%s mismatch: observed %.17g expected %.17g.',label,a,b);
end
end

function requireEq(a,b,label)
if ~isequal(a,b),error('E2ABR1:Eq','%s mismatch: observed %s expected %s.',label,valueText(a),valueText(b));end
end

function requireStr(a,b,label)
if ~strcmp(strtrim(char(a)),strtrim(char(b)))
    error('E2ABR1:Str','%s mismatch: observed "%s" expected "%s".',label,char(a),char(b));
end
end

function p=canonicalPath(p)
p=char(java.io.File(char(p)).getCanonicalPath());
end

function h=hashText(s)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
bytes=uint8(unicode2native(char(s),'UTF-8'));
md.update(typecast(bytes(:),'int8'));
raw=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(raw,2).',1,[]));
end

function h=sha256File(path)
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
fid=fopen(path,'rb');
if fid<0,error('E2ABR1:Hash','Cannot read: %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true
    bytes=fread(fid,1024*1024,'*uint8');
    if isempty(bytes),break;end
    md.update(typecast(bytes(:),'int8'));
end
raw=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(raw,2).',1,[]));
end

function s=nonce8()
x=char(java.util.UUID.randomUUID());
s=strrep(x(1:8),'-','');
end

function safeRmdir(p)
try
    if isfolder(p),rmdir(p,'s');end
catch
end
end

function safeClose(fid)
try
    if fid>0,fclose(fid);end
catch
end
end

function writeText(path,s)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('E2ABR1:Write','Cannot create %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',s);
end

function writeJson(path,S)
writeText(path,jsonencode(S,'PrettyPrint',true));
end

function writeCellCsv(path,headers,rows)
T=cell2table(rows,'VariableNames',headers);
writetable(T,path,'Encoding','UTF-8');
end

function s=valueText(x)
if ischar(x),s=x;return;end
if isstring(x),s=char(x);return;end
if isnumeric(x),s=mat2str(x,17);return;end
try,s=char(string(x));catch,s='<unprintable>';end
end

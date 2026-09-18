function result = PATCH_K26_K50_ESS2_P_PI_RUNTIME_GAINS_R1(modelRoot)
% PATCH_K26_K50_ESS2_P_PI_RUNTIME_GAINS_R1
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 P active-power PI online Kp/Ki exposure patch.
%
% PURPOSE
% -------
% Expose ONLY the ESS2 P active-power outer-loop gains as explicit RT-LAB
% tunable Constant block Values:
%
%   CFG_E2_DIAG_P_KP_RT / Value   default 0.06
%   CFG_E2_DIAG_P_KI_RT / Value   default 2.0
%
% Existing P PI:
%   Power Control Loop / PI regulator with anti-windup D
%
% Existing Q PI:
%   Power Control Loop / PI regulator with anti-windup D1
%
% The Q PI is not modified.
%
% IMPLEMENTATION
% --------------
% The original internal P-PI gains Kp4 and Kp5 are retained as Gain blocks
% but changed to unity.  Two explicit Constant + Product pairs reproduce the
% original mathematics at their default values:
%
%   Error -> Kp4(1) -> AA15_E2_P_KP_APPLY <- CFG_E2_DIAG_P_KP_RT(0.06)
%                                      |
%                                      +-> original proportional destination
%
%   Error -> Kp5(1) -> AA15_E2_P_KI_APPLY <- CFG_E2_DIAG_P_KI_RT(2.0)
%                                      |
%                                      +-> original anti-windup Switch/integrator path
%
% Therefore at defaults:
%   effective Kp = 0.06
%   effective Ki = 2.0
%
% This preserves the existing anti-windup / integrator / saturation logic.
%
% TRANSACTION
% -----------
%   1) exact disk model / stopped / clean gate
%   2) read-only structural preflight
%   3) byte-identical scratch copy
%   4) scratch edit -> postassert -> save -> close/reload -> postassert
%   5) formal whole-file backup
%   6) formal re-preflight
%   7) same minimal edit -> postassert
%   8) formal save exactly once
%   9) close/reload -> persistence postassert
%  10) any post-save failure -> whole-file rollback + SHA verification
%
% IMPORTANT
% ---------
% - No MATLAB Function block is added or changed.
% - No G27/G29/G30 width is changed.
% - No P/Q enable logic, RestoreAlpha logic, support, current loop, PLL,
%   electrical topology, S14, Coordinator or Secondary logic is changed.
% - This patch does NOT use host compile/update as a substitute for RT-LAB.
% - Run the independent Verifier after Patch PASS.
% - Only after Verifier PASS should RT-LAB Rebuild All be run.
%
% MATLAB R2023b.
% =========================================================================

VERSION='K26_K50_ESS2_P_PI_RUNTIME_GAINS_PATCH_R1_20260916';
MODEL='K26_K50_CLEAN_P1';

if nargin<1 || isempty(modelRoot)
    modelRoot=['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
        'yanshou_V7\models\K26_K50_CLEAN_P1'];
end
modelRoot=canonicalPath(char(modelRoot));
modelFile=fullfile(modelRoot,[MODEL '.slx']);
if ~isfile(modelFile)
    error('E2PPI:ModelMissing','Model missing: %s',modelFile);
end

stamp=datestr(now,'yyyymmdd_HHMMSS_FFF');
reportDir=fullfile(modelRoot,['PATCH_E2_P_PI_RUNTIME_GAINS_R1_' stamp]);
mkdir(reportDir);
logFile=fullfile(reportDir,'PATCH_REPORT.txt');
fid=fopen(logFile,'w','n','UTF-8');
if fid<0,error('E2PPI:Log','Cannot create %s',logFile);end
fidGuard=onCleanup(@()safeClose(fid)); %#ok<NASGU>

result=struct();
result.version=VERSION;
result.modelFile=modelFile;
result.reportDirectory=reportDir;
result.status='STARTED';
result.rollbackPerformed=false;
result.formalSaved=false;

backupFile='';
backupSha='';
formalSaved=false;

logf(fid,'ESS2 P PI runtime gains patch R1');
logf(fid,'Version : %s',VERSION);
logf(fid,'Model   : %s',modelFile);
logf(fid,'SHA pre : %s',sha256File(modelFile));

try
    compatibilitySelftest();
    numericSelftest();
    closeExactCleanModelIfLoaded(modelFile);

    % ---------------------------------------------------------------
    % 1. Formal disk read-only preflight
    % ---------------------------------------------------------------
    load_system(modelFile);
    assertLoadedExactFile(MODEL,modelFile);
    requireStoppedClean(MODEL);

    if isAlreadyPatched(MODEL)
        postassert(MODEL);
        logf(fid,'[ALREADY PATCHED] Current model already has the exact R1 runtime-gain interface.');
        result.status='ALREADY_PATCHED_VERIFIED';
        result.modelSha256=sha256File(modelFile);
        result.parameterPaths=parameterPaths(MODEL);
        return
    end

    preflightOriginal(MODEL);
    close_system(MODEL,0);
    logf(fid,'[PASS] formal read-only preflight.');

    % ---------------------------------------------------------------
    % 2. Byte-identical scratch patch
    % ---------------------------------------------------------------
    scratchDir=fullfile(reportDir,'SCRATCH');
    mkdir(scratchDir);
    scratchFile=fullfile(scratchDir,[MODEL '.slx']);
    copyfile(modelFile,scratchFile,'f');
    if ~strcmpi(sha256File(modelFile),sha256File(scratchFile))
        error('E2PPI:ScratchCopy','Scratch copy is not byte-identical.');
    end

    load_system(scratchFile);
    assertLoadedExactFile(MODEL,scratchFile);
    requireStoppedClean(MODEL);
    preflightOriginal(MODEL);
    applyPatch(MODEL);
    postassert(MODEL);
    save_system(MODEL);
    close_system(MODEL,0);

    load_system(scratchFile);
    assertLoadedExactFile(MODEL,scratchFile);
    requireStoppedClean(MODEL);
    postassert(MODEL);
    close_system(MODEL,0);
    logf(fid,'[PASS] scratch edit/save/reload persistence verification.');

    % ---------------------------------------------------------------
    % 3. Formal backup + re-preflight
    % ---------------------------------------------------------------
    backupFile=fullfile(reportDir,[MODEL '_PRE_P_PI_RUNTIME_GAINS_R1.slx']);
    copyfile(modelFile,backupFile,'f');
    backupSha=sha256File(backupFile);
    if ~strcmpi(backupSha,sha256File(modelFile))
        error('E2PPI:Backup','Whole-file backup SHA mismatch.');
    end
    logf(fid,'[PASS] formal whole-file backup: %s',backupFile);

    load_system(modelFile);
    assertLoadedExactFile(MODEL,modelFile);
    requireStoppedClean(MODEL);
    preflightOriginal(MODEL);

    % ---------------------------------------------------------------
    % 4. Formal edit; verify BEFORE the only formal save
    % ---------------------------------------------------------------
    applyPatch(MODEL);
    postassert(MODEL);
    logf(fid,'[PASS] formal in-memory postassert. Disk not saved yet.');

    save_system(MODEL);
    formalSaved=true;
    result.formalSaved=true;
    close_system(MODEL,0);

    % ---------------------------------------------------------------
    % 5. Persistence verification
    % ---------------------------------------------------------------
    load_system(modelFile);
    assertLoadedExactFile(MODEL,modelFile);
    requireStoppedClean(MODEL);
    postassert(MODEL);

    result.status='PATCH_SAVED_AND_PERSISTENCE_VERIFIED';
    result.modelSha256=sha256File(modelFile);
    result.backupFile=backupFile;
    result.backupSha256=backupSha;
    result.parameterPaths=parameterPaths(MODEL);

    logf(fid,'[PASS] PATCH_SAVED_AND_PERSISTENCE_VERIFIED');
    logf(fid,'New model SHA: %s',result.modelSha256);
    logf(fid,'Online parameter P-Kp: %s',result.parameterPaths.P_Kp);
    logf(fid,'Online parameter P-Ki: %s',result.parameterPaths.P_Ki);
    logf(fid,'NEXT: run VERIFY_K26_K50_ESS2_P_PI_RUNTIME_GAINS_R1.');
    logf(fid,'Only after verifier PASS: RT-LAB Rebuild All.');

catch ME
    logf(fid,'[FAIL] %s',getReport(ME,'extended','hyperlinks','off'));
    try
        if bdIsLoaded(MODEL),close_system(MODEL,0);end
    catch
    end

    if formalSaved && ~isempty(backupFile) && isfile(backupFile)
        try
            copyfile(backupFile,modelFile,'f');
            nowSha=sha256File(modelFile);
            if ~strcmpi(nowSha,backupSha)
                error('Rollback SHA mismatch: expected %s actual %s',backupSha,nowSha);
            end
            result.rollbackPerformed=true;
            result.status='FAILED_POSTSAVE_ROLLED_BACK';
            logf(fid,'[ROLLBACK PASS] whole-file backup restored and SHA verified.');
        catch RB
            result.status='FAILED_ROLLBACK_ERROR';
            logf(fid,'[ROLLBACK FAIL] %s',getReport(RB,'extended','hyperlinks','off'));
        end
    else
        result.status='FAILED_PRESAVE_DISK_UNCHANGED';
    end
    rethrow(ME);
end
end

% =========================================================================
% Exact model paths
% =========================================================================
function P=paths(mdl)
P=struct();
P.ctrl=[mdl '/SS_Slave2/ESS2_Control'];
P.power=[P.ctrl '/Power Control Loop'];
P.ppi=[P.power '/' sprintf('PI regulator\nwith anti-windup D')];
P.qpi=[P.power '/' sprintf('PI regulator\nwith anti-windup D1')];

P.perr=[P.ppi '/Error'];
P.pkp=[P.ppi '/Kp4'];
P.pki=[P.ppi '/Kp5'];
P.pzoh=[P.ppi '/' sprintf('Zero-Order\nHold')];
P.pswitch=[P.ppi '/Switch'];
P.pint=[P.ppi '/' sprintf('Discrete-Time\nIntegrator')];

P.qkp=[P.qpi '/Kp4'];
P.qki=[P.qpi '/Kp5'];

P.kpConst=[P.ppi '/CFG_E2_DIAG_P_KP_RT'];
P.kiConst=[P.ppi '/CFG_E2_DIAG_P_KI_RT'];
P.kpApply=[P.ppi '/AA15_E2_P_KP_APPLY'];
P.kiApply=[P.ppi '/AA15_E2_P_KI_APPLY'];
end

function S=parameterPaths(mdl)
P=paths(mdl);
S=struct();
S.P_Kp=[P.kpConst '/Value'];
S.P_Ki=[P.kiConst '/Value'];
end

% =========================================================================
% Preflight / edit / postassert
% =========================================================================
function tf=isAlreadyPatched(mdl)
P=paths(mdl);
existVec=[getSimulinkBlockHandle(P.kpConst)>0, ...
          getSimulinkBlockHandle(P.kiConst)>0, ...
          getSimulinkBlockHandle(P.kpApply)>0, ...
          getSimulinkBlockHandle(P.kiApply)>0];
if any(existVec) && ~all(existVec)
    error('E2PPI:PartialPatch','Partial prior runtime-gain patch detected. Manual review required.');
end
tf=all(existVec);
end

function preflightOriginal(mdl)
P=paths(mdl);
req={P.ctrl,P.power,P.ppi,P.qpi,P.perr,P.pkp,P.pki,P.pzoh,P.pswitch,P.pint,P.qkp,P.qki};
for i=1:numel(req),requireBlock(req{i});end

if isAlreadyPatched(mdl)
    error('E2PPI:Already','Model is already patched.');
end

assertNumericParam(P.pkp,'Gain',0.06,'ESS2 P PI original Kp4');
assertNumericParam(P.pki,'Gain',2.0,'ESS2 P PI original Kp5');
assertNumericParam(P.qkp,'Gain',0.06,'ESS2 Q PI Kp4 must remain frozen');
assertNumericParam(P.qki,'Gain',2.0,'ESS2 Q PI Kp5 must remain frozen');

assertDirectConnection(P.perr,1,P.pkp,1,'P Error -> P Kp4');
assertDirectConnection(P.perr,1,P.pki,1,'P Error -> P Kp5');
assertDirectConnection(P.pkp,1,P.pzoh,1,'P Kp4 -> P Zero-Order Hold');
assertDirectConnection(P.pki,1,P.pswitch,3,'P Kp5 -> P anti-windup Switch input3');

% The existing integrator/anti-windup structure must exist and remain native.
if ~strcmpi(get_param(P.pint,'BlockType'),'DiscreteIntegrator')
    error('E2PPI:Integrator','Unexpected P PI integrator block type.');
end
end

function applyPatch(mdl)
P=paths(mdl);

% Capture exact old destinations before breaking the two proven lines.
kpDst=captureOutputDestinations(P.pkp,1);
kiDst=captureOutputDestinations(P.pki,1);

if numel(kpDst)~=1 || ~strcmp(kpDst{1}.block,P.pzoh) || kpDst{1}.port~=1
    error('E2PPI:KpDest','Unexpected P-Kp destination set.');
end
if numel(kiDst)~=1 || ~strcmp(kiDst{1}.block,P.pswitch) || kiDst{1}.port~=3
    error('E2PPI:KiDest','Unexpected P-Ki destination set.');
end

% Explicit online constants: proven RT-LAB exposure pattern used elsewhere.
x=maxRightEdge(P.ppi)+120;
kpPos=[x 90 x+85 115];
kiPos=[x 250 x+85 275];
kpProdPos=[x+125 85 x+175 120];
kiProdPos=[x+125 245 x+175 280];

add_block('simulink/Sources/Constant',P.kpConst, ...
    'Value','0.06','SampleTime','inf','Position',kpPos);
add_block('simulink/Sources/Constant',P.kiConst, ...
    'Value','2.0','SampleTime','inf','Position',kiPos);
add_block('simulink/Math Operations/Product',P.kpApply, ...
    'Inputs','**','Position',kpProdPos);
add_block('simulink/Math Operations/Product',P.kiApply, ...
    'Inputs','**','Position',kiProdPos);

% Keep the original Gain blocks and their datatype/sample semantics, but
% make them unity. The explicit Constants now carry the actual Kp/Ki values.
set_param(P.pkp,'Gain','1');
set_param(P.pki,'Gain','1');

% Remove only the two proven outgoing lines.
deleteOutputLine(P.pkp,1);
deleteOutputLine(P.pki,1);

% New proportional path.
add_line(P.ppi,portRef(P.pkp,1),portRef(P.kpApply,1),'autorouting','on');
add_line(P.ppi,portRef(P.kpConst,1),portRef(P.kpApply,2),'autorouting','on');
add_line(P.ppi,portRef(P.kpApply,1),portRef(P.pzoh,1),'autorouting','on');

% New integral-gain path, upstream of the original anti-windup Switch.
add_line(P.ppi,portRef(P.pki,1),portRef(P.kiApply,1),'autorouting','on');
add_line(P.ppi,portRef(P.kiConst,1),portRef(P.kiApply,2),'autorouting','on');
add_line(P.ppi,portRef(P.kiApply,1),portRef(P.pswitch,3),'autorouting','on');
end

function postassert(mdl)
P=paths(mdl);
req={P.kpConst,P.kiConst,P.kpApply,P.kiApply,P.ppi,P.qpi,P.pint};
for i=1:numel(req),requireBlock(req{i});end

% Exact defaults: mathematical baseline preserved.
assertNumericParam(P.kpConst,'Value',0.06,'runtime P Kp default');
assertNumericParam(P.kiConst,'Value',2.0,'runtime P Ki default');
assertNumericParam(P.pkp,'Gain',1.0,'internal P Kp4 unity');
assertNumericParam(P.pki,'Gain',1.0,'internal P Kp5 unity');

% Q loop remains untouched.
assertNumericParam(P.qkp,'Gain',0.06,'Q Kp untouched');
assertNumericParam(P.qki,'Gain',2.0,'Q Ki untouched');

% Exact signal graph.
assertDirectConnection(P.perr,1,P.pkp,1,'P Error -> unity Kp4');
assertDirectConnection(P.perr,1,P.pki,1,'P Error -> unity Kp5');

assertDirectConnection(P.pkp,1,P.kpApply,1,'unity Kp4 -> runtime Kp product');
assertDirectConnection(P.kpConst,1,P.kpApply,2,'runtime Kp constant -> product');
assertDirectConnection(P.kpApply,1,P.pzoh,1,'runtime Kp product -> original P ZOH');

assertDirectConnection(P.pki,1,P.kiApply,1,'unity Kp5 -> runtime Ki product');
assertDirectConnection(P.kiConst,1,P.kiApply,2,'runtime Ki constant -> product');
assertDirectConnection(P.kiApply,1,P.pswitch,3,'runtime Ki product -> original anti-windup Switch');

% No accidental extra outgoing destinations.
assertSingleDestination(P.kpApply,1,P.pzoh,1,'P Kp product');
assertSingleDestination(P.kiApply,1,P.pswitch,3,'P Ki product');

% Existing integrator remains the native integrator.
if ~strcmpi(get_param(P.pint,'BlockType'),'DiscreteIntegrator')
    error('E2PPI:IntegratorChanged','P PI integrator type changed unexpectedly.');
end
end

% =========================================================================
% Structural helpers
% =========================================================================
function requireBlock(p)
if getSimulinkBlockHandle(p)<=0,error('E2PPI:Block','Missing block: %s',p);end
end

function assertNumericParam(block,param,want,label)
raw=get_param(block,param);
got=resolveNumeric(raw,block);
if ~isscalar(got)||~isfinite(got)||abs(got-want)>1e-12
    error('E2PPI:Value','%s mismatch. raw=%s resolved=%s want=%.17g', ...
        label,char(raw),mat2str(got),want);
end
end

function v=resolveNumeric(raw,ctx)
if isnumeric(raw),v=double(raw);return;end
s=char(raw);
v=[];
try
    q=slResolve(s,ctx);
    if isnumeric(q),v=double(q);end
catch
end
if isempty(v)
    q=str2double(s);
    if ~isnan(q),v=q;end
end
if isempty(v)
    error('E2PPI:Resolve','Cannot resolve numeric expression "%s" in %s',s,ctx);
end
end

function assertDirectConnection(src,srcPort,dst,dstPort,label)
ph=get_param(src,'PortHandles');
if srcPort>numel(ph.Outport),error('E2PPI:Port','%s source port missing.',label);end
lh=get_param(ph.Outport(srcPort),'Line');
if isempty(lh)||lh<0,error('E2PPI:Line','%s source has no line.',label);end
db=get_param(lh,'DstBlockHandle');
dp=get_param(lh,'DstPortHandle');
wantB=getSimulinkBlockHandle(dst);
wantP=get_param(get_param(dst,'PortHandles').Inport(dstPort),'PortNumber');
ok=false;
for i=1:min(numel(db),numel(dp))
    if db(i)==wantB && get_param(dp(i),'PortNumber')==wantP,ok=true;break;end
end
if ~ok,error('E2PPI:Connection','Missing direct connection: %s',label);end
end

function assertSingleDestination(src,srcPort,dst,dstPort,label)
D=captureOutputDestinations(src,srcPort);
if numel(D)~=1 || ~strcmp(D{1}.block,dst) || D{1}.port~=dstPort
    error('E2PPI:DestSet','%s destination set mismatch.',label);
end
end

function D=captureOutputDestinations(src,srcPort)
D={};
ph=get_param(src,'PortHandles');
lh=get_param(ph.Outport(srcPort),'Line');
if isempty(lh)||lh<0,return;end
db=get_param(lh,'DstBlockHandle');
dp=get_param(lh,'DstPortHandle');
for i=1:min(numel(db),numel(dp))
    if db(i)>=0 && dp(i)>=0
        q=struct();
        q.block=getfullname(db(i));
        q.port=str2double(get_param(dp(i),'PortNumber'));
        if isnan(q.port),q.port=get_param(dp(i),'PortNumber');end
        D{end+1}=q; %#ok<AGROW>
    end
end
end

function deleteOutputLine(src,srcPort)
ph=get_param(src,'PortHandles');
lh=get_param(ph.Outport(srcPort),'Line');
if ~isempty(lh)&&lh>=0,delete_line(lh);end
end

function s=portRef(block,port)
[~,name]=fileparts(block);
s=sprintf('%s/%d',name,port);
end

function x=maxRightEdge(sys)
b=find_system(sys,'SearchDepth',1,'Type','Block');
x=400;
for i=1:numel(b)
    try
        p=get_param(b{i},'Position');
        if isnumeric(p)&&numel(p)==4,x=max(x,p(3));end
    catch
    end
end
end

% =========================================================================
% Transaction / identity helpers
% =========================================================================
function requireStoppedClean(mdl)
if ~strcmpi(get_param(mdl,'SimulationStatus'),'stopped')
    error('E2PPI:Status','Model must be STOPPED before patching.');
end
if ~strcmpi(get_param(mdl,'Dirty'),'off')
    error('E2PPI:Dirty','Model must be clean (Dirty=off) before patching.');
end
end

function closeExactCleanModelIfLoaded(modelFile)
mdl='K26_K50_CLEAN_P1';
if ~bdIsLoaded(mdl),return;end
requireStoppedClean(mdl);
assertLoadedExactFile(mdl,modelFile);
close_system(mdl,0);
end

function assertLoadedExactFile(mdl,want)
raw=get_param(mdl,'FileName');
if ~strcmpi(canonicalPath(raw),canonicalPath(want))
    error('E2PPI:Identity','Loaded file mismatch. want=%s actual=%s',want,raw);
end
end

function p=canonicalPath(p)
try,p=char(java.io.File(char(p)).getCanonicalPath());catch,p=char(p);end
end

function h=sha256File(path)
md=java.security.MessageDigest.getInstance('SHA-256');
fis=java.io.FileInputStream(java.io.File(path));
c=onCleanup(@()fis.close()); %#ok<NASGU>
buf=zeros(1,1024*1024,'int8');
while true
    n=fis.read(buf,0,numel(buf));
    if n<0,break;end
    md.update(buf(1:n));
end
d=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(d,2).',1,[]));
end

function safeClose(fid)
try
    if fid>0,fclose(fid);end
catch
end
end

function logf(fid,varargin)
s=sprintf(varargin{:});
fprintf('%s\n',s);
fprintf(fid,'%s\n',s);
end

% =========================================================================
% Selftests
% =========================================================================
function compatibilitySelftest()
req={'contains','startsWith','endsWith','slResolve','getSimulinkBlockHandle'};
for i=1:numel(req)
    n=req{i};
    if exist(n,'file')==0 && exist(n,'builtin')==0
        error('E2PPI:Compatibility','Required MATLAB R2023b function unavailable: %s',n);
    end
end
end

function numericSelftest()
e=[-1 -0.1 0 0.1 1];
kp=0.06;ki=2.0;
oldP=kp.*e;newP=1.*e.*kp;
oldI=ki.*e;newI=1.*e.*ki;
if max(abs(oldP-newP))>1e-15 || max(abs(oldI-newI))>1e-15
    error('E2PPI:NumericSelftest','Default-value arithmetic equivalence selftest failed.');
end
end

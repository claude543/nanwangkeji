function result = ANALYZE_K26_V5_MODE7_VFF_RUN_V1_2(rootFolder,outFolder)
% ANALYZE_K26_V5_MODE7_VFF_RUN_V1
% K26_V5 Mode7 planned-islanding engineering evidence analyzer.
%
% PURPOSE
% -------
% Python supervisor is responsible for:
%   operating-point staging, Mode7 runtime contract, J1 action, data preservation.
%
% MATLAB is responsible for what it does best:
%   - read/merge G26~G30 MAT data point-by-point;
%   - prove diag30 semantics and shaper equation;
%   - locate model-local Mode7 target edge and J1 edge;
%   - quantify pre-J1 intervention quality;
%   - fit residual low-frequency growing modes with the same method;
%   - quantify physical primary-voltage/current propagation;
%   - quantify post-island slow frequency/angle/PI drift;
%   - write a compact evidence package for final human causal judgement.
%
% IMPORTANT
% ---------
% This script does NOT automatically declare the engineering fix successful.
% It produces evidence and flags. Final judgement should compare the evidence
% with B1/C1/C2/C1-Q/Mode6 history.
%
% USAGE
% -----
% Put this .m file in the CURRENT RUN data folder together with:
%   rootdiag_ev12_data*.mat
%   rootdiag_ess2_data*.mat
%   rootdiag_pv12_data*.mat
%   d1_gfm_superpack_data*.mat
%   freqdiag_ess1_data*.mat
%   optional *_manifest.json
%
% Then:
%   result = ANALYZE_K26_V5_MODE7_VFF_RUN_V1;
%
% 直接给 K26_V5 根目录，不需要搬 MAT：
%
%   result = ANALYZE_K26_V5_MODE7_VFF_RUN_V1_2( ...
%       'D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V5\models\K26_V5');
%
% 脚本会自动定位：
%   k26_v5_ss_slave \OpREDHAWKtarget\rootdiag_ev12_data*.mat
%   k26_v5_ss_slave2\OpREDHAWKtarget\rootdiag_ess2_data*.mat
%   k26_v5_ss_slave3\OpREDHAWKtarget\rootdiag_pv12_data*.mat
%   k26_v5_sm_master\OpREDHAWKtarget\d1_gfm_superpack_data*.mat
%   k26_v5_ss_slave2\OpREDHAWKtarget\freqdiag_ess1_data*.mat
%
% 如果目标文件不在这个精确层级，会在 K26_V5 内做受限递归搜索，
% 但必须同时命中正确的任务目录名和 OpREDHAWKtarget，避免混入旧任务。
% 不需要人工复制文件。

if nargin < 1 || isempty(rootFolder)
    error(['请把 K26_V5 根目录作为第一个参数传入，例如：' newline ...
        'result = ANALYZE_K26_V5_MODE7_VFF_RUN_V1_2(''D:\...\models\K26_V5'');']);
end
rootFolder = char(rootFolder);
if exist(rootFolder,'dir')~=7
    error('K26_V5 根目录不存在：%s',rootFolder);
end

% 规范化但不要求用户进入任何 OpREDHAWKtarget 子目录。
rootFolder = char(java.io.File(rootFolder).getCanonicalPath());

if nargin < 2 || isempty(outFolder)
    outFolder = fullfile(rootFolder,'MODE7_AUTO_ANALYSIS');
end
outFolder = char(outFolder);
if exist(outFolder,'dir')~=7
    [ok,msg]=mkdir(outFolder);
    if ~ok
        error('无法创建分析输出目录 %s：%s',outFolder,msg);
    end
end

OUT_TXT = fullfile(outFolder,'MODE7_AUTO_ANALYSIS_SUMMARY.txt');
OUT_MD  = fullfile(outFolder,'MODE7_AUTO_ANALYSIS_REPORT.md');
OUT_DEV = fullfile(outFolder,'MODE7_DEVICE_METRICS.csv');
OUT_MOD = fullfile(outFolder,'MODE7_MODAL_METRICS.csv');
OUT_MAT = fullfile(outFolder,'MODE7_EVIDENCE_PACKAGE.mat');

fid = fopen(OUT_TXT,'w','n','UTF-8');
if fid < 0
    error('Cannot create %s',OUT_TXT);
end
cleanupFid = onCleanup(@() fclose(fid));

logf(fid,repmat('=',1,132));
logf(fid,'K26_V5 MODE7 自动证据分析 V1.2');
logf(fid,'K26_V5 root: %s',rootFolder);
logf(fid,'Output folder: %s',outFolder);
logf(fid,repmat('=',1,132));

%% ------------------------------------------------------------------------
% 1. Optional Python manifest
%% ------------------------------------------------------------------------
manifest = struct();
manifestCandidates = {};
manifestRoots = {outFolder, rootFolder, pwd};
for rr=1:numel(manifestRoots)
    z=dir(fullfile(manifestRoots{rr},'**','*MODE7_VFF_SLOWFAST_ENGINEERING*_manifest.json'));
    for kk=1:numel(z)
        manifestCandidates{end+1}=fullfile(z(kk).folder,z(kk).name); %#ok<AGROW>
    end
    z0=dir(fullfile(manifestRoots{rr},'*MODE7_VFF_SLOWFAST_ENGINEERING*_manifest.json'));
    for kk=1:numel(z0)
        manifestCandidates{end+1}=fullfile(z0(kk).folder,z0(kk).name); %#ok<AGROW>
    end
end
manifestCandidates=unique(manifestCandidates,'stable');
if ~isempty(manifestCandidates)
    dates=zeros(1,numel(manifestCandidates));
    for kk=1:numel(manifestCandidates)
        z=dir(manifestCandidates{kk});
        dates(kk)=z.datenum;
    end
    [~,ix]=max(dates);
    mpath=manifestCandidates{ix};
    try
        manifest = jsondecode(fileread(mpath));
        logf(fid,'[MANIFEST] %s',mpath);
        if isfield(manifest,'fc_hz'), logf(fid,'[MANIFEST] fc=%.6f Hz',manifest.fc_hz); end
        if isfield(manifest,'alpha'), logf(fid,'[MANIFEST] alpha=%.12g',manifest.alpha); end
        if isfield(manifest,'kfast_island'), logf(fid,'[MANIFEST] 快速变化保留比例目标=%.6f',manifest.kfast_island); end
        if isfield(manifest,'kfast_slew_per_sample'), logf(fid,'[MANIFEST] 每步变化上限=%.6f',manifest.kfast_slew_per_sample); end
    catch ME
        logf(fid,'[MANIFEST WARN] %s',ME.message);
        manifest = struct();
    end
else
    logf(fid,'[MANIFEST] not found; MAT-local timing remains authoritative.');
end

%% ------------------------------------------------------------------------
% 2. Load exact five logger families
%% ------------------------------------------------------------------------
logf(fid,'\n--- 自动定位五类 RT-LAB MAT 文件 ---');
G26 = load_family_from_k26(rootFolder,'k26_v5_ss_slave', ...
    'rootdiag_ev12_data*.mat','rootdiag_ev12_data',61,'G26 EV1+EV2',fid);
G27 = load_family_from_k26(rootFolder,'k26_v5_ss_slave2', ...
    'rootdiag_ess2_data*.mat','rootdiag_ess2_data',31,'G27 ESS2',fid);
G28 = load_family_from_k26(rootFolder,'k26_v5_ss_slave3', ...
    'rootdiag_pv12_data*.mat','rootdiag_pv12_data',61,'G28 PV1+PV2',fid);
G29 = load_family_from_k26(rootFolder,'k26_v5_sm_master', ...
    'd1_gfm_superpack_data*.mat','d1_gfm_superpack_data',39,'G29 SM_Master',fid);
G30 = load_family_from_k26(rootFolder,'k26_v5_ss_slave2', ...
    'freqdiag_ess1_data*.mat','freqdiag_ess1_data',116,'G30 ESS1 slow diag',fid);

logf(fid,'[DATA] G26=%dx%d G27=%dx%d G28=%dx%d G29=%dx%d G30=%dx%d', ...
    size(G26,1),size(G26,2),size(G27,1),size(G27,2), ...
    size(G28,1),size(G28,2),size(G29,1),size(G29,2), ...
    size(G30,1),size(G30,2));

assert_all_finite(G26,'G26');
assert_all_finite(G27,'G27');
assert_all_finite(G28,'G28');
assert_all_finite(G29,'G29');
assert_all_finite(G30,'G30');

%% ------------------------------------------------------------------------
% 3. Decode five diag30 devices
%% ------------------------------------------------------------------------
D = struct();
D.EV1  = decode_diag30(G26,2);
D.EV2  = decode_diag30(G26,32);
D.ESS2 = decode_diag30(G27,2);
D.PV1  = decode_diag30(G28,2);
D.PV2  = decode_diag30(G28,32);

devNames = {'PV1','PV2','ESS2','EV1','EV2'};

%% ------------------------------------------------------------------------
% 4. Model-local timing: target edge + J1 edge
%% ------------------------------------------------------------------------
% G29 MAT row23 = model-local J1 applied close signal.
t29 = G29(1,:);
j1 = G29(23,:);
[j1LastClosed,j1FirstOpen] = falling_edge_times(t29,j1,0.5);
if ~isfinite(j1FirstOpen)
    error('Cannot find model-local J1 1->0 edge in G29 row23.');
end
logf(fid,'[J1 MODEL-LOCAL] lastClosed=%.6f firstOpen=%.6f',j1LastClosed,j1FirstOpen);

% Use five target traces and require coherent first 1->0 edge.
targetEdges = nan(1,5);
for i=1:5
    x = D.(devNames{i});
    [~,targetEdges(i)] = falling_edge_times(x.t,x.Kfast_target,0.5);
end
if any(~isfinite(targetEdges))
    error('At least one device has no Kfast target 1->0 edge.');
end
targetEdge = median(targetEdges);
logf(fid,'[SHAPER TARGET EDGE] device edges=%s median=%.6f',mat2str(targetEdges,7),targetEdge);
if max(abs(targetEdges-targetEdge)) > 5e-4
    error('Five shaper target edges are not coherent.');
end

lead = j1FirstOpen-targetEdge;
logf(fid,'[SHAPER LEAD] %.3f ms',lead*1000);

%% ------------------------------------------------------------------------
% 5. Hard contract + exact equation proof
%% ------------------------------------------------------------------------
contractPass = true;
deviceRows = {};

for i=1:5
    name = devNames{i};
    x = D.(name);

    modeErr = max(abs(x.mode-7));
    c1Err   = max(abs(x.oldC1-1));
    c2Err   = max(abs(x.C2-1));
    dErr    = max(abs(x.Dtrack-1));
    qErr    = max(abs(x.Qtrack-1));

    % Exact shaper equation should hold for every point:
    % applied = slow + K*(raw-slow)
    recD = x.Vslow_d + x.Kfast_eff.*(x.rawVd-x.Vslow_d);
    recQ = x.Vslow_q + x.Kfast_eff.*(x.rawVq-x.Vslow_q);
    eqResidual = max([max(abs(x.appVd-recD)),max(abs(x.appVq-recQ))]);

    % Pre-target exact bypass.
    pre = x.t < targetEdge-5e-4;
    preBypass = max([max(abs(x.appVd(pre)-x.rawVd(pre))),max(abs(x.appVq(pre)-x.rawVq(pre)))]);
    preK = median(x.Kfast_eff(pre));
    preKt = median(x.Kfast_target(pre));

    % Post-ramp range just before J1.
    postRamp = x.t >= targetEdge+0.011 & x.t <= j1FirstOpen-5e-4;
    if any(postRamp)
        postKMax = max(x.Kfast_eff(postRamp));
        postKtMax = max(abs(x.Kfast_target(postRamp)));
    else
        postKMax = NaN; postKtMax = NaN;
    end

    % C2 must remain transparent.
    irefResidual = max([max(abs(x.rawId-x.appId)),max(abs(x.rawIq-x.appIq))]);

    thisPass = modeErr<1e-9 && c1Err<1e-9 && c2Err<1e-9 && dErr<1e-9 && qErr<1e-9 ...
        && eqResidual<1e-9 && preBypass<1e-9 && abs(preK-1)<1e-6 && abs(preKt-1)<1e-6 ...
        && irefResidual<1e-9;
    contractPass = contractPass && thisPass;

    logf(fid,['[%s CONTRACT] pass=%d modeErr=%.3g C1/C2/D/Q err=%.3g/%.3g/%.3g/%.3g ' ...
        'eqResidual=%.3g preBypass=%.3g preK=%.6f postKmax=%.6f IrefResidual=%.3g'], ...
        name,thisPass,modeErr,c1Err,c2Err,dErr,qErr,eqResidual,preBypass,preK,postKMax,irefResidual);

    deviceRows = [deviceRows; {name,thisPass,modeErr,c1Err,c2Err,dErr,qErr,eqResidual,preBypass,preK,postKMax,postKtMax,irefResidual}]; %#ok<AGROW>
end

deviceTable = cell2table(deviceRows,'VariableNames',{ ...
    'Device','ContractPass','ModeErr','OldC1Err','C2Err','DTrackErr','QTrackErr', ...
    'EquationResidual','PreBypassResidual','PreKfast','PostRampKfastMax','PostRampTargetAbsMax','IrefResidual'});

writetable(deviceTable,OUT_DEV);
logf(fid,'[CONTRACT OVERALL] %d',contractPass);

%% ------------------------------------------------------------------------
% 6. Pre-J1 intervention-only physical quality from G29
%% ------------------------------------------------------------------------
preWin = t29>=targetEdge & t29<=j1LastClosed;
primVab = G29(21,:); % source input20 + TargetTime row
if any(preWin)
    preVspan = max(primVab(preWin))-min(primVab(preWin));
else
    preVspan = NaN;
end
logf(fid,'[PRE-J1 PRIMARY Vab span] %.6f V',preVspan);

%% ------------------------------------------------------------------------
% 7. Fast modal analysis, same J1+5~95ms window
%% ------------------------------------------------------------------------
modalRows = {};
wFast = @(t) (t>=j1FirstOpen+0.005 & t<=j1FirstOpen+0.095);

for i=1:5
    name=devNames{i};
    x=D.(name);
    mask=wFast(x.t);

    if nnz(mask)<50
        error('%s insufficient fast-window samples.',name);
    end

    signals = { ...
        'rawVd',x.rawVd; 'rawVq',x.rawVq; ...
        'appVd',x.appVd; 'appVq',x.appVq; ...
        'PI_d',x.PI_d; 'PI_q',x.PI_q; ...
        'Vconv_d',x.Vconv_d; 'Vconv_q',x.Vconv_q ...
    };

    for sidx=1:size(signals,1)
        sn=signals{sidx,1}; y=signals{sidx,2};
        fit=fit_exp_sine(x.t(mask),y(mask),[8 25],[-100 100]);
        fixed17=fit_fixed_mode(x.t(mask),y(mask),17.1652,25.3323);
        fixed106=fit_fixed_mode(x.t(mask),y(mask),10.6190,69.19);

        modalRows(end+1,:)={name,sn,fit.f,fit.sigma,fit.R2,fit.amp, ...
            fixed17.R2,fixed17.amp,fixed106.R2,fixed106.amp}; %#ok<AGROW>
    end
end

modalTable=cell2table(modalRows,'VariableNames',{ ...
    'Device','Signal','BestF_Hz','BestSigma_per_s','BestR2','BestAmp', ...
    'Fixed17_R2','Fixed17_Amp','Fixed10p6_R2','Fixed10p6_Amp'});
writetable(modalTable,OUT_MOD);

% Summarize Vconv modes.
isVd=strcmp(modalTable.Signal,'Vconv_d');
isVq=strcmp(modalTable.Signal,'Vconv_q');
logf(fid,'[Vconv_d modal mean] f=%.4fHz sigma=%+.3f/s R2=%.6f', ...
    mean(modalTable.BestF_Hz(isVd)),mean(modalTable.BestSigma_per_s(isVd)),mean(modalTable.BestR2(isVd)));
logf(fid,'[Vconv_q modal mean] f=%.4fHz sigma=%+.3f/s R2=%.6f', ...
    mean(modalTable.BestF_Hz(isVq)),mean(modalTable.BestSigma_per_s(isVq)),mean(modalTable.BestR2(isVq)));

%% ------------------------------------------------------------------------
% 8. Physical primary-voltage + branch-current propagation
%% ------------------------------------------------------------------------
% G29 mapping:
% row21 ESS1 primary Vab
% row22 PCC Vab
% row23 J1
% rows25:30 PV1/PV2/ESS1/ESS2/EV1/EV2 branch Ia
% row31 PCC Va
branchNames={'PV1','PV2','ESS1','ESS2','EV1','EV2'};
branchIa=G29(25:30,:);
pccVa=G29(31,:);

dt29=median(diff(t29));
rmsN=max(2,round(0.020/dt29));
primaryRMS=sqrt(movmean(primVab.^2,[rmsN-1 0]));
branchRMS=sqrt(movmean(branchIa.^2,[rmsN-1 0],2));

checkpoints=[0.020 0.040 0.060 0.080 0.100 0.120 0.150 0.200 0.300 0.500 0.750 1.000];
logf(fid,'[PRIMARY Vab 20ms causal RMS]');
for k=1:numel(checkpoints)
    tt=j1FirstOpen+checkpoints(k);
    if tt<=t29(end)
        v=interp1(t29,primaryRMS,tt,'nearest');
        logf(fid,'  +%.3fs : %.3f kV',checkpoints(k),v/1000);
    end
end

post1=t29>=j1FirstOpen & t29<=min(t29(end),j1FirstOpen+1.0);
if any(post1)
    logf(fid,'[PRIMARY 1s] RMS min=%.3fkV max=%.3fkV',min(primaryRMS(post1))/1000,max(primaryRMS(post1))/1000);
end

for b=1:6
    if any(post1)
        logf(fid,'[BRANCH %s 1s] RMS min=%.4f max=%.4f span=%.4f', ...
            branchNames{b},min(branchRMS(b,post1)),max(branchRMS(b,post1)), ...
            max(branchRMS(b,post1))-min(branchRMS(b,post1)));
    end
end

%% ------------------------------------------------------------------------
% 9. Actual physical PCC frequency from positive zero crossings
%% ------------------------------------------------------------------------
zc = zero_cross_frequency(t29,pccVa,j1FirstOpen,min(t29(end),j1FirstOpen+1.0));
if isempty(zc.freq)
    pccFreqMean=NaN;pccFreqMin=NaN;pccFreqMax=NaN;
    logf(fid,'[PCC PHYSICAL FREQUENCY] insufficient positive zero crossings.');
else
    pccFreqMean=mean(zc.freq);
    pccFreqMin=min(zc.freq);
    pccFreqMax=max(zc.freq);
    logf(fid,'[PCC PHYSICAL FREQUENCY 1s] mean=%.5fHz min=%.5f max=%.5f',pccFreqMean,pccFreqMin,pccFreqMax);
end

%% ------------------------------------------------------------------------
% 10. G30 slow frequency/angle evidence
%% ------------------------------------------------------------------------
t30=G30(1,:);
Fref=G30(2,:);
Fout=G30(3,:);
Theta=G30(4,:);
PLLfreq=G30(5,:);
Vabc30=G30(6:8,:);
J1rx=G30(16,:);

slowWin=t30>=j1FirstOpen+0.20 & t30<=min(t30(end),j1FirstOpen+1.0);
if nnz(slowWin)>10
    thetaU=unwrap(Theta);
    thetaFreq=[NaN diff(thetaU)./diff(t30)/(2*pi)];
    foutSpan=max(Fout(slowWin))-min(Fout(slowWin));
    pllSpan=max(PLLfreq(slowWin))-min(PLLfreq(slowWin));
    thetaFreqFinite=thetaFreq(slowWin & isfinite(thetaFreq));
    thetaFreqMean=mean(thetaFreqFinite);
    thetaFreqSpan=max(thetaFreqFinite)-min(thetaFreqFinite);

    vmag30=sqrt((2/3)*(Vabc30(1,:).^2+Vabc30(2,:).^2+Vabc30(3,:).^2));
    logf(fid,'[SLOW 0.2~1.0s] ESS1 Fout span=%.6fHz PLL span=%.6fHz theta-derived mean=%.6fHz span=%.6fHz', ...
        foutSpan,pllSpan,thetaFreqMean,thetaFreqSpan);
    logf(fid,'[SLOW 0.2~1.0s] ESS1 Vabc magnitude span=%.3fV',max(vmag30(slowWin))-min(vmag30(slowWin)));
else
    foutSpan=NaN;pllSpan=NaN;thetaFreqMean=NaN;thetaFreqSpan=NaN;
    logf(fid,'[SLOW WARN] G30 does not cover enough J1+0.2~1.0s data.');
end

%% ------------------------------------------------------------------------
% 11. Current-PI slow compensation/drift
%% ------------------------------------------------------------------------
piRows={};
for i=1:5
    name=devNames{i};x=D.(name);
    w=x.t>=j1FirstOpen+0.20 & x.t<=min(x.t(end),j1FirstOpen+1.0);
    if nnz(w)>10
        [sd,spand]=linear_slope_span(x.t(w),x.PI_d(w));
        [sq,spanq]=linear_slope_span(x.t(w),x.PI_q(w));
    else
        sd=NaN;spand=NaN;sq=NaN;spanq=NaN;
    end
    piRows(end+1,:)={name,sd,spand,sq,spanq}; %#ok<AGROW>
    logf(fid,'[%s PI slow] d slope=%+.6f/s span=%.6f | q slope=%+.6f/s span=%.6f',name,sd,spand,sq,spanq);
end
piTable=cell2table(piRows,'VariableNames',{'Device','PI_d_Slope_per_s','PI_d_Span','PI_q_Slope_per_s','PI_q_Span'});

%% ------------------------------------------------------------------------
% 12. Evidence flags (not final scientific verdict)
%% ------------------------------------------------------------------------
vconv = modalTable(strcmp(modalTable.Signal,'Vconv_d')|strcmp(modalTable.Signal,'Vconv_q'),:);
strongGrowingMode = any(vconv.BestSigma_per_s>5 & vconv.BestR2>0.995 & vconv.BestAmp>1e-4);

fastVoltageGross = false;
if any(post1)
    fastVoltageGross = min(primaryRMS(post1))<8000 || max(primaryRMS(post1))>12000;
end

slowFreqGross = isfinite(pccFreqMin) && (pccFreqMin<49 || pccFreqMax>51);
piGross = any(abs(piTable.PI_d_Slope_per_s)>1 | abs(piTable.PI_q_Slope_per_s)>1);

flags=struct();
flags.contractPass=contractPass;
flags.strongGrowingMode=strongGrowingMode;
flags.fastVoltageGross=fastVoltageGross;
flags.slowFreqGross=slowFreqGross;
flags.piGross=piGross;

logf(fid,'\n--- EVIDENCE FLAGS (NOT FINAL VERDICT) ---');
logf(fid,'contractPass=%d',flags.contractPass);
logf(fid,'strongGrowingMode=%d',flags.strongGrowingMode);
logf(fid,'fastVoltageGross=%d',flags.fastVoltageGross);
logf(fid,'slowFreqGross=%d',flags.slowFreqGross);
logf(fid,'piGross=%d',flags.piGross);

%% ------------------------------------------------------------------------
% 13. Save evidence package
%% ------------------------------------------------------------------------
result=struct();
result.rootFolder=rootFolder;
result.outFolder=outFolder;
result.manifest=manifest;
result.j1LastClosed=j1LastClosed;
result.j1FirstOpen=j1FirstOpen;
result.targetEdge=targetEdge;
result.shaperLead=lead;
result.devices=D;
result.deviceTable=deviceTable;
result.modalTable=modalTable;
result.piTable=piTable;
result.primaryRMS=primaryRMS;
result.branchRMS=branchRMS;
result.G29=G29;
result.G30=G30;
result.pccZeroCrossFrequency=zc;
result.flags=flags;

save(OUT_MAT,'result','-v7.3');

write_markdown_report(OUT_MD,result,pccFreqMean,pccFreqMin,pccFreqMax,foutSpan,pllSpan,thetaFreqMean,thetaFreqSpan);

logf(fid,'\n[OUTPUT] %s',OUT_TXT);
logf(fid,'[OUTPUT] %s',OUT_MD);
logf(fid,'[OUTPUT] %s',OUT_DEV);
logf(fid,'[OUTPUT] %s',OUT_MOD);
logf(fid,'[OUTPUT] %s',OUT_MAT);
logf(fid,'[DONE] Upload SUMMARY + REPORT + CSVs first. Raw MAT only if final judgement needs independent re-check.');

fprintf('\nMODE7 MATLAB analysis complete.\n');
fprintf('Summary: %s\n',OUT_TXT);
fprintf('Report : %s\n',OUT_MD);

end

%% =========================================================================
function X=load_family_from_k26(rootFolder,taskToken,pattern,varName,expectedRows,label,fid)
% 先按 K26_V5 标准 RT-LAB 层级精确定位；失败后再做受限递归定位。
filePaths = resolve_family_files(rootFolder,taskToken,pattern);

if isempty(filePaths)
    error(['[%s] 未找到 %s。' newline ...
        '已检查 K26_V5 下任务目录 %s 及其 OpREDHAWKtarget。' newline ...
        '请确认该轮 OpWrite 文件已经落盘。'],label,pattern,taskToken);
end

logf(fid,'[%s] 找到 %d 个 MAT 文件：',label,numel(filePaths));
for k=1:numel(filePaths)
    z=dir(filePaths{k});
    if isempty(z)
        logf(fid,'  [%02d] %s',k,filePaths{k});
    else
        logf(fid,'  [%02d] %s | %.3f MB | %s',k,filePaths{k}, ...
            z.bytes/1024/1024,datestr(z.datenum,'yyyy-mm-dd HH:MM:SS'));
    end
end

% 按修改时间排序，segment 会随后按 MAT 内真实 Target Time 再排序。
dates=zeros(1,numel(filePaths));
for k=1:numel(filePaths)
    z=dir(filePaths{k});
    dates(k)=z.datenum;
end
[~,ix]=sort(dates);
filePaths=filePaths(ix);

parts={};
for k=1:numel(filePaths)
    p=filePaths{k};
    S=load(p);

    if isfield(S,varName)
        A=S.(varName);
    else
        fn=fieldnames(S);
        cand=[];
        candName='';
        for j=1:numel(fn)
            v=S.(fn{j});
            if isnumeric(v) && ismatrix(v) && size(v,1)==expectedRows
                if ~isempty(cand)
                    error('[%s] %s 中有多个 %d 行数值矩阵，无法唯一判定。', ...
                        label,p,expectedRows);
                end
                cand=v;
                candName=fn{j};
            end
        end
        if isempty(cand)
            dims=cell(size(fn));
            for j=1:numel(fn)
                v=S.(fn{j});
                if isnumeric(v)&&ismatrix(v)
                    dims{j}=sprintf('%s=%dx%d',fn{j},size(v,1),size(v,2));
                else
                    dims{j}=sprintf('%s=<non-matrix>',fn{j});
                end
            end
            error('[%s] %s 中没有预期 %d 行矩阵。变量：%s', ...
                label,p,expectedRows,strjoin(dims,'; '));
        end
        A=cand;
        logf(fid,'[%s] %s 使用自动识别变量 %s',label,p,candName);
    end

    if size(A,1)~=expectedRows
        error('[%s] %s 预期 %d 行，实际 %d 行。可能不是本次 Mode7 Build 的数据。', ...
            label,p,expectedRows,size(A,1));
    end
    if isempty(A) || size(A,2)<2
        error('[%s] %s 数据为空或样本数不足。',label,p);
    end
    parts{end+1}=A; %#ok<AGROW>
end

% 拼接后按 Target Time 排序。
X=[parts{:}];
[tSort,idx]=sort(X(1,:));
X=X(:,idx);

% 同时间戳允许“完全相同的重复 segment”；不同数据则视为混入不同试验。
key=round(tSort*1e9)/1e9;
[tu,~,grp]=unique(key,'stable'); %#ok<ASGLU>
if numel(tu)<numel(tSort)
    keep=true(1,numel(tSort));
    for g=1:max(grp)
        jj=find(grp==g);
        if numel(jj)>1
            ref=X(:,jj(1));
            for q=2:numel(jj)
                delta=max(abs(X(:,jj(q))-ref),[],'all');
                if delta>1e-8
                    error(['[%s] 发现同一时间 %.9f s 对应不同数据。' newline ...
                        '很可能任务目录中混有不同轮次 MAT，请不要继续自动分析。'], ...
                        label,tSort(jj(1)));
                end
                keep(jj(q))=false;
            end
        end
    end
    X=X(:,keep);
end

if any(diff(X(1,:))<=0)
    error('[%s] 合并后的 Target Time 不是严格递增。',label);
end

logf(fid,'[%s] 合并完成：%dx%d，时间 %.6f ~ %.6f s，中位采样间隔 %.6f ms', ...
    label,size(X,1),size(X,2),X(1,1),X(1,end),median(diff(X(1,:)))*1000);
end

function filePaths=resolve_family_files(rootFolder,taskToken,pattern)
filePaths={};

% A. 标准结构：K26_V5\task\OpREDHAWKtarget
taskDir=find_child_dir_case_insensitive(rootFolder,taskToken);
if ~isempty(taskDir)
    targetDir=find_child_dir_case_insensitive(taskDir,'OpREDHAWKtarget');
    if ~isempty(targetDir)
        z=dir(fullfile(targetDir,pattern));
        for k=1:numel(z)
            if ~z(k).isdir
                filePaths{end+1}=fullfile(z(k).folder,z(k).name); %#ok<AGROW>
            end
        end
    end
end

% B. 如果用户传进来的其实就是 task 或 OpREDHAWKtarget，也兼容。
[~,rootName]=fileparts(rootFolder);
if strcmpi(rootName,taskToken)
    targetDir=find_child_dir_case_insensitive(rootFolder,'OpREDHAWKtarget');
    if ~isempty(targetDir)
        z=dir(fullfile(targetDir,pattern));
        for k=1:numel(z)
            if ~z(k).isdir
                filePaths{end+1}=fullfile(z(k).folder,z(k).name); %#ok<AGROW>
            end
        end
    end
elseif strcmpi(rootName,'OpREDHAWKtarget') && contains(lower(rootFolder),lower(taskToken))
    z=dir(fullfile(rootFolder,pattern));
    for k=1:numel(z)
        if ~z(k).isdir
            filePaths{end+1}=fullfile(z(k).folder,z(k).name); %#ok<AGROW>
        end
    end
end

% C. 标准结构没有找到时才做受限递归搜索。
if isempty(filePaths)
    z=dir(fullfile(rootFolder,'**',pattern));
    for k=1:numel(z)
        if z(k).isdir,continue;end
        folderLow=lower(strrep(z(k).folder,'/','\'));
        if contains(folderLow,lower(taskToken)) && contains(folderLow,'opredhawktarget')
            filePaths{end+1}=fullfile(z(k).folder,z(k).name); %#ok<AGROW>
        end
    end
end

filePaths=unique(filePaths,'stable');
end

function child=find_child_dir_case_insensitive(parent,nameWanted)
child='';
z=dir(parent);
for k=1:numel(z)
    if z(k).isdir && ~strcmp(z(k).name,'.') && ~strcmp(z(k).name,'..') ...
            && strcmpi(z(k).name,nameWanted)
        child=fullfile(parent,z(k).name);
        return;
    end
end
end

function assert_all_finite(X,name)
if any(~isfinite(X),'all')
    error('%s contains NaN/Inf.',name);
end
end

function d=decode_diag30(G,startRow)
% startRow points to scalar01. G row1 is Target Time.
a=G(startRow:startRow+29,:);
d=struct();
d.t=G(1,:);
d.rawId=a(1,:); d.rawIq=a(2,:);
d.appId=a(3,:); d.appIq=a(4,:);
d.Id=a(5,:); d.Iq=a(6,:);
d.rawVd=a(7,:); d.rawVq=a(8,:);
d.appVd=a(9,:); d.appVq=a(10,:);
d.PI_d=a(11,:); d.PI_q=a(12,:);
d.Vconv_d=a(13,:); d.Vconv_q=a(14,:);
d.modIndex=a(15,:);
d.P=a(16,:); d.Q=a(17,:);
d.execAngle=a(18,:); d.execFreq=a(19,:);
d.pllTheta=a(20,:); d.pllFreq=a(21,:);
d.mode=a(22,:); d.oldC1=a(23,:); d.C2=a(24,:);
d.Dtrack=a(25,:); d.Qtrack=a(26,:);
d.Vslow_d=a(27,:); d.Vslow_q=a(28,:);
d.Kfast_eff=a(29,:); d.Kfast_target=a(30,:);
end

function [lastHigh,firstLow]=falling_edge_times(t,x,thr)
idx=find(x(1:end-1)>thr & x(2:end)<=thr,1,'first');
if isempty(idx)
    lastHigh=NaN;firstLow=NaN;
else
    lastHigh=t(idx);firstLow=t(idx+1);
end
end

function fit=fit_exp_sine(t,y,fRange,sRange)
t=t(:);y=y(:);
tau=t-t(1);
bestSSE=Inf;bestF=NaN;bestS=NaN;bestC=[];

fGrid=linspace(fRange(1),fRange(2),86);
sGrid=linspace(sRange(1),sRange(2),81);
for si=1:numel(sGrid)
    sg=sGrid(si);
    e=exp(sg*tau);
    for fi=1:numel(fGrid)
        f=fGrid(fi);
        X=[ones(size(tau)) tau tau.^2 e.*sin(2*pi*f*tau) e.*cos(2*pi*f*tau)];
        c=X\y;
        r=y-X*c;
        sse=r'*r;
        if sse<bestSSE
            bestSSE=sse;bestF=f;bestS=sg;bestC=c;
        end
    end
end

obj=@(z) local_sse(z,tau,y,fRange,sRange);
z=fminsearch(obj,[bestF bestS],optimset('Display','off','TolX',1e-6,'TolFun',1e-12,'MaxIter',300));
bestF=min(max(z(1),fRange(1)),fRange(2));
bestS=min(max(z(2),sRange(1)),sRange(2));
e=exp(bestS*tau);
X=[ones(size(tau)) tau tau.^2 e.*sin(2*pi*bestF*tau) e.*cos(2*pi*bestF*tau)];
c=X\y;
r=y-X*c;
sse=r'*r;
sst=sum((y-mean(y)).^2);
R2=1-sse/max(sst,eps);

fit=struct('f',bestF,'sigma',bestS,'R2',R2,'amp',hypot(c(4),c(5)),'coef',c);
end

function sse=local_sse(z,tau,y,fRange,sRange)
f=z(1);sg=z(2);
if f<fRange(1)||f>fRange(2)||sg<sRange(1)||sg>sRange(2)
    sse=1e12+(f-min(max(f,fRange(1)),fRange(2)))^2+(sg-min(max(sg,sRange(1)),sRange(2)))^2;
    return;
end
e=exp(sg*tau);
X=[ones(size(tau)) tau tau.^2 e.*sin(2*pi*f*tau) e.*cos(2*pi*f*tau)];
c=X\y;
r=y-X*c;
sse=r'*r;
end

function fit=fit_fixed_mode(t,y,f,sg)
t=t(:);y=y(:);tau=t-t(1);e=exp(sg*tau);
X=[ones(size(tau)) tau tau.^2 e.*sin(2*pi*f*tau) e.*cos(2*pi*f*tau)];
c=X\y;r=y-X*c;
sst=sum((y-mean(y)).^2);
fit=struct('R2',1-(r'*r)/max(sst,eps),'amp',hypot(c(4),c(5)));
end

function z=zero_cross_frequency(t,x,t0,t1)
m=t>=t0 & t<=t1;
tt=t(m);xx=x(m);
idx=find(xx(1:end-1)<=0 & xx(2:end)>0);
cross=zeros(size(idx));
for k=1:numel(idx)
    i=idx(k);
    dx=xx(i+1)-xx(i);
    if abs(dx)<eps
        cross(k)=tt(i);
    else
        cross(k)=tt(i)+(0-xx(i))*(tt(i+1)-tt(i))/dx;
    end
end
if numel(cross)>=2
    f=1./diff(cross);
    z=struct('crossings',cross,'time',0.5*(cross(1:end-1)+cross(2:end)),'freq',f);
else
    z=struct('crossings',cross,'time',[],'freq',[]);
end
end

function [slope,span]=linear_slope_span(t,y)
t=t(:);y=y(:);
p=polyfit(t-t(1),y,1);
slope=p(1);
span=max(y)-min(y);
end

function logf(fid,fmt,varargin)
s=sprintf(fmt,varargin{:});
fprintf('%s\n',s);
fprintf(fid,'%s\n',s);
end

function write_markdown_report(path,result,pccMean,pccMin,pccMax,foutSpan,pllSpan,thetaMean,thetaSpan)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('Cannot create markdown report.');end
c=onCleanup(@() fclose(fid));

fprintf(fid,'# K26_V5 Mode7 自动证据报告\n\n');
fprintf(fid,'## 1. 试验合同\n\n');
fprintf(fid,'- 模型本地 J1 首次打开：`%.6f s`\n',result.j1FirstOpen);
fprintf(fid,'- 慢/快分离目标首次切换：`%.6f s`\n',result.targetEdge);
fprintf(fid,'- 提前量：`%.3f ms`\n',result.shaperLead*1000);
fprintf(fid,'- diag30 总体合同：`%d`\n\n',result.flags.contractPass);

fprintf(fid,'## 2. 快速动态证据\n\n');
vd=result.modalTable(strcmp(result.modalTable.Signal,'Vconv_d'),:);
vq=result.modalTable(strcmp(result.modalTable.Signal,'Vconv_q'),:);
fprintf(fid,'- 五台 `Vconv_d` 最佳拟合平均频率：`%.4f Hz`，平均增长率：`%+.3f s^-1`\n',mean(vd.BestF_Hz),mean(vd.BestSigma_per_s));
fprintf(fid,'- 五台 `Vconv_q` 最佳拟合平均频率：`%.4f Hz`，平均增长率：`%+.3f s^-1`\n',mean(vq.BestF_Hz),mean(vq.BestSigma_per_s));
fprintf(fid,'- 检测到高可信明显正增长模式：`%d`\n',result.flags.strongGrowingMode);
fprintf(fid,'- 一次侧电压出现明显越界：`%d`\n\n',result.flags.fastVoltageGross);

fprintf(fid,'## 3. 慢动态证据\n\n');
fprintf(fid,'- PCC 物理频率 1 s：mean=`%.5f Hz`, min=`%.5f`, max=`%.5f`\n',pccMean,pccMin,pccMax);
fprintf(fid,'- ESS1 下垂频率输出 0.2~1.0 s span：`%.6f Hz`\n',foutSpan);
fprintf(fid,'- ESS1 PLL频率 0.2~1.0 s span：`%.6f Hz`\n',pllSpan);
fprintf(fid,'- ESS1 执行角导出的平均频率：`%.6f Hz`，span=`%.6f Hz`\n',thetaMean,thetaSpan);
fprintf(fid,'- 慢频率明显越界：`%d`\n',result.flags.slowFreqGross);
fprintf(fid,'- 电流PI存在明显持续爬升标志：`%d`\n\n',result.flags.piGross);

fprintf(fid,'## 4. 自动程序不做的事情\n\n');
fprintf(fid,'本报告不自动宣布“修复成功”。最终需要把以上证据与历史的原系统、全量切断、只切Q、只切D结果放在同一因果框架中判断。\n');
end

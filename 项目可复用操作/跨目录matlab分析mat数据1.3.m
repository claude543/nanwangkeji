function result = ANALYZE_K26_V5_LAYER2_MODE3_FINAL_V1_6(rootFolder,outFolder)
% K26_V5 Layer-2 causal run numerical evidence analyzer V1.6
%
% MATLAB ROLE IS DELIBERATELY LIMITED:
%   1) discover/merge MAT segments;
%   2) decode frozen row maps;
%   3) locate model-local intervention/J1 edges;
%   4) verify point-by-point execution equations;
%   5) calculate RMS, slopes, integrals, modes, event times;
%   6) export compact evidence.
%
% MATLAB DOES NOT:
%   - declare the root cause;
%   - declare an engineering repair successful;
%   - decide which experiment should be run next.
%
% EXPECTED POST-LAYER2 BUILD MAT ROWS INCLUDING TARGET TIME:
%   G26 83, G27 42, G28 83, G29 39, G30 129.
%
% USAGE:
% result = ANALYZE_K26_V5_LAYER2_MODE3_FINAL_V1_6( ...
%   'D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V5\models\K26_V5');
%
% No manual MAT copying is required.

if nargin<1 || isempty(rootFolder)
    error('请把 K26_V5 根目录作为第一个参数。');
end
rootFolder=char(rootFolder);
if exist(rootFolder,'dir')~=7,error('目录不存在：%s',rootFolder);end
rootFolder=char(java.io.File(rootFolder).getCanonicalPath());

if nargin<2 || isempty(outFolder)
    outFolder=fullfile(rootFolder,['LAYER2_CAUSAL_ANALYSIS_' datestr(now,'yyyymmdd_HHMMSS')]);
end
outFolder=char(outFolder);
if exist(outFolder,'dir')~=7
    [ok,msg]=mkdir(outFolder);if ~ok,error('无法创建输出目录：%s',msg);end
end

OUT_SUM=fullfile(outFolder,'L2_NUMERICAL_SUMMARY.txt');
OUT_MD=fullfile(outFolder,'L2_EVIDENCE_REPORT.md');
OUT_DEV=fullfile(outFolder,'L2_DEVICE_METRICS.csv');
OUT_EVT=fullfile(outFolder,'L2_EVENT_TIMELINE.csv');
OUT_MOD=fullfile(outFolder,'L2_MODAL_METRICS.csv');
OUT_CP=fullfile(outFolder,'L2_VOLTAGE_CHECKPOINTS.csv');
OUT_SLOW=fullfile(outFolder,'L2_SLOW_METRICS.csv');
OUT_ESS1=fullfile(outFolder,'L2_ESS1_METRICS.csv');
OUT_SG=fullfile(outFolder,'L2_STRONGGRID_INTERVENTION_WINDOW.csv');
OUT_COV=fullfile(outFolder,'L2_DATA_COVERAGE.csv');
OUT_ALIGN=fullfile(outFolder,'L2_IREF_RECORDPOINT_ALIGNMENT.csv');
OUT_INT=fullfile(outFolder,'L2_INTERVENTION_MAGNITUDE.csv');
OUT_WIN=fullfile(outFolder,'L2_GFL_WINDOW_METRICS.csv');
OUT_ECORE=fullfile(outFolder,'L2_ESS1_CORE_WINDOW_METRICS.csv');
OUT_ECP=fullfile(outFolder,'L2_ESS1_CHECKPOINTS.csv');
OUT_EXT=fullfile(outFolder,'L2_VOLTAGE_ENVELOPE_EXTREMA.csv');
OUT_KEY=fullfile(outFolder,'L2_KEY_TIMESERIES_10MS.csv');
OUT_SIG=fullfile(outFolder,'L2_RUN_SIGNATURE.csv');
OUT_FASTGFL=fullfile(outFolder,'L2_FAST_GFL_LONG_0P4MS.csv');
OUT_FASTPHY=fullfile(outFolder,'L2_FAST_PHYSICAL_G29_0P4MS.csv');
OUT_G30ONSET=fullfile(outFolder,'L2_ESS1_ONSET_G30_1MS.csv');
OUT_JOINT=fullfile(outFolder,'L2_MODE3_JOINT_PROOF.csv');
OUT_MAT=fullfile(outFolder,'L2_EVIDENCE_PACKAGE.mat');

fid=fopen(OUT_SUM,'w','n','UTF-8');
if fid<0,error('Cannot create summary.');end
cFid=onCleanup(@()fclose(fid));

logf(fid,repmat('=',1,144));
logf(fid,'K26_V5 Layer-2 数值证据分析 V1.6');
logf(fid,'Root: %s',rootFolder);
logf(fid,'MATLAB只做数值计算/合同验证，不自动宣布根因或修复成功。');
VFF_EQ_TOL_ABS=5e-6;
IREF_EQ_TOL_ABS=1e-5;
DOSE_EFFECTIVE_MIN_RMS=1e-4;
logf(fid,'[NUMERICAL TOL] VFF equation <= %.3g | Iref equation <= %.3g | active-dose RMS floor=%.3g', ...
    VFF_EQ_TOL_ABS,IREF_EQ_TOL_ABS,DOSE_EFFECTIVE_MIN_RMS);
logf(fid,repmat('=',1,144));

%% 1. Optional manifest
manifest=struct();
manifestPath=find_latest_manifest(rootFolder,outFolder);
if ~isempty(manifestPath)
    try
        manifest=jsondecode(fileread(manifestPath));
        logf(fid,'[MANIFEST] %s',manifestPath);
    catch ME
        logf(fid,'[MANIFEST WARN] %s',ME.message);
        manifest=struct();
    end
else
    logf(fid,'[MANIFEST] not found; MAT-local time remains authoritative.');
end

%% 2. Load exact five families
logf(fid,'\n--- MAT自动定位 / 合并 ---');
G26=load_family_from_k26(rootFolder,'k26_v5_ss_slave','rootdiag_ev12_data*.mat','rootdiag_ev12_data',83,'G26 EV1+EV2',fid);
G27=load_family_from_k26(rootFolder,'k26_v5_ss_slave2','rootdiag_ess2_data*.mat','rootdiag_ess2_data',42,'G27 ESS2',fid);
G28=load_family_from_k26(rootFolder,'k26_v5_ss_slave3','rootdiag_pv12_data*.mat','rootdiag_pv12_data',83,'G28 PV1+PV2',fid);
G29=load_family_from_k26(rootFolder,'k26_v5_sm_master','d1_gfm_superpack_data*.mat','d1_gfm_superpack_data',39,'G29 SM',fid);
G30=load_family_from_k26(rootFolder,'k26_v5_ss_slave2','freqdiag_ess1_data*.mat','freqdiag_ess1_data',129,'G30 ESS1',fid);
assert_all_finite(G26,'G26');assert_all_finite(G27,'G27');assert_all_finite(G28,'G28');assert_all_finite(G29,'G29');assert_all_finite(G30,'G30');

%% 3. Decode five diag41
D=struct();
D.EV1=decode_diag41(G26,2);
D.EV2=decode_diag41(G26,43);
D.ESS2=decode_diag41(G27,2);
D.PV1=decode_diag41(G28,2);
D.PV2=decode_diag41(G28,43);
devNames={'PV1','PV2','ESS2','EV1','EV2'};

%% 4. Model-local J1 and control timing
t29=G29(1,:);j1=G29(23,:);
[j1LastClosed,j1FirstOpen]=falling_edge_times(t29,j1,0.5);
if ~isfinite(j1FirstOpen),error('G29 row23 未找到 J1 1->0。');end
logf(fid,'[J1 MODEL-LOCAL] lastClosed=%.6f firstOpen=%.6f',j1LastClosed,j1FirstOpen);

%% 4.1 Data coverage contract
covNames={'G26','G27','G28','G29','G30'};
covData={G26,G27,G28,G29,G30};
covRows=cell(5,10);
for ci=1:5
    A=covData{ci}; tt=A(1,:);
    after=tt(end)-j1FirstOpen;
    covRows(ci,:)={covNames{ci},size(A,1),size(A,2),tt(1),tt(end),median(diff(tt))*1000,after,after>=0.2,after>=1.0,after>=3.0};
end
coverageTable=cell2table(covRows,'VariableNames', ...
    {'Family','Rows','Samples','Start_s','End_s','MedianDt_ms','AfterJ1_s','Complete0p2s','Complete1s','Complete3s'});
writetable(coverageTable,OUT_COV);

fastCoverage=min([G26(1,end),G27(1,end),G28(1,end),G29(1,end)])-j1FirstOpen;
allCoverage=min([G26(1,end),G27(1,end),G28(1,end),G29(1,end),G30(1,end)])-j1FirstOpen;
g30Coverage=G30(1,end)-j1FirstOpen;
logf(fid,'[COVERAGE] fast/common G26~G29=J1+%.4fs | all-five=J1+%.4fs | G30=J1+%.4fs', ...
    fastCoverage,allCoverage,g30Coverage);
if fastCoverage < 2.99
    error('G26~G29共同覆盖不足J1后3s：%.4fs。不能做正式Layer-2慢动态判决。',fastCoverage);
end
if g30Coverage < 0.99
    error('G30覆盖不足J1后1s：%.4fs。ESS1支撑首发链证据不足。',g30Coverage);
elseif g30Coverage < 2.99
    logf(fid,'[COVERAGE WARN] G30不足3s；1~3s ESS1核心动态将使用G29，G30只分析实际覆盖窗口。');
end

% Mode7 fast-target edge remains common intervention marker.
kfastEdges=nan(1,5);
for i=1:5
    x=D.(devNames{i});
    [~,kfastEdges(i)]=falling_edge_times(x.t,x.Kfast_target,0.5);
end
if any(~isfinite(kfastEdges)),error('至少一台没有 Kfast target 1->0 边沿。');end
interventionEdge=median(kfastEdges);
logf(fid,'[INTERVENTION MODEL-LOCAL] Kfast target edges=%s median=%.6f lead=%.3fms', ...
    mat2str(kfastEdges,7),interventionEdge,(j1FirstOpen-interventionEdge)*1000);

l2Modes=zeros(1,5);
for i=1:5
    x=D.(devNames{i});
    pre=x.t<interventionEdge-0.002;
    l2Modes(i)=round(median(x.L2Mode(pre)));
end
if numel(unique(l2Modes))~=1,error('五台 L2_MODE 不一致：%s',mat2str(l2Modes));end
l2Mode=l2Modes(1);
if ~ismember(l2Mode,0:3),error('非法 L2_MODE=%g',l2Mode);end
logf(fid,'[L2 MODE] %d',l2Mode);
if l2Mode~=3
    logf(fid,'[MODE3 ANALYZER NOTE] 本脚本兼容0~3，但当前最终联合判决轮预期L2_MODE=3；实际=%d。',l2Mode);
end

% Frozen one-build dose contract.
expectedKslow=[1.0 0.5 1.0 0.5];
expectedKpq  =[1.0 1.0 0.5 0.5];
wantKslow=expectedKslow(l2Mode+1);
wantKpq=expectedKpq(l2Mode+1);
logf(fid,'[L2 EXPECTED DOSE] Kslow=%.3f Kpq=%.3f',wantKslow,wantKpq);

kslowEdges=nan(1,5);kpqEdges=nan(1,5);
for i=1:5
    x=D.(devNames{i});
    [~,kslowEdges(i)]=falling_edge_times(x.t,x.Kslow_target,0.999999);
    [~,kpqEdges(i)]=falling_edge_times(x.t,x.Kpq_target,0.999999);
end
if l2Mode==1
    activeL2Edges=kslowEdges;
    if any(~isfinite(activeL2Edges)),error('Mode1至少一台Kslow没有1->test target边沿。');end
    l2Edge=median(activeL2Edges);
    logf(fid,'[L2 ACTIVE TARGET EDGE] Kslow edges=%s median=%.6f leadToJ1=%.3fms', ...
        mat2str(activeL2Edges,7),l2Edge,(j1FirstOpen-l2Edge)*1000);
elseif l2Mode==2
    activeL2Edges=kpqEdges;
    if any(~isfinite(activeL2Edges)),error('Mode2至少一台Kpq没有1->test target边沿。');end
    l2Edge=median(activeL2Edges);
    logf(fid,'[L2 ACTIVE TARGET EDGE] Kpq edges=%s median=%.6f leadToJ1=%.3fms', ...
        mat2str(activeL2Edges,7),l2Edge,(j1FirstOpen-l2Edge)*1000);
elseif l2Mode==3
    if any(~isfinite(kslowEdges))||any(~isfinite(kpqEdges))
        error('Mode3的Kslow/Kpq双路径至少一台缺少1->test target边沿。');
    end
    activeL2Edges=[kslowEdges kpqEdges];
    l2Edge=median(activeL2Edges);
    logf(fid,'[L2 ACTIVE TARGET EDGE] Mode3 Kslow=%s Kpq=%s median=%.6f leadToJ1=%.3fms', ...
        mat2str(kslowEdges,7),mat2str(kpqEdges,7),l2Edge,(j1FirstOpen-l2Edge)*1000);
else
    activeL2Edges=nan(1,5);
    l2Edge=NaN;
end

%% 5. Point-by-point execution contract
rows={};
alignRows={};
interventionRows={};
executionContractValid=true;
auxIrefWarningAny=false;
for i=1:5
    name=devNames{i};x=D.(name);
    modeErr=max(abs(x.mode-7));
    c1Err=max(abs(x.oldC1-1));c2Err=max(abs(x.C2-1));dErr=max(abs(x.Dtrack-1));qErr=max(abs(x.Qtrack-1));
    l2Err=max(abs(x.L2Mode-l2Mode));

    post=x.t>=interventionEdge+0.012;
    pre=x.t<=interventionEdge-0.001;

    % Voltage final equation is piecewise by L2 mode.
    recMode7D=x.Vslow_d+x.Kfast_eff.*(x.rawVd-x.Vslow_d);
    recMode7Q=x.Vslow_q+x.Kfast_eff.*(x.rawVq-x.Vslow_q);
    recVD=recMode7D;recVQ=recMode7Q;
    if ismember(l2Mode,[1 3])
        recVD(post)=x.Vanchor_d(post)+x.Kslow_eff(post).*(x.Vslow_d(post)-x.Vanchor_d(post)) ...
            +x.Kfast_eff(post).*(x.rawVd(post)-x.Vslow_d(post));
        recVQ(post)=x.Vanchor_q(post)+x.Kslow_eff(post).*(x.Vslow_q(post)-x.Vanchor_q(post)) ...
            +x.Kfast_eff(post).*(x.rawVq(post)-x.Vslow_q(post));
    end
    vEq=max([max(abs(x.appVd-recVD)),max(abs(x.appVq-recVQ))]);
    vPre=max([max(abs(x.appVd(pre)-x.rawVd(pre))),max(abs(x.appVq(pre)-x.rawVq(pre)))]);

    % Old C2 TRACK=1 means its output equals raw Power-Control output exactly.
    % Layer-2 Iref equation therefore uses rawId/rawIq as Iselected.
    recID=x.rawId;recIQ=x.rawIq;
    if ismember(l2Mode,[2 3])
        recID(post)=x.Ianchor_d(post)+x.Kpq_eff(post).*(x.rawId(post)-x.Ianchor_d(post));
        recIQ(post)=x.Ianchor_q(post)+x.Kpq_eff(post).*(x.rawIq(post)-x.Ianchor_q(post));
    end
    iEq=max([max(abs(x.L2Iout_d-recID)),max(abs(x.L2Iout_q-recIQ))]);
    legacyIrefGap=max([max(abs(x.appId-x.L2Iout_d)),max(abs(x.appIq-x.L2Iout_q))]);
    iPre=max([max(abs(x.L2Iout_d(pre)-x.rawId(pre))),max(abs(x.L2Iout_q(pre)-x.rawIq(pre)))]);

    % Causal intervention magnitudes relative to the transparent path.
    vMode7D=x.Vslow_d+x.Kfast_eff.*(x.rawVd-x.Vslow_d);
    vMode7Q=x.Vslow_q+x.Kfast_eff.*(x.rawVq-x.Vslow_q);
    VffInterventionMag=hypot(x.appVd-vMode7D,x.appVq-vMode7Q);
    IrefInterventionMag=hypot(x.L2Iout_d-x.rawId,x.L2Iout_q-x.rawIq);
    ItrackErr=hypot(x.L2Iout_d-x.Id,x.L2Iout_q-x.Iq);

    kfastPost=median_safe(x.Kfast_eff(post));
    kslowPost=median_safe(x.Kslow_eff(post));
    kpqPost=median_safe(x.Kpq_eff(post));
    kslowTargetPost=median_safe(x.Kslow_target(post));
    kpqTargetPost=median_safe(x.Kpq_target(post));

    % Actual effective-gain settle times. These prove the causal dose was in
    % place before J1, rather than relying only on the target edge.
    kfastSettle=first_persistent_near(x.t,x.Kfast_eff,interventionEdge,0.0,1e-6,0.001);
    kslowSettle=first_persistent_near(x.t,x.Kslow_eff,interventionEdge,wantKslow,1e-6,0.001);
    kpqSettle=first_persistent_near(x.t,x.Kpq_eff,interventionEdge,wantKpq,1e-6,0.001);
    settleAll=max([kfastSettle,kslowSettle,kpqSettle]);
    if ~isfinite(settleAll),error('%s 至少一个Layer-2有效比例没有稳定到目标。',name);end
    settleMarginMs=(j1FirstOpen-settleAll)*1000;
    if settleMarginMs<=1.0,error('%s Layer-2比例到位距J1不足1ms：%.3fms',name,settleMarginMs);end

    % Intervention-only strong-grid window: causal intervention is already settled,
    % but J1 is still closed. This is the replacement for a separate transparent run.
    sg=x.t>=interventionEdge+0.012 & x.t<=j1FirstOpen-0.002;
    if nnz(sg)<5,error('%s intervention-only strong-grid window insufficient.',name);end
    kslowSG=median_safe(x.Kslow_eff(sg));
    kpqSG=median_safe(x.Kpq_eff(sg));
    vEqSG=max([max(abs(x.appVd(sg)-recVD(sg))),max(abs(x.appVq(sg)-recVQ(sg)))]);
    iEqSG=max([max(abs(x.L2Iout_d(sg)-recID(sg))),max(abs(x.L2Iout_q(sg)-recIQ(sg)))]);

    doseErr=max([abs(kfastPost-0.0),abs(kslowPost-wantKslow),abs(kslowTargetPost-wantKslow), ...
        abs(kpqPost-wantKpq),abs(kpqTargetPost-wantKpq)]);
    thisValid=(modeErr<1e-9)&&(c1Err<1e-9)&&(c2Err<1e-9)&&(dErr<1e-9)&&(qErr<1e-9) ...
        &&(l2Err<1e-9)&&(vEq<=VFF_EQ_TOL_ABS)&&(iEq<=IREF_EQ_TOL_ABS) ...
        &&(vPre<1e-8)&&(iPre<1e-8)&&(doseErr<1e-6) ...
        &&(vEqSG<=VFF_EQ_TOL_ABS)&&(iEqSG<=IREF_EQ_TOL_ABS);
    executionContractValid=executionContractValid&&thisValid;

    % scalar03/04 are a legacy record point that predates the new Layer-2
    % Iref wrapper. They are NOT a hard downstream proof in Mode2/3.
    % Diagnose their temporal relationship explicitly instead of invalidating
    % the causal contract.
    alignMask=x.t>=interventionEdge+0.012 & x.t<=min(x.t(end),j1FirstOpen+1.0);
    [bestLag,bestResidual,zeroLagResidual]=best_vector_lag( ...
        x.L2Iout_d(alignMask),x.L2Iout_q(alignMask),x.appId(alignMask),x.appIq(alignMask),5);
    auxWarn=(zeroLagResidual>=1e-8);
    auxIrefWarningAny=auxIrefWarningAny||auxWarn;
    alignRows(end+1,:)={name,bestLag,bestLag*median(diff(x.t))*1000,bestResidual,zeroLagResidual,legacyIrefGap}; %#ok<AGROW>

    winDefs=[-0.020 -0.002; 0.000 0.200; 0.200 1.000; 1.000 3.000];
    winNames={'StrongGrid','J1_0_0p2','J1_0p2_1','J1_1_3'};
    for wi=1:size(winDefs,1)
        if wi==1
            wm=x.t>=interventionEdge+0.012 & x.t<=j1FirstOpen-0.002;
            complete=true;
        else
            a=winDefs(wi,1); b=winDefs(wi,2);
            wm=x.t>=j1FirstOpen+a & x.t<=j1FirstOpen+b;
            complete=(x.t(end)>=j1FirstOpen+b);
        end
        interventionRows(end+1,:)={name,winNames{wi},complete, ...
            rms_safe(VffInterventionMag(wm)),max_safe(VffInterventionMag(wm)), ...
            rms_safe(IrefInterventionMag(wm)),max_safe(IrefInterventionMag(wm)), ...
            rms_safe(ItrackErr(wm)),max_safe(ItrackErr(wm))}; %#ok<AGROW>
    end

    rows(end+1,:)={name,thisValid,auxWarn,modeErr,c1Err,c2Err,dErr,qErr,l2Err,vEq,vPre,iEq,legacyIrefGap,iPre,doseErr, ...
        kfastPost,kslowPost,kslowTargetPost,kpqPost,kpqTargetPost,kslowSG,kpqSG,vEqSG,iEqSG, ...
        kfastSettle,kslowSettle,kpqSettle,settleMarginMs}; %#ok<AGROW>
    logf(fid,['[%s CONTRACT] valid=%d VEq=%.3g IEq=%.3g legacyIrefGap=%.3g preV=%.3g preI=%.3g ' ...
        'Kfast=%.4f Kslow=%.4f(target %.4f) Kpq=%.4f(target %.4f) settleMargin=%.3fms'], ...
        name,thisValid,vEq,iEq,legacyIrefGap,vPre,iPre,kfastPost,kslowPost,kslowTargetPost,kpqPost,kpqTargetPost,settleMarginMs);
end

deviceTable=cell2table(rows,'VariableNames',{ ...
    'Device','ExecutionContractValid','AuxIrefAlignmentWarning','ModeErr','OldC1Err','C2Err','DTrackErr','QTrackErr','L2ModeErr', ...
    'VoltageEquationResidual','VoltagePreBypassResidual','IrefEquationResidual','LegacyIrefRecordGap','IrefPreBypassResidual','DoseResidual', ...
    'PostKfast','PostKslow','PostKslowTarget','PostKpq','PostKpqTarget', ...
    'StrongGridKslow','StrongGridKpq','StrongGridVoltageEquationResidual','StrongGridIrefEquationResidual', ...
    'KfastSettle_s','KslowSettle_s','KpqSettle_s','SettleMarginToJ1_ms'});
writetable(deviceTable,OUT_DEV);
alignmentTable=cell2table(alignRows,'VariableNames', ...
    {'Device','BestLag_samples','BestLag_ms','BestLagResidual','ZeroLagResidual','LegacyRecordMaxGap'});
writetable(alignmentTable,OUT_ALIGN);
interventionTable=cell2table(interventionRows,'VariableNames', ...
    {'Device','Window','Complete','VffIntervention_RMS','VffIntervention_Max','IrefIntervention_RMS','IrefIntervention_Max','CurrentTrackError_RMS','CurrentTrackError_Max'});
writetable(interventionTable,OUT_INT);
logf(fid,'[EXECUTION CONTRACT OVERALL] %d',executionContractValid);
logf(fid,'[AUX IREF RECORD-POINT WARNING ANY] %d',auxIrefWarningAny);

%% 6. Physical voltage/current envelope from G29
primVab=G29(21,:);pccVab=G29(22,:);branchIa=G29(25:30,:);pccVa=G29(31,:);
branchNames={'PV1','PV2','ESS1','ESS2','EV1','EV2'};
dt29=median(diff(t29));rmsN=max(2,round(0.020/dt29));
primaryRMS=sqrt(movmean(primVab.^2,[rmsN-1 0]));
pccRMS=sqrt(movmean(pccVab.^2,[rmsN-1 0]));
branchRMS=sqrt(movmean(branchIa.^2,[rmsN-1 0],2));
preBase=t29>=j1FirstOpen-0.20 & t29<=j1FirstOpen-0.02;
if nnz(preBase)<20,error('J1前基准RMS窗口不足。');end
Vbase=median(primaryRMS(preBase));
Vpu=primaryRMS/Vbase;
logf(fid,'[PRIMARY PRE-J1 BASE] %.3f kV RMS',Vbase/1000);

sgPre=t29>=interventionEdge-0.020 & t29<=interventionEdge-0.003;
sgPost=t29>=interventionEdge+0.012 & t29<=j1FirstOpen-0.002;
if nnz(sgPre)<5||nnz(sgPost)<5,error('强网干预前/后窗口不足。');end
sgVpre=median(primaryRMS(sgPre));sgVpost=median(primaryRMS(sgPost));
sgVdeltaPu=(sgVpost-sgVpre)/Vbase;
sgRows=cell(6,5);
for b=1:6
    ipre=median(branchRMS(b,sgPre));ipost=median(branchRMS(b,sgPost));
    sgRows(b,:)={branchNames{b},ipre,ipost,ipost-ipre,(ipost-ipre)/max(abs(ipre),1e-9)};
end
strongGridTable=cell2table(sgRows,'VariableNames',{'Branch','Irms_Pre','Irms_Intervention','DeltaIrms','RelativeDelta'});
writetable(strongGridTable,OUT_SG);
logf(fid,'[INTERVENTION-ONLY STRONG GRID] Vpre=%.4fkV Vpost=%.4fkV delta=%+.6fpu',sgVpre/1000,sgVpost/1000,sgVdeltaPu);

cp=[0.020 0.050 0.100 0.150 0.200 0.300 0.500 0.750 1.000 1.500 2.000 2.500 3.000];
cpRows={};
for k=1:numel(cp)
    tt=j1FirstOpen+cp(k);
    if tt<=t29(end)
        vr=interp1(t29,primaryRMS,tt,'nearest');vp=vr/Vbase;
        ir=zeros(1,6);
        for b=1:6,ir(b)=interp1(t29,branchRMS(b,:),tt,'nearest');end
        cpRows(end+1,:)={cp(k),vr/1000,vp,ir(1),ir(2),ir(3),ir(4),ir(5),ir(6)}; %#ok<AGROW>
    end
end
cpTable=cell2table(cpRows,'VariableNames',{'AfterJ1_s','PrimaryV_kV','PrimaryV_pu','PV1_Irms','PV2_Irms','ESS1_Irms','ESS2_Irms','EV1_Irms','EV2_Irms'});
writetable(cpTable,OUT_CP);

cross95=first_persistent_below(t29,Vpu,j1FirstOpen,0.95,0.010);
cross90=first_persistent_below(t29,Vpu,j1FirstOpen,0.90,0.010);
cross80=first_persistent_below(t29,Vpu,j1FirstOpen,0.80,0.010);
cross50=first_persistent_below(t29,Vpu,j1FirstOpen,0.50,0.010);
[vSlopeEarly,vSpanEarly]=linear_window(t29-j1FirstOpen,Vpu,0.15,0.50);
[vSlopeLate,vSpanLate]=linear_window(t29-j1FirstOpen,Vpu,1.0,3.0);
areaMask=t29>=j1FirstOpen & t29<=min(t29(end),j1FirstOpen+3.0);
voltageDeficitArea=trapz(t29(areaMask)-j1FirstOpen,max(0,1-Vpu(areaMask)));
voltageOverArea=trapz(t29(areaMask)-j1FirstOpen,max(0,Vpu(areaMask)-1));
voltageAbsArea=trapz(t29(areaMask)-j1FirstOpen,abs(Vpu(areaMask)-1));

post3=t29>=j1FirstOpen & t29<=j1FirstOpen+3.0;
[minVpu,minIdxLocal]=min(Vpu(post3)); tmpT=t29(post3); minVtime=tmpT(minIdxLocal)-j1FirstOpen;
[maxVpu,maxIdxLocal]=max(Vpu(post3)); maxVtime=tmpT(maxIdxLocal)-j1FirstOpen;
recovery95=first_persistent_above(t29,Vpu,max(j1FirstOpen,cross80+0.01),0.95,0.010);
if isfinite(recovery95)
    second80=first_persistent_below(t29,Vpu,recovery95+0.02,0.80,0.010);
else
    second80=NaN;
end
over105=first_persistent_above(t29,Vpu,j1FirstOpen,1.05,0.010);
over110=first_persistent_above(t29,Vpu,j1FirstOpen,1.10,0.010);

slowN=max(3,round(0.050/dt29));
VslowEnv=movmean(Vpu,[slowN-1 0]);
extremaTable=extract_extrema_table(t29-j1FirstOpen,VslowEnv,0.10,3.00,0.08);
writetable(extremaTable,OUT_EXT);

logf(fid,'[VOLTAGE] <0.95pu=%s <0.90pu=%s <0.80pu=%s <0.50pu=%s',fmt_time(cross95),fmt_time(cross90),fmt_time(cross80),fmt_time(cross50));
logf(fid,'[VOLTAGE] recovery>0.95=%s second<0.80=%s over1.05=%s over1.10=%s', ...
    fmt_rel(recovery95,j1FirstOpen),fmt_rel(second80,j1FirstOpen),fmt_rel(over105,j1FirstOpen),fmt_rel(over110,j1FirstOpen));
logf(fid,'[VOLTAGE] min=%.5fpu@+%.4fs max=%.5fpu@+%.4fs',minVpu,minVtime,maxVpu,maxVtime);
logf(fid,'[VOLTAGE] slope0.15~0.50s=%+.6f pu/s slope1~3s=%+.6f pu/s deficit=%.6f over=%.6f absDev=%.6f pu*s', ...
    vSlopeEarly,vSlopeLate,voltageDeficitArea,voltageOverArea,voltageAbsArea);

%% 7. Fast modal calculations only
modalRows={};
for i=1:5
    name=devNames{i};x=D.(name);w=x.t>=j1FirstOpen+0.005 & x.t<=j1FirstOpen+0.095;
    if nnz(w)<50,error('%s fast-window samples insufficient.',name);end
    sigs={'appVd',x.appVd;'appVq',x.appVq;'PI_d',x.PI_d;'PI_q',x.PI_q;'Vconv_d',x.Vconv_d;'Vconv_q',x.Vconv_q};
    for sidx=1:size(sigs,1)
        sn=sigs{sidx,1};y=sigs{sidx,2};
        ft=fit_exp_sine(x.t(w),y(w),[8 25],[-100 100]);
        f17=fit_fixed_mode(x.t(w),y(w),17.1652,25.3323);
        f106=fit_fixed_mode(x.t(w),y(w),10.619,69.19);
        modalRows(end+1,:)={name,sn,ft.f,ft.sigma,ft.R2,ft.amp,f17.R2,f17.amp,f106.R2,f106.amp}; %#ok<AGROW>
    end
end
modalTable=cell2table(modalRows,'VariableNames',{'Device','Signal','BestF_Hz','BestSigma_per_s','BestR2','BestAmp','Fixed17_R2','Fixed17_Amp','Fixed10p6_R2','Fixed10p6_Amp'});
writetable(modalTable,OUT_MOD);
hi=modalTable.BestR2>=0.98 & isfinite(modalTable.BestSigma_per_s);
if any(hi)
    fastMaxSigmaHighR2=max(modalTable.BestSigma_per_s(hi));
    fastPositiveHighR2Count=nnz(modalTable.BestSigma_per_s(hi)>0);
else
    fastMaxSigmaHighR2=NaN;
    fastPositiveHighR2Count=0;
end
fixed17AmpMedian=median(modalTable.Fixed17_Amp,'omitnan');
fixed106AmpMedian=median(modalTable.Fixed10p6_Amp,'omitnan');
logf(fid,'[FAST MODAL SUMMARY] maxSigma(R2>=0.98)=%+.5f/s positiveCount=%d medianAmp17=%.6g medianAmp10p6=%.6g', ...
    fastMaxSigmaHighR2,fastPositiveHighR2Count,fixed17AmpMedian,fixed106AmpMedian);

%% 8. Five-GFL slow numerical metrics: PI, P/Q, current, frame
slowRows={};
for i=1:5
    name=devNames{i};x=D.(name);
    [pid1,pidSpan1]=linear_window(x.t-j1FirstOpen,x.PI_d,0.2,1.0);
    [piq1,piqSpan1]=linear_window(x.t-j1FirstOpen,x.PI_q,0.2,1.0);
    [pid3,pidSpan3]=linear_window(x.t-j1FirstOpen,x.PI_d,1.0,3.0);
    [piq3,piqSpan3]=linear_window(x.t-j1FirstOpen,x.PI_q,1.0,3.0);
    [pSlope,pSpan]=linear_window(x.t-j1FirstOpen,x.P,0.2,1.0);
    [qSlope,qSpan]=linear_window(x.t-j1FirstOpen,x.Q,0.2,1.0);
    [fSlope,fSpan]=linear_window(x.t-j1FirstOpen,x.execFreq,0.2,1.0);
    slowRows(end+1,:)={name,pid1,pidSpan1,piq1,piqSpan1,pid3,pidSpan3,piq3,piqSpan3,pSlope,pSpan,qSlope,qSpan,fSlope,fSpan}; %#ok<AGROW>
end
slowTable=cell2table(slowRows,'VariableNames',{'Device','PI_d_Slope_0p2_1','PI_d_Span_0p2_1','PI_q_Slope_0p2_1','PI_q_Span_0p2_1','PI_d_Slope_1_3','PI_d_Span_1_3','PI_q_Slope_1_3','PI_q_Span_1_3','P_Slope_0p2_1','P_Span_0p2_1','Q_Slope_0p2_1','Q_Span_0p2_1','ExecFreq_Slope_0p2_1','ExecFreq_Span_0p2_1'});
writetable(slowTable,OUT_SLOW);

gflWinRows={};
winA=[0 0.2;0.2 1.0;1.0 3.0];
winLbl={'0_0p2','0p2_1','1_3'};
for di=1:5
    name=devNames{di}; x=D.(name);
    vMode7D=x.Vslow_d+x.Kfast_eff.*(x.rawVd-x.Vslow_d);
    vMode7Q=x.Vslow_q+x.Kfast_eff.*(x.rawVq-x.Vslow_q);
    sigNames={'PI_d','PI_q','Vconv_d','Vconv_q','ModIndex','P','Q','ExecFreq','PLLfreq','FrameFreqGap', ...
        'RawId','RawIq','RawIrefMag','L2Iout_d','L2Iout_q','L2IrefMag','Id','Iq','CurrentMag', ...
        'VffInterventionMag','IrefInterventionMag','CurrentTrackErr'};
    sigData={x.PI_d,x.PI_q,x.Vconv_d,x.Vconv_q,x.ModIndex,x.P,x.Q,x.execFreq,x.pllFreq,x.execFreq-x.pllFreq, ...
        x.rawId,x.rawIq,hypot(x.rawId,x.rawIq),x.L2Iout_d,x.L2Iout_q,hypot(x.L2Iout_d,x.L2Iout_q), ...
        x.Id,x.Iq,hypot(x.Id,x.Iq), ...
        hypot(x.appVd-vMode7D,x.appVq-vMode7Q),hypot(x.L2Iout_d-x.rawId,x.L2Iout_q-x.rawIq), ...
        hypot(x.L2Iout_d-x.Id,x.L2Iout_q-x.Iq)};
    for wi=1:3
        a=winA(wi,1);b=winA(wi,2);
        for si=1:numel(sigNames)
            st=window_stats(x.t-j1FirstOpen,sigData{si},a,b);
            gflWinRows(end+1,:)={name,sigNames{si},winLbl{wi},a,b,st.complete,st.n,st.mean,st.rms,st.min,st.max,st.span,st.slope,st.absmax}; %#ok<AGROW>
        end
    end
end
gflWindowTable=cell2table(gflWinRows,'VariableNames', ...
    {'Device','Signal','Window','Start_s','End_s','Complete','N','Mean','RMS','Min','Max','Span','Slope_per_s','AbsMax'});
writetable(gflWindowTable,OUT_WIN);

%% 9. ESS1 full-coverage core from G29 + G30 support append
% G29 is the authoritative >=3s ESS1 core path.
EG=struct();
EG.t=t29;
EG.effIOUT_d=G29(4,:);EG.effIOUT_q=G29(5,:);
EG.finalIref_d=G29(8,:);EG.finalIref_q=G29(9,:);
EG.VPI_d=G29(10,:);EG.VPI_q=G29(11,:);
EG.CurrentPI_d=G29(12,:);EG.CurrentPI_q=G29(13,:);
EG.Vconv_d=G29(14,:);EG.Vconv_q=G29(15,:);
EG.ModIndex=G29(16,:);
EG.Fout=G29(18,:);EG.Vout=G29(19,:);
EG.rawVd=G29(32,:);EG.rawVq=G29(33,:);
EG.rawId=G29(34,:);EG.rawIq=G29(35,:);
EG.selectedVd=G29(36,:);EG.selectedVq=G29(37,:);
EG.selectedId=G29(38,:);EG.selectedIq=G29(39,:);
EG.ItrackError=hypot(EG.finalIref_d-EG.selectedId,EG.finalIref_q-EG.selectedIq);
EG.IrefMag=hypot(EG.finalIref_d,EG.finalIref_q);
EG.VPIMag=hypot(EG.VPI_d,EG.VPI_q);
EG.VconvMag=hypot(EG.Vconv_d,EG.Vconv_q);

ecoreRows={};
ecoreSigNames={'EffIOUT_d','EffIOUT_q','FinalIref_d','FinalIref_q','IrefMag','VPI_d','VPI_q','VPIMag', ...
    'CurrentPI_d','CurrentPI_q','Vconv_d','Vconv_q','VconvMag','ModIndex','Fout','Vout', ...
    'RawVd','RawVq','SelectedVd','SelectedVq','SelectedId','SelectedIq','ItrackError'};
ecoreSigData={EG.effIOUT_d,EG.effIOUT_q,EG.finalIref_d,EG.finalIref_q,EG.IrefMag,EG.VPI_d,EG.VPI_q,EG.VPIMag, ...
    EG.CurrentPI_d,EG.CurrentPI_q,EG.Vconv_d,EG.Vconv_q,EG.VconvMag,EG.ModIndex,EG.Fout,EG.Vout, ...
    EG.rawVd,EG.rawVq,EG.selectedVd,EG.selectedVq,EG.selectedId,EG.selectedIq,EG.ItrackError};
for wi=1:3
    a=winA(wi,1);b=winA(wi,2);
    for si=1:numel(ecoreSigNames)
        st=window_stats(EG.t-j1FirstOpen,ecoreSigData{si},a,b);
        ecoreRows(end+1,:)={ecoreSigNames{si},winLbl{wi},a,b,st.complete,st.n,st.mean,st.rms,st.min,st.max,st.span,st.slope,st.absmax}; %#ok<AGROW>
    end
end
ess1CoreWindowTable=cell2table(ecoreRows,'VariableNames', ...
    {'Signal','Window','Start_s','End_s','Complete','N','Mean','RMS','Min','Max','Span','Slope_per_s','AbsMax'});
writetable(ess1CoreWindowTable,OUT_ECORE);

t30=G30(1,:);
E=struct();
E.t=t30;
E.Fref=G30(2,:);E.Fout=G30(3,:);E.theta=G30(4,:);E.PLLfreq=G30(5,:);
E.Vabc=G30(6:8,:);E.P=G30(9,:);E.Q=G30(10,:);E.J1rx=G30(16,:);
% Appended signals 116..128 -> MAT rows117..129.
E.VPI_d=G30(117,:);E.VPI_q=G30(118,:);
E.IrefPre_d=G30(119,:);E.IrefPre_q=G30(120,:);
E.IrefFinal_d=G30(121,:);E.IrefFinal_q=G30(122,:);
E.Id=G30(123,:);E.Iq=G30(124,:);
E.Vconv_d=G30(125,:);E.Vconv_q=G30(126,:);
E.Vq_meas=G30(127,:);E.Vq_ref=G30(128,:);E.Vd_meas=G30(129,:);
E.Vq_error=E.Vq_ref-E.Vq_meas;
E.IrefSatResidual=hypot(E.IrefPre_d-E.IrefFinal_d,E.IrefPre_q-E.IrefFinal_q);
E.ItrackError=hypot(E.IrefFinal_d-E.Id,E.IrefFinal_q-E.Iq);
E.IrefPreMag=hypot(E.IrefPre_d,E.IrefPre_q);
E.IrefFinalMag=hypot(E.IrefFinal_d,E.IrefFinal_q);
E.VconvMag=hypot(E.Vconv_d,E.Vconv_q);

% Existing F25 scalar map. G30 signals77..90 flags -> rows78..91.
F25=struct();F25.t=t30;
F25.state=G30(78,:);F25.pre_ready=G30(79,:);F25.pre_ack=G30(80,:);
F25.edge_armed=G30(81,:);F25.edge_seen=G30(82,:);F25.event_match=G30(83,:);F25.fast_active=G30(84,:);
F25.post_candidate_valid=G30(85,:);F25.commit_active=G30(86,:);F25.commit_ack=G30(87,:);
F25.timeout=G30(88,:);F25.reject_code=G30(89,:);F25.slew_limit=G30(90,:);F25.mag_limit=G30(91,:);
% fast diag signals97..103 -> rows98..104.
F25.fast_target_d=G30(98,:);F25.fast_target_q=G30(99,:);F25.applied_d=G30(100,:);F25.applied_q=G30(101,:);F25.fast_error=G30(102,:);

satTime=first_above(t30,E.IrefSatResidual,j1FirstOpen,1e-6);
compLimitTime=first_component_limit(t30,E.IrefFinal_d,E.IrefFinal_q,j1FirstOpen,1.249);
slewTime=first_above(t30,F25.slew_limit,j1FirstOpen,0.5);
magTime=first_above(t30,F25.mag_limit,j1FirstOpen,0.5);
timeoutTime=first_above(t30,F25.timeout,j1FirstOpen,0.5);
ess1ModNearTime=first_above(EG.t,abs(EG.ModIndex),j1FirstOpen,0.98);
egPost3=EG.t>=j1FirstOpen & EG.t<=j1FirstOpen+3.0;
ess1ModMax=max_safe(abs(EG.ModIndex(egPost3)));
gflModMax=NaN;
for di=1:5
    xx=D.(devNames{di}); ww=xx.t>=j1FirstOpen & xx.t<=j1FirstOpen+3.0;
    gflModMax=max([gflModMax,max_safe(abs(xx.ModIndex(ww)))],[],'omitnan');
end

[vqErrSlope,vqErrSpan]=linear_window(t30-j1FirstOpen,E.Vq_error,0.2,1.0);
[iTrackSlope,iTrackSpan]=linear_window(t30-j1FirstOpen,E.ItrackError,0.2,1.0);
[iRefSlope,iRefSpan]=linear_window(t30-j1FirstOpen,E.IrefFinalMag,0.2,1.0);

% Theta-derived GFM frequency from G30 is onset support only; G29 Fout gives full 3s.
PI_CONST=4*atan(1); thetaU=unwrap(E.theta);thetaFreq=[NaN diff(thetaU)./diff(t30)/(2*PI_CONST)];
[foutSlope,foutSpan]=linear_window(EG.t-j1FirstOpen,EG.Fout,0.2,1.0);
[foutSlopeLate,foutSpanLate]=linear_window(EG.t-j1FirstOpen,EG.Fout,1.0,3.0);
[voutSlope,voutSpan]=linear_window(EG.t-j1FirstOpen,EG.Vout,0.2,1.0);
[voutSlopeLate,voutSpanLate]=linear_window(EG.t-j1FirstOpen,EG.Vout,1.0,3.0);
[thetaSlope,thetaSpan]=linear_window(t30-j1FirstOpen,thetaFreq,0.2,min(1.0,g30Coverage));

%% 10. PCC zero-cross frequency only while voltage is valid
zc=zero_cross_frequency_voltage_gated(t29,pccVa,Vpu,j1FirstOpen,min(t29(end),j1FirstOpen+3.0),0.70);
if isempty(zc.freq)
    logf(fid,'[PCC ZERO-CROSS] 无足够“电压>0.70pu”有效周期，不输出伪频率。');
else
    logf(fid,'[PCC ZERO-CROSS VALID ONLY] n=%d mean=%.5f min=%.5f max=%.5f Hz coverageEnd=J1+%.3fs', ...
        numel(zc.freq),mean(zc.freq),min(zc.freq),max(zc.freq),zc.lastValidTime-j1FirstOpen);
end

%% 11. Logged six-device P/Q algebraic sum on common real overlap only
% This is NOT called a load-balance proof because load P/Q and device sign
% conventions are not reconstructed here.
Psum=E.P;Qsum=E.Q;
for i=1:5
    x=D.(devNames{i});
    Pi=interp1(x.t,x.P,t30,'linear',NaN);
    Qi=interp1(x.t,x.Q,t30,'linear',NaN);
    Psum=Psum+Pi;Qsum=Qsum+Qi;
end
commonPQ=isfinite(Psum)&isfinite(Qsum);
Psum(~commonPQ)=NaN;Qsum(~commonPQ)=NaN;
[pSumSlope,pSumSpan]=linear_window(t30-j1FirstOpen,Psum,0.2,1.0);
[qSumSlope,qSumSpan]=linear_window(t30-j1FirstOpen,Qsum,0.2,1.0);

%% 11.1 ESS1 fixed checkpoints: G29 core + G30 support when available
essCpRows={};
for kk=1:numel(cp)
    rel=cp(kk); tt=j1FirstOpen+rel;
    if tt>t29(end),continue;end
    pv=interp1(t29,Vpu,tt,'nearest',NaN);
    vals29=[interp1(EG.t,EG.Fout,tt,'nearest',NaN),interp1(EG.t,EG.Vout,tt,'nearest',NaN), ...
        interp1(EG.t,EG.VPI_d,tt,'nearest',NaN),interp1(EG.t,EG.VPI_q,tt,'nearest',NaN), ...
        interp1(EG.t,EG.CurrentPI_d,tt,'nearest',NaN),interp1(EG.t,EG.CurrentPI_q,tt,'nearest',NaN), ...
        interp1(EG.t,EG.finalIref_d,tt,'nearest',NaN),interp1(EG.t,EG.finalIref_q,tt,'nearest',NaN), ...
        interp1(EG.t,EG.selectedId,tt,'nearest',NaN),interp1(EG.t,EG.selectedIq,tt,'nearest',NaN), ...
        interp1(EG.t,EG.Vconv_d,tt,'nearest',NaN),interp1(EG.t,EG.Vconv_q,tt,'nearest',NaN), ...
        interp1(EG.t,EG.ModIndex,tt,'nearest',NaN)];
    if tt<=t30(end)
        vals30=[interp1(t30,E.Vq_error,tt,'nearest',NaN),interp1(t30,E.IrefPreMag,tt,'nearest',NaN), ...
            interp1(t30,E.IrefFinalMag,tt,'nearest',NaN),interp1(t30,E.ItrackError,tt,'nearest',NaN), ...
            interp1(t30,E.IrefSatResidual,tt,'nearest',NaN),interp1(t30,F25.state,tt,'nearest',NaN), ...
            interp1(t30,F25.slew_limit,tt,'nearest',NaN),interp1(t30,F25.mag_limit,tt,'nearest',NaN), ...
            interp1(t30,F25.timeout,tt,'nearest',NaN)];
    else
        vals30=nan(1,9);
    end
    essCpRows(end+1,:)=[{rel,pv},num2cell(vals29),num2cell(vals30)]; %#ok<AGROW>
end
ess1CheckpointTable=cell2table(essCpRows,'VariableNames', ...
    {'AfterJ1_s','PrimaryV_pu','Fout','Vout','VPI_d','VPI_q','CurrentPI_d','CurrentPI_q', ...
    'FinalIref_d','FinalIref_q','SelectedId','SelectedIq','Vconv_d','Vconv_q','ModIndex', ...
    'G30_VqError','G30_IrefPreMag','G30_IrefFinalMag','G30_ItrackError','G30_IrefSatResidual', ...
    'F25_State','F25_SlewLimit','F25_MagLimit','F25_Timeout'});
writetable(ess1CheckpointTable,OUT_ECP);

ess1Table=table(l2Mode,executionContractValid,auxIrefWarningAny,g30Coverage,g30Coverage>=2.99, ...
    vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,iRefSlope,iRefSpan, ...
    foutSlope,foutSpan,foutSlopeLate,foutSpanLate,voutSlope,voutSpan,voutSlopeLate,voutSpanLate,thetaSlope,thetaSpan, ...
    pSumSlope,pSumSpan,qSumSlope,qSumSpan, ...
    satTime-j1FirstOpen,compLimitTime-j1FirstOpen,slewTime-j1FirstOpen,magTime-j1FirstOpen,timeoutTime-j1FirstOpen, ...
    'VariableNames',{'L2Mode','ExecutionContractValid','AuxIrefAlignmentWarningAny','G30CoverageAfterJ1_s','G30Complete3s', ...
    'G30_VqErrorSlope_0p2_1','G30_VqErrorSpan_0p2_1','G30_ItrackErrorSlope_0p2_1','G30_ItrackErrorSpan_0p2_1', ...
    'G30_IrefMagSlope_0p2_1','G30_IrefMagSpan_0p2_1','G29_FoutSlope_0p2_1','G29_FoutSpan_0p2_1', ...
    'G29_FoutSlope_1_3','G29_FoutSpan_1_3','G29_VoutSlope_0p2_1','G29_VoutSpan_0p2_1','G29_VoutSlope_1_3','G29_VoutSpan_1_3', ...
    'G30_ThetaFreqSlope_0p2_1','G30_ThetaFreqSpan_0p2_1','PsumSlope_0p2_1','PsumSpan_0p2_1','QsumSlope_0p2_1','QsumSpan_0p2_1', ...
    'IrefSatAfterJ1_s','IrefComponentLimitAfterJ1_s','F25SlewAfterJ1_s','F25MagAfterJ1_s','F25TimeoutAfterJ1_s'});
writetable(ess1Table,OUT_ESS1);

%% 12. Event timeline (pure timestamps)
eventNames={'Intervention_KfastTarget','Layer2_ActiveTarget','J1_FirstOpen','V_below_0p95pu','V_below_0p90pu','V_below_0p80pu','V_below_0p50pu', ...
    'V_recovery_above_0p95pu','V_second_below_0p80pu','V_above_1p05pu','V_above_1p10pu', ...
    'ESS1_Iref_SaturationResidual','ESS1_Iref_ComponentNearLimit','ESS1_ModIndex_above_0p98','F25_SlewLimit','F25_MagLimit','F25_Timeout'};
eventAbs=[interventionEdge,l2Edge,j1FirstOpen,cross95,cross90,cross80,cross50,recovery95,second80,over105,over110, ...
    satTime,compLimitTime,ess1ModNearTime,slewTime,magTime,timeoutTime];
eventRel=eventAbs-j1FirstOpen;
eventTable=table(eventNames(:),eventAbs(:),eventRel(:),'VariableNames',{'Event','AbsoluteTime_s','AfterJ1_s'});
writetable(eventTable,OUT_EVT);

%% 12.1A Exact-sample fast GFL long table (-30ms to +250ms)
fastGflRows={};
for di=1:5
    name=devNames{di};x=D.(name);
    w=x.t>=j1FirstOpen-0.030 & x.t<=j1FirstOpen+0.250;
    idx=find(w);
    for jj=reshape(idx,1,[])
        fastGflRows(end+1,:)={name,x.t(jj)-j1FirstOpen, ...
            x.rawId(jj),x.rawIq(jj),x.L2Iout_d(jj),x.L2Iout_q(jj),x.appId(jj),x.appIq(jj),x.Id(jj),x.Iq(jj), ...
            x.rawVd(jj),x.rawVq(jj),x.appVd(jj),x.appVq(jj),x.PI_d(jj),x.PI_q(jj),x.Vconv_d(jj),x.Vconv_q(jj), ...
            x.ModIndex(jj),x.P(jj),x.Q(jj),x.execFreq(jj),x.pllFreq(jj), ...
            x.Kfast_eff(jj),x.Kslow_eff(jj),x.Kpq_eff(jj),x.L2Mode(jj)}; %#ok<AGROW>
    end
end
fastGflTable=cell2table(fastGflRows,'VariableNames', ...
    {'Device','AfterJ1_s','RawIdRef','RawIqRef','L2IdRef','L2IqRef','LegacyAppliedIdRef','LegacyAppliedIqRef','Id','Iq', ...
    'RawVd','RawVq','AppliedVd','AppliedVq','CurrentPI_d','CurrentPI_q','Vconv_d','Vconv_q', ...
    'ModIndex','P','Q','ExecFreq','PLLFreq','Kfast','Kslow','Kpq','L2Mode'});
writetable(fastGflTable,OUT_FASTGFL);

%% 12.1B Exact G29 physical / ESS1 fast table
w29=t29>=j1FirstOpen-0.030 & t29<=j1FirstOpen+0.250;
fastPhyTable=table(t29(w29)'-j1FirstOpen,primaryRMS(w29)'/1000,pccRMS(w29)'/1000,Vpu(w29)',j1(w29)', ...
    branchRMS(1,w29)',branchRMS(2,w29)',branchRMS(3,w29)',branchRMS(4,w29)',branchRMS(5,w29)',branchRMS(6,w29)', ...
    EG.effIOUT_d(w29)',EG.effIOUT_q(w29)',EG.finalIref_d(w29)',EG.finalIref_q(w29)', ...
    EG.VPI_d(w29)',EG.VPI_q(w29)',EG.CurrentPI_d(w29)',EG.CurrentPI_q(w29)', ...
    EG.Vconv_d(w29)',EG.Vconv_q(w29)',EG.ModIndex(w29)',EG.Fout(w29)',EG.Vout(w29)', ...
    EG.selectedVd(w29)',EG.selectedVq(w29)',EG.selectedId(w29)',EG.selectedIq(w29)', ...
    'VariableNames',{'AfterJ1_s','PrimaryV_kV','PCCV_kV','PrimaryV_pu','J1', ...
    'PV1_Irms','PV2_Irms','ESS1_Irms','ESS2_Irms','EV1_Irms','EV2_Irms', ...
    'ESS1_EffIOUT_d','ESS1_EffIOUT_q','ESS1_FinalIref_d','ESS1_FinalIref_q','ESS1_VPI_d','ESS1_VPI_q', ...
    'ESS1_CurrentPI_d','ESS1_CurrentPI_q','ESS1_Vconv_d','ESS1_Vconv_q','ESS1_ModIndex','ESS1_Fout','ESS1_Vout', ...
    'ESS1_SelectedVd','ESS1_SelectedVq','ESS1_SelectedId','ESS1_SelectedIq'});
writetable(fastPhyTable,OUT_FASTPHY);

%% 12.1C Exact G30 ESS1 onset table (-30ms to +1s, or actual coverage)
w30=t30>=j1FirstOpen-0.030 & t30<=min(t30(end),j1FirstOpen+1.000);
g30OnsetTable=table(t30(w30)'-j1FirstOpen,E.Fref(w30)',E.Fout(w30)',E.theta(w30)',E.PLLfreq(w30)',E.P(w30)',E.Q(w30)', ...
    E.VPI_d(w30)',E.VPI_q(w30)',E.IrefPre_d(w30)',E.IrefPre_q(w30)',E.IrefFinal_d(w30)',E.IrefFinal_q(w30)', ...
    E.Id(w30)',E.Iq(w30)',E.Vconv_d(w30)',E.Vconv_q(w30)',E.Vq_meas(w30)',E.Vq_ref(w30)',E.Vd_meas(w30)', ...
    E.Vq_error(w30)',E.IrefSatResidual(w30)',E.ItrackError(w30)', ...
    F25.state(w30)',F25.fast_active(w30)',F25.commit_active(w30)',F25.timeout(w30)',F25.slew_limit(w30)',F25.mag_limit(w30)', ...
    'VariableNames',{'AfterJ1_s','Fref','Fout','Theta','PLLfreq','P','Q','VPI_d','VPI_q','IrefPre_d','IrefPre_q', ...
    'IrefFinal_d','IrefFinal_q','Id','Iq','Vconv_d','Vconv_q','Vq_meas','Vq_ref','Vd_meas','Vq_error', ...
    'IrefSatResidual','ItrackError','F25_State','F25_FastActive','F25_CommitActive','F25_Timeout','F25_SlewLimit','F25_MagLimit'});
writetable(g30OnsetTable,OUT_G30ONSET);

%% 12.2 Compact 10-ms key time series for human/assistant causal review
keyStart=j1FirstOpen-0.030;
keyEnd=min(j1FirstOpen+3.0,min([G26(1,end),G27(1,end),G28(1,end),G29(1,end)]));
keyT=keyStart:0.010:keyEnd;
key=table((keyT-j1FirstOpen)','VariableNames',{'AfterJ1_s'});
key.PrimaryV_pu=interp1(t29,Vpu,keyT,'linear',NaN)';
key.PrimaryV_kV=interp1(t29,primaryRMS/1000,keyT,'linear',NaN)';
key.PCCV_kV=interp1(t29,pccRMS/1000,keyT,'linear',NaN)';
for bi=1:6
    key.([branchNames{bi} '_Irms'])=interp1(t29,branchRMS(bi,:),keyT,'linear',NaN)';
end

% ESS1 authoritative G29 core.
egNames={'EffIOUT_d','EffIOUT_q','FinalIref_d','FinalIref_q','VPI_d','VPI_q','CurrentPI_d','CurrentPI_q', ...
    'Vconv_d','Vconv_q','ModIndex','Fout','Vout','SelectedVd','SelectedVq','SelectedId','SelectedIq'};
egData={EG.effIOUT_d,EG.effIOUT_q,EG.finalIref_d,EG.finalIref_q,EG.VPI_d,EG.VPI_q,EG.CurrentPI_d,EG.CurrentPI_q, ...
    EG.Vconv_d,EG.Vconv_q,EG.ModIndex,EG.Fout,EG.Vout,EG.selectedVd,EG.selectedVq,EG.selectedId,EG.selectedIq};
for si=1:numel(egNames)
    key.(['ESS1_' egNames{si}])=interp1(EG.t,egData{si},keyT,'linear',NaN)';
end

% Five GFL causal/controller signals.
for di=1:5
    name=devNames{di}; x=D.(name);
    dn=matlab.lang.makeValidName(name);
    pairs={ ...
        'RawId',x.rawId;'RawIq',x.rawIq;'L2Iout_d',x.L2Iout_d;'L2Iout_q',x.L2Iout_q;'Id',x.Id;'Iq',x.Iq; ...
        'RawVd',x.rawVd;'RawVq',x.rawVq;'AppVd',x.appVd;'AppVq',x.appVq;'PI_d',x.PI_d;'PI_q',x.PI_q; ...
        'Vconv_d',x.Vconv_d;'Vconv_q',x.Vconv_q;'ModIndex',x.ModIndex;'P',x.P;'Q',x.Q; ...
        'ExecFreq',x.execFreq;'PLLFreq',x.pllFreq;'FrameFreqGap',x.execFreq-x.pllFreq; ...
        'RawIrefMag',hypot(x.rawId,x.rawIq);'L2IrefMag',hypot(x.L2Iout_d,x.L2Iout_q);'CurrentMag',hypot(x.Id,x.Iq); ...
        'Kfast',x.Kfast_eff;'Kslow',x.Kslow_eff;'Kpq',x.Kpq_eff};
    for pairIdx=1:size(pairs,1)
        key.([dn '_' pairs{pairIdx,1}])=interp1(x.t,pairs{pairIdx,2},keyT,'linear',NaN)';
    end
end

% G30 support signals: remain NaN after actual G30 coverage; never extrapolate.
supportPairs={'VqError',E.Vq_error;'IrefPreMag',E.IrefPreMag;'IrefFinalMag',E.IrefFinalMag; ...
    'ItrackError',E.ItrackError;'IrefSatResidual',E.IrefSatResidual;'VconvMag',E.VconvMag; ...
    'F25State',F25.state;'F25Slew',F25.slew_limit;'F25Mag',F25.mag_limit;'F25Timeout',F25.timeout};
for pairIdx=1:size(supportPairs,1)
    key.(['ESS1_G30_' supportPairs{pairIdx,1}])=interp1(t30,supportPairs{pairIdx,2},keyT,'linear',NaN)';
end
key.LoggedDevicePsum=interp1(t30,Psum,keyT,'linear',NaN)';
key.LoggedDeviceQsum=interp1(t30,Qsum,keyT,'linear',NaN)';
writetable(key,OUT_KEY);

%% 12.3 One-row run signature for direct Mode1/Mode2/Mode3 comparison
v020=value_at_rel(t29,Vpu,j1FirstOpen,0.20);
v030=value_at_rel(t29,Vpu,j1FirstOpen,0.30);
v050=value_at_rel(t29,Vpu,j1FirstOpen,0.50);
v075=value_at_rel(t29,Vpu,j1FirstOpen,0.75);
v100=value_at_rel(t29,Vpu,j1FirstOpen,1.00);
v150=value_at_rel(t29,Vpu,j1FirstOpen,1.50);
v200=value_at_rel(t29,Vpu,j1FirstOpen,2.00);
v250=value_at_rel(t29,Vpu,j1FirstOpen,2.50);
v300=value_at_rel(t29,Vpu,j1FirstOpen,3.00);
piDmean02_1=mean(slowTable.PI_d_Slope_0p2_1,'omitnan');
piQmean02_1=mean(slowTable.PI_q_Slope_0p2_1,'omitnan');
piDmean1_3=mean(slowTable.PI_d_Slope_1_3,'omitnan');
piQmean1_3=mean(slowTable.PI_q_Slope_1_3,'omitnan');

iw=strcmp(interventionTable.Window,'J1_0p2_1');
meanVffInterventionRMS=mean(interventionTable.VffIntervention_RMS(iw),'omitnan');
meanIrefInterventionRMS=mean(interventionTable.IrefIntervention_RMS(iw),'omitnan');
meanCurrentTrackRMS=mean(interventionTable.CurrentTrackError_RMS(iw),'omitnan');
isg=strcmp(interventionTable.Window,'StrongGrid');
meanSGVffInterventionRMS=mean(interventionTable.VffIntervention_RMS(isg),'omitnan');
meanSGIrefInterventionRMS=mean(interventionTable.IrefIntervention_RMS(isg),'omitnan');

if l2Mode==3
    jointVffDoseEffective=(meanVffInterventionRMS>=DOSE_EFFECTIVE_MIN_RMS);
    jointIrefDoseEffective=(meanIrefInterventionRMS>=DOSE_EFFECTIVE_MIN_RMS);
    jointDoseEffective=jointVffDoseEffective&&jointIrefDoseEffective;
else
    jointVffDoseEffective=NaN;
    jointIrefDoseEffective=NaN;
    jointDoseEffective=NaN;
end

if l2Mode==1
    activeDoseRMS=meanVffInterventionRMS;
    activeDoseMax=mean(interventionTable.VffIntervention_Max(iw),'omitnan');
elseif l2Mode==2
    activeDoseRMS=meanIrefInterventionRMS;
    activeDoseMax=mean(interventionTable.IrefIntervention_Max(iw),'omitnan');
elseif l2Mode==3
    activeDoseRMS=hypot(meanVffInterventionRMS,meanIrefInterventionRMS);
    activeDoseMax=hypot(mean(interventionTable.VffIntervention_Max(iw),'omitnan'), ...
        mean(interventionTable.IrefIntervention_Max(iw),'omitnan'));
else
    activeDoseRMS=0.0;activeDoseMax=0.0;
end

runSignature=table(l2Mode,wantKslow,wantKpq,executionContractValid,auxIrefWarningAny, ...
    fastCoverage,g30Coverage,sgVdeltaPu,meanSGVffInterventionRMS,meanSGIrefInterventionRMS, ...
    meanVffInterventionRMS,meanIrefInterventionRMS,meanCurrentTrackRMS,activeDoseRMS,activeDoseMax, ...
    v020,v030,v050,v075,v100,v150,v200,v250,v300, ...
    cross95-j1FirstOpen,cross90-j1FirstOpen,cross80-j1FirstOpen,cross50-j1FirstOpen, ...
    recovery95-j1FirstOpen,second80-j1FirstOpen,over105-j1FirstOpen,over110-j1FirstOpen, ...
    minVpu,minVtime,maxVpu,maxVtime,vSlopeEarly,vSlopeLate,voltageDeficitArea,voltageOverArea,voltageAbsArea, ...
    fastMaxSigmaHighR2,fastPositiveHighR2Count,fixed17AmpMedian,fixed106AmpMedian, ...
    piDmean02_1,piQmean02_1,piDmean1_3,piQmean1_3, ...
    foutSpan,foutSpanLate,voutSpan,voutSpanLate,vqErrSpan,iTrackSpan,iRefSpan,ess1ModMax,gflModMax, ...
    satTime-j1FirstOpen,compLimitTime-j1FirstOpen,ess1ModNearTime-j1FirstOpen,slewTime-j1FirstOpen,magTime-j1FirstOpen,timeoutTime-j1FirstOpen, ...
    'VariableNames',{'L2Mode','Kslow','Kpq','ExecutionContractValid','AuxIrefRecordWarning', ...
    'FastCoverageAfterJ1_s','G30CoverageAfterJ1_s','StrongGridVoltageDelta_pu', ...
    'StrongGridMeanVffInterventionRMS','StrongGridMeanIrefInterventionRMS', ...
    'MeanVffInterventionRMS_0p2_1','MeanIrefInterventionRMS_0p2_1','MeanCurrentTrackRMS_0p2_1','ActiveCausalDoseRMS','ActiveCausalDoseMax', ...
    'Vpu_0p2','Vpu_0p3','Vpu_0p5','Vpu_0p75','Vpu_1','Vpu_1p5','Vpu_2','Vpu_2p5','Vpu_3', ...
    'Below0p95_s','Below0p90_s','Below0p80_s','Below0p50_s','Recovery0p95_s','SecondBelow0p80_s','Above1p05_s','Above1p10_s', ...
    'MinVpu','MinVpuTime_s','MaxVpu','MaxVpuTime_s','VoltageSlope_0p15_0p5','VoltageSlope_1_3', ...
    'VoltageDeficitArea','VoltageOverArea','VoltageAbsDeviationArea', ...
    'FastMaxSigma_R2ge0p98','FastPositiveCount_R2ge0p98','MedianFixed17Amp','MedianFixed10p6Amp', ...
    'MeanPI_dSlope_0p2_1','MeanPI_qSlope_0p2_1','MeanPI_dSlope_1_3','MeanPI_qSlope_1_3', ...
    'ESS1_FoutSpan_0p2_1','ESS1_FoutSpan_1_3','ESS1_VoutSpan_0p2_1','ESS1_VoutSpan_1_3', ...
    'G30_VqErrorSpan_0p2_1','G30_ItrackSpan_0p2_1','G30_IrefMagSpan_0p2_1','ESS1_ModIndexMax_0_3','GFL_ModIndexMax_0_3', ...
    'ESS1_IrefSat_s','ESS1_ComponentLimit_s','ESS1_ModIndex0p98_s','F25Slew_s','F25Mag_s','F25Timeout_s'});
writetable(runSignature,OUT_SIG);

%% 12.4 Mode3 final joint-proof input table
minSettleMargin=min(deviceTable.SettleMarginToJ1_ms);
allFiveContract=all(deviceTable.ExecutionContractValid~=0);
jointAnalysisReady=(l2Mode==3)&&executionContractValid&&allFiveContract&& ...
    (jointDoseEffective==1)&&(fastCoverage>=2.99)&&(g30Coverage>=0.99);

jointProofTable=table(l2Mode,wantKslow,wantKpq,executionContractValid,allFiveContract, ...
    minSettleMargin,meanSGVffInterventionRMS,meanSGIrefInterventionRMS, ...
    meanVffInterventionRMS,meanIrefInterventionRMS,jointVffDoseEffective,jointIrefDoseEffective,jointDoseEffective, ...
    fastCoverage,g30Coverage,v020,v030,v050,v075,v100,v150,v200,v250,v300, ...
    minVpu,minVtime,maxVpu,maxVtime,voltageDeficitArea,voltageOverArea,voltageAbsArea, ...
    fastMaxSigmaHighR2,fastPositiveHighR2Count,fixed17AmpMedian,fixed106AmpMedian, ...
    piDmean02_1,piQmean02_1,piDmean1_3,piQmean1_3, ...
    foutSpan,foutSpanLate,voutSpan,voutSpanLate,ess1ModMax,gflModMax, ...
    satTime-j1FirstOpen,compLimitTime-j1FirstOpen,ess1ModNearTime-j1FirstOpen, ...
    slewTime-j1FirstOpen,magTime-j1FirstOpen,timeoutTime-j1FirstOpen,jointAnalysisReady, ...
    'VariableNames',{'L2Mode','Kslow','Kpq','ExecutionContractValid','AllFiveDeviceContractValid', ...
    'MinSettleMarginToJ1_ms','StrongGridMeanVffDoseRMS','StrongGridMeanIrefDoseRMS', ...
    'PostJ1MeanVffDoseRMS_0p2_1','PostJ1MeanIrefDoseRMS_0p2_1','VffDoseEffective','IrefDoseEffective','JointDoseEffective', ...
    'FastCoverageAfterJ1_s','G30CoverageAfterJ1_s','Vpu_0p2','Vpu_0p3','Vpu_0p5','Vpu_0p75','Vpu_1','Vpu_1p5','Vpu_2','Vpu_2p5','Vpu_3', ...
    'MinVpu','MinVpuTime_s','MaxVpu','MaxVpuTime_s','VoltageDeficitArea','VoltageOverArea','VoltageAbsDeviationArea', ...
    'FastMaxSigma_R2ge0p98','FastPositiveCount_R2ge0p98','MedianFixed17Amp','MedianFixed10p6Amp', ...
    'MeanPI_dSlope_0p2_1','MeanPI_qSlope_0p2_1','MeanPI_dSlope_1_3','MeanPI_qSlope_1_3', ...
    'ESS1_FoutSpan_0p2_1','ESS1_FoutSpan_1_3','ESS1_VoutSpan_0p2_1','ESS1_VoutSpan_1_3', ...
    'ESS1_ModIndexMax_0_3','GFL_ModIndexMax_0_3','ESS1_IrefSat_s','ESS1_ComponentLimit_s','ESS1_ModIndex0p98_s', ...
    'F25Slew_s','F25Mag_s','F25Timeout_s','JointAnalysisReady'});
writetable(jointProofTable,OUT_JOINT);

%% 13. Compact numeric summary
logf(fid,'\n--- 纯数值摘要（不是根因判决） ---');
logf(fid,'executionContractValid=%d auxIrefAlignmentWarningAny=%d L2_MODE=%d',executionContractValid,auxIrefWarningAny,l2Mode);
logf(fid,'Voltage base=%.3fkV VdeficitArea(0~3s)=%.6fpu*s earlySlope=%+.6fpu/s lateSlope=%+.6fpu/s',Vbase/1000,voltageDeficitArea,vSlopeEarly,vSlopeLate);
logf(fid,'ESS1 VqError slope0.2~1=%+.6f/s span=%.6f',vqErrSlope,vqErrSpan);
logf(fid,'ESS1 ItrackError slope0.2~1=%+.6f/s span=%.6f',iTrackSlope,iTrackSpan);
logf(fid,'ESS1 IrefMag slope0.2~1=%+.6f/s span=%.6f',iRefSlope,iRefSpan);
logf(fid,'ESS1 G29 Fout span0.2~1=%.6fHz span1~3=%.6fHz | Vout span0.2~1=%.6f span1~3=%.6f',foutSpan,foutSpanLate,voutSpan,voutSpanLate);
logf(fid,'ESS1 G30 thetaFreq onset slope=%+.6fHz/s span=%.6fHz | G30 coverage=J1+%.4fs',thetaSlope,thetaSpan,g30Coverage);
logf(fid,'Logged-device algebraic Psum slope0.2~1=%+.6f/s span=%.6f | Qsum slope=%+.6f/s span=%.6f (not load-balance proof)',pSumSlope,pSumSpan,qSumSlope,qSumSpan);
logf(fid,'[INTERVENTION DOSE] meanRMS 0.2~1s: VFF=%.6g Iref=%.6g | ACTIVE=%.6g max=%.6g | currentTrack=%.6g | SG VFF=%.6g Iref=%.6g', ...
    meanVffInterventionRMS,meanIrefInterventionRMS,activeDoseRMS,activeDoseMax,meanCurrentTrackRMS,meanSGVffInterventionRMS,meanSGIrefInterventionRMS);
if l2Mode==3
    logf(fid,'[MODE3 JOINT PROOF INPUT] VFFdoseEffective=%d IrefDoseEffective=%d joint=%d analysisReady=%d minSettleMargin=%.3fms', ...
        jointVffDoseEffective,jointIrefDoseEffective,jointDoseEffective,jointAnalysisReady,minSettleMargin);
end
logf(fid,'[MODULATION] ESS1 max|ModIndex|0~3s=%.6f first>0.98=%s | GFL max=%.6f', ...
    ess1ModMax,fmt_rel(ess1ModNearTime,j1FirstOpen),gflModMax);
logf(fid,'F25/ESS1 events: sat=%s compLimit=%s slew=%s mag=%s timeout=%s',fmt_time(satTime-j1FirstOpen),fmt_time(compLimitTime-j1FirstOpen),fmt_time(slewTime-j1FirstOpen),fmt_time(magTime-j1FirstOpen),fmt_time(timeoutTime-j1FirstOpen));

%% 14. Save result and reports
result=struct();
result.version='LAYER2_CAUSAL_NUMERICAL_ANALYZER_V1_6';
result.rootFolder=rootFolder;result.outFolder=outFolder;result.manifest=manifest;
result.l2Mode=l2Mode;result.executionContractValid=executionContractValid;result.auxIrefAlignmentWarningAny=auxIrefWarningAny;result.expectedKslow=wantKslow;result.expectedKpq=wantKpq;result.l2ActiveTargetEdge=l2Edge;
result.interventionEdge=interventionEdge;result.j1LastClosed=j1LastClosed;result.j1FirstOpen=j1FirstOpen;
result.devices=D;result.deviceTable=deviceTable;result.jointProofTable=jointProofTable;result.alignmentTable=alignmentTable;result.interventionTable=interventionTable;result.slowTable=slowTable;result.gflWindowTable=gflWindowTable;result.ess1Table=ess1Table;result.ess1CoreWindowTable=ess1CoreWindowTable;result.ess1CheckpointTable=ess1CheckpointTable;result.modalTable=modalTable;result.coverageTable=coverageTable;result.runSignature=runSignature;
result.primaryRMS=primaryRMS;result.primaryVpu=Vpu;result.pccRMS=pccRMS;result.branchRMS=branchRMS;result.voltageCheckpointTable=cpTable;result.strongGridTable=strongGridTable;result.strongGridVdeltaPu=sgVdeltaPu;
result.voltageDeficitArea=voltageDeficitArea;result.voltageOverArea=voltageOverArea;result.voltageAbsArea=voltageAbsArea;result.voltageSlopeEarly=vSlopeEarly;result.voltageSlopeLate=vSlopeLate;result.voltageExtremaTable=extremaTable;
result.events=eventTable;result.ESS1=E;result.ESS1_G29=EG;result.F25=F25;result.thetaFrequency=thetaFreq;result.pccZeroCrossValid=zc;result.keyTimeseries=key;result.fastGflTable=fastGflTable;result.fastPhysicalTable=fastPhyTable;result.g30OnsetTable=g30OnsetTable;
result.PsumLogged=Psum;result.QsumLogged=Qsum;result.G29=G29;result.G30=G30;
save(OUT_MAT,'result','-v7.3');

write_report(OUT_MD,result,slowTable,cpTable,eventTable,vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,pSumSlope,pSumSpan,qSumSlope,qSumSpan);

logf(fid,'\n[OUTPUT] %s',OUT_SUM);logf(fid,'[OUTPUT] %s',OUT_MD);logf(fid,'[OUTPUT] %s',OUT_DEV);logf(fid,'[OUTPUT] %s',OUT_EVT);logf(fid,'[OUTPUT] %s',OUT_MOD);logf(fid,'[OUTPUT] %s',OUT_CP);logf(fid,'[OUTPUT] %s',OUT_SLOW);logf(fid,'[OUTPUT] %s',OUT_ESS1);logf(fid,'[OUTPUT] %s',OUT_SG);
logf(fid,'[OUTPUT] %s',OUT_COV);logf(fid,'[OUTPUT] %s',OUT_ALIGN);logf(fid,'[OUTPUT] %s',OUT_INT);logf(fid,'[OUTPUT] %s',OUT_WIN);logf(fid,'[OUTPUT] %s',OUT_ECORE);logf(fid,'[OUTPUT] %s',OUT_ECP);logf(fid,'[OUTPUT] %s',OUT_EXT);logf(fid,'[OUTPUT] %s',OUT_KEY);logf(fid,'[OUTPUT] %s',OUT_SIG);
logf(fid,'[OUTPUT] %s',OUT_FASTGFL);logf(fid,'[OUTPUT] %s',OUT_FASTPHY);logf(fid,'[OUTPUT] %s',OUT_G30ONSET);logf(fid,'[OUTPUT] %s',OUT_JOINT);logf(fid,'[OUTPUT] %s',OUT_MAT);
logf(fid,'[DONE] MATLAB只完成数值证据整理；下一步由因果比较决定。');

fprintf('\nLayer-2 numerical evidence analysis complete.\n%s\n',OUT_SUM);
end

%% =========================================================================
function d=decode_diag41(G,startRow)
a=G(startRow:startRow+40,:);d=struct();d.t=G(1,:);
d.rawId=a(1,:);d.rawIq=a(2,:);d.appId=a(3,:);d.appIq=a(4,:);d.Id=a(5,:);d.Iq=a(6,:);
d.rawVd=a(7,:);d.rawVq=a(8,:);d.appVd=a(9,:);d.appVq=a(10,:);d.PI_d=a(11,:);d.PI_q=a(12,:);
d.Vconv_d=a(13,:);d.Vconv_q=a(14,:);d.ModIndex=a(15,:);d.P=a(16,:);d.Q=a(17,:);d.execAngle=a(18,:);d.execFreq=a(19,:);d.pllTheta=a(20,:);d.pllFreq=a(21,:);
d.mode=a(22,:);d.oldC1=a(23,:);d.C2=a(24,:);d.Dtrack=a(25,:);d.Qtrack=a(26,:);
d.Vslow_d=a(27,:);d.Vslow_q=a(28,:);d.Kfast_eff=a(29,:);d.Kfast_target=a(30,:);
d.Vanchor_d=a(31,:);d.Vanchor_q=a(32,:);d.Kslow_eff=a(33,:);d.Kslow_target=a(34,:);
d.Ianchor_d=a(35,:);d.Ianchor_q=a(36,:);d.L2Iout_d=a(37,:);d.L2Iout_q=a(38,:);d.Kpq_eff=a(39,:);d.Kpq_target=a(40,:);d.L2Mode=a(41,:);
end

function path=find_latest_manifest(rootFolder,outFolder)
roots={outFolder,rootFolder,pwd};c={};dates=[];
for r=1:numel(roots)
    z=dir(fullfile(roots{r},'**','*LAYER2*manifest.json'));
    for k=1:numel(z),c{end+1}=fullfile(z(k).folder,z(k).name);dates(end+1)=z(k).datenum;end %#ok<AGROW>
end
if isempty(c),path='';else,[~,i]=max(dates);path=c{i};end
end

function X=load_family_from_k26(rootFolder,taskToken,pattern,varName,expectedRows,label,fid)
paths=resolve_family_files(rootFolder,taskToken,pattern);
if isempty(paths),error('[%s] 未找到 %s',label,pattern);end
logf(fid,'[%s] %d file(s)',label,numel(paths));
parts={};dates=zeros(1,numel(paths));
for k=1:numel(paths)
    z=dir(paths{k});dates(k)=z.datenum;logf(fid,'  %s | %.3fMB | %s',paths{k},z.bytes/1024/1024,datestr(z.datenum,'yyyy-mm-dd HH:MM:SS'));
end
[~,ord]=sort(dates);paths=paths(ord);
for k=1:numel(paths)
    S=load(paths{k});
    if isfield(S,varName),A=S.(varName);else
        fn=fieldnames(S);A=[];
        for j=1:numel(fn)
            v=S.(fn{j});if isnumeric(v)&&ismatrix(v)&&size(v,1)==expectedRows
                if ~isempty(A),error('%s 多个候选矩阵。',paths{k});end;A=v;
            end
        end
        if isempty(A),error('%s 没有 %d 行矩阵。',paths{k},expectedRows);end
    end
    if size(A,1)~=expectedRows,error('%s rows=%d expected=%d',paths{k},size(A,1),expectedRows);end
    parts{end+1}=A; %#ok<AGROW>
end
X=[parts{:}];[~,ix]=sort(X(1,:));X=X(:,ix);
key=round(X(1,:)*1e9)/1e9;[u,~,grp]=unique(key,'stable'); %#ok<ASGLU>
if numel(u)<numel(key)
    keep=true(1,numel(key));
    for g=1:max(grp)
        jj=find(grp==g);if numel(jj)>1
            ref=X(:,jj(1));
            for q=2:numel(jj)
                if max(abs(X(:,jj(q))-ref),[],'all')>1e-8,error('[%s] 同时刻不同数据，疑似混跑。',label);end
                keep(jj(q))=false;
            end
        end
    end
    X=X(:,keep);
end
if any(diff(X(1,:))<=0),error('[%s] time not strictly increasing.',label);end
logf(fid,'[%s] merged %dx%d time %.6f~%.6f dt=%.6fms',label,size(X,1),size(X,2),X(1,1),X(1,end),median(diff(X(1,:)))*1000);
end

function paths=resolve_family_files(rootFolder,taskToken,pattern)
paths={};task=find_child_dir_case_insensitive(rootFolder,taskToken);
if ~isempty(task)
    target=find_child_dir_case_insensitive(task,'OpREDHAWKtarget');
    if ~isempty(target)
        z=dir(fullfile(target,pattern));for k=1:numel(z),if ~z(k).isdir,paths{end+1}=fullfile(z(k).folder,z(k).name);end,end %#ok<AGROW>
    end
end
if isempty(paths)
    z=dir(fullfile(rootFolder,'**',pattern));
    for k=1:numel(z)
        if z(k).isdir,continue;end
        low=lower(strrep(z(k).folder,'/','\'));
        if contains(low,lower(taskToken))&&contains(low,'opredhawktarget'),paths{end+1}=fullfile(z(k).folder,z(k).name);end %#ok<AGROW>
    end
end
paths=unique(paths,'stable');
end

function child=find_child_dir_case_insensitive(parent,nameWanted)
child='';z=dir(parent);
for k=1:numel(z)
    if z(k).isdir&&~strcmp(z(k).name,'.')&&~strcmp(z(k).name,'..')&&strcmpi(z(k).name,nameWanted),child=fullfile(parent,z(k).name);return;end
end
end

function assert_all_finite(X,name)
if any(~isfinite(X(:))),error('%s contains nonfinite values.',name);end
end

function [lastHigh,firstLow]=falling_edge_times(t,x,thr)
idx=find(x(1:end-1)>thr & x(2:end)<=thr,1,'first');
if isempty(idx),lastHigh=NaN;firstLow=NaN;else,lastHigh=t(idx);firstLow=t(idx+1);end
end

function v=median_safe(x)
x=x(isfinite(x));if isempty(x),v=NaN;else,v=median(x);end
end

function [slope,span]=linear_window(t,y,a,b)
w=t>=a&t<=b&isfinite(y);
if nnz(w)<3,slope=NaN;span=NaN;return;end
p=polyfit(t(w),y(w),1);slope=p(1);span=max(y(w))-min(y(w));
end

function tt=first_persistent_below(t,y,t0,thr,persist)
tt=NaN;dt=median(diff(t));n=max(1,round(persist/dt));start=find(t>=t0,1,'first');
if isempty(start),return;end
mask=y<thr;
for k=start:max(start,numel(t)-n+1)
    if k+n-1<=numel(t)&&all(mask(k:k+n-1)),tt=t(k);return;end
end
end

function tt=first_above(t,y,t0,thr)
i=find(t>=t0 & y>thr,1,'first');if isempty(i),tt=NaN;else,tt=t(i);end
end

function tt=first_component_limit(t,d,q,t0,thr)
i=find(t>=t0 & (abs(d)>=thr | abs(q)>=thr),1,'first');if isempty(i),tt=NaN;else,tt=t(i);end
end

function s=fmt_time(x)
if ~isfinite(x),s='NaN';else,s=sprintf('%.6fs',x);end
end

function fit=fit_exp_sine(t,y,fRange,sRange)
t=t(:);y=y(:);tau=t-t(1);p=polyfit(tau,y,1);yd=y-polyval(p,tau);
scale=max(abs(yd));if scale<1e-12,fit=struct('f',NaN,'sigma',NaN,'R2',NaN,'amp',0);return;end
f0=linspace(fRange(1),fRange(2),35);s0=linspace(sRange(1),sRange(2),21);best=[Inf NaN NaN];
for fi=f0
    for sg=s0
        e=local_sse([fi sg],tau,yd,fRange,sRange);
        if e<best(1),best=[e fi sg];end
    end
end
z=fminsearch(@(z)local_sse(z,tau,yd,fRange,sRange),best(2:3),optimset('Display','off','MaxIter',400));
f=min(max(z(1),fRange(1)),fRange(2));sg=min(max(z(2),sRange(1)),sRange(2));
piConst=4*atan(1);E=exp(sg*tau);M=[E.*cos(2*piConst*f*tau) E.*sin(2*piConst*f*tau) ones(size(tau)) tau];c=M\y;yhat=M*c;
sse=sum((y-yhat).^2);sst=sum((y-mean(y)).^2);R2=1-sse/max(sst,eps);amp=hypot(c(1),c(2));
fit=struct('f',f,'sigma',sg,'R2',R2,'amp',amp);
end

function sse=local_sse(z,tau,y,fRange,sRange)
f=z(1);sg=z(2);if f<fRange(1)||f>fRange(2)||sg<sRange(1)||sg>sRange(2),sse=1e30;return;end
piConst=4*atan(1);E=exp(sg*tau);M=[E.*cos(2*piConst*f*tau) E.*sin(2*piConst*f*tau) ones(size(tau)) tau];c=M\y;r=y-M*c;sse=sum(r.^2);
end

function fit=fit_fixed_mode(t,y,f,sg)
t=t(:);y=y(:);tau=t-t(1);piConst=4*atan(1);E=exp(sg*tau);M=[E.*cos(2*piConst*f*tau) E.*sin(2*piConst*f*tau) ones(size(tau)) tau];c=M\y;yh=M*c;
sse=sum((y-yh).^2);sst=sum((y-mean(y)).^2);fit=struct('R2',1-sse/max(sst,eps),'amp',hypot(c(1),c(2)));
end

function z=zero_cross_frequency_voltage_gated(t,x,vpu,t0,t1,vmin)
w=t>=t0&t<=t1;tw=t(w);xw=x(w);vw=vpu(w);crossT=[];
for k=1:numel(tw)-1
    if vw(k)>=vmin&&vw(k+1)>=vmin&&xw(k)<=0&&xw(k+1)>0
        frac=-xw(k)/(xw(k+1)-xw(k));crossT(end+1)=tw(k)+frac*(tw(k+1)-tw(k)); %#ok<AGROW>
    end
end
if numel(crossT)<2,z=struct('times',crossT,'freq',[],'lastValidTime',NaN);return;end
per=diff(crossT);freq=1./per;ok=freq>=40&freq<=60;
freqTimes=crossT(2:end);
z=struct('times',freqTimes(ok), 'freq',freq(ok), 'lastValidTime',crossT(end));
end

function write_report(path,result,slowTable,cpTable,eventTable,vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,pSumSlope,pSumSpan,qSumSlope,qSumSpan)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('Cannot create report.');end;c=onCleanup(@()fclose(fid));
fprintf(fid,'# K26_V5 Layer-2 数值证据报告\n\n');
fprintf(fid,'> 本报告只整理数值证据，不自动宣布根因。\n\n');
fprintf(fid,'## 1. 运行合同\n\n');
fprintf(fid,'- L2_MODE：`%d`\n',result.l2Mode);fprintf(fid,'- 主执行合同有效：`%d`\n',result.executionContractValid);
fprintf(fid,'- 辅助Iref记录点对齐警告：`%d`\n',result.auxIrefAlignmentWarningAny);
fprintf(fid,'- 干预边沿：`%.6f s`\n',result.interventionEdge);fprintf(fid,'- J1首次打开：`%.6f s`\n',result.j1FirstOpen);
fprintf(fid,'- 干预后但J1仍闭合的强网电压变化：`%+.6f pu`\n',result.strongGridVdeltaPu);
fprintf(fid,'- G26~G29共同覆盖：`J1+%.4f s`\n',min([result.coverageTable.AfterJ1_s(1:4)]));
fprintf(fid,'- G30覆盖：`J1+%.4f s`（不足3s时，1~3s ESS1核心指标改用G29）\n\n',result.coverageTable.AfterJ1_s(5));
fprintf(fid,'## 2. 电压慢过程\n\n');
fprintf(fid,'- 0~3 s 电压缺额积分：`%.6f pu*s`\n',result.voltageDeficitArea);
fprintf(fid,'- 0.15~0.50 s 电压斜率：`%+.6f pu/s`\n',result.voltageSlopeEarly);
fprintf(fid,'- 1~3 s 电压斜率：`%+.6f pu/s`\n',result.voltageSlopeLate);
fprintf(fid,'- 0~3 s 欠压面积：`%.6f pu*s`\n',result.voltageDeficitArea);
fprintf(fid,'- 0~3 s 过压面积：`%.6f pu*s`\n',result.voltageOverArea);
fprintf(fid,'- 0~3 s 绝对偏差面积：`%.6f pu*s`\n\n',result.voltageAbsArea);
fprintf(fid,'### 检查点\n\n');
fprintf(fid,'| J1后(s) | 电压(kV RMS) | 电压(pu) |\n|---:|---:|---:|\n');
for i=1:height(cpTable),fprintf(fid,'| %.3f | %.4f | %.5f |\n',cpTable.AfterJ1_s(i),cpTable.PrimaryV_kV(i),cpTable.PrimaryV_pu(i));end
fprintf(fid,'\n## 3. ESS1支撑链\n\n');
fprintf(fid,'- Vq误差 0.2~1 s slope/span：`%+.6f / %.6f`\n',vqErrSlope,vqErrSpan);
fprintf(fid,'- 电流跟踪误差 0.2~1 s slope/span：`%+.6f / %.6f`\n',iTrackSlope,iTrackSpan);
fprintf(fid,'- 六设备记录P代数和 slope/span：`%+.6f / %.6f`\n',pSumSlope,pSumSpan);
fprintf(fid,'- 六设备记录Q代数和 slope/span：`%+.6f / %.6f`\n\n',qSumSlope,qSumSpan);
fprintf(fid,'## 4. 事件时间线\n\n');
fprintf(fid,'| 事件 | J1后(s) |\n|---|---:|\n');
for i=1:height(eventTable),fprintf(fid,'| %s | %.6f |\n',eventTable.Event{i},eventTable.AfterJ1_s(i));end
fprintf(fid,'\n## 5. 五台PI慢漂移\n\n');
fprintf(fid,'|设备|PI_d slope 0.2~1|PI_q slope 0.2~1|PI_d slope 1~3|PI_q slope 1~3|\n|---|---:|---:|---:|---:|\n');
for i=1:height(slowTable),fprintf(fid,'|%s|%+.6f|%+.6f|%+.6f|%+.6f|\n',slowTable.Device{i},slowTable.PI_d_Slope_0p2_1(i),slowTable.PI_q_Slope_0p2_1(i),slowTable.PI_d_Slope_1_3(i),slowTable.PI_q_Slope_1_3(i));end
fprintf(fid,'\n## 6. 使用规则\n\n');
fprintf(fid,'本报告不能单独得出“慢前馈是根因”或“P/Q是根因”。必须把历史正式Mode7与本次Mode1/Mode2/必要时Mode3放在同一指标体系中比较。\n');
end

function tt=first_persistent_near(t,y,t0,target,tol,persist)
tt=NaN;dt=median(diff(t));n=max(1,round(persist/dt));start=find(t>=t0,1,'first');
if isempty(start),return;end
ok=abs(y-target)<=tol;
for k=start:max(start,numel(t)-n+1)
    if k+n-1<=numel(t)&&all(ok(k:k+n-1)),tt=t(k);return;end
end
end

function tt=first_persistent_above(t,y,t0,thr,persist)
tt=NaN;dt=median(diff(t));n=max(1,round(persist/dt));start=find(t>=t0,1,'first');
if isempty(start),return;end
mask=y>thr;
for k=start:max(start,numel(t)-n+1)
    if k+n-1<=numel(t)&&all(mask(k:k+n-1)),tt=t(k);return;end
end
end

function s=fmt_rel(absT,j1)
if ~isfinite(absT),s='NaN';else,s=sprintf('%+.6fs',absT-j1);end
end

function v=rms_safe(x)
x=x(isfinite(x));if isempty(x),v=NaN;else,v=sqrt(mean(x.^2));end
end

function v=max_safe(x)
x=x(isfinite(x));if isempty(x),v=NaN;else,v=max(x);end
end

function [bestLag,bestResidual,zeroResidual]=best_vector_lag(ad,aq,bd,bq,maxLag)
ad=ad(:);aq=aq(:);bd=bd(:);bq=bq(:);
n=min([numel(ad),numel(aq),numel(bd),numel(bq)]);
ad=ad(1:n);aq=aq(1:n);bd=bd(1:n);bq=bq(1:n);
zeroResidual=max([abs(ad-bd);abs(aq-bq)],[],'all');
bestResidual=Inf;bestLag=0;
for lag=-maxLag:maxLag
    if lag>=0
        ia=(1+lag):n; ib=1:(n-lag);
    else
        ia=1:(n+lag); ib=(1-lag):n;
    end
    if isempty(ia),continue;end
    r=max([abs(ad(ia)-bd(ib));abs(aq(ia)-bq(ib))],[],'all');
    if r<bestResidual,bestResidual=r;bestLag=lag;end
end
end

function st=window_stats(t,y,a,b)
w=t>=a&t<=b&isfinite(y);
st=struct('complete',max(t)>=b,'n',nnz(w),'mean',NaN,'rms',NaN,'min',NaN,'max',NaN,'span',NaN,'slope',NaN,'absmax',NaN);
if nnz(w)<2,return;end
tw=t(w);yw=y(w);
st.mean=mean(yw);st.rms=sqrt(mean(yw.^2));st.min=min(yw);st.max=max(yw);st.span=st.max-st.min;st.absmax=max(abs(yw));
if nnz(w)>=3,p=polyfit(tw,yw,1);st.slope=p(1);end
end

function tbl=extract_extrema_table(t,y,a,b,minSep)
w=t>=a&t<=b&isfinite(y);tt=t(w);yy=y(w);
rows={};
if numel(tt)<5
    tbl=cell2table(cell(0,3),'VariableNames',{'Type','AfterJ1_s','Vpu'});
    return;
end
d=diff(yy);
candMin=find(d(1:end-1)<0 & d(2:end)>=0)+1;
candMax=find(d(1:end-1)>0 & d(2:end)<=0)+1;
lastT=-Inf;
events=[candMin(:),-ones(numel(candMin),1);candMax(:),ones(numel(candMax),1)];
[~,ord]=sort(events(:,1));events=events(ord,:);
for k=1:size(events,1)
    idx=events(k,1);
    if tt(idx)-lastT<minSep,continue;end
    if events(k,2)<0,typ='MIN';else,typ='MAX';end
    rows(end+1,:)={typ,tt(idx),yy(idx)}; %#ok<AGROW>
    lastT=tt(idx);
end
if isempty(rows)
    rows=cell(0,3);
end
tbl=cell2table(rows,'VariableNames',{'Type','AfterJ1_s','Vpu'});
end

function v=value_at_rel(t,y,j1,rel)
tt=j1+rel;
if tt<t(1)||tt>t(end),v=NaN;else,v=interp1(t,y,tt,'nearest',NaN);end
end

function logf(fid,fmt,varargin)
s=sprintf(fmt,varargin{:});fprintf('%s\n',s);fprintf(fid,'%s\n',s);
end

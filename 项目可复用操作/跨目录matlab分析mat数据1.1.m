function result = ANALYZE_K26_V5_LAYER2_CAUSAL_RUN_V1_1(rootFolder,outFolder)
% K26_V5 Layer-2 causal run numerical evidence analyzer V1.1
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
% result = ANALYZE_K26_V5_LAYER2_CAUSAL_RUN_V1_1( ...
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
    outFolder=fullfile(rootFolder,'LAYER2_CAUSAL_ANALYSIS');
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
OUT_MAT=fullfile(outFolder,'L2_EVIDENCE_PACKAGE.mat');

fid=fopen(OUT_SUM,'w','n','UTF-8');
if fid<0,error('Cannot create summary.');end
cFid=onCleanup(@()fclose(fid));

logf(fid,repmat('=',1,144));
logf(fid,'K26_V5 Layer-2 数值证据分析 V1.1');
logf(fid,'Root: %s',rootFolder);
logf(fid,'MATLAB只做数值计算/合同验证，不自动宣布根因或修复成功。');
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

kslowEdges=nan(1,5);kpqEdges=nan(1,5);
for i=1:5
    x=D.(devNames{i});
    [~,kslowEdges(i)]=falling_edge_times(x.t,x.Kslow_target,0.999999);
    [~,kpqEdges(i)]=falling_edge_times(x.t,x.Kpq_target,0.999999);
end

%% 5. Point-by-point execution contract
rows={};
dataContractValid=true;
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
    downstreamI=max([max(abs(x.appId-x.L2Iout_d)),max(abs(x.appIq-x.L2Iout_q))]);
    iPre=max([max(abs(x.L2Iout_d(pre)-x.rawId(pre))),max(abs(x.L2Iout_q(pre)-x.rawIq(pre)))]);

    kfastPost=median_safe(x.Kfast_eff(post));
    kslowPost=median_safe(x.Kslow_eff(post));
    kpqPost=median_safe(x.Kpq_eff(post));
    kslowTargetPost=median_safe(x.Kslow_target(post));
    kpqTargetPost=median_safe(x.Kpq_target(post));

    % Intervention-only strong-grid window: causal intervention is already settled,
    % but J1 is still closed. This is the replacement for a separate transparent run.
    sg=x.t>=interventionEdge+0.012 & x.t<=j1FirstOpen-0.002;
    if nnz(sg)<5,error('%s intervention-only strong-grid window insufficient.',name);end
    kslowSG=median_safe(x.Kslow_eff(sg));
    kpqSG=median_safe(x.Kpq_eff(sg));
    vEqSG=max([max(abs(x.appVd(sg)-recVD(sg))),max(abs(x.appVq(sg)-recVQ(sg)))]);
    iEqSG=max([max(abs(x.L2Iout_d(sg)-recID(sg))),max(abs(x.L2Iout_q(sg)-recIQ(sg)))]);

    thisValid=(modeErr<1e-9)&&(c1Err<1e-9)&&(c2Err<1e-9)&&(dErr<1e-9)&&(qErr<1e-9) ...
        &&(l2Err<1e-9)&&(vEq<1e-8)&&(iEq<1e-8)&&(downstreamI<1e-8)&&(vPre<1e-8)&&(iPre<1e-8);
    dataContractValid=dataContractValid&&thisValid;

    rows(end+1,:)={name,thisValid,modeErr,c1Err,c2Err,dErr,qErr,l2Err,vEq,vPre,iEq,downstreamI,iPre, ...
        kfastPost,kslowPost,kslowTargetPost,kpqPost,kpqTargetPost,kslowSG,kpqSG,vEqSG,iEqSG}; %#ok<AGROW>
    logf(fid,['[%s CONTRACT] valid=%d VEq=%.3g IEq=%.3g downstreamI=%.3g preV=%.3g preI=%.3g ' ...
        'Kfast=%.4f Kslow=%.4f(target %.4f) Kpq=%.4f(target %.4f)'], ...
        name,thisValid,vEq,iEq,downstreamI,vPre,iPre,kfastPost,kslowPost,kslowTargetPost,kpqPost,kpqTargetPost);
end

deviceTable=cell2table(rows,'VariableNames',{ ...
    'Device','DataContractValid','ModeErr','OldC1Err','C2Err','DTrackErr','QTrackErr','L2ModeErr', ...
    'VoltageEquationResidual','VoltagePreBypassResidual','IrefEquationResidual','IrefDownstreamResidual','IrefPreBypassResidual', ...
    'PostKfast','PostKslow','PostKslowTarget','PostKpq','PostKpqTarget', ...
    'StrongGridKslow','StrongGridKpq','StrongGridVoltageEquationResidual','StrongGridIrefEquationResidual'});
writetable(deviceTable,OUT_DEV);
logf(fid,'[DATA CONTRACT OVERALL] %d',dataContractValid);

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
logf(fid,'[VOLTAGE] <0.95pu=%s <0.90pu=%s <0.80pu=%s <0.50pu=%s',fmt_time(cross95),fmt_time(cross90),fmt_time(cross80),fmt_time(cross50));
logf(fid,'[VOLTAGE] slope0.15~0.50s=%+.6f pu/s slope1~3s=%+.6f pu/s deficitArea0~3s=%.6f pu*s',vSlopeEarly,vSlopeLate,voltageDeficitArea);

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

%% 9. ESS1 support-chain append + old F25 timeline
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

[vqErrSlope,vqErrSpan]=linear_window(t30-j1FirstOpen,E.Vq_error,0.2,1.0);
[iTrackSlope,iTrackSpan]=linear_window(t30-j1FirstOpen,E.ItrackError,0.2,1.0);
[iRefSlope,iRefSpan]=linear_window(t30-j1FirstOpen,E.IrefFinalMag,0.2,1.0);

% Theta-derived GFM frequency.
thetaU=unwrap(E.theta);thetaFreq=[NaN diff(thetaU)./diff(t30)/(2*pi)];
[foutSlope,foutSpan]=linear_window(t30-j1FirstOpen,E.Fout,0.2,1.0);
[thetaSlope,thetaSpan]=linear_window(t30-j1FirstOpen,thetaFreq,0.2,1.0);

%% 10. PCC zero-cross frequency only while voltage is valid
zc=zero_cross_frequency_voltage_gated(t29,pccVa,Vpu,j1FirstOpen,min(t29(end),j1FirstOpen+3.0),0.70);
if isempty(zc.freq)
    logf(fid,'[PCC ZERO-CROSS] 无足够“电压>0.70pu”有效周期，不输出伪频率。');
else
    logf(fid,'[PCC ZERO-CROSS VALID ONLY] n=%d mean=%.5f min=%.5f max=%.5f Hz coverageEnd=J1+%.3fs', ...
        numel(zc.freq),mean(zc.freq),min(zc.freq),max(zc.freq),zc.lastValidTime-j1FirstOpen);
end

%% 11. Six-device logged P/Q algebraic sum on common t30
Psum=E.P;Qsum=E.Q;
for i=1:5
    x=D.(devNames{i});
    Psum=Psum+interp1(x.t,x.P,t30,'linear','extrap');
    Qsum=Qsum+interp1(x.t,x.Q,t30,'linear','extrap');
end
[pSumSlope,pSumSpan]=linear_window(t30-j1FirstOpen,Psum,0.2,1.0);
[qSumSlope,qSumSpan]=linear_window(t30-j1FirstOpen,Qsum,0.2,1.0);

ess1Table=table(l2Mode,dataContractValid,vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,iRefSlope,iRefSpan, ...
    foutSlope,foutSpan,thetaSlope,thetaSpan,pSumSlope,pSumSpan,qSumSlope,qSumSpan, ...
    satTime-j1FirstOpen,compLimitTime-j1FirstOpen,slewTime-j1FirstOpen,magTime-j1FirstOpen,timeoutTime-j1FirstOpen, ...
    'VariableNames',{'L2Mode','DataContractValid','VqErrorSlope_0p2_1','VqErrorSpan_0p2_1','ItrackErrorSlope_0p2_1','ItrackErrorSpan_0p2_1', ...
    'IrefMagSlope_0p2_1','IrefMagSpan_0p2_1','FoutSlope_0p2_1','FoutSpan_0p2_1','ThetaFreqSlope_0p2_1','ThetaFreqSpan_0p2_1', ...
    'PsumSlope_0p2_1','PsumSpan_0p2_1','QsumSlope_0p2_1','QsumSpan_0p2_1','IrefSatAfterJ1_s','IrefComponentLimitAfterJ1_s','F25SlewAfterJ1_s','F25MagAfterJ1_s','F25TimeoutAfterJ1_s'});
writetable(ess1Table,OUT_ESS1);

%% 12. Event timeline (pure timestamps)
eventNames={'Intervention_KfastTarget','J1_FirstOpen','V_below_0p95pu','V_below_0p90pu','V_below_0p80pu','V_below_0p50pu', ...
    'ESS1_Iref_SaturationResidual','ESS1_Iref_ComponentNearLimit','F25_SlewLimit','F25_MagLimit','F25_Timeout'};
eventAbs=[interventionEdge,j1FirstOpen,cross95,cross90,cross80,cross50,satTime,compLimitTime,slewTime,magTime,timeoutTime];
eventRel=eventAbs-j1FirstOpen;
eventTable=table(eventNames(:),eventAbs(:),eventRel(:),'VariableNames',{'Event','AbsoluteTime_s','AfterJ1_s'});
writetable(eventTable,OUT_EVT);

%% 13. Compact numeric summary
logf(fid,'\n--- 纯数值摘要（不是根因判决） ---');
logf(fid,'dataContractValid=%d L2_MODE=%d',dataContractValid,l2Mode);
logf(fid,'Voltage base=%.3fkV VdeficitArea(0~3s)=%.6fpu*s earlySlope=%+.6fpu/s lateSlope=%+.6fpu/s',Vbase/1000,voltageDeficitArea,vSlopeEarly,vSlopeLate);
logf(fid,'ESS1 VqError slope0.2~1=%+.6f/s span=%.6f',vqErrSlope,vqErrSpan);
logf(fid,'ESS1 ItrackError slope0.2~1=%+.6f/s span=%.6f',iTrackSlope,iTrackSpan);
logf(fid,'ESS1 IrefMag slope0.2~1=%+.6f/s span=%.6f',iRefSlope,iRefSpan);
logf(fid,'ESS1 Fout slope0.2~1=%+.6fHz/s span=%.6fHz thetaFreq slope=%+.6fHz/s span=%.6fHz',foutSlope,foutSpan,thetaSlope,thetaSpan);
logf(fid,'Logged six-device Psum slope0.2~1=%+.6f/s span=%.6f | Qsum slope=%+.6f/s span=%.6f',pSumSlope,pSumSpan,qSumSlope,qSumSpan);
logf(fid,'F25/ESS1 events: sat=%s compLimit=%s slew=%s mag=%s timeout=%s',fmt_time(satTime-j1FirstOpen),fmt_time(compLimitTime-j1FirstOpen),fmt_time(slewTime-j1FirstOpen),fmt_time(magTime-j1FirstOpen),fmt_time(timeoutTime-j1FirstOpen));

%% 14. Save result and reports
result=struct();
result.version='LAYER2_CAUSAL_NUMERICAL_ANALYZER_V1_1';
result.rootFolder=rootFolder;result.outFolder=outFolder;result.manifest=manifest;
result.l2Mode=l2Mode;result.dataContractValid=dataContractValid;
result.interventionEdge=interventionEdge;result.j1LastClosed=j1LastClosed;result.j1FirstOpen=j1FirstOpen;
result.devices=D;result.deviceTable=deviceTable;result.slowTable=slowTable;result.ess1Table=ess1Table;result.modalTable=modalTable;
result.primaryRMS=primaryRMS;result.primaryVpu=Vpu;result.pccRMS=pccRMS;result.branchRMS=branchRMS;result.voltageCheckpointTable=cpTable;result.strongGridTable=strongGridTable;result.strongGridVdeltaPu=sgVdeltaPu;
result.voltageDeficitArea=voltageDeficitArea;result.voltageSlopeEarly=vSlopeEarly;result.voltageSlopeLate=vSlopeLate;
result.events=eventTable;result.ESS1=E;result.F25=F25;result.thetaFrequency=thetaFreq;result.pccZeroCrossValid=zc;
result.PsumLogged=Psum;result.QsumLogged=Qsum;result.G29=G29;result.G30=G30;
save(OUT_MAT,'result','-v7.3');

write_report(OUT_MD,result,slowTable,cpTable,eventTable,vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,pSumSlope,pSumSpan,qSumSlope,qSumSpan);

logf(fid,'\n[OUTPUT] %s',OUT_SUM);logf(fid,'[OUTPUT] %s',OUT_MD);logf(fid,'[OUTPUT] %s',OUT_DEV);logf(fid,'[OUTPUT] %s',OUT_EVT);logf(fid,'[OUTPUT] %s',OUT_MOD);logf(fid,'[OUTPUT] %s',OUT_CP);logf(fid,'[OUTPUT] %s',OUT_SLOW);logf(fid,'[OUTPUT] %s',OUT_ESS1);logf(fid,'[OUTPUT] %s',OUT_SG);logf(fid,'[OUTPUT] %s',OUT_MAT);
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
E=exp(sg*tau);M=[E.*cos(2*pi*f*tau) E.*sin(2*pi*f*tau) ones(size(tau)) tau];c=M\y;yhat=M*c;
sse=sum((y-yhat).^2);sst=sum((y-mean(y)).^2);R2=1-sse/max(sst,eps);amp=hypot(c(1),c(2));
fit=struct('f',f,'sigma',sg,'R2',R2,'amp',amp);
end

function sse=local_sse(z,tau,y,fRange,sRange)
f=z(1);sg=z(2);if f<fRange(1)||f>fRange(2)||sg<sRange(1)||sg>sRange(2),sse=1e30;return;end
E=exp(sg*tau);M=[E.*cos(2*pi*f*tau) E.*sin(2*pi*f*tau) ones(size(tau)) tau];c=M\y;r=y-M*c;sse=sum(r.^2);
end

function fit=fit_fixed_mode(t,y,f,sg)
t=t(:);y=y(:);tau=t-t(1);E=exp(sg*tau);M=[E.*cos(2*pi*f*tau) E.*sin(2*pi*f*tau) ones(size(tau)) tau];c=M\y;yh=M*c;
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
z=struct('times',crossT(2:end), 'freq',freq(ok), 'lastValidTime',crossT(end));
end

function write_report(path,result,slowTable,cpTable,eventTable,vqErrSlope,vqErrSpan,iTrackSlope,iTrackSpan,pSumSlope,pSumSpan,qSumSlope,qSumSpan)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('Cannot create report.');end;c=onCleanup(@()fclose(fid));
fprintf(fid,'# K26_V5 Layer-2 数值证据报告\n\n');
fprintf(fid,'> 本报告只整理数值证据，不自动宣布根因。\n\n');
fprintf(fid,'## 1. 运行合同\n\n');
fprintf(fid,'- L2_MODE：`%d`\n',result.l2Mode);fprintf(fid,'- 数据合同有效：`%d`\n',result.dataContractValid);
fprintf(fid,'- 干预边沿：`%.6f s`\n',result.interventionEdge);fprintf(fid,'- J1首次打开：`%.6f s`\n',result.j1FirstOpen);
fprintf(fid,'- 干预后但J1仍闭合的强网电压变化：`%+.6f pu`\n\n',result.strongGridVdeltaPu);
fprintf(fid,'## 2. 电压慢过程\n\n');
fprintf(fid,'- 0~3 s 电压缺额积分：`%.6f pu*s`\n',result.voltageDeficitArea);
fprintf(fid,'- 0.15~0.50 s 电压斜率：`%+.6f pu/s`\n',result.voltageSlopeEarly);
fprintf(fid,'- 1~3 s 电压斜率：`%+.6f pu/s`\n\n',result.voltageSlopeLate);
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
fprintf(fid,'本报告不能单独得出“慢前馈是根因”或“P/Q是根因”。必须把 Mode0/1/2/3 放在同一指标体系中比较。\n');
end

function logf(fid,fmt,varargin)
s=sprintf(fmt,varargin{:});fprintf('%s\n',s);fprintf(fid,'%s\n',s);
end

function result = ANALYZE_K26_K50_ESS2_PQ_CAUSAL_A0_R1(searchRoot)
% ANALYZE_K26_K50_ESS2_PQ_CAUSAL_A0_R1
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 A0 causal experiment DirectMAT calculator.
%
% A0 experiment contract
% ----------------------
%   P active-power outer loop = OFF
%   Q reactive-power outer loop = OFF
%   Direct dq-current branch   = ON
%   Direct Id target           = 0
%   Direct Iq target           = 0
%
% The frozen BASETEST legal target remains -0.005 pu, but the R2 Runner
% intentionally pauses BEFORE S14 state40 / nonzero pickup.  Therefore the
% actually executed Pref is expected to remain zero throughout the A0
% causal observation window.
%
% PURPOSE
% -------
% Use MATLAB for the large MAT numerical work.  This script:
%   1) auto-finds the latest completed pqcausal_a0_* R2 run;
%   2) uses the exact file-id / exact G27,G29,G30 filenames in manifest.json;
%   3) finds the exact MATs under current OpREDHAWKtarget directories;
%   4) audits MAT variables with whos('-file',...) before loading;
%   5) loads G27/G29/G30 one family at a time;
%   6) separates pre-state6 and four 1-s A0 windows after state6;
%   7) calculates voltage / power / current / PI / support / limiter metrics;
%   8) calculates early-vs-late growth evidence and descriptive FFT evidence;
%   9) verifies the host/model A0 command contract from G27/G29 evidence;
%  10) exports compact CSV/JSON/MAT/PNG evidence and a ZIP for upload.
%
% IMPORTANT
% ---------
%   - No RT-LAB connection.
%   - No model modification.
%   - No interpolation.
%   - No automatic electrical PASS/FAIL.
%   - FFT peaks are descriptive frequency evidence, NOT eigenvalue modes.
%   - G30 legacy rows 1~128 are not silently renamed without a frozen map.
%   - A MATLAB post-processing error is NOT a reason to rerun the RT-LAB trial.
%
% RECOMMENDED
% -----------
%   result = ANALYZE_K26_K50_ESS2_PQ_CAUSAL_A0_R1;
%
% Optional explicit run:
%   result = ANALYZE_K26_K50_ESS2_PQ_CAUSAL_A0_R1( ...
%       'D:\E2RUN\pqcausal_a0_YYYYMMDD_HHMMSS_xxxxxx');
%
% MATLAB R2023b.
% =========================================================================

if nargin < 1
    searchRoot = '';
end

C = local_config();
stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
result = struct();
result.version = C.version;
result.status = 'STARTED';

[tempGuard,run] = resolve_run(searchRoot,C); %#ok<NASGU>

fprintf('\n====================================================================\n');
fprintf('ESS2 A0 causal DirectMAT R1\n');
fprintf('Manifest : %s\n',run.manifestPath);
fprintf('Run dir  : %s\n',run.runDir);
fprintf('File ID  : %.0f\n',run.fileID);
fprintf('State6   : %.9f s\n',run.firstState6);
fprintf('====================================================================\n');

% Hard identity gate: this calculator is specifically for the corrected A0 R2.
validate_a0_manifest(run);

outDir = fullfile(run.outputAnchor,['MATLAB_A0_DIRECTMAT_' stamp]);
if exist(outDir,'dir') == 7
    outDir = [outDir '_' nonce4()];
end
mkdir(outDir);
result.outputDirectory = outDir;

summaryPath = fullfile(outDir,'00_SUMMARY.txt');
fid = fopen(summaryPath,'w','n','UTF-8');
if fid < 0
    error('A0MAT:SummaryCreate','Cannot create %s',summaryPath);
end
fidGuard = onCleanup(@()fclose(fid)); %#ok<NASGU>

try
    logf(fid,'K26_K50 / ESS2 A0 causal DirectMAT R1');
    logf(fid,'Version: %s',C.version);
    logf(fid,'Manifest: %s',run.manifestPath);
    logf(fid,'Manifest status: %s',run.status);
    logf(fid,'Manifest target clock: %.9f s',run.targetClock);
    logf(fid,'Manifest first state6: %.9f s',run.firstState6);
    logf(fid,'Manifest file ID: %.0f',run.fileID);
    logf(fid,'A0: P-loop OFF, Q-loop OFF, Direct branch ON, Id=Iq=0.');
    logf(fid,'Frozen legal pickup target remains -0.005 pu; executed Pref should remain 0 before state40.');
    logf(fid,'MATLAB computes evidence only. No automatic electrical PASS/FAIL.');

    %% ====================================================================
    % 1. Exact MAT discovery
    % =====================================================================
    roots = build_search_roots(run,C);
    selected = struct();
    fileRows = cell(0,8);

    groups = {'G27','G29','G30'};
    for gi=1:numel(groups)
        g=groups{gi};
        exactName=run.expected.(g);
        [selPath,candidates]=find_exact_mat(exactName,roots);
        selected.(g)=selPath;

        d=dir(selPath);
        inOp=contains(lower(strrep(selPath,'\','/')),'/opredhawktarget/');
        fileRows(end+1,:)={g,exactName,selPath,d.bytes,datestr(d.datenum,31), ...
            numel(candidates),inOp,'SELECTED'}; %#ok<AGROW>

        logf(fid,'[%s] %s',g,selPath);
        if numel(candidates)>1
            logf(fid,'[%s NOTE] %d exact-name copies found; newest OpREDHAWKtarget copy selected.', ...
                g,numel(candidates));
        end
    end

    Tfiles=cell2table(fileRows,'VariableNames', ...
        {'Group','ExpectedFile','SelectedPath','Bytes','Modified','CandidateCount','InOpREDHAWKtarget','Status'});
    writetable(Tfiles,fullfile(outDir,'01_FILE_DISCOVERY.csv'));

    %% ====================================================================
    % 2. G27 -- ESS2 high-rate causal evidence
    % =====================================================================
    logf(fid,'');
    logf(fid,'--- G27 LOAD / CALCULATION ---');

    [G27,var27]=load_exact_family(selected.G27,C.expectedVar.G27,C.expectedRows.G27,'G27',fid,outDir);
    [G27,ta27]=sanitize_time_axis(G27,'G27');
    writetable(ta27,fullfile(outDir,'02A_G27_TIME_AXIS.csv'));

    t=double(G27(1,:));
    X=@(k) double(G27(k+1,:));

    s=struct();
    s.RawP             = X(1);
    s.RawQ             = X(2);
    s.FinalId          = X(3);
    s.FinalIq          = X(4);
    s.IdMeas           = X(5);
    s.IqMeas           = X(6);
    s.ModIndex         = X(15);
    s.Pmeas            = X(16);
    s.Qmeas            = X(17);
    s.GammaP           = X(18);
    s.PLL              = X(19);
    s.RestoreState     = X(20);
    s.Vpu              = X(21);
    s.VsupportRef      = X(22);
    s.GammaQ           = X(23);
    s.PrefCmd          = X(24);
    s.PrefAfterUV      = X(25);
    s.PrefEff          = X(26);
    s.TotalSupportD    = X(29);
    s.TotalSupportQ    = X(30);
    s.RestoreHold      = X(31);
    s.RestoreAlpha     = X(33);
    s.Breaker          = X(34);
    s.CurrentLimit     = X(35);
    s.ReleaseAllowed   = X(37);
    s.FailCode         = X(38);
    s.VbpD             = X(39);
    s.VbpQ             = X(40);
    s.SupportClip      = X(41);
    s.RawModDemand     = X(42);
    s.ModHeadroom      = X(43);
    s.QsecApplied      = X(45);

    s.IrefUsedD        = X(63);
    s.IrefUsedQ        = X(64);
    s.ImeasUsedD       = X(65);
    s.ImeasUsedQ       = X(66);
    s.MatchRequest     = X(67);
    s.AlphaUsed        = X(68);
    s.HoldUsed         = X(69);
    s.AdapterValid     = X(70);
    s.ComponentClip    = X(71);
    s.RadiusClip       = X(72);
    s.RawModInternal   = X(73);
    s.ComponentMod     = X(74);
    s.PIStateClip      = X(75);
    s.CurrentErrorNorm = X(76);
    s.ExecResidualD    = X(77);
    s.ExecResidualQ    = X(78);

    s.AllowDampD       = X(79);
    s.AllowDampQ       = X(80);
    s.AllowSlowQ       = X(81);
    s.AllowLFQ         = X(82);
    s.RawDampD         = X(83);
    s.RawDampQ         = X(84);
    s.RawSlowQ         = X(85);
    s.RawLFQ           = X(86);
    s.SupportEnvelope  = X(87);
    s.VsupportCaptured = X(88);
    s.VcommandCaptured = X(89);
    s.SlowQAllocatedZ1 = X(90);
    s.SlowQClipZ1      = X(91);
    s.Kslow            = X(93);
    s.Kfast            = X(94);
    s.BaseScaleP       = X(95);
    s.BaseScaleQ       = X(96);
    s.GFLStageLocal    = X(97);
    s.VCommandLocal    = X(98);
    s.MasterFLocal     = X(99);
    s.PIntegral        = X(100);
    s.QIntegral        = X(101);
    s.ConnectMode      = X(102);
    s.RestoreDataValid = X(103);
    s.PrefApplied      = X(104);
    s.PmeasDiag        = X(105);
    s.PrefEffDiag      = X(106);
    s.Target           = X(107);
    s.ZeroQual         = X(108);
    s.PickupQual       = X(109);
    s.Severe           = X(110);
    s.DiagMode         = X(111);
    s.G27FileLimit     = X(112);
    s.G27FileStatus    = X(113);
    s.G30FileLimit     = X(114);
    s.G30FileStatus    = X(115);
    s.DiagFlagLocal    = X(116);
    s.FixedTargetLocal = X(117);
    s.G27FileID        = X(118);
    s.G30FileID        = X(119);

    % Derived physical/control quantities.
    s.RawBaseIrefMag       = hypot(s.RawP,s.RawQ);
    s.FinalIrefMag         = hypot(s.FinalId,s.FinalIq);
    s.ImeasMag             = hypot(s.IdMeas,s.IqMeas);
    s.IrefUsedMag          = hypot(s.IrefUsedD,s.IrefUsedQ);
    s.ImeasUsedMag         = hypot(s.ImeasUsedD,s.ImeasUsedQ);
    s.TotalSupportMag      = hypot(s.TotalSupportD,s.TotalSupportQ);
    s.AllowedSupportMaxAbs = max(abs([s.AllowDampD(:) s.AllowDampQ(:) s.AllowSlowQ(:) s.AllowLFQ(:)]),[],2).';
    s.RawSupportMaxAbs     = max(abs([s.RawDampD(:) s.RawDampQ(:) s.RawSlowQ(:) s.RawLFQ(:)]),[],2).';
    s.ExecResidualMag      = hypot(s.ExecResidualD,s.ExecResidualQ);
    s.VbpMag               = hypot(s.VbpD,s.VbpQ);
    s.PTrackingError       = s.PrefApplied-s.Pmeas;
    s.Vdev                 = s.Vpu-1.0;
    s.PLLdev               = s.PLL-50.0;

    evt=detect_a0_events(t,s,run);
    Tevt=event_table(evt);
    writetable(Tevt,fullfile(outDir,'03_G27_EVENT_TIMELINE.csv'));

    logf(fid,'G27 coverage: %.6f -> %.6f s (%d samples)',t(1),t(end),numel(t));
    logf(fid,'breaker close : %s',fmt_time(evt.breakerClose));
    logf(fid,'state5        : %s',fmt_time(evt.state5));
    logf(fid,'state6        : %s',fmt_time(evt.state6));
    logf(fid,'alpha open    : %s',fmt_time(evt.alphaOpen));
    logf(fid,'Pref nonzero  : %s',fmt_time(evt.prefNonzero));
    logf(fid,'A0 end        : %.6f s',t(end));

    phases=make_a0_phases(t,evt,C);
    Tphase=calculate_phase_metrics(t,s,phases);
    writetable(Tphase,fullfile(outDir,'04_G27_A0_PHASE_METRICS.csv'));

    Tw=calculate_a0_1s_windows(t,s,evt.state6,C.window_s);
    writetable(Tw,fullfile(outDir,'05_G27_A0_WINDOWS_1S.csv'));

    Tgrowth=calculate_growth_table(Tphase);
    writetable(Tgrowth,fullfile(outDir,'06_G27_A0_EARLY_LATE_GROWTH.csv'));

    Tspec=calculate_spectral_summary(t,s,phases);
    writetable(Tspec,fullfile(outDir,'07_G27_A0_SPECTRAL_SUMMARY.csv'));

    Tkey=key_samples_g27(t,s,evt,C.key_sample_s);
    writetable(Tkey,fullfile(outDir,'08_G27_A0_KEY_SAMPLES.csv'));

    Ta0local=a0_local_contract_table(t,s,evt,run);
    writetable(Ta0local,fullfile(outDir,'09_G27_A0_LOCAL_CONTRACT.csv'));

    localSummary=a0_local_summary(t,s,evt,Tphase,Tgrowth);

    compact=struct();
    compact.version=C.version;
    compact.manifest=run.manifest;
    compact.eventsG27=evt;
    compact.phases=phases;
    compact.G27=compact_g27(t,s,C.compact_dt_s);

    clear G27 X

    %% ====================================================================
    % 3. G29 -- S14/system chronology and zero-command contract
    % =====================================================================
    logf(fid,'');
    logf(fid,'--- G29 LOAD / CALCULATION ---');

    [G29,var29]=load_exact_family(selected.G29,C.expectedVar.G29,C.expectedRows.G29,'G29',fid,outDir);
    [G29,ta29]=sanitize_time_axis(G29,'G29');
    writetable(ta29,fullfile(outDir,'02B_G29_TIME_AXIS.csv'));

    t29=double(G29(1,:));
    Y=@(k) double(G29(k+1,:));

    g29=struct();
    g29.J1Applied       = Y(27);
    g29.Ppcc_kW         = Y(28);
    g29.Qpcc_kvar       = Y(29);
    g29.PCCFreq_Hz      = Y(30);
    g29.PCCVab_RMS_V    = Y(31);
    g29.Substate        = Y(47);
    g29.Coarse          = Y(48);
    g29.Elapsed         = Y(49);
    g29.RestoreStage    = Y(50);
    g29.CoordStage      = Y(51);
    g29.GFLStage        = Y(52);
    g29.PickupEnable    = Y(53);
    g29.OwnerRequest    = Y(54);
    g29.PickupTarget    = Y(55);
    g29.PickupApplied   = Y(56);
    g29.CoordinatorPref = Y(57);
    g29.FinalPCommand   = Y(58);
    g29.HandoverBeta    = Y(59);
    g29.ESS2Available   = Y(60);
    g29.CorrectionGain  = Y(61);
    g29.SecondaryEnable = Y(62);
    g29.CoordAuthority  = Y(63);
    g29.S14Active       = Y(64);
    g29.RestoreState    = Y(65);
    g29.Alpha           = Y(66);
    g29.FailCode        = Y(67);
    g29.ReleaseAllowed  = Y(68);
    g29.LegacyVoltageESS2 = Y(69);
    g29.DiagFlagSM      = Y(70);
    g29.FixedTargetSM   = Y(71);
    g29.G29FileLimit    = Y(72);
    g29.G29FileStatus   = Y(73);
    g29.G29FileID       = Y(74);

    Tg29trans=g29_transitions(t29,g29);
    writetable(Tg29trans,fullfile(outDir,'10_G29_TRANSITIONS.csv'));

    Tg29phase=g29_phase_metrics(t29,g29,phases);
    writetable(Tg29phase,fullfile(outDir,'11_G29_A0_PHASE_METRICS.csv'));

    Ta0system=a0_system_contract_table(t29,g29,evt);
    writetable(Ta0system,fullfile(outDir,'12_G29_A0_SYSTEM_CONTRACT.csv'));

    compact.G29=compact_g29(t29,g29,C.compact_dt_s);
    systemSummary=a0_system_summary(t29,g29,evt);

    clear G29 Y t29

    %% ====================================================================
    % 4. G30 -- ESS1 GFM generic evidence without inventing old labels
    % =====================================================================
    logf(fid,'');
    logf(fid,'--- G30 LOAD / CALCULATION ---');

    [G30,var30]=load_exact_family(selected.G30,C.expectedVar.G30,C.expectedRows.G30,'G30',fid,outDir);
    [G30,ta30]=sanitize_time_axis(G30,'G30');
    writetable(ta30,fullfile(outDir,'02C_G30_TIME_AXIS.csv'));

    t30=double(G30(1,:));
    g30Start=evt.state6;
    if ~isfinite(g30Start),g30Start=t30(1);end

    Tg30stats=g30_legacy_stats(t30,G30(2:129,:),g30Start);
    writetable(Tg30stats,fullfile(outDir,'13_G30_LEGACY_ROW_STATS_AFTER_STATE6.csv'));

    g30app=struct();
    g30app.FileLimit=double(G30(130,:));
    g30app.FileStatus=double(G30(131,:));
    g30app.FileID=double(G30(132,:));
    g30app.DiagFlag=double(G30(133,:));
    for k=1:12
        g30app.(sprintf('RestoreStatus_%d',k))=double(G30(133+k,:));
    end
    Tg30trans=g30_appended_transitions(t30,g30app);
    writetable(Tg30trans,fullfile(outDir,'14_G30_APPENDED_TRANSITIONS.csv'));

    compact.G30=compact_g30(t30,G30,C.compact_dt_s);
    compact.fileDiscovery=Tfiles;

    clear G30 t30

    %% ====================================================================
    % 5. Compact evidence / figures / top-level result
    % =====================================================================
    save(fullfile(outDir,'ANALYSIS_COMPACT.mat'),'compact','-v7');

    make_a0_figures(compact,outDir);

    result.status='CALCULATION_COMPLETE_A0_NO_ELECTRICAL_VERDICT';
    result.manifestPath=run.manifestPath;
    result.fileID=run.fileID;
    result.outputDirectory=outDir;
    result.targetClock_s=run.targetClock;
    result.state6_s=evt.state6;
    result.alphaOpen_s=evt.alphaOpen;
    result.prefNonzero_s=evt.prefNonzero;
    result.g27End_s=compact.G27.t(end);
    result.g29End_s=compact.G29.t(end);
    result.g30End_s=compact.G30.t(end);
    result.actualMatVariables=struct('G27',var27,'G29',var29,'G30',var30);
    result.localA0=localSummary;
    result.systemA0=systemSummary;
    result.note=['Descriptive A0 evidence only. No automatic electrical verdict. ' ...
        'Use A0 result first; only after analysis decide whether P0 is justified.'];

    json_write(fullfile(outDir,'RESULT.json'),result);
    save(fullfile(outDir,'RESULT.mat'),'result','-v7');

    % Human-readable compact summary.
    logf(fid,'');
    logf(fid,'--- A0 LOCAL DESCRIPTIVE SUMMARY ---');
    logf(fid,'Post-state6 duration = %.6f s',localSummary.postState6Duration_s);
    logf(fid,'Max |PrefApplied| after state6 = %.9g pu',localSummary.maxAbsPrefApplied);
    logf(fid,'Max raw/base current-ref magnitude after state6 = %.9g pu',localSummary.maxRawBaseIrefMag);
    logf(fid,'Max final current-ref magnitude after state6 = %.9g pu',localSummary.maxFinalIrefMag);
    logf(fid,'Max |P integral output| after state6 = %.9g',localSummary.maxAbsPIntegral);
    logf(fid,'Max |Q integral output| after state6 = %.9g',localSummary.maxAbsQIntegral);
    logf(fid,'Max allowed support after state6 = %.9g pu',localSummary.maxAllowedSupport);
    logf(fid,'CurrentLimit duty after state6 = %.9g',localSummary.currentLimitDuty);
    logf(fid,'ComponentClip duty after state6 = %.9g',localSummary.componentClipDuty);
    logf(fid,'Vpu early2s p2p / late2s p2p = %.9g / %.9g pu', ...
        localSummary.VpuEarly2P2P,localSummary.VpuLate2P2P);
    logf(fid,'Pmeas early2s p2p / late2s p2p = %.9g / %.9g pu', ...
        localSummary.PmeasEarly2P2P,localSummary.PmeasLate2P2P);
    logf(fid,'ImeasUsed early2s p2p / late2s p2p = %.9g / %.9g pu', ...
        localSummary.ImeasUsedEarly2P2P,localSummary.ImeasUsedLate2P2P);

    logf(fid,'');
    logf(fid,'--- A0 SYSTEM DESCRIPTIVE SUMMARY ---');
    logf(fid,'Max |FinalPCommand| after state6 = %.9g pu',systemSummary.maxAbsFinalPCommand);
    logf(fid,'Max |PickupApplied| after state6 = %.9g pu',systemSummary.maxAbsPickupApplied);
    logf(fid,'Max |OwnerRequest| after state6 = %.9g',systemSummary.maxAbsOwnerRequest);
    logf(fid,'Max |HandoverBeta| after state6 = %.9g',systemSummary.maxAbsHandoverBeta);
    logf(fid,'Max |CorrectionGain| after state6 = %.9g',systemSummary.maxAbsCorrectionGain);
    logf(fid,'Max |SecondaryEnable| after state6 = %.9g',systemSummary.maxAbsSecondaryEnable);
    logf(fid,'PCC V p2p after state6 = %.9g V',systemSummary.PCCV_p2p);
    logf(fid,'PCC f p2p after state6 = %.9g Hz',systemSummary.PCCF_p2p);

    uploadNote=sprintf([ ...
        'UPLOAD THIS A0 RESULT ZIP FOR ANALYSIS.\n' ...
        'Raw G27/G29/G30 MAT files normally do NOT need to be uploaded.\n' ...
        'A0 output: %s\n' ...
        'Status: %s\n'],outDir,result.status);
    text_write(fullfile(outDir,'README_UPLOAD.txt'),uploadNote);

    zipPath=[outDir '.zip'];
    zip(zipPath,{'*'},outDir);
    result.evidenceZip=zipPath;
    json_write(fullfile(outDir,'RESULT.json'),result);
    save(fullfile(outDir,'RESULT.mat'),'result','-v7');

    fprintf('\nA0 DirectMAT calculation complete.\n');
    fprintf('NO automatic electrical PASS/FAIL was declared.\n');
    fprintf('Output directory: %s\n',outDir);
    fprintf('Upload ZIP:       %s\n',zipPath);

catch ME
    try
        text_write(fullfile(outDir,'ERROR.txt'),getReport(ME,'extended','hyperlinks','off'));
    catch
        text_write(fullfile(outDir,'ERROR.txt'),ME.message);
    end
    fprintf(2,['\nA0 DirectMAT post-processing stopped. Existing raw MAT evidence is untouched.\n' ...
        'DO NOT rerun the RT-LAB trial because of this MATLAB error.\n%s\n'],ME.message);
    rethrow(ME);
end
end

% =========================================================================
% Configuration
% =========================================================================
function C=local_config()
C.version='K26_K50_ESS2_PQ_CAUSAL_A0_DIRECTMAT_R1_20260916';
C.defaultRunRoot='D:\E2RUN';
C.defaultModelRoot=['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
    'yanshou_V7\models\K26_K50_CLEAN_P1'];
C.expectedRunnerPrefix='ESS2_PQ_CAUSAL_A0_FORMAL_R2';
C.expectedRows.G27=120;
C.expectedRows.G29=75;
C.expectedRows.G30=145;
C.expectedVar.G27='rootdiag_ess2_data';
C.expectedVar.G29='d1_gfm_superpack_data';
C.expectedVar.G30='freqdiag_ess1_data';
C.window_s=1.0;
C.analysisAfterState6_s=4.0;
C.key_sample_s=0.25;
C.compact_dt_s=0.010;
end

% =========================================================================
% A0 manifest identity
% =========================================================================
function validate_a0_manifest(R)
J=R.manifest;
if isfield(J,'case') && ~strcmpi(char(J.case),'A0')
    error('A0MAT:WrongCase','Manifest case is %s, expected A0.',char(J.case));
end
if ~isfinite(R.firstState6)
    error('A0MAT:NoState6','Completed A0 manifest has no finite first_state6_s.');
end

if ~isfield(J,'diagnostic_config')
    error('A0MAT:NoDiagConfig','A0 R2 manifest lacks diagnostic_config.');
end
D=J.diagnostic_config;
must_num_field(D,'E2_DIAG_P_LOOP_ENABLE',0);
must_num_field(D,'E2_DIAG_Q_LOOP_ENABLE',0);
must_num_field(D,'E2_DIAG_DIRECT_IREF_ENABLE',1);
must_num_field(D,'E2_DIAG_DIRECT_ID_TARGET_PU',0);
must_num_field(D,'E2_DIAG_DIRECT_IQ_TARGET_PU',0);

if isfield(J,'frozen_legal_pickup_target_pu')
    x=double(J.frozen_legal_pickup_target_pu);
    if ~isfinite(x)||abs(x+0.005)>1e-9
        error('A0MAT:LegalTarget','Unexpected frozen legal pickup target: %.17g',x);
    end
end
end

function must_num_field(S,name,want)
if ~isfield(S,name)
    error('A0MAT:ManifestField','diagnostic_config missing %s.',name);
end
x=double(S.(name));
if ~isfinite(x)||abs(x-want)>1e-9
    error('A0MAT:ManifestValue','diagnostic_config.%s = %.17g, expected %.17g.',name,x,want);
end
end

% =========================================================================
% Resolve latest completed A0 run
% =========================================================================
function [guard,R]=resolve_run(inputPath,C)
guard=[];
if nargin<1,inputPath='';end
inputPath=char(inputPath);
outputAnchor='';
candidateManifests={};

if ~isempty(inputPath)
    if exist(inputPath,'dir')==7
        p=fullfile(inputPath,'manifest.json');
        if isfile(p),candidateManifests{end+1}=p;end %#ok<AGROW>
        dd=dir(fullfile(inputPath,'**','manifest.json'));
        for i=1:numel(dd)
            candidateManifests{end+1}=fullfile(dd(i).folder,dd(i).name); %#ok<AGROW>
        end
    elseif isfile(inputPath)
        [~,~,ext]=fileparts(inputPath);
        if strcmpi(ext,'.json')
            candidateManifests{end+1}=inputPath;
        elseif strcmpi(ext,'.zip')
            outputAnchor=fileparts(inputPath);
            if isempty(outputAnchor),outputAnchor=pwd;end
            tmp=tempname;mkdir(tmp);
            unzip(inputPath,tmp);
            guard=onCleanup(@()safe_rmdir(tmp));
            dd=dir(fullfile(tmp,'**','manifest.json'));
            for i=1:numel(dd)
                candidateManifests{end+1}=fullfile(dd(i).folder,dd(i).name); %#ok<AGROW>
            end
        else
            error('A0MAT:Input','Input must be A0 run directory, manifest.json, or result ZIP.');
        end
    else
        error('A0MAT:InputMissing','Input path does not exist: %s',inputPath);
    end
else
    roots={C.defaultRunRoot,pwd,fileparts(mfilename('fullpath'))};
    for r=1:numel(roots)
        if exist(roots{r},'dir')~=7,continue;end
        if strcmpi(canonical(roots{r}),canonical(C.defaultRunRoot))
            dd=dir(fullfile(roots{r},'pqcausal_a0_*','manifest.json'));
        else
            dd=dir(fullfile(roots{r},'**','manifest.json'));
        end
        for i=1:numel(dd)
            candidateManifests{end+1}=fullfile(dd(i).folder,dd(i).name); %#ok<AGROW>
        end
    end
end

candidateManifests=unique(candidateManifests,'stable');
valid=struct('path',{},'datenum',{},'J',{});
for i=1:numel(candidateManifests)
    p=candidateManifests{i};
    try
        J=jsondecode(fileread(p));
        ver=field_text(J,'version','');
        st=field_text(J,'status','');
        hasFiles=isfield(J,'expected_mat_files');
        caseOk=true;
        if isfield(J,'case'),caseOk=strcmpi(char(J.case),'A0');end
        if startsWith(ver,C.expectedRunnerPrefix) && startsWith(st,'CAPTURE_COMPLETE') && hasFiles && caseOk
            d=dir(p);
            q.path=p;q.datenum=d.datenum;q.J=J;
            valid(end+1)=q; %#ok<AGROW>
        end
    catch
    end
end

if isempty(valid)
    error('A0MAT:NoRun',['No completed %s manifest found. Expected e.g. ' ...
        'D:\E2RUN\pqcausal_a0_*\manifest.json.'],C.expectedRunnerPrefix);
end

[~,ix]=max([valid.datenum]);
sel=valid(ix);
J=sel.J;

R=struct();
R.manifestPath=sel.path;
R.runDir=fileparts(sel.path);
if isempty(outputAnchor),outputAnchor=R.runDir;end
R.outputAnchor=outputAnchor;
R.manifest=J;
R.status=field_text(J,'status','');
R.targetClock=field_num(J,'target_clock_s',NaN);
R.firstState6=field_num(J,'first_state6_s',NaN);
R.fileID=field_num(J,'file_id',NaN);
R.expected=struct();
R.expected.G27=char(J.expected_mat_files.G27);
R.expected.G29=char(J.expected_mat_files.G29);
R.expected.G30=char(J.expected_mat_files.G30);
end

function roots=build_search_roots(run,C)
roots={run.runDir,fileparts(run.runDir),pwd,fileparts(mfilename('fullpath')),C.defaultModelRoot};
roots=unique(roots,'stable');
keep=false(size(roots));
for i=1:numel(roots),keep(i)=exist(roots{i},'dir')==7;end
roots=roots(keep);
end

% =========================================================================
% Exact MAT discovery
% =========================================================================
function [selected,candidates]=find_exact_mat(exactName,roots)
candidates={};
for r=1:numel(roots)
    root=roots{r};
    p=fullfile(root,exactName);
    if isfile(p),candidates{end+1}=canonical(p);end %#ok<AGROW>
    dd=dir(fullfile(root,'**','OpREDHAWKtarget',exactName));
    for i=1:numel(dd)
        candidates{end+1}=canonical(fullfile(dd(i).folder,dd(i).name)); %#ok<AGROW>
    end
end
candidates=unique(candidates,'stable');

if isempty(candidates)
    for r=1:numel(roots)
        dd=dir(fullfile(roots{r},'**',exactName));
        for i=1:numel(dd)
            candidates{end+1}=canonical(fullfile(dd(i).folder,dd(i).name)); %#ok<AGROW>
        end
    end
    candidates=unique(candidates,'stable');
end

if isempty(candidates)
    error('A0MAT:MATMissing','Cannot find exact MAT file: %s',exactName);
end

score=zeros(numel(candidates),1);
dn=zeros(numel(candidates),1);
for i=1:numel(candidates)
    score(i)=contains(lower(strrep(candidates{i},'\','/')),'/opredhawktarget/');
    d=dir(candidates{i});dn(i)=d.datenum;
end
best=find(score==max(score));
[~,j]=max(dn(best));
selected=candidates{best(j)};
end

% =========================================================================
% MAT variable inventory + robust exact-family load
% =========================================================================
function [A,actualName]=load_exact_family(path,preferredName,expectedRows,label,fid,outDir)
W=whos('-file',path);
if isempty(W)
    error('A0MAT:EmptyMAT','%s MAT contains no variables: %s',label,path);
end

rows=cell(numel(W),8);
match=false(numel(W),1);
for i=1:numel(W)
    numericClass=is_numeric_class(W(i).class);
    twoD=(numel(W(i).size)<=2);
    expectedDim=any(W(i).size==expectedRows);
    match(i)=numericClass && twoD && expectedDim;
    rows(i,:)={W(i).name,W(i).class,mat2str(W(i).size),W(i).bytes, ...
        numericClass,twoD,expectedDim,strcmp(W(i).name,preferredName)};
end
Tin=cell2table(rows,'VariableNames', ...
    {'Name','Class','Size','Bytes','NumericClass','TwoDimensional','HasExpectedRowDimension','PreferredNameMatch'});
writetable(Tin,fullfile(outDir,sprintf('01B_%s_MAT_VARIABLES.csv',label)));

names={W.name};
k=find(strcmp(names,preferredName),1);
resolution='PREFERRED_NAME';

if isempty(k)
    cand=find(match);
    if numel(cand)==1
        k=cand(1);
        resolution='UNIQUE_NUMERIC_MATRIX_MATCHING_FROZEN_ROW_COUNT';
    elseif isempty(cand)
        detail=strjoin(arrayfun(@(q)sprintf('%s[%s] size=%s', ...
            W(q).name,W(q).class,mat2str(W(q).size)),1:numel(W),'UniformOutput',false),' | ');
        error('A0MAT:NoMatrixCandidate', ...
            '%s has no unique numeric 2-D matrix with dimension %d. Variables: %s', ...
            label,expectedRows,detail);
    else
        detail=strjoin(arrayfun(@(q)sprintf('%s size=%s',W(q).name,mat2str(W(q).size)), ...
            cand,'UniformOutput',false),' | ');
        error('A0MAT:AmbiguousMatrixCandidate', ...
            '%s has %d candidate matrices with dimension %d. No guessing. %s', ...
            label,numel(cand),expectedRows,detail);
    end
end

actualName=W(k).name;
logf(fid,'[%s] variable resolution: %s -> %s (%s)',label,preferredName,actualName,resolution);
logf(fid,'[%s] variable %s size=%s class=%s bytes=%g', ...
    label,actualName,mat2str(W(k).size),W(k).class,W(k).bytes);

S=load(path,actualName);
A=S.(actualName);
clear S;

if size(A,1)==expectedRows
    % expected orientation
elseif size(A,2)==expectedRows
    A=A.';
    logf(fid,'[%s] transposed to rows x samples.',label);
else
    error('A0MAT:RowCount','%s expected %d rows incl time; actual %dx%d.', ...
        label,expectedRows,size(A,1),size(A,2));
end

if ~isnumeric(A)||~isreal(A)
    error('A0MAT:DataType','%s matrix must be real numeric.',label);
end
end

function tf=is_numeric_class(cls)
tf=ismember(char(cls),{'double','single','int8','uint8','int16','uint16', ...
    'int32','uint32','int64','uint64','logical'});
end

% =========================================================================
% Time audit
% =========================================================================
function [A,T]=sanitize_time_axis(A,label)
t=double(A(1,:));
if any(~isfinite(t))
    error('A0MAT:TimeNaN','%s target-time row contains NaN/Inf.',label);
end
d=diff(t);
pos=d(d>0);
if isempty(pos)
    error('A0MAT:TimeAxis','%s has no increasing target time.',label);
end

med=median(pos);
nonpos=sum(d<=0);
large=sum(d>1.5*med);
short=sum(d<0.5*med & d>0);
maxgap=max(pos);
mingap=min(pos);

keep=[true d>0];
removed=sum(~keep);
if removed>0
    A=A(:,keep);
    t=A(1,:);
end

T=table({label},t(1),t(end),numel(t),med,mingap,maxgap,nonpos,large,short,removed, ...
    'VariableNames',{'Family','Start_s','End_s','Samples','MedianDt_s','MinPositiveDt_s', ...
    'MaxPositiveDt_s','NonPositiveIntervals','LargeGapIntervals','ShortIntervals','RemovedNonIncreasingSamples'});
end

% =========================================================================
% G27 A0 events / phases
% =========================================================================
function E=detect_a0_events(t,s,run)
E=struct();
E.breakerClose=first_time(t,s.Breaker>0.5);
E.state4=first_time(t,round(s.RestoreState)==4);
E.state5=first_time(t,round(s.RestoreState)==5);
E.state6=first_time(t,round(s.RestoreState)==6);
E.alphaOpen=first_time(t,s.RestoreAlpha>0.5);
E.prefNonzero=first_time(t,abs(s.PrefApplied)>5e-5);
E.rawBaseIrefNonzero=first_time(t,s.RawBaseIrefMag>5e-5);
E.finalIrefNonzero=first_time(t,s.FinalIrefMag>5e-5);
E.currentLimit=first_time(t,s.CurrentLimit>0.5);
E.componentClip=first_time(t,s.ComponentClip>0.5);
E.modHeadroomLoss=first_time(t,s.ModHeadroom<0.999999);
E.manifestState6=run.firstState6;
E.endTime=t(end);

% G27 state6 is authoritative for local alignment; manifest time is retained
% as an independent host-side cross-check.
if ~isfinite(E.state6)
    error('A0MAT:State6Missing','G27 contains no Restore state6.');
end
end

function T=event_table(E)
names=fieldnames(E);
rows=cell(numel(names),3);
for i=1:numel(names)
    rows(i,:)={names{i},E.(names{i}),'G27/manifest'};
end
T=cell2table(rows,'VariableNames',{'Event','Time_s','Source'});
end

function P=make_a0_phases(t,E,C)
t0=t(1);te=t(end);
s6=E.state6;
pre2=max(t0,s6-2.0);
postEnd=min(te,s6+C.analysisAfterState6_s);

P=[ ...
    phase('PRE_STATE6_2S',pre2,max(pre2,s6-1e-12)), ...
    phase('POST_STATE6_EARLY2',s6,min(postEnd,s6+2.0)), ...
    phase('POST_STATE6_LATE2',min(postEnd,s6+2.0),postEnd), ...
    phase('POST_STATE6_ALL',s6,postEnd) ...
    ];

if isfinite(E.state5)&&E.state5<s6
    P(end+1)=phase('CONNECTED_ZERO_ALPHA0',E.state5,s6); %#ok<AGROW>
end
end

function p=phase(name,t0,t1)
p=struct('name',name,'t0',t0,'t1',t1);
end

% =========================================================================
% Long-format phase metrics
% =========================================================================
function T=calculate_phase_metrics(t,s,phases)
names={ ...
    'Vpu','Vdev','PLL','PLLdev','Pmeas','Qmeas','PrefApplied','PrefEff','PTrackingError', ...
    'RawP','RawQ','RawBaseIrefMag','FinalIrefMag','IrefUsedMag','ImeasUsedMag', ...
    'IrefUsedD','IrefUsedQ','ImeasUsedD','ImeasUsedQ','CurrentErrorNorm','ExecResidualMag', ...
    'PIntegral','QIntegral','GammaP','GammaQ','BaseScaleP','BaseScaleQ', ...
    'RestoreAlpha','AlphaUsed','RestoreHold','HoldUsed','AdapterValid','GFLStageLocal', ...
    'CurrentLimit','ModIndex','RawModInternal','ModHeadroom','ComponentClip','RadiusClip','PIStateClip', ...
    'TotalSupportMag','AllowedSupportMaxAbs','RawSupportMaxAbs','SupportEnvelope', ...
    'VsupportRef','VCommandLocal','FailCode','Severe'};

rows=cell(0,12);
for pi=1:numel(phases)
    p=phases(pi);
    if ~isfinite(p.t0)||~isfinite(p.t1)||p.t1<=p.t0,continue;end
    idx=t>=p.t0 & t<=p.t1;
    if nnz(idx)<2,continue;end

    for ni=1:numel(names)
        nm=names{ni};
        x=s.(nm)(idx);
        tt=t(idx);
        m=metric_vector(tt,x);
        rows(end+1,:)={p.name,nm,p.t0,p.t1,nnz(idx),m.mean,m.min,m.max,m.p2p,m.std,m.rms,m.slope}; %#ok<AGROW>
    end
end

T=cell2table(rows,'VariableNames', ...
    {'Phase','Signal','Start_s','End_s','Samples','Mean','Min','Max','P2P','Std','RMS','Slope_per_s'});
end

function m=metric_vector(t,x)
m=struct('mean',NaN,'min',NaN,'max',NaN,'p2p',NaN,'std',NaN,'rms',NaN,'slope',NaN);
good=isfinite(t)&isfinite(x);
t=t(good);x=x(good);
if isempty(x),return;end
m.mean=mean(x);
m.min=min(x);
m.max=max(x);
m.p2p=m.max-m.min;
m.std=std(x,0);
m.rms=sqrt(mean(x.^2));
if numel(x)>=2 && max(t)>min(t)
    tc=t-mean(t);
    den=sum(tc.^2);
    if den>0,m.slope=sum(tc.*(x-mean(x)))/den;end
end
end

% =========================================================================
% Four 1-s windows after state6
% =========================================================================
function T=calculate_a0_1s_windows(t,s,state6,W)
if ~isfinite(state6)
    T=table();return
end

names={'Vpu','PLL','Pmeas','Qmeas','RawBaseIrefMag','FinalIrefMag', ...
    'IrefUsedMag','ImeasUsedMag','CurrentErrorNorm','PIntegral','QIntegral', ...
    'CurrentLimit','ModHeadroom','AllowedSupportMaxAbs','RawSupportMaxAbs','ComponentClip'};

rows=cell(0,12);
nwin=floor((t(end)-state6+1e-9)/W);
nwin=min(nwin,4);
for wi=1:nwin
    a=state6+(wi-1)*W;
    b=min(t(end),state6+wi*W);
    idx=t>=a & t<=b;
    if nnz(idx)<2,continue;end
    for ni=1:numel(names)
        nm=names{ni};
        m=metric_vector(t(idx),s.(nm)(idx));
        rows(end+1,:)={wi,a,b,nm,nnz(idx),m.mean,m.min,m.max,m.p2p,m.std,m.rms,m.slope}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames', ...
    {'Window','Start_s','End_s','Signal','Samples','Mean','Min','Max','P2P','Std','RMS','Slope_per_s'});
end

% =========================================================================
% Early-vs-late growth table
% =========================================================================
function T=calculate_growth_table(Tphase)
signals={'Vpu','PLL','Pmeas','Qmeas','ImeasUsedMag','CurrentErrorNorm','RawModInternal'};
rows=cell(0,9);
for i=1:numel(signals)
    nm=signals{i};
    a=Tphase(strcmp(Tphase.Phase,'POST_STATE6_EARLY2')&strcmp(Tphase.Signal,nm),:);
    b=Tphase(strcmp(Tphase.Phase,'POST_STATE6_LATE2')&strcmp(Tphase.Signal,nm),:);
    if isempty(a)||isempty(b),continue;end
    p2pr=safe_ratio(b.P2P(1),a.P2P(1));
    stdr=safe_ratio(b.Std(1),a.Std(1));
    rmsr=safe_ratio(b.RMS(1),a.RMS(1));
    rows(end+1,:)={nm,a.P2P(1),b.P2P(1),p2pr,a.Std(1),b.Std(1),stdr,rmsr,b.Slope_per_s(1)}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames', ...
    {'Signal','Early2_P2P','Late2_P2P','LateOverEarly_P2P', ...
    'Early2_Std','Late2_Std','LateOverEarly_Std','LateOverEarly_RMS','Late2_Slope_per_s'});
end

function r=safe_ratio(a,b)
if ~isfinite(a)||~isfinite(b)
    r=NaN;
elseif abs(b)<1e-12
    if abs(a)<1e-12,r=1;else,r=Inf;end
else
    r=a/b;
end
end

% =========================================================================
% Descriptive spectra
% =========================================================================
function T=calculate_spectral_summary(t,s,phases)
signals={'Vpu','Pmeas','Qmeas','PLL','ImeasUsedMag','CurrentErrorNorm','PIntegral'};
bands=[0.1 2;2 5;5 20;20 32];
rows=cell(0,13);

wanted={'CONNECTED_ZERO_ALPHA0','POST_STATE6_ALL'};
for pi=1:numel(phases)
    p=phases(pi);
    if ~any(strcmp(p.name,wanted)),continue;end
    idx=t>=p.t0&t<=p.t1;
    if nnz(idx)<64,continue;end

    for ni=1:numel(signals)
        nm=signals{ni};
        [tt,xx,dur,dtmed]=longest_contiguous(t(idx),s.(nm)(idx));
        if numel(xx)<64||dur<1.5,continue;end
        [dom,ef]=fft_energy(tt,xx,bands);
        rows(end+1,:)={p.name,nm,p.t0,p.t1,numel(xx),dur,dtmed,dom, ...
            ef(1),ef(2),ef(3),ef(4),sum(ef)}; %#ok<AGROW>
    end
end

T=cell2table(rows,'VariableNames', ...
    {'Phase','Signal','Start_s','End_s','Samples','ContiguousDuration_s','MedianDt_s','DominantHz', ...
    'EnergyFrac_0p1_2Hz','EnergyFrac_2_5Hz','EnergyFrac_5_20Hz','EnergyFrac_20_32Hz','EnergyFracSumBands'});
end

function [tt,xx,dur,dtmed]=longest_contiguous(t,x)
good=isfinite(t)&isfinite(x);
t=t(good);x=x(good);
if numel(t)<2
    tt=t;xx=x;dur=0;dtmed=NaN;return
end
d=diff(t);pos=d(d>0);
dtmed=median(pos);
cut=find(d>1.5*dtmed|d<=0);
edges=[1 cut+1;cut numel(t)].';
len=edges(:,2)-edges(:,1)+1;
[~,k]=max(len);
ix=edges(k,1):edges(k,2);
tt=t(ix);xx=x(ix);dur=tt(end)-tt(1);
end

function [dom,ef]=fft_energy(t,x,bands)
dom=NaN;ef=nan(1,size(bands,1));
if numel(x)<8,return;end
dt=median(diff(t));
if ~isfinite(dt)||dt<=0,return;end
fs=1/dt;
x=x(:)-mean(x);
N=numel(x);
if N<4,return;end

% Manual Hann window; no Signal Processing Toolbox dependency.
n=(0:N-1).';
w=0.5-0.5*cos(2*pi*n/(N-1));
y=x.*w;
Y=fft(y);
K=floor(N/2)+1;
f=(0:K-1).'*fs/N;
p=abs(Y(1:K)).^2;
sel=f>=0.1 & f<=min(40,fs/2);
if ~any(sel)||sum(p(sel))<=0,return;end
[~,k]=max(p.*sel);
dom=f(k);
den=sum(p(sel));
for b=1:size(bands,1)
    q=f>=bands(b,1)&f<bands(b,2);
    ef(b)=sum(p(q))/den;
end
end

% =========================================================================
% Key 0.25-s samples around state6
% =========================================================================
function T=key_samples_g27(t,s,E,step)
a=max(t(1),E.state6-1.0);
b=t(end);
targets=a:step:b;
rows=nan(numel(targets),18);
for i=1:numel(targets)
    [~,k]=min(abs(t-targets(i)));
    rows(i,:)=[t(k),s.RestoreState(k),s.RestoreAlpha(k),s.AlphaUsed(k),s.Breaker(k), ...
        s.Vpu(k),s.PLL(k),s.PrefApplied(k),s.Pmeas(k),s.Qmeas(k), ...
        s.RawP(k),s.RawQ(k),s.IrefUsedMag(k),s.ImeasUsedMag(k), ...
        s.PIntegral(k),s.QIntegral(k),s.CurrentLimit(k),s.ModHeadroom(k)];
end
T=array2table(rows,'VariableNames', ...
    {'Time_s','RestoreState','RestoreAlpha','AlphaUsed','Breaker','Vpu','PLL_Hz', ...
    'PrefApplied_pu','Pmeas_pu','Qmeas_pu','RawBaseId_pu','RawBaseIq_pu', ...
    'IrefUsedMag_pu','ImeasUsedMag_pu','PIntegral','QIntegral','CurrentLimit','ModHeadroom'});
end

% =========================================================================
% A0 local command/control contract
% =========================================================================
function T=a0_local_contract_table(t,s,E,R)
idx=t>=E.state6;
if ~any(idx),error('A0MAT:NoPostState6','No samples after state6.');end

rows={ ...
    'Manifest_PLoopEnable',double(R.manifest.diagnostic_config.E2_DIAG_P_LOOP_ENABLE),0,'host config'; ...
    'Manifest_QLoopEnable',double(R.manifest.diagnostic_config.E2_DIAG_Q_LOOP_ENABLE),0,'host config'; ...
    'Manifest_DirectEnable',double(R.manifest.diagnostic_config.E2_DIAG_DIRECT_IREF_ENABLE),1,'host config'; ...
    'Manifest_DirectIdTarget',double(R.manifest.diagnostic_config.E2_DIAG_DIRECT_ID_TARGET_PU),0,'host config'; ...
    'Manifest_DirectIqTarget',double(R.manifest.diagnostic_config.E2_DIAG_DIRECT_IQ_TARGET_PU),0,'host config'; ...
    'PostS6_MaxAbs_PrefApplied',max(abs(s.PrefApplied(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAbs_RawBaseId',max(abs(s.RawP(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAbs_RawBaseIq',max(abs(s.RawQ(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAbs_FinalIref',max(abs(s.FinalIrefMag(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAbs_PIntegral',max(abs(s.PIntegral(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAbs_QIntegral',max(abs(s.QIntegral(idx))),0,'G27 evidence'; ...
    'PostS6_MaxAllowedSupport',max(abs(s.AllowedSupportMaxAbs(idx))),0,'G27 evidence'; ...
    'PostS6_MinAlphaUsed',min(s.AlphaUsed(idx)),1,'G27 evidence'; ...
    'PostS6_MaxAlphaUsed',max(s.AlphaUsed(idx)),1,'G27 evidence'; ...
    'PostS6_MaxFailCode',max(abs(s.FailCode(idx))),0,'G27 evidence' ...
    };
T=cell2table(rows,'VariableNames',{'Item','Observed','NominalExpected','EvidenceSource'});
end

function S=a0_local_summary(t,s,E,Tphase,Tgrowth)
idx=t>=E.state6;
S=struct();
S.postState6Duration_s=t(end)-E.state6;
S.maxAbsPrefApplied=max(abs(s.PrefApplied(idx)));
S.maxRawBaseIrefMag=max(abs(s.RawBaseIrefMag(idx)));
S.maxFinalIrefMag=max(abs(s.FinalIrefMag(idx)));
S.maxIrefUsedMag=max(abs(s.IrefUsedMag(idx)));
S.maxImeasUsedMag=max(abs(s.ImeasUsedMag(idx)));
S.maxAbsPIntegral=max(abs(s.PIntegral(idx)));
S.maxAbsQIntegral=max(abs(s.QIntegral(idx)));
S.maxAllowedSupport=max(abs(s.AllowedSupportMaxAbs(idx)));
S.maxRawSupport=max(abs(s.RawSupportMaxAbs(idx)));
S.currentLimitDuty=mean(double(s.CurrentLimit(idx)>0.5));
S.componentClipDuty=mean(double(s.ComponentClip(idx)>0.5));
S.radiusClipDuty=mean(double(s.RadiusClip(idx)>0.5));
S.piStateClipDuty=mean(double(s.PIStateClip(idx)>0.5));
S.modHeadroomMin=min(s.ModHeadroom(idx));

S.VpuEarly2P2P=phase_value(Tphase,'POST_STATE6_EARLY2','Vpu','P2P');
S.VpuLate2P2P=phase_value(Tphase,'POST_STATE6_LATE2','Vpu','P2P');
S.PmeasEarly2P2P=phase_value(Tphase,'POST_STATE6_EARLY2','Pmeas','P2P');
S.PmeasLate2P2P=phase_value(Tphase,'POST_STATE6_LATE2','Pmeas','P2P');
S.ImeasUsedEarly2P2P=phase_value(Tphase,'POST_STATE6_EARLY2','ImeasUsedMag','P2P');
S.ImeasUsedLate2P2P=phase_value(Tphase,'POST_STATE6_LATE2','ImeasUsedMag','P2P');

S.VpuGrowthRatio=growth_value(Tgrowth,'Vpu','LateOverEarly_P2P');
S.PmeasGrowthRatio=growth_value(Tgrowth,'Pmeas','LateOverEarly_P2P');
S.ImeasUsedGrowthRatio=growth_value(Tgrowth,'ImeasUsedMag','LateOverEarly_P2P');
end

function v=phase_value(T,p,sig,col)
q=T(strcmp(T.Phase,p)&strcmp(T.Signal,sig),:);
if isempty(q),v=NaN;else,v=q.(col)(1);end
end

function v=growth_value(T,sig,col)
q=T(strcmp(T.Signal,sig),:);
if isempty(q),v=NaN;else,v=q.(col)(1);end
end

% =========================================================================
% G29
% =========================================================================
function T=g29_transitions(t,g)
names={'Substate','Coarse','RestoreStage','CoordStage','GFLStage','PickupEnable','OwnerRequest', ...
    'PickupApplied','FinalPCommand','HandoverBeta','ESS2Available','CorrectionGain','SecondaryEnable', ...
    'S14Active','RestoreState','Alpha','FailCode','ReleaseAllowed','DiagFlagSM','FixedTargetSM'};

rows=cell(0,5);
for ni=1:numel(names)
    nm=names{ni};x=g.(nm);
    dx=[true abs(diff(x))>1e-10];
    ix=find(dx);
    for j=1:numel(ix)
        k=ix(j);
        if k==1,old=NaN;else,old=x(k-1);end
        rows(end+1,:)={t(k),nm,old,x(k),k}; %#ok<AGROW>
    end
end

T=cell2table(rows,'VariableNames',{'Time_s','Signal','OldValue','NewValue','SampleIndex'});
if ~isempty(T),T=sortrows(T,'Time_s');end
end

function T=g29_phase_metrics(t,g,phases)
names={'J1Applied','Ppcc_kW','Qpcc_kvar','PCCFreq_Hz','PCCVab_RMS_V', ...
    'Substate','RestoreStage','CoordStage','GFLStage','PickupEnable','OwnerRequest', ...
    'PickupTarget','PickupApplied','CoordinatorPref','FinalPCommand','HandoverBeta', ...
    'ESS2Available','CorrectionGain','SecondaryEnable','RestoreState','Alpha','FailCode','ReleaseAllowed'};

rows=cell(0,8);
for pi=1:numel(phases)
    p=phases(pi);
    if ~isfinite(p.t0)||~isfinite(p.t1)||p.t1<=p.t0,continue;end
    idx=t>=p.t0&t<=p.t1;
    if nnz(idx)<2,continue;end
    for ni=1:numel(names)
        nm=names{ni};x=g.(nm)(idx);
        rows(end+1,:)={p.name,nm,p.t0,p.t1,mean(x,'omitnan'),min(x),max(x),max(x)-min(x)}; %#ok<AGROW>
    end
end

T=cell2table(rows,'VariableNames',{'Phase','Signal','Start_s','End_s','Mean','Min','Max','P2P'});
end

function T=a0_system_contract_table(t,g,E)
idx=t>=E.state6;
if ~any(idx),error('A0MAT:G29NoPostS6','G29 has no post-state6 samples.');end

rows={ ...
    'MaxAbs_FinalPCommand',max(abs(g.FinalPCommand(idx))),0; ...
    'MaxAbs_PickupApplied',max(abs(g.PickupApplied(idx))),0; ...
    'MaxAbs_CoordinatorPref',max(abs(g.CoordinatorPref(idx))),0; ...
    'MaxAbs_OwnerRequest',max(abs(g.OwnerRequest(idx))),0; ...
    'MaxAbs_HandoverBeta',max(abs(g.HandoverBeta(idx))),0; ...
    'MaxAbs_ESS2Available',max(abs(g.ESS2Available(idx))),0; ...
    'MaxAbs_CorrectionGain',max(abs(g.CorrectionGain(idx))),0; ...
    'MaxAbs_SecondaryEnable',max(abs(g.SecondaryEnable(idx))),0; ...
    'MaxAbs_FailCode',max(abs(g.FailCode(idx))),0; ...
    'Min_Substate',min(g.Substate(idx)),35; ...
    'Max_Substate',max(g.Substate(idx)),35 ...
    };
T=cell2table(rows,'VariableNames',{'Item','Observed','NominalExpected'});
end

function S=a0_system_summary(t,g,E)
idx=t>=E.state6;
S=struct();
S.maxAbsFinalPCommand=max(abs(g.FinalPCommand(idx)));
S.maxAbsPickupApplied=max(abs(g.PickupApplied(idx)));
S.maxAbsOwnerRequest=max(abs(g.OwnerRequest(idx)));
S.maxAbsHandoverBeta=max(abs(g.HandoverBeta(idx)));
S.maxAbsCorrectionGain=max(abs(g.CorrectionGain(idx)));
S.maxAbsSecondaryEnable=max(abs(g.SecondaryEnable(idx)));
S.PCCV_p2p=max(g.PCCVab_RMS_V(idx))-min(g.PCCVab_RMS_V(idx));
S.PCCF_p2p=max(g.PCCFreq_Hz(idx))-min(g.PCCFreq_Hz(idx));
S.PCCP_p2p=max(g.Ppcc_kW(idx))-min(g.Ppcc_kW(idx));
S.PCCQ_p2p=max(g.Qpcc_kvar(idx))-min(g.Qpcc_kvar(idx));
S.substateMin=min(g.Substate(idx));
S.substateMax=max(g.Substate(idx));
end

% =========================================================================
% G30 generic legacy stats
% =========================================================================
function T=g30_legacy_stats(t,A,startTime)
if ~isfinite(startTime),startTime=t(1);end
idx=t>=startTime;
if nnz(idx)<3,idx=true(size(t));end
tt=t(idx);

rows=cell(128,10);
for k=1:128
    x=double(A(k,idx));
    m=metric_vector(tt,x);
    [segT,segX,dur,dt]=longest_contiguous(tt,x);
    dom=NaN;
    if numel(segX)>=64&&dur>=1.5
        [dom,~]=fft_energy(segT,segX,[0.1 2;2 5;5 20;20 32]);
    end
    rows(k,:)={k,sprintf('LegacyG30_%03d',k),m.mean,m.min,m.max,m.p2p,m.std,m.slope,dom,dt};
end

T=cell2table(rows,'VariableNames', ...
    {'Channel','Label','Mean','Min','Max','P2P','Std','Slope_per_s','DominantHz_0p1_40','MedianDt_s'});
end

function T=g30_appended_transitions(t,g)
names=fieldnames(g);
rows=cell(0,5);
for ni=1:numel(names)
    nm=names{ni};x=g.(nm);
    dx=[true abs(diff(x))>1e-10];
    ix=find(dx);
    if numel(ix)>500,ix=ix(1:500);end
    for j=1:numel(ix)
        k=ix(j);
        if k==1,old=NaN;else,old=x(k-1);end
        rows(end+1,:)={t(k),nm,old,x(k),k}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'Time_s','Signal','OldValue','NewValue','SampleIndex'});
if ~isempty(T),T=sortrows(T,'Time_s');end
end

% =========================================================================
% Compact data
% =========================================================================
function C=compact_g27(t,s,dtWant)
idx=downsample_indices(t,dtWant);
C=struct();C.t=t(idx);
fields={'Vpu','PLL','RestoreState','RestoreAlpha','AlphaUsed','Breaker', ...
    'PrefApplied','PrefEff','Target','Pmeas','Qmeas','RawP','RawQ','RawBaseIrefMag', ...
    'FinalIrefMag','IrefUsedD','IrefUsedQ','ImeasUsedD','ImeasUsedQ','IrefUsedMag','ImeasUsedMag', ...
    'PIntegral','QIntegral','GammaP','GammaQ','BaseScaleP','BaseScaleQ', ...
    'CurrentLimit','ModIndex','RawModInternal','ModHeadroom','ComponentClip','RadiusClip','PIStateClip', ...
    'CurrentErrorNorm','ExecResidualMag','TotalSupportMag','AllowedSupportMaxAbs','RawSupportMaxAbs', ...
    'SupportEnvelope','GFLStageLocal','FailCode','Severe'};
for i=1:numel(fields),C.(fields{i})=s.(fields{i})(idx);end
end

function C=compact_g29(t,g,dtWant)
idx=downsample_indices(t,dtWant);
C=struct();C.t=t(idx);
fn=fieldnames(g);
for i=1:numel(fn),C.(fn{i})=g.(fn{i})(idx);end
end

function C=compact_g30(t,A,dtWant)
idx=downsample_indices(t,dtWant);
C=struct();
C.t=t(idx);
C.Legacy128=A(2:129,idx);
C.G30FileLimit=A(130,idx);
C.G30FileStatus=A(131,idx);
C.G30FileID=A(132,idx);
C.DiagFlagLocal=A(133,idx);
C.RestoreStatus12=A(134:145,idx);
end

function idx=downsample_indices(t,dtWant)
if numel(t)<2,idx=1:numel(t);return;end
dt=median(diff(t));
stride=max(1,round(dtWant/dt));
idx=1:stride:numel(t);
if idx(end)~=numel(t),idx(end+1)=numel(t);end
end

% =========================================================================
% Figures
% =========================================================================
function make_a0_figures(C,outDir)
try
    t=C.G27.t;
    s6=C.eventsG27.state6;

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(t,C.G27.Vpu);grid on;xline(s6,'--');ylabel('Vpu');title('A0 ESS2 voltage');
    subplot(3,1,2);plot(t,C.G27.Pmeas);grid on;xline(s6,'--');ylabel('P / pu');title('A0 ESS2 measured active power');
    subplot(3,1,3);plot(t,C.G27.PLL);grid on;xline(s6,'--');ylabel('Hz');xlabel('t / s');title('A0 ESS2 PLL frequency');
    exportgraphics(f,fullfile(outDir,'FIG_01_A0_V_P_F.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(t,C.G27.RawP,t,C.G27.RawQ);grid on;xline(s6,'--');
    ylabel('pu');legend('Raw base Id','Raw base Iq','Location','best');title('A0 base current reference');
    subplot(3,1,2);plot(t,C.G27.IrefUsedMag,t,C.G27.ImeasUsedMag);grid on;xline(s6,'--');
    ylabel('pu');legend('|Iref used|','|Imeas used|','Location','best');title('A0 current execution');
    subplot(3,1,3);plot(t,C.G27.PIntegral,t,C.G27.QIntegral);grid on;xline(s6,'--');
    ylabel('PI output');xlabel('t / s');legend('P integral','Q integral','Location','best');title('Power-loop integral outputs');
    exportgraphics(f,fullfile(outDir,'FIG_02_A0_CURRENT_AND_PI.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(t,C.G27.AllowedSupportMaxAbs,t,C.G27.RawSupportMaxAbs);grid on;xline(s6,'--');
    ylabel('pu');legend('Allowed support','Raw/unselected support','Location','best');title('Support isolation');
    subplot(3,1,2);plot(t,C.G27.CurrentLimit,t,C.G27.ComponentClip,t,C.G27.RadiusClip);grid on;xline(s6,'--');
    legend('CurrentLimit','ComponentClip','RadiusClip','Location','best');title('Execution limits');
    subplot(3,1,3);plot(t,C.G27.ModHeadroom,t,C.G27.CurrentErrorNorm);grid on;xline(s6,'--');
    xlabel('t / s');legend('ModHeadroom','CurrentErrorNorm','Location','best');title('Headroom / current error');
    exportgraphics(f,fullfile(outDir,'FIG_03_A0_SUPPORT_LIMITS.png'),'Resolution',160);close(f);

    if isfield(C,'G29')&&isfield(C.G29,'PCCVab_RMS_V')
        t2=C.G29.t;
        f=figure('Visible','off','Color','w');
        subplot(4,1,1);plot(t2,C.G29.PCCVab_RMS_V);grid on;xline(s6,'--');ylabel('V RMS');title('PCC voltage');
        subplot(4,1,2);plot(t2,C.G29.PCCFreq_Hz);grid on;xline(s6,'--');ylabel('Hz');title('PCC frequency');
        subplot(4,1,3);plot(t2,C.G29.Ppcc_kW,t2,C.G29.Qpcc_kvar);grid on;xline(s6,'--');
        ylabel('kW/kvar');legend('P','Q','Location','best');
        subplot(4,1,4);plot(t2,C.G29.Substate,t2,C.G29.FinalPCommand);grid on;xline(s6,'--');
        xlabel('t / s');legend('S14 substate','Final P command','Location','best');
        exportgraphics(f,fullfile(outDir,'FIG_04_A0_SYSTEM.png'),'Resolution',160);close(f);
    end
catch ME
    text_write(fullfile(outDir,'FIGURE_WARNING.txt'),getReport(ME,'basic','hyperlinks','off'));
end
end

% =========================================================================
% Helpers
% =========================================================================
function v=first_time(t,mask)
k=find(mask,1,'first');
if isempty(k),v=NaN;else,v=t(k);end
end

function s=fmt_time(x)
if isfinite(x),s=sprintf('%.6f s',x);else,s='NOT FOUND';end
end

function p=canonical(p)
try,p=char(java.io.File(p).getCanonicalPath());catch,p=char(p);end
end

function safe_rmdir(p)
try
    if exist(p,'dir')==7,rmdir(p,'s');end
catch
end
end

function s=nonce4()
a='0123456789abcdef';s=a(randi(numel(a),1,4));
end

function x=field_text(S,name,default)
if isfield(S,name)
    try,x=char(S.(name));catch,x=default;end
else
    x=default;
end
end

function x=field_num(S,name,default)
if isfield(S,name)
    try,x=double(S.(name));catch,x=default;end
else
    x=default;
end
end

function logf(fid,varargin)
s=sprintf(varargin{:});
fprintf('%s\n',s);
fprintf(fid,'%s\n',s);
end

function text_write(path,s)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('A0MAT:Write','Cannot create %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',s);
end

function json_write(path,S)
text_write(path,jsonencode(S,'PrettyPrint',true));
end

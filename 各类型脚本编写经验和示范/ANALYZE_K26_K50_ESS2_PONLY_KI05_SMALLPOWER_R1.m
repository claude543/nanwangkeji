function result = ANALYZE_K26_K50_ESS2_PONLY_KI05_SMALLPOWER_R1(searchRoot)
% ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 P-loop Ki=0.5 fixed-small-power DirectMAT calculator.
%
% PURPOSE
%   MATLAB does the heavy numerical work directly on the current RT-LAB MAT
%   files.  It does NOT connect to RT-LAB, modify the model, or declare an
%   electrical PASS/FAIL.
%
% CURRENT FORMAL RUN
%   Runner family : ESS2_PONLY_KI05_SMALLPOWER_FORMAL_R1
%   Required MAT  :
%       G27 rootdiag_ess2_data   -> 119 signals + target time = 120 rows
%       G29 d1_gfm_superpack_data -> 74 signals + target time = 75 rows
%       G30 freqdiag_ess1_data   -> 144 signals + target time = 145 rows
%
% NO MANUAL MAT COPYING IS REQUIRED.
%
% RECOMMENDED USE
%   result = ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT;
%
% Optional:
%   result = ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT( ...
%       'D:\E2RUN\observe_20260916_145646_729847');
%
% The script:
%   1) automatically finds the latest completed smallpower_ki05_* manifest;
%   2) reads the exact MAT file names/file-id from that manifest;
%   3) recursively finds those exact MATs in the current model/task
%      OpREDHAWKtarget directories;
%   4) inspects whos('-file',...) first. If the legacy OpWrite variable
%      name is absent, it accepts ONLY a unique numeric matrix whose
%      dimensions match the frozen current recorder width;
%   5) reads G27/G29/G30 one family at a time to avoid holding all large
%      MAT arrays in memory simultaneously;
%   6) uses the recorded target-time row instead of assuming ideal sampling;
%   7) calculates event timing, phase metrics, 2-s windows, spectral-energy
%      summaries, support isolation, PI/current execution evidence, G29 state
%      transitions and generic G30 legacy-row statistics;
%   8) writes a compact result ZIP.  Upload THAT ZIP for analysis; the raw
%      100~500 MB MAT files normally do not need to be uploaded.
%
% IMPORTANT EVIDENCE RULES
%   - no interpolation is used to manufacture event samples;
%   - missing/gapped time is audited explicitly;
%   - spectral peaks are descriptive FFT evidence, not eigenvalues/modes;
%   - G30 legacy channels 1~128 are not silently renamed without a frozen
%     channel map; they are exported as LegacyG30_001...128.
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

[tempGuard, run] = resolve_run(searchRoot,C); %#ok<NASGU>
fprintf('\n====================================================================\n');
fprintf('ESS2 P-loop Ki=0.5 small-power DirectMAT R1\n');
fprintf('Manifest : %s\n',run.manifestPath);
fprintf('Run dir  : %s\n',run.runDir);
fprintf('File ID  : %s\n',num2str(run.fileID,'%.0f'));
fprintf('====================================================================\n');

validate_smallpower_manifest(run);

outDir = fullfile(run.outputAnchor,['MATLAB_SMALLPOWER_KI05_DIRECTMAT_' stamp]);
if exist(outDir,'dir') == 7
    outDir = [outDir '_' nonce4()];
end
mkdir(outDir);
result.outputDirectory = outDir;

summaryPath = fullfile(outDir,'00_SUMMARY.txt');
fid = fopen(summaryPath,'w','n','UTF-8');
if fid < 0
    error('DIRECTMAT:SummaryCreate','Cannot create %s',summaryPath);
end
fidGuard = onCleanup(@()fclose(fid)); %#ok<NASGU>

try
    logf(fid,'K26_K50 / ESS2 P-loop Ki=0.5 fixed-small-power DirectMAT R1');
    logf(fid,'Version: %s',C.version);
    logf(fid,'Manifest: %s',run.manifestPath);
    logf(fid,'Manifest status: %s',run.status);
    logf(fid,'Manifest target clock: %.9f s',run.targetClock);
    logf(fid,'Manifest first state6: %.9f s',run.firstState6);
    logf(fid,'Manifest file ID: %.0f',run.fileID);
    logf(fid,'Controller contract: P-loop ON, Q-loop OFF, Direct OFF, Kp=0.06, Ki=0.5.');
    logf(fid,'Functional contract: real Pref 0 -> -0.005 pu, then fixed platform.');
    logf(fid,'MATLAB only computes evidence. No automatic electrical PASS/FAIL.');

    %% --------------------------------------------------------------------
    % 1. Find exact MAT files from manifest
    % ---------------------------------------------------------------------
    roots = build_search_roots(run,C);
    fileRows = cell(0,8);
    selected = struct();

    groups = {'G27','G29','G30'};
    for gi = 1:numel(groups)
        g = groups{gi};
        exactName = run.expected.(g);
        [selPath,candidates] = find_exact_mat(exactName,roots);
        selected.(g) = selPath;

        d = dir(selPath);
        inOp = contains(lower(strrep(selPath,'\','/')),'/opredhawktarget/');
        fileRows(end+1,:) = {g,exactName,selPath,d.bytes,datestr(d.datenum,31), ...
            numel(candidates),inOp,'SELECTED'}; %#ok<AGROW>

        logf(fid,'[%s] %s',g,selPath);
        if numel(candidates) > 1
            logf(fid,'[%s NOTE] exact filename had %d copies; newest OpREDHAWKtarget candidate selected.', ...
                g,numel(candidates));
        end
    end
    Tfiles = cell2table(fileRows,'VariableNames', ...
        {'Group','ExpectedFile','SelectedPath','Bytes','Modified','CandidateCount','InOpREDHAWKtarget','Status'});
    writetable(Tfiles,fullfile(outDir,'01_FILE_DISCOVERY.csv'));

    %% --------------------------------------------------------------------
    % 2. G27: ESS2 detailed causal data
    % ---------------------------------------------------------------------
    logf(fid,'');
    logf(fid,'--- G27 LOAD / CALCULATION ---');
    [G27,var27] = load_exact_family(selected.G27,'rootdiag_ess2_data',120,'G27',fid,outDir);
    [G27,ta27] = sanitize_time_axis(G27,'G27');
    writetable(ta27,fullfile(outDir,'02A_G27_TIME_AXIS.csv'));

    t = G27(1,:);
    X = @(k) G27(k+1,:); % channel k; row1 is target time

    % Key current G27 channels (frozen by the current BASETEST recorder).
    s = struct();
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

    s.FinalIrefMag     = hypot(s.FinalId,s.FinalIq);
    s.ImeasMag         = hypot(s.IdMeas,s.IqMeas);
    s.IrefUsedMag      = hypot(s.IrefUsedD,s.IrefUsedQ);
    s.ImeasUsedMag     = hypot(s.ImeasUsedD,s.ImeasUsedQ);
    s.TotalSupportMag  = hypot(s.TotalSupportD,s.TotalSupportQ);
    s.AllowedSupportMaxAbs = max(abs([s.AllowDampD(:) s.AllowDampQ(:) s.AllowSlowQ(:) s.AllowLFQ(:)]),[],2).';
    s.RawSupportMaxAbs = max(abs([s.RawDampD(:) s.RawDampQ(:) s.RawSlowQ(:) s.RawLFQ(:)]),[],2).';
    s.ExecResidualMag  = hypot(s.ExecResidualD,s.ExecResidualQ);
    s.VbpMag           = hypot(s.VbpD,s.VbpQ);
    s.PTrackingError    = s.Pmeas-s.PrefApplied;
    s.PProportional     = 0.06*(s.PrefApplied-s.Pmeas);
    s.PPIReconPred      = s.PProportional+s.PIntegral;
    s.PPIReconResidual  = s.RawP-s.PPIReconPred;

    evt = detect_g27_events(t,s,run);
    Tevt27 = struct2eventtable(evt,'G27');
    writetable(Tevt27,fullfile(outDir,'03A_G27_EVENT_TIMELINE.csv'));

    logf(fid,'G27 coverage: %.6f -> %.6f s (%d samples)',t(1),t(end),numel(t));
    logf(fid,'G27 breaker close: %s',fmt_time(evt.breakerClose));
    logf(fid,'G27 state5:       %s',fmt_time(evt.state5));
    logf(fid,'G27 state6:       %s',fmt_time(evt.state6));
    logf(fid,'G27 alpha=1:      %s',fmt_time(evt.alphaOpen));
    logf(fid,'G27 Pref starts:  %s',fmt_time(evt.prefStart));
    logf(fid,'G27 Pref target reached: %s',fmt_time(evt.targetReach));

    % Phases are descriptive time partitions, not PASS gates.
    phases = make_phases(t,evt);
    Tphase = calculate_phase_metrics(t,s,phases);
    writetable(Tphase,fullfile(outDir,'04_G27_PHASE_METRICS.csv'));

    Tw = calculate_2s_windows(t,s,evt.state6,2.0);
    writetable(Tw,fullfile(outDir,'05_G27_WINDOWS_2S.csv'));

    Tspec = calculate_spectral_summary(t,s,phases);
    writetable(Tspec,fullfile(outDir,'06_G27_SPECTRAL_SUMMARY.csv'));

    Tkey = key_samples_g27(t,s,evt,0.5);
    writetable(Tkey,fullfile(outDir,'09_G27_KEY_SAMPLES.csv'));

    Tsteady = platform_steady_windows(t,s,evt);
    writetable(Tsteady,fullfile(outDir,'10_G27_PLATFORM_STEADY_WINDOWS.csv'));

    Ttrack = tracking_accuracy_table(t,s,evt);
    writetable(Ttrack,fullfile(outDir,'11_G27_TRACKING_ACCURACY.csv'));

    Tgrowth = platform_growth_table(t,s,evt);
    writetable(Tgrowth,fullfile(outDir,'12_G27_PLATFORM_GROWTH.csv'));

    TzeroGrowth = zero_command_growth_table(t,s,evt);
    writetable(TzeroGrowth,fullfile(outDir,'15_G27_ZERO_COMMAND_GROWTH.csv'));

    Tcontrib = controller_contribution_table(t,s,evt);
    writetable(Tcontrib,fullfile(outDir,'16_G27_P_CONTROLLER_CONTRIBUTIONS.csv'));

    TlocalContract = smallpower_local_contract_table(t,s,evt,run);
    writetable(TlocalContract,fullfile(outDir,'13_G27_KI05_LOCAL_CONTRACT.csv'));

    localSummary = smallpower_local_summary(t,s,evt,Tsteady,Ttrack,Tgrowth,TzeroGrowth,Tcontrib);

    % Save compact G27 before clearing the large raw matrix.
    compact = struct();
    compact.version = C.version;
    compact.manifest = run.manifest;
    compact.G27 = compact_g27(t,s,0.010);
    compact.eventsG27 = evt;
    compact.phases = phases;
    clear G27 X t s

    %% --------------------------------------------------------------------
    % 3. G29: S14 / command / ownership chronology
    % ---------------------------------------------------------------------
    logf(fid,'');
    logf(fid,'--- G29 LOAD / CALCULATION ---');
    [G29,var29] = load_exact_family(selected.G29,'d1_gfm_superpack_data',75,'G29',fid,outDir);
    [G29,ta29] = sanitize_time_axis(G29,'G29');
    writetable(ta29,fullfile(outDir,'02B_G29_TIME_AXIS.csv'));

    t29 = G29(1,:);
    Y = @(k) G29(k+1,:);

    g29 = struct();
    % Frozen legacy G29 system-level rows that were already proven before BASETEST.
    g29.J1Applied      = Y(27);
    g29.Ppcc_kW        = Y(28);
    g29.Qpcc_kvar      = Y(29);
    g29.PCCFreq_Hz     = Y(30);
    g29.PCCVab_RMS_V   = Y(31);
    g29.Substate       = Y(47);
    g29.Coarse         = Y(48);
    g29.Elapsed        = Y(49);
    g29.RestoreStage   = Y(50);
    g29.CoordStage     = Y(51);
    g29.GFLStage       = Y(52);
    g29.PickupEnable   = Y(53);
    g29.OwnerRequest   = Y(54);
    g29.PickupTarget   = Y(55);
    g29.PickupApplied  = Y(56);
    g29.CoordinatorPref= Y(57);
    g29.FinalPCommand  = Y(58);
    g29.HandoverBeta   = Y(59);
    g29.ESS2Available  = Y(60);
    g29.CorrectionGain = Y(61);
    g29.SecondaryEnable= Y(62);
    g29.CoordAuthority = Y(63);
    g29.S14Active      = Y(64);
    g29.RestoreState   = Y(65);
    g29.Alpha          = Y(66);
    g29.FailCode       = Y(67);
    g29.ReleaseAllowed = Y(68);
    g29.LegacyVoltageESS2 = Y(69);
    g29.DiagFlagSM     = Y(70);
    g29.FixedTargetSM  = Y(71);
    g29.G29FileLimit   = Y(72);
    g29.G29FileStatus  = Y(73);
    g29.G29FileID      = Y(74);

    Tg29trans = g29_transitions(t29,g29);
    writetable(Tg29trans,fullfile(outDir,'07_G29_TRANSITIONS.csv'));

    Tg29phase = g29_phase_metrics(t29,g29,phases);
    writetable(Tg29phase,fullfile(outDir,'07B_G29_PHASE_METRICS.csv'));

    TsysContract = smallpower_system_contract_table(t29,g29,evt);
    writetable(TsysContract,fullfile(outDir,'14_G29_SMALLPOWER_SYSTEM_CONTRACT.csv'));
    systemSummary = smallpower_system_summary(t29,g29,evt);

    compact.G29 = compact_g29(t29,g29,0.010);
    clear G29 Y t29 g29

    %% --------------------------------------------------------------------
    % 4. G30: ESS1 GFM full family; legacy 1~128 not guessed
    % ---------------------------------------------------------------------
    logf(fid,'');
    logf(fid,'--- G30 LOAD / CALCULATION ---');
    [G30,var30] = load_exact_family(selected.G30,'freqdiag_ess1_data',145,'G30',fid,outDir);
    [G30,ta30] = sanitize_time_axis(G30,'G30');
    writetable(ta30,fullfile(outDir,'02C_G30_TIME_AXIS.csv'));

    t30 = G30(1,:);
    platformStart = evt.targetReach;
    if ~isfinite(platformStart)
        platformStart = evt.prefStart;
    end
    if ~isfinite(platformStart)
        platformStart = evt.state6;
    end

    Tg30stats = g30_legacy_stats(t30,G30(2:129,:),platformStart);
    writetable(Tg30stats,fullfile(outDir,'08_G30_LEGACY_ROW_STATS.csv'));

    % Appended G30 channels 129~144 are known.
    g30app = struct();
    g30app.FileLimit = G30(130,:);
    g30app.FileStatus= G30(131,:);
    g30app.FileID    = G30(132,:);
    g30app.DiagFlag  = G30(133,:);
    for k=1:12
        g30app.(sprintf('RestoreStatus_%d',k)) = G30(133+k,:);
    end
    Tg30trans = g30_appended_transitions(t30,g30app);
    writetable(Tg30trans,fullfile(outDir,'08B_G30_APPENDED_TRANSITIONS.csv'));

    compact.G30 = compact_g30(t30,G30,0.010);
    clear G30 t30

    %% --------------------------------------------------------------------
    % 5. Cross-family compact summaries and figures
    % ---------------------------------------------------------------------
    compact.fileDiscovery = Tfiles;
    save(fullfile(outDir,'ANALYSIS_COMPACT.mat'),'compact','-v7');

    make_figures(compact,outDir);

    %% --------------------------------------------------------------------
    % 6. High-level numerical summary (descriptive only)
    % ---------------------------------------------------------------------
    P = platform_summary(Tphase,'FIXED_PLATFORM');
    [gainCompare,ki0Path,ki2Path] = compare_ki_cases(C,P,localSummary,outDir,fid);
    result.status = 'CALCULATION_COMPLETE_SMALLPOWER_KI05_NO_ELECTRICAL_VERDICT';
    result.manifestPath = run.manifestPath;
    result.fileID = run.fileID;
    result.outputDirectory = outDir;
    result.targetClock_s = run.targetClock;
    result.firstState6_s = evt.state6;
    result.prefStart_s = evt.prefStart;
    result.targetReach_s = evt.targetReach;
    result.g27End_s = compact.G27.t(end);
    result.g29End_s = compact.G29.t(end);
    result.g30End_s = compact.G30.t(end);
    result.platform = P;
    result.localSummary = localSummary;
    result.systemSummary = systemSummary;
    result.kiComparison = gainCompare;
    result.ki0ComparisonSource = ki0Path;
    result.ki2ComparisonSource = ki2Path;
    result.actualMatVariables = struct('G27',var27,'G29',var29,'G30',var30);
    result.note = ['P-loop Ki=0.5 small-power numerical evidence only. Upload the compact ZIP; ' ...
        'do not rerun the physical test because of a post-processing error.'];

    json_write(fullfile(outDir,'RESULT.json'),result);
    save(fullfile(outDir,'RESULT.mat'),'result','-v7');

    uploadNote = sprintf([ ...
        'UPLOAD THIS RESULT ZIP FOR ANALYSIS.\n' ...
        'Raw G27/G29/G30 MAT files normally do NOT need to be uploaded.\n' ...
        'DirectMAT output: %s\n' ...
        'Status: %s\n'],outDir,result.status);
    text_write(fullfile(outDir,'README_UPLOAD.txt'),uploadNote);

    logf(fid,'');
    logf(fid,'--- DESCRIPTIVE PLATFORM SNAPSHOT ---');
    if isfield(P,'Vpu_mean')
        logf(fid,'Platform Vpu mean/min/max/p2p = %.6g / %.6g / %.6g / %.6g', ...
            P.Vpu_mean,P.Vpu_min,P.Vpu_max,P.Vpu_p2p);
        logf(fid,'Platform Pmeas mean/min/max = %.6g / %.6g / %.6g pu', ...
            P.Pmeas_mean,P.Pmeas_min,P.Pmeas_max);
        logf(fid,'Platform PrefApplied mean = %.6g pu',P.PrefApplied_mean);
        logf(fid,'Platform P tracking RMS error = %.6g pu',P.PTrackingError_rms);
        if isfield(localSummary,'last10_PmeasMean')
            logf(fid,'Last10s Pmeas / Pref / mean error = %.6g / %.6g / %.6g pu', ...
                localSummary.last10_PmeasMean,localSummary.last10_PrefMean,localSummary.last10_ErrorMean);
            logf(fid,'Last10s |mean error| / |target| = %.3f %%',100*localSummary.last10_RelAbsMean);
            logf(fid,'Last10s duty within +/-2/5/10%% target = %.4f / %.4f / %.4f', ...
                localSummary.last10_Within2pctDuty,localSummary.last10_Within5pctDuty,localSummary.last10_Within10pctDuty);
            logf(fid,'Platform first5->last5 Vpu/Pmeas/PLL/Imeas P2P ratios = %.4g / %.4g / %.4g / %.4g', ...
                localSummary.growth_Vpu,localSummary.growth_Pmeas,localSummary.growth_PLL,localSummary.growth_Imeas);
            logf(fid,'Post-state6 max |PIntegral| = %.6g; max |PI reconstruction residual| = %.6g', ...
                localSummary.maxAbsPIntegral,localSummary.maxAbsPPIReconResidual);
            logf(fid,'Zero-command Vpu/P/PLL/I growth = %.4g / %.4g / %.4g / %.4g', ...
                localSummary.zeroGrowth_Vpu,localSummary.zeroGrowth_Pmeas,localSummary.zeroGrowth_PLL,localSummary.zeroGrowth_Imeas);
            logf(fid,'Integral/Proportional RMS ratio: zero-command=%.4g, platform-last10=%.4g', ...
                localSummary.zeroIntegralToPropRMS,localSummary.platformLast10IntegralToPropRMS);
        end
        logf(fid,'Platform CurrentLimit duty = %.6g',P.CurrentLimit_mean);
        logf(fid,'Platform allowed-support max = %.6g',P.AllowedSupportMaxAbs_max);
        logf(fid,'Platform raw/unselected-support max = %.6g',P.RawSupportMaxAbs_max);
        logf(fid,'Platform PIntegral slope = %.6g per second',P.PIntegral_slope);
    else
        logf(fid,'Fixed platform was not long enough for a platform summary.');
    end

    zipPath = [outDir '.zip'];
    zip(zipPath,{'*'},outDir);
    result.evidenceZip = zipPath;
    json_write(fullfile(outDir,'RESULT.json'),result);
    save(fullfile(outDir,'RESULT.mat'),'result','-v7');

    fprintf('\nP-loop Ki=0.5 small-power DirectMAT calculation complete.\n');
    fprintf('NO automatic electrical PASS/FAIL was declared.\n');
    fprintf('Output directory: %s\n',outDir);
    fprintf('Upload ZIP:       %s\n',zipPath);

catch ME
    try
        text_write(fullfile(outDir,'ERROR.txt'),getReport(ME,'extended','hyperlinks','off'));
    catch
        text_write(fullfile(outDir,'ERROR.txt'),ME.message);
    end
    fprintf(2,['\nDirectMAT post-processing stopped. Existing raw MAT evidence is untouched.\n' ...
        'DO NOT rerun the physical RT-LAB trial because of this MATLAB error.\n%s\n'],ME.message);
    rethrow(ME);
end
end

% =========================================================================
% Configuration
% =========================================================================
function C = local_config()
C.version = 'K26_K50_ESS2_PONLY_KI05_SMALLPOWER_DIRECTMAT_R1_20260916';
C.defaultRunRoot = 'D:\E2RUN';
C.defaultModelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
    'yanshou_V7\models\K26_K50_CLEAN_P1'];
C.expectedRunnerPrefix = 'ESS2_PONLY_KI05_SMALLPOWER_FORMAL_R1';
C.expectedRows.G27 = 120;
C.expectedRows.G29 = 75;
C.expectedRows.G30 = 145;
C.expectedVar.G27 = 'rootdiag_ess2_data';
C.expectedVar.G29 = 'd1_gfm_superpack_data';
C.expectedVar.G30 = 'freqdiag_ess1_data';
C.window_s = 2.0;
C.compact_dt_s = 0.010;
end

function validate_smallpower_manifest(R)
J=R.manifest;
if ~isfield(J,'case') || ~strcmpi(char(J.case),'SMALLPOWER_KI05')
    error('SPKI05:Case','Manifest case is not SMALLPOWER_KI05.');
end
if ~isfield(J,'diagnostic_config')
    error('SPKI05:DiagConfig','Manifest lacks diagnostic_config.');
end
D=J.diagnostic_config;
must_num_field(D,'E2_DIAG_P_LOOP_ENABLE',1);
must_num_field(D,'E2_DIAG_Q_LOOP_ENABLE',0);
must_num_field(D,'E2_DIAG_DIRECT_IREF_ENABLE',0);

if ~isfield(J,'controller_variant')
    error('SPKI05:ControllerVariant','Manifest lacks controller_variant.');
end
V=J.controller_variant;
must_num_field(V,'P_Kp_expected',0.06);
must_num_field(V,'P_Ki_expected',0.5);

if isfield(V,'P_PI_runtime_before')
    must_num_field(V.P_PI_runtime_before,'Kp',0.06);
    must_num_field(V.P_PI_runtime_before,'Ki',2.0);
end
if isfield(V,'P_PI_runtime_after')
    must_num_field(V.P_PI_runtime_after,'Kp',0.06);
    must_num_field(V.P_PI_runtime_after,'Ki',0.5);
    if isfield(V.P_PI_runtime_after,'Kp_path')
        q=char(V.P_PI_runtime_after.Kp_path);
        if ~contains(q,'CFG_E2_DIAG_P_KP_RT')
            error('SPKI05:KpPath','Unexpected P-Kp runtime path: %s',q);
        end
    end
    if isfield(V.P_PI_runtime_after,'Ki_path')
        q=char(V.P_PI_runtime_after.Ki_path);
        if ~contains(q,'CFG_E2_DIAG_P_KI_RT')
            error('SPKI05:KiPath','Unexpected P-Ki runtime path: %s',q);
        end
    end
end

if isfield(J,'target_pu')
    if abs(double(J.target_pu)+0.005)>1e-12
        error('SPKI05:Target','Manifest target is not -0.005 pu.');
    end
end
end

function must_num_field(S,name,want)
if ~isfield(S,name)
    error('SPKI05:Field','Missing manifest field: %s',name);
end
got=double(S.(name));
if ~isscalar(got)||~isfinite(got)||abs(got-want)>1e-10
    error('SPKI05:FieldValue','Manifest %s mismatch: got %.17g want %.17g',name,got,want);
end
end

% =========================================================================
% Resolve latest completed run / manifest
% =========================================================================
function [guard,R] = resolve_run(inputPath,C)
guard = [];
if nargin < 1, inputPath=''; end
inputPath = char(inputPath);
outputAnchor = '';

candidateManifests = {};
if ~isempty(inputPath)
    if exist(inputPath,'dir') == 7
        p = fullfile(inputPath,'manifest.json');
        if isfile(p), candidateManifests{end+1}=p; end %#ok<AGROW>
        dd = dir(fullfile(inputPath,'**','manifest.json'));
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
            tmp=tempname; mkdir(tmp);
            unzip(inputPath,tmp);
            guard=onCleanup(@()safe_rmdir(tmp));
            dd=dir(fullfile(tmp,'**','manifest.json'));
            for i=1:numel(dd)
                candidateManifests{end+1}=fullfile(dd(i).folder,dd(i).name); %#ok<AGROW>
            end
        else
            error('DIRECTMAT:Input','Input must be a run directory, manifest.json, or result ZIP.');
        end
    else
        error('DIRECTMAT:InputMissing','Input path does not exist: %s',inputPath);
    end
else
    roots = {C.defaultRunRoot,pwd,fileparts(mfilename('fullpath'))};
    for r=1:numel(roots)
        if exist(roots{r},'dir') ~= 7, continue; end
        if strcmpi(roots{r},C.defaultRunRoot)
            dd=dir(fullfile(roots{r},'smallpower_ki05_*','manifest.json'));
        else
            dd=dir(fullfile(roots{r},'**','manifest.json'));
        end
        for i=1:numel(dd)
            candidateManifests{end+1}=fullfile(dd(i).folder,dd(i).name); %#ok<AGROW>
        end
    end
end

candidateManifests=unique(candidateManifests,'stable');
valid = struct('path',{},'datenum',{},'J',{});
for i=1:numel(candidateManifests)
    p=candidateManifests{i};
    try
        J=jsondecode(fileread(p));
        ver=field_text(J,'version','');
        st=field_text(J,'status','');
        hasFiles=isfield(J,'expected_mat_files');
        if startsWith(ver,C.expectedRunnerPrefix) && startsWith(st,'CAPTURE_COMPLETE') && hasFiles
            d=dir(p);
            q.path=p;q.datenum=d.datenum;q.J=J;
            valid(end+1)=q; %#ok<AGROW>
        end
    catch
    end
end
if isempty(valid)
    error('DIRECTMAT:NoRun',['No completed %s manifest found. ' ...
        'Expected e.g. D:/E2RUN/smallpower_ki05_*/manifest.json.'],C.expectedRunnerPrefix);
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
% Add model root parent only as a final fallback; do not recursively scan a whole drive.
if exist(C.defaultModelRoot,'dir')==7
    roots{end+1}=C.defaultModelRoot; %#ok<AGROW>
end
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

    % Fast path: exact file under current root.
    p=fullfile(root,exactName);
    if isfile(p),candidates{end+1}=canonical(p);end %#ok<AGROW>

    % Preferred RT-LAB path: any task/OpREDHAWKtarget/exact-file.
    dd=dir(fullfile(root,'**','OpREDHAWKtarget',exactName));
    for i=1:numel(dd)
        candidates{end+1}=canonical(fullfile(dd(i).folder,dd(i).name)); %#ok<AGROW>
    end
end
candidates=unique(candidates,'stable');

% Broader recursive search only when preferred paths failed.
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
    error('DIRECTMAT:MATMissing','Cannot find exact MAT file: %s',exactName);
end

% Prefer OpREDHAWKtarget, then newest copy.  Exact filename already carries
% the run file-id, so this never substitutes another run by wildcard stem.
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
% Load one exact MAT family
% =========================================================================
function [A,actualName]=load_exact_family(path,preferredName,expectedRows,label,fid,outDir)
% Inspect MAT metadata first.  Older static OpWrite files used stable variable
% names such as rootdiag_ess2_data.  Dynamic-file OpWrite builds may keep the
% same signal matrix under a different MAT variable name.  Never guess by
% wildcard file stem: resolve by exact preferred name first, otherwise require
% exactly one real numeric 2-D variable whose one dimension equals the frozen
% current recorder row count.

W=whos('-file',path);
if isempty(W)
    error('DIRECTMAT:EmptyMAT','%s: MAT file contains no variables: %s',label,path);
end

rows=cell(numel(W),8);
match=false(numel(W),1);
for i=1:numel(W)
    sz=W(i).size;
    if isempty(sz),sz=[0 0];end
    if numel(sz)==1,sz=[sz 1];end
    r=sz(1); c=prod(sz(2:end));
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
        % Give a useful error without loading the huge MAT.
        detail=strjoin(arrayfun(@(q)sprintf('%s[%s] size=%s', ...
            W(q).name,W(q).class,mat2str(W(q).size)),1:numel(W),'UniformOutput',false),' | ');
        error('DIRECTMAT:NoMatrixCandidate', ...
            ['%s: preferred variable "%s" is absent and no unique numeric 2-D variable ' ...
             'contains the expected dimension %d. Inventory was written to %s. Variables: %s'], ...
            label,preferredName,expectedRows,outDir,detail);
    else
        detail=strjoin(arrayfun(@(q)sprintf('%s size=%s', ...
            W(q).name,mat2str(W(q).size)),cand,'UniformOutput',false),' | ');
        error('DIRECTMAT:AmbiguousMatrixCandidate', ...
            ['%s: preferred variable "%s" is absent and %d candidate matrices match ' ...
             'expected dimension %d. No guessing is allowed. Inventory: %s. Candidates: %s'], ...
            label,preferredName,numel(cand),expectedRows,outDir,detail);
    end
end

actualName=W(k).name;
logf(fid,'[%s] MAT variable resolution: %s -> %s (%s)', ...
    label,preferredName,actualName,resolution);
logf(fid,'[%s] variable %s size=%s class=%s bytes=%g', ...
    label,actualName,mat2str(W(k).size),W(k).class,W(k).bytes);

S=load(path,actualName);
A=S.(actualName);
clear S;

if size(A,1)==expectedRows
    % normal
elseif size(A,2)==expectedRows
    A=A.';
    logf(fid,'[%s] transposed to rows x samples.',label);
else
    error('DIRECTMAT:RowCount', ...
        '%s expected %d rows including time, actual variable %s is %dx%d.', ...
        label,expectedRows,actualName,size(A,1),size(A,2));
end
if ~isnumeric(A) || ~isreal(A)
    error('DIRECTMAT:DataType','%s data variable %s must be real numeric.',label,actualName);
end
end

function tf=is_numeric_class(cls)
tf=ismember(char(cls),{'double','single','int8','uint8','int16','uint16', ...
    'int32','uint32','int64','uint64','logical'});
end

% =========================================================================
% Time audit. Remove only non-increasing duplicate/backward samples from the
% numerical copy; never interpolate missing time.
% =========================================================================
function [A,T]=sanitize_time_axis(A,label)
t=double(A(1,:));
if any(~isfinite(t))
    error('DIRECTMAT:TimeNaN','%s target-time row contains NaN/Inf.',label);
end
d=diff(t);
pos=d(d>0);
if isempty(pos),error('DIRECTMAT:TimeAxis','%s has no increasing target time.',label);end
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
% G27 events / phases
% =========================================================================
function E=detect_g27_events(t,s,run)
E=struct();
E.breakerClose=first_time(t,s.Breaker>0.5);
E.state4=first_time(t,round(s.RestoreState)==4);
E.state5=first_time(t,round(s.RestoreState)==5);
E.state6=first_time(t,round(s.RestoreState)==6);
E.alphaOpen=first_time(t,s.AlphaUsed>0.5);
if ~isfinite(E.alphaOpen),E.alphaOpen=first_time(t,s.RestoreAlpha>0.5);end
E.prefStart=first_time(t,abs(s.PrefApplied)>5e-5);
target=s.Target;
maskTarget=abs(target)>=1e-4 & abs(s.PrefApplied-target)<=1e-4;
if isfinite(E.prefStart),maskTarget=maskTarget & t>=E.prefStart;end
E.targetReach=first_time(t,maskTarget);
E.firstCurrentLimit=first_time(t,s.CurrentLimit>0.5);
E.firstSevere=first_time(t,s.Severe>0.5);
E.firstFailCode=first_time(t,s.FailCode>0.5);
E.end=t(end);
E.runnerFirstState6=run.firstState6;
E.runnerTargetClock=run.targetClock;
end

function P=make_phases(t,E)
P=struct('name',{},'t0',{},'t1',{});
P(end+1)=phase('PRE_CLOSE',t(1),E.breakerClose);
P(end+1)=phase('CONNECTED_ZERO',E.breakerClose,E.alphaOpen);
P(end+1)=phase('ZERO_COMMAND_KI05',E.alphaOpen,E.prefStart);
P(end+1)=phase('POWER_RAMP',E.prefStart,E.targetReach);
P(end+1)=phase('FIXED_PLATFORM',E.targetReach,t(end));
if isfinite(E.targetReach)
    dur=t(end)-E.targetReach;
    if dur>=5
        P(end+1)=phase('PLATFORM_FIRST5',E.targetReach,min(t(end),E.targetReach+5));
        P(end+1)=phase('PLATFORM_LAST5',max(E.targetReach,t(end)-5),t(end));
    end
    if dur>=10
        P(end+1)=phase('PLATFORM_LAST10',max(E.targetReach,t(end)-10),t(end));
    end
    if dur>=20
        P(end+1)=phase('PLATFORM_LAST20',max(E.targetReach,t(end)-20),t(end));
    end
end
end

function p=phase(name,t0,t1)
p=struct('name',name,'t0',t0,'t1',t1);
end

function T=struct2eventtable(E,source)
fn=fieldnames(E);
rows=cell(0,3);
for i=1:numel(fn)
    v=E.(fn{i});
    if isnumeric(v) && isscalar(v)
        rows(end+1,:)={source,fn{i},v}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'Source','Event','Time_s'});
end

% =========================================================================
% Phase metrics (long format)
% =========================================================================
function T=calculate_phase_metrics(t,s,phases)
signalNames={ ...
    'Vpu','PLL','PrefApplied','Target','Pmeas','PrefEff','PTrackingError','PProportional','PIntegral','QIntegral','PPIReconPred','PPIReconResidual', ...
    'FinalIrefMag','IrefUsedMag','ImeasUsedMag','GammaP','GammaQ','BaseScaleP','BaseScaleQ', ...
    'CurrentLimit','ModIndex','RawModInternal','ModHeadroom','TotalSupportMag', ...
    'AllowedSupportMaxAbs','RawSupportMaxAbs','SupportEnvelope','VsupportRef','VCommandLocal', ...
    'CurrentErrorNorm','ExecResidualMag','VbpMag','PickupQual','ZeroQual','Severe', ...
    'AdapterValid','ComponentClip','RadiusClip','PIStateClip'};
rows=cell(0,12);
for pi=1:numel(phases)
    p=phases(pi);
    if ~isfinite(p.t0) || ~isfinite(p.t1) || p.t1<=p.t0,continue;end
    idx=t>=p.t0 & t<=p.t1;
    if nnz(idx)<3,continue;end
    tt=t(idx);
    for si=1:numel(signalNames)
        nm=signalNames{si};
        x=double(s.(nm)(idx));
        m=metric_vector(tt,x);
        rows(end+1,:)={p.name,nm,p.t0,p.t1,nnz(idx),m.mean,m.min,m.max,m.p2p,m.std,m.rms,m.slope}; %#ok<AGROW>
    end
    err=double(s.Pmeas(idx)-s.PrefApplied(idx));
    m=metric_vector(tt,err);
    rows(end+1,:)={p.name,'PTrackingError',p.t0,p.t1,nnz(idx),m.mean,m.min,m.max,m.p2p,m.std,m.rms,m.slope}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames', ...
    {'Phase','Signal','Start_s','End_s','Samples','Mean','Min','Max','P2P','Std','RMS','Slope_per_s'});
end

function m=metric_vector(t,x)
good=isfinite(t)&isfinite(x);
t=t(good);x=x(good);
if isempty(x)
    m=struct('mean',NaN,'min',NaN,'max',NaN,'p2p',NaN,'std',NaN,'rms',NaN,'slope',NaN);return;
end
m.mean=mean(x);
m.min=min(x);m.max=max(x);m.p2p=m.max-m.min;
m.std=std(x,0);
m.rms=sqrt(mean(x.^2));
if numel(x)>=3 && (t(end)-t(1))>0
    tt=t-t(1);
    c=polyfit(tt,x,1);m.slope=c(1);
else
    m.slope=NaN;
end
end

% =========================================================================
% 2-second windows: exactly the question "bounded, drifting, growing?"
% =========================================================================
function T=calculate_2s_windows(t,s,startTime,W)
if ~isfinite(startTime),T=table();return;end
edges=startTime:W:t(end);
if isempty(edges) || edges(end)<t(end)-0.25*W,edges=[edges t(end)];end %#ok<AGROW>
rows=cell(0,31);
for i=1:max(0,numel(edges)-1)
    a=edges(i);b=edges(i+1);
    idx=t>=a & t< b;
    if i==numel(edges)-1,idx=t>=a & t<=b;end
    if nnz(idx)<3,continue;end
    tt=t(idx);
    mv=metric_vector(tt,s.Vpu(idx));
    mf=metric_vector(tt,s.PLL(idx));
    mp=metric_vector(tt,s.Pmeas(idx));
    mc=metric_vector(tt,s.PrefApplied(idx));
    me=metric_vector(tt,s.Pmeas(idx)-s.PrefApplied(idx));
    mi=metric_vector(tt,s.IrefUsedMag(idx));
    mm=metric_vector(tt,s.ImeasUsedMag(idx));
    mpi=metric_vector(tt,s.PIntegral(idx));
    mce=metric_vector(tt,s.CurrentErrorNorm(idx));
    rows(end+1,:)={i,a,b,nnz(idx), ...
        mv.mean,mv.min,mv.max,mv.p2p,mv.std,mv.slope, ...
        mf.mean,mf.p2p,mf.slope, ...
        mc.mean,mp.mean,mp.min,mp.max,mp.p2p,me.rms,mp.slope, ...
        mi.mean,mi.max,mm.mean,mm.max, ...
        mpi.mean,mpi.min,mpi.max,mpi.slope, ...
        mean(s.CurrentLimit(idx)>0.5),min(s.ModHeadroom(idx)),mce.mean}; %#ok<AGROW>
end
vars={'Window','Start_s','End_s','Samples', ...
    'VpuMean','VpuMin','VpuMax','VpuP2P','VpuStd','VpuSlope', ...
    'PLLMean_Hz','PLLP2P_Hz','PLLSlope_Hz_per_s', ...
    'PrefMean_pu','PmeasMean_pu','PmeasMin_pu','PmeasMax_pu','PmeasP2P_pu','PErrorRMS_pu','PmeasSlope_pu_per_s', ...
    'IrefMean_pu','IrefMax_pu','ImeasMean_pu','ImeasMax_pu', ...
    'PIntegralMean','PIntegralMin','PIntegralMax','PIntegralSlope_per_s', ...
    'CurrentLimitDuty','ModHeadroomMin','CurrentErrorNormMean'};
T=cell2table(rows,'VariableNames',vars);
end

% =========================================================================
% Spectral description (no Signal Processing Toolbox needed)
% =========================================================================
function T=calculate_spectral_summary(t,s,phases)
sigNames={'Vpu','Pmeas','IrefUsedMag','ImeasUsedMag','PIntegral','CurrentErrorNorm'};
wantPhases={'ZERO_COMMAND_KI05','FIXED_PLATFORM','PLATFORM_LAST10'};
bands=[0.1 5;5 20;20 32];
bandNames={'B0p1_5','B5_20','B20_32'};
rows=cell(0,10);
for pi=1:numel(phases)
    p=phases(pi);
    if ~ismember(p.name,wantPhases),continue;end
    if ~isfinite(p.t0)||~isfinite(p.t1)||p.t1<=p.t0,continue;end
    idx=t>=p.t0&t<=p.t1;
    tt=t(idx);
    for si=1:numel(sigNames)
        nm=sigNames{si};xx=double(s.(nm)(idx));
        [segT,segX,segDur,dt]=longest_contiguous(tt,xx);
        if numel(segX)<64 || segDur<0.2
            rows(end+1,:)={p.name,nm,NaN,NaN,NaN,NaN,NaN,segDur,dt,'INSUFFICIENT'}; %#ok<AGROW>
            continue
        end
        [dom,ef]=fft_energy(segT,segX,bands);
        rows(end+1,:)={p.name,nm,dom,ef(1),ef(2),ef(3),sum(ef),segDur,dt,'OK'}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames', ...
    {'Phase','Signal','DominantHz_0p1_40','EnergyFrac_0p1_5','EnergyFrac_5_20','EnergyFrac_20_32', ...
    'EnergyFrac_SelectedBands','ContiguousDuration_s','MedianDt_s','Status'});
T.Properties.UserData=struct('BandNames',{bandNames});
end

function [tt,xx,dur,dtmed]=longest_contiguous(t,x)
good=isfinite(t)&isfinite(x);
t=t(good);x=x(good);
if numel(t)<2,tt=t;xx=x;dur=0;dtmed=NaN;return;end
d=diff(t);dp=d(d>0);dtmed=median(dp);
cuts=find(d<=0 | d>1.5*dtmed);
st=[1 cuts+1];en=[cuts numel(t)];
lens=t(en)-t(st);
[~,k]=max(lens);
tt=t(st(k):en(k));xx=x(st(k):en(k));dur=tt(end)-tt(1);
end

function [dom,ef]=fft_energy(t,x,bands)
dt=median(diff(t));
x=x(:);
n=numel(x);
tt=(0:n-1)'*dt;
c=polyfit(tt,x,1);
y=x-polyval(c,tt);
if n>1
    w=0.5-0.5*cos(2*pi*(0:n-1)'/(n-1));
else
    w=1;
end
Y=fft(y.*w);
P=abs(Y).^2;
f=(0:n-1)'/(n*dt);
half=f<=min(40,0.5/dt) & f>=0.1;
if ~any(half) || sum(P(half))<=0
    dom=NaN;ef=nan(1,size(bands,1));return;
end
[~,j]=max(P.*half);
dom=f(j);
den=sum(P(half));
ef=nan(1,size(bands,1));
for k=1:size(bands,1)
    q=f>=bands(k,1)&f<bands(k,2)&half;
    ef(k)=sum(P(q))/den;
end
end

% =========================================================================
% Key samples
% =========================================================================
function T=key_samples_g27(t,s,E,step)
times=t(1):step:t(end);
special=[E.breakerClose E.state5 E.state6 E.alphaOpen E.prefStart E.targetReach E.end];
times=unique([times special(isfinite(special))]);
rows=nan(numel(times),16);
for i=1:numel(times)
    [~,k]=min(abs(t-times(i)));
    rows(i,:)=[t(k),s.RestoreState(k),s.RestoreAlpha(k),s.Breaker(k),s.Vpu(k),s.PLL(k), ...
        s.PrefApplied(k),s.Pmeas(k),s.PrefEff(k),s.PIntegral(k),s.IrefUsedMag(k), ...
        s.ImeasUsedMag(k),s.CurrentLimit(k),s.ModHeadroom(k),s.AllowedSupportMaxAbs(k),s.RawSupportMaxAbs(k)];
end
T=array2table(rows,'VariableNames',{'Time_s','RestoreState','RestoreAlpha','Breaker','Vpu','PLL_Hz', ...
    'PrefApplied_pu','Pmeas_pu','PrefEff_pu','PIntegral','IrefUsedMag_pu','ImeasUsedMag_pu', ...
    'CurrentLimit','ModHeadroom','AllowedSupportMaxAbs','RawSupportMaxAbs'});
end

% =========================================================================
% G29 analysis
% =========================================================================
function T=g29_transitions(t,g)
names={'Substate','Coarse','RestoreStage','CoordStage','GFLStage','PickupEnable','OwnerRequest', ...
    'PickupApplied','FinalPCommand','HandoverBeta','ESS2Available','CorrectionGain','SecondaryEnable', ...
    'S14Active','RestoreState','Alpha','FailCode','ReleaseAllowed','DiagFlagSM','FixedTargetSM'};
rows=cell(0,5);
for ni=1:numel(names)
    nm=names{ni};x=g.(nm);
    dx=[true abs(diff(x))>1e-10];
    idx=find(dx);
    for j=1:numel(idx)
        k=idx(j);
        if k==1,old=NaN;else,old=x(k-1);end
        rows(end+1,:)={t(k),nm,old,x(k),k}; %#ok<AGROW>
    end
end
if isempty(rows)
    T=cell2table(cell(0,5),'VariableNames',{'Time_s','Signal','OldValue','NewValue','SampleIndex'});
else
    T=cell2table(rows,'VariableNames',{'Time_s','Signal','OldValue','NewValue','SampleIndex'});
    T=sortrows(T,'Time_s');
end
end

function T=g29_phase_metrics(t,g,phases)
names={'J1Applied','Ppcc_kW','Qpcc_kvar','PCCFreq_Hz','PCCVab_RMS_V', ...
    'Substate','RestoreStage','CoordStage','GFLStage','PickupEnable','OwnerRequest','PickupApplied', ...
    'FinalPCommand','HandoverBeta','ESS2Available','CorrectionGain','SecondaryEnable','RestoreState', ...
    'Alpha','FailCode','ReleaseAllowed','LegacyVoltageESS2'};
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

% =========================================================================
% Small-power Ki=0.5 local/system contract + tracking summaries
% =========================================================================
function T=smallpower_local_contract_table(t,s,E,R)
idx=t>=E.state6;
if ~any(idx),error('SPKI05:NoPostState6','No G27 samples after state6.');end
platform=false(size(t));
if isfinite(E.targetReach),platform=t>=E.targetReach;end
rows={ ...
    'Manifest_PLoopEnable',double(R.manifest.diagnostic_config.E2_DIAG_P_LOOP_ENABLE),1,'host config'; ...
    'Manifest_QLoopEnable',double(R.manifest.diagnostic_config.E2_DIAG_Q_LOOP_ENABLE),0,'host config'; ...
    'Manifest_DirectEnable',double(R.manifest.diagnostic_config.E2_DIAG_DIRECT_IREF_ENABLE),0,'host config'; ...
    'Manifest_P_Kp',double(R.manifest.controller_variant.P_Kp_expected),0.06,'runtime PI config'; ...
    'Manifest_P_Ki',double(R.manifest.controller_variant.P_Ki_expected),0.5,'runtime PI config'; ...
    'PostS6_MaxAbs_PIntegral',max(abs(s.PIntegral(idx))),NaN,'nonzero integral contribution is descriptive'; ...
    'PostS6_MaxAbs_QIntegral',max(abs(s.QIntegral(idx))),0,'Q-loop disabled evidence'; ...
    'PostS6_MaxAbs_PPIReconResidual',max(abs(s.PPIReconResidual(idx))),0,'RawP = 0.06*(Pref-Pmeas)+PIntegral evidence'; ...
    'PostS6_MaxAllowedSupport',max(abs(s.AllowedSupportMaxAbs(idx))),0,'support isolation evidence'; ...
    'PostS6_MaxFailCode',max(abs(s.FailCode(idx))),0,'model structural validity'; ...
    'PostS6_MinAlphaUsed',min(s.AlphaUsed(idx)),1,'Current Adapter authority'; ...
    'PostS6_MaxAlphaUsed',max(s.AlphaUsed(idx)),1,'Current Adapter authority'; ...
    'PrefStartFound',double(isfinite(E.prefStart)),1,'real small-power command'; ...
    'PrefTargetReachFound',double(isfinite(E.targetReach)),1,'real -0.005 target'; ...
    'FixedPlatformDuration_s',platform_duration(t,E),NaN,'targetReach -> record end' ...
    };
if any(platform)
    rows(end+1,:)={'Platform_PrefMean',mean(s.PrefApplied(platform),'omitnan'),-0.005,'executed command'}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'Item','Observed','NominalExpected','EvidenceSource'});
end

function S=smallpower_local_summary(t,s,E,Tsteady,Ttrack,Tgrowth,TzeroGrowth,Tcontrib)
idx=t>=E.state6;
S=struct();
S.postState6Duration_s=t(end)-E.state6;
S.fixedPlatformDuration_s=platform_duration(t,E);
S.maxAbsPIntegral=max(abs(s.PIntegral(idx)));
S.maxAbsQIntegral=max(abs(s.QIntegral(idx)));
S.maxAbsPPIReconResidual=max(abs(s.PPIReconResidual(idx)));
S.maxAbsPProportional=max(abs(s.PProportional(idx)));
S.maxAllowedSupport=max(abs(s.AllowedSupportMaxAbs(idx)));
S.maxRawSupport=max(abs(s.RawSupportMaxAbs(idx)));
S.currentLimitDuty=mean(double(s.CurrentLimit(idx)>0.5));
S.componentClipDuty=mean(double(s.ComponentClip(idx)>0.5));
S.radiusClipDuty=mean(double(s.RadiusClip(idx)>0.5));
S.piStateClipDuty=mean(double(s.PIStateClip(idx)>0.5));
S.modHeadroomMin=min(s.ModHeadroom(idx));

S.last10_PmeasMean=table_value_sp(Tsteady,'LAST10','PmeasMean');
S.last10_PrefMean=table_value_sp(Tsteady,'LAST10','PrefMean');
S.last10_ErrorMean=table_value_sp(Tsteady,'LAST10','ErrorMean');
S.last10_ErrorRMS=table_value_sp(Tsteady,'LAST10','ErrorRMS');
S.last10_RelAbsMean=table_value_sp(Tsteady,'LAST10','RelAbsMean');
S.last10_Within2pctDuty=table_value_sp(Tsteady,'LAST10','Within2pctDuty');
S.last10_Within5pctDuty=table_value_sp(Tsteady,'LAST10','Within5pctDuty');
S.last10_Within10pctDuty=table_value_sp(Tsteady,'LAST10','Within10pctDuty');

S.firstEnter2pct_s=tracking_value_sp(Ttrack,'Within2pct','FirstEntry_s');
S.firstSustain2pct_2s_s=tracking_value_sp(Ttrack,'Within2pct','FirstSustained2s_s');
S.firstEnter5pct_s=tracking_value_sp(Ttrack,'Within5pct','FirstEntry_s');
S.firstSustain5pct_2s_s=tracking_value_sp(Ttrack,'Within5pct','FirstSustained2s_s');
S.firstEnter10pct_s=tracking_value_sp(Ttrack,'Within10pct','FirstEntry_s');
S.firstSustain10pct_2s_s=tracking_value_sp(Ttrack,'Within10pct','FirstSustained2s_s');

S.growth_Vpu=growth_value_sp(Tgrowth,'Vpu');
S.growth_Pmeas=growth_value_sp(Tgrowth,'Pmeas');
S.growth_PLL=growth_value_sp(Tgrowth,'PLL');
S.growth_Imeas=growth_value_sp(Tgrowth,'ImeasUsedMag');
S.zeroGrowth_Vpu=growth_value_generic(TzeroGrowth,'Vpu');
S.zeroGrowth_Pmeas=growth_value_generic(TzeroGrowth,'Pmeas');
S.zeroGrowth_PLL=growth_value_generic(TzeroGrowth,'PLL');
S.zeroGrowth_Imeas=growth_value_generic(TzeroGrowth,'ImeasUsedMag');
S.zeroIntegralToPropRMS=contribution_value(Tcontrib,'ZERO_COMMAND','IntegralToPropRMS');
S.platformLast10IntegralToPropRMS=contribution_value(Tcontrib,'PLATFORM_LAST10','IntegralToPropRMS');
end

function d=platform_duration(t,E)
if isfinite(E.targetReach),d=max(0,t(end)-E.targetReach);else,d=NaN;end
end

function T=platform_steady_windows(t,s,E)
rows=cell(0,26);
vars=steady_vars_sp();
if ~isfinite(E.targetReach)
    T=cell2table(rows,'VariableNames',vars);return;
end
win={ ...
    'FULL',E.targetReach,t(end); ...
    'FIRST5',E.targetReach,min(t(end),E.targetReach+5); ...
    'LAST20',max(E.targetReach,t(end)-20),t(end); ...
    'LAST10',max(E.targetReach,t(end)-10),t(end); ...
    'LAST5',max(E.targetReach,t(end)-5),t(end)};
for i=1:size(win,1)
    name=win{i,1};a=win{i,2};b=win{i,3};
    idx=t>=a&t<=b;
    if nnz(idx)<3,continue;end
    tt=t(idx);pref=s.PrefApplied(idx);p=s.Pmeas(idx);err=p-pref;
    targetScale=max(abs(mean(pref,'omitnan')),1e-12);
    mv=metric_vector(tt,s.Vpu(idx));
    mp=metric_vector(tt,p);
    mf=metric_vector(tt,s.PLL(idx));
    mi=metric_vector(tt,s.ImeasUsedMag(idx));
    me=metric_vector(tt,err);
    rows(end+1,:)={name,a,b,nnz(idx), ...
        mean(pref,'omitnan'),mp.mean,me.mean,mean(abs(err),'omitnan'),me.rms,max(abs(err)), ...
        abs(me.mean)/targetScale, ...
        mean(abs(err)<=0.02*targetScale),mean(abs(err)<=0.05*targetScale),mean(abs(err)<=0.10*targetScale), ...
        mv.mean,mv.p2p,mv.slope,mf.mean,mf.p2p,mf.slope, ...
        mp.p2p,mp.slope,mi.p2p,mean(s.CurrentLimit(idx)>0.5),min(s.ModHeadroom(idx)), ...
        max(abs(s.PPIReconResidual(idx)))}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',vars);
end

function v=steady_vars_sp()
v={'Window','Start_s','End_s','Samples','PrefMean','PmeasMean','ErrorMean','MeanAbsError','ErrorRMS','MaxAbsError', ...
   'RelAbsMean','Within2pctDuty','Within5pctDuty','Within10pctDuty', ...
   'VpuMean','VpuP2P','VpuSlope','PLLMean','PLLP2P','PLLSlope','PmeasP2P','PmeasSlope', ...
   'ImeasP2P','CurrentLimitDuty','ModHeadroomMin','PIReconResidualMax'};
end

function T=tracking_accuracy_table(t,s,E)
rows=cell(0,7);
vars={'Band','Tolerance_pu','TolerancePercent','FirstEntry_s','FirstEntryAfterTarget_s','FirstSustained2s_s','SustainedDelay_s'};
if ~isfinite(E.targetReach)
    T=cell2table(rows,'VariableNames',vars);return
end
targetMag=0.005;
bands={ ...
    'Within2pct',0.02*targetMag,2; ...
    'Within5pct',0.05*targetMag,5; ...
    'Within10pct',0.10*targetMag,10};
for i=1:size(bands,1)
    nm=bands{i,1};tol=bands{i,2};pct=bands{i,3};
    mask=t>=E.targetReach & abs(s.Pmeas-s.PrefApplied)<=tol;
    fe=first_time(t,mask);
    fs=first_sustained_time_sp(t,mask,E.targetReach,2.0);
    rows(end+1,:)={nm,tol,pct,fe,fe-E.targetReach,fs,fs-E.targetReach}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',vars);
end

function t0=first_sustained_time_sp(t,mask,startTime,dwell)
t0=NaN;
ix=find(t>=startTime);
if isempty(ix),return;end
i0=ix(1);
for i=i0:numel(t)
    if ~mask(i),continue;end
    j=find(t>=t(i)+dwell,1,'first');
    if isempty(j),return;end
    if all(mask(i:j))
        t0=t(i);return;
    end
end
end

function T=platform_growth_table(t,s,E)
names={'Vpu','Pmeas','PLL','ImeasUsedMag'};
rows=cell(0,5);
vars={'Signal','First5P2P','Last5P2P','LastOverFirst','PlatformDuration_s'};
if ~isfinite(E.targetReach) || t(end)-E.targetReach<10
    T=cell2table(rows,'VariableNames',vars);return
end
i1=t>=E.targetReach&t<=E.targetReach+5;
i2=t>=t(end)-5&t<=t(end);
for k=1:numel(names)
    nm=names{k};
    a=s.(nm)(i1);b=s.(nm)(i2);
    p1=max(a)-min(a);p2=max(b)-min(b);
    if p1>0,rat=p2/p1;else,rat=NaN;end
    rows(end+1,:)={nm,p1,p2,rat,t(end)-E.targetReach}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',vars);
end

function v=table_value_sp(T,win,col)
q=T(strcmp(T.Window,win),:);
if isempty(q),v=NaN;else,v=q.(col)(1);end
end

function v=tracking_value_sp(T,band,col)
q=T(strcmp(T.Band,band),:);
if isempty(q),v=NaN;else,v=q.(col)(1);end
end

function v=growth_value_sp(T,sig)
q=T(strcmp(T.Signal,sig),:);
if isempty(q),v=NaN;else,v=q.LastOverFirst(1);end
end

function T=zero_command_growth_table(t,s,E)
names={'Vpu','Pmeas','PLL','ImeasUsedMag'};
rows=cell(0,5);
vars={'Signal','Early2P2P','Late2P2P','LateOverEarly','ZeroWindowDuration_s'};
if ~isfinite(E.alphaOpen)||~isfinite(E.prefStart)||E.prefStart-E.alphaOpen<4
    T=cell2table(rows,'VariableNames',vars);return
end
i1=t>=E.alphaOpen&t<E.alphaOpen+2;
i2=t>=E.prefStart-2&t<E.prefStart;
for k=1:numel(names)
    nm=names{k};
    a=s.(nm)(i1);b=s.(nm)(i2);
    p1=max(a)-min(a);p2=max(b)-min(b);
    if p1>0,rat=p2/p1;else,rat=NaN;end
    rows(end+1,:)={nm,p1,p2,rat,E.prefStart-E.alphaOpen}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',vars);
end

function T=controller_contribution_table(t,s,E)
rows=cell(0,10);
vars={'Window','Start_s','End_s','Samples','PropRMS','IntegralRMS','RawPRMS','IntegralToPropRMS','IntegralToRawRMS','PIReconResidualMax'};
win={};
if isfinite(E.alphaOpen)&&isfinite(E.prefStart)&&E.prefStart>E.alphaOpen
    win(end+1,:)={'ZERO_COMMAND',E.alphaOpen,E.prefStart}; %#ok<AGROW>
end
if isfinite(E.targetReach)
    win(end+1,:)={'PLATFORM_FULL',E.targetReach,t(end)}; %#ok<AGROW>
    if t(end)-E.targetReach>=10
        win(end+1,:)={'PLATFORM_LAST10',t(end)-10,t(end)}; %#ok<AGROW>
    end
end
for i=1:size(win,1)
    nm=win{i,1};a=win{i,2};b=win{i,3};
    idx=t>=a&t<=b;
    if nnz(idx)<3,continue;end
    pr=s.PProportional(idx);ii=s.PIntegral(idx);rr=s.RawP(idx);res=s.PPIReconResidual(idx);
    prms=sqrt(mean(pr.^2,'omitnan'));
    irms=sqrt(mean(ii.^2,'omitnan'));
    rrms=sqrt(mean(rr.^2,'omitnan'));
    if prms>0,r1=irms/prms;else,r1=NaN;end
    if rrms>0,r2=irms/rrms;else,r2=NaN;end
    rows(end+1,:)={nm,a,b,nnz(idx),prms,irms,rrms,r1,r2,max(abs(res))}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',vars);
end

function v=growth_value_generic(T,sig)
q=T(strcmp(T.Signal,sig),:);
if isempty(q),v=NaN;else,v=q.LateOverEarly(1);end
end

function v=contribution_value(T,win,col)
q=T(strcmp(T.Window,win),:);
if isempty(q),v=NaN;else,v=q.(col)(1);end
end

function T=smallpower_system_contract_table(t,g,E)
idx=t>=E.state6;
if ~any(idx),error('SPKI05:G29NoPostS6','G29 has no post-state6 samples.');end
rows={ ...
    'MaxAbs_HandoverBeta',max(abs(g.HandoverBeta(idx))),0; ...
    'MaxAbs_CorrectionGain',max(abs(g.CorrectionGain(idx))),0; ...
    'MaxAbs_SecondaryEnable',max(abs(g.SecondaryEnable(idx))),0; ...
    'MaxAbs_FailCode',max(abs(g.FailCode(idx))),0; ...
    'MaxAbs_J1Applied',max(abs(g.J1Applied(idx))),0; ...
    'MaxAbs_FinalMinusPickup',max(abs(g.FinalPCommand(idx)-g.PickupApplied(idx))),0; ...
    'Min_Substate',min(g.Substate(idx)),35; ...
    'Max_Substate',max(g.Substate(idx)),45; ...
    'MaxAbs_FinalPCommand',max(abs(g.FinalPCommand(idx))),NaN; ...
    'MaxAbs_PickupApplied',max(abs(g.PickupApplied(idx))),NaN; ...
    'MaxAbs_CoordinatorPref_Background',max(abs(g.CoordinatorPref(idx))),NaN ...
    };
T=cell2table(rows,'VariableNames',{'Item','Observed','NominalExpected'});
end

function S=smallpower_system_summary(t,g,E)
idx=t>=E.state6;
S=struct();
S.maxAbsFinalPCommand=max(abs(g.FinalPCommand(idx)));
S.maxAbsPickupApplied=max(abs(g.PickupApplied(idx)));
S.maxAbsOwnerRequest=max(abs(g.OwnerRequest(idx)));
S.maxAbsHandoverBeta=max(abs(g.HandoverBeta(idx)));
S.maxAbsCorrectionGain=max(abs(g.CorrectionGain(idx)));
S.maxAbsSecondaryEnable=max(abs(g.SecondaryEnable(idx)));
S.maxAbsFailCode=max(abs(g.FailCode(idx)));
S.finalMinusPickupMax=max(abs(g.FinalPCommand(idx)-g.PickupApplied(idx)));
S.PCCV_p2p=max(g.PCCVab_RMS_V(idx))-min(g.PCCVab_RMS_V(idx));
S.PCCF_p2p=max(g.PCCFreq_Hz(idx))-min(g.PCCFreq_Hz(idx));
S.PCCP_p2p=max(g.Ppcc_kW(idx))-min(g.Ppcc_kW(idx));
S.PCCQ_p2p=max(g.Qpcc_kvar(idx))-min(g.Qpcc_kvar(idx));
S.substateMin=min(g.Substate(idx));
S.substateMax=max(g.Substate(idx));
end

function [S,ki0Path,ki2Path]=compare_ki_cases(C,Pcur,Lcur,outDir,fid)
S=struct();ki0Path='';ki2Path='';J0=struct();J2=struct();
try
    dd=dir(fullfile(C.defaultRunRoot,'smallpower_ki0_*','MATLAB_SMALLPOWER_KI0_DIRECTMAT_*','RESULT.json'));
    if ~isempty(dd)
        [~,ix]=max([dd.datenum]);ki0Path=fullfile(dd(ix).folder,dd(ix).name);J0=jsondecode(fileread(ki0Path));
    end
catch,J0=struct();ki0Path='';end
try
    dd=dir(fullfile(C.defaultRunRoot,'observe_*','MATLAB_DIRECTMAT_*','RESULT.json'));
    if ~isempty(dd)
        [~,ix]=max([dd.datenum]);ki2Path=fullfile(dd(ix).folder,dd(ix).name);J2=jsondecode(fileread(ki2Path));
    end
catch,J2=struct();ki2Path='';end
P0=get_struct_field_sp(J0,'platform');L0=get_struct_field_sp(J0,'localSummary');
P2=get_struct_field_sp(J2,'platform');L2=get_struct_field_sp(J2,'localSummary');
metrics={'Pmeas_mean','PTrackingError_rms','Vpu_p2p','Pmeas_p2p','PIntegral_p2p','CurrentLimit_mean','AllowedSupportMaxAbs_max'};
rows=cell(numel(metrics),4);
for i=1:numel(metrics)
    nm=metrics{i};rows(i,:)={nm,field_or_nan_sp(P0,nm),field_or_nan_sp(Pcur,nm),field_or_nan_sp(P2,nm)};
end
T=cell2table(rows,'VariableNames',{'Metric','Ki0','Ki0p5','Ki2'});
writetable(T,fullfile(outDir,'17_KI0_KI05_KI2_PLATFORM_COMPARISON.csv'));
localMetrics={'last10_PmeasMean','last10_RelAbsMean','growth_Vpu','growth_Pmeas','growth_PLL','growth_Imeas','maxAbsPIntegral'};
rows=cell(numel(localMetrics),4);
for i=1:numel(localMetrics)
    nm=localMetrics{i};rows(i,:)={nm,field_or_nan_sp(L0,nm),field_or_nan_sp(Lcur,nm),field_or_nan_sp(L2,nm)};
end
T2=cell2table(rows,'VariableNames',{'Metric','Ki0','Ki0p5','Ki2'});
writetable(T2,fullfile(outDir,'18_KI0_KI05_KI2_LOCAL_COMPARISON.csv'));
S.ki0Path=ki0Path;S.ki2Path=ki2Path;S.platform=T;S.local=T2;
logf(fid,'Ki=0 comparison source: %s',ki0Path);logf(fid,'Ki=2 comparison source: %s',ki2Path);
try
    f=figure('Visible','off','Color','w');
    vals=[field_or_nan_sp(P0,'Vpu_p2p') field_or_nan_sp(Pcur,'Vpu_p2p') field_or_nan_sp(P2,'Vpu_p2p'); ...
          field_or_nan_sp(P0,'Pmeas_p2p') field_or_nan_sp(Pcur,'Pmeas_p2p') field_or_nan_sp(P2,'Pmeas_p2p'); ...
          field_or_nan_sp(P0,'PTrackingError_rms') field_or_nan_sp(Pcur,'PTrackingError_rms') field_or_nan_sp(P2,'PTrackingError_rms')];
    bar(vals);grid on;set(gca,'XTickLabel',{'Vpu P2P','Pmeas P2P','P tracking RMS'});
    legend('Ki=0','Ki=0.5','Ki=2','Location','best');title('Small-power Ki comparison');
    exportgraphics(f,fullfile(outDir,'FIG_07_KI_COMPARISON.png'),'Resolution',160);close(f);
catch ME
    text_write(fullfile(outDir,'FIG_07_WARNING.txt'),getReport(ME,'basic','hyperlinks','off'));
end
end

function S=get_struct_field_sp(J,name)
if isstruct(J)&&isfield(J,name),S=J.(name);else,S=struct();end
end

function x=field_or_nan_sp(S,name)
if isstruct(S)&&isfield(S,name)
    try,x=double(S.(name));catch,x=NaN;end
else
    x=NaN;
end
end

% =========================================================================
% G30 generic legacy stats.  We deliberately do not invent labels 1~128.
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
    if numel(segX)>=64 && dur>=0.2
        [dom,~]=fft_energy(segT,segX,[0.1 5;5 20;20 32]);
    end
    rows(k,:)={k,sprintf('LegacyG30_%03d',k),m.mean,m.min,m.max,m.p2p,m.std,m.slope,dom,dt};
end
T=cell2table(rows,'VariableNames',{'Channel','Label','Mean','Min','Max','P2P','Std','Slope_per_s','DominantHz_0p1_40','MedianDt_s'});
end

function T=g30_appended_transitions(t,g)
names=fieldnames(g);
rows=cell(0,5);
for ni=1:numel(names)
    nm=names{ni};x=g.(nm);
    dx=[true abs(diff(x))>1e-10];
    idx=find(dx);
    % Prevent file-status chatter from producing huge tables.
    if numel(idx)>500,idx=idx(1:500);end
    for j=1:numel(idx)
        k=idx(j);
        if k==1,old=NaN;else,old=x(k-1);end
        rows(end+1,:)={t(k),nm,old,x(k),k}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'Time_s','Signal','OldValue','NewValue','SampleIndex'});
if ~isempty(T),T=sortrows(T,'Time_s');end
end

% =========================================================================
% Compact evidence
% =========================================================================
function C=compact_g27(t,s,dtWant)
idx=downsample_indices(t,dtWant);
C=struct();
C.t=t(idx);
fields={'Vpu','PLL','RestoreState','RestoreAlpha','Breaker','PrefApplied','Target','Pmeas','PrefEff', ...
    'PTrackingError','PProportional','PIntegral','PPIReconPred','PPIReconResidual','RawP','QIntegral', ...
    'IrefUsedMag','ImeasUsedMag','FinalIrefMag','GammaP','BaseScaleP', ...
    'CurrentLimit','ModIndex','RawModInternal','ModHeadroom','TotalSupportMag','AllowedSupportMaxAbs', ...
    'RawSupportMaxAbs','SupportEnvelope','VsupportRef','VCommandLocal','CurrentErrorNorm','ExecResidualMag', ...
    'PickupQual','ZeroQual','Severe','AdapterValid','ComponentClip','RadiusClip','PIStateClip'};
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
% Keep all legacy rows but only at 10-ms-class compact sampling.
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
% Figures from compact data
% =========================================================================
function make_figures(C,outDir)
try
    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(C.G27.t,C.G27.Vpu);grid on;xlabel('t / s');ylabel('Vpu');title('P-loop Ki=0.5 ESS2 voltage');
    subplot(3,1,2);plot(C.G27.t,C.G27.PLL);grid on;xlabel('t / s');ylabel('Hz');title('ESS2 PLL');
    subplot(3,1,3);plot(C.G27.t,C.G27.RestoreState);grid on;xlabel('t / s');ylabel('state');title('Restore state');
    exportgraphics(f,fullfile(outDir,'FIG_01_VOLTAGE_FREQUENCY_STATE.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(C.G27.t,C.G27.PrefApplied,C.G27.t,C.G27.Pmeas);grid on;
    xlabel('t / s');ylabel('pu');legend('Pref applied','P measured','Location','best');title('P-loop Ki=0.5 active-power tracking');
    subplot(3,1,2);plot(C.G27.t,C.G27.PTrackingError);grid on;xlabel('t / s');ylabel('pu');title('Pmeas - Pref tracking error');
    subplot(3,1,3);plot(C.G27.t,C.G27.IrefUsedMag,C.G27.t,C.G27.ImeasUsedMag);grid on;
    xlabel('t / s');ylabel('pu');legend('|Iref used|','|Imeas used|','Location','best');title('Current execution');
    exportgraphics(f,fullfile(outDir,'FIG_02_POWER_TRACKING_AND_CURRENT.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(C.G27.t,C.G27.PProportional,C.G27.t,C.G27.PIntegral,C.G27.t,C.G27.RawP);grid on;
    xlabel('t / s');ylabel('pu');legend('Kp*Perror','PIntegral','RawP','Location','best');title('Ki=0.5 P-PI contributions');
    subplot(3,1,2);plot(C.G27.t,C.G27.AllowedSupportMaxAbs,C.G27.t,C.G27.RawSupportMaxAbs);grid on;
    xlabel('t / s');ylabel('pu');legend('Allowed support','Raw/unselected support','Location','best');
    subplot(3,1,3);plot(C.G27.t,C.G27.CurrentLimit,C.G27.t,C.G27.ModHeadroom);grid on;
    xlabel('t / s');legend('CurrentLimit','ModHeadroom','Location','best');
    exportgraphics(f,fullfile(outDir,'FIG_03_CONTROLLER_SUPPORT_LIMITS.png'),'Resolution',160);close(f);

    if isfield(C,'eventsG27') && isfinite(C.eventsG27.targetReach)
        a=max(C.eventsG27.targetReach,C.G27.t(end)-10);
        idx=C.G27.t>=a;
        f=figure('Visible','off','Color','w');
        subplot(3,1,1);plot(C.G27.t(idx),C.G27.PrefApplied(idx),C.G27.t(idx),C.G27.Pmeas(idx));grid on;
        ylabel('P / pu');legend('Pref','Pmeas','Location','best');title('Final 10 s fixed platform');
        subplot(3,1,2);plot(C.G27.t(idx),C.G27.Vpu(idx));grid on;ylabel('Vpu');
        subplot(3,1,3);plot(C.G27.t(idx),C.G27.PLL(idx));grid on;ylabel('Hz');xlabel('t / s');
        exportgraphics(f,fullfile(outDir,'FIG_04_FINAL10S_PLATFORM.png'),'Resolution',160);close(f);
    end

    if isfield(C,'G29') && isfield(C.G29,'PCCVab_RMS_V')
        f=figure('Visible','off','Color','w');
        subplot(3,1,1);plot(C.G29.t,C.G29.PCCVab_RMS_V);grid on;xlabel('t / s');ylabel('V RMS');title('PCC voltage');
        subplot(3,1,2);plot(C.G29.t,C.G29.PCCFreq_Hz);grid on;xlabel('t / s');ylabel('Hz');title('PCC frequency');
        subplot(3,1,3);plot(C.G29.t,C.G29.Ppcc_kW,C.G29.t,C.G29.Qpcc_kvar);grid on;
        xlabel('t / s');ylabel('kW / kvar');legend('P','Q','Location','best');title('PCC power');
        exportgraphics(f,fullfile(outDir,'FIG_05_PCC_SYSTEM.png'),'Resolution',160);close(f);
    end

    f=figure('Visible','off','Color','w');
    subplot(2,1,1);plot(C.G27.t,C.G27.PPIReconResidual);grid on;
    xlabel('t / s');ylabel('pu');title('RawP - [0.06(Pref-Pmeas)+PIntegral]');
    subplot(2,1,2);plot(C.G27.t,C.G27.PIntegral);grid on;
    xlabel('t / s');ylabel('pu');title('P integral contribution');
    exportgraphics(f,fullfile(outDir,'FIG_06_PI_RECONSTRUCTION.png'),'Resolution',160);close(f);
catch ME
    text_write(fullfile(outDir,'FIGURE_WARNING.txt'),ME.message);
end
end

% =========================================================================
% Platform summary from long-format phase metrics
% =========================================================================
function S=platform_summary(T,phaseName)
S=struct();
if isempty(T),return;end
sig={'Vpu','Pmeas','PrefApplied','PTrackingError','CurrentLimit','AllowedSupportMaxAbs','RawSupportMaxAbs','PProportional','PIntegral','QIntegral','PPIReconResidual'};
for i=1:numel(sig)
    q=T(strcmp(T.Phase,phaseName)&strcmp(T.Signal,sig{i}),:);
    if isempty(q),continue;end
    nm=sig{i};
    S.([nm '_mean'])=q.Mean(1);
    S.([nm '_min'])=q.Min(1);
    S.([nm '_max'])=q.Max(1);
    S.([nm '_p2p'])=q.P2P(1);
    S.([nm '_std'])=q.Std(1);
    S.([nm '_rms'])=q.RMS(1);
    S.([nm '_slope'])=q.Slope_per_s(1);
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
else,x=default;end
end

function x=field_num(S,name,default)
if isfield(S,name)
    try,x=double(S.(name));catch,x=default;end
else,x=default;end
end

function logf(fid,varargin)
s=sprintf(varargin{:});
fprintf('%s\n',s);
fprintf(fid,'%s\n',s);
end

function text_write(path,s)
fid=fopen(path,'w','n','UTF-8');
if fid<0,error('DIRECTMAT:Write','Cannot create %s',path);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',s);
end

function json_write(path,S)
txt=jsonencode(S,'PrettyPrint',true);
text_write(path,txt);
end

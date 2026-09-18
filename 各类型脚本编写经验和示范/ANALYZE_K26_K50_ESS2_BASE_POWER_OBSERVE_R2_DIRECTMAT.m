function result = ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT(searchRoot)
% ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT
% =========================================================================
% K26_K50_CLEAN_P1 / ESS2 BASETEST fixed-small-power DirectMAT calculator.
%
% PURPOSE
%   MATLAB does the heavy numerical work directly on the current RT-LAB MAT
%   files.  It does NOT connect to RT-LAB, modify the model, or declare an
%   electrical PASS/FAIL.
%
% CURRENT FORMAL RUN
%   Runner family : ESS2_BASE_POWER_OBSERVE_R3
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
%   1) automatically finds the latest completed observe_* manifest;
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
fprintf('ESS2 BASETEST DirectMAT R2\n');
fprintf('Manifest : %s\n',run.manifestPath);
fprintf('Run dir  : %s\n',run.runDir);
fprintf('File ID  : %s\n',num2str(run.fileID,'%.0f'));
fprintf('====================================================================\n');

outDir = fullfile(run.outputAnchor,['MATLAB_DIRECTMAT_' stamp]);
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
    logf(fid,'K26_K50 / ESS2 BASETEST fixed-small-power DirectMAT R1');
    logf(fid,'Version: %s',C.version);
    logf(fid,'Manifest: %s',run.manifestPath);
    logf(fid,'Manifest status: %s',run.status);
    logf(fid,'Manifest target clock: %.9f s',run.targetClock);
    logf(fid,'Manifest first state6: %.9f s',run.firstState6);
    logf(fid,'Manifest file ID: %.0f',run.fileID);
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

    evt = detect_g27_events(t,s,run);
    Tevt27 = struct2eventtable(evt,'G27');
    writetable(Tevt27,fullfile(outDir,'03A_G27_EVENT_TIMELINE.csv'));

    logf(fid,'G27 coverage: %.6f -> %.6f s (%d samples)',t(1),t(end),numel(t));
    logf(fid,'G27 breaker close: %s',fmt_time(evt.breakerClose));
    logf(fid,'G27 state5:       %s',fmt_time(evt.state5));
    logf(fid,'G27 state6:       %s',fmt_time(evt.state6));
    logf(fid,'G27 alpha=1:      %s',fmt_time(evt.alphaOpen));
    logf(fid,'G27 Pref starts:  %s',fmt_time(evt.prefStart));
    logf(fid,'G27 target reach: %s',fmt_time(evt.targetReach));

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
    result.status = 'CALCULATION_COMPLETE_NO_ELECTRICAL_VERDICT';
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
    result.actualMatVariables = struct('G27',var27,'G29',var29,'G30',var30);
    result.note = ['Descriptive numerical evidence only. Upload the compact ZIP; ' ...
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

    fprintf('\nDirectMAT calculation complete.\n');
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
C.version = 'K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT_20260916';
C.defaultRunRoot = 'D:\E2RUN';
C.defaultModelRoot = ['D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\' ...
    'yanshou_V7\models\K26_K50_CLEAN_P1'];
C.expectedRunnerPrefix = 'ESS2_BASE_POWER_OBSERVE_R3';
C.expectedRows.G27 = 120;
C.expectedRows.G29 = 75;
C.expectedRows.G30 = 145;
C.expectedVar.G27 = 'rootdiag_ess2_data';
C.expectedVar.G29 = 'd1_gfm_superpack_data';
C.expectedVar.G30 = 'freqdiag_ess1_data';
C.window_s = 2.0;
C.compact_dt_s = 0.010;
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
            dd=dir(fullfile(roots{r},'observe_*','manifest.json'));
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
        'Expected e.g. D:\E2RUN\observe_*\manifest.json.'],C.expectedRunnerPrefix);
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
P(end+1)=phase('BASE_OPEN_P0',E.alphaOpen,E.prefStart);
P(end+1)=phase('POWER_RAMP',E.prefStart,E.targetReach);
P(end+1)=phase('FIXED_PLATFORM',E.targetReach,t(end));
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
    'Vpu','PLL','PrefApplied','Target','Pmeas','PrefEff','PIntegral','QIntegral', ...
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
wantPhases={'BASE_OPEN_P0','FIXED_PLATFORM'};
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
    'PIntegral','QIntegral','IrefUsedMag','ImeasUsedMag','FinalIrefMag','GammaP','BaseScaleP', ...
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
    subplot(3,1,1);plot(C.G27.t,C.G27.Vpu);grid on;xlabel('t / s');ylabel('Vpu');title('ESS2 voltage');
    subplot(3,1,2);plot(C.G27.t,C.G27.PLL);grid on;xlabel('t / s');ylabel('Hz');title('ESS2 PLL');
    subplot(3,1,3);plot(C.G27.t,C.G27.RestoreState);grid on;xlabel('t / s');ylabel('state');title('Restore state');
    exportgraphics(f,fullfile(outDir,'FIG_01_VOLTAGE_FREQUENCY_STATE.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(C.G27.t,C.G27.PrefApplied,C.G27.t,C.G27.Pmeas);grid on;
    xlabel('t / s');ylabel('pu');legend('Pref applied','P measured','Location','best');title('ESS2 active power');
    subplot(3,1,2);plot(C.G27.t,C.G27.PIntegral);grid on;xlabel('t / s');ylabel('pu');title('Power PI integral output');
    subplot(3,1,3);plot(C.G27.t,C.G27.IrefUsedMag,C.G27.t,C.G27.ImeasUsedMag);grid on;
    xlabel('t / s');ylabel('pu');legend('|Iref used|','|Imeas used|','Location','best');title('Current execution');
    exportgraphics(f,fullfile(outDir,'FIG_02_POWER_AND_CURRENT.png'),'Resolution',160);close(f);

    f=figure('Visible','off','Color','w');
    subplot(3,1,1);plot(C.G27.t,C.G27.AllowedSupportMaxAbs,C.G27.t,C.G27.RawSupportMaxAbs);grid on;
    xlabel('t / s');ylabel('pu');legend('Allowed support max abs','Raw/unselected support max abs','Location','best');
    title('BASETEST support isolation');
    subplot(3,1,2);plot(C.G27.t,C.G27.CurrentLimit,C.G27.t,C.G27.ModHeadroom);grid on;
    xlabel('t / s');legend('CurrentLimit','ModHeadroom','Location','best');
    subplot(3,1,3);plot(C.G27.t,C.G27.CurrentErrorNorm,C.G27.t,C.G27.ExecResidualMag);grid on;
    xlabel('t / s');legend('Current error norm','Execution residual magnitude','Location','best');
    exportgraphics(f,fullfile(outDir,'FIG_03_SUPPORT_AND_EXECUTION.png'),'Resolution',160);close(f);

    if isfield(C,'G29') && isfield(C.G29,'PCCVab_RMS_V')
        f=figure('Visible','off','Color','w');
        subplot(3,1,1);plot(C.G29.t,C.G29.PCCVab_RMS_V);grid on;xlabel('t / s');ylabel('V RMS');title('PCC voltage');
        subplot(3,1,2);plot(C.G29.t,C.G29.PCCFreq_Hz);grid on;xlabel('t / s');ylabel('Hz');title('PCC frequency');
        subplot(3,1,3);plot(C.G29.t,C.G29.Ppcc_kW,C.G29.t,C.G29.Qpcc_kvar);grid on;
        xlabel('t / s');ylabel('kW / kvar');legend('P','Q','Location','best');title('PCC power');
        exportgraphics(f,fullfile(outDir,'FIG_04_PCC_SYSTEM.png'),'Resolution',160);close(f);
    end
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
sig={'Vpu','Pmeas','PrefApplied','PTrackingError','CurrentLimit','AllowedSupportMaxAbs','RawSupportMaxAbs','PIntegral'};
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

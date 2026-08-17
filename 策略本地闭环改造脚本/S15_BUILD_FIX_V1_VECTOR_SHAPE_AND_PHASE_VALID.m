function S15_BUILD_FIX_V1_VECTOR_SHAPE_AND_PHASE_VALID
% S15_BUILD_FIX_V1_VECTOR_SHAPE_AND_PHASE_VALID
%
% Minimal repair for the first RT-LAB Build failure observed after S15 V2.
%
% Evidence-driven fixes only:
%   A) Advanced_Strategy_Core produces st/al/mt/cmd as zeros(1,15), i.e.
%      MATLAB 2-D row vectors [1x15], while RT-LAB code generation reports
%      Simulink backward propagation as 1-D [15].
%      This script DOES NOT change the original strategy algorithm.
%      It inserts four explicit Reshape adapters immediately after the
%      MATLAB Function outputs:
%
%          [1x15] -> Reshape(1-D array) -> [15]
%
%      so the MATLAB Function keeps its original semantics and the external
%      LOCAL15 interface remains the existing 15-element 1-D vector.
%
%   B) S15 V2 created FROM_REC_27 = AA15_S15_PHASE_VALID but its connection
%      loop used 1:26, leaving Recovery Core input27 undriven.
%      This script connects FROM_REC_27 -> Recovery Core input27.
%
% It does NOT:
%   - change any S1...S15 formulas;
%   - change Pref/Qref/Droop/GridOn/Breaker semantics;
%   - change S15 recovery thresholds or state machine;
%   - run RT-LAB Build.
%
% Project rule:
%   mdl = bdroot(gcs)

fprintf('\n============================================================\n');
fprintf(' S15 BUILD FIX V1 - Vector Shape + Phase Valid\n');
fprintf('============================================================\n');

mdl = bdroot(gcs);
if isempty(mdl)
    error('S15FIX:NoModel', ...
        'Open K26_V5 and click inside the model before running this script.');
end
load_system(mdl);

sm = [mdl '/SM_Master'];
strategy = [sm '/Advanced_Microgrid_15_Strategies'];
core = [strategy '/Advanced_Strategy_Core'];
rec = [sm '/AA15_LOCAL_CONTROL_STACK/AA15_S15_Recovery_Manager'];
recCore = [rec '/AA15_S15_Recovery_Core'];
from27 = [rec '/FROM_REC_27'];

required = {sm,strategy,core,rec,recCore,from27};
for i = 1:numel(required)
    if getSimulinkBlockHandle(required{i}) < 0
        error('S15FIX:MissingBlock','Missing required block: %s',required{i});
    end
end

modelFile = get_param(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('S15FIX:ModelFile','Cannot resolve active model file.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
[modelDir,modelBase,modelExt] = fileparts(modelFile);
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_S15_BUILD_FIX_V1_%s%s',modelBase,stamp,modelExt));
copyfile(modelFile,backupFile,'f');

fprintf('Model  : %s\n',mdl);
fprintf('Backup : %s\n',backupFile);

% -------------------------------------------------------------------------
% 1. Preflight original strategy interface
% -------------------------------------------------------------------------
fprintf('\n--- 1. Preflight Advanced_Strategy_Core interface ---\n');

corePH = get_param(core,'PortHandles');
if numel(corePH.Outport) ~= 4
    error('S15FIX:CorePorts', ...
        'Advanced_Strategy_Core expected 4 outputs, found %d.',numel(corePH.Outport));
end

outNames = {'strategy_status','strategy_alarm','strategy_metric','strategy_cmd'};
reshapeNames = { ...
    'AA15_RTLCG_RESHAPE_STATUS15', ...
    'AA15_RTLCG_RESHAPE_ALARM15', ...
    'AA15_RTLCG_RESHAPE_METRIC15', ...
    'AA15_RTLCG_RESHAPE_CMD15'};

for i = 1:4
    op = [strategy '/' outNames{i}];
    if getSimulinkBlockHandle(op) < 0 || ~strcmp(get_param(op,'BlockType'),'Outport')
        error('S15FIX:Outport','Missing expected strategy Outport: %s',op);
    end
end

% -------------------------------------------------------------------------
% 2. Insert explicit row-matrix -> 1-D vector adapters
% -------------------------------------------------------------------------
fprintf('\n--- 2. Insert four 1-D Reshape adapters ---\n');

corePos = get_param(core,'Position');

for i = 1:4
    op = [strategy '/' outNames{i}];
    rp = [strategy '/' reshapeNames{i}];

    opPH = get_param(op,'PortHandles');
    if isempty(opPH.Inport)
        error('S15FIX:OutportHandle','No input handle for %s.',op);
    end

    ln = get_param(opPH.Inport(1),'Line');
    if isequal(ln,-1)
        error('S15FIX:OutportUndriven','%s is undriven.',op);
    end

    srcPort = get_param(ln,'SrcPortHandle');
    srcPath = getfullname(get_param(srcPort,'Parent'));

    if strcmp(srcPath,core)
        % Clean pre-fix state: direct Core -> parent Outport.
        dstPorts = get_param(ln,'DstPortHandle');
        dstPorts = dstPorts(dstPorts >= 0);
        if numel(dstPorts) ~= 1 || dstPorts(1) ~= opPH.Inport(1)
            error('S15FIX:SharedStrategyOutput', ...
                ['Core output%d direct line has unexpected fan-out. ' ...
                 'Refusing whole-line deletion.'],i);
        end

        if getSimulinkBlockHandle(rp) >= 0
            error('S15FIX:UnexpectedReshape', ...
                'Reshape block exists but %s is still driven directly by Core: %s', ...
                outNames{i},rp);
        end

        opPos = get_param(op,'Position');
        x1 = corePos(3) + 35;
        x2 = opPos(1) - 35;
        if x2 - x1 < 70
            x1 = round((corePos(3)+opPos(1))/2)-30;
            x2 = x1 + 60;
        end
        ymid = round((opPos(2)+opPos(4))/2);
        rpos = [x1 ymid-16 x2 ymid+16];

        localAddReshapeBlock(rp,rpos);
        localSetOneDimensional(rp);

        % Delete only the verified single-destination direct line.
        delete_line(ln);

        rPH = get_param(rp,'PortHandles');
        add_line(strategy,corePH.Outport(i),rPH.Inport(1),'autorouting','on');
        add_line(strategy,rPH.Outport(1),opPH.Inport(1),'autorouting','on');

        fprintf('[FIX] Core out%d -> %s -> %s\n', ...
            i,reshapeNames{i},outNames{i});

    elseif strcmp(srcPath,rp)
        % Idempotent rerun: verify existing adapter.
        localSetOneDimensional(rp);
        rPH = get_param(rp,'PortHandles');

        inLine = get_param(rPH.Inport(1),'Line');
        if isequal(inLine,-1) || get_param(inLine,'SrcPortHandle') ~= corePH.Outport(i)
            error('S15FIX:ReshapeInput', ...
                '%s input is not driven by Core output%d.',rp,i);
        end

        fprintf('[KEEP] %s already inserted for %s.\n',reshapeNames{i},outNames{i});

    else
        error('S15FIX:UnexpectedStrategySource', ...
            '%s source is %s; expected Core or repair Reshape.',outNames{i},srcPath);
    end
end

% -------------------------------------------------------------------------
% 3. Repair S15 Recovery Core input27
% -------------------------------------------------------------------------
fprintf('\n--- 3. Repair Recovery Core input27 = AA15_S15_PHASE_VALID ---\n');

if ~strcmp(get_param(from27,'BlockType'),'From')
    error('S15FIX:From27Type','%s is not a From block.',from27);
end
if ~strcmp(get_param(from27,'GotoTag'),'AA15_S15_PHASE_VALID')
    error('S15FIX:From27Tag', ...
        'FROM_REC_27 tag=%s, expected AA15_S15_PHASE_VALID.', ...
        get_param(from27,'GotoTag'));
end

recPH = get_param(recCore,'PortHandles');
if numel(recPH.Inport) ~= 30
    error('S15FIX:RecoveryPorts', ...
        'Recovery Core expected 30 inputs, found %d.',numel(recPH.Inport));
end

fPH = get_param(from27,'PortHandles');
dst27 = recPH.Inport(27);
ln27 = get_param(dst27,'Line');

if isequal(ln27,-1)
    add_line(rec,fPH.Outport(1),dst27,'autorouting','on');
    fprintf('[FIX] FROM_REC_27 -> Recovery Core input27.\n');
else
    src27 = get_param(ln27,'SrcPortHandle');
    if src27 ~= fPH.Outport(1)
        srcPath27 = getfullname(get_param(src27,'Parent'));
        error('S15FIX:Input27Busy', ...
            'Recovery Core input27 is already driven by unexpected source: %s', ...
            srcPath27);
    end
    fprintf('[KEEP] Recovery Core input27 already correctly connected.\n');
end

% -------------------------------------------------------------------------
% 4. Normal Simulink update and exact post-assertions
% -------------------------------------------------------------------------
fprintf('\n--- 4. Model update + post-assertions ---\n');

set_param(mdl,'SimulationCommand','update');
fprintf('[PASS] SimulationCommand update succeeded.\n');

% Four external strategy outputs must now be driven by the four reshapes.
for i = 1:4
    op = [strategy '/' outNames{i}];
    rp = [strategy '/' reshapeNames{i}];

    if getSimulinkBlockHandle(rp) < 0
        error('S15FIX:ReshapeMissing','Missing %s after update.',rp);
    end

    opPH = get_param(op,'PortHandles');
    ln = get_param(opPH.Inport(1),'Line');
    if isequal(ln,-1)
        error('S15FIX:PostOutportUndriven','%s undriven after update.',op);
    end

    sp = get_param(ln,'SrcPortHandle');
    if ~strcmp(getfullname(get_param(sp,'Parent')),rp)
        error('S15FIX:PostOutportSource', ...
            '%s is not driven by %s after update.',op,rp);
    end
end

% Recovery input27 exact source.
recPH = get_param(recCore,'PortHandles');
ln27 = get_param(recPH.Inport(27),'Line');
if isequal(ln27,-1) || get_param(ln27,'SrcPortHandle') ~= fPH.Outport(1)
    error('S15FIX:PostInput27','Recovery Core input27 repair did not persist.');
end

% Protect Group28/S15 structure.
g28 = [sm '/AA15_GROUP28_MUX'];
if getSimulinkBlockHandle(g28) < 0 || ...
        str2double(get_param(g28,'Inputs')) ~= 13
    error('S15FIX:Group28','Group28 is not still at 13 physical inputs.');
end

s15Diag = [sm '/AA15_STAGE15_RECOVERY_DIAGNOSTICS'];
if getSimulinkBlockHandle(s15Diag) < 0
    error('S15FIX:S15Diag','S15 recovery diagnostics missing.');
end

save_system(mdl);

fprintf('\n============================================================\n');
fprintf(' S15 BUILD FIX V1 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Original 15-strategy formulas : UNCHANGED\n');
fprintf('Strategy interface fix        : 4x explicit 1-D Reshape\n');
fprintf('S15 phase_valid fix           : Recovery Core input27 CONNECTED\n');
fprintf('Group28                       : still 13 physical inputs\n');
fprintf('Backup                        : %s\n',backupFile);
fprintf('\nNEXT ACTION:\n');
fprintf('  RT-LAB -> Rebuild All\n');
fprintf('If Build fails again, stop and capture the FIRST new error only.\n');

end


function localAddReshapeBlock(dst,pos)
candidates = { ...
    'simulink/Math Operations/Reshape', ...
    'simulink/Signal Attributes/Reshape'};

lastErr = [];
for i = 1:numel(candidates)
    try
        add_block(candidates{i},dst,'Position',pos);
        return;
    catch ME
        lastErr = ME;
    end
end

if isempty(lastErr)
    error('S15FIX:ReshapeLibrary','Could not locate a Simulink Reshape block.');
else
    error('S15FIX:ReshapeLibrary', ...
        'Could not add a Simulink Reshape block. Last error: %s',lastErr.message);
end
end


function localSetOneDimensional(blk)
dp = get_param(blk,'DialogParameters');

if isstruct(dp) && isfield(dp,'OutputDimensionality')
    vals = {'1-D array','1-D array (one-dimensional)','1-D'};
    for i = 1:numel(vals)
        try
            set_param(blk,'OutputDimensionality',vals{i});
            return;
        catch
        end
    end
end

% Fallback for releases/variants exposing a direct dimensions field.
if isstruct(dp) && isfield(dp,'OutputDimensions')
    try
        set_param(blk,'OutputDimensions','[15]');
        return;
    catch
    end
end

error('S15FIX:ReshapeParameter', ...
    'Could not configure %s as a 1-D 15-element output.',blk);
end

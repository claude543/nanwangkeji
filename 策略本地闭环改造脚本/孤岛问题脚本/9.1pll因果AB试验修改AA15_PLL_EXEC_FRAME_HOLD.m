function PATCH_K26_V5_FIVE_GFL_PLL_WRAPPER_FRAME_HOLD_CAUSAL_B_V1
% PATCH_K26_V5_FIVE_GFL_PLL_WRAPPER_FRAME_HOLD_CAUSAL_B_V1
%
% IMPORTANT DESIGN CHANGE
% -----------------------
% This patch DOES NOT modify the inside of the MathWorks-linked PLL (3ph).
% It does NOT disable the PLL library link.
% It does NOT modify spsPLL3phLib.
%
% Instead, it modifies only the USER-EDITABLE Measurements wrapper around
% each PLL:
%
%   native PLL outputs
%       Freq_native, theta_native
%             |
%             +-----------------------> raw diagnostic Outports 9/10
%             |
%             v
%      AA15_PLL_EXEC_FRAME_HOLD
%             |
%             +--> existing internal tags [Freq_PLL]/[theta_PLL]
%             |    -> existing abc->dq / P,Q / Current Regulator paths
%             |
%             +--> NEW Measurements outputs 11/12
%                  -> parent GFL execution thetaF/FreqF
%
% Parent RootDiag remains connected to the RAW native PLL outputs 9/10.
% Therefore the existing 24-scalar OpWrite map is NOT resized:
%
%   raw wt_PLL/Freq_PLL  = existing diag rows 21/22
%   selected wt/Freq     = existing diag rows 10/8
%
% This gives a direct B-experiment proof that:
%   native PLL may continue to move,
%   while the execution frame is held/free-running.
%
% CAUSAL INTERVENTION
% -------------------
% Before T_HOLD:
%   Freq_exec  = Freq_native
%   theta_exec = theta_native
%
% At/after T_HOLD:
%   Freq_exec[n]  = last tracked native frequency
%   theta_exec[n] = theta_exec[n-1] + 2*pi*Freq_exec[n]*Ts
%
% So angle is NOT frozen.
% It continues rotating continuously at the last pre-J1 tracked frequency.
%
% T_HOLD = 8.1894 s, about 20 ms before expected J1 first-open 8.2094 s.
%
% SCIENTIFIC PURPOSE
% ------------------
% Remove only:
%   PCC error -> local PLL dynamic correction -> GFL EXECUTION frame
%
% while preserving:
%   topology, five GFL roles, ESS1 GFM, P/Q commands, Current PI,
%   Power Control, F24/F25, network, PWM, DC side, and native PLL itself.
%
% STRICT TRANSACTION
% ------------------
% - read-only preflight before first edit
% - exact model backup
% - no PLL link manipulation
% - standard Simulink blocks only
% - no MATLAB Function / Stateflow
% - update -> postassert -> save once -> close/reload audit
% - rollback exact backup on any failure
%
% OPWRITE
% -------
% No OpWrite is added, removed, or resized.
%
% RUN
% ---
% 1) Open current canonical K26_V5.slx.
% 2) Save it first (Dirty=off).
% 3) Click inside the model.
% 4) Run:
%      PATCH_K26_V5_FIVE_GFL_PLL_WRAPPER_FRAME_HOLD_CAUSAL_B_V1
%
% Do NOT Build unless script prints PATCH PASS.
%
% 2026-09-01
% -------------------------------------------------------------------------

clc;

T_HOLD = 8.1894;
TS_EXPR = 'Ts';

mdl = bdroot(gcs);
if isempty(mdl)
    error('PLLWRAPB:NoModel','Open K26_V5 and click inside it first.');
end
load_system(mdl);

if ~contains(mdl,'K26_V5')
    error('PLLWRAPB:WrongModel','Expected K26_V5, got %s.',mdl);
end

if ~strcmpi(localGet(mdl,'Dirty'),'off')
    error('PLLWRAPB:Dirty','Model must be saved / Dirty=off before patch.');
end

modelFile = localGet(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('PLLWRAPB:ModelFile','Cannot resolve current K26_V5 file.');
end

fprintf('\n====================================================================================================\n');
fprintf(' K26_V5 FIVE-GFL PLL WRAPPER EXEC-FRAME HOLD CAUSAL B PATCH V1\n');
fprintf('====================================================================================================\n');
fprintf('Model       : %s\n',mdl);
fprintf('File        : %s\n',modelFile);
fprintf('Dirty       : %s\n',localGet(mdl,'Dirty'));
fprintf('T_HOLD      : %.7f s\n',T_HOLD);
fprintf('Expected J1 : ~8.2094000 s\n');
fprintf('Lead        : ~%.3f ms\n',(8.2094-T_HOLD)*1000);
fprintf('PLL internals/library links WILL NOT be modified.\n');

spec = {
    'PV1',  [mdl '/SS_Slave3/PV1_Control'];
    'PV2',  [mdl '/SS_Slave3/PV2_Control'];
    'ESS2', [mdl '/SS_Slave2/ESS2_Control'];
    'EV1',  [mdl '/SS_Slave/EV1_Control'];
    'EV2',  [mdl '/SS_Slave/Control System'];
};

%% =========================================================================
% 1. STRICT READ-ONLY PREFLIGHT
% ==========================================================================
fprintf('\n--- 1. STRICT READ-ONLY PREFLIGHT ---\n');

R = struct([]);

for k = 1:size(spec,1)
    dev  = spec{k,1};
    ctrl = spec{k,2};
    meas = [ctrl '/Measurements'];

    localReq(ctrl);
    localReq(meas);

    pll = localResolveRealPLL(meas);

    % Must remain linked/resolved; this patch never touches it.
    if ~strcmpi(localGet(pll,'LinkStatus'),'resolved')
        error('PLLWRAPB:PLLLink', ...
            '%s PLL LinkStatus expected resolved; got %s.', ...
            dev,localGet(pll,'LinkStatus'));
    end

    gFreq = [meas '/Goto1'];
    gTheta= [meas '/Goto2'];
    oWt   = [meas '/wt_PLL'];
    oFreq = [meas '/Freq_PLL'];

    localReq(gFreq); localReq(gTheta); localReq(oWt); localReq(oFreq);

    if ~strcmp(localGet(gFreq,'BlockType'),'Goto') || ...
       ~strcmp(localGet(gFreq,'GotoTag'),'Freq_PLL')
        error('PLLWRAPB:FreqGoto', ...
            '%s expected Measurements/Goto1 tag Freq_PLL.',dev);
    end

    if ~strcmp(localGet(gTheta,'BlockType'),'Goto') || ...
       ~strcmp(localGet(gTheta,'GotoTag'),'theta_PLL')
        error('PLLWRAPB:ThetaGoto', ...
            '%s expected Measurements/Goto2 tag theta_PLL.',dev);
    end

    if ~strcmp(localGet(oWt,'BlockType'),'Outport') || ...
       ~strcmp(localGet(oWt,'Port'),'9')
        error('PLLWRAPB:WtOut','%s wt_PLL expected Outport 9.',dev);
    end

    if ~strcmp(localGet(oFreq,'BlockType'),'Outport') || ...
       ~strcmp(localGet(oFreq,'Port'),'10')
        error('PLLWRAPB:FreqOut','%s Freq_PLL expected Outport 10.',dev);
    end

    % Exact native PLL output destination contract in Measurements wrapper.
    phPLL = get_param(pll,'PortHandles');
    if numel(phPLL.Outport) < 2
        error('PLLWRAPB:PLLOut','%s PLL has fewer than 2 outputs.',dev);
    end

    dstFreq = sort(localDestTuples(phPLL.Outport(1)));
    dstTheta= sort(localDestTuples(phPLL.Outport(2)));

    expFreq = sort({
        sprintf('%s|1',gFreq);
        sprintf('%s|1',oFreq)
    });

    expTheta = sort({
        sprintf('%s|1',gTheta);
        sprintf('%s|1',oWt)
    });

    if ~isequal(dstFreq(:),expFreq(:))
        localPrintTupleMismatch(dev,'PLL Freq out',dstFreq,expFreq);
        error('PLLWRAPB:FreqNativeDest', ...
            '%s PLL Freq native destinations differ from audited contract.',dev);
    end

    if ~isequal(dstTheta(:),expTheta(:))
        localPrintTupleMismatch(dev,'PLL theta out',dstTheta,expTheta);
        error('PLLWRAPB:ThetaNativeDest', ...
            '%s PLL theta native destinations differ from audited contract.',dev);
    end

    % Parent execution / RootDiag contract.
    gThetaParent = [ctrl '/Goto16'];
    gFreqParent  = [ctrl '/Goto17'];
    rootMux      = [ctrl '/AA15_ROOTDIAG_MUX21PORT_24SCALAR'];

    localReq(gThetaParent); localReq(gFreqParent); localReq(rootMux);

    if ~strcmp(localGet(gThetaParent,'GotoTag'),'thetaF')
        error('PLLWRAPB:ThetaParentTag','%s parent Goto16 tag unexpected.',dev);
    end
    if ~strcmp(localGet(gFreqParent,'GotoTag'),'FreqF')
        error('PLLWRAPB:FreqParentTag','%s parent Goto17 tag unexpected.',dev);
    end

    phMeas = get_param(meas,'PortHandles');
    if numel(phMeas.Outport) ~= 10
        error('PLLWRAPB:MeasPorts', ...
            '%s Measurements expected exactly 10 outputs before patch; got %d.', ...
            dev,numel(phMeas.Outport));
    end

    dstWtParent = sort(localDestTuples(phMeas.Outport(9)));
    dstFParent  = sort(localDestTuples(phMeas.Outport(10)));

    expWtParent = sort({
        sprintf('%s|1',gThetaParent);
        sprintf('%s|19',rootMux)
    });

    expFParent = sort({
        sprintf('%s|1',gFreqParent);
        sprintf('%s|20',rootMux)
    });

    if ~isequal(dstWtParent(:),expWtParent(:))
        localPrintTupleMismatch(dev,'Measurements out9 wt_PLL',dstWtParent,expWtParent);
        error('PLLWRAPB:WtParentDest', ...
            '%s Measurements out9 topology differs from audited contract.',dev);
    end

    if ~isequal(dstFParent(:),expFParent(:))
        localPrintTupleMismatch(dev,'Measurements out10 Freq_PLL',dstFParent,expFParent);
        error('PLLWRAPB:FParentDest', ...
            '%s Measurements out10 topology differs from audited contract.',dev);
    end

    % No patch collisions.
    collisionNames = {
        [meas '/AA15_PLL_EXEC_FRAME_HOLD'];
        [meas '/AA15_PLL_NATIVE_FREQ_GOTO'];
        [meas '/AA15_PLL_NATIVE_THETA_GOTO'];
        [meas '/AA15_PLL_NATIVE_FREQ_TO_EXEC'];
        [meas '/AA15_PLL_NATIVE_THETA_TO_EXEC'];
        [meas '/AA15_PLL_NATIVE_FREQ_TO_RAW_OUT'];
        [meas '/AA15_PLL_NATIVE_THETA_TO_RAW_OUT'];
        [meas '/AA15_PLL_EXEC_FREQ_TO_OUT'];
        [meas '/AA15_PLL_EXEC_THETA_TO_OUT'];
        [meas '/wt_PLL_EXEC'];
        [meas '/Freq_PLL_EXEC']
    };

    for c = 1:numel(collisionNames)
        if getSimulinkBlockHandle(collisionNames{c}) >= 0
            error('PLLWRAPB:Collision', ...
                '%s patch collision: %s',dev,collisionNames{c});
        end
    end

    R(k).dev = dev; %#ok<AGROW>
    R(k).ctrl = ctrl;
    R(k).meas = meas;
    R(k).pll = pll;
    R(k).gFreq = gFreq;
    R(k).gTheta = gTheta;
    R(k).oWt = oWt;
    R(k).oFreq = oFreq;
    R(k).gThetaParent = gThetaParent;
    R(k).gFreqParent = gFreqParent;
    R(k).rootMux = rootMux;

    fprintf('[PASS] %-4s wrapper/native/raw-diagnostic contract exact.\n',dev);
end

% OpWrite count frozen.
opw0 = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
    'Regexp','on','Name','.*OpWrite.*');
fprintf('[INFO] Existing OpWrite-like count = %d; patch will not change it.\n',numel(opw0));

if ~strcmpi(localGet(mdl,'Dirty'),'off')
    error('PLLWRAPB:PreflightDirty','Preflight changed Dirty state unexpectedly.');
end

%% =========================================================================
% 2. EXACT BACKUP
% ==========================================================================
fprintf('\n--- 2. EXACT BACKUP ---\n');

[folder,base,ext] = fileparts(modelFile);
stamp = datestr(now,'yyyymmdd_HHMMSS');
backupFile = fullfile(folder, ...
    sprintf('%s__PRE_PLL_WRAPPER_FRAME_HOLD_B_V1_%s%s',base,stamp,ext));

[ok,msg] = copyfile(modelFile,backupFile,'f');
if ~ok
    error('PLLWRAPB:Backup','Backup failed: %s',msg);
end
fprintf('[PASS] Backup = %s\n',backupFile);

%% =========================================================================
% 3. EDIT: USER-EDITABLE MEASUREMENTS WRAPPERS ONLY
% ==========================================================================
fprintf('\n--- 3. EDIT MEASUREMENTS WRAPPERS ONLY ---\n');

try
    for k = 1:numel(R)
        dev = R(k).dev;
        meas = R(k).meas;
        pll = R(k).pll;

        fprintf('\n[%s] inserting wrapper-level causal frame hold...\n',dev);

        % Reconfirm PLL library link remains resolved before edit.
        if ~strcmpi(localGet(pll,'LinkStatus'),'resolved')
            error('PLLWRAPB:PreEditPLLLink', ...
                '%s PLL link unexpectedly changed.',dev);
        end

        % Delete the two existing branched native output lines.
        phPLL = get_param(pll,'PortHandles');
        lnF = get_param(phPLL.Outport(1),'Line');
        lnT = get_param(phPLL.Outport(2),'Line');

        if lnF < 0 || lnT < 0
            error('PLLWRAPB:NativeLines','%s native PLL output lines missing.',dev);
        end

        delete_line(lnF);
        delete_line(lnT);

        % -----------------------------------------------------------------
        % Native signal local tags:
        % PLL block remains untouched and continues computing natively.
        % -----------------------------------------------------------------
        gNativeF = [meas '/AA15_PLL_NATIVE_FREQ_GOTO'];
        gNativeT = [meas '/AA15_PLL_NATIVE_THETA_GOTO'];

        add_block('simulink/Signal Routing/Goto',gNativeF, ...
            'GotoTag','AA15_PLL_NATIVE_FREQ', ...
            'TagVisibility','local', ...
            'Position',[520 70 610 90]);

        add_block('simulink/Signal Routing/Goto',gNativeT, ...
            'GotoTag','AA15_PLL_NATIVE_THETA', ...
            'TagVisibility','local', ...
            'Position',[520 115 610 135]);

        localConnect(meas, ...
            get_param(pll,'PortHandles').Outport(1), ...
            get_param(gNativeF,'PortHandles').Inport(1));

        localConnect(meas, ...
            get_param(pll,'PortHandles').Outport(2), ...
            get_param(gNativeT,'PortHandles').Inport(1));

        % Raw native signal -> existing diagnostic outputs 9/10.
        fRaw = [meas '/AA15_PLL_NATIVE_FREQ_TO_RAW_OUT'];
        tRaw = [meas '/AA15_PLL_NATIVE_THETA_TO_RAW_OUT'];

        add_block('simulink/Signal Routing/From',fRaw, ...
            'GotoTag','AA15_PLL_NATIVE_FREQ', ...
            'Position',[650 60 750 80]);

        add_block('simulink/Signal Routing/From',tRaw, ...
            'GotoTag','AA15_PLL_NATIVE_THETA', ...
            'Position',[650 105 750 125]);

        localConnect(meas, ...
            get_param(fRaw,'PortHandles').Outport(1), ...
            get_param(R(k).oFreq,'PortHandles').Inport(1));

        localConnect(meas, ...
            get_param(tRaw,'PortHandles').Outport(1), ...
            get_param(R(k).oWt,'PortHandles').Inport(1));

        % Native signal -> execution frame hold manager.
        fExecIn = [meas '/AA15_PLL_NATIVE_FREQ_TO_EXEC'];
        tExecIn = [meas '/AA15_PLL_NATIVE_THETA_TO_EXEC'];

        add_block('simulink/Signal Routing/From',fExecIn, ...
            'GotoTag','AA15_PLL_NATIVE_FREQ', ...
            'Position',[650 165 750 185]);

        add_block('simulink/Signal Routing/From',tExecIn, ...
            'GotoTag','AA15_PLL_NATIVE_THETA', ...
            'Position',[650 210 750 230]);

        holdSS = [meas '/AA15_PLL_EXEC_FRAME_HOLD'];
        localCreateExecFrameHoldSubsystem(holdSS,T_HOLD,TS_EXPR);

        phHold = get_param(holdSS,'PortHandles');

        localConnect(meas, ...
            get_param(fExecIn,'PortHandles').Outport(1), ...
            phHold.Inport(1));

        localConnect(meas, ...
            get_param(tExecIn,'PortHandles').Outport(1), ...
            phHold.Inport(2));

        % Execution frame outputs -> existing local tags [Freq_PLL]/[theta_PLL].
        localConnect(meas,phHold.Outport(1), ...
            get_param(R(k).gFreq,'PortHandles').Inport(1));

        localConnect(meas,phHold.Outport(2), ...
            get_param(R(k).gTheta,'PortHandles').Inport(1));

        % NEW exec outputs 11/12 for parent control.
        oWtExec   = [meas '/wt_PLL_EXEC'];
        oFreqExec = [meas '/Freq_PLL_EXEC'];

        add_block('built-in/Outport',oWtExec, ...
            'Port','11','Position',[1110 155 1140 175]);

        add_block('built-in/Outport',oFreqExec, ...
            'Port','12','Position',[1110 200 1140 220]);

        tExecOut = [meas '/AA15_PLL_EXEC_THETA_TO_OUT'];
        fExecOut = [meas '/AA15_PLL_EXEC_FREQ_TO_OUT'];

        add_block('simulink/Signal Routing/From',tExecOut, ...
            'GotoTag','theta_PLL', ...
            'Position',[960 155 1060 175]);

        add_block('simulink/Signal Routing/From',fExecOut, ...
            'GotoTag','Freq_PLL', ...
            'Position',[960 200 1060 220]);

        localConnect(meas, ...
            get_param(tExecOut,'PortHandles').Outport(1), ...
            get_param(oWtExec,'PortHandles').Inport(1));

        localConnect(meas, ...
            get_param(fExecOut,'PortHandles').Outport(1), ...
            get_param(oFreqExec,'PortHandles').Inport(1));

        R(k).holdSS = holdSS;
        R(k).oWtExec = oWtExec;
        R(k).oFreqExec = oFreqExec;

        fprintf('[EDIT] %-4s Measurements wrapper modified; PLL block untouched.\n',dev);
    end

    % Update once so parent Measurements blocks acquire outputs 11/12.
    fprintf('\n--- 4. UPDATE AFTER WRAPPER PORT ADDITION ---\n');
    set_param(mdl,'SimulationCommand','update');
    fprintf('[PASS] update after adding Measurements outputs 11/12.\n');

    %% =========================================================================
    % 5. PARENT REWIRE:
    %    raw PLL outputs -> RootDiag
    %    exec PLL outputs -> thetaF/FreqF execution tags
    % ==========================================================================
    fprintf('\n--- 5. PARENT RAW-vs-EXEC REWIRE ---\n');

    for k = 1:numel(R)
        dev = R(k).dev;
        meas = R(k).meas;

        phMeas = get_param(meas,'PortHandles');
        if numel(phMeas.Outport) < 12
            error('PLLWRAPB:NewPorts', ...
                '%s Measurements did not expose 12 outputs after update.',dev);
        end

        % Old out9/out10 lines still represent pre-patch branch topology at parent.
        lnWt = get_param(phMeas.Outport(9),'Line');
        lnF  = get_param(phMeas.Outport(10),'Line');

        if lnWt < 0 || lnF < 0
            error('PLLWRAPB:ParentOldLines', ...
                '%s expected old parent raw branch lines before rewire.',dev);
        end

        delete_line(lnWt);
        delete_line(lnF);

        phRoot = get_param(R(k).rootMux,'PortHandles');
        phGT   = get_param(R(k).gThetaParent,'PortHandles');
        phGF   = get_param(R(k).gFreqParent,'PortHandles');

        % RAW native PLL stays in RootDiag rows 21/22.
        localConnect(R(k).ctrl,phMeas.Outport(9),phRoot.Inport(19));
        localConnect(R(k).ctrl,phMeas.Outport(10),phRoot.Inport(20));

        % EXEC held/free-running frame drives GFL control.
        localConnect(R(k).ctrl,phMeas.Outport(11),phGT.Inport(1));
        localConnect(R(k).ctrl,phMeas.Outport(12),phGF.Inport(1));

        fprintf('[EDIT] %-4s parent: raw->RootDiag, exec->thetaF/FreqF.\n',dev);
    end

    fprintf('\n--- 6. FINAL UPDATE ---\n');
    set_param(mdl,'SimulationCommand','update');
    fprintf('[PASS] final diagram update.\n');

    %% =========================================================================
    % 7. STRICT POSTASSERT
    % ==========================================================================
    fprintf('\n--- 7. STRICT POSTASSERT ---\n');

    for k = 1:numel(R)
        dev = R(k).dev;
        meas = R(k).meas;
        pll = R(k).pll;

        % Vendor PLL must remain untouched/resolved.
        if ~strcmpi(localGet(pll,'LinkStatus'),'resolved')
            error('PLLWRAPB:PostPLLLink', ...
                '%s PLL library link changed unexpectedly.',dev);
        end

        localReq(R(k).holdSS);
        localReq(R(k).oWtExec);
        localReq(R(k).oFreqExec);

        phPLL = get_param(pll,'PortHandles');
        dstFNative = localDestTuples(phPLL.Outport(1));
        dstTNative = localDestTuples(phPLL.Outport(2));

        expFNative = {sprintf('%s|1',[meas '/AA15_PLL_NATIVE_FREQ_GOTO'])};
        expTNative = {sprintf('%s|1',[meas '/AA15_PLL_NATIVE_THETA_GOTO'])};

        if ~isequal(sort(dstFNative(:)),sort(expFNative(:)))
            error('PLLWRAPB:PostNativeF','%s native Freq topology wrong.',dev);
        end
        if ~isequal(sort(dstTNative(:)),sort(expTNative(:)))
            error('PLLWRAPB:PostNativeT','%s native theta topology wrong.',dev);
        end

        % Exec manager must drive existing internal tags.
        phHold = get_param(R(k).holdSS,'PortHandles');

        dstExecF = localDestTuples(phHold.Outport(1));
        dstExecT = localDestTuples(phHold.Outport(2));

        expExecF = {sprintf('%s|1',R(k).gFreq)};
        expExecT = {sprintf('%s|1',R(k).gTheta)};

        if ~isequal(sort(dstExecF(:)),sort(expExecF(:)))
            error('PLLWRAPB:PostExecF','%s exec Freq tag topology wrong.',dev);
        end
        if ~isequal(sort(dstExecT(:)),sort(expExecT(:)))
            error('PLLWRAPB:PostExecT','%s exec theta tag topology wrong.',dev);
        end

        % Parent ports: raw to RootDiag only; exec to control only.
        phMeas = get_param(meas,'PortHandles');
        phRoot = get_param(R(k).rootMux,'PortHandles');

        d9  = localDestTuples(phMeas.Outport(9));
        d10 = localDestTuples(phMeas.Outport(10));
        d11 = localDestTuples(phMeas.Outport(11));
        d12 = localDestTuples(phMeas.Outport(12));

        e9  = {sprintf('%s|19',R(k).rootMux)};
        e10 = {sprintf('%s|20',R(k).rootMux)};
        e11 = {sprintf('%s|1',R(k).gThetaParent)};
        e12 = {sprintf('%s|1',R(k).gFreqParent)};

        if ~isequal(sort(d9(:)),sort(e9(:))),   error('PLLWRAPB:PostP9','%s out9 wrong.',dev); end
        if ~isequal(sort(d10(:)),sort(e10(:))), error('PLLWRAPB:PostP10','%s out10 wrong.',dev); end
        if ~isequal(sort(d11(:)),sort(e11(:))), error('PLLWRAPB:PostP11','%s out11 wrong.',dev); end
        if ~isequal(sort(d12(:)),sort(e12(:))), error('PLLWRAPB:PostP12','%s out12 wrong.',dev); end

        % RootDiag width frozen.
        if ~strcmp(localGet(R(k).rootMux,'Inputs'),'21')
            error('PLLWRAPB:RootDiagInputs', ...
                '%s RootDiag Mux input count changed.',dev);
        end

        fprintf('[PASS] %-4s postassert exact; vendor PLL untouched.\n',dev);
    end

    opw1 = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
        'Regexp','on','Name','.*OpWrite.*');

    if numel(opw1) ~= numel(opw0)
        error('PLLWRAPB:OpWriteChanged', ...
            'OpWrite-like count changed %d -> %d.',numel(opw0),numel(opw1));
    end

    fprintf('[PASS] OpWrite-like count unchanged = %d.\n',numel(opw1));

    %% =========================================================================
    % 8. SAVE ONCE
    % ==========================================================================
    fprintf('\n--- 8. SAVE ONCE ---\n');
    save_system(mdl);
    fprintf('[PASS] Saved current model once.\n');

    %% =========================================================================
    % 9. CLOSE / RELOAD / PERSISTENT AUDIT
    % ==========================================================================
    fprintf('\n--- 9. CLOSE / RELOAD / PERSISTENT AUDIT ---\n');

    close_system(mdl,0);
    load_system(mdl);

    if ~strcmpi(localGet(mdl,'Dirty'),'off')
        error('PLLWRAPB:ReloadDirty','Reloaded model Dirty is not off.');
    end

    for k = 1:numel(R)
        localReq(R(k).pll);
        localReq(R(k).holdSS);
        localReq(R(k).oWtExec);
        localReq(R(k).oFreqExec);

        if ~strcmpi(localGet(R(k).pll,'LinkStatus'),'resolved')
            error('PLLWRAPB:ReloadPLLLink', ...
                '%s vendor PLL link did not remain resolved.',R(k).dev);
        end

        fprintf('[PASS] %-4s persistent wrapper patch; PLL remains resolved.\n',R(k).dev);
    end

    fprintf('\n====================================================================================================\n');
    fprintf(' PATCH PASS\n');
    fprintf('====================================================================================================\n');
    fprintf('Backup : %s\n',backupFile);
    fprintf('Model  : %s\n',modelFile);
    fprintf('T_HOLD : %.7f s\n',T_HOLD);
    fprintf('\nIMPORTANT SEMANTICS FOR B:\n');
    fprintf('  Existing RootDiag wt_PLL/Freq_PLL rows remain RAW native PLL.\n');
    fprintf('  Existing wt_selected/Freq_selected rows are EXEC held/free-running frame.\n');
    fprintf('  No OpWrite group/width changed.\n');
    fprintf('  MathWorks PLL (3ph) internals/library links were NOT modified.\n');
    fprintf('====================================================================================================\n');

catch ME
    fprintf(2,'\n[PATCH FAILED] %s\n',ME.message);
    fprintf(2,'Rolling back exact backup...\n');

    try
        if bdIsLoaded(mdl)
            close_system(mdl,0);
        end
    catch
    end

    try
        copyfile(backupFile,modelFile,'f');
        load_system(mdl);
        fprintf(2,'[ROLLBACK PASS] Restored %s\n',modelFile);
    catch ME2
        fprintf(2,'[ROLLBACK ERROR] %s\n',ME2.message);
    end

    rethrow(ME);
end

end

%% =========================================================================
% Create transparent-track / free-run-hold subsystem
% ==========================================================================
function localCreateExecFrameHoldSubsystem(ss,T_HOLD,TS_EXPR)

add_block('built-in/SubSystem',ss, ...
    'Position',[790 265 965 375]);

% Ports
add_block('built-in/Inport',[ss '/Freq_native'], ...
    'Port','1','Position',[25 35 55 49]);
add_block('built-in/Inport',[ss '/Theta_native'], ...
    'Port','2','Position',[25 78 55 92]);

add_block('built-in/Outport',[ss '/Freq_exec'], ...
    'Port','1','Position',[515 35 545 49]);
add_block('built-in/Outport',[ss '/Theta_exec'], ...
    'Port','2','Position',[515 78 545 92]);

% Step: 1 before hold, 0 after hold.
add_block('simulink/Sources/Step',[ss '/TRACK_ENABLE'], ...
    'Time',num2str(T_HOLD,'%.10g'), ...
    'Before','1', ...
    'After','0', ...
    'SampleTime',TS_EXPR, ...
    'Position',[25 130 65 160]);

% Frequency state.
add_block('simulink/Signal Routing/Switch',[ss '/Freq_TrackOrHold'], ...
    'Criteria','u2 > Threshold', ...
    'Threshold','0.5', ...
    'Position',[160 25 205 70]);

add_block('simulink/Discrete/Unit Delay',[ss '/Freq_State'], ...
    'InitialCondition','50', ...
    'SampleTime',TS_EXPR, ...
    'Position',[265 115 315 145]);

% Use local Goto/From to avoid branch ambiguity.
add_block('simulink/Signal Routing/Goto',[ss '/Goto_FEXEC'], ...
    'GotoTag','AA15_FEXEC', ...
    'TagVisibility','local', ...
    'Position',[250 37 330 57]);

add_block('simulink/Signal Routing/From',[ss '/From_FEXEC_Out'], ...
    'GotoTag','AA15_FEXEC', ...
    'Position',[400 30 470 50]);

add_block('simulink/Signal Routing/From',[ss '/From_FEXEC_State'], ...
    'GotoTag','AA15_FEXEC', ...
    'Position',[175 118 245 138]);

add_block('simulink/Signal Routing/From',[ss '/From_FEXEC_ThetaStep'], ...
    'GotoTag','AA15_FEXEC', ...
    'Position',[175 195 245 215]);

% Theta state.
add_block('simulink/Discrete/Unit Delay',[ss '/Theta_State'], ...
    'InitialCondition','0', ...
    'SampleTime',TS_EXPR, ...
    'Position',[265 245 315 275]);

add_block('simulink/Math Operations/Gain',[ss '/FreqHz_to_DeltaTheta'], ...
    'Gain',['2*pi*' TS_EXPR], ...
    'Position',[270 190 350 220]);

add_block('simulink/Math Operations/Sum',[ss '/Theta_Advance'], ...
    'Inputs','++', ...
    'Position',[375 190 405 225]);

add_block('simulink/Signal Routing/Switch',[ss '/Theta_TrackOrAdvance'], ...
    'Criteria','u2 > Threshold', ...
    'Threshold','0.5', ...
    'Position',[430 65 475 110]);

add_block('simulink/Signal Routing/Goto',[ss '/Goto_TEXEC'], ...
    'GotoTag','AA15_TEXEC', ...
    'TagVisibility','local', ...
    'Position',[485 77 555 97]);

add_block('simulink/Signal Routing/From',[ss '/From_TEXEC_Out'], ...
    'GotoTag','AA15_TEXEC', ...
    'Position',[400 78 470 98]);

add_block('simulink/Signal Routing/From',[ss '/From_TEXEC_State'], ...
    'GotoTag','AA15_TEXEC', ...
    'Position',[175 248 245 268]);

% Wiring - each source has one direct destination; Goto/From handles fanout.
localConnect(ss, ...
    get_param([ss '/Freq_native'],'PortHandles').Outport(1), ...
    get_param([ss '/Freq_TrackOrHold'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/TRACK_ENABLE'],'PortHandles').Outport(1), ...
    get_param([ss '/Freq_TrackOrHold'],'PortHandles').Inport(2));

localConnect(ss, ...
    get_param([ss '/Freq_State'],'PortHandles').Outport(1), ...
    get_param([ss '/Freq_TrackOrHold'],'PortHandles').Inport(3));

localConnect(ss, ...
    get_param([ss '/Freq_TrackOrHold'],'PortHandles').Outport(1), ...
    get_param([ss '/Goto_FEXEC'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/From_FEXEC_Out'],'PortHandles').Outport(1), ...
    get_param([ss '/Freq_exec'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/From_FEXEC_State'],'PortHandles').Outport(1), ...
    get_param([ss '/Freq_State'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/From_FEXEC_ThetaStep'],'PortHandles').Outport(1), ...
    get_param([ss '/FreqHz_to_DeltaTheta'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/FreqHz_to_DeltaTheta'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_Advance'],'PortHandles').Inport(2));

localConnect(ss, ...
    get_param([ss '/Theta_State'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_Advance'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/Theta_native'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_TrackOrAdvance'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/TRACK_ENABLE'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_TrackOrAdvance'],'PortHandles').Inport(2));

localConnect(ss, ...
    get_param([ss '/Theta_Advance'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_TrackOrAdvance'],'PortHandles').Inport(3));

localConnect(ss, ...
    get_param([ss '/Theta_TrackOrAdvance'],'PortHandles').Outport(1), ...
    get_param([ss '/Goto_TEXEC'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/From_TEXEC_Out'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_exec'],'PortHandles').Inport(1));

localConnect(ss, ...
    get_param([ss '/From_TEXEC_State'],'PortHandles').Outport(1), ...
    get_param([ss '/Theta_State'],'PortHandles').Inport(1));

end

%% =========================================================================
% Generic helpers
% ==========================================================================
function pll = localResolveRealPLL(meas)
names = get_param(meas,'Blocks');
if ischar(names), names={names}; end
hits = {};

for i=1:numel(names)
    if strcmpi(localNorm(names{i}),'PLL (3ph)')
        hits{end+1,1}=[meas '/' names{i}]; %#ok<AGROW>
    end
end

if numel(hits) ~= 1
    error('PLLWRAPB:PLLResolve', ...
        'Expected exactly one normalized PLL (3ph) under %s; found %d.', ...
        localOneLine(meas),numel(hits));
end

pll=hits{1};

if ~strcmp(localGet(pll,'BlockType'),'SubSystem') || ...
   contains(lower(localNorm(localGet(pll,'Name'))),'power')
    error('PLLWRAPB:PLLFingerprint','Resolved block is not the real PLL.');
end
end

function localConnect(sys,srcH,dstH)
if isempty(srcH) || isempty(dstH) || srcH<0 || dstH<0
    error('PLLWRAPB:ConnectHandle','Invalid port handle in %s.',sys);
end
add_line(sys,srcH,dstH,'autorouting','on');
end

function dst = localDestTuples(outH)
dst={};
ln=get_param(outH,'Line');
if isempty(ln) || ln<0, return; end
dh=get_param(ln,'DstPortHandle');
dh=dh(dh>=0);

for i=1:numel(dh)
    dst{end+1,1}=sprintf('%s|%d', ...
        get_param(dh(i),'Parent'),get_param(dh(i),'PortNumber')); %#ok<AGROW>
end
end

function localPrintTupleMismatch(dev,label,actual,expected)
fprintf('\n[%s] %s mismatch\n',dev,label);
fprintf('Actual:\n');
for i=1:numel(actual), fprintf('  %s\n',actual{i}); end
fprintf('Expected:\n');
for i=1:numel(expected), fprintf('  %s\n',expected{i}); end
end

function s=localGet(p,param)
try
    x=get_param(p,param);
    if isnumeric(x)||islogical(x)
        s=mat2str(x);
    elseif ischar(x)
        s=x;
    elseif isstring(x)
        s=char(x);
    else
        s='';
    end
catch
    s='';
end
end

function s=localNorm(s)
if isempty(s), return; end
s=char(s);
s=regexprep(s,'\s+',' ');
s=strtrim(s);
end

function s=localOneLine(s)
s=localNorm(s);
end

function localReq(p)
if getSimulinkBlockHandle(p)<0
    error('PLLWRAPB:Missing','Missing required block: %s',localOneLine(p));
end
end

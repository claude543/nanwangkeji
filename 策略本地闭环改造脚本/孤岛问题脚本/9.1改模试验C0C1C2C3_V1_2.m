function PATCH_K26_V5_GFL_CAUSAL_HARNESS_C0C1C2C3_V1_2
% PATCH_K26_V5_GFL_CAUSAL_HARNESS_C0C1C2C3_V1_2
%
% =========================================================================
% PURPOSE
% =========================================================================
% One-Build orthogonal causal harness for K26_V5 full-six island root cause.
%
% CURRENT LOCKED SYSTEM-LEVEL ROOT DOMAIN:
%   J1 OPEN
%      ->
%   strong-grid stiffness/damping removed
%      ->
%   ESS1 GFM output impedance x five-GFL aggregate dynamic admittance
%      ->
%   ~14-16 Hz positive-growth mode
%
% B1 has already shown:
%   native PLL active frame dynamics are NOT necessary for instability.
%
% NEXT QUESTIONS:
%   C1: Is dynamic applied VdVqs -> Current Regulator/in1 direct voltage
%       feedforward a necessary adverse path?
%
%   C2: Is dynamic Power-Control IdIq_refF -> Current Regulator current
%       reference a necessary adverse path?
%
%   C3: Do C1 and C2 interact such that both dynamic paths must be removed?
%
% =========================================================================
% FIVE MUTUALLY EXCLUSIVE MODES
% =========================================================================
% Each of the FIVE GFL controls receives its own tunable Constant:
%
%   AA15_CAUSAL_MODE
%
% Allowed values:
%
%   0 = C0 BASELINE
%       B1 PLL frame = continuous native TRACK
%       C1 VdVqs     = TRACK
%       C2 IdIq_refF = TRACK
%
%   1 = B1 REPRODUCTION
%       B1 PLL frame = TRACK -> HOLD/FREE-RUN at T_INTERVENE
%       C1            = TRACK
%       C2            = TRACK
%
%   2 = C1
%       B1 PLL frame = continuous native TRACK
%       C1 VdVqs     = TRACK -> HOLD at T_INTERVENE
%       C2            = TRACK
%
%   3 = C2
%       B1 PLL frame = continuous native TRACK
%       C1            = TRACK
%       C2 IdIq_refF = TRACK -> HOLD at T_INTERVENE
%
%   4 = C3
%       B1 PLL frame = continuous native TRACK
%       C1 VdVqs     = TRACK -> HOLD at T_INTERVENE
%       C2 IdIq_refF = TRACK -> HOLD at T_INTERVENE
%
% T_INTERVENE = 8.1894 s
% ~20 ms before the established J1 first-open around 8.2094~8.2096 s.
%
% =========================================================================
% CAUSAL INTERVENTION IMPLEMENTATION
% =========================================================================
% C1 exact edge:
%
%   From26(tag=VdVqs)
%       -> AA15_C1_VDQ_TRACK_HOLD
%       -> Current Regulator/in1
%
% C2 exact edge:
%
%   Power Control Loop/out1 (IdIq_refF_raw)
%       -> AA15_C2_IREF_TRACK_HOLD
%       -> Goto18(tag=IdIq_refF)
%
% Track/Hold is NOT zeroing and NOT parameter retuning:
%
%   TRACK: applied[k] = raw[k]
%   HOLD : applied[k] = applied[k-1]
%
% A Unit Delay breaks algebraic loops and captures the last tracked 2-vector.
%
% =========================================================================
% B1 MODE GATING
% =========================================================================
% Existing AA15_PLL_EXEC_FRAME_HOLD remains intact in principle.
% This patch adds only a B1_HOLD_REQ input and a track gate:
%
%   mode ~= 1 -> B1 TRACK permanently
%   mode == 1 -> existing 8.1894-s Step determines TRACK->HOLD
%
% Thus C0/C1/C2/C3 recover native-PLL continuous tracking and do NOT carry
% the previous B1 intervention as a confounder.
%
% =========================================================================
% NEW 24-SCALAR CAUSAL LOGGER MAP PER GFL
% =========================================================================
% Existing G26/G27/G28 OpWrite allocation remains EXACTLY unchanged.
% Existing output3 width remains EXACTLY 24 per GFL.
% NO new OpWrite. NO OpComm widening.
%
% Physical Mux inputs = 17, compiled scalar width = 24:
%
%   physical input 01: raw IdIq_refF vector2       -> scalar 01 Id_refF_raw
%                                                        02 Iq_refF_raw
%   physical input 02: applied IdIq_refs vector2   -> scalar 03 Id_ref_applied
%                                                        04 Iq_ref_applied
%   physical input 03: applied IdIqs vector2       -> scalar 05 Id_meas_applied
%                                                        06 Iq_meas_applied
%   physical input 04: raw VdVqs vector2           -> scalar 07 VdVqs_raw
%                                                        08 VqVqs_raw
%   physical input 05: applied VdVqs vector2       -> scalar 09 VdVqs_applied
%                                                        10 VqVqs_applied
%   physical input 06: Current PI PIdq vector2     -> scalar 11 Current_PI_d
%                                                        12 Current_PI_q
%   physical input 07: VdVq_conv vector2           -> scalar 13 Vd_conv
%                                                        14 Vq_conv
%   physical input 08: ModIndex scalar             -> scalar 15 ModIndex
%   physical input 09: Pmeas selected scalar       -> scalar 16 Pmeas
%   physical input 10: Qmeas selected scalar       -> scalar 17 Qmeas
%   physical input 11: theta_exec selected scalar  -> scalar 18 theta_exec
%   physical input 12: Freq_exec selected scalar   -> scalar 19 Freq_exec
%   physical input 13: native PLL theta raw        -> scalar 20 theta_native_PLL
%   physical input 14: native PLL Freq raw         -> scalar 21 Freq_native_PLL
%   physical input 15: causal mode                 -> scalar 22 CAUSAL_MODE
%   physical input 16: C1 track enable             -> scalar 23 C1_TRACK_ENABLE
%   physical input 17: C2 track enable             -> scalar 24 C2_TRACK_ENABLE
%
% This creates direct RAW -> APPLIED -> RESPONSE evidence in the MAT.
%
% =========================================================================
% HARD SAFETY / TRANSACTION
% =========================================================================
% - saved current canonical K26_V5 only; Dirty must be OFF
% - exact read-only preflight before first edit
% - exact full-SLX backup before first edit
% - standard Simulink blocks only
% - NO MATLAB Function / Stateflow
% - NO new OpWrite
% - NO OpComm changes
% - NO Current PI / Rff / Lff parameter changes
% - NO ESS1 F20/F21/F22/F23/F24/F25 changes
% - NO PWM/DC/network/topology changes
% - update + explicit compile-state width audit
% - exact 5-OpWrite postassert
% - save once
% - close/reload persistent audit
% - any error after backup -> restore exact backup
%
% =========================================================================
% REQUIRED NEXT ACTION
% =========================================================================
% Run this patch ONLY on the CURRENT post-B1 / RootDiag-V4 canonical model.
% Do NOT Build unless this script prints:
%
%   CAUSAL HARNESS PATCH PASS
%
% After PASS:
%   STOP and upload the patch TXT for review.
%   Only then Rebuild All once.
%   After Build, C0 transparency regression is mandatory before C1.
%
% V1.2 FIX (2026-09-01):
% - V1.1 correctly created the C1 applied-VdVqs logger branch, but its
%   postassert still required C1_HOLD/out1 to have only ONE destination.
% - Correct postpatch contract is exactly TWO destinations:
%     Current Regulator/in1 + causal logger/in5.
% - V1.2 adds exact destination-set checking and an immediate 17-input
%   causal-logger source audit, so intentional diagnostic fanout cannot be
%   mistaken for a wiring defect.
%
% V1.1 FIX (2026-09-01):
% - V1 failed in logger replacement because a newly created Mux input could
%   inherit/auto-attach an old geometric branch ("target port already connected").
% - V1.1 explicitly deletes ONLY old-Mux destination branches, preserves
%   all source fanout, creates the new Mux away from the old wire bundle,
%   and verifies every new destination is free before causal rewiring.
%
% 2026-09-01
% =========================================================================

clc;

T_INTERVENE = 8.1894;
TS_EXPR = 'Ts';

mdl = bdroot(gcs);
if isempty(mdl)
    error('CAUSALHARNESS:NoModel', ...
        'Open CURRENT canonical K26_V5, click inside it, then run this patch.');
end
load_system(mdl);

if ~contains(mdl,'K26_V5')
    error('CAUSALHARNESS:WrongModel','Expected K26_V5, got %s.',mdl);
end

if ~strcmpi(localGet(mdl,'Dirty'),'off')
    error('CAUSALHARNESS:Dirty', ...
        'Current model Dirty=on. Save/reload canonical K26_V5 before patch.');
end

modelFile = localGet(mdl,'FileName');
if isempty(modelFile) || ~isfile(modelFile)
    error('CAUSALHARNESS:ModelFile','Cannot resolve current saved K26_V5.slx.');
end

[modelDir,modelBase,modelExt] = fileparts(modelFile);
if ~strcmp(modelBase,'K26_V5')
    error('CAUSALHARNESS:ModelBase','Expected saved model K26_V5.slx.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
logFile = fullfile(modelDir, ...
    sprintf('9.1_GFL_CAUSAL_HARNESS_C0C1C2C3_V1_2_%s.txt',stamp));
backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_GFL_CAUSAL_HARNESS_C0C1C2C3_V1_2_%s%s', ...
    modelBase,stamp,modelExt));

try diary off; catch, end
diary(logFile); diary on;
cDiary = onCleanup(@()localDiaryOff()); %#ok<NASGU>

fprintf('\n====================================================================================================\n');
fprintf(' K26_V5 GFL CAUSAL HARNESS C0/C1/C2/C3 PATCH V1.2\n');
fprintf('====================================================================================================\n');
fprintf('Model       : %s\n',modelFile);
fprintf('Dirty       : %s\n',localGet(mdl,'Dirty'));
fprintf('T_INTERVENE : %.7f s\n',T_INTERVENE);
fprintf('Rule        : final model still exactly FIVE OpWrite blocks.\n');
fprintf('Rule        : C0/C1/C2/C3 use native PLL continuous TRACK; only Mode1 reproduces B1.\n');

editStarted = false;
saved = false;

try
    %% ====================================================================
    % 1. GLOBAL FROZEN LOGGER / PARENT PREFLIGHT
    % =====================================================================
    fprintf('\n--- 1. GLOBAL FIVE-OPWRITE / FROZEN LOGGER PREFLIGHT ---\n');

    sm  = [mdl '/SM_Master'];
    ss1 = [mdl '/SS_Slave'];
    ss2 = [mdl '/SS_Slave2'];
    ss3 = [mdl '/SS_Slave3'];
    for p={sm,ss1,ss2,ss3}
        localReq(p{1});
    end

    ops0 = localFindAllOpWrites(mdl);
    if numel(ops0) ~= 5
        error('CAUSALHARNESS:OpWriteCount', ...
            'Expected exactly 5 OpWriteFile blocks, found %d.',numel(ops0));
    end

    opByGroup = cell(1,31);
    for i=1:numel(ops0)
        g=localReadNumericMask(ops0{i},'Acq_Group');
        fprintf('  G%g : %s\n',g,ops0{i});
        if ~ismember(g,26:30)
            error('CAUSALHARNESS:UnexpectedGroup','Unexpected acquisition group %g.',g);
        end
        if ~isempty(opByGroup{g})
            error('CAUSALHARNESS:DuplicateGroup','Duplicate group %g.',g);
        end
        opByGroup{g}=ops0{i};
    end
    for g=26:30
        if isempty(opByGroup{g})
            error('CAUSALHARNESS:MissingGroup','Missing acquisition group %d.',g);
        end
    end

    op26=opByGroup{26};
    op27=opByGroup{27};
    op28=opByGroup{28};
    op29=opByGroup{29};
    op30=opByGroup{30};

    exp26=[ss1 '/AA15_ROOTDIAG_EV12_OPWRITE_G26'];
    exp27=[ss2 '/AA15_ROOTDIAG_ESS2_OPWRITE_G27'];
    exp28=[ss3 '/AA15_ROOTDIAG_PV12_OPWRITE_G28'];
    exp29=[sm  '/AA15_FREQDIAG_SM_OPWRITE_G29'];
    exp30=[ss2 '/AA15_FREQDIAG_ESS1_OPWRITE_G30'];

    if ~strcmp(op26,exp26), error('CAUSALHARNESS:G26Path','G26 path mismatch.'); end
    if ~strcmp(op27,exp27), error('CAUSALHARNESS:G27Path','G27 path mismatch.'); end
    if ~strcmp(op28,exp28), error('CAUSALHARNESS:G28Path','G28 path mismatch.'); end
    if ~strcmp(op29,exp29), error('CAUSALHARNESS:G29Path','G29 path mismatch.'); end
    if ~strcmp(op30,exp30), error('CAUSALHARNESS:G30Path','G30 path mismatch.'); end

    localAssertMaskNumeric(op26,'Decimation',2);
    localAssertMaskNumeric(op27,'Decimation',2);
    localAssertMaskNumeric(op28,'Decimation',2);
    localAssertMaskNumeric(op29,'Decimation',2);
    localAssertMaskNumeric(op30,'Decimation',5);

    g29Mux=[sm '/AA15_D1_SUPERPACK_MUX30'];
    g30Mux=[ss2 '/AA15_FREQDIAG_ESS1_MUX'];
    localReq(g29Mux); localReq(g30Mux);

    if localNumeric(localGet(g29Mux,'Inputs'))~=38
        error('CAUSALHARNESS:G29Width','Expected frozen G29 Mux Inputs=38.');
    end
    if localNumeric(localGet(g30Mux,'Inputs'))~=63
        error('CAUSALHARNESS:G30Width','Expected frozen G30 Mux Inputs=63.');
    end

    opSrc0=cell(1,5);
    for i=1:5
        opSrc0{i}=localSourceDescriptor(localGetInportHandle(ops0{i},1));
    end

    fprintf('[PASS] Existing G26/G27/G28 rootdiag allocation exact.\n');
    fprintf('[PASS] G29/G30 frozen contracts exact.\n');

    %% ====================================================================
    % 2. FIVE GFL STRICT READ-ONLY PREFLIGHT
    % =====================================================================
    fprintf('\n--- 2. FIVE-GFL STRICT READ-ONLY PREFLIGHT ---\n');

    spec = {
        'PV1',  [mdl '/SS_Slave3/PV1_Control'];
        'PV2',  [mdl '/SS_Slave3/PV2_Control'];
        'ESS2', [mdl '/SS_Slave2/ESS2_Control'];
        'EV1',  [mdl '/SS_Slave/EV1_Control'];
        'EV2',  [mdl '/SS_Slave/Control System'];
    };

    R=struct([]);

    for k=1:size(spec,1)
        dev=spec{k,1};
        ctrl=spec{k,2};
        meas=[ctrl '/Measurements'];
        hold=[meas '/AA15_PLL_EXEC_FRAME_HOLD'];
        ireg=[ctrl '/Current Regulator'];
        pcl=[ctrl '/Power Control Loop'];

        localReq(ctrl); localReq(meas); localReq(hold); localReq(ireg); localReq(pcl);

        % Existing post-B1 Measurements contract.
        phMeas=get_param(meas,'PortHandles');
        if numel(phMeas.Inport)~=4 || numel(phMeas.Outport)~=12
            error('CAUSALHARNESS:MeasContract', ...
                '%s Measurements expected 4 inputs / 12 outputs prepatch; got %d/%d.', ...
                dev,numel(phMeas.Inport),numel(phMeas.Outport));
        end

        % Existing B1 Step exact.
        b1Step=[hold '/TRACK_ENABLE'];
        localReq(b1Step);
        if abs(localNumeric(localGet(b1Step,'Time'))-T_INTERVENE)>1e-12 || ...
           abs(localNumeric(localGet(b1Step,'Before'))-1)>1e-12 || ...
           abs(localNumeric(localGet(b1Step,'After'))-0)>1e-12
            error('CAUSALHARNESS:B1Step', ...
                '%s B1 TRACK_ENABLE no longer matches 8.1894 / 1 / 0.',dev);
        end

        phHold=get_param(hold,'PortHandles');
        if numel(phHold.Inport)~=2 || numel(phHold.Outport)~=2
            error('CAUSALHARNESS:B1HoldContract', ...
                '%s B1 hold expected 2 inputs / 2 outputs prepatch.',dev);
        end

        % C1 exact edge From26 -> Current Regulator/in1.
        from26=[ctrl '/From26'];
        localReq(from26);
        if ~strcmp(localGet(from26,'BlockType'),'From') || ...
           ~strcmp(localGet(from26,'GotoTag'),'VdVqs')
            error('CAUSALHARNESS:C1From26','%s From26 is not tag VdVqs.',dev);
        end

        phFrom26=get_param(from26,'PortHandles');
        phIreg=get_param(ireg,'PortHandles');
        localAssertExactSingleDestination( ...
            phFrom26.Outport(1),ireg,1, ...
            sprintf('%s C1 From26(VdVqs)->CurrentReg/in1',dev));

        % Current Regulator other inputs frozen.
        localAssertInportSourceTag(ireg,2,'IdIqs',dev);
        localAssertInportSourceTag(ireg,3,'IdIq_refs',dev);

        % C2 exact edge PowerControl/out1 -> Goto18.
        goto18=[ctrl '/Goto18'];
        localReq(goto18);
        if ~strcmp(localGet(goto18,'BlockType'),'Goto') || ...
           ~strcmp(localGet(goto18,'GotoTag'),'IdIq_refF')
            error('CAUSALHARNESS:C2Goto18','%s Goto18 is not tag IdIq_refF.',dev);
        end

        phPcl=get_param(pcl,'PortHandles');
        if numel(phPcl.Outport)~=1
            error('CAUSALHARNESS:PclOut','%s Power Control expected one output.',dev);
        end
        localAssertExactSingleDestination( ...
            phPcl.Outport(1),goto18,1, ...
            sprintf('%s C2 PowerControl/out1->Goto18',dev));

        % Actual selected/applied publications.
        swIref=[ctrl '/Switch'];
        muxV=[ctrl '/Mux'];
        muxI=[ctrl '/Mux1'];
        swP=[ctrl '/Switch3'];
        swTheta=[ctrl '/Switch5'];
        swQ=[ctrl '/Switch4'];
        swFreq=[ctrl '/Switch7'];
        goto19=[ctrl '/Goto19'];
        goto20=[ctrl '/Goto20'];
        goto21=[ctrl '/Goto21'];
        goto23=[ctrl '/Goto23'];

        reqs={swIref,muxV,muxI,swP,swTheta,swQ,swFreq,goto19,goto20,goto21,goto23};
        for q=1:numel(reqs), localReq(reqs{q}); end

        localAssertBlockFeedsGoto(swIref,goto19,'IdIq_refs',dev);
        localAssertBlockFeedsGoto(muxV,goto20,'VdVqs',dev);
        localAssertBlockFeedsGoto(muxI,goto21,'IdIqs',dev);
        localAssertBlockFeedsGoto(swTheta,goto23,'wts',dev);

        % Existing current regulator outputs.
        phIreg=get_param(ireg,'PortHandles');
        if numel(phIreg.Outport)~=2
            error('CAUSALHARNESS:IregOutCount','%s Current Regulator expected 2 outputs.',dev);
        end

        % Existing rootdiag output3 and old Mux21.
        oldMux=[ctrl '/AA15_ROOTDIAG_MUX21PORT_24SCALAR'];
        diagOut=[ctrl '/AA15_ROOTDIAG_OUT24'];
        localReq(oldMux); localReq(diagOut);

        if ~strcmp(localGet(oldMux,'BlockType'),'Mux') || ...
           localNumeric(localGet(oldMux,'Inputs'))~=21
            error('CAUSALHARNESS:OldDiagMux', ...
                '%s expected existing AA15_ROOTDIAG_MUX21PORT_24SCALAR Inputs=21.',dev);
        end

        if ~strcmp(localGet(diagOut,'BlockType'),'Outport') || ...
           localNumeric(localGet(diagOut,'Port'))~=3
            error('CAUSALHARNESS:DiagOut','%s diagnostic Outport3 contract changed.',dev);
        end

        phOld=get_param(oldMux,'PortHandles');
        phDiagOut=get_param(diagOut,'PortHandles');
        localAssertExactSingleDestination( ...
            phOld.Outport(1),diagOut,1, ...
            sprintf('%s old diag Mux->Out24',dev));

        % Native PLL raw outputs 9/10 remain direct diagnostic-only quantities.
        localAssertExactSingleDestination( ...
            phMeas.Outport(9),oldMux,19, ...
            sprintf('%s Measurements/out9 native theta -> old rootdiag in19',dev));
        localAssertExactSingleDestination( ...
            phMeas.Outport(10),oldMux,20, ...
            sprintf('%s Measurements/out10 native freq -> old rootdiag in20',dev));

        % Current patch artifacts must not already exist.
        collision={
            [ctrl '/AA15_CAUSAL_MODE']
            [ctrl '/AA15_C_HOLD_STEP']
            [ctrl '/AA15_C1_VDQ_TRACK_HOLD']
            [ctrl '/AA15_C2_IREF_TRACK_HOLD']
            [ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR']
            [meas '/AA15_B1_HOLD_REQ']
            [hold '/AA15_B1_HOLD_REQ']
            [hold '/AA15_B1_TRACK_GATE']
        };
        for c=1:numel(collision)
            if getSimulinkBlockHandle(collision{c})>=0
                error('CAUSALHARNESS:Collision', ...
                    '%s causal harness artifact already exists: %s',dev,collision{c});
            end
        end

        R(k).dev=dev; %#ok<AGROW>
        R(k).ctrl=ctrl;
        R(k).meas=meas;
        R(k).hold=hold;
        R(k).b1Step=b1Step;
        R(k).ireg=ireg;
        R(k).pcl=pcl;
        R(k).from26=from26;
        R(k).goto18=goto18;
        R(k).swIref=swIref;
        R(k).muxV=muxV;
        R(k).muxI=muxI;
        R(k).swP=swP;
        R(k).swQ=swQ;
        R(k).swTheta=swTheta;
        R(k).swFreq=swFreq;
        R(k).oldMux=oldMux;
        R(k).diagOut=diagOut;
        R(k).oldMuxPos=get_param(oldMux,'Position');

        fprintf('[PASS] %-4s C1/C2/B1/rootdiag exact prepatch contract.\n',dev);
    end

    if ~strcmpi(localGet(mdl,'Dirty'),'off')
        error('CAUSALHARNESS:PreflightDirty','Read-only preflight unexpectedly changed Dirty.');
    end

    %% ====================================================================
    % 3. FULL BACKUP
    % =====================================================================
    fprintf('\n--- 3. FULL MODEL BACKUP ---\n');
    [ok,msg]=copyfile(modelFile,backupFile,'f');
    if ~ok
        error('CAUSALHARNESS:Backup','Backup failed: %s',msg);
    end
    fprintf('[BACKUP PASS] %s\n',backupFile);
    editStarted=true;

    %% ====================================================================
    % 4. MODIFY B1 HOLD SUBSYSTEMS: ADD MODE GATE INPUT
    % =====================================================================
    fprintf('\n--- 4. B1 MODE GATING INSIDE FIVE MEASUREMENTS WRAPPERS ---\n');

    for k=1:numel(R)
        dev=R(k).dev;
        meas=R(k).meas;
        hold=R(k).hold;

        % Measurements new external input5.
        b1ReqMeas=[meas '/AA15_B1_HOLD_REQ'];
        add_block('built-in/Inport',b1ReqMeas, ...
            'Port','5', ...
            'Position',[20 255 50 269]);

        % Hold subsystem new input3.
        b1ReqHold=[hold '/AA15_B1_HOLD_REQ'];
        add_block('built-in/Inport',b1ReqHold, ...
            'Port','3', ...
            'Position',[25 165 55 179]);

        phReqMeas=get_param(b1ReqMeas,'PortHandles');
        phHold=get_param(hold,'PortHandles');
        localConnect(meas,phReqMeas.Outport(1),phHold.Inport(3));

        % Existing Step must feed only the two existing track switches.
        step=R(k).b1Step;
        phStep=get_param(step,'PortHandles');
        oldStepDests=sort(localDestTuples(phStep.Outport(1)));
        expStepDests=sort({
            sprintf('%s|2',[hold '/Freq_TrackOrHold']);
            sprintf('%s|2',[hold '/Theta_TrackOrAdvance'])
        });
        if ~isequal(oldStepDests(:),expStepDests(:))
            error('CAUSALHARNESS:B1StepFanout', ...
                '%s existing B1 Step destinations changed before gate insertion.',dev);
        end

        % Entire existing Step line is intentionally replaced; it has exactly
        % the two proven B1-switch destinations and no other branches.
        ln=get_param(phStep.Outport(1),'Line');
        if ln<0
            error('CAUSALHARNESS:B1StepLine','%s B1 Step line missing.',dev);
        end
        delete_line(ln);

        one=[hold '/AA15_B1_TRACK_ONE'];
        gate=[hold '/AA15_B1_TRACK_GATE'];

        add_block('simulink/Sources/Constant',one, ...
            'Value','1', ...
            'SampleTime','inf', ...
            'Position',[110 170 145 190]);

        add_block('simulink/Signal Routing/Switch',gate, ...
            'Criteria','u2 > Threshold', ...
            'Threshold','0.5', ...
            'Position',[165 125 210 175]);

        phOne=get_param(one,'PortHandles');
        phGate=get_param(gate,'PortHandles');
        phReqHold=get_param(b1ReqHold,'PortHandles');

        % if B1_HOLD_REQ==1 -> use original Step; else -> constant TRACK=1
        localConnect(hold,phStep.Outport(1),phGate.Inport(1));
        localConnect(hold,phReqHold.Outport(1),phGate.Inport(2));
        localConnect(hold,phOne.Outport(1),phGate.Inport(3));

        phFsw=get_param([hold '/Freq_TrackOrHold'],'PortHandles');
        phTsw=get_param([hold '/Theta_TrackOrAdvance'],'PortHandles');
        localConnect(hold,phGate.Outport(1),phFsw.Inport(2));
        localConnect(hold,phGate.Outport(1),phTsw.Inport(2));

        fprintf('[EDIT] %-4s B1 gate added: Mode1 request can invoke existing 8.1894-s Hold.\n',dev);
    end

    % Refresh Measurements external interfaces to expose input5.
    set_param(mdl,'SimulationCommand','update');
    fprintf('[PASS] update after adding Measurements input5 / B1 hold input3.\n');

    %% ====================================================================
    % 5. ADD PARENT MODE LOGIC + C1/C2 TRACK-HOLD BLOCKS
    % =====================================================================
    fprintf('\n--- 5. ADD FIVE PARENT CAUSAL MODE / C1 / C2 HARNESSES ---\n');

    for k=1:numel(R)
        dev=R(k).dev;
        ctrl=R(k).ctrl;
        meas=R(k).meas;
        ireg=R(k).ireg;
        pcl=R(k).pcl;

        % Place new blocks to the right of current parent content.
        pos=localRightmostPosition(ctrl);
        x=pos(3)+80;
        y=max(80,pos(2));

        mode=[ctrl '/AA15_CAUSAL_MODE'];
        cStep=[ctrl '/AA15_C_HOLD_STEP'];

        add_block('simulink/Sources/Constant',mode, ...
            'Value','0', ...
            'SampleTime','inf', ...
            'Position',[x y x+45 y+25]);

        add_block('simulink/Sources/Step',cStep, ...
            'Time',num2str(T_INTERVENE,'%.10g'), ...
            'Before','1', ...
            'After','0', ...
            'SampleTime',TS_EXPR, ...
            'Position',[x y+55 x+55 y+85]);

        % Mode equality logic 1,2,3,4.
        eq1=localAddModeEq(ctrl,mode,1,[x+90 y]);
        eq2=localAddModeEq(ctrl,mode,2,[x+90 y+45]);
        eq3=localAddModeEq(ctrl,mode,3,[x+90 y+90]);
        eq4=localAddModeEq(ctrl,mode,4,[x+90 y+135]);

        % OR requests for C1=(2|4), C2=(3|4).
        c1Req=[ctrl '/AA15_C1_HOLD_REQ_OR'];
        c2Req=[ctrl '/AA15_C2_HOLD_REQ_OR'];

        add_block('simulink/Logic and Bit Operations/Logical Operator',c1Req, ...
            'Operator','OR','Inputs','2', ...
            'Position',[x+245 y+40 x+285 y+75]);

        add_block('simulink/Logic and Bit Operations/Logical Operator',c2Req, ...
            'Operator','OR','Inputs','2', ...
            'Position',[x+245 y+105 x+285 y+140]);

        phEq2=get_param(eq2,'PortHandles');
        phEq3=get_param(eq3,'PortHandles');
        phEq4=get_param(eq4,'PortHandles');
        phC1Req=get_param(c1Req,'PortHandles');
        phC2Req=get_param(c2Req,'PortHandles');

        localConnect(ctrl,phEq2.Outport(1),phC1Req.Inport(1));
        localConnect(ctrl,phEq4.Outport(1),phC1Req.Inport(2));
        localConnect(ctrl,phEq3.Outport(1),phC2Req.Inport(1));
        localConnect(ctrl,phEq4.Outport(1),phC2Req.Inport(2));

        % Track gates:
        % hold request=1 -> select shared Step (1 before T, 0 after T)
        % hold request=0 -> select constant 1
        one=[ctrl '/AA15_C_TRACK_ONE'];
        c1Gate=[ctrl '/AA15_C1_TRACK_GATE'];
        c2Gate=[ctrl '/AA15_C2_TRACK_GATE'];

        add_block('simulink/Sources/Constant',one, ...
            'Value','1','SampleTime','inf', ...
            'Position',[x+330 y+5 x+365 y+25]);

        add_block('simulink/Signal Routing/Switch',c1Gate, ...
            'Criteria','u2 > Threshold','Threshold','0.5', ...
            'Position',[x+390 y+35 x+435 y+80]);

        add_block('simulink/Signal Routing/Switch',c2Gate, ...
            'Criteria','u2 > Threshold','Threshold','0.5', ...
            'Position',[x+390 y+105 x+435 y+150]);

        phStep=get_param(cStep,'PortHandles');
        phOne=get_param(one,'PortHandles');
        phC1Gate=get_param(c1Gate,'PortHandles');
        phC2Gate=get_param(c2Gate,'PortHandles');

        localConnect(ctrl,phStep.Outport(1),phC1Gate.Inport(1));
        localConnect(ctrl,phC1Req.Outport(1),phC1Gate.Inport(2));
        localConnect(ctrl,phOne.Outport(1),phC1Gate.Inport(3));

        localConnect(ctrl,phStep.Outport(1),phC2Gate.Inport(1));
        localConnect(ctrl,phC2Req.Outport(1),phC2Gate.Inport(2));
        localConnect(ctrl,phOne.Outport(1),phC2Gate.Inport(3));

        % Mode1 -> Measurements input5 B1_HOLD_REQ.
        phMeas=get_param(meas,'PortHandles');
        if numel(phMeas.Inport)~=5
            error('CAUSALHARNESS:MeasInput5', ...
                '%s Measurements expected 5 external inputs after update.',dev);
        end
        phEq1=get_param(eq1,'PortHandles');
        localConnect(ctrl,phEq1.Outport(1),phMeas.Inport(5));

        % Add C1/C2 vector hold subsystems.
        c1Hold=[ctrl '/AA15_C1_VDQ_TRACK_HOLD'];
        c2Hold=[ctrl '/AA15_C2_IREF_TRACK_HOLD'];

        localCreateVectorTrackHold(c1Hold,TS_EXPR,[x+500 y+20 x+670 y+95]);
        localCreateVectorTrackHold(c2Hold,TS_EXPR,[x+500 y+115 x+670 y+190]);

        phC1Hold=get_param(c1Hold,'PortHandles');
        phC2Hold=get_param(c2Hold,'PortHandles');

        % C1 rewire exact single line From26 -> CurrentReg/in1.
        phFrom26=get_param(R(k).from26,'PortHandles');
        phIreg=get_param(ireg,'PortHandles');

        localDeleteExactSingleLine( ...
            phFrom26.Outport(1),phIreg.Inport(1), ...
            sprintf('%s C1 original edge',dev));

        localConnect(ctrl,phFrom26.Outport(1),phC1Hold.Inport(1));
        localConnect(ctrl,phC1Gate.Outport(1),phC1Hold.Inport(2));
        localConnect(ctrl,phC1Hold.Outport(1),phIreg.Inport(1));

        % C2 rewire exact single line PowerControl/out1 -> Goto18.
        phPcl=get_param(pcl,'PortHandles');
        phGoto18=get_param(R(k).goto18,'PortHandles');

        localDeleteExactSingleLine( ...
            phPcl.Outport(1),phGoto18.Inport(1), ...
            sprintf('%s C2 original edge',dev));

        localConnect(ctrl,phPcl.Outport(1),phC2Hold.Inport(1));
        localConnect(ctrl,phC2Gate.Outport(1),phC2Hold.Inport(2));
        localConnect(ctrl,phC2Hold.Outport(1),phGoto18.Inport(1));

        R(k).mode=mode;
        R(k).cStep=cStep;
        R(k).eq1=eq1;
        R(k).eq2=eq2;
        R(k).eq3=eq3;
        R(k).eq4=eq4;
        R(k).c1Req=c1Req;
        R(k).c2Req=c2Req;
        R(k).c1Gate=c1Gate;
        R(k).c2Gate=c2Gate;
        R(k).c1Hold=c1Hold;
        R(k).c2Hold=c2Hold;

        fprintf('[EDIT] %-4s parent Mode/C1/C2 harness inserted.\n',dev);
    end

    %% ====================================================================
    % 6. REPLACE OLD ROOTDIAG INTERNAL MUX WITH CAUSAL 17-PORT / 24-SCALAR
    % =====================================================================
    fprintf('\n--- 6. REBUILD FIVE 24-SCALAR LOGGERS AS RAW->APPLIED->RESPONSE ---\n');

    for k=1:numel(R)
        dev=R(k).dev;
        ctrl=R(k).ctrl;
        meas=R(k).meas;
        ireg=R(k).ireg;
        pcl=R(k).pcl;

        oldMux=R(k).oldMux;
        diagOut=R(k).diagOut;
        newMux=[ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'];

        oldPos=R(k).oldMuxPos;

        % -----------------------------------------------------------------
        % V1.1 FIX:
        % Never rely on delete_block(oldMux) to clean branched signal lines.
        %
        % The old RootDiag Mux inputs are mostly branches of signals that
        % also feed Bus Creator / control diagnostics. We therefore remove
        % ONLY the branches whose destination is the old Mux input ports.
        % All other branches from the same source ports are preserved.
        %
        % We also remove the old Mux->Out24 branch explicitly.
        % -----------------------------------------------------------------
        phOld=get_param(oldMux,'PortHandles');
        phDiagOut=get_param(diagOut,'PortHandles');

        if numel(phOld.Inport)~=21 || numel(phOld.Outport)~=1
            error('CAUSALHARNESS:OldMuxInterface', ...
                '%s old RootDiag Mux interface changed before replacement.',dev);
        end

        for jj=1:numel(phOld.Inport)
            localDisconnectIncomingBranch( ...
                phOld.Inport(jj), ...
                sprintf('%s old RootDiag Mux/in%d',dev,jj));
        end

        localDisconnectIncomingBranch( ...
            phDiagOut.Inport(1), ...
            sprintf('%s old RootDiag Mux -> Out24',dev));

        % All old-Mux ports must now be clean before the block is deleted.
        for jj=1:numel(phOld.Inport)
            localAssertInportUnconnected( ...
                phOld.Inport(jj), ...
                sprintf('%s cleaned old RootDiag Mux/in%d',dev,jj));
        end
        localAssertInportUnconnected( ...
            phDiagOut.Inport(1), ...
            sprintf('%s cleaned diagnostic Out24/in1',dev));

        delete_block(oldMux);

        % Do NOT place the new Mux on the old wire bundle. Programmatic
        % placement on top of an existing/dangling line can cause Simulink
        % to auto-attach that line to a new input port. Shift the new Mux
        % rightward, then autoroute explicit connections.
        newPos=oldPos + [260 0 260 0];

        add_block('simulink/Signal Routing/Mux',newMux, ...
            'Inputs','17', ...
            'Position',newPos);

        phNew=get_param(newMux,'PortHandles');
        phDiagOut=get_param(diagOut,'PortHandles');

        if numel(phNew.Inport)~=17 || numel(phNew.Outport)~=1
            error('CAUSALHARNESS:NewMuxInterface', ...
                '%s new causal Mux expected 17 inputs / 1 output.',dev);
        end

        % A newly created causal Mux MUST start with no incoming lines.
        % If Simulink nevertheless auto-attached a geometric wire, remove
        % only that destination branch safely before continuing.
        for jj=1:numel(phNew.Inport)
            localEnsureInportFree( ...
                phNew.Inport(jj), ...
                sprintf('%s new causal Mux/in%d',dev,jj));
        end
        localEnsureInportFree( ...
            phDiagOut.Inport(1), ...
            sprintf('%s diagnostic Out24/in1 before new logger output',dev));

        % Source handles for causal map.
        phPcl=get_param(pcl,'PortHandles');            % raw Iref vector2
        phSwIref=get_param(R(k).swIref,'PortHandles');% applied Iref vector2
        phMuxI=get_param(R(k).muxI,'PortHandles');    % applied IdIq vector2
        phFrom26=get_param(R(k).from26,'PortHandles');% raw VdVqs vector2
        phC1Hold=get_param(R(k).c1Hold,'PortHandles');% applied VdVqs vector2
        phIreg=get_param(ireg,'PortHandles');          % out1 Vconv, out2 PIdq
        phMod=get_param([ctrl '/From'],'PortHandles'); % ModIndex scalar
        phP=get_param(R(k).swP,'PortHandles');
        phQ=get_param(R(k).swQ,'PortHandles');
        phTheta=get_param([ctrl '/From12'],'PortHandles'); % wts selected theta
        phFreq=get_param(R(k).swFreq,'PortHandles');
        phMeas=get_param(meas,'PortHandles');          % out9/out10 native raw
        phMode=get_param(R(k).mode,'PortHandles');
        phC1Gate=get_param(R(k).c1Gate,'PortHandles');
        phC2Gate=get_param(R(k).c2Gate,'PortHandles');

        % 1 raw IdIq_refF vector2
        localConnect(ctrl,phPcl.Outport(1),phNew.Inport(1));
        % 2 applied IdIq_refs vector2
        localConnect(ctrl,phSwIref.Outport(1),phNew.Inport(2));
        % 3 applied IdIqs vector2
        localConnect(ctrl,phMuxI.Outport(1),phNew.Inport(3));
        % 4 raw selected VdVqs vector2
        localConnect(ctrl,phFrom26.Outport(1),phNew.Inport(4));
        % 5 applied VdVqs vector2
        localConnect(ctrl,phC1Hold.Outport(1),phNew.Inport(5));
        % 6 Current PI vector2
        localConnect(ctrl,phIreg.Outport(2),phNew.Inport(6));
        % 7 VdVq_conv vector2
        localConnect(ctrl,phIreg.Outport(1),phNew.Inport(7));
        % 8 ModIndex
        localConnect(ctrl,phMod.Outport(1),phNew.Inport(8));
        % 9 P selected
        localConnect(ctrl,phP.Outport(1),phNew.Inport(9));
        % 10 Q selected
        localConnect(ctrl,phQ.Outport(1),phNew.Inport(10));
        % 11 theta_exec selected
        localConnect(ctrl,phTheta.Outport(1),phNew.Inport(11));
        % 12 Freq_exec selected
        localConnect(ctrl,phFreq.Outport(1),phNew.Inport(12));
        % 13/14 native PLL raw theta/freq
        localConnect(ctrl,phMeas.Outport(9),phNew.Inport(13));
        localConnect(ctrl,phMeas.Outport(10),phNew.Inport(14));
        % 15 mode
        localConnect(ctrl,phMode.Outport(1),phNew.Inport(15));
        % 16/17 C1/C2 track enable
        localConnect(ctrl,phC1Gate.Outport(1),phNew.Inport(16));
        localConnect(ctrl,phC2Gate.Outport(1),phNew.Inport(17));

        localConnect(ctrl,phNew.Outport(1),phDiagOut.Inport(1));

        % V1.2 immediate logger wiring contract:
        % verify all 17 causal logger inputs have exactly the intended sources
        % before proceeding to update/postassert.
        localAssertLogger17Sources( ...
            newMux, ...
            { ...
              sprintf('%s|1',pcl), ...             % 01 raw IdIq_refF
              sprintf('%s|1',R(k).swIref), ...    % 02 applied IdIq_refs
              sprintf('%s|1',R(k).muxI), ...      % 03 applied IdIqs
              sprintf('%s|1',R(k).from26), ...    % 04 raw VdVqs
              sprintf('%s|1',R(k).c1Hold), ...    % 05 applied VdVqs
              sprintf('%s|2',ireg), ...            % 06 Current PI PIdq
              sprintf('%s|1',ireg), ...            % 07 VdVq_conv
              sprintf('%s|1',[ctrl '/From']), ...  % 08 ModIndex
              sprintf('%s|1',R(k).swP), ...        % 09 Pmeas
              sprintf('%s|1',R(k).swQ), ...        % 10 Qmeas
              sprintf('%s|1',[ctrl '/From12']), ...% 11 theta_exec selected
              sprintf('%s|1',R(k).swFreq), ...     % 12 Freq_exec selected
              sprintf('%s|9',meas), ...             % 13 native theta raw
              sprintf('%s|10',meas), ...            % 14 native freq raw
              sprintf('%s|1',R(k).mode), ...        % 15 causal mode
              sprintf('%s|1',R(k).c1Gate), ...      % 16 C1 track
              sprintf('%s|1',R(k).c2Gate) ...       % 17 C2 track
            }, ...
            dev);

        R(k).newMux=newMux;

        fprintf('[EDIT] %-4s causal logger remapped: 17 physical ports -> 24 scalars.\n',dev);
    end

    %% ====================================================================
    % 7. UPDATE + STRICT STRUCTURAL POSTASSERT
    % =====================================================================
    fprintf('\n--- 7. UPDATE + STRICT STRUCTURAL POSTASSERT ---\n');
    set_param(mdl,'SimulationCommand','update');

    for k=1:numel(R)
        dev=R(k).dev;
        ctrl=R(k).ctrl;
        meas=R(k).meas;
        hold=R(k).hold;
        ireg=R(k).ireg;
        pcl=R(k).pcl;

        % Mode default and intervention time.
        if localNumeric(localGet(R(k).mode,'Value'))~=0
            error('CAUSALHARNESS:ModeDefault','%s default causal mode is not 0.',dev);
        end
        if abs(localNumeric(localGet(R(k).cStep,'Time'))-T_INTERVENE)>1e-12
            error('CAUSALHARNESS:CStepTime','%s C hold Step time changed.',dev);
        end

        % B1 new interfaces exact.
        phMeas=get_param(meas,'PortHandles');
        phHold=get_param(hold,'PortHandles');
        if numel(phMeas.Inport)~=5 || numel(phMeas.Outport)~=12
            error('CAUSALHARNESS:MeasPost','%s Measurements postpatch interface wrong.',dev);
        end
        if numel(phHold.Inport)~=3 || numel(phHold.Outport)~=2
            error('CAUSALHARNESS:B1HoldPost','%s B1 hold postpatch interface wrong.',dev);
        end

        % Mode1 comparator must be exact sole source of Measurements/in5.
        srcB1=localSourceBlock(phMeas.Inport(5));
        if ~strcmp(srcB1,R(k).eq1)
            error('CAUSALHARNESS:B1ReqSource','%s Measurements/in5 not driven by mode==1.',dev);
        end

        % C1 raw/applied exact.
        phFrom26=get_param(R(k).from26,'PortHandles');
        phC1Hold=get_param(R(k).c1Hold,'PortHandles');
        phIreg=get_param(ireg,'PortHandles');

        localAssertHasDestination(phFrom26.Outport(1),R(k).c1Hold,1, ...
            sprintf('%s raw VdVqs -> C1',dev));

        % V1.2 FIX:
        % C1 applied VdVqs MUST intentionally fan out to TWO destinations:
        %   1) Current Regulator/in1  : actual control input
        %   2) causal logger/in5      : applied-VdVqs evidence
        % Therefore an exact-single-destination assertion is wrong here.
        localAssertExactDestinationSet( ...
            phC1Hold.Outport(1), ...
            {sprintf('%s|1',ireg), sprintf('%s|5',R(k).newMux)}, ...
            sprintf('%s C1 applied VdVqs control+logger fanout',dev));

        % C2 raw/applied exact.
        phPcl=get_param(pcl,'PortHandles');
        phC2Hold=get_param(R(k).c2Hold,'PortHandles');
        phGoto18=get_param(R(k).goto18,'PortHandles');

        localAssertHasDestination(phPcl.Outport(1),R(k).c2Hold,1, ...
            sprintf('%s raw IdIq_refF -> C2',dev));
        localAssertExactSingleDestination(phC2Hold.Outport(1),R(k).goto18,1, ...
            sprintf('%s C2 applied IdIq_refF -> Goto18',dev));

        % No direct old C1/C2 bypass edges remain.
        if localHasDestination(phFrom26.Outport(1),ireg,1)
            error('CAUSALHARNESS:C1BypassRemains', ...
                '%s direct From26->CurrentReg/in1 bypass still exists.',dev);
        end
        if localHasDestination(phPcl.Outport(1),R(k).goto18,1)
            error('CAUSALHARNESS:C2BypassRemains', ...
                '%s direct PowerControl->Goto18 bypass still exists.',dev);
        end

        % Logger path and physical ports.
        localReq(R(k).newMux);
        if localNumeric(localGet(R(k).newMux,'Inputs'))~=17
            error('CAUSALHARNESS:NewMuxPorts','%s new causal Mux Inputs !=17.',dev);
        end
        if getSimulinkBlockHandle([ctrl '/AA15_ROOTDIAG_MUX21PORT_24SCALAR'])>=0
            error('CAUSALHARNESS:OldMuxStillExists','%s old rootdiag Mux still exists.',dev);
        end

        phNew=get_param(R(k).newMux,'PortHandles');
        localAssertExactSingleDestination(phNew.Outport(1),R(k).diagOut,1, ...
            sprintf('%s causal Mux -> existing Out24',dev));

        % Control output3 remains exactly the existing diagnostic output.
        cph=get_param(ctrl,'PortHandles');
        if numel(cph.Outport)~=3
            error('CAUSALHARNESS:ControlOutCount', ...
                '%s expected exactly 3 outputs after patch.',dev);
        end
        if localNumeric(localGet(R(k).diagOut,'Port'))~=3
            error('CAUSALHARNESS:DiagPort3','%s diagnostic Outport no longer Port3.',dev);
        end

        fprintf('[PASS] %-4s structural postassert exact.\n',dev);
    end

    %% ====================================================================
    % 8. EXPLICIT COMPILE-STATE WIDTH / MODE CONTRACT AUDIT
    % =====================================================================
    fprintf('\n--- 8. EXPLICIT COMPILE-STATE WIDTH AUDIT ---\n');

    evPair=[ss1 '/AA15_ROOTDIAG_EV12_MUX2'];
    pvPair=[ss3 '/AA15_ROOTDIAG_PV12_MUX2'];
    localReq(evPair); localReq(pvPair);

    localAuditCompiledWidths(mdl,R,evPair,pvPair,op26,op27,op28);

    fprintf('[PASS] Explicit compile-state causal widths exact.\n');

    %% ====================================================================
    % 9. EXACT FIVE-OPWRITE / FROZEN GROUP POSTASSERT
    % =====================================================================
    fprintf('\n--- 9. FINAL FIVE-OPWRITE / FROZEN GROUP POSTASSERT ---\n');

    ops1=localFindAllOpWrites(mdl);
    if numel(ops1)~=5
        error('CAUSALHARNESS:FinalOpCount','Final OpWrite count is %d, not 5.',numel(ops1));
    end

    groups=zeros(1,5);
    for i=1:5
        groups(i)=localReadNumericMask(ops1{i},'Acq_Group');
    end
    if ~isequal(sort(groups),26:30)
        error('CAUSALHARNESS:FinalGroups','Final acquisition groups are not exactly 26:30.');
    end

    % Paths remain exact.
    finalMap=cell(1,31);
    for i=1:numel(ops1)
        g=localReadNumericMask(ops1{i},'Acq_Group');
        finalMap{g}=ops1{i};
    end
    if ~strcmp(finalMap{26},exp26), error('CAUSALHARNESS:FinalG26','G26 changed.'); end
    if ~strcmp(finalMap{27},exp27), error('CAUSALHARNESS:FinalG27','G27 changed.'); end
    if ~strcmp(finalMap{28},exp28), error('CAUSALHARNESS:FinalG28','G28 changed.'); end
    if ~strcmp(finalMap{29},exp29), error('CAUSALHARNESS:FinalG29','G29 changed.'); end
    if ~strcmp(finalMap{30},exp30), error('CAUSALHARNESS:FinalG30','G30 changed.'); end

    if localNumeric(localGet(g29Mux,'Inputs'))~=38
        error('CAUSALHARNESS:G29Post','G29 Mux changed.');
    end
    if localNumeric(localGet(g30Mux,'Inputs'))~=63
        error('CAUSALHARNESS:G30Post','G30 Mux changed.');
    end

    % Verify OpWrite source descriptors unchanged.
    for i=1:numel(ops0)
        g=localReadNumericMask(ops0{i},'Acq_Group');
        oldDesc=opSrc0{i};
        newDesc=localSourceDescriptor(localGetInportHandle(finalMap{g},1));
        if ~strcmp(oldDesc,newDesc)
            error('CAUSALHARNESS:OpSourceChanged', ...
                'G%d source changed: %s -> %s',g,oldDesc,newDesc);
        end
    end

    fprintf('[PASS] Final OpWrite count exactly 5; G26~G30 allocation unchanged.\n');
    fprintf('[PASS] G29/G30 source/width contracts unchanged.\n');

    %% ====================================================================
    % 10. SAVE ONCE
    % =====================================================================
    fprintf('\n--- 10. SAVE ONCE ---\n');
    save_system(mdl);
    saved=true;
    fprintf('[SAVE PASS] %s\n',modelFile);

    %% ====================================================================
    % 11. CLOSE / RELOAD PERSISTENT AUDIT
    % =====================================================================
    fprintf('\n--- 11. CLOSE / RELOAD PERSISTENT AUDIT ---\n');

    close_system(mdl,0);
    load_system(modelFile);
    mdl=modelBase;

    if ~strcmpi(localGet(mdl,'Dirty'),'off')
        error('CAUSALHARNESS:ReloadDirty','Reloaded model Dirty=on.');
    end

    % Rebuild paths after reload.
    specReload = {
        'PV1',  [mdl '/SS_Slave3/PV1_Control'];
        'PV2',  [mdl '/SS_Slave3/PV2_Control'];
        'ESS2', [mdl '/SS_Slave2/ESS2_Control'];
        'EV1',  [mdl '/SS_Slave/EV1_Control'];
        'EV2',  [mdl '/SS_Slave/Control System'];
    };

    for k=1:size(specReload,1)
        dev=specReload{k,1};
        ctrl=specReload{k,2};
        meas=[ctrl '/Measurements'];
        hold=[meas '/AA15_PLL_EXEC_FRAME_HOLD'];

        localReq([ctrl '/AA15_CAUSAL_MODE']);
        localReq([ctrl '/AA15_C1_VDQ_TRACK_HOLD']);
        localReq([ctrl '/AA15_C2_IREF_TRACK_HOLD']);
        localReq([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR']);
        localReq([meas '/AA15_B1_HOLD_REQ']);
        localReq([hold '/AA15_B1_HOLD_REQ']);
        localReq([hold '/AA15_B1_TRACK_GATE']);

        if localNumeric(localGet([ctrl '/AA15_CAUSAL_MODE'],'Value'))~=0
            error('CAUSALHARNESS:ReloadMode','%s reloaded default mode !=0.',dev);
        end
        if localNumeric(localGet([ctrl '/AA15_CAUSALDIAG_MUX17PORT_24SCALAR'],'Inputs'))~=17
            error('CAUSALHARNESS:ReloadMux','%s reloaded causal diag Mux !=17 ports.',dev);
        end

        fprintf('[PASS] %-4s persistent causal harness present; default Mode0.\n',dev);
    end

    opsReload=localFindAllOpWrites(mdl);
    if numel(opsReload)~=5
        error('CAUSALHARNESS:ReloadOps','Reloaded model does not contain exactly 5 OpWrites.');
    end

    fprintf('\n====================================================================================================\n');
    fprintf(' CAUSAL HARNESS PATCH PASS\n');
    fprintf('====================================================================================================\n');
    fprintf('Backup : %s\n',backupFile);
    fprintf('Log    : %s\n',logFile);
    fprintf('Model  : %s\n',modelFile);
    fprintf('\nMODE CONTRACT:\n');
    fprintf('  0 C0 baseline : B1 TRACK, C1 TRACK, C2 TRACK\n');
    fprintf('  1 B1 repro    : B1 TRACK->HOLD, C1 TRACK, C2 TRACK\n');
    fprintf('  2 C1          : B1 TRACK, C1 TRACK->HOLD, C2 TRACK\n');
    fprintf('  3 C2          : B1 TRACK, C1 TRACK, C2 TRACK->HOLD\n');
    fprintf('  4 C3          : B1 TRACK, C1 TRACK->HOLD, C2 TRACK->HOLD\n');
    fprintf('\nNEW GFL DIAG24 MAP:\n');
    fprintf('  01-02 raw Id/Iq_refF\n');
    fprintf('  03-04 applied Id/Iq_ref\n');
    fprintf('  05-06 applied Id/Iq_meas\n');
    fprintf('  07-08 raw Vd/VqVqs\n');
    fprintf('  09-10 applied Vd/VqVqs\n');
    fprintf('  11-12 Current PI d/q\n');
    fprintf('  13-14 Vd/Vq_conv\n');
    fprintf('  15 ModIndex, 16 P, 17 Q\n');
    fprintf('  18 theta_exec, 19 Freq_exec\n');
    fprintf('  20 theta_native_PLL, 21 Freq_native_PLL\n');
    fprintf('  22 CAUSAL_MODE, 23 C1_TRACK, 24 C2_TRACK\n');
    fprintf('\nNEXT:\n');
    fprintf('  1) STOP. Do NOT Rebuild yet.\n');
    fprintf('  2) Upload this patch TXT for review.\n');
    fprintf('  3) After review only: RT-LAB Rebuild All once.\n');
    fprintf('  4) After Build: C0 transparency regression is mandatory before C1.\n');
    fprintf('====================================================================================================\n');

catch ME
    fprintf(2,'\n[PATCH ERROR] %s\n',ME.message);
    fprintf(2,'%s\n',getReport(ME,'extended','hyperlinks','off'));

    if editStarted
        fprintf(2,'\n[ROLLBACK] Restoring exact PREPATCH SLX...\n');
        try
            if bdIsLoaded(modelBase)
                close_system(modelBase,0);
            end
        catch
        end

        if isfile(backupFile)
            [ok,msg]=copyfile(backupFile,modelFile,'f');
            if ~ok
                fprintf(2,'[ROLLBACK COPY FAILED] %s\n',msg);
            else
                try
                    load_system(modelFile);
                    fprintf(2,'[ROLLBACK PASS] Exact backup restored and reloaded.\n');
                catch ME2
                    fprintf(2,'[ROLLBACK RELOAD FAILED] %s\n',ME2.message);
                end
            end
        end
    end

    rethrow(ME);
end

if ~saved
    error('CAUSALHARNESS:NotSaved','Patch ended without successful save.');
end

end

%% =========================================================================
% Create a 2-vector transparent-track / last-sample-hold subsystem.
% Inputs:
%   1 raw vector
%   2 track_enable scalar
% Output:
%   1 applied vector
% ==========================================================================
function localCreateVectorTrackHold(ss,TS_EXPR,pos)

add_block('built-in/SubSystem',ss,'Position',pos);

add_block('built-in/Inport',[ss '/Raw'], ...
    'Port','1','Position',[25 35 55 49]);
add_block('built-in/Inport',[ss '/TRACK_ENABLE'], ...
    'Port','2','Position',[25 85 55 99]);
add_block('built-in/Outport',[ss '/Applied'], ...
    'Port','1','Position',[365 45 395 59]);

add_block('simulink/Discrete/Unit Delay',[ss '/Held_State'], ...
    'InitialCondition','0', ...
    'SampleTime',TS_EXPR, ...
    'Position',[190 115 240 145]);

add_block('simulink/Signal Routing/Switch',[ss '/TrackOrHold'], ...
    'Criteria','u2 > Threshold', ...
    'Threshold','0.5', ...
    'Position',[180 35 225 80]);

% Local Goto/From fanout for applied output -> state and Outport.
add_block('simulink/Signal Routing/Goto',[ss '/Goto_APPLIED'], ...
    'GotoTag','AA15_APPLIED', ...
    'TagVisibility','local', ...
    'Position',[265 47 335 67]);

add_block('simulink/Signal Routing/From',[ss '/From_APPLIED_Out'], ...
    'GotoTag','AA15_APPLIED', ...
    'Position',[275 20 345 40]);

add_block('simulink/Signal Routing/From',[ss '/From_APPLIED_State'], ...
    'GotoTag','AA15_APPLIED', ...
    'Position',[95 120 165 140]);

phRaw=get_param([ss '/Raw'],'PortHandles');
phEn=get_param([ss '/TRACK_ENABLE'],'PortHandles');
phState=get_param([ss '/Held_State'],'PortHandles');
phSw=get_param([ss '/TrackOrHold'],'PortHandles');
phGoto=get_param([ss '/Goto_APPLIED'],'PortHandles');
phFromOut=get_param([ss '/From_APPLIED_Out'],'PortHandles');
phFromState=get_param([ss '/From_APPLIED_State'],'PortHandles');
phOut=get_param([ss '/Applied'],'PortHandles');

localConnect(ss,phRaw.Outport(1),phSw.Inport(1));
localConnect(ss,phEn.Outport(1),phSw.Inport(2));
localConnect(ss,phState.Outport(1),phSw.Inport(3));
localConnect(ss,phSw.Outport(1),phGoto.Inport(1));

localConnect(ss,phFromOut.Outport(1),phOut.Inport(1));
localConnect(ss,phFromState.Outport(1),phState.Inport(1));

end

%% =========================================================================
% Add mode==N using Constant(N) + Relational Operator.
% Returns relational block path.
% ==========================================================================
function rel=localAddModeEq(ctrl,mode,n,xy)

x=xy(1); y=xy(2);
c=[ctrl sprintf('/AA15_MODE_CONST_%d',n)];
rel=[ctrl sprintf('/AA15_MODE_EQ_%d',n)];

add_block('simulink/Sources/Constant',c, ...
    'Value',num2str(n), ...
    'SampleTime','inf', ...
    'Position',[x y x+35 y+20]);

add_block('simulink/Logic and Bit Operations/Relational Operator',rel, ...
    'Operator','==', ...
    'Position',[x+70 y-2 x+110 y+22]);

phMode=get_param(mode,'PortHandles');
phC=get_param(c,'PortHandles');
phRel=get_param(rel,'PortHandles');

localConnect(ctrl,phMode.Outport(1),phRel.Inport(1));
localConnect(ctrl,phC.Outport(1),phRel.Inport(2));

end

%% =========================================================================
% Explicit compile-state width audit.
% ==========================================================================
function localAuditCompiledWidths(mdl,R,evPair,pvPair,op26,op27,op28)

terminatedKey=['CAUSALHARNESS_COMPILE_TERMINATED_' mdl];
try
    if isappdata(0,terminatedKey), rmappdata(0,terminatedKey); end
catch
end
cleanupObj=onCleanup(@()localTerminateCompileIfNeeded(mdl,terminatedKey)); %#ok<NASGU>

try
    feval(mdl,[],[],[],'compile');
catch ME
    error('CAUSALHARNESS:CompileStart', ...
        'Explicit Simulink compile failed: %s',ME.message);
end

for k=1:numel(R)
    dev=R(k).dev;
    ctrl=R(k).ctrl;

    phMode=get_param(R(k).mode,'PortHandles');
    phC1Gate=get_param(R(k).c1Gate,'PortHandles');
    phC2Gate=get_param(R(k).c2Gate,'PortHandles');
    phC1Hold=get_param(R(k).c1Hold,'PortHandles');
    phC2Hold=get_param(R(k).c2Hold,'PortHandles');
    phNew=get_param(R(k).newMux,'PortHandles');
    cph=get_param(ctrl,'PortHandles');

    localAssertCompiledWidth(phMode.Outport(1),1,[dev ' mode']);
    localAssertCompiledWidth(phC1Gate.Outport(1),1,[dev ' C1 track enable']);
    localAssertCompiledWidth(phC2Gate.Outport(1),1,[dev ' C2 track enable']);
    localAssertCompiledWidth(phC1Hold.Outport(1),2,[dev ' C1 applied VdVqs']);
    localAssertCompiledWidth(phC2Hold.Outport(1),2,[dev ' C2 applied IdIq_refF']);
    localAssertCompiledWidth(phNew.Outport(1),24,[dev ' causal diag24']);

    if numel(cph.Outport)~=3
        error('CAUSALHARNESS:CompiledControlOut','%s compiled output count !=3.',dev);
    end
    localAssertCompiledWidth(cph.Outport(3),24,[dev ' control output3']);
end

phEv=get_param(evPair,'PortHandles');
phPv=get_param(pvPair,'PortHandles');
localAssertCompiledWidth(phEv.Outport(1),48,'EV pair diagnostic vector');
localAssertCompiledWidth(phPv.Outport(1),48,'PV pair diagnostic vector');

localAssertCompiledWidth(localGetInportHandle(op26,1),48,'G26 input');
localAssertCompiledWidth(localGetInportHandle(op27,1),24,'G27 input');
localAssertCompiledWidth(localGetInportHandle(op28,1),48,'G28 input');

fprintf('[COMPILED WIDTH PASS] all five C1/C2 outputs=2; diag24=24; pairs/opwrites unchanged.\n');

try
    feval(mdl,[],[],[],'term');
    setappdata(0,terminatedKey,true);
catch ME
    error('CAUSALHARNESS:CompileTerminate', ...
        'Compile audit passed but terminate failed: %s',ME.message);
end

end

function localAssertCompiledWidth(portH,expected,label)
try
    w=get_param(portH,'CompiledPortWidth');
catch ME
    error('CAUSALHARNESS:WidthUnavailable', ...
        'Cannot read compiled width for %s: %s',label,ME.message);
end
if isempty(w) || ~isnumeric(w) || numel(w)~=1 || w~=expected
    error('CAUSALHARNESS:Width', ...
        '%s expected compiled width=%d, got %s.',label,expected,mat2str(w));
end
end

function localTerminateCompileIfNeeded(mdl,key)
already=false;
try
    already=isappdata(0,key) && getappdata(0,key);
catch
end
if ~already
    try feval(mdl,[],[],[],'term'); catch, end
end
try
    if isappdata(0,key), rmappdata(0,key); end
catch
end
end

%% =========================================================================
% Structural helpers.
% ==========================================================================

function localAssertLogger17Sources(newMux,expected,dev)
ph=get_param(newMux,'PortHandles');
if numel(ph.Inport)~=17
    error('CAUSALHARNESS:Logger17Count', ...
        '%s causal logger expected 17 physical inputs, got %d.',dev,numel(ph.Inport));
end
if numel(expected)~=17
    error('CAUSALHARNESS:Logger17Internal', ...
        '%s internal expected-source list is not length 17.',dev);
end

for ii=1:17
    ln=get_param(ph.Inport(ii),'Line');
    if isempty(ln)||ln<0
        error('CAUSALHARNESS:Logger17Unconnected', ...
            '%s causal logger/in%d is unconnected.',dev,ii);
    end
    sh=get_param(ln,'SrcPortHandle');
    if isempty(sh)||sh<0
        error('CAUSALHARNESS:Logger17NoSource', ...
            '%s causal logger/in%d source cannot be resolved.',dev,ii);
    end
    actual=sprintf('%s|%d',get_param(sh,'Parent'),get_param(sh,'PortNumber'));
    if ~strcmp(actual,expected{ii})
        error('CAUSALHARNESS:Logger17WrongSource', ...
            '%s causal logger/in%d expected %s, got %s.', ...
            dev,ii,expected{ii},actual);
    end
end
fprintf('[PASS] %-4s all 17 causal logger physical inputs have exact intended sources.\n',dev);
end

function localDisconnectIncomingBranch(inH,label)
% Delete ONLY the branch ending at this destination port.
% This preserves all other destinations on the same source signal line.

if isempty(inH) || inH<0
    error('CAUSALHARNESS:DisconnectHandle','%s invalid destination handle.',label);
end

ln=get_param(inH,'Line');
if isempty(ln) || ln<0
    return;
end

srcH=get_param(ln,'SrcPortHandle');
if isempty(srcH) || srcH<0
    error('CAUSALHARNESS:DisconnectSource', ...
        '%s is connected but source port cannot be resolved.',label);
end

dstBlock=get_param(inH,'Parent');
sys=get_param(dstBlock,'Parent');

try
    delete_line(sys,srcH,inH);
catch ME
    error('CAUSALHARNESS:DisconnectBranch', ...
        '%s branch-only delete failed: %s',label,ME.message);
end

ln2=get_param(inH,'Line');
if ~(isempty(ln2) || ln2<0)
    error('CAUSALHARNESS:DisconnectResidual', ...
        '%s still has an incoming signal after branch-only delete.',label);
end
end

function localAssertInportUnconnected(inH,label)
if isempty(inH) || inH<0
    error('CAUSALHARNESS:InportHandle','%s invalid inport handle.',label);
end
ln=get_param(inH,'Line');
if ~(isempty(ln) || ln<0)
    src=localSourceBlock(inH);
    error('CAUSALHARNESS:InportOccupied', ...
        '%s unexpectedly remains connected from %s.',label,src);
end
end

function localEnsureInportFree(inH,label)
% A brand-new destination should be free. If Simulink auto-attached a
% geometric/dangling line because of placement, remove only that branch.
ln=get_param(inH,'Line');
if isempty(ln) || ln<0
    return;
end

src=localSourceBlock(inH);
fprintf('[CLEAN] %s had an unexpected auto-attached source %s; removing destination branch only.\n', ...
    label,src);

localDisconnectIncomingBranch(inH,label);
localAssertInportUnconnected(inH,label);
end

function localAssertInportSourceTag(ss,inNo,tag,dev)
ph=get_param(ss,'PortHandles');
if numel(ph.Inport)<inNo
    error('CAUSALHARNESS:InportMissing','%s %s missing in%d.',dev,ss,inNo);
end
src=localSourceBlock(ph.Inport(inNo));
if isempty(src) || ~strcmp(localGet(src,'BlockType'),'From') || ...
        ~strcmp(localGet(src,'GotoTag'),tag)
    error('CAUSALHARNESS:InportTag', ...
        '%s %s/in%d expected From tag=%s; got %s.',dev,ss,inNo,tag,src);
end
end

function localAssertBlockFeedsGoto(src,goto,tag,dev)
if ~strcmp(localGet(goto,'BlockType'),'Goto') || ~strcmp(localGet(goto,'GotoTag'),tag)
    error('CAUSALHARNESS:GotoTag','%s expected %s tag=%s.',dev,goto,tag);
end
phS=get_param(src,'PortHandles');
phG=get_param(goto,'PortHandles');
if isempty(phS.Outport) || isempty(phG.Inport)
    error('CAUSALHARNESS:BlockPorts','%s source/goto ports missing.',dev);
end
if ~localHasDestination(phS.Outport(1),goto,1)
    error('CAUSALHARNESS:BlockGotoEdge','%s %s does not feed %s.',dev,src,goto);
end
end

function localAssertExactDestinationSet(outH,expected,label)
% Assert an exact, order-independent destination set.
% expected is a cell array of '<block>|<port>' strings.
d=sort(localDestTuples(outH));
e=sort(expected(:));
if ~isequal(d(:),e(:))
    fprintf(2,'[%s] actual destinations:\n',label);
    for i=1:numel(d), fprintf(2,'  %s\n',d{i}); end
    fprintf(2,'[%s] expected destinations:\n',label);
    for i=1:numel(e), fprintf(2,'  %s\n',e{i}); end
    error('CAUSALHARNESS:ExactDestinationSet', ...
        '%s exact destination-set contract failed.',label);
end
end

function localAssertExactSingleDestination(outH,dstBlock,dstPort,label)
d=localDestTuples(outH);
exp={sprintf('%s|%d',dstBlock,dstPort)};
if ~isequal(sort(d(:)),sort(exp(:)))
    fprintf(2,'[%s] actual destinations:\n',label);
    for i=1:numel(d), fprintf(2,'  %s\n',d{i}); end
    error('CAUSALHARNESS:ExactDestination','%s exact single-destination contract failed.',label);
end
end

function localAssertHasDestination(outH,dstBlock,dstPort,label)
if ~localHasDestination(outH,dstBlock,dstPort)
    error('CAUSALHARNESS:MissingDestination','%s destination missing.',label);
end
end

function tf=localHasDestination(outH,dstBlock,dstPort)
tf=false;
ln=get_param(outH,'Line');
if isempty(ln)||ln<0, return; end
dh=get_param(ln,'DstPortHandle');
dh=dh(dh>=0);
for i=1:numel(dh)
    if strcmp(get_param(dh(i),'Parent'),dstBlock) && ...
       get_param(dh(i),'PortNumber')==dstPort
        tf=true;
        return;
    end
end
end

function localDeleteExactSingleLine(srcH,dstH,label)
% This helper is used only after preflight has proven src has exactly one
% destination and that destination is dstH. Deleting the whole line is then
% safe because no other branch exists.
ln=get_param(srcH,'Line');
if isempty(ln)||ln<0
    error('CAUSALHARNESS:DeleteLineMissing','%s source line missing.',label);
end
dh=get_param(ln,'DstPortHandle');
dh=dh(dh>=0);
if numel(dh)~=1 || dh(1)~=dstH
    error('CAUSALHARNESS:DeleteLineNotSingle', ...
        '%s is no longer an exact single-edge line.',label);
end
delete_line(ln);
end

function dst=localDestTuples(outH)
dst={};
ln=get_param(outH,'Line');
if isempty(ln)||ln<0, return; end
dh=get_param(ln,'DstPortHandle');
dh=dh(dh>=0);
for i=1:numel(dh)
    dst{end+1,1}=sprintf('%s|%d', ...
        get_param(dh(i),'Parent'),get_param(dh(i),'PortNumber')); %#ok<AGROW>
end
end

function src=localSourceBlock(inH)
src='';
try
    ln=get_param(inH,'Line');
    if isempty(ln)||ln<0, return; end
    sh=get_param(ln,'SrcPortHandle');
    if isempty(sh)||sh<0, return; end
    src=get_param(sh,'Parent');
catch
    src='';
end
end

function localConnect(sys,srcH,dstH)
if isempty(srcH)||isempty(dstH)||srcH<0||dstH<0
    error('CAUSALHARNESS:ConnectHandle','Invalid port handle in %s.',sys);
end
add_line(sys,srcH,dstH,'autorouting','on');
end

function pos=localRightmostPosition(parent)
blocks=find_system(parent,'SearchDepth',1,'Type','Block');
best=[100 100 200 150];
for i=1:numel(blocks)
    if strcmp(blocks{i},parent), continue; end
    try
        p=get_param(blocks{i},'Position');
        if numel(p)==4 && p(3)>best(3)
            best=p;
        end
    catch
    end
end
pos=best;
end

%% =========================================================================
% OpWrite helpers.
% ==========================================================================
function ops=localFindAllOpWrites(mdl)
blocks=find_system(mdl, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'Type','Block');
ops={};
for i=1:numel(blocks)
    ref=localGet(blocks{i},'ReferenceBlock');
    src=localGet(blocks{i},'SourceBlock');
    mtype=localGet(blocks{i},'MaskType');
    txt=lower([ref ' ' src ' ' mtype]);
    if contains(txt,'opwritefile')
        ops{end+1,1}=blocks{i}; %#ok<AGROW>
    end
end
ops=unique(ops);
end

function v=localReadNumericMask(block,param)
s='';
try
    s=get_param(block,param);
catch
    try
        names=get_param(block,'MaskNames');
        vals=get_param(block,'MaskValues');
        idx=find(strcmp(names,param),1);
        if ~isempty(idx), s=vals{idx}; end
    catch
    end
end
v=str2double(char(string(s)));
if isnan(v)
    try
        v=evalin('base',char(string(s)));
    catch
        v=NaN;
    end
end
end

function localAssertMaskNumeric(block,param,expected)
v=localReadNumericMask(block,param);
if ~isfinite(v) || abs(v-expected)>1e-12
    error('CAUSALHARNESS:MaskAssert', ...
        '%s %s expected %g, got %g.',block,param,expected,v);
end
end

function h=localGetInportHandle(block,index)
ph=get_param(block,'PortHandles');
if numel(ph.Inport)<index
    error('CAUSALHARNESS:Inport','%s missing inport%d.',block,index);
end
h=ph.Inport(index);
end

function s=localSourceDescriptor(inH)
s='<unconnected>';
try
    ln=get_param(inH,'Line');
    if isempty(ln)||ln<0, return; end
    sh=get_param(ln,'SrcPortHandle');
    if isempty(sh)||sh<0, return; end
    s=sprintf('%s/out%d',get_param(sh,'Parent'),get_param(sh,'PortNumber'));
catch
end
end

%% =========================================================================
% Generic helpers.
% ==========================================================================
function localReq(p)
if getSimulinkBlockHandle(p)<0
    error('CAUSALHARNESS:Missing','Missing required block: %s',localOneLine(p));
end
end

function v=localNumeric(x)
if isnumeric(x)
    v=double(x);
else
    v=str2double(strtrim(char(string(x))));
end
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

function s=localOneLine(s)
s=char(s);
s=regexprep(s,'\s+',' ');
s=strtrim(s);
end

function localDiaryOff()
try diary off; catch, end
end

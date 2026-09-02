function AUDIT_K26_V5_GFL_PLL_FRAME_ACTUATION_PATH_PREAB_V1
% AUDIT_K26_V5_GFL_PLL_FRAME_ACTUATION_PATH_PREAB_V1
%
% READ-ONLY structural audit before the final PLL/frame isolation A/B.
%
% PURPOSE
% -------
% Natural R3 data has already localized the observational primary initiator
% to the five GFL SRF-PLL / frame dynamics.
%
% BEFORE any A/B patch, this audit must establish the ACTUAL execution paths:
%
%   1) wt_PLL -> wt_selected -> every angle-dependent consumer
%   2) local PLL-frame Vd/Vq -> Current Regulator voltage feedforward
%   3) Current Regulator exact structural composition of VdVq_conv
%   4) all other local-PLL-derived actuation paths
%
% This prevents a false A/B where wt_selected is isolated but PLL-frame
% voltage feedforward remains active.
%
% ABSOLUTE SAFETY
% ---------------
% NO set_param
% NO add_block / delete_block
% NO add_line / delete_line
% NO save_system
% NO SimulationCommand
% NO Build / Load / Execute / Reset
%
% RUN
% ---
% 1) Open CURRENT canonical K26_V5.slx.
% 2) Ensure model Dirty=off.
% 3) Click once anywhere inside K26_V5.
% 4) Run:
%      AUDIT_K26_V5_GFL_PLL_FRAME_ACTUATION_PATH_PREAB_V1
%
% Send back ONLY the generated TXT.
%
% 2026-09-01
% -------------------------------------------------------------------------

clc;

mdl = bdroot(gcs);
if isempty(mdl)
    error('PREAB:NoModel', ...
        'Open current K26_V5 and click inside the model first.');
end
load_system(mdl);

if ~contains(mdl,'K26_V5')
    error('PREAB:WrongModel','Expected K26_V5, got %s.',mdl);
end

if ~strcmpi(localSafeGet(mdl,'Dirty'),'off')
    error('PREAB:Dirty', ...
        'Model Dirty=on. Save/reload the canonical model before this READ-ONLY audit.');
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
outFile = fullfile(pwd, ...
    ['AUDIT_K26_V5_GFL_PLL_FRAME_ACTUATION_PATH_PREAB_V1_output_' stamp '.txt']);

diary(outFile);
cleanupObj = onCleanup(@()localCloseDiary()); %#ok<NASGU>

fprintf('\n====================================================================================================\n');
fprintf(' K26_V5 GFL PLL/FRAME ACTUATION-PATH PRE-A/B AUDIT V1  [STRICT READ ONLY]\n');
fprintf('====================================================================================================\n');
fprintf('Model : %s\n',mdl);
fprintf('File  : %s\n',localSafeGet(mdl,'FileName'));
fprintf('Dirty : %s\n',localSafeGet(mdl,'Dirty'));
fprintf('Time  : %s\n',datestr(now,31));
fprintf(['\nScientific target:\n' ...
         '  Determine exactly which local-PLL-derived paths must be isolated together\n' ...
         '  to create a CLEAN causal A/B, without changing Current PI / plant / F25.\n']);

%% =========================================================================
% 1. Resolve five GFL control subsystems
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 1. RESOLVE FIVE GFL CONTROLS\n');
fprintf('====================================================================================================\n');

spec = {
    'PV1',  [mdl '/SS_Slave3'], {'PV1_Control'};
    'PV2',  [mdl '/SS_Slave3'], {'PV2_Control'};
    'ESS2', [mdl '/SS_Slave2'], {'ESS2_Control'};
    'EV1',  [mdl '/SS_Slave'],  {'EV1_Control'};
    'EV2',  [mdl '/SS_Slave'],  {'Control System','EV2_Control'};
};

R = cell(size(spec,1),3);

for k=1:size(spec,1)
    dev=spec{k,1};
    parent=spec{k,2};
    aliases=spec{k,3};

    ctrl='';
    for a=1:numel(aliases)
        p=[parent '/' aliases{a}];
        if getSimulinkBlockHandle(p)>=0
            ctrl=p;
            break;
        end
    end

    if isempty(ctrl)
        % Strict fingerprint fallback; terminators do not pass.
        cands=find_system(parent,'SearchDepth',1,'Type','Block');
        keep={};
        for i=1:numel(cands)
            c=cands{i};
            if strcmp(c,parent), continue; end
            if getSimulinkBlockHandle([c '/Measurements'])>=0 && ...
               getSimulinkBlockHandle([c '/Current Regulator'])>=0
                keep{end+1,1}=c; %#ok<AGROW>
            end
        end
        if numel(keep)~=1
            fprintf('[CANDIDATES] %s under %s:\n',dev,parent);
            for i=1:numel(keep), fprintf('  %s\n',keep{i}); end
            error('PREAB:ResolveControl', ...
                'Cannot uniquely resolve %s control.',dev);
        end
        ctrl=keep{1};
    end

    R{k,1}=dev; R{k,2}=parent; R{k,3}=ctrl;
    fprintf('[PASS] %-4s -> %s | LinkStatus=%s\n', ...
        dev,ctrl,localSafeGet(ctrl,'LinkStatus'));
end

%% =========================================================================
% 2. Per-device PLL source inventory
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 2. PLL / MEASUREMENTS OUTPUTS AND THEIR REAL PARENT-LEVEL DESTINATIONS\n');
fprintf('====================================================================================================\n');

pllNames={'wt_PLL','Freq_PLL','VdVq_measPLL','IdIq_measPLL','P_meas_PLL','Q_meas_PLL'};

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3};
    meas=[ctrl '/Measurements'];

    fprintf('\n--- %s ---\n',dev);
    fprintf('Measurements = %s\n',meas);

    if getSimulinkBlockHandle(meas)<0
        fprintf('[FAIL] Measurements missing.\n');
        continue;
    end

    for q=1:numel(pllNames)
        nm=pllNames{q};
        op=find_system(meas,'SearchDepth',1,'BlockType','Outport','Name',nm);
        if numel(op)~=1
            fprintf('[WARN] %-16s exact Outport not uniquely found (count=%d).\n',nm,numel(op));
            continue;
        end
        portNum=str2double(localSafeGet(op{1},'Port'));
        fprintf('%-16s internal=%s | Port=%g\n',nm,op{1},portNum);

        mph=get_param(meas,'PortHandles');
        if isfinite(portNum) && portNum>=1 && portNum<=numel(mph.Outport)
            fprintf('  parent-level destinations:\n');
            localPrintOutputDestinations(mph.Outport(portNum),'    ');
        end
    end
end

%% =========================================================================
% 3. Goto/From tag execution map: wts/theta, Vdq, Idq, Freq
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 3. PLL/SELECTED-FRAME GOTO/FROM EXECUTION MAP\n');
fprintf('====================================================================================================\n');
fprintf(['Tags are printed from REAL connectivity. In particular, inspect:\n' ...
         '  wts / thetaF / Freq / FreqF / VdVqs / VdVqF / IdIqs / IdIqF\n']);

tags={'wts','thetaF','Freq','FreqF','VdVqs','VdVqF','IdIqs','IdIqF','Vref','ModIndex'};

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3};
    fprintf('\n--- %s ---\n',dev);

    for q=1:numel(tags)
        tag=tags{q};

        gs=find_system(ctrl,'SearchDepth',1, ...
            'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
        hitsG={};
        for i=1:numel(gs)
            if strcmp(localSafeGet(gs{i},'GotoTag'),tag)
                hitsG{end+1,1}=gs{i}; %#ok<AGROW>
            end
        end

        fs=find_system(ctrl,'SearchDepth',1, ...
            'LookUnderMasks','all','FollowLinks','on','BlockType','From');
        hitsF={};
        for i=1:numel(fs)
            if strcmp(localSafeGet(fs{i},'GotoTag'),tag)
                hitsF{end+1,1}=fs{i}; %#ok<AGROW>
            end
        end

        if isempty(hitsG) && isempty(hitsF), continue; end

        fprintf('TAG %-10s\n',tag);

        for i=1:numel(hitsG)
            ph=get_param(hitsG{i},'PortHandles');
            fprintf('  GOTO %s <- %s\n', ...
                hitsG{i},localInputSource(ph.Inport(1)));
        end

        for i=1:numel(hitsF)
            ph=get_param(hitsF{i},'PortHandles');
            fprintf('  FROM %s ->\n',hitsF{i});
            if ~isempty(ph.Outport)
                localPrintOutputDestinations(ph.Outport(1),'      ');
            end
        end
    end
end

%% =========================================================================
% 4. Top-level switches: actual selected path under ConnectMode/GRIDON
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 4. TOP-LEVEL SELECTOR/SWITCH MAP\n');
fprintf('====================================================================================================\n');
fprintf(['This section identifies whether local PLL quantities are selected into the\n' ...
         'actual GFL execution path, rather than merely logged.\n']);

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3};
    fprintf('\n--- %s ---\n',dev);

    sw=find_system(ctrl,'SearchDepth',1,'BlockType','Switch');
    for i=1:numel(sw)
        ph=get_param(sw{i},'PortHandles');
        if numel(ph.Inport)<3, continue; end

        fprintf('Switch %s | Threshold=%s | Criteria=%s\n', ...
            sw{i},localSafeGet(sw{i},'Threshold'),localSafeGet(sw{i},'Criteria'));
        fprintf('  u1 = %s\n',localInputSource(ph.Inport(1)));
        fprintf('  u2 = %s\n',localInputSource(ph.Inport(2)));
        fprintf('  u3 = %s\n',localInputSource(ph.Inport(3)));
        fprintf('  out destinations:\n');
        localPrintOutputDestinations(ph.Outport(1),'    ');
    end
end

%% =========================================================================
% 5. Current Regulator external input contract
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 5. CURRENT REGULATOR EXTERNAL INPUTS + ACTUAL PARENT SOURCES\n');
fprintf('====================================================================================================\n');
fprintf(['Critical question: is VdVq_meas into Current Regulator sourced from\n' ...
         'local PLL-frame VdVq, selected-frame VdVq, or something else?\n']);

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3}; cr=[ctrl '/Current Regulator'];
    fprintf('\n--- %s ---\n',dev);

    if getSimulinkBlockHandle(cr)<0
        fprintf('[FAIL] Current Regulator missing: %s\n',cr);
        continue;
    end

    ins=find_system(cr,'SearchDepth',1,'BlockType','Inport');
    [~,ord]=sort(cellfun(@(x)str2double(localSafeGet(x,'Port')),ins));
    ins=ins(ord);

    crph=get_param(cr,'PortHandles');

    for i=1:numel(ins)
        pn=str2double(localSafeGet(ins{i},'Port'));
        fprintf('Inport %-2g %-24s\n',pn,localBlockName(ins{i}));
        if isfinite(pn) && pn>=1 && pn<=numel(crph.Inport)
            fprintf('  PARENT SOURCE = %s\n',localInputSource(crph.Inport(pn)));
        end
    end

    outs=find_system(cr,'SearchDepth',1,'BlockType','Outport');
    [~,ord]=sort(cellfun(@(x)str2double(localSafeGet(x,'Port')),outs));
    outs=outs(ord);
    fprintf('Outputs:\n');
    for i=1:numel(outs)
        pn=str2double(localSafeGet(outs{i},'Port'));
        ph=get_param(outs{i},'PortHandles');
        fprintf('  Outport %-2g %-18s <- %s\n', ...
            pn,localBlockName(outs{i}),localInputSource(ph.Inport(1)));
    end
end

%% =========================================================================
% 6. Current Regulator exact internal structural inventory
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 6. CURRENT REGULATOR INTERNAL SUM/GAIN/PRODUCT/PI STRUCTURE\n');
fprintf('====================================================================================================\n');
fprintf(['This is a structural equation audit. Every Sum/Gain/Product/Saturation/\n' ...
         'Selector/PI-relevant block is printed with sources and destinations.\n']);

interesting={'Sum','Gain','Product','Saturation','Selector','Demux','Mux', ...
             'Integrator','DiscreteIntegrator','UnitDelay','Delay','Switch', ...
             'Trigonometry','Fcn','Math','Bias'};

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3}; cr=[ctrl '/Current Regulator'];
    fprintf('\n--- %s ---\n',dev);

    blocks=find_system(cr,'LookUnderMasks','all','FollowLinks','on','Type','Block');

    for i=1:numel(blocks)
        b=blocks{i};
        if strcmp(b,cr), continue; end
        bt=localSafeGet(b,'BlockType');

        keep=any(strcmp(bt,interesting)) || ...
             contains(lower(localBlockName(b)),'pi') || ...
             contains(lower(localBlockName(b)),'decoup') || ...
             contains(lower(localBlockName(b)),'feed') || ...
             contains(lower(localBlockName(b)),'vd') || ...
             contains(lower(localBlockName(b)),'vq');

        if ~keep, continue; end

        fprintf('\nBLOCK %s\n',b);
        fprintf('  BlockType=%s\n',bt);

        % Useful dialog parameters when they exist.
        pnames={'Inputs','Gain','Multiplication','UpperLimit','LowerLimit', ...
                'Threshold','Criteria','Value','Numerator','Denominator', ...
                'SampleTime','DelayLength'};
        for q=1:numel(pnames)
            val=localSafeGet(b,pnames{q});
            if ~isempty(val)
                fprintf('  %s=%s\n',pnames{q},val);
            end
        end

        ph=get_param(b,'PortHandles');
        if isfield(ph,'Inport')
            for q=1:numel(ph.Inport)
                fprintf('  IN%-2d <- %s\n',q,localInputSource(ph.Inport(q)));
            end
        end
        if isfield(ph,'Outport')
            for q=1:numel(ph.Outport)
                fprintf('  OUT%-2d ->\n',q);
                localPrintOutputDestinations(ph.Outport(q),'      ');
            end
        end
    end
end

%% =========================================================================
% 7. Backtrace VdVq_conv and PIdq from Current Regulator outputs
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 7. BACKTRACE CURRENT-REGULATOR OUTPUT DEPENDENCIES\n');
fprintf('====================================================================================================\n');
fprintf(['Recursive structural backtrace from VdVq_conv / PIdq to Inports.\n' ...
         'This should reveal the direct voltage-feedforward branch versus PI branch.\n']);

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3}; cr=[ctrl '/Current Regulator'];
    fprintf('\n--- %s ---\n',dev);

    for nm={'VdVq_conv','PIdq'}
        op=find_system(cr,'SearchDepth',1,'BlockType','Outport','Name',nm{1});
        if numel(op)~=1
            fprintf('[WARN] cannot uniquely resolve %s Outport.\n',nm{1});
            continue;
        end
        ph=get_param(op{1},'PortHandles');
        fprintf('\nTRACE %s <-\n',op{1});
        localTraceUpstream(ph.Inport(1),cr,'  ',0,14,{});
    end
end

%% =========================================================================
% 8. Explicit PLL-derived execution consumers
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 8. EXPLICIT LOCAL-PLL-DERIVED EXECUTION CONSUMERS\n');
fprintf('====================================================================================================\n');
fprintf(['For each device, list every direct destination of the principal PLL aliases.\n' ...
         'A CLEAN A/B must neutralize every destination that changes actuation.\n']);

for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3};
    fprintf('\n--- %s ---\n',dev);

    aliasTags={'wts','Freq','VdVqs','IdIqs'};
    for a=1:numel(aliasTags)
        tag=aliasTags{a};
        fs=find_system(ctrl,'SearchDepth',1,'BlockType','From');
        hits={};
        for i=1:numel(fs)
            if strcmp(localSafeGet(fs{i},'GotoTag'),tag)
                hits{end+1,1}=fs{i}; %#ok<AGROW>
            end
        end
        if isempty(hits), continue; end
        fprintf('ALIAS %s\n',tag);
        for i=1:numel(hits)
            ph=get_param(hits{i},'PortHandles');
            fprintf('  %s ->\n',hits{i});
            localPrintOutputDestinations(ph.Outport(1),'      ');
        end
    end
end

%% =========================================================================
% 9. Cross-device structural equivalence
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 9. FIVE-DEVICE STRUCTURAL FINGERPRINT\n');
fprintf('====================================================================================================\n');

fingerprints=cell(size(R,1),1);
for k=1:size(R,1)
    dev=R{k,1}; ctrl=R{k,3}; cr=[ctrl '/Current Regulator'];

    sw=find_system(ctrl,'SearchDepth',1,'BlockType','Switch');
    crb=find_system(cr,'LookUnderMasks','all','FollowLinks','on','Type','Block');

    gotos=find_system(ctrl,'SearchDepth',1,'BlockType','Goto');
    tagsHere={};
    for i=1:numel(gotos)
        tagsHere{end+1}=localSafeGet(gotos{i},'GotoTag'); %#ok<AGROW>
    end
    tagsHere=sort(unique(tagsHere));

    fp=sprintf('topSwitch=%d|CRblocks=%d|tags=%s', ...
        numel(sw),numel(crb),strjoin(tagsHere,','));
    fingerprints{k}=fp;

    fprintf('%-4s : %s\n',dev,fp);
end

if numel(unique(fingerprints))==1
    fprintf('[PASS] Five GFL controls share the same audited structural fingerprint.\n');
else
    fprintf('[IMPORTANT] Five GFL controls are NOT structurally identical by this fingerprint.\n');
end

%% =========================================================================
% 10. Audit conclusion contract
% ==========================================================================
fprintf('\n\n====================================================================================================\n');
fprintf(' 10. PRE-A/B DECISION CHECKLIST\n');
fprintf('====================================================================================================\n');

fprintf(['Use the TXT to answer these BEFORE patching:\n\n' ...
'Q1. Is wt_selected actually sourced from local wt_PLL in all five GFLs?\n' ...
'Q2. Which exact angle-dependent consumers use wt_selected?\n' ...
'Q3. Is Current Regulator VdVq_meas sourced from local PLL-frame VdVq?\n' ...
'Q4. Does VdVq_conv include direct voltage feedforward in addition to PIdq?\n' ...
'Q5. Are there any other PLL-derived execution aliases beyond wt_selected?\n' ...
'Q6. Are all five devices structurally equivalent for the intended A/B?\n' ...
'Q7. Therefore, which execution paths must be isolated TOGETHER to make the A/B clean?\n\n']);

fprintf(['IMPORTANT:\n' ...
'  Do NOT patch only wt_selected until Q3/Q4/Q5 are answered.\n' ...
'  If local PLL-frame Vd/Vq still directly feeds Vconv, then angle isolation alone\n' ...
'  does NOT remove PLL/frame actuation and cannot serve as a valid causal A/B.\n']);

fprintf('\n====================================================================================================\n');
fprintf(' AUDIT COMPLETE. MODEL WAS NOT MODIFIED.\n');
fprintf(' Output TXT: %s\n',outFile);
fprintf('====================================================================================================\n');

end

%% =========================================================================
% Helpers
% ==========================================================================
function s=localSafeGet(block,param)
try
    x=get_param(block,param);
    if isnumeric(x)
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

function nm=localBlockName(p)
try
    nm=get_param(p,'Name');
catch
    [~,nm]=fileparts(p);
end
end

function src=localInputSource(inH)
src='<unconnected>';
try
    ln=get_param(inH,'Line');
    if isempty(ln) || ln<0, return; end
    sh=get_param(ln,'SrcPortHandle');
    if isempty(sh) || sh<0, return; end
    sb=get_param(sh,'Parent');
    pn=get_param(sh,'PortNumber');
    src=sprintf('%s/out%d',sb,pn);
catch
end
end

function localPrintOutputDestinations(outH,indent)
try
    ln=get_param(outH,'Line');
    if isempty(ln) || ln<0
        fprintf('%s<unconnected>\n',indent);
        return;
    end
    dh=get_param(ln,'DstPortHandle');
    if isempty(dh)
        fprintf('%s<no resolved destinations>\n',indent);
        return;
    end
    dh=dh(dh>=0);
    if isempty(dh)
        fprintf('%s<no resolved destinations>\n',indent);
        return;
    end
    for i=1:numel(dh)
        db=get_param(dh(i),'Parent');
        pn=get_param(dh(i),'PortNumber');
        fprintf('%s%s/in%d\n',indent,db,pn);
    end
catch ME
    fprintf('%s<destination read error: %s>\n',indent,ME.message);
end
end

function localTraceUpstream(inH,scope,indent,depth,maxDepth,visited)
if depth>maxDepth
    fprintf('%s<depth limit>\n',indent);
    return;
end

src=localInputSource(inH);
fprintf('%s%s\n',indent,src);

if strcmp(src,'<unconnected>'), return; end

% Parse source block from ".../outN".
tok=regexp(src,'^(.*)/out\d+$','tokens','once');
if isempty(tok), return; end
b=tok{1};

if any(strcmp(visited,b))
    fprintf('%s  <already visited>\n',indent);
    return;
end
visited=[visited {b}];

% Stop if source block is outside Current Regulator scope.
if ~startsWith(b,[scope '/'])
    fprintf('%s  <external to Current Regulator>\n',indent);
    return;
end

bt=localSafeGet(b,'BlockType');
fprintf('%s  BlockType=%s\n',indent,bt);

% Print useful params.
pnames={'Inputs','Gain','Multiplication','UpperLimit','LowerLimit','Value','GotoTag'};
for q=1:numel(pnames)
    v=localSafeGet(b,pnames{q});
    if ~isempty(v)
        fprintf('%s  %s=%s\n',indent,pnames{q},v);
    end
end

% Inport block is a leaf of this subsystem.
if strcmp(bt,'Inport')
    fprintf('%s  <Current Regulator Inport leaf>\n',indent);
    return;
end

try
    ph=get_param(b,'PortHandles');
    if isfield(ph,'Inport')
        for q=1:numel(ph.Inport)
            fprintf('%s  upstream IN%d:\n',indent,q);
            localTraceUpstream(ph.Inport(q),scope,[indent '    '],depth+1,maxDepth,visited);
        end
    end
catch ME
    fprintf('%s  <trace error: %s>\n',indent,ME.message);
end
end

function localCloseDiary()
try
    diary off;
catch
end
end

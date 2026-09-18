function result = PATCH_E2_HEALTH_HANDOVER_R2_2(modelFile)
% R2.2: rolling-model-tolerant scratch-first patch. No whole-model byte/SHA gate. No electrical execution.
% See docs/00_README.md and the Chinese modification guide before use.
packageDir=fileparts(mfilename('fullpath'));
% Self-contained bootstrap: helper files are in this package root.
oldPath_boot=path; addpath(packageDir); bootGuard=onCleanup(@()path(oldPath_boot)); %#ok<NASGU>
M=jsondecode(e2hh_read(fullfile(packageDir,'MANIFEST.json')));model=M.model;
e2hh_bundlecheck_R2_2(packageDir,M);
if nargin<1 || isempty(modelFile)
    if ~bdIsLoaded(model),error('E2HHR2:NotLoaded','Open the saved source model first.');end
    modelFile=get_param(model,'FileName');
end
jf=java.io.File(char(modelFile));modelFile=char(jf.getCanonicalPath());
if ~isfile(modelFile),error('E2HHR2:MissingFile','Source SLX does not exist.');end
if ~bdIsLoaded(model),error('E2HHR2:NotLoaded','Open the saved source model; patch will not choose a model.');end
loadedJ=java.io.File(get_param(model,'FileName'));
if ~strcmpi(char(loadedJ.getCanonicalPath()),modelFile)
    error('E2HHR2:DifferentSource','Same-name loaded model is a different file.');
end
if ~strcmp(get_param(model,'SimulationStatus'),'stopped') || ~strcmp(get_param(model,'Dirty'),'off')
    error('E2HHR2:State','Source must be stopped and saved; nothing was modified.');
end
kind=e2hh_detect_R2(model,M,packageDir);
if strcmp(kind,'R2')
    result=VERIFY_E2_HEALTH_HANDOVER_R2_2;
    fprintf('Already R2/R2.2 payload: read-only verification only. Patch was NOT rerun.\n');return;
end
if strcmp(kind,'R1')
    e2hh_assert_complete_R1_layout(model);
end
% This test directly executes numerical copies of the three payload functions.
% No Simulink model is updated/compiled/simulated by the self-test.
selftest=SELFTEST_E2_HEALTH_HANDOVER_R2_2;
if ~strcmp(selftest.status,'NATIVE_NUMERIC_SELFTEST_PASS')
    error('E2HHR2:SelfTest','Native numerical self-test did not pass. Source unchanged.');
end
stamp=datestr(now,'yyyymmdd_HHMMSS_FFF');runDir=fullfile(packageDir,['APPLY_' stamp]);mkdir(runDir);
scratchDir=fullfile(runDir,'scratch');mkdir(scratchDir);
backupFile=fullfile(runDir,[model '_BEFORE.slx']);scratchFile=fullfile(scratchDir,[model '.slx']);
copyfile(modelFile,backupFile);copyfile(modelFile,scratchFile);
result=struct('version',M.version,'status','STARTED','sourceKind',kind,'sourceFile',modelFile, ...
    'backupFile',backupFile,'runDir',runDir, ...
    'formalWritten',false,'nativeCompilePerformed',false,'targetExecuted',false, ...
    'numericSelftest',selftest.status);
oldPath=path;pathGuard=onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(packageDir);addpath(fileparts(modelFile));
try
    close_system(model,0);load_system(scratchFile);
    if ~strcmp(get_param(model,'SimulationStatus'),'stopped'),error('E2HHR2:Running','Scratch is running.');end
    beforeCharts=e2hh_charts(model);beforeEdges=e2hh_edges(model);
    beforeBlocks=find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block');
    if ~strcmp(e2hh_detect_R2(model,M,packageDir),kind),error('E2HHR2:ScratchIdentity','Scratch sources changed on load.');end
    % Preserve all pre-existing port order. Add only declared trailing fields.
    for k=1:numel(M.cores)
        c=M.cores(k);ch=e2hh_chart([model '/' c.path]);
        ch.Script=e2hh_read(fullfile(packageDir,c.payload_file));
        ai=cellstr(string(c.new_inputs));ao=cellstr(string(c.outputs));
        for j=numel(c.old_inputs)+1:numel(ai)
            e2hh_set_data(ch,ai{j},'Input',j,c.new_input_sizes(j));
        end
        for j=numel(c.old_outputs)+1:numel(ao)
            e2hh_set_data(ch,ao{j},'Output',j,c.new_output_sizes(j));
        end
    end
    drawnow;
    if strcmp(kind,'ORIGINAL')
        recInfo=e2hh_install_R1_layout(model,M);
    else
        recInfo=e2hh_r1_recinfo(model);
    end
    SM=[model '/SM_Master'];STR=[SM '/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core'];
    st=M.cores(strcmp({M.cores.key},'strategy'));
    outNames=cellstr(string(st.outputs));ob=find(strcmp(outNames,'hr_observe'));
    if numel(ob)~=1,error('E2HHR2:ObservePort','Expected one observation port.');end
    recInfo=e2hh_append_observe_R2(model,STR,ob,recInfo);
    defaults=e2hh_defaults_R2(model);
    for k=1:numel(defaults),set_param(defaults(k).path,defaults(k).property,defaults(k).value);end
    afterBlocks=find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block');
    added=setdiff(afterBlocks,beforeBlocks);newEdges=e2hh_edges(model);
    missing=setdiff(beforeEdges,newEdges);
    if ~isempty(missing),error('E2HHR2:OldWire','An original signal connection disappeared.');end
    record=struct('version',M.version,'model',model,'sourceKind',kind,'sourceFile',modelFile, ...
        'backupFile',backupFile,'originalCharts',beforeCharts, ...
        'originalEdges',{beforeEdges},'addedBlocks',{added},'expectedNewEdges',{setdiff(newEdges,beforeEdges)}, ...
        'expectedDefaults',defaults,'recorderExtension',recInfo,'modifiedCorePaths',{{M.cores.path}}, ...
        'nativeCompilePerformed',false);
    recordFile=fullfile(runDir,'PATCH_RECORD.json');e2hh_json(recordFile,record);
    e2hh_json(fullfile(packageDir,'LAST_PATCH_RECORD.json'),record);
    check=VERIFY_E2_HEALTH_HANDOVER_R2_2(recordFile,false);
    if ~strcmp(check.status,'READ_ONLY_STRUCTURE_PASS'),error('E2HHR2:ScratchVerify','Scratch verification blocked.');end
    save_system(model,scratchFile);close_system(model,0);load_system(scratchFile);
    check=VERIFY_E2_HEALTH_HANDOVER_R2_2(recordFile,false);
    if ~strcmp(check.status,'READ_ONLY_STRUCTURE_PASS'),error('E2HHR2:Persistence','Reopened scratch did not verify.');end
    close_system(model,0);
    % R2.2 does not compare whole-model bytes/SHA. Re-check only the target
    % control cores immediately before formal overwrite. Unrelated edits elsewhere
    % in this rolling research model are explicitly allowed.
    load_system(modelFile);
    formalKind=e2hh_detect_R2(model,M,packageDir);
    if ~strcmp(formalKind,kind)
        close_system(model,0);
        error('E2HHR21:TargetCoreChanged','One of the three target control cores changed while the patch was running. No overwrite performed.');
    end
    close_system(model,0);
    copyfile(scratchFile,modelFile,'f');result.formalWritten=true;
    result.status='PATCH_SAVED_AND_PERSISTENCE_VERIFIED';e2hh_json(fullfile(runDir,'RESULT.json'),result);
    load_system(modelFile);check=VERIFY_E2_HEALTH_HANDOVER_R2_2(recordFile,true);
    result.independentStructureStatus=check.status;
    if ~strcmp(check.status,'READ_ONLY_STRUCTURE_PASS')
        error('E2HHR2:FinalVerify','Formal file saved; review verifier/log, do NOT mechanically rerun patch.');
    end
    e2hh_json(fullfile(runDir,'RESULT.json'),result);
    fprintf('\nPATCH_SAVED_AND_PERSISTENCE_VERIFIED\n%s\n',modelFile);
    fprintf('Backup: %s\nResult: %s\n',backupFile,fullfile(runDir,'RESULT.json'));
    fprintf('R2.2 G29: 94 data channels + time = 95 rows. Native RT-LAB build and electrical run NOT performed.\n');
catch ME
    result.errorIdentifier=ME.identifier;result.error=ME.message;
    if result.formalWritten
        result.status='FORMAL_SAVED_NEEDS_READ_ONLY_REVIEW';
    else
        result.status='BLOCKED_BEFORE_FORMAL_WRITE';
        try
            if bdIsLoaded(model),close_system(model,0);end
            load_system(modelFile);
        catch REST,result.restoreLoadedWarning=REST.message;end
    end
    try,e2hh_json(fullfile(runDir,'RESULT.json'),result);catch,end
    fprintf(2,'\n%s\n%s\nResult: %s\n',result.status,ME.message,runDir);rethrow(ME);
end
end

function e2hh_set_data(ch,name,scope,port,width)
ds=ch.find('-isa','Stateflow.Data','Name',name);
if isempty(ds),ds=Stateflow.Data(ch);ds.Name=name;end
if numel(ds)~=1,error('E2HHR2:DataAmbiguous','Non-unique added chart field: %s',name);end
ds.Scope=scope;ds.Port=port;ds.Props.Array.Size=num2str(width);
ds.Props.Type.Method='Built-in';ds.Props.Type.Primitive='double';
end

function kind=e2hh_detect_R2(model,M,folder)
% Local semantic source classification only. No whole-model SHA/byte identity.
% Unrelated model edits are allowed. The three target cores must still have one
% of the supported executable projections so this patch does not overwrite an
% unknown edit inside the exact logic it owns.
which=cell(numel(M.cores),1);
for k=1:numel(M.cores)
    c=M.cores(k);ch=e2hh_chart([model '/' c.path]);s=e2hh_execnorm(ch.Script);
    if strcmp(s,e2hh_execnorm(e2hh_read(fullfile(folder,c.payload_file))))
        which{k}='R2';
    elseif strcmp(s,e2hh_execnorm(e2hh_read(fullfile(folder,c.r1_file))))
        which{k}='R1';
    elseif strcmp(c.key,'coord') && strcmp(s,e2hh_execnorm(e2hh_read(fullfile(folder,'reference/r1/coord_R1_OUTPUT_FIXED.m.txt'))))
        which{k}='R1';
    elseif strcmp(s,e2hh_execnorm(e2hh_read(fullfile(folder,c.original_file))))
        which{k}='ORIGINAL';
    else
        error('E2HHR21:TargetCoreSemanticConflict', ...
            ['Target core has executable edits not covered by this patch: ' c.path '. ' ...
             'Unrelated model edits are allowed; this local conflict needs merge/re-audit so your edits are not overwritten.']);
    end
end
if numel(unique(which))~=1
    error('E2HHR21:MixedTargetCoreVersion','The three target cores are at mixed patch levels; no automatic overwrite.');
end
kind=which{1};
end

function s=e2hh_execnorm(s)
% Ignore comments/formatting only; executable changes remain visible.
s=strrep(s,sprintf('\r\n'),sprintf('\n'));s=strrep(s,sprintf('\r'),sprintf('\n'));
L=regexp(s,'\n','split');out=cell(size(L));
for i=1:numel(L)
    q=L{i};pct=strfind(q,'%');
    if ~isempty(pct),q=q(1:pct(1)-1);end
    out{i}=regexprep(q,'\s+','');
end
s=strjoin(out,'');
end

function e2hh_assert_complete_R1_layout(model)
% An incomplete R1 scratch/manual save is not treated as an applied R1 model.
SM=[model '/SM_Master'];CO=[SM '/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR'];
needed={[SM '/E2HH_COORD_COMMAND_Z1'],[SM '/E2HH_S14_COMMAND_Z1'], ...
    [SM '/E2HH_APPLIED_COMMAND_Z1'],[SM '/E2HH_MASTER_VALID_Z1'],[SM '/E2HH_STEP_Z1'], ...
    [CO '/E2HH_AVAILABLE_Z1'],[CO '/CFG_E2HH_NEXT_TARGET_PU'],[CO '/CFG_E2HH_APPROVED_LIMITS']};
for k=1:numel(needed)
    if getSimulinkBlockHandle(needed{k})<0
        error('E2HHR2:IncompleteR1','R1 layout incomplete: %s. Use untouched backup or inspect failed R1 log; no automatic repair.',needed{k});
    end
end
ph=get_param([CO '/AA15_FINAL_COORD_CORE'],'PortHandles');
if numel(ph.Inport)~=70 || numel(ph.Outport)~=49
    error('E2HHR2:IncompleteR1Port','Applied R1 upgrade requires 70 inputs and corrected 49 outputs.');
end
for k=65:70
    if get_param(ph.Inport(k),'Line')<0,error('E2HHR2:IncompleteR1Port','R1 added coordinator input is unconnected.');end
end
end

function d=e2hh_defaults_R2(model)
b=find_system(model,'LookUnderMasks','all','FollowLinks','off','BlockType','Constant');
d=struct('path',{},'property',{},'value',{});m=0;ki=0;tol=0;
for k=1:numel(b)
    p=b{k};nm=get_param(p,'Name');v='';
    if any(strcmp(nm,{'AA15_BASETEST_ENABLE','AA15_ESS2_BASETEST_ENABLE'})),v='3';m=m+1;end
    if contains(p,'/ESS2_Control/Power Control Loop/')
        if strcmp(nm,'CFG_E2_DIAG_P_KI_RT'),v='0.5';ki=ki+1;end
        if strcmp(nm,'CFG_E2_DIAG_P_KP_RT'),v='0.06';end
        if strcmp(nm,'CFG_E2_DIAG_P_LOOP_ENABLE'),v='1';end
        if any(strcmp(nm,{'CFG_E2_DIAG_Q_LOOP_ENABLE','CFG_E2_DIAG_DIRECT_IREF_ENABLE','CFG_E2_DIAG_DIRECT_ID_TARGET_PU','CFG_E2_DIAG_DIRECT_IQ_TARGET_PU'})),v='0';end
    end
    if strcmp(nm,'CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU') && contains(p,'/SS_Slave2/AA15_ESS2_RESTORE_CONFIG/')
        v='0.0005';tol=tol+1;
    end
    if strcmp(nm,'CFG_E2HH_NEXT_TARGET_PU'),v='-0.005';end
    if strcmp(nm,'CFG_E2HH_APPROVED_LIMITS'),v='[-0.005;-0.005;0.0025;0.0025]';end
    if ~isempty(v),d(end+1)=struct('path',p,'property','Value','value',v);end %#ok<AGROW>
end
if m~=4 || ki~=1 || tol~=1,error('E2HHR2:DefaultCount','Audited mode/gain/tolerance constant count differs (need 4/1/1).');end
end

function info=e2hh_install_R1_layout(model,M)
    SM=[model '/SM_Master'];
    STR=[SM '/Advanced_Microgrid_15_Strategies/Advanced_Strategy_Core'];
    CO=[SM '/AA15_ISLAND_SUPERVISORY_COORDINATION/AA15_FINAL_ISLAND_COORDINATOR/AA15_FINAL_COORD_CORE'];
    BL=[SM '/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND'];
    strategy=M.cores(strcmp({M.cores.key},'strategy'));
    coord=M.cores(strcmp({M.cores.key},'coord'));
    nS=numel(strategy.old_inputs);nC=numel(coord.old_inputs);
    coOut=cellstr(string(coord.outputs));coIn=cellstr(string(coord.old_inputs));
    po=find(strcmp(coOut,'po3'));av=find(strcmp(coIn,'ess2_available'));
    if numel(po)~=1 || numel(av)~=1,error('E2HH:CoordinatorPorts','Cannot uniquely identify ESS2 output/availability.');end
    % Explicit one-sample delays break all added direct-feedthrough routes.
    zCoord=[SM '/E2HH_COORD_COMMAND_Z1'];
    zS14=[SM '/E2HH_S14_COMMAND_Z1'];
    zApplied=[SM '/E2HH_APPLIED_COMMAND_Z1'];
    e2hh_delay(zCoord);e2hh_delay(zS14);e2hh_delay(zApplied);
    e2hh_route(model,CO,po,zCoord,1,'E2HH_COORD_COMMAND');
    e2hh_route(model,zCoord,1,STR,nS+1,'E2HH_COORD_COMMAND_Z');
    e2hh_route(model,BL,2,zS14,1,'E2HH_S14_COMMAND');
    e2hh_route(model,zS14,1,STR,nS+2,'E2HH_S14_COMMAND_Z');
    masterOut=find(strcmp(coOut,'hr_master_ok'));
    if numel(masterOut)~=1,error('E2HH:MasterOutput','New master reference health output is missing.');end
    zMaster=[SM '/E2HH_MASTER_VALID_Z1'];e2hh_delay(zMaster);
    e2hh_route(model,CO,masterOut,zMaster,1,'E2HH_MASTER_VALID');
    e2hh_route(model,zMaster,1,STR,nS+3,'E2HH_MASTER_VALID_Z');

    e2hh_route(model,BL,1,zApplied,1,'E2HH_APPLIED_COMMAND');
    e2hh_route(model,zApplied,1,CO,nC+2,'E2HH_APPLIED_COMMAND_Z');
    modeSource=[SM '/AA15_BASETEST_ENABLE'];
    if getSimulinkBlockHandle(modeSource)<0,error('E2HH:ModeSource','Approved master mode source is missing.');end
    e2hh_route(model,modeSource,1,CO,nC+1,'E2HH_MODE');
    % Previous availability comes from the exact currently connected input.
    [avSrc,avPort]=e2hh_source(CO,av);
    zAv=[get_param(CO,'Parent') '/E2HH_AVAILABLE_Z1'];e2hh_delay(zAv);
    e2hh_route(model,avSrc,avPort,zAv,1,'E2HH_AVAILABILITY');
    e2hh_route(model,zAv,1,CO,nC+3,'E2HH_AVAILABILITY_Z');
    % Append explicitly defined handover and guarded-test channels to the existing G29 mux.
    % Existing channel positions and all original data connections are retained.
    nextTarget=[get_param(CO,'Parent') '/CFG_E2HH_NEXT_TARGET_PU'];
    limits=[get_param(CO,'Parent') '/CFG_E2HH_APPROVED_LIMITS'];
    add_block('built-in/Constant',nextTarget,'Value','-0.005','SampleTime','0.0001');
    % [absolute min, absolute max, increasing rate, decreasing magnitude rate].
    % Defaults authorize no departure from the proven -0.005 pu operating point.
    add_block('built-in/Constant',limits,'Value','[-0.005;-0.005;0.0025;0.0025]','SampleTime','0.0001');
    e2hh_local_line(nextTarget,1,CO,nC+4);
    e2hh_local_line(limits,1,CO,nC+5);
    stepSrc=[SM '/AA15_S14V2_G29_SUBSTATE'];
    if getSimulinkBlockHandle(stepSrc)<0,error('E2HH:StepSource','Audited S14 substate output is missing.');end
    stepZ=[SM '/E2HH_STEP_Z1'];e2hh_delay(stepZ);
    e2hh_route(model,stepSrc,1,stepZ,1,'E2HH_STEP');
    e2hh_route(model,stepZ,1,CO,nC+6,'E2HH_STEP_Z');
    info=e2hh_extend_g29(model,modeSource,zCoord,zS14,zApplied,zAv,nextTarget,limits,stepZ);
end

function e2hh_delay(p)
if getSimulinkBlockHandle(p)>=0,error('E2HH:NotFresh','New block already exists: %s',p);end
add_block('simulink/Discrete/Unit Delay',p,'InitialCondition','0','SampleTime','0.0001');
end
function e2hh_route(model,src,sp,dst,dp,tag,width)
if nargin<7,width=1;end
% Only ordinary signal ports within SM_Master are routed. No physical ports.
spar=get_param(src,'Parent');dpar=get_param(dst,'Parent');
if ~startsWith(spar,[model '/SM_Master']) || ~startsWith(dpar,[model '/SM_Master'])
    error('E2HH:CrossTaskForbidden','This patch cannot create an unplanned task crossing.');
end
sa=e2hh_ancestors(spar);da=e2hh_ancestors(dpar);common='';
for k=1:min(numel(sa),numel(da)),if strcmp(sa{k},da{k}),common=sa{k};else,break;end,end
if isempty(common),error('E2HH:Hierarchy','No common local task ancestor.');end
while ~strcmp(get_param(src,'Parent'),common)
    parent=get_param(src,'Parent');p=[parent '/' tag '_OUT'];
    if getSimulinkBlockHandle(p)>=0,error('E2HH:PortNameCollision','Port exists: %s',p);end
    op=find_system(parent,'SearchDepth',1,'BlockType','Outport');nums=cellfun(@(x)str2double(get_param(x,'Port')),op);
    no=max([0;nums(:)])+1;add_block('built-in/Outport',p,'Port',num2str(no));
    e2hh_local_line(src,sp,p,1);src=parent;sp=no;
end
j=find(strcmp(da,common),1);
for k=j+1:numel(da)
    child=da{k};p=[child '/' tag '_IN'];
    if getSimulinkBlockHandle(p)>=0,error('E2HH:PortNameCollision','Port exists: %s',p);end
    ip=find_system(child,'SearchDepth',1,'BlockType','Inport');nums=cellfun(@(x)str2double(get_param(x,'Port')),ip);
    ni=max([0;nums(:)])+1;add_block('built-in/Inport',p,'Port',num2str(ni), ...
        'PortDimensions',num2str(width),'OutDataTypeStr','double');
    e2hh_local_line(src,sp,child,ni);src=p;sp=1;
end
e2hh_local_line(src,sp,dst,dp);
end
function a=e2hh_ancestors(p)
a={p};while contains(p,'/'),p=get_param(p,'Parent');a=[{p},a];end %#ok<AGROW>
end
function e2hh_local_line(src,sp,dst,dp)
ps=get_param(src,'PortHandles');pd=get_param(dst,'PortHandles');
if numel(ps.Outport)<sp || numel(pd.Inport)<dp,error('E2HH:PortNotReady','New scalar ports did not materialize.');end
if get_param(pd.Inport(dp),'Line')~=-1,error('E2HH:OccupiedInput','Refusing to overwrite an existing input.');end
if ~strcmp(get_param(src,'Parent'),get_param(dst,'Parent')),error('E2HH:DifferentParents','Internal routing error.');end
add_line(get_param(src,'Parent'),ps.Outport(sp),pd.Inport(dp),'autorouting','on');
end
function [src,sp]=e2hh_source(b,p)
ph=get_param(b,'PortHandles');lh=get_param(ph.Inport(p),'Line');
if lh<0,error('E2HH:MissingSource','Missing original input.');end
h=get_param(lh,'SrcPortHandle');src=getfullname(get_param(h,'Parent'));sp=get_param(h,'PortNumber');
end

function info=e2hh_extend_g29(model,mode,zCoord,zS14,zApplied,zAv,nextTarget,limits,stepZ)
% Resolve an existing group29 recorder by actual mask parameters, never by ID.
all=find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block');
hits={};
for k=1:numel(all)
    b=all{k};if ~startsWith(b,[model '/SM_Master']),continue;end
    nm=lower(get_param(b,'Name'));
    try,mt=lower(get_param(b,'MaskType'));catch,mt='';end
    if ~(contains(nm,'opwrite')||contains(mt,'opwrite')),continue;end
    try,dp=get_param(b,'DialogParameters');catch,continue;end
    f=fieldnames(dp);is29=false;
    for j=1:numel(f)
        if contains(lower(f{j}),'group')
            try,v=get_param(b,f{j});is29=is29||abs(str2double(v)-29)<1e-12;catch,end
        end
    end
    if is29,hits{end+1}=b;end %#ok<AGROW>
end
% Prefer the outer mask when both a mask and its own S-function report group29.
keep=true(size(hits));for i=1:numel(hits),for j=1:numel(hits)
    if i~=j && startsWith(hits{i},[hits{j} '/']),keep(i)=false;end
end,end;hits=hits(keep);
if numel(hits)~=1,error('E2HH:G29Ambiguous','Cannot uniquely resolve group29 recorder mask.');end
rec=hits{1};[b,bp]=e2hh_source(rec,1);seen={};
while ~strcmp(get_param(b,'BlockType'),'Mux')
    if any(strcmp(seen,b)),error('E2HH:G29Cycle','Cycle while locating G29 input mux.');end;seen{end+1}=b; %#ok<AGROW>
    typ=get_param(b,'BlockType');
    if strcmp(typ,'From')
        gb=get_param(b,'GotoBlock');
        if isstruct(gb) && numel(gb)==1 && isfield(gb,'handle'),gb=gb.handle;end
        if iscell(gb) && numel(gb)==1,gb=gb{1};end
        if isnumeric(gb)&&numel(gb)==1&&gb>0,b=getfullname(gb);
        elseif ischar(gb)&&getSimulinkBlockHandle(gb)>0,b=gb;
        else,error('E2HH:G29Tag','Recorder tag does not resolve uniquely.');end
        [b,bp]=e2hh_source(b,1);
    elseif strcmp(typ,'Inport')
        p=str2double(get_param(b,'Port'));[b,bp]=e2hh_source(get_param(b,'Parent'),p);
    elseif strcmp(typ,'SubSystem')
        % The audited writer is fed by AA15_BASETEST_G29_NORMALIZER.
        % Follow its exact output port to the final MuxN. Do NOT append before
        % its fixed 74-output DemuxN or widen the existing inter-task packet.
        if ~strcmp(b,[model '/SM_Master/AA15_BASETEST_G29_NORMALIZER'])
            error('E2HHR2:G29UnknownSubsystem','Unexpected recorder wrapper: %s',b);
        end
        out=find_system(b,'SearchDepth',1,'BlockType','Outport');hit={};
        for q=1:numel(out)
            if str2double(get_param(out{q},'Port'))==bp,hit{end+1}=out{q};end %#ok<AGROW>
        end
        if numel(hit)~=1,error('E2HHR2:G29Outport','Recorder output port is not unique.');end
        [b,bp]=e2hh_source(hit{1},1);
    else
        error('E2HH:G29Boundary','Recorder data is not a transparent route to an existing mux: %s',b);
    end
end
mux=b;
if ~strcmp(mux,[model '/SM_Master/AA15_BASETEST_G29_NORMALIZER/MuxN'])
    error('E2HHR2:G29FinalMux','Expected final 74-channel normalization mux, not an upstream assembler.');
end
oldInputs=get_param(mux,'Inputs');
if isempty(regexp(oldInputs,'^[0-9\s\[\];,]+$','once'))
    error('E2HH:G29MuxExpression','Recorder mux inputs must be explicit numeric configuration.');
end
v=sscanf(regexprep(oldInputs,'[\[\];,]',' '),'%f').';
ph=get_param(mux,'PortHandles');oldN=numel(ph.Inport);
if numel(v)==1
    if v~=oldN,error('E2HH:G29MuxPorts','Mux input count mismatch.');end
    newInputs=num2str(oldN+9);
else
    if numel(v)~=oldN,error('E2HH:G29MuxWidths','Mux width-vector count mismatch.');end
    newInputs=mat2str([v ones(1,7) 4 1]);
end
set_param(mux,'Inputs',newInputs);
parent=get_param(mux,'Parent');dif=[parent '/E2HH_COMMAND_DIFFERENCE'];ab=[parent '/E2HH_COMMAND_DIFFERENCE_ABS'];
add_block('built-in/Sum',dif,'Inputs','+-');add_block('built-in/Abs',ab);
e2hh_route(model,zCoord,1,dif,1,'E2HH_DIAG_COORD');
e2hh_route(model,zS14,1,dif,2,'E2HH_DIAG_S14');e2hh_local_line(dif,1,ab,1);
sources={mode,zCoord,zS14,zApplied,zAv,ab,nextTarget,limits,stepZ};labels={'MODE','COORD_Z','S14_Z','APPLIED_Z','AVAIL_Z','MATCH_ERROR','NEXT_TARGET','APPROVED_LIMITS','STEP_Z'};
widths=[1 1 1 1 1 1 1 4 1];
for k=1:9,e2hh_route(model,sources{k},1,mux,oldN+k,['E2HH_REC_' labels{k}],widths(k));end
info=struct('recorder',rec,'mux',mux,'oldInputs',oldInputs,'newInputs',newInputs, ...
    'originalDataChannels',74,'newDataChannels',86,'newRowsWithTime',87, ...
    'firstNewDataChannel',75,'addedChannelNames',{labels}, ...
    'compiledWidthVerified',false,'nominal60sBudgetBytes',156600000);
end

function info=e2hh_r1_recinfo(model)
% Audited final recorder-normalizer mux; do not widen its original Demux input.
mux=[model '/SM_Master/AA15_BASETEST_G29_NORMALIZER/MuxN'];
if getSimulinkBlockHandle(mux)<0,error('E2HHR2:R1Mux','Expected R1 recorder mux missing.');end
ph=get_param(mux,'PortHandles');
% Verify the R1 append marker and its sources,
% then preserve actual stored configuration; compiled width is checked later.
if numel(ph.Inport)~=83,error('E2HHR2:R1Mux','Expected complete R1 final recorder mux with 83 input ports (86 data channels).');end
if getSimulinkBlockHandle([get_param(mux,'Parent') '/E2HH_COMMAND_DIFFERENCE_ABS'])<0
    error('E2HHR2:R1Recorder','R1 recorder diagnostic append marker missing.');
end
info=struct('recorder','R1_PRESERVED_GROUP29','mux',mux,'oldInputs',get_param(mux,'Inputs'), ...
    'newInputs',get_param(mux,'Inputs'),'originalDataChannels',74,'newDataChannels',86,'newRowsWithTime',87);
end

function info=e2hh_append_observe_R2(model,STR,op,info)
mux=info.mux;old=get_param(mux,'Inputs');ph=get_param(mux,'PortHandles');n=numel(ph.Inport);
if isempty(regexp(old,'^[0-9\s\[\];,]+$','once')),error('E2HHR2:MuxExpression','Nonliteral recorder dimensions.');end
v=sscanf(regexprep(old,'[\[\];,]',' '),'%f').';
if numel(v)==1
    if v~=n,error('E2HHR2:MuxCount','Mux input count disagrees with stored value.');end
    value=num2str(n+1);
else
    if numel(v)~=n,error('E2HHR2:MuxWidthCount','Mux width vector disagrees with ports.');end
    value=mat2str([v 8]);
end
set_param(mux,'Inputs',value);
e2hh_route(model,STR,op,mux,n+1,'E2HH_R2_OBSERVE',8);
info.beforeR2Inputs=old;info.newInputs=value;info.r2ObservationMuxPort=n+1;
info.r2ObservationWidth=8;info.newDataChannels=94;info.newRowsWithTime=95;
info.firstR2DataChannel=87;info.nominal60sBudgetBytes=171000000;
end

function C01_GENERATE_MATLAB_GOLDEN()
% Generate deterministic C01 input/golden CSVs in the current folder.
%
% Outputs:
%   C01_strategy15_input.csv
%   C01_strategy15_matlab_golden.csv
%
% The input CSV has 40 numeric columns, no header.
% The golden CSV has 60 numeric columns:
%   status[15], alarm[15], metric[15], cmd[15].

clear Advanced_Strategy_Core_C01_REFERENCE;

dt = 0.1;
t1 = (0:dt:100).';
n1 = numel(t1);

X = zeros(n1,40);

% Fixed source-strategy configuration.
Pu = 100.0;
dw = 30.0;
dlim = 100.0;
eb = 5.0;
Vn = 10000.0;
vd = 0.02;
Qlim = 100.0;
arl = 20.0;
ard = 5.0;
ifd = 0.20;
ivd = 0.10;
srl = 10.0;
pft = 10.0;
Pt = -100.0;
uv = 0.90;
uf = 49.50;
ls = 50.0;
pk = 150.0;
val = 50.0;
plan_s = 10.0;
ex = 30.0;
rnew_t = 90.0;
bs = 1.0;
se = 1.0;
w1 = 0.20;
w2 = 0.20;
w3 = 0.20;
w4 = 0.20;
w5 = 0.20;

for k = 1:n1
    t = t1(k);

    P = -80.0 + 40.0*sin(2*pi*t/17.0);
    Q = 20.0*cos(2*pi*t/13.0);
    V = 10000.0 + 150.0*sin(2*pi*t/11.0);
    F = 50.0 + 0.05*sin(2*pi*t/9.0);

    % Force dedicated trigger windows.
    if t >= 5 && t < 10
        P = -220.0;              % demand/peak
    elseif t >= 10 && t < 15
        P = 90.0;                % anti-reverse/export
    elseif t >= 15 && t < 20
        P = -20.0;               % valley
    end

    if t >= 25 && t < 28
        V = 8500.0;              % UV
    end

    if t >= 30 && t < 33
        F = 49.0;                % UF
    end

    if t >= 35 && t < 38
        V = 8500.0;
        F = 49.0;                % UV+UF
    end

    comm = 1.0;
    if t >= 45 && t < 51
        comm = 0.0;              % communication raw S5/S15
    end

    en = 1.0;
    if t >= 70 && t < 72
        en = 0.0;                % source enable-off behavior
    end

    S1 = 0.55 + 0.20*sin(2*pi*t/31.0);
    S2 = 0.60 + 0.15*cos(2*pi*t/29.0);

    if t >= 55 && t < 57
        S1 = 0.15;
        S2 = 0.20;               % S14 low-SOC failure branch
    end

    % PV available-power steps + smooth variation.
    PV1 = 60.0 + 20.0*sin(2*pi*t/7.0);
    PV2 = 55.0 + 15.0*cos(2*pi*t/8.0);

    if t >= 40 && t < 41
        PV1 = 100.0;
        PV2 = 100.0;
    end

    X(k,:) = [ ...
        t,P,Q,V,F,S1,S2,PV1,PV2,comm,en, ...
        Pu,dw,dlim,eb,Vn,vd,Qlim,arl,ard,ifd,ivd,srl,pft,Pt, ...
        uv,uf,ls,pk,val,plan_s,ex,rnew_t,bs,se,w1,w2,w3,w4,w5];
end

% Append a time-rewind segment to verify the original t<last_t reset path.
t2 = (0:dt:5).';
n2 = numel(t2);
X2 = zeros(n2,40);

for k = 1:n2
    t = t2(k);
    P = -120.0 + 10.0*sin(t);
    Q = 0.0;
    V = 10000.0;
    F = 50.0;
    S1 = 0.60;
    S2 = 0.60;
    PV1 = 70.0;
    PV2 = 60.0;
    comm = 1.0;
    en = 1.0;

    X2(k,:) = [ ...
        t,P,Q,V,F,S1,S2,PV1,PV2,comm,en, ...
        Pu,dw,dlim,eb,Vn,vd,Qlim,arl,ard,ifd,ivd,srl,pft,Pt, ...
        uv,uf,ls,pk,val,plan_s,ex,rnew_t,bs,se,w1,w2,w3,w4,w5];
end

X = [X;X2];

Y = zeros(size(X,1),60);

clear Advanced_Strategy_Core_C01_REFERENCE;

for k = 1:size(X,1)
    r = num2cell(X(k,:));

    [st,al,mt,cmd] = Advanced_Strategy_Core_C01_REFERENCE( ...
        r{1},r{2},r{3},r{4},r{5},r{6},r{7},r{8},r{9},r{10},r{11}, ...
        r{12},r{13},r{14},r{15},r{16},r{17},r{18},r{19},r{20}, ...
        r{21},r{22},r{23},r{24},r{25},r{26},r{27},r{28},r{29}, ...
        r{30},r{31},r{32},r{33},r{34},r{35},r{36},r{37},r{38}, ...
        r{39},r{40});

    Y(k,:) = [st,al,mt,cmd];
end

writematrix(X,'C01_strategy15_input.csv');
writematrix(Y,'C01_strategy15_matlab_golden.csv');

fprintf('Generated %d C01 samples.\n',size(X,1));
fprintf('Input : C01_strategy15_input.csv\n');
fprintf('Golden: C01_strategy15_matlab_golden.csv\n');
end

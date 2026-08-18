function C01_COMPARE_MATLAB_AND_C()
% Compare C01 MATLAB golden output against the C CSV runner output.
%
% Required files in current folder:
%   C01_strategy15_matlab_golden.csv
%   C01_strategy15_c_output.csv

gold = readmatrix('C01_strategy15_matlab_golden.csv');
c = readmatrix('C01_strategy15_c_output.csv');

assert(isequal(size(gold),size(c)), ...
    'C01:SizeMismatch', ...
    'Golden size %s, C size %s.',mat2str(size(gold)),mat2str(size(c)));

err = abs(gold-c);
maxErr = max(err,[],'all');

% Discrete-like groups: status and alarm must be exact.
discErr = max(abs(gold(:,1:30)-c(:,1:30)),[],'all');

fprintf('C01 rows                 : %d\n',size(gold,1));
fprintf('Max abs error all outputs: %.17g\n',maxErr);
fprintf('Max status/alarm error   : %.17g\n',discErr);

if discErr ~= 0
    error('C01:DiscreteMismatch', ...
        'status/alarm are not exactly identical.');
end

if maxErr > 1e-9
    [r,col] = find(err > 1e-9,1,'first');
    error('C01:NumericMismatch', ...
        'First error >1e-9 at row=%d col=%d; golden=%.17g C=%.17g err=%.17g', ...
        r,col,gold(r,col),c(r,col),err(r,col));
end

fprintf('C01 MATLAB-vs-C GOLDEN CHECK: PASS\n');
end

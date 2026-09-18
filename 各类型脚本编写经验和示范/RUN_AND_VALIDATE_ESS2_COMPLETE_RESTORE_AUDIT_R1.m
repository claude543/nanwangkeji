function result = RUN_AND_VALIDATE_ESS2_COMPLETE_RESTORE_AUDIT_R1
% RUN_AND_VALIDATE_ESS2_COMPLETE_RESTORE_AUDIT_R1
% 运行正式只读审计，并在结束后验证生成ZIP确实是本轮审计结果。
% 本文件不修改模型。

clc;
fprintf('=== ESS2 COMPLETE RESTORE AUDIT RUN + PACKAGE VALIDATION ===\n');

if exist('AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1','file') ~= 2
    error(['找不到 AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1.m。' ...
        '请把本文件与审计主脚本、JSON scope放在同一目录后运行。']);
end

result = AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1;

if ~isstruct(result) || ~isfield(result,'archive') || isempty(result.archive)
    error('审计没有返回有效 result.archive；不要上传其他历史ZIP。');
end

z = char(result.archive);
if exist(z,'file') ~= 2
    error('审计返回的ZIP不存在：%s',z);
end

[~,bn,ext] = fileparts(z);
if isempty(regexpi([bn ext],'^E2_COMPLETE_RESTORE_AUDIT_.*\.zip$','once'))
    error('ZIP文件名不符合本轮正式审计格式：%s',z);
end

required = { ...
    'RESULT.json', ...
    '00_RUN_LOG.txt', ...
    '01_MODEL_PROPERTIES.csv', ...
    '02_CRITICAL_SCOPE.csv', ...
    '03_DIRECT_EDGES.csv', ...
    '04_NATIVE_FROM_GOTO.csv', ...
    '05_FUNCTION_INDEX.csv', ...
    '06_PARAMETERS.csv', ...
    '08_CRITICAL_INPUT_TRACES.csv', ...
    '09_COMMUNICATION_BOUNDARIES.csv', ...
    '09_RECORDER_SETTINGS.csv', ...
    '10_TARGETED_PATTERN_INVENTORY.csv', ...
    '11_DESIGN_QUESTIONS.csv', ...
    '12_ISSUES.csv', ...
    '12_BOUNDARY_NOTES.csv'};

names = string(unzipList(z));
missing = strings(0,1);
for k=1:numel(required)
    if ~any(names == string(required{k}))
        missing(end+1,1)=string(required{k}); %#ok<AGROW>
    end
end

if ~isempty(missing)
    fprintf('\n[PACKAGE VALIDATION FAIL] 缺少：\n');
    fprintf('  %s\n',missing);
    error('当前ZIP不是完整的ESS2正式恢复改模前审计结果，不要上传。');
end

fprintf('\n============================================================\n');
fprintf('[AUDIT PACKAGE VALIDATION PASS]\n');
fprintf('这才是需要上传的ZIP：\n%s\n',z);
fprintf('============================================================\n');
end

function names = unzipList(zipPath)
% 只列ZIP文件名，不解压模型，不修改任何源文件。
import java.util.zip.ZipFile
zf = ZipFile(java.io.File(zipPath));
c = onCleanup(@() zf.close());
e = zf.entries();
names = {};
while e.hasMoreElements()
    en = e.nextElement();
    if ~en.isDirectory()
        s = char(en.getName());
        [~,name,ext] = fileparts(s);
        names{end+1,1} = [name ext]; %#ok<AGROW>
    end
end
end

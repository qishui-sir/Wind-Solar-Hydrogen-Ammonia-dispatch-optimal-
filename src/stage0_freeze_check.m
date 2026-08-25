function report = stage0_freeze_check(config)
%STAGE0_FREEZE_CHECK Verify the cleaned Zhou baseline workspace boundary.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = project_root();
add_project_paths(project_dir);

run_tests = option_value(config, 'run_tests', true);
protocol = protocol_v5();
manifest = s2_baseline_manifest();

report = struct();
report.stage = "stage0";
report.executed_at = string(datetime('now', 'TimeZone', 'local'));
report.project_dir = string(project_dir);
report.protocol_valid = protocol_v5('verify', protocol);
report.manifest_valid = s2_baseline_manifest('verify', manifest);
report.required_files_missing = missing_required_files(project_dir);
report.forbidden_files_present = present_forbidden_files(project_dir);
report.forbidden_hits = scan_forbidden_references(project_dir);

if run_tests
    test_files = { ...
        fullfile(project_dir, 'test', 'test_my_system.m'), ...
        fullfile(project_dir, 'test', 'test_load_res_year.m'), ...
        fullfile(project_dir, 'test', 'test_protocol_v5.m')};
    test_results = runtests(test_files);
    report.test_log = "";
    report.test_count = numel(test_results);
    report.test_passed_count = nnz([test_results.Passed]);
    report.tests_passed = all([test_results.Passed]);
else
    report.test_log = "";
    report.test_count = 0;
    report.test_passed_count = 0;
    report.tests_passed = true;
end

report.passed = report.protocol_valid && report.manifest_valid && ...
    isempty(report.required_files_missing) && ...
    isempty(report.forbidden_files_present) && ...
    isempty(report.forbidden_hits) && report.tests_passed;

if ~report.passed
    error('stage0_freeze_check:failed', ...
        'Stage 0 freeze check failed. Inspect the returned report.');
end
end

function project_dir = project_root()
src_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(src_dir);
end

function add_project_paths(project_dir)
addpath(fullfile(project_dir, 'src'));
addpath(fullfile(project_dir, 'src', 'params'));
addpath(fullfile(project_dir, 'src', 'results'));
addpath(fullfile(project_dir, 'src', 'protocol'));
end

function missing_files = missing_required_files(project_dir)
required_files = [
    "src/load_res_year.m"
    "src/baseline.m"
    "src/dispatch_model.m"
    "src/rolling_dispatch.m"
    "src/params/default.m"
    "src/params/AEL.m"
    "src/params/HB.m"
    "src/params/my_system.m"
    "src/protocol/protocol_v5.m"
    "src/protocol/s2_baseline_manifest.m"
    "test/test_my_system.m"
    "test/test_load_res_year.m"
    "test/test_protocol_v5.m"];

missing_files = strings(0, 1);
for file_index = 1:numel(required_files)
    file_path = fullfile(project_dir, char(required_files(file_index)));
    if ~isfile(file_path)
        missing_files(end + 1, 1) = required_files(file_index); %#ok<AGROW>
    end
end
end

function present_files = present_forbidden_files(project_dir)
forbidden_files = [
    "src/algorithm.m"
    "src/" + "qi_ael_" + "model.m"
    "src/class/" + "AEL" + "Config.m"
    "test/" + "test_load_res_" + "7day.m"
    "test/test_myself.m"];

present_files = strings(0, 1);
for file_index = 1:numel(forbidden_files)
    file_path = fullfile(project_dir, char(forbidden_files(file_index)));
    if isfile(file_path)
        present_files(end + 1, 1) = forbidden_files(file_index); %#ok<AGROW>
    end
end
end

function hits = scan_forbidden_references(project_dir)
tokens = [
    "load_res_" + "7day"
    "qi_ael_" + "model"
    "AEL" + "Config"
    "AEL." + "detail"
    "time." + "days"];

files = [
    dir(fullfile(project_dir, 'src', '**', '*.m'))
    dir(fullfile(project_dir, 'test', '**', '*.m'))
    dir(fullfile(project_dir, 'docs', '**', '*.md'))];

hits = strings(0, 1);
for file_index = 1:numel(files)
    file_path = fullfile(files(file_index).folder, files(file_index).name);
    if strcmp(files(file_index).name, 'stage0_freeze_check.m')
        continue
    end

    text = string(fileread(file_path));
    for token_index = 1:numel(tokens)
        if contains(text, tokens(token_index))
            hit = relative_path(project_dir, file_path) + " :: " + ...
                tokens(token_index);
            hits(end + 1, 1) = hit; %#ok<AGROW>
        end
    end
end
end

function rel_path = relative_path(project_dir, file_path)
prefix = [project_dir filesep];
if startsWith(file_path, prefix)
    rel_path = string(extractAfter(file_path, strlength(prefix)));
else
    rel_path = string(file_path);
end
rel_path = replace(rel_path, filesep, "/");
end

function value = option_value(config, name, default_value)
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
else
    value = default_value;
end
end

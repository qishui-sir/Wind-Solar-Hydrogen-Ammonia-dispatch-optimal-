function test_results = run_full_tests(config)
%RUN_FULL_TESTS Run all MATLAB tests under test/.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
assert_success = option_value(config, 'assert_success', true);

test_results = runtests(fullfile(project_dir, 'test'), ...
    'IncludeSubfolders', true);
fprintf('\n========== Full test summary ==========\n');
fprintf('Total: %d; Passed: %d; Failed: %d\n', numel(test_results), ...
    nnz([test_results.Passed]), nnz(~[test_results.Passed]));
fprintf('=======================================\n');

if assert_success && ~all([test_results.Passed])
    error('run_full_tests:failed', 'One or more full tests failed.');
end
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(fullfile(src_dir, 'utils'), '-begin');
project_dir = setup_project_paths(project_dir);
end

function value = option_value(config, name, default_value)
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
else
    value = default_value;
end
end
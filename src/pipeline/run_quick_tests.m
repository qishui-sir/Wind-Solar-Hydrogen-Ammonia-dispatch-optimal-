function test_results = run_quick_tests(config)
%RUN_QUICK_TESTS Run deterministic Stage 0 and unit-level checks.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
assert_success = option_value(config, 'assert_success', true);

test_files = { ...
    fullfile(project_dir, 'test', 'test_my_system.m'), ...
    fullfile(project_dir, 'test', 'test_load_res_year.m'), ...
    fullfile(project_dir, 'test', 'test_protocol_v5.m'), ...
    fullfile(project_dir, 'test', 'test_chose_index.m'), ...
    fullfile(project_dir, 'test', 'test_CI_vertify.m'), ...
    fullfile(project_dir, 'test', 'test_stage0_reproducibility.m')};

test_results = runtests(test_files);
display_test_summary(test_results);
if assert_success && ~all([test_results.Passed])
    error('run_quick_tests:failed', 'One or more quick tests failed.');
end
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(fullfile(src_dir, 'utils'), '-begin');
project_dir = setup_project_paths(project_dir);
end

function display_test_summary(test_results)
fprintf('\n========== Quick test summary ==========\n');
fprintf('Total: %d; Passed: %d; Failed: %d\n', numel(test_results), ...
    nnz([test_results.Passed]), nnz(~[test_results.Passed]));
fprintf('========================================\n');
end

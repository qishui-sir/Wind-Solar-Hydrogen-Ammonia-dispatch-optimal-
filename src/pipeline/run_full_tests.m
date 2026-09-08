function test_results = run_full_tests(config)
%RUN_FULL_TESTS Run all MATLAB tests under test/.

if nargin < 1 || isempty(config)
    config = struct();
end

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath'));
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

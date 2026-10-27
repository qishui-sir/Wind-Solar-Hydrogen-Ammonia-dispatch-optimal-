function tests = test_O1_cache
%TEST_O1_CACHE Small reference-cache regressions; invokes short MILP solves.
% Run only when tests are explicitly requested. No annual experiment is run.
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src');
test_case.TestData.old_path = path;
addpath(src_dir, fullfile(src_dir, 'params'), ...
    fullfile(src_dir, 'results'), fullfile(src_dir, 'algorithm'), ...
    fullfile(src_dir, 'algorithm', 'O1'));

data_cfg = struct('pv_year', 2022, 'pw_year', 2022, ...
    'pv_capacity_kw', 200000, 'pw_capacity_kw', 200000, ...
    'day_count', 1);
test_case.TestData.renewable_data = load_res_year(data_cfg);
end

function teardownOnce(test_case)
path(test_case.TestData.old_path);
end

function test_cache_rejects_changed_target(test_case)
[work_dir, cleanup] = temporary_cache_directory(); %#ok<ASGLU>
params = cache_test_params();
config = cache_test_config(params, ...
    test_case.TestData.renewable_data.time_count, 0.40, work_dir);

[~, first_output] = run_o1(params, test_case.TestData.renewable_data, config);
verifyTrue(test_case, isfile(fullfile(work_dir, 'O1_stage1_cache.mat')));
verifyFalse(test_case, contains(first_output, 'loaded from cache'));

[~, same_output] = run_o1(params, test_case.TestData.renewable_data, config);
verifyTrue(test_case, contains(same_output, 'loaded from cache'));

changed_config = config;
changed_config.nh3_target_t = target_output_t(params, ...
    test_case.TestData.renewable_data.time_count, 0.45);
[~, changed_output] = run_o1(params, ...
    test_case.TestData.renewable_data, changed_config);
verifyFalse(test_case, contains(changed_output, 'loaded from cache'));
end

function test_cache_rejects_changed_storage_capacity(test_case)
[work_dir, cleanup] = temporary_cache_directory(); %#ok<ASGLU>
params = cache_test_params();
config = cache_test_config(params, ...
    test_case.TestData.renewable_data.time_count, 0.40, work_dir);

run_o1(params, test_case.TestData.renewable_data, config);
changed_params = params;
changed_params.h2_storage.capacity = 1.1 * params.h2_storage.capacity;
[~, changed_output] = run_o1(changed_params, ...
    test_case.TestData.renewable_data, config);
verifyFalse(test_case, contains(changed_output, 'loaded from cache'));
end

function params = cache_test_params()
params = my_system('s2');
params.AEL.common.startup = true;
params.environment.co2_enabled = false;
params.grid.curtail_limit = 1;
params.grid.max_sell = 1;
params.solver.display = 'off';
end

function config = cache_test_config(params, time_count, target_fraction, work_dir)
config = struct();
config.nh3_target_t = target_output_t(params, time_count, target_fraction);
config.economic_delta_usd_t = 0;
config.cache_directory = work_dir;
config.use_cache = true;
config.defer_feasibility_search = true;
% This suite checks Stage 1 cache isolation, not economic-threshold search.
config.economic_run_budget_s = eps;
config.max_time_s = 5;
config.cost_relative_gap = 0.02;
config.count_absolute_gap = 0.99;
config.change_epsilon = 0.01;
config.display = 'off';
end

function value = target_output_t(params, time_count, load_fraction)
value = load_fraction * params.HB.nh3_output * time_count * ...
    params.time.step / params.unit.mass_scale;
end

function [study, output] = run_o1(params, renewable_data, config)
output = evalc(['study = baseline(params, renewable_data, ', ...
    '@(model) O1(model, config));']);
end

function [work_dir, cleanup] = temporary_cache_directory()
work_dir = tempname;
mkdir(work_dir);
cleanup = onCleanup(@() remove_temporary_cache(work_dir));
end

function remove_temporary_cache(work_dir)
if ~isfolder(work_dir), return; end
[work_ok, work_info] = fileattrib(work_dir);
[root_ok, root_info] = fileattrib(tempdir);
if ~work_ok || ~root_ok
    warning('test_O1_cache:cleanup_skipped', 'Cannot resolve temporary cache path.');
    return
end
temp_root = root_info.Name;
if temp_root(end) ~= filesep, temp_root = [temp_root, filesep]; end
if ~startsWith(work_info.Name, temp_root, 'IgnoreCase', ispc)
    warning('test_O1_cache:cleanup_skipped', 'Cache path is outside the temporary folder.');
    return
end
rmdir(work_info.Name, 's');
end

function tests = test_O1_cache
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src');
test_case.TestData.old_path = path;
addpath(src_dir, fullfile(src_dir, 'params'), ...
    fullfile(src_dir, 'results'), fullfile(src_dir, 'class'), ...
    fullfile(src_dir, 'algorithm'));

data_cfg = struct('pv_year', 2022, 'pw_year', 2022, ...
    'pv_capacity_kw', 200000, 'pw_capacity_kw', 200000, ...
    'day_count', 1);
test_case.TestData.renewable_data = load_res_year(data_cfg);
end

function teardownOnce(test_case)
path(test_case.TestData.old_path);
end

function test_cache_rejects_changed_target(test_case)
[work_dir, cleanup] = temporary_working_directory(); %#ok<ASGLU>
params = cache_test_params();
config = cache_test_config(params, ...
    test_case.TestData.renewable_data.time_count, 0.40);

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
[~, cleanup] = temporary_working_directory(); %#ok<ASGLU>
params = cache_test_params();
config = cache_test_config(params, ...
    test_case.TestData.renewable_data.time_count, 0.40);

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

function config = cache_test_config(params, time_count, target_fraction)
config = struct();
config.nh3_target_t = target_output_t(params, time_count, target_fraction);
config.cost_allowance_usd_t = 0;
config.frontier_k = [];
config.max_time_s = 5;
config.cost_relative_gap = 0.02;
config.count_absolute_gap = 0.99;
config.change_epsilon = 0.01;
config.penalty_alpha = 1;
config.penalty_max_time_s = 1;
config.penalty_relative_gap = 0.02;
config.max_count_bound_width = 0;
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

function [work_dir, cleanup] = temporary_working_directory()
old_dir = pwd;
work_dir = tempname;
mkdir(work_dir);
cd(work_dir);
cleanup = onCleanup(@() restore_working_directory(old_dir, work_dir));
end

function restore_working_directory(old_dir, work_dir)
cd(old_dir);
if isfolder(work_dir)
    rmdir(work_dir, 's');
end
end

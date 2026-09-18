function tests = test_O1_search
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

function test_uses_fixed_k_cost_search(test_case)
[~, cleanup] = temporary_working_directory(); %#ok<ASGLU>
params = my_system('s2');
params.AEL.common.startup = true;
params.environment.co2_enabled = false;
params.grid.curtail_limit = 1;
params.grid.max_sell = 1;
params.solver.display = 'off';

T = test_case.TestData.renewable_data.time_count;
config = struct();
config.nh3_target_t = 0.40 * params.HB.nh3_output * T * ...
    params.time.step / params.unit.mass_scale;
config.cost_allowance_usd_t = [1, 1e6];
config.frontier_k = [];
config.max_time_s = 5;
config.cost_relative_gap = 0.02;
config.count_absolute_gap = 0.99;
config.change_epsilon = 0.01;
config.penalty_alpha = 1;
config.penalty_max_time_s = 1;
config.penalty_relative_gap = 0.02;
config.max_count_bound_width = Inf;
config.max_k_search_points = 8;
config.display = 'off';

study = baseline(params, test_case.TestData.renewable_data, ...
    @(model) O1(model, config));
verifyEqual(test_case, study.search.method, "cost_at_fixed_K");
verifyEqual(test_case, study.search.solver_model_build_count, 1);
verifyGreaterThanOrEqual(test_case, height(study.search.points), 1);
verifyTrue(test_case, all(study.search.points.objective_kind == "cost"));
verifyEqual(test_case, numel(unique(study.search.points.K)), ...
    height(study.search.points));
check = study.check.minimum_updates_representative;
verifyLessThanOrEqual(test_case, abs(check.nh3_residual_t), 1e-6);
verifyLessThanOrEqual(test_case, check.max_power_residual_kw, 1e-5);
verifyLessThanOrEqual(test_case, check.max_storage_residual_kg, 1e-5);
verifyLessThanOrEqual(test_case, check.binary_updates, ...
    study.feasibility.K_upper);
solution = study.feasibility.minimum_cost_at_upper_bound.solution;
verifyLessThanOrEqual(test_case, ...
    max(abs(solution.SU_AEL(:) - round(solution.SU_AEL(:)))), 1e-7);
verifyLessThanOrEqual(test_case, ...
    max(abs(solution.SD_AEL(:) - round(solution.SD_AEL(:)))), 1e-7);
verifyEqual(test_case, study.economic(2).K_lower, 0);
verifyEqual(test_case, study.economic(2).K_upper, 0);
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

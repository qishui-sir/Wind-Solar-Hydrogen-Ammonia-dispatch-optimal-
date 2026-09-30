if ~exist('study_year', 'var') || isempty(study_year)
    study_year = 2022;
end
validateattributes(study_year, {'numeric'}, ...
    {'scalar', 'integer', 'finite', 'positive'}, mfilename, 'study_year');
clearvars -except study_year;
clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
results_dir = fullfile(source_dir, 'results');
class_dir = fullfile(source_dir, 'class');
algorithm_dir = fullfile(source_dir, 'algorithm');
addpath(source_dir, params_dir, results_dir, class_dir, algorithm_dir);

data_cfg = struct();
data_cfg.pv_year = study_year;
data_cfg.pw_year = study_year;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);
fprintf('[main] study year=%d, modeled hours=%d.\n', ...
    study_year, renewable_data.time_count);

params = my_system('s2');
params.AEL.common.startup = true;
params.solver.relative_gap = 0.02;

ael_output = qi_ael_model(2000, 0, params.AEL.detail); 

fprintf('[main] AEL startup electricity=%d (%.2f load fraction/h), no extra charge\n', ...
    params.AEL.common.startup, params.AEL.common.startup_elec);

o1_config = struct();
o1_config.nh3_target_t = 80000;
o1_config.cost_allowance_usd_t = [0, 1, 5, 10];
o1_config.frontier_k = [];
o1_config.frontier_all_k = true;
o1_config.frontier_max_time_s = 60;
o1_config.frontier_max_attempts = 1;
o1_config.frontier_solution_interval = 25;
o1_config.frontier_run_budget_s = 1800;
o1_config.frontier_points_per_run = 200;
o1_config.compute_frontier_during_search = true;
o1_config.max_time_s = 1200;
o1_config.count_max_time_s = 900;
o1_config.fixed_max_time_s = 180;
o1_config.cost_relative_gap = 1e-3;
o1_config.count_absolute_gap = 0.99;
o1_config.change_epsilon = 0.01;
% Kfeas保留严格区间也继续计算逐K经济成本，避免单点unknown阻塞O1。
o1_config.max_count_bound_width = Inf;
% 自主认证K*：单次运行限时、逐任务缓存，中断后再次运行自动续算。
o1_config.max_k_search_points = 160;
o1_config.feasibility_probe_k = [];
o1_config.autonomous_search = true;
o1_config.run_budget_s = 3600;
o1_config.max_k_attempts_per_source = 2;
% 启用由原模型LP严格推导的冗余窗口覆盖割，只加强求解、不改变可行域。
o1_config.enable_window_cuts = false;
o1_config.window_lengths_h = 720;
o1_config.window_candidates_per_length = 25;
o1_config.max_window_cuts = 25;
o1_config.window_lp_max_time_s = 15;
o1_config.enable_start_repair = true;
o1_config.repair_max_time_s = 600;
o1_config.use_cache = true;
o1_config.display = 'iter';
fprintf('[main] baseline relative gap=%.4f; O1 cost gap=%.4f; ', ...
    params.solver.relative_gap, o1_config.cost_relative_gap);
fprintf('O1 count-continuation budget=%d; epsilon=%.2f%%\n', ...
    o1_config.max_k_search_points, 100 * o1_config.change_epsilon);
fprintf(['[main] all certified-feasible K values are queued; ', ...
    'per-point limit=%g s, ', ...
    'retry limit=%d.\n'], o1_config.frontier_max_time_s, ...
    o1_config.frontier_max_attempts);
fprintf(['[main] autonomous O1 enabled: feasibility budget=%g s, ', ...
    'frontier budget=%g s, frontier points/run=%d.\n'], ...
    o1_config.run_budget_s, o1_config.frontier_run_budget_s, ...
    o1_config.frontier_points_per_run);

O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));

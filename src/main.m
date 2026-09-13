clear;clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
results_dir = fullfile(source_dir, 'results');
class_dir = fullfile(source_dir, 'class');
algorithm_dir = fullfile(source_dir, 'algorithm');
addpath(source_dir, params_dir, results_dir, class_dir, algorithm_dir);

data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);

params = my_system('s2');
params.AEL.common.startup = true;   % S2 baseline with the S3 startup electricity
params.solver.relative_gap = 0.02;

ael_output = qi_ael_model(2000, 0, params.AEL.detail); 

fprintf('[main] AEL startup electricity=%d (%.2f load fraction/h), no extra charge\n', ...
    params.AEL.common.startup, params.AEL.common.startup_elec);

o1_config = struct();
o1_config.nh3_target_t = 80000;
o1_config.cost_allowance_usd_t = [0, 1, 5, 10];
o1_config.frontier_k = []; % Add selected K values after locating boundaries.
o1_config.max_time_s = 1200;
o1_config.cost_relative_gap = 1e-3;
o1_config.count_absolute_gap = 0.99;
o1_config.change_epsilon = 0.01; % 1% nominal HB-load scheduling deadband.
o1_config.max_count_bound_width = 20;
o1_config.display = 'iter';
fprintf('[main] baseline relative gap=%.4f; O1 cost gap=%.4f; ', ...
    params.solver.relative_gap, o1_config.cost_relative_gap);
fprintf('O1 count absolute gap=%.2f; epsilon=%.2f%%\n', ...
    o1_config.count_absolute_gap, 100 * o1_config.change_epsilon);

O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));

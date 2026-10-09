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
o1_dir = fullfile(algorithm_dir, 'O1');
addpath(source_dir, params_dir, results_dir, class_dir, ...
    algorithm_dir, o1_dir);

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
% main始终复用src缓存，不受调用时MATLAB当前目录影响；数据签名仍严格校验。
o1_config.cache_directory = source_dir;
o1_config.progress_file = fullfile(project_dir, '会话记录.md');
o1_config.nh3_target_t = 80000;
% delta是相对真实参考最优成本的经济损失限额，不是固定K求解误差。
o1_config.economic_delta_usd_t = 0.5;
o1_config.defer_feasibility_search = true;
% 两个成本帽模型与少量二分认证交替；每阶段结束就保存证据。
o1_config.economic_cap_time_s = 600;
o1_config.economic_fixed_time_s = 600;
o1_config.economic_retry_time_s = 1800;
% LP修复计入阶段总时限；宽松帽停滞后让出一轮，再以短预算试探。
o1_config.economic_lp_time_s = 30;
o1_config.economic_stalled_cap_time_s = 120;
o1_config.economic_max_attempts = 4;
o1_config.economic_points_per_round = 4;
o1_config.economic_max_solves_per_run = 64;
o1_config.economic_run_budget_s = Inf;
% 参考误差阻碍认证时按需续算，门槛始终保持delta=0.5。
o1_config.economic_reference_time_s = 600;
o1_config.economic_reference_max_refinements = 3;
o1_config.economic_reference_tolerance_usd_t = 0.001;
o1_config.economic_scale_solver = true;
o1_config.economics_solver = 'gurobi';
o1_config.gurobi_matlab_directory = '';
o1_config.gurobi_mip_focus = -1;
o1_config.gurobi_method = -1;
o1_config.gurobi_threads = 0;
o1_config.max_time_s = 1200;
o1_config.cost_relative_gap = 1e-3;
o1_config.change_epsilon = 0.01;
o1_config.enable_window_cuts = false;
o1_config.use_cache = true;
o1_config.display = 'iter';
fprintf('[main] 求Kref与Keco；Kfea搜索暂缓；delta=%.3g USD/t。\n', ...
    o1_config.economic_delta_usd_t);
fprintf('[main] 经济后端=%s；首轮每阶段%g s，续算%g s，最多%d轮。\n', ...
    o1_config.economics_solver,o1_config.economic_fixed_time_s, ...
    o1_config.economic_retry_time_s,o1_config.economic_max_attempts);
O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));
Kref = O1_results.Kref;
Keco = O1_results.Keco; % 未严格证明时为NaN；区间保存在O1_results.economic。

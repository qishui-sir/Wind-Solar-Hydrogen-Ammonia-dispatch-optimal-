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
o1_config.cost_allowance_usd_t = [0, 1, 5, 10];
o1_config.frontier_k = [];
o1_config.frontier_all_k = true;
o1_config.defer_feasibility_search = true;
o1_config.certify_all_frontier_k = true;
o1_config.frontier_max_time_s = 30;
o1_config.frontier_max_attempts = 1;
o1_config.frontier_solution_interval = 25;
o1_config.frontier_run_budget_s = 1800;
o1_config.frontier_points_per_run = 200;
% 锚点先提供成本界；目标区间内每个整数K都按0.5 USD/t验收。
o1_config.frontier_anchor_count = 12;
o1_config.frontier_key_k = 111;
o1_config.frontier_auto_key_count = 2;
o1_config.frontier_certification_tolerance_usd_t = 0.5;
o1_config.frontier_certification_max_time_s = 3600;
o1_config.frontier_certification_max_attempts = 4;
% 单次main连续遍历次数下界至参考解K；每轮每K最多尝试4次。
% 单K仍保留3600秒时限，超时轮转到其他K；未达标点按缓存续算。
o1_config.frontier_certification_points_per_run = Inf;
o1_config.frontier_certification_run_budget_s = Inf;
% 先尝试缓存HB模式的上界改进；失败只表示受限模式失败，不抬高全局下界。
o1_config.frontier_polish_enabled = true;
o1_config.frontier_polish_only = false;
o1_config.frontier_polish_max_time_s = 840;
o1_config.frontier_polish_max_attempts = 1;
% 固定模式失败后，自动搜索缓存模式并集及其循环时间邻域。
o1_config.frontier_pattern_pool_enabled = true;
o1_config.frontier_pattern_pool_radii_h = [0, 1, 3, 6, 12];
o1_config.frontier_pattern_pool_max_time_s = 240;
% 候选池失败后，依次采用全局成本帽、可热启动超额模型与台数外松弛认证。
% 新上界一律恢复原整数台数与方向变量，认证精度始终按原成本区间计算。
o1_config.frontier_global_bisection_enabled = true;
o1_config.frontier_global_bisection_max_time_s = 840;
o1_config.frontier_global_bisection_max_attempts = 6;
% 按购电增量选择少量局部窗口，仅改进可行上界，不把局部下界用于认证。
o1_config.frontier_local_cost_enabled = true;
o1_config.frontier_local_cost_window_h = 168;
o1_config.frontier_local_cost_max_time_s = 60;
o1_config.frontier_local_cost_max_windows = 3;
% 既有全局策略用尽后，再尝试少量更新时刻的全年远距离重定位。
o1_config.frontier_relocation_cost_enabled = true;
o1_config.frontier_relocation_cost_radii = [2, 4, 8];
o1_config.frontier_relocation_cost_max_time_s = 240;
% 只改变求解器内部连续变量单位；目标、整数变量和原物理矩阵不变。
o1_config.frontier_scale_solver = true;
% Gurobi先求解原MILP，不叠加旧后端的冗余成本底线；旧下界仍在记录层保留。
o1_config.frontier_bound_floor = false;
% 高精度认证恢复原启停方向整数性，避免依赖启动方向外松弛的弱证书。
o1_config.frontier_keep_startup_binary = true;
% 仅替换固定K经济后端；计数求解暂保留旧实现，原模型和缓存签名不变。
% 接口路径先复用MATLAB路径，再从GUROBI_HOME或系统命令路径发现。
o1_config.frontier_solver = 'gurobi';
o1_config.gurobi_matlab_directory = '';
% -1表示按缓存尝试次数选择0/3/1/2策略；不是传给Gurobi的原生参数值。
o1_config.gurobi_mip_focus = -1;
o1_config.gurobi_method = -1;
o1_config.gurobi_threads = 0;
% 下一轮将块长增至672小时以保留更多跨时段耦合；原模型完整MILP仍负责最终认证。
o1_config.gurobi_partition_enabled = true;
o1_config.gurobi_partition_hours = [672];
o1_config.gurobi_partition_time_s = [180];
o1_config.gurobi_partition_refine_blocks = 0;
o1_config.gurobi_partition_refine_time_s = 180;
o1_config.gurobi_partition_max_attempts = 3;
o1_config.gurobi_partition_upper_time_s = 300;
o1_config.gurobi_partition_outer_time_s = 0;
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
fprintf(['[main] 目标区间为次数下界至参考经济解K，每个整数K均验收；', ...
    '锚点单次上限=%g s，尝试上限=%d。\n'], o1_config.frontier_max_time_s, ...
    o1_config.frontier_max_attempts);
fprintf('[main] 固定K经济后端=%s；原约束、参数和目标函数保持不变。\n', ...
    o1_config.frontier_solver);
fprintf('[main] K认证分区下界=%d；分区时长=%s h；本轮单点时限=%g s。\n', ...
    o1_config.gurobi_partition_enabled, mat2str(o1_config.gurobi_partition_hours), ...
    o1_config.frontier_certification_max_time_s);
fprintf(['[main] Kfeas搜索暂缓；整区间连续经济认证，', ...
    '单K时限=%g s，每轮每K最多%d次，目标<=%.3g USD/t。\n'], ...
    o1_config.frontier_certification_max_time_s, ...
    o1_config.frontier_certification_max_attempts, ...
    o1_config.frontier_certification_tolerance_usd_t);
if o1_config.frontier_polish_enabled
    fprintf(['[main] 关键K定向上界精修已启用：单次上限=%g s，', ...
        '仅精修=%d。\n'], o1_config.frontier_polish_max_time_s, ...
        o1_config.frontier_polish_only);
end
if o1_config.frontier_pattern_pool_enabled
    fprintf(['[main] HB候选池半径=%s h，单阶段上限=%g s；', ...
        '全局成本帽二分=%d。\n'], ...
        mat2str(o1_config.frontier_pattern_pool_radii_h), ...
        o1_config.frontier_pattern_pool_max_time_s, ...
        o1_config.frontier_global_bisection_enabled);
end

O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));

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
% 默认只计算84、90、100、110……及参考解的实际K端点。
% 后续补点：例如frontier_k=[85,86,95]；全部整数点：frontier_k_step=1。
o1_config.frontier_k = [];
o1_config.frontier_all_k = true;
o1_config.frontier_k_start = 84;
o1_config.frontier_k_step = 10;
o1_config.defer_feasibility_search = true;
o1_config.certify_all_frontier_k = true;
o1_config.frontier_solution_interval = 25;
% 仅选定点按0.5 USD/t验收，未选中的点不进入求解队列。
o1_config.frontier_key_k = [];
o1_config.frontier_certification_tolerance_usd_t = 0.5;
o1_config.frontier_screening_max_time_s = 600;
o1_config.frontier_certification_max_time_s = 3600;
o1_config.frontier_certification_max_attempts = 4;
% 先按每K 600秒遍历所有选定点；全部完成后再按3600秒处理困难点。
% 每次main每K最多4次（含本轮短遍历）；超时未达标只缓存进度，不计最终结果。
o1_config.frontier_certification_points_per_run = Inf;
o1_config.frontier_certification_run_budget_s = Inf;
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
% -1自动选择策略；无可行首解时优先1，有首解时按缓存次数选择0/3/1/2。
o1_config.gurobi_mip_focus = -1;
% 逐K结果及短遍历标记保存在固定K缓存，不再为每次求解复制完整模型和.sol文件。
o1_config.gurobi_checkpoint_enabled = false;
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
% Kfeas保留严格区间也继续计算选定K的经济成本。
o1_config.max_count_bound_width = Inf;
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
fprintf('epsilon=%.2f%%\n', 100 * o1_config.change_epsilon);
fprintf(['[main] 目标点：起点K=%g、区间内%g的整数倍、参考经济解K；', ...
    '额外补点=%s，其余整数点暂缓。\n'], ...
    o1_config.frontier_k_start, o1_config.frontier_k_step, ...
    mat2str(o1_config.frontier_k));
fprintf('[main] 固定K经济后端=%s；原约束、参数和目标函数保持不变。\n', ...
    o1_config.frontier_solver);
fprintf('[main] K认证分区下界=%d；分区时长=%s h；本轮单点时限=%g s。\n', ...
    o1_config.gurobi_partition_enabled, mat2str(o1_config.gurobi_partition_hours), ...
    o1_config.frontier_certification_max_time_s);
fprintf(['[main] Kfeas搜索暂缓；先逐K短遍历%g s，再处理困难点%g s；', ...
    '每次main每K最多%d次，最终目标<=%.3g USD/t。\n'], ...
    o1_config.frontier_screening_max_time_s, o1_config.frontier_certification_max_time_s, ...
    o1_config.frontier_certification_max_attempts, ...
    o1_config.frontier_certification_tolerance_usd_t);
O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));

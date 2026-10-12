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
% 完整分解与可行解搜索交替推进；最后用相邻整数点严格认证。
o1_config.economic_cap_time_s = 600;
o1_config.economic_fixed_time_s = 600;
o1_config.economic_retry_time_s = 1800;
% 热启动及成本抛光的LP时间计入阶段总时限。
o1_config.economic_lp_time_s = 30;
o1_config.economic_event_time_s = 60; % 只记录有结论的删除试探；超时加时重试。
o1_config.economic_event_lp_time_s = 5;
o1_config.economic_event_candidates = 24;
o1_config.economic_event_retry_max_s = 20;
o1_config.economic_cut_margin = 1e-5;
o1_config.economic_annual_cut_limit = 256; % 全年MILP使用有限割池，完整定价保留全部有效割。
o1_config.economic_start_time_s = 3; % 限制起点补全，部分点使用变量提示。
o1_config.economic_stalled_cap_time_s = 120;
% 购售电净额抵消经矩阵条件检查；证明阶段保留AEL台数和启停整数。
o1_config.economic_grid_simplify = true;
o1_config.economic_proof_mode = 'full';
o1_config.economic_structural_search = true;
o1_config.economic_block_lengths_h = [96,192,384,768]; % 先至384 h，证据停滞后少量试验768 h。
o1_config.economic_block_budget_s = 1200;
o1_config.economic_block_round_time_s = 450;
o1_config.economic_block_lp_time_s = 60;
o1_config.economic_block_time_s = 5; % 所有块先短定价；上界下降仍续算冻结扫描。
o1_config.economic_block_max_time_s = 60;
o1_config.economic_block_refine_count = 3; % 完整证书后只加时复核误差最大的少数块。
o1_config.economic_block_batch = 8; % 定价检查点间隔；每份分解证书必须覆盖全部块。
o1_config.economic_block_max_cuts = 8192; % 保留有效割及部分扫描的固定行前缀。
o1_config.economic_decomposition_oracle_tolerance = 0.05; % 窄区间目标；宽区间按预测提升调整。
o1_config.economic_decomposition_tolerance = 0.2;
o1_config.economic_decomposition_stall_sweeps = 3;
o1_config.economic_decomposition_min_dual_sweeps = 4;
o1_config.economic_local_time_s = 90;
o1_config.economic_local_passes = 2;
o1_config.economic_local_headroom_usd = 3000; % 先降低成本，为联合删除事件留出余量。
o1_config.economic_local_target_step = 10; % 目标用于提前停止，保留旧K可行起点。
o1_config.economic_local_max_step = 10;
o1_config.economic_event_exchange_old = 64;
o1_config.economic_event_exchange_new = 64;
o1_config.economic_event_exchange_offsets = [-12,-6,-3,-1,1,3,6,12];
o1_config.economic_event_exchange_radius = 16;
o1_config.economic_ael_repair_hours = 48;
o1_config.economic_local_integer_limit = 160;
% 分解松弛求准后仍有整数差距时，再启动分支定价认证。
o1_config.economic_branch_enable = true;
o1_config.economic_branch_time_s = 120;
o1_config.economic_branch_price_time_s = 10;
o1_config.economic_branch_max_nodes = 32;
o1_config.economic_branch_relaxation_gap = 0.5;
o1_config.economic_branch_min_interval = 10;
o1_config.economic_final_interval = 20;
o1_config.economic_certification_time_s = 300; % 宽区间每次运行最多一次全年求界。
o1_config.economic_certification_reserve_s = 300;
o1_config.economic_certification_retry_gain = 1; % 连续下界提升至少1次才触发同模型重试。
o1_config.economic_max_attempts = 8;
o1_config.economic_points_per_round = 1;
o1_config.economic_max_solves_per_run = 4096;
% 先作30分钟效果验证；进度自动缓存，确认上下界推进后可延长预算。
o1_config.economic_run_budget_s = 1800;
% 参考误差阻碍认证时按需续算，门槛始终保持delta=0.5。
o1_config.economic_reference_time_s = 600;
o1_config.economic_reference_max_refinements = 3;
o1_config.economic_reference_tolerance_usd_t = 0.001;
o1_config.economic_scale_solver = true;
o1_config.economics_solver = 'gurobi';
o1_config.gurobi_matlab_directory = '';
o1_config.gurobi_mip_focus = -1;
o1_config.gurobi_method = -1;
o1_config.gurobi_threads = 4;
o1_config.max_time_s = 1200;
o1_config.cost_relative_gap = 1e-3;
o1_config.change_epsilon = 0.01;
o1_config.enable_window_cuts = false;
o1_config.use_cache = true;
o1_config.display = 'iter';
fprintf('[main] 求Kref与Keco；Kfea搜索暂缓；delta=%.3g USD/t。\n', ...
    o1_config.economic_delta_usd_t);
fprintf('[main] 经济后端=%s；经济阶段预算%g s，分块预算%g s，局部每次%g s。\n', ...
    o1_config.economics_solver,o1_config.economic_run_budget_s, ...
    o1_config.economic_block_budget_s,o1_config.economic_local_time_s);
O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));
Kref = O1_results.Kref;
Keco = O1_results.Keco; % 未严格证明时为NaN；区间保存在O1_results.economic。
if isfield(O1_results,'threshold_state')
    convergence_report = O1_results.threshold_state.structural_report;
    fprintf('[main] 严格区间宽度%g -> %g，压缩%.1f%%；下界+%g，上界减少%g，收敛目标达成=%d。\n', ...
        convergence_report.initial_width,convergence_report.current_width, ...
        100*convergence_report.width_reduction_fraction,convergence_report.lower_gain, ...
        convergence_report.upper_gain,convergence_report.acceptance_target_met);
    fprintf('[main] 本轮新增完整分解扫描%d轮，累计%d轮；完整分解推进目标达成=%d。\n', ...
        convergence_report.new_complete_sweeps,convergence_report.complete_sweeps, ...
        convergence_report.decomposition_progress_met);
end
if isfield(O1_results,'threshold_state') && isfield(O1_results.threshold_state,'decomposition') && ...
        isfield(O1_results.threshold_state.decomposition,'best_lower')
    decomposition_report=O1_results.threshold_state.decomposition;
    fprintf('[main] 分解下界=%.6f；DW受限主问题上界=%.6f（仅用于分解收敛）；状态=%s。\n', ...
        decomposition_report.best_lower,decomposition_report.master_upper,decomposition_report.stop_reason);
    if isfield(decomposition_report,'master_report')
        master_report=decomposition_report.master_report;
        fprintf('[main] 主问题算法=%g，原始残差=%.3g，数值检查=%s。\n', ...
            master_report.algorithm,master_report.original_residual,master_report.reason);
    end
end
if isfield(O1_results,'threshold_state') && isfield(O1_results.threshold_state,'branch') && ...
        isfield(O1_results.threshold_state.branch,'nodes')
    branch_report=O1_results.threshold_state.branch;
    fprintf('[main] 分支定价：完整覆盖下界=%g，保留%d个节点，状态=%s。\n', ...
        branch_report.global_lower,numel(branch_report.nodes),branch_report.status);
end
if isfield(O1_results,'threshold_state')
    fprintf('[main] 当前严格经济余量=%.3f USD；余量与求解误差分别记录。\n', ...
        O1_results.threshold_state.structural_report.strict_slack_usd);
end
if isnan(Keco)
    fprintf('[main] Keco尚未严格认证；已保存证据及分解进度，下次运行main续算。\n');
else
    fprintf('[main] 已严格认证：Kref=%g，Keco=%g，经济损失上限=%.3g USD/t。\n', ...
        Kref,Keco,o1_config.economic_delta_usd_t);
end

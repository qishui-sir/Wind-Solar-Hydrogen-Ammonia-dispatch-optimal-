if ~exist('study_year', 'var') || isempty(study_year)
    study_year = 2022;
end
validateattributes(study_year, {'numeric'}, ...
    {'scalar', 'integer', 'finite', 'positive'}, mfilename, 'study_year');
% 默认计算/恢复完整分区证书后返回；设为true可继续原来的上界和决定性搜索。
if ~exist('continue_economic_search', 'var') || isempty(continue_economic_search)
    continue_economic_search = false;
end
validateattributes(continue_economic_search, {'logical','numeric'}, {'scalar','binary'});
% 是否启用缓存：true=读取并写入src/cache下已有证据，可跨轮次续算；
% false=不复用/回写旧缓存状态；分区模型、raw和检查点仍保存到本轮独立证据目录。
if ~exist('use_cache', 'var') || isempty(use_cache)
    use_cache = true;
end
validateattributes(use_cache, {'logical','numeric'}, {'scalar','binary'});
use_cache = logical(use_cache);
clearvars -except study_year continue_economic_search use_cache;
clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
results_dir = fullfile(source_dir, 'results');
algorithm_dir = fullfile(source_dir, 'algorithm');
o1_dir = fullfile(algorithm_dir, 'O1');
addpath(source_dir, params_dir, results_dir, ...
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

fprintf('[main] AEL startup electricity=%d (%.2f load fraction/h), no extra charge\n', ...
    params.AEL.common.startup, params.AEL.common.startup_elec);

o1_config = struct();
% 运行态缓存统一放在src/cache：main读取的全部.mat都在这里。
%   O1_economic_threshold_partition21_cache.mat  分块证书状态（Keco区间证据）
%   O1_economic_threshold_cache.mat              旧版经济阈值状态（回退读取）
%   O1_stage1_cache.mat                          Stage 1 参考解
%   O1_partition21_v1/                           分块证书检查点树
%   legacy/                                      搬迁前的旧.mat快照，不参与读取
% 其余中间产物仍在project/dsh_test下：reports/ 报告与进度  logs/ 主流程日志
%   probes/ 探针与其实验日志  audit/ 独立证书审计  diag/ 结构与语法检查
%   validation/ 30天端到端验证  archive/ 一次性产物
cache_directory = fullfile(source_dir, 'cache');
if ~isfolder(cache_directory)
    mkdir(cache_directory);
end
o1_config.cache_directory = cache_directory;
o1_config.progress_file = fullfile(project_dir, 'dsh_test', 'reports', 'O1进度.md');
o1_config.nh3_target_t = 80000;
% delta是相对真实参考最优成本的经济损失限额，不是固定K求解误差。
o1_config.economic_delta_usd_t = 0.5;
o1_config.defer_feasibility_search = true;
% ---- 决定性搜索（v2/v3）：只有“见证”或“排除证书”能推进Keco区间 ----
% v3 起：固定z（平台重拟合）产生的界与不可行性一律不作为F(K)的排除证据（限制模型的界不合法）。
o1_config.economic_search_version = 3;
o1_config.economic_adjacent_attempts = 2;
o1_config.economic_decide_relaxations = true;
o1_config.economic_decide_scale = true;   % 目标压缩到允许成本量级，避免数值噪声
o1_config.economic_decide_gap_usd = 4;    % 决定性求解决策间隔(USD)
o1_config.economic_band_fraction = 0.001; % 参考带目标：允许成本的0.1%（=40 USD），配合 gap/4 逐轮收紧，用于测试 C* 括号能夹多紧
o1_config.economic_reference_max_refinements = 6;
o1_config.economic_reference_time_s = 2400;
o1_config.economic_reference_tolerance_usd_t = 0.001;
% 决定性求解首轮/加时上限；跨轮次运行会继续加时而不是重投同样的时限。
o1_config.economic_fixed_time_s = 900;
o1_config.economic_retry_time_s = 7200;
o1_config.economic_certification_time_s = 7200;
o1_config.economic_cap_time_s = 1200;
% 计数目标（min count）的模型使用全部有效割：实测下界 256条→361、2048条→403、2192条→404.92。
o1_config.economic_count_cut_limit = 0;      % 派生割池经查不可靠：放松整数的模型在含割时给出 >已知可行值的界（不合法），故关闭
% 决定性求解每轮总预算限流（单次上限仍是 economic_secondary_time_cap_s）：
% 实测真正的下降全部来自降序搜索，决定性求解常以 TIME_LIMIT 收场，因此只留 1800 s。
o1_config.economic_decisive_budget_s = 1800;
% 上界启发式（平台重拟合/局部/事件）有独立预算；平台重拟合是压低计数的实际主力，
% 因此给它较大的预算份额，同时保留决定性求解所需的加时预算。
o1_config.economic_primal_budget_s = 10800;
o1_config.economic_primal_slice_s = 1200;
o1_config.economic_primal_first_s = 1200;
o1_config.economic_plateau_scan = 10;
o1_config.economic_plateau_time_s = 300;
o1_config.economic_plateau_lp_time_s = 10;
o1_config.economic_plateau_pattern_s = 600;    % 松弛模式生成（z整数/AEL放松）：独立探针需 ~1 h 才可能收敛，故管道内只当廉价彩票，主力仍是窗口路线
o1_config.economic_local_passes = 2;
o1_config.economic_local_time_s = 120;
o1_config.economic_local_headroom_usd = 3000;
o1_config.economic_local_target_step = 10;
o1_config.economic_local_max_step = 10;
o1_config.economic_local_integer_limit = 160;
o1_config.economic_event_time_s = 600;
o1_config.economic_event_lp_time_s = 20;
o1_config.economic_event_candidates = 48;
o1_config.economic_event_retry_max_s = 30;
o1_config.economic_event_exchange_old = 64;
o1_config.economic_event_exchange_new = 64;
o1_config.economic_event_exchange_offsets = [-12,-6,-3,-1,1,3,6,12];
o1_config.economic_event_exchange_radius = 16;
o1_config.economic_ael_repair_hours = 48;
o1_config.economic_lp_time_s = 30;
o1_config.economic_start_time_s = 3;
o1_config.economic_stalled_cap_time_s = 120;
o1_config.economic_points_per_round = 1;
o1_config.economic_final_interval = 20;
o1_config.economic_cut_margin = 1e-5;
o1_config.economic_annual_cut_limit = 0;
% 购售电净额抵消经矩阵条件检查；full用于决定性原整数模型。
% 分区下界另按固定根LP价格保留局部HB更新整数，放松其余整数。
o1_config.economic_grid_simplify = true;
o1_config.economic_proof_mode = 'full';
% 完整有限盒分块证书独立推进下界；旧DW/分支定价和派生割保持关闭。
o1_config.economic_structural_search = true;
o1_config.economic_branch_enable = false;
o1_config.economic_lower_policy_version = 4;
o1_config.economic_block_lengths_h = [96,192];
o1_config.economic_block_lp_time_s = 180;
o1_config.economic_block_time_s = 3;
o1_config.economic_block_max_time_s = 6;
o1_config.economic_block_budget_s = 900;
o1_config.economic_block_round_time_s = 900;
o1_config.economic_max_attempts = 24;
o1_config.economic_max_solves_per_run = 4096;
% 单轮运行预算；跨轮次续算同时加时，进度全部持久化。
o1_config.economic_run_budget_s = 14400;
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
o1_config.use_cache = use_cache;
o1_config.display = 'iter';
if ~continue_economic_search
    % 完整一轮包含根LP及全部局部块；结果来自实际证书和当前矩阵核验的调度。
    o1_config.economic_max_attempts = 1;
    o1_config.economic_run_budget_s = 1200;
end
fprintf('[main] 求Kref与Keco；Kfea搜索暂缓；delta=%.3g USD/t；参考带目标=%.1f USD。\n', ...
    o1_config.economic_delta_usd_t, ...
    o1_config.economic_band_fraction*o1_config.economic_delta_usd_t*o1_config.nh3_target_t);
fprintf('[main] 经济后端=%s；本次预算%g s。\n', ...
    o1_config.economics_solver,o1_config.economic_run_budget_s);
if continue_economic_search
    fprintf('[main] 决定性首轮%g s/加时上限%g s；上界启发式预算%g s。\n', ...
        o1_config.economic_fixed_time_s,o1_config.economic_retry_time_s, ...
        o1_config.economic_primal_budget_s);
else
    fprintf('[main] 完成全年分区计数证书后返回，已有上界调度按当前原模型核验。\n');
end
fprintf('[main] 运行模式：继续区间搜索=%d；分区=%s h，局部时限=%g/%g s。\n', ...
    continue_economic_search,mat2str(o1_config.economic_block_lengths_h), ...
    o1_config.economic_block_time_s,o1_config.economic_block_max_time_s);
if use_cache
    fprintf('[main] 缓存：启用，读取并写入 %s。\n', cache_directory);
else
    fprintf('[main] 缓存：不复用旧状态；本轮分区审计证据仍保存到独立目录。\n');
end
O1_results = baseline(params, renewable_data, ...
    @(model) O1(model, o1_config));
Kref = O1_results.Kref;
Keco = O1_results.Keco; % 未严格证明时为NaN；区间保存在O1_results.economic。
economic = O1_results.economic;
Keco_interval = [economic.K_lower, economic.K_upper];
allowance_usd = o1_config.economic_delta_usd_t * o1_config.nh3_target_t;
band_usd = economic.cost_cap_usd - economic.strict_cost_cap_usd;
if isfield(O1_results,'threshold_state')
    convergence_report = O1_results.threshold_state.structural_report;
    fprintf(['[main] Keco严格区间 %g -> %g（宽度%g -> %g），下界+%g，上界减少%g。\n'], ...
        convergence_report.initial_K_lower,convergence_report.initial_K_upper, ...
        convergence_report.initial_width,convergence_report.current_width, ...
        convergence_report.lower_gain,convergence_report.upper_gain);
    fprintf(['[main] 经济帽：sat=%.3f USD，fail=%.3f USD；允许成本A=%.1f USD；' ...
        '参考带=%.3f USD（占A的%.3f%%）；不可判定窗口宽度=%.3f USD。\n'], ...
        economic.strict_cost_cap_usd,economic.cost_cap_usd,allowance_usd, ...
        band_usd,100*band_usd/max(eps,allowance_usd),band_usd);
    if isfinite(convergence_report.decisive_K)
        fprintf('[main] 决定性求解：上一步K=%g，状态=%s，未判定原因=%s。\n', ...
            convergence_report.decisive_K,char(convergence_report.decisive_status), ...
            char(convergence_report.unresolved_reason));
    end
    if continue_economic_search && ~economic.is_proven
        fprintf(['[main] 下一步可在K=%g尝试改善区间：cost<=sat 的已验证见证可降低上界，' ...
            'min cost>fail 的有效下界可排除此次数及以下。\n'], ...
            economic.K_upper-1);
    end
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
if isfield(O1_results,'threshold_state')
    fprintf('[main] 当前严格经济余量=%.3f USD；余量与求解误差分别记录。\n', ...
        O1_results.threshold_state.structural_report.strict_slack_usd);
end
if isnan(Keco)
    fprintf(['[main] Keco尚未确定唯一值：Keco∈[%g,%g]，参考成本带宽%.3f USD；' ...
        '证据已缓存；继续搜索请先设置 continue_economic_search=true。\n'], ...
        economic.K_lower,economic.K_upper,band_usd);
else
    fprintf('[main] 已严格认证：Kref=%g，Keco=%g，经济损失上限=%.3g USD/t。\n', ...
        Kref,Keco,o1_config.economic_delta_usd_t);
end

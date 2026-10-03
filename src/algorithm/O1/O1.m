function study = O1(model, config)
%O1 统筹HB负荷设定值更新次数研究。
% 本文件负责配置、共享上下文、缓存读写和最终校验。
% O1Feasibility负责收缩可行K区间；O1Economics负责计算固定K成本
% 及其经济边界。
arguments
    model (1, 1) struct
    config (1, 1) struct
end

config = validate_config(config);
ctx = build_context(model, config);
ctx.services = struct( ...
    'fixed_point_store', @(varargin) persist_point_with_progress(ctx, varargin{:}), ...
    'solve_problem', @solve_problem, ...
    'build_fixed_solver', @build_fixed_solver, ...
    'recover_direction_binaries', @recover_direction_binaries, ...
    'migrate_cost_record', @migrate_cost_record, ...
    'add_change_indicators', @add_change_indicators, ...
    'evaluate_cost_components', @evaluate_cost_components, ...
    'evaluate_operation_metrics', @evaluate_operation_metrics);
window_info = struct('enabled', config.enable_window_cuts, ...
    'candidate_count', 0, 'cut_count', 0, ...
    'start_hour', zeros(0, 1), 'end_hour', zeros(0, 1), ...
    'minimum_updates', zeros(0, 1));

fprintf('\n[O1] Stage 1: economic reference\n');
reference = load_or_solve_reference(ctx);
study = struct('method', 'minimum_HB_load_updates', ...
    'definition', ['Number of cyclic hourly HB set-point updates; ', ...
    'HB load may remain inside the configured tracking band.'], ...
    'config', config, 'output_range_t', ctx.output_range_t, ...
    'window_cuts', window_info, 'reference', reference, ...
    'feasibility', struct(), 'economic', struct([]), ...
    'frontier', table(), 'frontier_structure', struct(), ...
    'cost_certification', table(), 'check', struct(), ...
    'progressive_penalty', struct());
if ~reference.has_incumbent
    study.status = 'incomplete_reference_no_incumbent';
    print_summary(study);
    return
end

reference.solution = add_change_indicators(reference.solution, ctx);
reference.count_upper = round(sum(reference.solution.O1_HB_change));
reference.cost_components = evaluate_cost_components(reference.solution, ctx);
reference.operation_metrics = evaluate_operation_metrics(reference.solution, ctx);
study.reference = reference;
study.check.reference = solution_check(reference.solution, ctx);

fprintf('[O1] Stage 2: direct minimum-count solve, initial K=%g\n', ...
    reference.count_upper);
[feasibility, feasibility_points, build_info] = ...
    O1Feasibility(ctx, reference.solution, Inf, "feasibility");
study.feasibility = feasibility;
if isfield(build_info, 'window_cuts')
    study.window_cuts = build_info.window_cuts;
end
study.search = struct( ...
    'method', "cost_at_fixed_K", ... % 兼容既有结果字段
    'strategy', "direct_count_with_fixed_k_feasibility", ...
    'solver_model_build_count', 1 + build_info.seed_validation_model_build_count, ...
    'solver_model_build_time_s', build_info.elapsed_s, ...
    'points', feasibility_points);
if feasibility.minimum_updates.has_incumbent
    study.check.minimum_updates = solution_check( ...
        feasibility.minimum_updates.solution, ctx);
end

if (~isfinite(feasibility.bound_width) || ...
        feasibility.bound_width > config.max_count_bound_width) && ...
        ~config.compute_frontier_during_search
    fprintf(['[O1] Stop after Stage 2: K_feas bound width %g exceeds ', ...
        'the configured limit %g.\n'], feasibility.bound_width, ...
        config.max_count_bound_width);
    study.status = 'incomplete_feasibility_bound';
    print_summary(study);
    return
end

economic_outputs = O1Economics(ctx, feasibility, reference);
representative = economic_outputs.representative;
frontier = economic_outputs.frontier;
frontier_state = economic_outputs.frontier_state;
if representative.has_incumbent && representative.count_upper < feasibility.K_upper
    % 经济优化发现更小实际计数时，立即刷新计数缓存；只读原矩阵，不启动K搜索。
    previous_upper = feasibility.K_upper;
    refresh_ctx = ctx;
    refresh_ctx.config.max_k_search_points = 0;
    [feasibility, refreshed_points, refreshed_build] = O1Feasibility( ...
        refresh_ctx, feasibility.minimum_updates.solution, Inf, "feasibility");
    study.feasibility = feasibility;
    study.search.points = refreshed_points;
    study.search.solver_model_build_count = ...
        study.search.solver_model_build_count + 1 + ...
        refreshed_build.seed_validation_model_build_count;
    study.search.solver_model_build_time_s = ...
        study.search.solver_model_build_time_s + refreshed_build.elapsed_s;
    study.check.minimum_updates = solution_check(feasibility.minimum_updates.solution, ctx);
    if feasibility.K_upper < previous_upper
        representative = promote_cost_seed(representative, ...
            feasibility.minimum_updates.solution, feasibility.K_upper, ctx);
        entry = struct('mode', "frontier_cost", 'cost_cap', Inf, ...
            'K', feasibility.K_upper, 'record', representative, ...
            'source', "verified_economic_count_seed");
        ctx.services.fixed_point_store(ctx.point_cache_file, ctx.cost_signature, ...
            "append", "frontier_cost", Inf, entry);
        % 只重建展示与证书表，不重启成本求解；新K必须出现在本轮结果中。
        refresh_ctx.config.frontier_points_per_run = 0;
        refresh_ctx.config.frontier_certification_points_per_run = 0;
        refresh_ctx.config.frontier_certification_run_budget_s = 0;
        refresh_ctx.config.cost_allowance_usd_t = [];
        economic_outputs = O1Economics(refresh_ctx, feasibility, reference);
        representative = economic_outputs.representative;
        frontier = economic_outputs.frontier;
        frontier_state = economic_outputs.frontier_state;
        fprintf('[O1] 经济解同步收缩计数区间：[%g, %g]，最小K已证明=%d。\n', ...
            feasibility.K_lower, feasibility.K_upper, feasibility.is_proven);
    end
end
study.feasibility.minimum_cost_at_upper_bound = representative;
study.frontier = frontier;
study.frontier_state = frontier_state;
study.frontier_structure = economic_outputs.structure;
study.cost_certification = economic_outputs.certification;
if representative.has_incumbent && isfield(representative, 'solution') && ...
        ~isempty(fieldnames(representative.solution))
    study.check.minimum_updates_representative = ...
        solution_check(representative.solution, ctx);
    witness_cost = evaluate(ctx.system_cost_usd, representative.solution);
    study.check.minimum_updates_representative.witness_cost_usd = witness_cost;
    study.check.minimum_updates_representative.upper_cost_witness_valid = ...
        witness_cost <= representative.objective_upper + ...
        max(1e-4, 1e-9 * abs(representative.objective_upper));
end

if ~feasibility.is_proven
    study.status = 'incomplete_feasibility_with_frontier';
    print_summary(study);
    return
end

if ~isfinite(reference.objective_lower)
    study.status = 'incomplete_reference_bound';
    print_summary(study);
    return
end

study.economic = economic_outputs.boundaries;
if ~frontier_state.certification_complete
    study.status = 'incomplete_cost_certification';
elseif isempty(study.economic) && ~isempty(config.cost_allowance_usd_t)
    study.status = 'incomplete_economic_boundaries';
elseif feasibility.is_proven && ...
        (isempty(study.economic) || all([study.economic.is_proven]))
    study.status = 'complete';
else
    study.status = 'complete_with_bounds';
end
print_summary(study);
end

function seed = promote_cost_seed(prior, solution, K, ctx)
%PROMOTE_COST_SEED C*(较小K)>=C*(原K)，可继承美元下界，但不继承求解历史。
seed = prior;
names = fieldnames(seed);
prefixes = ["polish_", "pattern_pool_", "global_bisection_", "local_cost_", ...
    "relocation_cost_", "pool_cost_optimization_", "last_cost_cap_", "raw_solver_"];
remove = false(size(names));
for i = 1:numel(names)
    remove(i) = any(startsWith(string(names{i}), prefixes));
end
seed = rmfield(seed, names(remove));
seed.solution = solution;
seed.K_limit = K;
seed.count_upper = round(sum(solution.O1_HB_change));
seed.count_lower = NaN;
seed.objective_upper = evaluate(ctx.system_cost_usd, solution);
seed.system_cost_upper = seed.objective_upper;
seed.absolute_gap = seed.objective_upper - seed.objective_lower;
seed.relative_gap = seed.absolute_gap / max(1, abs(seed.objective_upper));
seed.is_proven = seed.absolute_gap <= max(1e-7, eps(abs(seed.objective_upper)));
seed.is_certified = seed.absolute_gap / ctx.config.nh3_target_t <= ...
    ctx.config.frontier_certification_tolerance_usd_t;
seed.status = "seed_cost_bound";
seed.frontier_phase = "certification_seed";
seed.solve_backend = "verified_monotonic_cost_seed";
seed.inherited_cost_bound_K = prior.K_limit;
seed.elapsed_s = 0;
seed.exitflag = NaN;
seed.output = struct();
seed.frontier_attempts = 0;
seed.anchor_attempts = 0;
seed.certification_attempts = 0;
seed.scaled_certification_attempts = 0;
seed.floor_certification_attempts = 0;
seed.startup_binary_certification_attempts = 0;
seed.gurobi_certification_attempts = 0;
seed.cost_components = evaluate_cost_components(solution, ctx);
seed.operation_metrics = evaluate_operation_metrics(solution, ctx);
end

function config = validate_config(config)
defaults = struct( ...
    'nh3_target_t', 80000, ...
    'cost_allowance_usd_t', [0, 1, 5, 10], ...
    'frontier_k', [], ...
    'frontier_all_k', false, ...
    'frontier_max_time_s', 180, ...
    'frontier_max_attempts', 2, ...
    'frontier_solution_interval', 25, ...
    'frontier_run_budget_s', Inf, ...
    'frontier_points_per_run', 25, ...
    'frontier_anchor_count', 12, ...
    'frontier_key_k', [], ...
    'frontier_auto_key_count', 2, ...
    'frontier_certification_tolerance_usd_t', 0.5, ...
    'frontier_certification_max_time_s', 1800, ...
    'frontier_certification_max_attempts', 2, ...
    'frontier_certification_points_per_run', 1, ...
    'frontier_certification_run_budget_s', Inf, ...
    'frontier_polish_enabled', false, ...
    'frontier_polish_only', false, ...
    'frontier_polish_max_time_s', 900, ...
    'frontier_polish_max_attempts', 1, ...
    'frontier_pattern_pool_enabled', false, ...
    'frontier_pattern_pool_radii_h', [0, 1, 3, 6, 12], ...
    'frontier_pattern_pool_max_time_s', 300, ...
    'frontier_global_bisection_enabled', false, ...
    'frontier_global_bisection_max_time_s', 1800, ...
    'frontier_global_bisection_max_attempts', 6, ...
    'frontier_local_cost_enabled', false, ...
    'frontier_local_cost_window_h', 168, ...
    'frontier_local_cost_max_time_s', 60, ...
    'frontier_local_cost_max_windows', 3, ...
    'frontier_relocation_cost_enabled', false, ...
    'frontier_relocation_cost_radii', [2, 4, 8], ...
    'frontier_relocation_cost_max_time_s', 240, ...
    'frontier_scale_solver', false, ...
    'frontier_bound_floor', false, ...
    'frontier_keep_startup_binary', false, ...
    'frontier_solver', 'intlinprog', ...
    'gurobi_matlab_directory', '', ...
    'gurobi_mip_focus', 0, ...
    'gurobi_method', -1, ...
    'gurobi_threads', 0, ...
    'compute_frontier_during_search', true, ...
    'max_time_s', 1200, ...
    'count_max_time_s', 900, ...
    'fixed_max_time_s', 600, ...
    'cost_relative_gap', 1e-3, ...
    'count_absolute_gap', 0.99, ...
    'change_epsilon', 0.01, ...
    'max_count_bound_width', 0, ...
    'max_k_search_points', 16, ...
    'feasibility_probe_k', [], ...
    'autonomous_search', false, ...
    'run_budget_s', Inf, ...
    'max_k_attempts_per_source', 2, ...
    'change_tolerance', 1e-6, ...
    'enable_window_cuts', true, ...
    'window_lengths_h', [72, 168], ...
    'window_candidates_per_length', 2, ...
    'max_window_cuts', 4, ...
    'window_lp_max_time_s', 45, ...
    'enable_start_repair', true, ...
    'repair_max_time_s', 300, ...
    'use_cache', true, ...
    'cache_directory', '', ...
    'progress_file', '', ...
    'display', 'off', ...
    ... % 兼容旧配置，已不参与求解。
    'penalty_alpha', [0.1, 1, 10], ...
    'penalty_max_time_s', 300, ...
    'penalty_relative_gap', 0.02);
allowed = fieldnames(defaults);
unknown = setdiff(fieldnames(config), allowed);
if ~isempty(unknown)
    error('O1:unknown_config', 'Unknown O1 option: %s.', unknown{1});
end
for i = 1:numel(allowed)
    name = allowed{i};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    end
end

if ~(ischar(config.cache_directory) || ...
        (isstring(config.cache_directory) && isscalar(config.cache_directory)))
    error('O1:bad_cache_directory', '缓存目录须为字符路径。');
end
if strlength(string(config.cache_directory)) == 0
    config.cache_directory = pwd;
end
if ~isfolder(config.cache_directory)
    error('O1:missing_cache_directory', '缓存目录不存在：%s', config.cache_directory);
end
if ~(ischar(config.progress_file) || ...
        (isstring(config.progress_file) && isscalar(config.progress_file)))
    error('O1:bad_progress_file', '会话记录路径须为字符路径。');
end
if ~(ischar(config.frontier_solver) || ...
        (isstring(config.frontier_solver) && isscalar(config.frontier_solver))) || ...
        ~ismember(string(config.frontier_solver), ["intlinprog", "gurobi"])
    error('O1:bad_frontier_solver', '经济后端须为intlinprog或gurobi。');
end
config.frontier_solver = char(config.frontier_solver);
if ~(ischar(config.gurobi_matlab_directory) || ...
        (isstring(config.gurobi_matlab_directory) && isscalar(config.gurobi_matlab_directory)))
    error('O1:bad_gurobi_directory', 'Gurobi MATLAB接口目录须为字符路径。');
end
validateattributes(config.gurobi_mip_focus, {'numeric'}, ...
    {'scalar', 'integer', '>=', -1, '<=', 3});
validateattributes(config.gurobi_method, {'numeric'}, ...
    {'scalar', 'integer', '>=', -1, '<=', 5});
validateattributes(config.gurobi_threads, {'numeric'}, ...
    {'scalar', 'integer', '>=', 0});
if strcmp(config.frontier_solver, 'gurobi')
    gurobi_dir = char(config.gurobi_matlab_directory);
    if isempty(gurobi_dir) && ~ismember(exist('gurobi', 'file'), [2, 3])
        gurobi_root = getenv('GUROBI_HOME');
        if isempty(gurobi_root) && ispc
            [path_status, cli_paths] = system('where gurobi_cl');
            if path_status == 0
                cli_paths = splitlines(strtrim(cli_paths));
                gurobi_root = fileparts(fileparts(char(cli_paths(1))));
            end
        end
        if ~isempty(gurobi_root)
            gurobi_dir = fullfile(gurobi_root, 'matlab');
        end
    end
    if ~isempty(gurobi_dir)
        if ~isfile(fullfile(gurobi_dir, ['gurobi.', mexext]))
            error('O1:missing_gurobi_directory', '目录中未找到Gurobi MATLAB接口：%s', gurobi_dir);
        end
        addpath(gurobi_dir);
    end
    % 官方目录同时含帮助用.m与实际MEX，首次查找可返回2，加载后可返回3。
    if ~ismember(exist('gurobi', 'file'), [2, 3])
        error('O1:missing_gurobi', '未找到Gurobi MATLAB接口，请配置gurobi_matlab_directory。');
    end
end

must_be_positive_scalar(config.nh3_target_t, 'nh3_target_t');
must_be_positive_scalar(config.max_time_s, 'max_time_s');
must_be_positive_scalar(config.frontier_max_time_s, 'frontier_max_time_s');
must_be_positive_scalar(config.frontier_certification_max_time_s, ...
    'frontier_certification_max_time_s');
must_be_positive_scalar(config.frontier_certification_tolerance_usd_t, ...
    'frontier_certification_tolerance_usd_t');
must_be_positive_scalar(config.frontier_polish_max_time_s, ...
    'frontier_polish_max_time_s');
must_be_positive_scalar(config.frontier_pattern_pool_max_time_s, ...
    'frontier_pattern_pool_max_time_s');
must_be_positive_scalar(config.frontier_global_bisection_max_time_s, ...
    'frontier_global_bisection_max_time_s');
must_be_positive_scalar(config.frontier_local_cost_max_time_s, ...
    'frontier_local_cost_max_time_s');
must_be_positive_scalar(config.frontier_relocation_cost_max_time_s, ...
    'frontier_relocation_cost_max_time_s');
must_be_positive_scalar(config.count_max_time_s, 'count_max_time_s');
must_be_positive_scalar(config.fixed_max_time_s, 'fixed_max_time_s');
must_be_positive_scalar(config.window_lp_max_time_s, 'window_lp_max_time_s');
must_be_positive_scalar(config.repair_max_time_s, 'repair_max_time_s');
if ~isscalar(config.run_budget_s) || isnan(config.run_budget_s) || ...
        config.run_budget_s <= 0
    error('O1:bad_run_budget', ...
        'run_budget_s must be a positive scalar or Inf.');
end
if ~isscalar(config.frontier_run_budget_s) || ...
        isnan(config.frontier_run_budget_s) || ...
        config.frontier_run_budget_s <= 0
    error('O1:bad_frontier_run_budget', ...
        'frontier_run_budget_s must be a positive scalar or Inf.');
end
if ~isscalar(config.frontier_certification_run_budget_s) || ...
        isnan(config.frontier_certification_run_budget_s) || ...
        config.frontier_certification_run_budget_s <= 0
    error('O1:bad_certification_run_budget', ...
        'frontier_certification_run_budget_s必须为正数或Inf。');
end
if any(~isfinite(config.cost_allowance_usd_t)) || ...
        any(config.cost_allowance_usd_t < 0)
    error('O1:bad_allowance', ...
        'cost_allowance_usd_t must contain finite nonnegative values.');
end
if any(~isfinite(config.frontier_k)) || any(config.frontier_k < 0) || ...
        any(abs(config.frontier_k - round(config.frontier_k)) > 1e-9)
    error('O1:bad_frontier', ...
        'frontier_k must contain nonnegative integers.');
end
if any(~isfinite(config.frontier_key_k)) || ...
        any(config.frontier_key_k < 0) || ...
        any(abs(config.frontier_key_k - round(config.frontier_key_k)) > 1e-9)
    error('O1:bad_frontier_key_k', ...
        'frontier_key_k必须包含非负整数。');
end
if config.cost_relative_gap < 0 || config.cost_relative_gap >= 1
    error('O1:bad_cost_gap', 'cost_relative_gap must be in [0, 1).');
end
if config.count_absolute_gap < 0 || config.count_absolute_gap >= 1
    error('O1:bad_count_gap', 'count_absolute_gap must be in [0, 1).');
end
if config.change_epsilon < 0 || ~isfinite(config.change_epsilon)
    error('O1:bad_change_epsilon', ...
        'change_epsilon must be finite and nonnegative.');
end
if config.change_tolerance < 0 || ~isfinite(config.change_tolerance)
    error('O1:bad_change_tolerance', ...
        'change_tolerance must be finite and nonnegative.');
end
if config.max_count_bound_width < 0 || isnan(config.max_count_bound_width)
    error('O1:bad_count_bound_width', ...
        'max_count_bound_width must be nonnegative.');
end
if any(~isfinite(config.feasibility_probe_k)) || ...
        any(config.feasibility_probe_k < 0) || ...
        any(abs(config.feasibility_probe_k - ...
        round(config.feasibility_probe_k)) > 1e-9)
    error('O1:bad_feasibility_probe', ...
        'feasibility_probe_k must contain nonnegative integers.');
end
integer_fields = {'max_k_search_points', 'window_candidates_per_length', ...
    'max_window_cuts', 'frontier_max_attempts', ...
    'frontier_solution_interval', 'frontier_points_per_run', ...
    'frontier_anchor_count', 'frontier_auto_key_count', ...
    'frontier_certification_max_attempts', ...
    'frontier_certification_points_per_run', ...
    'frontier_polish_max_attempts', ...
    'frontier_global_bisection_max_attempts', ...
    'frontier_local_cost_window_h', 'frontier_local_cost_max_windows', ...
    'max_k_attempts_per_source'};
for i = 1:numel(integer_fields)
    value = config.(integer_fields{i});
    if ~isscalar(value) || ~isfinite(value) || value < 0 || ...
            abs(value - round(value)) > 1e-9
        error('O1:bad_integer_option', '%s must be a nonnegative integer.', ...
            integer_fields{i});
    end
end
if config.frontier_max_attempts < 1
    error('O1:bad_frontier_attempts', ...
        'frontier_max_attempts must be positive.');
end
if config.frontier_solution_interval < 1
    error('O1:bad_frontier_solution_interval', ...
        'frontier_solution_interval must be positive.');
end
if config.frontier_points_per_run < 1
    error('O1:bad_frontier_points_per_run', ...
        'frontier_points_per_run must be positive.');
end
if config.frontier_anchor_count < 2
    error('O1:bad_frontier_anchor_count', ...
        'frontier_anchor_count必须至少为2。');
end
if config.frontier_certification_max_attempts < 1
    error('O1:bad_frontier_certification_attempts', ...
        'frontier_certification_max_attempts必须为正整数。');
end
if config.frontier_certification_points_per_run < 1
    error('O1:bad_frontier_certification_points', ...
        'frontier_certification_points_per_run必须为正整数。');
end
if config.frontier_polish_max_attempts < 1
    error('O1:bad_frontier_polish_attempts', ...
        'frontier_polish_max_attempts必须为正整数。');
end
if config.frontier_global_bisection_max_attempts < 1
    error('O1:bad_global_bisection_attempts', ...
        'frontier_global_bisection_max_attempts必须为正整数。');
end
if config.frontier_local_cost_window_h < 2 || ...
        config.frontier_local_cost_max_windows < 1
    error('O1:bad_local_cost_options', ...
        '局部成本窗口须至少2小时，窗口尝试上限须为正整数。');
end
if any(~isfinite(config.frontier_pattern_pool_radii_h)) || ...
        any(config.frontier_pattern_pool_radii_h < 0) || ...
        any(abs(config.frontier_pattern_pool_radii_h - ...
        round(config.frontier_pattern_pool_radii_h)) > 1e-9)
    error('O1:bad_pattern_pool_radii', ...
        'frontier_pattern_pool_radii_h必须包含非负整数。');
end
if any(~isfinite(config.frontier_relocation_cost_radii)) || ...
        any(config.frontier_relocation_cost_radii < 0) || ...
        any(config.frontier_relocation_cost_radii ~= ...
        round(config.frontier_relocation_cost_radii))
    error('O1:bad_cost_relocation_radii', '远距离成本搜索半径须为非负整数。');
end
if config.max_k_attempts_per_source < 1
    error('O1:bad_k_attempts', ...
        'max_k_attempts_per_source must be positive.');
end
if any(~isfinite(config.window_lengths_h)) || ...
        any(config.window_lengths_h <= 0)
    error('O1:bad_window_lengths', ...
        'window_lengths_h must contain positive finite values.');
end
logical_fields = {'enable_window_cuts', 'enable_start_repair', 'use_cache', ...
    'frontier_all_k', 'autonomous_search', ...
    'compute_frontier_during_search', 'frontier_polish_enabled', ...
    'frontier_polish_only', 'frontier_pattern_pool_enabled', ...
    'frontier_global_bisection_enabled', 'frontier_local_cost_enabled', ...
    'frontier_relocation_cost_enabled', 'frontier_scale_solver'};
for i = 1:numel(logical_fields)
    value = config.(logical_fields{i});
    if ~(islogical(value) && isscalar(value)) && ...
            ~(isnumeric(value) && isscalar(value) && ismember(value, [0, 1]))
        error('O1:bad_logical_option', '%s must be logical.', ...
            logical_fields{i});
    end
    config.(logical_fields{i}) = logical(value);
end
if ~(ischar(config.display) || ...
        (isstring(config.display) && isscalar(config.display)))
    error('O1:bad_display', 'display must be text.');
end
config.cost_allowance_usd_t = sort(unique(config.cost_allowance_usd_t(:)));
config.frontier_k = unique(round(config.frontier_k(:)), 'stable');
config.frontier_key_k = unique(round(config.frontier_key_k(:)), 'stable');
config.frontier_pattern_pool_radii_h = unique(round( ...
    config.frontier_pattern_pool_radii_h(:).'), 'stable');
config.feasibility_probe_k = unique( ...
    round(config.feasibility_probe_k(:)).', 'stable');
config.window_lengths_h = unique(config.window_lengths_h(:).', 'stable');

    function must_be_positive_scalar(value, name)
        if ~isscalar(value) || ~isfinite(value) || value <= 0
            error('O1:bad_positive_option', ...
                '%s must be a positive finite scalar.', name);
        end
    end
end

function ctx = build_context(model, config)
required = {'problem', 'variables', 'expressions', 'options', 'params', ...
    'renewable_data', 'context', 'start_power_per_module_kw'};
for i = 1:numel(required)
    if ~isfield(model, required{i})
        error('O1:bad_model', 'Missing model field: %s.', required{i});
    end
end
if ~isfield(model.variables, 'HB_load') || ...
        ~isfield(model.expressions, 'nh3_total_t') || ...
        ~isfield(model.expressions, 'system_cost_usd')
    error('O1:bad_model', ...
        'The model must expose HB_load, nh3_total_t and system_cost_usd.');
end

params = model.params;
T = model.renewable_data.time_count;
dt = params.time.step;
HB_load = model.variables.HB_load;
NH3_total_t = model.expressions.nh3_total_t;
system_cost_usd = model.expressions.system_cost_usd;
if isfield(model.expressions, 'cost_components')
    cost_components = model.expressions.cost_components;
else
    cost_components = struct();
end
minimum_output_t = params.HB.min_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
maximum_output_t = params.HB.max_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
target_tolerance = max(1e-6, 1e-9 * config.nh3_target_t);
if config.nh3_target_t < minimum_output_t - target_tolerance || ...
        config.nh3_target_t > maximum_output_t + target_tolerance
    error('O1:target_out_of_range', ...
        'NH3 target %.6g t is outside [%.6g, %.6g] t.', ...
        config.nh3_target_t, minimum_output_t, maximum_output_t);
end

HB_ramp = params.HB.ramp_rate * dt;
if config.change_epsilon >= HB_ramp
    error('O1:bad_change_epsilon', ...
        'change_epsilon must be smaller than the HB ramp limit %.6g.', ...
        HB_ramp);
end

base_problem = model.problem;
base_problem.Constraints.O1_nh3_target = NH3_total_t == config.nh3_target_t;
base_problem.Constraints.O1_cyclic_ramp_up = ...
    HB_load(1) - HB_load(end) <= HB_ramp;
base_problem.Constraints.O1_cyclic_ramp_down = ...
    HB_load(end) - HB_load(1) <= HB_ramp;

z = optimvar('O1_HB_change', T, 'Type', 'integer', ...
    'LowerBound', 0, 'UpperBound', 1);
setpoint = optimvar('O1_HB_setpoint', T, ...
    'LowerBound', params.HB.min_load, 'UpperBound', params.HB.max_load);
setpoint_change = [setpoint(2:end); setpoint(1)] - setpoint;
problem = base_problem;
problem.Constraints.O1_tracking_up = ...
    HB_load - setpoint <= config.change_epsilon / 2;
problem.Constraints.O1_tracking_down = ...
    setpoint - HB_load <= config.change_epsilon / 2;
problem.Constraints.O1_change_up = ...
    setpoint_change <= (HB_ramp + config.change_epsilon) * z;
problem.Constraints.O1_change_down = ...
    -setpoint_change <= (HB_ramp + config.change_epsilon) * z;

cost_options = optimoptions(model.options, ...
    'RelativeGapTolerance', config.cost_relative_gap, ...
    'MaxTime', config.max_time_s, 'Display', config.display);
frontier_options = optimoptions(model.options, ...
    'RelativeGapTolerance', config.cost_relative_gap, ...
    'MaxTime', config.frontier_max_time_s, 'Display', 'off');
certification_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, ...
    'AbsoluteGapTolerance', ...
    config.frontier_certification_tolerance_usd_t * config.nh3_target_t, ...
    'MaxTime', config.frontier_certification_max_time_s, ...
    'Display', 'off');
polish_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxFeasiblePoints', 1, ...
    'MaxTime', config.frontier_polish_max_time_s, 'Display', 'off');
pattern_pool_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxFeasiblePoints', 1, ...
    'MaxTime', config.frontier_pattern_pool_max_time_s, 'Display', 'off');
global_bisection_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxFeasiblePoints', 1, ...
    'MaxTime', config.frontier_global_bisection_max_time_s, ...
    'Display', 'off');
count_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, ...
    'AbsoluteGapTolerance', config.count_absolute_gap, ...
    'MaxTime', config.count_max_time_s, 'Display', config.display);
feasibility_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxFeasiblePoints', 1, 'MaxTime', config.fixed_max_time_s, ...
    'Display', config.display);
repair_options = optimoptions(feasibility_options, ...
    'MaxTime', config.repair_max_time_s);

signature = struct();
signature.schema_version = 4;
signature.nh3_target_t = config.nh3_target_t;
signature.change_epsilon = config.change_epsilon;
signature.time_count = T;
signature.time_step_h = model.renewable_data.time_step_h;
signature.pv_power_kw = model.renewable_data.pv_power_kw(:);
signature.pw_power_kw = model.renewable_data.pw_power_kw(:);
signature.model_parameters = params;
if isfield(signature.model_parameters, 'solver')
    signature.model_parameters = rmfield(signature.model_parameters, 'solver');
end
cost_signature = signature;
cost_signature.objective_definition = ...
    "system_cost_without_ammonia_revenue_v1";
objective_shift_usd = params.ammonia.price * config.nh3_target_t;

[~, run_id] = fileparts(tempname);
ctx = struct('model', model, 'config', config, 'params', params, ...
    'run_id', run_id, ...
    'T', T, 'dt', dt, 'HB_ramp', HB_ramp, 'HB_load', HB_load, ...
    'z', z, 'setpoint', setpoint, 'update_count', sum(z), ...
    'system_cost_usd', system_cost_usd, ...
    'objective_shift_usd', objective_shift_usd, ...
    'cost_components', cost_components, 'base_problem', base_problem, ...
    'problem', problem, 'cost_options', cost_options, ...
    'frontier_options', frontier_options, ...
    'certification_options', certification_options, ...
    'polish_options', polish_options, ...
    'pattern_pool_options', pattern_pool_options, ...
    'global_bisection_options', global_bisection_options, ...
    'count_options', count_options, ...
    'feasibility_options', feasibility_options, ...
    'repair_options', repair_options, 'signature', signature, ...
    'cost_signature', cost_signature, ...
    'output_range_t', [minimum_output_t, maximum_output_t], ...
    'stage1_cache_file', fullfile(config.cache_directory, 'O1_stage1_cache.mat'), ...
    'point_cache_file', fullfile(config.cache_directory, 'O1_fixed_k_cache.mat'));
end

function [problem, info] = add_window_cover_cuts(ctx)
problem = ctx.problem;
info = struct('enabled', ctx.config.enable_window_cuts, ...
    'candidate_count', 0, 'cut_count', 0, ...
    'start_hour', zeros(0, 1), 'end_hour', zeros(0, 1), ...
    'minimum_updates', zeros(0, 1));
if ~ctx.config.enable_window_cuts || ctx.config.max_window_cuts == 0
    return
end

maximum_candidates = numel(ctx.config.window_lengths_h) ...
    * ctx.config.window_candidates_per_length;
candidate_windows = zeros(maximum_candidates, 2);
candidate_count = 0;
power = ctx.model.renewable_data.renewable_power_kw(:);
energy_prefix = [0; cumsum(power)];
for hours_value = ctx.config.window_lengths_h
    length_steps = max(2, round(hours_value / ctx.dt));
    if length_steps >= ctx.T
        continue
    end
    stride = max(1, floor(length_steps / 2));
    starts = unique([1:stride:(ctx.T - length_steps + 1), ...
        ctx.T - length_steps + 1]);
    ends = starts + length_steps - 1;
    totals = energy_prefix(ends + 1) - energy_prefix(starts);
    [~, low_order] = sort(totals, 'ascend');
    [~, high_order] = sort(totals, 'descend');
    take_low = ceil(ctx.config.window_candidates_per_length / 2);
    take_high = floor(ctx.config.window_candidates_per_length / 2);
    chosen = [low_order(1:min(take_low, numel(low_order))), ...
        high_order(1:min(take_high, numel(high_order)))];
    chosen = chosen(:);
    chosen_starts = starts(chosen);
    chosen_ends = ends(chosen);
    new_windows = [chosen_starts(:), chosen_ends(:)];
    window_rows = candidate_count + (1:size(new_windows, 1));
    candidate_windows(window_rows, :) = new_windows;
    candidate_count = candidate_count + size(new_windows, 1);
end
candidate_windows = candidate_windows(1:candidate_count, :);
candidate_windows = unique(candidate_windows, 'rows', 'stable');
info.candidate_count = size(candidate_windows, 1);
if isempty(candidate_windows)
    return
end

probe = problem;
probe.Objective = 0;
window_initial = struct();
if isfile(ctx.point_cache_file)
    try
        cached_points = fixed_point_store(ctx.point_cache_file, ...
            ctx.signature, "load", "feasibility", Inf, struct());
        feasible_mask = arrayfun(@(entry) ...
            entry.record.has_incumbent && ...
            isfield(entry.record, 'solution') && ...
            isfield(entry.record.solution, 'O1_HB_change'), cached_points);
        feasible_points = cached_points(feasible_mask);
        if ~isempty(feasible_points)
            [~, best_seed] = min(arrayfun(@(entry) ...
                entry.record.count_upper, feasible_points));
            window_initial = feasible_points(best_seed).record.solution;
        end
    catch
        window_initial = struct();
    end
end
if isempty(fieldnames(window_initial))
    solver_problem = prob2struct(probe, 'Solver', 'intlinprog');
else
    solver_problem = prob2struct( ...
        probe, window_initial, 'Solver', 'intlinprog');
end
indices = varindex(probe);
z_indices = indices.O1_HB_change(:);
lp_options = optimoptions('linprog', 'Display', 'none', ...
    'MaxTime', ctx.config.window_lp_max_time_s);
for i = 1:size(candidate_windows, 1)
    transitions = candidate_windows(i, 1):(candidate_windows(i, 2) - 1);
    objective = zeros(numel(solver_problem.lb), 1);
    objective(z_indices(transitions)) = 1;
    try
        [~, lower_bound, exitflag] = linprog(objective, ...
            solver_problem.Aineq, solver_problem.bineq, ...
            solver_problem.Aeq, solver_problem.beq, ...
            solver_problem.lb, solver_problem.ub, lp_options);
    catch
        continue
    end
    if exitflag <= 0 || ~isfinite(lower_bound)
        continue
    end
    required_updates = ceil(lower_bound - 1e-6);
    if required_updates < 1
        if mod(i, 10) == 0 || i == size(candidate_windows, 1)
            fprintf('[O1] Window-cut LP: %d/%d candidates, %d cuts.\n', ...
                i, size(candidate_windows, 1), info.cut_count);
        end
        continue
    end
    cut_id = info.cut_count + 1;
    name = sprintf('O1_window_cover_%03d', cut_id);
    problem.Constraints.(name) = ...
        sum(ctx.z(transitions)) >= required_updates;
    info.cut_count = cut_id;
    info.start_hour(cut_id, 1) = candidate_windows(i, 1);
    info.end_hour(cut_id, 1) = candidate_windows(i, 2);
    info.minimum_updates(cut_id, 1) = required_updates;
    if mod(i, 10) == 0 || i == size(candidate_windows, 1)
        fprintf('[O1] Window-cut LP: %d/%d candidates, %d cuts.\n', ...
            i, size(candidate_windows, 1), info.cut_count);
    end
    if info.cut_count >= ctx.config.max_window_cuts
        break
    end
end
fprintf('[O1] Window cuts: %d certified cuts from %d candidates.\n', ...
    info.cut_count, info.candidate_count);
end

function reference = load_or_solve_reference(ctx)
reference = struct();
if ctx.config.use_cache && isfile(ctx.stage1_cache_file)
    try
        loaded = load(ctx.stage1_cache_file);
        has_payload = isfield(loaded, 'reference') && ...
            isfield(loaded, 'cache_signature');
        valid = has_payload && ...
            isequaln(loaded.cache_signature, ctx.cost_signature);
        migrated = false;
        if has_payload && ~valid && ...
                isequaln(loaded.cache_signature, ctx.signature)
            loaded.reference = migrate_cost_record(loaded.reference, ctx);
            valid = true;
            migrated = true;
        end
        if valid
            candidate = loaded.reference;
            valid = isstruct(candidate) && candidate.has_incumbent && ...
                isfield(candidate, 'solution') && ...
                isfield(candidate.solution, 'HB_load') && ...
                numel(candidate.solution.HB_load) == ctx.T && ...
                (candidate.is_proven || ...
                (isfinite(candidate.relative_gap) && ...
                candidate.relative_gap <= ctx.config.cost_relative_gap + 1e-12));
        end
        if valid
            reference = candidate;
            if migrated
                cache_payload = struct('reference', reference, ...
                    'cache_signature', ctx.cost_signature);
                save(ctx.stage1_cache_file, '-struct', ...
                    'cache_payload', '-v7.3');
                fprintf('[O1] Stage 1旧目标缓存已换算为当前成本口径。\n');
            else
                fprintf('[O1] Stage 1 loaded from cache: %s\n', ...
                    ctx.stage1_cache_file);
            end
        else
            fprintf('[O1] Stage 1 cache ignored: model instance changed.\n');
        end
    catch exception
        fprintf('[O1] Stage 1 cache ignored: %s\n', exception.message);
    end
end
if ~isempty(fieldnames(reference))
    return
end

reference_problem = ctx.base_problem;
reference_problem.Objective = ctx.system_cost_usd;
reference = solve_problem(reference_problem, ctx.cost_options, ...
    "cost", struct(), ctx.system_cost_usd);
if reference.has_incumbent && ctx.config.use_cache
    cache_payload = struct('reference', reference, ...
        'cache_signature', ctx.cost_signature);
    save(ctx.stage1_cache_file, '-struct', 'cache_payload', '-v7.3');
    fprintf('[O1] Stage 1 result cached to: %s\n', ctx.stage1_cache_file);
end
end

function record = migrate_cost_record(record, ctx)
%MIGRATE_COST_RECORD 将旧的“成本减氨收入”记录换算为当前成本口径。
if ~isstruct(record) || isempty(fieldnames(record))
    return
end
shift_fields = {'objective_lower', 'objective_upper', ...
    'system_cost_lower', 'system_cost_upper'};
for field_index = 1:numel(shift_fields)
    name = shift_fields{field_index};
    if isfield(record, name) && isscalar(record.(name)) && ...
            isfinite(record.(name))
        record.(name) = record.(name) + ctx.objective_shift_usd;
    end
end
if isfield(record, 'solution') && isstruct(record.solution) && ...
        ~isempty(fieldnames(record.solution))
    try
        current_cost = evaluate(ctx.system_cost_usd, record.solution);
        if isfinite(current_cost)
            record.objective_upper = current_cost;
            record.system_cost_upper = current_cost;
        end
        record.cost_components = evaluate_cost_components( ...
            record.solution, ctx);
        record.operation_metrics = evaluate_operation_metrics( ...
            record.solution, ctx);
    catch
    end
end
if isfield(record, 'objective_lower') && ...
        isfield(record, 'objective_upper') && ...
        isfinite(record.objective_lower) && isfinite(record.objective_upper)
    record.absolute_gap = max(0, ...
        record.objective_upper - record.objective_lower);
    record.relative_gap = record.absolute_gap / ...
        max(1, abs(record.objective_upper));
end
record.objective_definition = ...
    "system_cost_without_ammonia_revenue_v1";
record.migrated_from_ammonia_revenue_objective = true;
end

function entries = persist_point_with_progress(ctx, file, signature, action, mode, cost_cap, entry)
%PERSIST_POINT_WITH_PROGRESS 先保存有效检查点，再追加少量中文可追溯记录。
entries = fixed_point_store(file, signature, action, mode, cost_cap, entry);
if action ~= "append" || mode ~= "frontier_cost" || ...
        strlength(string(ctx.config.progress_file)) == 0
    return
end
r = entry.record;
try
    % MATLAB结构字段只能用合法标识符；序列化后映射为中文JSON键。
    event = struct('event', '经济阶段检查点', ...
        'time', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'run', ctx.run_id, 'hours', ctx.T, ...
        'target', ctx.config.nh3_target_t, 'K', entry.K, ...
        'lower', r.objective_lower, 'upper', r.objective_upper, ...
        'uncertainty', (r.objective_upper - r.objective_lower) / ...
        ctx.config.nh3_target_t, 'certified', false, ...
        'year', year(ctx.model.renewable_data.time(1)), ...
        'stage', '其他经济阶段', 'elapsed', r.elapsed_s);
    event.backend = char(r.solve_backend);
    if isfield(r, 'gurobi_mip_focus') && isfinite(r.gurobi_mip_focus)
        event.gurobi_focus = r.gurobi_mip_focus;
        event.gurobi_attempt = r.gurobi_certification_attempts;
    end
    if isfield(r, 'is_certified')
        event.certified = logical(r.is_certified);
    end
    phase_names = ["anchor", "certification", "certification_seed", "polish", ...
        "pattern_pool", "pool_optimization", "local_cost", "global_bisection", "relocation_cost"];
    phase_labels = ["锚点求解", "原模型认证", "认证种子", "固定模式精修", ...
        "候选池成本帽", "候选池成本优化", "局部窗口上界搜索", "全局多策略认证", "远距离更新时刻成本搜索"];
    if isfield(r, 'frontier_phase')
        phase_index = find(phase_names == string(r.frontier_phase), 1);
        if ~isempty(phase_index)
            event.stage = char(phase_labels(phase_index));
        end
    end
    line = jsonencode(event);
    keys = {'event', '事件'; 'time', '时间'; 'run', '运行编号'; ...
        'hours', '时段数'; 'target', '产氨目标吨'; 'K', 'K上限'; ...
        'lower', '有效成本下界美元'; 'upper', '已验证成本上界美元'; ...
        'uncertainty', '不确定性美元每吨'; 'certified', '认证达标'; ...
        'year', '年份'; 'stage', '阶段'; 'elapsed', '阶段耗时秒'; ...
        'backend', '求解后端'; 'gurobi_focus', 'Gurobi策略编号'; ...
        'gurobi_attempt', 'Gurobi认证次数'};
    for i = 1:size(keys, 1)
        line = strrep(line, ['"', keys{i, 1}, '":'], ['"', keys{i, 2}, '":']);
    end
    [fid, message] = fopen(ctx.config.progress_file, 'a', 'n', 'UTF-8');
    if fid < 0
        error('O1:progress_open_failed', '%s', message);
    end
    close_file = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '\n- 自动检查点：%s\n', line);
catch exception
    warning('O1:progress_write_failed', ...
        'MAT缓存已保存，但中文会话记录追加失败：%s', exception.message);
end
end

function entries = fixed_point_store(file, signature, action, mode, cost_cap, entry)
% 同一轮频繁读取大缓存时复用内存；文件被外部更新或删除后必须重载。
persistent memory_file memory_stamp memory_sets
cache_sets = struct('signature', {}, 'entries', {});
file_info = dir(file);
if isempty(file_info)
    stamp = [];
else
    stamp = [file_info.datenum, file_info.bytes];
end
if isequal(memory_file, file) && isequal(memory_stamp, stamp) && ...
        ~isempty(memory_sets)
    cache_sets = memory_sets;
elseif ~isempty(file_info)
    try
        loaded = load(file, 'cache_sets');
        if isfield(loaded, 'cache_sets')
            cache_sets = loaded.cache_sets;
        end
    catch exception
        % 不把读取失败当作空缓存，否则下一次追加会覆盖既有证据。
        error('O1:cache_read_failed', '读取缓存失败，保留原文件：%s', ...
            exception.message);
    end
end
memory_file = file;
memory_stamp = stamp;
memory_sets = cache_sets;
set_index = [];
for i = 1:numel(cache_sets)
    if isequaln(cache_sets(i).signature, signature)
        set_index = i;
        break
    end
end
if isempty(set_index)
    entries = struct('mode', {}, 'cost_cap', {}, 'K', {}, ...
        'record', {}, 'source', {});
else
    entries = cache_sets(set_index).entries;
end

if action == "load"
    keep = false(size(entries));
    for i = 1:numel(entries)
        same_cap = same_cost_cap(entries(i).cost_cap, cost_cap);
        keep(i) = string(entries(i).mode) == string(mode) && same_cap;
    end
    entries = entries(keep);
    return
end

if isempty(set_index)
    set_index = numel(cache_sets) + 1;
    cache_sets(set_index).signature = signature;
    cache_sets(set_index).entries = entries;
end
all_entries = cache_sets(set_index).entries;
match = [];
for i = 1:numel(all_entries)
    same_cap = same_cost_cap(all_entries(i).cost_cap, entry.cost_cap);
    if string(all_entries(i).mode) == string(entry.mode) && ...
            all_entries(i).K == entry.K && same_cap
        match = i;
        break
    end
end
if isempty(match)
    all_entries(end + 1) = entry;
else
    all_entries(match) = entry;
end
cache_sets(set_index).entries = all_entries;
temporary_file = [file, '.tmp.mat'];
save(temporary_file, 'cache_sets', '-v7.3');
movefile(temporary_file, file, 'f');
file_info = dir(file);
memory_stamp = [file_info.datenum, file_info.bytes];
memory_sets = cache_sets;
entries = all_entries;

    function tf = same_cost_cap(left, right)
        tf = (isinf(left) && isinf(right) && sign(left) == sign(right)) || ...
            (isfinite(left) && isfinite(right) && ...
            abs(left - right) <= 1e-9 * max([1, abs(left), abs(right)]));
    end
end

function record = solve_problem(problem, options, objective_kind, ...
        initial_solution, cost_expression)
record = struct('objective_kind', string(objective_kind), ...
    'has_incumbent', false, 'objective_lower', NaN, ...
    'objective_upper', NaN, 'system_cost_lower', NaN, ...
    'system_cost_upper', NaN, 'absolute_gap', NaN, ...
    'relative_gap', NaN, 'count_lower', NaN, 'count_upper', NaN, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "not_run", 'message', "", 'output', struct(), ...
    'solution', struct(), 'solve_backend', "problem_based", ...
    'K_limit', NaN, 'elapsed_s', NaN);
started = tic;
try
    if isstruct(initial_solution) && ~isempty(fieldnames(initial_solution))
        [solution, fval, exitflag, output] = solve(problem, initial_solution, ...
            'Solver', 'intlinprog', 'Options', options);
    else
        [solution, fval, exitflag, output] = solve(problem, ...
            'Solver', 'intlinprog', 'Options', options);
    end
catch exception
    record.elapsed_s = toc(started);
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.elapsed_s = toc(started);

record.exitflag = exitflag;
record.output = output;
record.is_infeasible = exitflag == -2;
if isfield(output, 'message')
    record.message = string(output.message);
end
record.has_incumbent = isstruct(solution) && ...
    isfield(solution, 'HB_load') && ~isempty(solution.HB_load) && ...
    isscalar(fval) && isfinite(fval);
if isfield(output, 'bestbound') && isscalar(output.bestbound) && ...
        isfinite(output.bestbound) && objective_kind == "count"
    record.objective_lower = output.bestbound;
end
if ~record.has_incumbent
    if objective_kind == "count" && isfinite(record.objective_lower)
        record.count_lower = max(0, ceil(record.objective_lower - 1e-7));
    end
    if record.is_infeasible
        record.status = "infeasible";
    else
        record.status = "unknown";
    end
    return
end

record.solution = solution;
record.objective_upper = fval;
if isfield(output, 'absolutegap') && isscalar(output.absolutegap) && ...
        isfinite(output.absolutegap)
    record.absolute_gap = max(0, output.absolutegap);
    record.objective_lower = fval - record.absolute_gap;
elseif exitflag > 0
    record.absolute_gap = 0;
    record.objective_lower = fval;
end
if isfield(output, 'relativegap') && isscalar(output.relativegap) && ...
        isfinite(output.relativegap)
    record.relative_gap = max(0, output.relativegap);
elseif isfinite(record.absolute_gap)
    record.relative_gap = record.absolute_gap / max(1, abs(fval));
end
try
    record.system_cost_upper = evaluate(cost_expression, solution);
catch
    record.system_cost_upper = NaN;
end

if objective_kind == "count"
    record.count_upper = round(sum(solution.O1_HB_change));
    record.count_lower = max(0, ceil(record.objective_lower - 1e-7));
    record.is_proven = record.count_lower == record.count_upper;
elseif objective_kind == "cost"
    record.system_cost_lower = record.objective_lower;
    record.is_proven = exitflag > 0 && record.absolute_gap <= ...
        max(1e-7, eps(abs(fval)));
else
    record.count_upper = round(sum(solution.O1_HB_change));
    record.is_proven = true;
end
if record.is_proven
    record.status = "proven";
else
    record.status = "incumbent_with_bound";
end
end

function [solver_data, elapsed_s] = build_fixed_solver(problem, ctx, initial)
%BUILD_FIXED_SOLVER 构建可复用的固定K矩阵模型。
started = tic;
solver_problem = prob2struct(problem, initial, 'Solver', 'intlinprog');
solver_problem.options = ctx.feasibility_options;
indices = varindex(problem);
z_indices = indices.O1_HB_change(:);
A = solver_problem.Aineq;
row_nnz = full(sum(spones(A), 2));
z_nnz = full(sum(spones(A(:, z_indices)), 2));
candidates = find(row_nnz == numel(z_indices) & ...
    z_nnz == numel(z_indices));
update_row = NaN;
update_coefficient = NaN;
for i = 1:numel(candidates)
    values = full(A(candidates(i), z_indices));
    coefficient = values(1);
    if coefficient > 0 && max(abs(values - coefficient)) <= 1e-12 && ...
            abs(solver_problem.bineq(candidates(i)) / coefficient ...
            - ctx.T) <= 1e-8
        update_row = candidates(i);
        update_coefficient = coefficient;
        break
    end
end
if ~isfinite(update_row)
    error('O1:update_row_not_found', ...
        'Cannot locate the fixed-K constraint in the solver matrix.');
end
% 原约束推导的冗余凸包割：z=0时相邻实际负荷差不超过epsilon，
% z=1时不超过物理爬坡R，因此|负荷差|<=epsilon+(R-epsilon)*z。
% 它不排除任何原整数可行解，只加强分支定界中的分数z松弛。
hours = (1:ctx.T).';
next_hours = [hours(2:end); hours(1)];
load_indices = indices.HB_load(:);
load_difference = sparse([hours; hours], ...
    [load_indices(next_hours); load_indices], ...
    [ones(ctx.T, 1); -ones(ctx.T, 1)], ctx.T, numel(solver_problem.lb));
change_part = sparse(hours, z_indices, ...
    (ctx.HB_ramp - ctx.config.change_epsilon) * ones(ctx.T, 1), ...
    ctx.T, numel(solver_problem.lb));
solver_problem.Aineq = [solver_problem.Aineq; ...
    load_difference - change_part; -load_difference - change_part];
solver_problem.bineq = [solver_problem.bineq; ...
    ctx.config.change_epsilon * ones(2 * ctx.T, 1)];
solver_data = struct('problem', solver_problem, 'indices', indices, ...
    'update_row', update_row, 'update_coefficient', update_coefficient, ...
    'hb_ramp_hull_cut_count', 2 * ctx.T);
elapsed_s = toc(started);
end

function [x, exitflag, output] = recover_direction_binaries( ...
        problem, relaxed_x, indices, max_time_s)
%RECOVER_DIRECTION_BINARIES 固定离散方向变量后恢复LP可行点。
lower = problem.lb;
upper = problem.ub;
fixed = problem.intcon(:);
fixed_values = round(relaxed_x(fixed));

if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    n_ael = round(relaxed_x(indices.n_ael(:)));
    direction = double([n_ael(1); diff(n_ael)] > 0);
    fixed = [fixed; indices.I_AEL_up(:)]; %#ok<AGROW>
    fixed_values = [fixed_values; direction]; %#ok<AGROW>
end
if isfield(indices, 'u_purchase') && isfield(indices, 'p_purchase') && ...
        isfield(indices, 'p_sell')
    net_purchase = relaxed_x(indices.p_purchase(:)) ...
        - relaxed_x(indices.p_sell(:));
    grid_direction = double(net_purchase > 1e-8);
    fixed = [fixed; indices.u_purchase(:)]; %#ok<AGROW>
    fixed_values = [fixed_values; grid_direction]; %#ok<AGROW>
end

[fixed, unique_rows] = unique(fixed, 'stable');
fixed_values = fixed_values(unique_rows);
lower(fixed) = fixed_values;
upper(fixed) = fixed_values;
options = optimoptions('linprog', 'Algorithm', 'interior-point', ...
    'ConstraintTolerance', 1e-5, 'Display', 'none', ...
    'MaxTime', max_time_s);
[x, ~, exitflag, output] = linprog(problem.f, problem.Aineq, ...
    problem.bineq, problem.Aeq, problem.beq, lower, upper, options);
end

function components = evaluate_cost_components(solution, ctx)
components = struct();
if ~isfield(ctx, 'cost_components') || ...
        isempty(fieldnames(ctx.cost_components)) || ...
        ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
names = fieldnames(ctx.cost_components);
for name_index = 1:numel(names)
    name = names{name_index};
    expression = ctx.cost_components.(name);
    if isnumeric(expression) && isscalar(expression)
        value = expression;
    else
        try
            value = evaluate(expression, solution);
        catch
            value = NaN;
        end
    end
    if isscalar(value)
        components.(name) = double(value);
    else
        components.(name) = NaN;
    end
end
end

function metrics = evaluate_operation_metrics(solution, ctx)
metrics = struct('curtailment_mwh', NaN, 'purchase_mwh', NaN, ...
    'sales_mwh', NaN, 'ael_start_energy_mwh', NaN, ...
    'ael_started_modules', NaN, 'storage_swing_kg', NaN, ...
    'storage_throughput_kg', NaN);
if ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
if isfield(solution, 'p_curt')
    metrics.curtailment_mwh = sum(solution.p_curt(:)) * ctx.dt / 1000;
end
if isfield(solution, 'p_purchase')
    metrics.purchase_mwh = sum(solution.p_purchase(:)) * ctx.dt / 1000;
end
if isfield(solution, 'p_sell')
    metrics.sales_mwh = sum(solution.p_sell(:)) * ctx.dt / 1000;
end
if isfield(solution, 'SU_AEL')
    started_modules = sum(solution.SU_AEL(:));
    metrics.ael_started_modules = started_modules;
    metrics.ael_start_energy_mwh = started_modules * ...
        ctx.model.start_power_per_module_kw * ctx.dt / 1000;
end
if isfield(solution, 'storage_H2')
    storage = solution.storage_H2(:);
    metrics.storage_swing_kg = max(storage) - min(storage);
    metrics.storage_throughput_kg = sum(abs(diff(storage))) / 2;
end
end

function start = add_change_indicators(solution, ctx)
start = solution;
HB_load = solution.HB_load(:);
if isfield(solution, 'O1_HB_setpoint') && ...
        numel(solution.O1_HB_setpoint) == ctx.T
    setpoint = solution.O1_HB_setpoint(:);
    tolerance = max([1e-9, ctx.config.change_tolerance, ...
        ctx.model.options.ConstraintTolerance]);
    tracking_ok = max(abs(HB_load - setpoint)) <= ...
        ctx.config.change_epsilon / 2 + tolerance;
    bounds_ok = min(setpoint) >= ctx.params.HB.min_load - tolerance && ...
        max(setpoint) <= ctx.params.HB.max_load + tolerance;
    if tracking_ok && bounds_ok
        change = [setpoint(2:end); setpoint(1)] - setpoint;
        if isfield(solution, 'O1_HB_change') && ...
                numel(solution.O1_HB_change) == ctx.T
            solver_z = solution.O1_HB_change(:);
            rounded_z = round(solver_z);
            integer_ok = max(abs(solver_z - rounded_z)) <= tolerance;
            link_violation = max(abs(change) - ...
                (ctx.HB_ramp + ctx.config.change_epsilon) * rounded_z);
            if integer_ok && link_violation <= tolerance
                start.O1_HB_setpoint = setpoint;
                start.O1_HB_change = double(abs(change) > tolerance);
                return
            end
        else
            start.O1_HB_setpoint = setpoint;
            start.O1_HB_change = double(abs(change) > tolerance);
            return
        end
    end
end
lower = max(ctx.params.HB.min_load, ...
    HB_load - ctx.config.change_epsilon / 2);
upper = min(ctx.params.HB.max_load, ...
    HB_load + ctx.config.change_epsilon / 2);
[setpoint, starts] = merge_once(lower, upper, 1);
candidate_starts = unique([1; starts(:)], 'stable');
if ctx.config.change_epsilon == 0
    candidate_starts = 1;
end
change = [setpoint(2:end); setpoint(1)] - setpoint;
best_count = sum(abs(change) > 1e-12);
best_variation = sum(abs(change));
for i = 2:numel(candidate_starts)
    candidate = merge_once(lower, upper, candidate_starts(i));
    candidate_change = [candidate(2:end); candidate(1)] - candidate;
    candidate_count = sum(abs(candidate_change) > 1e-12);
    candidate_variation = sum(abs(candidate_change));
    if candidate_count < best_count || ...
            (candidate_count == best_count && ...
            candidate_variation < best_variation)
        setpoint = candidate;
        best_count = candidate_count;
        best_variation = candidate_variation;
    end
end
change = [setpoint(2:end); setpoint(1)] - setpoint;
start.O1_HB_setpoint = setpoint;
start.O1_HB_change = double(abs(change) > 1e-12);

    function [values, platform_starts] = merge_once( ...
            interval_lower, interval_upper, first_hour)
        T = numel(interval_lower);
        order = [first_hour:T, 1:first_hour-1];
        ranges = zeros(T, 2);
        segment_lower = zeros(T, 1);
        segment_upper = zeros(T, 1);
        first_position = 1;
        segment_count = 0;
        current_lower = interval_lower(order(1));
        current_upper = interval_upper(order(1));
        for position = 2:T
            next_lower = max(current_lower, interval_lower(order(position)));
            next_upper = min(current_upper, interval_upper(order(position)));
            if next_lower <= next_upper + 1e-12
                current_lower = next_lower;
                current_upper = next_upper;
            else
                segment_count = segment_count + 1;
                segment_lower(segment_count) = current_lower;
                segment_upper(segment_count) = current_upper;
                ranges(segment_count, :) = [first_position, position - 1];
                first_position = position;
                current_lower = interval_lower(order(position));
                current_upper = interval_upper(order(position));
            end
        end
        segment_count = segment_count + 1;
        segment_lower(segment_count) = current_lower;
        segment_upper(segment_count) = current_upper;
        ranges(segment_count, :) = [first_position, T];
        segment_lower = segment_lower(1:segment_count);
        segment_upper = segment_upper(1:segment_count);
        ranges = ranges(1:segment_count, :);

        merge_ends = false;
        if segment_count > 1
            merged_lower = max(segment_lower(1), segment_lower(end));
            merged_upper = min(segment_upper(1), segment_upper(end));
            merge_ends = merged_lower <= merged_upper + 1e-12;
        end
        values = zeros(T, 1);
        platform_starts = zeros(segment_count, 1);
        for segment = 1:segment_count
            value = (segment_lower(segment) + segment_upper(segment)) / 2;
            if merge_ends && (segment == 1 || segment == segment_count)
                value = (merged_lower + merged_upper) / 2;
            end
            positions = ranges(segment, 1):ranges(segment, 2);
            hours = order(positions);
            values(hours) = value;
            platform_starts(segment) = hours(1);
        end
        platform_starts = unique(platform_starts, 'stable');
    end
end

function check = solution_check(solution, ctx)
HB_load = solution.HB_load(:);
HB_change = [HB_load(2:end); HB_load(1)] - HB_load;
NH3_total_t = sum(HB_load) * ctx.params.HB.nh3_output * ctx.dt ...
    / ctx.params.unit.mass_scale;
check = struct('raw_updates', ...
    sum(abs(HB_change) > ctx.config.change_tolerance), ...
    'setpoint_updates', NaN, 'effective_updates', NaN, ...
    'actual_updates', NaN, 'binary_updates', NaN, ...
    'max_tracking_deviation', NaN);
if isfield(solution, 'O1_HB_setpoint')
    setpoint = solution.O1_HB_setpoint(:);
    change = [setpoint(2:end); setpoint(1)] - setpoint;
    numerical_tolerance = max(ctx.config.change_tolerance, ...
        ctx.model.options.ConstraintTolerance);
    check.setpoint_updates = sum(abs(change) > numerical_tolerance);
    check.effective_updates = check.setpoint_updates;
    check.actual_updates = check.setpoint_updates;
    check.max_tracking_deviation = max(abs(HB_load - setpoint));
end
if isfield(solution, 'O1_HB_change')
    check.binary_updates = round(sum(solution.O1_HB_change));
end
check.total_variation = sum(abs(HB_change));
check.maximum_change = max(abs(HB_change));
check.change_epsilon = ctx.config.change_epsilon;
check.nh3_total_t = NH3_total_t;
check.nh3_residual_t = NH3_total_t - ctx.config.nh3_target_t;
P_AEL_start = ctx.model.start_power_per_module_kw * solution.SU_AEL(:);
power_residual = ctx.model.context.P_total(:) + solution.p_purchase(:) ...
    - solution.P_AEL(:) - P_AEL_start ...
    - HB_load * ctx.model.context.HB_power_kw ...
    - solution.p_sell(:) - solution.p_curt(:);
H2_production = solution.P_AEL(:) * ctx.dt ...
    / ctx.model.context.AEL_spec_energy * ctx.model.context.H2_density;
H2_use = HB_load * ctx.model.context.NH3_rate * ctx.dt ...
    * ctx.params.HB.lit_h2;
storage_H2 = solution.storage_H2(:);
storage_residual = storage_H2(2:end) - storage_H2(1:end-1) ...
    - H2_production + H2_use;
check.max_power_residual_kw = max(abs(power_residual));
check.max_storage_residual_kg = max(abs(storage_residual));
end

function print_summary(study)
fprintf('\n========== O1 minimum HB load updates ==========\n');
fprintf('NH3 target: %.3f t over the modeled horizon\n', ...
    study.config.nh3_target_t);
fprintf('HB set-point tracking band epsilon: %.3f%% of nominal load\n', ...
    100 * study.config.change_epsilon);
if study.reference.has_incumbent
    fprintf('Economic reference: [%.3f, %.3f] USD\n', ...
        study.reference.objective_lower, study.reference.objective_upper);
else
    fprintf('Economic reference: no incumbent (%s)\n', study.reference.status);
end
if isfield(study.feasibility, 'minimum_updates')
    row = study.feasibility.minimum_updates;
    fprintf('K_feas: [%g, %g], proven=%d\n', ...
        row.count_lower, row.count_upper, row.is_proven);
end
if isfield(study.feasibility, 'scheduler')
    scheduler = study.feasibility.scheduler;
    fprintf(['K scheduler: autonomous=%d, elapsed=%.1f s, ', ...
        'budget_exhausted=%d\n'], scheduler.autonomous, ...
        scheduler.elapsed_s, scheduler.budget_exhausted);
end
if isfield(study, 'frontier') && ~isempty(study.frontier)
    finite_costs = sum(isfinite(study.frontier.cost_upper_usd));
    fprintf(['锚点约束成本前沿：K=%g:%g，有限成本界=%d/%d\n'], ...
        min(study.frontier.K), max(study.frontier.K), ...
        finite_costs, height(study.frontier));
end
if isfield(study, 'frontier_state')
    state = study.frontier_state;
    fprintf(['前沿进度：直接求解=%d/%d，本轮新增锚点=%d，', ...
        '未直接求解=%d，下一关键K=%g\n'], state.completed_points, ...
        state.total_points, state.new_points, state.pending_points, ...
        state.next_pending_K);
end
if isfield(study, 'cost_certification') && ...
        ~isempty(study.cost_certification)
    for index = 1:height(study.cost_certification)
        row = study.cost_certification(index, :);
        fprintf(['关键K=%g：成本区间=[%.6g, %.6g] USD，', ...
            '不确定性=%.6g USD/t，目标<=%.6g，认证=%d\n'], ...
            row.K, row.cost_lower_usd, row.cost_upper_usd, ...
            row.uncertainty_usd_t, row.target_usd_t, ...
            row.is_certified);
    end
end
if isfield(study, 'economic') && ~isempty(study.economic)
    for i = 1:numel(study.economic)
        row = study.economic(i);
        fprintf(['delta=%g USD/t (certified <= %.6g): ', ...
            'K_econ=[%g, %g], proven=%d\n'], ...
            row.allowance_usd_t, row.certified_allowance_usd_t, ...
            row.K_lower, row.K_upper, row.is_proven);
    end
end
fprintf('O1 status: %s\n', study.status);
end

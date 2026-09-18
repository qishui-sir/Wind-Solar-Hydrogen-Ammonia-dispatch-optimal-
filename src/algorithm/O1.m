function study = O1(model, config)
    arguments
        model (1, 1) struct
        config (1, 1) struct
    end

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
    config = validate_config(config);
    params = model.params;
    T = model.renewable_data.time_count;
    dt = params.time.step;
    HB_load = model.variables.HB_load;
    NH3_total_t = model.expressions.nh3_total_t;
    system_cost_usd = model.expressions.system_cost_usd;

    % 验证NH3目标是否在允许范围内
    minimum_output_t = params.HB.min_load * params.HB.nh3_output * T * dt ...
        / params.unit.mass_scale;
    maximum_output_t = params.HB.max_load * params.HB.nh3_output * T * dt ...
        / params.unit.mass_scale;
    target_tolerance = max(1e-6, 1e-9 * config.nh3_target_t);
    if config.nh3_target_t < minimum_output_t - target_tolerance || ...
            config.nh3_target_t > maximum_output_t + target_tolerance
        error('O1:target_out_of_range', ...
            ['NH3 target %.6g t is outside the HB-only range ', ...
            '[%.6g, %.6g] t for this horizon.'], ...
            config.nh3_target_t, minimum_output_t, maximum_output_t);
    end

    HB_ramp = params.HB.ramp_rate * dt;
    if config.change_epsilon >= HB_ramp
        error('O1:bad_change_epsilon', ...
            'change_epsilon must be smaller than the hourly HB ramp limit %.6g.', ...
            HB_ramp);
    end

    % 约束条件
    base_problem = model.problem;
    base_problem.Constraints.O1_nh3_target = ...
        NH3_total_t == config.nh3_target_t;
    base_problem.Constraints.O1_cyclic_ramp_up = ...
        HB_load(1) - HB_load(end) <= HB_ramp;
    base_problem.Constraints.O1_cyclic_ramp_down = ...
        HB_load(end) - HB_load(1) <= HB_ramp;

    % 两套求解选项：最小化成本，最小化变化次数
    cost_options = optimoptions(model.options, ...
        'RelativeGapTolerance', config.cost_relative_gap, ...
        'MaxTime', config.max_time_s, 'Display', config.display);
    count_options = optimoptions(model.options, ...
        'RelativeGapTolerance', 0, ...
        'AbsoluteGapTolerance', config.count_absolute_gap, ...
        'MaxTime', config.max_time_s, 'Display', config.display);

    study = struct();
    study.method = 'minimum_HB_load_updates';
    study.definition = ['Number of hourly HB set-point updates. Actual HB load ', ...
        'may remain within a change_epsilon-wide band around an unchanged ', ...
        'set-point; the cyclic last-to-first boundary is included.'];
    study.config = config;
    study.output_range_t = [minimum_output_t, maximum_output_t];
    study.progressive_penalty = struct();

    % 优化变量
    z = optimvar('O1_HB_change', T, 'Type', 'integer', ...
        'LowerBound', 0, 'UpperBound', 1);
    HB_setpoint = optimvar('O1_HB_setpoint', T, ...
        'LowerBound', params.HB.min_load, 'UpperBound', params.HB.max_load);
    setpoint_next = [HB_setpoint(2:end); HB_setpoint(1)];
    setpoint_change = setpoint_next - HB_setpoint;
    tracking_half_band = config.change_epsilon / 2;
    setpoint_change_limit = HB_ramp + config.change_epsilon;
    problem = base_problem;
    problem.Constraints.O1_tracking_up = ...
        HB_load - HB_setpoint <= tracking_half_band;
    problem.Constraints.O1_tracking_down = ...
        HB_setpoint - HB_load <= tracking_half_band;
    problem.Constraints.O1_change_up = ...
        setpoint_change <= setpoint_change_limit * z;
    problem.Constraints.O1_change_down = ...
        -setpoint_change <= setpoint_change_limit * z;
    update_count = sum(z);

    % 经济基础阶段
    %  删除经济惩罚
    %   加入缓存重载经济基础阶段的结果，避免重复求解
    fprintf('\n[O1] Stage 1: economic reference\n');
    stage1_cache_file = fullfile(pwd, 'O1_stage1_cache.mat');
    use_cache = true;   % 改成 false 可强制重算 Stage 1
    cache_signature = build_stage1_cache_signature(config, params);
    reference = struct();
    if use_cache && isfile(stage1_cache_file)
        loaded = load(stage1_cache_file);
        [cache_is_valid, cache_reason] = validate_stage1_cache(loaded, ...
            cache_signature, T, config.cost_relative_gap);
        if cache_is_valid
            reference = loaded.reference;
            fprintf('[O1] Stage 1 loaded from cache: %s\n', stage1_cache_file);
        else
            fprintf('[O1] Stage 1 cache ignored: %s\n', cache_reason);
        end
    end
    if isempty(fieldnames(reference)) || ~reference.has_incumbent
        reference_problem = problem;
        reference_problem.Objective = system_cost_usd;
        reference = solve_record(reference_problem, cost_options, 'cost', []);
        if reference.has_incumbent
            save(stage1_cache_file, 'reference', 'cache_signature');
            fprintf('[O1] Stage 1 result cached to: %s\n', stage1_cache_file);
        end
    end
    study.reference = reference;
    study.feasibility = struct();
    study.economic = struct([]);
    study.frontier = table();
    if ~reference.has_incumbent
        study.status = 'incomplete_reference_no_incumbent';
        print_summary(study);
        return
    end
    reference_count_start = add_change_indicators(reference.solution, ...
        config.change_epsilon, params.HB.min_load, params.HB.max_load);
    reference.solution = reference_count_start;
    study.reference = reference;

    % 可行性解：最小化变化次数（无成本约束）
    fprintf(['[O1] Stage 2: minimum feasible effective load updates ', ...
    '(warm start K=%g from economic reference)\n'], ...
    sum(reference_count_start.O1_HB_change));
    feasibility_problem = problem;
    feasibility_problem.Objective = update_count;
    feasibility = solve_record(feasibility_problem, count_options, 'count', ...
        reference_count_start);
    study.feasibility = struct('minimum_updates', feasibility);

    if ~feasibility.has_incumbent
        study.status = 'incomplete_no_incumbent';
        print_summary(study);
        return
    end

    K_feas_upper = feasibility.count_upper;
    study.feasibility.K_lower = feasibility.count_lower;
    study.feasibility.K_upper = K_feas_upper;
    study.feasibility.bound_width = ...
        K_feas_upper - feasibility.count_lower;
    study.feasibility.is_proven = feasibility.is_proven;
    study.check = struct();
    study.check.reference = solution_check(reference.solution, model, config);
    study.check.minimum_updates = solution_check(...
        feasibility.solution, model, config);

    % 当K_feas区间仍过宽时，继续求成本边界只会重复日志中已经观察到的
    % 根节点超时。保留上下界并停止，先改善核心计数问题。
    if ~isfinite(study.feasibility.bound_width) || ...
            study.feasibility.bound_width > config.max_count_bound_width
        fprintf(['[O1] Stop after Stage 2: K_feas bound width %g exceeds ', ...
            'the configured limit %g.\n'], study.feasibility.bound_width, ...
            config.max_count_bound_width);
        study.status = 'incomplete_feasibility_bound';
        print_summary(study);
        return
    end

    % 在当前已证明的K_feas区间上界内求成本最低的代表性调度。
    fprintf('[O1] Stage 3: minimum cost with K <= %g\n', K_feas_upper);
    representative_problem = problem;
    representative_problem.Constraints.O1_update_limit = ...
        update_count <= K_feas_upper;
    representative_problem.Objective = system_cost_usd;
    representative = solve_record(representative_problem, cost_options, 'cost', ...
        feasibility.solution);
    study.feasibility.minimum_cost_at_upper_bound = representative;
    if representative.has_incumbent
        study.check.minimum_updates_representative = solution_check(...
            representative.solution, model, config);
    end

    reference_lower = reference.objective_lower;
    reference_upper = reference.objective_upper;
    if ~isfinite(reference_lower)
        study.status = 'incomplete_reference_bound';
        print_summary(study);
        return
    end

    % 从Uc + deltaQ和Lc + deltaQ的成本上下限中，取成本上限，减少下限MILP的求解已提高求解效率。
    % 经济性分析：使用已知可行的经济参考上界作为统一成本锚点。相对于
    % 并对未知真最优值的最大附加误差单独报告，避免每个delta重复求解上下界。
    allowances = config.cost_allowance_usd_t(:);
    economic = repmat(struct(), numel(allowances), 1);
    reference_uncertainty_usd_t = ...
        (reference_upper - reference_lower) / config.nh3_target_t;
    economic_start = reference_count_start;
    for i = 1:numel(allowances)
        allowance = allowances(i);
        allowance_total = allowance * config.nh3_target_t;
        cost_cap = reference_upper + allowance_total;
        economic_start = choose_count_start(economic_start, ...
            {feasibility.solution, representative.solution}, ...
            system_cost_usd, cost_cap);
        fprintf(['[O1] Economic boundary: delta=%g USD/t, cap=%.3f USD, ', ...
            'warm start K=%g\n'], allowance, cost_cap, ...
            sum(economic_start.O1_HB_change));
        economic_problem = problem;
        economic_problem.Constraints.O1_cost_limit = ...
            system_cost_usd <= cost_cap;
        economic_problem.Objective = update_count;
        boundary = solve_record(economic_problem, count_options, 'count', ...
            economic_start);

        K_lower = 0;
        if isfinite(feasibility.count_lower)
            K_lower = feasibility.count_lower;
        end
        if isfinite(boundary.count_lower)
            K_lower = max(K_lower, boundary.count_lower);
        end
        K_upper = NaN;
        if boundary.has_incumbent
            K_upper = boundary.count_upper;
            economic_start = boundary.solution;
        end
        economic(i).allowance_usd_t = allowance;
        economic(i).cost_cap_usd = cost_cap;
        economic(i).reference_uncertainty_usd_t = ...
            reference_uncertainty_usd_t;
        economic(i).certified_allowance_usd_t = ...
            allowance + reference_uncertainty_usd_t;
        economic(i).K_lower = K_lower;
        economic(i).K_upper = K_upper;
        economic(i).is_proven = isfinite(K_lower) && isfinite(K_upper) && ...
            K_lower == K_upper;
        economic(i).minimum_updates = boundary;
    end
    study.economic = economic;

    % Pareto前沿点：给定变化次数上限，求最小成本
    frontier_K = unique(round(config.frontier_k(:)));
    frontier_K = frontier_K(frontier_K >= 0 & frontier_K <= T);
    frontier = table('Size', [numel(frontier_K), 6], ...
        'VariableTypes', {'double', 'double', 'double', 'double', 'double', 'string'}, ...
        'VariableNames', {'K', 'cost_lower_usd', 'cost_upper_usd', ...
        'premium_lower_usd_t', 'premium_upper_usd_t', 'status'});
    for i = 1:numel(frontier_K)
        frontier_problem = problem;
        frontier_problem.Constraints.O1_update_limit = ...
            update_count <= frontier_K(i);
        frontier_problem.Objective = system_cost_usd;
        point = solve_record(frontier_problem, cost_options, 'cost', []);
        frontier.K(i) = frontier_K(i);
        frontier.cost_lower_usd(i) = point.objective_lower;
        frontier.cost_upper_usd(i) = point.objective_upper;
        frontier.premium_lower_usd_t(i) = ...
            (point.objective_lower - reference_upper) / config.nh3_target_t;
        frontier.premium_upper_usd_t(i) = ...
            (point.objective_upper - reference_lower) / config.nh3_target_t;
        frontier.status(i) = point.status;
    end
    study.frontier = frontier;

    % 验证
    if feasibility.is_proven && ...
            (isempty(economic) || all([economic.is_proven]))
        study.status = 'complete';
    else
        study.status = 'complete_with_bounds';
    end
    print_summary(study);
end

%% 函数
function config = validate_config(config)
defaults = struct('nh3_target_t', 80000, ...
    'cost_allowance_usd_t', [0, 1, 5, 10], 'frontier_k', [], ...
    'max_time_s', 1200, 'cost_relative_gap', 1e-3, ...
    'count_absolute_gap', 0.99, 'change_epsilon', 0.01, ...
    'penalty_alpha', [0.1, 1, 10], 'penalty_max_time_s', 300, ...
    'penalty_relative_gap', 0.02, ...
    'max_count_bound_width', 20, 'change_tolerance', 1e-6, ...
    'display', 'off');
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
if ~isscalar(config.nh3_target_t) || ~isfinite(config.nh3_target_t) || ...
        config.nh3_target_t <= 0
    error('O1:bad_target', 'nh3_target_t must be a positive finite scalar.');
end
if ~isnumeric(config.cost_allowance_usd_t) || ...
        any(~isfinite(config.cost_allowance_usd_t)) || ...
        any(config.cost_allowance_usd_t < 0)
    error('O1:bad_allowance', ...
        'cost_allowance_usd_t must contain finite nonnegative values.');
end
if ~isnumeric(config.frontier_k) || any(~isfinite(config.frontier_k)) || ...
        any(config.frontier_k < 0) || ...
        any(abs(config.frontier_k - round(config.frontier_k)) > 1e-9)
    error('O1:bad_frontier', ...
        'frontier_k must contain nonnegative integer values.');
end
if ~isscalar(config.max_time_s) || ~isfinite(config.max_time_s) || ...
        config.max_time_s <= 0
    error('O1:bad_time', 'max_time_s must be a positive finite scalar.');
end
if ~isscalar(config.cost_relative_gap) || config.cost_relative_gap < 0 || ...
        config.cost_relative_gap >= 1
    error('O1:bad_cost_gap', 'cost_relative_gap must be in [0, 1).');
end
if ~isscalar(config.count_absolute_gap) || config.count_absolute_gap < 0 || ...
        config.count_absolute_gap >= 1
    error('O1:bad_count_gap', 'count_absolute_gap must be in [0, 1).');
end
if ~isscalar(config.change_epsilon) || config.change_epsilon < 0 || ...
        ~isfinite(config.change_epsilon)
    error('O1:bad_change_epsilon', ...
        'change_epsilon must be a finite nonnegative load fraction.');
end
if ~isnumeric(config.penalty_alpha) || isempty(config.penalty_alpha) || ...
        ~isvector(config.penalty_alpha) || ...
        any(~isfinite(config.penalty_alpha)) || any(config.penalty_alpha <= 0)
    error('O1:bad_penalty_alpha', ...
        'penalty_alpha must contain positive finite values.');
end
if ~isscalar(config.penalty_max_time_s) || ...
        ~isfinite(config.penalty_max_time_s) || config.penalty_max_time_s <= 0
    error('O1:bad_penalty_time', ...
        'penalty_max_time_s must be a positive finite scalar.');
end
if ~isscalar(config.penalty_relative_gap) || ...
        config.penalty_relative_gap < 0 || config.penalty_relative_gap >= 1
    error('O1:bad_penalty_gap', ...
        'penalty_relative_gap must be in [0, 1).');
end
if ~isscalar(config.max_count_bound_width) || ...
        config.max_count_bound_width < 0 || ...
        isnan(config.max_count_bound_width)
    error('O1:bad_count_bound_width', ...
        'max_count_bound_width must be nonnegative.');
end
if ~isscalar(config.change_tolerance) || config.change_tolerance < 0 || ...
        ~isfinite(config.change_tolerance)
    error('O1:bad_change_tolerance', ...
        'change_tolerance must be finite and nonnegative.');
end
if ~(ischar(config.display) || ...
        (isstring(config.display) && isscalar(config.display)))
    error('O1:bad_display', 'display must be text.');
end
config.cost_allowance_usd_t = unique(config.cost_allowance_usd_t, 'stable');
config.penalty_alpha = config.penalty_alpha(:).';
end

% Stage1缓存签名：用于验证缓存的有效性
function signature = build_stage1_cache_signature(config, params)
signature = struct();
signature.schema_version = 1;
signature.nh3_target_t = config.nh3_target_t;
signature.change_epsilon = config.change_epsilon;
signature.model_parameters = struct( ...
    'time_step', params.time.step, ...
    'unit', params.unit, ...
    'renewable_capacity', struct( ...
        'PV_capacity', params.renewable.PV_capacity, ...
        'PW_capacity', params.renewable.PW_capacity), ...
    'finance', params.finance, ...
    'pw', params.pw, ...
    'pv', params.pv, ...
    'h2_storage', params.h2_storage, ...
    'ammonia', params.ammonia, ...
    'material', params.material, ...
    'labor', params.labor, ...
    'converter', params.converter, ...
    'transformer', params.transformer, ...
    'grid', params.grid, ...
    'environment', params.environment, ...
    'AEL_common', params.AEL.common, ...
    'HB', params.HB);
end

function [is_valid, reason] = validate_stage1_cache(loaded, ...
        expected_signature, expected_length, requested_relative_gap)
is_valid = false;
reason = 'missing cache metadata';
if ~isstruct(loaded) || ~isfield(loaded, 'reference') || ...
        ~isfield(loaded, 'cache_signature')
    return
end
if ~isequaln(loaded.cache_signature, expected_signature)
    reason = 'production target or model parameters changed';
    return
end

reference = loaded.reference;
reason = 'cached reference is incomplete';
if ~isstruct(reference) || ~isfield(reference, 'has_incumbent') || ...
        ~reference.has_incumbent || ~isfield(reference, 'solution') || ...
        ~isstruct(reference.solution) || ...
        ~isfield(reference.solution, 'HB_load') || ...
        numel(reference.solution.HB_load) ~= expected_length
    return
end

reason = 'cached cost bound is looser than requested';
if isfield(reference, 'is_proven') && reference.is_proven
    is_valid = true;
elseif requested_relative_gap > 0 && ...
        isfield(reference, 'relative_gap') && ...
        isscalar(reference.relative_gap) && ...
        isfinite(reference.relative_gap) && ...
        reference.relative_gap <= requested_relative_gap + 1e-12
    is_valid = true;
end
if is_valid
    reason = '';
end
end

% 初始解替换为区间交集合并
function start = add_change_indicators(solution, epsilon, minimum_load, ...
        maximum_load)
start = solution;
HB_load = solution.HB_load(:);
interval_lower = max(minimum_load, HB_load - epsilon / 2);
interval_upper = min(maximum_load, HB_load + epsilon / 2);

[setpoint, platform_starts] = merge_load_intervals(...
    interval_lower, interval_upper, 1);
candidate_starts = unique([1; platform_starts(:)], 'stable');
if epsilon == 0
    candidate_starts = 1;
end
best_count = sum(abs([setpoint(2:end); setpoint(1)] - setpoint) > 1e-12);
best_variation = sum(abs([setpoint(2:end); setpoint(1)] - setpoint));
for i = 2:numel(candidate_starts)
    candidate = merge_load_intervals(interval_lower, interval_upper, ...
        candidate_starts(i));
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
setpoint_change = [setpoint(2:end); setpoint(1)] - setpoint;
start.O1_HB_setpoint = setpoint;
start.O1_HB_change = double(abs(setpoint_change) > 1e-12);
end

function [setpoint, platform_starts] = merge_load_intervals(...
        interval_lower, interval_upper, first_hour)
T = numel(interval_lower);
order = [first_hour:T, 1:first_hour-1];
segment_first = 1;
segment_count = 0;
segment_lower = zeros(T, 1);
segment_upper = zeros(T, 1);
segment_ranges = zeros(T, 2);
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
        segment_ranges(segment_count, :) = [segment_first, position - 1];
        segment_first = position;
        current_lower = interval_lower(order(position));
        current_upper = interval_upper(order(position));
    end
end
segment_count = segment_count + 1;
segment_lower(segment_count) = current_lower;
segment_upper(segment_count) = current_upper;
segment_ranges(segment_count, :) = [segment_first, T];

segment_lower = segment_lower(1:segment_count);
segment_upper = segment_upper(1:segment_count);
segment_ranges = segment_ranges(1:segment_count, :);
merge_ends = false;
if segment_count > 1
    merged_lower = max(segment_lower(1), segment_lower(end));
    merged_upper = min(segment_upper(1), segment_upper(end));
    merge_ends = merged_lower <= merged_upper + 1e-12;
end

setpoint = zeros(T, 1);
platform_starts = zeros(segment_count, 1);
for segment = 1:segment_count
    value = (segment_lower(segment) + segment_upper(segment)) / 2;
    if merge_ends && (segment == 1 || segment == segment_count)
        value = (merged_lower + merged_upper) / 2;
    end
    positions = segment_ranges(segment, 1):segment_ranges(segment, 2);
    hours = order(positions);
    setpoint(hours) = value;
    platform_starts(segment) = hours(1);
end
platform_starts = unique(platform_starts, 'stable');
end

function best = choose_count_start(initial_solution, candidates, ...
        system_cost_usd, cost_cap)
all_candidates = [{initial_solution}, candidates];
best = struct();
best_count = Inf;
cost_tolerance = 1e-8 * max(1, abs(cost_cap));
for i = 1:numel(all_candidates)
    candidate = all_candidates{i};
    if ~isstruct(candidate) || isempty(fieldnames(candidate)) || ...
            ~isfield(candidate, 'O1_HB_change')
        continue
    end
    try
        candidate_cost = evaluate(system_cost_usd, candidate);
    catch
        continue
    end
    candidate_count = round(sum(candidate.O1_HB_change));
    if candidate_cost <= cost_cap + cost_tolerance && ...
            candidate_count < best_count
        best = candidate;
        best_count = candidate_count;
    end
end
end

function record = solve_record(problem, options, objective_kind, initial_solution)
record = struct('objective_kind', objective_kind, 'has_incumbent', false, ...
    'objective_lower', NaN, 'objective_upper', NaN, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, 'count_upper', NaN, 'is_proven', false, ...
    'exitflag', NaN, 'status', "not_run", 'message', "", ...
    'output', struct(), 'solution', struct());
try
    has_initial = isstruct(initial_solution) && ...
        ~isempty(fieldnames(initial_solution));
    if ~has_initial
        [solution, fval, exitflag, output] = solve(problem, ...
            'Solver', 'intlinprog', 'Options', options);
    else
        [solution, fval, exitflag, output] = solve(problem, initial_solution, ...
            'Solver', 'intlinprog', 'Options', options);
    end
catch exception
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.exitflag = exitflag;
record.output = output;
if isfield(output, 'message')
    record.message = string(output.message);
end
record.has_incumbent = isstruct(solution) && ...
    isfield(solution, 'HB_load') && ~isempty(solution.HB_load) && ...
    isscalar(fval) && isfinite(fval);
if ~record.has_incumbent
    record.status = "no_incumbent";
    return
end
record.solution = solution;
record.objective_upper = fval;
if isfield(output, 'absolutegap') && ~isempty(output.absolutegap) && ...
        isscalar(output.absolutegap) && isfinite(output.absolutegap)
    record.absolute_gap = max(0, output.absolutegap);
    record.objective_lower = fval - record.absolute_gap;
elseif exitflag > 0
    record.absolute_gap = 0;
    record.objective_lower = fval;
else
    record.objective_lower = NaN;
end
if isfield(output, 'relativegap') && ~isempty(output.relativegap) && ...
        isscalar(output.relativegap) && isfinite(output.relativegap)
    record.relative_gap = max(0, output.relativegap);
end
if strcmp(objective_kind, 'count')
    record.count_upper = round(sum(solution.O1_HB_change));
    record.count_lower = max(0, ceil(record.objective_lower - 1e-7));
    record.is_proven = record.count_lower == record.count_upper;
elseif strcmp(objective_kind, 'penalty')
    record.is_proven = false;
else
    record.is_proven = exitflag > 0 && record.absolute_gap <= ...
        max(1e-7, eps(abs(fval)));
end
if strcmp(objective_kind, 'penalty')
    record.status = "heuristic_incumbent";
elseif record.is_proven
    record.status = "proven";
else
    record.status = "incumbent_with_bound";
end
% 诊断
if isfield(record.output, 'bestbound') && isfinite(record.output.bestbound)
    fprintf('[DBG] bestbound=%.6g, incumbent=%.6g, gap=%.4g%%\n', ...
        record.output.bestbound, record.objective_upper, ...
        100 * record.relative_gap);
end
sol = record.solution;
fprintf('[DBG] P_sell range: [%.4g, %.4g]\n', ...
    min(sol.p_sell), max(sol.p_sell));
fprintf('[DBG] P_buy range: [%.4g, %.4g]\n', ...
    min(sol.p_purchase), max(sol.p_purchase));
fprintf('[DBG] storage_H2 range: [%.4g, %.4g]\n', ...
    min(sol.storage_H2), max(sol.storage_H2));
fprintf('[DBG] HB_load range: [%.4g, %.4g]\n', ...
    min(sol.HB_load), max(sol.HB_load));
end




function check = solution_check(solution, model, config)
HB_load = solution.HB_load(:);
HB_change = [HB_load(2:end); HB_load(1)] - HB_load;
NH3_total_t = sum(HB_load) * model.params.HB.nh3_output ...
    * model.params.time.step / model.params.unit.mass_scale;
check = struct();
check.raw_updates = sum(abs(HB_change) > config.change_tolerance);
check.setpoint_updates = NaN;
check.effective_updates = NaN;
check.actual_updates = NaN;
check.binary_updates = NaN;
check.max_tracking_deviation = NaN;
if isfield(solution, 'O1_HB_setpoint')
    HB_setpoint = solution.O1_HB_setpoint(:);
    setpoint_change = [HB_setpoint(2:end); HB_setpoint(1)] - HB_setpoint;
    check.setpoint_updates = sum(abs(setpoint_change) > ...
        config.change_tolerance);
    check.effective_updates = check.setpoint_updates;
    check.actual_updates = check.setpoint_updates;
    check.max_tracking_deviation = max(abs(HB_load - HB_setpoint));
end
if isfield(solution, 'O1_HB_change')
    check.binary_updates = round(sum(solution.O1_HB_change));
end
check.total_variation = sum(abs(HB_change));
check.maximum_change = max(abs(HB_change));
check.change_epsilon = config.change_epsilon;
check.nh3_total_t = NH3_total_t;
check.nh3_residual_t = NH3_total_t - config.nh3_target_t;
P_AEL_start = model.start_power_per_module_kw * solution.SU_AEL;
power_residual = model.context.P_total + solution.p_purchase ...
    - solution.P_AEL - P_AEL_start ...
    - HB_load * model.context.HB_power_kw ...
    - solution.p_sell - solution.p_curt;
H2_production = solution.P_AEL * model.params.time.step ...
    / model.context.AEL_spec_energy * model.context.H2_density;
H2_use = HB_load * model.context.NH3_rate * model.params.time.step ...
    * model.params.HB.lit_h2;
storage_residual = solution.storage_H2(2:end) ...
    - solution.storage_H2(1:end-1) - H2_production + H2_use;
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
    minimum_updates = study.feasibility.minimum_updates;
    if minimum_updates.has_incumbent
        fprintf('K_feas: [%g, %g], proven=%d\n', ...
            minimum_updates.count_lower, minimum_updates.count_upper, ...
            minimum_updates.is_proven);
    else
        fprintf('K_feas: no incumbent (%s)\n', minimum_updates.status);
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

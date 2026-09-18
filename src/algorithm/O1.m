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

    % 固定K求最小成本，并复用同一份求解器矩阵。
    K_reference = round(sum(reference_count_start.O1_HB_change));
    fprintf('[O1] Stage 2: fixed-K cost search, initial K=%g\n', K_reference);
    cost_at_k_problem = problem;
    cost_at_k_problem.Constraints.O1_update_limit = update_count <= T;
    cost_at_k_problem.Objective = system_cost_usd;
    [fixed_k_solver, build_time_s] = build_fixed_k_solver( ...
        cost_at_k_problem, cost_options, reference_count_start, T);
    point_cache = initialize_k_cache(reference, reference_count_start, ...
        K_reference);
    [feasibility, point_cache] = search_feasibility_boundary( ...
        fixed_k_solver, point_cache, K_reference, config, params);
    study.feasibility = feasibility;
    study.search = struct('method', "cost_at_fixed_K", ...
        'solver_model_build_count', 1, ...
        'solver_model_build_time_s', build_time_s, 'points', table());

    study.check = struct();
    study.check.reference = solution_check(reference.solution, model, config);
    if feasibility.minimum_updates.has_incumbent
        study.check.minimum_updates = solution_check( ...
            feasibility.minimum_updates.solution, model, config);
    end

    if ~isfinite(feasibility.bound_width) || ...
            feasibility.bound_width > config.max_count_bound_width
        study.search.points = k_cache_table(point_cache);
        fprintf(['[O1] Stop after Stage 2: K_feas bound width %g exceeds ', ...
            'the configured limit %g.\n'], feasibility.bound_width, ...
            config.max_count_bound_width);
        study.status = 'incomplete_feasibility_bound';
        print_summary(study);
        return
    end

    representative = feasibility.minimum_cost_at_upper_bound;
    if representative.has_incumbent
        study.check.minimum_updates_representative = solution_check( ...
            representative.solution, model, config);
    end

    reference_lower = reference.objective_lower;
    reference_upper = reference.objective_upper;
    if ~isfinite(reference_lower)
        study.status = 'incomplete_reference_bound';
        print_summary(study);
        return
    end

    % 用成本上下界判定每个K是否满足经济预算。
    allowances = config.cost_allowance_usd_t(:);
    economic = struct([]);
    reference_uncertainty_usd_t = ...
        (reference_upper - reference_lower) / config.nh3_target_t;
    for i = 1:numel(allowances)
        allowance = allowances(i);
        fprintf('[O1] Economic boundary: delta=%g USD/t\n', allowance);
        [economic_row, point_cache] = search_economic_boundary( ...
            fixed_k_solver, point_cache, feasibility, K_reference, ...
            allowance, reference_lower, reference_upper, config, params);
        economic_row.reference_uncertainty_usd_t = ...
            reference_uncertainty_usd_t;
        economic_row.certified_allowance_usd_t = ...
            allowance + reference_uncertainty_usd_t;
        if isempty(economic)
            economic = economic_row;
        else
            economic(i, 1) = economic_row;
        end
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
        [point, point_cache] = get_k_point(fixed_k_solver, point_cache, ...
            frontier_K(i), config, params);
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
    study.search.points = k_cache_table(point_cache);

    % 验证
    if study.feasibility.is_proven && ...
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
    'max_count_bound_width', 20, 'max_k_search_points', 16, ...
    'change_tolerance', 1e-6, ...
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
if ~isscalar(config.max_k_search_points) || ...
        ~isfinite(config.max_k_search_points) || ...
        config.max_k_search_points < 1 || ...
        abs(config.max_k_search_points - round(config.max_k_search_points)) > 1e-9
    error('O1:bad_k_search_points', ...
        'max_k_search_points must be a positive integer.');
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

% 把 problem-based 模型一次性转成 solver-based 矩阵
% 固定K模型只转换一次，后续仅修改次数约束右端项。
function [solver_data, elapsed_s] = build_fixed_k_solver( ...
        problem, options, initial_solution, maximum_K)
started = tic;
solver_problem = prob2struct(problem, initial_solution, ...
    'Solver', 'intlinprog');
solver_problem.options = options;
indices = varindex(problem);
z_indices = indices.O1_HB_change(:);
A = solver_problem.Aineq;
z_block = A(:, z_indices);
row_nnz = full(sum(spones(A), 2));
z_nnz = full(sum(spones(z_block), 2));
candidates = find(row_nnz == numel(z_indices) & ...
    z_nnz == numel(z_indices));

update_row = NaN;
update_coefficient = NaN;
for i = 1:numel(candidates)
    row = candidates(i);
    values = full(A(row, z_indices));
    coefficient = values(1);
    if coefficient > 0 && ...
            max(abs(values - coefficient)) <= 1e-12 && ...
            abs(solver_problem.bineq(row) / coefficient - maximum_K) <= 1e-8
        update_row = row;
        update_coefficient = coefficient;
        break
    end
end
if ~isfinite(update_row)
    error('O1:update_row_not_found', ...
        'Cannot locate the fixed-K constraint in the solver matrix.');
end

solver_data = struct('problem', solver_problem, 'indices', indices, ...
    'update_row', update_row, ...
    'update_coefficient', update_coefficient);
elapsed_s = toc(started);
end

% 经济参考解Stage1的结果初始化K缓存
function cache = initialize_k_cache(reference, solution, K)
record = reference;
record.objective_kind = 'cost';
record.solution = solution;
record.count_upper = K;
record.count_lower = NaN;
record.solve_backend = "problem_reference";
record.is_infeasible = false;
record.K_limit = K;
cache = struct('K', K, 'record', record, 'source', "reference");
end

% 在[K_lower, K_upper]二分搜索最小可行变化次数
function [summary, cache] = search_feasibility_boundary( ...
        solver_data, cache, K_reference, config, params)
lower_infeasible = -1;
upper_feasible = K_reference;
best_record = cache(1).record;
trace_K = zeros(0, 1);
trace_status = strings(0, 1);

for iteration = 1:config.max_k_search_points
    if upper_feasible - lower_infeasible <= 1
        break
    end
    K = floor((lower_infeasible + upper_feasible) / 2);
    [record, cache] = get_k_point(solver_data, cache, K, config, params);
    trace_K(end + 1, 1) = K; %#ok<AGROW>
    if record.has_incumbent
        upper_feasible = K;
        best_record = record;
        trace_status(end + 1, 1) = "feasible"; %#ok<AGROW>
    elseif record.is_infeasible
        lower_infeasible = K;
        trace_status(end + 1, 1) = "infeasible"; %#ok<AGROW>
    else
        trace_status(end + 1, 1) = "unknown"; %#ok<AGROW>
        break
    end
end

K_lower = lower_infeasible + 1;
K_upper = upper_feasible;
minimum_updates = make_count_summary( ...
    K_lower, K_upper, best_record, "fixed_k_feasibility_search");
summary = struct();
summary.minimum_updates = minimum_updates;
summary.minimum_cost_at_upper_bound = best_record;
summary.K_lower = K_lower;
summary.K_upper = K_upper;
summary.bound_width = K_upper - K_lower;
summary.is_proven = K_lower == K_upper;
summary.search = table(trace_K, trace_status, ...
    'VariableNames', {'K', 'classification'});
end

% 在给定成本允许量δ下，二分搜索满足成本预算的最小K。
function [economic, cache] = search_economic_boundary( ...
        solver_data, cache, feasibility, K_reference, allowance, ...
        reference_lower, reference_upper, config, params)
allowance_total = allowance * config.nh3_target_t;
cost_cap = reference_upper + allowance_total;
lower_infeasible = feasibility.K_lower - 1;
upper_feasible = K_reference;
[best_record, cache] = get_k_point( ...
    solver_data, cache, K_reference, config, params);
trace_K = zeros(0, 1);
trace_status = strings(0, 1);

% 复用已有K点，先收紧经济边界。
for i = 1:numel(cache)
    K = cache(i).K;
    classification = classify_cost_point(cache(i).record, cost_cap);
    if classification == "feasible" && K < upper_feasible
        upper_feasible = K;
        best_record = cache(i).record;
    elseif classification == "infeasible" && ...
            K > lower_infeasible && K < upper_feasible
        lower_infeasible = K;
    end
end

for iteration = 1:config.max_k_search_points
    if upper_feasible - lower_infeasible <= 1
        break
    end
    K = floor((lower_infeasible + upper_feasible) / 2);
    [record, cache] = get_k_point(solver_data, cache, K, config, params);
    classification = classify_cost_point(record, cost_cap);
    trace_K(end + 1, 1) = K; %#ok<AGROW>
    trace_status(end + 1, 1) = classification; %#ok<AGROW>
    if classification == "feasible"
        upper_feasible = K;
        best_record = record;
    elseif classification == "infeasible"
        lower_infeasible = K;
    else
        break
    end
end

K_lower = lower_infeasible + 1;
K_upper = upper_feasible;
boundary = make_count_summary( ...
    K_lower, K_upper, best_record, "fixed_k_economic_search");
economic = struct();
economic.allowance_usd_t = allowance;
economic.cost_cap_usd = cost_cap;
economic.reference_lower_usd = reference_lower;
economic.reference_upper_usd = reference_upper;
economic.K_lower = K_lower;
economic.K_upper = K_upper;
economic.is_proven = K_lower == K_upper;
economic.minimum_updates = boundary;
economic.search = table(trace_K, trace_status, ...
    'VariableNames', {'K', 'classification'});
end

function classification = classify_cost_point(record, cost_cap)
tolerance = 1e-8 * max(1, abs(cost_cap));
if record.has_incumbent && ...
        record.objective_upper <= cost_cap + tolerance
    classification = "feasible";
elseif record.is_infeasible || ...
        (isfinite(record.objective_lower) && ...
        record.objective_lower > cost_cap + tolerance)
    classification = "infeasible";
else
    classification = "unknown";
end
end

function summary = make_count_summary(K_lower, K_upper, cost_record, status)
summary = struct('objective_kind', 'k_search', ...
    'has_incumbent', cost_record.has_incumbent, ...
    'objective_lower', NaN, 'objective_upper', NaN, ...
    'absolute_gap', K_upper - K_lower, 'relative_gap', NaN, ...
    'count_lower', K_lower, 'count_upper', K_upper, ...
    'is_proven', K_lower == K_upper, 'exitflag', cost_record.exitflag, ...
    'status', string(status), 'message', cost_record.message, ...
    'output', cost_record.output, 'solution', cost_record.solution);
end

function [record, cache] = get_k_point( ...
        solver_data, cache, K, config, params)
index = find([cache.K] == K, 1);
if ~isempty(index)
    record = cache(index).record;
    return
end

initial_solution = choose_k_start(cache, K);
record = solve_fixed_k(solver_data, K, initial_solution);
if record.has_incumbent
    record.solution = add_change_indicators(record.solution, ...
        config.change_epsilon, params.HB.min_load, params.HB.max_load);
    record.count_upper = round(sum(record.solution.O1_HB_change));
end
entry = struct('K', K, 'record', record, 'source', "fixed_k");
cache(end + 1) = entry;
end

function solution = choose_k_start(cache, K)
solution = struct();
best_cost = Inf;
for i = 1:numel(cache)
    record = cache(i).record;
    if ~record.has_incumbent || record.count_upper > K
        continue
    end
    if record.objective_upper < best_cost
        solution = record.solution;
        best_cost = record.objective_upper;
    end
end
end

% 在固定K的情况下求解最小成本问题
function record = solve_fixed_k(solver_data, K, initial_solution)
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.x0 = solution_to_vector(initial_solution, solver_data.indices, ...
    numel(problem.lb));

record = empty_cost_record(K);
try
    [x, fval, exitflag, output] = intlinprog(problem);
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
record.is_infeasible = exitflag == -2;
record.has_incumbent = ~isempty(x) && isscalar(fval) && isfinite(fval);
if ~record.has_incumbent
    if record.is_infeasible
        record.status = "infeasible";
    else
        record.status = "no_incumbent";
    end
    return
end

record.solution = vector_to_solution(x, solver_data.indices);
record.objective_upper = fval + problem.f0;
if isfield(output, 'absolutegap') && isscalar(output.absolutegap) && ...
        isfinite(output.absolutegap)
    record.absolute_gap = max(0, output.absolutegap);
    record.objective_lower = record.objective_upper - record.absolute_gap;
elseif exitflag > 0
    record.absolute_gap = 0;
    record.objective_lower = record.objective_upper;
end
if isfinite(record.absolute_gap)
    record.relative_gap = record.absolute_gap / ...
        max(1, abs(record.objective_upper));
end
record.count_upper = round(sum(record.solution.O1_HB_change));
record.is_proven = exitflag > 0 && record.absolute_gap <= ...
    max(1e-7, eps(abs(record.objective_upper)));
if record.is_proven
    record.status = "proven";
else
    record.status = "incumbent_with_bound";
end
end

function record = empty_cost_record(K)
record = struct('objective_kind', 'cost', 'has_incumbent', false, ...
    'objective_lower', NaN, 'objective_upper', NaN, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, 'count_upper', NaN, 'is_proven', false, ...
    'is_infeasible', false, 'exitflag', NaN, 'status', "not_run", ...
    'message', "", 'output', struct(), 'solution', struct(), ...
    'solve_backend', "intlinprog_matrix", 'K_limit', K);
end

function vector = solution_to_vector(solution, indices, variable_count)
if ~isstruct(solution) || isempty(fieldnames(solution))
    vector = [];
    return
end
vector = zeros(variable_count, 1);
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(solution, name) || ...
            numel(solution.(name)) ~= numel(indices.(name))
        vector = [];
        return
    end
    vector(indices.(name)(:)) = solution.(name)(:);
end
end

function solution = vector_to_solution(vector, indices)
solution = struct();
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    variable_indices = indices.(name);
    solution.(name) = reshape(vector(variable_indices(:)), ...
        size(variable_indices));
end
end

function points = k_cache_table(cache)
row_count = numel(cache);
K = zeros(row_count, 1);
cost_lower_usd = NaN(row_count, 1);
cost_upper_usd = NaN(row_count, 1);
has_incumbent = false(row_count, 1);
is_infeasible = false(row_count, 1);
status = strings(row_count, 1);
source = strings(row_count, 1);
objective_kind = repmat("cost", row_count, 1);
for i = 1:row_count
    K(i) = cache(i).K;
    record = cache(i).record;
    cost_lower_usd(i) = record.objective_lower;
    cost_upper_usd(i) = record.objective_upper;
    has_incumbent(i) = record.has_incumbent;
    is_infeasible(i) = record.is_infeasible;
    status(i) = string(record.status);
    source(i) = cache(i).source;
end
points = table(K, cost_lower_usd, cost_upper_usd, has_incumbent, ...
    is_infeasible, status, source, objective_kind);
points = sortrows(points, 'K');
end

% Stage1缓存签名：用于验证缓存的有效性
function signature = build_stage1_cache_signature(config, params)
signature = struct();
signature.schema_version = 2;
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
P_AEL_start = model.start_power_per_module_kw * solution.SU_AEL(:);
power_residual = model.context.P_total(:) + solution.p_purchase(:) ...
    - solution.P_AEL(:) - P_AEL_start ...
    - HB_load * model.context.HB_power_kw ...
    - solution.p_sell(:) - solution.p_curt(:);
H2_production = solution.P_AEL(:) * model.params.time.step ...
    / model.context.AEL_spec_energy * model.context.H2_density;
H2_use = HB_load * model.context.NH3_rate * model.params.time.step ...
    * model.params.HB.lit_h2;
storage_H2 = solution.storage_H2(:);
storage_residual = storage_H2(2:end) ...
    - storage_H2(1:end-1) - H2_production + H2_use;
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

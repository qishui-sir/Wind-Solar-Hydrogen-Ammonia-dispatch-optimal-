function study = O1(model, config)
%O1 求解HB最小设定值变化次数及其经济边界。
arguments
    model (1, 1) struct
    config (1, 1) struct
end

config = validate_config(config);
ctx = build_context(model, config);
[ctx.problem, window_info] = add_window_cover_cuts(ctx);

fprintf('\n[O1] Stage 1: economic reference\n');
reference = load_or_solve_reference(ctx);
study = struct('method', 'minimum_HB_load_updates', ...
    'definition', ['Number of cyclic hourly HB set-point updates; ', ...
    'HB load may remain inside the configured tracking band.'], ...
    'config', config, 'output_range_t', ctx.output_range_t, ...
    'window_cuts', window_info, 'reference', reference, ...
    'feasibility', struct(), 'economic', struct([]), ...
    'frontier', table(), 'check', struct(), ...
    'progressive_penalty', struct());
if ~reference.has_incumbent
    study.status = 'incomplete_reference_no_incumbent';
    print_summary(study);
    return
end

reference.solution = add_change_indicators(reference.solution, ctx);
reference.count_upper = round(sum(reference.solution.O1_HB_change));
study.reference = reference;
study.check.reference = solution_check(reference.solution, ctx);

fprintf('[O1] Stage 2: direct minimum-count solve, initial K=%g\n', ...
    reference.count_upper);
[feasibility, feasibility_points, build_info] = ...
    solve_count_boundary(ctx, reference.solution, Inf, "feasibility");
study.feasibility = feasibility;
study.search = struct( ...
    'method', "cost_at_fixed_K", ... % 兼容既有结果字段
    'strategy', "direct_count_with_fixed_k_feasibility", ...
    'solver_model_build_count', 1, ...
    'solver_model_build_time_s', build_info.elapsed_s, ...
    'points', feasibility_points);
if feasibility.minimum_updates.has_incumbent
    study.check.minimum_updates = solution_check( ...
        feasibility.minimum_updates.solution, ctx);
end

if ~isfinite(feasibility.bound_width) || ...
        feasibility.bound_width > config.max_count_bound_width
    fprintf(['[O1] Stop after Stage 2: K_feas bound width %g exceeds ', ...
        'the configured limit %g.\n'], feasibility.bound_width, ...
        config.max_count_bound_width);
    study.status = 'incomplete_feasibility_bound';
    print_summary(study);
    return
end

[representative, frontier] = solve_cost_outputs(ctx, feasibility, ...
    config.frontier_k, reference);
study.feasibility.minimum_cost_at_upper_bound = representative;
study.frontier = frontier;
if representative.has_incumbent
    study.check.minimum_updates_representative = ...
        solution_check(representative.solution, ctx);
end

if ~isfinite(reference.objective_lower)
    study.status = 'incomplete_reference_bound';
    print_summary(study);
    return
end

study.economic = solve_economic_boundaries(ctx, reference, feasibility);
if feasibility.is_proven && ...
        (isempty(study.economic) || all([study.economic.is_proven]))
    study.status = 'complete';
else
    study.status = 'complete_with_bounds';
end
print_summary(study);
end

function config = validate_config(config)
defaults = struct( ...
    'nh3_target_t', 80000, ...
    'cost_allowance_usd_t', [0, 1, 5, 10], ...
    'frontier_k', [], ...
    'max_time_s', 1200, ...
    'cost_relative_gap', 1e-3, ...
    'count_absolute_gap', 0.99, ...
    'change_epsilon', 0.01, ...
    'max_count_bound_width', 0, ...
    'max_k_search_points', 16, ...
    'change_tolerance', 1e-6, ...
    'enable_window_cuts', true, ...
    'window_lengths_h', [72, 168], ...
    'window_candidates_per_length', 2, ...
    'max_window_cuts', 4, ...
    'window_lp_max_time_s', 45, ...
    'enable_start_repair', true, ...
    'repair_max_time_s', 300, ...
    'use_cache', true, ...
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

must_be_positive_scalar(config.nh3_target_t, 'nh3_target_t');
must_be_positive_scalar(config.max_time_s, 'max_time_s');
must_be_positive_scalar(config.window_lp_max_time_s, 'window_lp_max_time_s');
must_be_positive_scalar(config.repair_max_time_s, 'repair_max_time_s');
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
integer_fields = {'max_k_search_points', 'window_candidates_per_length', ...
    'max_window_cuts'};
for i = 1:numel(integer_fields)
    value = config.(integer_fields{i});
    if ~isscalar(value) || ~isfinite(value) || value < 0 || ...
            abs(value - round(value)) > 1e-9
        error('O1:bad_integer_option', '%s must be a nonnegative integer.', ...
            integer_fields{i});
    end
end
if config.max_k_search_points < 1
    error('O1:bad_k_search_points', ...
        'max_k_search_points must be positive.');
end
if any(~isfinite(config.window_lengths_h)) || ...
        any(config.window_lengths_h <= 0)
    error('O1:bad_window_lengths', ...
        'window_lengths_h must contain positive finite values.');
end
logical_fields = {'enable_window_cuts', 'enable_start_repair', 'use_cache'};
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
count_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, ...
    'AbsoluteGapTolerance', config.count_absolute_gap, ...
    'MaxTime', config.max_time_s, 'Display', config.display);
feasibility_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxTime', config.max_time_s, 'Display', config.display);
repair_options = optimoptions(feasibility_options, ...
    'MaxTime', min(config.max_time_s, config.repair_max_time_s));

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

ctx = struct('model', model, 'config', config, 'params', params, ...
    'T', T, 'dt', dt, 'HB_ramp', HB_ramp, 'HB_load', HB_load, ...
    'z', z, 'setpoint', setpoint, 'update_count', sum(z), ...
    'system_cost_usd', system_cost_usd, 'base_problem', base_problem, ...
    'problem', problem, 'cost_options', cost_options, ...
    'count_options', count_options, ...
    'feasibility_options', feasibility_options, ...
    'repair_options', repair_options, 'signature', signature, ...
    'output_range_t', [minimum_output_t, maximum_output_t], ...
    'stage1_cache_file', fullfile(pwd, 'O1_stage1_cache.mat'), ...
    'point_cache_file', fullfile(pwd, 'O1_fixed_k_cache.mat'));
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
solver_problem = prob2struct(probe, 'Solver', 'intlinprog');
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
        valid = isfield(loaded, 'reference') && ...
            isfield(loaded, 'cache_signature') && ...
            isequaln(loaded.cache_signature, ctx.signature);
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
            fprintf('[O1] Stage 1 loaded from cache: %s\n', ...
                ctx.stage1_cache_file);
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
        'cache_signature', ctx.signature);
    save(ctx.stage1_cache_file, '-struct', 'cache_payload', '-v7.3');
    fprintf('[O1] Stage 1 result cached to: %s\n', ctx.stage1_cache_file);
end
end

function [summary, points, build_info] = solve_count_boundary( ...
        ctx, initial_solution, cost_cap, mode)
boundary_problem = ctx.problem;
cost_tolerance = 1e-8 * max(1, abs(cost_cap));
if isfinite(cost_cap)
    boundary_problem.Constraints.O1_cost_cap = ...
        ctx.system_cost_usd <= cost_cap;
    initial_cost = evaluate(ctx.system_cost_usd, initial_solution);
    if ~isfinite(initial_cost) || initial_cost > cost_cap + cost_tolerance
        error('O1:invalid_boundary_start', ...
            'The economic-boundary initial solution violates its cost cap.');
    end
end
entries = fixed_point_store(ctx.point_cache_file, ctx.signature, ...
    "load", mode, cost_cap, struct());
search_start = initial_solution;
search_start_count = round(sum(search_start.O1_HB_change));
for i = 1:numel(entries)
    record = entries(i).record;
    if record.has_incumbent && isfinite(cost_cap) && ...
            (~isfinite(record.system_cost_upper) || ...
            record.system_cost_upper > cost_cap + cost_tolerance)
        entries(i).record.has_incumbent = false;
        entries(i).record.status = "cost_cap_violation";
        continue
    end
    if record.has_incumbent && record.count_upper < search_start_count
        search_start = record.solution;
        search_start_count = record.count_upper;
    end
end
initial_count = round(sum(initial_solution.O1_HB_change));
if search_start_count < initial_count
    fprintf('[O1] Reusing cached feasible start: K=%g.\n', ...
        search_start_count);
end
boundary_problem.Objective = ctx.update_count;
direct = solve_problem(boundary_problem, ctx.count_options, ...
    "count", search_start, ctx.system_cost_usd);
if direct.has_incumbent && isfinite(cost_cap) && ...
        (~isfinite(direct.system_cost_upper) || ...
        direct.system_cost_upper > cost_cap + cost_tolerance)
    direct.has_incumbent = false;
    direct.status = "cost_cap_violation";
end
if direct.has_incumbent
    direct.solution = add_change_indicators(direct.solution, ctx);
    direct.count_upper = round(sum(direct.solution.O1_HB_change));
    direct.objective_upper = direct.count_upper;
    if isfinite(direct.objective_lower)
        direct.absolute_gap = max(0, ...
            direct.objective_upper - direct.objective_lower);
        direct.relative_gap = direct.absolute_gap / ...
            max(1, direct.objective_upper);
    end
    direct.is_proven = isfinite(direct.count_lower) && ...
        direct.count_lower == direct.count_upper;
end

seed_count = search_start_count;
best_record = direct;
if ~direct.has_incumbent || seed_count < direct.count_upper
    best_record = direct;
    best_record.has_incumbent = true;
    best_record.solution = search_start;
    best_record.count_upper = seed_count;
    best_record.objective_upper = seed_count;
    best_record.system_cost_upper = evaluate( ...
        ctx.system_cost_usd, search_start);
    best_record.status = "seed_incumbent";
end
lower = 0;
if isfinite(direct.count_lower)
    lower = direct.count_lower;
end
upper = best_record.count_upper;
lower = min(lower, upper);

fixed_problem = boundary_problem;
fixed_problem.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
fixed_problem.Objective = 0;
[solver_data, elapsed_s] = build_fixed_solver( ...
    fixed_problem, ctx, search_start);
build_info = struct('elapsed_s', elapsed_s);
for i = 1:numel(entries)
    record = entries(i).record;
    if record.has_incumbent
        if record.count_upper < upper
            upper = record.count_upper;
            best_record = record;
        end
    elseif record.is_infeasible
        lower = max(lower, entries(i).K + 1);
    end
end
lower = min(lower, upper);

trace_K = zeros(0, 1);
trace_status = strings(0, 1);
certified = arrayfun(@(e) e.record.has_incumbent || ...
    e.record.is_infeasible, entries);
tried = [entries(certified).K];
for iteration = 1:ctx.config.max_k_search_points
    if lower >= upper
        break
    end
    candidates = setdiff(lower:(upper - 1), tried);
    if isempty(candidates)
        break
    end
    midpoint = (lower + upper - 1) / 2;
    [~, choice] = min(abs(candidates - midpoint) - 1e-9 * candidates);
    K = candidates(choice);
    [record, source] = solve_fixed_point( ...
        solver_data, boundary_problem, entries, search_start, K, ctx);
    if record.has_incumbent && isfinite(cost_cap) && ...
            (~isfinite(record.system_cost_upper) || ...
            record.system_cost_upper > cost_cap + cost_tolerance)
        record.has_incumbent = false;
        record.status = "cost_cap_violation";
    end
    entry = struct('mode', string(mode), 'cost_cap', cost_cap, ...
        'K', K, 'record', record, 'source', source);
    entries = update_entry(entries, entry);
    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
        "append", mode, cost_cap, entry);
    tried(end + 1) = K; %#ok<AGROW>
    trace_K(end + 1, 1) = K; %#ok<AGROW>
    if record.has_incumbent
        upper = min(upper, record.count_upper);
        if record.count_upper <= best_record.count_upper
            best_record = record;
        end
        trace_status(end + 1, 1) = "feasible"; %#ok<AGROW>
    elseif record.is_infeasible
        lower = max(lower, K + 1);
        trace_status(end + 1, 1) = "infeasible"; %#ok<AGROW>
    else
        trace_status(end + 1, 1) = "unknown"; %#ok<AGROW>
    end
end

minimum_updates = struct('objective_kind', 'count', ...
    'has_incumbent', best_record.has_incumbent, ...
    'objective_lower', lower, 'objective_upper', upper, ...
    'absolute_gap', upper - lower, ...
    'relative_gap', (upper - lower) / max(1, upper), ...
    'count_lower', lower, 'count_upper', upper, ...
    'is_proven', lower == upper, 'exitflag', direct.exitflag, ...
    'status', "direct_count_with_fixed_k_fallback", ...
    'message', direct.message, 'output', direct.output, ...
    'solution', best_record.solution);
summary = struct('minimum_updates', minimum_updates, ...
    'minimum_cost_at_upper_bound', best_record, ...
    'direct_count', direct, 'K_lower', lower, 'K_upper', upper, ...
    'bound_width', upper - lower, 'is_proven', lower == upper, ...
    'search', table(trace_K, trace_status, ...
    'VariableNames', {'K', 'classification'}));

display_entries = entries;
if direct.has_incumbent && ...
        ~any([display_entries.K] == direct.count_upper)
    display_entries(end + 1) = struct('mode', string(mode), ...
        'cost_cap', cost_cap, 'K', direct.count_upper, ...
        'record', direct, 'source', "direct_count");
end
points = make_point_table(display_entries);

    function list = update_entry(list, new_entry)
        match = find([list.K] == new_entry.K, 1);
        if isempty(match)
            list(end + 1) = new_entry;
        else
            list(match) = new_entry;
        end
    end

    function result = make_point_table(list)
        if isempty(list)
            result = table('Size', [0, 9], ...
                'VariableTypes', {'double', 'double', 'double', ...
                'logical', 'logical', 'string', 'string', 'string', 'string'}, ...
                'VariableNames', {'K', 'cost_lower_usd', 'cost_upper_usd', ...
                'has_incumbent', 'is_infeasible', 'status', 'source', ...
                'objective_kind', 'solve_kind'});
            return
        end
        K_value = [list.K].';
        cost_lower = arrayfun(@(e) e.record.system_cost_lower, list).';
        cost_upper = arrayfun(@(e) e.record.system_cost_upper, list).';
        has_incumbent = arrayfun(@(e) e.record.has_incumbent, list).';
        is_infeasible = arrayfun(@(e) e.record.is_infeasible, list).';
        status = string(arrayfun(@(e) char(e.record.status), list, ...
            'UniformOutput', false)).';
        source = string({list.source}).';
        objective_kind = repmat("cost", numel(list), 1);
        solve_kind = string(arrayfun(@(e) char(e.record.objective_kind), list, ...
            'UniformOutput', false)).';
        result = table(K_value, cost_lower, cost_upper, has_incumbent, ...
            is_infeasible, status, source, objective_kind, solve_kind, ...
            'VariableNames', {'K', 'cost_lower_usd', 'cost_upper_usd', ...
            'has_incumbent', 'is_infeasible', 'status', 'source', ...
            'objective_kind', 'solve_kind'});
        result = sortrows(result, 'K');
    end
end

function [solver_data, elapsed_s] = build_fixed_solver(problem, ctx, initial)
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
solver_data = struct('problem', solver_problem, 'indices', indices, ...
    'update_row', update_row, 'update_coefficient', update_coefficient);
elapsed_s = toc(started);
end

function [record, source] = solve_fixed_point( ...
        solver_data, boundary_problem, entries, initial, K, ctx)
start = struct();
start_cost = Inf;
initial_count = round(sum(initial.O1_HB_change));
if initial_count <= K
    start = initial;
    start_cost = evaluate(ctx.system_cost_usd, initial);
end
for i = 1:numel(entries)
    candidate = entries(i).record;
    if candidate.has_incumbent && candidate.count_upper <= K && ...
            candidate.system_cost_upper < start_cost
        start = candidate.solution;
        start_cost = candidate.system_cost_upper;
    end
end

source = "fixed_k";
if isempty(fieldnames(start)) && ctx.config.enable_start_repair
    repair_source = initial;
    repair_count = initial_count;
    for i = 1:numel(entries)
        candidate = entries(i).record;
        if candidate.has_incumbent && candidate.count_upper > K && ...
                candidate.count_upper < repair_count
            repair_source = candidate.solution;
            repair_count = candidate.count_upper;
        end
    end
    repaired = repair_start(boundary_problem, repair_source, K, ctx);
    if repaired.has_incumbent
        record = repaired;
        source = "repaired_start";
        return
    end
end

problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.x0 = [];
if ~isempty(fieldnames(start))
    vector = zeros(numel(problem.lb), 1);
    names = fieldnames(solver_data.indices);
    complete = true;
    for i = 1:numel(names)
        name = names{i};
        if ~isfield(start, name) || ...
                numel(start.(name)) ~= numel(solver_data.indices.(name))
            complete = false;
            break
        end
        vector(solver_data.indices.(name)(:)) = start.(name)(:);
    end
    if complete
        problem.x0 = vector;
        source = "cached_start";
    end
end

record = struct('objective_kind', "feasibility", ...
    'has_incumbent', false, 'objective_lower', NaN, ...
    'objective_upper', NaN, 'system_cost_lower', NaN, ...
    'system_cost_upper', NaN, 'absolute_gap', NaN, ...
    'relative_gap', NaN, 'count_lower', NaN, 'count_upper', NaN, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "not_run", 'message', "", 'output', struct(), ...
    'solution', struct(), 'solve_backend', "intlinprog_matrix", ...
    'K_limit', K);
try
    [x, fval, exitflag, output] = intlinprog(problem);
catch exception
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.exitflag = exitflag;
record.output = output;
record.is_infeasible = exitflag == -2;
if isfield(output, 'message')
    record.message = string(output.message);
end
record.has_incumbent = ~isempty(x) && isscalar(fval) && isfinite(fval);
if ~record.has_incumbent
    if record.is_infeasible
        record.status = "infeasible";
    else
        record.status = "unknown";
    end
    return
end

solution = struct();
names = fieldnames(solver_data.indices);
for i = 1:numel(names)
    name = names{i};
    index = solver_data.indices.(name);
    solution.(name) = reshape(x(index(:)), size(index));
end
solution = add_change_indicators(solution, ctx);
count = round(sum(solution.O1_HB_change));
if count > K
    record.has_incumbent = false;
    record.status = "invalid_incumbent";
    return
end
record.solution = solution;
record.objective_lower = 0;
record.objective_upper = 0;
record.absolute_gap = 0;
record.relative_gap = 0;
record.count_upper = count;
record.system_cost_upper = evaluate(ctx.system_cost_usd, solution);
record.is_proven = true;
record.status = "feasible";
end

function record = repair_start(problem, source, K, ctx)
record = struct('has_incumbent', false);
if ~isstruct(source) || ~isfield(source, 'HB_load')
    return
end
if K < 2
    segment_count = 1;
else
    segment_count = min(K, ctx.T);
end
segment_ends = floor((1:segment_count) * ctx.T / segment_count);
segment_starts = [1, segment_ends(1:end-1) + 1];
lengths = segment_ends - segment_starts + 1;
averages = zeros(segment_count, 1);
source_load = source.HB_load(:);
for i = 1:segment_count
    averages(i) = mean(source_load(segment_starts(i):segment_ends(i)));
end

I = speye(segment_count);
rows = (1:segment_count).';
next_rows = mod(rows, segment_count) + 1;
D = sparse([rows; rows], [rows; next_rows], ...
    [-ones(segment_count, 1); ones(segment_count, 1)], ...
    segment_count, segment_count);
A = [I, -I; -I, -I; D, sparse(segment_count, segment_count); ...
    -D, sparse(segment_count, segment_count)];
b = [averages; -averages; ...
    ctx.HB_ramp * ones(2 * segment_count, 1)];
target_load_sum = ctx.config.nh3_target_t * ctx.params.unit.mass_scale ...
    / (ctx.params.HB.nh3_output * ctx.dt);
Aeq = [lengths, zeros(1, segment_count)];
beq = target_load_sum;
lb = [ctx.params.HB.min_load * ones(segment_count, 1); ...
    zeros(segment_count, 1)];
ub = [ctx.params.HB.max_load * ones(segment_count, 1); ...
    Inf(segment_count, 1)];
lp_options = optimoptions('linprog', 'Display', 'none', 'MaxTime', 10);
try
    [value, ~, exitflag] = linprog([zeros(segment_count, 1); ...
        ones(segment_count, 1)], A, b, Aeq, beq, lb, ub, lp_options);
catch
    return
end
if exitflag <= 0 || isempty(value)
    return
end

levels = value(1:segment_count);
candidate_load = zeros(ctx.T, 1);
for i = 1:segment_count
    candidate_load(segment_starts(i):segment_ends(i)) = levels(i);
end
candidate_change = [candidate_load(2:end); candidate_load(1)] ...
    - candidate_load;
candidate_z = double(abs(candidate_change) > 1e-9);
if sum(candidate_z) > K
    return
end

repair_problem = problem;
repair_problem.Constraints.O1_repair_load = ctx.HB_load == candidate_load;
repair_problem.Constraints.O1_repair_setpoint = ...
    ctx.setpoint == candidate_load;
repair_problem.Constraints.O1_repair_changes = ctx.z == candidate_z;
repair_problem.Objective = 0;
record = solve_problem(repair_problem, ctx.repair_options, ...
    "feasibility", struct(), ctx.system_cost_usd);
if record.has_incumbent
    record.solution = add_change_indicators(record.solution, ctx);
    record.count_upper = round(sum(record.solution.O1_HB_change));
    record.K_limit = K;
    record.status = "repaired_feasible";
    if record.count_upper > K
        record.has_incumbent = false;
        record.status = "invalid_repair";
    end
end
end

function entries = fixed_point_store(file, signature, action, mode, cost_cap, entry)
cache_sets = struct('signature', {}, 'entries', {});
if isfile(file)
    try
        loaded = load(file, 'cache_sets');
        if isfield(loaded, 'cache_sets')
            cache_sets = loaded.cache_sets;
        end
    catch
        cache_sets = struct('signature', {}, 'entries', {});
    end
end
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
    'K_limit', NaN);
try
    if isstruct(initial_solution) && ~isempty(fieldnames(initial_solution))
        [solution, fval, exitflag, output] = solve(problem, initial_solution, ...
            'Solver', 'intlinprog', 'Options', options);
    else
        [solution, fval, exitflag, output] = solve(problem, ...
            'Solver', 'intlinprog', 'Options', options);
    end
catch exception
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end

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

function [representative, frontier] = solve_cost_outputs( ...
        ctx, feasibility, frontier_K, reference)
upper = feasibility.K_upper;
initial = feasibility.minimum_updates.solution;
representative = solve_cost_point(ctx, upper, initial);
if ~representative.has_incumbent
    representative = feasibility.minimum_cost_at_upper_bound;
end

frontier_K = unique(round(frontier_K(:)));
frontier_K = frontier_K(frontier_K >= 0 & frontier_K <= ctx.T);
frontier = table('Size', [numel(frontier_K), 6], ...
    'VariableTypes', {'double', 'double', 'double', 'double', 'double', 'string'}, ...
    'VariableNames', {'K', 'cost_lower_usd', 'cost_upper_usd', ...
    'premium_lower_usd_t', 'premium_upper_usd_t', 'status'});
for i = 1:numel(frontier_K)
    point = solve_cost_point(ctx, frontier_K(i), initial);
    frontier.K(i) = frontier_K(i);
    frontier.cost_lower_usd(i) = point.objective_lower;
    frontier.cost_upper_usd(i) = point.objective_upper;
    frontier.premium_lower_usd_t(i) = ...
        (point.objective_lower - reference.objective_upper) ...
        / ctx.config.nh3_target_t;
    frontier.premium_upper_usd_t(i) = ...
        (point.objective_upper - reference.objective_lower) ...
        / ctx.config.nh3_target_t;
    frontier.status(i) = point.status;
end

    function point = solve_cost_point(local_ctx, K, start)
        cost_problem = local_ctx.problem;
        cost_problem.Constraints.O1_update_limit = ...
            local_ctx.update_count <= K;
        cost_problem.Objective = local_ctx.system_cost_usd;
        if round(sum(start.O1_HB_change)) > K
            start = struct();
        end
        point = solve_problem(cost_problem, local_ctx.cost_options, ...
            "cost", start, local_ctx.system_cost_usd);
        if point.has_incumbent
            point.solution = add_change_indicators(point.solution, local_ctx);
            point.count_upper = round(sum(point.solution.O1_HB_change));
        end
    end
end

function economic = solve_economic_boundaries(ctx, reference, feasibility)
allowances = ctx.config.cost_allowance_usd_t(:);
economic = struct([]);
start = reference.solution;
uncertainty = (reference.objective_upper - reference.objective_lower) ...
    / ctx.config.nh3_target_t;
for i = 1:numel(allowances)
    allowance = allowances(i);
    cost_cap = reference.objective_upper + ...
        allowance * ctx.config.nh3_target_t;
    fprintf('[O1] Economic boundary: delta=%g USD/t\n', allowance);
    [boundary, ~, ~] = solve_count_boundary( ...
        ctx, start, cost_cap, "economic");
    boundary.K_lower = max(boundary.K_lower, feasibility.K_lower);
    if boundary.K_lower > boundary.K_upper
        error('O1:inconsistent_economic_bounds', ...
            'Economic K bounds conflict with the feasibility lower bound.');
    end
    boundary.minimum_updates.count_lower = boundary.K_lower;
    boundary.bound_width = boundary.K_upper - boundary.K_lower;
    boundary.is_proven = boundary.K_lower == boundary.K_upper;
    boundary.minimum_updates.objective_lower = boundary.K_lower;
    boundary.minimum_updates.absolute_gap = boundary.bound_width;
    boundary.minimum_updates.relative_gap = boundary.bound_width ...
        / max(1, boundary.K_upper);
    boundary.minimum_updates.is_proven = boundary.is_proven;
    row = struct('allowance_usd_t', allowance, ...
        'cost_cap_usd', cost_cap, ...
        'reference_lower_usd', reference.objective_lower, ...
        'reference_upper_usd', reference.objective_upper, ...
        'reference_uncertainty_usd_t', uncertainty, ...
        'certified_allowance_usd_t', allowance + uncertainty, ...
        'K_lower', boundary.K_lower, 'K_upper', boundary.K_upper, ...
        'is_proven', boundary.is_proven, ...
        'minimum_updates', boundary.minimum_updates, ...
        'search', boundary.search);
    if isempty(economic)
        economic = row;
    else
        economic(i, 1) = row;
    end
    if boundary.minimum_updates.has_incumbent
        start = boundary.minimum_updates.solution;
    end
end
end

function start = add_change_indicators(solution, ctx)
start = solution;
HB_load = solution.HB_load(:);
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
    check.setpoint_updates = sum(abs(change) > ctx.config.change_tolerance);
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

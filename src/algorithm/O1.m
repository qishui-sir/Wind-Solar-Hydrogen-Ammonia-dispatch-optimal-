function study = O1(model, config)
%O1 求解HB最小设定值变化次数及其经济边界。
arguments
    model (1, 1) struct
    config (1, 1) struct
end

config = validate_config(config);
ctx = build_context(model, config);
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
    'frontier', table(), 'check', struct(), ...
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
    solve_count_boundary(ctx, reference.solution, Inf, "feasibility");
study.feasibility = feasibility;
if isfield(build_info, 'window_cuts')
    study.window_cuts = build_info.window_cuts;
end
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

[representative, frontier, frontier_state] = solve_cost_outputs(ctx, feasibility, ...
    config.frontier_k, reference);
study.feasibility.minimum_cost_at_upper_bound = representative;
study.frontier = frontier;
study.frontier_state = frontier_state;
if representative.has_incumbent && isfield(representative, 'solution') && ...
        ~isempty(fieldnames(representative.solution))
    study.check.minimum_updates_representative = ...
        solution_check(representative.solution, ctx);
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
    'frontier_all_k', false, ...
    'frontier_max_time_s', 180, ...
    'frontier_max_attempts', 2, ...
    'frontier_solution_interval', 25, ...
    'frontier_run_budget_s', Inf, ...
    'frontier_points_per_run', 25, ...
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
must_be_positive_scalar(config.frontier_max_time_s, 'frontier_max_time_s');
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
    'compute_frontier_during_search'};
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

ctx = struct('model', model, 'config', config, 'params', params, ...
    'T', T, 'dt', dt, 'HB_ramp', HB_ramp, 'HB_load', HB_load, ...
    'z', z, 'setpoint', setpoint, 'update_count', sum(z), ...
    'system_cost_usd', system_cost_usd, ...
    'cost_components', cost_components, 'base_problem', base_problem, ...
    'problem', problem, 'cost_options', cost_options, ...
    'frontier_options', frontier_options, ...
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
fixed_problem = boundary_problem;
fixed_problem.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
% 固定K只判定可行性，避免在无关的成本下界上消耗根节点时间。
fixed_problem.Objective = 0;
[solver_data, elapsed_s] = build_fixed_solver( ...
    fixed_problem, ctx, search_start);
[solver_data, matrix_window_info] = add_matrix_window_cover_cuts( ...
    solver_data, ctx, string(mode) == "feasibility");
window_cut_count = matrix_window_info.cut_count;
build_info = struct('elapsed_s', elapsed_s, ...
    'window_cuts', matrix_window_info);
cached_direct = find(string({entries.source}) == "direct_bound" & ...
    arrayfun(@(entry) isfield(entry.record, 'window_cut_count') && ...
    entry.record.window_cut_count == window_cut_count, entries), 1);
if ctx.config.use_cache && ~isempty(cached_direct)
    direct = entries(cached_direct).record;
    direct.elapsed_s = 0;
    fprintf('[O1] Reusing certified count bound: [%g, %g].\n', ...
        direct.count_lower, direct.count_upper);
else
    direct = solve_count_relaxation_matrix( ...
        solver_data, search_start, ctx);
    direct.window_cut_count = window_cut_count;
    fprintf('[O1] count relaxation: lower=%g, upper=%g, status=%s, %.1f s\n', ...
        direct.count_lower, direct.count_upper, direct.status, direct.elapsed_s);
end
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
if ctx.config.use_cache && isempty(cached_direct) && ...
        (direct.is_proven || direct.count_lower > 0)
    bound_entry = struct('mode', string(mode), 'cost_cap', cost_cap, ...
        'K', ctx.T + 1, 'record', direct, 'source', "direct_bound");
    entries = update_entry(entries, bound_entry);
    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
        "append", mode, cost_cap, bound_entry);
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
trace_attempt = zeros(0, 1);
repair_strategy = "local_compact_window_v5";
certified = arrayfun(@(e) e.record.has_incumbent || ...
    e.record.is_infeasible, entries);
tried = [entries(certified).K];
search_started = tic;
budget_exhausted = false;
for iteration = 1:ctx.config.max_k_search_points
    if lower >= upper
        break
    end
    if ctx.config.autonomous_search && ...
            toc(search_started) >= ctx.config.run_budget_s
        budget_exhausted = true;
        fprintf('[O1] autonomous run budget %.1f s exhausted; state cached.\n', ...
            ctx.config.run_budget_s);
        break
    end
    candidates = setdiff(lower:(upper - 1), tried);
    if isempty(candidates)
        break
    end
    if ctx.config.autonomous_search
        [K, previous_attempt] = choose_autonomous_K( ...
            candidates, lower, upper, entries, ctx.config);
        fprintf(['[O1] autonomous task K=%g selected from [%g,%g], ', ...
            'source-attempt=%d.\n'], K, lower, upper, previous_attempt + 1);
    else
        % 显式探针保留为兼容模式；自主模式不依赖硬编码K列表。
        requested_probes = ctx.config.feasibility_probe_k;
        available_probes = requested_probes( ...
            ismember(requested_probes, candidates));
        if isempty(available_probes)
            K = max(candidates);
        else
            K = available_probes(1);
            fprintf('[O1] targeted feasibility probe K=%g selected.\n', K);
        end
        previous_attempt = 0;
    end
    source_upper = upper;
    [record, source] = solve_fixed_point( ...
        solver_data, boundary_problem, entries, search_start, K, ctx, ...
        repair_strategy, mode, cost_cap);
    record.autonomous_attempt_count = previous_attempt + 1;
    record.autonomous_source_upper = source_upper;
    if record.has_incumbent && isfinite(cost_cap) && ...
            (~isfinite(record.system_cost_upper) || ...
            record.system_cost_upper > cost_cap + cost_tolerance)
        record.has_incumbent = false;
        record.status = "cost_cap_violation";
    end
    if ~record.has_incumbent && ~record.is_infeasible
        record.repair_strategy = repair_strategy;
    end
    entry = struct('mode', string(mode), 'cost_cap', cost_cap, ...
        'K', K, 'record', record, 'source', source);
    tried(end + 1) = K; %#ok<AGROW>
    trace_K(end + 1, 1) = K; %#ok<AGROW>
    trace_attempt(end + 1, 1) = record.autonomous_attempt_count; %#ok<AGROW>
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
        entry.source = "continuation_exhausted";
    end
    entries = update_entry(entries, entry);
    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
        "append", mode, cost_cap, entry);
    fprintf('[O1] fixed K=%g: %s (%s), %.1f s\n', ...
        K, trace_status(end), source, record.elapsed_s);
    if trace_status(end) == "unknown" && ~ctx.config.autonomous_search
        break
    elseif trace_status(end) == "unknown"
        fprintf('[O1] K=%g deferred; autonomous scheduler continues.\n', K);
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
    'search', table(trace_K, trace_status, trace_attempt, ...
    'VariableNames', {'K', 'classification', 'attempt'}), ...
    'scheduler', struct('autonomous', ctx.config.autonomous_search, ...
    'elapsed_s', toc(search_started), ...
    'run_budget_s', ctx.config.run_budget_s, ...
    'budget_exhausted', budget_exhausted));

display_entries = entries(string({entries.source}) ~= "direct_bound");
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

    function [selected_K, previous_attempt] = choose_autonomous_K( ...
            available_K, current_lower, current_upper, list, options)
        available_K = available_K(:).';
        attempts = zeros(size(available_K));
        for candidate_index = 1:numel(available_K)
            match = find([list.K] == available_K(candidate_index), 1);
            if isempty(match)
                continue
            end
            prior = list(match).record;
            if isfield(prior, 'autonomous_attempt_count') && ...
                    isfield(prior, 'autonomous_source_upper') && ...
                    prior.autonomous_source_upper == current_upper
                attempts(candidate_index) = ...
                    double(prior.autonomous_attempt_count);
            end
        end

        minimum_attempt = min(attempts);
        if minimum_attempt >= options.max_k_attempts_per_source
            % 所有候选都已轮转到当前上限时，从尝试最少者继续；
            % 不把计算预算限制误当成数学不可行。
            eligible = available_K(attempts == minimum_attempt);
        else
            eligible = available_K( ...
                attempts == minimum_attempt & ...
                attempts < options.max_k_attempts_per_source);
        end
        explicit = options.feasibility_probe_k( ...
            ismember(options.feasibility_probe_k, eligible));
        if ~isempty(explicit)
            selected_K = explicit(1);
        else
            midpoint = floor((current_lower + current_upper) / 2);
            anchors = unique([current_lower, current_upper - 1, midpoint, ...
                floor((current_lower + 3 * current_upper) / 4), ...
                ceil((3 * current_lower + current_upper) / 4)], 'stable');
            anchors = anchors(ismember(anchors, eligible));
            if ~isempty(anchors)
                selected_K = anchors(1);
            else
                % 未处理候选较多时优先靠近可行上界，便于产生新热启动。
                selected_K = max(eligible);
            end
        end
        previous_attempt = attempts(available_K == selected_K);
        previous_attempt = previous_attempt(1);
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

function record = solve_count_relaxation(problem, initial, ctx)
record = struct('objective_kind', "count", 'has_incumbent', true, ...
    'objective_lower', NaN, 'objective_upper', NaN, ...
    'system_cost_lower', NaN, 'system_cost_upper', NaN, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, 'count_upper', NaN, 'is_proven', false, ...
    'is_infeasible', false, 'exitflag', NaN, 'status', "unknown", ...
    'message', "", 'output', struct(), 'solution', initial, ...
    'solve_backend', "linprog_relaxation", 'K_limit', NaN, ...
    'elapsed_s', NaN);
record.count_upper = round(sum(initial.O1_HB_change));
record.objective_upper = record.count_upper;
record.system_cost_upper = evaluate(ctx.system_cost_usd, initial);
started = tic;
try
    solver_problem = prob2struct(problem, 'Solver', 'intlinprog');
    options = optimoptions('linprog', 'Display', ctx.config.display, ...
        'MaxTime', ctx.config.count_max_time_s);
    [~, fval, exitflag, output] = linprog(solver_problem.f, ...
        solver_problem.Aineq, solver_problem.bineq, ...
        solver_problem.Aeq, solver_problem.beq, ...
        solver_problem.lb, solver_problem.ub, options);
catch exception
    record.elapsed_s = toc(started);
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.elapsed_s = toc(started);
record.exitflag = exitflag;
record.output = output;
if isfield(output, 'message')
    record.message = string(output.message);
end
if exitflag <= 0 || ~isfinite(fval)
    return
end
record.objective_lower = fval;
record.count_lower = max(0, ceil(fval - 1e-7));
record.absolute_gap = record.count_upper - record.objective_lower;
record.relative_gap = record.absolute_gap / max(1, record.count_upper);
record.is_proven = record.count_lower == record.count_upper;
if record.is_proven
    record.status = "proven";
else
    record.status = "lp_bound_with_seed";
end
end

function record = solve_count_relaxation_matrix(solver_data, initial, ctx)
record = struct('objective_kind', "count", 'has_incumbent', true, ...
    'objective_lower', NaN, 'objective_upper', NaN, ...
    'system_cost_lower', NaN, 'system_cost_upper', NaN, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, 'count_upper', NaN, 'is_proven', false, ...
    'is_infeasible', false, 'exitflag', NaN, 'status', "unknown", ...
    'message', "", 'output', struct(), 'solution', initial, ...
    'solve_backend', "linprog_matrix_relaxation", 'K_limit', NaN, ...
    'elapsed_s', NaN);
record.count_upper = round(sum(initial.O1_HB_change));
record.objective_upper = record.count_upper;
record.system_cost_upper = evaluate(ctx.system_cost_usd, initial);
problem = solver_data.problem;
objective = zeros(numel(problem.lb), 1);
objective(solver_data.indices.O1_HB_change(:)) = 1;
started = tic;
try
    options = optimoptions('linprog', 'Display', ctx.config.display, ...
        'MaxTime', ctx.config.count_max_time_s);
    [~, fval, exitflag, output] = linprog(objective, ...
        problem.Aineq, problem.bineq, problem.Aeq, problem.beq, ...
        problem.lb, problem.ub, options);
catch exception
    record.elapsed_s = toc(started);
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.elapsed_s = toc(started);
record.exitflag = exitflag;
record.output = output;
if isfield(output, 'message')
    record.message = string(output.message);
end
if exitflag <= 0 || ~isfinite(fval)
    return
end
record.objective_lower = fval;
record.count_lower = max(0, ceil(fval - 1e-7));
record.absolute_gap = record.count_upper - record.objective_lower;
record.relative_gap = record.absolute_gap / max(1, record.count_upper);
record.is_proven = record.count_lower == record.count_upper;
if record.is_proven
    record.status = "proven";
else
    record.status = "lp_bound_with_seed";
end
end

function [solver_data, info] = add_matrix_window_cover_cuts( ...
        solver_data, ctx, apply_cuts)
info = struct('enabled', ctx.config.enable_window_cuts && apply_cuts, ...
    'candidate_count', 0, 'cut_count', 0, ...
    'start_hour', zeros(0, 1), 'end_hour', zeros(0, 1), ...
    'minimum_updates', zeros(0, 1));
if ~info.enabled || ctx.config.max_window_cuts == 0
    return
end

candidate_windows = zeros(0, 2);
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
    take = min(ctx.config.window_candidates_per_length, numel(starts));
    if take == numel(starts)
        chosen = 1:numel(starts);
    else
        [~, low_order] = sort(totals, 'ascend');
        [~, high_order] = sort(totals, 'descend');
        take_low = ceil(take / 2);
        take_high = floor(take / 2);
        chosen = [low_order(1:take_low), high_order(1:take_high)];
    end
    selected_starts = starts(chosen);
    selected_ends = ends(chosen);
    candidate_windows = [candidate_windows; ... %#ok<AGROW>
        selected_starts(:), selected_ends(:)];
end
candidate_windows = unique(candidate_windows, 'rows', 'stable');
info.candidate_count = size(candidate_windows, 1);
if isempty(candidate_windows)
    return
end

problem = solver_data.problem;
z_indices = solver_data.indices.O1_HB_change(:);
options = optimoptions('linprog', 'Display', 'none', ...
    'MaxTime', ctx.config.window_lp_max_time_s);
for i = 1:size(candidate_windows, 1)
    transitions = candidate_windows(i, 1):(candidate_windows(i, 2) - 1);
    objective = zeros(numel(problem.lb), 1);
    objective(z_indices(transitions)) = 1;
    try
        [~, lower_bound, exitflag] = linprog(objective, ...
            problem.Aineq, problem.bineq, problem.Aeq, problem.beq, ...
            problem.lb, problem.ub, options);
    catch
        continue
    end
    if exitflag > 0 && isfinite(lower_bound)
        required_updates = ceil(lower_bound - 1e-6);
        if required_updates >= 1
            row = sparse(1, numel(problem.lb));
            row(z_indices(transitions)) = -1;
            problem.Aineq(end + 1, :) = row;
            problem.bineq(end + 1, 1) = -required_updates;
            info.cut_count = info.cut_count + 1;
            info.start_hour(end + 1, 1) = candidate_windows(i, 1);
            info.end_hour(end + 1, 1) = candidate_windows(i, 2);
            info.minimum_updates(end + 1, 1) = required_updates;
        end
    end
    if mod(i, 10) == 0 || i == size(candidate_windows, 1)
        fprintf('[O1] Matrix window-cut LP: %d/%d, %d cuts.\n', ...
            i, size(candidate_windows, 1), info.cut_count);
    end
    if info.cut_count >= ctx.config.max_window_cuts
        break
    end
end
solver_data.problem = problem;
fprintf('[O1] Matrix window cuts: %d certified cuts from %d candidates.\n', ...
    info.cut_count, info.candidate_count);
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
        solver_data, boundary_problem, entries, initial, K, ctx, ...
        repair_strategy, mode, cost_cap)
repair_metadata = struct();
repair_elapsed_s = 0;
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

if ~isempty(fieldnames(start))
    count = round(sum(start.O1_HB_change));
    record = struct('objective_kind', "feasibility", ...
        'has_incumbent', true, 'objective_lower', 0, ...
        'objective_upper', 0, 'system_cost_lower', NaN, ...
        'system_cost_upper', start_cost, 'absolute_gap', 0, ...
        'relative_gap', 0, 'count_lower', NaN, 'count_upper', count, ...
        'is_proven', true, 'is_infeasible', false, 'exitflag', 1, ...
        'status', "cached_feasible", 'message', "", 'output', struct(), ...
        'solution', start, 'solve_backend', "cached_solution", ...
        'K_limit', K, 'elapsed_s', 0);
    source = "cached_start";
    return
end

source = "fixed_k";
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
repair_source_z = round(repair_source.O1_HB_change(:));
repair_source_key = z_source_pattern_key(repair_source_z);
if ctx.config.enable_start_repair
    skip_fixed_boundaries = false;
    z_layer_attempt_count = 0;
    z_layer_attempted_layer = NaN;
    local_window_progress = struct( ...
        'hours', {}, 'status', {}, 'attempts', {}, ...
        'fixed_z_tested', {});
    for i = 1:numel(entries)
        prior = entries(i).record;
        if entries(i).K ~= K
            continue
        end
        if ~isfield(prior, 'repair_strategy')
            continue
        end
        prior_strategy = string(prior.repair_strategy);
        same_strategy = prior_strategy == repair_strategy;
        legacy_strategy = ismember(prior_strategy, ...
            ["grid_relaxation_v3", "local_boundary_shift_v4"]);
        if ~same_strategy && ~legacy_strategy
            continue
        end
        if ~isfield(prior, 'z_source_key_v2') || ...
                ~isequal(double(prior.z_source_key_v2(:).'), ...
                repair_source_key)
            % 同一K在更近的可行上界出现后，旧迁移层相对于另一套
            % 源边界定义，不能复用其层号、尝试次数或局部扫描状态。
            continue
        end
        if isfield(prior, 'z_layer_attempt_count')
            z_layer_attempt_count = max(z_layer_attempt_count, ...
                double(prior.z_layer_attempt_count));
        elseif isfield(prior, 'z_relocation_layer')
            % 兼容首次加入分层搜索后已经保存的记录。
            z_layer_attempt_count = max(z_layer_attempt_count, 1);
        end
        if isfield(prior, 'z_relocation_layer')
            z_layer_attempted_layer = double(prior.z_relocation_layer);
        end
        if isfield(prior, 'fixed_boundary_complete') && ...
                isfield(prior, 'fixed_boundary_all_infeasible') && ...
                prior.fixed_boundary_complete && ...
                prior.fixed_boundary_all_infeasible
            skip_fixed_boundaries = true;
        end
        if legacy_strategy
            continue
        end
        if isfield(prior, 'local_window_progress')
            local_window_progress = prior.local_window_progress;
        elseif isfield(prior, 'local_window_candidate_counts')
            counts = prior.local_window_candidate_counts;
            known_hours = [24, 168, 720];
            known_limits = [48, 48, 24];
            for count_index = 1:size(counts, 1)
                match = find(known_hours == counts(count_index, 1), 1);
                if isempty(match)
                    continue
                end
                status = repmat("pending", known_limits(match), 1);
                attempts = zeros(known_limits(match), 1);
                completed = min(counts(count_index, 2), ...
                    known_limits(match));
                status(1:completed) = "infeasible";
                attempts(1:completed) = 1;
                local_window_progress(end + 1) = struct( ... %#ok<AGROW>
                    'hours', known_hours(match), 'status', status, ...
                    'attempts', attempts, ...
                    'fixed_z_tested', false(size(status)));
            end
        elseif isfield(prior, 'local_window_hours_completed')
            old_hours = prior.local_window_hours_completed(:);
            old_limits = [12, 12, 4];
            known_hours = [24, 168, 720];
            for old_index = 1:numel(old_hours)
                match = find(known_hours == old_hours(old_index), 1);
                if ~isempty(match)
                    status = repmat("pending", old_limits(match), 1);
                    status(:) = "infeasible";
                    local_window_progress(end + 1) = struct( ... %#ok<AGROW>
                        'hours', old_hours(old_index), 'status', status, ...
                        'attempts', ones(old_limits(match), 1), ...
                        'fixed_z_tested', false(size(status)));
                end
            end
        end
    end
    if ~isempty(local_window_progress) && ...
            ~isfield(local_window_progress, 'fixed_z_tested')
        for progress_index = 1:numel(local_window_progress)
            local_window_progress(progress_index).fixed_z_tested = ...
                false(size(local_window_progress(progress_index).status));
        end
    end
    % 分层z搜索的检查点会替换同一K的上一条记录。即使显式的
    % fixed_boundary_complete字段因此不在最新记录中，完整的
    % fixed_z_tested向量仍能证明固定边界预筛已经完成。
    for progress_index = 1:numel(local_window_progress)
        tested = logical(local_window_progress( ...
            progress_index).fixed_z_tested(:));
        if ~isempty(tested) && all(tested)
            skip_fixed_boundaries = true;
        end
        attempts = double(local_window_progress( ...
            progress_index).attempts(:));
        if any(attempts >= 4)
            % 能进入全年固定模式恢复，说明两个z-only引导目标均已
            % 完成；由尝试次数恢复该状态，避免检查点字段被覆盖。
            z_layer_attempt_count = max(z_layer_attempt_count, 2);
        end
    end
    checkpoint = struct('enabled', ctx.config.use_cache, ...
        'mode', string(mode), 'cost_cap', cost_cap, 'K', K, ...
        'repair_strategy', repair_strategy, ...
        'z_layer_attempt_count', z_layer_attempt_count, ...
        'z_layer_attempted_layer', z_layer_attempted_layer);
    repaired = repair_start(boundary_problem, repair_source, K, ctx, ...
        skip_fixed_boundaries, local_window_progress, checkpoint);
    if repaired.has_incumbent
        record = repaired;
        source = "repaired_start";
        return
    end
    if repaired.is_infeasible && ...
            repaired.status == "z_only_relaxation_infeasible"
        record = repaired;
        source = "z_only_relaxation";
        return
    end
    if ismember(repaired.status, [ ...
            "z_layer_relaxation_infeasible", ...
            "z_layer_relaxation_unknown", ...
            "z_layer_recovery_unknown", ...
            "z_layer_global_scan_unknown"])
        % z-only分层搜索已经完成一层；保留该层的严格结论或候选，
        % 下一次从缓存中的下一层继续，避免又退回相同的全年MIP。
        record = repaired;
        record.status = "repair_in_progress";
        source = "z_layer_progress";
        return
    end
    fprintf('[O1] repair K=%g failed: %s, %.1f s (%s)\n', ...
        K, repaired.status, repaired.elapsed_s, repaired.message);
    repair_metadata = repaired;
    repair_elapsed_s = repaired.elapsed_s;
    if repaired.status == "local_integer_unknown" && ...
            isfield(repaired, 'local_window_progress')
        defer_global_mip = false;
        for progress_index = 1:numel(repaired.local_window_progress)
            progress = repaired.local_window_progress(progress_index);
            status = string(progress.status(:));
            attempts = double(progress.attempts(:));
            unresolved = status ~= "infeasible";
            if any(unresolved) && min(attempts(unresolved)) < 4
                defer_global_mip = true;
                break
            end
        end
        if defer_global_mip
            record = repaired;
            record.status = "repair_in_progress";
            source = "repair_progress";
            return
        end
    end
end

problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.x0 = [];
relaxed_grid = zeros(0, 1);
relaxed_ael = zeros(0, 1);
indices = solver_data.indices;
% 固定K只需要首个可行点。使用完整零目标可避免距离目标拖慢根LP；
% 上一可行边界解虽超出当前K一个更新，但仍可作为MIP修复起点。
problem.f = zeros(size(problem.Aineq, 2), 1);
source_names = fieldnames(indices);
source_vector = zeros(numel(problem.lb), 1);
complete_source = true;
for source_index = 1:numel(source_names)
    source_name = source_names{source_index};
    if ~isfield(repair_source, source_name) || ...
            numel(repair_source.(source_name)) ~= ...
            numel(indices.(source_name))
        complete_source = false;
        break
    end
    source_vector(indices.(source_name)(:)) = ...
        repair_source.(source_name)(:);
end
if complete_source
    problem.x0 = source_vector;
end
if isfield(indices, 'u_purchase') && ...
        isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    % 净交换量可恢复原互斥解，避免无效方向分支。
    relaxed_grid = indices.u_purchase(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_grid);
end
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    % AEL方向由在线台数差恢复，减少无效二元分支。
    relaxed_ael = indices.I_AEL_up(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_ael);
end

record = struct('objective_kind', "feasibility", ...
    'has_incumbent', false, 'objective_lower', NaN, ...
    'objective_upper', NaN, 'system_cost_lower', NaN, ...
    'system_cost_upper', NaN, 'absolute_gap', NaN, ...
    'relative_gap', NaN, 'count_lower', NaN, 'count_upper', NaN, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "not_run", 'message', "", 'output', struct(), ...
    'solution', struct(), 'solve_backend', "intlinprog_matrix_zero_objective", ...
    'K_limit', K, 'elapsed_s', NaN);
if complete_source
    record.solve_backend = record.solve_backend + "_near_feasible_start";
end
if ~isempty(relaxed_grid)
    record.solve_backend = record.solve_backend + "_grid_relaxed";
end
if ~isempty(relaxed_ael)
    record.solve_backend = record.solve_backend + "_ael_direction_relaxed";
end
started = tic;
try
    [x, fval, exitflag, output] = intlinprog(problem);
    if ~isempty(x) && ...
            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
        [x, recovery_flag, recovery_output] = ...
            recover_direction_binaries(problem, x, indices, 60);
        if recovery_flag <= 0 || isempty(x)
            exitflag = 0;
            fval = NaN;
            output = recovery_output;
        else
            fval = problem.f.' * x;
        end
    end
catch exception
    record.elapsed_s = toc(started) + repair_elapsed_s;
    record.status = "solver_error";
    record.message = string(exception.message);
    metadata_names = {'grid_repair_complete', 'grid_repair_free_count', ...
        'fixed_boundary_complete', 'fixed_boundary_all_infeasible', ...
        'local_window_candidate_counts', 'local_window_progress'};
    for metadata_index = 1:numel(metadata_names)
        name = metadata_names{metadata_index};
        if isfield(repair_metadata, name)
            record.(name) = repair_metadata.(name);
        end
    end
    return
end
record.elapsed_s = toc(started) + repair_elapsed_s;
metadata_names = {'grid_repair_complete', 'grid_repair_free_count', ...
    'fixed_boundary_complete', 'fixed_boundary_all_infeasible', ...
    'local_window_candidate_counts', 'local_window_progress'};
for metadata_index = 1:numel(metadata_names)
    name = metadata_names{metadata_index};
    if isfield(repair_metadata, name)
        record.(name) = repair_metadata.(name);
    end
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
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    index = indices.(name);
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

function record = repair_start( ...
        problem, source, K, ctx, skip_fixed_boundaries, ...
        local_window_progress, checkpoint)
if nargin < 5
    skip_fixed_boundaries = false;
end
if nargin < 6
    local_window_progress = struct( ...
        'hours', {}, 'status', {}, 'attempts', {}, ...
        'fixed_z_tested', {});
end
if nargin < 7
    checkpoint = struct('enabled', false);
end
record = struct('has_incumbent', false);
if ~isstruct(source) || ~isfield(source, 'HB_load')
    return
end
problem.Constraints.O1_update_limit = ctx.update_count <= K;
source_load = source.HB_load(:);
if isfield(source, 'O1_HB_setpoint') && ...
        numel(source.O1_HB_setpoint) == ctx.T
    source_setpoint = source.O1_HB_setpoint(:);
else
    source_setpoint = source_load;
end
source_change = abs([source_setpoint(2:end); source_setpoint(1)] ...
    - source_setpoint);
[~, anchor] = max(source_change);
first_hour = mod(anchor, ctx.T) + 1;
order = [first_hour:ctx.T, 1:first_hour - 1];
ordered_setpoint = source_setpoint(order);
change_tolerance = max(1e-9, ctx.config.change_tolerance);
segment_starts = [1; ...
    find(abs(diff(ordered_setpoint)) > change_tolerance) + 1];
segment_ends = [segment_starts(2:end) - 1; ctx.T];
lengths = segment_ends - segment_starts + 1;
source_segment_count = numel(lengths);
ordered_load = source_load(order);
averages = zeros(numel(lengths), 1);
for i = 1:numel(lengths)
    averages(i) = mean(ordered_load(segment_starts(i):segment_ends(i)));
end
source_next_segment = [2:numel(lengths), 1];
source_merge_cost = lengths .* lengths(source_next_segment) ...
    ./ (lengths + lengths(source_next_segment)) ...
    .* (averages - averages(source_next_segment)).^2;
[~, source_alternatives] = sort(source_merge_cost, 'ascend');
source_boundary_hours = order(segment_ends);
source_z = zeros(ctx.T, 1);
source_z(source_boundary_hours) = 1;

target_segments = 1;
if K >= 2
    target_segments = min(K, numel(lengths));
end
fixed_integer_attempted = false;
if target_segments == numel(lengths) - 1
    candidate_changes = repmat(source_z, 1, numel(source_alternatives));
    for alternative = 1:numel(source_alternatives)
        boundary = source_boundary_hours(source_alternatives(alternative));
        candidate_changes(boundary, alternative) = 0;
    end
    repair_problem = problem;
    repair_problem.Objective = ctx.system_cost_usd;
    record = solve_fixed_integer_repair( ...
        repair_problem, source, K, ctx, candidate_changes, ...
        skip_fixed_boundaries, local_window_progress, checkpoint);
    fixed_integer_attempted = true;
    if record.has_incumbent && record.count_upper <= K
        record.K_limit = K;
        record.status = "repaired_feasible";
        fprintf('[O1] repair K=%g selected from all existing boundaries.\n', K);
        return
    end
end
% 优先合并负荷最接近的相邻平台，保留原调度的时间结构。
while numel(lengths) > target_segments
    merge_cost = lengths(1:end-1) .* lengths(2:end) ...
        ./ (lengths(1:end-1) + lengths(2:end)) ...
        .* (averages(1:end-1) - averages(2:end)).^2;
    [~, merge_at] = min(merge_cost);
    merged_length = lengths(merge_at) + lengths(merge_at + 1);
    averages(merge_at) = ...
        (lengths(merge_at) * averages(merge_at) + ...
        lengths(merge_at + 1) * averages(merge_at + 1)) ...
        / merged_length;
    lengths(merge_at) = merged_length;
    segment_ends(merge_at) = segment_ends(merge_at + 1);
    lengths(merge_at + 1) = [];
    averages(merge_at + 1) = [];
    segment_starts(merge_at + 1) = [];
    segment_ends(merge_at + 1) = [];
end
segment_count = numel(lengths);
candidate_z = zeros(ctx.T, 1);
if segment_count > 1
    candidate_z(order(segment_ends)) = 1;
end

% 非相邻K探针不能只依赖把上一可行解连续贪心合并后的单一模式。
% 用两个K边界种子进入全年连续松弛分段与z层搜索；所有候选最终仍
% 经原模型的严格整数恢复，因此这里只改变搜索顺序，不改变约束。
if ~fixed_integer_attempted && target_segments < source_segment_count - 1
    repair_problem = problem;
    repair_problem.Objective = ctx.system_cost_usd;
    % 单删除列并不是K可行候选，而是给q层提供全部旧边界的合并
    % 失真排序；q层自身的sum(z)<=K仍决定实际删除多少个边界。
    direct_candidates = repmat(source_z, 1, numel(source_alternatives));
    for alternative = 1:numel(source_alternatives)
        boundary = source_boundary_hours(source_alternatives(alternative));
        direct_candidates(boundary, alternative) = 0;
    end
    record = solve_fixed_integer_repair( ...
        repair_problem, source, K, ctx, direct_candidates, ...
        skip_fixed_boundaries, local_window_progress, checkpoint);
    fixed_integer_attempted = true;
    if record.has_incumbent && record.count_upper <= K
        record.K_limit = K;
        record.status = "repaired_feasible";
        fprintf('[O1] direct probe K=%g recovered a strict schedule.\n', K);
        return
    end
end

repair_problem = problem;
% 只固定平台边界，平台负荷由系统约束共同决定。
repair_problem.Constraints.O1_repair_changes = ctx.z == candidate_z;
repair_problem.Objective = ctx.system_cost_usd;
candidate_start = source;
candidate_start.O1_HB_change = reshape(candidate_z, size(source.HB_load));
if ~fixed_integer_attempted
    record = solve_fixed_integer_repair( ...
        repair_problem, candidate_start, K, ctx);
end
if ~record.has_incumbent && ~fixed_integer_attempted
    repair_elapsed_s = record.elapsed_s;
    repair_metadata = record;
    fprintf(['[O1] fixed-integer repair K=%g failed: %s, %.1f s ', ...
        '(%s)\n'], K, record.status, record.elapsed_s, record.message);
    record = solve_problem(repair_problem, ctx.repair_options, ...
        "feasibility", struct(), ctx.system_cost_usd);
    record.elapsed_s = record.elapsed_s + repair_elapsed_s;
    metadata_names = {'grid_repair_complete', 'grid_repair_free_count', ...
        'fixed_boundary_complete', 'fixed_boundary_all_infeasible', ...
        'local_window_candidate_counts', 'local_window_progress'};
    for i = 1:numel(metadata_names)
        name = metadata_names{i};
        if isfield(repair_metadata, name)
            record.(name) = repair_metadata.(name);
        end
    end
end
if record.has_incumbent
    record.solution = add_change_indicators(record.solution, ctx);
    record.count_upper = round(sum(record.solution.O1_HB_change));
    record.K_limit = K;
    record.status = "repaired_feasible";
    if record.count_upper > K
        record.has_incumbent = false;
        record.status = "invalid_repair";
        if isfield(record, 'solver_count')
            fprintf(['[O1] invalid repair diagnostics: solverK=%g, ', ...
                'recountK=%g, inactive drift=%.3g, ', ...
                'link violation=%.3g, z residual=%.3g\n'], ...
                record.solver_count, record.count_upper, ...
                record.max_inactive_drift, record.max_link_violation, ...
                record.max_z_residual);
        end
    end
end
end

function record = solve_fixed_integer_repair( ...
        problem, initial, K, ctx, change_candidates, ...
        skip_fixed_candidates, local_window_progress, checkpoint)
if nargin < 5
    change_candidates = zeros(ctx.T, 0);
end
if nargin < 6
    skip_fixed_candidates = false;
end
if nargin < 7
    local_window_progress = struct( ...
        'hours', {}, 'status', {}, 'attempts', {}, ...
        'fixed_z_tested', {});
end
if nargin < 8
    checkpoint = struct('enabled', false);
end
direct_global_z_scan = isfield(checkpoint, 'z_layer_attempt_count') && ...
    checkpoint.z_layer_attempt_count >= 2 && ...
    isfield(checkpoint, 'z_layer_attempted_layer') && ...
    checkpoint.z_layer_attempted_layer == 0;
if direct_global_z_scan
    skip_fixed_candidates = true;
end
record = struct('objective_kind', "feasibility", ...
    'has_incumbent', false, 'objective_lower', NaN, ...
    'objective_upper', NaN, 'system_cost_lower', NaN, ...
    'system_cost_upper', NaN, 'absolute_gap', NaN, ...
    'relative_gap', NaN, 'count_lower', NaN, 'count_upper', NaN, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "fixed_integer_unknown", 'message', "", ...
    'output', struct(), 'solution', struct(), ...
    'solve_backend', "linprog_fixed_integer", 'K_limit', K, ...
    'elapsed_s', NaN);
if ~isempty(local_window_progress)
    record.local_window_progress = local_window_progress;
end
started = tic;
try
    solver_problem = prob2struct(problem, initial, 'Solver', 'intlinprog');
    indices = varindex(problem);
    relaxed_grid = zeros(0, 1);
    relaxed_ael = zeros(0, 1);
    if isfield(indices, 'u_purchase') && ...
            isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
            all(ctx.model.context.C_purchase(:) >= ...
            ctx.model.context.C_sell(:) - 1e-12)
        % 净购售电可恢复互斥方向，修复阶段无需对方向分支。
        relaxed_grid = indices.u_purchase(:);
        solver_problem.intcon = setdiff( ...
            solver_problem.intcon(:), relaxed_grid);
    end
    if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
        % 在线台数确定启停方向，候选解再由原模型LP恢复。
        relaxed_ael = indices.I_AEL_up(:);
        solver_problem.intcon = setdiff( ...
            solver_problem.intcon(:), relaxed_ael);
    end
    fixed = solver_problem.intcon(:);
    if isempty(change_candidates)
        candidate_count = 1;
    else
        if size(change_candidates, 1) ~= ctx.T
            error('O1:bad_repair_candidates', ...
                'Repair candidates must contain one row per time step.');
        end
        z_indices = indices.O1_HB_change(:);
        fixed = setdiff(fixed, z_indices);
        candidate_count = size(change_candidates, 2);
    end
    if candidate_count > 1
        source_z = round(solver_problem.x0(z_indices));
        source_key = z_source_pattern_key(source_z);
        record.z_source_key_v2 = source_key;
    else
        source_z = zeros(0, 1);
        source_key = zeros(1, 3);
    end
    variable_lower = solver_problem.lb;
    variable_upper = solver_problem.ub;
    fixed_values = round(solver_problem.x0(fixed));
    solver_problem.lb(fixed) = fixed_values;
    solver_problem.ub(fixed) = fixed_values;
    options = optimoptions('linprog', 'Display', 'none', ...
        'MaxTime', min(60, ctx.config.repair_max_time_s));
    x = [];
    exitflag = NaN;
    output = struct();
    all_infeasible = true;
    fixed_precheck_count = 0;
    % 局部窗口已多轮无解时，不再局限于“删除一个旧边界”。先求
    % 全年最小计数连续松弛，再把其设定值轨迹重分段为恰好K段。
    % 这里只生成候选；每个候选仍须通过原约束的严格整数恢复。
    % 连续轨迹分段只用于真正的大跨度K任务；靠近可行上界时，
    % 相邻源解的边界迁移更强。触发阈值按当前源解规模归一化，
    % 因而不依赖某个年份的手工K列表。
    source_update_count = sum(source_z);
    update_gap = source_update_count - K;
    use_global_segmentation = update_gap >= ...
        max(2, ceil(0.05 * max(1, source_update_count)));
    for progress_index = 1:numel(local_window_progress)
        if any(local_window_progress(progress_index).attempts(:) >= 3)
            use_global_segmentation = true;
            break
        end
    end
    cached_relaxations = fixed_point_store(ctx.point_cache_file, ...
        ctx.signature, "load", "global_relaxation", Inf, struct());
    % 缓存的全年连续松弛仍用于分层证书，但不再强制每个新K先跑
    % 17个启发式分段；相邻可行K的z迁移层已证明更直接有效。
    if isempty(x) && candidate_count > 1 && use_global_segmentation && K > 0
        relaxed_problem = solver_problem;
        relaxed_problem.lb = variable_lower;
        relaxed_problem.ub = variable_upper;
        relaxed_problem.f(:) = 0;
        relaxed_problem.f(z_indices) = 1;
        relaxed_options = optimoptions('linprog', 'Display', 'none', ...
            'MaxTime', min(300, ctx.config.repair_max_time_s));
        global_started = tic;
        global_x = [];
        global_value = NaN;
        global_flag = NaN;
        global_output = struct();
        cached_index = [];
        for relaxation_index = numel(cached_relaxations):-1:1
            cached_record = cached_relaxations(relaxation_index).record;
            if isfield(cached_record, 'raw_x') && ...
                    isfield(cached_record, 'objective_lower') && ...
                    cached_record.objective_lower <= K + 1e-7
                cached_index = relaxation_index;
                break
            end
        end
        if ~isempty(cached_index) && ...
                isfield(cached_relaxations(cached_index).record, 'raw_x') && ...
                numel(cached_relaxations(cached_index).record.raw_x) == ...
                numel(relaxed_problem.lb)
            global_x = cached_relaxations(cached_index).record.raw_x;
            global_value = cached_relaxations( ...
                cached_index).record.objective_lower;
            global_flag = 1;
            global_output = struct('message', ...
                "Loaded cached global count relaxation.");
        else
            [global_x, global_value, global_flag, global_output] = linprog( ...
                relaxed_problem.f, relaxed_problem.Aineq, ...
                relaxed_problem.bineq, relaxed_problem.Aeq, ...
                relaxed_problem.beq, relaxed_problem.lb, ...
                relaxed_problem.ub, relaxed_options);
            if ~isempty(global_x) && global_flag > 0
                relaxation_record = struct('raw_x', global_x, ...
                    'objective_lower', global_value, ...
                    'status', "global_relaxation_cached", ...
                    'has_incumbent', true);
                relaxation_entry = struct('mode', "global_relaxation", ...
                    'cost_cap', Inf, 'K', K, ...
                    'record', relaxation_record, ...
                    'source', "global_count_relaxation");
                fixed_point_store(ctx.point_cache_file, ctx.signature, ...
                    "append", "global_relaxation", Inf, relaxation_entry);
            end
        end
        fprintf(['[O1] global count relaxation for K=%g: ', ...
            'exitflag=%g, value=%.6g, %.1f s.\n'], K, global_flag, ...
            global_value, toc(global_started));
        pattern_search_cached = false;
        if ~isempty(cached_index)
            cached_record = cached_relaxations(cached_index).record;
            if isfield(cached_record, 'infeasible_pattern_K_v2')
                pattern_search_cached = ismember(K, ...
                    cached_record.infeasible_pattern_K_v2(:));
            end
        end
        if pattern_search_cached
            fprintf(['[O1] Reusing certified failure of all global ', ...
                'segmented patterns for K=%g.\n'], K);
        elseif ~isempty(global_x)
            global_z = global_x(z_indices);
            [~, top_order] = sort(global_z, 'descend');
            top_pattern = zeros(ctx.T, 1);
            top_pattern(top_order(1:min(K, ctx.T))) = 1;

            relaxed_setpoint = global_x(indices.O1_HB_setpoint(:));
            setpoint_change = abs([relaxed_setpoint(2:end); ...
                relaxed_setpoint(1)] - relaxed_setpoint);
            [~, anchor] = max(setpoint_change);
            first_hour = mod(anchor, ctx.T) + 1;
            ordered_hours = [first_hour:ctx.T, 1:first_hour - 1].';
            segment_lengths = ones(ctx.T, 1);
            segment_averages = relaxed_setpoint(ordered_hours);
            segment_ends = (1:ctx.T).';
            while numel(segment_lengths) > K
                merge_cost = segment_lengths(1:end-1) .* ...
                    segment_lengths(2:end) ./ ...
                    (segment_lengths(1:end-1) + ...
                    segment_lengths(2:end)) .* ...
                    (segment_averages(1:end-1) - ...
                    segment_averages(2:end)).^2;
                [~, merge_at] = min(merge_cost);
                merged_length = segment_lengths(merge_at) + ...
                    segment_lengths(merge_at + 1);
                segment_averages(merge_at) = ...
                    (segment_lengths(merge_at) * ...
                    segment_averages(merge_at) + ...
                    segment_lengths(merge_at + 1) * ...
                    segment_averages(merge_at + 1)) / merged_length;
                segment_lengths(merge_at) = merged_length;
                segment_ends(merge_at) = segment_ends(merge_at + 1);
                segment_lengths(merge_at + 1) = [];
                segment_averages(merge_at + 1) = [];
                segment_ends(merge_at + 1) = [];
            end
            segmented_pattern = zeros(ctx.T, 1);
            segmented_pattern(ordered_hours(segment_ends)) = 1;

            minimax_ends = minimax_piecewise_constant_ends( ...
                relaxed_setpoint(ordered_hours), K);
            minimax_pattern = zeros(ctx.T, 1);
            minimax_pattern(ordered_hours(minimax_ends)) = 1;
            phase_patterns = zeros(ctx.T, 12);
            phase_first_hours = round(linspace(1, ctx.T + 1, 13));
            phase_first_hours = phase_first_hours(1:12);
            for phase_index = 1:numel(phase_first_hours)
                phase_first = phase_first_hours(phase_index);
                phase_order = [phase_first:ctx.T, 1:phase_first - 1].';
                phase_ends = minimax_piecewise_constant_ends( ...
                    relaxed_setpoint(phase_order), K);
                phase_patterns(phase_order(phase_ends), phase_index) = 1;
            end

            ordered_setpoint = relaxed_setpoint(ordered_hours);
            variation = abs([diff(ordered_setpoint); ...
                ordered_setpoint(1) - ordered_setpoint(end)]);
            cumulative_variation = cumsum(variation);
            variation_pattern = zeros(ctx.T, 1);
            if cumulative_variation(end) > 0
                targets = (1:K).' * cumulative_variation(end) / K;
                variation_ends = arrayfun(@(target) find( ...
                    cumulative_variation >= target, 1), targets);
                variation_ends = unique(variation_ends, 'stable');
                if numel(variation_ends) < K
                    [~, variation_order] = sort(variation, 'descend');
                    fill = setdiff(variation_order, variation_ends, ...
                        'stable');
                    variation_ends = [variation_ends; ...
                        fill(1:(K - numel(variation_ends)))];
                end
                variation_pattern(ordered_hours(variation_ends)) = 1;
            end

            source_pattern = source_z;
            source_boundaries = find(source_pattern > 0.5);
            if numel(source_boundaries) > K
                [~, remove_order] = sort(global_z(source_boundaries), ...
                    'ascend');
                source_pattern(source_boundaries( ...
                    remove_order(1:(numel(source_boundaries) - K)))) = 0;
            end
            global_patterns = unique([top_pattern, segmented_pattern, ...
                minimax_pattern, phase_patterns, variation_pattern, ...
                source_pattern].', ...
                'rows', 'stable').';
            patterns_all_infeasible = true;
            for pattern_index = 1:size(global_patterns, 2)
                [candidate_x, pattern_flag, pattern_output, ...
                    projection_index] = solve_projected_ael_pattern( ...
                    solver_problem, indices, global_patterns(:, pattern_index), ...
                    variable_lower, variable_upper, ctx, 90);
                exitflag = pattern_flag;
                output = pattern_output;
                patterns_all_infeasible = patterns_all_infeasible && ...
                    pattern_flag == -2 && isempty(candidate_x);
                fprintf(['[O1] global segmented pattern %d/%d: ', ...
                    'projection=%d, exitflag=%g.\n'], pattern_index, ...
                    size(global_patterns, 2), projection_index, exitflag);
                if ~isempty(candidate_x)
                    x = candidate_x;
                    record.solve_backend = ...
                        "linprog_global_segmented_projected_ael";
                    break
                end
            end
            if isempty(x) && patterns_all_infeasible && ...
                    ~isempty(cached_index)
                cached_entry = cached_relaxations(cached_index);
                cached_record = cached_entry.record;
                if isfield(cached_record, 'infeasible_pattern_K_v2')
                    completed_K = cached_record.infeasible_pattern_K_v2(:);
                else
                    completed_K = zeros(0, 1);
                end
                cached_record.infeasible_pattern_K_v2 = unique( ...
                    [completed_K; K], 'stable');
                cached_entry.record = cached_record;
                fixed_point_store(ctx.point_cache_file, ctx.signature, ...
                    "append", cached_entry.mode, ...
                    cached_entry.cost_cap, cached_entry);
            end
        else
            exitflag = global_flag;
            output = global_output;
        end
    end
    % 三类确定性局部投影均完成后，求解仅保留HB边界z为整数的
    % 全年松弛。按照相对上一可行解“新增边界”的数量分层，先
    % 完整判定最接近源解的层；这不会删减原可行域，且可避免
    % 求解器反复在同一个未闭合的根节点上消耗全部时限。
    run_z_only_relaxation = false;
    if isempty(local_window_progress) && candidate_count > 1
        run_z_only_relaxation = true;
    end
    for progress_index = 1:numel(local_window_progress)
        progress = local_window_progress(progress_index);
        status = string(progress.status(:));
        attempts = double(progress.attempts(:));
        unresolved = status ~= "infeasible";
        if any(unresolved) && min(attempts(unresolved)) >= 3
            run_z_only_relaxation = true;
            break
        end
    end
    next_relocation_layer = 0;
    for relaxation_index = numel(cached_relaxations):-1:1
        candidate_record = cached_relaxations(relaxation_index).record;
        if isfield(candidate_record, 'raw_x') && ...
                isfield(candidate_record, 'objective_lower') && ...
                candidate_record.objective_lower <= K + 1e-7 && ...
                isfield(candidate_record, ...
                'infeasible_z_relocation_layers_v2')
            excluded = double(candidate_record. ...
                ('infeasible_z_relocation_layers_v2'));
            source_rows = excluded(:, 1) == K & ...
                all(excluded(:, 2:4) == source_key, 2);
            excluded_layers = excluded(source_rows, 5);
            while ismember(next_relocation_layer, excluded_layers)
                next_relocation_layer = next_relocation_layer + 1;
            end
            break
        end
    end
    if next_relocation_layer > 0
        % q=0闭合后，局部删除候选已全部标记不可行；后续迁移层
        % 本身就是新的未决搜索，不能再依赖局部候选触发条件。
        run_z_only_relaxation = true;
    end
    same_z_layer = isfield(checkpoint, 'z_layer_attempted_layer') && ...
        isfinite(checkpoint.z_layer_attempted_layer) && ...
        checkpoint.z_layer_attempted_layer == next_relocation_layer;
    if isfield(checkpoint, 'z_layer_attempt_count') && ...
            checkpoint.z_layer_attempt_count >= 2 && same_z_layer
        fprintf(['[O1] z-only relocation layer K=%g already tried ', ...
            '%d guided objectives for q=%g; continuing with ', ...
            'fixed-pattern integer recovery.\n'], K, ...
            checkpoint.z_layer_attempt_count, next_relocation_layer);
        run_z_only_relaxation = false;
    end
    if isempty(x) && candidate_count > 1 && run_z_only_relaxation
        z_only_problem = solver_problem;
        z_only_problem.lb = variable_lower;
        z_only_problem.ub = variable_upper;
        source_positions = find(source_z > 0.5);
        new_positions = find(source_z < 0.5);

        % 已严格排除的层写在全年连续松弛记录中。每一行分别为
        % [目标K, 源边界数, 源位置和, 源位置平方和, 新增边界数]，
        % 因而换年份、换K或换可行源解时都不会误复用。
        z_layer_entries = fixed_point_store(ctx.point_cache_file, ...
            ctx.signature, "load", "global_relaxation", Inf, struct());
        z_layer_cache_index = [];
        excluded_layers = zeros(0, 1);
        for relaxation_index = numel(z_layer_entries):-1:1
            candidate_record = z_layer_entries(relaxation_index).record;
            if isfield(candidate_record, 'raw_x') && ...
                    isfield(candidate_record, 'objective_lower') && ...
                    candidate_record.objective_lower <= K + 1e-7
                z_layer_cache_index = relaxation_index;
                if isfield(candidate_record, ...
                    'infeasible_z_relocation_layers_v2')
                    all_layers = double(candidate_record. ...
                        ('infeasible_z_relocation_layers_v2'));
                    source_rows = all_layers(:, 1) == K & ...
                        all(all_layers(:, 2:4) == source_key, 2);
                    excluded_layers = all_layers(source_rows, 5);
                end
                break
            end
        end
        relocation_layer = 0;
        while ismember(relocation_layer, excluded_layers)
            relocation_layer = relocation_layer + 1;
        end
        if relocation_layer > K
            % 0:K各层的并集就是全部K边界模式；只有这种情形才构成
            % 原整数模型的全局不可行证明。
            record.is_infeasible = true;
            record.is_proven = true;
            record.status = "z_only_relaxation_infeasible";
            record.solve_backend = "intlinprog_z_layer_exhaustive";
            record.message = "All z relocation layers are infeasible.";
            record.elapsed_s = toc(started);
            return
        end

        if relocation_layer == 0
            z_only_problem.lb(z_indices(new_positions)) = 0;
            z_only_problem.ub(z_indices(new_positions)) = 0;
            z_only_problem.intcon = z_indices(source_positions);
        else
            relocation_row = sparse(1, numel(z_only_problem.f));
            relocation_row(z_indices(new_positions)) = 1;
            z_only_problem.Aeq = [z_only_problem.Aeq; relocation_row];
            z_only_problem.beq = [z_only_problem.beq; relocation_layer];
            z_only_problem.intcon = z_indices;
        end
        z_only_problem.f(:) = 0;
        z_layer_attempt_count = 0;
        if isfield(checkpoint, 'z_layer_attempt_count') && ...
                isfield(checkpoint, 'z_layer_attempted_layer') && ...
                checkpoint.z_layer_attempted_layer == relocation_layer
            z_layer_attempt_count = checkpoint.z_layer_attempt_count;
        end
        if z_layer_attempt_count >= 1
            % 首次零目标未找到可行点后，以相邻平台合并失真排序
            % 引导分支。目标只影响可行点搜索顺序，不改变任何约束。
            deletion_rank = zeros(ctx.T, 1);
            for candidate = 1:candidate_count
                removed = find(source_z > 0.5 & ...
                    change_candidates(:, candidate) < 0.5, 1);
                if ~isempty(removed)
                    deletion_rank(removed) = candidate;
                end
            end
            scale = max(1, max(deletion_rank));
            z_only_problem.f(z_indices(source_positions)) = ...
                -deletion_rank(source_positions) / scale;
            fprintf(['[O1] z-only relocation layer K=%g uses ', ...
                'merge-distortion guidance (attempt %d).\n'], ...
                K, z_layer_attempt_count + 1);
        end
        z_only_problem.x0 = [];
        z_only_problem.options = optimoptions(ctx.repair_options, ...
            'MaxTime', min(600, ctx.config.repair_max_time_s), ...
            'MaxFeasiblePoints', 1, 'Display', 'iter');
        z_only_started = tic;
        [z_only_x, ~, z_only_flag, z_only_output] = ...
            intlinprog(z_only_problem);
        fprintf(['[O1] z-only relocation layer K=%g, q=%g: ', ...
            'exitflag=%g, incumbent=%d, %.1f s.\n'], K, ...
            relocation_layer, z_only_flag, ~isempty(z_only_x), ...
            toc(z_only_started));
        exitflag = z_only_flag;
        output = z_only_output;
        if z_only_flag == -2
            record.exitflag = z_only_flag;
            record.output = z_only_output;
            record.is_infeasible = false;
            record.is_proven = false;
            record.status = "z_layer_relaxation_infeasible";
            record.solve_backend = "intlinprog_z_relocation_layer";
            record.z_relocation_layer = relocation_layer;
            record.z_layer_attempt_count = z_layer_attempt_count + 1;
            if isfield(z_only_output, 'message')
                record.message = string(z_only_output.message);
            end
            if ~isempty(z_layer_cache_index)
                cached_entry = z_layer_entries(z_layer_cache_index);
                cached_record = cached_entry.record;
                if isfield(cached_record, ...
                        'infeasible_z_relocation_layers_v2')
                    completed_layers = double(cached_record. ...
                        ('infeasible_z_relocation_layers_v2'));
                else
                    completed_layers = zeros(0, 5);
                end
                cached_record.infeasible_z_relocation_layers_v2 = ...
                    unique([completed_layers; K, source_key, ...
                    relocation_layer], ...
                    'rows', 'stable');
                cached_entry.record = cached_record;
                fixed_point_store(ctx.point_cache_file, ctx.signature, ...
                    "append", cached_entry.mode, ...
                    cached_entry.cost_cap, cached_entry);
            end
            record.elapsed_s = toc(started);
            return
        elseif ~isempty(z_only_x)
            z_only_pattern = round(z_only_x(z_indices));
            [candidate_x, z_recovery_flag, z_recovery_output, ...
                projection_index] = solve_projected_ael_pattern( ...
                solver_problem, indices, z_only_pattern, ...
                variable_lower, variable_upper, ctx, 90);
            exitflag = z_recovery_flag;
            output = z_recovery_output;
            fprintf(['[O1] z-only pattern integer-AEL recovery: ', ...
                'projection=%d, exitflag=%g.\n'], ...
                projection_index, z_recovery_flag);
            if ~isempty(candidate_x)
                x = candidate_x;
                record.solve_backend = ...
                    "intlinprog_z_only_then_projected_ael";
            else
                record.status = "z_layer_recovery_unknown";
                record.z_relocation_layer = relocation_layer;
                record.z_layer_attempt_count = z_layer_attempt_count + 1;
                record.z_pattern_candidate = z_only_pattern;
                record.solve_backend = ...
                    "intlinprog_z_layer_then_projected_ael";
                record.elapsed_s = toc(started);
                return
            end
        else
            record.status = "z_layer_relaxation_unknown";
            record.z_relocation_layer = relocation_layer;
            record.z_layer_attempt_count = z_layer_attempt_count + 1;
            record.solve_backend = "intlinprog_z_relocation_layer";
            if isfield(z_only_output, 'message')
                record.message = string(z_only_output.message);
            end
            record.elapsed_s = toc(started);
            return
        end
    end
    if isempty(x) && ~skip_fixed_candidates
        % 逐一完成全部单边界删除的连续重平衡预筛；每个候选均保持
        % 原离散运行状态不变，因此比直接进入局部MIP便宜得多。
        fixed_attempt_limit = candidate_count;
        for candidate = 1:fixed_attempt_limit
            lower = solver_problem.lb;
            upper = solver_problem.ub;
            if ~isempty(change_candidates)
                values = change_candidates(:, candidate);
                lower(z_indices) = values;
                upper(z_indices) = values;
            end
            [candidate_x, ~, exitflag, output] = linprog( ...
                solver_problem.f, solver_problem.Aineq, ...
                solver_problem.bineq, solver_problem.Aeq, ...
                solver_problem.beq, lower, upper, options);
            fixed_precheck_count = candidate;
            all_infeasible = all_infeasible && exitflag == -2;
            if mod(candidate, 10) == 0 || candidate == candidate_count || ...
                    (exitflag > 0 && ~isempty(candidate_x))
                fprintf('[O1] boundary LP precheck: %d/%d, exitflag=%g.\n', ...
                    candidate, candidate_count, exitflag);
            end
            if exitflag > 0 && ~isempty(candidate_x)
                x = candidate_x;
                break
            end
        end
        if fixed_precheck_count < 10
            fprintf('[O1] boundary LP precheck: %d/%d.\n', ...
                fixed_precheck_count, candidate_count);
        end
    end

    % 分层扩大局部状态释放范围，再进入全局修复。
    if isempty(x) && candidate_count > 1
        record.fixed_boundary_complete = skip_fixed_candidates || ...
            fixed_precheck_count == candidate_count;
        record.fixed_boundary_all_infeasible = ...
            record.fixed_boundary_complete && all_infeasible;
        source_z = round(solver_problem.x0(z_indices));
        boundaries = find(source_z > 0.5);
        local_all_infeasible = true;
        % 对全部边界执行周尺度局部搜索；已缓存的固定边界结果会跳过。
        % 周尺度可显著减少自由HB边界数，再由AEL松弛模型生成候选分段。
        window_hours = 168;
        window_candidates = candidate_count;
        window_time_s = ctx.config.repair_max_time_s;
        for window_index = 1:numel(window_hours)
            buffer = window_hours(window_index);
            local_count = min(window_candidates(window_index), ...
                candidate_count);
            progress_row = find([local_window_progress.hours] == buffer, 1);
            if isempty(progress_row)
                if direct_global_z_scan
                    candidate_status = repmat("unknown", local_count, 1);
                    candidate_attempts = 3 * ones(local_count, 1);
                    fixed_z_tested = true(local_count, 1);
                else
                    candidate_status = repmat("pending", local_count, 1);
                    candidate_attempts = zeros(local_count, 1);
                    fixed_z_tested = false(local_count, 1);
                end
                local_window_progress(end + 1) = struct( ... %#ok<AGROW>
                    'hours', buffer, 'status', candidate_status, ...
                    'attempts', candidate_attempts, ...
                    'fixed_z_tested', fixed_z_tested);
                progress_row = numel(local_window_progress);
            else
                candidate_status = string( ...
                    local_window_progress(progress_row).status(:));
                candidate_attempts = double( ...
                    local_window_progress(progress_row).attempts(:));
                fixed_z_tested = logical(local_window_progress( ...
                    progress_row).fixed_z_tested(:));
                if numel(candidate_status) < local_count
                    candidate_status(end + 1:local_count, 1) = "pending";
                    candidate_attempts(end + 1:local_count, 1) = 0;
                    fixed_z_tested(end + 1:local_count, 1) = false;
                else
                    candidate_status = candidate_status(1:local_count);
                    candidate_attempts = candidate_attempts(1:local_count);
                    fixed_z_tested = fixed_z_tested(1:local_count);
                end
            end
            if isfield(checkpoint, 'z_layer_attempt_count') && ...
                    checkpoint.z_layer_attempt_count >= 2
                % 早期“infeasible”只对应局部窗口。要形成q=0的全年
                % 证书，仍需释放全部连续/AEL状态重新检查这些模式。
                local_only = candidate_status == "infeasible" & ...
                    candidate_attempts < 4;
                candidate_status(local_only) = "unknown";
                candidate_attempts(local_only) = 3;
                local_window_progress(progress_row).status = ...
                    candidate_status;
                local_window_progress(progress_row).attempts = ...
                    candidate_attempts;
                record.local_window_progress = local_window_progress;
            end
            if all(candidate_status == "infeasible")
                continue
            end
            pending_candidates = find(candidate_status == "pending");
            if isempty(pending_candidates)
                unknown_candidates = find(candidate_status == "unknown");
                minimum_attempt = min( ...
                    candidate_attempts(unknown_candidates));
                candidate_order = unknown_candidates( ...
                    candidate_attempts(unknown_candidates) == ...
                    minimum_attempt);
                % 候选编号按相邻平台的合并失真升序生成，优先搜索
                % 最接近K+1可行解的边界删除，避免先耗时于最差合并。
                candidate_order = sort(candidate_order, 'ascend');
            else
                candidate_order = pending_candidates;
            end
            if isfield(checkpoint, 'z_layer_attempt_count') && ...
                    checkpoint.z_layer_attempt_count >= 2 && ...
                    ~any(candidate_attempts >= 5)
                % z-only引导的对偶界已经越过最前两个删除模式；先用
                % 不同LP算法加深当前第三个模式，避免顺序扫描百余项。
                focused = find(candidate_status == "unknown" & ...
                    candidate_attempts == 4, 1, 'last');
                if ~isempty(focused)
                    candidate_order = focused;
                    fprintf(['[O1] focused global recovery on candidate ', ...
                        '%d after guided z-only search.\n'], focused);
                end
            end
            fixed_z_candidates = candidate_order( ...
                ~fixed_z_tested(candidate_order));
            for candidate = reshape(fixed_z_candidates, 1, [])
                values = change_candidates(:, candidate);
                [lower, upper, ~] = local_candidate_bounds( ...
                    solver_problem, indices, source_z, boundaries, ...
                    values, buffer, ctx.T, z_indices, ...
                    variable_lower, variable_upper);
                next_attempt = candidate_attempts(candidate) + 1;
                time_multiplier = 2 ^ min(next_attempt - 1, 3);
                candidate_time_s = min(ctx.config.repair_max_time_s, ...
                    window_time_s(window_index) * time_multiplier);
                local_started = tic;
                fixed_z_problem = solver_problem;
                fixed_z_problem.lb = lower;
                fixed_z_problem.ub = upper;
                fixed_z_problem.f(:) = 0;
                fixed_z_problem.x0 = [];
                fixed_z_problem.options = optimoptions( ...
                    ctx.repair_options, 'MaxTime', ...
                    min(60, candidate_time_s), 'Display', 'off');
                [candidate_x, ~, exitflag, output] = ...
                    intlinprog(fixed_z_problem);
                if ~isempty(candidate_x) && ...
                        (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
                    [candidate_x, recovery_flag, recovery_output] = ...
                        recover_direction_binaries( ...
                        fixed_z_problem, candidate_x, indices, 60);
                    if recovery_flag <= 0 || isempty(candidate_x)
                        exitflag = 0;
                        output = recovery_output;
                    end
                end
                fixed_z_tested(candidate) = true;
                local_window_progress(progress_row).fixed_z_tested = ...
                    fixed_z_tested;
                record.local_window_progress = local_window_progress;
                record.exitflag = exitflag;
                record.output = output;
                fprintf(['[O1] local %dh candidate %d/%d fixed-z: ', ...
                    'exitflag=%g, %.1f s.\n'], buffer, candidate, ...
                    local_count, exitflag, toc(local_started));
                if ~isempty(candidate_x)
                    x = candidate_x;
                    record.solve_backend = "intlinprog_local_fixed_z";
                    break
                end
                should_checkpoint_fixed = ...
                    (mod(candidate, 10) == 0) || ...
                    candidate == local_count || exitflag == 0;
                if isfield(checkpoint, 'enabled') && checkpoint.enabled && ...
                        should_checkpoint_fixed
                    record.status = "repair_in_progress";
                    record.elapsed_s = toc(started);
                    record.repair_strategy = checkpoint.repair_strategy;
                    progress_entry = struct('mode', checkpoint.mode, ...
                        'cost_cap', checkpoint.cost_cap, ...
                        'K', checkpoint.K, 'record', record, ...
                        'source', "repair_progress");
                    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
                        "append", checkpoint.mode, ...
                        checkpoint.cost_cap, progress_entry);
                end
            end
            if ~isempty(x)
                break
            end
            for candidate = reshape(candidate_order, 1, [])
                values = change_candidates(:, candidate);
                [lower, upper, hours] = local_candidate_bounds( ...
                    solver_problem, indices, source_z, boundaries, ...
                    values, buffer, ctx.T, z_indices, ...
                    variable_lower, variable_upper);
                candidate_attempts(candidate) = ...
                    candidate_attempts(candidate) + 1;
                time_multiplier = 2 ^ min( ...
                    candidate_attempts(candidate) - 1, 3);
                candidate_time_s = min(ctx.config.repair_max_time_s, ...
                    window_time_s(window_index) * time_multiplier);
                local_started = tic;
                if candidate_attempts(candidate) >= 4
                    % 前两类局部分段均失败后，固定该K边界模式并释放
                    % 全年AEL整数状态，允许跨月储氢与启停重排。
                    global_pattern_problem = solver_problem;
                    global_pattern_problem.lb = variable_lower;
                    global_pattern_problem.ub = variable_upper;
                    global_pattern_problem.lb(z_indices) = values;
                    global_pattern_problem.ub(z_indices) = values;
                    global_pattern_problem.f(:) = 0;
                    if ~isempty(solver_problem.x0)
                        global_pattern_problem.x0 = solver_problem.x0;
                        global_pattern_problem.x0(z_indices) = values;
                    end
                    % 固定z后，仅n_ael仍是实质整数变量。先解全年
                    % 连续松弛，再把逐时台数按多种规则投影为整数；
                    % 固定投影后模型退化为LP，可快速严格复核。
                    candidate_x = [];
                    exitflag = 0;
                    output = struct();
                    local_backend = "linprog_global_fixed_z_projected_ael";
                    n_indices = indices.n_ael(:);
                    module_power = ctx.params.AEL.common.module_power;
                    module_min_load = ctx.params.AEL.common.min_load;
                    module_max_load = ctx.params.AEL.common.max_load;
                    module_count = ctx.params.AEL.common.module_num;
                    if candidate_attempts(candidate) >= 4
                        projection_options = optimoptions('linprog', ...
                            'Algorithm', 'interior-point', ...
                            'MaxTime', min(120, candidate_time_s), ...
                            'Display', 'off');
                    else
                        projection_options = optimoptions('linprog', ...
                            'MaxTime', min(60, candidate_time_s), ...
                            'Display', 'off');
                    end
                    relaxed_problem = global_pattern_problem;
                    relaxed_problem.f(:) = 0;
                    [relaxed_x, ~, relaxed_flag, relaxed_output] = ...
                        linprog(relaxed_problem.f, ...
                        relaxed_problem.Aineq, relaxed_problem.bineq, ...
                        relaxed_problem.Aeq, relaxed_problem.beq, ...
                        relaxed_problem.lb, relaxed_problem.ub, ...
                        projection_options);
                    exitflag = relaxed_flag;
                    output = relaxed_output;
                    if ~isempty(relaxed_x)
                        relaxed_n = relaxed_x(n_indices);
                        relaxed_power = relaxed_x(indices.P_AEL(:));
                        minimum_n = ceil(relaxed_power ./ ...
                            (module_max_load * module_power) - 1e-8);
                        maximum_n = floor(relaxed_power ./ ...
                            (module_min_load * module_power) + 1e-8);
                        minimum_n = max(0, min(module_count, minimum_n));
                        maximum_n = max(minimum_n, ...
                            min(module_count, maximum_n));
                        hysteresis_n = zeros(size(relaxed_n));
                        previous_n = 0;
                        for hour_index = 1:numel(hysteresis_n)
                            hysteresis_n(hour_index) = min(max( ...
                                previous_n, minimum_n(hour_index)), ...
                                maximum_n(hour_index));
                            previous_n = hysteresis_n(hour_index);
                        end
                        fractional_n = relaxed_n - floor(relaxed_n);
                        rounding_thresholds = 0.1:0.1:0.9;
                        threshold_schedules = floor(relaxed_n) + ...
                            double(fractional_n >= rounding_thresholds);
                        projected_schedules = [round(relaxed_n), ...
                            ceil(relaxed_n - 1e-8), floor(relaxed_n + 1e-8), ...
                            hysteresis_n, threshold_schedules];
                        projected_schedules = max(0, min(module_count, ...
                            projected_schedules));
                        projected_schedules = unique( ...
                            projected_schedules.', 'rows', 'stable').';
                        for projection_index = 1:size(projected_schedules, 2)
                            projected_problem = global_pattern_problem;
                            projected_n = projected_schedules( ...
                                :, projection_index);
                            projected_problem.lb(n_indices) = projected_n;
                            projected_problem.ub(n_indices) = projected_n;
                            if isfield(indices, 'I_AEL_up')
                                direction = double([projected_n(1); ...
                                    diff(projected_n)] > 0);
                                projected_problem.lb( ...
                                    indices.I_AEL_up(:)) = direction;
                                projected_problem.ub( ...
                                    indices.I_AEL_up(:)) = direction;
                            end
                            [projected_x, ~, projected_flag, ...
                                projected_output] = linprog( ...
                                projected_problem.f, ...
                                projected_problem.Aineq, ...
                                projected_problem.bineq, ...
                                projected_problem.Aeq, ...
                                projected_problem.beq, ...
                                projected_problem.lb, ...
                                projected_problem.ub, ...
                                projection_options);
                            exitflag = projected_flag;
                            output = projected_output;
                            if ~isempty(projected_x)
                                candidate_x = projected_x;
                                fprintf(['[O1] global fixed-z candidate ', ...
                                    '%d found projected n_ael LP seed ', ...
                                    '%d/%d.\n'], candidate, ...
                                    projection_index, ...
                                    size(projected_schedules, 2));
                                break
                            end
                        end
                    end
                    if isempty(candidate_x) && ~isempty(relaxed_x)
                        nearby_problem = global_pattern_problem;
                        nearby_problem.lb(n_indices) = max(0, ...
                            floor(relaxed_n + 1e-8));
                        nearby_problem.ub(n_indices) = min(module_count, ...
                            ceil(relaxed_n - 1e-8));
                        nearby_problem.x0 = relaxed_x;
                        nearby_problem.options = optimoptions( ...
                            ctx.repair_options, 'MaxTime', ...
                            min(60, candidate_time_s), 'Display', 'off');
                        [candidate_x, ~, exitflag, output] = ...
                            intlinprog(nearby_problem);
                        local_backend = ...
                            "intlinprog_global_fixed_z_nearby_ael";
                    elseif isempty(candidate_x) && exitflag ~= -2
                        global_pattern_problem.options = optimoptions( ...
                            ctx.repair_options, 'MaxTime', ...
                            min(20, candidate_time_s), 'Display', 'off');
                        [candidate_x, ~, exitflag, output] = ...
                            intlinprog(global_pattern_problem);
                        local_backend = "intlinprog_global_fixed_z";
                    end
                    if ~isempty(candidate_x) && ...
                            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
                        [candidate_x, direction_flag, direction_output] = ...
                            recover_direction_binaries( ...
                            global_pattern_problem, candidate_x, indices, 60);
                        if direction_flag <= 0 || isempty(candidate_x)
                            exitflag = 0;
                            output = direction_output;
                        end
                    end
                else
                % 固定边界预筛完成后，允许窗口内边界重定位。
                free_z = z_indices(unique(hours(:), 'stable'));
                lower(free_z) = variable_lower(free_z);
                upper(free_z) = variable_upper(free_z);
                local_problem = solver_problem;
                local_problem.lb = lower;
                local_problem.ub = upper;
                local_problem.f(:) = 0;
                local_problem.x0 = [];
                % 先解局部连续松弛，并按分数型z的贡献提取恰好K个边界；
                % 再固定该分段，以原整数模型恢复AEL台数并严格验证。
                pattern_problem = local_problem;
                pattern_problem.f(:) = 0;
                pattern_problem.f(z_indices) = 1 - 2 * values;
                pattern_options = optimoptions('linprog', ...
                    'MaxTime', min(15, candidate_time_s), 'Display', 'off');
                [pattern_x, ~, pattern_flag, pattern_output] = linprog( ...
                    pattern_problem.f, pattern_problem.Aineq, ...
                    pattern_problem.bineq, pattern_problem.Aeq, ...
                    pattern_problem.beq, pattern_problem.lb, ...
                    pattern_problem.ub, pattern_options);
                candidate_x = [];
                exitflag = pattern_flag;
                output = pattern_output;
                local_backend = "linprog_fractional_z_integer_recovery";
                if ~isempty(pattern_x)
                    recovered_problem = local_problem;
                    pattern_z = round(values);
                    free_positions = find(ismember(z_indices, free_z));
                    fixed_positions = setdiff((1:ctx.T).', free_positions);
                    free_target = K - sum(pattern_z(fixed_positions));
                    free_target = max(0, min(numel(free_positions), ...
                        round(free_target)));
                    pattern_z(free_positions) = 0;
                    if candidate_attempts(candidate) >= 2 && ...
                            isfield(indices, 'O1_HB_setpoint') && ...
                            free_target > 0
                        % 第二轮使用连续设定值曲线的最小方差分段，避免
                        % 重复第一轮“最大分数z”投影所产生的同类模式。
                        ordered_hours = unique(hours(:), 'stable');
                        ordered_setpoint = pattern_x( ...
                            indices.O1_HB_setpoint(ordered_hours));
                        segment_lengths = ones(numel(ordered_hours), 1);
                        segment_averages = ordered_setpoint(:);
                        segment_ends = (1:numel(ordered_hours)).';
                        target_segments = min(numel(ordered_hours), ...
                            free_target + 1);
                        if candidate_attempts(candidate) == 2
                            while numel(segment_lengths) > target_segments
                                merge_cost = segment_lengths(1:end-1) .* ...
                                    segment_lengths(2:end) ./ ...
                                    (segment_lengths(1:end-1) + ...
                                    segment_lengths(2:end)) .* ...
                                    (segment_averages(1:end-1) - ...
                                    segment_averages(2:end)).^2;
                                [~, merge_at] = min(merge_cost);
                                merged_length = ...
                                    segment_lengths(merge_at) + ...
                                    segment_lengths(merge_at + 1);
                                segment_averages(merge_at) = ...
                                    (segment_lengths(merge_at) * ...
                                    segment_averages(merge_at) + ...
                                    segment_lengths(merge_at + 1) * ...
                                    segment_averages(merge_at + 1)) / ...
                                    merged_length;
                                segment_lengths(merge_at) = merged_length;
                                segment_ends(merge_at) = ...
                                    segment_ends(merge_at + 1);
                                segment_lengths(merge_at + 1) = [];
                                segment_averages(merge_at + 1) = [];
                                segment_ends(merge_at + 1) = [];
                            end
                            local_backend = local_backend + ...
                                "_greedy_segmentation";
                        else
                            segment_ends = ...
                                minimax_piecewise_constant_ends( ...
                                ordered_setpoint, target_segments);
                            local_backend = local_backend + ...
                                "_minimax_segmentation";
                        end
                        boundary_hours = ordered_hours( ...
                            segment_ends(1:end-1));
                        pattern_z(boundary_hours) = 1;
                    else
                        [~, fractional_order] = sort( ...
                            pattern_x(z_indices(free_positions)), 'descend');
                        selected = fractional_order(1:free_target);
                        pattern_z(free_positions(selected)) = 1;
                        local_backend = local_backend + ...
                            "_top_fractional";
                    end
                    recovered_problem.lb(z_indices) = pattern_z;
                    recovered_problem.ub(z_indices) = pattern_z;
                    recovered_problem.options = optimoptions( ...
                        ctx.repair_options, 'MaxTime', ...
                        min(60, candidate_time_s), 'Display', 'off');
                    [candidate_x, ~, recovery_flag, recovery_output] = ...
                        intlinprog(recovered_problem);
                    exitflag = recovery_flag;
                    output = recovery_output;
                    if ~isempty(candidate_x) && ...
                            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
                        [candidate_x, direction_flag, direction_output] = ...
                            recover_direction_binaries( ...
                            recovered_problem, candidate_x, indices, 60);
                        if direction_flag <= 0 || isempty(candidate_x)
                            exitflag = 0;
                            output = direction_output;
                        end
                    elseif isempty(candidate_x)
                        % 一个松弛分段恢复失败不能证明整个自由边界邻域不可行。
                        exitflag = 0;
                    end
                end
                end
                local_elapsed_s = toc(local_started);
                candidate_infeasible = exitflag == -2;
                if candidate_infeasible
                    candidate_status(candidate) = "infeasible";
                elseif ~isempty(candidate_x)
                    candidate_status(candidate) = "feasible";
                else
                    candidate_status(candidate) = "unknown";
                end
                local_window_progress(progress_row).status = ...
                    candidate_status;
                local_window_progress(progress_row).attempts = ...
                    candidate_attempts;
                local_window_progress(progress_row).fixed_z_tested = ...
                    fixed_z_tested;
                record.local_window_progress = local_window_progress;
                counts = zeros(numel(local_window_progress), 2);
                for count_index = 1:numel(local_window_progress)
                    status = string( ...
                        local_window_progress(count_index).status(:));
                    first_open = find(status ~= "infeasible", 1);
                    if isempty(first_open)
                        completed = numel(status);
                    else
                        completed = first_open - 1;
                    end
                    counts(count_index, :) = [ ...
                        local_window_progress(count_index).hours, completed];
                end
                record.local_window_candidate_counts = counts;
                record.exitflag = exitflag;
                record.output = output;
                if isfield(output, 'message')
                    record.message = string(output.message);
                end
                fprintf(['[O1] local %dh candidate %d/%d ', ...
                    'attempt %d: exitflag=%g, %.1f s.\n'], ...
                    buffer, candidate, local_count, ...
                    candidate_attempts(candidate), exitflag, ...
                    local_elapsed_s);
                if ~isempty(candidate_x)
                    x = candidate_x;
                    record.solve_backend = local_backend;
                    break
                end
                should_checkpoint = isfield(checkpoint, 'enabled') && ...
                    checkpoint.enabled && ...
                    ((exitflag == 0 && mod(candidate, 10) == 0) || ...
                    local_elapsed_s >= 30 || candidate == local_count);
                if should_checkpoint
                    record.status = "repair_in_progress";
                    record.elapsed_s = toc(started);
                    record.repair_strategy = checkpoint.repair_strategy;
                    progress_entry = struct('mode', checkpoint.mode, ...
                        'cost_cap', checkpoint.cost_cap, ...
                        'K', checkpoint.K, 'record', record, ...
                        'source', "repair_progress");
                    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
                        "append", checkpoint.mode, ...
                        checkpoint.cost_cap, progress_entry);
                end
            end
            local_all_infeasible = local_all_infeasible && all( ...
                candidate_status == "infeasible");
            if ~isempty(x)
                break
            end
        end
        if isempty(x)
            record.is_infeasible = false;
            global_scan_active = isfield(checkpoint, ...
                'z_layer_attempt_count') && ...
                checkpoint.z_layer_attempt_count >= 2;
            global_scan_complete = global_scan_active;
            if global_scan_active
                for progress_index = 1:numel(local_window_progress)
                    status = string(local_window_progress( ...
                        progress_index).status(:));
                    attempts = double(local_window_progress( ...
                        progress_index).attempts(:));
                    global_scan_complete = global_scan_complete && ...
                        all(status == "infeasible" & attempts >= 4);
                end
            end
            if global_scan_complete
                cache_infeasible_z_relocation_layer( ...
                    ctx, K, source_key, 0);
                record.status = "z_layer_relaxation_infeasible";
                record.z_relocation_layer = 0;
                record.z_layer_attempt_count = ...
                    checkpoint.z_layer_attempt_count;
                record.solve_backend = ...
                    "linprog_fixed_z_layer_exhaustive";
            elseif global_scan_active
                record.status = "z_layer_global_scan_unknown";
                record.z_relocation_layer = 0;
                record.z_layer_attempt_count = ...
                    checkpoint.z_layer_attempt_count;
            elseif local_all_infeasible
                record.status = "local_integer_infeasible";
            else
                record.status = "local_integer_unknown";
            end
        end
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
if candidate_count == 1
    record.is_infeasible = isempty(x) && all_infeasible;
end
if isfield(output, 'message')
    record.message = string(output.message);
end
if exitflag <= 0 || isempty(x)
    if record.is_infeasible && record.status == "fixed_integer_unknown"
        record.status = "fixed_integer_infeasible";
    end
    return
end

if ~isempty(relaxed_grid)
    record.solve_backend = record.solve_backend + "_grid_relaxed";
end
if ~isempty(relaxed_ael)
    record.solve_backend = record.solve_backend + ...
        "_ael_direction_relaxed";
end

solution = struct();
names = fieldnames(indices);
for i = 1:numel(names)
    index = indices.(names{i});
    solution.(names{i}) = reshape(x(index(:)), size(index));
end
raw_z = solution.O1_HB_change(:);
rounded_z = round(raw_z);
setpoint = solution.O1_HB_setpoint(:);
setpoint_change = [setpoint(2:end); setpoint(1)] - setpoint;
inactive = rounded_z < 0.5;
record.solver_count = round(sum(rounded_z));
record.max_z_residual = max(abs(raw_z - rounded_z));
record.max_link_violation = max(abs(setpoint_change) - ...
    (ctx.HB_ramp + ctx.config.change_epsilon) * rounded_z);
if any(inactive)
    record.max_inactive_drift = max(abs(setpoint_change(inactive)));
else
    record.max_inactive_drift = 0;
end
solution = add_change_indicators(solution, ctx);
record.has_incumbent = true;
record.objective_lower = 0;
record.objective_upper = 0;
record.absolute_gap = 0;
record.relative_gap = 0;
record.count_upper = round(sum(solution.O1_HB_change));
record.system_cost_upper = evaluate(ctx.system_cost_usd, solution);
record.is_proven = true;
record.status = "fixed_integer_feasible";
record.solution = solution;
end

function [lower, upper, hours] = local_candidate_bounds( ...
        solver_problem, indices, source_z, boundaries, values, ...
        buffer, T, z_indices, variable_lower, variable_upper)
removed = find(source_z - values > 0.5, 1);
previous = boundaries(find(boundaries < removed, 1, 'last'));
following = boundaries(find(boundaries > removed, 1, 'first'));
if isempty(previous)
    previous = boundaries(end);
end
if isempty(following)
    following = boundaries(1);
end
span = mod(following - previous, T);
hours = mod(previous + ((1 - buffer):(span + buffer)) - 1, T) + 1;

index_names = fieldnames(indices);
free_parts = cell(numel(index_names), 1);
for name_index = 1:numel(index_names)
    name = index_names{name_index};
    variable_index = indices.(name);
    if numel(variable_index) == T
        free_parts{name_index} = reshape( ...
            variable_index(hours(:)), [], 1);
    elseif strcmp(name, 'storage_H2') && numel(variable_index) == T + 1
        storage_hours = unique([hours(:); hours(:) + 1]);
        free_parts{name_index} = reshape( ...
            variable_index(storage_hours), [], 1);
    else
        free_parts{name_index} = zeros(0, 1);
    end
end
free_local = unique(vertcat(free_parts{:}));
fixed_local = setdiff((1:numel(solver_problem.lb)).', free_local);
lower = variable_lower;
upper = variable_upper;
fixed_values = solver_problem.x0(fixed_local);
integer_mask = ismember(fixed_local, solver_problem.intcon(:));
fixed_values(integer_mask) = round(fixed_values(integer_mask));
lower(fixed_local) = fixed_values;
upper(fixed_local) = fixed_values;
lower(z_indices) = values;
upper(z_indices) = values;
end

function segment_ends = minimax_piecewise_constant_ends(values, target_count)
%MINIMAX_PIECEWISE_CONSTANT_ENDS Greedy optimal partition for a max range.
values = values(:);
sample_count = numel(values);
target_count = max(1, min(sample_count, round(target_count)));
lower_tolerance = 0;
upper_tolerance = max(values) - min(values);
for iteration = 1:45
    middle_tolerance = (lower_tolerance + upper_tolerance) / 2;
    trial_ends = partition_with_range(values, middle_tolerance);
    if numel(trial_ends) > target_count
        lower_tolerance = middle_tolerance;
    else
        upper_tolerance = middle_tolerance;
    end
end
segment_ends = partition_with_range(values, ...
    upper_tolerance + 1e-12);
while numel(segment_ends) < target_count
    starts = [1; segment_ends(1:end-1) + 1];
    lengths = segment_ends - starts + 1;
    [longest, split_index] = max(lengths);
    if longest <= 1
        break
    end
    split_at = starts(split_index) + floor(longest / 2) - 1;
    segment_ends = [segment_ends(1:split_index - 1); split_at; ...
        segment_ends(split_index:end)];
end

    function ends = partition_with_range(series, tolerance)
        ends = zeros(0, 1);
        segment_minimum = series(1);
        segment_maximum = series(1);
        for value_index = 2:numel(series)
            next_minimum = min(segment_minimum, series(value_index));
            next_maximum = max(segment_maximum, series(value_index));
            if next_maximum - next_minimum > 2 * tolerance
                ends(end + 1, 1) = value_index - 1; %#ok<AGROW>
                segment_minimum = series(value_index);
                segment_maximum = series(value_index);
            else
                segment_minimum = next_minimum;
                segment_maximum = next_maximum;
            end
        end
        ends(end + 1, 1) = numel(series);
    end
end

function [x, exitflag, output, selected_projection] = ...
        solve_projected_ael_pattern(solver_problem, indices, pattern_z, ...
        variable_lower, variable_upper, ctx, max_time_s)
%SOLVE_PROJECTED_AEL_PATTERN Recover a strict integer AEL schedule for fixed z.
x = [];
exitflag = 0;
output = struct();
selected_projection = 0;
z_indices = indices.O1_HB_change(:);
n_indices = indices.n_ael(:);
pattern_problem = solver_problem;
pattern_problem.lb = variable_lower;
pattern_problem.ub = variable_upper;
pattern_problem.lb(z_indices) = pattern_z;
pattern_problem.ub(z_indices) = pattern_z;

options = optimoptions('linprog', 'Algorithm', 'interior-point', ...
    'ConstraintTolerance', 1e-5, 'Display', 'none', ...
    'MaxTime', max_time_s);
relaxed_problem = pattern_problem;
relaxed_problem.f = solver_problem.f;
[relaxed_x, ~, exitflag, output] = linprog(relaxed_problem.f, ...
    relaxed_problem.Aineq, relaxed_problem.bineq, ...
    relaxed_problem.Aeq, relaxed_problem.beq, relaxed_problem.lb, ...
    relaxed_problem.ub, options);
if isempty(relaxed_x)
    return
end

module_power = ctx.params.AEL.common.module_power;
module_min_load = ctx.params.AEL.common.min_load;
module_max_load = ctx.params.AEL.common.max_load;
module_count = ctx.params.AEL.common.module_num;
relaxed_n = relaxed_x(n_indices);
relaxed_power = relaxed_x(indices.P_AEL(:));
minimum_n = ceil(relaxed_power ./ ...
    (module_max_load * module_power) - 1e-8);
maximum_n = floor(relaxed_power ./ ...
    (module_min_load * module_power) + 1e-8);
minimum_n = max(0, min(module_count, minimum_n));
maximum_n = max(minimum_n, min(module_count, maximum_n));
hysteresis_n = zeros(size(relaxed_n));
previous_n = 0;
for hour_index = 1:numel(hysteresis_n)
    hysteresis_n(hour_index) = min(max(previous_n, ...
        minimum_n(hour_index)), maximum_n(hour_index));
    previous_n = hysteresis_n(hour_index);
end
fractional_n = relaxed_n - floor(relaxed_n);
rounding_thresholds = 0.1:0.1:0.9;
threshold_schedules = floor(relaxed_n) + ...
    double(fractional_n >= rounding_thresholds);
projected_schedules = [round(relaxed_n), ceil(relaxed_n - 1e-8), ...
    floor(relaxed_n + 1e-8), hysteresis_n, threshold_schedules];
projected_schedules = max(0, min(module_count, projected_schedules));
projected_schedules = unique(projected_schedules.', 'rows', 'stable').';
for projection_index = 1:size(projected_schedules, 2)
    projected_problem = pattern_problem;
    projected_n = projected_schedules(:, projection_index);
    projected_problem.lb(n_indices) = projected_n;
    projected_problem.ub(n_indices) = projected_n;
    if isfield(indices, 'I_AEL_up')
        direction = double([projected_n(1); diff(projected_n)] > 0);
        projected_problem.lb(indices.I_AEL_up(:)) = direction;
        projected_problem.ub(indices.I_AEL_up(:)) = direction;
    end
    [projected_x, ~, projected_flag, projected_output] = linprog( ...
        projected_problem.f, projected_problem.Aineq, ...
        projected_problem.bineq, projected_problem.Aeq, ...
        projected_problem.beq, projected_problem.lb, ...
        projected_problem.ub, options);
    exitflag = projected_flag;
    output = projected_output;
    if isempty(projected_x)
        continue
    end
    [recovered_x, recovery_flag, recovery_output] = ...
        recover_direction_binaries( ...
        projected_problem, projected_x, indices, max_time_s);
    exitflag = recovery_flag;
    output = recovery_output;
    if recovery_flag > 0 && ~isempty(recovered_x)
        x = recovered_x;
        selected_projection = projection_index;
        return
    end
end
end

function [x, exitflag, output] = recover_direction_binaries( ...
        problem, relaxed_x, indices, max_time_s)
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

function cache_infeasible_z_relocation_layer( ...
        ctx, K, source_key, relocation_layer)
entries = fixed_point_store(ctx.point_cache_file, ctx.signature, ...
    "load", "global_relaxation", Inf, struct());
for entry_index = numel(entries):-1:1
    cached_record = entries(entry_index).record;
    if ~isfield(cached_record, 'raw_x') || ...
            ~isfield(cached_record, 'objective_lower') || ...
            cached_record.objective_lower > K + 1e-7
        continue
    end
    if isfield(cached_record, 'infeasible_z_relocation_layers_v2')
        completed = double(cached_record. ...
            ('infeasible_z_relocation_layers_v2'));
    else
        completed = zeros(0, 5);
    end
    cached_record.infeasible_z_relocation_layers_v2 = unique( ...
        [completed; K, source_key, relocation_layer], 'rows', 'stable');
    cached_entry = entries(entry_index);
    cached_entry.record = cached_record;
    fixed_point_store(ctx.point_cache_file, ctx.signature, ...
        "append", cached_entry.mode, cached_entry.cost_cap, cached_entry);
    return
end
end

function key = z_source_pattern_key(source_z)
%Z_SOURCE_PATTERN_KEY Exact-in-double identity for a yearly binary pattern.
positions = find(round(source_z(:)) > 0.5);
key = [numel(positions), sum(positions), sum(positions .^ 2)];
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

function [representative, frontier, frontier_state] = solve_cost_outputs( ...
        ctx, feasibility, requested_K, reference)
% 逐K求解C*(K)。单点超时保留可行种子成本界并继续，所有点均可缓存续算。
upper = feasibility.K_upper;
initial = feasibility.minimum_updates.solution;
reference_count = round(sum(reference.solution.O1_HB_change));
if ctx.config.frontier_all_k
    % 已知K_upper严格可行，因此[K_upper, reference_count]均可直接
    % 进行成本优化；无需等待最小K的下界与上界闭合。
    first_K = max(0, ceil(feasibility.K_upper));
    last_K = min(ctx.T, reference_count);
    frontier_K = (first_K:last_K).';
else
    frontier_K = unique(round(requested_K(:)));
    frontier_K = frontier_K(frontier_K >= 0 & frontier_K <= ctx.T);
end

variable_types = {'double', 'double', 'double', 'double', 'double', ...
    'double', 'double', 'double', 'logical', 'logical', 'string', ...
    'string', 'double', 'double'};
variable_names = {'K', 'cost_lower_usd', 'cost_upper_usd', ...
    'lcoa_lower_usd_t', 'lcoa_upper_usd_t', ...
    'premium_lower_usd_t', 'premium_upper_usd_t', ...
    'actual_updates', 'has_incumbent', 'is_proven', 'status', ...
    'solve_backend', 'elapsed_s', 'attempts'};
frontier = table('Size', [numel(frontier_K), numel(variable_names)], ...
    'VariableTypes', variable_types, 'VariableNames', variable_names);
frontier.K = frontier_K;
frontier.cost_lower_usd(:) = NaN;
frontier.cost_upper_usd(:) = NaN;
frontier.lcoa_lower_usd_t(:) = NaN;
frontier.lcoa_upper_usd_t(:) = NaN;
frontier.premium_lower_usd_t(:) = NaN;
frontier.premium_upper_usd_t(:) = NaN;
frontier.actual_updates(:) = NaN;
frontier.has_incumbent(:) = false;
frontier.is_proven(:) = false;
frontier.status(:) = "not_run";
frontier.solve_backend(:) = "";
frontier.elapsed_s(:) = 0;
frontier.attempts(:) = 0;
component_names = fieldnames(ctx.cost_components);
for component_index = 1:numel(component_names)
    frontier.(component_names{component_index}) = ...
        NaN(height(frontier), 1);
end
metric_names = {'curtailment_mwh', 'purchase_mwh', 'sales_mwh', ...
    'ael_start_energy_mwh', 'ael_started_modules', ...
    'storage_swing_kg', 'storage_throughput_kg'};
for metric_index = 1:numel(metric_names)
    frontier.(metric_names{metric_index}) = NaN(height(frontier), 1);
end

for row = 1:height(frontier)
    K = frontier.K(row);
    if K < feasibility.K_lower
        point = make_non_solved_point(K, Inf, Inf, ...
            "infeasible_certified", "count_bound");
        assign_row(row, point);
    elseif K >= reference_count
        point = reference;
        point.K_limit = K;
        point.count_upper = reference_count;
        point.status = "reference_bound";
        point.solve_backend = "economic_reference";
        point.elapsed_s = 0;
        point.frontier_attempts = 0;
        assign_row(row, point);
    end
end

solve_K = frontier_K(frontier_K >= feasibility.K_upper & ...
    frontier_K < reference_count);
if upper < reference_count
    solve_K = unique([upper; solve_K(:)]);
else
    solve_K = zeros(0, 1);
end
% 从当前可行边界向经济参考状态推进，使最关心的低K成本优先产生，
% 后续运行再从缓存中的第一个未完成点继续。
solve_K = sort(solve_K, 'ascend');
cost_problem = ctx.problem;
cost_problem.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
cost_problem.Objective = ctx.system_cost_usd;
[cost_solver, build_elapsed_s] = build_fixed_solver( ...
    cost_problem, ctx, initial);
cost_solver.problem.options = ctx.frontier_options;
fprintf(['[O1] Cost frontier: %d optimized K points, %d total rows; ', ...
    'matrix build %.1f s.\n'], numel(solve_K), numel(frontier_K), ...
    build_elapsed_s);

cache_mode = "frontier_cost";
cost_entries = fixed_point_store(ctx.point_cache_file, ctx.signature, ...
    "load", cache_mode, Inf, struct());
current_start = initial;
representative = reference;
frontier_started = tic;
new_point_count = 0;
budget_exhausted = false;
for index = 1:numel(solve_K)
    K = solve_K(index);
    cached_index = find([cost_entries.K] == K, 1);
    cached = struct();
    attempts = 0;
    if ~isempty(cached_index)
        cached = cost_entries(cached_index).record;
        if isfield(cached, 'frontier_attempts')
            attempts = cached.frontier_attempts;
        end
        if isfield(cached, 'solution') && ...
                ~isempty(fieldnames(cached.solution)) && ...
                round(sum(cached.solution.O1_HB_change)) <= K
            cached_cost = cached.objective_upper;
            current_cost = evaluate(ctx.system_cost_usd, current_start);
            if isfinite(cached_cost) && cached_cost < current_cost
                current_start = cached.solution;
            end
        end
    end

    current_count = round(sum(current_start.O1_HB_change));
    gained_feasible_seed = ~isempty(fieldnames(cached)) && ...
        ~cached.has_incumbent && current_count <= K;
    retryable_status = ["seed_cost_bound", "unknown", "solver_error"];
    missing_attribution = ~isempty(fieldnames(cached)) && ...
        cached.has_incumbent && ...
        (~isfield(cached, 'cost_components') || ...
        ~isfield(cached, 'operation_metrics'));
    retryable_fallback = ~isempty(fieldnames(cached)) && ...
        ((any(string(cached.status) == retryable_status) && ...
        attempts < ctx.config.frontier_max_attempts) || ...
        gained_feasible_seed || missing_attribution);
    reusable = ~isempty(fieldnames(cached)) && ~retryable_fallback;
    if reusable
        point = cached;
        point.elapsed_s = 0;
        fprintf('[O1] cost K=%g reused: [%g, %g] USD (%s).\n', ...
            K, point.objective_lower, point.objective_upper, point.status);
    else
        if new_point_count >= ctx.config.frontier_points_per_run || ...
                toc(frontier_started) >= ctx.config.frontier_run_budget_s
            budget_exhausted = true;
            fprintf(['[O1] frontier run budget reached after %d new ', ...
                'points; remaining K values stay cached as pending.\n'], ...
                new_point_count);
            break
        end
        point = solve_cost_frontier_point( ...
            cost_solver, K, current_start, ctx, reference, attempts + 1);
        new_point_count = new_point_count + 1;
        cache_record = point;
        keep_solution = K == upper || ...
            mod(abs(K - upper), ...
            ctx.config.frontier_solution_interval) == 0;
        if ~keep_solution
            cache_record.solution = struct();
        end
        entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
            'record', cache_record, 'source', "frontier_cost");
        fixed_point_store(ctx.point_cache_file, ctx.signature, ...
            "append", cache_mode, Inf, entry);
        cached_index = find([cost_entries.K] == K, 1);
        if isempty(cached_index)
            cost_entries(end + 1) = entry;
        else
            cost_entries(cached_index) = entry;
        end
        fprintf(['[O1] cost K=%g: [%g, %g] USD, used K=%g, ', ...
            '%s, %.1f s.\n'], K, point.objective_lower, ...
            point.objective_upper, point.count_upper, point.status, ...
            point.elapsed_s);
    end
    if isfield(point, 'solution') && ...
            ~isempty(fieldnames(point.solution)) && ...
            round(sum(point.solution.O1_HB_change)) <= K
        current_start = point.solution;
    end
    row = find(frontier.K == K, 1);
    if ~isempty(row)
        assign_row(row, point);
    end
    if K == upper
        representative = point;
        if ~isfield(representative, 'solution') || ...
                isempty(fieldnames(representative.solution))
            representative.solution = initial;
        end
    end
end
pending_rows = find(frontier.status == "not_run");
if isempty(pending_rows)
    next_pending_K = NaN;
else
    next_pending_K = frontier.K(pending_rows(1));
end
frontier_state = struct('elapsed_s', toc(frontier_started), ...
    'new_points', new_point_count, ...
    'points_per_run', ctx.config.frontier_points_per_run, ...
    'run_budget_s', ctx.config.frontier_run_budget_s, ...
    'budget_exhausted', budget_exhausted, ...
    'completed_points', sum(frontier.status ~= "not_run"), ...
    'pending_points', numel(pending_rows), ...
    'next_pending_K', next_pending_K, ...
    'total_points', height(frontier));

    function point = make_non_solved_point(K, lower_cost, upper_cost, ...
            status, backend)
        point = struct('objective_kind', "cost", ...
            'has_incumbent', isfinite(upper_cost), ...
            'objective_lower', lower_cost, 'objective_upper', upper_cost, ...
            'system_cost_lower', lower_cost, ...
            'system_cost_upper', upper_cost, 'absolute_gap', NaN, ...
            'relative_gap', NaN, 'count_lower', NaN, ...
            'count_upper', NaN, 'is_proven', false, ...
            'is_infeasible', status == "infeasible_certified", ...
            'exitflag', NaN, 'status', string(status), 'message', "", ...
            'output', struct(), 'solution', struct(), ...
            'solve_backend', string(backend), 'K_limit', K, ...
            'elapsed_s', 0, 'frontier_attempts', 0);
    end

    function assign_row(row, point)
        lower_cost = point.objective_lower;
        upper_cost = point.objective_upper;
        ammonia_revenue = ctx.params.ammonia.price ...
            * ctx.config.nh3_target_t;
        frontier.cost_lower_usd(row) = lower_cost;
        frontier.cost_upper_usd(row) = upper_cost;
        frontier.lcoa_lower_usd_t(row) = ...
            (lower_cost + ammonia_revenue) / ctx.config.nh3_target_t;
        frontier.lcoa_upper_usd_t(row) = ...
            (upper_cost + ammonia_revenue) / ctx.config.nh3_target_t;
        frontier.premium_lower_usd_t(row) = ...
            (lower_cost - reference.objective_upper) ...
            / ctx.config.nh3_target_t;
        frontier.premium_upper_usd_t(row) = ...
            (upper_cost - reference.objective_lower) ...
            / ctx.config.nh3_target_t;
        if isfield(point, 'count_upper')
            frontier.actual_updates(row) = point.count_upper;
        end
        frontier.has_incumbent(row) = point.has_incumbent;
        frontier.is_proven(row) = point.is_proven;
        frontier.status(row) = string(point.status);
        frontier.solve_backend(row) = string(point.solve_backend);
        frontier.elapsed_s(row) = point.elapsed_s;
        if isfield(point, 'frontier_attempts')
            frontier.attempts(row) = point.frontier_attempts;
        end
        if isfield(point, 'cost_components')
            components = point.cost_components;
        elseif isfield(point, 'solution') && ...
                ~isempty(fieldnames(point.solution))
            components = evaluate_cost_components(point.solution, ctx);
        else
            components = struct();
        end
        for component_index = 1:numel(component_names)
            name = component_names{component_index};
            if isfield(components, name)
                frontier.(name)(row) = components.(name);
            end
        end
        if isfield(point, 'operation_metrics')
            metrics = point.operation_metrics;
        elseif isfield(point, 'solution') && ...
                ~isempty(fieldnames(point.solution))
            metrics = evaluate_operation_metrics(point.solution, ctx);
        else
            metrics = struct();
        end
        for metric_index = 1:numel(metric_names)
            name = metric_names{metric_index};
            if isfield(metrics, name)
                frontier.(name)(row) = metrics.(name);
            end
        end
    end
end

function record = solve_cost_frontier_point( ...
        solver_data, K, start, ctx, reference, attempt)
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.options = ctx.frontier_options;
indices = solver_data.indices;
seed_count = round(sum(start.O1_HB_change));
seed_cost = evaluate(ctx.system_cost_usd, start);
seed_is_feasible = seed_count <= K && isfinite(seed_cost);
if seed_is_feasible
    problem.x0 = solution_to_vector(indices, start, numel(problem.lb));
    seed_solution = start;
    seed_upper = seed_cost;
    initial_status = "seed_cost_bound";
    initial_backend = "seed_fallback";
else
    problem.x0 = [];
    seed_solution = struct();
    seed_upper = Inf;
    initial_status = "unknown";
    initial_backend = "no_feasible_seed";
end
relaxed_grid = zeros(0, 1);
relaxed_ael = zeros(0, 1);
if isfield(indices, 'u_purchase') && ...
        isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    relaxed_grid = indices.u_purchase(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_grid);
end
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    relaxed_ael = indices.I_AEL_up(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_ael);
end

reference_lower = reference.objective_lower;
if ~isfinite(reference_lower)
    reference_lower = -Inf;
end
record = struct('objective_kind', "cost", ...
    'has_incumbent', seed_is_feasible, ...
    'objective_lower', reference_lower, ...
    'objective_upper', seed_upper, ...
    'system_cost_lower', reference_lower, ...
    'system_cost_upper', seed_upper, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, ...
    'count_upper', ternary_count(seed_is_feasible, seed_count), ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', initial_status, 'message', "", 'output', struct(), ...
    'solution', seed_solution, 'solve_backend', initial_backend, ...
    'K_limit', K, 'elapsed_s', NaN, 'frontier_attempts', attempt);
if seed_is_feasible
    record.cost_components = evaluate_cost_components(seed_solution, ctx);
    record.operation_metrics = evaluate_operation_metrics(seed_solution, ctx);
end
started = tic;
candidate_x = [];
search_output = struct();
try
    [candidate_x, ~, exitflag, search_output] = intlinprog(problem);
    output = search_output;
    if ~isempty(candidate_x) && ...
            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
        [candidate_x, recovery_flag, recovery_output] = ...
            recover_direction_binaries(problem, candidate_x, indices, 60);
        if recovery_flag <= 0 || isempty(candidate_x)
            candidate_x = [];
            exitflag = 0;
            output = struct('message', "Integer-direction recovery failed.", ...
                'search', search_output, 'recovery', recovery_output);
        end
    end
catch exception
    exitflag = NaN;
    output = struct('message', exception.message);
end
record.elapsed_s = toc(started);
record.exitflag = exitflag;
record.output = output;
if isfield(output, 'message')
    record.message = string(output.message);
end
lower_bound = reference_lower;
if isfield(search_output, 'bestbound') && ...
        isscalar(search_output.bestbound) && ...
        isfinite(search_output.bestbound)
    lower_bound = max(lower_bound, search_output.bestbound);
end

candidate_accepted = false;
if ~isempty(candidate_x)
    solution = vector_to_solution(candidate_x, indices);
    solution = add_change_indicators(solution, ctx);
    candidate_count = round(sum(solution.O1_HB_change));
    candidate_cost = evaluate(ctx.system_cost_usd, solution);
    if candidate_count <= K && isfinite(candidate_cost)
        candidate_accepted = true;
        record.has_incumbent = true;
        if candidate_cost < record.objective_upper
            record.solution = solution;
            record.objective_upper = candidate_cost;
            record.system_cost_upper = candidate_cost;
            record.count_upper = candidate_count;
        end
    end
end
if candidate_accepted
    record.solve_backend = "intlinprog_matrix_cost";
    if ~isempty(relaxed_grid)
        record.solve_backend = record.solve_backend + "_grid_relaxed";
    end
    if ~isempty(relaxed_ael)
        record.solve_backend = record.solve_backend ...
            + "_ael_direction_relaxed";
    end
    record.status = "incumbent_with_bound";
elseif ~record.has_incumbent && exitflag == -2
    record.objective_lower = Inf;
    record.objective_upper = Inf;
    record.system_cost_lower = Inf;
    record.system_cost_upper = Inf;
    record.is_infeasible = true;
    record.status = "infeasible_certified";
    record.solve_backend = "intlinprog_matrix_cost";
    return
end
record.objective_lower = min(lower_bound, record.objective_upper);
record.system_cost_lower = record.objective_lower;
record.absolute_gap = record.objective_upper - record.objective_lower;
record.relative_gap = record.absolute_gap ...
    / max(1, abs(record.objective_upper));
record.is_proven = record.absolute_gap <= ...
    max(1e-7, eps(abs(record.objective_upper)));
if record.is_proven
    record.status = "proven";
end
if record.has_incumbent && ~isempty(fieldnames(record.solution))
    record.cost_components = evaluate_cost_components(record.solution, ctx);
    record.operation_metrics = evaluate_operation_metrics( ...
        record.solution, ctx);
end

    function value = ternary_count(condition, count)
        if condition
            value = count;
        else
            value = NaN;
        end
    end
end

function vector = solution_to_vector(indices, solution, vector_length)
vector = [];
if ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
candidate = zeros(vector_length, 1);
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(solution, name) || ...
            numel(solution.(name)) ~= numel(indices.(name))
        return
    end
    candidate(indices.(name)(:)) = solution.(name)(:);
end
vector = candidate;
end

function solution = vector_to_solution(vector, indices)
solution = struct();
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    index = indices.(name);
    solution.(name) = reshape(vector(index(:)), size(index));
end
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
    fprintf(['Certified-feasible cost frontier: K=%g:%g, ', ...
        'finite costs=%d/%d\n'], ...
        min(study.frontier.K), max(study.frontier.K), ...
        finite_costs, height(study.frontier));
end
if isfield(study, 'frontier_state')
    state = study.frontier_state;
    fprintf(['Frontier progress: completed=%d/%d, new=%d, ', ...
        'pending=%d, next K=%g\n'], state.completed_points, ...
        state.total_points, state.new_points, state.pending_points, ...
        state.next_pending_K);
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

function outputs = O1Economics(ctx, feasibility, reference)
%O1ECONOMICS 求解固定K成本前沿及其经济边界。
% 本文件负责成本前沿记录、经济成本容许量和运行指标。
[representative, frontier, frontier_state] = solve_cost_outputs( ...
    ctx, feasibility, ctx.config.frontier_k, reference);
economic = struct([]);
if feasibility.is_proven && isfinite(reference.objective_lower)
    economic = solve_economic_boundaries(ctx, reference, feasibility);
end
outputs = struct('representative', representative, ...
    'frontier', frontier, 'frontier_state', frontier_state, ...
    'boundaries', economic);
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
[cost_solver, build_elapsed_s] = ctx.services.build_fixed_solver( ...
    cost_problem, ctx, initial);
cost_solver.problem.options = ctx.frontier_options;
fprintf(['[O1] Cost frontier: %d optimized K points, %d total rows; ', ...
    'matrix build %.1f s.\n'], numel(solve_K), numel(frontier_K), ...
    build_elapsed_s);

cache_mode = "frontier_cost";
cost_entries = ctx.services.fixed_point_store(ctx.point_cache_file, ...
    ctx.cost_signature, ...
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
        ctx.services.fixed_point_store(ctx.point_cache_file, ...
            ctx.cost_signature, ...
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
        frontier.cost_lower_usd(row) = lower_cost;
        frontier.cost_upper_usd(row) = upper_cost;
        frontier.lcoa_lower_usd_t(row) = ...
            lower_cost / ctx.config.nh3_target_t;
        frontier.lcoa_upper_usd_t(row) = ...
            upper_cost / ctx.config.nh3_target_t;
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
            components = ctx.services.evaluate_cost_components(point.solution, ctx);
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
            metrics = ctx.services.evaluate_operation_metrics(point.solution, ctx);
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
    record.cost_components = ctx.services.evaluate_cost_components(seed_solution, ctx);
    record.operation_metrics = ctx.services.evaluate_operation_metrics(seed_solution, ctx);
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
            ctx.services.recover_direction_binaries( ...
            problem, candidate_x, indices, 60);
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
    solution = ctx.services.add_change_indicators(solution, ctx);
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
    record.cost_components = ctx.services.evaluate_cost_components(record.solution, ctx);
    record.operation_metrics = ctx.services.evaluate_operation_metrics( ...
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
    [boundary, ~, ~] = O1Feasibility( ...
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

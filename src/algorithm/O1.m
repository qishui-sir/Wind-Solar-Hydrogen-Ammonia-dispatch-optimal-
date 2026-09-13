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

% 优化变量
z = optimvar('O1_HB_change', T, 'Type', 'integer', ...
    'LowerBound', 0, 'UpperBound', 1);
HB_next = [HB_load(2:end); HB_load(1)];
HB_change = HB_next - HB_load;
HB_ramp = params.HB.ramp_rate * dt;

% 约束条件
problem = model.problem;
problem.Constraints.O1_nh3_target = NH3_total_t == config.nh3_target_t;
problem.Constraints.O1_change_up = HB_change <= HB_ramp * z;
problem.Constraints.O1_change_down = -HB_change <= HB_ramp * z;
update_count = sum(z);

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
study.definition = ['Number of hourly HB load set-point changes, including ', ...
    'the cyclic last-to-first boundary.'];
study.config = config;
study.output_range_t = [minimum_output_t, maximum_output_t];

% 参考解：无变化次数约束下的最小成本
reference_problem = problem;
reference_problem.Objective = system_cost_usd;
reference = solve_record(reference_problem, cost_options, 'cost', []);
study.reference = reference;

% 可行性解：最小化变化次数（无成本约束）
feasibility_problem = problem;
feasibility_problem.Objective = update_count;
feasibility = solve_record(feasibility_problem, count_options, 'count', ...
    reference.solution);
study.feasibility = struct('minimum_updates', feasibility);

if ~reference.has_incumbent || ~feasibility.has_incumbent
    study.status = 'incomplete_no_incumbent';
    study.economic = struct([]);
    study.frontier = table();
    print_summary(study);
    return
end

% 在最小变化次数上求最小成本
K_feas_upper = feasibility.count_upper;
representative_problem = problem;
representative_problem.Constraints.O1_update_limit = ...
    update_count <= K_feas_upper;
representative_problem.Objective = system_cost_usd;
representative = solve_record(representative_problem, cost_options, 'cost', ...
    feasibility.solution);
study.feasibility.minimum_cost_at_upper_bound = representative;
study.feasibility.K_lower = feasibility.count_lower;
study.feasibility.K_upper = K_feas_upper;
study.feasibility.is_proven = ...
    isfinite(feasibility.count_lower) && ...
    feasibility.count_lower == K_feas_upper;

reference_lower = reference.objective_lower;
reference_upper = reference.objective_upper;
if ~isfinite(reference_lower)
    study.status = 'incomplete_reference_bound';
    study.economic = struct([]);
    study.frontier = table();
    print_summary(study);
    return
end

% 经济性分析：给定成本预算，最少需要多少次变化
allowances = config.cost_allowance_usd_t(:);
economic = repmat(struct(), numel(allowances), 1);
for i = 1:numel(allowances)
    allowance = allowances(i);
    allowance_total = allowance * config.nh3_target_t;
    optimistic_cap = reference_upper + allowance_total;
    conservative_cap = reference_lower + allowance_total;

    optimistic_problem = problem;
    optimistic_problem.Constraints.O1_cost_limit = ...
        system_cost_usd <= optimistic_cap;
    optimistic_problem.Objective = update_count;
    optimistic = solve_record(optimistic_problem, count_options, 'count', ...
        reference.solution);

    if abs(reference_upper - reference_lower) <= config.cost_bound_tolerance_usd
        conservative = optimistic;
    else
        conservative_start = [];
        if reference_upper <= conservative_cap + config.cost_bound_tolerance_usd
            conservative_start = reference.solution;
        elseif representative.has_incumbent && ...
                evaluate(system_cost_usd, representative.solution) <= ...
                conservative_cap + config.cost_bound_tolerance_usd
            conservative_start = representative.solution;
        end
        conservative_problem = problem;
        conservative_problem.Constraints.O1_cost_limit = ...
            system_cost_usd <= conservative_cap;
        conservative_problem.Objective = update_count;
        conservative = solve_record(conservative_problem, count_options, ...
            'count', conservative_start);
    end

    K_lower = 0;
    if isfinite(feasibility.count_lower)
        K_lower = feasibility.count_lower;
    end
    if isfinite(optimistic.count_lower)
        K_lower = max(K_lower, optimistic.count_lower);
    end
    K_upper = NaN;
    if conservative.has_incumbent
        K_upper = conservative.count_upper;
    end
    economic(i).allowance_usd_t = allowance;
    economic(i).budget_lower_usd = conservative_cap;
    economic(i).budget_upper_usd = optimistic_cap;
    economic(i).K_lower = K_lower;
    economic(i).K_upper = K_upper;
    economic(i).is_proven = isfinite(K_lower) && isfinite(K_upper) && ...
        K_lower == K_upper;
    economic(i).optimistic = optimistic;
    economic(i).conservative = conservative;
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
study.check = struct();
study.check.reference = solution_check(reference.solution, model, config);
study.check.minimum_updates = solution_check(...
    feasibility.solution, model, config);
if representative.has_incumbent
    study.check.minimum_updates_representative = solution_check(...
        representative.solution, model, config);
end
study.status = 'complete';
print_summary(study);
end

%% 函数
function config = validate_config(config)
defaults = struct('nh3_target_t', 80000, ...
    'cost_allowance_usd_t', [0, 1, 5, 10], 'frontier_k', [], ...
    'max_time_s', 1200, 'cost_relative_gap', 1e-3, ...
    'count_absolute_gap', 0.99, 'cost_bound_tolerance_usd', 1e-4, ...
    'change_tolerance', 1e-6, 'display', 'off');
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
if ~isscalar(config.cost_bound_tolerance_usd) || ...
        config.cost_bound_tolerance_usd < 0 || ...
        ~isfinite(config.cost_bound_tolerance_usd)
    error('O1:bad_bound_tolerance', ...
        'cost_bound_tolerance_usd must be finite and nonnegative.');
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
else
    record.is_proven = exitflag > 0 && record.absolute_gap <= ...
        max(1e-7, eps(abs(fval)));
end
if record.is_proven
    record.status = "proven";
else
    record.status = "incumbent_with_bound";
end
end

function check = solution_check(solution, model, config)
HB_load = solution.HB_load(:);
HB_change = [HB_load(2:end); HB_load(1)] - HB_load;
NH3_total_t = sum(HB_load) * model.params.HB.nh3_output ...
    * model.params.time.step / model.params.unit.mass_scale;
check = struct();
check.actual_updates = sum(abs(HB_change) > config.change_tolerance);
check.binary_updates = round(sum(solution.O1_HB_change));
check.total_variation = sum(abs(HB_change));
check.maximum_change = max(abs(HB_change));
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
if study.reference.has_incumbent
    fprintf('Economic reference: [%.3f, %.3f] USD\n', ...
        study.reference.objective_lower, study.reference.objective_upper);
else
    fprintf('Economic reference: no incumbent (%s)\n', study.reference.status);
end
minimum_updates = study.feasibility.minimum_updates;
if minimum_updates.has_incumbent
    fprintf('K_feas: [%g, %g], proven=%d\n', ...
        minimum_updates.count_lower, minimum_updates.count_upper, ...
        minimum_updates.is_proven);
else
    fprintf('K_feas: no incumbent (%s)\n', minimum_updates.status);
end
if isfield(study, 'economic') && ~isempty(study.economic)
    for i = 1:numel(study.economic)
        row = study.economic(i);
        fprintf('delta=%g USD/t: K_econ=[%g, %g], proven=%d\n', ...
            row.allowance_usd_t, row.K_lower, row.K_upper, row.is_proven);
    end
end
end

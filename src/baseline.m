function result = baseline(params, renewable_data, run_options)
%BASELINE Solve the Zhou S2 annual dispatch model and assemble its results.

if nargin < 3 || isempty(run_options)
    run_options = struct();
end
verbose = option_value(run_options, 'verbose', true);

this_file = mfilename('fullpath');
source_dir = fileparts(this_file);
if verbose
    fprintf("%s\n%s", this_file, source_dir);
end
addpath(fullfile(source_dir, 'params'));
addpath(fullfile(source_dir, 'results'));

model = dispatch_model(params, renewable_data, run_options);
contract_enabled = model.contract.enabled;

solver_display = option_value(run_options, 'solver_display', 'iter');
default_relative_gap = option_value( ...
    run_options, 'relative_gap_tolerance', 1e-4);
solver_options = optimoptions('intlinprog', ...
    'Display', solver_display, ...
    'ConstraintTolerance', 1e-5, ...
    'RelativeGapTolerance', 1e-4);
solver_options.RelativeGapTolerance = default_relative_gap;
max_time_seconds = option_value(run_options, 'max_time_seconds', []);
if ~isempty(max_time_seconds)
    solver_options.MaxTime = max_time_seconds;
end

initial_solution_supplied = false;
if contract_enabled
    economic_relative_gap = option_value(run_options, ...
        'economic_relative_gap_tolerance', default_relative_gap);
    solver_options.RelativeGapTolerance = economic_relative_gap;
    initial_solution = option_value( ...
        run_options, 'initial_solution', struct());
    initial_solution = sanitize_initial_solution(initial_solution);
    if isempty(fieldnames(initial_solution))
        [sol, fval, exitflag, output] = solve(model.problem, ...
            'Solver', 'intlinprog', 'Options', solver_options);
    else
        [sol, fval, exitflag, output] = solve( ...
            model.problem, initial_solution, ...
            'Solver', 'intlinprog', 'Options', solver_options);
        initial_solution_supplied = true;
    end
    require_feasible_solution(sol, exitflag, output, ...
        'fixed contract economic dispatch', true);
else
    [sol, fval, exitflag, output] = solve(model.problem, ...
        'Solver', 'intlinprog', 'Options', solver_options);
    require_feasible_solution(sol, exitflag, output, ...
        'economic baseline', false);
end

sol.P_AEL_start = model.context.AEL_start_power_per_module * sol.SU_AEL;
if verbose && model.context.ael_common.startup
    fprintf('AEL启动耗电：%.3f MWh/a。\n', ...
        sum(sol.P_AEL_start) * model.context.dt / 1000);
end
if verbose
    print_solver_result(sol, fval, exitflag, output);
end

result = results(params, renewable_data, sol, fval, ...
    exitflag, output, model.context);
if contract_enabled
    result.contract = contract_result(result, sol, model.contract);
    result.optimization.mode = 'fixed_contract_economic_feasibility';
    result.optimization.initial_solution_supplied = ...
        initial_solution_supplied;
    result.optimization.capacity_feasible = true;
    result.optimization.economic_objective_converged = exitflag == 1;
    result.optimization.economic_relative_gap_tolerance = ...
        economic_relative_gap;
end
end

function initial_solution = sanitize_initial_solution(initial_solution)
removed_fields = {'daily_contract_kg', 'P_AEL_start'};
for field_index = 1:numel(removed_fields)
    if isfield(initial_solution, removed_fields{field_index})
        initial_solution = rmfield(initial_solution, ...
            removed_fields{field_index});
    end
end
end

function contract = contract_result(result, sol, settings)
daily_nh3_kg = sum(reshape(result.dispatch.NH3_prod, ...
    settings.samples_per_day, []), 1)';
backlog_kg = zeros(numel(daily_nh3_kg), 1);
previous_backlog = 0;
for day_index = 1:numel(daily_nh3_kg)
    previous_backlog = max(0, previous_backlog + ...
        settings.daily_quantity_kg - daily_nh3_kg(day_index));
    backlog_kg(day_index) = previous_backlog;
end

contract = struct();
contract.quantity_source = "fixed_outer_search_candidate";
contract.no_early_delivery_credit = true;
contract.max_delay_days = settings.max_delay_days;
contract.daily_quantity_kg = settings.daily_quantity_kg;
contract.day_count = numel(daily_nh3_kg);
contract.annual_quantity_t = ...
    settings.daily_quantity_kg * contract.day_count / 1000;
contract.daily_nh3_kg = daily_nh3_kg;
contract.backlog_kg = backlog_kg;
contract.maximum_backlog_kg = max(backlog_kg);
contract.max_allowed_backlog_kg = ...
    settings.max_delay_days * settings.daily_quantity_kg;
contract.terminal_backlog_kg = backlog_kg(end);
contract.delay_ok = contract.maximum_backlog_kg <= ...
    contract.max_allowed_backlog_kg + 1e-3;
contract.terminal_ok = contract.terminal_backlog_kg <= 1e-3;
contract.lcoa_cap_usd_per_t = settings.lcoa_cap_usd_per_t;
contract.selected_lcoa_usd_per_t = result.summary.lcoa;
contract.model_backlog_envelope_kg = sol.contract_backlog(2:end);
end

function require_feasible_solution(sol, exitflag, output, phase_name, ...
        accept_time_limit_incumbent)
has_incumbent = isstruct(sol) && isfield(sol, 'P_AEL') && ...
    ~isempty(sol.P_AEL);
if has_incumbent && isfield(output, 'constrviolation') && ...
        output.constrviolation > 1e-5
    has_incumbent = false;
end
if ~has_incumbent
    if exitflag == -2
        error_id = 'baseline:infeasible_problem';
    else
        error_id = 'baseline:no_feasible_solution';
    end
    error(error_id, ...
        ['%s optimization did not return a feasible dispatch. ', ...
        'Exitflag: %d. Solver message: %s'], ...
        phase_name, exitflag, output.message);
end
time_limit_incumbent_is_allowed = ...
    accept_time_limit_incumbent && exitflag == 0;
if exitflag <= 0 && ~time_limit_incumbent_is_allowed
    error('baseline:solver_not_converged', ...
        ['%s optimization returned an incumbent but did not converge. ', ...
        'Exitflag: %d. Solver message: %s'], ...
        phase_name, exitflag, output.message);
end
end

function print_solver_result(sol, fval, exitflag, output)
disp(sol);
if exitflag == 1
    disp(['最优年度成本减收益: ', num2str(fval)]);
else
    disp(['当前可行年度成本减收益: ', num2str(fval)]);
end
disp(['求解状态: ', num2str(exitflag)]);
disp(output);
end

function value = option_value(options, name, default_value)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = default_value;
end
end

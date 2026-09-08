function [result, run_info, metrics] = stage3_run_v51_contract_closed_loop(config)
%STAGE3_RUN_V51_CONTRACT_CLOSED_LOOP Test one fixed firm-contract candidate.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = setup_project_paths(mfilename('fullpath'));

dry_run = option_value(config, 'dry_run', false);
save_output = option_value(config, 'save_output', true);
stage1_mat_path = option_value(config, 'stage1_mat_path', ...
    fullfile(project_dir, 'runs', 'stage1', ...
    'zhou_s2_baseline_2022_latest.mat'));
run_dir = option_value(config, 'run_dir', ...
    fullfile(project_dir, 'runs', 'stage3'));
max_time_seconds = option_value(config, 'max_time_seconds', 300);

loaded = load_stage1_mat(stage1_mat_path);
params = loaded.params;
renewable_data = loaded.renewable_data;
stage1_result = loaded.result;
stage1_run_info = loaded.run_info;

subprotocol = protocol_v5('v5_1');
protocol_valid = protocol_v5('verify_v5_1', subprotocol);
contract = contract_capacity_plan(stage1_result, params, subprotocol, ...
    stage1_mat_path, renewable_data.time_count, config);
[seed_result, seed_source] = load_seed_result( ...
    stage1_result, stage1_mat_path, config);
warm_start = contract_warm_start(seed_result, params, ...
    contract.max_delay_days, contract.candidate_daily_kg, seed_source);
contract.warm_start = warm_start.summary;

run_info = make_run_info(project_dir, stage1_mat_path, ...
    stage1_run_info, renewable_data, protocol_valid, contract, ...
    max_time_seconds);

result = [];
metrics = [];
if dry_run
    return
end

baseline_options = struct( ...
    'verbose', option_value(config, 'verbose', true), ...
    'solver_display', option_value(config, 'solver_display', 'iter'), ...
    'max_time_seconds', max_time_seconds, ...
    'economic_relative_gap_tolerance', ...
        contract.economic_relative_gap_tolerance, ...
    'initial_solution', warm_start.values, ...
    'contract', struct( ...
        'enabled', true, ...
        'max_delay_days', contract.max_delay_days, ...
        'fixed_daily_quantity_kg', contract.candidate_daily_kg, ...
        'daily_quantity_upper_kg', contract.daily_quantity_upper_kg, ...
        'lcoa_cap_usd_per_t', contract.lcoa_cap_usd_per_t));

try
    result = baseline(params, renewable_data, baseline_options);
catch exception
    [handled, run_info] = classify_unsolved_attempt(run_info, exception);
    if ~handled
        rethrow(exception)
    end
    if save_output
        run_info.output_path = string(candidate_output_path( ...
            run_dir, run_info.data_year, contract.candidate_annual_t));
        save_stage3_output(char(run_info.output_path), result, run_info, ...
            metrics, params, renewable_data, contract, stage1_result, ...
            stage1_run_info);
    end
    print_stage3_summary(run_info, metrics, contract);
    return
end
contract = merge_contract_result(contract, result.contract);
metrics = stage3_metrics(result, stage1_result, contract, subprotocol, ...
    stage1_mat_path);
if ~(metrics.Feasibility.contract_delay_ok && ...
        metrics.Feasibility.terminal_contract_ok && ...
        metrics.Feasibility.lcoa_cap_ok)
    error('stage3_run_v51_contract_closed_loop:postsolve_check_failed', ...
        'Solved dispatch failed a contract or LCOA postsolve check.');
end
if result.optimization.economic_objective_converged
    run_info.status = "feasible_economic_optimum";
else
    run_info.status = "feasible_economic_incomplete";
end
run_info.contract = contract;
run_info.checks = metrics.Feasibility;
run_info.solver_exitflag = result.exitflag;
run_info.solver_output = result.output;

if save_output
    output_path = candidate_output_path( ...
        run_dir, run_info.data_year, contract.candidate_annual_t);
    run_info.output_path = string(output_path);
    save_stage3_output(output_path, result, run_info, metrics, params, ...
        renewable_data, contract, stage1_result, stage1_run_info);
end

print_stage3_summary(run_info, metrics, contract);

end

function loaded = load_stage1_mat(stage1_mat_path)
if isstring(stage1_mat_path) && isscalar(stage1_mat_path)
    stage1_mat_path = char(stage1_mat_path);
end
if ~isfile(stage1_mat_path)
    error('stage3_run_v51_contract_closed_loop:missing_stage1_mat', ...
        'Missing stage 1 MAT file: %s', stage1_mat_path);
end

loaded = load(stage1_mat_path, 'result', 'run_info', ...
    'params', 'renewable_data');
required_vars = {'result', 'run_info', 'params', 'renewable_data'};
for var_index = 1:numel(required_vars)
    if ~isfield(loaded, required_vars{var_index})
        error('stage3_run_v51_contract_closed_loop:bad_stage1_mat', ...
            'Stage 1 MAT file must contain %s.', required_vars{var_index});
    end
end
if ~isfield(loaded.result, 'summary') || ...
        ~all(isfield(loaded.result.summary, ...
        {'NH3_prod_t_y', 'lcoa', 'net_profit'}))
    error('stage3_run_v51_contract_closed_loop:bad_stage1_result', ...
        'Stage 1 summary must contain NH3_prod_t_y, lcoa, and net_profit.');
end
end

function contract = contract_capacity_plan(stage1_result, params, ...
        subprotocol, stage1_mat_path, time_count, config)
reference_annual_t = stage1_result.summary.NH3_prod_t_y;
baseline_lcoa = stage1_result.summary.lcoa;
if ~(isnumeric(reference_annual_t) && isscalar(reference_annual_t) && ...
        isfinite(reference_annual_t) && reference_annual_t > 0)
    error('stage3_run_v51_contract_closed_loop:bad_contract_quantity', ...
        'Stage 1 NH3 production must be a positive finite scalar.');
end
if ~(isnumeric(baseline_lcoa) && isscalar(baseline_lcoa) && ...
        isfinite(baseline_lcoa) && baseline_lcoa > 0)
    error('stage3_run_v51_contract_closed_loop:bad_baseline_lcoa', ...
        'Stage 1 LCOA must be a positive finite scalar.');
end

samples_per_day = round(24 / params.time.step);
if abs(samples_per_day - 24 / params.time.step) > 1e-9 || ...
        mod(time_count, samples_per_day) ~= 0
    error('stage3_run_v51_contract_closed_loop:bad_contract_time', ...
        'The renewable dataset must contain complete operating days.');
end
day_count = time_count / samples_per_day;
initial_candidates = ...
    subprotocol.ContractCapacityOptimization.InitialCandidatesAnnualT(:);
initial_candidates(end) = reference_annual_t;
candidate_annual_t = option_value(config, 'candidate_annual_t', ...
    initial_candidates(1));
daily_quantity_upper_kg = ...
    params.HB.max_load * params.HB.nh3_output * 24;
annual_quantity_upper_t = daily_quantity_upper_kg * day_count / 1000;
if ~(isnumeric(candidate_annual_t) && isscalar(candidate_annual_t) && ...
        isfinite(candidate_annual_t) && candidate_annual_t > 0 && ...
        candidate_annual_t <= annual_quantity_upper_t + 1e-9)
    error('stage3_run_v51_contract_closed_loop:bad_candidate_quantity', ...
        ['candidate_annual_t must be positive and no greater than the ', ...
        'HB annual production limit %.6f t.'], annual_quantity_upper_t);
end

max_lcoa_increase_fraction = option_value(config, ...
    'max_lcoa_increase_fraction', ...
    subprotocol.ContractCapacityOptimization.MaxLCOAIncreaseFraction);
if ~(isnumeric(max_lcoa_increase_fraction) && ...
        isscalar(max_lcoa_increase_fraction) && ...
        isfinite(max_lcoa_increase_fraction) && ...
        max_lcoa_increase_fraction >= 0)
    error('stage3_run_v51_contract_closed_loop:bad_lcoa_increase', ...
        'max_lcoa_increase_fraction must be a nonnegative scalar.');
end

contract = struct();
contract.quantity_source = ...
    "fixed_outer_search_candidate";
contract.reference_source = ...
    "stage1_mat_result_summary_NH3_prod_t_y";
contract.source_mat_path = string(stage1_mat_path);
contract.protocol_version = subprotocol.ProtocolVersion;
contract.protocol_seal = subprotocol.Seal;
contract.reference_annual_t = reference_annual_t;
contract.reference_daily_kg = reference_annual_t * 1000 / day_count;
contract.candidate_annual_t = candidate_annual_t;
contract.candidate_daily_kg = candidate_annual_t * 1000 / day_count;
contract.day_count = day_count;
contract.max_delay_days = subprotocol.Contract.MaxDelayDays;
contract.no_early_delivery_credit = true;
contract.equipment_scope = "existing_Zhou_S2_assets_only";
contract.daily_quantity_upper_kg = daily_quantity_upper_kg;
contract.baseline_lcoa_usd_per_t = baseline_lcoa;
contract.max_lcoa_increase_fraction = max_lcoa_increase_fraction;
contract.lcoa_cap_usd_per_t = ...
    baseline_lcoa * (1 + max_lcoa_increase_fraction);
contract.objective_method = ...
    "fixed_contract_feasibility_with_economic_inner_objective";
contract.economic_relative_gap_tolerance = option_value(config, ...
    'economic_relative_gap_tolerance', ...
    subprotocol.ContractCapacityOptimization.EconomicRelativeGapTolerance);
contract.search = struct( ...
    'method', "monotone_fixed_candidate_bracketing", ...
    'candidates_annual_t', initial_candidates, ...
    'bracket_relative_tolerance', ...
        subprotocol.ContractCapacityOptimization.ContractBracketRelativeTolerance, ...
    'infeasible_candidate_requires_slack_diagnosis', true, ...
    'timeout_without_incumbent_is_unresolved', true);
end

function [seed_result, seed_source] = load_seed_result( ...
        stage1_result, stage1_mat_path, config)
warm_start_mat_path = option_value(config, 'warm_start_mat_path', '');
if isempty(warm_start_mat_path)
    seed_result = stage1_result;
    seed_source = string(stage1_mat_path);
    return
end
if isstring(warm_start_mat_path) && isscalar(warm_start_mat_path)
    warm_start_mat_path = char(warm_start_mat_path);
end
if ~isfile(warm_start_mat_path)
    error('stage3_run_v51_contract_closed_loop:missing_warm_start_mat', ...
        'Missing warm-start MAT file: %s', warm_start_mat_path);
end
loaded = load(warm_start_mat_path, 'result');
if ~isfield(loaded, 'result') || isempty(loaded.result)
    error('stage3_run_v51_contract_closed_loop:bad_warm_start_mat', ...
        'Warm-start MAT file must contain a solved result.');
end
seed_result = loaded.result;
seed_source = string(warm_start_mat_path);
end

function warm_start = contract_warm_start(seed_result, params, ...
        max_delay_days, daily_quantity_kg, seed_source)
if ~isfield(seed_result, 'sol') || ~isstruct(seed_result.sol) || ...
        ~isfield(seed_result, 'dispatch') || ...
        ~isfield(seed_result.dispatch, 'NH3_prod')
    error('stage3_run_v51_contract_closed_loop:missing_warm_start', ...
        'Warm-start result must contain sol and dispatch.NH3_prod.');
end

samples_per_day = round(24 / params.time.step);
if abs(samples_per_day - 24 / params.time.step) > 1e-9 || ...
        mod(numel(seed_result.dispatch.NH3_prod), samples_per_day) ~= 0
    error('stage3_run_v51_contract_closed_loop:bad_warm_start_time', ...
        'Stage 1 dispatch must contain complete days.');
end
daily_nh3_kg = sum(reshape(seed_result.dispatch.NH3_prod, ...
    samples_per_day, []), 1)';
backlog_kg = contract_backlog(daily_nh3_kg, daily_quantity_kg);
is_contract_feasible = max(backlog_kg) <= ...
    max_delay_days * daily_quantity_kg + 1e-3 && ...
    backlog_kg(end) <= 1e-3;

variable_names = {'HB_load', 'I_AEL_up', 'P_AEL', 'SD_AEL', ...
    'SU_AEL', 'n_ael', 'p_curt', 'p_purchase', 'p_sell', ...
    'storage_H2', 'u_purchase'};
values = struct();
for variable_index = 1:numel(variable_names)
    name = variable_names{variable_index};
    if ~isfield(seed_result.sol, name)
        error('stage3_run_v51_contract_closed_loop:bad_warm_start', ...
            'Warm-start solution is missing %s.', name);
    end
    values.(name) = seed_result.sol.(name);
end
values.contract_backlog = [0; backlog_kg];

warm_start = struct();
warm_start.values = values;
warm_start.summary = struct( ...
    'available', true, ...
    'source', seed_source, ...
    'daily_quantity_kg', daily_quantity_kg, ...
    'annual_quantity_t', daily_quantity_kg * numel(daily_nh3_kg) / 1000, ...
    'maximum_backlog_kg', max(backlog_kg), ...
    'max_allowed_backlog_kg', max_delay_days * daily_quantity_kg, ...
    'terminal_backlog_kg', backlog_kg(end), ...
    'is_contract_feasible', is_contract_feasible);
end

function backlog_kg = contract_backlog(daily_nh3_kg, daily_quantity_kg)
backlog_kg = zeros(numel(daily_nh3_kg), 1);
previous_backlog = 0;
for day_index = 1:numel(daily_nh3_kg)
    previous_backlog = max(0, previous_backlog + ...
        daily_quantity_kg - daily_nh3_kg(day_index));
    backlog_kg(day_index) = previous_backlog;
end
end

function run_info = make_run_info(project_dir, stage1_mat_path, ...
    stage1_run_info, renewable_data, protocol_valid, contract, ...
    max_time_seconds)
run_info = struct();
run_info.stage = "stage3";
run_info.status = "ready";
run_info.executed_at = string(datetime('now', 'TimeZone', 'local'));
run_info.project_dir = string(project_dir);
run_info.model_variant = "Zhou_S2_v51_fixed_contract_search";
run_info.contract_policy = ...
    "hard_7_day_no_early_credit_terminal_zero_existing_assets_only";
run_info.stage1_mat_path = string(stage1_mat_path);
run_info.stage1_status = string(stage1_run_info.status);
run_info.data_year = stage1_run_info.data_year;
run_info.renewable_time_count = renewable_data.time_count;
run_info.protocol_valid = protocol_valid;
run_info.contract = contract;
run_info.solver_max_time_seconds = max_time_seconds;
run_info.solver_phase_count = 1;
run_info.economic_relative_gap_tolerance = ...
    contract.economic_relative_gap_tolerance;
run_info.output_path = "";
run_info.solver_log = "";
run_info.checks = struct();
run_info.solver_exitflag = [];
run_info.solver_output = struct();
run_info.solver_error = struct();
run_info.infeasibility_review = infeasibility_review_plan();
end

function plan = infeasibility_review_plan()
plan = [
    "1. Preserve the hard seven-day and terminal-zero model."
    "2. Confirm the stage1 dispatch remains feasible under the LCOA cap."
    "3. If not, add separate delay and terminal slack only in a diagnostic copy."
    "4. Minimize terminal slack, maximum daily slack, then total slack."
    "5. Report the binding dates and NH3 quantities before changing constraints."];
end

function contract = merge_contract_result(plan, solved)
contract = plan;
solved_fields = fieldnames(solved);
for field_index = 1:numel(solved_fields)
    name = solved_fields{field_index};
    contract.(name) = solved.(name);
end
contract.reference_retention_fraction = ...
    contract.annual_quantity_t / contract.reference_annual_t;
end

function metrics = stage3_metrics(result, stage1_result, contract, ...
        subprotocol, stage1_mat_path)
lcoa_increase_fraction = result.summary.lcoa ...
    / stage1_result.summary.lcoa - 1;

metrics = struct();
metrics.ProtocolVersion = subprotocol.ProtocolVersion;
metrics.ProtocolSeal = subprotocol.Seal;
metrics.SourceMatPath = string(stage1_mat_path);
metrics.Contract = contract;
metrics.Primary = struct( ...
    'contract_shortfall_p95', prctile(contract.backlog_kg, 95), ...
    'mar', mean(abs(diff(result.dispatch.HB_load))), ...
    'h2_soc_p05', prctile(result.storage.soc_work, 5));
metrics.Economic = struct( ...
    'lcoa', result.summary.lcoa, ...
    'net_profit_usd', result.summary.net_profit);
metrics.BaselineComparison = struct( ...
    'lcoa_increase_fraction', lcoa_increase_fraction, ...
    'net_profit_change_usd', result.summary.net_profit ...
        - stage1_result.summary.net_profit, ...
    'firm_contract_to_baseline_output_fraction', ...
        contract.reference_retention_fraction);
metrics.Feasibility = struct( ...
    'capacity_feasible', true, ...
    'contract_delay_ok', contract.delay_ok, ...
    'terminal_contract_ok', contract.terminal_ok, ...
    'lcoa_cap_ok', isempty(contract.lcoa_cap_usd_per_t) || ...
        result.summary.lcoa <= contract.lcoa_cap_usd_per_t + 1e-6, ...
    'maximum_contract_backlog_kg', contract.maximum_backlog_kg, ...
    'terminal_contract_backlog_kg', contract.terminal_backlog_kg);
metrics.Status = struct( ...
    'is_stage3_solution', true, ...
    'economic_objective_converged', ...
        result.optimization.economic_objective_converged, ...
    'is_confirmatory_result', false, ...
    'claim_limit', "2022_existing_asset_contract_capacity_development_result");
end

function print_stage3_summary(run_info, metrics, contract)
fprintf('\n========== Stage 3 v5.1 Contract Closed Loop ==========\n');
fprintf('Status: %s\n', run_info.status);
fprintf('Stage 1 MAT: %s\n', run_info.stage1_mat_path);
fprintf('Policy: existing assets, %d-day delay, no early credit\n', ...
    contract.max_delay_days);
fprintf('LCOA cap: %.6f USD/t-NH3\n', contract.lcoa_cap_usd_per_t);
fprintf('Candidate: %.6f t-NH3/a, %.6f kg-NH3/d\n', ...
    contract.candidate_annual_t, contract.candidate_daily_kg);
if isfield(contract, 'annual_quantity_t')
    fprintf('Firm contract: %.6f t-NH3/a, %.6f kg-NH3/d\n', ...
        contract.annual_quantity_t, contract.daily_quantity_kg);
end
if isstruct(metrics) && isfield(metrics, 'Contract')
    fprintf('contract_shortfall_p95: %.3f kg-NH3\n', ...
        metrics.Primary.contract_shortfall_p95);
    fprintf('maximum_contract_backlog: %.3f kg-NH3\n', ...
        metrics.Contract.maximum_backlog_kg);
    fprintf('terminal_contract_backlog: %.3f kg-NH3\n', ...
        metrics.Contract.terminal_backlog_kg);
    fprintf('LCOA increase: %.6f %%\n', ...
        100 * metrics.BaselineComparison.lcoa_increase_fraction);
end
if strlength(run_info.output_path) > 0
    fprintf('Saved: %s\n', run_info.output_path);
end
end

function [handled, run_info] = classify_unsolved_attempt(run_info, exception)
handled = true;
switch exception.identifier
    case 'baseline:infeasible_problem'
        run_info.status = "solver_reported_infeasible_requires_slack_diagnosis";
    case 'baseline:no_feasible_solution'
        run_info.status = "unresolved_no_integer_incumbent";
    otherwise
        handled = false;
        return
end
run_info.solver_error = struct( ...
    'identifier', string(exception.identifier), ...
    'message', string(exception.message));
end

function output_path = candidate_output_path( ...
        run_dir, data_year, candidate_annual_t)
candidate_tag = strrep(sprintf('%010.3f', candidate_annual_t), '.', 'p');
output_path = fullfile(run_dir, sprintf( ...
    'v51_contract_candidate_%st_%d_latest.mat', ...
    candidate_tag, data_year));
end

function save_stage3_output(output_path, result, run_info, metrics, ...
        params, renewable_data, contract, stage1_result, stage1_run_info)
run_dir = fileparts(output_path);
ensure_directory(run_dir);
save(output_path, 'result', 'run_info', 'metrics', 'params', ...
    'renewable_data', 'contract', 'stage1_result', 'stage1_run_info');
end

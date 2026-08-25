function metrics = evaluate_protocol_v51_metrics(mat_path)
%EVALUATE_PROTOCOL_V51_METRICS Compute v5.1 metrics from the stage 1 MAT file.

project_dir = project_root();
add_project_paths(project_dir);

if nargin < 1 || isempty(mat_path)
    mat_path = fullfile(project_dir, 'runs', 'stage1', ...
        'zhou_s2_baseline_2022_latest.mat');
end
if isstring(mat_path) && isscalar(mat_path)
    mat_path = char(mat_path);
end
if ~isfile(mat_path)
    error('evaluate_protocol_v51_metrics:missing_file', ...
        'Missing stage 1 MAT file: %s', mat_path);
end

loaded = load(mat_path, 'result', 'params', 'run_info');
required_vars = {'result', 'params', 'run_info'};
for var_index = 1:numel(required_vars)
    if ~isfield(loaded, required_vars{var_index})
        error('evaluate_protocol_v51_metrics:bad_mat_file', ...
            'MAT file must contain %s.', required_vars{var_index});
    end
end

subprotocol = protocol_v5('v5_1');
if ~protocol_v5('verify_v5_1', subprotocol)
    error('evaluate_protocol_v51_metrics:bad_protocol', ...
        'Protocol v5.1 verification failed.');
end

metrics = calculate_metrics( ...
    loaded.result, loaded.params, loaded.run_info, subprotocol, mat_path);

if nargout == 0
    print_metrics(metrics);
end
end

function metrics = calculate_metrics(result, params, run_info, ...
    subprotocol, mat_path)
validate_result_shape(result, params);

dt = params.time.step;
samples_per_day = samples_per_day_from_dt(dt);
hourly_nh3_kg = result.dispatch.NH3_prod(:);
complete_days = floor(numel(hourly_nh3_kg) / samples_per_day);
daily_nh3_kg = reshape( ...
    hourly_nh3_kg(1:complete_days * samples_per_day), ...
    samples_per_day, complete_days);
daily_nh3_kg = sum(daily_nh3_kg, 1)';

contract_rule = contract_rule_from_protocol( ...
    subprotocol.Contract, complete_days);
contract = evaluate_contract_backlog(daily_nh3_kg, contract_rule);
diagnostics = evaluate_contract_diagnostics( ...
    result, params, contract, daily_nh3_kg, samples_per_day, dt);

hb_load = result.dispatch.HB_load(:);
mar = mean(abs(diff(hb_load)));

h2_soc = result.storage.soc_work(:);
h2_soc_p05 = prctile(h2_soc, 5);

metrics = struct();
metrics.ProtocolVersion = subprotocol.ProtocolVersion;
metrics.ProtocolSeal = subprotocol.Seal;
metrics.SourceMatPath = string(mat_path);
metrics.Stage1Status = string(run_info.status);
metrics.ModelVariant = string(run_info.model_variant);
metrics.DataYear = run_info.data_year;
metrics.HourCount = numel(hourly_nh3_kg);
metrics.CompleteDays = complete_days;
metrics.Contract = contract;
metrics.Diagnostics = diagnostics;
metrics.Primary = struct( ...
    'contract_shortfall_p95', contract.shortfall_p95_kg, ...
    'mar', mar, ...
    'h2_soc_p05', h2_soc_p05);
metrics.Economic = struct( ...
    'lcoa', result.summary.lcoa, ...
    'net_profit_usd', result.summary.net_profit);
metrics.Feasibility = struct( ...
    'maximum_contract_backlog_kg', contract.maximum_backlog_kg, ...
    'terminal_contract_backlog_kg', contract.terminal_backlog_kg, ...
    'contract_delay_ok', contract.maximum_backlog_kg <= ...
        contract.max_allowed_backlog_kg + 1e-3, ...
    'terminal_contract_ok', abs(contract.terminal_backlog_kg - ...
        subprotocol.Contract.TerminalBacklogKG) <= 1e-3, ...
    'strict_delivery_ok', contract.late_cohort_count == 0 && ...
        contract.unserved_cohort_count == 0);
metrics.Baseline = struct( ...
    'nh3_t_y', result.summary.NH3_prod_t_y, ...
    'objective_usd', result.fval, ...
    'exitflag', result.exitflag, ...
    'power_residual_kw', result.check.max_power_residual_kw, ...
    'storage_residual_kg', result.check.max_storage_residual_kg);
metrics.Status = struct( ...
    'is_stage1_solution', string(run_info.status) == "solved", ...
    'is_v51_metric_ready', true, ...
    'is_confirmatory_result', false, ...
    'claim_limit', "stage1_baseline_metric_smoke_test_only");
end

function contract = evaluate_contract_backlog(daily_nh3_kg, contract_rule)
day_count = numel(daily_nh3_kg);
backlog_kg = zeros(day_count, 1);
previous_backlog = 0;

for day_index = 1:day_count
    current_backlog = previous_backlog + ...
        contract_rule.DailyQuantityKG - daily_nh3_kg(day_index);
    backlog_kg(day_index) = max(0, current_backlog);
    previous_backlog = backlog_kg(day_index);
end

contract = struct();
contract.daily_nh3_kg = daily_nh3_kg;
contract.daily_contract_kg = contract_rule.DailyQuantityKG;
contract.backlog_kg = backlog_kg;
contract.shortfall_p95_kg = prctile(backlog_kg, 95);
contract.maximum_backlog_kg = max(backlog_kg);
contract.terminal_backlog_kg = backlog_kg(end);
contract.max_allowed_backlog_kg = contract_rule.MaxBacklogKG;
contract.delay_days = contract_rule.MaxDelayDays;
contract.annual_contract_t = contract_rule.AnnualQuantityT;
contract.annual_actual_t = sum(daily_nh3_kg) / 1000;
contract.annual_surplus_t = contract.annual_actual_t - ...
    contract.annual_contract_t;
delivery = evaluate_fifo_delivery( ...
    daily_nh3_kg, contract_rule.DailyQuantityKG, ...
    contract_rule.MaxDelayDays);
contract.delivery_delay_days = delivery.delay_days;
contract.remaining_cohort_kg = delivery.remaining_kg;
contract.maximum_delivery_delay_days = delivery.maximum_delay_days;
contract.late_cohort_count = delivery.late_cohort_count;
contract.unserved_cohort_count = delivery.unserved_cohort_count;
end

function delivery = evaluate_fifo_delivery( ...
        daily_nh3_kg, daily_contract_kg, max_delay_days)
day_count = numel(daily_nh3_kg);
remaining_kg = zeros(day_count, 1);
completion_day = NaN(day_count, 1);
first_open_day = 1;
tol = 1e-6;

for delivery_day = 1:day_count
    remaining_kg(delivery_day) = daily_contract_kg;
    available_kg = daily_nh3_kg(delivery_day);
    for contract_day = first_open_day:delivery_day
        delivered_kg = min(remaining_kg(contract_day), available_kg);
        remaining_kg(contract_day) = ...
            remaining_kg(contract_day) - delivered_kg;
        available_kg = available_kg - delivered_kg;
        if remaining_kg(contract_day) <= tol
            remaining_kg(contract_day) = 0;
            completion_day(contract_day) = delivery_day;
            if contract_day == first_open_day
                while first_open_day <= delivery_day && ...
                        remaining_kg(first_open_day) == 0
                    first_open_day = first_open_day + 1;
                end
            end
        end
        if available_kg <= tol
            break
        end
    end
end

delay_days = completion_day - (1:day_count)';
completed_delays = delay_days(~isnan(delay_days));
if isempty(completed_delays)
    maximum_delay_days = NaN;
else
    maximum_delay_days = max(completed_delays);
end

delivery = struct();
delivery.delay_days = delay_days;
delivery.remaining_kg = remaining_kg;
delivery.maximum_delay_days = maximum_delay_days;
delivery.late_cohort_count = nnz(delay_days > max_delay_days);
delivery.unserved_cohort_count = nnz(remaining_kg > tol);
end

function diagnostics = evaluate_contract_diagnostics(result, params, ...
    contract, daily_nh3_kg, samples_per_day, dt)
day_count = numel(daily_nh3_kg);
complete_hour_count = day_count * samples_per_day;

hb_load = result.dispatch.HB_load(:);
hb_load = hb_load(1:complete_hour_count);
h2_soc = hourly_storage_soc(result.storage.soc_work(:), complete_hour_count);

hb_max_load = param_value(params, {'HB', 'max_load'}, NaN);
hb_ramp = param_value(params, {'HB', 'ramp_rate'}, NaN);
nh3_rate = param_value(params, {'HB', 'nh3_output'}, NaN);
ael_max_power = param_value(params, {'AEL', 'common', 'max_power'}, NaN);
transformer_kw = param_value(params, {'transformer', 'max_load'}, NaN) * ...
    param_value(params, {'transformer', 'capacity'}, NaN) * 1000;

daily = struct();
daily.day_index = (1:day_count)';
daily.start_time = daily_start_time(result, complete_hour_count, ...
    samples_per_day);
daily.daily_nh3_kg = daily_nh3_kg;
daily.daily_contract_kg = repmat(contract.daily_contract_kg, day_count, 1);
daily.daily_shortfall_kg = max(0, contract.daily_contract_kg - daily_nh3_kg);
daily.backlog_kg = contract.backlog_kg;
daily.backlog_excess_kg = max(0, ...
    contract.backlog_kg - contract.max_allowed_backlog_kg);
daily.hb_mean_load = daily_stat(hb_load, samples_per_day, @mean);
daily.hb_min_load = daily_stat(hb_load, samples_per_day, @min);
daily.hb_max_load = daily_stat(hb_load, samples_per_day, @max);
daily.h2_min_work_soc = daily_stat(h2_soc, samples_per_day, @min);
daily.h2_mean_work_soc = daily_stat(h2_soc, samples_per_day, @mean);
daily.hb_headroom_nh3_kg = daily_hb_headroom( ...
    hb_load, hb_max_load, nh3_rate, dt, samples_per_day);
daily.hb_ramp_saturated_hours = daily_ramp_saturation( ...
    hb_load, hb_ramp, samples_per_day);
daily.sell_kwh = daily_optional_sum(result.dispatch, ...
    'P_sell', complete_hour_count, samples_per_day, dt);
daily.purchase_kwh = daily_optional_sum(result.dispatch, ...
    'P_purchase', complete_hour_count, samples_per_day, dt);
daily.curtail_kwh = daily_optional_sum(result.dispatch, ...
    'P_curt', complete_hour_count, samples_per_day, dt);
daily.ael_headroom_kwh = daily_power_headroom(result.dispatch, ...
    'P_AEL', ael_max_power, complete_hour_count, samples_per_day, dt);
daily.purchase_headroom_kwh = daily_power_headroom(result.dispatch, ...
    'P_purchase', transformer_kw, complete_hour_count, samples_per_day, dt);

diagnostics = struct();
diagnostics.DecisionMethod = decision_method();
diagnostics.Daily = daily;
diagnostics.Summary = summarize_contract_diagnostics(daily, contract);
diagnostics.ReserveScreen = evaluate_h2_reserve_screen( ...
    daily, diagnostics.Summary, params);
end

function method = decision_method()
method = struct();
method.Scope = "postprocess_stage1_dispatch_no_optimization";
method.ContractViolation = ...
    "hard_breach_if_fifo_delivery_exceeds_seven_days_or_terminal_backlog_positive";
method.PrimarySignals = [ ...
    "h2_floor_share_on_decision_days"; ...
    "hb_recovery_cover_share_on_decision_days"; ...
    "hb_ramp_saturation_share_on_decision_days"; ...
    "sell_share_on_decision_days"];
method.H2FloorWorkSOCThreshold = 0.01;
method.DominantBottleneckRule = [ ...
    "h2_floor_share>=0.5 => hydrogen_inventory_floor_binding"; ...
    "hb_cover<0.5 and ramp_share>=0.5 => hb_ramp_or_capacity_limited"; ...
    "hb_cover>=0.5 and sell_share>=0.2 => contract_blind_economic_dispatch_with_sell_revenue"; ...
    "hb_cover>=0.5 => contract_blind_dispatch_timing"; ...
    "otherwise => mixed_or_inconclusive"];
end

function summary = summarize_contract_diagnostics(daily, contract)
tol = 1e-3;
h2_floor_threshold = 0.01;
breach_mask = daily.backlog_kg > contract.max_allowed_backlog_kg + tol;
positive_backlog_mask = daily.backlog_kg > tol;
deficit_mask = daily.daily_shortfall_kg > tol;
terminal_violation = contract.terminal_backlog_kg > tol;
decision_mask = breach_mask;
if terminal_violation
    decision_mask(end) = true;
end

recovery_need_kg = max(daily.backlog_excess_kg, daily.daily_shortfall_kg);
if terminal_violation
    recovery_need_kg(end) = max(recovery_need_kg(end), ...
        contract.terminal_backlog_kg);
end

summary = struct();
summary.daily_contract_kg = contract.daily_contract_kg;
summary.max_allowed_backlog_kg = contract.max_allowed_backlog_kg;
summary.first_positive_backlog_day = first_index(positive_backlog_mask);
summary.first_daily_deficit_day = first_index(deficit_mask);
summary.first_delay_violation_day = first_index(breach_mask);
summary.max_backlog_day = first_index( ...
    daily.backlog_kg == max(daily.backlog_kg));
summary.max_daily_shortfall_day = first_index( ...
    daily.daily_shortfall_kg == max(daily.daily_shortfall_kg));
summary.delay_violation_day_count = nnz(breach_mask);
summary.deficit_day_count = nnz(deficit_mask);
summary.positive_backlog_day_count = nnz(positive_backlog_mask);
summary.terminal_backlog_kg = contract.terminal_backlog_kg;
summary.max_backlog_kg = contract.maximum_backlog_kg;
summary.max_backlog_excess_kg = max(daily.backlog_excess_kg);
summary.max_daily_shortfall_kg = max(daily.daily_shortfall_kg);
summary.h2_floor_share_on_decision_days = true_share( ...
    daily.h2_min_work_soc(decision_mask) <= h2_floor_threshold);
summary.hb_recovery_cover_share_on_decision_days = true_share( ...
    daily.hb_headroom_nh3_kg(decision_mask) + tol >= ...
    recovery_need_kg(decision_mask));
summary.hb_ramp_saturation_share_on_decision_days = true_share( ...
    daily.hb_ramp_saturated_hours(decision_mask) > 0);
summary.sell_share_on_decision_days = true_share( ...
    daily.sell_kwh(decision_mask) > tol);
summary.dominant_bottleneck = classify_bottleneck(summary, ...
    any(decision_mask));
end

function label = classify_bottleneck(summary, has_decision_days)
if ~has_decision_days
    label = "no_contract_breach";
elseif summary.h2_floor_share_on_decision_days >= 0.5
    label = "hydrogen_inventory_floor_binding";
elseif summary.hb_recovery_cover_share_on_decision_days < 0.5 && ...
        summary.hb_ramp_saturation_share_on_decision_days >= 0.5
    label = "hb_ramp_or_capacity_limited";
elseif summary.hb_recovery_cover_share_on_decision_days >= 0.5 && ...
        summary.sell_share_on_decision_days >= 0.2
    label = "contract_blind_economic_dispatch_with_sell_revenue";
elseif summary.hb_recovery_cover_share_on_decision_days >= 0.5
    label = "contract_blind_dispatch_timing";
else
    label = "mixed_or_inconclusive";
end
end

function reserve = evaluate_h2_reserve_screen(daily, summary, params)
h2_per_nh3 = param_value(params, {'HB', 'lit_h2'}, NaN);
h2_density = param_value(params, {'unit', 'h2_density'}, NaN);
work_mass = param_value(params, {'h2_storage', 'work_mass'}, NaN);
max_mass = param_value(params, {'h2_storage', 'mass'}, NaN);

excess = daily.backlog_excess_kg(:);
incremental_extra_nh3 = max(0, diff([0; excess]));
headroom_shortfall = max(0, ...
    incremental_extra_nh3 - daily.hb_headroom_nh3_kg(:));

reserve = struct();
reserve.Method = ...
    "optimistic_postprocess_lower_bound_keep_ael_h2_production_trajectory";
reserve.Assumptions = [ ...
    "annual_contract_quantity_comes_from_stage1_mat"; ...
    "ael_h2_production_trajectory_is_not_reoptimized"; ...
    "extra_nh3_uses_additional_h2_reserve_at_HB_lit_h2_ratio"; ...
    "hourly_hb_ramp_and_power_coupling_are_not_enforced_in_this_screen"];
reserve.nh3_equivalent_for_delay_cap_kg = summary.max_backlog_excess_kg;
reserve.h2_for_delay_cap_kg = ...
    summary.max_backlog_excess_kg * h2_per_nh3;
reserve.h2_for_delay_cap_nm3 = reserve.h2_for_delay_cap_kg / h2_density;
reserve.working_storage_multiple = reserve.h2_for_delay_cap_kg / work_mass;
reserve.total_storage_mass_multiple = reserve.h2_for_delay_cap_kg / max_mass;
reserve.terminal_clearance_nh3_equivalent_kg = summary.terminal_backlog_kg;
reserve.h2_for_terminal_clearance_kg = ...
    summary.terminal_backlog_kg * h2_per_nh3;
reserve.h2_for_terminal_clearance_nm3 = ...
    reserve.h2_for_terminal_clearance_kg / h2_density;
reserve.terminal_working_storage_multiple = ...
    reserve.h2_for_terminal_clearance_kg / work_mass;
reserve.incremental_extra_nh3_kg = incremental_extra_nh3;
reserve.max_daily_incremental_extra_nh3_kg = max(incremental_extra_nh3);
reserve.max_daily_incremental_extra_day = first_index( ...
    incremental_extra_nh3 == reserve.max_daily_incremental_extra_nh3_kg);
reserve.headroom_shortfall_day_count = nnz(headroom_shortfall > 1e-9);
reserve.max_headroom_shortfall_nh3_kg = max(headroom_shortfall);
reserve.decision = classify_reserve_screen(reserve);
reserve.WindowSensitivity = evaluate_delay_window_sensitivity( ...
    daily, summary, params, [3; 7; 14]);
end

function decision = classify_reserve_screen(reserve)
if reserve.h2_for_delay_cap_kg <= 1e-9
    decision = "no_extra_reserve_required_for_delay_cap";
elseif reserve.working_storage_multiple > 1
    decision = "reserve_requirement_exceeds_existing_working_storage";
elseif reserve.headroom_shortfall_day_count > 0
    decision = "reactive_hb_headroom_insufficient_requires_anticipatory_dispatch";
else
    decision = "reserve_screen_passes_for_next_contract_aware_dispatch_check";
end
end

function sensitivity = evaluate_delay_window_sensitivity(daily, summary, ...
    params, delay_days)
h2_per_nh3 = param_value(params, {'HB', 'lit_h2'}, NaN);
h2_density = param_value(params, {'unit', 'h2_density'}, NaN);
work_mass = param_value(params, {'h2_storage', 'work_mass'}, NaN);
max_mass = param_value(params, {'h2_storage', 'mass'}, NaN);

delay_days = delay_days(:);
window_count = numel(delay_days);
tol = 1e-9;

sensitivity = struct();
sensitivity.Method = ...
    "same_stage1_backlog_trace_only_delay_window_changes";
sensitivity.delay_days = delay_days;
sensitivity.allowed_backlog_kg = delay_days * summary.daily_contract_kg;
sensitivity.violation_day_count = zeros(window_count, 1);
sensitivity.first_violation_day = NaN(window_count, 1);
sensitivity.max_backlog_excess_kg = zeros(window_count, 1);
sensitivity.nh3_equivalent_for_delay_cap_kg = zeros(window_count, 1);
sensitivity.h2_for_delay_cap_kg = zeros(window_count, 1);
sensitivity.h2_for_delay_cap_nm3 = zeros(window_count, 1);
sensitivity.working_storage_multiple = zeros(window_count, 1);
sensitivity.total_storage_mass_multiple = zeros(window_count, 1);
sensitivity.max_daily_incremental_extra_nh3_kg = zeros(window_count, 1);
sensitivity.max_daily_incremental_extra_day = NaN(window_count, 1);
sensitivity.headroom_shortfall_day_count = zeros(window_count, 1);
sensitivity.max_headroom_shortfall_nh3_kg = zeros(window_count, 1);
sensitivity.policy_note = strings(window_count, 1);
sensitivity.decision = strings(window_count, 1);

for window_index = 1:window_count
    allowed_backlog = sensitivity.allowed_backlog_kg(window_index);
    excess = max(0, daily.backlog_kg(:) - allowed_backlog);
    incremental_extra_nh3 = max(0, diff([0; excess]));
    headroom_shortfall = max(0, ...
        incremental_extra_nh3 - daily.hb_headroom_nh3_kg(:));

    sensitivity.violation_day_count(window_index) = nnz(excess > tol);
    sensitivity.first_violation_day(window_index) = first_index(excess > tol);
    sensitivity.max_backlog_excess_kg(window_index) = max(excess);
    sensitivity.nh3_equivalent_for_delay_cap_kg(window_index) = ...
        sensitivity.max_backlog_excess_kg(window_index);
    sensitivity.h2_for_delay_cap_kg(window_index) = ...
        sensitivity.max_backlog_excess_kg(window_index) * h2_per_nh3;
    sensitivity.h2_for_delay_cap_nm3(window_index) = ...
        sensitivity.h2_for_delay_cap_kg(window_index) / h2_density;
    sensitivity.working_storage_multiple(window_index) = ...
        sensitivity.h2_for_delay_cap_kg(window_index) / work_mass;
    sensitivity.total_storage_mass_multiple(window_index) = ...
        sensitivity.h2_for_delay_cap_kg(window_index) / max_mass;
    sensitivity.max_daily_incremental_extra_nh3_kg(window_index) = ...
        max(incremental_extra_nh3);
    sensitivity.max_daily_incremental_extra_day(window_index) = ...
        first_index(incremental_extra_nh3 > tol & ...
        incremental_extra_nh3 == ...
        sensitivity.max_daily_incremental_extra_nh3_kg(window_index));
    sensitivity.headroom_shortfall_day_count(window_index) = ...
        nnz(headroom_shortfall > tol);
    sensitivity.max_headroom_shortfall_nh3_kg(window_index) = ...
        max(headroom_shortfall);

    if delay_days(window_index) <= 7
        sensitivity.policy_note(window_index) = ...
            "within_preferred_contract_delay_window";
    else
        sensitivity.policy_note(window_index) = ...
            "stress_sensitivity_beyond_preferred_delay_window";
    end
    sensitivity.decision(window_index) = classify_delay_window_screen( ...
        sensitivity.h2_for_delay_cap_kg(window_index), ...
        sensitivity.working_storage_multiple(window_index), ...
        sensitivity.headroom_shortfall_day_count(window_index));
end
end

function decision = classify_delay_window_screen(h2_for_delay_cap_kg, ...
    working_storage_multiple, headroom_shortfall_day_count)
if h2_for_delay_cap_kg <= 1e-9
    decision = "no_extra_reserve_required_for_delay_cap";
elseif working_storage_multiple > 1
    decision = "reserve_requirement_exceeds_existing_working_storage";
elseif headroom_shortfall_day_count > 0
    decision = "reactive_hb_headroom_insufficient_requires_anticipatory_dispatch";
else
    decision = "reserve_screen_passes_for_next_contract_aware_dispatch_check";
end
end

function values = hourly_storage_soc(storage_soc, complete_hour_count)
if numel(storage_soc) == complete_hour_count + 1
    values = storage_soc(2:end);
else
    values = storage_soc(1:complete_hour_count);
end
end

function values = daily_start_time(result, complete_hour_count, samples_per_day)
values = NaT(complete_hour_count / samples_per_day, 1);
if ~isfield(result, 'time') || ~isdatetime(result.time)
    return
end
hourly_time = result.time(:);
if numel(hourly_time) < complete_hour_count
    return
end
hourly_time = hourly_time(1:complete_hour_count);
values = hourly_time(1:samples_per_day:end);
end

function values = daily_stat(hourly_values, samples_per_day, stat_fn)
day_count = floor(numel(hourly_values) / samples_per_day);
hourly_values = hourly_values(1:day_count * samples_per_day);
values_by_day = reshape(hourly_values, samples_per_day, day_count);
if strcmp(func2str(stat_fn), 'mean')
    values = mean(values_by_day, 1)';
else
    values = stat_fn(values_by_day, [], 1)';
end
end

function values = daily_hb_headroom(hb_load, hb_max_load, nh3_rate, dt, ...
    samples_per_day)
if isnan(hb_max_load) || isnan(nh3_rate)
    values = NaN(numel(hb_load) / samples_per_day, 1);
    return
end
hourly_headroom = max(0, hb_max_load - hb_load) * nh3_rate * dt;
values = daily_sum(hourly_headroom, samples_per_day);
end

function values = daily_ramp_saturation(hb_load, hb_ramp, samples_per_day)
if isnan(hb_ramp)
    values = NaN(numel(hb_load) / samples_per_day, 1);
    return
end
ramp_abs = [0; abs(diff(hb_load))];
values = daily_sum(double(ramp_abs >= hb_ramp - 1e-9), samples_per_day);
end

function values = daily_optional_sum(source, field_name, hour_count, ...
    samples_per_day, dt)
if isfield(source, field_name)
    hourly_values = source.(field_name)(:);
    hourly_values = hourly_values(1:hour_count) * dt;
    values = daily_sum(hourly_values, samples_per_day);
else
    values = NaN(hour_count / samples_per_day, 1);
end
end

function values = daily_power_headroom(source, field_name, max_power, ...
    hour_count, samples_per_day, dt)
if isfield(source, field_name) && ~isnan(max_power)
    hourly_values = source.(field_name)(:);
    hourly_values = max(0, max_power - hourly_values(1:hour_count)) * dt;
    values = daily_sum(hourly_values, samples_per_day);
else
    values = NaN(hour_count / samples_per_day, 1);
end
end

function values = daily_sum(hourly_values, samples_per_day)
day_count = floor(numel(hourly_values) / samples_per_day);
hourly_values = hourly_values(1:day_count * samples_per_day);
values_by_day = reshape(hourly_values, samples_per_day, day_count);
values = sum(values_by_day, 1)';
end

function index = first_index(mask)
index = find(mask, 1, 'first');
if isempty(index)
    index = NaN;
end
end

function value = true_share(mask)
if isempty(mask)
    value = NaN;
else
    value = mean(double(mask(:)));
end
end

function value = param_value(source, path, default_value)
value = source;
for path_index = 1:numel(path)
    field_name = path{path_index};
    if ~isstruct(value) || ~isfield(value, field_name)
        value = default_value;
        return
    end
    value = value.(field_name);
end
if ~(isnumeric(value) && isscalar(value) && isfinite(value))
    value = default_value;
end
end

function validate_result_shape(result, params)
if ~isfield(result, 'dispatch') || ~isfield(result.dispatch, 'NH3_prod') || ...
        ~isfield(result.dispatch, 'HB_load')
    error('evaluate_protocol_v51_metrics:bad_result', ...
        'result.dispatch must contain NH3_prod and HB_load.');
end
if ~isfield(result, 'storage') || ~isfield(result.storage, 'soc_work')
    error('evaluate_protocol_v51_metrics:bad_result', ...
        'result.storage must contain soc_work.');
end
if ~isfield(result, 'summary') || ~isfield(result.summary, 'lcoa') || ...
        ~isfield(result.summary, 'net_profit') || ...
        ~isfield(result.summary, 'NH3_prod_t_y')
    error('evaluate_protocol_v51_metrics:bad_result', ...
        'result.summary must contain NH3_prod_t_y, lcoa, and net_profit.');
end
samples_per_day_from_dt(params.time.step);
end

function contract_rule = contract_rule_from_protocol(contract_rule, day_count)
annual_contract_t = contract_rule.AnnualQuantityT;
daily_contract_kg = contract_rule.DailyQuantityKG;
if ~isnumeric(annual_contract_t) || ~isscalar(annual_contract_t) || ...
        ~isfinite(annual_contract_t) || annual_contract_t <= 0 || ...
        ~isnumeric(daily_contract_kg) || ~isscalar(daily_contract_kg) || ...
        ~isfinite(daily_contract_kg) || daily_contract_kg <= 0
    error('evaluate_protocol_v51_metrics:bad_contract_quantity', ...
        'Frozen annual and daily contract quantities must be positive.');
end
if abs(daily_contract_kg * day_count / 1000 - annual_contract_t) > 1e-6
    error('evaluate_protocol_v51_metrics:contract_calendar_mismatch', ...
        'Frozen annual and daily contracts do not match %d complete days.', ...
        day_count);
end
contract_rule.MaxBacklogKG = ...
    daily_contract_kg * contract_rule.MaxDelayDays;
end

function samples_per_day = samples_per_day_from_dt(dt)
samples_per_day_exact = 24 / dt;
samples_per_day = round(samples_per_day_exact);
if abs(samples_per_day - samples_per_day_exact) > 1e-9
    error('evaluate_protocol_v51_metrics:bad_time_step', ...
        'Time step must divide 24 hours exactly.');
end
end

function project_dir = project_root()
results_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(results_dir);
project_dir = fileparts(src_dir);
end

function add_project_paths(project_dir)
addpath(fullfile(project_dir, 'src'));
addpath(fullfile(project_dir, 'src', 'params'));
addpath(fullfile(project_dir, 'src', 'results'));
addpath(fullfile(project_dir, 'src', 'protocol'));
end

function print_metrics(metrics)
fprintf('\n========== Protocol v5.1 Metrics ==========\n');
fprintf('Source: %s\n', metrics.SourceMatPath);
fprintf('Protocol: %s / %s\n', ...
    metrics.ProtocolVersion, metrics.ProtocolSeal);
fprintf('Data year: %d, hours: %d, complete days: %d\n', ...
    metrics.DataYear, metrics.HourCount, metrics.CompleteDays);
fprintf('contract_shortfall_p95: %.3f kg-NH3\n', ...
    metrics.Primary.contract_shortfall_p95);
fprintf('MAR: %.8f fraction/h\n', metrics.Primary.mar);
fprintf('h2_soc_p05: %.8f fraction\n', metrics.Primary.h2_soc_p05);
fprintf('LCOA: %.6f USD/t-NH3\n', metrics.Economic.lcoa);
fprintf('maximum_contract_backlog: %.3f kg-NH3\n', ...
    metrics.Feasibility.maximum_contract_backlog_kg);
fprintf('terminal_contract_backlog: %.3f kg-NH3\n', ...
    metrics.Feasibility.terminal_contract_backlog_kg);
fprintf('maximum FIFO delivery delay: %.0f days\n', ...
    metrics.Contract.maximum_delivery_delay_days);
fprintf('late/unserved contract cohorts: %d/%d\n', ...
    metrics.Contract.late_cohort_count, ...
    metrics.Contract.unserved_cohort_count);
fprintf('annual actual-contract surplus: %.3f t-NH3\n', ...
    metrics.Contract.annual_surplus_t);
end

% TEST_CI_VERTIFY Evaluate the locked core indicators on a real MILP result.
% Run src/main.m first so results, params, and renewable_data exist in the
% current workspace. This script does not solve or modify the optimization.

required_variables = ["results", "params", "renewable_data"];
for variable_index = 1:numel(required_variables)
    variable_name = char(required_variables(variable_index));
    if exist(variable_name, 'var') ~= 1
        error('test_CI_vertify:missing_workspace_input', ...
            ['Missing workspace variable "%s". Run src/main.m first, ', ...
            'then run test/test_CI_vertify.m in the same workspace.'], ...
            variable_name);
    end
end

CI_protocol = struct();
CI_protocol.version = "4.0.0";
CI_protocol.seal = "731C9F86";
CI_protocol.core_metrics = ["daily_shortfall_p95"; "mar"; ...
    "switch_count"; "h2_soc_p05"];
CI_protocol.hard_safety_metric = "h2_min_margin";
CI_protocol.h2_safe_soc = 0.20;
CI_protocol.scope = "real_MILP_dispatch_descriptive_validation";

CI_validation = evaluate_real_dispatch(...
    results, params, renewable_data, CI_protocol);
print_validation(CI_validation);

function validation = evaluate_real_dispatch(...
        result, params, renewable_data, protocol)
must_be_feasible_result(result);
dt = must_positive_scalar(params.time.step, 'params.time.step');

hb_load = required_dispatch_vector(result, 'HB_load');
sample_count = numel(hb_load);
nh3_step_kg = ammonia_vector(result, params, hb_load, dt);
storage_h2_kg = required_dispatch_vector(result, 'storage_H2');

if numel(nh3_step_kg) ~= sample_count
    error('test_CI_vertify:bad_nh3_length', ...
        'NH3 production and HB load must have the same number of samples.');
end
if numel(storage_h2_kg) == sample_count + 1
    storage_h2_kg = storage_h2_kg(2:end);
elseif numel(storage_h2_kg) ~= sample_count
    error('test_CI_vertify:bad_storage_length', ...
        'H2 storage must contain T or T+1 samples.');
end
if any(~isfinite([hb_load; nh3_step_kg; storage_h2_kg]))
    error('test_CI_vertify:nonfinite_dispatch', ...
        'Real dispatch inputs must contain only finite values.');
end

[hb_on, hb_state_source] = identify_hb_state(result, params, hb_load);
[daily_shortfall_p95, daily_output_kg, complete_days, discarded_samples] = ...
    daily_shortfall_metric(nh3_step_kg, dt);

online_transition = hb_on(1:(end - 1)) == 1 & hb_on(2:end) == 1;
hourly_ramp = abs(diff(hb_load)) / dt;
if any(online_transition)
    mar = mean(hourly_ramp(online_transition));
else
    mar = NaN;
end
switch_count = sum(abs(diff(hb_on)));

h2_capacity_kg = must_positive_scalar(...
    params.h2_storage.mass, 'params.h2_storage.mass');
h2_soc = storage_h2_kg / h2_capacity_kg;
h2_soc_p05 = prctile(h2_soc, 5);
h2_min_margin = min(h2_soc - protocol.h2_safe_soc);
h2_risk_hours = sum(h2_soc < protocol.h2_safe_soc) * dt;

metric = protocol.core_metrics;
value = [daily_shortfall_p95; mar; switch_count; h2_soc_p05];
unit = ["fraction"; "fraction/h"; "events/a"; "fraction"];
direction = ["larger_is_worse"; "larger_is_worse"; ...
    "larger_is_worse"; "larger_is_better"];
role = ["lower-tail ammonia delivery"; "online HB load variation"; ...
    "HB binary-state transitions"; "statistical H2 reserve"];
computable = isfinite(value);
applicability = repmat("computed_from_real_dispatch", 4, 1);
if all(hb_on == 1)
    applicability(metric == "switch_count") = ...
        "computed_but_not_discriminative_in_always_on_HB_model";
end
validation.core_metrics = table(metric, value, unit, direction, role, ...
    computable, applicability, 'VariableNames', {'Metric', 'Value', ...
    'Unit', 'Direction', 'Role', 'Computable', 'Applicability'});

hard_status = "pass";
if h2_min_margin < -1e-12
    hard_status = "fail";
end
validation.hard_safety = table(protocol.hard_safety_metric, ...
    h2_min_margin, "fraction", protocol.h2_safe_soc, h2_risk_hours, ...
    hard_status, 'VariableNames', {'Metric', 'Value', 'Unit', ...
    'SafetySOC', 'RiskHours', 'Status'});

validation.protocol = protocol;
validation.data = struct();
validation.data.year = identify_data_year(result, renewable_data);
validation.data.sample_count = sample_count;
validation.data.time_step_h = dt;
validation.data.complete_days = complete_days;
validation.data.discarded_samples = discarded_samples;
validation.data.daily_nh3_output_kg = daily_output_kg;
validation.data.hb_state_source = hb_state_source;
validation.data.is_2025_holdout = validation.data.year == "2025";

validation.diagnostics = struct();
validation.diagnostics.minimum_hb_load = min(hb_load);
validation.diagnostics.maximum_hb_load = max(hb_load);
validation.diagnostics.maximum_hb_ramp = max(hourly_ramp);
validation.diagnostics.minimum_h2_soc = min(h2_soc);
validation.diagnostics.maximum_h2_soc = max(h2_soc);
validation.diagnostics.hb_switching_observed = any(diff(hb_on) ~= 0);
validation.diagnostics.all_core_computable = all(computable);
validation.diagnostics.h2_hard_safety_pass = hard_status == "pass";
validation.diagnostics.legacy_zhou_dcv = legacy_dcv(result);

validation.confirmatory_claim_allowed = false;
if all(hb_on == 1)
    validation.conclusion = "real_dispatch_metrics_computed_but_" + ...
        "switching_discrimination_is_not_identifiable";
else
    validation.conclusion = "real_dispatch_metrics_computed_descriptive_only";
end
validation.note = "This run checks computability and physical meaning on " + ...
    "one real MILP dispatch. It does not reselect metrics and does not by " + ...
    "itself constitute independent 2025 confirmation.";
end

function must_be_feasible_result(result)
if ~isstruct(result) || ~isfield(result, 'exitflag') || ...
        ~(isnumeric(result.exitflag) && isscalar(result.exitflag) && ...
        result.exitflag > 0)
    error('test_CI_vertify:infeasible_result', ...
        'results must be a feasible baseline output with exitflag > 0.');
end
end

function values = required_dispatch_vector(result, field_name)
if ~isfield(result, 'dispatch') || ...
        ~isfield(result.dispatch, field_name)
    error('test_CI_vertify:missing_dispatch_field', ...
        'results.dispatch.%s is required.', field_name);
end
values = result.dispatch.(field_name);
values = values(:);
end

function values = ammonia_vector(result, params, hb_load, dt)
if isfield(result, 'dispatch') && isfield(result.dispatch, 'NH3_prod')
    values = result.dispatch.NH3_prod(:);
else
    values = hb_load * params.HB.nh3_output * dt;
end
end

function [hb_on, source] = identify_hb_state(result, params, hb_load)
tolerance = 1e-8;
if isfield(result, 'dispatch') && isfield(result.dispatch, 'HB_on')
    hb_on = result.dispatch.HB_on(:);
    source = "results.dispatch.HB_on";
elseif isfield(result, 'sol') && isfield(result.sol, 'HB_on')
    hb_on = result.sol.HB_on(:);
    source = "results.sol.HB_on";
elseif params.HB.min_load > 0 && ...
        all(hb_load >= params.HB.min_load - tolerance)
    hb_on = ones(size(hb_load));
    source = "model_lower_bound_implies_always_on";
else
    error('test_CI_vertify:missing_hb_binary_state', ...
        ['HB switching cannot be verified without an explicit HB_on ', ...
        'variable when zero-load operation is permitted.']);
end

if numel(hb_on) ~= numel(hb_load) || ...
        any(abs(hb_on - round(hb_on)) > tolerance) || ...
        any(hb_on < -tolerance | hb_on > 1 + tolerance)
    error('test_CI_vertify:bad_hb_binary_state', ...
        'HB_on must be a binary vector with the same length as HB_load.');
end
hb_on = round(hb_on);
end

function [metric, daily_output, day_count, discarded] = ...
        daily_shortfall_metric(nh3_step_kg, dt)
samples_per_day_exact = 24 / dt;
samples_per_day = round(samples_per_day_exact);
if abs(samples_per_day - samples_per_day_exact) > 1e-9
    error('test_CI_vertify:unsupported_time_step', ...
        'The time step must divide 24 hours exactly.');
end
day_count = floor(numel(nh3_step_kg) / samples_per_day);
if day_count < 2
    error('test_CI_vertify:insufficient_days', ...
        'At least two complete days are required.');
end
used_samples = day_count * samples_per_day;
discarded = numel(nh3_step_kg) - used_samples;
daily_output = sum(reshape(nh3_step_kg(1:used_samples), ...
    samples_per_day, day_count), 1)';
mean_output = mean(daily_output);
if mean_output <= eps
    error('test_CI_vertify:zero_ammonia_output', ...
        'Mean daily ammonia output must be positive.');
end
relative_shortfall = max(mean_output - daily_output, 0) / mean_output;
metric = prctile(relative_shortfall, 95);
end

function year_text = identify_data_year(result, renewable_data)
year_text = "unknown";
if isfield(result, 'time') && isdatetime(result.time) && ~isempty(result.time)
    years = unique(year(result.time));
elseif isfield(renewable_data, 'time') && ...
        isdatetime(renewable_data.time) && ~isempty(renewable_data.time)
    years = unique(year(renewable_data.time));
else
    years = [];
end
if isscalar(years)
    year_text = string(years);
elseif numel(years) > 1
    year_text = strjoin(string(years), ',');
end
end

function value = legacy_dcv(result)
value = NaN;
if isfield(result, 'summary') && ...
        isfield(result.summary, 'NH3_daily_cumulative_volatility')
    value = result.summary.NH3_daily_cumulative_volatility;
end
end

function value = must_positive_scalar(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
    error('test_CI_vertify:bad_positive_scalar', ...
        '%s must be a positive finite scalar.', name);
end
end

function print_validation(validation)
fprintf('\n========== Real-dispatch core-indicator validation ==========\n');
fprintf('Protocol: v%s / Seal %s\n', ...
    validation.protocol.version, validation.protocol.seal);
fprintf('Data year: %s; samples: %d; complete days: %d; dt: %.3f h\n', ...
    validation.data.year, validation.data.sample_count, ...
    validation.data.complete_days, validation.data.time_step_h);
fprintf('HB state source: %s\n', validation.data.hb_state_source);
disp(validation.core_metrics);
fprintf('Hard H2 safety audit:\n');
disp(validation.hard_safety);
fprintf('Conclusion: %s\n', validation.conclusion);
fprintf('%s\n', validation.note);
fprintf('=============================================================\n');
end

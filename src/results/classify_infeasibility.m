function diagnosis = classify_infeasibility(record)
%CLASSIFY_INFEASIBILITY Rule-based failure classification for MILP runs.
%   The classifier is diagnostic evidence, not a feasibility proof.

record = load_record(record);
run_info = get_field(record, 'run_info', struct());
failure_context = get_field(record, 'failure_context', struct());
params = get_field(record, 'params', struct());

diagnosis = struct();
diagnosis.status = "diagnosed";
diagnosis.method = "rule_based_v1";
diagnosis.failure_day = failure_day(run_info, failure_context);
diagnosis.failure_stage = failure_stage(run_info);
diagnosis.categories = strings(0, 1);
diagnosis.primary_category = "unknown";
diagnosis.evidence = struct();
diagnosis.limitations = ...
    "Rule-based classification identifies likely binding mechanisms; " + ...
    "it does not replace a formal IIS or slack-minimization proof.";

message_text = lower(join([ ...
    field_string(run_info, 'error_id'), ...
    field_string(run_info, 'error_message'), ...
    field_string(run_info, 'status'), ...
    field_string(run_info, 'scheme'), ...
    field_string(run_info, 'forecast_mode')], " "));
state = get_field(failure_context, 'state', struct());

if contains(message_text, "realtime_production_projection")
    diagnosis.categories = add_category(diagnosis.categories, ...
        "renewable_absorption_recourse_binding");
    diagnosis.evidence.realtime_projection_failed = true;
    if has_field(state, 'ael_online_modules')
        diagnosis.categories = add_category(diagnosis.categories, ...
            "ael_commitment_recourse_binding");
        diagnosis.evidence.ael_online_modules = ...
            scalar_or_nan(state.ael_online_modules);
    end
    if has_field(state, 'hb_load')
        diagnosis.categories = add_category(diagnosis.categories, ...
            "hb_commitment_recourse_binding");
        diagnosis.evidence.hb_load = scalar_or_nan(state.hb_load);
    end
end

if contains(message_text, "carbon") || positive_carbon_debt(run_info)
    diagnosis.categories = add_category(diagnosis.categories, ...
        "carbon_budget_binding");
    diagnosis.evidence.carbon_state = get_field( ...
        run_info, 'carbon_state', struct());
end

[h2_kg, h2_lower_kg] = h2_state_evidence(state, params);
if isfinite(h2_kg)
    diagnosis.evidence.h2_kg = h2_kg;
end
if isfinite(h2_lower_kg)
    diagnosis.evidence.h2_lower_kg = h2_lower_kg;
end
if isfinite(h2_kg) && isfinite(h2_lower_kg) && ...
        h2_kg <= h2_lower_kg + 1e-3
    diagnosis.categories = add_category(diagnosis.categories, ...
        "h2_inventory_binding");
end

scheme = field_string(run_info, 'scheme');
contract_scheme = scheme == "contract_plan_and_hb_smoothing" || ...
    scheme == "joint_contract_h2_trajectory_coordination";
if contains(message_text, "contract") || ...
        (contract_scheme && has_field(state, 'contract_cohorts_kg'))
    diagnosis.categories = add_category(diagnosis.categories, ...
        "contract_delivery_binding");
end

if isempty(diagnosis.categories)
    diagnosis.categories = "unclassified_solver_infeasibility";
end
diagnosis.primary_category = choose_primary_category( ...
    diagnosis.categories);
end

function record = load_record(record)
if ischar(record) || isstring(record)
    record = load(char(record));
elseif ~isstruct(record)
    error('classify_infeasibility:bad_input', ...
        'Input must be a MAT path or a struct.');
end
end

function value = get_field(data, name, default_value)
if isstruct(data) && isfield(data, name)
    value = data.(name);
else
    value = default_value;
end
end

function tf = has_field(data, name)
tf = isstruct(data) && isfield(data, name);
end

function value = field_string(data, name)
value = "";
if has_field(data, name)
    value = string(data.(name));
end
end

function day_value = failure_day(run_info, failure_context)
day_value = NaN;
if has_field(run_info, 'failed_day')
    day_value = double(run_info.failed_day);
elseif has_field(failure_context, 'day_index')
    day_value = double(failure_context.day_index);
end
end

function stage = failure_stage(run_info)
stage = "unknown";
if has_field(run_info, 'error_message')
    message_text = lower(string(run_info.error_message));
    if contains(message_text, "realtime_production_projection")
        stage = "realtime_production_projection";
    elseif contains(message_text, "day_ahead")
        stage = "day_ahead_projection";
    elseif contains(message_text, "terminal")
        stage = "terminal_feasibility_check";
    end
end
end

function tf = positive_carbon_debt(run_info)
tf = false;
if has_field(run_info, 'carbon_state')
    carbon_state = run_info.carbon_state;
    if has_field(carbon_state, 'debt_kg')
        tf = isfinite(double(carbon_state.debt_kg)) && ...
            double(carbon_state.debt_kg) > 1e-6;
    end
end
if has_field(run_info, 'final_carbon_debt_kg')
    tf = tf || double(run_info.final_carbon_debt_kg) > 1e-6;
end
end

function [h2_kg, h2_lower_kg] = h2_state_evidence(state, params)
h2_kg = NaN;
h2_lower_kg = NaN;
if has_field(state, 'h2_kg')
    h2_kg = scalar_or_nan(state.h2_kg);
end
try
    if has_field(params, 'h2_storage') && has_field(params, 'unit') && ...
            has_field(params.unit, 'h2_density')
        limits = h2_storage_limits(params.h2_storage, ...
            params.unit.h2_density);
        h2_lower_kg = limits.min_mass;
    end
catch
end
end

function value = scalar_or_nan(input_value)
value = NaN;
if isnumeric(input_value) && isscalar(input_value)
    value = double(input_value);
end
end

function categories = add_category(categories, name)
name = string(name);
if ~any(categories == name)
    categories(end + 1, 1) = name;
end
end

function primary = choose_primary_category(categories)
priority = [ ...
    "renewable_absorption_recourse_binding"; ...
    "carbon_budget_binding"; ...
    "h2_inventory_binding"; ...
    "contract_delivery_binding"; ...
    "ael_commitment_recourse_binding"; ...
    "hb_commitment_recourse_binding"; ...
    "unclassified_solver_infeasibility"];
primary = categories(1);
for index = 1:numel(priority)
    if any(categories == priority(index))
        primary = priority(index);
        return
    end
end
end

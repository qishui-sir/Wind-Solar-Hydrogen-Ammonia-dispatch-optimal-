function report = run_feasibility_boundary(config)
%RUN_FEASIBILITY_BOUNDARY Plan or run strict feasibility boundary cases.
%   The default is a dry plan. Set execute=true to run expensive cases.

if nargin < 1 || isempty(config)
    config = struct();
end

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath'));
years = double(option_value(config, 'years', [2022, 2023, 2024, 2025]));
years = years(:);
execute = logical(option_value(config, 'execute', false));
resume = logical(option_value(config, 'resume', true));
save_output = logical(option_value(config, 'save_output', true));
boundary_dir = char(option_value(config, 'boundary_dir', ...
    fullfile(project_dir, 'runs', 'feasibility_boundary')));
summarize_existing = logical(option_value(config, ...
    'summarize_existing', execute));
requested_layers = string(option_value(config, 'layers', all_layers()));
forecast_seed = double(option_value(config, 'forecast_seed', 1));
fallback = option_value(config, 'forecast_fallback', []);
if isempty(fallback)
    fallback = build_development_forecast_fallback();
end

records = repmat(empty_record(), 0, 1);
for year_index = 1:numel(years)
    year_value = years(year_index);
    specs = layer_specs(requested_layers);
    for spec_index = 1:numel(specs)
        spec = specs(spec_index);
        records(end + 1, 1) = evaluate_case(project_dir, year_value, ...
            boundary_dir, spec.layer, spec.scheme, spec.forecast_mode, execute, ...
            fallback, forecast_seed, resume); %#ok<AGROW>
    end
end

cases = struct2table(records);
if summarize_existing
    failure_summary = summarize_failure_diagnostics(boundary_dir);
else
    failure_summary = struct2table(repmat(empty_failure_record(), 0, 1));
end
report = struct( ...
    'created_at', string(datetime('now')), ...
    'execute', execute, ...
    'boundary_dir', string(boundary_dir), ...
    'FailureSummary', failure_summary, ...
    'Cases', cases);

if save_output
    ensure_directory(boundary_dir);
    save(fullfile(boundary_dir, 'feasibility_boundary_latest.mat'), ...
        'report');
    writetable(cases, fullfile(boundary_dir, ...
        'feasibility_boundary_latest.csv'));
    writetable(failure_summary, fullfile(boundary_dir, ...
        'failure_diagnosis_summary_latest.csv'));
end
end

function record = evaluate_case(project_dir, year_value, boundary_dir, layer, scheme, ...
        forecast_mode, execute, fallback, forecast_seed, resume)
record = empty_record();
record.year = year_value;
record.layer = layer;
record.scheme = scheme;
record.forecast_mode = forecast_mode;
record.forecast_seed = forecast_seed;
record.allow_infeasible_continuation = false;
record.confirmatory_role = "feasibility_boundary_not_optimization";
record.status = "planned";

stage1_mat = fullfile(project_dir, 'runs', 'stage1', ...
    sprintf('zhou_s2_baseline_%d_latest.mat', year_value));
record.source_mat_path = string(stage1_mat);

if layer == "annual_oracle"
    record.output_path = string(stage1_mat);
else
    record.output_path = rolling_boundary_path(boundary_dir, layer, ...
        year_value);
end

if layer == "rolling_oracle_strict" && ~ismember(year_value, [2022, 2023])
    record.status = "protocol_blocked";
    record.error_id = "run_feasibility_boundary:oracle_year_forbidden";
    record.error_message = ...
        "observed_oracle rolling dispatch is restricted to 2022/2023.";
    return
end
if ~execute
    return
end
if resume
    record = reuse_existing_result(record, year_value, scheme, ...
        forecast_mode);
    if record.status ~= "planned"
        return
    end
end

try
    if layer == "annual_oracle"
        run_annual_case(year_value);
    else
        if ~isfile(stage1_mat)
            run_annual_case(year_value);
        end
        rolling_config = struct( ...
            'source_mat_path', stage1_mat, ...
            'scheme', scheme, ...
            'forecast_mode', forecast_mode, ...
            'forecast_seed', forecast_seed, ...
            'allow_infeasible_continuation', false, ...
            'output_dir', rolling_boundary_dir(boundary_dir, layer), ...
            'save_output', true, ...
            'verbose', false, ...
            'solver_display', 'none');
        if ismember(forecast_mode, ...
                ["simulated_persistence", "simulated_residual_scenario"])
            rolling_config.forecast_fallback = fallback;
        end
        rolling_dispatch(rolling_config);
    end
    record.status = "completed";
catch exception
    record.status = "failed";
    record.error_id = string(exception.identifier);
    record.error_message = one_line_message(exception.message);
    record = attach_diagnosis(record);
end
end

function record = reuse_existing_result(record, year_value, scheme, ...
        forecast_mode)
if ~isfile(record.output_path)
    return
end
try
    loaded = load(record.output_path, 'run_info');
catch
    return
end
if ~isfield(loaded, 'run_info')
    return
end
run_info = loaded.run_info;
if record.layer == "annual_oracle"
    if isfield(run_info, 'data_year') && ...
            double(run_info.data_year) == year_value && ...
            isfield(run_info, 'status') && ...
            string(run_info.status) == "solved"
        record.status = "completed";
    end
    return
end
if ~run_info_matches(run_info, year_value, scheme, forecast_mode)
    return
end
if isfield(run_info, 'status') && string(run_info.status) == "completed"
    record.status = "completed";
elseif isfield(run_info, 'status') && ...
        string(run_info.status) == "requires_slack_diagnosis"
    record.status = "failed";
    record.error_id = field_or_empty(run_info, 'error_id');
    record.error_message = one_line_message( ...
        field_or_empty(run_info, 'error_message'));
    record = attach_diagnosis(record);
end
end

function ok = run_info_matches(run_info, year_value, scheme, forecast_mode)
ok = isfield(run_info, 'data_year') && ...
    double(run_info.data_year) == year_value && ...
    isfield(run_info, 'scheme') && string(run_info.scheme) == scheme && ...
    isfield(run_info, 'forecast_mode') && ...
    string(run_info.forecast_mode) == forecast_mode;
end

function value = field_or_empty(data, field_name)
value = "";
if isstruct(data) && isfield(data, field_name)
    value = string(data.(field_name));
end
end

function message = one_line_message(message)
message = regexprep(string(message), '\s+', ' ');
message = strtrim(message);
end

function run_annual_case(year_value)
stage1_run_zhou_s2_baseline(struct( ...
    'data_year', year_value, ...
    'save_output', true));
end

function record = attach_diagnosis(record)
if ~isfile(record.output_path)
    return
end
try
    diagnosis = classify_infeasibility(record.output_path);
    record.diagnosis_primary_category = diagnosis.primary_category;
    if isfield(diagnosis, 'failure_day')
        record.failed_day = double(diagnosis.failure_day);
    end
catch
end
end

function summary = summarize_failure_diagnostics(boundary_dir)
files = dir(fullfile(boundary_dir, 'rolling', '*', '*.mat'));
records = repmat(empty_failure_record(), 0, 1);
for index = 1:numel(files)
    mat_path = fullfile(files(index).folder, files(index).name);
    try
        loaded = load(mat_path, 'run_info', 'failure_context', ...
            'diagnosis', 'params');
        if ~is_failure_record(loaded)
            continue
        end
        records(end + 1, 1) = failure_record_from_mat( ...
            mat_path, loaded); %#ok<AGROW>
    catch exception
        records(end + 1, 1) = load_failure_record( ...
            mat_path, exception); %#ok<AGROW>
    end
end
summary = struct2table(records);
if ~isempty(summary)
    summary = sortrows(summary, {'year', 'layer'});
end
end

function tf = is_failure_record(loaded)
tf = isfield(loaded, 'failure_context') || isfield(loaded, 'diagnosis');
if isfield(loaded, 'run_info') && isfield(loaded.run_info, 'status')
    tf = tf || string(loaded.run_info.status) == ...
        "requires_slack_diagnosis";
end
end

function record = failure_record_from_mat(mat_path, loaded)
record = empty_failure_record();
run_info = get_struct_field(loaded, 'run_info', struct());
failure_context = get_struct_field(loaded, 'failure_context', struct());
params = get_struct_field(loaded, 'params', struct());
if isfield(loaded, 'diagnosis')
    diagnosis = loaded.diagnosis;
else
    diagnosis = classify_infeasibility(loaded);
end

[~, layer] = fileparts(fileparts(mat_path));
record.year = scalar_field_or_nan(run_info, 'data_year');
record.layer = string(layer);
record.forecast_mode = string_field_or_empty(run_info, 'forecast_mode');
record.failed_day = scalar_field_or_nan(run_info, 'failed_day');
if isnan(record.failed_day) && isfield(diagnosis, 'failure_day')
    record.failed_day = double(diagnosis.failure_day);
end
record.failure_stage = string_field_or_empty(diagnosis, 'failure_stage');
record.primary_category = string_field_or_empty( ...
    diagnosis, 'primary_category');
record.category_list = join_string_values( ...
    get_struct_field(diagnosis, 'categories', strings(0, 1)));
record.error_id = string_field_or_empty(run_info, 'error_id');
record.error_message = one_line_message( ...
    string_field_or_empty(run_info, 'error_message'));
record.carbon_debt_kg = carbon_debt_or_nan(run_info);
record.state_h2_kg = nested_scalar_or_nan( ...
    failure_context, {'state', 'h2_kg'});
record.h2_lower_kg = h2_lower_bound_or_nan(params);
if isfinite(record.state_h2_kg) && isfinite(record.h2_lower_kg)
    record.h2_margin_kg = record.state_h2_kg - record.h2_lower_kg;
end
record.contract_backlog_kg = contract_backlog_or_nan(failure_context);
record.carbon_reserve_kg = scalar_field_or_nan( ...
    failure_context, 'carbon_reserve_kg');
record.base_carbon_reserve_kg = scalar_field_or_nan( ...
    failure_context, 'base_carbon_reserve_kg');
record.h2_carbon_guard_kg = scalar_field_or_nan( ...
    failure_context, 'h2_carbon_guard_kg');
record.commit_min_nh3_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'production', ...
    'commit_min_nh3_kg'});
record.due_at_commit_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'production', ...
    'due_at_commit_kg'});
record.allowable_backlog_after_commit_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'production', ...
    'allowable_backlog_after_commit_kg'});
record.initial_emissions_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', ...
    'initial_emissions_kg'});
record.initial_nh3_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', 'initial_nh3_kg'});
record.remaining_reference_nh3_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', ...
    'remaining_reference_nh3_kg'});
record.reference_nh3_per_step_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', ...
    'reference_nh3_per_step_kg'});
record.commit_reserve_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', ...
    'commit_reserve_kg'});
record.horizon_reserve_kg = nested_scalar_or_nan( ...
    failure_context, {'plan_options', 'carbon', ...
    'horizon_reserve_kg'});
record.restoration_day_count = restoration_count_or_nan(run_info);
record.mat_path = string(mat_path);
end

function record = load_failure_record(mat_path, exception)
record = empty_failure_record();
[~, layer] = fileparts(fileparts(mat_path));
record.layer = string(layer);
record.primary_category = "summary_load_failed";
record.error_id = string(exception.identifier);
record.error_message = one_line_message(exception.message);
record.mat_path = string(mat_path);
end

function output_path = rolling_boundary_path(boundary_dir, layer, year_value)
output_path = fullfile(rolling_boundary_dir(boundary_dir, layer), ...
    sprintf('v51_contract_plan_and_hb_smoothing_%d_latest.mat', ...
    year_value));
end

function output_dir = rolling_boundary_dir(boundary_dir, layer)
output_dir = fullfile(boundary_dir, 'rolling', char(layer));
end

function layers = all_layers()
layers = [ ...
    "annual_oracle"; ...
    "rolling_oracle_strict"; ...
    "rolling_persistence_strict"; ...
    "rolling_residual_strict"];
end

function specs = layer_specs(requested_layers)
valid_layers = all_layers();
requested_layers = requested_layers(:);
unknown = setdiff(requested_layers, valid_layers);
if ~isempty(unknown)
    error('run_feasibility_boundary:bad_layer', ...
        'Unknown feasibility boundary layer: %s.', ...
        strjoin(cellstr(unknown), ', '));
end

specs = repmat(struct('layer', "", 'scheme', "", ...
    'forecast_mode', ""), numel(requested_layers), 1);
for index = 1:numel(requested_layers)
    layer = requested_layers(index);
    specs(index).layer = layer;
    switch layer
        case "annual_oracle"
            specs(index).scheme = "annual_fixed_horizon";
            specs(index).forecast_mode = "observed_full_year";
        case "rolling_oracle_strict"
            specs(index).scheme = "contract_plan_and_hb_smoothing";
            specs(index).forecast_mode = "observed_oracle";
        case "rolling_persistence_strict"
            specs(index).scheme = "contract_plan_and_hb_smoothing";
            specs(index).forecast_mode = "simulated_persistence";
        case "rolling_residual_strict"
            specs(index).scheme = "contract_plan_and_hb_smoothing";
            specs(index).forecast_mode = "simulated_residual_scenario";
    end
end
end

function record = empty_record()
record = struct( ...
    'year', NaN, ...
    'layer', "", ...
    'scheme', "", ...
    'forecast_mode', "", ...
    'forecast_seed', NaN, ...
    'failed_day', NaN, ...
    'allow_infeasible_continuation', false, ...
    'confirmatory_role', "", ...
    'status', "", ...
    'source_mat_path', "", ...
    'output_path', "", ...
    'error_id', "", ...
    'error_message', "", ...
    'diagnosis_primary_category', "");
end

function record = empty_failure_record()
record = struct( ...
    'year', NaN, ...
    'layer', "", ...
    'forecast_mode', "", ...
    'failed_day', NaN, ...
    'failure_stage', "", ...
    'primary_category', "", ...
    'category_list', "", ...
    'error_id', "", ...
    'error_message', "", ...
    'carbon_debt_kg', NaN, ...
    'state_h2_kg', NaN, ...
    'h2_lower_kg', NaN, ...
    'h2_margin_kg', NaN, ...
    'contract_backlog_kg', NaN, ...
    'carbon_reserve_kg', NaN, ...
    'base_carbon_reserve_kg', NaN, ...
    'h2_carbon_guard_kg', NaN, ...
    'commit_min_nh3_kg', NaN, ...
    'due_at_commit_kg', NaN, ...
    'allowable_backlog_after_commit_kg', NaN, ...
    'initial_emissions_kg', NaN, ...
    'initial_nh3_kg', NaN, ...
    'remaining_reference_nh3_kg', NaN, ...
    'reference_nh3_per_step_kg', NaN, ...
    'commit_reserve_kg', NaN, ...
    'horizon_reserve_kg', NaN, ...
    'restoration_day_count', NaN, ...
    'mat_path', "");
end

function value = get_struct_field(data, field_name, default_value)
if isstruct(data) && isfield(data, field_name)
    value = data.(field_name);
else
    value = default_value;
end
end

function value = string_field_or_empty(data, field_name)
value = "";
if isstruct(data) && isfield(data, field_name)
    value = string(data.(field_name));
end
end

function value = scalar_field_or_nan(data, field_name)
value = NaN;
if isstruct(data) && isfield(data, field_name)
    value = scalar_or_nan(data.(field_name));
end
end

function value = nested_scalar_or_nan(data, fields)
value = NaN;
current = data;
for index = 1:numel(fields)
    if ~isstruct(current) || ~isfield(current, fields{index})
        return
    end
    current = current.(fields{index});
end
value = scalar_or_nan(current);
end

function value = scalar_or_nan(input_value)
value = NaN;
if isnumeric(input_value) && isscalar(input_value)
    value = double(input_value);
end
end

function text = join_string_values(values)
if isempty(values)
    text = "";
    return
end
text = strjoin(cellstr(string(values(:))), '|');
text = string(text);
end

function value = carbon_debt_or_nan(run_info)
value = nested_scalar_or_nan(run_info, {'carbon_state', 'debt_kg'});
if isnan(value)
    value = scalar_field_or_nan(run_info, 'final_carbon_debt_kg');
end
end

function value = h2_lower_bound_or_nan(params)
value = NaN;
try
    if isfield(params, 'h2_storage') && isfield(params, 'unit') && ...
            isfield(params.unit, 'h2_density')
        limits = h2_storage_limits(params.h2_storage, ...
            params.unit.h2_density);
        value = double(limits.min_mass);
    end
catch
end
end

function value = contract_backlog_or_nan(failure_context)
value = nested_scalar_or_nan(failure_context, ...
    {'state', 'contract_backlog_kg'});
if ~isnan(value)
    return
end
if isstruct(failure_context) && isfield(failure_context, 'state') && ...
        isfield(failure_context.state, 'contract_cohorts_kg') && ...
        isnumeric(failure_context.state.contract_cohorts_kg)
    value = double(sum(failure_context.state.contract_cohorts_kg(:)));
end
end

function value = restoration_count_or_nan(run_info)
value = NaN;
if isstruct(run_info) && isfield(run_info, 'production_pacing_history') && ...
        isfield(run_info.production_pacing_history, 'day_ahead_restored')
    value = double(sum(run_info.production_pacing_history ...
        .day_ahead_restored(:) ~= 0));
end
end

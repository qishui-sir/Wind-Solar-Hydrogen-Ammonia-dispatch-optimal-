function report = run_feasibility_boundary(config)
%RUN_FEASIBILITY_BOUNDARY Plan or run strict feasibility boundary cases.
%   The default is a dry plan. Set execute=true to run expensive cases.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
years = double(option_value(config, 'years', [2022, 2023, 2024, 2025]));
years = years(:);
execute = logical(option_value(config, 'execute', false));
save_output = logical(option_value(config, 'save_output', true));
fallback = option_value(config, 'forecast_fallback', []);
if isempty(fallback)
    fallback = build_development_forecast_fallback();
end

records = repmat(empty_record(), 0, 1);
for year_index = 1:numel(years)
    year_value = years(year_index);
    records(end + 1, 1) = evaluate_case(project_dir, year_value, ...
        "annual_oracle", "annual_fixed_horizon", "observed_full_year", ...
        execute, []); %#ok<AGROW>
    records(end + 1, 1) = evaluate_case(project_dir, year_value, ...
        "rolling_oracle_strict", "contract_plan_and_hb_smoothing", ...
        "observed_oracle", execute, fallback); %#ok<AGROW>
    records(end + 1, 1) = evaluate_case(project_dir, year_value, ...
        "rolling_simulated_strict", "contract_plan_and_hb_smoothing", ...
        "simulated_persistence", execute, fallback); %#ok<AGROW>
end

cases = struct2table(records);
report = struct( ...
    'created_at', string(datetime('now')), ...
    'execute', execute, ...
    'Cases', cases);

if save_output
    output_dir = fullfile(project_dir, 'runs', 'feasibility_boundary');
    ensure_directory(output_dir);
    save(fullfile(output_dir, 'feasibility_boundary_latest.mat'), ...
        'report');
    writetable(cases, fullfile(output_dir, ...
        'feasibility_boundary_latest.csv'));
end
end

function record = evaluate_case(project_dir, year_value, layer, scheme, ...
        forecast_mode, execute, fallback)
record = empty_record();
record.year = year_value;
record.layer = layer;
record.scheme = scheme;
record.forecast_mode = forecast_mode;
record.allow_infeasible_continuation = false;
record.confirmatory_role = "feasibility_boundary_not_optimization";
record.status = "planned";

stage1_mat = fullfile(project_dir, 'runs', 'stage1', ...
    sprintf('zhou_s2_baseline_%d_latest.mat', year_value));
record.source_mat_path = string(stage1_mat);

if layer == "annual_oracle"
    record.output_path = string(stage1_mat);
else
    record.output_path = rolling_boundary_path(project_dir, layer, ...
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
            'allow_infeasible_continuation', false, ...
            'output_dir', rolling_boundary_dir(project_dir, layer), ...
            'save_output', true, ...
            'verbose', false, ...
            'solver_display', 'none');
        if forecast_mode == "simulated_persistence"
            rolling_config.forecast_fallback = fallback;
        end
        rolling_dispatch(rolling_config);
    end
    record.status = "completed";
catch exception
    record.status = "failed";
    record.error_id = string(exception.identifier);
    record.error_message = string(exception.message);
    record = attach_diagnosis(record);
end
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
catch
end
end

function output_path = rolling_boundary_path(project_dir, layer, year_value)
output_path = fullfile(rolling_boundary_dir(project_dir, layer), ...
    sprintf('v51_contract_plan_and_hb_smoothing_%d_latest.mat', ...
    year_value));
end

function output_dir = rolling_boundary_dir(project_dir, layer)
output_dir = fullfile(project_dir, 'runs', 'feasibility_boundary', ...
    'rolling', char(layer));
end

function record = empty_record()
record = struct( ...
    'year', NaN, ...
    'layer', "", ...
    'scheme', "", ...
    'forecast_mode', "", ...
    'allow_infeasible_continuation', false, ...
    'confirmatory_role', "", ...
    'status', "", ...
    'source_mat_path', "", ...
    'output_path', "", ...
    'error_id', "", ...
    'error_message', "", ...
    'diagnosis_primary_category', "");
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(genpath(src_dir));
end

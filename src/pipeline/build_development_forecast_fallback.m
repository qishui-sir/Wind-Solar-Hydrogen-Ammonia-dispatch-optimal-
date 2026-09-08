function fallback = build_development_forecast_fallback()
%BUILD_DEVELOPMENT_FORECAST_FALLBACK 24-hour fallback profile from 2022/2023.
%   Returns the hour-of-day median PV and wind profiles across the frozen
%   2022/2023 development years, per protocol v5.1 forecast rules. 2024/2025
%   runs must use this external fallback and must not derive it from the
%   target year (no target-year leakage).

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath')); %#ok<NASGU>

pv_2022 = load_res_year(struct('year', 2022));
pw_2022 = load_res_year(struct('year', 2022));
pv_2023 = load_res_year(struct('year', 2023));
pw_2023 = load_res_year(struct('year', 2023));

pv_all = [pv_2022.pv_power_kw(:); pv_2023.pv_power_kw(:)];
pw_all = [pw_2022.pw_power_kw(:); pw_2023.pw_power_kw(:)];

if numel(pv_all) ~= numel(pw_all) || mod(numel(pv_all), 24) ~= 0
    error('build_development_forecast_fallback:bad_shape', ...
        'Development-year profiles must share a 24-hour-aligned length.');
end

fallback = struct();
fallback.source_years = [2022, 2023];
fallback.pv_power_kw = median(reshape(pv_all, 24, []), 2);
fallback.pw_power_kw = median(reshape(pw_all, 24, []), 2);
fallback.residual_library = build_residual_library({pv_2022, pv_2023});
fallback.residual_method = ...
    "target_hour_observed_minus_previous_day_same_hour_persistence";
end

function residual_library = build_residual_library(development_data)
resource = strings(0, 1);
month_value = zeros(0, 1);
hour_value = zeros(0, 1);
residual_kw = zeros(0, 1);

for data_index = 1:numel(development_data)
    data = development_data{data_index};
    target_indices = (25:data.time_count)';
    previous_indices = target_indices - 24;
    target_month = month(data.time(target_indices));
    target_hour = hour(data.time(target_indices)) + 1;

    pv_residual = data.pv_power_kw(target_indices) ...
        - data.pv_power_kw(previous_indices);
    pw_residual = data.pw_power_kw(target_indices) ...
        - data.pw_power_kw(previous_indices);

    row_count = numel(target_indices);
    resource = [resource; repmat("pv", row_count, 1); ...
        repmat("pw", row_count, 1)]; %#ok<AGROW>
    month_value = [month_value; target_month; target_month]; %#ok<AGROW>
    hour_value = [hour_value; target_hour; target_hour]; %#ok<AGROW>
    residual_kw = [residual_kw; pv_residual(:); pw_residual(:)]; %#ok<AGROW>
end

residual_library = table(resource, month_value, hour_value, residual_kw, ...
    'VariableNames', {'resource', 'month', 'hour', 'residual_kw'});
end

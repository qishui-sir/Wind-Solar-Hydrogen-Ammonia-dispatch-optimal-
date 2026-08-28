function fallback = build_development_forecast_fallback()
%BUILD_DEVELOPMENT_FORECAST_FALLBACK 24-hour fallback profile from 2022/2023.
%   Returns the hour-of-day median PV and wind profiles across the frozen
%   2022/2023 development years, per protocol v5.1 forecast rules. 2024/2025
%   runs must use this external fallback and must not derive it from the
%   target year (no target-year leakage).

project_dir = bootstrap_project(); %#ok<NASGU>

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
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(fullfile(src_dir, 'utils'), '-begin');
project_dir = setup_project_paths(project_dir);
end

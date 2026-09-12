% RUN_7DAY_LOG: run the baseline MILP for a configurable horizon, log to file.
% Usage:
%   run_7day_log(day_count, out_csv)
% Writes a tidy summary CSV once the solve finishes.

function run_7day_log(day_count, out_csv)
if nargin < 1 || isempty(day_count)
    day_count = 7;
end
if nargin < 2 || isempty(out_csv)
    out_csv = fullfile(tempdir, 'dispatch_summary.csv');
end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'figures'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

fprintf('[%s] loading renewable data (%d days)\n', datestr(now,'HH:MM:SS'), day_count);
data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = day_count;
renewable_data = load_res_year(data_cfg);
fprintf('[%s] renewable rows = %d\n', datestr(now,'HH:MM:SS'), renewable_data.time_count);

fprintf('[%s] building params\n', datestr(now,'HH:MM:SS'));
params = my_system('s2');
params.AEL.common.startup = true;
fprintf('[%s] AEL modules=%d module_power=%.1f kW max_power=%.1f kW\n', ...
    datestr(now,'HH:MM:SS'), params.AEL.common.module_num, ...
    params.AEL.common.module_power, params.AEL.common.max_power);

fprintf('[%s] starting MILP solve\n', datestr(now,'HH:MM:SS'));
t_start = tic;
results = baseline(params, renewable_data);
elapsed = toc(t_start);
fprintf('[%s] solve finished in %.1f s\n', datestr(now,'HH:MM:SS'), elapsed);

s = results.summary;
row = table( ...
    string(params.scenario.id), day_count, renewable_data.time_count, elapsed, ...
    s.NH3_prod_t_y, s.lcoa, s.net_profit, s.ael_equiv_hours, ...
    s.AEL_startup_count, s.sell_rate, s.curtail_rate, s.purchase_rate, ...
    s.co2_intensity, s.h2_min_abs_soc, s.h2_min_work_soc, s.h2_p05_work_soc, ...
    s.NH3_daily_cumulative_volatility, ...
    'VariableNames', {'scenario','days','rows','elapsed_s','nh3_t','lcoa_usd_t', ...
    'net_profit_usd','ael_hours','ael_startups','sell_rate','curtail_rate', ...
    'purchase_rate','co2_intensity','h2_min_abs_soc','h2_min_work_soc', ...
    'h2_p05_work_soc','nh3_dcv'});
writetable(row, out_csv);
fprintf('[%s] wrote %s\n', datestr(now,'HH:MM:SS'), out_csv);

% Also persist the full dispatch for later analysis.
mat_path = fullfile(project_dir, 'results_out', sprintf('dispatch_%dd_%s.mat', day_count, params.scenario.id));
if ~isfolder(fullfile(project_dir, 'results_out'))
    mkdir(fullfile(project_dir, 'results_out'));
end
params_save = params; %#ok<NASGU>
results_save = results; %#ok<NASGU>
renewable_save = renewable_data; %#ok<NASGU>
save(mat_path, 'params_save', 'results_save', 'renewable_save', '-v7.3');
fprintf('[%s] wrote %s\n', datestr(now,'HH:MM:SS'), mat_path);
end

% RUN_RESERVE: price operational stability by imposing a hydrogen working-reserve floor.
%
% Usage: run_reserve(day_count, reserves, year)
%   day_count : horizon length in days (default 30)
%   reserves  : vector of working-SOC reserve floors, e.g. [0 0.10 0.20 0.35]
%   year      : renewable data year (default 2022)
%
% For each reserve floor the model is re-solved on the same renewable window and
% the full operational-stability report is written to one row per reserve level.

function run_reserve(day_count, reserves, year, gap)
if nargin < 1 || isempty(day_count); day_count = 30; end
if nargin < 2 || isempty(reserves); reserves = [0, 0.10, 0.20, 0.35]; end
if nargin < 3 || isempty(year); year = 2022; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

out_dir = fullfile(project_dir, 'results_out');
if ~isfolder(out_dir); mkdir(out_dir); end
tag = sprintf('%dd_%d', day_count, year);

fprintf('[%s] reserve sweep: %d days, year %d, %d reserve levels\n', ...
    stamp(), day_count, year, numel(reserves));

data_cfg = struct();
data_cfg.pv_year = year;
data_cfg.pw_year = year;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = day_count;
renewable_data = load_res_year(data_cfg);
fprintf('[%s] rows=%d\n', stamp(), renewable_data.time_count);

rows = cell(numel(reserves), 1);
for k = 1:numel(reserves)
    res = reserves(k);
    fprintf('\n[%s] ===== reserve floor = %.3f =====\n', stamp(), res);
    params = my_system('s2');
    params.AEL.common.startup = true;
    params.h2_storage.min_work_soc = res;
    if nargin >= 4 && ~isempty(gap)
        params.solver.relative_gap = gap;
    end

    t0 = tic;
    try
        results = baseline(params, renewable_data);
    catch err
        fprintf('[%s] reserve %.3f FAILED: %s\n', stamp(), res, err.message);
        continue
    end
    elapsed = toc(t0);
    m = metrics_local(results, params);
    m.reserve_floor = res;
    m.year = year;
    m.day_count = day_count;
    m.elapsed_s = elapsed;
    m.nh3_t = results.summary.NH3_prod_t_y;
    m.lcoa_usd_t = results.summary.lcoa;
    m.sell_rate = results.summary.sell_rate;
    m.curtail_rate = results.summary.curtail_rate;
    m.purchase_rate = results.summary.purchase_rate;
    m.raw_objective = results.fval;
    % Cost decomposition, so a fixed-cost-spreading effect is not mistaken for an
    % operating-cost change.
    m.cost_purchase = results.cost.purchase;
    m.cost_sell_revenue = results.cost.sell_revenue;
    m.cost_curtail = results.cost.curtail;
    m.cost_raw_material = results.cost.raw_material;
    m.cost_variable = results.cost.variable;
    m.nh3_income = results.economics.INC.ammonia;
    rows{k} = m;

    params_save = params; %#ok<NASGU>
    results_save = results; %#ok<NASGU>
    renewable_save = renewable_data; %#ok<NASGU>
    save(fullfile(out_dir, sprintf('reserve_%s_%03d.mat', tag, round(res*1000))), ...
        'params_save', 'results_save', 'renewable_save', '-v7.3');
    fprintf('[%s] reserve %.3f done in %.1f s: LCOA=%.2f, NH3=%.1f t, minSOC=%.4f\n', ...
        stamp(), res, elapsed, m.lcoa_usd_t, m.nh3_t, m.h2_min_work_soc);
end

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    error('run_reserve:all_failed', 'No reserve level solved.');
end
T = struct2table([rows{:}]);
writetable(T, fullfile(out_dir, sprintf('reserve_sweep_%s.csv', tag)));
fprintf('\n[%s] wrote reserve_sweep_%s.csv\n', stamp(), tag);

% ---- paper-ready comparison table ----
show = {'reserve_floor', 'nh3_t', 'lcoa_usd_t', 'h2_min_work_soc', ...
    'h2_p05_work_soc', 'h2_risk_hours', 'h2_empty_hours', 'daily_shortfall_p95', ...
    'switch_count', 'mod_start_events', 'mod_units_started', 'ael_start_energy_mwh', ...
    'ramp_p95', 'curtail_rate', 'sell_rate', 'purchase_rate'};
disp(T(:, show));
fprintf('[%s] === reserve sweep done ===\n', stamp());
end

function t = stamp(); t = datestr(now, 'HH:MM:SS'); end

function m = metrics_local(results, params)
dt = params.time.step;
P_AEL = results.dispatch.P_AEL(:);
N_AEL = results.dispatch.N_AEL(:);
HB = results.dispatch.HB_load(:);
soc_work = results.storage.soc_work(:);
NH3 = results.dispatch.NH3_prod(:);
T = results.dispatch.P_total;

m = struct();
m.ael_energy_share = sum(P_AEL) / max(sum(T), eps);
dN = diff([0; N_AEL]);
m.mod_start_events = sum(dN > 0);
m.mod_units_started = sum(max(dN, 0));
m.mod_mean_online = mean(N_AEL);
m.ael_start_energy_mwh = results.summary.AEL_start_energy_kwh / 1000;
m.hb_mean_load = mean(HB);
hb_on = double(HB > 1e-9);
ramp = abs(diff(HB)) / dt;
r = ramp(hb_on(1:end-1) == 1 & hb_on(2:end) == 1);
if isempty(r); r = 0; end
m.ramp_p95 = prctile(r, 95);
m.switch_count = sum(abs(diff(hb_on)));
spd = round(24 / dt);
nd = floor(numel(NH3) / spd);
daily = sum(reshape(NH3(1:nd*spd), spd, nd), 1)';
m.daily_shortfall_p95 = prctile(max(mean(daily) - daily, 0) / mean(daily), 95);
m.daily_output_cv = std(daily, 1) / mean(daily);
m.h2_min_work_soc = min(soc_work);
m.h2_p05_work_soc = prctile(soc_work, 5);
m.h2_mean_work_soc = mean(soc_work);
m.h2_risk_hours = sum(soc_work < 0.20) * dt;
m.h2_empty_hours = sum(soc_work <= 1e-6) * dt;
m.curtail_energy_gwh = sum(results.dispatch.P_curt) * dt / 1e6;
end

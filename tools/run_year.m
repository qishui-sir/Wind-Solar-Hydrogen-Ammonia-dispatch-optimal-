% RUN_YEAR: full-year hourly MILP dispatch with a rich operational-stability report.
%
% Usage: run_year(year, out_prefix)
%   year        : renewable data year (2022..2025), default 2022
%   out_prefix  : output path prefix, default <project>/results_out/year_<yr>

function run_year(year, out_prefix, gap, max_time_s)
if nargin < 1 || isempty(year); year = 2022; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'figures'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

out_dir = fullfile(project_dir, 'results_out');
if ~isfolder(out_dir); mkdir(out_dir); end
if nargin < 2 || isempty(out_prefix)
    out_prefix = fullfile(out_dir, sprintf('year_%d', year));
end

params = my_system('s2');
params.AEL.common.startup = true;

% Solver budget. A full-year integer dispatch is not closable to 1e-4 in
% practical time; the accepted gap is reported with every result.
if nargin >= 3 && ~isempty(gap); params.solver.relative_gap = gap; end
if nargin >= 4 && ~isempty(max_time_s); params.solver.max_time_s = max_time_s; end

fprintf('[%s] === full-year run %d ===\n', stamp(), year);
fprintf('[%s] AEL modules=%d module_power=%.0f kW\n', stamp(), ...
    params.AEL.common.module_num, params.AEL.common.module_power);

data_cfg = struct();
data_cfg.pv_year = year;
data_cfg.pw_year = year;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);
fprintf('[%s] rows=%d\n', stamp(), renewable_data.time_count);

t0 = tic;
results = baseline(params, renewable_data);
elapsed = toc(t0);
fprintf('[%s] solved in %.1f s, exitflag=%d\n', stamp(), elapsed, results.exitflag);

metrics = year_stability_report(results, params, renewable_data);
metrics.year = year;
metrics.elapsed_s = elapsed;
if isfield(params, 'solver') && isfield(params.solver, 'relative_gap')
    metrics.accepted_gap = params.solver.relative_gap;
else
    metrics.accepted_gap = 1e-4;
end

% ---- headline economics ----
s = results.summary;
nh3_t = s.NH3_prod_t_y;
metrics.nh3_t = nh3_t;
metrics.lcoa_usd_t = s.lcoa;
metrics.net_profit_usd = s.net_profit;
metrics.ael_equiv_hours = s.ael_equiv_hours;
metrics.ael_start_energy_mwh = s.AEL_start_energy_kwh / 1000;
metrics.sell_rate = s.sell_rate;
metrics.curtail_rate = s.curtail_rate;
metrics.purchase_rate = s.purchase_rate;
metrics.co2_intensity = s.co2_intensity;
metrics.ael_startups = s.AEL_startup_count;
metrics.ael_shutdowns = s.AEL_shutdown_count;
metrics.hb_avg_load = s.HB_average_load;

% ---- write outputs ----
csv_path = [out_prefix, '_metrics.csv'];
writetable(struct2table(metrics), csv_path);
fprintf('[%s] wrote %s\n', stamp(), csv_path);

disp(struct2table(metrics));

params_save = params; %#ok<NASGU>
results_save = results; %#ok<NASGU>
renewable_save = renewable_data; %#ok<NASGU>
metrics_save = metrics; %#ok<NASGU>
mat_path = [out_prefix, '_dispatch.mat'];
save(mat_path, 'params_save', 'results_save', 'renewable_save', ...
    'metrics_save', '-v7.3');
fprintf('[%s] wrote %s\n', stamp(), mat_path);
fprintf('[%s] === done ===\n', stamp());
end

function t = stamp()
t = datestr(now, 'HH:MM:SS');
end

function m = year_stability_report(results, params, renewable_data)
dt = params.time.step;
T = results.dispatch.P_total;
P_AEL = results.dispatch.P_AEL(:);
P_AEL_start = results.dispatch.P_AEL_start(:);
N_AEL = results.dispatch.N_AEL(:);
HB = results.dispatch.HB_load(:);
soc_abs = results.storage.soc_abs(:);
soc_work = results.storage.soc_work(:);
NH3 = results.dispatch.NH3_prod(:);
P_buy = results.dispatch.P_purchase(:);
P_sell = results.dispatch.P_sell(:);
P_curt = results.dispatch.P_curt(:);

m = struct();

% --- renewable resource ---
m.res_capacity_factor = mean(T) / (params.renewable.total_capacity);
m.res_mean_mw = mean(T) / 1000;
m.res_p05_mw = prctile(T, 5) / 1000;
m.res_p95_mw = prctile(T, 95) / 1000;
m.res_zero_hours = sum(T < 1e-6) * dt;
m.res_below_aelmin_hours = sum(T < params.AEL.common.min_power) * dt;

% --- power split ---
m.ael_energy_gwh = sum(P_AEL) * dt / 1e6;
m.ael_energy_share = sum(P_AEL) / max(sum(T), eps);
m.ael_min_power_violation_hours = sum( ...
    (P_AEL > 1e-6) & (P_AEL < params.AEL.common.min_power - 1e-6)) * dt;
m.ael_zero_hours = sum(P_AEL < 1e-6) * dt;
m.ael_load_p05 = prctile(P_AEL / params.AEL.common.max_power, 5);
m.ael_load_mean = mean(P_AEL) / params.AEL.common.max_power;
m.ael_load_p95 = prctile(P_AEL / params.AEL.common.max_power, 95);
m.ael_full_load_hours = sum(P_AEL) * dt / params.AEL.common.max_power;

% --- AEL module commitment (the discrete side) ---
dN = diff([0; N_AEL]);
m.mod_start_events = sum(dN > 0);
m.mod_stop_events = sum(dN < 0);
m.mod_units_started = sum(max(dN, 0));
m.mod_units_stopped = sum(max(-dN, 0));
m.mod_mean_online = mean(N_AEL);
m.mod_max_online = max(N_AEL);
m.mod_online_p05 = prctile(N_AEL, 5);
m.mod_online_p95 = prctile(N_AEL, 95);
m.mod_commit_std = std(N_AEL);
% dwell analysis of the online-count trajectory
m.mod_updown_events = sum(abs(dN) > 0);
m.mod_net_change_abs = sum(abs(dN));

% --- Haber-Bosch / ammonia delivery ---
hb_on = double(HB > 0);
m.hb_min_load = min(HB);
m.hb_mean_load = mean(HB);
m.hb_p05_load = prctile(HB, 5);
m.hb_below_min_hours = sum(HB < params.HB.min_load - 1e-8) * dt;
ramp = abs(diff(HB)) / dt;
ramp_online = ramp(hb_on(1:end-1) == 1 & hb_on(2:end) == 1);
if isempty(ramp_online); ramp_online = 0; end
m.mar = mean(ramp_online);
m.rms_ramp = sqrt(mean(ramp_online.^2));
m.ramp_p95 = prctile(ramp_online, 95);
m.ramp_max = max(ramp_online);
m.switch_count = sum(abs(diff(hb_on)));
m.low_load_ratio = mean(HB(hb_on == 1) < 0.4);
if isempty(m.low_load_ratio) || isnan(m.low_load_ratio); m.low_load_ratio = 1; end

% --- daily ammonia delivery stability ---
spd = round(24 / dt);
nd = floor(numel(NH3) / spd);
daily = sum(reshape(NH3(1:nd*spd), spd, nd), 1)';
m.daily_nh3_mean_t = mean(daily) / 1000;
m.daily_nh3_min_t = min(daily) / 1000;
m.daily_nh3_max_t = max(daily) / 1000;
m.daily_output_cv = std(daily, 1) / mean(daily);
m.daily_output_max_dev = max(abs(daily - mean(daily))) / mean(daily);
shortfall = max(mean(daily) - daily, 0) / mean(daily);
m.daily_shortfall_p95 = prctile(shortfall, 95);
m.daily_output_p05_t = prctile(daily, 5) / 1000;
DCV = zeros(nd, 1);
for d = 1:nd
    seg = NH3((d-1)*spd + (1:spd));
    DCV(d) = sqrt(mean((seg - mean(seg)).^2)) / params.HB.nh3_output;
end
m.dcv_mean = mean(DCV);
m.dcv_p95 = prctile(DCV, 95);
m.dcv_max = max(DCV);

% --- hydrogen security ---
m.h2_min_abs_soc = min(soc_abs);
m.h2_min_work_soc = min(soc_work);
m.h2_p05_work_soc = prctile(soc_work, 5);
m.h2_mean_work_soc = mean(soc_work);
m.h2_safe_soc = 0.20;
m.h2_min_margin = min(soc_work) - 0.20;
m.h2_risk_hours = sum(soc_work < 0.20) * dt;
m.h2_empty_hours = sum(soc_work <= 1e-6) * dt;
m.h2_full_hours = sum(soc_work >= 1 - 1e-6) * dt;

% --- grid & residuals ---
m.buy_energy_gwh = sum(P_buy) * dt / 1e6;
m.sell_energy_gwh = sum(P_sell) * dt / 1e6;
m.curtail_energy_gwh = sum(P_curt) * dt / 1e6;
m.max_power_residual_kw = results.check.max_power_residual_kw;
m.max_storage_residual_kg = results.check.max_storage_residual_kg;
end

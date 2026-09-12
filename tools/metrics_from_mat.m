% METRICS_FROM_MAT: recompute the operational-stability report from a saved run.
% Usage: metrics_from_mat(mat_path, out_csv)
%
% This applies the same definition set used by run_year.m to an already-solved
% dispatch, so a previously completed short-horizon run can be re-analysed
% without re-solving.

function metrics_from_mat(mat_path, out_csv)
if nargin < 1 || isempty(mat_path)
    error('metrics_from_mat:bad_input', 'mat_path is required.');
end
if ~isfile(mat_path)
    error('metrics_from_mat:no_file', 'File not found: %s', mat_path);
end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

S = load(mat_path, 'params_save', 'results_save', 'renewable_save');
params = S.params_save;
results = S.results_save;
renewable_data = S.renewable_save;

metrics = year_stability_report_local(results, params, renewable_data);
metrics.mat_path = string(mat_path);
metrics.hours = numel(results.dispatch.P_total);
metrics.nh3_t = results.summary.NH3_prod_t_y;
metrics.lcoa_usd_t = results.summary.lcoa;
metrics.net_profit_usd = results.summary.net_profit;
metrics.ael_equiv_hours = results.summary.ael_equiv_hours;
metrics.ael_start_energy_mwh = results.summary.AEL_start_energy_kwh / 1000;
metrics.sell_rate = results.summary.sell_rate;
metrics.curtail_rate = results.summary.curtail_rate;
metrics.purchase_rate = results.summary.purchase_rate;
metrics.co2_intensity = results.summary.co2_intensity;

if nargin >= 2 && ~isempty(out_csv)
    writetable(struct2table(metrics), out_csv);
    fprintf('wrote %s\n', out_csv);
end
disp(struct2table(metrics));
end

function m = year_stability_report_local(results, params, renewable_data) %#ok<INUSD>
dt = params.time.step;
T = results.dispatch.P_total;
P_AEL = results.dispatch.P_AEL(:);
N_AEL = results.dispatch.N_AEL(:);
HB = results.dispatch.HB_load(:);
soc_abs = results.storage.soc_abs(:);
soc_work = results.storage.soc_work(:);
NH3 = results.dispatch.NH3_prod(:);
P_buy = results.dispatch.P_purchase(:);
P_sell = results.dispatch.P_sell(:);
P_curt = results.dispatch.P_curt(:);

m = struct();
m.res_capacity_factor = mean(T) / (params.renewable.total_capacity);
m.res_mean_mw = mean(T) / 1000;
m.res_p05_mw = prctile(T, 5) / 1000;
m.res_p95_mw = prctile(T, 95) / 1000;
m.res_zero_hours = sum(T < 1e-6) * dt;
m.res_below_aelmin_hours = sum(T < params.AEL.common.min_power) * dt;

m.ael_energy_gwh = sum(P_AEL) * dt / 1e6;
m.ael_energy_share = sum(P_AEL) / max(sum(T), eps);
m.ael_zero_hours = sum(P_AEL < 1e-6) * dt;
m.ael_load_p05 = prctile(P_AEL / params.AEL.common.max_power, 5);
m.ael_load_mean = mean(P_AEL) / params.AEL.common.max_power;
m.ael_load_p95 = prctile(P_AEL / params.AEL.common.max_power, 95);
m.ael_full_load_hours = sum(P_AEL) * dt / params.AEL.common.max_power;

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
m.mod_updown_events = sum(abs(dN) > 0);
m.mod_net_change_abs = sum(abs(dN));

m.hb_min_load = min(HB);
m.hb_mean_load = mean(HB);
m.hb_p05_load = prctile(HB, 5);
m.hb_below_min_hours = sum(HB < params.HB.min_load - 1e-8) * dt;
hb_on = double(HB > 1e-9);
ramp = abs(diff(HB)) / dt;
ramp_online = ramp(hb_on(1:end-1) == 1 & hb_on(2:end) == 1);
if isempty(ramp_online); ramp_online = 0; end
m.mar = mean(ramp_online);
m.rms_ramp = sqrt(mean(ramp_online.^2));
m.ramp_p95 = prctile(ramp_online, 95);
m.ramp_max = max(ramp_online);
m.switch_count = sum(abs(diff(hb_on)));

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

m.h2_min_abs_soc = min(soc_abs);
m.h2_min_work_soc = min(soc_work);
m.h2_p05_work_soc = prctile(soc_work, 5);
m.h2_mean_work_soc = mean(soc_work);
m.h2_min_margin = min(soc_work) - 0.20;
m.h2_risk_hours = sum(soc_work < 0.20) * dt;
m.h2_empty_hours = sum(soc_work <= 1e-6) * dt;
m.h2_full_hours = sum(soc_work >= 1 - 1e-6) * dt;

m.buy_energy_gwh = sum(P_buy) * dt / 1e6;
m.sell_energy_gwh = sum(P_sell) * dt / 1e6;
m.curtail_energy_gwh = sum(P_curt) * dt / 1e6;
end

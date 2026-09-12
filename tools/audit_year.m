% AUDIT_YEAR: integrity audit of a solved annual dispatch, plus the reserve-price
% counterfactual on the same schedule.
%
% Usage: audit_year(mat_path)

function audit_year(mat_path)
if nargin < 1 || isempty(mat_path)
    error('audit_year:bad_input', 'mat_path is required.');
end
source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

S = load(mat_path, 'params_save', 'results_save');
params = S.params_save; results = S.results_save;
dt = params.time.step;

P_AEL = results.dispatch.P_AEL(:);
N_AEL = results.dispatch.N_AEL(:);
HB = results.dispatch.HB_load(:);
soc = results.storage.soc_work(:);
if numel(soc) == numel(P_AEL) + 1; soc = soc(2:end); end
NH3 = results.dispatch.NH3_prod(:);
lim = h2_storage_limits(params.h2_storage, params.unit.h2_density);

ael_min = params.AEL.common.min_power;
ael_max = params.AEL.common.max_power;

fprintf('\n=========== ANNUAL DISPATCH AUDIT ===========\n');
fprintf('file: %s\n', mat_path);
fprintf('hours: %d\n', numel(P_AEL));

%% --- 1. HARD CONSTRAINT COMPLIANCE ---
fprintf('\n--- 1. equipment-envelope compliance ---\n');
fprintf('AEL min-power floor          : %.1f kW (%.2f p.u.)\n', ael_min, params.AEL.common.min_load);

% How should the floor be enforced? Two readings:
%  (i) aggregate: total AEL power must be >= min_load * max_power when running
%  (ii) modular:   modelled as min_load * N * module_power <= P_AEL
agg_viol_hours = sum((P_AEL > 1e-6) & (P_AEL < ael_min - 1e-6)) * dt;
agg_deficit_kwh = sum(max(ael_min - P_AEL, 0) .* (P_AEL > 1e-6)) * dt;
mod_floor = params.AEL.common.min_load * N_AEL * params.AEL.common.module_power;
mod_viol_hours = sum(P_AEL < mod_floor - 1e-6) * dt;
fprintf('hours below aggregate floor   : %d (%.2f%% of year)\n', ...
    agg_viol_hours, 100 * agg_viol_hours / numel(P_AEL));
fprintf('energy shortfall vs aggregate : %.1f MWh\n', agg_deficit_kwh / 1000);
fprintf('hours below modular floor     : %d\n', mod_viol_hours);
fprintf('min observed AEL load         : %.4f p.u.\n', min(P_AEL) / ael_max);
fprintf('P5 / P50 AEL load             : %.4f / %.4f p.u.\n', ...
    prctile(P_AEL, 5) / ael_max, prctile(P_AEL, 50) / ael_max);

fprintf('\nHB envelope:\n');
fprintf('  min observed load           : %.4f (floor %.2f)\n', ...
    min(HB), params.HB.min_load);
fprintf('  hours below floor           : %d\n', ...
    sum(HB < params.HB.min_load - 1e-8) * dt);
ramp = abs(diff(HB)) / dt;
fprintf('  max observed ramp           : %.4f (limit %.2f)\n', ...
    max(ramp), params.HB.ramp_rate);

%% --- 2. RESERVE PRICE ---
fprintf('\n--- 2. hydrogen reserve price (counterfactual on this schedule) ---\n');
fprintf('usable inventory: %.1f kg (%.1f Nm3)\n', lim.work_mass, lim.work_capacity);
floors = [0, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50];
rows = cell(numel(floors), 1);
for k = 1:numel(floors)
    r = floors(k);
    viol = soc < r - 1e-9;
    deficit_kg = sum(max(r - soc, 0)) * lim.work_mass;
    rows{k} = struct('floor', r, ...
        'risk_hours', sum(viol) * dt, ...
        'risk_pct_of_year', 100 * mean(viol), ...
        'mean_deficit_pct_of_usable', 100 * mean(max(r - soc, 0)), ...
        'cum_deficit_t_H2', deficit_kg / 1000, ...
        'extra_ael_gwh', deficit_kg * params.AEL.common.mass_spec_energy / 1e6, ...
        'extra_ael_pct_of_ael_energy', 100 * deficit_kg * params.AEL.common.mass_spec_energy / ...
            max(sum(P_AEL) * dt, eps));
end
T = struct2table([rows{:}]);
disp(T);
writetable(T, fullfile(fileparts(mat_path), 'annual_reserve_price.csv'));

%% --- 3. CYCLING BURDEN ---
fprintf('\n--- 3. cycling burden ---\n');
dN = diff([0; N_AEL]);
fprintf('module start events          : %d  (%.2f /day)\n', sum(dN > 0), sum(dN > 0) / (numel(P_AEL)/24));
fprintf('module units started         : %d  (%.2f /day)\n', sum(max(dN,0)), sum(max(dN,0)) / (numel(P_AEL)/24));
fprintf('module units stopped         : %d\n', sum(max(-dN,0)));
fprintf('start-up energy              : %.1f MWh/a (%.4f%% of AEL energy)\n', ...
    sum(results.dispatch.P_AEL_start) * dt / 1000, ...
    100 * sum(results.dispatch.P_AEL_start) * dt / max(sum(P_AEL) * dt, eps));
dSoc = diff(soc);
fprintf('H2 buffer throughput         : %.2f usable volumes/year (%.3f /day)\n', ...
    sum(abs(dSoc)), sum(abs(dSoc)) / (numel(soc)/24));
fprintf('hours buffer empty           : %d\n', sum(soc <= 1e-6) * dt);
fprintf('hours buffer below 20%%       : %d (%.1f%% of year)\n', ...
    sum(soc < 0.20) * dt, 100 * mean(soc < 0.20));

%% --- 4. AMMONIA DELIVERY TAIL ---
spd = 24; nd = floor(numel(NH3) / spd);
daily = sum(reshape(NH3(1:nd*spd), spd, nd), 1)';
fprintf('\n--- 4. ammonia delivery ---\n');
fprintf('annual NH3                   : %.1f t (%.1f%% of 100 kt design)\n', ...
    sum(NH3)/1000, 100 * sum(NH3)/1000 / 100000);
fprintf('daily mean / P5 / min        : %.1f / %.1f / %.1f t\n', ...
    mean(daily)/1000, prctile(daily,5)/1000, min(daily)/1000);
fprintf('daily CV                     : %.4f\n', std(daily,1)/mean(daily));
fprintf('P95 daily shortfall          : %.4f\n', ...
    prctile(max(mean(daily)-daily,0)/mean(daily), 95));
fprintf('days below 50%% of mean       : %d of %d\n', ...
    sum(daily < 0.5*mean(daily)), nd);
fprintf('==============================================\n');
end

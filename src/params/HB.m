function par = HB(config, scenario_id)
%HB Haber-Bosch parameters for the Zhou 7-day PtA case.

if nargin == 1 && (ischar(config) || (isstring(config) && isscalar(config)))
    scenario_id = config;
    config = struct();
elseif nargin < 1 || isempty(config)
    config = struct();
end

if nargin < 2 || isempty(scenario_id)
    scenario_id = 's2';
end

if isstring(scenario_id) && isscalar(scenario_id)
    scenario_id = char(scenario_id);
end

scenario_id = lower(strtrim(scenario_id));

par.capex_usd_tpy = 561; % HB capital cost, USD/(t/year)
par.om_fraction = 0.02; % HB O&M rate, fraction/year
par.capacity_t_y = 100000; % HB ammonia capacity, t/year
par.electricity_mwh_per_t_nh3 = 0.95; % HB electricity use, MWh/t-NH3
par.nh3_t_per_t_nh3 = 1.00; % Zhou ammonia product factor, t/t-NH3
par.literature_h2_t_per_t_nh3 = 0.18; % Zhou rounded H2 use, t/t-NH3
par.literature_n2_t_per_t_nh3 = 0.84; % Zhou rounded N2 use, t/t-NH3
par.active_h2_t_per_t_nh3 = 6 / 34; % Dispatch H2 stoichiometry, t/t-NH3
par.active_n2_t_per_t_nh3 = 28 / 34; % Dispatch N2 stoichiometry, t/t-NH3
par.h2_t_per_t_nh3 = par.active_h2_t_per_t_nh3; % Active H2 balance alias, t/t-NH3
par.n2_t_per_t_nh3 = par.active_n2_t_per_t_nh3; % Active N2 balance alias, t/t-NH3
par.water_t_per_t_nh3 = 2.70; % HB water use, t/t-NH3
par.load_step_fraction = 0.10; % HB multi-state load step, fraction
par.control_interval_h = 4; % HB control interval, h

switch scenario_id
    case 's1'
        par.min_load_fraction = 1.00; % HB minimum load, fraction
        par.max_load_fraction = 1.00; % HB maximum load, fraction
        par.set_load_fraction = 1.00; % HB fixed load, fraction
        par.ramp_fraction_h = 0; % HB ramp rate, fraction/h
        par.stable_window_h = [0, 24]; % HB stable operation window, h
        par.flexible_window_h = zeros(0, 2); % HB flexible operation window, h
    case 's2'
        par.min_load_fraction = 0.30; % HB minimum load, fraction
        par.max_load_fraction = 1.00; % HB maximum load, fraction
        par.set_load_fraction = []; % HB fixed load; empty means flexible
        par.ramp_fraction_h = 0.20; % HB ramp rate, fraction/h
        par.stable_window_h = zeros(0, 2); % HB stable operation window, h
        par.flexible_window_h = [0, 24]; % HB flexible operation window, h
    case 's3'
        par.min_load_fraction = 0.30; % HB minimum load, fraction
        par.max_load_fraction = 1.10; % HB maximum load, fraction
        par.set_load_fraction = 0.30:0.10:1.10; % HB allowed load states, fraction
        par.ramp_fraction_h = 0.20; % HB ramp rate, fraction/h
        par.stable_window_h = [0, 12; 16, 24]; % HB stable operation window, h
        par.flexible_window_h = [12, 16]; % HB flexible operation window, h
    otherwise
        error('HB:bad_case', 'scenario_id must be s1, s2, or s3.');
end

hour_per_year = 8760;
kg_per_t = 1000;
if isfield(config, 'time') && isfield(config.time, 'hour_per_year')
    hour_per_year = config.time.hour_per_year;
end
if isfield(config, 'unit') && isfield(config.unit, 'kg_per_t')
    kg_per_t = config.unit.kg_per_t;
end

par.capacity_kg_h = par.capacity_t_y * kg_per_t / hour_per_year; % HB ammonia output, kg/h
par.h2_demand_kg_h = par.capacity_kg_h * par.active_h2_t_per_t_nh3; % HB active H2 demand, kg/h
par.n2_demand_kg_h = par.capacity_kg_h * par.active_n2_t_per_t_nh3; % HB active N2 demand, kg/h
par.literature_h2_demand_kg_h = ...
    par.capacity_kg_h * par.literature_h2_t_per_t_nh3; % Zhou rounded H2 demand, kg/h
par.literature_n2_demand_kg_h = ...
    par.capacity_kg_h * par.literature_n2_t_per_t_nh3; % Zhou rounded N2 demand, kg/h
par.nominal_power_mw = ...
    par.capacity_t_y * par.electricity_mwh_per_t_nh3 / hour_per_year; % HB nominal power, MW
end

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

par.capex = 561;        % HB capital cost, USD/(t/year)
par.om_rate = 0.02;     % HB O&M rate, fraction/year
par.capacity = 100000;  % HB ammonia capacity, t/year
par.spec_energy = 0.95; % HB electricity use, MWh/t-NH3
par.nh3_ratio = 1.00;   % Zhou ammonia product factor, t/t-NH3
par.lit_h2 = 0.18;      % Zhou rounded H2 use, t/t-NH3
par.lit_n2 = 0.84;      % Zhou rounded N2 use, t/t-NH3
par.act_h2 = 6 / 34;    % Dispatch H2 stoichiometry, t/t-NH3
par.act_n2 = 28 / 34;   % Dispatch N2 stoichiometry, t/t-NH3
par.water_use = 2.70;   % HB water use, t/t-NH3
par.load_step = 0.10;   % HB multi-state load step, fraction
par.ctrl_interval = 4;  % HB control interval, h

switch scenario_id
    case 's1'
        par.min_load = 1.00;            % HB minimum load, fraction
        par.max_load = 1.00;            % HB maximum load, fraction
        par.set_load = 1.00;            % HB fixed load, fraction
        par.ramp_rate = 0;              % HB ramp rate, fraction/h
        par.stable_window = [0, 24];    % HB stable operation window, h
        par.flex_window = zeros(0, 2);  % HB flexible operation window, h
    case 's2'
        par.min_load = 0.30;            % HB minimum load, fraction
        par.max_load = 1.00;            % HB maximum load, fraction
        par.set_load = [];              % HB fixed load; empty means flexible
        par.ramp_rate = 0.20;           % HB ramp rate, fraction/h
        par.stable_window = zeros(0, 2);% HB stable operation window, h
        par.flex_window = [0, 24]; % HB flexible operation window, h
    case 's3'
        par.min_load = 0.30;            % HB minimum load, fraction
        par.max_load = 1.10;            % HB maximum load, fraction
        par.set_load = 0.30:0.10:1.10;  % HB allowed load states, fraction
        par.ramp_rate = 0.20;           % HB ramp rate, fraction/h
        par.stable_window = [0, 12; 16, 24]; % HB stable operation window, h
        par.flex_window = [12, 16];     % HB flexible operation window, h
    otherwise
        error('HB:bad_case', 'scenario_id must be s1, s2, or s3.');
end

hour_year = 8760;
mass_scale = 1000;
if isfield(config, 'time') && isfield(config.time, 'hour_year')
    hour_year = config.time.hour_year;
end
if isfield(config, 'unit') && isfield(config.unit, 'mass_scale')
    mass_scale = config.unit.mass_scale;
end

par.nh3_output = par.capacity * mass_scale / hour_year; % HB ammonia output, kg/h
par.h2_demand = par.nh3_output * par.act_h2; % HB active H2 demand, kg/h
par.n2_demand = par.nh3_output * par.act_n2; % HB active N2 demand, kg/h
par.lit_h2_demand = par.nh3_output * par.lit_h2; % Zhou rounded H2 demand, kg/h
par.lit_n2_demand = par.nh3_output * par.lit_n2; % Zhou rounded N2 demand, kg/h
par.nom_power = par.capacity * par.spec_energy / hour_year; % HB nominal power, MW
end

function config = default(scenario_id)
%DEFAULT Default system-level parameters for the Zhou 7-day PtA case.

if nargin < 1 || isempty(scenario_id)
    scenario_id = 's2';
end

if isstring(scenario_id) && isscalar(scenario_id)
    scenario_id = char(scenario_id);
end

if ~ischar(scenario_id)
    error('default:bad_case', 'scenario_id must be s1, s2, or s3.');
end

scenario_id = lower(strtrim(scenario_id));
config = struct();

config.source.paper = 'Zhou 2024 ECM'; % Source paper
config.source.doi = '10.1016/j.enconman.2024.118720'; % Source DOI
config.source.note = 'Table 2 plus Table 3/4 scenario data.'; % Source table note

config.time.step = 1;           % Simulation time step, h
config.time.days = 7;           % Simulation horizon, day
config.time.hour_day = 24;      % Hours per day, h/day
config.time.hour_year = 8760;   % Hours per year, h/year

config.unit.h2_density = 0.08988;   % H2 density, kg/Nm3
config.unit.mass_scale = 1000;      % Mass conversion, kg/t
config.unit.power_scale = 1000;     % Power conversion, kW/MW

config.renewable.total_capacity = 400e3;% Total PV+PW capacity, kW
config.renewable.PV_capacity = 200e3;   % PV capacity, kW
config.renewable.PW_capacity = 200e3;   % PW/wind capacity, kW
config.renewable.PV_ref = 100e3;        % Zhou recommended PV capacity, kW
config.renewable.PW_ref = 300e3;        % Zhou recommended PW/wind capacity, kW
config.renewable.PW_min = 0;            % PW/wind scan lower bound, kW
config.renewable.PW_max = 400e3;        % PW/wind scan upper bound, kW
config.renewable.PW_step = 50e3;        % PW/wind scan step, kW
config.renewable.data_dir = '';         % Renewable data folder; empty means caller sets it
config.renewable.start_time = [];       % Renewable data start time; empty means first row

config.finance.lifetime = 20;           % Project lifetime, year
config.finance.discount = 0.05;         % Discount rate, fraction/year
config.finance.loan_term = 20;          % Loan term, year
config.finance.loan_ratio = 0.80;       % Loan ratio, fraction
config.finance.loan_interest = 0.046;   % Loan interest rate, fraction/year
if config.finance.discount == 0
    config.finance.crf = 1 / config.finance.lifetime; % Capital recovery factor, 1/year
else
    config.finance.crf = config.finance.discount * ...
        (1 + config.finance.discount)^config.finance.lifetime / ...
        ((1 + config.finance.discount)^config.finance.lifetime - 1); % Capital recovery factor, 1/year
end

config.pw.capex = 685;      % PW/wind capital cost, USD/kW
config.pw.om_rate = 0.02;   % PW/wind O&M rate, fraction/year
config.pv.capex = 543;      % PV capital cost, USD/kW
config.pv.om_rate = 0.01;   % PV O&M rate, fraction/year

config.h2_storage.capex = 50;           % H2 storage capital cost, USD/Nm3
config.h2_storage.om_rate = 0.01;       % H2 storage O&M rate, fraction/year
config.h2_storage.module_cap = 22000;   % H2 storage module capacity, Nm3
config.h2_storage.min_pressure = 0.5;   % H2 storage minimum pressure, MPa
config.h2_storage.max_pressure = 1.5;   % H2 storage maximum pressure, MPa
config.h2_storage.temperature = 30;     % H2 storage operating temperature, degC

config.ammonia.price = 557;         % Ammonia selling price, USD/t
config.material.water_price = 1.4;  % Water price, USD/t
config.material.cat_price = 18;     % Catalyst price, USD/t

% Zhou does not publish labor coefficients. The S2 calibration uses the
% 2022 Inner Mongolia manufacturing wage scale and an integrated-plant crew.
config.labor.fte = 200;              % Full-time equivalent employees
config.labor.salary = 15000;         % Loaded labor cost, USD/(employee year)
config.labor.note = ['Calibration assumption: 200 FTE at 15,000 USD/FTE-year; ', ...
    'annual labor cost is 3.0 MUSD.'];

config.converter.capex = 43;        % Converter capital cost, USD/kW
config.converter.om_rate = 0.02;    % Converter O&M rate, fraction/year
config.transformer.capex = 51;      % Transformer capital cost, USD/kW
config.transformer.om_rate = 0.02;  % Transformer O&M rate, fraction/year
config.transformer.max_load = 0.90; % Transformer maximum load, fraction

config.grid.sell_price = 0.041;     % Grid selling price, USD/kWh
config.grid.buy_price = 0.053;      % Grid buying price, USD/kWh
config.grid.cap_fee = 3.85;         % Grid capacity fee, USD/(kW month)
config.grid.contract_kw = [];       % Contract demand, kW; empty uses dispatch peak
config.grid.curtail_limit = 0.10;   % Curtailment limit, fraction
config.grid.max_sell = 0.20;        % Electricity selling limit, fraction
config.grid.buy_enabled = true;     % Enable electricity purchase
config.grid.sell_enabled = true;    % Enable electricity selling

config.environment.grid_co2 = 0.5703;   % Grid CO2 factor, kg-CO2/kWh
config.environment.co2_limit = 0.3;     % Ammonia CO2 limit, kg-CO2/kg-NH3

config.optimizer.c1 = 1;            % PSO cognitive weight
config.optimizer.c2 = 1;            % PSO social weight
config.optimizer.inertia = 1;       % PSO inertia weight
config.optimizer.iter_num = 100;    % PSO iteration count
config.optimizer.particle_num = 10; % PSO particle count

switch scenario_id
    case 's1'
        config.scenario.id = 's1';              % Scenario id
        config.scenario.mode = 'fixed_load';    % Scenario mode
        config.environment.co2_enabled = false; % Enable CO2 constraint
        config.h2_storage.capacity = 17.6e4;    % H2 storage capacity, Nm3
        config.transformer.capacity = 190;      % Transformer capacity, MW
        config.ref.nh3_output = 1.00e5;         % Zhou NH3 output, t/year
        config.ref.lcoa = 549;                  % Zhou LCOA, USD/t
        config.ref.net_profit = 0.75e6;          % Zhou annual net profit, USD/year
        config.ref.ael_hours = 7163;            % Zhou AEL utilization, h/year
        config.ref.grid_buy = 0.3086;           % Zhou grid buying fraction
        config.ref.grid_sell = 0.1724;          % Zhou grid selling fraction
        config.ref.curtailment = 0.0021;        % Zhou curtailment fraction
        config.ref.co2_intensity = 1.70;        % Zhou carbon intensity, kg-CO2/kg-NH3
    case 's2'
        config.scenario.id = 's2';
        config.scenario.mode = 'continuous_flexible';
        config.environment.co2_enabled = true;
        config.h2_storage.capacity = 11.0e4;
        config.transformer.capacity = 200;
        config.grid.contract_kw = 30e3; % Calibrated S2 contract demand, kW
        config.ref.nh3_output = 7.12e4;
        config.ref.lcoa = 464;
        config.ref.net_profit = 6.65e6;
        config.ref.ael_hours = 5492;
        config.ref.grid_buy = 0.0015;
        config.ref.grid_sell = 0.1920;
        config.ref.curtailment = 0.0020;
        config.ref.co2_intensity = 0.01;
    case 's3'
        config.scenario.id = 's3';
        config.scenario.mode = 'multi_state_flexible';
        config.environment.co2_enabled = true;
        config.h2_storage.capacity = 13.2e4;
        config.transformer.capacity = 189;
        config.ref.nh3_output = 7.04e4;
        config.ref.lcoa = 475;
        config.ref.net_profit = 5.80e6;
        config.ref.ael_hours = 5460;
        config.ref.grid_buy = 0.0112;
        config.ref.grid_sell = 0.2000;
        config.ref.curtailment = 0.0038;
        config.ref.co2_intensity = 0.09;
    otherwise
        error('default:bad_case', 'scenario_id must be s1, s2, or s3.');
end

config.h2_storage.mass = ...
    config.h2_storage.capacity * config.unit.h2_density; % H2 storage capacity, kg
end

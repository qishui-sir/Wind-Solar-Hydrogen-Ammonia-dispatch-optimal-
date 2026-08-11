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

config.time.time_step_h = 1; % Simulation time step, h
config.time.day_count = 7; % Simulation horizon, day
config.time.hour_per_day = 24; % Hours per day, h/day
config.time.hour_per_year = 8760; % Hours per year, h/year

config.unit.h2_kg_per_nm3 = 0.08988; % H2 density, kg/Nm3
config.unit.kg_per_t = 1000; % Mass conversion, kg/t
config.unit.kw_per_mw = 1000; % Power conversion, kW/MW

config.renewable.total_capacity_kw = 400e3; % Total PV+PW capacity, kW
config.renewable.pv_capacity_kw = 200e3; % PV capacity, kW
config.renewable.pw_capacity_kw = 200e3; % PW/wind capacity, kW
config.renewable.pv_recommended_kw = 100e3; % Zhou recommended PV capacity, kW
config.renewable.pw_recommended_kw = 300e3; % Zhou recommended PW/wind capacity, kW
config.renewable.pw_min_capacity_kw = 0; % PW/wind scan lower bound, kW
config.renewable.pw_max_capacity_kw = 400e3; % PW/wind scan upper bound, kW
config.renewable.pw_capacity_step_kw = 50e3; % PW/wind scan step, kW
config.renewable.data_dir = ''; % Renewable data folder; empty means caller sets it
config.renewable.start_time = []; % Renewable data start time; empty means first row

config.finance.project_lifetime_y = 20; % Project lifetime, year
config.finance.discount_rate = 0.05; % Discount rate, fraction/year
config.finance.loan_year = 20; % Loan term, year
config.finance.loan_ratio = 0.80; % Loan ratio, fraction
config.finance.loan_interest_rate = 0.046; % Loan interest rate, fraction/year
if config.finance.discount_rate == 0
    config.finance.capital_recovery_factor = ...
        1 / config.finance.project_lifetime_y; % Capital recovery factor, 1/year
else
    config.finance.capital_recovery_factor = ...
        config.finance.discount_rate * ...
        (1 + config.finance.discount_rate)^config.finance.project_lifetime_y / ...
        ((1 + config.finance.discount_rate)^config.finance.project_lifetime_y - 1); % Capital recovery factor, 1/year
end

config.pw.capex_usd_kw = 685; % PW/wind capital cost, USD/kW
config.pw.om_fraction = 0.02; % PW/wind O&M rate, fraction/year
config.pv.capex_usd_kw = 543; % PV capital cost, USD/kW
config.pv.om_fraction = 0.01; % PV O&M rate, fraction/year

config.h2_storage.capex_usd_nm3 = 50; % H2 storage capital cost, USD/Nm3
config.h2_storage.om_fraction = 0.01; % H2 storage O&M rate, fraction/year
config.h2_storage.module_capacity_nm3 = 22000; % H2 storage module capacity, Nm3
config.h2_storage.min_pressure_mpa = 0.5; % H2 storage minimum pressure, MPa
config.h2_storage.max_pressure_mpa = 1.5; % H2 storage maximum pressure, MPa
config.h2_storage.temperature_celsius = 30; % H2 storage operating temperature, degC

config.ammonia.price_usd_t = 557; % Ammonia selling price, USD/t
config.material.water_price_usd_t = 1.4; % Water price, USD/t
config.material.catalyst_price_usd_t = 18; % Catalyst price, USD/t

config.converter.capex_usd_kw = 43; % Converter capital cost, USD/kW
config.converter.om_fraction = 0.02; % Converter O&M rate, fraction/year
config.transformer.capex_usd_kw = 51; % Transformer capital cost, USD/kW
config.transformer.om_fraction = 0.02; % Transformer O&M rate, fraction/year
config.transformer.max_load_fraction = 0.90; % Transformer maximum load, fraction

config.grid.sell_price_usd_kwh = 0.041; % Grid selling price, USD/kWh
config.grid.buy_price_usd_kwh = 0.053; % Grid buying price, USD/kWh
config.grid.capacity_fee_usd_kw_month = 3.85; % Grid capacity fee, USD/(kW month)
config.grid.curtailment_limit_fraction = 0.10; % Curtailment limit, fraction
config.grid.max_sell_fraction = 0.20; % Electricity selling limit, fraction
config.grid.enable_buy = true; % Enable electricity purchase
config.grid.enable_sell = true; % Enable electricity selling

config.environment.grid_co2_kg_kwh = 0.5703; % Grid CO2 factor, kg-CO2/kWh
config.environment.co2_limit_kg_kg_nh3 = 0.3; % Ammonia CO2 limit, kg-CO2/kg-NH3

config.optimizer.cognitive_weight = 1; % PSO cognitive weight
config.optimizer.social_weight = 1; % PSO social weight
config.optimizer.inertia_weight = 1; % PSO inertia weight
config.optimizer.iteration_count = 100; % PSO iteration count
config.optimizer.particle_count = 10; % PSO particle count

switch scenario_id
    case 's1'
        config.scenario.id = 's1'; % Scenario id
        config.scenario.mode = 'fixed_load'; % Scenario mode
        config.environment.enable_co2_limit = false; % Enable CO2 constraint
        config.h2_storage.capacity_nm3 = 17.6e4; % H2 storage capacity, Nm3
        config.transformer.capacity_mw = 190; % Transformer capacity, MW
        config.ref.nh3_output_t_y = 1.00e5; % Zhou NH3 output, t/year
        config.ref.lcoa_usd_t = 549; % Zhou LCOA, USD/t
        config.ref.ael_use_h = 7163; % Zhou AEL utilization, h/year
        config.ref.grid_buy_fraction = 0.3086; % Zhou grid buying fraction
        config.ref.grid_sell_fraction = 0.1724; % Zhou grid selling fraction
        config.ref.curtailment_fraction = 0.0021; % Zhou curtailment fraction
        config.ref.co2_kg_kg_nh3 = 1.70; % Zhou carbon intensity, kg-CO2/kg-NH3
    case 's2'
        config.scenario.id = 's2'; % Scenario id
        config.scenario.mode = 'continuous_flexible'; % Scenario mode
        config.environment.enable_co2_limit = true; % Enable CO2 constraint
        config.h2_storage.capacity_nm3 = 11.0e4; % H2 storage capacity, Nm3
        config.transformer.capacity_mw = 200; % Transformer capacity, MW
        config.ref.nh3_output_t_y = 7.12e4; % Zhou NH3 output, t/year
        config.ref.lcoa_usd_t = 464; % Zhou LCOA, USD/t
        config.ref.ael_use_h = 5492; % Zhou AEL utilization, h/year
        config.ref.grid_buy_fraction = 0.0015; % Zhou grid buying fraction
        config.ref.grid_sell_fraction = 0.1920; % Zhou grid selling fraction
        config.ref.curtailment_fraction = 0.0020; % Zhou curtailment fraction
        config.ref.co2_kg_kg_nh3 = 0.01; % Zhou carbon intensity, kg-CO2/kg-NH3
    case 's3'
        config.scenario.id = 's3'; % Scenario id
        config.scenario.mode = 'multi_state_flexible'; % Scenario mode
        config.environment.enable_co2_limit = true; % Enable CO2 constraint
        config.h2_storage.capacity_nm3 = 13.2e4; % H2 storage capacity, Nm3
        config.transformer.capacity_mw = 189; % Transformer capacity, MW
        config.ref.nh3_output_t_y = 7.04e4; % Zhou NH3 output, t/year
        config.ref.lcoa_usd_t = 475; % Zhou LCOA, USD/t
        config.ref.ael_use_h = 5460; % Zhou AEL utilization, h/year
        config.ref.grid_buy_fraction = 0.0112; % Zhou grid buying fraction
        config.ref.grid_sell_fraction = 0.2000; % Zhou grid selling fraction
        config.ref.curtailment_fraction = 0.0038; % Zhou curtailment fraction
        config.ref.co2_kg_kg_nh3 = 0.09; % Zhou carbon intensity, kg-CO2/kg-NH3
    otherwise
        error('default:bad_case', 'scenario_id must be s1, s2, or s3.');
end

config.h2_storage.capacity_kg = ...
    config.h2_storage.capacity_nm3 * config.unit.h2_kg_per_nm3; % H2 storage capacity, kg
end

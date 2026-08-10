function system_parameters = system_parameters_7day(scenario_name)
%SYSTEM_PARAMETERS_7DAY Integrated Zhou-based parameters for a 7-day case.
%   system_parameters = system_parameters_7day()
%   system_parameters = system_parameters_7day('continuous_flexible')
%   Accepted scenarios: fixed_load, continuous_flexible, multi_state_flexible.

if nargin < 1 || isempty(scenario_name)
    scenario_name = 'continuous_flexible';
end

scenario_name = normalize_scenario_name(scenario_name);

system_parameters = struct();
system_parameters = set_source_parameters(system_parameters, scenario_name);
system_parameters = set_time_parameters(system_parameters);
system_parameters = set_unit_parameters(system_parameters);
system_parameters = set_renewable_parameters(system_parameters);
system_parameters = set_financial_parameters(system_parameters);
system_parameters = set_generation_cost_parameters(system_parameters);
system_parameters = set_electrolyzer_parameters(system_parameters);
system_parameters = set_electrochemical_parameters(system_parameters);
system_parameters = set_hydrogen_storage_parameters(system_parameters);
system_parameters = set_haber_bosch_parameters(system_parameters);
system_parameters = set_electrical_parameters(system_parameters);
system_parameters = set_environment_parameters(system_parameters);
system_parameters = set_optimizer_parameters(system_parameters);
system_parameters = set_scenario_parameters(system_parameters, scenario_name);
system_parameters = add_derived_parameters(system_parameters);
system_parameters = add_parameter_audit(system_parameters);

validate_system_parameters(system_parameters);
end

function scenario_name = normalize_scenario_name(scenario_name)
if isstring(scenario_name)
    scenario_name = char(scenario_name);
end

if ~ischar(scenario_name)
    error('system_parameters_7day:bad_scenario', ...
        'scenario_name must be text.');
end

scenario_name = lower(strtrim(scenario_name));

switch scenario_name
    case {'s1', 'fixed', 'fixed_load'}
        scenario_name = 'fixed_load';
    case {'s2', 'flexible', 'continuous_flexible'}
        scenario_name = 'continuous_flexible';
    case {'s3', 'multi_state', 'multi_state_flexible'}
        scenario_name = 'multi_state_flexible';
    otherwise
        error('system_parameters_7day:bad_scenario', ...
            'Use fixed_load, continuous_flexible, or multi_state_flexible.');
end
end

function system_parameters = set_source_parameters(system_parameters, scenario_name)
system_parameters.source.literature_name = 'Zhou 2024 Energy Conversion and Management';
system_parameters.source.paper_title = ...
    ['Optimal capacity and multi-stable flexible operation strategy ', ...
    'of green ammonia systems adapting to renewable energy fluctuation'];
system_parameters.source.doi = '10.1016/j.enconman.2024.118720';
system_parameters.source.scenario_name = scenario_name;
system_parameters.source.parameter_table = 'Table 2';
system_parameters.source.scenario_table = 'Table 3';
system_parameters.source.reference_result_table = 'Table 4';
end

function system_parameters = set_time_parameters(system_parameters)
system_parameters.time.time_step_hour = 1;
system_parameters.time.simulation_day_count = 7;
system_parameters.time.hour_per_day = 24;
system_parameters.time.hour_per_year = 8760;
end

function system_parameters = set_unit_parameters(system_parameters)
system_parameters.unit.kg_per_ton = 1000;
system_parameters.unit.kw_per_mw = 1000;
system_parameters.unit.kwh_per_mwh = 1000;
system_parameters.unit.month_per_year = 12;
system_parameters.unit.hydrogen_density_kg_per_nm3 = 0.08988;
system_parameters.unit.hydrogen_nm3_per_kg = ...
    1 / system_parameters.unit.hydrogen_density_kg_per_nm3;
end

function system_parameters = set_renewable_parameters(system_parameters)
system_parameters.renewable.total_capacity_mw = 400;
system_parameters.renewable.photovoltaic_capacity_mw = 200;
system_parameters.renewable.wind_turbine_capacity_mw = 200;

system_parameters.renewable.recommended_photovoltaic_capacity_mw = 100;
system_parameters.renewable.recommended_wind_turbine_capacity_mw = 300;
system_parameters.renewable.wind_turbine_scan_capacity_mw = 0:50:400;
system_parameters.renewable.photovoltaic_scan_capacity_mw = ...
    system_parameters.renewable.total_capacity_mw - ...
    system_parameters.renewable.wind_turbine_scan_capacity_mw;

system_parameters.renewable.data_directory = '';
system_parameters.renewable.start_time = [];
end

function system_parameters = set_financial_parameters(system_parameters)
system_parameters.financial.project_lifetime_year = 20;
system_parameters.financial.discount_rate_per_year = 0.05;
system_parameters.financial.loan_term_year = 20;
system_parameters.financial.loan_ratio = 0.80;
system_parameters.financial.loan_interest_rate_per_year = 0.046;
system_parameters.financial.capital_recovery_factor = calculate_capital_recovery_factor( ...
    system_parameters.financial.discount_rate_per_year, ...
    system_parameters.financial.project_lifetime_year);
end

function system_parameters = set_generation_cost_parameters(system_parameters)
system_parameters.wind_turbine.capital_cost_usd_per_kw = 685;
system_parameters.wind_turbine.operation_maintenance_fraction_per_year = 0.02;

system_parameters.photovoltaic.capital_cost_usd_per_kw = 543;
system_parameters.photovoltaic.operation_maintenance_fraction_per_year = 0.01;
end

function system_parameters = set_electrolyzer_parameters(system_parameters)
system_parameters.alkaline_electrolyzer.capital_cost_usd_per_kw = 285;
system_parameters.alkaline_electrolyzer.operation_maintenance_fraction_per_year = 0.02;
system_parameters.alkaline_electrolyzer.module_hydrogen_capacity_nm3_per_hour = 1000;
system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_nm3 = 5.0;
system_parameters.alkaline_electrolyzer.minimum_load_fraction = 0.20;
system_parameters.alkaline_electrolyzer.maximum_load_fraction = 1.00;
system_parameters.alkaline_electrolyzer.minimum_stable_time_minute = 60;
system_parameters.alkaline_electrolyzer.startup_electricity_load_fraction_per_hour = 0.15;
system_parameters.alkaline_electrolyzer.water_consumption_ton_per_ton_hydrogen = 28;
system_parameters.alkaline_electrolyzer.piecewise_segment_count = 12;
system_parameters.alkaline_electrolyzer.initial_degradation_voltage_v = 0;
end

function system_parameters = set_electrochemical_parameters(system_parameters)
system_parameters.electrochemical_model.faraday_constant_c_per_mol = 96485.33212;
system_parameters.electrochemical_model.cell_count = 298;
system_parameters.electrochemical_model.active_area_m2 = 2.0;
system_parameters.electrochemical_model.ohmic_coefficient_1_ohm_m2 = 1.71e-4;
system_parameters.electrochemical_model.ohmic_coefficient_2_ohm_m2_per_celsius = -1.96e-7;
system_parameters.electrochemical_model.activation_coefficient_voltage_v = 0.16;
system_parameters.electrochemical_model.activation_coefficient_1_m2_per_a = -0.24;
system_parameters.electrochemical_model.activation_coefficient_2_m2_celsius_per_a = 26.23;
system_parameters.electrochemical_model.activation_coefficient_3_m2_celsius2_per_a = 139.88;
system_parameters.electrochemical_model.temperature_celsius = 90.0;
system_parameters.electrochemical_model.temperature_kelvin = ...
    system_parameters.electrochemical_model.temperature_celsius + 273.15;
system_parameters.electrochemical_model.faraday_efficiency_fraction = 1.0;
system_parameters.electrochemical_model.electron_count_per_hydrogen_molecule = 2;
system_parameters.electrochemical_model.hydrogen_molar_mass_kg_per_mol = 2.01588e-3;
end

function system_parameters = set_hydrogen_storage_parameters(system_parameters)
system_parameters.hydrogen_storage.capital_cost_usd_per_nm3 = 50;
system_parameters.hydrogen_storage.operation_maintenance_fraction_per_year = 0.01;
system_parameters.hydrogen_storage.module_capacity_nm3 = 22000;
system_parameters.hydrogen_storage.minimum_pressure_mpa = 0.5;
system_parameters.hydrogen_storage.maximum_pressure_mpa = 1.5;
system_parameters.hydrogen_storage.operation_temperature_celsius = 30;
end

function system_parameters = set_haber_bosch_parameters(system_parameters)
system_parameters.haber_bosch.capital_cost_usd_per_ton_per_year_capacity = 561;
system_parameters.haber_bosch.operation_maintenance_fraction_per_year = 0.02;
system_parameters.haber_bosch.rated_ammonia_capacity_ton_per_year = 100000;
system_parameters.haber_bosch.electricity_consumption_mwh_per_ton_ammonia = 0.95;

system_parameters.haber_bosch.literature_ammonia_output_ton_per_ton_ammonia = 1.00;
system_parameters.haber_bosch.literature_nitrogen_consumption_ton_per_ton_ammonia = 0.84;
system_parameters.haber_bosch.literature_hydrogen_consumption_ton_per_ton_ammonia = 0.18;

system_parameters.haber_bosch.stoichiometric_nitrogen_consumption_ton_per_ton_ammonia = 28 / 34;
system_parameters.haber_bosch.stoichiometric_hydrogen_consumption_ton_per_ton_ammonia = 6 / 34;
system_parameters.haber_bosch.active_nitrogen_consumption_ton_per_ton_ammonia = 28 / 34;
system_parameters.haber_bosch.active_hydrogen_consumption_ton_per_ton_ammonia = 6 / 34;

system_parameters.haber_bosch.water_consumption_ton_per_ton_ammonia = 2.70;
system_parameters.haber_bosch.stable_load_step_fraction = 0.10;
system_parameters.haber_bosch.flexible_load_interval_hour = 4;

system_parameters.ammonia_product.selling_price_usd_per_ton = 557;
system_parameters.raw_material.water_price_usd_per_ton = 1.4;
system_parameters.raw_material.catalyst_price_usd_per_ton = 18;
end

function system_parameters = set_electrical_parameters(system_parameters)
system_parameters.converter.capital_cost_usd_per_kw = 43;
system_parameters.converter.operation_maintenance_fraction_per_year = 0.02;

system_parameters.transformer.capital_cost_usd_per_kw = 51;
system_parameters.transformer.operation_maintenance_fraction_per_year = 0.02;
system_parameters.transformer.maximum_load_fraction = 0.90;

system_parameters.public_grid.electricity_selling_price_usd_per_kwh = 0.041;
system_parameters.public_grid.electricity_purchase_price_usd_per_kwh = 0.053;
system_parameters.public_grid.capacity_charge_usd_per_kw_month = 3.85;
system_parameters.public_grid.curtailment_limit_fraction = 0.10;
system_parameters.public_grid.electricity_selling_limit_fraction = 0.20;
system_parameters.public_grid.enable_electricity_purchase = true;
system_parameters.public_grid.enable_electricity_selling = true;
end

function system_parameters = set_environment_parameters(system_parameters)
system_parameters.environment.grid_carbon_emission_kg_per_kwh = 0.5703;
system_parameters.environment.ammonia_carbon_limit_kg_per_kg = 0.3;
end

function system_parameters = set_optimizer_parameters(system_parameters)
system_parameters.particle_swarm.cognitive_weight = 1;
system_parameters.particle_swarm.social_weight = 1;
system_parameters.particle_swarm.inertia_weight = 1;
system_parameters.particle_swarm.maximum_iteration_count = 100;
system_parameters.particle_swarm.population_count = 10;
end

function system_parameters = set_scenario_parameters(system_parameters, scenario_name)
system_parameters.scenario.name = scenario_name;

switch scenario_name
    case 'fixed_load'
        system_parameters.scenario.zhou_case_name = 'S1';
        system_parameters.haber_bosch.minimum_load_fraction = 1.00;
        system_parameters.haber_bosch.maximum_load_fraction = 1.00;
        system_parameters.haber_bosch.fixed_load_fraction = 1.00;
        system_parameters.haber_bosch.ramp_rate_fraction_per_hour = 0;
        system_parameters.haber_bosch.stable_operation_window_hour = [0, 24];
        system_parameters.haber_bosch.flexible_operation_window_hour = zeros(0, 2);
        system_parameters.alkaline_electrolyzer.enable_startup_electricity = false;
        system_parameters.environment.enable_carbon_constraint = false;
        system_parameters.alkaline_electrolyzer.installed_capacity_mw = 140;
        system_parameters.hydrogen_storage.installed_capacity_nm3 = 17.6e4;
        system_parameters.transformer.installed_capacity_mw = 190;
        system_parameters.reference_result.ammonia_production_ton_per_year = 1.00e5;
        system_parameters.reference_result.levelized_cost_usd_per_ton = 549;
        system_parameters.reference_result.electrolyzer_utilization_hour = 7163;
        system_parameters.reference_result.electricity_purchase_fraction = 0.3086;
        system_parameters.reference_result.electricity_selling_fraction = 0.1724;
        system_parameters.reference_result.curtailment_fraction = 0.0021;
        system_parameters.reference_result.carbon_emission_kg_per_kg_ammonia = 1.70;

    case 'continuous_flexible'
        system_parameters.scenario.zhou_case_name = 'S2';
        system_parameters.haber_bosch.minimum_load_fraction = 0.30;
        system_parameters.haber_bosch.maximum_load_fraction = 1.00;
        system_parameters.haber_bosch.fixed_load_fraction = [];
        system_parameters.haber_bosch.ramp_rate_fraction_per_hour = 0.20;
        system_parameters.haber_bosch.stable_operation_window_hour = zeros(0, 2);
        system_parameters.haber_bosch.flexible_operation_window_hour = [0, 24];
        system_parameters.alkaline_electrolyzer.enable_startup_electricity = false;
        system_parameters.environment.enable_carbon_constraint = true;
        system_parameters.alkaline_electrolyzer.installed_capacity_mw = 130;
        system_parameters.hydrogen_storage.installed_capacity_nm3 = 11.0e4;
        system_parameters.transformer.installed_capacity_mw = 200;
        system_parameters.reference_result.ammonia_production_ton_per_year = 7.12e4;
        system_parameters.reference_result.levelized_cost_usd_per_ton = 464;
        system_parameters.reference_result.electrolyzer_utilization_hour = 5492;
        system_parameters.reference_result.electricity_purchase_fraction = 0.0015;
        system_parameters.reference_result.electricity_selling_fraction = 0.1920;
        system_parameters.reference_result.curtailment_fraction = 0.0020;
        system_parameters.reference_result.carbon_emission_kg_per_kg_ammonia = 0.01;

    case 'multi_state_flexible'
        system_parameters.scenario.zhou_case_name = 'S3';
        system_parameters.haber_bosch.minimum_load_fraction = 0.30;
        system_parameters.haber_bosch.maximum_load_fraction = 1.10;
        system_parameters.haber_bosch.fixed_load_fraction = 0.30:0.10:1.10;
        system_parameters.haber_bosch.ramp_rate_fraction_per_hour = 0.20;
        system_parameters.haber_bosch.stable_operation_window_hour = [0, 12; 16, 24];
        system_parameters.haber_bosch.flexible_operation_window_hour = [12, 16];
        system_parameters.alkaline_electrolyzer.enable_startup_electricity = true;
        system_parameters.environment.enable_carbon_constraint = true;
        system_parameters.alkaline_electrolyzer.installed_capacity_mw = 130;
        system_parameters.hydrogen_storage.installed_capacity_nm3 = 13.2e4;
        system_parameters.transformer.installed_capacity_mw = 189;
        system_parameters.reference_result.ammonia_production_ton_per_year = 7.04e4;
        system_parameters.reference_result.levelized_cost_usd_per_ton = 475;
        system_parameters.reference_result.electrolyzer_utilization_hour = 5460;
        system_parameters.reference_result.electricity_purchase_fraction = 0.0112;
        system_parameters.reference_result.electricity_selling_fraction = 0.2000;
        system_parameters.reference_result.curtailment_fraction = 0.0038;
        system_parameters.reference_result.carbon_emission_kg_per_kg_ammonia = 0.09;
end
end

function system_parameters = add_derived_parameters(system_parameters)
unit = system_parameters.unit;

system_parameters.renewable.total_capacity_kw = ...
    system_parameters.renewable.total_capacity_mw * unit.kw_per_mw;
system_parameters.renewable.photovoltaic_capacity_kw = ...
    system_parameters.renewable.photovoltaic_capacity_mw * unit.kw_per_mw;
system_parameters.renewable.wind_turbine_capacity_kw = ...
    system_parameters.renewable.wind_turbine_capacity_mw * unit.kw_per_mw;

system_parameters.alkaline_electrolyzer.maximum_power_kw = ...
    system_parameters.alkaline_electrolyzer.installed_capacity_mw * unit.kw_per_mw;
system_parameters.alkaline_electrolyzer.minimum_power_kw = ...
    system_parameters.alkaline_electrolyzer.maximum_power_kw * ...
    system_parameters.alkaline_electrolyzer.minimum_load_fraction;
system_parameters.alkaline_electrolyzer.module_power_kw = ...
    system_parameters.alkaline_electrolyzer.module_hydrogen_capacity_nm3_per_hour * ...
    system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_nm3;
system_parameters.alkaline_electrolyzer.module_count = ceil( ...
    system_parameters.alkaline_electrolyzer.maximum_power_kw / ...
    system_parameters.alkaline_electrolyzer.module_power_kw);
system_parameters.alkaline_electrolyzer.rated_hydrogen_output_nm3_per_hour = ...
    system_parameters.alkaline_electrolyzer.maximum_power_kw / ...
    system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_nm3;
system_parameters.alkaline_electrolyzer.rated_hydrogen_output_kg_per_hour = ...
    system_parameters.alkaline_electrolyzer.rated_hydrogen_output_nm3_per_hour * ...
    unit.hydrogen_density_kg_per_nm3;
system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_kg = ...
    system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_nm3 / ...
    unit.hydrogen_density_kg_per_nm3;

system_parameters.hydrogen_storage.installed_capacity_kg = ...
    system_parameters.hydrogen_storage.installed_capacity_nm3 * ...
    unit.hydrogen_density_kg_per_nm3;

system_parameters.haber_bosch.rated_ammonia_output_kg_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_capacity_ton_per_year * ...
    unit.kg_per_ton / system_parameters.time.hour_per_year;
system_parameters.haber_bosch.rated_ammonia_output_ton_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_capacity_ton_per_year / ...
    system_parameters.time.hour_per_year;
system_parameters.haber_bosch.rated_hydrogen_demand_kg_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_output_kg_per_hour * ...
    system_parameters.haber_bosch.active_hydrogen_consumption_ton_per_ton_ammonia;
system_parameters.haber_bosch.rated_nitrogen_demand_kg_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_output_kg_per_hour * ...
    system_parameters.haber_bosch.active_nitrogen_consumption_ton_per_ton_ammonia;
system_parameters.haber_bosch.literature_hydrogen_demand_kg_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_output_kg_per_hour * ...
    system_parameters.haber_bosch.literature_hydrogen_consumption_ton_per_ton_ammonia;
system_parameters.haber_bosch.literature_nitrogen_demand_kg_per_hour = ...
    system_parameters.haber_bosch.rated_ammonia_output_kg_per_hour * ...
    system_parameters.haber_bosch.literature_nitrogen_consumption_ton_per_ton_ammonia;
system_parameters.haber_bosch.rated_electric_power_mw = ...
    system_parameters.haber_bosch.rated_ammonia_capacity_ton_per_year * ...
    system_parameters.haber_bosch.electricity_consumption_mwh_per_ton_ammonia / ...
    system_parameters.time.hour_per_year;

system_parameters.hydrogen_storage.full_load_supply_hour = ...
    system_parameters.hydrogen_storage.installed_capacity_kg / ...
    system_parameters.haber_bosch.rated_hydrogen_demand_kg_per_hour;

system_parameters.converter.installed_capacity_mw = ...
    system_parameters.alkaline_electrolyzer.installed_capacity_mw;
system_parameters.transformer.maximum_usable_power_mw = ...
    system_parameters.transformer.installed_capacity_mw * ...
    system_parameters.transformer.maximum_load_fraction;
end

function system_parameters = add_parameter_audit(system_parameters)
audit_warning = {};

literature_mass_sum = ...
    system_parameters.haber_bosch.literature_hydrogen_consumption_ton_per_ton_ammonia + ...
    system_parameters.haber_bosch.literature_nitrogen_consumption_ton_per_ton_ammonia;
stoichiometric_mass_sum = ...
    system_parameters.haber_bosch.stoichiometric_hydrogen_consumption_ton_per_ton_ammonia + ...
    system_parameters.haber_bosch.stoichiometric_nitrogen_consumption_ton_per_ton_ammonia;

if abs(literature_mass_sum - 1.0) > 1e-6
    audit_warning{end + 1} = ...
        'Zhou rounded H2 and N2 ratios sum to 1.02; active mass balance uses exact 6/34 and 28/34.';
end

audit_warning{end + 1} = ...
    'Zhou electrolyzer energy is kWh/Nm3, not kWh/kg; the kWh/kg value is derived separately.';
audit_warning{end + 1} = ...
    'Electrochemical ohmic and activation empirical terms use Celsius; reversible voltage uses Kelvin.';
audit_warning{end + 1} = ...
    'Startup electricity parameter is recorded as 15 percent load per hour from Zhou Table 2.';

system_parameters.audit.literature_haber_bosch_mass_sum = literature_mass_sum;
system_parameters.audit.stoichiometric_haber_bosch_mass_sum = stoichiometric_mass_sum;
system_parameters.audit.specific_energy_kwh_per_nm3 = ...
    system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_nm3;
system_parameters.audit.specific_energy_kwh_per_kg = ...
    system_parameters.alkaline_electrolyzer.specific_energy_consumption_kwh_per_kg;
system_parameters.audit.warning_message = audit_warning;
end

function validate_system_parameters(system_parameters)
renewable_capacity_error_mw = ...
    system_parameters.renewable.photovoltaic_capacity_mw + ...
    system_parameters.renewable.wind_turbine_capacity_mw - ...
    system_parameters.renewable.total_capacity_mw;

if abs(renewable_capacity_error_mw) > 1e-9
    error('system_parameters_7day:bad_renewable_capacity', ...
        'Photovoltaic plus wind capacity must equal total renewable capacity.');
end

if system_parameters.alkaline_electrolyzer.minimum_power_kw > ...
        system_parameters.alkaline_electrolyzer.maximum_power_kw
    error('system_parameters_7day:bad_electrolyzer_load', ...
        'Electrolyzer minimum power exceeds maximum power.');
end

if system_parameters.haber_bosch.minimum_load_fraction > ...
        system_parameters.haber_bosch.maximum_load_fraction
    error('system_parameters_7day:bad_haber_bosch_load', ...
        'Haber-Bosch minimum load exceeds maximum load.');
end

if system_parameters.hydrogen_storage.installed_capacity_kg <= 0
    error('system_parameters_7day:bad_hydrogen_storage', ...
        'Hydrogen storage capacity must be positive.');
end

if system_parameters.transformer.installed_capacity_mw <= 0
    error('system_parameters_7day:bad_transformer_capacity', ...
        'Transformer capacity must be positive.');
end

if system_parameters.time.time_step_hour <= 0
    error('system_parameters_7day:bad_time_step', ...
        'Time step must be positive.');
end
end

function capital_recovery_factor = calculate_capital_recovery_factor(rate, year_count)
if rate == 0
    capital_recovery_factor = 1 / year_count;
else
    capital_recovery_factor = rate * (1 + rate)^year_count / ...
        ((1 + rate)^year_count - 1);
end
end

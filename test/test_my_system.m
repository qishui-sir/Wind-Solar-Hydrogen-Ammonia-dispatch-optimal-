function tests = test_my_system
tests = functiontests(localfunctions);
end

function setupOnce(~)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src'));
addpath(fullfile(project_dir, 'src', 'params'));
end

function testDefaultScenarioIsS2(test_case)
case_config = my_system();

verifyEqual(test_case, case_config.scenario.id, 's2');
verifyEqual(test_case, case_config.scenario.mode, 'continuous_flexible');
verifyEqual(test_case, case_config.AEL.capacity_mw, 130);
verifyEqual(test_case, case_config.h2_storage.capacity_nm3, 11.0e4);
verifyEqual(test_case, case_config.ref.lcoa_usd_t, 464);
end

function testStandaloneParameterFiles(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
params_dir = fullfile(project_dir, 'src', 'params');
old_path = path;
path_cleanup = onCleanup(@() path(old_path));
addpath(params_dir, '-begin');

verifyTrue(test_case, strcmpi(which('default'), fullfile(params_dir, 'default.m')));

default_config = default('s2');
ael_parameters = AEL(default_config, 's2');
hb_parameters = HB(default_config, 's2');

verifyEqual(test_case, default_config.ref.lcoa_usd_t, 464);
verifyEqual(test_case, ael_parameters.F, 96485.33212);
verifyEqual(test_case, ael_parameters.capacity_mw, 130);
verifyEqual(test_case, ael_parameters.qi_stack_h2_nm3_h, 500);
verifyEqual(test_case, ael_parameters.module_h2_nm3_h, 1000);
verifyEqual(test_case, hb_parameters.active_h2_t_per_t_nh3, 6 / 34);
verifyEqual(test_case, hb_parameters.max_load_fraction, 1.00);
end

function testScenarioSelection(test_case)
s1_config = my_system('s1');
s3_config = my_system("s3");

verifyEqual(test_case, s1_config.scenario.mode, 'fixed_load');
verifyEqual(test_case, s1_config.HB.min_load_fraction, 1.00);
verifyEqual(test_case, s1_config.HB.max_load_fraction, 1.00);
verifyEqual(test_case, s1_config.environment.enable_co2_limit, false);

verifyEqual(test_case, s3_config.scenario.mode, 'multi_state_flexible');
verifyEqual(test_case, s3_config.HB.max_load_fraction, 1.10);
verifyEqual(test_case, s3_config.AEL.enable_start_energy, true);
verifyEqual(test_case, s3_config.transformer.capacity_mw, 189);
end

function testDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.renewable.total_capacity_kw, ...
    case_config.renewable.pv_capacity_kw + case_config.renewable.pw_capacity_kw);
verifyEqual(test_case, case_config.AEL.max_power_kw, 130000);
verifyEqual(test_case, case_config.AEL.module_count, 26);
verifyEqual(test_case, case_config.AEL.qi_stack_count, 52);
verifyEqual(test_case, case_config.AEL.qi_stack_count_per_module, 2);
verifyEqual(test_case, case_config.h2_storage.capacity_kg, 9886.8, 'AbsTol', 1e-9);
verifyEqual(test_case, case_config.converter.capacity_mw, ...
    case_config.AEL.capacity_mw);
end

function testZhouEnergyUnitAndDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.AEL.specific_energy_kwh_nm3, 5.0);
verifyEqual(test_case, case_config.AEL.specific_energy_kwh_kg, ...
    55.63, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.AEL.h2_output_nm3_h, 26000);
verifyEqual(test_case, case_config.AEL.h2_output_kg_h, ...
    2336.88, 'AbsTol', 1e-9);
end

function testHaberBoschUsesExactStoichiometryForDispatch(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.HB.literature_h2_t_per_t_nh3, 0.18);
verifyEqual(test_case, case_config.HB.literature_n2_t_per_t_nh3, 0.84);
verifyEqual(test_case, case_config.audit.literature_h2_n2_sum, 1.02, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.active_h2_t_per_t_nh3, 6 / 34);
verifyEqual(test_case, case_config.HB.active_n2_t_per_t_nh3, 28 / 34);
verifyEqual(test_case, case_config.audit.active_h2_n2_sum, 1.0, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.capacity_kg_h, 11415.53, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.HB.h2_demand_kg_h, 2014.50, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.HB.nominal_power_mw, 10.8447, 'AbsTol', 5e-5);
end

function testTemperatureAndStartupUnitNames(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.AEL.temperature_celsius, 90.0);
verifyEqual(test_case, case_config.AEL.temperature_kelvin, 363.15);
verifyEqual(test_case, case_config.AEL.pid_i_temperature_setpoint_celsius, 89.57);
verifyEqual(test_case, case_config.AEL.mpc_temperature_setpoint_celsius, 93.23);
verifyEqual(test_case, ...
    case_config.AEL.startup_electricity_load_fraction_per_hour, 0.15);
end

function testQiAelVoltageHeatAndHydrogenEquations(test_case)
ael_parameters = AEL();
model_output = qi_ael_model(2000, 0, ael_parameters);

verifyEqual(test_case, model_output.average_temperature_celsius, 90.0);
verifyEqual(test_case, model_output.reversible_voltage_v, ...
    1.1752222640544785, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.ohmic_voltage_v, 0.30672, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.activation_voltage_v, ...
    0.7888550832435931, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.cell_voltage_v, ...
    2.2707973472980716, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.power_mw, ...
    2.7067904379793015, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.heat_power_mw, ...
    0.9426304379793013, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.hydrogen_power_mw, 1.76416, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.h2_nm3_h, ...
    498.75708358750325, 'AbsTol', 1e-9);
verifyEqual(test_case, model_output.efficiency_hhv, ...
    0.6517534476429573, 'AbsTol', 1e-12);
end

function testQiAelModelLoadsAelDefaults(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
src_dir = fullfile(project_dir, 'src');
params_dir = fullfile(src_dir, 'params');
old_path = path;
path_cleanup = onCleanup(@() path(old_path));

rmpath(params_dir);
addpath(src_dir, '-begin');
default_output = qi_ael_model(2000);

addpath(params_dir, '-begin');
explicit_output = qi_ael_model(2000, 0, AEL());

verifyEqual(test_case, default_output.power_mw, explicit_output.power_mw, 'AbsTol', 1e-12);
verifyEqual(test_case, default_output.P_AEL, explicit_output.P_AEL, 'AbsTol', 1e-12);
verifyEqual(test_case, default_output.U_deg, 0);
end

function testRejectsUnknownScenario(test_case)
verifyError(test_case, @() my_system('s4'), 'my_system:bad_case');
end

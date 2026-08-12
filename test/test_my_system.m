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
verifyEqual(test_case, case_config.AEL.capacity, 130);
verifyEqual(test_case, case_config.h2_storage.capacity, 11.0e4);
verifyEqual(test_case, case_config.ref.lcoa, 464);
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

verifyEqual(test_case, default_config.ref.lcoa, 464);
verifyEqual(test_case, ael_parameters.far_const, 96485.33212);
verifyEqual(test_case, ael_parameters.capacity, 130);
verifyEqual(test_case, ael_parameters.stack_h2, 500);
verifyEqual(test_case, ael_parameters.module_h2, 1000);
verifyEqual(test_case, hb_parameters.act_h2, 6 / 34);
verifyEqual(test_case, hb_parameters.max_load, 1.00);
end

function testAelParametersDoNotExposeDuplicateAliases(test_case)
ael_parameters = AEL();

duplicate_names = {'F', 'faraday_constant_c_mol', 'eta_F', ...
    'faraday_efficiency', 'N_cell', 'cell_count', 'A_m2', ...
    'cell_area_m2', 'T_C', 'T_K', 'temperature_celsius', ...
    'temperature_kelvin', 'stack_temperature_celsius', ...
    'separator_temperature_celsius', 'thermal_neutral_voltage', ...
    'specific_energy', 'startup_enabled', 'startup_electricity', ...
    'h2_mass_output', 'qi_h2_rate', 'qi_cur_density', ...
    'mod_h2_rate', 'vol_spe_energy', 'mas_spe_energy'};

for name_index = 1:numel(duplicate_names)
    verifyFalse(test_case, isfield(ael_parameters, duplicate_names{name_index}), ...
        sprintf('AEL parameter alias should be removed: %s', ...
        duplicate_names{name_index}));
end
end

function testAelAndHbFieldNamesAreShort(test_case)
verifyFieldNamesAreShort(test_case, AEL());
verifyFieldNamesAreShort(test_case, HB());
end

function testSystemFieldNamesAreShort(test_case)
case_config = my_system();

verifyFieldNamesAreShort(test_case, case_config);
end

function testDefaultDoesNotExposeLongAliases(test_case)
default_config = default('s2');

old_names = {'time_step_h', 'day_count', 'hour_per_day', ...
    'hour_per_year', 'h2_kg_per_nm3', 'kg_per_t', 'kw_per_mw', ...
    'total_capacity_kw', 'pv_capacity_kw', 'pw_capacity_kw', ...
    'pv_recommended_kw', 'pw_recommended_kw', 'pw_min_capacity_kw', ...
    'pw_max_capacity_kw', 'pw_capacity_step_kw', 'project_lifetime_y', ...
    'discount_rate', 'capital_recovery_factor', 'capex_usd_kw', ...
    'om_fraction', 'module_capacity_nm3', 'temperature_celsius', ...
    'max_load_fraction', 'sell_price_usd_kwh', 'grid_co2_kg_kwh', ...
    'co2_limit_kg_kg_nh3', 'enable_co2_limit', 'nh3_output_t_y', ...
    'lcoa_usd_t', 'grid_buy_fraction', 'curtailment_fraction'};

for name_index = 1:numel(old_names)
    verifyFalse(test_case, structHasField(default_config, old_names{name_index}), ...
        sprintf('Default parameter alias should be removed: %s', ...
        old_names{name_index}));
end
end

function testZhouDefaultTableValues(test_case)
s1_config = default('s1');
s2_config = default('s2');
s3_config = default('s3');

verifyEqual(test_case, s2_config.time.step, 1);
verifyEqual(test_case, s2_config.time.days, 7);
verifyEqual(test_case, s2_config.time.hour_year, 8760);
verifyEqual(test_case, s2_config.unit.h2_density, 0.08988);
verifyEqual(test_case, s2_config.unit.mass_scale, 1000);
verifyEqual(test_case, s2_config.unit.power_scale, 1000);

verifyEqual(test_case, s2_config.renewable.total_capacity, 400e3);
verifyEqual(test_case, s2_config.renewable.PV_capacity, 200e3);
verifyEqual(test_case, s2_config.renewable.PW_capacity, 200e3);
verifyEqual(test_case, s2_config.renewable.PV_ref, 100e3);
verifyEqual(test_case, s2_config.renewable.PW_ref, 300e3);

verifyEqual(test_case, s2_config.finance.lifetime, 20);
verifyEqual(test_case, s2_config.finance.discount, 0.05);
verifyEqual(test_case, s2_config.finance.loan_term, 20);
verifyEqual(test_case, s2_config.finance.loan_ratio, 0.80);
verifyEqual(test_case, s2_config.finance.loan_interest, 0.046);

verifyEqual(test_case, s2_config.pw.capex, 685);
verifyEqual(test_case, s2_config.pw.om_rate, 0.02);
verifyEqual(test_case, s2_config.pv.capex, 543);
verifyEqual(test_case, s2_config.pv.om_rate, 0.01);
verifyEqual(test_case, s2_config.h2_storage.capex, 50);
verifyEqual(test_case, s2_config.h2_storage.module_cap, 22000);
verifyEqual(test_case, s2_config.h2_storage.temperature, 30);
verifyEqual(test_case, s2_config.ammonia.price, 557);
verifyEqual(test_case, s2_config.grid.sell_price, 0.041);
verifyEqual(test_case, s2_config.grid.buy_price, 0.053);
verifyEqual(test_case, s2_config.grid.cap_fee, 3.85);
verifyEqual(test_case, s2_config.grid.curtail_limit, 0.10);
verifyEqual(test_case, s2_config.grid.max_sell, 0.20);
verifyEqual(test_case, s2_config.environment.grid_co2, 0.5703);
verifyEqual(test_case, s2_config.environment.co2_limit, 0.3);

verifyEqual(test_case, s1_config.h2_storage.capacity, 17.6e4);
verifyEqual(test_case, s2_config.h2_storage.capacity, 11.0e4);
verifyEqual(test_case, s3_config.h2_storage.capacity, 13.2e4);
verifyEqual(test_case, s2_config.transformer.capacity, 200);
verifyEqual(test_case, s2_config.ref.nh3_output, 7.12e4);
verifyEqual(test_case, s2_config.ref.lcoa, 464);
verifyEqual(test_case, s2_config.ref.ael_hours, 5492);
verifyEqual(test_case, s2_config.ref.grid_buy, 0.0015);
verifyEqual(test_case, s2_config.ref.grid_sell, 0.1920);
verifyEqual(test_case, s2_config.ref.curtailment, 0.0020);
verifyEqual(test_case, s2_config.ref.co2_intensity, 0.01);
end

function testSystemDerivedUnits(test_case)
case_config = my_system('s2');

expected_crf = 0.05 * (1 + 0.05)^20 / ((1 + 0.05)^20 - 1);

verifyEqual(test_case, case_config.finance.crf, expected_crf, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.h2_storage.mass, ...
    case_config.h2_storage.capacity * case_config.unit.h2_density, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, case_config.AEL.max_power, ...
    case_config.AEL.capacity * case_config.unit.power_scale);
verifyEqual(test_case, case_config.AEL.mass_spec_energy, ...
    case_config.AEL.spec_energy / case_config.unit.h2_density, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.nh3_output, ...
    case_config.HB.capacity * case_config.unit.mass_scale / ...
    case_config.time.hour_year, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.h2_demand, ...
    case_config.HB.nh3_output * 6 / 34, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.nom_power, ...
    case_config.HB.capacity * case_config.HB.spec_energy / ...
    case_config.time.hour_year, 'AbsTol', 1e-12);
end

function testScenarioSelection(test_case)
s1_config = my_system('s1');
s3_config = my_system("s3");

verifyEqual(test_case, s1_config.scenario.mode, 'fixed_load');
verifyEqual(test_case, s1_config.HB.min_load, 1.00);
verifyEqual(test_case, s1_config.HB.max_load, 1.00);
verifyEqual(test_case, s1_config.environment.co2_enabled, false);

verifyEqual(test_case, s3_config.scenario.mode, 'multi_state_flexible');
verifyEqual(test_case, s3_config.HB.max_load, 1.10);
verifyEqual(test_case, s3_config.AEL.startup, true);
verifyEqual(test_case, s3_config.transformer.capacity, 189);
end

function testDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.renewable.total_capacity, ...
    case_config.renewable.PV_capacity + case_config.renewable.PW_capacity);
verifyEqual(test_case, case_config.AEL.max_power, 130000);
verifyEqual(test_case, case_config.AEL.module_num, 26);
verifyEqual(test_case, case_config.AEL.stack_num, 52);
verifyEqual(test_case, case_config.AEL.stack_per_module, 2);
verifyEqual(test_case, case_config.h2_storage.mass, 9886.8, 'AbsTol', 1e-9);
verifyEqual(test_case, case_config.converter.capacity, ...
    case_config.AEL.capacity);
end

function testZhouEnergyUnitAndDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.AEL.spec_energy, 5.0);
verifyEqual(test_case, case_config.AEL.mass_spec_energy, ...
    55.63, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.AEL.h2_output, 26000);
verifyEqual(test_case, case_config.AEL.h2_mass, ...
    2336.88, 'AbsTol', 1e-9);
end

function testHaberBoschUsesExactStoichiometryForDispatch(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.HB.lit_h2, 0.18);
verifyEqual(test_case, case_config.HB.lit_n2, 0.84);
verifyEqual(test_case, case_config.audit.lit_sum, 1.02, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.act_h2, 6 / 34);
verifyEqual(test_case, case_config.HB.act_n2, 28 / 34);
verifyEqual(test_case, case_config.audit.act_sum, 1.0, 'AbsTol', 1e-12);
verifyEqual(test_case, case_config.HB.nh3_output, 11415.53, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.HB.h2_demand, 2014.50, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.HB.nom_power, 10.8447, 'AbsTol', 5e-5);
end

function testTemperatureAndStartupUnitNames(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.AEL.stack_temp, 90.0);
verifyEqual(test_case, case_config.AEL.sep_temp, 90.0);
verifyEqual(test_case, case_config.AEL.pid_i_set, 89.57);
verifyEqual(test_case, case_config.AEL.mpc_set, 93.23);
verifyEqual(test_case, case_config.AEL.startup_elec, 0.15);
end

function testQiAelVoltageHeatAndHydrogenEquations(test_case)
ael_parameters = AEL();
model_output = qi_ael_model(2000, 0, ael_parameters);

verifyEqual(test_case, model_output.avg_temp, 90.0);
verifyEqual(test_case, model_output.rev_voltage, ...
    1.1752222640544785, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.ohm_voltage, 0.30672, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.act_voltage, ...
    0.7888550832435931, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.cel_voltage, ...
    2.2707973472980716, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.power, ...
    2.7067904379793015, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.hea_power, ...
    0.9426304379793013, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.hyd_power, 1.76416, 'AbsTol', 1e-12);
verifyEqual(test_case, model_output.h2_flow, ...
    498.75708358750325, 'AbsTol', 1e-9);
verifyEqual(test_case, model_output.hhv_efficiency, ...
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

verifyEqual(test_case, default_output.power, explicit_output.power, 'AbsTol', 1e-12);
verifyEqual(test_case, default_output.deg_voltage, 0);
end

function testRejectsUnknownScenario(test_case)
verifyError(test_case, @() my_system('s4'), 'my_system:bad_case');
end

function verifyFieldNamesAreShort(test_case, value, prefix)
if nargin < 3
    prefix = "";
end

if ~isstruct(value)
    return
end

names = fieldnames(value);
for name_index = 1:numel(names)
    name = names{name_index};
    full_name = name;
    if strlength(prefix) > 0
        full_name = prefix + "." + name;
    end

    verifyLessThanOrEqual(test_case, strlength(name), 16, ...
        sprintf('Parameter name exceeds 16 characters: %s', full_name));

    if isscalar(value)
        verifyFieldNamesAreShort(test_case, value.(name), full_name);
    end
end
end

function has_field = structHasField(value, target_name)
has_field = false;
if ~isstruct(value)
    return
end

names = fieldnames(value);
for name_index = 1:numel(names)
    name = names{name_index};
    if strcmp(name, target_name)
        has_field = true;
        return
    end

    if isscalar(value) && structHasField(value.(name), target_name)
        has_field = true;
        return
    end
end
end

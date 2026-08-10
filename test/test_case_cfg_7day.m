function tests = test_case_cfg_7day
tests = functiontests(localfunctions);
end

function setupOnce(~)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src'));
end

function testDefaultScenarioIsS2(test_case)
case_config = case_cfg_7day();

verifyEqual(test_case, case_config.scenario.id, 's2');
verifyEqual(test_case, case_config.scenario.mode, 'continuous_flexible');
verifyEqual(test_case, case_config.alkaline_electrolyzer.capacity_mw, 130);
verifyEqual(test_case, case_config.h2_storage.capacity_nm3, 11.0e4);
verifyEqual(test_case, case_config.reference.lcoa_usd_t, 464);
end

function testScenarioSelection(test_case)
s1_config = case_cfg_7day('s1');
s3_config = case_cfg_7day("s3");

verifyEqual(test_case, s1_config.scenario.mode, 'fixed_load');
verifyEqual(test_case, s1_config.haber_bosch.min_load_fraction, 1.00);
verifyEqual(test_case, s1_config.haber_bosch.max_load_fraction, 1.00);
verifyEqual(test_case, s1_config.environment.enable_co2_limit, false);

verifyEqual(test_case, s3_config.scenario.mode, 'multi_state_flexible');
verifyEqual(test_case, s3_config.haber_bosch.max_load_fraction, 1.10);
verifyEqual(test_case, s3_config.alkaline_electrolyzer.enable_start_energy, true);
verifyEqual(test_case, s3_config.transformer.capacity_mw, 189);
end

function testDerivedValues(test_case)
case_config = case_cfg_7day('s2');

verifyEqual(test_case, case_config.renewable.total_capacity_kw, ...
    case_config.renewable.pv_capacity_kw + case_config.renewable.pw_capacity_kw);
verifyEqual(test_case, case_config.alkaline_electrolyzer.max_power_kw, 130000);
verifyEqual(test_case, case_config.alkaline_electrolyzer.module_count, 26);
verifyEqual(test_case, case_config.h2_storage.capacity_kg, 9886.8, 'AbsTol', 1e-9);
verifyEqual(test_case, case_config.converter.capacity_mw, ...
    case_config.alkaline_electrolyzer.capacity_mw);
end

function testRejectsUnknownScenario(test_case)
verifyError(test_case, @() case_cfg_7day('s4'), 'case_cfg_7day:bad_case');
end

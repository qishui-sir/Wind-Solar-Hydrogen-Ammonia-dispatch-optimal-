function tests = test_load_res_7day
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src'));
test_case.TestData.project_dir = project_dir;
test_case.TestData.data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
end

function testDefaultDataLocation(test_case)
renewable_data = load_res_7day();

verifyEqual(test_case, renewable_data.time_count, 168);
verifyEqual(test_case, renewable_data.time(1), ...
    datetime(2022, 1, 1, 0, 0, 0, 'TimeZone', 'UTC'));
verifyEqual(test_case, renewable_data.time(end), ...
    datetime(2022, 1, 7, 23, 0, 0, 'TimeZone', 'UTC'));
verifyEqual(test_case, renewable_data.source.data_dir, test_case.TestData.data_dir);
verifyGreaterThanOrEqual(test_case, min(renewable_data.renewable_power_kw), 0);
end

function testDataDirConfig(test_case)
config = struct();
config.data_dir = test_case.TestData.data_dir;

renewable_data = load_res_7day(config);

verifyEqual(test_case, renewable_data.time_count, 168);
verifyEqual(test_case, renewable_data.pv_power_kw(1), 0.035, 'AbsTol', 1e-12);
verifyEqual(test_case, renewable_data.pw_power_kw(1), 0.605, 'AbsTol', 1e-12);
end

function testCustomSpanAndScaling(test_case)
config = struct();
config.data_dir = test_case.TestData.data_dir;
config.start_time = '2022-01-02 00:00';
config.day_count = 1;
config.pv_capacity_kw = 100;
config.pw_capacity_kw = 200;

renewable_data = load_res_7day(config);

verifyEqual(test_case, renewable_data.time_count, 24);
verifyEqual(test_case, renewable_data.time(1), ...
    datetime(2022, 1, 2, 0, 0, 0, 'TimeZone', 'UTC'));
verifyEqual(test_case, renewable_data.pv_power_kw, ...
    renewable_data.pv_capacity_factor * config.pv_capacity_kw, 'AbsTol', 1e-10);
verifyEqual(test_case, renewable_data.pw_power_kw, ...
    renewable_data.pw_capacity_factor * config.pw_capacity_kw, 'AbsTol', 1e-10);
end

function testRejectsNonIntegralSpan(test_case)
config = struct();
config.data_dir = test_case.TestData.data_dir;
config.time_step_h = 5;

verifyError(test_case, @() load_res_7day(config), 'load_res_7day:bad_time_grid');
end

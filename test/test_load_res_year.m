function tests = test_load_res_year
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src'));
test_case.TestData.data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
end

function testDefaultAnnualDataLocation(test_case)
renewable_data = load_res_year();

verifyEqual(test_case, renewable_data.time_count, 8760);
verifyEqual(test_case, renewable_data.time(1), ...
    datetime(2022, 1, 1, 0, 0, 0, 'TimeZone', 'UTC'));
verifyEqual(test_case, renewable_data.time(end), ...
    datetime(2022, 12, 31, 23, 0, 0, 'TimeZone', 'UTC'));
verifyEqual(test_case, renewable_data.source.pv_year, 2022);
verifyEqual(test_case, renewable_data.source.pw_year, 2022);
verifyEqual(test_case, renewable_data.source.output_year, 2022);
verifyEqual(test_case, size(renewable_data.pv_power_kw), [8760, 1]);
verifyEqual(test_case, size(renewable_data.pw_power_kw), [8760, 1]);
end

function testCustomYearAndCapacityScaling(test_case)
config = struct();
config.data_dir = test_case.TestData.data_dir;
config.year = 2025;
config.pv_capacity_kw = 100;
config.pw_capacity_kw = 200;

renewable_data = load_res_year(config);

verifyEqual(test_case, renewable_data.time_count, 8760);
verifyEqual(test_case, renewable_data.source.pv_year, 2025);
verifyEqual(test_case, renewable_data.source.pw_year, 2025);
verifyEqual(test_case, renewable_data.source.output_year, 2025);
verifyEqual(test_case, renewable_data.pv_power_kw, ...
    renewable_data.pv_capacity_factor * config.pv_capacity_kw, 'AbsTol', 1e-10);
verifyEqual(test_case, renewable_data.pw_power_kw, ...
    renewable_data.pw_capacity_factor * config.pw_capacity_kw, 'AbsTol', 1e-10);
verifyEqual(test_case, renewable_data.renewable_power_kw, ...
    renewable_data.pv_power_kw + renewable_data.pw_power_kw, 'AbsTol', 1e-10);
end

function testRejectsRemovedSevenDayOptions(test_case)
config = struct();
config.day_count = 7;

verifyError(test_case, @() load_res_year(config), ...
    'load_res_year:removed_debug_option');

config = struct();
config.start_time = datetime(2022, 1, 1, 'TimeZone', 'UTC');

verifyError(test_case, @() load_res_year(config), ...
    'load_res_year:removed_debug_option');
end

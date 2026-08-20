function tests = test_my_system
tests = functiontests(localfunctions);
end

function setupOnce(~)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src'));
addpath(fullfile(project_dir, 'src', 'params'));
addpath(fullfile(project_dir, 'src', 'results'));
end

function testAelCountAlgorithmRespectsPowerBounds(test_case)
ael_common = AEL().common;
power_kw = [0; 5000; 20000; 20000; 5000; 0];

[optimized_count, info] = algorithm(power_kw, ael_common);

verifyEqual(test_case, info.lower_bound, [0; 1; 4; 4; 1; 0]);
verifyEqual(test_case, info.upper_bound, [0; 5; 20; 20; 5; 0]);
verifyGreaterThanOrEqual(test_case, optimized_count, info.lower_bound);
verifyLessThanOrEqual(test_case, optimized_count, info.upper_bound);
verifyEqual(test_case, optimized_count, round(optimized_count));
end

function testAelCountAlgorithmRetainsOnlyFeasibleOnlineModules(test_case)
ael_common = AEL().common;
power_kw = [40000; 7000; 45000];
options = struct('future_hours', 1, 'history_days', 7, ...
    'future_weight', 0.7, 'keep_threshold', 0.5);

[optimized_count, info] = algorithm(power_kw, ael_common, options);

verifyEqual(test_case, info.lower_bound, [8; 2; 9]);
verifyEqual(test_case, info.upper_bound, [26; 7; 26]);
verifyEqual(test_case, optimized_count, [8; 7; 9]);
verifyEqual(test_case, info.startup_count, 10);
verifyEqual(test_case, info.start_event_count, 2);
end

function testAelCountAlgorithmClipsSolverToleranceAtZero(test_case)
ael_common = AEL().common;
power_kw = [-1e-5; 0; 5000];

[optimized_count, info] = algorithm(power_kw, ael_common);

verifyEqual(test_case, info.lower_bound, [0; 0; 1]);
verifyEqual(test_case, info.upper_bound, [0; 0; 5]);
verifyEqual(test_case, optimized_count, [0; 0; 1]);
end

function testAelCountAlgorithmRejectsMaterialNegativePower(test_case)
ael_common = AEL().common;

verifyError(test_case, @() algorithm(-1, ael_common), ...
    'algorithm:negative_power');
end

function testBaselineDoesNotInvokeSlidingWindowAlgorithm(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
baseline_source = fileread(fullfile(project_dir, 'src', 'baseline.m'));

verifyEmpty(test_case, regexp(baseline_source, ...
    '\<algorithm\s*\(', 'once'));
end

function testDefaultScenarioIsS2(test_case)
case_config = my_system();

verifyEqual(test_case, case_config.scenario.id, 's2');
verifyEqual(test_case, case_config.scenario.mode, 'continuous_flexible');
verifyEqual(test_case, case_config.AEL.common.capacity, 130);
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
verifyEqual(test_case, ael_parameters.detail.far_const, 96485.33212);
verifyEqual(test_case, ael_parameters.common.capacity, 130);
verifyEqual(test_case, ael_parameters.detail.stack_h2, 500);
verifyEqual(test_case, ael_parameters.common.module_h2, 1000);
verifyEqual(test_case, hb_parameters.act_h2, 6 / 34);
verifyEqual(test_case, hb_parameters.max_load, 1.00);
end

function testAelParametersUseCommonDetailSections(test_case)
ael_parameters = AEL();

verifyEqual(test_case, fieldnames(ael_parameters), {'common'; 'detail'});
verifyTrue(test_case, all(isfield(ael_parameters.common, ...
    {'capacity', 'max_power', 'min_power', 'spec_energy'})));
verifyTrue(test_case, all(isfield(ael_parameters.detail, ...
    {'far_const', 'stack_temp', 'stack_h2'})));
end

function testResultsBuilderCreatesBaselineSummary(test_case)
params = my_system('s2');
dt = 1;

sol = struct();
sol.P_AEL = [50; 60];
sol.HB_load = [0; 0];
sol.storage_H2 = [10; 10.8988; 11.97736];
sol.p_purchase = [0; 0];
sol.p_sell = [45; 140];
sol.p_curt = [0; 0];
sol.u_purchase = [0; 0];
sol.P_AEL_start = [5; 0];
sol.n_ael = [0; 2];
sol.n_ael_optimized = [1; 1];
sol.ael_count_info = struct('lower_bound', [1; 1], ...
    'upper_bound', [2; 2]);

renewable_data = struct();
renewable_data.time_count = 2;
renewable_data.time = [1; 2];

context = struct();
context.T = 2;
context.dt = dt;
context.P_total = [100; 200];
context.AEL_spec_energy = params.AEL.common.spec_energy;
context.H2_density = params.unit.h2_density;
context.NH3_rate = params.HB.nh3_output;
context.HB_power_kw = params.HB.nom_power * 1000;
context.C_curt = params.grid.curtail_penalty;
context.C_purchase = params.grid.buy_price;
context.C_sell = params.grid.sell_price;
context.ael_common = params.AEL.common;
context.N_AEL_initial = 0;

H2_prod_kg = sum(sol.P_AEL) * dt / context.AEL_spec_energy ...
    * context.H2_density;
water_cost = params.material.water_price * ...
    params.AEL.common.water_use * H2_prod_kg / params.unit.mass_scale;
objective_value = annual_fixed_cost(params).total + water_cost ...
    - params.grid.sell_price * sum(sol.p_sell) * dt;

built = feval('results', params, renewable_data, sol, objective_value, 1, ...
    struct('message', 'ok'), context);

verifyEqual(test_case, built.dispatch.P_AEL, sol.P_AEL);
verifyEqual(test_case, built.dispatch.P_AEL_start, sol.P_AEL_start);
verifyEqual(test_case, built.dispatch.N_AEL, sol.n_ael_optimized);
verifyEqual(test_case, built.dispatch.N_AEL_lower, [1; 1]);
verifyEqual(test_case, built.dispatch.N_AEL_upper, [2; 2]);
verifyEqual(test_case, built.summary.H2_prod_kg, ...
    sum(sol.P_AEL) * dt / context.AEL_spec_energy * context.H2_density, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.summary.AEL_average_online_modules, 1);
verifyEqual(test_case, built.summary.AEL_startup_count, 1);
verifyEqual(test_case, built.summary.AEL_start_energy_kwh, 5);
verifyEqual(test_case, built.optimization.mode, ...
    'single_stage_with_count_postprocess');
verifyEqual(test_case, built.check.max_AEL_lower_violation, 0);
verifyEqual(test_case, built.check.max_AEL_upper_violation, 0);
expected_water_cost = params.material.water_price * (...
    params.AEL.common.water_use * built.summary.H2_prod_kg / 1000 + ...
    params.HB.water_use * built.summary.NH3_prod_kg / 1000);
expected_catalyst_cost = params.material.cat_price * ...
    built.summary.NH3_prod_kg / 1000;
verifyEqual(test_case, built.cost.water, expected_water_cost, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.cost.catalyst, expected_catalyst_cost, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.check.max_power_residual_kw, 0, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.time, renewable_data.time);
end

function testResultsComputesCurrentAmmoniaKpisWithoutReferenceComparison(test_case)
params = my_system('s2');
dt = 1;
T = 48;
hb_load = [zeros(12, 1); ones(12, 1); 0.5 * ones(24, 1)];
nh3_rate = params.HB.nh3_output;
h2_use_kg = hb_load * nh3_rate * params.HB.lit_h2;

sol = struct();
sol.HB_load = hb_load;
sol.P_AEL = h2_use_kg * params.AEL.common.spec_energy / ...
    params.unit.h2_density;
sol.storage_H2 = zeros(T + 1, 1);
sol.p_purchase = 100 * hb_load;
sol.p_sell = zeros(T, 1);
sol.p_curt = zeros(T, 1);
sol.u_purchase = double(sol.p_purchase > 0);

renewable_data = struct('time_count', T, 'time', (1:T)');
context = struct();
context.T = T;
context.dt = dt;
context.P_total = sol.P_AEL + hb_load * params.HB.nom_power * 1000 ...
    - sol.p_purchase;
context.AEL_spec_energy = params.AEL.common.spec_energy;
context.H2_density = params.unit.h2_density;
context.NH3_rate = nh3_rate;
context.HB_power_kw = params.HB.nom_power * 1000;
context.C_curt = params.grid.curtail_penalty;
context.C_purchase = params.grid.buy_price;
context.C_sell = params.grid.sell_price;
context.ael_common = params.AEL.common;

NH3_prod_kg = sum(hb_load) * nh3_rate * dt;
H2_prod_kg = sum(h2_use_kg);
water_cost = params.material.water_price * (...
    params.AEL.common.water_use * H2_prod_kg / params.unit.mass_scale + ...
    params.HB.water_use * NH3_prod_kg / params.unit.mass_scale);
objective_value = annual_fixed_cost(params).total + water_cost + ...
    params.material.cat_price * NH3_prod_kg / params.unit.mass_scale + ...
    params.grid.buy_price * sum(sol.p_purchase) * dt - ...
    params.ammonia.price * NH3_prod_kg / params.unit.mass_scale;

command_output = evalc("built = feval('results', params, renewable_data, " + ...
    "sol, objective_value, 1, struct('message', 'ok'), context);");

expected_co2_intensity = params.environment.grid_co2 * ...
    sum(sol.p_purchase) * dt / built.summary.NH3_prod_kg;
verifyEqual(test_case, built.summary.NH3_daily_cumulative_volatility, ...
    0.25, 'AbsTol', 1e-12);
verifyEqual(test_case, built.HB.daily_volatility, [0.5; 0], ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.summary.co2_intensity, ...
    expected_co2_intensity, 'AbsTol', 1e-12);
verifySubstring(test_case, command_output, '制氨日累计波动率：25.00 %');
verifySubstring(test_case, command_output, '碳排放强度：');
verifyEmpty(test_case, regexp(command_output, '对标|文献|偏差', 'once'));
verifyFalse(test_case, isfield(built, 'zhou_audit'));
end

function testResultLcoaUsesZhouCostBreakdown(test_case)
params = my_system('s2');

result = struct();
result.summary = struct();
result.summary.NH3_prod_t_y = 1000;
result.summary.H2_prod_kg = 2000;
result.summary.purchase_kwh = 5000;
result.summary.sell_kwh = 2000;
result.dispatch = struct();
result.dispatch.P_purchase = [0; 300; 100];

economics = result_LCOA(params, result);

loan_crf = params.finance.loan_interest * ...
    (1 + params.finance.loan_interest)^params.finance.loan_term / ...
    ((1 + params.finance.loan_interest)^params.finance.loan_term - 1);
investment = ...
    params.pw.capex * params.renewable.PW_capacity + ...
    params.pv.capex * params.renewable.PV_capacity + ...
    params.AEL.common.capex * params.AEL.common.max_power + ...
    params.h2_storage.capex * params.h2_storage.capacity + ...
    params.converter.capex * params.converter.capacity * 1000 + ...
    params.transformer.capex * params.transformer.capacity * 1000 + ...
    params.HB.capex * params.HB.capacity;

expected_IN = investment * params.finance.crf;
expected_IC = investment * loan_crf;
expected_CEC = (1 - params.finance.loan_ratio) * expected_IN ...
    + params.finance.loan_ratio * expected_IC;
expected_OM = ...
    params.pw.capex * params.renewable.PW_capacity * params.pw.om_rate + ...
    params.pv.capex * params.renewable.PV_capacity * params.pv.om_rate + ...
    params.AEL.common.capex * params.AEL.common.max_power * params.AEL.common.om_rate + ...
    params.h2_storage.capex * params.h2_storage.capacity * params.h2_storage.om_rate + ...
    params.converter.capex * params.converter.capacity * 1000 * params.converter.om_rate + ...
    params.transformer.capex * params.transformer.capacity * 1000 * params.transformer.om_rate + ...
    params.HB.capex * params.HB.capacity * params.HB.om_rate;
expected_water = params.material.water_price * ...
    (params.AEL.common.water_use * 2 + params.HB.water_use * 1000);
expected_RM = expected_water + params.material.cat_price * 1000 ...
    + params.grid.buy_price * 5000 ...
    + params.grid.cap_fee * params.grid.contract_kw * 12;
expected_LC = params.labor.fte * params.labor.salary;
expected_INC = params.ammonia.price * 1000 ...
    + params.grid.sell_price * 2000;
expected_total_cost = expected_CEC + expected_OM + expected_LC + expected_RM;
expected_lcoa = ...
    (expected_total_cost - params.grid.sell_price * 2000) / 1000;

verifyEqual(test_case, economics.INC.total, expected_INC, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.IN.total, expected_IN, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.IC.total, expected_IC, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.CEC.total, expected_CEC, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.OM.total, expected_OM, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.LC.total, expected_LC, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.RM.total, expected_RM, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.total_cost, expected_total_cost, ...
    'AbsTol', 1e-8);
verifyEqual(test_case, economics.net_profit, ...
    expected_INC - expected_total_cost, 'AbsTol', 1e-8);
verifyEqual(test_case, economics.lcoa, expected_lcoa, 'AbsTol', 1e-8);
end

function testAnnualObjectiveAccountingMatchesReportedNetProfit(test_case)
params = my_system('s2');
fixed = annual_fixed_cost(params);

result = struct();
result.summary = struct();
result.summary.NH3_prod_t_y = 1000;
result.summary.H2_prod_kg = 2000;
result.summary.purchase_kwh = 5000;
result.summary.sell_kwh = 2000;
result.summary.curtail_kwh = 300;
result.dispatch = struct('P_purchase', [0; 300; 100]);

economics = result_LCOA(params, result);
variable_cost = economics.RM.water + economics.RM.catalyst + ...
    economics.RM.grid_purchase + economics.RM.curtailment;
objective_value = fixed.total + variable_cost - economics.INC.total;

verifyEqual(test_case, fixed.total, economics.CEC.total + ...
    economics.OM.total + economics.LC.total + ...
    economics.RM.grid_capacity, 'AbsTol', 1e-8);
verifyEqual(test_case, -objective_value, economics.net_profit, ...
    'AbsTol', 1e-8);
end

function testBaselineObjectiveIncludesAnnualAccounting(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
baseline_source = fileread(fullfile(project_dir, 'src', 'baseline.m'));

verifyNotEmpty(test_case, regexp(baseline_source, ...
    'annual_fixed_cost\s*\(', 'once'));
verifyNotEmpty(test_case, regexp(baseline_source, ...
    'prob\.Objective\s*=\s*obj_formula\s*\+\s*annual_fixed_cost_expr', ...
    'once'));
end

function testReferenceS2EconomicsMatchesZhouLcoa(test_case)
params = my_system('s2');

ael_kwh = params.ref.ael_hours * params.AEL.common.max_power;
hb_kwh = params.ref.nh3_output * params.HB.spec_energy * 1000;
renewable_kwh = (ael_kwh + hb_kwh) / ...
    (1 + params.ref.grid_buy - params.ref.grid_sell - params.ref.curtailment);

result = struct();
result.summary = struct();
result.summary.NH3_prod_t_y = params.ref.nh3_output;
result.summary.H2_prod_kg = ...
    ael_kwh / params.AEL.common.spec_energy * params.unit.h2_density;
result.summary.purchase_kwh = renewable_kwh * params.ref.grid_buy;
result.summary.sell_kwh = renewable_kwh * params.ref.grid_sell;
result.dispatch = struct();
result.dispatch.P_purchase = zeros(params.time.hour_year, 1);

economics = result_LCOA(params, result);

verifyEqual(test_case, economics.RM.water, 772234.482432, 'AbsTol', 1e-6);
verifyEqual(test_case, economics.RM.catalyst, 1281600, 'AbsTol', 1e-6);
verifyEqual(test_case, economics.RM.grid_capacity, 1386000, 'AbsTol', 1e-6);
verifyEqual(test_case, economics.LC.total, 3000000, 'AbsTol', 1e-6);
verifyEqual(test_case, economics.lcoa, 464.469881935871, 'AbsTol', 1e-9);
verifyEqual(test_case, economics.unit_cost.labor, ...
    economics.LC.total / params.ref.nh3_output, 'AbsTol', 1e-12);
verifyEqual(test_case, economics.unit_cost.water, ...
    economics.RM.water / params.ref.nh3_output, 'AbsTol', 1e-12);
verifyEqual(test_case, economics.unit_cost.catalyst, ...
    economics.RM.catalyst / params.ref.nh3_output, 'AbsTol', 1e-12);
verifyEqual(test_case, economics.unit_cost.grid_capacity, ...
    economics.RM.grid_capacity / params.ref.nh3_output, 'AbsTol', 1e-12);
verifyEqual(test_case, economics.unit_cost.lcoa, economics.lcoa, 'AbsTol', 1e-12);
verifyEqual(test_case, economics.net_profit_gap, ...
    economics.net_profit - params.ref.net_profit, 'AbsTol', 1e-8);
verifyLessThanOrEqual(test_case, abs(economics.lcoa - params.ref.lcoa), 0.5);
verifyLessThanOrEqual(test_case, ...
    abs(economics.net_profit - 6.65e6), 0.1e6);
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
verifyEqual(test_case, my_system('s2').AEL.common.capex, 285);
verifyEqual(test_case, my_system('s2').AEL.common.om_rate, 0.02);
verifyEqual(test_case, s2_config.h2_storage.capex, 50);
verifyEqual(test_case, s2_config.h2_storage.module_cap, 22000);
verifyEqual(test_case, s2_config.h2_storage.temperature, 30);
verifyEqual(test_case, s2_config.ammonia.price, 557);
verifyEqual(test_case, s2_config.grid.sell_price, 0.041);
verifyEqual(test_case, s2_config.grid.buy_price, 0.053);
verifyEqual(test_case, s2_config.grid.cap_fee, 3.85);
verifyEqual(test_case, s2_config.grid.contract_kw, 30e3);
verifyEqual(test_case, s2_config.grid.curtail_limit, 0.10);
verifyEqual(test_case, s2_config.grid.max_sell, 0.20);
verifyEqual(test_case, s2_config.labor.fte, 200);
verifyEqual(test_case, s2_config.labor.salary, 15000);
verifyEqual(test_case, s2_config.environment.grid_co2, 0.5703);
verifyEqual(test_case, s2_config.environment.co2_limit, 0.3);

verifyEqual(test_case, s1_config.h2_storage.capacity, 17.6e4);
verifyEqual(test_case, s2_config.h2_storage.capacity, 11.0e4);
verifyEqual(test_case, s3_config.h2_storage.capacity, 13.2e4);
verifyEqual(test_case, s2_config.transformer.capacity, 200);
verifyEqual(test_case, s2_config.ref.nh3_output, 7.12e4);
verifyEqual(test_case, s2_config.ref.lcoa, 464);
verifyEqual(test_case, s2_config.ref.net_profit, 6.65e6);
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
verifyEqual(test_case, case_config.AEL.common.max_power, ...
    case_config.AEL.common.capacity * case_config.unit.power_scale);
verifyEqual(test_case, case_config.AEL.common.mass_spec_energy, ...
    case_config.AEL.common.spec_energy / case_config.unit.h2_density, ...
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
verifyEqual(test_case, s3_config.AEL.common.startup, true);
verifyEqual(test_case, s3_config.transformer.capacity, 189);
end

function testDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.renewable.total_capacity, ...
    case_config.renewable.PV_capacity + case_config.renewable.PW_capacity);
verifyEqual(test_case, case_config.AEL.common.max_power, 130000);
verifyEqual(test_case, case_config.AEL.common.module_num, 26);
verifyEqual(test_case, case_config.AEL.detail.stack_num, 52);
verifyEqual(test_case, case_config.AEL.detail.stack_per_module, 2);
verifyEqual(test_case, case_config.h2_storage.mass, 9886.8, 'AbsTol', 1e-9);
verifyEqual(test_case, case_config.converter.capacity, ...
    case_config.AEL.common.capacity);
end

function testZhouEnergyUnitAndDerivedValues(test_case)
case_config = my_system('s2');

verifyEqual(test_case, case_config.AEL.common.spec_energy, 5.0);
verifyEqual(test_case, case_config.AEL.common.mass_spec_energy, ...
    55.63, 'AbsTol', 5e-3);
verifyEqual(test_case, case_config.AEL.common.h2_output, 26000);
verifyEqual(test_case, case_config.AEL.common.h2_mass, ...
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

verifyEqual(test_case, case_config.AEL.detail.stack_temp, 90.0);
verifyEqual(test_case, case_config.AEL.detail.sep_temp, 90.0);
verifyEqual(test_case, case_config.AEL.detail.pid_i_set, 89.57);
verifyEqual(test_case, case_config.AEL.detail.mpc_set, 93.23);
verifyEqual(test_case, case_config.AEL.common.startup_elec, 0.15);
end

function testQiAelVoltageHeatAndHydrogenEquations(test_case)
ael_parameters = AEL();
model_output = qi_ael_model(2000, 0, ael_parameters.detail);

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

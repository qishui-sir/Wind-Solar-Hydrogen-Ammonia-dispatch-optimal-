function tests = test_system
%TEST_SYSTEM Consolidated parameter, accounting and model-structure regressions.
% No annual optimization or research experiment is launched by this suite.
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src');
test_case.TestData.old_path = path;
addpath(src_dir, fullfile(src_dir, 'params'), fullfile(src_dir, 'results'));
end

function teardownOnce(test_case)
path(test_case.TestData.old_path);
end

function testAelStartupElectricityIsPhysical(test_case)
% Startup electricity is a physical load. S2 has it disabled by default; S3 and
% the main.m baseline enable it at the Zhou value.
s2 = my_system('s2');
s3 = my_system('s3');
verifyFalse(test_case, s2.AEL.common.startup);
verifyTrue(test_case, s3.AEL.common.startup);
verifyEqual(test_case, s3.AEL.common.startup_elec, 0.15);
end

function testNoArtificialStartupPenaltyParameter(test_case)
% The removed artificial penalty parameter must not come back.
s3 = my_system('s3');
verifyFalse(test_case, isfield(s3.AEL.common, 'startup_penalty'));
end

function testDefaultScenarioIsS2(test_case)
case_config = my_system();

verifyEqual(test_case, case_config.scenario.id, 's2');
verifyEqual(test_case, case_config.scenario.mode, 'continuous_flexible');
verifyEqual(test_case, case_config.AEL.common.capacity, 130);
verifyEqual(test_case, case_config.h2_storage.capacity, 11.0e4);
verifyEqual(test_case, case_config.ref.lcoa, 464);
verifyEqual(test_case, case_config.grid.curtail_penalty, 0);
verifyEqual(test_case, case_config.grid.curtail_limit, 0.10);
end

function testH2StoragePressureDefinesPhysicalBounds(test_case)
case_config = my_system('s2');
storage = case_config.h2_storage;

verifyEqual(test_case, storage.pressure_basis, 'absolute');
verifyEqual(test_case, storage.min_abs_soc, 1 / 3, 'AbsTol', 1e-12);
verifyEqual(test_case, storage.min_capacity, 11.0e4 / 3, ...
    'AbsTol', 1e-9);
verifyEqual(test_case, storage.work_capacity, 2 * 11.0e4 / 3, ...
    'AbsTol', 1e-9);
verifyEqual(test_case, storage.min_mass, 3295.6, 'AbsTol', 1e-9);
verifyEqual(test_case, storage.work_mass, 6591.2, 'AbsTol', 1e-9);
verifyEqual(test_case, storage.initial_mass, 6591.2, 'AbsTol', 1e-9);
end

function testH2StorageGaugePressureUsesAbsolutePressureRatio(test_case)
storage = struct('capacity', 22000, 'min_pressure', 0.5, ...
    'max_pressure', 1.5, 'pressure_basis', 'gauge', ...
    'atm_pressure', 0.101325, 'init_work_soc', 0.5);

limits = h2_storage_limits(storage, 0.08988);
expected_fraction = (0.5 + 0.101325) / (1.5 + 0.101325);

verifyEqual(test_case, limits.min_abs_soc, expected_fraction, ...
    'AbsTol', 1e-12);
verifyEqual(test_case, limits.min_capacity, 22000 * expected_fraction, ...
    'AbsTol', 1e-9);
verifyEqual(test_case, limits.initial_mass, ...
    (limits.min_capacity + 0.5 * limits.work_capacity) * 0.08988, ...
    'AbsTol', 1e-9);
end

function testAelParametersUseCommonDetailSections(test_case)
ael_parameters = AEL();

verifyEqual(test_case, fieldnames(ael_parameters), {'common'; 'detail'});
verifyTrue(test_case, all(isfield(ael_parameters.common, ...
    {'capacity', 'max_power', 'min_power', 'spec_energy'})));
verifyTrue(test_case, all(isfield(ael_parameters.detail, ...
    {'far_const', 'stack_temp', 'stack_h2'})));
end

function testAnnualCostBreakdown(test_case)
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

function testRejectsUnknownScenario(test_case)
verifyError(test_case, @() my_system('s4'), 'my_system:bad_case');
end

function testResultsComputesCurrentAmmoniaKpisWithoutReferenceComparison(test_case)
% Synthetic postprocessing inputs only; this is not a feasible dispatch witness.
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
    params.grid.buy_price * sum(sol.p_purchase) * dt;

evalc("built = feval('results', params, renewable_data, " + ...
    "sol, objective_value, 1, struct('message', 'ok'), context);");

expected_co2_intensity = params.environment.grid_co2 * ...
    sum(sol.p_purchase) * dt / built.summary.NH3_prod_kg;
verifyEqual(test_case, built.summary.NH3_daily_cumulative_volatility, ...
    0.25, 'AbsTol', 1e-12);
verifyEqual(test_case, built.HB.daily_volatility, [0.5; 0], ...
    'AbsTol', 1e-12);
verifyEqual(test_case, built.summary.co2_intensity, ...
    expected_co2_intensity, 'AbsTol', 1e-12);
verifyFalse(test_case, isfield(built, 'zhou_audit'));
end

function test_start_stop_counts_are_implicitly_integer(test_case)
T = 24;
data = struct('time_count', T, 'time', (1:T)', ...
    'pv_power_kw', zeros(T, 1), 'pw_power_kw', 60000 * ones(T, 1));
params = my_system('s2');
audit = baseline(params, data, @audit_integrality);
verifyFalse(test_case, audit.su_is_declared_integer);
verifyFalse(test_case, audit.sd_is_declared_integer);
verifyTrue(test_case, audit.online_is_declared_integer);
verifyTrue(test_case, audit.direction_is_declared_integer);
end

function audit = audit_integrality(model)
% Inspect the original integer columns without invoking a solver.
solver_model = prob2struct(model.problem, 'Solver', 'intlinprog');
indices = varindex(model.problem);
audit = struct();
audit.su_is_declared_integer = ...
    any(ismember(indices.SU_AEL(:), solver_model.intcon));
audit.sd_is_declared_integer = ...
    any(ismember(indices.SD_AEL(:), solver_model.intcon));
audit.online_is_declared_integer = ...
    all(ismember(indices.n_ael(:), solver_model.intcon));
audit.direction_is_declared_integer = ...
    all(ismember(indices.I_AEL_up(:), solver_model.intcon));
end


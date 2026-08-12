function results = baseline_test(case_id, opts)
%BASELINE Deterministic 7-day Zhou S2 baseline dispatch model.
%   results = baseline() solves the S2 continuous flexible baseline.
%   results = baseline('s2', opts) allows selected options.
%
%   This file intentionally uses Zhou's fixed AEL energy consumption
%   5.0 kWh/Nm3-H2. It does not call Qi-AEL voltage, temperature,
%   efficiency, degradation, Copula, or robust optimization models.

if nargin < 1 || isempty(case_id)
    case_id = 's2';
end

if nargin < 2
    opts = struct();
end

cfg = case_cfg_7day(case_id);
opts = set_default_opts(opts, cfg);
data = load_res_7day(cfg.res);

model = build_baseline_model(cfg, data, opts);
[x, fval, exitflag, output] = solve_baseline_model(model, opts);
results = collect_baseline_results(x, fval, exitflag, output, model);

if opts.save_result
    results.output = save_baseline_results(results, opts);
end

print_baseline_summary(results);
end

function opts = set_default_opts(opts, cfg)
opts = set_missing(opts, 'alpha_nh3', 1.0);
opts = set_missing(opts, 'h2_initial_soc_fraction', 0.50);
opts = set_missing(opts, 'hb_initial_load_fraction', cfg.hb.ld_min);
opts = set_missing(opts, 'enforce_co2_limit', false);
opts = set_missing(opts, 'enforce_sell_limit', true);
opts = set_missing(opts, 'enforce_curtailment_limit', false);
opts = set_missing(opts, 'use_transformer_load_fraction', false);
opts = set_missing(opts, 'curtailment_penalty_usd_per_kwh', 1.0e-4);
opts = set_missing(opts, 'h2_short_penalty_usd_per_kg', 50);
opts = set_missing(opts, 'nh3_short_penalty_usd_per_kg', 10);
opts = set_missing(opts, 'save_result', true);
opts = set_missing(opts, 'output_dir', fullfile(pwd, 'results', 'zhou_s2_baseline'));
opts = set_missing(opts, 'solver_display', 'off');

if opts.alpha_nh3 < cfg.hb.ld_min || opts.alpha_nh3 > cfg.hb.ld_max
    error('baseline:bad_alpha_nh3', ...
        'opts.alpha_nh3 must be between HB min and max load fractions.');
end

if opts.h2_initial_soc_fraction < 0 || opts.h2_initial_soc_fraction > 1
    error('baseline:bad_soc', ...
        'opts.h2_initial_soc_fraction must be in [0, 1].');
end

if opts.hb_initial_load_fraction < cfg.hb.ld_min || ...
        opts.hb_initial_load_fraction > cfg.hb.ld_max
    error('baseline:bad_hb_initial_load', ...
        'opts.hb_initial_load_fraction must satisfy HB load bounds.');
end
end

function s = set_missing(s, field_name, value)
if ~isfield(s, field_name) || isempty(s.(field_name))
    s.(field_name) = value;
end
end

function model = build_baseline_model(cfg, data, opts)
const = build_constants(cfg, data, opts);
idx = build_index(data.t_num);

n_var = idx.n_var;
lb = zeros(n_var, 1);
ub = inf(n_var, 1);

ub(idx.p_ael_kw) = const.p_ael_max_kw;
lb(idx.hb_load) = const.hb_load_min;
ub(idx.hb_load) = const.hb_load_max;
ub(idx.s_h2_kg) = const.h2_storage_cap_kg;
ub(idx.p_buy_kw) = const.p_buy_max_kw;
ub(idx.p_sell_kw) = const.p_sell_max_kw;
ub(idx.p_curt_kw) = data.p_ren_kw;
ub(idx.u_buy) = 1;

f = build_objective(idx, const, opts);
[a_eq, b_eq] = build_equalities(idx, const, data);
[a_ineq, b_ineq] = build_inequalities(idx, const, data, opts);

model.cfg = cfg;
model.data = data;
model.opts = opts;
model.const = const;
model.idx = idx;
model.f = f;
model.a_ineq = a_ineq;
model.b_ineq = b_ineq;
model.a_eq = a_eq;
model.b_eq = b_eq;
model.lb = lb;
model.ub = ub;
model.intcon = idx.u_buy;
end

function const = build_constants(cfg, data, opts)
const.dt_h = data.dt_h;
const.t_num = data.t_num;

const.p_ael_max_kw = cfg.ael.p_max_kw;
const.ael_h2_kg_per_kwh = cfg.u.h2_kg_nm3 / cfg.ael.sp_kwh_nm3;
const.ael_h2_kg_per_kw_step = const.ael_h2_kg_per_kwh * const.dt_h;

const.h2_storage_cap_kg = cfg.hst.cap_kg;
const.h2_initial_kg = opts.h2_initial_soc_fraction * cfg.hst.cap_kg;

const.hb_load_min = cfg.hb.ld_min;
const.hb_load_max = cfg.hb.ld_max;
const.hb_ramp_per_step = cfg.hb.ramp_rt * const.dt_h;
const.hb_initial_load = opts.hb_initial_load_fraction;
const.nh3_kg_per_load_step = cfg.hb.cap_kg_h * const.dt_h;
const.h2_hb_kg_per_load_step = ...
    const.nh3_kg_per_load_step * (6 / 34);
const.n2_hb_kg_per_load_step = ...
    const.nh3_kg_per_load_step * (28 / 34);
const.p_hb_kw_per_load = cfg.hb.p_nom_mw * cfg.u.mw_kw;

const.nh3_target_kg = ...
    opts.alpha_nh3 * const.nh3_kg_per_load_step * data.t_num;

const.tr_cap_kw = cfg.tr.cap_mw * cfg.u.mw_kw;
if opts.use_transformer_load_fraction
    const.grid_limit_kw = const.tr_cap_kw * cfg.tr.ld_max;
else
    const.grid_limit_kw = const.tr_cap_kw;
end

const.grid_buy_usd_per_kwh = cfg.grid.buy_kwh;
const.grid_sell_usd_per_kwh = cfg.grid.sell_kwh;
const.p_buy_max_kw = const.grid_limit_kw * double(cfg.grid.buy_on);
const.p_sell_max_kw = const.grid_limit_kw * double(cfg.grid.sell_on);
const.grid_co2_kg_per_kwh = cfg.env.co2_grid;
const.co2_limit_kg_per_kg_nh3 = cfg.env.co2_lim;
const.sell_energy_limit_kwh = ...
    cfg.grid.sell_rt * sum(data.p_ren_kw) * const.dt_h;
const.curtail_energy_limit_kwh = ...
    cfg.grid.cur_rt * sum(data.p_ren_kw) * const.dt_h;

const.water_price_usd_per_ton = cfg.mat.h2o_usd_t;
const.ael_water_ton_per_kg_h2 = cfg.ael.h2o_t_t / cfg.u.kg_t;
const.hb_water_ton_per_kg_nh3 = cfg.hb.h2o_t_t / cfg.u.kg_t;
end

function idx = build_index(t_num)
next_id = 1;
[idx.p_ael_kw, next_id] = take_index(next_id, t_num);
[idx.hb_load, next_id] = take_index(next_id, t_num);
[idx.s_h2_kg, next_id] = take_index(next_id, t_num + 1);
[idx.p_buy_kw, next_id] = take_index(next_id, t_num);
[idx.p_sell_kw, next_id] = take_index(next_id, t_num);
[idx.p_curt_kw, next_id] = take_index(next_id, t_num);
[idx.u_buy, next_id] = take_index(next_id, t_num);
[idx.h2_short_kg, next_id] = take_index(next_id, t_num);
[idx.nh3_short_kg, next_id] = take_index(next_id, 1);
idx.n_var = next_id - 1;
end

function [idx_range, next_id] = take_index(next_id, count)
idx_range = next_id:(next_id + count - 1);
next_id = next_id + count;
end

function f = build_objective(idx, const, opts)
f = zeros(idx.n_var, 1);

f(idx.p_buy_kw) = const.grid_buy_usd_per_kwh * const.dt_h;
f(idx.p_sell_kw) = -const.grid_sell_usd_per_kwh * const.dt_h;
f(idx.p_curt_kw) = opts.curtailment_penalty_usd_per_kwh * const.dt_h;
f(idx.h2_short_kg) = opts.h2_short_penalty_usd_per_kg;
f(idx.nh3_short_kg) = opts.nh3_short_penalty_usd_per_kg;

ael_water_usd_per_kw = ...
    const.ael_h2_kg_per_kw_step * ...
    const.ael_water_ton_per_kg_h2 * ...
    const.water_price_usd_per_ton;
hb_water_usd_per_load = ...
    const.nh3_kg_per_load_step * ...
    const.hb_water_ton_per_kg_nh3 * ...
    const.water_price_usd_per_ton;

f(idx.p_ael_kw) = f(idx.p_ael_kw) + ael_water_usd_per_kw;
f(idx.hb_load) = f(idx.hb_load) + hb_water_usd_per_load;
end

function [a_eq, b_eq] = build_equalities(idx, const, data)
t_num = const.t_num;
n_var = idx.n_var;

row_num = t_num + t_num + 1;
a_eq = sparse(row_num, n_var);
b_eq = zeros(row_num, 1);

row = 0;

for t = 1:t_num
    row = row + 1;
    a_eq(row, idx.p_ael_kw(t)) = 1;
    a_eq(row, idx.hb_load(t)) = const.p_hb_kw_per_load;
    a_eq(row, idx.p_sell_kw(t)) = 1;
    a_eq(row, idx.p_curt_kw(t)) = 1;
    a_eq(row, idx.p_buy_kw(t)) = -1;
    b_eq(row) = data.p_ren_kw(t);
end

for t = 1:t_num
    row = row + 1;
    a_eq(row, idx.s_h2_kg(t + 1)) = 1;
    a_eq(row, idx.s_h2_kg(t)) = -1;
    a_eq(row, idx.p_ael_kw(t)) = -const.ael_h2_kg_per_kw_step;
    a_eq(row, idx.h2_short_kg(t)) = -1;
    a_eq(row, idx.hb_load(t)) = const.h2_hb_kg_per_load_step;
end

row = row + 1;
a_eq(row, idx.s_h2_kg(1)) = 1;
b_eq(row) = const.h2_initial_kg;
end

function [a_ineq, b_ineq] = build_inequalities(idx, const, data, opts)
t_num = const.t_num;
n_var = idx.n_var;

row_max = 4 * t_num + 8;
a_ineq = sparse(row_max, n_var);
b_ineq = zeros(row_max, 1);
row = 0;

for t = 1:t_num
    row = row + 1;
    a_ineq(row, idx.p_buy_kw(t)) = 1;
    a_ineq(row, idx.u_buy(t)) = -const.grid_limit_kw;

    row = row + 1;
    a_ineq(row, idx.p_sell_kw(t)) = 1;
    a_ineq(row, idx.u_buy(t)) = const.grid_limit_kw;
    b_ineq(row) = const.grid_limit_kw;
end

for t = 1:t_num
    row = row + 1;
    a_ineq(row, idx.hb_load(t)) = 1;
    if t == 1
        b_ineq(row) = const.hb_initial_load + const.hb_ramp_per_step;
    else
        a_ineq(row, idx.hb_load(t - 1)) = -1;
        b_ineq(row) = const.hb_ramp_per_step;
    end

    row = row + 1;
    a_ineq(row, idx.hb_load(t)) = -1;
    if t == 1
        b_ineq(row) = const.hb_ramp_per_step - const.hb_initial_load;
    else
        a_ineq(row, idx.hb_load(t - 1)) = 1;
        b_ineq(row) = const.hb_ramp_per_step;
    end
end

row = row + 1;
a_ineq(row, idx.s_h2_kg(end)) = -1;
b_ineq(row) = -const.h2_initial_kg;

row = row + 1;
a_ineq(row, idx.hb_load) = -const.nh3_kg_per_load_step;
a_ineq(row, idx.nh3_short_kg) = -1;
b_ineq(row) = -const.nh3_target_kg;

if opts.enforce_sell_limit
    row = row + 1;
    a_ineq(row, idx.p_sell_kw) = const.dt_h;
    b_ineq(row) = const.sell_energy_limit_kwh;
end

if opts.enforce_curtailment_limit
    row = row + 1;
    a_ineq(row, idx.p_curt_kw) = const.dt_h;
    b_ineq(row) = const.curtail_energy_limit_kwh;
end

if opts.enforce_co2_limit
    row = row + 1;
    a_ineq(row, idx.p_buy_kw) = const.grid_co2_kg_per_kwh * const.dt_h;
    a_ineq(row, idx.hb_load) = ...
        -const.co2_limit_kg_per_kg_nh3 * const.nh3_kg_per_load_step;
    b_ineq(row) = 0;
end

a_ineq = a_ineq(1:row, :);
b_ineq = b_ineq(1:row);
end

function [x, fval, exitflag, output] = solve_baseline_model(model, opts)
if exist('intlinprog', 'file') ~= 2
    error('baseline:no_intlinprog', ...
        ['intlinprog is required for the buy/sell binary variable. ', ...
        'Install or enable MATLAB Optimization Toolbox.']);
end

solver_options = optimoptions('intlinprog', 'Display', opts.solver_display);

[x, fval, exitflag, output] = intlinprog( ...
    model.f, model.intcon, ...
    model.a_ineq, model.b_ineq, ...
    model.a_eq, model.b_eq, ...
    model.lb, model.ub, ...
    solver_options);

if isempty(x)
    error('baseline:no_solution', ...
        'intlinprog returned no solution. Exitflag: %d.', exitflag);
end
end

function results = collect_baseline_results(x, fval, exitflag, output, model)
idx = model.idx;
const = model.const;
data = model.data;
cfg = model.cfg;

p_ael_kw = x(idx.p_ael_kw);
hb_load = x(idx.hb_load);
s_h2_kg = x(idx.s_h2_kg);
p_buy_kw = x(idx.p_buy_kw);
p_sell_kw = x(idx.p_sell_kw);
p_curt_kw = x(idx.p_curt_kw);
u_buy = round(x(idx.u_buy));
h2_short_kg = x(idx.h2_short_kg);
nh3_short_kg = x(idx.nh3_short_kg);

p_ael_kw = p_ael_kw(:);
hb_load = hb_load(:);
s_h2_kg = s_h2_kg(:);
p_buy_kw = p_buy_kw(:);
p_sell_kw = p_sell_kw(:);
p_curt_kw = p_curt_kw(:);
u_buy = u_buy(:);
h2_short_kg = h2_short_kg(:);

p_hb_kw = hb_load * const.p_hb_kw_per_load;
h2_ael_kg = p_ael_kw * const.ael_h2_kg_per_kw_step;
nh3_kg = hb_load * const.nh3_kg_per_load_step;
h2_hb_kg = hb_load * const.h2_hb_kg_per_load_step;
n2_hb_kg = hb_load * const.n2_hb_kg_per_load_step;

power_residual_kw = ...
    data.p_ren_kw + p_buy_kw - ...
    p_ael_kw - p_hb_kw - p_sell_kw - p_curt_kw;
storage_residual_kg = ...
    diff(s_h2_kg) - h2_ael_kg - h2_short_kg + h2_hb_kg;

cost = build_cost_breakdown( ...
    p_ael_kw, hb_load, p_buy_kw, p_sell_kw, p_curt_kw, ...
    h2_short_kg, nh3_short_kg, const, model.opts);

dispatch = table();
dispatch.time = data.tm;
dispatch.p_pv_kw = data.p_pv_kw;
dispatch.p_wd_kw = data.p_wd_kw;
dispatch.p_ren_kw = data.p_ren_kw;
dispatch.p_ael_kw = p_ael_kw;
dispatch.p_hb_kw = p_hb_kw;
dispatch.hb_load = hb_load;
dispatch.h2_ael_kg = h2_ael_kg;
dispatch.h2_hb_kg = h2_hb_kg;
dispatch.n2_hb_kg = n2_hb_kg;
dispatch.nh3_kg = nh3_kg;
dispatch.s_h2_start_kg = s_h2_kg(1:end - 1);
dispatch.s_h2_end_kg = s_h2_kg(2:end);
dispatch.p_buy_kw = p_buy_kw;
dispatch.p_sell_kw = p_sell_kw;
dispatch.p_curt_kw = p_curt_kw;
dispatch.u_buy = u_buy;
dispatch.h2_short_kg = h2_short_kg;
dispatch.power_residual_kw = power_residual_kw;
dispatch.storage_residual_kg = storage_residual_kg;

kpi = build_kpi(dispatch, s_h2_kg, cost, fval, exitflag, cfg, const, ...
    nh3_short_kg);

results.cfg = cfg;
results.opts = model.opts;
results.const = const;
results.dispatch = dispatch;
results.s_h2_kg = s_h2_kg;
results.cost = cost;
results.kpi = kpi;
results.solver.fval = fval;
results.solver.exitflag = exitflag;
results.solver.output = output;
end

function cost = build_cost_breakdown( ...
    p_ael_kw, hb_load, p_buy_kw, p_sell_kw, p_curt_kw, ...
    h2_short_kg, nh3_short_kg, const, opts)

cost.grid_buy_usd = ...
    sum(p_buy_kw) * const.dt_h * const.grid_buy_usd_per_kwh;
cost.grid_sell_usd = ...
    sum(p_sell_kw) * const.dt_h * const.grid_sell_usd_per_kwh;
cost.curtailment_usd = ...
    sum(p_curt_kw) * const.dt_h * opts.curtailment_penalty_usd_per_kwh;
cost.h2_short_usd = ...
    sum(h2_short_kg) * opts.h2_short_penalty_usd_per_kg;
cost.nh3_short_usd = ...
    nh3_short_kg * opts.nh3_short_penalty_usd_per_kg;

h2_ael_kg = p_ael_kw * const.ael_h2_kg_per_kw_step;
nh3_kg = hb_load * const.nh3_kg_per_load_step;
cost.ael_water_usd = ...
    sum(h2_ael_kg) * const.ael_water_ton_per_kg_h2 * ...
    const.water_price_usd_per_ton;
cost.hb_water_usd = ...
    sum(nh3_kg) * const.hb_water_ton_per_kg_nh3 * ...
    const.water_price_usd_per_ton;

cost.total_usd = ...
    cost.grid_buy_usd - cost.grid_sell_usd + ...
    cost.curtailment_usd + cost.h2_short_usd + ...
    cost.nh3_short_usd + cost.ael_water_usd + cost.hb_water_usd;
end

function kpi = build_kpi(dispatch, s_h2_kg, cost, fval, exitflag, cfg, ...
    const, nh3_short_kg)

ren_energy_kwh = sum(dispatch.p_ren_kw) * const.dt_h;
buy_energy_kwh = sum(dispatch.p_buy_kw) * const.dt_h;
sell_energy_kwh = sum(dispatch.p_sell_kw) * const.dt_h;
curtail_energy_kwh = sum(dispatch.p_curt_kw) * const.dt_h;
ael_energy_kwh = sum(dispatch.p_ael_kw) * const.dt_h;
hb_energy_kwh = sum(dispatch.p_hb_kw) * const.dt_h;

nh3_total_kg = sum(dispatch.nh3_kg);
h2_short_total_kg = sum(dispatch.h2_short_kg);

kpi.exitflag = exitflag;
kpi.objective_usd = fval;
kpi.cost_total_usd = cost.total_usd;
kpi.nh3_total_kg = nh3_total_kg;
kpi.nh3_target_kg = const.nh3_target_kg;
kpi.nh3_short_kg = nh3_short_kg;
kpi.h2_short_total_kg = h2_short_total_kg;
kpi.unit_operating_cost_usd_per_ton_nh3 = ...
    cost.total_usd / max(nh3_total_kg / cfg.u.kg_t, eps);

kpi.ren_energy_kwh = ren_energy_kwh;
kpi.buy_energy_kwh = buy_energy_kwh;
kpi.sell_energy_kwh = sell_energy_kwh;
kpi.curtail_energy_kwh = curtail_energy_kwh;
kpi.ael_energy_kwh = ael_energy_kwh;
kpi.hb_energy_kwh = hb_energy_kwh;

kpi.renewable_utilization_fraction = ...
    (ren_energy_kwh - curtail_energy_kwh) / max(ren_energy_kwh, eps);
kpi.curtailment_fraction = curtail_energy_kwh / max(ren_energy_kwh, eps);
kpi.grid_buy_fraction_of_load = ...
    buy_energy_kwh / max(ael_energy_kwh + hb_energy_kwh, eps);
kpi.grid_sell_fraction_of_renewable = ...
    sell_energy_kwh / max(ren_energy_kwh, eps);
kpi.ael_utilization_hour = ael_energy_kwh / const.p_ael_max_kw;
kpi.hb_average_load = mean(dispatch.hb_load);
kpi.h2_soc_initial_kg = s_h2_kg(1);
kpi.h2_soc_final_kg = s_h2_kg(end);
kpi.h2_soc_min_kg = min(s_h2_kg);
kpi.h2_soc_max_kg = max(s_h2_kg);
kpi.co2_intensity_kg_per_kg_nh3 = ...
    buy_energy_kwh * const.grid_co2_kg_per_kwh / max(nh3_total_kg, eps);
kpi.max_power_residual_kw = max(abs(dispatch.power_residual_kw));
kpi.max_storage_residual_kg = max(abs(dispatch.storage_residual_kg));
kpi.buy_sell_overlap_kwh = ...
    sum(min(dispatch.p_buy_kw, dispatch.p_sell_kw)) * const.dt_h;
end

function output = save_baseline_results(results, opts)
if ~isfolder(opts.output_dir)
    mkdir(opts.output_dir);
end

dispatch_path = fullfile(opts.output_dir, 'baseline_dispatch.csv');
kpi_path = fullfile(opts.output_dir, 'baseline_kpi.mat');

writetable(results.dispatch, dispatch_path);
kpi = results.kpi; %#ok<NASGU>
cost = results.cost; %#ok<NASGU>
const = results.const; %#ok<NASGU>
save(kpi_path, 'kpi', 'cost', 'const');

output.dispatch_path = dispatch_path;
output.kpi_path = kpi_path;
end

function print_baseline_summary(results)
kpi = results.kpi;

fprintf('\nZhou S2 deterministic 7-day baseline\n');
fprintf('Exitflag: %d\n', kpi.exitflag);
fprintf('NH3: %.2f kg, target: %.2f kg, short: %.6f kg\n', ...
    kpi.nh3_total_kg, kpi.nh3_target_kg, kpi.nh3_short_kg);
fprintf('H2 short: %.6f kg\n', kpi.h2_short_total_kg);
fprintf('Operating cost: %.2f USD, %.2f USD/t-NH3\n', ...
    kpi.cost_total_usd, kpi.unit_operating_cost_usd_per_ton_nh3);
fprintf('Renewable utilization: %.4f, curtailment: %.4f\n', ...
    kpi.renewable_utilization_fraction, kpi.curtailment_fraction);
fprintf('Grid buy/load: %.4f, grid sell/renewable: %.4f\n', ...
    kpi.grid_buy_fraction_of_load, kpi.grid_sell_fraction_of_renewable);
fprintf('AEL utilization hour in 7 days: %.2f h\n', ...
    kpi.ael_utilization_hour);
fprintf('HB average load: %.4f\n', kpi.hb_average_load);
fprintf('CO2 intensity: %.6f kg-CO2/kg-NH3\n', ...
    kpi.co2_intensity_kg_per_kg_nh3);
fprintf('Max power residual: %.3e kW\n', kpi.max_power_residual_kw);
fprintf('Max storage residual: %.3e kg\n', kpi.max_storage_residual_kg);
fprintf('Buy/sell overlap: %.3e kWh\n\n', kpi.buy_sell_overlap_kwh);
end

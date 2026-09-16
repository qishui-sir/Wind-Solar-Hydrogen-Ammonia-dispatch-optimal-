% DIAG_O1_TWO_SOLVES: solve the two O1 objectives in isolation and report their
% true LP lower bounds, on a short horizon.
%
% MATLAB's intlinprog output has no 'bestbound' field; the lower bound is
% reconstructed as (fval - absolutegap), which is what solve_record uses.
%
% Usage: diag_o1_two_solves(day_count, target_fraction)

function diag_o1_two_solves(day_count, target_fraction)
if nargin < 1 || isempty(day_count); day_count = 30; end
if nargin < 2 || isempty(target_fraction); target_fraction = 0.75; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(fullfile(src_dir, 'algorithm'));
addpath(source_dir);

data_cfg = struct();
data_cfg.pv_year = 2022; data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000; data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = day_count;
renewable_data = load_res_year(data_cfg);
T = renewable_data.time_count;

params = my_system('s2');
params.AEL.common.startup = true;
params.solver.relative_gap = 0.02;

dt = params.time.step;
max_out = params.HB.max_load * params.HB.nh3_output * T * dt / params.unit.mass_scale;
target_t = target_fraction * max_out;
fprintf('[two] horizon=%d h, target=%.1f t (%.0f%% of HB-only max %.1f)\n', ...
    T, target_t, 100*target_fraction, max_out);

cfg = struct('nh3_target_t', target_t, 'change_epsilon', 0.01, ...
    'display', 'iter');

out = baseline(params, renewable_data, @(model) run_two(model, cfg));
disp(out);
end

function out = run_two(model, cfg)
params = model.params;
T = model.renewable_data.time_count;
dt = params.time.step;
HB_load = model.variables.HB_load;

prob = model.problem;
prob.Constraints.o1_nh3 = model.expressions.nh3_total_t == cfg.nh3_target_t;

z = optimvar('dbg_change', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
sp = optimvar('dbg_setpoint', T, 'LowerBound', params.HB.min_load, ...
    'UpperBound', params.HB.max_load);
sp_next = [sp(2:end); sp(1)];
dsp = sp_next - sp;
M = params.HB.ramp_rate * dt + cfg.change_epsilon;
prob.Constraints.dbg_track_up = HB_load - sp <= cfg.change_epsilon/2;
prob.Constraints.dbg_track_dn = sp - HB_load <= cfg.change_epsilon/2;
prob.Constraints.dbg_chg_up = dsp <= M * z;
prob.Constraints.dbg_chg_dn = -dsp <= M * z;
count = sum(z);

out = struct();
out.M_bigM = M;
out.target_t = cfg.nh3_target_t;

% ---- solve 1: baseline's own NET objective (what baseline.m minimizes) ----
p1 = prob; p1.Objective = model.expressions.system_cost_usd + ...
    (model.problem.Objective - model.expressions.system_cost_usd);
o1 = optimoptions(model.options, 'RelativeGapTolerance', 1e-3, ...
    'MaxTime', 180, 'Display', cfg.display);
out.solve1 = solve_and_report(p1, o1, 'NET obj (with NH3 revenue)', []);

% ---- solve 2: gross system_cost_usd (what O1 minimizes) ----
p2 = prob; p2.Objective = model.expressions.system_cost_usd;
o2 = optimoptions(model.options, 'RelativeGapTolerance', 1e-3, ...
    'MaxTime', 180, 'Display', cfg.display);
out.solve2 = solve_and_report(p2, o2, 'GROSS system_cost_usd', []);

% ---- solve 3: count objective ----
p3 = prob; p3.Objective = count;
o3 = optimoptions(model.options, 'RelativeGapTolerance', 0, ...
    'AbsoluteGapTolerance', 0.99, 'MaxTime', 180, 'Display', cfg.display);
out.solve3 = solve_and_report(p3, o3, 'COUNT sum(z)', []);

% value of both expressions at the reference solution
if isstruct(out.solve2.solution) && isfield(out.solve2.solution, 'P_AEL')
    s = out.solve2.solution;
    out.net_at_gross_solution = evaluate( ...
        model.problem.Objective, s);
    out.gross_at_gross_solution = evaluate( ...
        model.expressions.system_cost_usd, s);
    % evaluate both at the NET-optimal solution too
    if isstruct(out.solve1.solution) && isfield(out.solve1.solution, 'P_AEL')
        out.net_at_net_solution = evaluate(model.problem.Objective, out.solve1.solution);
        out.gross_at_net_solution = evaluate( ...
            model.expressions.system_cost_usd, out.solve1.solution);
    end
end
end

function rec = solve_and_report(prob, opts, label, init)
fprintf('\n########## %s ##########\n', label);
try
    if isempty(init)
        [sol, fval, ef, output] = solve(prob, 'Solver', 'intlinprog', 'Options', opts);
    else
        [sol, fval, ef, output] = solve(prob, init, 'Solver', 'intlinprog', 'Options', opts);
    end
catch err
    fprintf('[two] %s FAILED: %s\n', label, err.message);
    rec = struct('label', label, 'error', string(err.message));
    return
end
ag = NaN; rg = NaN;
if isfield(output, 'absolutegap'); ag = output.absolutegap; end
if isfield(output, 'relativegap'); rg = output.relativegap; end
lo = fval - ag;
fprintf('\n[two] --- %s ---\n', label);
fprintf('[two] fval (best sol)      = %.6f\n', fval);
fprintf('[two] absolutegap          = %.6f\n', ag);
fprintf('[two] lower bound (fval-ag)= %.6f   <-- BestBound\n', lo);
fprintf('[two] relativegap          = %.6g\n', rg);
fprintf('[two] exitflag             = %d\n', ef);
fprintf('[two] LOWER BOUND NEGATIVE? %d\n', lo < 0);
rec = struct('label', label, 'fval', fval, 'absolutegap', ag, ...
    'lower_bound', lo, 'relative_gap', rg, 'exitflag', ef, ...
    'solution', sol);
end

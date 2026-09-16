% DIAG_O1_BOUNDS: dump the primal/dual bounds at every O1 stage on a short horizon.
%
% Purpose: locate which MILP produces a negative lower bound, and which MILP has
% an unusable (too wide) gap. Runs the same O1 study as main.m but on a short
% horizon with small time budgets so the bounds can be inspected quickly.
%
% Usage: diag_o1_bounds(day_count, target_fraction)

function diag_o1_bounds(day_count, target_fraction)
if nargin < 1 || isempty(day_count); day_count = 30; end
if nargin < 2 || isempty(target_fraction); target_fraction = 0.8; end

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

% Scale the NH3 target to this horizon.
dt = params.time.step;
max_output_t = params.HB.max_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
min_output_t = params.HB.min_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
target_t = target_fraction * max_output_t;

fprintf('[diag] horizon %d d (%d h)\n', day_count, T);
fprintf('[diag] NH3 feasible range [%.1f, %.1f] t; target = %.1f t\n', ...
    min_output_t, max_output_t, target_t);

o1_config = struct();
o1_config.nh3_target_t = target_t;
o1_config.cost_allowance_usd_t = [0, 1, 5, 10];
o1_config.frontier_k = [];
o1_config.max_time_s = 120;
o1_config.cost_relative_gap = 1e-3;
o1_config.count_absolute_gap = 0.99;
o1_config.change_epsilon = 0.01;
o1_config.penalty_alpha = [0.1, 1, 10];
o1_config.penalty_max_time_s = 30;
o1_config.penalty_relative_gap = 0.02;
o1_config.max_count_bound_width = 20;
o1_config.display = 'off';

t0 = tic;
study = baseline(params, renewable_data, @(model) O1(model, o1_config));
elapsed = toc(t0);
fprintf('\n[diag] O1 finished in %.1f s, status=%s\n', elapsed, study.status);

% ---- per-stage bounds ----
fprintf('\n================ STAGE BOUNDS ================\n');
fprintf('%-34s %14s %14s %12s %10s\n', 'stage/objective', 'lower', 'upper', 'gap_abs', 'status');

pr_row('reference(cost)', study.reference);
if isfield(study, 'progressive_penalty') && ...
        isfield(study.progressive_penalty, 'runs')
    runs = study.progressive_penalty.runs;
    for i = 1:numel(runs)
        fprintf('%-34s %14s %14s %12s %10s\n', ...
            sprintf('penalty alpha=%g', runs(i).alpha), ...
            '(not stored)', num2str(runs(i).weighted_objective), ...
            num2str(runs(i).relative_gap), char(runs(i).status));
    end
end
if isfield(study, 'feasibility') && isfield(study.feasibility, 'minimum_updates')
    pr_row('feasibility(count)', study.feasibility.minimum_updates);
    fprintf('   -> K_lower=%s  K_upper=%s  width=%s  proven=%d\n', ...
        num2str(study.feasibility.K_lower), ...
        num2str(study.feasibility.K_upper), ...
        num2str(study.feasibility.bound_width), ...
        study.feasibility.is_proven);
end
if isfield(study.feasibility, 'minimum_cost_at_upper_bound')
    pr_row('representative(cost)', study.feasibility.minimum_cost_at_upper_bound);
end
if isfield(study, 'economic')
    for i = 1:numel(study.economic)
        e = study.economic(i);
        fprintf('%-34s %14s %14s %12s %10s\n', ...
            sprintf('economic delta=%g', e.allowance_usd_t), ...
            num2str(e.K_lower), num2str(e.K_upper), ...
            num2str(e.K_upper - e.K_lower), 'K-interval');
    end
end
fprintf('=============================================\n');

% ---- raw record dump for the failing stage ----
if isstruct(study.reference) && ~isempty(fieldnames(study.reference))
    r = study.reference;
    fprintf('\n[diag] reference record:\n');
    fprintf('   status   = %s\n', char(getf_str(r, 'status')));
    fprintf('   exitflag = %s\n', num2str(getf(r, 'exitflag')));
    fprintf('   has_incumbent = %d\n', logical(getf(r, 'has_incumbent')));
    if isfield(r, 'message')
        fprintf('   message  = %s\n', char(string(r.message)));
    end
    if isfield(r, 'output') && isstruct(r.output) && ~isempty(fieldnames(r.output))
        o = r.output;
        fn = fieldnames(o);
        fprintf('   output fields: %s\n', strjoin(fn.', ', '));
        for i = 1:numel(fn)
            v = o.(fn{i});
            if isnumeric(v) && isscalar(v)
                fprintf('      %-18s = %g\n', fn{i}, v);
            elseif ischar(v) || isstring(v)
                fprintf('      %-18s = %s\n', fn{i}, char(string(v)));
            end
        end
    end
end

% ---- why is the count bound weak? inspect the change big-M ----
fprintf('\n[diag] change-indicator big-M = HB_ramp + epsilon = %.4f\n', ...
    params.HB.ramp_rate + o1_config.change_epsilon);
fprintf('[diag] tracking half-band = %.4f\n', o1_config.change_epsilon / 2);
end

function pr_row(label, rec)
if ~isstruct(rec) || isempty(fieldnames(rec))
    fprintf('%-34s %14s %14s %12s %10s\n', label, '-', '-', '-', 'empty');
    return
end
lo = getf(rec, 'objective_lower');
up = getf(rec, 'objective_upper');
ag = getf(rec, 'absolute_gap');
st = getf(rec, 'status');
fprintf('%-34s %14.6g %14.6g %12.6g %10s\n', label, lo, up, ag, char(st));
end

function v = getf(s, f)
if isfield(s, f); v = s.(f); else; v = NaN; end
end

function v = getf_str(s, f)
if isfield(s, f); v = s.(f); else; v = ''; end
end

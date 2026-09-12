% DIAG_GAP: investigate why the full-year MILP stalls at ~0.2% gap under 1e-4.
%
% This does NOT relax the tolerance. It runs the same problem and, after a
% bounded number of branch-and-bound nodes, reports the incumbent and the lower
% bound so we can see where the gap is actually stuck and why.
%
% Usage: diag_gap(day_count, year, max_nodes, max_seconds)

function diag_gap(day_count, year, max_nodes, max_seconds)
if nargin < 1 || isempty(day_count); day_count = 365; end
if nargin < 2 || isempty(year); year = 2022; end
if nargin < 3 || isempty(max_nodes); max_nodes = 0; end      % 0 = no node cap
if nargin < 4 || isempty(max_seconds); max_seconds = 900; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

fprintf('[diag] horizon=%d d, year=%d, max_nodes=%d, max_seconds=%d\n', ...
    day_count, year, max_nodes, max_seconds);

data_cfg = struct();
data_cfg.pv_year = year; data_cfg.pw_year = year;
data_cfg.pv_capacity_kw = 200000; data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = day_count;
renewable_data = load_res_year(data_cfg);
fprintf('[diag] rows=%d\n', renewable_data.time_count);

params = my_system('s2');
params.AEL.common.startup = true;
params.AEL.common.startup_penalty = 0.053;
params.solver.relative_gap = 1e-4;
if max_nodes > 0
    params.solver.max_nodes = max_nodes;
end
params.solver.max_time_s = max_seconds;

t0 = tic;
results = baseline(params, renewable_data);
elapsed = toc(t0);

fprintf('\n[diag] done in %.1f s\n', elapsed);
fprintf('[diag] exitflag=%d\n', results.exitflag);
out = results.output;
if isfield(out, 'relativegap')
    fprintf('[diag] relativegap=%.6g\n', out.relativegap);
end
if isfield(out, 'absolutegap')
    fprintf('[diag] absolutegap=%.6g\n', out.absolutegap);
end
if isfield(out, 'numnodes')
    fprintf('[diag] numnodes=%d\n', out.numnodes);
end
if isfield(out, 'numfeaspoints')
    fprintf('[diag] feasible points=%d\n', out.numfeaspoints);
end

% Objective magnitude decomposition: large opposing terms make a relative gap of
% 1e-4 on the *net* objective require very high absolute precision.
fprintf('\n[diag] objective decomposition (magnitude check):\n');
fprintf('  NH3 income      : %12.2f USD\n', results.economics.INC.ammonia);
fprintf('  grid sell       : %12.2f USD\n', results.economics.INC.grid_sell);
fprintf('  annual fixed    : %12.2f USD\n', results.economics.total_cost);
fprintf('  net (objective) : %12.2f USD\n', results.fval);
fprintf('  AEL starts      : %d (penalty %.2f USD)\n', ...
    sum(results.dispatch.N_AEL(:) > 0 & [0; diff(results.dispatch.N_AEL(:))] > 0), ...
    results.cost.startup_penalty);
end

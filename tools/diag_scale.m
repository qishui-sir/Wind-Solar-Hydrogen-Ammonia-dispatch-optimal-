% DIAG_SCALE: does the 1e-4 gap become reachable as the horizon shrinks?
%
% Runs the same model at increasing horizons and records the B&B work needed.
% This is a diagnostic; it does not change the formulation or the tolerance.

function diag_scale(day_list, year)
if nargin < 1 || isempty(day_list); day_list = [7, 14, 30, 60, 90]; end
if nargin < 2 || isempty(year); year = 2022; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

rows = cell(numel(day_list), 1);
for k = 1:numel(day_list)
    days = day_list(k);
    fprintf('\n########## horizon = %d days ##########\n', days);

    data_cfg = struct();
    data_cfg.pv_year = year; data_cfg.pw_year = year;
    data_cfg.pv_capacity_kw = 200000; data_cfg.pw_capacity_kw = 200000;
    data_cfg.day_count = days;
    renewable_data = load_res_year(data_cfg);

    params = my_system('s2');
    params.AEL.common.startup = true;
    params.solver.relative_gap = 1e-4;

    t0 = tic;
    results = baseline(params, renewable_data);
    el = toc(t0);

    out = results.output;
    dN = diff([0; results.dispatch.N_AEL(:)]);
    row = struct();
    row.days = days;
    row.hours = renewable_data.time_count;
    row.elapsed_s = el;
    row.exitflag = results.exitflag;
    row.relgap = getfield_default(out, 'relativegap', NaN);
    row.absgap = getfield_default(out, 'absolutegap', NaN);
    row.numnodes = getfield_default(out, 'numnodes', NaN);
    row.obj = results.fval;
    row.units_started = sum(max(dN, 0));
    row.start_events = sum(dN > 0);
    rows{k} = row;

    fprintf('[scale] %d d: %.1f s, nodes=%d, gap=%.3g, started=%d\n', ...
        days, el, row.numnodes, row.relgap, row.units_started);
end

T = struct2table([rows{:}]);
disp(T);
writetable(T, fullfile(project_dir, 'results_out', 'diag_scale.csv'));
fprintf('\nwrote diag_scale.csv\n');
end

function v = getfield_default(s, f, d)
if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end

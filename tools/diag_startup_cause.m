% DIAG_STARTUP_CAUSE Compare physical startup electricity on/off at given gaps.
%
% Two factors are varied independently on the same horizon and data:
%   - whether physical startup electricity is enabled
%   - the relative gap tolerance
% Everything else is held fixed, so the effect of each factor is separable.

% Usage: diag_startup_cause(days, year, startup_enabled, gaps)
% The third argument accepts only logical values or 0/1, not cost coefficients.
function diag_startup_cause(days, year, startup_enabled, gaps)
if nargin < 1 || isempty(days); days = 7; end
if nargin < 2 || isempty(year); year = 2022; end
if nargin < 3 || isempty(startup_enabled); startup_enabled = [false, true]; end
if nargin < 4 || isempty(gaps); gaps = [1e-4, 0.02]; end
if ~(islogical(startup_enabled) || isnumeric(startup_enabled)) || ...
        ~isvector(startup_enabled) || ~all(ismember(startup_enabled, [0, 1]))
    error('diag_startup_cause:bad_startup_flag', ...
        'Use startup_enabled=[false,true]; extra startup cost coefficients were removed.');
end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

data_cfg = struct();
data_cfg.pv_year = year; data_cfg.pw_year = year;
data_cfg.pv_capacity_kw = 200000; data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = days;
renewable_data = load_res_year(data_cfg);
fprintf('[cause] %d days (%d h), year %d\n', days, renewable_data.time_count, year);

rows = {};
for g = 1:numel(gaps)
    for c = 1:numel(startup_enabled)
        gap = gaps(g); enabled = logical(startup_enabled(c));
        params = my_system('s2');
        params.AEL.common.startup = enabled;
        params.solver.relative_gap = gap;

        fprintf('\n[cause] gap=%.4g, startup electricity=%d\n', gap, enabled);
        try
            results = baseline(params, renewable_data);
        catch err
            fprintf('[cause] FAILED: %s\n', err.message);
            continue
        end

        dN = diff([0; results.dispatch.N_AEL(:)]);
        out = results.output;
        row = struct();
        row.gap_tol = gap;
        row.startup_enabled = enabled;
        row.units_started = sum(max(dN, 0));
        row.start_events = sum(dN > 0);
        row.units_stopped = sum(max(-dN, 0));
        row.startup_mwh = results.summary.AEL_start_energy_kwh / 1000;
        row.obj = results.fval;
        row.nh3_t = results.summary.NH3_prod_t_y;
        if isfield(out, 'relativegap'); row.relgap = out.relativegap; else; row.relgap = NaN; end
        if isfield(out, 'numnodes'); row.nodes = out.numnodes; else; row.nodes = NaN; end
        rows{end+1} = row; %#ok<AGROW>

        fprintf('[cause]   started=%d (events=%d), startup=%.2f MWh, gap_achieved=%.3g\n', ...
            row.units_started, row.start_events, row.startup_mwh, row.relgap);
    end
end

T = struct2table([rows{:}]);
disp(T);
writetable(T, fullfile(project_dir, 'results_out', 'diag_startup_cause.csv'));
fprintf('\nwrote diag_startup_cause.csv\n');

fprintf('\n=== effect of physical startup electricity (per gap) ===\n');
for g = 1:numel(gaps)
    sel = T(T.gap_tol == gaps(g), :);
    if height(sel) >= 2
        fprintf('gap=%.4g : started %s  (startup enabled %s)\n', gaps(g), ...
            mat2str(sel.units_started'), mat2str(sel.startup_enabled'));
    end
end
end

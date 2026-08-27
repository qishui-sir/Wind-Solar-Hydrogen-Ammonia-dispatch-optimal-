function report = benchmark_solver_time(config)
%BENCHMARK_SOLVER_TIME Estimate single-candidate cost and recommend a grid size.
%
%   report = benchmark_solver_time()
%   report = benchmark_solver_time(config)
%
% Reads run_info.solver_records from already-completed rolling MAT files
% (zero re-computation), extrapolates single-machine wall-clock time per
% candidate, and recommends the largest candidate grid that fits the compute
% budget. It never runs the dispatch model and never changes results.
%
% config fields:
%   rolling_dirs  cellstr of rolling result directories to scan
%                 (default: stage5/joint_grid/rolling and
%                 stage4/h2_reserve_grid/rolling)
%   grid_sizes    vector of candidate grid sizes to project (default [15 27 45 156])
%   budget_hours  wall-clock budget for the grid in hours (default 400)
%   safety_factor multiplier to cover slower persistence solves (default 1.5)
%   verbose       logical, print the report (default true)

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = setup_project_paths(mfilename('fullpath'));

rolling_dirs = option_value(config, 'rolling_dirs', ...
    default_rolling_dirs(project_dir));
if ischar(rolling_dirs) || isstring(rolling_dirs)
    rolling_dirs = {char(rolling_dirs)};
end
grid_sizes = option_value(config, 'grid_sizes', [15, 27, 45, 156]);
budget_hours = option_value(config, 'budget_hours', 400);
safety_factor = option_value(config, 'safety_factor', 1.5);
verbose = option_value(config, 'verbose', true);

validate_numeric(grid_sizes, 'grid_sizes');
validate_positive_scalar(budget_hours, 'budget_hours');
validate_positive_scalar(safety_factor, 'safety_factor');

per_file = scan_rolling_results(rolling_dirs);
completed = per_file(per_file.Status == "completed", :);

report = struct();
report.project_dir = string(project_dir);
report.scanned_file_count = height(per_file);
report.completed_candidate_count = height(completed);
report.budget_hours = budget_hours;
report.safety_factor = safety_factor;

if isempty(completed)
    report.single_candidate_seconds_median = NaN;
    report.single_candidate_seconds_p95 = NaN;
    report.grid_projection = table();
    report.recommended_grid_size = NaN;
    if verbose
        fprintf(['benchmark_solver_time: no completed rolling results found ', ...
            'under the scanned directories.\n']);
    end
    return
end

total_seconds = completed.TotalSeconds;
report.single_candidate_seconds_min = min(total_seconds);
report.single_candidate_seconds_median = median(total_seconds);
report.single_candidate_seconds_p95 = prctile(total_seconds, 95);
report.single_candidate_seconds_max = max(total_seconds);
report.seconds_per_day_median = median(completed.SecondsPerDay);
report.seconds_per_day_p95 = prctile(completed.SecondsPerDay, 95);

report.grid_projection = project_grid_cost( ...
    grid_sizes, total_seconds, safety_factor);
report.recommended_grid_size = recommend_grid_size( ...
    report.grid_projection, budget_hours);

if verbose
    print_report(report);
end
end

function dirs = default_rolling_dirs(project_dir)
dirs = { ...
    fullfile(project_dir, 'runs', 'stage5', 'joint_grid', 'rolling'), ...
    fullfile(project_dir, 'runs', 'stage4', 'h2_reserve_grid', 'rolling')};
end

function per_file = scan_rolling_results(rolling_dirs)
file_all = string.empty(0, 1);
status_all = string.empty(0, 1);
day_all = zeros(0, 1);
plan_all = zeros(0, 1);
recourse_all = zeros(0, 1);

for dir_index = 1:numel(rolling_dirs)
    dir_path = char(rolling_dirs{dir_index});
    if ~isfolder(dir_path)
        continue
    end
    listing = dir(fullfile(dir_path, '*.mat'));
    for file_index = 1:numel(listing)
        mat_path = fullfile(dir_path, listing(file_index).name);
        [status, day_count, plan_sec, recourse_sec] = ...
            inspect_one_result(mat_path);
        file_all(end + 1, 1) = string(mat_path); %#ok<AGROW>
        status_all(end + 1, 1) = status; %#ok<AGROW>
        day_all(end + 1, 1) = day_count; %#ok<AGROW>
        plan_all(end + 1, 1) = plan_sec; %#ok<AGROW>
        recourse_all(end + 1, 1) = recourse_sec; %#ok<AGROW>
    end
end

total_all = plan_all + recourse_all;
seconds_per_day = total_all ./ max(day_all, 1);
per_file = table(file_all, status_all, day_all, plan_all, recourse_all, ...
    total_all, seconds_per_day, ...
    'VariableNames', {'File', 'Status', 'DayCount', 'PlanSeconds', ...
    'RecourseSeconds', 'TotalSeconds', 'SecondsPerDay'});
end

function [status, day_count, plan_sec, recourse_sec] = ...
        inspect_one_result(mat_path)
status = "unreadable";
day_count = NaN;
plan_sec = NaN;
recourse_sec = NaN;
try
    loaded = load(mat_path, 'run_info');
catch
    return
end
if ~isstruct(loaded) || ~isfield(loaded, 'run_info')
    return
end
info = loaded.run_info;
if isfield(info, 'status')
    status = string(info.status);
end
if status ~= "completed" || ~isfield(info, 'solver_records')
    return
end
rec = info.solver_records;
if ~isstruct(rec) || ~isfield(rec, 'plan_seconds') || ...
        ~isfield(rec, 'recourse_seconds')
    return
end
plan = double(rec.plan_seconds(:));
recourse = double(rec.recourse_seconds(:));
plan_sec = sum(plan, 'omitnan');
recourse_sec = sum(recourse, 'omitnan');
day_count = max(numel(plan), numel(recourse));
end

function projection = project_grid_cost(grid_sizes, total_seconds, ...
        safety_factor)
grid_sizes = grid_sizes(:);
median_sec = median(total_seconds);
p95_sec = prctile(total_seconds, 95);
hours_median = grid_sizes * median_sec * safety_factor / 3600;
hours_p95 = grid_sizes * p95_sec * safety_factor / 3600;
projection = table(grid_sizes, hours_median, hours_p95, ...
    'VariableNames', {'GridSizeCandidates', ...
    'WallClockHoursMedian', 'WallClockHoursP95'});
end

function best = recommend_grid_size(projection, budget_hours)
feasible = projection.WallClockHoursP95 <= budget_hours;
if ~any(feasible)
    best = projection.GridSizeCandidates(1);
    return
end
best = max(projection.GridSizeCandidates(feasible));
end

function print_report(report)
fprintf('\n========== Rolling solver-time benchmark ==========\n');
fprintf('Scanned MAT files: %d\n', report.scanned_file_count);
fprintf('Completed rolling candidates: %d\n', ...
    report.completed_candidate_count);
fprintf('Single candidate total solve time:\n');
fprintf('  min %.1f min | median %.1f min | p95 %.1f min | max %.1f min\n', ...
    report.single_candidate_seconds_min / 60, ...
    report.single_candidate_seconds_median / 60, ...
    report.single_candidate_seconds_p95 / 60, ...
    report.single_candidate_seconds_max / 60);
fprintf('Per operating day (plan + recourse): median %.1f s | p95 %.1f s\n', ...
    report.seconds_per_day_median, report.seconds_per_day_p95);
fprintf('\nGrid projection (safety factor %.1fx, single serial machine):\n', ...
    report.safety_factor);
disp(report.grid_projection);
fprintf('\nBudget: %.0f wall-clock hours\n', report.budget_hours);
fprintf(['Recommended grid size (largest with p95 hours <= budget): %d ', ...
    'candidates\n'], report.recommended_grid_size);
if report.recommended_grid_size < ...
        max(report.grid_projection.GridSizeCandidates)
    fprintf(['Note: larger grids exceed the budget on one serial machine. ', ...
        'Reduce the grid, add parallel cores, or extend the budget.\n']);
end
fprintf(['Note: baselines are observed_oracle 2022 results. Persistence ', ...
    'runs can be slower because of extra projection/recourse solves; ', ...
    'the safety factor covers that.\n']);
fprintf('====================================================\n');
end

function validate_numeric(values, name)
if ~(isnumeric(values) && isvector(values) && ...
        all(isfinite(values)) && all(values > 0))
    error('benchmark_solver_time:bad_input', ...
        '%s must be a positive numeric vector.', name);
end
end

function validate_positive_scalar(value, name)
if ~(isnumeric(value) && isscalar(value) && ...
        isfinite(value) && value > 0)
    error('benchmark_solver_time:bad_input', ...
        '%s must be a positive scalar.', name);
end
end

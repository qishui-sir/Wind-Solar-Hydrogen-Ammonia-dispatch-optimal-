function run_full_campaign(config)
%RUN_FULL_CAMPAIGN Full paper compute: 2024 calibration + 2025 lock.
%   - 2024: Stage 1 + rolling baseline + Stage 5 joint grid (persistence)
%           + v5.2 selection audit
%   - 2025: Stage 1 + rolling baseline + economic_only + selected candidate
%
%   Logs every step to runs/campaign_log.txt and skips already-computed
%   artifacts, so restarting after a shutdown resumes without redoing work.
%
% config fields:
%   run_2024  logical (default true)
%   run_2025  logical (default true)
%   stage5    struct forwarded to stage5_run_v51_joint_grid (grid size etc.)

if nargin < 1 || isempty(config)
    config = struct();
end

% Bootstrap the path without relying on any already-added folder.
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(genpath(fullfile(project_dir, 'src')));

ensure_directory(fullfile(project_dir, 'runs'));
log_path = fullfile(project_dir, 'runs', 'campaign_log.txt');
diary(char(log_path));
diary on;
cleanup = onCleanup(@() diary('off'));

fprintf('\n===== Campaign start: %s =====\n', char(datetime('now')));

fallback = build_development_forecast_fallback();

if option_value(config, 'run_2024', true)
    run_year_calibration(project_dir, 2024, fallback, config);
end
if option_value(config, 'run_2025', true)
    run_year_lock(project_dir, 2025, fallback, config);
end

fprintf('===== Campaign end: %s =====\n', char(datetime('now')));
diary off;
end

function run_year_calibration(project_dir, year, fallback, config)
fprintf('\n----- %d calibration (persistence) -----\n', year);
stage1_mat = ensure_stage1(project_dir, year);
baseline_mat = ensure_rolling_baseline(project_dir, year, fallback, stage1_mat);

stage5_config = option_value(config, 'stage5', struct());
stage5_config.source_mat_path = stage1_mat;
stage5_config.baseline_mat_path = baseline_mat;
stage5_config.forecast_mode = "simulated_persistence";
stage5_config.forecast_fallback = fallback;
stage5_config.resume = true;
stage5_config.output_dir = fullfile(project_dir, 'runs', 'stage5', ...
    'joint_grid');
stage5_config.rolling_output_dir = fullfile(project_dir, ...
    'runs', 'stage5', 'joint_grid', 'rolling');

fprintf('Stage 5 joint grid %d...\n', year);
if option_value(config, 'use_parallel', true)
    try
        [grid_table, grid_run_info] = run_stage5_parallel(stage5_config);
    catch exception
        warning('run_full_campaign:parallel_failed', ...
            'Parallel Stage 5 failed (%s); falling back to serial.', ...
            exception.message);
        [grid_table, grid_run_info] = stage5_run_v51_joint_grid(stage5_config);
    end
else
    [grid_table, grid_run_info] = stage5_run_v51_joint_grid(stage5_config);
end

[selected, audit_table, selection_info] = ...
    select_protocol_v52_candidate(grid_table, grid_run_info, struct());
ensure_directory(fullfile(project_dir, 'runs', 'stage2'));
base = sprintf('v52_selection_audit_%d_latest', year);
writetable(audit_table, fullfile(project_dir, 'runs', 'stage2', ...
    [base, '.csv']));
save(fullfile(project_dir, 'runs', 'stage2', [base, '.mat']), ...
    'selected', 'audit_table', 'selection_info');
fprintf('v5.2 selection %d: %s | selected: %s\n', year, ...
    selection_info.status, string(selection_info.selected_case_id));
end

function run_year_lock(project_dir, year, fallback, ~)
fprintf('\n----- %d lock (persistence) -----\n', year);
stage1_mat = ensure_stage1(project_dir, year);
ensure_rolling_baseline(project_dir, year, fallback, stage1_mat);
ensure_economic_only(project_dir, year, fallback, stage1_mat);

selection_mat = fullfile(project_dir, 'runs', 'stage2', ...
    'v52_selection_audit_2024_latest.mat');
if isfile(selection_mat)
    loaded = load(selection_mat, 'selected');
    if isfield(loaded, 'selected') && ...
            isfield(loaded.selected, 'case_id') && ...
            strlength(string(loaded.selected.case_id)) > 0
        run_selected_candidate(project_dir, year, fallback, ...
            stage1_mat, loaded.selected);
    else
        fprintf('No eligible candidate from 2024; skip 2025 selected run.\n');
    end
else
    fprintf('Missing 2024 selection audit; skip 2025 selected run.\n');
end
end

function stage1_mat = ensure_stage1(project_dir, year)
stage1_mat = fullfile(project_dir, 'runs', 'stage1', ...
    sprintf('zhou_s2_baseline_%d_latest.mat', year));
if ~isfile(stage1_mat)
    fprintf('Stage 1 baseline %d...\n', year);
    stage1_run_zhou_s2_baseline(struct( ...
        'data_year', year, 'save_output', true));
end
if ~isfile(stage1_mat)
    error('run_full_campaign:missing_stage1', ...
        'Missing Stage 1 MAT file: %s', stage1_mat);
end
fprintf('Stage 1 %d ready.\n', year);
end

function baseline_mat = ensure_rolling_baseline(project_dir, year, ...
        fallback, stage1_mat)
baseline_mat = fullfile(project_dir, 'runs', 'rolling', ...
    sprintf('v51_contract_plan_and_hb_smoothing_%d_latest.mat', year));
if ~isfile(baseline_mat)
    fprintf('Rolling baseline %d (persistence)...\n', year);
    rolling_dispatch(struct( ...
        'source_mat_path', stage1_mat, ...
        'scheme', "contract_plan_and_hb_smoothing", ...
        'forecast_mode', "simulated_persistence", ...
        'forecast_fallback', fallback, ...
        'allow_infeasible_continuation', true, ...
        'output_dir', fullfile(project_dir, 'runs', 'rolling'), ...
        'save_output', true, ...
        'verbose', false, ...
        'solver_display', 'none'));
end
if ~isfile(baseline_mat)
    error('run_full_campaign:missing_baseline', ...
        'Missing rolling baseline MAT file: %s', baseline_mat);
end
fprintf('Rolling baseline %d ready.\n', year);
end

function ensure_economic_only(project_dir, year, fallback, stage1_mat)
output = fullfile(project_dir, 'runs', 'rolling', ...
    sprintf('v51_economic_only_%d_latest.mat', year));
if isfile(output)
    fprintf('economic_only %d ready.\n', year);
    return
end
fprintf('economic_only %d (persistence)...\n', year);
rolling_dispatch(struct( ...
    'source_mat_path', stage1_mat, ...
    'scheme', "economic_only", ...
    'forecast_mode', "simulated_persistence", ...
    'forecast_fallback', fallback, ...
    'allow_infeasible_continuation', true, ...
    'output_dir', fullfile(project_dir, 'runs', 'rolling'), ...
    'save_output', true, ...
    'verbose', false, ...
    'solver_display', 'none'));
end

function run_selected_candidate(project_dir, year, fallback, ...
        stage1_mat, selected)
fprintf('Selected candidate %d: %s...\n', year, ...
    string(selected.case_id));
rolling_dispatch(struct( ...
    'source_mat_path', stage1_mat, ...
    'scheme', "contract_plan_and_hb_smoothing", ...
    'forecast_mode', "simulated_persistence", ...
    'forecast_fallback', fallback, ...
    'h2_reserve_quantile', selected.h2_reserve_quantile, ...
    'h2_reserve_lookahead_days', selected.h2_reserve_lookahead_days, ...
    'h2_reserve_soft', selected.h2_reserve_soft, ...
    'h2_reserve_gate_mode', string(selected.h2_reserve_gate_mode), ...
    'contract_pacing_aggressiveness', ...
        selected.contract_pacing_aggressiveness, ...
    'hb_smoothing_reduction_fraction', ...
        selected.hb_smoothing_reduction_fraction, ...
    'allow_infeasible_continuation', true, ...
    'output_dir', fullfile(project_dir, 'runs', 'rolling'), ...
    'save_output', true, ...
    'verbose', false, ...
    'solver_display', 'none'));
end

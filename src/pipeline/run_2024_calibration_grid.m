function outputs = run_2024_calibration_grid(config)
%RUN_2024_CALIBRATION_GRID Run the 2024 calibration grid end-to-end.
%   Steps: (1) 2024 Stage 1 annual baseline, (2) 2022/2023 forecast fallback,
%   (3) 2024 rolling baseline, (4) Stage 5 joint grid under simulated
%   persistence, (5) v5.2 selection audit.
%
%   2024 is the calibration year, so observed_oracle is not used; the grid
%   runs simulated_persistence with the frozen 2022/2023 fallback.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = setup_project_paths(mfilename('fullpath'));
data_year = option_value(config, 'data_year', 2024);
verbose = option_value(config, 'verbose', true);

outputs = struct();

% 1. Stage 1 2024 annual baseline
stage1_mat = fullfile(project_dir, 'runs', 'stage1', ...
    sprintf('zhou_s2_baseline_%d_latest.mat', data_year));
if option_value(config, 'run_stage1', true) && ~isfile(stage1_mat)
    if verbose, fprintf('Stage 1 baseline (%d)...\n', data_year); end
    stage1_run_zhou_s2_baseline(struct( ...
        'data_year', data_year, 'save_output', true));
end
if ~isfile(stage1_mat)
    error('run_2024_calibration_grid:missing_stage1', ...
        'Missing Stage 1 MAT file: %s', stage1_mat);
end

% 2. forecast fallback (2022/2023, no target-year leakage)
fallback = build_development_forecast_fallback();

% 3. 2024 rolling baseline
baseline_mat = fullfile(project_dir, 'runs', 'rolling', ...
    sprintf('v51_contract_plan_and_hb_smoothing_%d_latest.mat', data_year));
if option_value(config, 'run_baseline', true) && ~isfile(baseline_mat)
    if verbose, fprintf('Rolling baseline (%d, persistence)...\n', data_year); end
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
    error('run_2024_calibration_grid:missing_baseline', ...
        'Missing rolling baseline MAT file: %s', baseline_mat);
end

% 4. Stage 5 joint grid (persistence)
stage5_config = option_value(config, 'stage5', struct());
stage5_config.source_mat_path = stage1_mat;
stage5_config.baseline_mat_path = baseline_mat;
stage5_config.forecast_mode = "simulated_persistence";
stage5_config.forecast_fallback = fallback;
stage5_config.output_dir = fullfile(project_dir, 'runs', 'stage5', ...
    'joint_grid');
stage5_config.rolling_output_dir = fullfile(project_dir, ...
    'runs', 'stage5', 'joint_grid', 'rolling');
if verbose
    fprintf('Stage 5 joint grid (%d, persistence)...\n', data_year);
end
[grid_table, grid_run_info] = stage5_run_v51_joint_grid(stage5_config);

% 5. v5.2 selection audit
selection_config = option_value(config, 'v52_selection', struct());
[selected, audit_table, selection_info] = ...
    select_protocol_v52_candidate(grid_table, grid_run_info, selection_config);
if option_value(config, 'save_selection', true)
    ensure_directory(fullfile(project_dir, 'runs', 'stage2'));
    base = sprintf('v52_selection_audit_%d_latest', data_year);
    selection_info.output_mat_path = string(fullfile(project_dir, ...
        'runs', 'stage2', [base, '.mat']));
    selection_info.output_csv_path = string(fullfile(project_dir, ...
        'runs', 'stage2', [base, '.csv']));
    writetable(audit_table, char(selection_info.output_csv_path));
    save(char(selection_info.output_mat_path), 'selected', ...
        'audit_table', 'selection_info');
end

outputs.grid_table = grid_table;
outputs.grid_run_info = grid_run_info;
outputs.selected = selected;
outputs.audit_table = audit_table;
outputs.selection_info = selection_info;

if verbose
    fprintf('v5.2 selection: %s | selected case: %s\n', ...
        selection_info.status, string(selection_info.selected_case_id));
end
end

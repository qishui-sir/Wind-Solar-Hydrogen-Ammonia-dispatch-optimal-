function outputs = run_paper_campaign(config)
%RUN_PAPER_CAMPAIGN Full paper compute campaign (strategy A: dual bound).
%   Upper bound: observed_oracle grids for development years (2022 already
%   done, 2023 recomputed here). Lower bound: simulated_persistence grids for
%   2024 calibration and (later) 2025 lock. Runs serially.
%
% config fields:
%   run_2023_oracle    logical (default true)
%   run_2024_persist   logical (default true)
%   run_v52_selection  logical (default true)
%   stage5             struct forwarded to stage5_run_v51_joint_grid

if nargin < 1 || isempty(config)
    config = struct();
end

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath'));
verbose = option_value(config, 'verbose', true);
outputs = struct();

fallback = build_development_forecast_fallback();

if option_value(config, 'run_2023_oracle', true)
    if verbose, fprintf('\n===== Campaign: 2023 observed_oracle grid =====\n'); end
    outputs.year2023 = run_grid_year(project_dir, 2023, ...
        "observed_oracle", [], config, verbose);
end

if option_value(config, 'run_2024_persist', true)
    if verbose, fprintf('\n===== Campaign: 2024 persistence grid =====\n'); end
    outputs.year2024 = run_grid_year(project_dir, 2024, ...
        "simulated_persistence", fallback, config, verbose);
    if option_value(config, 'run_v52_selection', true)
        outputs.v52_selection = run_v52_selection(project_dir, ...
            outputs.year2024, 2024, verbose);
    end
end

if verbose, fprintf('\n===== Campaign finished =====\n'); end
end

function result = run_grid_year(project_dir, year, forecast_mode, ...
        fallback, config, verbose)
result = struct();

stage1_mat = fullfile(project_dir, 'runs', 'stage1', ...
    sprintf('zhou_s2_baseline_%d_latest.mat', year));
if ~isfile(stage1_mat)
    if verbose, fprintf('[campaign] Stage 1 baseline %d...\n', year); end
    stage1_run_zhou_s2_baseline(struct( ...
        'data_year', year, 'save_output', true));
end
if ~isfile(stage1_mat)
    error('run_paper_campaign:missing_stage1', ...
        'Missing Stage 1 MAT file: %s', stage1_mat);
end

baseline_mat = fullfile(project_dir, 'runs', 'rolling', ...
    sprintf('v51_contract_plan_and_hb_smoothing_%d_latest.mat', year));
if ~isfile(baseline_mat)
    baseline_config = struct( ...
        'source_mat_path', stage1_mat, ...
        'scheme', "contract_plan_and_hb_smoothing", ...
        'forecast_mode', forecast_mode, ...
        'allow_infeasible_continuation', true, ...
        'output_dir', fullfile(project_dir, 'runs', 'rolling'), ...
        'save_output', true, ...
        'verbose', false, ...
        'solver_display', 'none');
    if ~isempty(fallback)
        baseline_config.forecast_fallback = fallback;
    end
    if verbose
        fprintf('[campaign] Rolling baseline %d (%s)...\n', ...
            year, forecast_mode);
    end
    rolling_dispatch(baseline_config);
end
if ~isfile(baseline_mat)
    error('run_paper_campaign:missing_baseline', ...
        'Missing rolling baseline MAT file: %s', baseline_mat);
end

stage5_config = struct();
stage5_config.source_mat_path = stage1_mat;
stage5_config.baseline_mat_path = baseline_mat;
stage5_config.forecast_mode = forecast_mode;
if ~isempty(fallback)
    stage5_config.forecast_fallback = fallback;
end
stage5_config.output_dir = fullfile(project_dir, 'runs', 'stage5', ...
    'joint_grid');
stage5_config.rolling_output_dir = fullfile(project_dir, ...
    'runs', 'stage5', 'joint_grid', 'rolling');

forwarded = option_value(config, 'stage5', struct());
forwarded_names = fieldnames(forwarded);
for field_index = 1:numel(forwarded_names)
    name = forwarded_names{field_index};
    stage5_config.(name) = forwarded.(name);
end

if verbose
    fprintf('[campaign] Stage 5 grid %d (%s)...\n', year, forecast_mode);
end
[grid_table, grid_run_info] = stage5_run_v51_joint_grid(stage5_config);
result.grid_table = grid_table;
result.grid_run_info = grid_run_info;
end

function selection = run_v52_selection(project_dir, year_result, year, ...
        verbose)
[selected, audit_table, selection_info] = ...
    select_protocol_v52_candidate(year_result.grid_table, ...
    year_result.grid_run_info, struct());
ensure_directory(fullfile(project_dir, 'runs', 'stage2'));
base = sprintf('v52_selection_audit_%d_latest', year);
mat_path = fullfile(project_dir, 'runs', 'stage2', [base, '.mat']);
csv_path = fullfile(project_dir, 'runs', 'stage2', [base, '.csv']);
writetable(audit_table, csv_path);
save(mat_path, 'selected', 'audit_table', 'selection_info');
if verbose
    fprintf('[campaign] v5.2 selection %d: %s | selected: %s\n', ...
        year, selection_info.status, string(selection_info.selected_case_id));
end
selection = struct( ...
    'selected', selected, ...
    'audit_table', audit_table, ...
    'selection_info', selection_info);
end

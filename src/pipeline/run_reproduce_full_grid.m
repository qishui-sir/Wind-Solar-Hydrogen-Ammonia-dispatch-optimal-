function outputs = run_reproduce_full_grid(config)
%RUN_REPRODUCE_FULL_GRID Recompute Stage 4 and Stage 5 grids.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
run_stage4 = option_value(config, 'run_stage4', true);
run_stage5 = option_value(config, 'run_stage5', true);
run_v52_selection = option_value(config, 'run_v52_selection', false);
outputs = struct();
stage5_grid_table = [];
stage5_run_info = [];

if run_stage4
    stage4_config = option_value(config, 'stage4', struct());
    outputs.stage4 = stage4_run_v51_h2_reserve_grid(stage4_config);
end
if run_stage5
    stage5_config = option_value(config, 'stage5', struct());
    [stage5_grid_table, stage5_run_info] = ...
        stage5_run_v51_joint_grid(stage5_config);
    outputs.stage5 = stage5_grid_table;
    outputs.stage5_run_info = stage5_run_info;
end
if run_v52_selection
    selection_config = option_value(config, 'v52_selection', struct());
    outputs.v52_selection = run_v52_selection_audit( ...
        project_dir, stage5_grid_table, stage5_run_info, selection_config);
end

stage0_manifest("results", struct('project_dir', project_dir));
stage0_constraint_audit(struct('project_dir', project_dir));
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(fullfile(src_dir, 'utils'), '-begin');
project_dir = setup_project_paths(project_dir);
end

function selection_output = run_v52_selection_audit( ...
        project_dir, stage5_grid_table, stage5_run_info, config)
if nargin < 4 || isempty(config)
    config = struct();
end
if isempty(stage5_grid_table)
    grid_mat_path = option_value(config, 'grid_mat_path', ...
        fullfile(project_dir, 'runs', 'stage5', 'joint_grid', ...
        'v51_joint_grid_2024_latest.mat'));
    [stage5_grid_table, stage5_run_info] = load_stage5_grid(grid_mat_path);
else
    grid_mat_path = option_value(config, 'grid_mat_path', "");
end

[selected, audit_table, selection_info] = ...
    select_protocol_v52_candidate(stage5_grid_table, ...
    stage5_run_info, config);

save_output = option_value(config, 'save_output', true);
output_dir = option_value(config, 'output_dir', ...
    fullfile(project_dir, 'runs', 'stage2'));
selection_info.source_grid_mat_path = string(grid_mat_path);
selection_info.output_mat_path = "";
selection_info.output_csv_path = "";
if save_output
    ensure_directory(output_dir);
    output_base = sprintf('v52_selection_audit_%d_latest', ...
        selection_info.data_year);
    output_mat_path = fullfile(output_dir, [output_base, '.mat']);
    output_csv_path = fullfile(output_dir, [output_base, '.csv']);
    selection_info.output_mat_path = string(output_mat_path);
    selection_info.output_csv_path = string(output_csv_path);
    writetable(audit_table, output_csv_path);
    save(output_mat_path, 'selected', 'audit_table', 'selection_info');
end

selection_output = struct( ...
    'selected', selected, ...
    'audit_table', audit_table, ...
    'selection_info', selection_info);
end

function [grid_table, run_info] = load_stage5_grid(grid_mat_path)
if isstring(grid_mat_path) && isscalar(grid_mat_path)
    grid_mat_path = char(grid_mat_path);
end
if ~isfile(grid_mat_path)
    error('run_reproduce_full_grid:missing_stage5_grid', ...
        'Missing Stage 5 grid MAT file: %s', grid_mat_path);
end
loaded = load(grid_mat_path, 'grid_table', 'run_info');
if ~isfield(loaded, 'grid_table') || ~isfield(loaded, 'run_info')
    error('run_reproduce_full_grid:bad_stage5_grid', ...
        'Stage 5 grid MAT must contain grid_table and run_info.');
end
grid_table = loaded.grid_table;
run_info = loaded.run_info;
end

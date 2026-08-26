function outputs = run_reproduce_full_grid(config)
%RUN_REPRODUCE_FULL_GRID Recompute Stage 4 and Stage 5 grids.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
run_stage4 = option_value(config, 'run_stage4', true);
run_stage5 = option_value(config, 'run_stage5', true);
outputs = struct();

if run_stage4
    stage4_config = option_value(config, 'stage4', struct());
    outputs.stage4 = stage4_run_v51_h2_reserve_grid(stage4_config);
end
if run_stage5
    stage5_config = option_value(config, 'stage5', struct());
    outputs.stage5 = stage5_run_v51_joint_grid(stage5_config);
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

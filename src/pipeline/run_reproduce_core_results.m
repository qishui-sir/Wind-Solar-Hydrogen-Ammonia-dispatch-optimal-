function outputs = run_reproduce_core_results(config)
%RUN_REPRODUCE_CORE_RESULTS Recompute the core annual and contract results.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
data_year = option_value(config, 'data_year', 2022);

stage1_config = option_value(config, 'stage1', struct());
stage1_config.data_year = data_year;
stage1_config.save_output = true;
[stage1_result, stage1_run_info] = stage1_run_zhou_s2_baseline(stage1_config);

stage3_config = option_value(config, 'stage3', struct());
stage3_config.stage1_mat_path = char(stage1_run_info.output_path);
stage3_config.save_output = true;
[stage3_result, stage3_run_info, stage3_metrics] = ...
    stage3_run_v51_contract_closed_loop(stage3_config);

outputs = struct( ...
    'stage1_result', stage1_result, ...
    'stage1_run_info', stage1_run_info, ...
    'stage3_result', stage3_result, ...
    'stage3_run_info', stage3_run_info, ...
    'stage3_metrics', stage3_metrics);

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

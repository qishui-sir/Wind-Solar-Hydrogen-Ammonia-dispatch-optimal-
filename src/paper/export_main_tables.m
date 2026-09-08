function output_files = export_main_tables(config)
%EXPORT_MAIN_TABLES Export paper-ready tables from reproducibility manifests.

if nargin < 1 || isempty(config)
    config = struct();
end

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath'));
output_dir = option_value(config, 'output_dir', ...
    fullfile(project_dir, 'paper_outputs', 'tables'));
ensure_directory(output_dir);

manifest_path = fullfile(project_dir, 'runs', 'manifest', ...
    'results_manifest.csv');
if ~isfile(manifest_path)
    stage0_manifest("results", struct('project_dir', project_dir));
end

output_files = strings(0, 1);
manifest = readtable(manifest_path, 'TextType', 'string');
main_manifest_path = fullfile(output_dir, 'table_results_manifest.csv');
writetable(manifest, main_manifest_path);
output_files(end + 1, 1) = string(main_manifest_path);

comparison_files = dir(fullfile(project_dir, 'runs', 'stage5', '**', '*.csv'));
for file_index = 1:numel(comparison_files)
    source_path = fullfile(comparison_files(file_index).folder, ...
        comparison_files(file_index).name);
    target_path = fullfile(output_dir, comparison_files(file_index).name);
    copyfile(source_path, target_path);
    output_files(end + 1, 1) = string(target_path); %#ok<AGROW>
end
end

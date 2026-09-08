function output_files = export_main_figures(config)
%EXPORT_MAIN_FIGURES Collect existing reproducible figures for paper drafting.

if nargin < 1 || isempty(config)
    config = struct();
end

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'utils'), '-begin');
project_dir = setup_project_paths(mfilename('fullpath'));
output_dir = option_value(config, 'output_dir', ...
    fullfile(project_dir, 'paper_outputs', 'figures'));
ensure_directory(output_dir);

figure_sources = { ...
    fullfile(project_dir, 'data', 'renewables_ninja', ...
        'daily_PV_WT_power.png'), ...
    fullfile(project_dir, 'test', 'png', 'thermal.png'), ...
    fullfile(project_dir, 'test', 'png', 'daily_brokline.png'), ...
    fullfile(project_dir, 'test', 'png', 'ael_startup_sensitivity.png')};

output_files = strings(0, 1);
for index = 1:numel(figure_sources)
    source_path = figure_sources{index};
    if isfile(source_path)
        [~, name, ext] = fileparts(source_path);
        target_path = fullfile(output_dir, [name, ext]);
        copyfile(source_path, target_path);
        output_files(end + 1, 1) = string(target_path); %#ok<AGROW>
    end
end
end

parameter_set = params();
ael_output = qi_ael_model(2000, 0, parameter_set);

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
config.data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
renewable_data = load_res_7day(config);

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
addpath(params_dir);

config = my_system('s2');
ael_output = qi_ael_model(2000, 0, config.AEL);

renewable_config.data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
renewable_data = load_res_7day(renewable_config);

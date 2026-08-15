clear;clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
addpath(params_dir);

data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);

params = my_system('s2');
ael_output = qi_ael_model(2000, 0, params.AEL.detail);

results = baseline(params,renewable_data);
%% 
% figure_total(params,results);

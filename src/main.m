clear;clc;

source_dir = fileparts(mfilename('fullpath'));
addpath(source_dir);
addpath(fullfile(source_dir, 'params'));
addpath(fullfile(source_dir, 'results'));
addpath(fullfile(source_dir, 'protocol'));

data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);

params = my_system('s2');
params.AEL.common.startup = true;

results = baseline(params, renewable_data);
%% 
% figure_total(params,results);

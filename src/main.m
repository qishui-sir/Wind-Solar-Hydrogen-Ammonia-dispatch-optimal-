clear;clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
results_dir = fullfile(source_dir, 'results');
class_dir = fullfile(source_dir, 'class');
addpath(source_dir, params_dir, results_dir, class_dir);

data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);

params = my_system('s2');
params.AEL.common.startup = true;   % S2 baseline with the S3 startup electricity
params.solver.relative_gap = 0.02;

ael_output = qi_ael_model(2000, 0, params.AEL.detail); 

fprintf('[main] AEL startup electricity=%d (%.2f load fraction/h), no extra charge\n', ...
    params.AEL.common.startup, params.AEL.common.startup_elec);
fprintf('[main] solver gap=%.4f\n', params.solver.relative_gap);

results = baseline(params, renewable_data);
%% 
% figure_total(params,results);

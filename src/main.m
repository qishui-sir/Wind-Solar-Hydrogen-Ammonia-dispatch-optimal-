clear;clc;

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
params_dir = fullfile(source_dir, 'params');
results_dir = fullfile(source_dir, 'results');
class_dir = fullfile(source_dir, 'class');

% Path setup: add the project's own folders. 'src' itself is the working folder
% when main.m is run normally, but add it explicitly so running from anywhere is
% safe.
addpath(source_dir, params_dir, results_dir, class_dir);

data_cfg = struct();
data_cfg.pv_year = 2022;
data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000;
data_cfg.pw_capacity_kw = 200000;
renewable_data = load_res_year(data_cfg);

params = my_system('s2');
params.AEL.common.startup = true;                    % startup electricity
params.AEL.common.startup_penalty = 0.053;           % Zhou S3 penalty (USD/kWh)
params.solver.relative_gap = 1e-3;

ael_output = qi_ael_model(2000, 0, params.AEL.detail);

fprintf('[main] AEL startup=%d, startup penalty=%.4f USD/kWh\n', ...
    params.AEL.common.startup, params.AEL.common.startup_penalty);
fprintf('[main] solver gap=%.4f\n', params.solver.relative_gap);

results = baseline(params, renewable_data);
%% 
% figure_total(params,results);

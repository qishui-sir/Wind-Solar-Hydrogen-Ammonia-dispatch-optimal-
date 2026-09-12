% CHECK_STARTUP_PENALTY: fast comparison of the S3 startup penalty on a short horizon.
%
% Usage: check_startup_penalty(day_count, coefficients)
%   day_count     : horizon in days (default 3)
%   coefficients  : vector of startup-penalty coefficients (default [0 0.053 0.5])
%
% The first coefficient (0) reproduces S2: the penalty term is present but
% priced at zero. The rest show how the optimal start count responds. This is a
% diagnostic only; it does not modify any parameters on disk.

function check_startup_penalty(day_count, coefficients)
if nargin < 1 || isempty(day_count); day_count = 3; end
if nargin < 2 || isempty(coefficients); coefficients = [0, 0.053, 0.5]; end

source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

out_dir = fullfile(project_dir, 'results_out');
if ~isfolder(out_dir); mkdir(out_dir); end

data_cfg = struct();
data_cfg.pv_year = 2022; data_cfg.pw_year = 2022;
data_cfg.pv_capacity_kw = 200000; data_cfg.pw_capacity_kw = 200000;
data_cfg.day_count = day_count;
renewable_data = load_res_year(data_cfg);

fprintf('\n=== startup-penalty check: %d days (%d h) ===\n', ...
    day_count, renewable_data.time_count);

rows = cell(numel(coefficients), 1);
for k = 1:numel(coefficients)
    c = coefficients(k);
    params = my_system('s3');
    params.AEL.common.startup_penalty = c;
    fprintf('\n--- coefficient = %.4f USD/kWh ---\n', c);

    results = baseline(params, renewable_data);
    d = results.dispatch;
    dN = diff([0; d.N_AEL(:)]);

    row = struct();
    row.coefficient = c;
    row.objective = results.fval;
    row.nh3_t = results.summary.NH3_prod_t_y;
    row.lcoa_usd_t = results.summary.lcoa;
    row.mod_units_started = sum(max(dN, 0));
    row.start_events = sum(dN > 0);
    row.units_stopped = sum(max(-dN, 0));
    row.startup_energy_mwh = results.summary.AEL_start_energy_kwh / 1000;
    row.startup_penalty_usd = results.cost.startup_penalty;
    row.mean_online = mean(d.N_AEL);
    row.min_online = min(d.N_AEL);
    row.max_online = max(d.N_AEL);
    row.ael_energy_gwh = sum(d.P_AEL) * params.time.step / 1e6;
    rows{k} = row;

    fprintf('started=%d (events=%d), penalty=%.0f USD, objective=%.0f\n', ...
        row.mod_units_started, row.start_events, row.startup_penalty_usd, row.objective);
end

T = struct2table([rows{:}]);
disp(T);
writetable(T, fullfile(out_dir, sprintf('startup_penalty_check_%dd.csv', day_count)));

fprintf('\n--- start count vs coefficient ---\n');
for k = 1:height(T)
    fprintf('  c=%-7.4f  started=%-6d  events=%-5d  obj=%.0f  penalty=%.0f USD\n', ...
        T.coefficient(k), T.mod_units_started(k), T.start_events(k), ...
        T.objective(k), T.startup_penalty_usd(k));
end
end

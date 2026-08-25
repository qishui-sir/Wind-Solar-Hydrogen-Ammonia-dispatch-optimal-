function [result, run_info] = stage1_run_zhou_s2_baseline(config)
%STAGE1_RUN_ZHOU_S2_BASELINE Run or prepare the annual Zhou S2 baseline.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = project_root();
add_project_paths(project_dir);

dry_run = option_value(config, 'dry_run', false);
save_output = option_value(config, 'save_output', true);
scenario_id = option_value(config, 'scenario_id', 's2');
data_year = option_value(config, 'data_year', 2022);
run_dir = option_value(config, 'run_dir', ...
    fullfile(project_dir, 'runs', 'stage1'));

data_config = option_value(config, 'data', struct());
if ~isfield(data_config, 'pv_year')
    data_config.pv_year = data_year;
end
if ~isfield(data_config, 'pw_year')
    data_config.pw_year = data_year;
end
if ~isfield(data_config, 'pv_capacity_kw')
    data_config.pv_capacity_kw = 200000;
end
if ~isfield(data_config, 'pw_capacity_kw')
    data_config.pw_capacity_kw = 200000;
end

renewable_data = load_res_year(data_config);
params = my_system(scenario_id);
params.AEL.common.startup = true;

protocol_valid = protocol_v5('verify', protocol_v5());
manifest_valid = s2_baseline_manifest('verify', s2_baseline_manifest());

run_info = struct();
run_info.stage = "stage1";
run_info.status = "ready";
run_info.executed_at = string(datetime('now', 'TimeZone', 'local'));
run_info.project_dir = string(project_dir);
run_info.scenario_id = string(scenario_id);
run_info.model_variant = "Zhou_S2_capacity_with_S3_startup_electricity";
run_info.data_year = data_year;
run_info.renewable_time_count = renewable_data.time_count;
run_info.protocol_valid = protocol_valid;
run_info.manifest_valid = manifest_valid;
run_info.params = params;
run_info.output_path = "";
run_info.solver_log = "";
run_info.checks = struct();

if renewable_data.time_count ~= params.time.hour_year
    error('stage1_run_zhou_s2_baseline:bad_horizon', ...
        'Expected %d annual hours, got %d.', ...
        params.time.hour_year, renewable_data.time_count);
end
if ~protocol_valid || ~manifest_valid
    error('stage1_run_zhou_s2_baseline:bad_freeze', ...
        'Protocol v5 or S2 manifest verification failed.');
end

result = [];
if dry_run
    return
end

solver_log = evalc('result = baseline(params, renewable_data);');
run_info.solver_log = string(solver_log);
run_info.checks = validate_stage1_result(params, renewable_data, result);
run_info.status = "solved";

if ~run_info.checks.passed
    error('stage1_run_zhou_s2_baseline:failed_checks', ...
        'Stage 1 baseline solved but failed invariant checks.');
end

if save_output
    if ~isfolder(run_dir)
        mkdir(run_dir);
    end
    output_path = fullfile(run_dir, ...
        sprintf('zhou_s2_baseline_%d_latest.mat', data_year));
    run_info.output_path = string(output_path);
    save(output_path, 'result', 'run_info', 'params', 'renewable_data');
end
end

function checks = validate_stage1_result(params, renewable_data, result)
tol_power = 1e-3;
tol_mass = 1e-3;

dispatch = result.dispatch;
storage = dispatch.storage_H2(:);
ael_count = round(dispatch.N_AEL(:));
ael_power = dispatch.P_AEL(:);
hb_load = dispatch.HB_load(:);

ael_lower_violation = max([0; ...
    params.AEL.common.min_load * ael_count * ...
    params.AEL.common.module_power - ael_power]);
ael_upper_violation = max([0; ...
    ael_power - params.AEL.common.max_load * ael_count * ...
    params.AEL.common.module_power]);
hb_lower_violation = max([0; params.HB.min_load - hb_load]);
hb_upper_violation = max([0; hb_load - params.HB.max_load]);
hb_ramp_violation = max([0; abs(diff(hb_load)) - params.HB.ramp_rate]);
storage_lower_violation = max([0; params.h2_storage.min_mass - storage]);
storage_upper_violation = max([0; storage - params.h2_storage.mass]);

co2_lhs = params.environment.grid_co2 * result.summary.purchase_kwh;
co2_rhs = params.environment.co2_limit * result.summary.NH3_prod_kg;

checks = struct();
checks.exitflag_ok = result.exitflag > 0;
checks.annual_hours_ok = renewable_data.time_count == params.time.hour_year;
checks.nh3_positive = result.summary.NH3_prod_t_y > 0;
checks.power_balance_ok = result.check.max_power_residual_kw <= tol_power;
checks.storage_balance_ok = result.check.max_storage_residual_kg <= tol_mass;
checks.initial_storage_ok = abs(storage(1) - ...
    params.h2_storage.initial_mass) <= tol_mass;
checks.terminal_storage_ok = abs(storage(end) - ...
    params.h2_storage.initial_mass) <= tol_mass;
checks.storage_bounds_ok = max(storage_lower_violation, ...
    storage_upper_violation) <= tol_mass;
checks.ael_bounds_ok = max(ael_lower_violation, ...
    ael_upper_violation) <= tol_power;
checks.hb_bounds_ok = max(hb_lower_violation, ...
    hb_upper_violation) <= 1e-8;
checks.hb_ramp_ok = hb_ramp_violation <= 1e-8;
checks.co2_ok = ~params.environment.co2_enabled || ...
    co2_lhs <= co2_rhs + 1e-6;
checks.buy_sell_overlap_ok = result.check.buy_sell_overlap_kwh <= 1e-6;

checks.max_ael_lower_violation_kw = ael_lower_violation;
checks.max_ael_upper_violation_kw = ael_upper_violation;
checks.max_hb_ramp_violation = hb_ramp_violation;
checks.max_storage_lower_violation_kg = storage_lower_violation;
checks.max_storage_upper_violation_kg = storage_upper_violation;
checks.co2_lhs = co2_lhs;
checks.co2_rhs = co2_rhs;

checks.passed = checks.exitflag_ok && checks.annual_hours_ok && ...
    checks.nh3_positive && checks.power_balance_ok && ...
    checks.storage_balance_ok && checks.initial_storage_ok && ...
    checks.terminal_storage_ok && checks.storage_bounds_ok && ...
    checks.ael_bounds_ok && checks.hb_bounds_ok && checks.hb_ramp_ok && ...
    checks.co2_ok && checks.buy_sell_overlap_ok;
end

function project_dir = project_root()
src_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(src_dir);
end

function add_project_paths(project_dir)
addpath(fullfile(project_dir, 'src'));
addpath(fullfile(project_dir, 'src', 'params'));
addpath(fullfile(project_dir, 'src', 'results'));
addpath(fullfile(project_dir, 'src', 'protocol'));
end

function value = option_value(config, name, default_value)
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
else
    value = default_value;
end
end

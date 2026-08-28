function [grid_table, run_info] = run_stage5_parallel(config)
%RUN_STAGE5_PARALLEL Parallel Stage 5 joint grid using parfor over candidates.
%
%   [grid_table, run_info] = run_stage5_parallel(config)
%
% Same candidate grid as stage5_run_v51_joint_grid, but candidates run in
% parallel with parfor (Parallel Computing Toolbox). Each candidate is fully
% independent, so wall-clock time is roughly (num_candidates / num_workers)
% times the single-candidate cost. Already-computed candidates are skipped
% (resume), so a restart never redoes finished work.
%
% config fields (same as stage5_run_v51_joint_grid plus):
%   num_workers   parpool worker count (default: existing pool or auto)

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = setup_project_paths(mfilename('fullpath'));
subprotocol = protocol_v5('v5_1');
if ~protocol_v5('verify_v5_1', subprotocol)
    error('run_stage5_parallel:bad_protocol', ...
        'Protocol v5.1 verification failed.');
end

source_mat_path = option_value(config, 'source_mat_path', ...
    fullfile(project_dir, 'runs', 'stage1', ...
    'zhou_s2_baseline_2022_latest.mat'));
baseline_mat_path = option_value(config, 'baseline_mat_path', ...
    fullfile(project_dir, 'runs', 'rolling', ...
    'v51_contract_plan_and_hb_smoothing_2022_latest.mat'));
output_dir = option_value(config, 'output_dir', ...
    fullfile(project_dir, 'runs', 'stage5', 'joint_grid'));
rolling_output_dir = option_value(config, 'rolling_output_dir', ...
    fullfile(output_dir, 'rolling'));
save_output = option_value(config, 'save_output', true);
verbose = option_value(config, 'verbose', true);

forecast_mode = string(option_value(config, 'forecast_mode', ...
    "observed_oracle"));
gate_mode = string(option_value(config, 'h2_reserve_gate_mode', ...
    "contract_carbon_state_gate"));
soft_reserve = option_value(config, 'h2_reserve_soft', true);
allow_infeasible = option_value(config, ...
    'allow_infeasible_continuation', true);
restoration_penalty = option_value(config, ...
    'restoration_slack_penalty_usd_per_kg', 1e6);
resume = option_value(config, 'resume', true);
num_workers = option_value(config, 'num_workers', 0);

source_year_value = source_year_from_mat(source_mat_path);

reserve_designs = create_reserve_designs( ...
    option_value(config, 'reserve_quantiles', ...
    [0, subprotocol.Calibration.CandidateGrid.ReserveQuantile]), ...
    option_value(config, 'reserve_lookahead_days', ...
    subprotocol.Calibration.CandidateGrid.ReserveLookaheadDays));
pacing_values = option_value(config, ...
    'contract_pacing_aggressiveness', [0, 0.25, 0.50]);
smoothing_values = option_value(config, ...
    'hb_smoothing_reduction_fraction', ...
    subprotocol.Calibration.CandidateGrid.HBSmoothingTargetReductionFraction);

specs = build_candidate_specs( ...
    reserve_designs, pacing_values, smoothing_values);
specs = attach_candidate_year(specs, source_year_value);
candidate_limit = option_value(config, 'candidate_limit', Inf);
if isfinite(candidate_limit) && candidate_limit < numel(specs)
    specs = specs(1:candidate_limit);
end

% forecast fallback for non-development-year persistence runs
fallback = [];
if forecast_mode == "simulated_persistence" && ...
        ~ismember(source_year_value, subprotocol.DataSplit.DevelopmentYears)
    fallback = build_development_forecast_fallback();
end

if num_workers > 0
    pool = gcp('nocreate');
    if isempty(pool) || pool.NumWorkers < num_workers
        delete(gcp('nocreate'));
        parpool(num_workers);
    end
end

if verbose
    fprintf('Running %d candidates (year %d, %s)...\n', ...
        numel(specs), source_year_value, forecast_mode);
end

rows = cell(numel(specs), 1);
parfor candidate_index = 1:numel(specs)
    rows{candidate_index} = run_one_candidate( ...
        specs(candidate_index), source_year_value, source_mat_path, ...
        forecast_mode, gate_mode, soft_reserve, allow_infeasible, ...
        restoration_penalty, rolling_output_dir, resume, fallback);
end

rows = rows(~cellfun(@isempty, rows));
if ~isempty(rows)
    rows = vertcat(rows{:});
end

include_baseline = option_value(config, 'include_baseline', true);
if include_baseline
    baseline = baseline_row(baseline_mat_path);
    if isempty(rows)
        rows = baseline;
    else
        rows = [baseline; rows];
    end
end

grid_table = struct2table(rows);
run_info = struct( ...
    'stage', "stage5_parallel", ...
    'status', "completed", ...
    'executed_at', string(datetime('now')), ...
    'protocol_version', subprotocol.ProtocolVersion, ...
    'protocol_seal', subprotocol.Seal, ...
    'source_mat_path', string(source_mat_path), ...
    'baseline_mat_path', string(baseline_mat_path), ...
    'data_year', source_year_value, ...
    'scheme', "contract_plan_and_hb_smoothing", ...
    'forecast_mode', forecast_mode, ...
    'h2_reserve_gate_mode', gate_mode, ...
    'h2_reserve_soft', soft_reserve, ...
    'candidate_count', numel(specs), ...
    'selected_candidate', select_candidate(grid_table), ...
    'output_path', "");

if save_output
    ensure_directory(output_dir);
    output_path = fullfile(output_dir, sprintf( ...
        'v51_joint_grid_%d_latest.mat', source_year_value));
    run_info.output_path = string(output_path);
    save(output_path, 'grid_table', 'run_info', 'subprotocol');
end

if nargout == 0
    disp(grid_table);
    disp(run_info.selected_candidate);
end
end

function row = run_one_candidate(spec, data_year, source_mat_path, ...
        forecast_mode, gate_mode, soft_reserve, allow_infeasible, ...
        restoration_penalty, rolling_output_dir, resume, fallback)
row = empty_grid_row();
row.case_id = spec.case_id;
row.h2_reserve_quantile = spec.quantile;
row.h2_reserve_lookahead_days = spec.lookahead_days;
row.contract_pacing_aggressiveness = spec.pacing;
row.hb_smoothing_reduction_fraction = spec.smoothing;
row.h2_reserve_gate_mode = gate_mode;
row.h2_reserve_soft = soft_reserve;
row.is_baseline = false;

candidate_path = candidate_rolling_path( ...
    rolling_output_dir, data_year, spec, gate_mode, soft_reserve);
if resume && isfile(candidate_path)
    try
        loaded = load(candidate_path, 'result', 'run_info', 'metrics');
        if is_completed_candidate_mat( ...
                loaded, data_year, forecast_mode)
            row = completed_row(row, loaded.result, loaded.run_info, ...
                loaded.metrics);
            return
        end
    catch
    end
end

rolling_config = struct( ...
    'source_mat_path', source_mat_path, ...
    'scheme', "contract_plan_and_hb_smoothing", ...
    'forecast_mode', forecast_mode, ...
    'h2_reserve_quantile', spec.quantile, ...
    'h2_reserve_lookahead_days', spec.lookahead_days, ...
    'h2_reserve_soft', soft_reserve, ...
    'h2_reserve_gate_mode', gate_mode, ...
    'contract_pacing_aggressiveness', spec.pacing, ...
    'hb_smoothing_reduction_fraction', spec.smoothing, ...
    'allow_infeasible_continuation', allow_infeasible, ...
    'restoration_slack_penalty_usd_per_kg', restoration_penalty, ...
    'output_dir', rolling_output_dir, ...
    'save_output', true, ...
    'verbose', false, ...
    'solver_display', 'none');
if ~isempty(fallback)
    rolling_config.forecast_fallback = fallback;
end

try
    [result, candidate_info, metrics] = rolling_dispatch(rolling_config);
    row = completed_row(row, result, candidate_info, metrics);
catch exception
    row.status = "failed";
    row.error_id = string(exception.identifier);
    row.error_message = string(exception.message);
end
end

function specs = build_candidate_specs(reserve_designs, pacing_values, ...
        smoothing_values)
pacing_values = pacing_values(:)';
smoothing_values = smoothing_values(:)';
count = numel(reserve_designs) * numel(pacing_values) * ...
    numel(smoothing_values);
specs = repmat(struct('case_id', "", 'quantile', NaN, 'lookahead_days', ...
    NaN, 'pacing', NaN, 'smoothing', NaN, 'year', NaN), count, 1);
index = 0;
for reserve_index = 1:numel(reserve_designs)
    reserve = reserve_designs(reserve_index);
    for pacing = pacing_values
        for smoothing = smoothing_values
            index = index + 1;
            specs(index).case_id = candidate_id( ...
                reserve.quantile, reserve.lookahead_days, ...
                pacing, smoothing);
            specs(index).quantile = reserve.quantile;
            specs(index).lookahead_days = reserve.lookahead_days;
            specs(index).pacing = pacing;
            specs(index).smoothing = smoothing;
        end
    end
end
end

function ok = is_completed_candidate_mat(loaded, data_year, forecast_mode)
ok = isstruct(loaded) && isfield(loaded, 'result') && ...
    isfield(loaded, 'run_info') && isfield(loaded, 'metrics');
if ~ok
    return
end
info = loaded.run_info;
ok = isfield(info, 'status') && string(info.status) == "completed" && ...
    isfield(info, 'data_year') && double(info.data_year) == data_year && ...
    isfield(info, 'forecast_mode') && ...
    string(info.forecast_mode) == forecast_mode;
end

function specs = attach_candidate_year(specs, data_year)
for index = 1:numel(specs)
    specs(index).year = data_year;
end
end

function designs = create_reserve_designs(quantiles, lookahead_days)
quantiles = unique(quantiles(:)', 'stable');
lookahead_days = unique(lookahead_days(:)', 'stable');
design_capacity = nnz(quantiles == 0) ...
    + nnz(quantiles ~= 0) * numel(lookahead_days);
designs = repmat(struct('quantile', NaN, 'lookahead_days', NaN), ...
    max(design_capacity, 1), 1);
design_count = 0;
for quantile = quantiles
    if quantile == 0
        design_count = design_count + 1;
        designs(design_count) = struct('quantile', 0, 'lookahead_days', 0);
        continue
    end
    for lookahead = lookahead_days
        design_count = design_count + 1;
        designs(design_count) = struct( ...
            'quantile', quantile, 'lookahead_days', lookahead);
    end
end
designs = designs(1:design_count);
end

function id = candidate_id(quantile, lookahead, pacing, smoothing)
id = string(sprintf('joint_h2q%03d_l%d_cp%03d_hb%03d', ...
    round(100 * quantile), lookahead, round(100 * pacing), ...
    round(100 * smoothing)));
end

function path = candidate_rolling_path(output_dir, data_year, spec, ...
        gate_mode, soft_reserve)
tag = "v51_contract_plan_and_hb_smoothing";
if spec.quantile > 0
    tag = sprintf('%s_h2q%03d_l%d', tag, ...
        round(100 * spec.quantile), spec.lookahead_days);
    if soft_reserve
        tag = sprintf('%s_soft', tag);
    end
end
if spec.pacing > 0
    tag = sprintf('%s_cp%03d', tag, round(100 * spec.pacing));
end
if spec.smoothing > 0
    tag = sprintf('%s_hb%03d', tag, round(100 * spec.smoothing));
end
if gate_mode ~= "off"
    tag = sprintf('%s_gate', tag);
end
path = fullfile(output_dir, sprintf('%s_%d_latest.mat', tag, data_year));
end

function row = empty_grid_row()
row = struct( ...
    'case_id', "", ...
    'status', "", ...
    'is_baseline', false, ...
    'h2_reserve_quantile', NaN, ...
    'h2_reserve_lookahead_days', NaN, ...
    'h2_reserve_gate_mode', "", ...
    'h2_reserve_soft', false, ...
    'contract_pacing_aggressiveness', NaN, ...
    'hb_smoothing_reduction_fraction', NaN, ...
    'h2_reserve_mean_applied_scale', NaN, ...
    'h2_reserve_min_applied_scale', NaN, ...
    'h2_reserve_projected_days', NaN, ...
    'h2_reserve_gate_closed_days', NaN, ...
    'restoration_day_count', NaN, ...
    'expired_contract_kg', NaN, ...
    'completed_days', NaN, ...
    'expected_days', NaN, ...
    'NH3_t_y', NaN, ...
    'LCOA_USD_t', NaN, ...
    'net_profit_MUSD', NaN, ...
    'contract_shortfall_p95_kg', NaN, ...
    'MAR', NaN, ...
    'h2_soc_p05', NaN, ...
    'max_backlog_kg', NaN, ...
    'terminal_backlog_kg', NaN, ...
    'co2_kg_per_kg', NaN, ...
    'purchase_rate', NaN, ...
    'sell_rate', NaN, ...
    'curtail_rate', NaN, ...
    'AEL_startup_count', NaN, ...
    'strict_delivery_ok', false, ...
    'terminal_contract_ok', false, ...
    'annual_output_ok', false, ...
    'terminal_h2_ok', false, ...
    'annual_co2_ok', false, ...
    'annual_sell_ok', false, ...
    'annual_curtail_ok', false, ...
    'lcoa_cap_ok', false, ...
    'output_path', "", ...
    'error_id', "", ...
    'error_message', "");
end

function row = completed_row(row, result, candidate_info, metrics)
row.status = string(candidate_info.status);
if isfield(candidate_info, 'day_count')
    row.completed_days = candidate_info.day_count;
    row.expected_days = candidate_info.day_count;
end
if isfield(candidate_info, 'production_pacing_history') && ...
        isfield(candidate_info.production_pacing_history, ...
        'h2_reserve_applied_scale')
    history = candidate_info.production_pacing_history;
    scales = history.h2_reserve_applied_scale;
    projected = history.h2_reserve_projected;
    row.h2_reserve_mean_applied_scale = mean(scales, 'omitnan');
    row.h2_reserve_min_applied_scale = min(scales, [], 'omitnan');
    row.h2_reserve_projected_days = nnz(projected);
    if isfield(history, 'h2_reserve_gate_open')
        row.h2_reserve_gate_closed_days = nnz(~history.h2_reserve_gate_open);
    end
    if isfield(history, 'day_ahead_restored')
        row.restoration_day_count = nnz(history.day_ahead_restored);
    end
    if isfield(history, 'expired_contract_kg')
        row.expired_contract_kg = sum(history.expired_contract_kg, 'omitnan');
    end
end
row.NH3_t_y = result.summary.NH3_prod_t_y;
row.LCOA_USD_t = result.summary.lcoa;
row.net_profit_MUSD = result.summary.net_profit / 1e6;
row.contract_shortfall_p95_kg = metrics.Primary.contract_shortfall_p95;
row.MAR = metrics.Primary.mar;
row.h2_soc_p05 = metrics.Primary.h2_soc_p05;
row.max_backlog_kg = metrics.Contract.maximum_backlog_kg;
row.terminal_backlog_kg = metrics.Contract.terminal_backlog_kg;
row.co2_kg_per_kg = result.summary.co2_intensity;
row.purchase_rate = result.summary.purchase_rate;
row.sell_rate = result.summary.sell_rate;
row.curtail_rate = result.summary.curtail_rate;
row.AEL_startup_count = result.summary.AEL_startup_count;
row.strict_delivery_ok = metrics.Feasibility.strict_delivery_ok;
row.terminal_contract_ok = metrics.Feasibility.terminal_contract_ok;
row.annual_output_ok = metrics.Feasibility.annual_output_ok;
row.terminal_h2_ok = metrics.Feasibility.terminal_h2_ok;
row.annual_co2_ok = metrics.Feasibility.annual_co2_ok;
row.annual_sell_ok = metrics.Feasibility.annual_sell_ok;
row.annual_curtail_ok = metrics.Feasibility.annual_curtail_ok;
row.lcoa_cap_ok = metrics.Feasibility.lcoa_cap_ok;
row.output_path = string(candidate_info.output_path);
end

function row = baseline_row(mat_path)
if ~isfile(mat_path)
    error('run_stage5_parallel:missing_baseline', ...
        'Missing baseline rolling result: %s', mat_path);
end
loaded = load(mat_path, 'result', 'run_info', 'metrics');
row = empty_grid_row();
row.case_id = "baseline_joint_reference";
row.h2_reserve_quantile = 0;
row.h2_reserve_lookahead_days = 0;
row.h2_reserve_gate_mode = "off";
row.h2_reserve_soft = false;
row.contract_pacing_aggressiveness = 0;
row.hb_smoothing_reduction_fraction = 0;
row.is_baseline = true;
row = completed_row(row, loaded.result, loaded.run_info, loaded.metrics);
end

function selected = select_candidate(grid_table)
feasible = grid_table.status == "completed" ...
    & grid_table.strict_delivery_ok ...
    & grid_table.terminal_contract_ok ...
    & grid_table.annual_output_ok ...
    & grid_table.terminal_h2_ok ...
    & grid_table.annual_co2_ok ...
    & grid_table.annual_sell_ok ...
    & grid_table.annual_curtail_ok ...
    & grid_table.lcoa_cap_ok;
if ~any(feasible)
    selected = struct('status', "no_feasible_candidate");
    return
end
candidates = grid_table(feasible, :);
candidates.h2_soc_p05_sort = -candidates.h2_soc_p05;
candidates = sortrows(candidates, { ...
    'contract_shortfall_p95_kg', 'MAR', 'h2_soc_p05_sort', 'LCOA_USD_t'});
selected = table2struct(candidates(1, :), 'ToScalar', true);
selected = rmfield(selected, 'h2_soc_p05_sort');
end

function year_value = source_year_from_mat(source_mat_path)
loaded = load(source_mat_path, 'run_info', 'renewable_data');
if isfield(loaded, 'run_info') && isfield(loaded.run_info, 'data_year')
    year_value = loaded.run_info.data_year;
elseif isfield(loaded, 'renewable_data') && ...
        isfield(loaded.renewable_data, 'time') && ...
        isdatetime(loaded.renewable_data.time)
    year_value = year(loaded.renewable_data.time(1));
else
    error('run_stage5_parallel:missing_year', ...
        'Input MAT must provide run_info.data_year or datetime values.');
end
end

function study = O1(model, config)
%O1 先求参考经济调度，再严格识别经济允许的最小HB设定值更新次数。
% Kfea模块独立保留；默认只读取已有物理证据，不执行可行性搜索。
arguments
    model (1, 1) struct
    config (1, 1) struct
end
config = validate_config(config);
ctx = build_context(model, config);
ctx.services = struct('fixed_point_store', @fixed_point_store, ...
    'solve_problem', @solve_problem, 'build_fixed_solver', @build_fixed_solver, ...
    'recover_direction_binaries', @recover_direction_binaries, ...
    'migrate_cost_record', @migrate_cost_record, ...
    'add_change_indicators', @add_change_indicators, ...
    'evaluate_cost_components', @evaluate_cost_components, ...
    'evaluate_operation_metrics', @evaluate_operation_metrics, ...
    'save_reference', @save_reference);
fprintf('\n[O1] Stage 1: economic reference\n');
reference = load_or_solve_reference(ctx);
study = struct('method', 'certified_economic_update_threshold', ...
    'definition', ['Number of cyclic HB set-point updates with the ', ...
    'configured tracking band; economic loss relative to the true reference optimum.'], ...
    'config', config, 'reference', reference, 'feasibility', struct(), ...
    'economic', struct(), 'Kref', NaN, 'Keco', NaN, 'check', struct());
if ~reference.has_incumbent
    study.status = 'incomplete_reference_no_incumbent';
    print_summary(study);
    return
end
reference.solution = add_change_indicators(reference.solution, ctx);
reference.count_upper = round(sum(reference.solution.O1_HB_change));
reference.objective_upper = evaluate(ctx.system_cost_usd, reference.solution);
reference.system_cost_upper = reference.objective_upper;
reference.cost_components = evaluate_cost_components(reference.solution, ctx);
reference.operation_metrics = evaluate_operation_metrics(reference.solution, ctx);
p = ctx.problem;
p.Objective = ctx.system_cost_usd;
p.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
[ctx.cost_solver, build_elapsed] = build_fixed_solver(p, ctx, reference.solution);
if config.defer_feasibility_search
    fprintf('[O1] Kfea搜索暂缓：仅读取同模型缓存证据。\n');
    [feasibility, ~, ~] = load_deferred_feasibility(ctx, reference);
else
    [feasibility, ~, ~] = O1Feasibility(ctx, reference.solution, Inf, "feasibility");
end
study.feasibility = feasibility;
outputs = O1Economics(ctx, feasibility, reference);
study.reference = outputs.reference;
study.economic = outputs.boundaries;
study.threshold_state = outputs.state;
study.cost_certification = outputs.certification;
study.Kref = outputs.reference.count_upper;
study.Keco = outputs.boundaries.Keco;
study.search = struct('method', "threshold_identification", ...
    'solver_model_build_count', 1, 'solver_model_build_time_s', build_elapsed, ...
    'points', outputs.certification);
study.check.reference = solution_check(outputs.reference.solution, ctx);
if outputs.representative.has_incumbent && ...
        ~isempty(fieldnames(outputs.representative.solution))
    study.check.economic_witness = solution_check(outputs.representative.solution, ctx);
end
if study.economic.is_proven
    study.status = 'complete_economic_threshold';
else
    study.status = char(outputs.state.stop_reason);
end
print_summary(study);
end

function [summary, points, info] = load_deferred_feasibility(ctx, reference)
% 84等下界来自相同数据及物理参数签名的证书，不能硬编码到其他算例。
entries = struct('mode', {}, 'cost_cap', {}, 'K', {}, 'record', {}, 'source', {});
if ctx.config.use_cache
    entries = ctx.services.fixed_point_store(ctx.point_cache_file, ...
        ctx.signature, "load", "feasibility", Inf, struct());
    for signature = {ctx.signature, ctx.cost_signature}
        costs = ctx.services.fixed_point_store(ctx.point_cache_file, ...
            signature{1}, "load", "frontier_cost", Inf, struct());
        entries = [entries, costs]; %#ok<AGROW>
    end
end
lower = 0;
initial = reference.solution;
upper = reference.count_upper;
validation_solver = ctx.cost_solver;
validation_builds = 0;
validation_elapsed = 0;
for i = 1:numel(entries)
    r = entries(i).record;
    if string(entries(i).mode) == "feasibility"
        if isfield(r, 'objective_kind') && string(r.objective_kind) == "count" && ...
                isfield(r, 'count_lower') && isfinite(r.count_lower)
            lower = max(lower, ceil(r.count_lower));
        end
        if r.is_infeasible && entries(i).K <= ctx.T
            lower = max(lower, entries(i).K + 1);
        end
    end
    if ~r.has_incumbent || ~isfield(r, 'solution') || ...
            isempty(fieldnames(r.solution))
        continue
    end
    candidate = ctx.services.add_change_indicators(r.solution, ctx);
    count = round(sum(candidate.O1_HB_change));
    if count >= upper
        continue
    end
    if isempty(fieldnames(validation_solver))
        p = ctx.problem;
        p.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
        [validation_solver, validation_elapsed] = ...
            ctx.services.build_fixed_solver(p, ctx, initial);
        validation_builds = 1;
    end
    vector = validation_solver.problem.x0(:);
    names = fieldnames(validation_solver.indices);
    for j = 1:numel(names)
        vector(validation_solver.indices.(names{j})(:)) = candidate.(names{j})(:);
    end
    p = validation_solver.problem;
    violation = max([0; p.Aineq * vector - p.bineq(:); ...
        abs(p.Aeq * vector - p.beq(:)); p.lb(:) - vector; vector - p.ub(:)]);
    integer_error = max([0; abs(vector(p.intcon) - round(vector(p.intcon)))]);
    if violation <= ctx.model.options.ConstraintTolerance && integer_error <= 1e-6
        initial = candidate;
        upper = count;
    end
end
if lower > upper
    error('O1:inconsistent_count_cache', '缓存次数下界超过已验证可行上界。');
end
minimum = struct('objective_kind', "count", 'has_incumbent', true, ...
    'objective_lower', lower, 'objective_upper', upper, ...
    'count_lower', lower, 'count_upper', upper, 'absolute_gap', upper - lower, ...
    'relative_gap', (upper - lower) / max(1, upper), 'is_proven', lower == upper, ...
    'solution', initial, 'status', "deferred_cached_bounds");
cost_seed = reference;
cost_seed.solution = initial;
cost_seed.count_upper = upper;
cost_seed.objective_upper = evaluate(ctx.system_cost_usd, initial);
cost_seed.system_cost_upper = cost_seed.objective_upper;
cost_seed.cost_components = evaluate_cost_components(initial, ctx);
cost_seed.operation_metrics = evaluate_operation_metrics(initial, ctx);
summary = struct('minimum_updates', minimum, 'minimum_cost_at_upper_bound', cost_seed, ...
    'K_lower', lower, 'K_upper', upper, 'bound_width', upper - lower, ...
    'is_proven', lower == upper, 'deferred', true, ...
    'scheduler', struct('autonomous', false, 'elapsed_s', 0, 'budget_exhausted', false));
points = table();
info = struct('seed_validation_model_build_count', validation_builds, ...
    'elapsed_s', validation_elapsed);
fprintf('[O1] 保留次数区间[%g, %g]；不求解最小可行次数。\n', lower, upper);
end

function config = validate_config(config)
defaults = struct('nh3_target_t', 80000, 'economic_delta_usd_t', 0.5, ...
    'defer_feasibility_search', true, 'economics_solver', 'intlinprog', ...
    'economic_cap_time_s', 600, 'economic_fixed_time_s', 600, ...
    'economic_retry_time_s', 1800, 'economic_max_attempts', 4, ...
    'economic_lp_time_s', 30, 'economic_stalled_cap_time_s', 120, ...
    'economic_grid_simplify', true, 'economic_proof_mode', 'full', ...
    'economic_structural_search', false, 'economic_block_lengths_h', [96,192,384,768], ...
    'economic_block_budget_s', 3600, 'economic_block_round_time_s', 900, ...
    'economic_block_lp_time_s', 120, 'economic_block_time_s', 10, ...
    'economic_block_max_time_s', 60, 'economic_block_batch', 8, 'economic_block_max_cuts', 8192, ...
    'economic_decomposition_oracle_tolerance', 1, 'economic_decomposition_tolerance', 0.2, ...
    'economic_decomposition_stall_sweeps', 6, 'economic_decomposition_min_dual_sweeps', 8, ...
    'economic_local_time_s', 90, 'economic_local_passes', 3, ...
    'economic_final_interval', 20, 'economic_certification_time_s', 1800, ...
    'economic_certification_reserve_s', 1800, 'economic_certification_retry_gain', 1, ...
    'economic_points_per_round', 4, 'economic_max_solves_per_run', 64, ...
    'economic_run_budget_s', Inf, 'economic_reference_time_s', 600, ...
    'economic_reference_max_refinements', 3, ...
    'economic_reference_tolerance_usd_t', 0.001, 'economic_scale_solver', true, ...
    'gurobi_matlab_directory', '', 'gurobi_mip_focus', -1, ...
    'gurobi_method', -1, 'gurobi_threads', 0, ...
    'max_time_s', 1200, 'cost_relative_gap', 1e-3, ...
    'count_max_time_s', 900, 'fixed_max_time_s', 600, ...
    'count_absolute_gap', 0.99, 'change_epsilon', 0.01, 'change_tolerance', 1e-6, ...
    'max_k_search_points', 16, 'feasibility_probe_k', [], ...
    'autonomous_search', false, 'run_budget_s', Inf, 'max_k_attempts_per_source', 2, ...
    'enable_window_cuts', false, 'window_lengths_h', [72, 168], ...
    'window_candidates_per_length', 2, 'max_window_cuts', 4, 'window_lp_max_time_s', 45, ...
    'enable_start_repair', true, 'repair_max_time_s', 300, ...
    'use_cache', true, 'cache_directory', '', 'progress_file', '', 'display', 'off');
unknown = setdiff(fieldnames(config), fieldnames(defaults));
if ~isempty(unknown)
    error('O1:unknown_config', 'Unknown O1 option: %s.', unknown{1});
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(config, names{i}) || isempty(config.(names{i}))
        config.(names{i}) = defaults.(names{i});
    end
end
positive = {'nh3_target_t', 'max_time_s', 'count_max_time_s', 'fixed_max_time_s', ...
    'economic_cap_time_s', 'economic_fixed_time_s', 'economic_retry_time_s', ...
    'economic_lp_time_s', 'economic_stalled_cap_time_s', ...
    'economic_block_budget_s','economic_block_round_time_s','economic_block_lp_time_s', ...
    'economic_block_time_s','economic_block_max_time_s', ...
    'economic_decomposition_oracle_tolerance','economic_decomposition_tolerance', ...
    'economic_certification_reserve_s','economic_certification_retry_gain', ...
    'economic_local_time_s','economic_certification_time_s', ...
    'economic_reference_time_s', 'economic_reference_tolerance_usd_t', ...
    'window_lp_max_time_s', 'repair_max_time_s'};
for i = 1:numel(positive)
    validateattributes(config.(positive{i}), {'numeric'}, {'scalar','real','positive','finite'});
end
validateattributes(config.economic_delta_usd_t, {'numeric'}, {'scalar','real','nonnegative','finite'});
integers = {'economic_max_attempts','economic_points_per_round', ...
    'economic_block_batch','economic_block_max_cuts','economic_decomposition_stall_sweeps', ...
    'economic_decomposition_min_dual_sweeps', ...
    'economic_local_passes','economic_final_interval', ...
    'max_k_search_points','window_candidates_per_length','max_window_cuts', ...
    'economic_reference_max_refinements','max_k_attempts_per_source'};
for i = 1:numel(integers)
    validateattributes(config.(integers{i}), {'numeric'}, {'scalar','integer','nonnegative','finite'});
end
if config.economic_max_attempts < 1 || config.economic_points_per_round < 1
    error('O1:bad_attempts', '经济续算轮数及每轮候选数必须为正整数。');
end
validateattributes(config.economic_max_solves_per_run, {'numeric'}, {'scalar','positive'});
if isfinite(config.economic_max_solves_per_run) && ...
        config.economic_max_solves_per_run ~= round(config.economic_max_solves_per_run)
    error('O1:bad_solve_limit','economic_max_solves_per_run须为正整数或Inf。');
end
for name = {'run_budget_s','economic_run_budget_s'}
    validateattributes(config.(name{1}), {'numeric'}, {'scalar','real','positive'});
end
validateattributes(config.cost_relative_gap, {'numeric'}, {'scalar','>=',0,'<',1,'finite'});
validateattributes(config.count_absolute_gap, {'numeric'}, {'scalar','>=',0,'<',1,'finite'});
validateattributes(config.change_epsilon, {'numeric'}, {'scalar','nonnegative','finite'});
validateattributes(config.change_tolerance, {'numeric'}, {'scalar','nonnegative','finite'});
validateattributes(config.feasibility_probe_k, {'numeric'}, {'integer','nonnegative','finite'});
validateattributes(config.window_lengths_h, {'numeric'}, {'vector','positive','finite'});
validateattributes(config.economic_block_lengths_h, {'numeric'}, {'vector','integer','positive','finite'});
if config.economic_block_batch < 1 || config.economic_block_max_cuts < 1
    error('O1:bad_block_limits','分块批量和有效割数量上限须为正整数。');
end
if config.economic_block_max_time_s<config.economic_block_time_s || ...
        config.economic_decomposition_stall_sweeps<1 || config.economic_decomposition_min_dual_sweeps<1 || ...
        any(diff(config.economic_block_lengths_h)<=0)
    error('O1:bad_decomposition_options','块长度须递增，最大定价预算不得小于初始预算，停滞轮数须为正。');
end
for name = {'defer_feasibility_search','economic_scale_solver','economic_grid_simplify','enable_window_cuts', ...
        'economic_structural_search','enable_start_repair','use_cache','autonomous_search'}
    validateattributes(config.(name{1}), {'logical','numeric'}, {'scalar','binary'});
    config.(name{1}) = logical(config.(name{1}));
end
for name = {'cache_directory','progress_file','display','economics_solver','gurobi_matlab_directory','economic_proof_mode'}
    value = config.(name{1});
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('O1:bad_text_option','%s须为字符路径或文本。',name{1});
    end
    config.(name{1}) = char(value);
end
if isempty(config.cache_directory), config.cache_directory = pwd; end
if ~isfolder(config.cache_directory)
    error('O1:missing_cache_directory','缓存目录不存在：%s',config.cache_directory);
end
if ~ismember(string(config.economics_solver), ["gurobi","intlinprog"])
    error('O1:bad_solver','经济后端须为gurobi或intlinprog。');
end
if ~ismember(string(config.economic_proof_mode), ["full","hb_only"])
    error('O1:bad_proof_mode','economic_proof_mode须为full或hb_only。');
end
validateattributes(config.gurobi_mip_focus, {'numeric'}, {'scalar','integer','>=',-1,'<=',3});
validateattributes(config.gurobi_method, {'numeric'}, {'scalar','integer','>=',-1,'<=',5});
validateattributes(config.gurobi_threads, {'numeric'}, {'scalar','integer','nonnegative'});
if strcmp(config.economics_solver, 'gurobi')
    gurobi_dir = config.gurobi_matlab_directory;
    if isempty(gurobi_dir) && ~ismember(exist('gurobi','file'), [2,3])
        gurobi_root = getenv('GUROBI_HOME');
        if isempty(gurobi_root) && ispc
            [status, paths] = system('where gurobi_cl');
            if status == 0
                paths = splitlines(strtrim(paths));
                gurobi_root = fileparts(fileparts(char(paths(1))));
            end
        end
        if ~isempty(gurobi_root), gurobi_dir = fullfile(gurobi_root,'matlab'); end
    end
    if ~isempty(gurobi_dir)
        if ~isfile(fullfile(gurobi_dir, ['gurobi.',mexext]))
            error('O1:missing_gurobi_directory','未找到Gurobi MATLAB接口：%s',gurobi_dir);
        end
        addpath(gurobi_dir);
    end
    if ~ismember(exist('gurobi','file'), [2,3])
        error('O1:missing_gurobi','请配置gurobi_matlab_directory。');
    end
end
% 以下字段仅供未改动的Kfea模块读取，不再触发成本前沿调度。
config.frontier_key_k = [];
config.frontier_certification_tolerance_usd_t = 0.5;
config.feasibility_probe_k = unique(config.feasibility_probe_k(:),'stable');
end

function ctx = build_context(model, config)
required = {'problem', 'variables', 'expressions', 'options', 'params', ...
    'renewable_data', 'context', 'start_power_per_module_kw'};
for i = 1:numel(required)
    if ~isfield(model, required{i})
        error('O1:bad_model', 'Missing model field: %s.', required{i});
    end
end
if ~isfield(model.variables, 'HB_load') || ...
        ~isfield(model.expressions, 'nh3_total_t') || ...
        ~isfield(model.expressions, 'system_cost_usd')
    error('O1:bad_model', ...
        'The model must expose HB_load, nh3_total_t and system_cost_usd.');
end

params = model.params;
T = model.renewable_data.time_count;
dt = params.time.step;
HB_load = model.variables.HB_load;
NH3_total_t = model.expressions.nh3_total_t;
system_cost_usd = model.expressions.system_cost_usd;
if isfield(model.expressions, 'cost_components')
    cost_components = model.expressions.cost_components;
else
    cost_components = struct();
end
minimum_output_t = params.HB.min_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
maximum_output_t = params.HB.max_load * params.HB.nh3_output * T * dt ...
    / params.unit.mass_scale;
target_tolerance = max(1e-6, 1e-9 * config.nh3_target_t);
if config.nh3_target_t < minimum_output_t - target_tolerance || ...
        config.nh3_target_t > maximum_output_t + target_tolerance
    error('O1:target_out_of_range', ...
        'NH3 target %.6g t is outside [%.6g, %.6g] t.', ...
        config.nh3_target_t, minimum_output_t, maximum_output_t);
end

HB_ramp = params.HB.ramp_rate * dt;
if config.change_epsilon >= HB_ramp
    error('O1:bad_change_epsilon', ...
        'change_epsilon must be smaller than the HB ramp limit %.6g.', ...
        HB_ramp);
end

base_problem = model.problem;
base_problem.Constraints.O1_nh3_target = NH3_total_t == config.nh3_target_t;
base_problem.Constraints.O1_cyclic_ramp_up = ...
    HB_load(1) - HB_load(end) <= HB_ramp;
base_problem.Constraints.O1_cyclic_ramp_down = ...
    HB_load(end) - HB_load(1) <= HB_ramp;

z = optimvar('O1_HB_change', T, 'Type', 'integer', ...
    'LowerBound', 0, 'UpperBound', 1);
setpoint = optimvar('O1_HB_setpoint', T, ...
    'LowerBound', params.HB.min_load, 'UpperBound', params.HB.max_load);
setpoint_change = [setpoint(2:end); setpoint(1)] - setpoint;
problem = base_problem;
problem.Constraints.O1_tracking_up = ...
    HB_load - setpoint <= config.change_epsilon / 2;
problem.Constraints.O1_tracking_down = ...
    setpoint - HB_load <= config.change_epsilon / 2;
problem.Constraints.O1_change_up = ...
    setpoint_change <= (HB_ramp + config.change_epsilon) * z;
problem.Constraints.O1_change_down = ...
    -setpoint_change <= (HB_ramp + config.change_epsilon) * z;

cost_options = optimoptions(model.options, ...
    'RelativeGapTolerance', config.cost_relative_gap, ...
    'MaxTime', config.max_time_s, 'Display', config.display);
count_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, ...
    'AbsoluteGapTolerance', config.count_absolute_gap, ...
    'MaxTime', config.count_max_time_s, 'Display', config.display);
feasibility_options = optimoptions(model.options, ...
    'RelativeGapTolerance', 0, 'AbsoluteGapTolerance', 0, ...
    'MaxFeasiblePoints', 1, 'MaxTime', config.fixed_max_time_s, ...
    'Display', config.display);
repair_options = optimoptions(feasibility_options, ...
    'MaxTime', config.repair_max_time_s);

signature = struct();
signature.schema_version = 4;
signature.nh3_target_t = config.nh3_target_t;
signature.change_epsilon = config.change_epsilon;
signature.time_count = T;
signature.time_step_h = model.renewable_data.time_step_h;
signature.pv_power_kw = model.renewable_data.pv_power_kw(:);
signature.pw_power_kw = model.renewable_data.pw_power_kw(:);
signature.model_parameters = params;
if isfield(signature.model_parameters, 'solver')
    signature.model_parameters = rmfield(signature.model_parameters, 'solver');
end
cost_signature = signature;
cost_signature.objective_definition = ...
    "system_cost_without_ammonia_revenue_v1";
objective_shift_usd = params.ammonia.price * config.nh3_target_t;

[~, run_id] = fileparts(tempname);
ctx = struct('model', model, 'config', config, 'params', params, ...
    'run_id', run_id, ...
    'T', T, 'dt', dt, 'HB_ramp', HB_ramp, 'HB_load', HB_load, ...
    'z', z, 'setpoint', setpoint, 'update_count', sum(z), ...
    'system_cost_usd', system_cost_usd, ...
    'objective_shift_usd', objective_shift_usd, ...
    'cost_components', cost_components, 'base_problem', base_problem, ...
    'problem', problem, 'cost_options', cost_options, ...
    'count_options', count_options, ...
    'feasibility_options', feasibility_options, ...
    'repair_options', repair_options, 'signature', signature, ...
    'cost_signature', cost_signature, ...
    'output_range_t', [minimum_output_t, maximum_output_t], ...
    'stage1_cache_file', fullfile(config.cache_directory, 'O1_stage1_cache.mat'), ...
    'point_cache_file', fullfile(config.cache_directory, 'O1_fixed_k_cache.mat'));
end

function reference = load_or_solve_reference(ctx)
reference = struct();
if ctx.config.use_cache && isfile(ctx.stage1_cache_file)
    try
        loaded = load(ctx.stage1_cache_file);
        has_payload = isfield(loaded, 'reference') && ...
            isfield(loaded, 'cache_signature');
        valid = has_payload && ...
            isequaln(loaded.cache_signature, ctx.cost_signature);
        migrated = false;
        if has_payload && ~valid && ...
                isequaln(loaded.cache_signature, ctx.signature)
            loaded.reference = migrate_cost_record(loaded.reference, ctx);
            valid = true;
            migrated = true;
        end
        if valid
            candidate = loaded.reference;
            valid = isstruct(candidate) && candidate.has_incumbent && ...
                isfield(candidate, 'solution') && ...
                isfield(candidate.solution, 'HB_load') && ...
                numel(candidate.solution.HB_load) == ctx.T && ...
                isfinite(candidate.objective_upper);
        end
        if valid
            reference = candidate;
            if migrated
                cache_payload = struct('reference', reference, ...
                    'cache_signature', ctx.cost_signature);
                save(ctx.stage1_cache_file, '-struct', ...
                    'cache_payload', '-v7.3');
                fprintf('[O1] Stage 1旧目标缓存已换算为当前成本口径。\n');
            else
                fprintf('[O1] Stage 1 loaded from cache: %s\n', ...
                    ctx.stage1_cache_file);
            end
        else
            fprintf('[O1] Stage 1 cache ignored: model instance changed.\n');
        end
    catch exception
        fprintf('[O1] Stage 1 cache ignored: %s\n', exception.message);
    end
end
if ~isempty(fieldnames(reference))
    return
end

reference_problem = ctx.base_problem;
reference_problem.Objective = ctx.system_cost_usd;
reference = solve_problem(reference_problem, ctx.cost_options, ...
    "cost", struct(), ctx.system_cost_usd);
if reference.has_incumbent && ctx.config.use_cache
    cache_payload = struct('reference', reference, ...
        'cache_signature', ctx.cost_signature);
    save(ctx.stage1_cache_file, '-struct', 'cache_payload', '-v7.3');
    fprintf('[O1] Stage 1 result cached to: %s\n', ctx.stage1_cache_file);
end
end

function record = migrate_cost_record(record, ctx)
%MIGRATE_COST_RECORD 将旧的“成本减氨收入”记录换算为当前成本口径。
if ~isstruct(record) || isempty(fieldnames(record))
    return
end
shift_fields = {'objective_lower', 'objective_upper', ...
    'system_cost_lower', 'system_cost_upper'};
for field_index = 1:numel(shift_fields)
    name = shift_fields{field_index};
    if isfield(record, name) && isscalar(record.(name)) && ...
            isfinite(record.(name))
        record.(name) = record.(name) + ctx.objective_shift_usd;
    end
end
if isfield(record, 'solution') && isstruct(record.solution) && ...
        ~isempty(fieldnames(record.solution))
    try
        current_cost = evaluate(ctx.system_cost_usd, record.solution);
        if isfinite(current_cost)
            record.objective_upper = current_cost;
            record.system_cost_upper = current_cost;
        end
        record.cost_components = evaluate_cost_components( ...
            record.solution, ctx);
        record.operation_metrics = evaluate_operation_metrics( ...
            record.solution, ctx);
    catch
    end
end
if isfield(record, 'objective_lower') && ...
        isfield(record, 'objective_upper') && ...
        isfinite(record.objective_lower) && isfinite(record.objective_upper)
    record.absolute_gap = max(0, ...
        record.objective_upper - record.objective_lower);
    record.relative_gap = record.absolute_gap / ...
        max(1, abs(record.objective_upper));
end
record.objective_definition = ...
    "system_cost_without_ammonia_revenue_v1";
record.migrated_from_ammonia_revenue_objective = true;
end

function entries = fixed_point_store(file, signature, action, mode, cost_cap, entry)
% 同一轮频繁读取大缓存时复用内存；文件被外部更新或删除后必须重载。
persistent memory_file memory_stamp memory_sets
cache_sets = struct('signature', {}, 'entries', {});
file_info = dir(file);
if isempty(file_info)
    stamp = [];
else
    stamp = [file_info.datenum, file_info.bytes];
end
if isequal(memory_file, file) && isequal(memory_stamp, stamp) && ...
        ~isempty(memory_sets)
    cache_sets = memory_sets;
elseif ~isempty(file_info)
    try
        loaded = load(file, 'cache_sets');
        if isfield(loaded, 'cache_sets')
            cache_sets = loaded.cache_sets;
        end
    catch exception
        % 不把读取失败当作空缓存，否则下一次追加会覆盖既有证据。
        error('O1:cache_read_failed', '读取缓存失败，保留原文件：%s', ...
            exception.message);
    end
end
memory_file = file;
memory_stamp = stamp;
memory_sets = cache_sets;
set_index = [];
for i = 1:numel(cache_sets)
    if isequaln(cache_sets(i).signature, signature)
        set_index = i;
        break
    end
end
if isempty(set_index)
    entries = struct('mode', {}, 'cost_cap', {}, 'K', {}, ...
        'record', {}, 'source', {});
else
    entries = cache_sets(set_index).entries;
end

if action == "load"
    keep = false(size(entries));
    for i = 1:numel(entries)
        same_cap = same_cost_cap(entries(i).cost_cap, cost_cap);
        keep(i) = string(entries(i).mode) == string(mode) && same_cap;
    end
    entries = entries(keep);
    return
end

if isempty(set_index)
    set_index = numel(cache_sets) + 1;
    cache_sets(set_index).signature = signature;
    cache_sets(set_index).entries = entries;
end
all_entries = cache_sets(set_index).entries;
match = [];
for i = 1:numel(all_entries)
    same_cap = same_cost_cap(all_entries(i).cost_cap, entry.cost_cap);
    if string(all_entries(i).mode) == string(entry.mode) && ...
            all_entries(i).K == entry.K && same_cap
        match = i;
        break
    end
end
if isempty(match)
    all_entries(end + 1) = entry;
else
    all_entries(match) = entry;
end
cache_sets(set_index).entries = all_entries;
temporary_file = [file, '.tmp.mat'];
save(temporary_file, 'cache_sets', '-v7.3');
movefile(temporary_file, file, 'f');
file_info = dir(file);
memory_stamp = [file_info.datenum, file_info.bytes];
memory_sets = cache_sets;
entries = all_entries;

    function tf = same_cost_cap(left, right)
        tf = (isinf(left) && isinf(right) && sign(left) == sign(right)) || ...
            (isfinite(left) && isfinite(right) && ...
            abs(left - right) <= 1e-9 * max([1, abs(left), abs(right)]));
    end
end

function record = solve_problem(problem, options, objective_kind, ...
        initial_solution, cost_expression)
record = struct('objective_kind', string(objective_kind), ...
    'has_incumbent', false, 'objective_lower', NaN, ...
    'objective_upper', NaN, 'system_cost_lower', NaN, ...
    'system_cost_upper', NaN, 'absolute_gap', NaN, ...
    'relative_gap', NaN, 'count_lower', NaN, 'count_upper', NaN, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "not_run", 'message', "", 'output', struct(), ...
    'solution', struct(), 'solve_backend', "problem_based", ...
    'K_limit', NaN, 'elapsed_s', NaN);
started = tic;
try
    if isstruct(initial_solution) && ~isempty(fieldnames(initial_solution))
        [solution, fval, exitflag, output] = solve(problem, initial_solution, ...
            'Solver', 'intlinprog', 'Options', options);
    else
        [solution, fval, exitflag, output] = solve(problem, ...
            'Solver', 'intlinprog', 'Options', options);
    end
catch exception
    record.elapsed_s = toc(started);
    record.status = "solver_error";
    record.message = string(exception.message);
    return
end
record.elapsed_s = toc(started);

record.exitflag = exitflag;
record.output = output;
record.is_infeasible = exitflag == -2;
if isfield(output, 'message')
    record.message = string(output.message);
end
record.has_incumbent = isstruct(solution) && ...
    isfield(solution, 'HB_load') && ~isempty(solution.HB_load) && ...
    isscalar(fval) && isfinite(fval);
if isfield(output, 'bestbound') && isscalar(output.bestbound) && ...
        isfinite(output.bestbound) && objective_kind == "count"
    record.objective_lower = output.bestbound;
end
if ~record.has_incumbent
    if objective_kind == "count" && isfinite(record.objective_lower)
        record.count_lower = max(0, ceil(record.objective_lower - 1e-7));
    end
    if record.is_infeasible
        record.status = "infeasible";
    else
        record.status = "unknown";
    end
    return
end

record.solution = solution;
record.objective_upper = fval;
if isfield(output, 'absolutegap') && isscalar(output.absolutegap) && ...
        isfinite(output.absolutegap)
    record.absolute_gap = max(0, output.absolutegap);
    record.objective_lower = fval - record.absolute_gap;
elseif exitflag > 0
    record.absolute_gap = 0;
    record.objective_lower = fval;
end
if isfield(output, 'relativegap') && isscalar(output.relativegap) && ...
        isfinite(output.relativegap)
    record.relative_gap = max(0, output.relativegap);
elseif isfinite(record.absolute_gap)
    record.relative_gap = record.absolute_gap / max(1, abs(fval));
end
try
    record.system_cost_upper = evaluate(cost_expression, solution);
catch
    record.system_cost_upper = NaN;
end

if objective_kind == "count"
    record.count_upper = round(sum(solution.O1_HB_change));
    record.count_lower = max(0, ceil(record.objective_lower - 1e-7));
    record.is_proven = record.count_lower == record.count_upper;
elseif objective_kind == "cost"
    record.system_cost_lower = record.objective_lower;
    record.is_proven = exitflag > 0 && record.absolute_gap <= ...
        max(1e-7, eps(abs(fval)));
else
    record.count_upper = round(sum(solution.O1_HB_change));
    record.is_proven = true;
end
if record.is_proven
    record.status = "proven";
else
    record.status = "incumbent_with_bound";
end
end

function [solver_data, elapsed_s] = build_fixed_solver(problem, ctx, initial)
%BUILD_FIXED_SOLVER 构建可复用的固定K矩阵模型。
started = tic;
solver_problem = prob2struct(problem, initial, 'Solver', 'intlinprog');
solver_problem.options = ctx.feasibility_options;
indices = varindex(problem);
z_indices = indices.O1_HB_change(:);
A = solver_problem.Aineq;
row_nnz = full(sum(spones(A), 2));
z_nnz = full(sum(spones(A(:, z_indices)), 2));
candidates = find(row_nnz == numel(z_indices) & ...
    z_nnz == numel(z_indices));
update_row = NaN;
update_coefficient = NaN;
for i = 1:numel(candidates)
    values = full(A(candidates(i), z_indices));
    coefficient = values(1);
    if coefficient > 0 && max(abs(values - coefficient)) <= 1e-12 && ...
            abs(solver_problem.bineq(candidates(i)) / coefficient ...
            - ctx.T) <= 1e-8
        update_row = candidates(i);
        update_coefficient = coefficient;
        break
    end
end
if ~isfinite(update_row)
    error('O1:update_row_not_found', ...
        'Cannot locate the fixed-K constraint in the solver matrix.');
end
% 原约束推导的冗余凸包割：z=0时相邻实际负荷差不超过epsilon，
% z=1时不超过物理爬坡R，因此|负荷差|<=epsilon+(R-epsilon)*z。
% 它不排除任何原整数可行解，只加强分支定界中的分数z松弛。
hours = (1:ctx.T).';
next_hours = [hours(2:end); hours(1)];
load_indices = indices.HB_load(:);
load_difference = sparse([hours; hours], ...
    [load_indices(next_hours); load_indices], ...
    [ones(ctx.T, 1); -ones(ctx.T, 1)], ctx.T, numel(solver_problem.lb));
change_part = sparse(hours, z_indices, ...
    (ctx.HB_ramp - ctx.config.change_epsilon) * ones(ctx.T, 1), ...
    ctx.T, numel(solver_problem.lb));
solver_problem.Aineq = [solver_problem.Aineq; ...
    load_difference - change_part; -load_difference - change_part];
solver_problem.bineq = [solver_problem.bineq; ...
    ctx.config.change_epsilon * ones(2 * ctx.T, 1)];
solver_data = struct('problem', solver_problem, 'indices', indices, ...
    'update_row', update_row, 'update_coefficient', update_coefficient, ...
    'hb_ramp_hull_cut_count', 2 * ctx.T);
% T+1个储氢状态单独标时；标时仅用于选择块内变量，不固定块边界。
solver_data.variable_hour = zeros(numel(solver_problem.lb),1);
for name = fieldnames(indices).'
    index = indices.(name{1})(:);
    if numel(index) == ctx.T || strcmp(name{1},'storage_H2') && numel(index) == ctx.T+1
        solver_data.variable_hour(index) = (1:numel(index)).';
    end
end
elapsed_s = toc(started);
end

function [x, exitflag, output] = recover_direction_binaries( ...
        problem, relaxed_x, indices, max_time_s)
%RECOVER_DIRECTION_BINARIES 固定离散方向变量后恢复LP可行点。
lower = problem.lb;
upper = problem.ub;
fixed = problem.intcon(:);
fixed_values = round(relaxed_x(fixed));

if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    n_ael = round(relaxed_x(indices.n_ael(:)));
    direction = double([n_ael(1); diff(n_ael)] > 0);
    fixed = [fixed; indices.I_AEL_up(:)];
    fixed_values = [fixed_values; direction];
end
if isfield(indices, 'u_purchase') && isfield(indices, 'p_purchase') && ...
        isfield(indices, 'p_sell')
    net_purchase = relaxed_x(indices.p_purchase(:)) ...
        - relaxed_x(indices.p_sell(:));
    grid_direction = double(net_purchase > 1e-8);
    fixed = [fixed; indices.u_purchase(:)];
    fixed_values = [fixed_values; grid_direction];
end

[fixed, unique_rows] = unique(fixed, 'stable');
fixed_values = fixed_values(unique_rows);
lower(fixed) = fixed_values;
upper(fixed) = fixed_values;
options = optimoptions('linprog', 'Algorithm', 'interior-point', ...
    'ConstraintTolerance', 1e-5, 'Display', 'none', ...
    'MaxTime', max_time_s);
[x, ~, exitflag, output] = linprog(problem.f, problem.Aineq, ...
    problem.bineq, problem.Aeq, problem.beq, lower, upper, options);
end

function components = evaluate_cost_components(solution, ctx)
components = struct();
if ~isfield(ctx, 'cost_components') || ...
        isempty(fieldnames(ctx.cost_components)) || ...
        ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
names = fieldnames(ctx.cost_components);
for name_index = 1:numel(names)
    name = names{name_index};
    expression = ctx.cost_components.(name);
    if isnumeric(expression) && isscalar(expression)
        value = expression;
    else
        try
            value = evaluate(expression, solution);
        catch
            value = NaN;
        end
    end
    if isscalar(value)
        components.(name) = double(value);
    else
        components.(name) = NaN;
    end
end
end

function metrics = evaluate_operation_metrics(solution, ctx)
metrics = struct('curtailment_mwh', NaN, 'purchase_mwh', NaN, ...
    'sales_mwh', NaN, 'ael_start_energy_mwh', NaN, ...
    'ael_started_modules', NaN, 'storage_swing_kg', NaN, ...
    'storage_throughput_kg', NaN);
if ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
if isfield(solution, 'p_curt')
    metrics.curtailment_mwh = sum(solution.p_curt(:)) * ctx.dt / 1000;
end
if isfield(solution, 'p_purchase')
    metrics.purchase_mwh = sum(solution.p_purchase(:)) * ctx.dt / 1000;
end
if isfield(solution, 'p_sell')
    metrics.sales_mwh = sum(solution.p_sell(:)) * ctx.dt / 1000;
end
if isfield(solution, 'SU_AEL')
    started_modules = sum(solution.SU_AEL(:));
    metrics.ael_started_modules = started_modules;
    metrics.ael_start_energy_mwh = started_modules * ...
        ctx.model.start_power_per_module_kw * ctx.dt / 1000;
end
if isfield(solution, 'storage_H2')
    storage = solution.storage_H2(:);
    metrics.storage_swing_kg = max(storage) - min(storage);
    metrics.storage_throughput_kg = sum(abs(diff(storage))) / 2;
end
end

function start = add_change_indicators(solution, ctx)
start = solution;
HB_load = solution.HB_load(:);
if isfield(solution, 'O1_HB_setpoint') && ...
        numel(solution.O1_HB_setpoint) == ctx.T
    setpoint = solution.O1_HB_setpoint(:);
    tolerance = max([1e-9, ctx.config.change_tolerance, ...
        ctx.model.options.ConstraintTolerance]);
    tracking_ok = max(abs(HB_load - setpoint)) <= ...
        ctx.config.change_epsilon / 2 + tolerance;
    bounds_ok = min(setpoint) >= ctx.params.HB.min_load - tolerance && ...
        max(setpoint) <= ctx.params.HB.max_load + tolerance;
    if tracking_ok && bounds_ok
        change = [setpoint(2:end); setpoint(1)] - setpoint;
        if isfield(solution, 'O1_HB_change') && ...
                numel(solution.O1_HB_change) == ctx.T
            solver_z = solution.O1_HB_change(:);
            rounded_z = round(solver_z);
            integer_ok = max(abs(solver_z - rounded_z)) <= tolerance;
            link_violation = max(abs(change) - ...
                (ctx.HB_ramp + ctx.config.change_epsilon) * rounded_z);
            if integer_ok && link_violation <= tolerance
                start.O1_HB_setpoint = setpoint;
                start.O1_HB_change = double(abs(change) > tolerance);
                return
            end
        else
            start.O1_HB_setpoint = setpoint;
            start.O1_HB_change = double(abs(change) > tolerance);
            return
        end
    end
end
lower = max(ctx.params.HB.min_load, ...
    HB_load - ctx.config.change_epsilon / 2);
upper = min(ctx.params.HB.max_load, ...
    HB_load + ctx.config.change_epsilon / 2);
[setpoint, starts] = merge_once(lower, upper, 1);
candidate_starts = unique([1; starts(:)], 'stable');
if ctx.config.change_epsilon == 0
    candidate_starts = 1;
end
change = [setpoint(2:end); setpoint(1)] - setpoint;
best_count = sum(abs(change) > 1e-12);
best_variation = sum(abs(change));
for i = 2:numel(candidate_starts)
    candidate = merge_once(lower, upper, candidate_starts(i));
    candidate_change = [candidate(2:end); candidate(1)] - candidate;
    candidate_count = sum(abs(candidate_change) > 1e-12);
    candidate_variation = sum(abs(candidate_change));
    if candidate_count < best_count || ...
            (candidate_count == best_count && ...
            candidate_variation < best_variation)
        setpoint = candidate;
        best_count = candidate_count;
        best_variation = candidate_variation;
    end
end
change = [setpoint(2:end); setpoint(1)] - setpoint;
start.O1_HB_setpoint = setpoint;
start.O1_HB_change = double(abs(change) > 1e-12);

    function [values, platform_starts] = merge_once( ...
            interval_lower, interval_upper, first_hour)
        T = numel(interval_lower);
        order = [first_hour:T, 1:first_hour-1];
        ranges = zeros(T, 2);
        segment_lower = zeros(T, 1);
        segment_upper = zeros(T, 1);
        first_position = 1;
        segment_count = 0;
        current_lower = interval_lower(order(1));
        current_upper = interval_upper(order(1));
        for position = 2:T
            next_lower = max(current_lower, interval_lower(order(position)));
            next_upper = min(current_upper, interval_upper(order(position)));
            if next_lower <= next_upper + 1e-12
                current_lower = next_lower;
                current_upper = next_upper;
            else
                segment_count = segment_count + 1;
                segment_lower(segment_count) = current_lower;
                segment_upper(segment_count) = current_upper;
                ranges(segment_count, :) = [first_position, position - 1];
                first_position = position;
                current_lower = interval_lower(order(position));
                current_upper = interval_upper(order(position));
            end
        end
        segment_count = segment_count + 1;
        segment_lower(segment_count) = current_lower;
        segment_upper(segment_count) = current_upper;
        ranges(segment_count, :) = [first_position, T];
        segment_lower = segment_lower(1:segment_count);
        segment_upper = segment_upper(1:segment_count);
        ranges = ranges(1:segment_count, :);

        merge_ends = false;
        if segment_count > 1
            merged_lower = max(segment_lower(1), segment_lower(end));
            merged_upper = min(segment_upper(1), segment_upper(end));
            merge_ends = merged_lower <= merged_upper + 1e-12;
        end
        values = zeros(T, 1);
        platform_starts = zeros(segment_count, 1);
        for segment = 1:segment_count
            value = (segment_lower(segment) + segment_upper(segment)) / 2;
            if merge_ends && (segment == 1 || segment == segment_count)
                value = (merged_lower + merged_upper) / 2;
            end
            positions = ranges(segment, 1):ranges(segment, 2);
            hours = order(positions);
            values(hours) = value;
            platform_starts(segment) = hours(1);
        end
        platform_starts = unique(platform_starts, 'stable');
    end
end

function check = solution_check(solution, ctx)
HB_load = solution.HB_load(:);
HB_change = [HB_load(2:end); HB_load(1)] - HB_load;
NH3_total_t = sum(HB_load) * ctx.params.HB.nh3_output * ctx.dt ...
    / ctx.params.unit.mass_scale;
check = struct('raw_updates', ...
    sum(abs(HB_change) > ctx.config.change_tolerance), ...
    'setpoint_updates', NaN, 'effective_updates', NaN, ...
    'actual_updates', NaN, 'binary_updates', NaN, ...
    'max_tracking_deviation', NaN);
if isfield(solution, 'O1_HB_setpoint')
    setpoint = solution.O1_HB_setpoint(:);
    change = [setpoint(2:end); setpoint(1)] - setpoint;
    numerical_tolerance = max(ctx.config.change_tolerance, ...
        ctx.model.options.ConstraintTolerance);
    check.setpoint_updates = sum(abs(change) > numerical_tolerance);
    check.effective_updates = check.setpoint_updates;
    check.actual_updates = check.setpoint_updates;
    check.max_tracking_deviation = max(abs(HB_load - setpoint));
end
if isfield(solution, 'O1_HB_change')
    check.binary_updates = round(sum(solution.O1_HB_change));
end
check.total_variation = sum(abs(HB_change));
check.maximum_change = max(abs(HB_change));
check.change_epsilon = ctx.config.change_epsilon;
check.nh3_total_t = NH3_total_t;
check.nh3_residual_t = NH3_total_t - ctx.config.nh3_target_t;
P_AEL_start = ctx.model.start_power_per_module_kw * solution.SU_AEL(:);
power_residual = ctx.model.context.P_total(:) + solution.p_purchase(:) ...
    - solution.P_AEL(:) - P_AEL_start ...
    - HB_load * ctx.model.context.HB_power_kw ...
    - solution.p_sell(:) - solution.p_curt(:);
H2_production = solution.P_AEL(:) * ctx.dt ...
    / ctx.model.context.AEL_spec_energy * ctx.model.context.H2_density;
H2_use = HB_load * ctx.model.context.NH3_rate * ctx.dt ...
    * ctx.params.HB.lit_h2;
storage_H2 = solution.storage_H2(:);
storage_residual = storage_H2(2:end) - storage_H2(1:end-1) ...
    - H2_production + H2_use;
check.max_power_residual_kw = max(abs(power_residual));
check.max_storage_residual_kg = max(abs(storage_residual));
end

function save_reference(reference, ctx)
if ~ctx.config.use_cache, return; end
cache_payload = struct('reference',reference,'cache_signature',ctx.cost_signature);
file = [ctx.stage1_cache_file,'.tmp.mat'];
save(file,'-struct','cache_payload','-v7.3');
movefile(file,ctx.stage1_cache_file,'f');
end

function print_summary(study)
fprintf('\n========== O1 economic update threshold ==========\n');
fprintf('NH3 target: %.3f t; delta: %.6g USD/t; allowed extra cost: %.3f USD\n', ...
    study.config.nh3_target_t, study.config.economic_delta_usd_t, ...
    study.config.economic_delta_usd_t * study.config.nh3_target_t);
if study.reference.has_incumbent
    fprintf('Economic reference: [%.3f, %.3f] USD; Kref=%g\n', ...
        study.reference.objective_lower, study.reference.objective_upper, study.Kref);
end
if ~isempty(fieldnames(study.feasibility))
    fprintf('Kfea cached bounds: [%g, %g]; search deferred=%d\n', ...
        study.feasibility.K_lower,study.feasibility.K_upper,study.config.defer_feasibility_search);
end
if ~isempty(fieldnames(study.economic))
    e = study.economic;
    fprintf('Tsat=%.3f USD; Tfail=%.3f USD\n',e.strict_cost_cap_usd,e.cost_cap_usd);
    fprintf('Keco=[%g, %g], proven=%d\n',e.K_lower,e.K_upper,e.is_proven);
    if e.is_proven
        fprintf('[O1] Keco=%g：满足证据=%s；K=%g及以下排除证据=%s。\n', ...
            e.Keco,e.satisfied_evidence.source,e.Keco-1,e.rejected_evidence.source);
    else
        fprintf('[O1] 尚未证明唯一Keco；已缓存证据，下次main继续阈值认证。\n');
    end
end
fprintf('O1 status: %s\n',study.status);
end

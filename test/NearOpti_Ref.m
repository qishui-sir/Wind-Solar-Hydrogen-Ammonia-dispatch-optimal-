%% 测试一：极窄近优成本带内最小化全年设定值更新次数
% 直接运行本文件即可；不依赖测试二，不调用main或O1，不生成其他文件。
% 结果留在工作区NearOpti_Ref_result，全年调度在其中的dispatch表。
% 默认在“找到不超过487次”或“证明至少488次”时提前停止。
% 如需继续缩小计数区间，可将stop_after_decision改为false并增加时限。
NearOpti_Ref_config = struct( ...
    'year', 2022, 'target_t', 80000, 'tracking_width', 0.01, ...
    'threshold_K', 487, 'comparison_delta_usd_t', 0.5, ...
    'reference_lp_time_s', 180, 'reference_mip_time_s', 1200, ...
    'reference_gap_usd', 40, 'solve_time_s', 3600, ...
    'threads', 4, 'gurobi_matlab_directory', '', ...
    'money_guard_usd', 0.01, 'integer_bound_guard', 1e-5, ...
    'integer_tolerance', 1e-6, 'constraint_tolerance', 1e-5, ...
    'stop_after_decision', true);
NearOpti_Ref_result = run_near_optimal(NearOpti_Ref_config, mfilename('fullpath'));

function result = run_near_optimal(cfg, entry_file)
old_path = path;
path_cleanup = onCleanup(@() path(old_path));
clock = tic;
ctx = build_context(cfg, entry_file);
validateattributes(cfg.threshold_K, {'numeric'}, {'scalar', 'integer', 'nonnegative', '<=', ctx.T});
ref = compute_reference(ctx, cfg);
result = struct('status', "incomplete_reference", 'config', cfg, ...
    'reference', ref, 'count_lower', 0, 'count_upper', Inf, ...
    'cost_cap_usd', ref.cost_upper_usd, 'solution', struct(), 'dispatch', table(), ...
    'comparison_witness_validated', false, 'solver_status', "NOT_RUN", 'elapsed_s', toc(clock));
if ~ref.valid || ref.gap_usd > cfg.reference_gap_usd
    fprintf('\n参考成本尚未夹到%.3f USD以内，暂不把当前帽称为极窄近优带。\n', cfg.reference_gap_usd);
    fprintf('请先增加reference_mip_time_s；没有首解或限时均不表示更新问题不可行。\n');
    return
end
B0 = ref.cost_upper_usd;
m = add_cost_cap(ctx.full, B0);
best = check_point(ref.solution, m, ctx, cfg);
comparison_cap = ref.cost_lower_usd + cfg.comparison_delta_usd_t * cfg.target_t;
% 现有低更新见证只用于初值或对照，必须在当前原模型上重新验证。
for i = 1:numel(ctx.seeds)
    candidate = check_point(ctx.seeds(i).solution, ctx.full, ctx, cfg);
    if ~candidate.valid, continue; end
    if candidate.count <= cfg.threshold_K && candidate.cost <= comparison_cap - cfg.money_guard_usd
        result.comparison_witness_validated = true;
    end
    if candidate.cost <= B0 && (~best.valid || candidate.count < best.count)
        candidate = check_point(candidate.solution, m, ctx, cfg);
        if candidate.valid, best = candidate; end
    end
end
fprintf('\n极窄近优帽B0=%.6f USD，真实成本损失最多%.9f USD/t。\n', ...
    B0, (B0 - ref.cost_lower_usd) / cfg.target_t);
f = zeros(size(m.cost_f));
f(m.indices.O1_HB_change(:)) = 1;
run = struct('status', "NOT_RUN_ALREADY_DECIDED", 'raw', struct(), 'x', []);
lower = 0;
if ~(cfg.stop_after_decision && best.valid && best.count <= cfg.threshold_K)
    extra = struct('MIPGapAbs', 0.49, 'MIPFocus', 1);
    if cfg.stop_after_decision
        % 两个停止条件均围绕论文判别门槛，不能把提前停止误写成精确最优。
        extra.BestObjStop = cfg.threshold_K + 0.5;
        extra.BestBdStop = cfg.threshold_K + 100 * cfg.integer_bound_guard;
    end
    run = solve_model(m, f, 0, best.x, cfg.solve_time_s, cfg, extra, false, '极窄近优最少更新');
    if ~isempty(run.x)
        candidate = check_point(vector_solution(run.x, m.indices), m, ctx, cfg);
        if candidate.valid && candidate.cost <= B0 && (~best.valid || candidate.count < best.count)
            best = candidate;
        end
    end
    bound = global_lower(run, cfg.integer_bound_guard);
    if isfinite(bound), lower = max(0, ceil(bound)); end
    assert(run.status ~= "INFEASIBLE", ...
        'B0由当前可行参考构造，却报告不可行；请检查模型或数值一致性，不能据此排除更新次数。');
end
if best.valid
    assert(lower <= best.count, '计数下界超过当前验证见证，停止使用矛盾证据。');
    result.count_upper = best.count;
    result.solution = best.solution;
    result.dispatch = dispatch_table(best.solution, ctx);
    result.cost_usd = best.cost;
    result.max_original_residual = best.residual;
end
result.count_lower = lower;
result.solver_status = run.status;
result.raw_solver = run.raw;
result.elapsed_s = toc(clock);
if result.count_upper <= cfg.threshold_K
    result.status = "near_optimal_low_update_witness";
    fprintf('\n结论：极窄近优带内已验证不超过%d次的调度；原高计数参考存在可避免更新。\n', cfg.threshold_K);
elseif lower > cfg.threshold_K
    result.status = "near_optimal_requires_more_updates";
    fprintf('\n结论：极窄近优带至少需要%d次，已排除不超过%d次。\n', lower, cfg.threshold_K);
    if result.comparison_witness_validated
        fprintf('同时已在%.3f USD/t经济预算内复核不超过%d次的见证，经济让步确实降低所需更新数。\n', ...
            cfg.comparison_delta_usd_t, cfg.threshold_K);
    else
        fprintf('尚未复核到相应经济预算内的对照见证，暂不作两种预算的优势比较。\n');
    end
else
    result.status = "unresolved";
    fprintf('\n结论：尚未跨过%d次判别门槛；限时或未找到更好解不能作排除证据。\n', cfg.threshold_K);
end
fprintf('近优带最低更新次数区间=[%g, %g]，状态=%s，总耗时=%.1f s。\n', ...
    result.count_lower, result.count_upper, char(result.solver_status), result.elapsed_s);
fprintf('查看NearOpti_Ref_result；本次没有写入任何报告、缓存或调度文件。\n');
end

function ctx = build_context(cfg, entry_file)
% 只调用baseline的建模回调，不调用会写缓存的O1入口。
project_dir = fileparts(entry_file);
while ~isfile(fullfile(project_dir, 'src', 'baseline.m'))
    parent = fileparts(project_dir);
    assert(~strcmp(parent, project_dir), '未找到项目src/baseline.m。');
    project_dir = parent;
end
src = fullfile(project_dir, 'src');
addpath(src, fullfile(src, 'params'), fullfile(src, 'results'));
ensure_gurobi(cfg.gurobi_matlab_directory);
data_cfg = struct('pv_year', cfg.year, 'pw_year', cfg.year, ...
    'pv_capacity_kw', 200000, 'pw_capacity_kw', 200000);
data = load_res_year(data_cfg);
params = my_system('s2');
params.AEL.common.startup = true;
params.solver.relative_gap = 0.02;
params.solver.display = 'off';
base = baseline(params, data, @(model) model);
T = data.time_count;
h = base.variables.HB_load;
R = params.HB.ramp_rate * params.time.step;
assert(cfg.tracking_width >= 0 && cfg.tracking_width < R, '跟踪带必须小于单步爬坡限值。');
assert(cfg.target_t >= params.HB.min_load * params.HB.nh3_output * T * params.time.step / 1000 ...
    && cfg.target_t <= params.HB.max_load * params.HB.nh3_output * T * params.time.step / 1000, ...
    '年度产量超出当前负荷范围。');
physical = base.problem;
physical.Constraints.O1_nh3_target = base.expressions.nh3_total_t == cfg.target_t;
physical.Constraints.O1_cyclic_ramp_up = h(1) - h(end) <= R;
physical.Constraints.O1_cyclic_ramp_down = h(end) - h(1) <= R;
physical.Objective = base.expressions.system_cost_usd;
ctx.physical = pack_problem(physical, base.expressions.system_cost_usd, params.time.step);
s = optimvar('O1_HB_setpoint', T, 'LowerBound', params.HB.min_load, ...
    'UpperBound', params.HB.max_load);
z = optimvar('O1_HB_change', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
ds = [s(2:end); s(1)] - s;
dh = [h(2:end); h(1)] - h;
full_problem = physical;
full_problem.Constraints.O1_tracking_up = h - s <= cfg.tracking_width / 2;
full_problem.Constraints.O1_tracking_down = s - h <= cfg.tracking_width / 2;
full_problem.Constraints.O1_change_up = ds <= (R + cfg.tracking_width) * z;
full_problem.Constraints.O1_change_down = -ds <= (R + cfg.tracking_width) * z;
full_problem.Constraints.O1_update_limit = sum(z) <= T;
full_problem.Constraints.experiment_hull_up = dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
full_problem.Constraints.experiment_hull_down = -dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
ctx.full = pack_problem(full_problem, base.expressions.system_cost_usd, params.time.step);
ctx.params = params;
ctx.data = data;
ctx.T = T;
ctx.dt = params.time.step;
ctx.R = R;
signature = struct('schema_version', 4, 'nh3_target_t', cfg.target_t, ...
    'change_epsilon', cfg.tracking_width, 'time_count', T, ...
    'time_step_h', data.time_step_h, 'pv_power_kw', data.pv_power_kw(:), ...
    'pw_power_kw', data.pw_power_kw(:), 'model_parameters', params);
signature.model_parameters = rmfield(signature.model_parameters, 'solver');
signature.objective_definition = "system_cost_without_ammonia_revenue_v1";
ctx.seeds = read_cache_candidates(fullfile(src, 'cache'), signature);
fprintf('年份=%d，时段=%d，产量=%.0f t，跟踪总带宽=%.4f。\n', cfg.year, T, cfg.target_t, cfg.tracking_width);
end

function ensure_gurobi(configured_dir)
% 优先使用现有路径，其次读取GUROBI_HOME或系统中的gurobi_cl位置。
if ~isempty(configured_dir), addpath(configured_dir); end
if ismember(exist('gurobi', 'file'), [2, 3]), return; end
gurobi_home = getenv('GUROBI_HOME');
if isempty(gurobi_home) && ispc
    [status, locations] = system('where gurobi_cl');
    if status == 0
        locations = splitlines(strtrim(locations));
        gurobi_home = fileparts(fileparts(char(locations(1))));
    end
end
if ~isempty(gurobi_home), addpath(fullfile(gurobi_home, 'matlab')); end
assert(ismember(exist('gurobi', 'file'), [2, 3]), ...
    '未找到Gurobi接口，请填写配置中的gurobi_matlab_directory。');
end

function m = pack_problem(problem, cost_expression, dt)
% 固定费用常数直接在全零变量结构上计算，避免遗漏或重复计入。
m.p = prob2struct(problem, 'Solver', 'intlinprog');
m.indices = varindex(problem);
m.cost_f = m.p.f(:);
zero = vector_solution(zeros(numel(m.p.lb), 1), m.indices);
m.cost_offset = double(evaluate(cost_expression, zero));
m.units = ones(numel(m.p.lb), 1);
for field = {'P_AEL', 'storage_H2', 'p_purchase', 'p_sell', 'p_curt', 'grid_contract_kw'}
    if isfield(m.indices, field{1}), m.units(m.indices.(field{1})(:)) = 1000; end
end
m.units(m.p.intcon) = 1;
m.buy_f = zeros(size(m.cost_f));
m.buy_f(m.indices.p_purchase(:)) = dt / 1000; % 目标和输出均以MWh计。
assert(all(isfinite(m.p.lb)) && all(isfinite(m.p.ub)), '安全对偶盒界要求变量边界有限。');
end

function g = scaled_model(m, f, constant, relax)
% 连续功率/库存缩放，整数变量单位保持1；原约束不删除、不放松。
A = [m.p.Aineq; m.p.Aeq] * spdiags(m.units, 0, numel(m.units), numel(m.units));
scale = max(1, full(max(abs(A), [], 2)));
g = struct('A', spdiags(1 ./ scale, 0, numel(scale), numel(scale)) * A, ...
    'rhs', [m.p.bineq(:); m.p.beq(:)] ./ scale, ...
    'sense', [repmat('<', size(m.p.Aineq, 1), 1); repmat('=', size(m.p.Aeq, 1), 1)], ...
    'obj', f(:) .* m.units, 'objcon', constant, ...
    'lb', m.p.lb(:) ./ m.units, 'ub', m.p.ub(:) ./ m.units, ...
    'modelsense', 'min', 'vtype', repmat('C', numel(m.units), 1));
if ~relax, g.vtype(m.p.intcon) = 'I'; end
end

function run = solve_model(m, f, constant, seed, seconds, cfg, extra, relax, label)
g = scaled_model(m, f, constant, relax);
if ~relax && ~isempty(seed), g.start = seed(:) ./ m.units; end
options = struct('TimeLimit', seconds, 'Threads', cfg.threads, 'Seed', 0, ...
    'MIPGap', 0, 'MIPGapAbs', 0, 'MIPFocus', 1, 'Method', 1, ...
    'FeasibilityTol', 1e-9, 'IntFeasTol', 1e-9, 'OptimalityTol', 1e-9, ...
    'NumericFocus', 2, 'DualReductions', 0, 'StartTimeLimit', 3, ...
    'OutputFlag', 1, 'LogToConsole', 1, 'DisplayInterval', 30, ...
    'LogFile', '', 'ResultFile', '', 'SolFiles', '', 'NodefileStart', Inf);
for name = fieldnames(extra).', options.(name{1}) = extra.(name{1}); end
fprintf('\n[%s] 本阶段时限=%.0f s；仅在终端输出，不写日志或结果文件。\n', label, seconds);
raw = gurobi(g, options);
run = struct('raw', raw, 'status', string(raw.status), 'x', []);
if isfield(raw, 'x') && numel(raw.x) == numel(m.units) && all(isfinite(raw.x))
    run.x = raw.x(:) .* m.units;
end
end

function seeds = read_cache_candidates(cache_dir, signature)
% 缓存只读。签名不符时忽略；下界一律不从这些缓存读取。
seeds = struct('solution', {}, 'source', {}, 'is_reference', {});
files = {'O1_stage1_cache.mat', 'O1_economic_threshold_partition21_cache.mat'};
if ~isfile(fullfile(cache_dir, files{2})), files{2} = 'O1_economic_threshold_cache.mat'; end
for file_index = 1:numel(files)
    file = fullfile(cache_dir, files{file_index});
    if ~isfile(file), continue; end
    try
        loaded = load(file);
        if file_index == 1
            if isfield(loaded, 'cache_signature') && isequaln(loaded.cache_signature, signature) ...
                    && isfield(loaded, 'reference') && isfield(loaded.reference, 'solution')
                seeds(end+1) = struct('solution', loaded.reference.solution, 'source', files{file_index}, 'is_reference', true); %#ok<AGROW>
            end
        elseif isfield(loaded, 'signature') && isequaln(loaded.signature, signature) ...
                && isfield(loaded, 'schema_version') && loaded.schema_version == 1 && isfield(loaded, 'state')
            state = loaded.state;
            if isfield(state, 'reference') && isfield(state.reference, 'solution')
                seeds(end+1) = struct('solution', state.reference.solution, 'source', files{file_index}, 'is_reference', true); %#ok<AGROW>
            end
            for group = {'points', 'caps'}
                if ~isfield(state, group{1}), continue; end
                rows = state.(group{1});
                for j = 1:numel(rows)
                    if isfield(rows(j), 'has_incumbent') && rows(j).has_incumbent && isfield(rows(j), 'solution')
                        seeds(end+1) = struct('solution', rows(j).solution, 'source', files{file_index}, 'is_reference', false); %#ok<AGROW>
                    end
                end
            end
        end
    catch exception
        fprintf('忽略无法读取的候选缓存%s：%s\n', files{file_index}, exception.message);
    end
end
fprintf('读取到%d条签名匹配的候选记录，后续逐条验证，不直接接纳缓存结论。\n', numel(seeds));
end

function reference = compute_reference(ctx, cfg)
% 无计数限制时令s=h、所有必要边允许更新，即与原物理域投影等价。
m = ctx.physical;
best = check_point(struct(), m, ctx, cfg);
source = "无";
for i = 1:numel(ctx.seeds)
    if ~ctx.seeds(i).is_reference, continue; end
    candidate = check_point(ctx.seeds(i).solution, m, ctx, cfg);
    if candidate.valid && candidate.cost < best.cost, best = candidate; source = string(ctx.seeds(i).source); end
end
lp = solve_model(m, m.cost_f, m.cost_offset, [], cfg.reference_lp_time_s, cfg, struct(), true, '当前参考成本LP');
% 对偶乘子经符号投影与有限盒残差修正后给下界，不把LP原始可行值当下界。
g = scaled_model(m, m.cost_f, m.cost_offset, true);
lower = safe_lp_lower(g, lp.raw, cfg.money_guard_usd);
mip = struct('status', "NOT_NEEDED", 'raw', struct(), 'x', []);
if ~best.valid || best.cost - lower > cfg.reference_gap_usd
    mip = solve_model(m, m.cost_f, m.cost_offset, best.x, cfg.reference_mip_time_s, cfg, ...
        struct('MIPGapAbs', cfg.reference_gap_usd / 2), false, '当前参考成本MILP');
    if ~isempty(mip.x)
        candidate = check_point(vector_solution(mip.x, m.indices), m, ctx, cfg);
        if candidate.valid && candidate.cost < best.cost, best = candidate; source = "本次参考MILP"; end
    end
    lower = max(lower, global_lower(mip, cfg.money_guard_usd));
end
reference = struct('cost_lower_usd', lower, 'cost_upper_usd', Inf, 'gap_usd', Inf, ...
    'solution', struct(), 'source', source, 'purchase_mwh', Inf, ...
    'count', Inf, 'valid', false, 'lp_status', lp.status, 'mip_status', mip.status);
if ~best.valid, return; end
% 完整模型再次复核，并给上界保留明确的金额保护，吸收求和次序差异。
best = check_point(best.solution, ctx.full, ctx, cfg);
if ~best.valid, return; end
reference.cost_upper_usd = best.cost + cfg.money_guard_usd;
reference.gap_usd = reference.cost_upper_usd - lower;
assert(lower <= reference.cost_upper_usd, '参考下界超过已验证上界，停止使用该数值证据。');
reference.solution = best.solution;
reference.purchase_mwh = best.purchase_mwh;
reference.count = best.count;
reference.valid = true;
fprintf('\n参考成本区间=[%.6f, %.6f] USD，宽度=%.6f USD。\n', ...
    lower, reference.cost_upper_usd, reference.gap_usd);
fprintf('参考上界含%.4f USD数值保护；参考购电=%.6f MWh，参考更新=%g次。\n', ...
    cfg.money_guard_usd, reference.purchase_mwh, reference.count);
end

function lower = safe_lp_lower(g, raw, guard)
% 对任意合法符号乘子pi：b''pi+min_box[(c-A''pi)''x]是原问题下界。
pi = zeros(size(g.rhs));
if isfield(raw, 'pi') && numel(raw.pi) == numel(pi) && all(isfinite(raw.pi)), pi = raw.pi(:); end
pi(g.sense == '<') = min(pi(g.sense == '<'), 0);
q = g.obj - g.A.' * pi;
% 为浮点矩阵乘法及年度求和留出保守残差保护；并非精确有理数认证。
operations = full(sum(spones(g.A), 1)).' + 2;
q_error = 16 * eps * operations .* (abs(g.obj) + abs(g.A).' * abs(pi) + 1);
terms = [g.objcon; g.rhs .* pi; ...
    min(q .* g.lb, q .* g.ub) - q_error .* max(abs(g.lb), abs(g.ub))];
lower = sum(terms) - guard - 64 * eps * sum(abs(terms));
end

function lower = global_lower(run, guard)
% 只接纳正常终止/限时的全局界，数值异常状态不提供排除证据。
lower = -Inf;
allowed = {'OPTIMAL', 'TIME_LIMIT', 'NODE_LIMIT', 'ITERATION_LIMIT', ...
    'SOLUTION_LIMIT', 'WORK_LIMIT', 'INTERRUPTED', 'USER_OBJ_LIMIT'};
if ~any(strcmp(char(run.status), allowed)), return; end
for name = {'objboundc', 'objbound'}
    if isfield(run.raw, name{1}) && isfinite(run.raw.(name{1}))
        value = run.raw.(name{1});
        lower = value - max(guard, 1e-9 * max(1, abs(value)));
        return
    end
end
end

function point = check_point(solution, m, ctx, cfg)
point = struct('valid', false, 'solution', struct(), 'x', [], ...
    'cost', Inf, 'purchase_mwh', Inf, 'count', Inf, 'residual', Inf);
if ~isstruct(solution) || ~isfield(solution, 'HB_load'), return; end
if isfield(m.indices, 'O1_HB_setpoint')
    [restored, ok] = restore_platforms(solution, ctx, cfg);
    if ~ok
        % 没有合格平台时仅用s=h重建合法初值，绝不把微小实际变化抹成零。
        solution.O1_HB_setpoint = solution.HB_load(:);
        h = solution.HB_load(:);
        solution.O1_HB_change = double([h(2:end); h(1)] ~= h);
        [restored, ok] = restore_platforms(solution, ctx, cfg);
    end
    if ~ok, return; end
    solution = restored;
end
x = zeros(numel(m.p.lb), 1);
for name = fieldnames(m.indices).'
    index = m.indices.(name{1});
    if ~isfield(solution, name{1}) || numel(solution.(name{1})) ~= numel(index), return; end
    x(index(:)) = solution.(name{1})(:);
end
if any(~isfinite(x)) || max([0; abs(x(m.p.intcon) - round(x(m.p.intcon)))]) > cfg.integer_tolerance, return; end
x(m.p.intcon) = round(x(m.p.intcon));
residual = max([0; m.p.Aineq * x - m.p.bineq(:); ...
    abs(m.p.Aeq * x - m.p.beq(:)); m.p.lb(:) - x; x - m.p.ub(:)]);
if residual > cfg.constraint_tolerance, return; end
native = vector_solution(x, m.indices);
for name = fieldnames(native).', solution.(name{1}) = native.(name{1}); end
point.valid = true;
point.solution = solution;
point.x = x;
point.cost = m.cost_f.' * x + m.cost_offset;
point.purchase_mwh = m.buy_f.' * x;
point.residual = residual;
if isfield(solution, 'O1_HB_change'), point.count = sum(solution.O1_HB_change); end
end

function [solution, ok] = restore_platforms(solution, ctx, cfg)
% 循环零更新平台必须有共同跟踪区间，不能仅逐边容差判断以免累计漂移。
ok = false;
T = ctx.T;
required = {'HB_load', 'O1_HB_setpoint', 'O1_HB_change'};
if ~all(isfield(solution, required)), return; end
h = solution.HB_load(:); s = solution.O1_HB_setpoint(:); z = solution.O1_HB_change(:);
if numel(h) ~= T || numel(s) ~= T || numel(z) ~= T || any(~isfinite([h; s; z])), return; end
if max(abs(z - round(z))) > cfg.integer_tolerance, return; end
z = round(z);
if any(z ~= 0 & z ~= 1), return; end
cuts = find(z == 1);
if isempty(cuts)
    order = (1:T).'; ends = T;
else
    order = mod(cuts(1) + (0:T-1).', T) + 1;
    ends = find(z(order) == 1);
end
first = 1;
tiny = 1e-12 * max(1, max(abs(h)));
for last = ends(:).'
    hours = order(first:last);
    lo = max([h(hours) - cfg.tracking_width / 2; ctx.params.HB.min_load]);
    hi = min([h(hours) + cfg.tracking_width / 2; ctx.params.HB.max_load]);
    if lo > hi + 2 * tiny, return; end
    if lo <= hi, value = min(hi, max(lo, s(hours(1)))); else, value = (lo + hi) / 2; end
    s(hours) = value;
    first = last + 1;
end
ds = [s(2:end); s(1)] - s;
z = double(ds ~= 0);
if max(abs(h - s)) > cfg.tracking_width / 2 + tiny || ...
        any(s < ctx.params.HB.min_load - tiny | s > ctx.params.HB.max_load + tiny) || ...
        max(abs(ds) - (ctx.R + cfg.tracking_width) * z) > 2 * tiny
    return
end
solution.O1_HB_setpoint = s;
solution.O1_HB_change = z;
ok = true;
end

function solution = vector_solution(x, indices)
solution = struct();
for name = fieldnames(indices).'
    index = indices.(name{1});
    solution.(name{1}) = reshape(x(index(:)), size(index));
end
end

function m = add_cost_cap(m, cap)
% 成本常数只扣除一次，费用不扣售氨收入，和当前主程序口径相同。
m.p.Aineq = [m.p.Aineq; m.cost_f.'];
m.p.bineq = [m.p.bineq(:); cap - m.cost_offset];
end

function table_out = dispatch_table(solution, ctx)
table_out = table();
if isempty(fieldnames(solution)), return; end
T = ctx.T;
table_out = table(ctx.data.time(:), solution.HB_load(:), solution.O1_HB_setpoint(:), ...
    solution.O1_HB_change(:), solution.p_purchase(:) / 1000, ...
    solution.p_sell(:) / 1000, solution.p_curt(:) / 1000, solution.P_AEL(:) / 1000, ...
    ctx.params.AEL.common.startup_elec * ctx.params.AEL.common.module_power * solution.SU_AEL(:) / 1000, ...
    solution.storage_H2(1:T), solution.storage_H2(2:T+1), solution.n_ael(:), ...
    'VariableNames', {'Time', 'HB_load', 'HB_setpoint', 'Update_after_hour', ...
    'Purchase_MW', 'Sales_MW', 'Curtail_MW', 'AEL_MW', 'AEL_start_MW', ...
    'H2_start_kg', 'H2_end_kg', 'AEL_online_modules'});
end


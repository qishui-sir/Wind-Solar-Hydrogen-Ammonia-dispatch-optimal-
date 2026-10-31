function out = Calculate_K(K, solve_time_s, opts)
%CALCULATE_K 固定更新预算K的年度最小成本求解，并登记进主程序经济阈值缓存。
%   CALCULATE_K(K)              默认求解时长3600 s。
%   CALCULATE_K(K,solve_time_s) 指定求解时长（秒），例如 CALCULATE_K(700,3600)。
%   CALCULATE_K(...,opts)       仅供调试：覆盖 cache_file / mip_gap_abs_usd 等字段。
%
% 求解对象是原年度模型的 F(K)=min C(x) s.t. N(x)<=K：目标为年度净系统成本，
% 唯一新增约束是更新预算。经济容许损失delta不是本函数的输入——它只决定main
% 读取该点后如何判定经济合格，由main自身配置决定，与本求解无关。
%
% 单点独立求解：不做停滞提前停止，Gurobi在同一棵搜索树上持续改进，给定时间越长
% [cost_lower,cost_upper]只会收窄。obj.seed_mode控制起点：
%   'cache'（默认）只取满足本K预算的缓存解作为初始上界，不改变下界，也不限制后续
%          改进；实测冷启动900 s仍找不到任何可行解，故实际使用必须给一个可行起点。
%   'none'  完全冷启动，只适合有充裕机时或需要验证独立性的场合。
% 只有同时通过原年度矩阵、原整数集合、平台语义与成本重算的解才写入缓存；
% 缓存签名不一致时拒绝改写，绝不覆盖现有证据。
arguments
    K (1,1) double {mustBeReal, mustBeFinite, mustBeNonnegative, mustBeInteger}
    solve_time_s (1,1) double {mustBeReal, mustBeFinite, mustBePositive} = 3600
    opts struct = struct()
end
cfg = default_config();
for name = fieldnames(opts).'
    cfg.(name{1}) = opts.(name{1});
end
cfg.K = K;
cfg.total_time_s = solve_time_s;
out = run_fixed_budget(cfg, mfilename('fullpath'));
end

function out = run_fixed_budget(cfg, entry_file)
%RUN_FIXED_BUDGET 建模、单次长时限求解、原域核验并写入缓存。
old_path = path;
path_cleanup = onCleanup(@() path(old_path));
clock = tic;
ctx = build_context(cfg, entry_file);
validateattributes(cfg.K, {'numeric'}, ...
    {'scalar', 'integer', 'nonnegative', '<=', ctx.T});
out = struct('status', "not_started", 'K', cfg.K, ...
    'cost_lower_usd', -Inf, 'cost_upper_usd', Inf, 'gap_usd', Inf, ...
    'count', Inf, ...
    'reference_cost_usd', NaN, 'overrun_usd', NaN, 'overrun_usd_t', NaN, ...
    'solution', struct(), 'solver_status', "NOT_RUN", ...
    'elapsed_s', 0, 'cache_file', ctx.cache_file, 'cache_written', false);
fprintf(['\n[Calculate_K] 年份=%d，时段=%d，跟踪总带宽=%.4f，更新预算K=%d；' ...
    '单点求解时限=%.0f s，冷启动且不继承其它K的解。\n'], ...
    cfg.year, ctx.T, cfg.tracking_width, cfg.K, cfg.total_time_s);
m = with_count_budget(ctx.full, cfg.K);
seed = [];
if strcmpi(cfg.seed_mode, 'cache')
    [seed, seed_point] = pick_seed(ctx, m, cfg);
    if ~isempty(seed)
        fprintf(['[Calculate_K] 初始上界取自缓存可行解：成本=%.6f USD，更新=%g次；' ...
            '它只是上界起点，不限制求解器继续改进。\n'], ...
            seed_point.cost, seed_point.count);
    else
        fprintf('[Calculate_K] 缓存中没有满足K的可行解，本次冷启动。\n');
    end
end
run = solve_model(m, m.cost_f, m.cost_offset, seed, cfg.total_time_s, cfg, ...
    struct('MIPGapAbs', cfg.mip_gap_abs_usd), false, ...
    sprintf('K=%d最小成本', cfg.K));
out.solver_status = run.status;
out.elapsed_s = toc(clock);
if run.status == "INFEASIBLE"
    % K小于物理可行的最低更新数时，原年度模型确实无解；登记为排除证据。
    out.status = "update_budget_infeasible";
    out.cost_upper_usd = Inf;
    out.count = Inf;
    fprintf(['[Calculate_K] K=%d在当前年度模型下不可行：' ...
        '该预算下不存在可行调度，写入排除证据后停止。\n'], cfg.K);
    if cfg.write_cache
        record = infeasible_record(cfg, run.status, out.elapsed_s);
        out.cache_written = write_cache_point(ctx, cfg, record);
    end
    return
end
candidate = check_point(struct(), m, ctx, cfg);
if ~isempty(run.x)
    candidate = check_point(vector_solution(run.x, m.indices), m, ctx, cfg);
end
if ~candidate.valid
    out.status = "solver_returned_no_valid_witness";
    fprintf(['[Calculate_K] K=%d在本次时限内没有取得通过原域核验的可行解' ...
        '（求解状态=%s）。未找到解不构成排除证据，本次不写入缓存。\n'], ...
        cfg.K, char(out.solver_status));
    return
end
out.cost_lower_usd = global_lower(run, cfg.money_guard_usd);
out.cost_upper_usd = candidate.cost;
out.count = candidate.count;
out.solution = candidate.solution;
out.residual = candidate.residual;
assert(out.cost_lower_usd <= out.cost_upper_usd + cfg.money_guard_usd, ...
    'Calculate_K:inconsistent_bounds', ...
    '成本下界超过已核验上界，停止使用该数值证据。');
out.gap_usd = out.cost_upper_usd - out.cost_lower_usd;
if isfinite(ctx.cached.reference_left)
    % 与参考下界的差额就是该点在前沿上的横坐标；不依赖任何经济预算假设。
    out.reference_cost_usd = ctx.cached.reference_left;
    out.overrun_usd = out.cost_upper_usd - ctx.cached.reference_left;
    out.overrun_usd_t = out.overrun_usd / cfg.target_t;
end
fprintf(['[Calculate_K] 求解状态=%s；成本区间=[%.6f, %.6f] USD；' ...
    '实际更新=%g次；原矩阵残差=%.3g。\n'], char(out.solver_status), ...
    out.cost_lower_usd, out.cost_upper_usd, out.count, out.residual);
fprintf('[Calculate_K] 成本区间宽度=%.3f USD（占上界%.4g%%）。\n', ...
    out.gap_usd, 100 * out.gap_usd / max(1, abs(out.cost_upper_usd)));
if out.gap_usd > cfg.solved_gap_usd
    % 上界与下界相差过大时，cost_upper只是弱上界，不能当作F(K)的近似值。
    fprintf(['[Calculate_K] 提示：该点尚未收敛（宽度>%.0f USD），' ...
        'cost_upper是弱上界；前沿作图应把[下界,上界]整段画出。\n'], ...
        cfg.solved_gap_usd);
end
out.status = "fixed_k_cost_point";
out.elapsed_s = toc(clock);
if cfg.write_cache
    record = feasible_record(cfg, candidate, out.cost_lower_usd, ...
        out.solver_status, out.elapsed_s);
    out.cache_written = write_cache_point(ctx, cfg, record);
end
fprintf('[Calculate_K] 结束：状态=%s，总耗时=%.1f s。\n', ...
    char(out.status), out.elapsed_s);
end

function cfg = default_config()
%DEFAULT_CONFIG 求解与登记参数；交互调用时只改K与求解时长即可。
cfg = struct( ...
    'year', 2022, 'target_t', 80000, 'tracking_width', 0.01, ...
    'K', 600, 'total_time_s', 3600, 'mip_gap_abs_usd', 1, ...
    'solved_gap_usd', 1000, 'seed_mode', 'cache', ...
    'gurobi_params', struct(), ...
    'threads', 4, 'gurobi_matlab_directory', '', ...
    'money_guard_usd', 0.01, 'integer_tolerance', 1e-6, ...
    'constraint_tolerance', 1e-5, 'write_cache', true, 'cache_file', '');
end

function ctx = build_context(cfg, entry_file)
%BUILD_CONTEXT 只调用baseline的建模回调，构造与O1一致的年度模型。
project_dir = fileparts(entry_file);
while ~isfile(fullfile(project_dir, 'src', 'baseline.m'))
    parent = fileparts(project_dir);
    assert(~strcmp(parent, project_dir), 'Calculate_K:no_project', ...
        '未找到项目src/baseline.m。');
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
assert(cfg.tracking_width >= 0 && cfg.tracking_width < R, ...
    'Calculate_K:bad_band', '跟踪带必须小于单步爬坡限值。');
physical = base.problem;
physical.Constraints.O1_nh3_target = base.expressions.nh3_total_t == cfg.target_t;
physical.Constraints.O1_cyclic_ramp_up = h(1) - h(end) <= R;
physical.Constraints.O1_cyclic_ramp_down = h(end) - h(1) <= R;
physical.Objective = base.expressions.system_cost_usd;
s = optimvar('O1_HB_setpoint', T, 'LowerBound', params.HB.min_load, ...
    'UpperBound', params.HB.max_load);
z = optimvar('O1_HB_change', T, 'Type', 'integer', 'LowerBound', 0, ...
    'UpperBound', 1);
ds = [s(2:end); s(1)] - s;
dh = [h(2:end); h(1)] - h;
full_problem = physical;
full_problem.Constraints.O1_tracking_up = h - s <= cfg.tracking_width / 2;
full_problem.Constraints.O1_tracking_down = s - h <= cfg.tracking_width / 2;
full_problem.Constraints.O1_change_up = ds <= (R + cfg.tracking_width) * z;
full_problem.Constraints.O1_change_down = -ds <= (R + cfg.tracking_width) * z;
full_problem.Constraints.O1_update_limit = sum(z) <= T;
% 原约束推导的有效强化；不排除任何原整数可行解，与O1的固定K矩阵一致。
full_problem.Constraints.experiment_hull_up = ...
    dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
full_problem.Constraints.experiment_hull_down = ...
    -dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
ctx.full = pack_problem(full_problem, base.expressions.system_cost_usd);
ctx.cost_expression = base.expressions.system_cost_usd;
ctx.params = params;
ctx.data = data;
ctx.T = T;
ctx.dt = params.time.step;
ctx.R = R;
ctx.epsilon = cfg.tracking_width;
ctx.cache_file = fullfile(src, 'cache', ...
    'O1_economic_threshold_partition21_cache.mat');
if ~isempty(cfg.cache_file)
    % 仅供离线校验使用；默认始终写主程序实际读取的那一份缓存。
    ctx.cache_file = cfg.cache_file;
end
signature = struct();
signature.schema_version = 4;
signature.nh3_target_t = cfg.target_t;
signature.change_epsilon = cfg.tracking_width;
signature.time_count = T;
signature.time_step_h = data.time_step_h;
signature.pv_power_kw = data.pv_power_kw(:);
signature.pw_power_kw = data.pw_power_kw(:);
signature.model_parameters = params;
if isfield(signature.model_parameters, 'solver')
    signature.model_parameters = rmfield(signature.model_parameters, 'solver');
end
ctx.cost_signature = signature;
ctx.cost_signature.objective_definition = ...
    "system_cost_without_ammonia_revenue_v1";
ctx.cached = read_cache_header(ctx.cache_file, ctx.cost_signature, ...
    strcmpi(cfg.seed_mode, 'cache'));
end

function ensure_gurobi(configured_dir)
%ENSURE_GUROBI 优先使用现有路径，其次读取GUROBI_HOME或系统中的gurobi_cl位置。
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
assert(ismember(exist('gurobi', 'file'), [2, 3]), 'Calculate_K:no_gurobi', ...
    '未找到Gurobi接口，请填写配置中的gurobi_matlab_directory。');
end

function m = pack_problem(problem, cost_expression)
%PACK_PROBLEM 与原矩阵同一份系数，固定费用常数在全零变量上单独计算。
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
assert(all(isfinite(m.p.lb)) && all(isfinite(m.p.ub)), ...
    'Calculate_K:finite_box', '安全对偶盒界要求变量边界有限。');
end

function m = with_count_budget(m, K)
%WITH_COUNT_BUDGET 在年度模型上加入更新预算行 N(x) <= K。
row = sparse(1, numel(m.cost_f));
row(m.indices.O1_HB_change(:)) = 1;
m.p.Aineq = [m.p.Aineq; row];
m.p.bineq = [m.p.bineq(:); K];
m.count_row = size(m.p.Aineq, 1);
end

function g = scaled_model(m, f, constant, relax)
%SCALED_MODEL 连续功率与库存按1000缩放，整数变量单位保持1；约束不删不放松。
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
%SOLVE_MODEL 单次Gurobi求解；只保留原始返回和还原到原尺度的可行点。
g = scaled_model(m, f, constant, relax);
if ~relax && ~isempty(seed), g.start = seed(:) ./ m.units; end
options = struct('TimeLimit', seconds, 'Threads', cfg.threads, 'Seed', 0, ...
    'MIPGap', 0, 'MIPGapAbs', 0, 'MIPFocus', 1, 'Method', 1, ...
    'FeasibilityTol', 1e-9, 'IntFeasTol', 1e-9, 'OptimalityTol', 1e-9, ...
    'NumericFocus', 2, 'DualReductions', 0, 'StartTimeLimit', 30, ...
    'OutputFlag', 1, 'LogToConsole', 1, 'DisplayInterval', 30, ...
    'LogFile', '', 'ResultFile', '', 'SolFiles', '', 'NodefileStart', Inf);
if isfield(cfg, 'gurobi_params') && isstruct(cfg.gurobi_params)
    % 允许在不改代码的前提下试 Cuts / Heuristics / MIPFocus 等调参。
    for name = fieldnames(cfg.gurobi_params).'
        options.(name{1}) = cfg.gurobi_params.(name{1});
    end
end
for name = fieldnames(extra).'
    options.(name{1}) = extra.(name{1});
end
fprintf('\n[Calculate_K] %s：本片时限=%.0f s，整数变量=%d个。\n', ...
    label, seconds, numel(m.p.intcon));
raw = gurobi(g, options);
run = struct('raw', raw, 'status', string(raw.status), 'x', []);
if isfield(raw, 'x') && numel(raw.x) == numel(m.units) && all(isfinite(raw.x))
    run.x = raw.x(:) .* m.units;
end
end

function cached = read_cache_header(file, signature, want_solutions)
%READ_CACHE_HEADER 读缓存的参考成本与点数；需要热启动时才附带可行解。
cached = struct('exists', isfile(file), 'signature_matches', false, ...
    'point_count', 0, 'solutions', {{}}, ...
    'reference_left', NaN, 'reference_right', NaN, 'K_upper', NaN);
if ~cached.exists, return; end
try
    loaded = load(file);
catch exception
    fprintf('[Calculate_K] 缓存无法读取：%s\n', exception.message);
    return
end
cached.signature_matches = isfield(loaded, 'signature') && ...
    isequaln(loaded.signature, signature);
if ~cached.signature_matches
    fprintf('[Calculate_K] 缓存签名与当前模型不一致，本次不写入。\n');
    return
end
if ~isfield(loaded, 'state'), return; end
state = loaded.state;
if isfield(state, 'points')
    cached.point_count = numel(state.points);
    if want_solutions
        for j = 1:numel(state.points)
            if isfield(state.points(j), 'has_incumbent') && ...
                    state.points(j).has_incumbent && ...
                    isfield(state.points(j), 'solution')
                cached.solutions{end+1} = state.points(j).solution;
            end
        end
    end
end
if isfield(state, 'reference')
    if want_solutions && isfield(state.reference, 'solution')
        cached.solutions{end+1} = state.reference.solution;
    end
    if isfield(state.reference, 'objective_lower')
        cached.reference_left = state.reference.objective_lower;
    end
    if isfield(state.reference, 'objective_upper')
        cached.reference_right = state.reference.objective_upper;
    end
end
if isfield(state, 'Keco_upper'), cached.K_upper = state.Keco_upper; end
fprintf('[Calculate_K] 缓存可读：%d个成本点，参考成本=[%.6f, %.6f] USD。\n', ...
    cached.point_count, cached.reference_left, cached.reference_right);
end

function [seed, seed_point] = pick_seed(ctx, m, cfg)
%PICK_SEED 从缓存里挑一个满足本K预算且成本最低的可行解，仅作初始上界。
seed = [];
seed_point = struct('cost', NaN, 'count', NaN);
for i = 1:numel(ctx.cached.solutions)
    candidate = check_point(ctx.cached.solutions{i}, m, ctx, cfg);
    if candidate.valid && (isnan(seed_point.cost) || candidate.cost < seed_point.cost)
        seed = candidate.x;
        seed_point = struct('cost', candidate.cost, 'count', candidate.count);
    end
end
end

function point = check_point(solution, m, ctx, cfg)
%CHECK_POINT 原年度矩阵、原整数集、平台语义与成本口径的完整复核。
point = empty_point(cfg.K);
point.cost = Inf;
point.valid = false;
point.x = [];
point.residual = NaN;
if ~isstruct(solution) || isempty(fieldnames(solution)), return; end
if ~isfield(solution, 'HB_load'), return; end
[solution, ok] = restore_platforms(solution, ctx, cfg);
if ~ok, return; end
x = solution_vector(m.indices, solution, numel(m.p.lb));
if isempty(x) || any(~isfinite(x)), return; end
residual = max([0; m.p.Aineq * x - m.p.bineq(:); ...
    abs(m.p.Aeq * x - m.p.beq(:)); m.p.lb(:) - x; x - m.p.ub(:)]);
integer_error = max([0; abs(x(m.p.intcon) - round(x(m.p.intcon)))]);
if residual > cfg.constraint_tolerance || integer_error > cfg.integer_tolerance
    return
end
point.count = round(sum(solution.O1_HB_change(:)));
if point.count > cfg.K, return; end
point.cost = double(evaluate(ctx.cost_expression, solution));
if ~isfinite(point.cost), return; end
point.valid = true;
point.solution = solution;
point.x = x;
point.residual = residual;
end

function [solution, ok] = restore_platforms(solution, ctx, cfg)
%RESTORE_PLATFORMS 循环零更新平台必须有共同跟踪区间，不能只做逐边容差判断。
ok = false;
T = ctx.T;
if ~isfield(solution, 'HB_load'), return; end
if ~all(isfield(solution, {'O1_HB_setpoint', 'O1_HB_change'}))
    % 缓存候选可能只带实际负荷；此时以s=h重建并允许全部边更新。
    h = solution.HB_load(:);
    solution.O1_HB_setpoint = h;
    solution.O1_HB_change = double([h(2:end); h(1)] ~= h);
end
h = solution.HB_load(:); s = solution.O1_HB_setpoint(:); z = solution.O1_HB_change(:);
if numel(h) ~= T || numel(s) ~= T || numel(z) ~= T || any(~isfinite([h; s; z]))
    return
end
if max(abs(z - round(z))) > cfg.integer_tolerance, return; end
z = round(z);
if any(z ~= 0 & z ~= 1), return; end
half = cfg.tracking_width / 2;
tiny = 1e-12 * max(1, max(abs(h)));
cuts = find(z == 1);
if isempty(cuts)
    order = (1:T).';
    ends = T;
else
    order = mod(cuts(1) + (0:T-1).', T) + 1;
    ends = find(z(order) == 1);
end
first = 1;
for last = ends(:).'
    hours = order(first:last);
    low = max([h(hours) - half; ctx.params.HB.min_load]);
    high = min([h(hours) + half; ctx.params.HB.max_load]);
    if low > high + 2 * tiny, return; end
    if low <= high
        value = min(high, max(low, s(hours(1))));
    else
        value = (low + high) / 2;
    end
    s(hours) = value;
    first = last + 1;
end
ds = [s(2:end); s(1)] - s;
z = double(ds ~= 0);
if max(abs(h - s)) > half + tiny || ...
        any(s < ctx.params.HB.min_load - tiny | s > ctx.params.HB.max_load + tiny) || ...
        max(abs(ds) - (ctx.R + cfg.tracking_width) * z) > 2 * tiny
    return
end
solution.O1_HB_setpoint = s;
solution.O1_HB_change = z;
ok = true;
end

function x = solution_vector(indices, solution, n)
%SOLUTION_VECTOR 按变量名恢复完整列向量；缺变量或维度不符时返回空。
x = [];
if ~isstruct(solution), return; end
x = zeros(n, 1);
for name = fieldnames(indices).'
    index = indices.(name{1});
    if ~isfield(solution, name{1}), x = []; return; end
    value = solution.(name{1});
    if numel(value) ~= numel(index), x = []; return; end
    x(index(:)) = value(:);
end
end

function solution = vector_solution(x, indices)
%VECTOR_SOLUTION 按变量名切分列向量。
solution = struct();
for name = fieldnames(indices).'
    index = indices.(name{1});
    solution.(name{1}) = reshape(x(index(:)), size(index));
end
end

function lower = global_lower(run, guard)
%GLOBAL_LOWER 只接纳正常终止或限时的全局界；数值异常状态不提供排除证据。
lower = -Inf;
allowed = {'OPTIMAL', 'TIME_LIMIT', 'NODE_LIMIT', 'ITERATION_LIMIT', ...
    'SOLUTION_LIMIT', 'WORK_LIMIT', 'INTERRUPTED', 'USER_OBJ_LIMIT'};
if ~any(strcmp(char(run.status), allowed)), return; end
value = Inf;
found = false;
for name = {'objboundc', 'objbound'}
    if isfield(run.raw, name{1}) && isfinite(run.raw.(name{1}))
        value = min(value, run.raw.(name{1}));
        found = true;
    end
end
if ~found, return; end
lower = value - max(guard, 1e-9 * max(1, abs(value)));
end

function record = feasible_record(cfg, candidate, cost_lower, solver_status, elapsed_s)
%FEASIBLE_RECORD 构造可写入缓存的固定K成本点。
record = empty_point(cfg.K);
record.cost_lower_usd = cost_lower;
record.cost_upper_usd = candidate.cost;
record.has_incumbent = true;
record.solution = candidate.solution;
record.count_upper = candidate.count;
record.is_infeasible = false;
record.status = "unknown";
record.attempts = 1;
record.elapsed_s = elapsed_s;
record.solver_status = solver_status;
record.source = "Calculate_K_fixed_budget";
record.matrix_violation = candidate.residual;
end

function record = infeasible_record(cfg, solver_status, elapsed_s)
%INFEASIBLE_RECORD 只有求解器证明不可行时才登记的排除证据。
record = empty_point(cfg.K);
record.cost_lower_usd = Inf;
record.cost_upper_usd = Inf;
record.has_incumbent = false;
record.count_upper = cfg.K;
record.is_infeasible = true;
record.status = "rejected";
record.attempts = 1;
record.elapsed_s = elapsed_s;
record.solver_status = solver_status;
record.source = "Calculate_K_infeasible";
record.matrix_violation = NaN;
end

function written = write_cache_point(ctx, cfg, record)
%WRITE_CACHE_POINT 把成本点合并进缓存，其余状态原样保留。
file = ctx.cache_file;
assert(isfile(file), 'Calculate_K:no_cache', ...
    '未找到经济阈值缓存%s；请先运行一次main生成缓存。', file);
loaded = load(file);
assert(isfield(loaded, 'schema_version') && loaded.schema_version == 1, ...
    'Calculate_K:bad_schema', '缓存schema_version不是1，拒绝改写。');
assert(isfield(loaded, 'signature') && isequaln(loaded.signature, ctx.cost_signature), ...
    'Calculate_K:signature', ...
    '当前模型与缓存签名不一致，拒绝写入：请先运行main重建缓存。');
assert(isfield(loaded, 'state'), 'Calculate_K:bad_state', '缓存缺少state字段。');
state = loaded.state;
if ~isfield(state, 'points')
    state.points = repmat(empty_point(0), 0, 1);
end
prior_count = numel(state.points);
[state.points, replaced] = merge_point(state.points, record, record.K);
point_count = numel(state.points);
payload = rmfield(loaded, 'state');
payload.state = state;
temporary = [file, '.tmp.mat'];
cleanup = onCleanup(@() delete_if_exists(temporary));
save(temporary, '-struct', 'payload', '-v7.3');
check = load(temporary);
assert(isfield(check, 'schema_version') && check.schema_version == 1 && ...
    isequaln(check.signature, loaded.signature) && ...
    isfield(check, 'state') && numel(check.state.points) == point_count, ...
    'Calculate_K:verify_failed', '写入前校验失败，原缓存未改动。');
movefile(temporary, file, 'f');
written = true;
fprintf(['[Calculate_K] 缓存已更新：成本点 %d -> %d（%s），source=%s；' ...
    '参考解、成本帽与分区证书保持不变。\n'], prior_count, point_count, ...
    ternary(replaced, '替换同K记录', '新增'), char(record.source));
report_effect(ctx, cfg, record);
end

function report_effect(ctx, cfg, record)
%REPORT_EFFECT 报告该点在需求—成本前沿上的位置，并说明对main区间的潜在作用。
if record.is_infeasible
    fprintf(['[Calculate_K] K=%d已由求解器证明不可行；main读取后会把它当作' ...
        '排除证据，K_lower>=%d。\n'], record.K, record.K + 1);
    return
end
if isfinite(ctx.cached.reference_left)
    overrun = record.cost_upper_usd - ctx.cached.reference_left;
    fprintf(['[Calculate_K] 相对参考下界的成本溢价=%.3f USD（%.6f USD/t）；' ...
        '前沿坐标=(K=%d, 溢价=%.3f USD)。\n'], ...
        overrun, overrun / cfg.target_t, record.K, overrun);
end
if isfinite(ctx.cached.K_upper) && record.count_upper < ctx.cached.K_upper
    fprintf(['[Calculate_K] 计数%g低于缓存中的现有上界%g；' ...
        'main读取后由自身经济帽判定是否据此收紧K_upper。\n'], ...
        record.count_upper, ctx.cached.K_upper);
else
    fprintf(['[Calculate_K] 该点已入库，供main与前沿分析使用；' ...
        '经济合格性由main按自身delta判定。\n']);
end
end

function [points, replaced] = merge_point(points, record, K)
%MERGE_POINT 与O1Economics一致：下界取大、上界取优、计数随上界更新。
if isempty(points)
    prior = empty_point(K);
    replaced = false;
else
    template = points(1);
    index = find([points.K] == K, 1);
    if isempty(index)
        prior = template;
        prior.K = K;
        prior.cost_lower_usd = -Inf;
        prior.cost_upper_usd = Inf;
        prior.has_incumbent = false;
        prior.solution = struct();
        prior.count_upper = K;
        prior.is_infeasible = false;
        prior.status = "unknown";
        prior.attempts = 0;
        prior.elapsed_s = 0;
        prior.solver_status = "";
        prior.source = "";
        prior.matrix_violation = NaN;
        replaced = false;
    else
        prior = points(index);
        replaced = true;
    end
end
prior.cost_lower_usd = max(prior.cost_lower_usd, record.cost_lower_usd);
prior.is_infeasible = prior.is_infeasible || record.is_infeasible;
if record.has_incumbent && (record.cost_upper_usd < prior.cost_upper_usd || ...
        (record.cost_upper_usd == prior.cost_upper_usd && ...
        ~isempty(fieldnames(record.solution))))
    prior.has_incumbent = true;
    prior.cost_upper_usd = record.cost_upper_usd;
    prior.count_upper = record.count_upper;
    prior.solution = record.solution;
    prior.matrix_violation = record.matrix_violation;
end
prior.attempts = max(prior.attempts, record.attempts);
prior.elapsed_s = prior.elapsed_s + record.elapsed_s;
if strlength(record.solver_status) > 0, prior.solver_status = record.solver_status; end
prior.source = record.source;
index = find([points.K] == K, 1);
if isempty(index)
    points(end+1, 1) = prior;
else
    points(index) = prior;
end
[~, order] = sort([points.K]);
points = points(order);
end

function point = empty_point(K)
%EMPTY_POINT 与O1Economics同字段顺序的成本点模板。
point = struct('K', K, 'cost_lower_usd', -Inf, 'cost_upper_usd', Inf, ...
    'has_incumbent', false, 'solution', struct(), 'count_upper', K, ...
    'is_infeasible', false, 'status', "unknown", 'attempts', 0, ...
    'elapsed_s', 0, 'solver_status', "", 'source', "", ...
    'matrix_violation', NaN);
end

function out = ternary(condition, when_true, when_false)
%TERNARY 单行条件选择，避免在fprintf参数里写分支。
if condition
    out = when_true;
else
    out = when_false;
end
end

function delete_if_exists(file)
%DELETE_IF_EXISTS 清除本次临时文件；正式缓存从不留副本。
if isfile(file)
    delete(file);
end
end

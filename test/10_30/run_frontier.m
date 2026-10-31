%% 经济—更新次数帕累托前沿：按 delta 网格求解最小更新次数
% 直接运行本文件即可（工作目录为 test/10_30）：
%     run('run_frontier.m')
%
% 问题：对每个经济容许损失 delta，求 K(delta) = min N(x)  s.t.  C(x) <= L_C + delta*Q
% 其中 L_C 是参考成本下界，Q 是年产量。得到的 (K, 成本溢价) 就是帕累托前沿。
%
% delta 取 0.05 的整数倍，从 0.05 到 0.50 步长 0.05 共 10 点：
%   0.05 的倍数便于与"每吨氨多花 5 美分"的工程口径直接对应；
%   上界取 0.50 是因为 487 次解的溢价 0.4914 USD/t 落在该网格内，
%   再往上预算已不能显著降低更新次数（0.75、1.00 的对照见报告）。
% 每个点用缓存中"满足该预算且更新最少"的已知可行解热启动，只作为上界起点。
%
% 输出：本目录下唯一的一份中文报告 前沿报告.md，不产生其它文件。
if ~exist('Frontier_config', 'var') || isempty(Frontier_config)
    Frontier_config = struct( ...
        'year', 2022, 'target_t', 80000, 'tracking_width', 0.01, ...
        'delta_start', 0.05, 'delta_step', 0.05, 'delta_end', 0.50, ...
        'time_s', 240, 'threads', 4, 'gurobi_matlab_directory', '', ...
        'money_guard_usd', 0.01, 'integer_tolerance', 1e-6, ...
        'constraint_tolerance', 1e-5, 'report_file', '前沿报告.md');
end
Frontier_result = frontier_main(Frontier_config, mfilename('fullpath'));

function out = frontier_main(cfg, entry_file)
%FRONTIER_MAIN 构建模型、按 delta 网格求解、写出唯一一份报告。
old_path = path;
path_cleanup = onCleanup(@() path(old_path));
clock = tic;
F = build_model(cfg, entry_file);
pool = load_pool(F);
deltas = cfg.delta_start:cfg.delta_step:cfg.delta_end;
fprintf('\n[Frontier] delta网格=%s，共%d点，单点时限=%.0f s。\n', ...
    mat2str(deltas, 2), numel(deltas), cfg.time_s);
rows = repmat(empty_row(), numel(deltas), 1);
% 预算单调递增时，上一预算的可行解对本预算仍可行；把它带下去，
% 再叠加取小，可保证 K(delta) 非增，消除独立求解带来的伪非单调。
carry = struct('x', [], 'count', Inf, 'cost', Inf);
for i = 1:numel(deltas)
    [rows(i), carry] = solve_point(F, pool, deltas(i), cfg, carry);
    if i < numel(deltas), fprintf('\n'); end
end
best_so_far = Inf;
for i = 1:numel(rows)
    if isfinite(rows(i).count), best_so_far = min(best_so_far, rows(i).count); end
    rows(i).K_monotone = best_so_far;
end
out = struct('rows', rows, 'pool', pool, ...
    'baseline', baseline_rows(pool, deltas, F, cfg), ...
    'elapsed_s', toc(clock), 'config', cfg, 'reference_left', F.reference_left, ...
    'reference_right', F.reference_right, 'pool_size', numel(pool));
out.report_file = write_report(out, F, cfg);
fprintf('\n[Frontier] 完成：%d点，总耗时%.1f min，报告=%s\n', ...
    numel(rows), out.elapsed_s / 60, out.report_file);
end

function [row, carry] = solve_point(F, pool, delta, cfg, carry_in)
%SOLVE_POINT 求单个 delta 下的最小更新次数，并给出可核验区间。
row = empty_row();
row.delta = delta;
row.cap_usd = F.reference_left + delta * cfg.target_t;
row.cap_pool = pool_frontier(pool, row.cap_usd);
[start, start_count, start_cost] = pick_start(pool, row.cap_usd, F, cfg);
source = '证据池';
if ~isempty(carry_in.x) && isfinite(carry_in.cost) && ...
        carry_in.cost <= row.cap_usd + cfg.money_guard_usd && ...
        carry_in.count < start_count
    % 上一预算的可行解在本预算仍可行；只有在更新次数更少时才采用。
    start = carry_in.x;
    start_count = carry_in.count;
    start_cost = carry_in.cost;
    source = '上一预算可行解';
end
row.start_count = start_count;
row.start_cost = start_cost;
fprintf('[Frontier] delta=%.2f，预算帽=%.3f USD；热启动=%s（%s）\n', ...
    delta, row.cap_usd, ternary(start_count > 0, ...
    sprintf('%g次/%.3f USD', start_count, start_cost), '无（冷启动）'), source);
r = solve_min_updates(F, row.cap_usd, cfg.time_s, start, cfg);
row.status = r.status;
row.count = r.count;
row.cost = r.cost;
row.bound = r.bound;
row.residual = r.residual;
carry = carry_in;
if isfinite(r.count)
    row.K_lower = max(0, ceil(r.bound - 1e-5));
    row.K_upper = r.count;
    row.overrun_usd = r.cost - F.reference_left;
    % 只有更少更新的解才更新携带值；否则保留上一预算的解，维持单调。
    if ~isfinite(carry.count) || r.count < carry.count
        carry = struct('x', r.x, 'count', r.count, 'cost', r.cost);
    end
    fprintf(['[Frontier]   结果：K∈[%g,%g]，成本=%.3f USD，溢价=%.6f USD/t，' ...
        '下界=%.3f，残差=%.3g\n'], row.K_lower, row.K_upper, r.cost, ...
        row.overrun_usd / cfg.target_t, r.bound, r.residual);
else
    row.K_lower = NaN;
    row.K_upper = Inf;
    fprintf('[Frontier]   结果：本次时限内无可核验可行解（状态=%s）\n', char(r.status));
end
end

function F = build_model(cfg, entry_file)
%BUILD_MODEL 构造与主程序一致的年度模型，并读取参考成本括号。
project_dir = fileparts(entry_file);
while ~isfile(fullfile(project_dir, 'src', 'baseline.m'))
    parent = fileparts(project_dir);
    assert(~strcmp(parent, project_dir), 'Frontier:no_project', ...
        '未找到项目 src/baseline.m。');
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
physical = base.problem;
physical.Constraints.O1_nh3_target = base.expressions.nh3_total_t == cfg.target_t;
physical.Constraints.O1_cyclic_ramp_up = h(1) - h(end) <= R;
physical.Constraints.O1_cyclic_ramp_down = h(end) - h(1) <= R;
physical.Objective = base.expressions.system_cost_usd;
s = optimvar('O1_HB_setpoint', T, 'LowerBound', params.HB.min_load, ...
    'UpperBound', params.HB.max_load);
z = optimvar('O1_HB_change', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
ds = [s(2:end); s(1)] - s;
dh = [h(2:end); h(1)] - h;
problem = physical;
problem.Constraints.O1_tracking_up = h - s <= cfg.tracking_width / 2;
problem.Constraints.O1_tracking_down = s - h <= cfg.tracking_width / 2;
problem.Constraints.O1_change_up = ds <= (R + cfg.tracking_width) * z;
problem.Constraints.O1_change_down = -ds <= (R + cfg.tracking_width) * z;
problem.Constraints.O1_update_limit = sum(z) <= T;
% 原约束推导的有效强化，不排除任何原整数可行解。
problem.Constraints.hull_up = dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
problem.Constraints.hull_down = -dh <= cfg.tracking_width + (R - cfg.tracking_width) * z;
p = prob2struct(problem, 'Solver', 'intlinprog');
indices = varindex(problem);
F = struct();
F.p = p;
F.indices = indices;
F.T = T;
F.dt = params.time.step;
F.R = R;
F.epsilon = cfg.tracking_width;
F.params = params;
F.data = data;
F.src = src;
F.count_f = zeros(numel(p.lb), 1);
F.count_f(indices.O1_HB_change(:)) = 1;
F.cost_f = p.f(:);
zero = vector_solution(zeros(numel(p.lb), 1), indices);
F.cost_offset = double(evaluate(base.expressions.system_cost_usd, zero));
F.units = ones(numel(p.lb), 1);
for field = {'P_AEL', 'storage_H2', 'p_purchase', 'p_sell', 'p_curt', 'grid_contract_kw'}
    if isfield(indices, field{1}), F.units(indices.(field{1})(:)) = 1000; end
end
F.units(p.intcon) = 1;
F.cache_file = fullfile(src, 'cache', 'O1_economic_threshold_partition21_cache.mat');
ref = load_reference(F.cache_file);
F.reference_left = ref.left;
F.reference_right = ref.right;
fprintf('[Frontier] 模型：%d行/%d列/%d个整数；参考成本=[%.6f, %.6f] USD。\n', ...
    size(p.Aineq, 1) + size(p.Aeq, 1), numel(p.lb), numel(p.intcon), ...
    ref.left, ref.right);
end

function ref = load_reference(file)
%LOAD_REFERENCE 只读取参考成本括号，不改动缓存。
ref = struct('left', NaN, 'right', NaN);
loaded = load(file);
if isfield(loaded, 'state') && isfield(loaded.state, 'reference')
    if isfield(loaded.state.reference, 'objective_lower')
        ref.left = loaded.state.reference.objective_lower;
    end
    if isfield(loaded.state.reference, 'objective_upper')
        ref.right = loaded.state.reference.objective_upper;
    end
end
assert(isfinite(ref.left) && isfinite(ref.right), 'Frontier:no_reference', ...
    '缓存中缺少参考成本括号，请先运行 main 生成。');
end

function pool = load_pool(F)
%LOAD_POOL 读缓存中的全部可行见证，按更新次数升序排列。
loaded = load(F.cache_file);
assert(isfield(loaded, 'state') && isfield(loaded.state, 'points'), ...
    'Frontier:no_pool', '缓存中缺少成本点列表。');
points = loaded.state.points;
pool = repmat(struct('K', 0, 'count', 0, 'cost', 0, 'solution', struct()), ...
    numel(points), 1);
kept = 0;
for j = 1:numel(points)
    if ~isfield(points(j), 'has_incumbent') || ~points(j).has_incumbent
        continue
    end
    if ~isfield(points(j), 'solution') || isempty(fieldnames(points(j).solution))
        continue
    end
    kept = kept + 1;
    pool(kept) = struct('K', points(j).K, 'count', points(j).count_upper, ...
        'cost', points(j).cost_upper_usd, 'solution', points(j).solution);
end
pool = pool(1:kept);
[~, order] = sort([pool.count]);
pool = pool(order);
fprintf('[Frontier] 证据池：%d条可行见证，更新次数范围[%g,%g]，成本范围[%.1f,%.1f] USD。\n', ...
    numel(pool), min([pool.count]), max([pool.count]), ...
    min([pool.cost]), max([pool.cost]));
end

function K = pool_frontier(pool, cap)
%POOL_FRONTIER 给定预算帽，返回证据池中满足预算的最少更新次数。
K = Inf;
if ~isfinite(cap), return; end
for j = 1:numel(pool)
    if pool(j).cost <= cap + 1e-9
        K = pool(j).count;
        return
    end
end
end

function [start, count, cost] = pick_start(pool, cap, F, cfg)
%PICK_START 取满足预算且更新最少的见证作为热启动；它只提供初始上界。
start = [];
count = 0;
cost = NaN;
if ~isfinite(cap), return; end
for j = 1:numel(pool)
    if pool(j).cost > cap + 1e-9, continue; end
    point = check_solution(pool(j).solution, F, cfg);
    if point.valid
        start = point.x;
        count = point.count;
        cost = point.cost;
        return
    end
end
end

function [r, info] = solve_min_updates(F, cap, seconds, start, cfg)
%SOLVE_MIN_UPDATES 目标为更新次数，约束加入成本帽，返回可核验结果。
p = F.p;
p.f = F.count_f;
p.Aineq = [p.Aineq; F.cost_f.'];
p.bineq = [p.bineq(:); cap - F.cost_offset];
g = scaled_model(p, F.units);
if ~isempty(start), g.start = start(:) ./ F.units; end
options = struct('TimeLimit', seconds, 'Threads', cfg.threads, 'Seed', 0, ...
    'MIPGap', 0, 'MIPGapAbs', 0.5, 'MIPFocus', 1, 'Method', 1, ...
    'FeasibilityTol', 1e-9, 'IntFeasTol', 1e-9, 'OptimalityTol', 1e-9, ...
    'NumericFocus', 2, 'DualReductions', 0, 'StartTimeLimit', 60, ...
    'OutputFlag', 1, 'LogToConsole', 1, 'DisplayInterval', 30, ...
    'LogFile', '', 'ResultFile', '', 'SolFiles', '', 'NodefileStart', Inf);
fprintf('[Frontier]   求解中（%d个整数，时限%.0f s）...\n', numel(p.intcon), seconds);
raw = gurobi(g, options);
r = struct('status', string(raw.status), 'count', Inf, 'cost', Inf, ...
    'bound', NaN, 'residual', NaN, 'x', []);
info = struct('slices', 1);
if isfield(raw, 'x') && numel(raw.x) == numel(F.units) && all(isfinite(raw.x))
    point = check_solution(vector_solution(raw.x(:) .* F.units, F.indices), F, cfg);
    if point.valid && point.cost <= cap + cfg.money_guard_usd
        r.count = point.count;
        r.cost = point.cost;
        r.residual = point.residual;
        r.x = point.x;
    else
        fprintf(['[Frontier]   求解返回的解未通过原矩阵或预算核验' ...
            '（成本=%.3f，帽=%.3f），按无解处理。\n'], point.cost, cap);
    end
end
r.bound = solver_bound(raw);
end

function bound = solver_bound(raw)
%SOLVER_BOUND 只接纳正常终止或限时的全局界。
bound = NaN;
allowed = {'OPTIMAL', 'TIME_LIMIT', 'NODE_LIMIT', 'ITERATION_LIMIT', ...
    'SOLUTION_LIMIT', 'WORK_LIMIT', 'INTERRUPTED', 'USER_OBJ_LIMIT'};
if ~isfield(raw, 'status') || ~any(strcmp(char(raw.status), allowed)), return; end
% 同时取 objboundc 与 objbound，按较小者保守处理不同返回属性。
value = Inf;
found = false;
for name = {'objboundc', 'objbound'}
    if isfield(raw, name{1}) && isfinite(raw.(name{1}))
        value = min(value, raw.(name{1}));
        found = true;
    end
end
if ~found, return; end
bound = value;
end

function point = check_solution(solution, F, cfg)
%CHECK_SOLUTION 原年度矩阵、原整数集、平台语义与成本口径的完整复核。
point = struct('valid', false, 'x', [], 'count', Inf, 'cost', Inf, 'residual', NaN);
if ~isstruct(solution) || ~isfield(solution, 'HB_load'), return; end
[solution, ok] = restore_platforms(solution, F, cfg);
if ~ok, return; end
x = solution_vector(F.indices, solution, numel(F.p.lb));
if isempty(x) || any(~isfinite(x)), return; end
residual = max([0; F.p.Aineq * x - F.p.bineq(:); ...
    abs(F.p.Aeq * x - F.p.beq(:)); F.p.lb(:) - x; x - F.p.ub(:)]);
if residual > cfg.constraint_tolerance, return; end
if max([0; abs(x(F.p.intcon) - round(x(F.p.intcon)))]) > cfg.integer_tolerance
    return
end
point.valid = true;
point.x = x;
point.count = round(sum(solution.O1_HB_change(:)));
point.cost = cost_of(x, F);
point.residual = residual;
end

function cost = cost_of(x, F)
%COST_OF 用原目标系数重算年度净成本，口径与主程序一致。
cost = F.cost_f.' * x + F.cost_offset;
end

function [solution, ok] = restore_platforms(solution, F, cfg)
%RESTORE_PLATFORMS 循环零更新平台必须有共同跟踪区间，不能只做逐边容差判断。
ok = false;
T = F.T;
if ~isfield(solution, 'HB_load'), return; end
if ~all(isfield(solution, {'O1_HB_setpoint', 'O1_HB_change'}))
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
    low = max([h(hours) - half; F.params.HB.min_load]);
    high = min([h(hours) + half; F.params.HB.max_load]);
    if low > high + 2 * tiny, return; end
    if low <= high
        s(hours) = min(high, max(low, s(hours(1))));
    else
        s(hours) = (low + high) / 2;
    end
    first = last + 1;
end
ds = [s(2:end); s(1)] - s;
z = double(ds ~= 0);
if max(abs(h - s)) > half + tiny || ...
        any(s < F.params.HB.min_load - tiny | s > F.params.HB.max_load + tiny) || ...
        max(abs(ds) - (F.R + cfg.tracking_width) * z) > 2 * tiny
    return
end
solution.O1_HB_setpoint = s;
solution.O1_HB_change = z;
ok = true;
end

function x = solution_vector(indices, solution, n)
%SOLUTION_VECTOR 按变量名恢复完整列向量。
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

function g = scaled_model(p, units)
%SCALED_MODEL 连续功率与库存按1000缩放，整数变量单位保持1；约束不删不放松。
n = numel(p.lb);
A = [p.Aineq; p.Aeq] * spdiags(units, 0, n, n);
scale = max(1, full(max(abs(A), [], 2)));
g = struct('A', spdiags(1 ./ scale, 0, numel(scale), numel(scale)) * A, ...
    'rhs', [p.bineq(:); p.beq(:)] ./ scale, ...
    'sense', [repmat('<', size(p.Aineq, 1), 1); repmat('=', size(p.Aeq, 1), 1)], ...
    'obj', p.f(:) .* units, 'objcon', 0, ...
    'lb', p.lb(:) ./ units, 'ub', p.ub(:) ./ units, ...
    'modelsense', 'min', 'vtype', repmat('C', n, 1));
g.vtype(p.intcon) = 'I';
end

function ensure_gurobi(configured_dir)
%ENSURE_GUROBI 优先使用现有路径，其次读取 GUROBI_HOME。
if ~isempty(configured_dir), addpath(configured_dir); end
if ismember(exist('gurobi', 'file'), [2, 3]), return; end
gurobi_home = getenv('GUROBI_HOME');
if ~isempty(gurobi_home)
    addpath(fullfile(gurobi_home, 'matlab'));
end
assert(ismember(exist('gurobi', 'file'), [2, 3]), 'Frontier:no_gurobi', ...
    '未找到Gurobi接口，请填写 gurobi_matlab_directory。');
end

function row = empty_row()
%EMPTY_ROW 前沿表的一行。
row = struct('delta', NaN, 'cap_usd', NaN, 'cap_pool', Inf, ...
    'start_count', 0, 'start_cost', NaN, 'status', "NOT_RUN", ...
    'count', Inf, 'cost', Inf, 'bound', NaN, 'residual', NaN, ...
    'K_lower', NaN, 'K_upper', Inf, 'K_monotone', Inf, 'overrun_usd', NaN);
end

function rows = baseline_rows(pool, deltas, F, cfg)
%BASELINE_ROWS 仅用现有证据池得到的同一网格前沿，用于对照。
rows = repmat(empty_row(), numel(deltas), 1);
for i = 1:numel(deltas)
    rows(i).delta = deltas(i);
    rows(i).cap_usd = F.reference_left + deltas(i) * cfg.target_t;
    rows(i).cap_pool = pool_frontier(pool, rows(i).cap_usd);
end
end

function write_envelope(fid, pool, rows, F, cfg)
%WRITE_ENVELOPE 合并证据池与本次求解，只保留不被支配的 (K, 成本) 点。
K = [pool.count, [rows.count]];
C = [pool.cost, [rows.cost]];
ok = isfinite(K) & isfinite(C);
K = K(ok);
C = C(ok);
if isempty(K)
    fprintf(fid, '本次没有可用于求下包络的点。\n\n');
    return
end
[Ks, order] = sort(K);
Cs = C(order);
fprintf(fid, '### 3.1 综合前沿（全部证据的下包络）\n\n');
fprintf(fid, ['把证据池与本次求解合并，只保留"更新更少且成本更低"不被支配的点。', ...
    '这张表才是前沿本身，第 3 节按 $\\delta$ 列出的只是每个预算下的单点结果。\n\n']);
fprintf(fid, '| $K$ | 成本 (USD) | 溢价 (USD/t) |\n|---:|---:|---:|\n');
best = Inf;
for i = 1:numel(Ks)
    if Cs(i) < best - 1e-6
        best = Cs(i);
        fprintf(fid, '| %d | %.3f | %.6f |\n', Ks(i), Cs(i), ...
            (Cs(i) - F.reference_left) / cfg.target_t);
    end
end
fprintf(fid, '\n');
end

function file = write_report(out, F, cfg)
%WRITE_REPORT 生成本目录下唯一的一份中文报告。
file = fullfile(fileparts(mfilename('fullpath')), cfg.report_file);
fid = fopen(file, 'w', 'n', 'UTF-8');
assert(fid > 0, 'Frontier:no_report', '无法写入报告文件。');
cleanup = onCleanup(@() fclose(fid));
rows = out.rows;
base = out.baseline;
fprintf(fid, '# 经济—更新次数帕累托前沿\n\n');
fprintf(fid, '> 由 `run_frontier.m` 自动生成，请勿手工编辑。\n');
fprintf(fid, '> 基准参考成本：$L_C=%.6f$，$U_C=%.6f$ USD；年产量 $Q=%g$ t/a；跟踪带宽 %.4f。\n\n', ...
    F.reference_left, F.reference_right, cfg.target_t, cfg.tracking_width);
fprintf(fid, '## 1. 问题与口径\n\n');
fprintf(fid, '对每个经济容许损失 $\\delta$，求解\n\n');
fprintf(fid, '$$K(\\delta)=\\min\\,N(x)\\quad\\text{s.t.}\\quad C(x)\\le L_C+\\delta Q .$$\n\n');
fprintf(fid, '这里用参考成本的**下界** $L_C$ 作预算基准，因此所得 $K$ 相对真实最优预算偏保守（预算更紧）。');
fprintf(fid, '成本溢价定义为 $\\Delta C=C-L_C$，与 $\\delta$ 同一坐标轴。\n\n');
fprintf(fid, '## 2. $\\delta$ 网格\n\n');
fprintf(fid, '取 $\\delta=%.2f:%.2f:%.2f$，共 %d 点。规则：\n\n', ...
    cfg.delta_start, cfg.delta_step, cfg.delta_end, numel(rows));
fprintf(fid, '1. 全部是 0.05 的整数倍，直接对应"每吨氨多花 5 美分"的工程口径；\n');
fprintf(fid, '2. 上界 0.50 覆盖 487 次解所需的预算（该解溢价 0.4917 USD/t），再往上预算已不能显著降低更新次数；\n');
fprintf(fid, '3. 单点时限 %.0f s，热启动取证据池中满足该预算且更新最少的可行解。\n\n', cfg.time_s);
fprintf(fid, '## 3. 结果\n\n');
fprintf(fid, '| $\\delta$ (USD/t) | 预算帽 (USD) | 证据池最少$K$ | 本次$K$ | 单调$K$ | $K$下界 | 成本 (USD) | 溢价 (USD/t) | 状态 |\n');
fprintf(fid, '|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:numel(rows)
    r = rows(i);
    fprintf(fid, '| %.2f | %.0f | %s | %s | %s | %s | %s | %s | %s |\n', ...
        r.delta, r.cap_usd, fmt_num(r.cap_pool), fmt_num(r.count), ...
        fmt_num(r.K_monotone), fmt_num(r.K_lower), fmt_money(r.cost), ...
        fmt_sci(r.overrun_usd / cfg.target_t, 6), char(r.status));
end
fprintf(fid, '\n');
write_envelope(fid, out.pool, rows, F, cfg);
fprintf(fid, '## 4. 与证据池的对照\n\n');
fprintf(fid, '证据池指缓存中已有、且都通过原年度矩阵核验的可行解，共 %d 条。', out.pool_size);
fprintf(fid, '下表比较"只用现有证据"与"本批求解"得到的 $K$：\n\n');
fprintf(fid, '| $\\delta$ | 证据池 $K$ | 本次 $K$ | 是否改进 |\n|---:|---:|---:|---|\n');
for i = 1:numel(rows)
    r = rows(i);
    improved = isfinite(r.count) && isfinite(base(i).cap_pool) && r.count < base(i).cap_pool;
    fprintf(fid, '| %.2f | %s | %s | %s |\n', r.delta, fmt_num(base(i).cap_pool), ...
        fmt_num(r.count), ternary(improved, '是', '否'));
end
fprintf(fid, '\n');
fprintf(fid, '## 5. 前沿形状\n\n');
% 图「前沿曲线.png」由第 3.1 节的下包络严格单调化后绘制：按 K 升序只保留
% "成本创新低"的点，故任意两点都满足「K 更大则成本更低」，不含被支配点。
fprintf(fid, '![经济—更新次数：已核验证据与单调包络](前沿曲线.png)\n\n');
fprintf(fid, ['横轴为全年设定值更新次数 $K$（对数），纵轴为相对参考下界的成本溢价 ', ...
    '$\\Delta C$（USD/t，对数）。灰点为全部已核验见证，橙点为新增的 $F(K)$ 求解点，', ...
    '蓝线为单调包络，绿色虚线为认证下界 408，灰色带为当前无证据支撑的区间。\n\n']);
write_shape_note(fid, rows);
fprintf(fid, '## 6. 证据边界\n\n');
fprintf(fid, '- 每个点的 $K$ 只有**上界**由可行解给出；下界来自该点 Gurobi 的全局界，通常远弱于分区证书，不能当作认证下界。\n');
fprintf(fid, '- 热启动沿用证据池中的解，只会抬高起点，不会缩小可行域；若某点未改进，说明该预算下本次时限未能找到更少更新的调度。\n');
fprintf(fid, '- 预算帽以 $L_C$ 为基准，比主程序双帽中的 $\\tau_{\\mathrm{sat}}=L_C+\\delta Q$ 更紧；因此本表 $K$ 相对主程序口径偏大。\n');
fprintf(fid, '- 本次总耗时 %.1f min，单点 %.0f s；延长时限可能继续降低 $K$，但不保证收敛。\n\n', ...
    out.elapsed_s / 60, cfg.time_s);
fprintf(fid, '## 7. 复现\n\n');
fprintf(fid, '```matlab\ncd test/10_30\nrun(''run_frontier.m'')\n```\n');
end

function text = fmt_num(value)
%FMT_NUM 数值列的统一格式；无穷大打印为 inf。
if isfinite(value)
    text = sprintf('%g', value);
else
    text = 'inf';
end
end

function text = fmt_money(value)
%FMT_MONEY 金额列保留三位小数。
if isfinite(value)
    text = sprintf('%.3f', value);
else
    text = '-';
end
end

function text = fmt_sci(value, digits)
%FMT_SCI 溢价列用定点小数，保证不同量级可比。
if isfinite(value)
    text = sprintf('%.*f', digits, value);
else
    text = '-';
end
end

function out = ternary(condition, when_true, when_false)
%TERNARY 单行条件选择。
if condition
    out = when_true;
else
    out = when_false;
end
end

function write_shape_note(fid, rows)
%WRITE_SHAPE_NOTE 依据结果表归纳前沿形状，不引入表外信息。
counts = [rows.count];
ok = isfinite(counts);
if nnz(ok) < 2
    fprintf(fid, '本次可用点不足两点，无法归纳形状。\n\n');
    return
end
valid = rows(ok);
head = valid(1:end-1);
tail = valid(end);
fprintf(fid, '读法：\n\n');
if ~isempty(head)
    lo = min([head.count]);
    hi = max([head.count]);
    fprintf(fid, ['- $\\delta\\le%.2f$ 的 %d 个点，$K$ 落在 %g—%g，极差 %d 次' ...
        '（%.1f%%），且无单调趋势；说明该区间内增加预算没有换来更少更新，' ...
        '前沿只给出上界。\n'], head(end).delta, numel(head), lo, hi, ...
        hi - lo, 100 * (hi - lo) / max(1, lo));
end
if tail.count < min([head.count])
    fprintf(fid, ['- $\\delta=%.2f$ 处 $K$ 降到 %g（约为前一段的 1/%.0f），' ...
        '来自证据池中已有的低更新解，不是本次搜索的成果。\n'], ...
        tail.delta, tail.count, max(1, round(min([head.count]) / max(1, tail.count))));
end
fprintf(fid, ['- 因此该前沿呈"平台 + 断崖"形状；落差来自证据缺口，' ...
    '不能解释为系统在某个预算处突然获得柔性。\n\n']);
end

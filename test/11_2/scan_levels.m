%% 分块证书：按不同分块粒度 H 重算全局计数下界
% 只读主缓存，不写入任何主程序文件；结果保存在本目录 scan_results.mat。
% 数学口径与 O1Economics.certified_partition_kernel 完全一致：
%   cert(H) = B - guardB + sum_j max( lp_j , safe_j )
% 其中
%   pi      为根 LP 对偶价格（来自 certificate.mat）
%   B       为跨块行 sum(rhs.*pi)
%   lp_j    为第 j 块的局部对偶下界（含 guard）
%   safe_j  为把该块的 z 保持二进制后的 MILP 对偶界（Gurobi objbound，含 guard）
% 对任意可行调度，N = sum(z) >= cert(H)，因此 cert(H) 是 Keco 的合法下界。

clear; clc;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
cert_dir = fullfile(root, 'src', 'cache', 'O1_partition21_v1', ...
    'f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');

ensure_gurobi('');

S = load(fullfile(cert_dir, 'certificate.mat'));
C = load(fullfile(cert_dir, 'context.mat'));
model = C.model; hour = C.hour; z = C.z;
pi = S.proof.pi(:);
s = model.sense(:);
pi(s == '<') = min(0, pi(s == '<'));
pi(s == '>') = max(0, pi(s == '>'));

n = numel(model.obj); T = numel(z);
pattern = spones(model.A);
box = max(abs(model.lb(:)), abs(model.ub(:)));
h = hour(:);
valid = isfinite(h) & h >= 1 & h <= T + 1 & h == round(h);

% 待扫描的分块粒度；先跑中等粒度，再视趋势加密
H_list = [2190 1460 1000 730 500 336 240];
block_limit_s = 90;       % 单块 MILP 时限（对偶界在时限内仍然合法）
threads = 4;

results = struct('H', {}, 'cert', {}, 'cert_lp', {}, 'blocks', {}, ...
    'solver_s', {}, 'l_improved', {});
fprintf('起始：%s\n', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));

for H = H_list
    t0 = tic;
    [B, guardB, cross, cols, rows, q, lp] = build_partition(model, pi, hour, z, H, valid, pattern, box);
    K = numel(cols);
    ell = lp; solver_s = 0; calls = 0;
    for j = 1:K
        cj = cols{j}; ij = rows{j};
        inz = ismember(cj, z);
        if ~any(inz)
            continue
        end
        local = struct('A', model.A(ij, cj), 'rhs', model.rhs(ij), 'sense', s(ij), ...
            'obj', q(cj), 'lb', model.lb(cj), 'ub', model.ub(cj), ...
            'vtype', repmat('C', numel(cj), 1), 'modelsense', 'min');
        local.vtype(inz) = 'B';
        gp = struct('TimeLimit', block_limit_s, 'Threads', threads, 'OutputFlag', 0, ...
            'MIPGap', 0, 'MIPGapAbs', 0, 'FeasibilityTol', 1e-9, 'IntFeasTol', 1e-9, ...
            'OptimalityTol', 1e-9, 'Seed', 20261017);
        ts = tic;
        try
            r = gurobi(local, gp);
        catch
            continue
        end
        solver_s = solver_s + toc(ts); calls = calls + 1;
        safe = mip_safe_bound(local, r);
        if isfinite(safe), ell(j) = max(ell(j), safe); end
    end
    cert = B - guardB + sum(ell);
    results(end+1) = struct('H', H, 'cert', cert, 'cert_lp', B - guardB + sum(lp), ...
        'blocks', K, 'solver_s', solver_s, 'l_improved', sum(ell - lp)); %#ok<SAGROW>
    fprintf('H=%4d  块=%3d  cert=%.6f  (LP部分 %.4f, 整数增益 %.4f)  求解 %.1fs  用时 %.1f min\n', ...
        H, K, cert, B - guardB + sum(lp), sum(ell - lp), solver_s, toc(t0) / 60);
    save(fullfile(fileparts(mfilename('fullpath')), 'scan_results.mat'), 'results');
end

fprintf('\n最佳：H=%d, cert=%.6f -> ceil = %d\n', ...
    results(end).H, max([results.cert]), ceil(max([results.cert]) - 1e-5));
save(fullfile(fileparts(mfilename('fullpath')), 'scan_results.mat'), 'results');

% ================= 局部函数 =================
function [B, guardB, cross, cols, rows, q, lp] = build_partition(model, pi, hour, z, H, valid, pattern, box)
%BUILD_PARTITION 与主程序一致的分块：按小时把变量归块，跨块行用 pi 对偶化。
    n = numel(model.obj); T = numel(z);
    K = ceil(T / H);
    own = zeros(n, 1);
    own(valid) = floor((min(hour(valid), T) - 1) / H) + 1;
    extra = find(~valid);
    own(extra) = K + (1:numel(extra))';
    K = K + numel(extra);

    groups = sparse(1:n, own, 1, n, K);
    p = spones(pattern * groups);
    degree = full(sum(p, 2));
    cross = degree ~= 1;
    owner_row = full(p * (1:K)') ./ max(1, degree);
    owner_row(cross) = 0;

    cols = cell(K, 1); rows = cell(K, 1);
    for j = 1:K
        cols{j} = find(own == j);
        rows{j} = find(~cross & owner_row == j);
    end

    q = model.obj(:) - model.A(cross, :)' * pi(cross);
    bp = model.rhs(cross) .* pi(cross);
    B = sum(bp);
    guardB = 1e-6 + 1e-9 * (1 + sum(abs(bp)));

    lp = zeros(K, 1);
    for j = 1:K
        cj = cols{j}; ij = rows{j};
        localbp = model.rhs(ij) .* pi(ij);
        gj = q(cj) - model.A(ij, cj)' * pi(ij);
        raw = sum(localbp) + sum(min(gj .* model.lb(cj), gj .* model.ub(cj)));
        guard = 1e-6 + 1e-9 * (1 + abs(raw) + sum(abs(localbp)) + sum(abs(gj) .* box(cj)));
        lp(j) = raw - guard;
    end
end

function safe = mip_safe_bound(local, r)
%MIP_SAFE_BOUND 取 Gurobi 对偶界并减去 guard；口径与 partition_mip_bound 相同。
    safe = -Inf;
    trusted = {'OPTIMAL', 'TIME_LIMIT', 'NODE_LIMIT', 'ITERATION_LIMIT', ...
        'SOLUTION_LIMIT', 'WORK_LIMIT', 'MEM_LIMIT', 'INTERRUPTED', 'SUBOPTIMAL', ...
        'USER_OBJ_LIMIT'};
    if ~any(strcmpi(r.status, trusted)), return; end
    values = [];
    for name = {'objboundc', 'objbound'}
        if isfield(r, name{1}) && isscalar(r.(name{1})) && isfinite(r.(name{1}))
            values(end+1) = r.(name{1}); %#ok<AGROW>
        end
    end
    if isempty(values), return; end
    raw = min(values);
    guard = 1e-6 + 1e-9 * (1 + abs(raw) + ...
        sum(abs(local.obj(:)) .* max(abs(local.lb(:)), abs(local.ub(:)))));
    safe = raw - guard;
end

function ensure_gurobi(configured_dir)
%ENSURE_GUROBI 优先使用现有路径，其次读取 GUROBI_HOME 或系统中的 gurobi_cl 位置。
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
end

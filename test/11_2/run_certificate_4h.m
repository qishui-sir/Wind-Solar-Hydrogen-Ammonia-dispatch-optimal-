%% 分层嵌套分块证书：多粒度累加，抬高 Keco 下界
% 数学口径与主程序 certified_partition_kernel 一致，函数已重命名以独立运行。
%   cert(H) = B - guardB + sum_j max( lp_j , seed_j , milp_j )
%   seed_j  ：由更细一层（H/2）的证书合并而来，保证粗块不会弱于细块之和
%   milp_j  ：把该块内的 z 保持二进制后 Gurobi 给出的对偶界（含 guard）
% 任一 H 的 cert(H) 都是合法下界（对任意满足 cost<=cap 的调度，N >= cert(H)）。

clear; clc;

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cert_dir = fullfile(root, 'src', 'cache', 'O1_partition21_v1', ...
    'f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');

ensure_gurobi('');

S = load(fullfile(cert_dir, 'certificate.mat'));
C = load(fullfile(cert_dir, 'context.mat'));
model = C.model; hour = C.hour; z = C.z;
pi = S.proof.pi(:);
sense = model.sense(:);
pi(sense == '<') = min(0, pi(sense == '<'));
pi(sense == '>') = max(0, pi(sense == '>'));

T = numel(z); n = numel(model.obj);
pattern = spones(model.A);
box = max(abs(model.lb(:)), abs(model.ub(:)));
hour = hour(:);
valid = isfinite(hour) & hour >= 1 & hour <= T + 1 & hour == round(hour);

levels = [96 192 384 768];
block_limit_s = 300;
budget_s = 4 * 3600;
threads = 8;
t_start = tic;

previous = [];
best = -Inf; best_H = NaN;
log_rows = [];

fprintf('开始：%s，层 %s\n', char(datetime('now', 'Format', 'HH:mm:ss')), mat2str(levels));
for li = 1:numel(levels)
    H = levels(li);
    [part, lp] = p2_partition(model, pi, hour, z, H, valid, pattern, box);
    K = numel(part.cols);
    ell = lp; seed = -Inf(K, 1);

    % ---- 子层种子：合并两块时，粗块至少不弱于两个细块之和 ----
    if ~isempty(previous) && mod(H, previous.H) == 0
        q = part.q;
        for j = 1:K
            cj = part.cols{j};
            kids = unique(previous.own(cj));
            % 尾块可能只对应一个子块（T 不能被 H 整除），此时种子退化为子块界本身
            assert(~isempty(kids) && numel(kids) <= 2, 'p2:merge', '粗块未覆盖一个或两个子块');
            old_cols = vertcat(previous.cols{kids});
            assert(isequal(sort(old_cols), cj), 'p2:merge', '子块列集不吻合');
            newly = part.rows{j};
            sel = previous.cross(newly);
            newly_local = newly(sel);
            delta = q(cj) - previous.q(cj) - model.A(newly_local, cj)' * pi(newly_local);
            bterm = model.rhs(newly_local) .* pi(newly_local);
            correction = sum(min(delta .* model.lb(cj), delta .* model.ub(cj)));
            mg = 1e-6 + 1e-9 * (1 + sum(abs(bterm)) + sum(abs(delta) .* box(cj)));
            seed(j) = sum(previous.l(kids)) + sum(bterm) + correction - mg;
        end
        ell = max(ell, seed);
    end

    % ---- 局部整数块 ----
    solver_s = 0; calls = 0;
    for j = 1:K
        if toc(t_start) > budget_s, break; end
        cj = part.cols{j}; ij = part.rows{j};
        inz = ismember(cj, z);
        if ~any(inz), continue; end
        local = struct('A', model.A(ij, cj), 'rhs', model.rhs(ij), 'sense', sense(ij), ...
            'obj', part.q(cj), 'lb', model.lb(cj), 'ub', model.ub(cj), ...
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
        b = p2_safe_bound(local, r);
        if isfinite(b) && b > ell(j)
            ell(j) = b;
        end
    end

    cert = part.B - part.guardB + sum(ell);
    if cert > best, best = cert; best_H = H; end
    fprintf(['H=%4d 块=%3d  seed增益=%7.3f  整数增益=%7.3f  cert=%10.6f  ' ...
        'ceil=%3d  求解%6.0fs  累计%5.1fmin\n'], H, K, sum(max(0, seed - lp)), ...
        sum(ell - lp), cert, ceil(cert - 1e-5), solver_s, toc(t_start) / 60);
    log_rows(end+1, :) = [H, K, cert, sum(ell - lp)]; %#ok<SAGROW>

    previous = struct('H', H, 'own', part.own, 'cols', {part.cols}, ...
        'cross', part.cross, 'q', part.q, 'l', ell);
    save(fullfile(here, 'certificate_levels.mat'), 'log_rows', 'best', 'best_H', 'ell', 'H');
end

fprintf('\n最佳下界 %.6f（H=%d）-> K_eco >= %d\n', best, best_H, ceil(best - 1e-5));
save(fullfile(here, 'certificate_levels.mat'), 'log_rows', 'best', 'best_H', 'ell', 'H');

% ================= 局部函数 =================
function [part, lp] = p2_partition(model, pi, hour, z, H, valid, pattern, box)
%P2_PARTITION 按小时把变量归块；跨块行用 pi 对偶化；块内用对偶界。
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

    part = struct('H', H, 'own', own, 'cols', {cols}, 'rows', {rows}, ...
        'cross', cross, 'q', q, 'B', B, 'guardB', guardB, 'K', K);
end

function safe = p2_safe_bound(local, r)
%P2_SAFE_BOUND 取 Gurobi 对偶界并减 guard；口径与主程序 partition_mip_bound 相同。
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

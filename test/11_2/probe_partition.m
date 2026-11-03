%% 复现分块证书的 LP 部分，并扫描不同分块粒度 H
% 数据来源：src/cache/O1_partition21_v1/<hash>/context.mat 与 certificate.mat（只读）
% 本脚本不做任何写入，只打印：给定同一组对偶价格 pi，不同 H 下的
%   B, guardB, sum(lp), 以及不含局部整数块的证书值 cert_LP = B - guardB + sum(lp)
% 目的：确认实现与主程序一致（H=96 应得 359.190344，H=192 应得 359.190390），
%       再看分块粒度对 LP 部分与潜在整数改进空间的影响。

clear; clc;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % project 根目录
cert_dir = fullfile(root, 'src', 'cache', 'O1_partition21_v1', ...
    'f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');

S = load(fullfile(cert_dir, 'certificate.mat'));
C = load(fullfile(cert_dir, 'context.mat'));
model = C.model; hour = C.hour; z = C.z;
pi = S.proof.pi;

% ---- 与主程序一致的符号修正 ----
pi = pi(:);
s = model.sense(:);
pi(s == '<') = min(0, pi(s == '<'));
pi(s == '>') = max(0, pi(s == '>'));

n = numel(model.obj); m = numel(model.rhs);
T = numel(z);
pattern = spones(model.A);
box = max(abs(model.lb(:)), abs(model.ub(:)));

h = hour(:);
valid = isfinite(h) & h >= 1 & h <= T + 1 & h == round(h);

fprintf('模型：%d 变量，%d 行，T=%d，pi 非零 %d 个\n', n, m, T, nnz(pi));

% ---- 复核整模型对偶恒等式 ----
g_full = model.obj(:) - model.A' * pi;
full_raw = model.rhs(:)' * pi + sum(min(g_full .* model.lb(:), g_full .* model.ub(:)));
fprintf('整模型对偶恒等式 full_raw = %.9f\n', full_raw);

% ---- 扫描 H ----
H_list = [24 48 72 96 120 144 168 192 240 288 336 420 500 730 1000 1460 2190];
fprintf('\n%6s %6s %12s %12s %12s %12s %10s\n', ...
    'H', 'blocks', 'B', 'sum(lp)', 'cert_LP', 'sum(lp_raw)', 'gap');
for H = H_list
    K = ceil(T / H);
    own = zeros(n, 1);
    own(valid) = floor((min(h(valid), T) - 1) / H) + 1;
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

    lp = zeros(K, 1); lp_raw = zeros(K, 1);
    for j = 1:K
        cj = cols{j}; ij = rows{j};
        localbp = model.rhs(ij) .* pi(ij);
        gj = q(cj) - model.A(ij, cj)' * pi(ij);
        raw = sum(localbp) + sum(min(gj .* model.lb(cj), gj .* model.ub(cj)));
        guard = 1e-6 + 1e-9 * (1 + abs(raw) + sum(abs(localbp)) + sum(abs(gj) .* box(cj)));
        lp(j) = raw - guard;
        lp_raw(j) = raw;
    end

    cert_lp = B - guardB + sum(lp);
    ident = abs(B + sum(lp_raw) - full_raw);
    fprintf('%6d %6d %12.4f %12.4f %12.6f %12.4f %10.2e\n', ...
        H, K, B, sum(lp), cert_lp, sum(lp_raw), ident);
end

fprintf('\n现有证书：L1 H=96 -> 403.071017（含整数块），L2 H=192 -> 407.647278（含整数块）\n');
fprintf('LP 部分两者都是 359.19，说明 44~48 的下界增量全部来自局部整数块。\n');

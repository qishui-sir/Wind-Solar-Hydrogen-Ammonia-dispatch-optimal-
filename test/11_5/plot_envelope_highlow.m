%% 包络点的成本与求解误差（高低图）— Nature 风格（蓝色主调）
% 数据来源：src/cache/O1_economic_threshold_partition21_cache.mat 的 state.points
% 每个包络点画一根竖线：下端=全局下界，上端=已核验可行解成本，长度=未闭合误差。
% 视窗：K ∈ [400,1010]，成本 ∈ [31.69,32.30] MUSD。
% 输出：test/11_5/包络点高低图.png

clear; clc; close all;

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cache_file = fullfile(root, 'src', 'cache', 'O1_economic_threshold_partition21_cache.mat');
assert(isfile(cache_file), '找不到 %s', cache_file);

S = load(cache_file);
assert(isfield(S,'state') && isfield(S.state,'points'), '缓存缺少 state.points');
P = S.state.points;

n   = [P.count_upper];       n  = n(:);
lo  = [P.cost_lower_usd];    lo = lo(:);
up  = [P.cost_upper_usd];    up = up(:);
has = logical([P.has_incumbent]); has = has(:);
ok  = has & isfinite(lo) & isfinite(up) & lo > 0 & up > 0 & isfinite(n);
n = n(ok); lo = lo(ok); up = up(ok);

% ---- 去重 + 单调包络 ----
[uN, ~, ic] = unique(n);
best_up = accumarray(ic, up, [], @min);
best_lo = nan(size(best_up));
for k = 1:numel(uN)
    m = (n == uN(k)) & (up == best_up(k));
    best_lo(k) = min(lo(m));
end
env_n = []; env_up = []; env_lo = [];
run_min = Inf;
for k = 1:numel(uN)
    if best_up(k) < run_min - 1e-6
        run_min = best_up(k);
        env_n(end+1,1)  = uN(k);       %#ok<SAGROW>
        env_up(end+1,1) = best_up(k);  %#ok<SAGROW>
        env_lo(end+1,1) = best_lo(k);  %#ok<SAGROW>
    end
end
gap = env_up - env_lo;

% ---- 视窗 ----
sel = env_n >= 400 & env_n <= 1010;
K = env_n(sel); upv = env_up(sel); lov = env_lo(sel); gapv = gap(sel);
assert(~isempty(K), '视窗 400—1010 内没有包络点');

L_C = 31747614.090131;
CAP = 31787614.090;

fprintf('包络点 %d 个，视窗内 %d 个：\n', numel(env_n), numel(K));
for i = 1:numel(K)
    fprintf('  n=%4d  上端=%.0f  下端=%.0f  误差=%.0f\n', K(i), upv(i), lov(i), gapv(i));
end

% ---- 蓝色单色渐变：浅蓝（误差小）→ 藏青（误差大）----
% 锚点取自 ColorBrewer Blues 中深段，去掉过淡色阶以保证竖线可见
anchors = [
    0.259 0.573 0.776;   % #4292C6 浅中蓝
    0.129 0.443 0.710;   % #2171B5 中蓝
    0.031 0.318 0.612;   % #08519C 深蓝
    0.031 0.188 0.420;   % #08306B 藏青
];
xi   = linspace(0, 1, 256);
cmap = interp1(linspace(0,1,size(anchors,1)), anchors, xi, 'linear');
cmap = min(max(cmap, 0), 1);

lg  = log10(max(gapv, 1) + 1);
t   = (lg - min(lg)) / max(1e-12, max(lg) - min(lg));
idx = min(max(round(t * 255) + 1, 1), 256);
col = cmap(idx, :);

% ---- 图幅 ----
fig = builtin('figure', 'Color', 'w', 'Units', 'centimeters', ...
    'Position', [2 2 16.0 9.0]);
ax = axes(fig, 'Units', 'normalized', 'Position', [0.10 0.13 0.87 0.83]);
hold(ax, 'on');

% 竖线
for i = 1:numel(K)
    plot(ax, [K(i) K(i)], [lov(i) upv(i)], '-', 'Color', col(i,:), 'LineWidth', 1.5);
end

% 上下端圆点：样式完全一致
for i = 1:numel(K)
    plot(ax, K(i), upv(i), 'o', 'MarkerSize', 5.5, ...
        'MarkerFaceColor', col(i,:), 'MarkerEdgeColor', 'w', 'LineWidth', 0.7);
    plot(ax, K(i), lov(i), 'o', 'MarkerSize', 5.5, ...
        'MarkerFaceColor', col(i,:), 'MarkerEdgeColor', 'w', 'LineWidth', 0.7);
end

% 参考线：τ_sat 用唯一暖色强调，L_C 用中性灰
h_CAP = yline(ax, CAP, '--', 'Color', [0.839 0.376 0.302], 'LineWidth', 1.0); % #D6604D
h_LC  = yline(ax, L_C, ':',  'Color', [0.47 0.47 0.47],    'LineWidth', 1.0);

% ---- 坐标轴（Nature 风格）----
ax.FontName    = 'Arial';
ax.FontSize    = 8;
ax.LineWidth   = 0.8;
ax.TickDir     = 'in';
ax.TickLength  = [0.012 0.012];
ax.Box         = 'on';
ax.Layer       = 'top';
ax.XColor      = [0.15 0.15 0.15];
ax.YColor      = [0.15 0.15 0.15];
ax.XGrid       = 'off';
ax.YGrid       = 'on';
ax.GridColor   = [0.90 0.92 0.94];    % 极淡蓝灰，与蓝色主调协调
ax.GridAlpha   = 1.0;
ax.GridLineStyle = '-';

xlim(ax, [380 1010]);
ylim(ax, [31690000 32300000]);
ax.XAxis.TickValues = 400:100:1000;
ax.YAxis.TickValues = 31.70e6:0.1e6:32.30e6;
ax.YAxis.TickLabels = {'31.70','31.80','31.90','32.00','32.10','32.20','32.30'};

xlabel(ax, '实际更新次数 K（次/a）', 'FontName','Microsoft YaHei', 'FontSize', 9);
ylabel(ax, '年度成本（MUSD/a）',      'FontName','Microsoft YaHei', 'FontSize', 9);

% ---- 阈值标注 ----
text(ax, 630, CAP + 0.035e6, '\tau_{sat} = 31.788 M（δ = 0.5 严格帽）', ...
    'FontName','Microsoft YaHei', 'FontSize', 7.5, 'Color', [0.839 0.376 0.302]);
text(ax, 520, L_C - 0.025e6, 'L_C = 31.748 M（参考下界）', ...
    'FontName','Microsoft YaHei', 'FontSize', 7.5, 'Color', [0.47 0.47 0.47]);

% ---- 误差数值标注 ----
for i = 1:numel(K)
    if gapv(i) >= 1000
        txt = sprintf('%.0fk', gapv(i) / 1000);
    else
        txt = sprintf('%.0f', gapv(i));
    end
    text(ax, K(i), upv(i) + 0.014e6, txt, ...
        'FontName','Arial', 'FontSize', 6.8, 'Color', [0.30 0.30 0.30], ...
        'HorizontalAlignment','center', 'VerticalAlignment','bottom');
end

% ---- 图例：标题说明蓝色深浅语义 ----
h_pt = plot(ax, nan, nan, 'o-', 'Color', [0.129 0.443 0.710], ...
    'MarkerSize', 5.5, 'MarkerFaceColor', [0.129 0.443 0.710], ...
    'MarkerEdgeColor', 'w', 'LineWidth', 1.5);
lgd = legend(ax, [h_pt, h_CAP, h_LC], ...
    {'包络点（上=可行解，下=下界）', '\tau_{sat} 严格帽', 'L_C 参考下界'}, ...
    'FontName','Microsoft YaHei', 'FontSize', 7.2, ...
    'Box', 'off', 'Location', 'northeast');

out = fullfile(here, '包络点高低图.png');
exportgraphics(fig, out, 'Resolution', 300);
fprintf('已保存 %s\n', out);
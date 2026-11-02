%% 读取包络数据，绘制散点，用于观察走势
% 数据来源：同目录 前沿包络点.csv（由主缓存导出）
% 横轴：全年设定值更新次数 K；纵轴：相对参考下界的成本溢价 ΔC（USD/t）

clear; clc; close all;

% ===== 开关：true 开启局部放大，false 只画主图 =====
use_zoom = true;
zoom_x   = [480 1550];              % 放大窗横轴范围
zoom_y   = [0 0.38];                % 放大窗纵轴范围
zoom_pos = [0.47 0.40 0.40 0.33];   % 放大窗位置（图窗归一化）

here = fileparts(mfilename('fullpath'));
csv_file = fullfile(here, '前沿包络点.csv');
assert(isfile(csv_file), '找不到 %s', csv_file);

tbl = readtable(csv_file, 'Encoding', 'UTF-8');
K = tbl.K_updates;
premium = tbl.premium_usd_per_t;

fig = builtin('figure', 'Color', 'w', 'Position', [100 100 780 540]);
ax = axes(fig);
hold(ax, 'on');

% 主数据点
plot(ax, K, premium, 'o-', 'MarkerSize', 7.5, ...
    'MarkerFaceColor', [0.20 0.45 0.75], 'MarkerEdgeColor', [0.10 0.22 0.42], ...
    'LineStyle', '-', 'DisplayName', '包络点');

% 两条参考线：经济帽与认证下界
yline(ax, 0.5, ':', 'Color', [0.80 0.30 0.30], 'LineWidth', 1.0, ...
    'DisplayName', '\delta=0.5 经济帽');
xline(ax, 408, '--', 'Color', [0.20 0.60 0.30], 'LineWidth', 1.0, ...
    'DisplayName', '认证下界 408');

set(ax, 'XScale', 'line', 'YScale', 'line', 'FontSize', 10);
grid(ax, 'on');
grid(ax, 'minor');
ax.XMinorGrid = 'on';
ax.YMinorGrid = 'on';
ax.Box = 'on';

xlabel(ax, '全年设定值更新次数 K', 'FontSize', 11);
ylabel(ax, '相对参考下界的成本溢价 \DeltaC (USD/t)', 'FontSize', 11);
title(ax, '', 'FontSize', 12);

xlim(ax, [95 1600]);
ylim(ax, [3e-5 30]);
legend(ax, 'Location', 'northeast', 'FontSize', 9, 'Box', 'off');


% ===== 局部放大（由 use_zoom 控制）=====
if use_zoom
    add_zoom_panel(fig, K, premium, zoom_x, zoom_y, zoom_pos);
end

% 控制台摘要，便于核对
fprintf('共 %d 个包络点，K 范围 %d—%d\n', numel(K), min(K), max(K));
fprintf('溢价范围 %.6f—%.6f USD/t\n', min(premium), max(premium));

out_png = fullfile(here, 'plot_frontier.png');
exportgraphics(fig, out_png, 'Resolution', 200);
fprintf('已保存 %s\n', out_png);

% ================= 局部函数 =================
function ax2 = add_zoom_panel(fig, K, premium, xr, yr, pos)
%ADD_ZOOM_PANEL 在主图空白区叠加一个同风格放大窗，并在主图标出取景框。
%   fig      图窗句柄
%   ax_main  主坐标轴句柄
%   K, premium  原始数据
%   xr, yr   放大窗的横纵范围
%   pos      放大窗位置（图窗归一化坐标 [left bottom width height]）
    ax2 = axes(fig, 'Units', 'normalized', 'Position', pos);
    hold(ax2, 'on');

    % 与主图一致的线型与配色
    plot(ax2, K, premium, 'o-', 'MarkerSize', 5.0, ...
        'MarkerFaceColor', [0.20 0.45 0.75], 'MarkerEdgeColor', [0.10 0.22 0.42], ...
        'LineStyle', '-', 'LineWidth', 1.0);
    yline(ax2, 0.5, ':', 'Color', [0.80 0.30 0.30], 'LineWidth', 1.0);
    xline(ax2, 408, '--', 'Color', [0.20 0.60 0.30], 'LineWidth', 1.0);

    % 与主图一致的网格与边框
    set(ax2, 'XScale', 'line', 'YScale', 'line', 'FontSize', 8);
    grid(ax2, 'on');
    grid(ax2, 'minor');
    ax2.XMinorGrid = 'on';
    ax2.YMinorGrid = 'on';
    ax2.Box = 'on';

    xlim(ax2, xr);
    ylim(ax2, yr);
    xlabel(ax2, 'K', 'FontSize', 9);
    ylabel(ax2, '\DeltaC (USD/t)', 'FontSize', 9);
    title(ax2, 'K > 480 局部放大', 'FontSize', 10);

end

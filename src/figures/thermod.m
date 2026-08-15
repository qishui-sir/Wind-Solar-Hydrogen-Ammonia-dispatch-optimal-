clear;clc;

root_dir = 'C:\Users\祁水\Desktop\风光氢氨系统\project\data\renewables_ninja';
PV_file = fullfile(root_dir,'2022PV.csv');
PW_file = fullfile(root_dir,'2022PW.csv');

opts_PV = detectImportOptions(PV_file);
opts_PV = setvaropts(opts_PV, 1, 'InputFormat', 'yyyy/MM/dd HH:mm');
opts_PW = detectImportOptions(PW_file);
opts_PW = setvaropts(opts_PW, 1, 'InputFormat', 'yyyy-MM-dd HH:mm');
pv_data = readtable(PV_file, opts_PV);
pw_data = readtable(PW_file, opts_PW);

time_pv_utc = pv_data{:, 1};
cf_pv = pv_data{:, 2};
time_pw_utc = pw_data{:, 1};
cf_pv = cf_pv .* 200;
time_pv = time_pv_utc + hours(8);
time_pw = time_pw_utc + hours(8);

cf_pw   = pw_data{:, 2};
cf_pw = cf_pw .* 200;

month_pv = month(time_pv);
hour_pv  = hour(time_pv);
month_pw = month(time_pw);
hour_pw  = hour(time_pw);

pv_matrix = nan(12,24);
pw_matrix = nan(12,24);

for m = 1:12
    for h = 0:23
        idx = (month_pv == m) & (hour_pv == h);
        if any(idx)
            pv_matrix(m,h+1) = mean(cf_pv(idx));
        end
        idx = (month_pw == m) & (hour_pw == h);
        if any(idx)
            pw_matrix(m,h+1) = mean(cf_pw(idx));
        end
    end
end


%% ========== 参考文献风格的离散热力图 ==========
nColors = 30;

% 文献中的色轴范围
wt_limits = [25, 120];      % WT：25~120 MW
pv_limits = [0, 160];       % PV：0~160 MW

% 将超出显示范围的数据截断到色轴边界
pw_matrix_clip = min(max(pw_matrix, wt_limits(1)), wt_limits(2));
pv_matrix_clip = min(max(pv_matrix, pv_limits(1)), pv_limits(2));

% 映射为1~30的离散颜色编号
pw_matrix_disc = floor( ...
    (pw_matrix_clip - wt_limits(1)) ./ diff(wt_limits) ...
    * nColors) + 1;

pv_matrix_disc = floor( ...
    (pv_matrix_clip - pv_limits(1)) ./ diff(pv_limits) ...
    * nColors) + 1;

% 最大值必须归入第30级，而不是第31级
pw_matrix_disc(pw_matrix >= wt_limits(2)) = nColors;
pv_matrix_disc(pv_matrix >= pv_limits(2)) = nColors;

% 小于下限的值归入第1级
pw_matrix_disc(pw_matrix <= wt_limits(1)) = 1;
pv_matrix_disc(pv_matrix <= pv_limits(1)) = 1;

% 保留缺失值
pw_matrix_disc(isnan(pw_matrix)) = NaN;
pv_matrix_disc(isnan(pv_matrix)) = NaN;

%% ========== WT离散色带 ==========
% 提取自参考图，排列方向：顶部紫色→底部黄色
cmap_wt_top_to_bottom = [
     68,   1,  84
     70,  14,  97
     72,  26, 108
     71,  37, 117
     70,  48, 125
     67,  59, 131
     63,  69, 135
     59,  80, 138
     55,  88, 140
     51,  97, 141
     47, 106, 141
     43, 115, 142
     40, 123, 142
     37, 131, 141
     34, 139, 141
     31, 148, 139
     30, 156, 137
     32, 164, 133
     38, 172, 129
     48, 180, 122
     62, 188, 115
     79, 195, 105
     96, 201,  96
    116, 208,  84
    139, 213,  70
    162, 218,  55
    186, 222,  39
    207, 225,  28
    231, 228,  25
    253, 231,  36
] / 255;

% MATLAB第一行颜色对应最小值，因此反转
cmap_wt = flipud(cmap_wt_top_to_bottom);

%% ========== PV离散色带 ==========
% 提取自参考图，排列方向：顶部黑色→底部浅黄色
cmap_pv_top_to_bottom = [
      0,   0,   3
      4,   3,  19
     12,   9,  38
     21,  14,  56
     32,  17,  77
     47,  16,  98
     62,  15, 114
     77,  17, 122
     90,  21, 126
    104,  27, 128
    118,  33, 129
    132,  38, 129
    146,  43, 128
    159,  47, 126
    174,  52, 123
    189,  57, 119
    203,  62, 113
    215,  69, 107
    228,  78, 100
    238,  91,  94
    245, 106,  91
    249, 123,  93
    251, 138,  98
    253, 155, 106
    254, 172, 117
    254, 188, 130
    253, 205, 144
    253, 220, 157
    252, 236, 174
    251, 252, 191
] / 255;

% 低值为浅黄色，高值为黑色
cmap_pv = flipud(cmap_pv_top_to_bottom);

%% ========== 坐标轴参数 ==========
month_labels = {
    'Jan','Feb','Mar','Apr','May','Jun', ...
    'Jul','Aug','Sep','Oct','Nov','Dec'
};

x_tick_values = 2:2:24;

%% ========== 创建画布 ==========
fig = figure( ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [2, 2, 34, 13], ...
    'Renderer', 'painters');

tl = tiledlayout(fig, 1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

%% ========== 左图：WT ==========
ax1 = nexttile(tl, 1);

img1 = imagesc(ax1, 1:24, 1:12, pw_matrix_disc);
img1.AlphaData = ~isnan(pw_matrix_disc);

set(ax1, ...
    'YDir', 'normal', ...
    'Color', [0.94, 0.94, 0.94], ...
    'XLim', [0.5, 24.5], ...
    'YLim', [0.5, 12.5], ...
    'XTick', x_tick_values, ...
    'XTickLabel', string(x_tick_values), ...
    'YTick', 1:12, ...
    'YTickLabel', month_labels, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 15, ...
    'LineWidth', 1.1, ...
    'TickDir', 'out', ...
    'Layer', 'top', ...
    'Box', 'on');

pbaspect(ax1, [1.05, 1, 1]);

xlabel(ax1, 'Times (h)', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 17);

% 添加12×24单元格边界
add_cell_grid(ax1);

% WT独立色带
colormap(ax1, cmap_wt);
clim(ax1, [0.5, nColors + 0.5]);

cb1 = colorbar(ax1, 'eastoutside');
cb1.FontName = 'Times New Roman';
cb1.FontSize = 14;
cb1.LineWidth = 1.0;
cb1.TickDirection = 'out';

% 文献色带刻度
wt_tick_values = [25, 44, 63, 82, 101, 120];

% 将真实功率刻度映射到离散色带坐标
wt_tick_positions = 0.5 + ...
    (wt_tick_values - wt_limits(1)) ./ diff(wt_limits) ...
    * nColors;

cb1.Ticks = wt_tick_positions;
cb1.TickLabels = string(wt_tick_values);
cb1.Label.String = 'WT output (MW)';
cb1.Label.FontName = 'Times New Roman';
cb1.Label.FontSize = 17;

%% ========== 右图：PV ==========
ax2 = nexttile(tl, 2);

img2 = imagesc(ax2, 1:24, 1:12, pv_matrix_disc);
img2.AlphaData = ~isnan(pv_matrix_disc);

set(ax2, ...
    'YDir', 'normal', ...
    'Color', [0.94, 0.94, 0.94], ...
    'XLim', [0.5, 24.5], ...
    'YLim', [0.5, 12.5], ...
    'XTick', x_tick_values, ...
    'XTickLabel', string(x_tick_values), ...
    'YTick', 1:12, ...
    'YTickLabel', month_labels, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 15, ...
    'LineWidth', 1.1, ...
    'TickDir', 'out', ...
    'Layer', 'top', ...
    'Box', 'on');

pbaspect(ax2, [1.05, 1, 1]);

xlabel(ax2, 'Times (h)', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 17);

% 添加12×24单元格边界
add_cell_grid(ax2);

% PV独立色带
colormap(ax2, cmap_pv);
clim(ax2, [0.5, nColors + 0.5]);

cb2 = colorbar(ax2, 'eastoutside');
cb2.FontName = 'Times New Roman';
cb2.FontSize = 14;
cb2.LineWidth = 1.0;
cb2.TickDirection = 'out';

pv_tick_values = [0, 32, 64, 96, 128, 160];

pv_tick_positions = 0.5 + ...
    (pv_tick_values - pv_limits(1)) ./ diff(pv_limits) ...
    * nColors;

cb2.Ticks = pv_tick_positions;
cb2.TickLabels = string(pv_tick_values);
cb2.Label.String = 'PV output (MW)';
cb2.Label.FontName = 'Times New Roman';
cb2.Label.FontSize = 17;


%% ========== 局部函数：绘制单元格边界 ==========
function add_cell_grid(ax)

    % 单元格边界坐标
    [Xg, Yg] = meshgrid(0.5:1:24.5, 0.5:1:12.5);
    Zg = ones(size(Xg));

    hold(ax, 'on');

    surface(ax, Xg, Yg, Zg, ...
        'FaceColor', 'none', ...
        'EdgeColor', [1, 1, 1], ...
        'EdgeAlpha', 0.12, ...
        'LineWidth', 0.10, ...
        'HandleVisibility', 'off');

    hold(ax, 'off');
end
drawnow;  % 等待tiledlayout完成布局

cb1.Units = 'centimeters';
cb2.Units = 'centimeters';

pos1 = cb1.Position;
pos2 = cb2.Position;

pos1(3) = 0.80;   % WT色带宽度，单位cm
pos2(3) = 0.80;   % PV色带宽度，单位cm

cb1.Position = pos1;
cb2.Position = pos2;

pos1 = cb1.Position;
pos1(1) = pos1(1) + 1.35;  % 向左移动0.10 cm
cb1.Position = pos1;

pos2 = cb2.Position;
pos2(1) = pos2(1) + 0.80;
cb2.Position = pos2;
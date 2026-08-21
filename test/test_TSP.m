%% 验证假设：欧氏TSP最短路径是否同时具有最小内角标准差
% -------------------------------------------------------------------------
% 对每一组10城市数据：
% 1) 枚举固定从城市1出发的全部Hamilton回路；
% 2) 利用正反向对称性，只保留9!/2 = 181440条候选路径；
% 3) 排除自相交路径，因为自相交路线没有统一的多边形内角定义；
% 4) 分别寻找"路径长度最小"和"内角标准差最小"的简单闭合路径；
% 5) 重复多组随机实验，统计二者重合率、TSP角度排名和相关性。
%
% 说明：
% - AngleRankPercent越接近0，TSP路径的内角标准差排名越靠前；
% - SpearmanRho > 0表示路径越长时，内角标准差总体也越大；
% - LengthPenaltyPct表示选择最小角度标准差路径需要增加多少路程。

clear;
clc;
close all;

%% ===================== 1. 实验参数 =====================

n = 10;                         % 城市总数（城市1固定为原点）
origin = [0, 0];
coordMax = 100;                 % 随机整数坐标范围[0,100]

numExperiments = 5000;            % 初步验证建议30；正式统计建议100或更多
baseRandomSeed = 2026;          % 固定种子，保证实验可复现
displayProgress = true;

% 数值判断容差
angleTolerance = 1e-9;

rng(baseRandomSeed);

%% ===================== 2. 预生成所有候选访问顺序 =====================

fprintf('正在生成全部候选访问顺序...\n');

permutationMatrix = perms(2:n);

% 路径正向与反向等价，例如：
% 1-2-3-4-1 和 1-4-3-2-1表示同一无向回路。
keepDirection = permutationMatrix(:,1) < permutationMatrix(:,end);
permutationMatrix = permutationMatrix(keepDirection,:);

% 使用uint16降低多组实验时的内存占用
permutationMatrix = uint16(permutationMatrix);

numCandidateTours = size(permutationMatrix,1);
tourOrders = [uint16(ones(numCandidateTours,1)), permutationMatrix];

fprintf('完整排列数：%d\n', factorial(n-1));
fprintf('消除正反向重复后的候选路径数：%d\n\n', numCandidateTours);

clear permutationMatrix keepDirection;

%% ===================== 3. 预分配实验结果 =====================

shortestLength = zeros(numExperiments,1);
shortestAngleStd = zeros(numExperiments,1);

minimumAngleStd = zeros(numExperiments,1);
angleOptimalLength = zeros(numExperiments,1);

sameExactTour = false(numExperiments,1);
tspIsAngleOptimal = false(numExperiments,1);

tspAngleRank = zeros(numExperiments,1);
tspAngleRankPercent = zeros(numExperiments,1);
spearmanRho = zeros(numExperiments,1);

lengthPenaltyPct = zeros(numExperiments,1);
angleOptimalityGapPct = zeros(numExperiments,1);
numSimpleTours = zeros(numExperiments,1);
solveTime = zeros(numExperiments,1);

% 保存第1组实验，供后续绘图
firstCase = struct();

%% ===================== 4. 多组随机实验 =====================

for experimentID = 1:numExperiments

    experimentTimer = tic;

    % 生成不重复、且不与原点重合的整数城市
    cities = generateIntegerCities(n, origin, coordMax);

    % 一次性评价该城市集合的全部候选路径
    allMetrics = evaluateAllTours(cities, tourOrders);

    simpleMask = allMetrics.isSimple;
    numSimpleTours(experimentID) = nnz(simpleMask);

    if numSimpleTours(experimentID) == 0
        error('第%d组实验没有得到简单闭合路径。', experimentID);
    end

    simpleIndices = find(simpleMask);
    simpleLengths = allMetrics.length(simpleMask);
    simpleAngleStd = allMetrics.angleStd(simpleMask);

    % -------- 距离最优路径 --------
    [shortestLength(experimentID), localShortestIndex] = ...
        min(simpleLengths);

    shortestGlobalIndex = simpleIndices(localShortestIndex);
    shortestAngleStd(experimentID) = ...
        allMetrics.angleStd(shortestGlobalIndex);

    % -------- 内角标准差最优路径 --------
    [minimumAngleStd(experimentID), localAngleIndex] = ...
        min(simpleAngleStd);

    angleGlobalIndex = simpleIndices(localAngleIndex);
    angleOptimalLength(experimentID) = ...
        allMetrics.length(angleGlobalIndex);

    % 两个目标是否选择完全相同的路径
    sameExactTour(experimentID) = ...
        shortestGlobalIndex == angleGlobalIndex;

    % 考虑并列最优：TSP路径的角度标准差是否达到全局最小值
    tspIsAngleOptimal(experimentID) = ...
        shortestAngleStd(experimentID) <= ...
        minimumAngleStd(experimentID) + angleTolerance;

    % TSP路径的内角标准差在全部简单路径中的排名
    tspAngleRank(experimentID) = 1 + sum( ...
        simpleAngleStd < ...
        shortestAngleStd(experimentID) - angleTolerance);

    tspAngleRankPercent(experimentID) = ...
        100 * (tspAngleRank(experimentID) - 1) / ...
        max(numSimpleTours(experimentID) - 1, 1);

    % 路径长度与内角标准差的Spearman秩相关系数
    spearmanRho(experimentID) = localSpearmanCorrelation( ...
        simpleLengths, simpleAngleStd);

    % 角度最优路径相对于TSP的距离增幅
    lengthPenaltyPct(experimentID) = 100 * ( ...
        angleOptimalLength(experimentID) / ...
        shortestLength(experimentID) - 1);

    % TSP相对于最小角度标准差的差距
    if minimumAngleStd(experimentID) > angleTolerance
        angleOptimalityGapPct(experimentID) = 100 * ( ...
            shortestAngleStd(experimentID) / ...
            minimumAngleStd(experimentID) - 1);
    else
        angleOptimalityGapPct(experimentID) = NaN;
    end

    solveTime(experimentID) = toc(experimentTimer);

    % 保存第1组完整结果用于可视化
    if experimentID == 1
        firstCase.cities = cities;
        firstCase.shortestPath = [ ...
            double(tourOrders(shortestGlobalIndex,:)), 1];
        firstCase.angleOptimalPath = [ ...
            double(tourOrders(angleGlobalIndex,:)), 1];
        firstCase.shortestLength = shortestLength(experimentID);
        firstCase.shortestAngleStd = shortestAngleStd(experimentID);
        firstCase.minimumAngleStd = minimumAngleStd(experimentID);
        firstCase.angleOptimalLength = angleOptimalLength(experimentID);
        firstCase.simpleLengths = simpleLengths;
        firstCase.simpleAngleStd = simpleAngleStd;
    end

    if displayProgress
        fprintf(['实验 %3d/%3d：简单路径=%6d，', ...
                 'TSP角度排名=%5d（%.3f%%），', ...
                 'rho=%+.3f，耗时=%.2f s\n'], ...
            experimentID, numExperiments, ...
            numSimpleTours(experimentID), ...
            tspAngleRank(experimentID), ...
            tspAngleRankPercent(experimentID), ...
            spearmanRho(experimentID), ...
            solveTime(experimentID));
    end
end

%% ===================== 5. 构造实验结果表 =====================

experimentTable = table( ...
    (1:numExperiments)', ...
    numSimpleTours, ...
    shortestLength, ...
    shortestAngleStd, ...
    minimumAngleStd, ...
    angleOptimalLength, ...
    lengthPenaltyPct, ...
    angleOptimalityGapPct, ...
    tspAngleRank, ...
    tspAngleRankPercent, ...
    spearmanRho, ...
    sameExactTour, ...
    tspIsAngleOptimal, ...
    solveTime, ...
    'VariableNames', { ...
    'Experiment', ...
    'NumSimpleTours', ...
    'TSP_Length', ...
    'TSP_AngleStd_deg', ...
    'MinimumAngleStd_deg', ...
    'AngleOptimal_Length', ...
    'LengthPenalty_pct', ...
    'AngleGap_pct', ...
    'TSP_AngleRank', ...
    'AngleRankPercent', ...
    'SpearmanRho', ...
    'SameExactTour', ...
    'TSP_IsAngleOptimal', ...
    'SolveTime_s'});

%% ===================== 6. 汇总统计 =====================

exactSameRate = 100 * mean(sameExactTour);
angleOptimalRate = 100 * mean(tspIsAngleOptimal);

meanRankPercent = mean(tspAngleRankPercent);
medianRankPercent = median(tspAngleRankPercent);

meanSpearman = mean(spearmanRho, 'omitnan');
medianSpearman = median(spearmanRho, 'omitnan');

meanLengthPenalty = mean(lengthPenaltyPct, 'omitnan');
medianLengthPenalty = median(lengthPenaltyPct, 'omitnan');

totalSolveTime = sum(solveTime);

fprintf('\n============================================================\n');
fprintf('                多组实验汇总结果\n');
fprintf('============================================================\n');
fprintf('随机实验数量：%d\n', numExperiments);
fprintf('两目标选择完全相同路径的比例：%.2f%%\n', exactSameRate);
fprintf('TSP同时达到最小内角标准差的比例：%.2f%%\n', angleOptimalRate);
fprintf('TSP内角标准差平均排名百分位：%.4f%%（0%%为最好）\n', ...
    meanRankPercent);
fprintf('TSP内角标准差中位排名百分位：%.4f%%\n', ...
    medianRankPercent);
fprintf('长度与内角标准差平均Spearman相关系数：%+.4f\n', ...
    meanSpearman);
fprintf('长度与内角标准差中位Spearman相关系数：%+.4f\n', ...
    medianSpearman);
fprintf('角度最优路径的平均距离增幅：%.4f%%\n', ...
    meanLengthPenalty);
fprintf('角度最优路径的中位距离增幅：%.4f%%\n', ...
    medianLengthPenalty);
fprintf('总计算时间：%.2f s\n', totalSolveTime);

fprintf('\n结果解释：\n');

if angleOptimalRate >= 95
    fprintf(['当前样本强烈支持：TSP最短路径通常同时具有', ...
             '全局最小内角标准差。\n']);
elseif meanRankPercent <= 5
    fprintf(['当前样本支持相关性假设：TSP虽然不总是角度最优，', ...
             '但其内角标准差通常位于全部简单路径的前5%%。\n']);
else
    fprintf(['当前样本不支持"最短路径必然具有最小内角标准差"；', ...
             '两者应作为不同优化目标。\n']);
end

%% ===================== 7. 保存数值结果 =====================

writetable(experimentTable, 'tsp_angle_validation_results.csv');

%% ===================== 8. 第一组实验可视化 =====================

colors.path = [0, 114, 178] / 255;
colors.angle = [213, 94, 0] / 255;
colors.city = [230, 159, 0] / 255;
colors.origin = [204, 0, 0] / 255;
colors.text = [45, 45, 45] / 255;
colors.grid = [190, 190, 190] / 255;
colors.scatter = [110, 110, 110] / 255;

fig1 = figure( ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [2, 2, 28, 9.5], ...
    'Renderer', 'painters');

layout1 = tiledlayout(fig1, 1, 3, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

% 最短距离路径
ax1 = nexttile(layout1,1);
drawTour(ax1, firstCase.cities, firstCase.shortestPath, ...
    colors.path, colors);
styleTourAxes(ax1, coordMax, colors);
title(ax1, sprintf([ ...
    'Shortest-distance tour\n', ...
    '$L=%.2f,\;\sigma_{\theta}=%.2f^{\circ}$'], ...
    firstCase.shortestLength, firstCase.shortestAngleStd), ...
    'Interpreter', 'latex', ...
    'FontWeight', 'normal');

% 最小内角标准差路径
ax2 = nexttile(layout1,2);
drawTour(ax2, firstCase.cities, firstCase.angleOptimalPath, ...
    colors.angle, colors);
styleTourAxes(ax2, coordMax, colors);
title(ax2, sprintf([ ...
    'Minimum-angle-dispersion tour\n', ...
    '$L=%.2f,\;\sigma_{\theta}=%.2f^{\circ}$'], ...
    firstCase.angleOptimalLength, firstCase.minimumAngleStd), ...
    'Interpreter', 'latex', ...
    'FontWeight', 'normal');

% 全部简单路径的长度—内角标准差分布
ax3 = nexttile(layout1,3);
hold(ax3, 'on');

scatter(ax3, ...
    firstCase.simpleLengths, ...
    firstCase.simpleAngleStd, ...
    7, colors.scatter, ...
    'filled', ...
    'MarkerFaceAlpha', 0.16, ...
    'MarkerEdgeAlpha', 0.16);

scatter(ax3, ...
    firstCase.shortestLength, ...
    firstCase.shortestAngleStd, ...
    75, colors.path, ...
    'filled', ...
    'MarkerEdgeColor', 'w', ...
    'LineWidth', 0.8);

scatter(ax3, ...
    firstCase.angleOptimalLength, ...
    firstCase.minimumAngleStd, ...
    85, colors.angle, ...
    'd', ...
    'filled', ...
    'MarkerEdgeColor', 'w', ...
    'LineWidth', 0.8);

xlabel(ax3, 'Tour length');
ylabel(ax3, 'Interior-angle standard deviation (deg)');

title(ax3, 'All non-self-intersecting tours', ...
    'FontWeight', 'normal');

legend(ax3, ...
    {'All simple tours', 'Shortest tour', 'Minimum-angle tour'}, ...
    'Location', 'best', ...
    'Box', 'off');

styleStatAxes(ax3, colors);
hold(ax3, 'off');

exportgraphics(fig1, ...
    'tsp_angle_single_case.pdf', ...
    'ContentType', 'vector');

exportgraphics(fig1, ...
    'tsp_angle_single_case.tif', ...
    'Resolution', 600);

%% ===================== 9. 多组实验统计图 =====================

fig2 = figure( ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [3, 3, 20, 8.5], ...
    'Renderer', 'painters');

layout2 = tiledlayout(fig2, 1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

% TSP角度排名百分位
ax4 = nexttile(layout2,1);

histogram(ax4, tspAngleRankPercent, ...
    'BinMethod', 'sturges', ...
    'FaceColor', colors.path, ...
    'EdgeColor', 'w', ...
    'FaceAlpha', 0.85);

xlabel(ax4, 'TSP angle-rank percentile (%)');
ylabel(ax4, 'Frequency');
title(ax4, 'Angle-dispersion rank of TSP', ...
    'FontWeight', 'normal');
styleStatAxes(ax4, colors);

% 各组实验的相关系数
ax5 = nexttile(layout2,2);

bar(ax5, 1:numExperiments, spearmanRho, ...
    0.72, ...
    'FaceColor', colors.angle, ...
    'EdgeColor', 'none');

hold(ax5, 'on');
yline(ax5, meanSpearman, '--', ...
    sprintf('Mean = %.3f', meanSpearman), ...
    'Color', colors.path, ...
    'LineWidth', 1.2, ...
    'LabelHorizontalAlignment', 'left');
hold(ax5, 'off');

xlabel(ax5, 'Experiment');
ylabel(ax5, 'Spearman correlation coefficient');
title(ax5, 'Length-angle relationship', ...
    'FontWeight', 'normal');
styleStatAxes(ax5, colors);

exportgraphics(fig2, ...
    'tsp_angle_monte_carlo.pdf', ...
    'ContentType', 'vector');

exportgraphics(fig2, ...
    'tsp_angle_monte_carlo.tif', ...
    'Resolution', 600);

%% ===================== 局部函数 =====================

function cities = generateIntegerCities(n, origin, coordMax)
% 生成不重复的整数坐标，并排除原点

    gridSize = coordMax + 1;
    numRandomCities = n - 1;

    selectedID = randperm( ...
        gridSize^2 - 1, numRandomCities) + 1;

    [yIndex, xIndex] = ind2sub( ...
        [gridSize, gridSize], selectedID);

    randomCities = [ ...
        xIndex(:) - 1, ...
        yIndex(:) - 1];

    cities = [origin; randomCities];
end

function metrics = evaluateAllTours(cities, tourOrders)
% 向量化计算全部路径的长度、内角标准差以及是否自相交

    numTours = size(tourOrders,1);
    numCities = size(tourOrders,2);

    orderIndex = double(tourOrders);

    % 将全部路径的城市坐标展开为numTours × numCities矩阵
    x = reshape( ...
        cities(orderIndex(:),1), ...
        numTours, numCities);

    y = reshape( ...
        cities(orderIndex(:),2), ...
        numTours, numCities);

    xNext = circshift(x, [0, -1]);
    yNext = circshift(y, [0, -1]);

    % 路径总长度
    edgeLengths = hypot(xNext - x, yNext - y);
    totalLength = sum(edgeLengths,2);

    % 多边形方向
    signedArea2 = sum( ...
        x .* yNext - y .* xNext, 2);

    polygonDirection = sign(signedArea2);

    % 每个顶点的有符号转角
    xPrevious = circshift(x, [0, 1]);
    yPrevious = circshift(y, [0, 1]);

    incomingX = x - xPrevious;
    incomingY = y - yPrevious;

    outgoingX = xNext - x;
    outgoingY = yNext - y;

    turnCross = ...
        incomingX .* outgoingY - ...
        incomingY .* outgoingX;

    turnDot = ...
        incomingX .* outgoingX + ...
        incomingY .* outgoingY;

    turningAngles = atan2d(turnCross, turnDot);

    interiorAngles = 180 - bsxfun( ...
        @times, polygonDirection, turningAngles);

    meanAngles = mean(interiorAngles,2);

    angleDeviation = bsxfun( ...
        @minus, interiorAngles, meanAngles);

    angleStd = sqrt(mean(angleDeviation.^2,2));

    % 排除退化路径和自相交路径
    degenerateMask = abs(signedArea2) <= 1e-10;
    selfIntersectingMask = detectSelfIntersections(x,y);

    metrics.length = totalLength;
    metrics.angleStd = angleStd;
    metrics.isSimple = ...
        ~degenerateMask & ~selfIntersectingMask;
end

function selfIntersecting = detectSelfIntersections(x,y)
% 向量化检测每一行路径是否存在非相邻边相交

    numTours = size(x,1);
    numEdges = size(x,2);

    selfIntersecting = false(numTours,1);

    for edge1 = 1:numEdges

        edge1Next = mod(edge1, numEdges) + 1;

        for edge2 = edge1+1:numEdges

            edge2Next = mod(edge2, numEdges) + 1;

            % 相邻边共享一个端点，不属于自相交
            if edge2 == edge1Next || edge1 == edge2Next
                continue;
            end

            intersects = segmentsIntersectVectorized( ...
                x(:,edge1), y(:,edge1), ...
                x(:,edge1Next), y(:,edge1Next), ...
                x(:,edge2), y(:,edge2), ...
                x(:,edge2Next), y(:,edge2Next));

            selfIntersecting = selfIntersecting | intersects;

            % 所有路径均已确认自相交时可提前退出
            if all(selfIntersecting)
                return;
            end
        end
    end
end

function intersects = segmentsIntersectVectorized( ...
    ax, ay, bx, by, cx, cy, dx, dy)
% 同时判断多组线段AB和CD是否相交

    tolerance = 1e-10;

    o1 = cross2D(bx-ax, by-ay, cx-ax, cy-ay);
    o2 = cross2D(bx-ax, by-ay, dx-ax, dy-ay);
    o3 = cross2D(dx-cx, dy-cy, ax-cx, ay-cy);
    o4 = cross2D(dx-cx, dy-cy, bx-cx, by-cy);

    properIntersection = ...
        (((o1 > tolerance) & (o2 < -tolerance)) | ...
         ((o1 < -tolerance) & (o2 > tolerance))) & ...
        (((o3 > tolerance) & (o4 < -tolerance)) | ...
         ((o3 < -tolerance) & (o4 > tolerance)));

    collinearTouch = ...
        ((abs(o1) <= tolerance) & ...
         pointOnSegment(cx,cy,ax,ay,bx,by,tolerance)) | ...
        ((abs(o2) <= tolerance) & ...
         pointOnSegment(dx,dy,ax,ay,bx,by,tolerance)) | ...
        ((abs(o3) <= tolerance) & ...
         pointOnSegment(ax,ay,cx,cy,dx,dy,tolerance)) | ...
        ((abs(o4) <= tolerance) & ...
         pointOnSegment(bx,by,cx,cy,dx,dy,tolerance));

    intersects = properIntersection | collinearTouch;
end

function value = cross2D(ux,uy,vx,vy)
% 二维向量叉积

    value = ux .* vy - uy .* vx;
end

function onSegment = pointOnSegment( ...
    px,py,ax,ay,bx,by,tolerance)
% 判断点P是否位于闭线段AB的包围盒内

    onSegment = ...
        px >= min(ax,bx) - tolerance & ...
        px <= max(ax,bx) + tolerance & ...
        py >= min(ay,by) - tolerance & ...
        py <= max(ay,by) + tolerance;
end

function rho = localSpearmanCorrelation(x,y)
% 不依赖Statistics and Machine Learning Toolbox的Spearman相关系数

    rankX = localTiedRank(x(:));
    rankY = localTiedRank(y(:));

    correlationMatrix = corrcoef(rankX,rankY);

    if numel(correlationMatrix) < 4
        rho = NaN;
    else
        rho = correlationMatrix(1,2);
    end
end

function ranks = localTiedRank(values)
% 计算秩；相同数据使用平均秩

    [sortedValues, sortOrder] = sort(values);
    numValues = numel(values);
    ranks = zeros(numValues,1);

    % 利用分组边界向量化处理并列值，避免逐元素while循环
    groupStart = [1; find(diff(sortedValues) ~= 0) + 1];
    groupEnd = [groupStart(2:end) - 1; numValues];
    averageGroupRank = (groupStart + groupEnd) / 2;

    groupID = cumsum([true; diff(sortedValues) ~= 0]);
    sortedRanks = averageGroupRank(groupID);

    ranks(sortOrder) = sortedRanks;
end

function drawTour(ax,cities,closedPath,pathColor,colors)
% 绘制单条闭合路径

    hold(ax,'on');

    pathCoordinates = cities(closedPath,:);

    plot(ax, ...
        pathCoordinates(:,1), ...
        pathCoordinates(:,2), ...
        '-', ...
        'Color', pathColor, ...
        'LineWidth', 1.8);

    scatter(ax, ...
        cities(2:end,1), ...
        cities(2:end,2), ...
        48, colors.city, ...
        'filled', ...
        'MarkerEdgeColor', 'w', ...
        'LineWidth', 0.8);

    plot(ax, ...
        cities(1,1), cities(1,2), ...
        'p', ...
        'Color', colors.origin, ...
        'MarkerFaceColor', colors.origin, ...
        'MarkerEdgeColor', 'w', ...
        'MarkerSize', 14, ...
        'LineWidth', 0.8);

    for cityID = 1:size(cities,1)

        if cityID == 1
            labelText = 'O';
            fontWeight = 'bold';
        else
            labelText = sprintf('%d',cityID);
            fontWeight = 'normal';
        end

        text(ax, ...
            cities(cityID,1)+2.2, ...
            cities(cityID,2)+2.2, ...
            labelText, ...
            'FontName', 'Arial', ...
            'FontSize', 8.5, ...
            'FontWeight', fontWeight, ...
            'Color', colors.text);
    end

    hold(ax,'off');
end

function styleTourAxes(ax,coordMax,colors)
% 路径图坐标轴格式

    axis(ax,'equal');
    xlim(ax,[-8,coordMax+8]);
    ylim(ax,[-8,coordMax+8]);

    xlabel(ax,'X coordinate');
    ylabel(ax,'Y coordinate');

    styleStatAxes(ax,colors);
end

function styleStatAxes(ax,colors)
% 统计图通用坐标轴格式

    ax.Box = 'on';
    ax.Layer = 'top';
    ax.LineWidth = 0.9;
    ax.TickDir = 'out';
    ax.TickLength = [0.015,0.015];
    ax.FontName = 'Arial';
    ax.FontSize = 9;
    ax.XColor = colors.text;
    ax.YColor = colors.text;

    grid(ax,'on');
    ax.GridColor = colors.grid;
    ax.GridAlpha = 0.25;
    ax.GridLineStyle = '--';
end
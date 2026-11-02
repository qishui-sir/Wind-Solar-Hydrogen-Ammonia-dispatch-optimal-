%% 批量采样：对给定 K 网格逐点求解 min C s.t. N<=K
% 运行方式（项目根目录）：run('test/10_30/run_sampling.m')
% 每点的解由 Calculate_K 写入主缓存 src/cache；本脚本自身不修改 test/10_30 以外的代码文件。
% 网格按前沿形状分段：低平台、541—741 平台、741—846 拐点、846 以上平坦区。
% 每点单独计时；单点异常被捕获后继续，不中断整批。

here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fileparts(here));

% 采样网格与单点时限（秒）
K_list = [ 575  600  625  700  750];
T_list = [3600 3600 3600 2400 2400];
tags = ["密550-650", "密550-650", "密550-650", "密650-888", "密650-888"];

fprintf('[Sampling] 共%d个点，计划总时长约%.1f h。\n', ...
    numel(K_list), sum(T_list) / 3600);
t0 = tic;
for i = 1:numel(K_list)
    K = K_list(i);
    seconds = T_list(i);
    fprintf('\n===== [%s] %d/%d  K=%d  %s =====\n', ...
        string(datetime('now','Format','HH:mm:ss')), i, numel(K_list), K, tags(i));
    try
        r = Calculate_K(K, seconds);
        fprintf('[Sampling] DONE K=%d status=%s count=%g cost=%.3f written=%d\n', ...
            K, r.status, r.count, r.cost_upper_usd, r.cache_written);
    catch exception
        fprintf('[Sampling] FAIL K=%d : %s\n', K, exception.message);
    end
    fprintf('[Sampling] 累计 %.1f min\n', toc(t0) / 60);
end
fprintf('[Sampling] 全部完成，总耗时 %.1f min\n', toc(t0) / 60);

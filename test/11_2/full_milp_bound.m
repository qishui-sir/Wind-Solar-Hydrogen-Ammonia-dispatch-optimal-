%% 直接求解"最小更新次数"整数模型的 Gurobi 对偶界（合法下界）
% 模型：min sum(z)  s.t. 原年度约束 + cost <= cap（与 partition21 同一模型、同一 cap）
% 整数集合：meta.original_intcon（原始模型的全部整数列），比分块证书只保留 z 更强
% 输出：Gurobi 的 objbound（对偶界），任何时刻都是 min count 的合法下界
% 只读 context.mat，不写主程序任何文件。

clear; clc;

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
cert_dir = fullfile(root, 'src', 'cache', 'O1_partition21_v1', ...
    'f3422c24f28f9419f262bcb1b5d5463dbf8f1574de49de5af6d14b361ffef1a6');

ensure_gurobi('');

C = load(fullfile(cert_dir, 'context.mat'));
model = C.model; meta = C.meta;

n = numel(model.obj); m = numel(model.rhs);
fprintf('模型 %d 变量 / %d 行；cap=%.3f USD\n', n, m, meta.cap_usd);

% ---- 整数集合：原始模型的整数列 ----
intcon = meta.original_intcon(:);
vt = repmat('C', n, 1);
isbin = model.lb(intcon) == 0 & model.ub(intcon) == 1;
vt(intcon(isbin)) = 'B';
vt(intcon(~isbin)) = 'I';
fprintf('整数列 %d 个（其中二元 %d 个）\n', numel(intcon), nnz(isbin));

mip = struct('A', model.A, 'rhs', model.rhs, 'sense', model.sense, ...
    'obj', model.obj, 'lb', model.lb, 'ub', model.ub, ...
    'vtype', vt, 'modelsense', model.modelsense);

time_limit_s = 4 * 3600;
gp = struct('TimeLimit', time_limit_s, 'Threads', 4, 'OutputFlag', 1, ...
    'MIPGap', 0, 'MIPGapAbs', 0, 'Seed', 20261103, ...
    'LogFile', fullfile(here, 'full_milp.log'));

t0 = tic;
r = gurobi(mip, gp);
elapsed = toc(t0);

fprintf('\n状态=%s  用时=%.1f min\n', r.status, elapsed / 60);
if isfield(r, 'objbound')
    fprintf('对偶界 objbound=%.9f -> K_eco >= %d\n', r.objbound, ceil(r.objbound - 1e-6));
end
if isfield(r, 'objboundc')
    fprintf('对偶界 objboundc=%.9f -> K_eco >= %d\n', r.objboundc, ceil(r.objboundc - 1e-6));
end
if isfield(r, 'x') && ~isempty(r.x)
    fprintf('当前解 count=%.0f\n', sum(r.x(C.z)));
end
save(fullfile(here, 'full_milp_bound.mat'), 'r', 'elapsed', 'gp');

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

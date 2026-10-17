function audit_mat_paths(files)
%AUDIT_MAT_PATHS 列出 .mat 缓存中的字段结构，并找出内嵌的绝对路径字符串。
% 用途：搬迁缓存目录前，确认哪些字段存了绝对路径（搬迁后会失效）。
if nargin < 1 || isempty(files)
    error('audit_mat_paths:input', '请传入 .mat 文件路径，或使用字符串 ''auto''。');
end
if ischar(files) && any(strcmp(files, {'auto', 'src', 'live'}))
    project = fileparts(fileparts(mfilename('fullpath')));
    if strcmp(files, 'live')
        dir_path = fullfile(project, 'dsh_test', 'cache');
    else
        dir_path = fullfile(project, 'src', 'cache');
    end
    files = { ...
        fullfile(dir_path, 'O1_economic_threshold_partition21_cache.mat'), ...
        fullfile(dir_path, 'O1_economic_threshold_cache.mat'), ...
        fullfile(dir_path, 'O1_stage1_cache.mat'), ...
        fullfile(dir_path, 'O1_fixed_k_cache.mat')};
end
if ischar(files), files = {files}; end

for f = 1:numel(files)
    file = files{f};
    fprintf('\n=============== %s\n', file);
    if ~isfile(file)
        fprintf('  [缺失] 文件不存在\n');
        continue
    end
    d = load(file);
    names = fieldnames(d);
    fprintf('  顶层变量: %s\n', strjoin(names, ', '));
    for n = 1:numel(names)
        v = d.(names{n});
        fprintf('    %-28s %-12s %s\n', names{n}, class(v), mat2str(size(v)));
    end
    hits = {};
    hits = scan_paths(d, '', hits);
    fprintf('  --- 含绝对路径 / 缓存相对路径的字符串 (%d) ---\n', numel(hits));
    for h = 1:numel(hits)
        fprintf('    %s\n', hits{h});
    end
end
end

function hits = scan_paths(v, prefix, hits)
%SCAN_PATHS 递归扫描 struct/cell 中的 char/string，报告疑似路径。
if isstruct(v)
    for i = 1:numel(v)
        fn = fieldnames(v);
        for k = 1:numel(fn)
            if numel(v) > 1
                p = sprintf('%s(%d).%s', prefix, i, fn{k});
            else
                p = [prefix, '.', fn{k}];
            end
            hits = scan_paths(v(i).(fn{k}), p, hits);
        end
    end
elseif iscell(v)
    for k = 1:numel(v)
        hits = scan_paths(v{k}, sprintf('%s{%d}', prefix, k), hits);
    end
elseif ischar(v)
    if looks_like_path(v)
        hits{end+1} = sprintf('%-42s = %s', prefix, truncate(v)); %#ok<AGROW>
    end
elseif isstring(v)
    for k = 1:numel(v)
        s = char(v(k));
        if looks_like_path(s)
            hits{end+1} = sprintf('%-42s = %s', prefix, truncate(s)); %#ok<AGROW>
        end
    end
end
end

function tf = looks_like_path(s)
tf = ~isempty(s) && (contains(s, ':\') || contains(s, ':/') || ...
    contains(s, 'O1_partition21_v1') || contains(s, 'dsh_test'));
if tf && numel(s) > 200
    % 长的普通文本（如报告）里偶然提到路径时仍报告，但只截断显示。
    tf = true;
end
end

function out = truncate(s)
if numel(s) > 160
    out = [s(1:160), ' ...'];
else
    out = s;
end
end

function project_dir = project_root(anchor_path)
%PROJECT_ROOT Return the root folder for this project.
% The lookup is independent of the current MATLAB working directory.

if nargin < 1 || isempty(anchor_path)
    anchor_path = mfilename('fullpath');
end

if isstring(anchor_path) && isscalar(anchor_path)
    anchor_path = char(anchor_path);
end

if isfolder(anchor_path)
    current_dir = anchor_path;
else
    current_dir = fileparts(anchor_path);
end

while true
    has_src = isfolder(fullfile(current_dir, 'src'));
    has_data = isfolder(fullfile(current_dir, 'data'));
    has_protocol = isfile(fullfile(current_dir, 'docs', 'protocol_v5.md'));
    if has_src && has_data && has_protocol
        project_dir = current_dir;
        return
    end

    parent_dir = fileparts(current_dir);
    if strcmp(parent_dir, current_dir)
        error('project_root:not_found', ...
            'Could not find project root from anchor: %s', anchor_path);
    end
    current_dir = parent_dir;
end
end
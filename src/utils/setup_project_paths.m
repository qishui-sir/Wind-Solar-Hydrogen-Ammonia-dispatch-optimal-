function project_dir = setup_project_paths(anchor_path)
%SETUP_PROJECT_PATHS Add the project source folders to the MATLAB path.

if nargin < 1 || isempty(anchor_path)
    anchor_path = mfilename('fullpath');
end

utils_dir = fileparts(mfilename('fullpath'));
if ~path_contains_dir(utils_dir)
    addpath(utils_dir, '-begin');
end

project_dir = project_root(anchor_path);
source_dirs = { ...
    'src', ...
    fullfile('src', 'params'), ...
    fullfile('src', 'results'), ...
    fullfile('src', 'protocol'), ...
    fullfile('src', 'utils'), ...
    fullfile('src', 'reproducibility'), ...
    fullfile('src', 'pipeline'), ...
    fullfile('src', 'paper')};

for dir_index = 1:numel(source_dirs)
    candidate = fullfile(project_dir, source_dirs{dir_index});
    if isfolder(candidate) && ~path_contains_dir(candidate)
        addpath(candidate, '-begin');
    end
end
end

function exists_on_path = path_contains_dir(candidate)
if isstring(candidate) && isscalar(candidate)
    candidate = char(candidate);
end
existing_dirs = strsplit(path, pathsep);
exists_on_path = any(strcmp(existing_dirs, candidate));
end
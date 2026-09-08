% RUN_IN_MATLAB  In-MATLAB entry point for the full paper campaign.
%   Usage: open this file in MATLAB and press F5 (Run), or type:
%       run_in_matlab
%
%   Runs 2024 calibration + 2025 lock with automatic parallel (parfor)
%   acceleration, falling back to serial if the pool is unavailable.

% Switch to the project root (this script's folder)
project_dir = fileparts(mfilename('fullpath'));
cd(project_dir);

% Add all source folders to the MATLAB path
addpath(fullfile(project_dir, 'src', 'utils'), '-begin');
setup_project_paths(project_dir);

% Run the full campaign (parallel by default)
run_full_campaign();

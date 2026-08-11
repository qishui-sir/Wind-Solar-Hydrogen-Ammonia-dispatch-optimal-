function config = my_system(scenario_id)
%MY_SYSTEM Complete default, AEL, and HB parameters for a 7-day PtA case.
%   config = my_system() returns the S2 continuous flexible case.
%   config = my_system('s1'|'s2'|'s3') selects a Zhou scenario.

if nargin < 1 || isempty(scenario_id)
    scenario_id = 's2';
end

if isstring(scenario_id) && isscalar(scenario_id)
    scenario_id = char(scenario_id);
end

if ~ischar(scenario_id)
    error('my_system:bad_case', 'scenario_id must be s1, s2, or s3.');
end

scenario_id = lower(strtrim(scenario_id));
if ~ismember(scenario_id, {'s1', 's2', 's3'})
    error('my_system:bad_case', 'scenario_id must be s1, s2, or s3.');
end

params_dir = fileparts(mfilename('fullpath'));
if ~isfolder(params_dir)
    error('my_system:param_dir', 'Missing parameter folder: %s', params_dir);
end

old_path = path;
path_cleanup = onCleanup(@() path(old_path));
addpath(params_dir, '-begin');

expected_default_file = fullfile(params_dir, 'default.m');
actual_default_file = which('default');
if ~strcmpi(actual_default_file, expected_default_file)
    error('my_system:param_shadow', ...
        'Expected default.m at %s, but MATLAB resolved default as %s.', ...
        expected_default_file, actual_default_file);
end

config = default(scenario_id);
config.AEL = AEL(config, scenario_id);
config.HB = HB(config, scenario_id);

config.converter.capacity_mw = config.AEL.capacity_mw; % Converter capacity, MW
config.ref.ael_capacity_mw = config.AEL.capacity_mw; % Zhou AEL capacity, MW
config.ref.h2_storage_capacity_nm3 = config.h2_storage.capacity_nm3; % Zhou H2 storage capacity, Nm3
config.ref.transformer_capacity_mw = config.transformer.capacity_mw; % Zhou transformer capacity, MW

config.audit.literature_h2_n2_sum = ...
    config.HB.literature_h2_t_per_t_nh3 + ...
    config.HB.literature_n2_t_per_t_nh3; % Zhou rounded H2+N2 mass sum
config.audit.active_h2_n2_sum = ...
    config.HB.active_h2_t_per_t_nh3 + ...
    config.HB.active_n2_t_per_t_nh3; % Active stoichiometric mass sum
config.audit.note = ['Zhou H2=0.18 and N2=0.84 are retained; ', ...
    'dispatch mass balance uses exact 6/34 and 28/34.']; % Mass-balance note

if abs(config.renewable.pv_capacity_kw + ...
        config.renewable.pw_capacity_kw - ...
        config.renewable.total_capacity_kw) > 1e-6
    error('my_system:bad_res', 'PV plus PW must equal total renewable capacity.');
end

if config.AEL.min_power_kw > config.AEL.max_power_kw
    error('my_system:bad_ael', 'AEL min power exceeds max power.');
end

if config.HB.min_load_fraction > config.HB.max_load_fraction
    error('my_system:bad_hb', 'HB min load exceeds max load.');
end

if config.h2_storage.capacity_kg <= 0 || config.transformer.capacity_mw <= 0
    error('my_system:bad_cap', 'Main capacities must be positive.');
end
end

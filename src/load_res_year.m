function renewable_data = load_res_year(config)
%LOAD_RES_YEAR Load full-year PV and wind profiles for Zhou dispatch runs.

if nargin < 1 || isempty(config)
    config = struct();
end

if ~isstruct(config)
    error('load_res_year:bad_config', 'config must be a struct.');
end

reject_removed_debug_options(config);

data_dir = option_value(config, 'data_dir', default_data_dir());
year_value = option_value(config, 'year', 2022);
pv_year = option_value(config, 'pv_year', year_value);
pw_year = option_value(config, 'pw_year', year_value);
pv_capacity_kw = option_value(config, 'pv_capacity_kw', 200000);
pw_capacity_kw = option_value(config, 'pw_capacity_kw', 200000);
time_step_h = option_value(config, 'time_step_h', 1);
keep_leap_day = option_value(config, 'keep_leap_day', false);

if pv_capacity_kw < 0 || pw_capacity_kw < 0
    error('load_res_year:bad_capacity', 'Renewable capacities must be nonnegative.');
end
if time_step_h <= 0
    error('load_res_year:bad_time_step', 'time_step_h must be positive.');
end

pv_path = option_value(config, 'pv_path', ...
    fullfile(data_dir, sprintf('%dPV.csv', pv_year)));
pw_path = option_value(config, 'pw_path', ...
    fullfile(data_dir, sprintf('%dPW.csv', pw_year)));

[pv_time, pv_factor, pv_stats] = read_profile(pv_path);
[pw_time, pw_factor, pw_stats] = read_profile(pw_path);

output_year = choose_output_year(config, pv_time, pw_time, keep_leap_day);
[pv_time, pv_factor] = normalize_profile_year( ...
    pv_time, pv_factor, output_year, keep_leap_day);
[pw_time, pw_factor] = normalize_profile_year( ...
    pw_time, pw_factor, output_year, keep_leap_day);

[time_grid, pv_factor, pw_factor] = align_profiles( ...
    pv_time, pv_factor, pw_time, pw_factor, time_step_h);

pv_power_kw = pv_factor * pv_capacity_kw;
pw_power_kw = pw_factor * pw_capacity_kw;

renewable_data = struct();
renewable_data.time = time_grid;
renewable_data.time_index = (1:numel(time_grid))';
renewable_data.time_step_h = time_step_h;
renewable_data.time_count = numel(time_grid);
renewable_data.pv_capacity_factor = pv_factor;
renewable_data.pw_capacity_factor = pw_factor;
renewable_data.pv_power_kw = pv_power_kw;
renewable_data.pw_power_kw = pw_power_kw;
renewable_data.renewable_power_kw = pv_power_kw + pw_power_kw;
renewable_data.unit.power = 'kW';
renewable_data.unit.time = 'UTC';
renewable_data.source = struct();
renewable_data.source.data_dir = data_dir;
renewable_data.source.pv_path = pv_path;
renewable_data.source.pw_path = pw_path;
renewable_data.source.pv_year = pv_year;
renewable_data.source.pw_year = pw_year;
renewable_data.source.output_year = output_year;
renewable_data.source.keep_leap_day = keep_leap_day;
renewable_data.source.pv_capacity_kw = pv_capacity_kw;
renewable_data.source.pw_capacity_kw = pw_capacity_kw;
renewable_data.source.start_time = time_grid(1);
renewable_data.source.end_time = time_grid(end);
renewable_data.source.pv_stats = pv_stats;
renewable_data.source.pw_stats = pw_stats;
end

function reject_removed_debug_options(config)
removed_options = {'day_count', 'start_time'};
for option_index = 1:numel(removed_options)
    if isfield(config, removed_options{option_index})
        error('load_res_year:removed_debug_option', ...
            ['Seven-day/debug span selection was removed. ', ...
            'Load a complete annual profile instead.']);
    end
end
end

function data_dir = default_data_dir()
src_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(src_dir);
data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
end

function value = option_value(config, name, default_value)
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
else
    value = default_value;
end
end

function [profile_time, profile_value, stats] = read_profile(file_path)
if isstring(file_path) && isscalar(file_path)
    file_path = char(file_path);
end

if ~isfile(file_path)
    error('load_res_year:missing_file', 'Missing renewable profile: %s', file_path);
end

lines = readlines(file_path);
header_index = find(startsWith(strtrim(lines), "time,"), 1, 'first');
if isempty(header_index)
    error('load_res_year:bad_file', 'Missing time header in %s.', file_path);
end

fid = fopen(file_path, 'r');
if fid < 0
    error('load_res_year:open_file', 'Cannot open renewable profile: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));

data = textscan(fid, '%s%f%*[^\n]', 'Delimiter', ',', ...
    'HeaderLines', header_index, 'Whitespace', '', ...
    'ReturnOnError', false);

time_text = strtrim(string(data{1}));
profile_value = data{2};
stats.raw_rows = numel(time_text);

profile_time = parse_time_text(time_text);
bad_rows = ismissing(time_text) | isnat(profile_time) | isnan(profile_value);
stats.bad_rows = nnz(bad_rows);

profile_time = profile_time(~bad_rows);
profile_value = profile_value(~bad_rows);
profile_value(profile_value < 0) = 0;

[profile_time, sort_index] = sort(profile_time);
profile_value = profile_value(sort_index);

[profile_time, ~, group_index] = unique(profile_time);
stats.duplicate_rows = numel(group_index) - numel(profile_time);
if stats.duplicate_rows > 0
    profile_value = accumarray(group_index, profile_value, [], @mean);
end

if isempty(profile_time)
    error('load_res_year:empty_profile', 'No valid rows in %s.', file_path);
end
end

function profile_time = parse_time_text(time_text)
profile_time = NaT(size(time_text), 'TimeZone', 'UTC');
formats = {'yyyy-MM-dd HH:mm', 'yyyy-MM-dd H:mm', ...
    'yyyy/M/d HH:mm', 'yyyy/M/d H:mm', ...
    'yyyy/MM/dd HH:mm', 'yyyy/MM/dd H:mm'};

for format_index = 1:numel(formats)
    missing_index = isnat(profile_time) & strlength(time_text) > 0;
    if ~any(missing_index)
        break
    end
    try
        profile_time(missing_index) = datetime( ...
            time_text(missing_index), 'InputFormat', formats{format_index}, ...
            'TimeZone', 'UTC');
    catch
    end
end
end

function output_year = choose_output_year(config, pv_time, pw_time, keep_leap_day)
if isfield(config, 'output_year') && ~isempty(config.output_year)
    output_year = config.output_year;
    return
end

pv_years = unique(year(pv_time));
pw_years = unique(year(pw_time));
has_single_year = isscalar(pv_years) && isscalar(pw_years) && ...
    pv_years == pw_years;
has_leap_day = any(month(pv_time) == 2 & day(pv_time) == 29) || ...
    any(month(pw_time) == 2 & day(pw_time) == 29);

if keep_leap_day && has_leap_day
    output_year = 2024;
elseif has_single_year && ~has_leap_day
    output_year = pv_years;
else
    output_year = 2022;
end
end

function [profile_time, profile_value] = normalize_profile_year( ...
    profile_time, profile_value, output_year, keep_leap_day)
if ~keep_leap_day
    keep_index = ~(month(profile_time) == 2 & day(profile_time) == 29);
    profile_time = profile_time(keep_index);
    profile_value = profile_value(keep_index);
end

try
    profile_time = datetime(output_year, month(profile_time), day(profile_time), ...
        hour(profile_time), minute(profile_time), second(profile_time), ...
        'TimeZone', 'UTC');
catch err
    error('load_res_year:bad_output_year', ...
        'output_year cannot represent the selected profile dates: %s', ...
        err.message);
end
end

function [time_grid, pv_factor, pw_factor] = align_profiles( ...
    pv_time, pv_factor, pw_time, pw_factor, time_step_h)
start_time = max([pv_time(1); pw_time(1)]);
end_time = min([pv_time(end); pw_time(end)]);
if end_time < start_time
    error('load_res_year:bad_time_grid', ...
        'PV and wind profiles do not overlap after year normalization.');
end

time_grid = (start_time:hours(time_step_h):end_time)';
pv_factor = interpolate_profile(pv_time, pv_factor, time_grid);
pw_factor = interpolate_profile(pw_time, pw_factor, time_grid);

if isempty(time_grid) || numel(time_grid) < 24
    error('load_res_year:bad_time_grid', 'Annual profile is unexpectedly short.');
end
end

function values = interpolate_profile(source_time, source_values, target_time)
origin_time = source_time(1);
source_x = hours(source_time - origin_time);
target_x = hours(target_time - origin_time);
values = interp1(source_x, source_values, target_x, 'linear');

if any(isnan(values))
    values = fillmissing(values, 'nearest');
end
values = values(:);
end

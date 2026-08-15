function renewable_data = load_res_year(config)
%LOAD_RES_YEAR Read PV/PW hourly data and return an annual data set.
%   renewable_data = load_res_year() reads 2022PV.csv and 2022PW.csv.
%   renewable_data = load_res_year(config) allows custom data directory,
%   source years, file names, full paths, time step, start time, optional
%   day count, and capacity scaling.
%
%   Source selection examples:
%      config.year = 2024;               :use 2024PV.csv and 2024PW.csv
%      config.pv_year = 2023;            :use 2023PV.csv
%      config.pw_year = 2025;            :use 2025PW.csv
%      config.pv_file = '2024PV.csv';   % direct file name under data_dir
%      config.pw_path = '...\2022PW.csv'; % absolute or relative file path

if nargin < 1
    config = struct();
end

config = set_default_config(config);
must_file(config.pv_path);
must_file(config.pw_path);

pv_series = read_renewables_ninja_csv(config.pv_path);
pw_series = read_renewables_ninja_csv(config.pw_path);

pv_series = clean_power_series(pv_series);
pw_series = clean_power_series(pw_series);

[pv_series, pw_series, config] = ...
    normalize_calendar_year(pv_series, pw_series, config);

[time_grid, pv_unit_power_kw, pw_unit_power_kw] = ...
    make_common_time_grid(pv_series, pw_series, config);
[time, pv_unit_power_kw, pw_unit_power_kw] = ...
    select_time_span(time_grid, pv_unit_power_kw, pw_unit_power_kw, config);

pv_power_kw = config.pv_capacity_kw .* pv_unit_power_kw;
pw_power_kw = config.pw_capacity_kw .* pw_unit_power_kw;

renewable_data = pack_renewable_data( ...
    time, pv_power_kw, pw_power_kw, config, pv_series, pw_series);
check_output_data(renewable_data);
end

function config = set_default_config(config)
source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
default_data_dir = fullfile(project_dir, 'data', 'renewables_ninja');
legacy_data_dir = fullfile(source_dir, 'upload');

data_dir = get_config_value(config, {'data_dir'}, []);
if is_empty_value(data_dir)
    if isfolder(default_data_dir)
        config.data_dir = default_data_dir;
    else
        config.data_dir = legacy_data_dir;
    end
else
    config.data_dir = path_to_char(data_dir, 'config.data_dir');
end

common_year = get_config_value(config, {'year'}, 2022);
common_year = must_year_scalar(common_year, 'config.year');

pv_year = get_config_value(config, {'pv_year', 'PV_year'}, common_year);
pw_year = get_config_value(config, {'pw_year', 'PW_year'}, common_year);
config.pv_year = must_year_scalar(pv_year, 'config.pv_year');
config.pw_year = must_year_scalar(pw_year, 'config.pw_year');

config.pv_path = resolve_source_path(config, ...
    {'pv_path', 'PV_path'}, {'pv_file', 'PV_file'}, ...
    config.pv_year, 'PV.csv', 'config.pv_path');
config.pw_path = resolve_source_path(config, ...
    {'pw_path', 'PW_path'}, {'pw_file', 'PW_file'}, ...
    config.pw_year, 'PW.csv', 'config.pw_path');

config.pv_source_year = detect_source_year(config.pv_path, config.pv_year);
config.pw_source_year = detect_source_year(config.pw_path, config.pw_year);

if ~isfield(config, 'time_step_h') || isempty(config.time_step_h)
    config.time_step_h = 1;
end

if ~isfield(config, 'day_count')
    config.day_count = [];
end

if ~isfield(config, 'start_time')
    config.start_time = [];
end

pv_capacity_kw = get_config_value(config, ...
    {'pv_capacity_kw', 'PV_capacity_kw', 'PV_capacity'}, 1);
pw_capacity_kw = get_config_value(config, ...
    {'pw_capacity_kw', 'PW_capacity_kw', 'PW_capacity'}, 1);
config.pv_capacity_kw = pv_capacity_kw;
config.pw_capacity_kw = pw_capacity_kw;

keep_leap_day = get_config_value(config, {'keep_leap_day'}, false);
output_year = get_config_value(config, {'output_year'}, []);

config.time_step_h = must_positive_scalar( ...
    config.time_step_h, 'config.time_step_h', 'load_res_year:bad_time_step');
config.pv_capacity_kw = must_positive_scalar( ...
    config.pv_capacity_kw, 'config.pv_capacity_kw', 'load_res_year:bad_capacity');
config.pw_capacity_kw = must_positive_scalar( ...
    config.pw_capacity_kw, 'config.pw_capacity_kw', 'load_res_year:bad_capacity');
config.keep_leap_day = must_logical_scalar( ...
    keep_leap_day, 'config.keep_leap_day');

if is_empty_value(output_year)
    config.output_year = [];
else
    config.output_year = must_year_scalar(output_year, 'config.output_year');
end

if ~isempty(config.day_count)
    config.day_count = must_positive_scalar( ...
        config.day_count, 'config.day_count', 'load_res_year:bad_day_count');
    time_step_count = 24 * config.day_count / config.time_step_h;
    if abs(time_step_count - round(time_step_count)) > 1e-9
        error('load_res_year:bad_time_grid', ...
            'config.time_step_h must divide 24 * config.day_count evenly.');
    end
end
end

function file_path = resolve_source_path( ...
    config, path_fields, file_fields, source_year, suffix, path_name)
path_value = get_config_value(config, path_fields, []);
file_value = get_config_value(config, file_fields, []);

if ~is_empty_value(path_value)
    file_path = path_to_char(path_value, path_name);
elseif ~is_empty_value(file_value)
    file_name = path_to_char(file_value, file_fields{1});
    file_path = fullfile(config.data_dir, file_name);
else
    file_path = fullfile(config.data_dir, sprintf('%d%s', source_year, suffix));
end
end

function value = get_config_value(config, names, default_value)
value = default_value;
for name_index = 1:numel(names)
    field_name = names{name_index};
    if isfield(config, field_name)
        candidate = config.(field_name);
        if ~is_empty_value(candidate)
            value = candidate;
            return
        end
    end
end
end

function is_empty = is_empty_value(value)
is_empty = isempty(value);
if is_empty
    return
end

if isstring(value) && isscalar(value)
    is_empty = strlength(strtrim(value)) == 0;
elseif ischar(value)
    is_empty = isempty(strtrim(value));
end
end

function value = must_year_scalar(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value))
    error('load_res_year:bad_year', '%s must be a finite scalar year.', name);
end

if abs(value - round(value)) > 1e-9
    error('load_res_year:bad_year', '%s must be an integer year.', name);
end

value = round(value);
end

function value = must_positive_scalar(value, name, error_id)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
    error(error_id, '%s must be a positive finite scalar.', name);
end
end

function value = must_logical_scalar(value, name)
if islogical(value) && isscalar(value)
    return
end

if isnumeric(value) && isscalar(value) && isfinite(value)
    value = logical(value);
    return
end

if ischar(value) || (isstring(value) && isscalar(value))
    value_text = lower(strtrim(char(value)));
    if any(strcmp(value_text, {'true', '1', 'yes'}))
        value = true;
        return
    elseif any(strcmp(value_text, {'false', '0', 'no'}))
        value = false;
        return
    end
end

error('load_res_year:bad_logical', '%s must be a logical scalar.', name);
end

function path_text = path_to_char(path_value, name)
if ~(ischar(path_value) || (isstring(path_value) && isscalar(path_value)))
    error('load_res_year:bad_path', '%s must be a text scalar.', name);
end

path_text = char(path_value);
if isempty(strtrim(path_text))
    error('load_res_year:bad_path', '%s must not be empty.', name);
end
end

function must_file(file_path)
if ~isfile(file_path)
    error('load_res_year:no_file', 'File not found: %s', file_path);
end
end

function source_year = detect_source_year(file_path, default_year)
[~, file_name] = fileparts(file_path);
year_text = regexp(file_name, '(19|20)\d{2}', 'match', 'once');
if isempty(year_text)
    source_year = default_year;
else
    source_year = str2double(year_text);
end
end

function power_series = read_renewables_ninja_csv(file_path)
file_lines = readlines(file_path);
header_line_index = find_header_line(file_lines);
header_names = split(strtrim(file_lines(header_line_index)), ',');
header_names = lower(strtrim(header_names));

time_column_index = find(strcmp(header_names, 'time'), 1);
power_column_index = find(strcmp(header_names, 'electricity'), 1);

if isempty(time_column_index) || isempty(power_column_index)
    error('load_res_year:bad_header', ...
        'Missing time/electricity columns in %s.', file_path);
end

data_lines = file_lines((header_line_index + 1):end);
data_lines = data_lines(strlength(strtrim(data_lines)) > 0);
row_count = numel(data_lines);
time_text = strings(row_count, 1);
power_kw = nan(row_count, 1);

for row_index = 1:row_count
    row_tokens = split(data_lines(row_index), ',');
    if numel(row_tokens) < max(time_column_index, power_column_index)
        continue
    end

    time_text(row_index) = strtrim(row_tokens(time_column_index));
    power_kw(row_index) = str2double(strtrim(row_tokens(power_column_index)));
end

time = parse_time_text(time_text);
valid_row_index = ~isnat(time) & ~isnan(power_kw);
if ~any(valid_row_index)
    error('load_res_year:bad_data', ...
        'No valid time/electricity rows in %s.', file_path);
end

power_series.time = time(valid_row_index);
power_series.power_kw = power_kw(valid_row_index);
power_series.file_path = file_path;
power_series.raw_row_count = row_count;
power_series.bad_row_count = row_count - nnz(valid_row_index);
end

function header_line_index = find_header_line(file_lines)
for line_index = 1:numel(file_lines)
    line_text = lower(strtrim(file_lines(line_index)));
    if startsWith(line_text, 'time,') || strcmp(line_text, 'time')
        header_line_index = line_index;
        return
    end
end

error('load_res_year:no_header', 'No time header found.');
end

function time = parse_time_text(time_text)
input_formats = { ...
    'yyyy-MM-dd HH:mm', ...
    'yyyy/M/d H:mm', ...
    'yyyy/MM/dd HH:mm', ...
    'yyyy-MM-dd HH:mm:ss', ...
    'yyyy/M/d H:mm:ss'};

time = NaT(size(time_text), 'TimeZone', 'UTC');
for format_index = 1:numel(input_formats)
    try
        parsed_time = datetime(time_text, ...
            'InputFormat', input_formats{format_index}, ...
            'TimeZone', 'UTC');
        if all(~isnat(parsed_time))
            time = parsed_time;
            return
        end
    catch
    end
end

for row_index = 1:numel(time_text)
    for format_index = 1:numel(input_formats)
        try
            time(row_index) = datetime(time_text(row_index), ...
                'InputFormat', input_formats{format_index}, ...
                'TimeZone', 'UTC');
            break
        catch
        end
    end
end
end

function power_series = clean_power_series(power_series)
if isempty(power_series.time)
    error('load_res_year:empty_source', ...
        'Source file has no valid data: %s', power_series.file_path);
end

[sorted_time, sort_index] = sort(power_series.time);
sorted_power_kw = power_series.power_kw(sort_index);

[unique_time, ~, group_index] = unique(sorted_time);
unique_power_kw = accumarray(group_index, sorted_power_kw, [], @mean);

power_series.time = unique_time;
power_series.power_kw = max(unique_power_kw, 0);
power_series.duplicate_row_count = numel(sorted_time) - numel(unique_time);
end

function [pv_series, pw_series, config] = ...
    normalize_calendar_year(pv_series, pw_series, config)
pv_has_leap_day = has_leap_day(pv_series.time);
pw_has_leap_day = has_leap_day(pw_series.time);
use_leap_day = config.keep_leap_day && pv_has_leap_day && pw_has_leap_day;

if isempty(config.output_year)
    config.output_year = choose_output_year(config, use_leap_day);
elseif is_leap_year(config.output_year) && ~use_leap_day
    error('load_res_year:bad_output_year', ...
        ['config.output_year cannot be a leap year unless both source ', ...
        'files keep February 29.']);
end

if ~use_leap_day
    pv_series = remove_leap_day(pv_series);
    pw_series = remove_leap_day(pw_series);
end

pv_series.time = normalize_time_year(pv_series.time, config.output_year);
pw_series.time = normalize_time_year(pw_series.time, config.output_year);

pv_series = clean_power_series(pv_series);
pw_series = clean_power_series(pw_series);
end

function output_year = choose_output_year(config, use_leap_day)
if use_leap_day
    output_year = 2024;
elseif config.pv_source_year == config.pw_source_year && ...
        ~is_leap_year(config.pv_source_year)
    output_year = config.pv_source_year;
else
    output_year = 2022;
end
end

function has_day = has_leap_day(time)
has_day = any(month(time) == 2 & day(time) == 29);
end

function power_series = remove_leap_day(power_series)
keep_index = ~(month(power_series.time) == 2 & day(power_series.time) == 29);
power_series.time = power_series.time(keep_index);
power_series.power_kw = power_series.power_kw(keep_index);
end

function time = normalize_time_year(time, output_year)
try
    time = datetime(output_year, month(time), day(time), hour(time), ...
        minute(time), second(time), 'TimeZone', 'UTC');
catch error_info
    error('load_res_year:bad_calendar', ...
        'Cannot normalize source time to output year %d: %s', ...
        output_year, error_info.message);
end
end

function is_leap = is_leap_year(year_value)
is_leap = mod(year_value, 400) == 0 || ...
    (mod(year_value, 4) == 0 && mod(year_value, 100) ~= 0);
end

function [time_grid, pv_unit_power_kw, pw_unit_power_kw] = ...
    make_common_time_grid(pv_series, pw_series, config)
start_time = max([pv_series.time(1); pw_series.time(1)]);
end_time = min([pv_series.time(end); pw_series.time(end)]);

if end_time < start_time
    error('load_res_year:no_overlap', ...
        'PV and PW files have no overlapping normalized time range.');
end

time_grid = (start_time:hours(config.time_step_h):end_time)';
if isempty(time_grid)
    error('load_res_year:empty_time_grid', ...
        'No time grid can be built from the normalized source range.');
end

pv_unit_power_kw = interpolate_power_series( ...
    pv_series.time, pv_series.power_kw, time_grid);
pw_unit_power_kw = interpolate_power_series( ...
    pw_series.time, pw_series.power_kw, time_grid);

pv_unit_power_kw = fill_power_gaps(pv_unit_power_kw);
pw_unit_power_kw = fill_power_gaps(pw_unit_power_kw);
end

function interpolated_power_kw = interpolate_power_series( ...
    source_time, source_power_kw, target_time)
source_hour = hours(source_time - source_time(1));
target_hour = hours(target_time - source_time(1));

interpolated_power_kw = interp1( ...
    source_hour, source_power_kw, target_hour, 'linear', NaN);
interpolated_power_kw = max(interpolated_power_kw, 0);
end

function power_kw = fill_power_gaps(power_kw)
if any(isnan(power_kw))
    power_kw = fillmissing(power_kw, 'linear', 'EndValues', 'nearest');
end

if any(isnan(power_kw))
    error('load_res_year:bad_nan', 'Power data still contains NaN.');
end
end

function [time, pv_power_kw, pw_power_kw] = select_time_span( ...
    time_grid, pv_all_power_kw, pw_all_power_kw, config)
if isempty(config.start_time)
    start_time = time_grid(1);
elseif isa(config.start_time, 'datetime')
    start_time = normalize_input_time(config.start_time, config.output_year);
else
    parsed_time = parse_time_text(string(config.start_time));
    if ~isscalar(parsed_time)
        error('load_res_year:bad_time', ...
            'config.start_time must be a scalar time.');
    end

    start_time = normalize_input_time(parsed_time(1), config.output_year);
end

if isnat(start_time)
    error('load_res_year:bad_time', 'Invalid config.start_time.');
end

if isempty(config.day_count)
    selected_index = time_grid >= start_time;
    expected_count = nnz(selected_index);
else
    needed_row_count = round(24 * config.day_count / config.time_step_h);
    end_time = start_time + hours((needed_row_count - 1) * config.time_step_h);
    selected_index = time_grid >= start_time & time_grid <= end_time;
    expected_count = needed_row_count;
end

time = time_grid(selected_index);
pv_power_kw = pv_all_power_kw(selected_index);
pw_power_kw = pw_all_power_kw(selected_index);

if numel(time) ~= expected_count
    error('load_res_year:bad_span', ...
        'Selected span has %d rows, expected %d.', ...
        numel(time), expected_count);
end
end

function time = normalize_input_time(time, output_year)
if ~isscalar(time) || isnat(time)
    error('load_res_year:bad_time', ...
        'config.start_time must be a valid scalar time.');
end

time.TimeZone = 'UTC';
time = normalize_time_year(time, output_year);
end

function renewable_data = pack_renewable_data( ...
    time, pv_power_kw, pw_power_kw, config, pv_series, pw_series)
renewable_data.time = time;
renewable_data.time_index = (1:numel(time))';
renewable_data.time_step_h = config.time_step_h;
renewable_data.time_count = numel(time);

renewable_data.pv_power_kw = pv_power_kw(:);
renewable_data.pw_power_kw = pw_power_kw(:);
renewable_data.renewable_power_kw = ...
    renewable_data.pv_power_kw + renewable_data.pw_power_kw;

renewable_data.pv_capacity_factor = ...
    renewable_data.pv_power_kw ./ config.pv_capacity_kw;
renewable_data.pw_capacity_factor = ...
    renewable_data.pw_power_kw ./ config.pw_capacity_kw;

renewable_data.unit = 'kW';
renewable_data.time_zone = 'UTC';

renewable_data.source.pv_path = config.pv_path;
renewable_data.source.pw_path = config.pw_path;
renewable_data.source.data_dir = config.data_dir;
renewable_data.source.start_time = renewable_data.time(1);
renewable_data.source.end_time = renewable_data.time(end);
renewable_data.source.day_count = ...
    renewable_data.time_count * config.time_step_h / 24;
renewable_data.source.pv_capacity_kw = config.pv_capacity_kw;
renewable_data.source.pw_capacity_kw = config.pw_capacity_kw;
renewable_data.source.pv_raw_row_count = pv_series.raw_row_count;
renewable_data.source.pw_raw_row_count = pw_series.raw_row_count;
renewable_data.source.pv_bad_row_count = pv_series.bad_row_count;
renewable_data.source.pw_bad_row_count = pw_series.bad_row_count;
renewable_data.source.pv_duplicate_row_count = pv_series.duplicate_row_count;
renewable_data.source.pw_duplicate_row_count = pw_series.duplicate_row_count;
end

function check_output_data(renewable_data)
if renewable_data.time_count <= 0
    error('load_res_year:empty', 'Output data is empty.');
end

if any(isnan(renewable_data.renewable_power_kw))
    error('load_res_year:nan_out', 'Output data contains NaN.');
end

if any(renewable_data.pv_power_kw < 0) || any(renewable_data.pw_power_kw < 0)
    error('load_res_year:negative_output', ...
        'Output data contains negative power.');
end

if renewable_data.time_count > 1
    time_step_vector_h = hours(diff(renewable_data.time));
    if any(abs(time_step_vector_h - renewable_data.time_step_h) > 1e-9)
        error('load_res_year:bad_step', 'Output time step is not uniform.');
    end
end
end

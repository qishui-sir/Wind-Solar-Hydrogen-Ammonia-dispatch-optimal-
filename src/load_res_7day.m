function renewable_data = load_res_7day(config)
%LOAD_RES_7DAY Read PV/PW hourly data and return a 7-day data set.
%   renewable_data = load_res_7day() reads the project Renewables.ninja files.
%   renewable_data = load_res_7day(config) allows a custom data directory/file
%   paths, start time, day count, time step, and capacity scaling.

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

if ~isfield(config, 'data_dir') || isempty(config.data_dir)
    if isfolder(default_data_dir)
        config.data_dir = default_data_dir;
    else
        config.data_dir = legacy_data_dir;
    end
else
    config.data_dir = path_to_char(config.data_dir, 'config.data_dir');
end

if ~isfield(config, 'pv_path') || isempty(config.pv_path)
    config.pv_path = fullfile(config.data_dir, '2022PV.csv');
else
    config.pv_path = path_to_char(config.pv_path, 'config.pv_path');
end

if ~isfield(config, 'pw_path') || isempty(config.pw_path)
    config.pw_path = fullfile(config.data_dir, '2022PW.csv');
else
    config.pw_path = path_to_char(config.pw_path, 'config.pw_path');
end

if ~isfield(config, 'time_step_h') || isempty(config.time_step_h)
    config.time_step_h = 1;
end

if ~isfield(config, 'day_count') || isempty(config.day_count)
    config.day_count = 7;
end

if ~isfield(config, 'start_time')
    config.start_time = [];
end

if ~isfield(config, 'pv_capacity_kw') || isempty(config.pv_capacity_kw)
    config.pv_capacity_kw = 1;
end

if ~isfield(config, 'pw_capacity_kw') || isempty(config.pw_capacity_kw)
    config.pw_capacity_kw = 1;
end

config.time_step_h = must_positive_scalar( ...
    config.time_step_h, 'config.time_step_h', 'load_res_7day:bad_time_step');
config.day_count = must_positive_scalar( ...
    config.day_count, 'config.day_count', 'load_res_7day:bad_day_count');
config.pv_capacity_kw = must_positive_scalar( ...
    config.pv_capacity_kw, 'config.pv_capacity_kw', 'load_res_7day:bad_capacity');
config.pw_capacity_kw = must_positive_scalar( ...
    config.pw_capacity_kw, 'config.pw_capacity_kw', 'load_res_7day:bad_capacity');

time_step_count = 24 * config.day_count / config.time_step_h;
if abs(time_step_count - round(time_step_count)) > 1e-9
    error('load_res_7day:bad_time_grid', ...
        'config.time_step_h must divide 24 * config.day_count evenly.');
end
end

function value = must_positive_scalar(value, name, error_id)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
    error(error_id, '%s must be a positive finite scalar.', name);
end
end

function path_text = path_to_char(path_value, name)
if ~(ischar(path_value) || (isstring(path_value) && isscalar(path_value)))
    error('load_res_7day:bad_path', '%s must be a text scalar.', name);
end

path_text = char(path_value);
if isempty(strtrim(path_text))
    error('load_res_7day:bad_path', '%s must not be empty.', name);
end
end

function must_file(file_path)
if ~isfile(file_path)
    error('load_res_7day:no_file', 'File not found: %s', file_path);
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
    error('load_res_7day:bad_header', ...
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
    error('load_res_7day:bad_data', ...
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

error('load_res_7day:no_header', 'No time header found.');
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
    error('load_res_7day:empty_source', ...
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

function [time_grid, pv_unit_power_kw, pw_unit_power_kw] = ...
    make_common_time_grid(pv_series, pw_series, config)
start_time = max([pv_series.time(1); pw_series.time(1)]);
end_time = min([pv_series.time(end); pw_series.time(end)]);

if end_time < start_time
    error('load_res_7day:no_overlap', ...
        'PV and PW files have no overlapping time range.');
end

time_grid = (start_time:hours(config.time_step_h):end_time)';
if isempty(time_grid)
    error('load_res_7day:empty_time_grid', ...
        'No time grid can be built from the overlapping source range.');
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
    error('load_res_7day:bad_nan', 'Power data still contains NaN.');
end
end

function [time, pv_power_kw, pw_power_kw] = select_time_span( ...
    time_grid, pv_all_power_kw, pw_all_power_kw, config)
if isempty(config.start_time)
    start_time = time_grid(1);
elseif isa(config.start_time, 'datetime')
    start_time = config.start_time;
    if ~isscalar(start_time) || isnat(start_time)
        error('load_res_7day:bad_time', ...
            'config.start_time must be a valid scalar time.');
    end

    start_time.TimeZone = 'UTC';
else
    start_time = parse_time_text(string(config.start_time));
    if ~isscalar(start_time)
        error('load_res_7day:bad_time', ...
            'config.start_time must be a scalar time.');
    end

    start_time = start_time(1);
    if isnat(start_time)
        error('load_res_7day:bad_time', 'Invalid config.start_time.');
    end
end

needed_row_count = round(24 * config.day_count / config.time_step_h);
end_time = start_time + hours((needed_row_count - 1) * config.time_step_h);
selected_index = time_grid >= start_time & time_grid <= end_time;

time = time_grid(selected_index);
pv_power_kw = pv_all_power_kw(selected_index);
pw_power_kw = pw_all_power_kw(selected_index);

if numel(time) ~= needed_row_count
    error('load_res_7day:bad_span', ...
        'Selected span has %d rows, expected %d.', ...
        numel(time), needed_row_count);
end
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
renewable_data.source.day_count = config.day_count;
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
    error('load_res_7day:empty', 'Output data is empty.');
end

if any(isnan(renewable_data.renewable_power_kw))
    error('load_res_7day:nan_out', 'Output data contains NaN.');
end

if any(renewable_data.pv_power_kw < 0) || any(renewable_data.pw_power_kw < 0)
    error('load_res_7day:negative_output', ...
        'Output data contains negative power.');
end

time_step_vector_h = hours(diff(renewable_data.time));
if any(abs(time_step_vector_h - renewable_data.time_step_h) > 1e-9)
    error('load_res_7day:bad_step', 'Output time step is not uniform.');
end
end

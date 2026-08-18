function [optimized_count, info] = algorithm(power_kw, ael_common, options)
%ALGORITHM Optimize AEL online-module retention after the dispatch MILP.

if nargin < 3 || isempty(options)
    options = struct();
end

options = applyDefaults(options);
power_kw = power_kw(:);

module_num = ael_common.module_num;
module_power_kw = ael_common.module_power;
module_min_kw = ael_common.min_load * module_power_kw;
module_max_kw = ael_common.max_load * module_power_kw;

validateattributes(power_kw, {'numeric'}, ...
    {'real', 'finite', 'column'});
validateattributes(module_num, {'numeric'}, ...
    {'scalar', 'integer', 'positive'});
validateattributes(module_min_kw, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(module_max_kw, {'numeric'}, ...
    {'scalar', 'real', 'finite', '>=', module_min_kw});

power_tolerance_kw = max(1e-6, 1e-7 * module_power_kw);
if any(power_kw < -power_tolerance_kw)
    bad_time = find(power_kw < -power_tolerance_kw, 1);
    error('algorithm:negative_power', ...
        ['AEL power at time %d is negative beyond solver tolerance: ', ...
        'P = %.6f kW, tolerance = %.6f kW.'], ...
        bad_time, power_kw(bad_time), power_tolerance_kw);
end
power_kw = max(power_kw, 0);

lower_bound = ceil(max(power_kw - power_tolerance_kw, 0) ...
    / module_max_kw);
upper_bound = floor((power_kw + power_tolerance_kw) ...
    / module_min_kw);
lower_bound = min(max(lower_bound, 0), module_num);
upper_bound = min(max(upper_bound, 0), module_num);

if any(lower_bound > upper_bound)
    bad_time = find(lower_bound > upper_bound, 1);
    error('algorithm:infeasible_bounds', ...
        ['AEL power at time %d has no feasible integer module count: ', ...
        'P = %.6f kW, lower = %d, upper = %d.'], ...
        bad_time, power_kw(bad_time), lower_bound(bad_time), ...
        upper_bound(bad_time));
end

time_count = numel(power_kw);
optimized_count = zeros(time_count, 1);

for time_index = 1:time_count
    if time_index == 1
        previous_count = min(max(options.initial_count, ...
            lower_bound(time_index)), upper_bound(time_index));
    else
        previous_count = optimized_count(time_index - 1);
    end

    current_count = lower_bound(time_index);
    retention_limit = min(previous_count, upper_bound(time_index));
    if retention_limit > current_count
        optional_levels = ((current_count + 1):retention_limit)';
        future_end = min(time_count, ...
            time_index + options.future_hours);
        future_window = lower_bound(time_index:future_end);
        future_factor = mean(...
            future_window' >= optional_levels, 2);

        history_indices = time_index - options.hours_per_day * ...
            (1:options.history_days);
        history_indices = history_indices(history_indices >= 1);
        if isempty(history_indices)
            combined_score = future_factor;
        else
            history_window = optimized_count(history_indices);
            history_factor = mean(...
                history_window' >= optional_levels, 2);
            combined_score = ...
                options.future_weight * future_factor + ...
                (1 - options.future_weight) * history_factor;
        end

        retained_levels = optional_levels(...
            combined_score >= options.keep_threshold);
        if ~isempty(retained_levels)
            current_count = max(retained_levels);
        end
    end

    optimized_count(time_index) = min(max(current_count, ...
        lower_bound(time_index)), upper_bound(time_index));
end

module_change = diff([options.initial_count; optimized_count]);
info.lower_bound = lower_bound;
info.upper_bound = upper_bound;
info.startup_count = sum(max(module_change, 0));
info.start_event_count = sum(module_change > 0);
info.shutdown_count = sum(max(-module_change, 0));
info.extra_online_hours = sum(optimized_count - lower_bound);
info.options = options;
end

function options = applyDefaults(options)
defaults = struct();
defaults.future_hours = 11;
defaults.history_days = 7;
defaults.hours_per_day = 24;
defaults.future_weight = 0.7;
defaults.keep_threshold = 0.5;
defaults.initial_count = 0;

names = fieldnames(defaults);
for name_index = 1:numel(names)
    name = names{name_index};
    if ~isfield(options, name) || isempty(options.(name))
        options.(name) = defaults.(name);
    end
end

validateattributes(options.future_hours, {'numeric'}, ...
    {'scalar', 'integer', 'nonnegative'});
validateattributes(options.history_days, {'numeric'}, ...
    {'scalar', 'integer', 'nonnegative'});
validateattributes(options.hours_per_day, {'numeric'}, ...
    {'scalar', 'integer', 'positive'});
validateattributes(options.future_weight, {'numeric'}, ...
    {'scalar', 'real', '>=', 0, '<=', 1});
validateattributes(options.keep_threshold, {'numeric'}, ...
    {'scalar', 'real', '>=', 0, '<=', 1});
validateattributes(options.initial_count, {'numeric'}, ...
    {'scalar', 'integer', 'nonnegative'});
end

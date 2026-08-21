function tests = test_myself
if nargout == 0
    test_file = [mfilename('fullpath'), '.m'];
    results = runtests(test_file);
    assertSuccess(results);
    return
end
tests = functiontests(localfunctions);
end

function testRandomScheduleOptimization(test_case)
config = localConfig();
required_count = randomCountSchedule(config);

result = optimizeCountSchedule(required_count, config);
repeat_result = optimizeCountSchedule(required_count, config);

verifySize(test_case, required_count, [config.sample_count, 1]);
verifyGreaterThanOrEqual(test_case, required_count, 0);
verifyLessThanOrEqual(test_case, required_count, config.module_count);
verifyGreaterThanOrEqual(test_case, result.optimized_count, required_count);
verifyLessThanOrEqual(test_case, result.optimized_count, config.module_count);
verifyLessThanOrEqual(test_case, result.optimized_unit_starts, ...
    result.original_unit_starts);
verifyLessThanOrEqual(test_case, result.optimized_start_events, ...
    result.original_start_events);
verifyEqual(test_case, result.optimized_count, ...
    repeat_result.optimized_count);
verifyEqual(test_case, result.future_factor, ...
    repeat_result.future_factor);
verifyEqual(test_case, result.history_factor, ...
    repeat_result.history_factor);
verifyEqual(test_case, optimizedUnitStartsOnly(required_count, config), ...
    result.optimized_unit_starts);
verifySize(test_case, result.future_factor, ...
    [config.sample_count, config.module_count]);
verifySize(test_case, result.history_factor, ...
    [config.sample_count, config.module_count]);
verifyGreaterThanOrEqual(test_case, result.future_factor, 0);
verifyLessThanOrEqual(test_case, result.future_factor, 1);

first_window = required_count(1:(config.future_hours + 1));
expected_first_factor = mean(first_window >= 5);
verifyEqual(test_case, result.future_factor(1, 5), ...
    expected_first_factor, 'AbsTol', 1e-12);

first_full_history_time = config.history_days * config.hours_per_day + 1;
history_indices = first_full_history_time - ...
    config.hours_per_day * (1:config.history_days);
expected_history_factor = mean(...
    result.optimized_count(history_indices) >= 5);
verifyEqual(test_case, result.history_factor(first_full_history_time, 5), ...
    expected_history_factor, 'AbsTol', 1e-12);

printComparison(result, config);
end

function testRandomScheduleIsReproducible(test_case)
config = localConfig();

first_schedule = randomCountSchedule(config);
second_schedule = randomCountSchedule(config);

verifyEqual(test_case, first_schedule, second_schedule);
end

function testStartupSensitivityAnalysis(test_case)
config = localConfig();
required_count = randomCountSchedule(config);
test_dir = fileparts(mfilename('fullpath'));
figure_path = fullfile(test_dir, 'png', ...
    'ael_startup_sensitivity.png');

sensitivity = runSensitivityAnalysis(...
    required_count, config, figure_path);

verifyEqual(test_case, sensitivity.future_hours, (1:71)');
verifyEqual(test_case, sensitivity.history_days, (1:20)');
verifySize(test_case, sensitivity.future_reduction, ...
    [71, config.sensitivity_rounds]);
verifySize(test_case, sensitivity.history_reduction, ...
    [20, config.sensitivity_rounds]);
verifySize(test_case, sensitivity.future_mean, [71, 1]);
verifySize(test_case, sensitivity.history_mean, [20, 1]);
verifyGreaterThanOrEqual(test_case, sensitivity.future_reduction, 0);
verifyLessThanOrEqual(test_case, sensitivity.future_reduction, 100);
verifyGreaterThanOrEqual(test_case, sensitivity.history_reduction, 0);
verifyLessThanOrEqual(test_case, sensitivity.history_reduction, 100);
verifyNotEqual(test_case, sensitivity.future_reduction(:, 1), ...
    sensitivity.future_reduction(:, 2));
verifyTrue(test_case, isfile(figure_path));
end

function config = localConfig()
config.sample_count = 700;
config.module_count = 26;
config.hours_per_day = 24;
config.future_hours = 5;
config.history_days = 7;
config.future_weight = 0.5;
config.keep_threshold = 0.5;
config.random_seed = 20240818;
config.sensitivity_rounds = 10;
config.show_figure = true;
end

function required_count = randomCountSchedule(config)
old_random_state = rng;
random_cleanup = onCleanup(@() rng(old_random_state));
rng(config.random_seed, 'twister');
required_count = randi([0, config.module_count], config.sample_count, 1);
end

function result = optimizeCountSchedule(required_count, config)
sample_count = numel(required_count);
module_levels = (1:config.module_count)';
optimized_count = zeros(sample_count, 1);
future_factor = zeros(sample_count, config.module_count);
history_factor = nan(sample_count, config.module_count);
combined_score = zeros(sample_count, config.module_count);

for time_index = 1:sample_count
    future_end = min(sample_count, time_index + config.future_hours);
    future_window = required_count(time_index:future_end);
    future_factor(time_index, :) = mean(...
        future_window' >= module_levels, 2)';

    history_indices = time_index - config.hours_per_day * ...
        (1:config.history_days);
    history_indices = history_indices(history_indices >= 1);

    if isempty(history_indices)
        combined_score(time_index, :) = future_factor(time_index, :);
    else
        history_window = optimized_count(history_indices);
        history_factor(time_index, :) = mean(...
            history_window' >= module_levels, 2)';
        combined_score(time_index, :) = ...
            config.future_weight * future_factor(time_index, :) + ...
            (1 - config.future_weight) * history_factor(time_index, :);
    end

    if time_index == 1
        previous_count = 0;
    else
        previous_count = optimized_count(time_index - 1);
    end

    current_requirement = required_count(time_index);
    optimized_count(time_index) = current_requirement;

    if previous_count > current_requirement
        optional_levels = (current_requirement + 1):previous_count;
        retained_levels = optional_levels(...
            combined_score(time_index, optional_levels) >= ...
            config.keep_threshold);

        if ~isempty(retained_levels)
            optimized_count(time_index) = max(retained_levels);
        end
    end
end

[original_unit_starts, original_start_events] = ...
    startupStatistics(required_count);
[optimized_unit_starts, optimized_start_events] = ...
    startupStatistics(optimized_count);

result.required_count = required_count;
result.optimized_count = optimized_count;
result.future_factor = future_factor;
result.history_factor = history_factor;
result.combined_score = combined_score;
result.original_unit_starts = original_unit_starts;
result.optimized_unit_starts = optimized_unit_starts;
result.original_start_events = original_start_events;
result.optimized_start_events = optimized_start_events;
end

function [unit_starts, start_events] = startupStatistics(module_count)
startup_count = max(diff([0; module_count]), 0);
unit_starts = sum(startup_count);
start_events = sum(startup_count > 0);
end

function sensitivity = runSensitivityAnalysis(...
    required_count, config, figure_path)
future_hours = (1:71)';
history_days = (1:20)';
round_count = config.sensitivity_rounds;
future_unit_starts = zeros(numel(future_hours), round_count);
history_unit_starts = zeros(numel(history_days), round_count);
future_reduction = zeros(size(future_unit_starts));
history_reduction = zeros(size(history_unit_starts));
round_seeds = config.random_seed + (0:(round_count - 1));

figure_dir = fileparts(figure_path);
if ~isfolder(figure_dir)
    mkdir(figure_dir);
end

show_figure = config.show_figure && usejava('desktop');
if show_figure
    figure_visibility = 'on';
else
    figure_visibility = 'off';
end

delete(findall(groot, 'Type', 'figure', ...
    'Tag', 'AelStartupSensitivity'));
figure_handle = figure('Visible', figure_visibility, 'Color', 'w', ...
    'Position', [100, 100, 1300, 520], ...
    'Tag', 'AelStartupSensitivity', ...
    'Name', 'AEL startup sensitivity', 'NumberTitle', 'off');
plot_layout = tiledlayout(figure_handle, 1, 2, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
future_axes = nexttile(plot_layout);
hold(future_axes, 'on');
grid(future_axes, 'on');
xlim(future_axes, [future_hours(1), future_hours(end)]);
ylim(future_axes, [0, 100]);
xlabel(future_axes, 'Future horizon (h)');
ylabel(future_axes, 'Unit-start reduction (%)');
title(future_axes, 'History fixed at 7 days');

history_axes = nexttile(plot_layout);
hold(history_axes, 'on');
grid(history_axes, 'on');
xlim(history_axes, [history_days(1), history_days(end)]);
ylim(history_axes, [0, 100]);
xlabel(history_axes, 'History window (days)');
ylabel(history_axes, 'Unit-start reduction (%)');
title(history_axes, 'Future horizon fixed at 5 h');

round_colors = lines(round_count);
for round_index = 1:round_count
    round_config = config;
    round_config.random_seed = round_seeds(round_index);
    if round_index == 1
        round_required_count = required_count;
    else
        round_required_count = randomCountSchedule(round_config);
    end
    [original_unit_starts, ~] = ...
        startupStatistics(round_required_count);

    for value_index = 1:numel(future_hours)
        trial_config = round_config;
        trial_config.future_hours = future_hours(value_index);
        trial_config.history_days = 7;
        future_unit_starts(value_index, round_index) = ...
            optimizedUnitStartsOnly(round_required_count, trial_config);
    end

    for value_index = 1:numel(history_days)
        trial_config = round_config;
        trial_config.future_hours = 5;
        trial_config.history_days = history_days(value_index);
        history_unit_starts(value_index, round_index) = ...
            optimizedUnitStartsOnly(round_required_count, trial_config);
    end

    future_reduction(:, round_index) = 100 * ...
        (1 - future_unit_starts(:, round_index) / original_unit_starts);
    history_reduction(:, round_index) = 100 * ...
        (1 - history_unit_starts(:, round_index) / original_unit_starts);

    plot(future_axes, future_hours, future_reduction(:, round_index), ...
        'LineWidth', 0.9, 'Color', round_colors(round_index, :), ...
        'HandleVisibility', 'off');
    plot(history_axes, history_days, history_reduction(:, round_index), ...
        'LineWidth', 0.9, 'Color', round_colors(round_index, :), ...
        'HandleVisibility', 'off');
    title(plot_layout, sprintf(...
        'AEL startup sensitivity: round %d of %d', ...
        round_index, round_count));
    drawnow limitrate;
end

future_mean = mean(future_reduction, 2);
history_mean = mean(history_reduction, 2);
plot(future_axes, future_hours, future_mean, 'k-', ...
    'LineWidth', 2.6, 'DisplayName', 'Mean of all rounds');
plot(history_axes, history_days, history_mean, 'k-o', ...
    'LineWidth', 2.6, 'MarkerSize', 4, ...
    'MarkerFaceColor', 'k', 'DisplayName', 'Mean of all rounds');
legend(future_axes, 'Location', 'southeast');
legend(history_axes, 'Location', 'southeast');

all_reductions = [future_reduction(:); history_reduction(:)];
y_padding = max(0.5, 0.1 * range(all_reductions));
y_limits = [max(0, min(all_reductions) - y_padding), ...
    min(100, max(all_reductions) + y_padding)];
ylim(future_axes, y_limits);
ylim(history_axes, y_limits);
title(plot_layout, sprintf(...
    'AEL startup sensitivity: %d random data sets, 700 samples each', ...
    round_count));
drawnow;

exportgraphics(figure_handle, figure_path, 'Resolution', 200);
if ~show_figure
    close(figure_handle);
end

sensitivity.future_hours = future_hours;
sensitivity.future_unit_starts = future_unit_starts;
sensitivity.future_reduction = future_reduction;
sensitivity.future_mean = future_mean;
sensitivity.history_days = history_days;
sensitivity.history_unit_starts = history_unit_starts;
sensitivity.history_reduction = history_reduction;
sensitivity.history_mean = history_mean;
sensitivity.round_seeds = round_seeds;
sensitivity.figure_path = figure_path;

[best_future_reduction, best_future_index] = max(future_mean);
[best_history_reduction, best_history_index] = max(history_mean);
fprintf('\nAEL startup sensitivity analysis\n');
fprintf('Random data sets: %d, samples per set: %d\n', ...
    round_count, config.sample_count);
fprintf('Best mean future horizon: %d h, reduction: %.2f%%\n', ...
    future_hours(best_future_index), best_future_reduction);
fprintf('Best mean history window: %d days, reduction: %.2f%%\n', ...
    history_days(best_history_index), best_history_reduction);
fprintf('Sensitivity figure: %s\n', figure_path);
end

function unit_starts = optimizedUnitStartsOnly(required_count, config)
sample_count = numel(required_count);
optimized_count = zeros(sample_count, 1);

for time_index = 1:sample_count
    if time_index == 1
        previous_count = 0;
    else
        previous_count = optimized_count(time_index - 1);
    end

    current_requirement = required_count(time_index);
    optimized_count(time_index) = current_requirement;
    if previous_count <= current_requirement
        continue
    end

    optional_levels = ((current_requirement + 1):previous_count)';
    future_end = min(sample_count, time_index + config.future_hours);
    future_window = required_count(time_index:future_end);
    future_factor = mean(future_window' >= optional_levels, 2);

    history_indices = time_index - config.hours_per_day * ...
        (1:config.history_days);
    history_indices = history_indices(history_indices >= 1);
    if isempty(history_indices)
        combined_score = future_factor;
    else
        history_window = optimized_count(history_indices);
        history_factor = mean(history_window' >= optional_levels, 2);
        combined_score = config.future_weight * future_factor + ...
            (1 - config.future_weight) * history_factor;
    end

    retained_levels = optional_levels(...
        combined_score >= config.keep_threshold);
    if ~isempty(retained_levels)
        optimized_count(time_index) = max(retained_levels);
    end
end

[unit_starts, ~] = startupStatistics(optimized_count);
end

function printComparison(result, config)
fprintf('\nAEL random schedule startup comparison\n');
fprintf('Samples: %d, modules: 0-%d\n', ...
    config.sample_count, config.module_count);
fprintf('Future horizon: %d h, history: %d days\n', ...
    config.future_hours, config.history_days);
fprintf('Original unit starts:  %d\n', result.original_unit_starts);
fprintf('Optimized unit starts: %d\n', result.optimized_unit_starts);
fprintf('Original start events:  %d\n', result.original_start_events);
fprintf('Optimized start events: %d\n', result.optimized_start_events);
fprintf('Unit-start reduction:   %.2f%%\n', ...
    100 * (1 - result.optimized_unit_starts / result.original_unit_starts));
fprintf('Event reduction:        %.2f%%\n', ...
    100 * (1 - result.optimized_start_events / result.original_start_events));

preview_count = min(20, config.sample_count);
preview = table((1:preview_count)', ...
    result.required_count(1:preview_count), ...
    result.optimized_count(1:preview_count), ...
    'VariableNames', {'Hour', 'Original', 'Optimized'});
disp(preview);
end

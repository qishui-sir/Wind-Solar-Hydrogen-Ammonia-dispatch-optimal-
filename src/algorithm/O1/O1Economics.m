function outputs = O1Economics(ctx, feasibility, reference)
%O1ECONOMICS 求解固定K成本前沿及其经济边界。
% 本文件负责成本前沿记录、经济成本容许量和运行指标。
[representative, frontier, frontier_state, structure, certification] = ...
    solve_cost_outputs( ...
    ctx, feasibility, ctx.config.frontier_k, reference);
economic = struct([]);
if feasibility.is_proven && isfinite(reference.objective_lower)
    economic = solve_economic_boundaries(ctx, reference, feasibility);
end
outputs = struct('representative', representative, ...
    'frontier', frontier, 'frontier_state', frontier_state, ...
    'structure', structure, 'certification', certification, ...
    'boundaries', economic);
end

function [representative, frontier, frontier_state, structure, ...
        certification] = solve_cost_outputs( ...
        ctx, feasibility, requested_K, reference)
% 先用稀疏锚点识别C*(K)前沿，再对少量关键K执行高精度认证。
upper = feasibility.K_upper;
initial = feasibility.minimum_updates.solution;
reference_count = round(sum(reference.solution.O1_HB_change));
if ctx.config.frontier_all_k
    % 已知K_upper严格可行，因此[K_upper, reference_count]均可直接
    % 进行成本优化；无需等待最小K的下界与上界闭合。
    first_K = max(0, ceil(feasibility.K_upper));
    last_K = min(ctx.T, reference_count);
    frontier_K = (first_K:last_K).';
else
    frontier_K = unique(round([requested_K(:); ...
        ctx.config.frontier_key_k(:); upper]));
    frontier_K = frontier_K(frontier_K >= 0 & frontier_K <= ctx.T);
end

variable_types = {'double', 'double', 'double', 'double', 'double', ...
    'double', 'double', 'double', 'logical', 'logical', 'logical', ...
    'string', 'string', 'string', 'double', 'double', 'double'};
variable_names = {'K', 'cost_lower_usd', 'cost_upper_usd', ...
    'lcoa_lower_usd_t', 'lcoa_upper_usd_t', ...
    'premium_lower_usd_t', 'premium_upper_usd_t', ...
    'actual_updates', 'has_incumbent', 'is_proven', 'is_certified', ...
    'status', 'phase', 'solve_backend', 'uncertainty_usd_t', ...
    'elapsed_s', 'attempts'};
frontier = table('Size', [numel(frontier_K), numel(variable_names)], ...
    'VariableTypes', variable_types, 'VariableNames', variable_names);
frontier.K = frontier_K;
frontier.cost_lower_usd(:) = NaN;
frontier.cost_upper_usd(:) = NaN;
frontier.lcoa_lower_usd_t(:) = NaN;
frontier.lcoa_upper_usd_t(:) = NaN;
frontier.premium_lower_usd_t(:) = NaN;
frontier.premium_upper_usd_t(:) = NaN;
frontier.actual_updates(:) = NaN;
frontier.has_incumbent(:) = false;
frontier.is_proven(:) = false;
frontier.is_certified(:) = false;
frontier.status(:) = "not_run";
frontier.phase(:) = "";
frontier.solve_backend(:) = "";
frontier.uncertainty_usd_t(:) = NaN;
frontier.elapsed_s(:) = 0;
frontier.attempts(:) = 0;
component_names = fieldnames(ctx.cost_components);
for component_index = 1:numel(component_names)
    frontier.(component_names{component_index}) = ...
        NaN(height(frontier), 1);
end
metric_names = {'curtailment_mwh', 'purchase_mwh', 'sales_mwh', ...
    'ael_start_energy_mwh', 'ael_started_modules', ...
    'storage_swing_kg', 'storage_throughput_kg'};
for metric_index = 1:numel(metric_names)
    frontier.(metric_names{metric_index}) = NaN(height(frontier), 1);
end

for row = 1:height(frontier)
    K = frontier.K(row);
    if K < feasibility.K_lower
        point = make_non_solved_point(K, Inf, Inf, ...
            "infeasible_certified", "count_bound");
        assign_row(row, point);
    elseif K >= reference_count
        point = reference;
        point.K_limit = K;
        point.count_upper = reference_count;
        point.status = "reference_bound";
        point.solve_backend = "economic_reference";
        point.elapsed_s = 0;
        point.frontier_attempts = 0;
        assign_row(row, point);
    end
end

if ctx.config.frontier_all_k
    solve_K = select_frontier_anchors(upper, reference_count - 1, ...
        ctx.config.frontier_anchor_count, requested_K, ...
        ctx.config.frontier_key_k);
else
    solve_K = unique([upper; requested_K(:)]);
    solve_K = solve_K(solve_K >= upper & solve_K < reference_count);
end
solve_K = sort(solve_K, 'ascend');
cost_problem = ctx.problem;
cost_problem.Constraints.O1_update_limit = ctx.update_count <= ctx.T;
cost_problem.Objective = ctx.system_cost_usd;
[cost_solver, build_elapsed_s] = ctx.services.build_fixed_solver( ...
    cost_problem, ctx, initial);
cost_solver.problem.options = ctx.frontier_options;
if ctx.config.frontier_scale_solver
    units = ones(numel(cost_solver.problem.lb), 1);
    names = {'P_AEL', 'p_purchase', 'p_sell', 'p_curt', 'storage_H2'};
    for i = 1:numel(names)
        if isfield(cost_solver.indices, names{i})
            units(cost_solver.indices.(names{i})(:)) = 1000;
        end
    end
    % 仅用于长时原模型认证；快速锚点与局部搜索继续使用已验证的原单位。
    cost_solver.variable_units = units;
end
fprintf(['[O1] Cost frontier: %d optimized K points, %d total rows; ', ...
    'matrix build %.1f s.\n'], numel(solve_K), numel(frontier_K), ...
    build_elapsed_s);

cache_mode = "frontier_cost";
cost_entries = ctx.services.fixed_point_store(ctx.point_cache_file, ...
    ctx.cost_signature, ...
    "load", cache_mode, Inf, struct());
legacy_entries = ctx.services.fixed_point_store(ctx.point_cache_file, ...
    ctx.signature, "load", cache_mode, Inf, struct());
for legacy_index = 1:numel(legacy_entries)
    legacy_entry = legacy_entries(legacy_index);
    if any([cost_entries.K] == legacy_entry.K)
        continue
    end
    legacy_entry.record = ctx.services.migrate_cost_record( ...
        legacy_entry.record, ctx);
    legacy_entry.record.frontier_phase = "legacy_anchor";
    cost_entries(end + 1) = legacy_entry; %#ok<AGROW>
end
current_start = initial;
representative = reference;
frontier_started = tic;
new_point_count = 0;
budget_exhausted = false;
for index = 1:numel(solve_K)
    K = solve_K(index);
    cached_index = find([cost_entries.K] == K, 1);
    cached = struct();
    attempts = 0;
    if ~isempty(cached_index)
        cached = cost_entries(cached_index).record;
        % 旧的未知记录也可能获得新单调下界，不能只初始化空记录。
        cached = strengthen_anchor_bound(cached, K, cost_entries, reference, ctx);
        cost_entries(cached_index).record = cached;
        if isfield(cached, 'frontier_attempts')
            attempts = cached.frontier_attempts;
        end
        if isfield(cached, 'solution') && ...
                ~isempty(fieldnames(cached.solution)) && ...
                round(sum(cached.solution.O1_HB_change)) <= K
            cached_cost = cached.objective_upper;
            current_cost = evaluate(ctx.system_cost_usd, current_start);
            if isfinite(cached_cost) && cached_cost < current_cost
                current_start = cached.solution;
            end
        end
    end

    current_count = round(sum(current_start.O1_HB_change));
    gained_feasible_seed = ~isempty(fieldnames(cached)) && ...
        ~cached.has_incumbent && current_count <= K;
    retryable_status = ["seed_cost_bound", "unknown", "solver_error"];
    missing_attribution = ~isempty(fieldnames(cached)) && ...
        cached.has_incumbent && ...
        (~isfield(cached, 'cost_components') || ...
        ~isfield(cached, 'operation_metrics'));
    retryable_fallback = ~isempty(fieldnames(cached)) && ...
        ((any(string(cached.status) == retryable_status) && ...
        attempts < ctx.config.frontier_max_attempts) || ...
        gained_feasible_seed || missing_attribution);
    reusable = ~isempty(fieldnames(cached)) && ~retryable_fallback;
    if reusable
        point = cached;
        point.elapsed_s = 0;
        if ~isfield(point, 'frontier_phase')
            point.frontier_phase = "anchor";
            cost_entries(cached_index).record = point;
        end
        fprintf('[O1] 锚点K=%g复用缓存：[%g, %g] USD（%s）。\n', ...
            K, point.objective_lower, point.objective_upper, point.status);
    else
        if new_point_count >= ctx.config.frontier_points_per_run || ...
                toc(frontier_started) >= ctx.config.frontier_run_budget_s
            budget_exhausted = true;
            fprintf(['[O1] frontier run budget reached after %d new ', ...
                'points; remaining K values stay cached as pending.\n'], ...
                new_point_count);
            break
        end
        if isempty(fieldnames(cached))
            % 新发现的较小K继承较大K的有效美元下界，不从参考下界重新开始。
            cached = monotonic_anchor_envelope(K, cost_entries, reference, ctx);
            cached.solution = current_start;
            cached.has_incumbent = current_count <= K;
            cached.count_upper = current_count;
            cached.objective_upper = evaluate(ctx.system_cost_usd, current_start);
            cached.system_cost_upper = cached.objective_upper;
            cached.status = "seed_cost_bound";
        end
        point = solve_cost_frontier_point(cost_solver, K, current_start, ...
            ctx, reference, attempts + 1, "anchor", cached);
        new_point_count = new_point_count + 1;
        cache_record = point;
        % 稀疏锚点数有界，保留完整向量，自动选为关键点后可直接热启动。
        keep_solution = numel(solve_K) <= ctx.config.frontier_anchor_count + ...
            numel(ctx.config.frontier_key_k) || K == upper || ...
            any(K == ctx.config.frontier_key_k) || ...
            mod(abs(K - upper), ...
            ctx.config.frontier_solution_interval) == 0;
        if ~keep_solution
            cache_record.solution = struct();
        end
        entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
            'record', cache_record, 'source', "frontier_anchor");
        ctx.services.fixed_point_store(ctx.point_cache_file, ...
            ctx.cost_signature, ...
            "append", cache_mode, Inf, entry);
        cached_index = find([cost_entries.K] == K, 1);
        if isempty(cached_index)
            cost_entries(end + 1) = entry;
        else
            cost_entries(cached_index) = entry;
        end
        fprintf(['[O1] 锚点K=%g：[%g, %g] USD，实际K=%g，', ...
            '%s，%.1f s。\n'], K, point.objective_lower, ...
            point.objective_upper, point.count_upper, point.status, ...
            point.elapsed_s);
    end
    if isfield(point, 'solution') && ...
            ~isempty(fieldnames(point.solution)) && ...
            round(sum(point.solution.O1_HB_change)) <= K
        current_start = point.solution;
    end
    row = find(frontier.K == K, 1);
    if ~isempty(row)
        assign_row(row, point);
    end
    if K == upper
        representative = point;
        if ~isfield(representative, 'solution') || ...
                isempty(fieldnames(representative.solution))
            representative.solution = initial;
        end
    end
end

structure = analyze_frontier_structure(cost_entries, reference, ...
    upper, reference_count, ctx);
if ctx.config.frontier_all_k
    automatic_K = structure.recommended_K(:);
else
    automatic_K = zeros(0, 1);
end
critical_K = unique([ctx.config.frontier_key_k(:); upper; ...
    automatic_K], 'stable');
critical_K = critical_K(critical_K >= upper & ...
    critical_K < reference_count);
certification_started = tic;
certification_new_points = 0;
certification_budget_exhausted = false;
for critical_index = 1:numel(critical_K)
    K = critical_K(critical_index);
    cached_index = find([cost_entries.K] == K, 1);
    cached = struct();
    if ~isempty(cached_index)
        cached = cost_entries(cached_index).record;
        cached = strengthen_anchor_bound(cached, K, cost_entries, reference, ctx);
        cost_entries(cached_index).record = cached;
    end
    uncertainty = record_uncertainty_usd_t(cached, ctx);
    certification_attempts = record_field(cached, ...
        'certification_attempts', 0);
    % 旧单位的认证额度用完后，允许一次独立的等价缩放认证，不清空旧历史。
    needs_scaled_certification = ctx.config.frontier_scale_solver && ...
        record_field(cached, 'scaled_certification_attempts', 0) < 1;
    needs_floor_certification = ctx.config.frontier_bound_floor && ...
        record_field(cached, 'floor_certification_attempts', 0) < 1;
    needs_startup_certification = ctx.config.frontier_keep_startup_binary && ...
        record_field(cached, 'startup_binary_certification_attempts', 0) < 1;
    use_gurobi = strcmp(ctx.config.frontier_solver, 'gurobi');
    gurobi_attempts = record_field(cached, 'gurobi_certification_attempts', 0);
    needs_gurobi_certification = use_gurobi && ...
        gurobi_attempts < ctx.config.frontier_certification_max_attempts;
    prefer_direct_certification = needs_floor_certification || ...
        needs_startup_certification || use_gurobi;
    if uncertainty <= ...
            ctx.config.frontier_certification_tolerance_usd_t
        continue
    end
    if certification_new_points >= ...
            ctx.config.frontier_certification_points_per_run || ...
            toc(certification_started) >= ...
            ctx.config.frontier_certification_run_budget_s
        certification_budget_exhausted = true;
        break
    end
    certification_start = best_feasible_seed( ...
        K, cost_entries, initial, ctx);
    if isempty(cached_index)
        % 自动关键点可能不是锚点：先建立真实种子记录，不能访问空记录的界值。
        cached = monotonic_anchor_envelope(K, cost_entries, reference, ctx);
        cached.solution = certification_start;
        cached.has_incumbent = true;
        cached.objective_upper = evaluate(ctx.system_cost_usd, certification_start);
        cached.system_cost_upper = cached.objective_upper;
        cached.count_upper = round(sum(certification_start.O1_HB_change));
        cached.absolute_gap = cached.objective_upper - cached.objective_lower;
        cached.frontier_phase = "certification_seed";
        cached.status = "seed_cost_bound";
        cached.is_certified = record_uncertainty_usd_t(cached, ctx) <= ...
            ctx.config.frontier_certification_tolerance_usd_t;
        if cached.is_certified
            cached.status = "certified_tolerance";
        end
        cached.cost_components = ctx.services.evaluate_cost_components( ...
            certification_start, ctx);
        cached.operation_metrics = ctx.services.evaluate_operation_metrics( ...
            certification_start, ctx);
        entry = struct('mode', cache_mode, 'cost_cap', Inf, ...
            'K', K, 'record', cached, 'source', "frontier_certification_seed");
        ctx.services.fixed_point_store(ctx.point_cache_file, ...
            ctx.cost_signature, "append", cache_mode, Inf, entry);
        cost_entries(end + 1) = entry; %#ok<AGROW>
        cached_index = numel(cost_entries);
        if cached.is_certified
            continue
        end
    end
    polish_attempts = record_field(cached, 'polish_attempts', 0);
    can_polish = ctx.config.frontier_polish_enabled && ...
        ~prefer_direct_certification && ...
        ~isempty(fieldnames(cached)) && cached.has_incumbent && ...
        polish_attempts < ctx.config.frontier_polish_max_attempts;
    if can_polish
        remaining_budget_s = ...
            ctx.config.frontier_certification_run_budget_s - ...
            toc(certification_started);
        if remaining_budget_s <= 61
            certification_budget_exhausted = true;
            break
        end
        stage_ctx = ctx;
        stage_ctx.polish_options = optimoptions(ctx.polish_options, ...
            'MaxTime', min(ctx.config.frontier_polish_max_time_s, ...
            remaining_budget_s - 60));
        total_attempts = record_field(cached, 'frontier_attempts', 0) + 1;
        point = polish_cost_upper_bound(cost_solver, K, ...
            certification_start, stage_ctx, total_attempts, cached);
        certification_new_points = certification_new_points + 1;
        entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
            'record', point, 'source', "frontier_polish");
        ctx.services.fixed_point_store(ctx.point_cache_file, ...
            ctx.cost_signature, "append", cache_mode, Inf, entry);
        if isempty(cached_index)
            cost_entries(end + 1) = entry; %#ok<AGROW>
            cached_index = numel(cost_entries);
        else
            cost_entries(cached_index) = entry;
        end
        fprintf(['[O1] 关键点K=%g定向上界精修：[%g, %g] USD，', ...
            '不确定性=%.6g USD/t，目标<=%.6g USD/t，%s，%.1f s。\n'], ...
            K, point.objective_lower, point.objective_upper, ...
            record_uncertainty_usd_t(point, ctx), ...
            ctx.config.frontier_certification_tolerance_usd_t, ...
            point.polish_status, point.polish_elapsed_s);
        cached = point;
        uncertainty = record_uncertainty_usd_t(cached, ctx);
        if uncertainty <= ...
                ctx.config.frontier_certification_tolerance_usd_t
            continue
        end
        if ctx.config.frontier_polish_only
            continue
        end
    end

    % 先在缓存模式并集及其循环时间邻域内寻找达标上界。
    local_search_pending = false;
    if ctx.config.frontier_pattern_pool_enabled && ~prefer_direct_certification && ...
            ~isempty(fieldnames(cached)) && cached.has_incumbent
        [base_hours, pattern_count] = collect_cached_pattern_pool( ...
            K, cost_entries, initial, ctx.T);
        same_pool = isfield(cached, 'pattern_pool_base_hours') && ...
            isequal(cached.pattern_pool_base_hours(:), base_hours(:));
        if same_pool
            completed_radii = record_field(cached, ...
                'pattern_pool_completed_radii_h', zeros(0, 1));
            pool_status = string(record_field(cached, ...
                'pattern_pool_status', strings(0, 1)));
            pool_elapsed = record_field(cached, ...
                'pattern_pool_elapsed_s', zeros(0, 1));
            pool_sizes = record_field(cached, ...
                'pattern_pool_candidate_hours', zeros(0, 1));
        else
            completed_radii = zeros(0, 1);
            pool_status = strings(0, 1);
            pool_elapsed = zeros(0, 1);
            pool_sizes = zeros(0, 1);
        end
        radii = ctx.config.frontier_pattern_pool_radii_h(:);
        remaining_radii = radii(~ismember(radii, completed_radii));
        if pattern_count == 1 && polish_attempts > 0
            % 单一模式的0小时邻域与已经完成的固定模式精修完全等价。
            remaining_radii(remaining_radii == 0) = [];
        end
        while ~isempty(remaining_radii) && ...
                certification_new_points < ...
                ctx.config.frontier_certification_points_per_run
            remaining_budget_s = ...
                ctx.config.frontier_certification_run_budget_s - ...
                toc(certification_started);
            if remaining_budget_s <= 61
                certification_budget_exhausted = true;
                break
            end
            radius_h = remaining_radii(1);
            allowed_z = expand_cyclic_hours(base_hours, radius_h, ctx.T);
            stage_time_s = min( ...
                ctx.config.frontier_pattern_pool_max_time_s, ...
                remaining_budget_s - 60);
            certification_start = best_feasible_seed( ...
                K, cost_entries, initial, ctx);
            target_upper = cached.objective_lower + ...
                ctx.config.frontier_certification_tolerance_usd_t * ...
                ctx.config.nh3_target_t;
            outcome = solve_cost_cap_domain(cost_solver, K, ...
                certification_start, ctx, target_upper, allowed_z, ...
                stage_time_s, ctx.pattern_pool_options);
            total_attempts = record_field(cached, ...
                'frontier_attempts', 0) + 1;
            point = merge_cost_cap_outcome(cached, outcome, ctx, K, ...
                total_attempts, "pattern_pool", ...
                "intlinprog_hb_pattern_pool_target_cap", ...
                target_upper, false);
            completed_radii(end + 1, 1) = radius_h; %#ok<AGROW>
            pool_status(end + 1, 1) = outcome.status; %#ok<AGROW>
            pool_elapsed(end + 1, 1) = outcome.elapsed_s; %#ok<AGROW>
            pool_sizes(end + 1, 1) = outcome.candidate_hours; %#ok<AGROW>
            point.pattern_pool_base_hours = base_hours;
            point.pattern_pool_pattern_count = pattern_count;
            point.pattern_pool_completed_radii_h = completed_radii;
            point.pattern_pool_status = pool_status;
            point.pattern_pool_elapsed_s = pool_elapsed;
            point.pattern_pool_candidate_hours = pool_sizes;
            entry = struct('mode', cache_mode, 'cost_cap', Inf, ...
                'K', K, 'record', point, 'source', "frontier_pattern_pool");
            ctx.services.fixed_point_store(ctx.point_cache_file, ...
                ctx.cost_signature, "append", cache_mode, Inf, entry);
            cost_entries(cached_index) = entry;
            cached = point;
            certification_new_points = certification_new_points + 1;
            fprintf(['[O1] 关键点K=%g候选池：独立模式=%d，半径=%g h，', ...
                '候选时刻=%d，[%g, %g] USD，不确定性=%.6g USD/t，', ...
                '%s，%.1f s。\n'], K, pattern_count, radius_h, ...
                outcome.candidate_hours, point.objective_lower, ...
                point.objective_upper, ...
                record_uncertainty_usd_t(point, ctx), ...
                outcome.status, outcome.elapsed_s);
            if point.is_certified
                break
            end
            remaining_radii = radii(~ismember(radii, completed_radii));
            if pattern_count == 1 && polish_attempts > 0
                remaining_radii(remaining_radii == 0) = [];
            end
        end
        local_search_pending = ~isempty(remaining_radii);
        if cached.is_certified
            continue
        end
    end
    if certification_budget_exhausted || ...
            certification_new_points >= ...
            ctx.config.frontier_certification_points_per_run
        certification_budget_exhausted = true;
        break
    end
    if ctx.config.frontier_polish_only && local_search_pending
        break
    end

    % 少量高购电增量窗口只改进原模型上界；完成时刻落盘后不重复搜索。
    if ctx.config.frontier_local_cost_enabled && ~local_search_pending && ...
            ~prefer_direct_certification
        completed = record_field(cached, 'local_cost_completed_starts', zeros(0, 1));
        while numel(completed) < ctx.config.frontier_local_cost_max_windows && ...
                certification_new_points < ...
                ctx.config.frontier_certification_points_per_run
            remaining_s = ctx.config.frontier_certification_run_budget_s - ...
                toc(certification_started);
            if remaining_s <= 61
                certification_budget_exhausted = true;
                break
            end
            certification_start = best_feasible_seed(K, cost_entries, initial, ctx);
            starts = rank_cost_windows(certification_start, reference, ctx);
            starts = starts(~ismember(starts, completed));
            if isempty(starts)
                break
            end
            first = starts(1);
            last = min(ctx.T, first + ctx.config.frontier_local_cost_window_h - 1);
            local_solver = restrict_cost_window(cost_solver, ...
                certification_start, first:last, ctx.T);
            upper_options = optimoptions(ctx.pattern_pool_options, ...
                'MaxFeasiblePoints', Inf, 'AbsoluteGapTolerance', ...
                ctx.config.frontier_certification_tolerance_usd_t * ...
                ctx.config.nh3_target_t / 4);
            outcome = solve_cost_cap_domain(local_solver, K, ...
                certification_start, ctx, Inf, true(ctx.T, 1), ...
                min(ctx.config.frontier_local_cost_max_time_s, remaining_s - 60), ...
                upper_options);
            point = merge_cost_cap_outcome(cached, outcome, ctx, K, ...
                record_field(cached, 'frontier_attempts', 0) + 1, ...
                "local_cost", "intlinprog_seeded_local_cost", Inf, false);
            completed(end + 1, 1) = first; %#ok<AGROW>
            point.local_cost_completed_starts = completed;
            point.local_cost_window_h = ctx.config.frontier_local_cost_window_h;
            entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
                'record', point, 'source', "frontier_local_cost");
            ctx.services.fixed_point_store(ctx.point_cache_file, ...
                ctx.cost_signature, "append", cache_mode, Inf, entry);
            cost_entries(cached_index) = entry;
            cached = point;
            certification_new_points = certification_new_points + 1;
            fprintf(['[O1] K=%g局部成本窗口%d:%d：[%g, %g] USD，', ...
                '不确定性=%.6g USD/t，%s，%.1f s。\n'], ...
                K, first, last, point.objective_lower, point.objective_upper, ...
                record_uncertainty_usd_t(point, ctx), outcome.status, outcome.elapsed_s);
            if point.is_certified
                break
            end
        end
        if cached.is_certified
            continue
        end
    end
    if certification_budget_exhausted || certification_new_points >= ...
            ctx.config.frontier_certification_points_per_run
        certification_budget_exhausted = true;
        break
    end

    % 全局阶段停滞后，允许少量新更新时刻出现在全年任意位置。
    if ctx.config.frontier_relocation_cost_enabled && ~local_search_pending && ...
            ~prefer_direct_certification && ...
            (~ctx.config.frontier_global_bisection_enabled || ...
            record_field(cached, 'global_bisection_attempts', 0) >= ...
            ctx.config.frontier_global_bisection_max_attempts)
        completed_q = record_field(cached, 'relocation_cost_completed_radii', zeros(0, 1));
        radii_q = unique(ctx.config.frontier_relocation_cost_radii(:), 'stable');
        pending_q = radii_q(~ismember(radii_q, completed_q));
        while ~isempty(pending_q) && certification_new_points < ...
                ctx.config.frontier_certification_points_per_run
            remaining_s = ctx.config.frontier_certification_run_budget_s - ...
                toc(certification_started);
            if remaining_s <= 61
                certification_budget_exhausted = true;
                break
            end
            q = pending_q(1);
            certification_start = best_feasible_seed(K, cost_entries, initial, ctx);
            branch_solver = cost_solver;
            branch_solver.restricted_cost_domain = true;
            z_positions = branch_solver.indices.O1_HB_change(:);
            outside = z_positions(certification_start.O1_HB_change(:) < 0.5);
            branch_solver.problem.Aineq(end + 1, :) = sparse( ...
                ones(numel(outside), 1), outside, ones(numel(outside), 1), ...
                1, numel(branch_solver.problem.lb));
            branch_solver.problem.bineq(end + 1, 1) = q;
            upper_options = optimoptions(ctx.pattern_pool_options, ...
                'MaxFeasiblePoints', Inf, 'AbsoluteGapTolerance', ...
                ctx.config.frontier_certification_tolerance_usd_t * ...
                ctx.config.nh3_target_t / 4);
            outcome = solve_cost_cap_domain(branch_solver, K, ...
                certification_start, ctx, Inf, true(ctx.T, 1), ...
                min(ctx.config.frontier_relocation_cost_max_time_s, remaining_s - 60), ...
                upper_options);
            point = merge_cost_cap_outcome(cached, outcome, ctx, K, ...
                record_field(cached, 'frontier_attempts', 0) + 1, ...
                "relocation_cost", "intlinprog_seeded_global_relocation", Inf, false);
            completed_q(end + 1, 1) = q; %#ok<AGROW>
            point.relocation_cost_completed_radii = completed_q;
            entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
                'record', point, 'source', "frontier_relocation_cost");
            ctx.services.fixed_point_store(ctx.point_cache_file, ...
                ctx.cost_signature, "append", cache_mode, Inf, entry);
            cost_entries(cached_index) = entry;
            cached = point;
            certification_new_points = certification_new_points + 1;
            fprintf(['[O1] K=%g远距离成本搜索q=%d：[%g, %g] USD，', ...
                '不确定性=%.6g USD/t，%s，%.1f s。\n'], ...
                K, q, point.objective_lower, point.objective_upper, ...
                record_uncertainty_usd_t(point, ctx), outcome.status, outcome.elapsed_s);
            if point.is_certified
                break
            end
            pending_q = radii_q(~ismember(radii_q, completed_q));
        end
        if cached.is_certified
            continue
        end
    end
    if certification_budget_exhausted || certification_new_points >= ...
            ctx.config.frontier_certification_points_per_run
        certification_budget_exhausted = true;
        break
    end

    % 候选池穷尽后，放开全部HB时刻并用成本帽二分压缩全局区间。
    if ctx.config.frontier_global_bisection_enabled && ~prefer_direct_certification && ...
            ~local_search_pending
        bisection_attempts = record_field(cached, ...
            'global_bisection_attempts', 0);
        while bisection_attempts < ...
                ctx.config.frontier_global_bisection_max_attempts && ...
                certification_new_points < ...
                ctx.config.frontier_certification_points_per_run
            remaining_budget_s = ...
                ctx.config.frontier_certification_run_budget_s - ...
                toc(certification_started);
            if remaining_budget_s <= 61
                certification_budget_exhausted = true;
                break
            end
            target_upper = select_untried_cost_cap(cached);
            stage_time_s = min( ...
                ctx.config.frontier_global_bisection_max_time_s, ...
                remaining_budget_s - 60);
            certification_start = best_feasible_seed( ...
                K, cost_entries, initial, ctx);
            % 两次无首解后换用可热启动的成本帽超额模型，避免重复冷启动。
            use_warm_cap = bisection_attempts >= 2;
            pool_cost_attempts = record_field(cached, ...
                'pool_cost_optimization_attempts', 0);
            use_pool_cost = bisection_attempts >= 4 && ...
                pool_cost_attempts == 0 && ctx.config.frontier_pattern_pool_enabled;
            stage_phase = "global_bisection";
            stage_label = "全局成本认证";
            raise_global_lower = true;
            if use_pool_cost
                % 先前硬目标帽失败不代表候选池没有中间上界改善。
                [base_hours, ~] = collect_cached_pattern_pool( ...
                    K, cost_entries, initial, ctx.T);
                radius_h = max([0; ctx.config.frontier_pattern_pool_radii_h(:)]);
                allowed_z = expand_cyclic_hours(base_hours, radius_h, ctx.T);
                stage_time_s = min(stage_time_s, ...
                    ctx.config.frontier_pattern_pool_max_time_s);
                upper_options = optimoptions(ctx.pattern_pool_options, ...
                    'MaxFeasiblePoints', Inf, ...
                    'AbsoluteGapTolerance', ...
                    ctx.config.frontier_certification_tolerance_usd_t * ...
                    ctx.config.nh3_target_t / 4);
                target_upper = Inf;
                outcome = solve_cost_cap_domain(cost_solver, K, ...
                    certification_start, ctx, target_upper, allowed_z, ...
                    stage_time_s, upper_options);
                cost_cap_backend = "intlinprog_seeded_pool_cost_minimum";
                stage_phase = "pool_optimization";
                stage_label = "候选池原成本精修";
                raise_global_lower = false;
            elseif use_warm_cap
                % 已有全局下界L时，以L为基准最小化成本超额，避免在
                % 高成本帽以下出现大块平坦目标区；最终目标仍是原成本。
                target_upper = cached.objective_lower;
                relax_ael_counts = bisection_attempts >= 3;
                outcome = solve_warm_cost_cap(cost_solver, K, ...
                    certification_start, ctx, target_upper, stage_time_s, ...
                    relax_ael_counts);
                cost_cap_backend = "intlinprog_warm_cost_cap_excess";
            else
                outcome = solve_cost_cap_domain(cost_solver, K, ...
                    certification_start, ctx, target_upper, ...
                    true(ctx.T, 1), stage_time_s, ...
                    ctx.global_bisection_options);
                cost_cap_backend = "intlinprog_global_cost_cap";
            end
            total_attempts = record_field(cached, ...
                'frontier_attempts', 0) + 1;
            point = merge_cost_cap_outcome(cached, outcome, ctx, K, ...
                total_attempts, stage_phase, ...
                cost_cap_backend, target_upper, raise_global_lower);
            if use_pool_cost
                point.pool_cost_optimization_attempts = pool_cost_attempts + 1;
            end
            cap_history = record_field(cached, ...
                'global_bisection_caps_usd', zeros(0, 1));
            status_history = string(record_field(cached, ...
                'global_bisection_status', strings(0, 1)));
            elapsed_history = record_field(cached, ...
                'global_bisection_elapsed_s', zeros(0, 1));
            cap_history(end + 1, 1) = target_upper;
            status_history(end + 1, 1) = outcome.status;
            elapsed_history(end + 1, 1) = outcome.elapsed_s;
            bisection_attempts = bisection_attempts + 1;
            point.global_bisection_attempts = bisection_attempts;
            point.global_bisection_caps_usd = cap_history;
            point.global_bisection_status = status_history;
            point.global_bisection_elapsed_s = elapsed_history;
            entry = struct('mode', cache_mode, 'cost_cap', Inf, ...
                'K', K, 'record', point, ...
                'source', "frontier_" + stage_phase);
            ctx.services.fixed_point_store(ctx.point_cache_file, ...
                ctx.cost_signature, "append", cache_mode, Inf, entry);
            cost_entries(cached_index) = entry;
            cached = point;
            certification_new_points = certification_new_points + 1;
            fprintf(['[O1] 关键点K=%g%s，成本基准=%g USD：', ...
                '[%g, %g] USD，不确定性=%.6g USD/t，%s，%.1f s。\n'], ...
                K, stage_label, target_upper, point.objective_lower, ...
                point.objective_upper, ...
                record_uncertainty_usd_t(point, ctx), ...
                outcome.status, outcome.elapsed_s);
            if raise_global_lower && isfinite(outcome.raw_best_bound_usd)
                fprintf('[O1] 本轮全局求解器有效下界=%g USD。\n', ...
                    outcome.raw_best_bound_usd);
            end
            if point.is_certified
                break
            end
        end
        if cached.is_certified
            continue
        end
        if bisection_attempts >= ...
                ctx.config.frontier_global_bisection_max_attempts
            fprintf('[O1] 关键点K=%g多策略阶段已用完，转入剩余原模型认证。\n', K);
            if certification_attempts >= ...
                    ctx.config.frontier_certification_max_attempts && ...
                    ~needs_scaled_certification && ~needs_floor_certification && ...
                    ~needs_startup_certification && ~needs_gurobi_certification
                % 单个关键点的全部预算耗尽不能永久阻塞其他关键点。
                continue
            end
        else
            break
        end
    end

    if certification_attempts >= ...
            ctx.config.frontier_certification_max_attempts && ...
            ~needs_scaled_certification && ~needs_floor_certification && ...
            ~needs_startup_certification && ~needs_gurobi_certification
        continue
    end
    if use_gurobi && ~needs_gurobi_certification
        continue
    end
    if certification_new_points >= ...
            ctx.config.frontier_certification_points_per_run || ...
            toc(certification_started) >= ...
            ctx.config.frontier_certification_run_budget_s
        certification_budget_exhausted = true;
        break
    end
    total_attempts = record_field(cached, 'frontier_attempts', 0) + 1;
    remaining_budget_s = ctx.config.frontier_certification_run_budget_s - ...
        toc(certification_started);
    if remaining_budget_s <= 61
        certification_budget_exhausted = true;
        break
    end
    stage_ctx = ctx;
    stage_ctx.certification_options = optimoptions(ctx.certification_options, ...
        'MaxTime', min(ctx.config.frontier_certification_max_time_s, ...
        remaining_budget_s - 60));
    point = solve_cost_frontier_point(cost_solver, K, ...
        certification_start, stage_ctx, reference, total_attempts, ...
        "certification", cached);
    certification_new_points = certification_new_points + 1;
    entry = struct('mode', cache_mode, 'cost_cap', Inf, 'K', K, ...
        'record', point, 'source', "frontier_certification");
    ctx.services.fixed_point_store(ctx.point_cache_file, ...
        ctx.cost_signature, "append", cache_mode, Inf, entry);
    if isempty(cached_index)
        cost_entries(end + 1) = entry; %#ok<AGROW>
    else
        cost_entries(cached_index) = entry;
    end
    fprintf(['[O1] 关键点K=%g认证：[%g, %g] USD，', ...
        '不确定性=%.6g USD/t，目标<=%.6g USD/t，%.1f s。\n'], ...
        K, point.objective_lower, point.objective_upper, ...
        record_uncertainty_usd_t(point, ctx), ...
        ctx.config.frontier_certification_tolerance_usd_t, ...
        point.elapsed_s);
end

structure = analyze_frontier_structure(cost_entries, reference, ...
    upper, reference_count, ctx);
% 认证阶段可能改进上界；代表解必须与最新缓存一致，不能保留锚点旧解。
representative_index = find([cost_entries.K] == upper, 1);
if ~isempty(representative_index) && ...
        cost_entries(representative_index).record.has_incumbent
    representative = cost_entries(representative_index).record;
    if ~isfield(representative, 'solution') || ...
            isempty(fieldnames(representative.solution))
        representative.solution = best_feasible_seed( ...
            upper, cost_entries, initial, ctx);
    end
end
for row = 1:height(frontier)
    K = frontier.K(row);
    if K < feasibility.K_lower
        continue
    end
    direct_index = find([cost_entries.K] == K, 1);
    if ~isempty(direct_index)
        assign_row(row, cost_entries(direct_index).record);
    elseif K >= reference_count
        point = reference;
        point.frontier_phase = "reference";
        point.is_certified = record_uncertainty_usd_t(point, ctx) <= ...
            ctx.config.frontier_certification_tolerance_usd_t;
        assign_row(row, point);
    else
        envelope = monotonic_anchor_envelope( ...
            K, cost_entries, reference, ctx);
        if isfinite(envelope.objective_lower) || ...
                isfinite(envelope.objective_upper)
            assign_row(row, envelope);
        end
    end
end
frontier = apply_monotonic_closure(frontier);
certification = build_certification_table(critical_K, frontier, ctx);
if isempty(certification) || all(certification.is_certified)
    next_pending_K = NaN;
else
    next_pending_K = certification.K( ...
        find(~certification.is_certified, 1));
end
direct_points = sum(ismember(frontier.phase, ...
    ["anchor", "legacy_anchor", "certification", "polish", ...
    "pattern_pool", "pool_optimization", "local_cost", "relocation_cost", ...
    "global_bisection", "reference"]));
frontier_state = struct('elapsed_s', toc(frontier_started), ...
    'new_points', new_point_count, ...
    'points_per_run', ctx.config.frontier_points_per_run, ...
    'run_budget_s', ctx.config.frontier_run_budget_s, ...
    'budget_exhausted', budget_exhausted, ...
    'completed_points', direct_points, ...
    'pending_points', max(0, height(frontier) - direct_points), ...
    'next_pending_K', next_pending_K, ...
    'total_points', height(frontier), ...
    'anchor_K', solve_K, 'critical_K', critical_K, ...
    'certification_new_points', certification_new_points, ...
    'certification_budget_exhausted', ...
    certification_budget_exhausted, ...
    'certification_complete', isempty(certification) || ...
    all(certification.is_certified), ...
    'certification_target_usd_t', ...
    ctx.config.frontier_certification_tolerance_usd_t);

    function point = make_non_solved_point(K, lower_cost, upper_cost, ...
            status, backend)
        point = struct('objective_kind', "cost", ...
            'has_incumbent', isfinite(upper_cost), ...
            'objective_lower', lower_cost, 'objective_upper', upper_cost, ...
            'system_cost_lower', lower_cost, ...
            'system_cost_upper', upper_cost, 'absolute_gap', NaN, ...
            'relative_gap', NaN, 'count_lower', NaN, ...
            'count_upper', NaN, 'is_proven', false, ...
            'is_infeasible', status == "infeasible_certified", ...
            'exitflag', NaN, 'status', string(status), 'message', "", ...
            'output', struct(), 'solution', struct(), ...
            'solve_backend', string(backend), 'K_limit', K, ...
            'elapsed_s', 0, 'frontier_attempts', 0);
    end

    function assign_row(row, point)
        lower_cost = point.objective_lower;
        upper_cost = point.objective_upper;
        frontier.cost_lower_usd(row) = lower_cost;
        frontier.cost_upper_usd(row) = upper_cost;
        frontier.lcoa_lower_usd_t(row) = ...
            lower_cost / ctx.config.nh3_target_t;
        frontier.lcoa_upper_usd_t(row) = ...
            upper_cost / ctx.config.nh3_target_t;
        frontier.premium_lower_usd_t(row) = ...
            (lower_cost - reference.objective_upper) ...
            / ctx.config.nh3_target_t;
        frontier.premium_upper_usd_t(row) = ...
            (upper_cost - reference.objective_lower) ...
            / ctx.config.nh3_target_t;
        if isfield(point, 'count_upper')
            frontier.actual_updates(row) = point.count_upper;
        end
        frontier.has_incumbent(row) = point.has_incumbent;
        frontier.is_proven(row) = point.is_proven;
        if isfield(point, 'is_certified')
            frontier.is_certified(row) = point.is_certified;
        else
            frontier.is_certified(row) = ...
                record_uncertainty_usd_t(point, ctx) <= ...
                ctx.config.frontier_certification_tolerance_usd_t;
        end
        frontier.status(row) = string(point.status);
        if isfield(point, 'frontier_phase')
            frontier.phase(row) = string(point.frontier_phase);
        end
        frontier.solve_backend(row) = string(record_field( ...
            point, 'solve_backend', "legacy_cache"));
        frontier.uncertainty_usd_t(row) = ...
            record_uncertainty_usd_t(point, ctx);
        frontier.elapsed_s(row) = record_field(point, 'elapsed_s', 0);
        if isfield(point, 'frontier_attempts')
            frontier.attempts(row) = point.frontier_attempts;
        end
        if isfield(point, 'cost_components')
            components = point.cost_components;
        elseif isfield(point, 'solution') && ...
                ~isempty(fieldnames(point.solution))
            components = ctx.services.evaluate_cost_components(point.solution, ctx);
        else
            components = struct();
        end
        for component_index = 1:numel(component_names)
            name = component_names{component_index};
            if isfield(components, name)
                frontier.(name)(row) = components.(name);
            end
        end
        if isfield(point, 'operation_metrics')
            metrics = point.operation_metrics;
        elseif isfield(point, 'solution') && ...
                ~isempty(fieldnames(point.solution))
            metrics = ctx.services.evaluate_operation_metrics(point.solution, ctx);
        else
            metrics = struct();
        end
        for metric_index = 1:numel(metric_names)
            name = metric_names{metric_index};
            if isfield(metrics, name)
                frontier.(name)(row) = metrics.(name);
            end
        end
    end

    function closed = apply_monotonic_closure(open_frontier)
        % 真实最优成本随K增大非增；用已有有效界修正展示而不虚构直接解。
        closed = open_frontier;
        row_count = height(closed);
        upper_changed = false(row_count, 1);
        upper_fields = [{'actual_updates'}, component_names(:).', ...
            metric_names(:).'];
        for current_row = 2:row_count
            previous_row = current_row - 1;
            if isfinite(closed.cost_upper_usd(previous_row)) && ...
                    (~isfinite(closed.cost_upper_usd(current_row)) || ...
                    closed.cost_upper_usd(previous_row) < ...
                    closed.cost_upper_usd(current_row))
                closed.cost_upper_usd(current_row) = ...
                    closed.cost_upper_usd(previous_row);
                closed.has_incumbent(current_row) = ...
                    closed.has_incumbent(previous_row);
                for field_index = 1:numel(upper_fields)
                    name = upper_fields{field_index};
                    closed.(name)(current_row) = ...
                        closed.(name)(previous_row);
                end
                upper_changed(current_row) = true;
            end
        end
        for current_row = row_count - 1:-1:1
            next_row = current_row + 1;
            if isfinite(closed.cost_lower_usd(next_row)) && ...
                    (~isfinite(closed.cost_lower_usd(current_row)) || ...
                    closed.cost_lower_usd(next_row) > ...
                    closed.cost_lower_usd(current_row))
                closed.cost_lower_usd(current_row) = ...
                    closed.cost_lower_usd(next_row);
            end
        end
        for current_row = 1:row_count
            lower_cost = closed.cost_lower_usd(current_row);
            upper_cost = closed.cost_upper_usd(current_row);
            closed.lcoa_lower_usd_t(current_row) = ...
                lower_cost / ctx.config.nh3_target_t;
            closed.lcoa_upper_usd_t(current_row) = ...
                upper_cost / ctx.config.nh3_target_t;
            closed.premium_lower_usd_t(current_row) = ...
                (lower_cost - reference.objective_upper) / ...
                ctx.config.nh3_target_t;
            closed.premium_upper_usd_t(current_row) = ...
                (upper_cost - reference.objective_lower) / ...
                ctx.config.nh3_target_t;
            if isfinite(lower_cost) && isfinite(upper_cost)
                closed.uncertainty_usd_t(current_row) = ...
                    max(0, upper_cost - lower_cost) / ...
                    ctx.config.nh3_target_t;
                closed.is_proven(current_row) = ...
                    upper_cost - lower_cost <= ...
                    max(1e-7, eps(abs(upper_cost)));
                closed.is_certified(current_row) = ...
                    closed.has_incumbent(current_row) && ...
                    closed.uncertainty_usd_t(current_row) <= ...
                    ctx.config.frontier_certification_tolerance_usd_t;
            end
            if upper_changed(current_row)
                closed.status(current_row) = "monotonic_envelope";
                closed.solve_backend(current_row) = ...
                    "monotonic_frontier_closure";
            end
        end
    end
end

function anchor_K = select_frontier_anchors( ...
        first_K, last_K, anchor_count, requested_K, key_K)
%SELECT_FRONTIER_ANCHORS 生成低K加密且覆盖全区间的稀疏锚点。
if last_K < first_K
    anchor_K = zeros(0, 1);
    return
end
span = last_K - first_K;
if span == 0
    generated = first_K;
else
    near_count = max(2, ceil(anchor_count / 2));
    uniform_count = max(2, floor(anchor_count / 2));
    offsets = unique([0; round(logspace(0, log10(span), near_count)).']);
    near = first_K + offsets;
    uniform = round(linspace(first_K, last_K, uniform_count)).';
    generated = unique([first_K; last_K; near(:); uniform(:)]);
end
generated = generated(generated >= first_K & generated <= last_K);
if numel(generated) > anchor_count
    keep = unique(round(linspace(1, numel(generated), anchor_count)));
    generated = generated(keep);
end
explicit = unique([requested_K(:); key_K(:)]);
explicit = explicit(explicit >= first_K & explicit <= last_K);
anchor_K = unique([generated(:); explicit(:)]);
end

function structure = analyze_frontier_structure( ...
        entries, reference, first_K, reference_K, ctx)
%ANALYZE_FRONTIER_STRUCTURE 根据锚点识别平台段、陡降段和候选关键K。
K = zeros(0, 1);
lower = zeros(0, 1);
upper = zeros(0, 1);
phase = strings(0, 1);
for entry_index = 1:numel(entries)
    record = entries(entry_index).record;
    if entries(entry_index).K < first_K || ...
            entries(entry_index).K >= reference_K || ...
            ~isfield(record, 'objective_lower') || ...
            ~isfield(record, 'objective_upper') || ...
            ~isfinite(record.objective_lower) || ...
            ~isfinite(record.objective_upper)
        continue
    end
    K(end + 1, 1) = entries(entry_index).K; %#ok<AGROW>
    lower(end + 1, 1) = record.objective_lower; %#ok<AGROW>
    upper(end + 1, 1) = record.objective_upper; %#ok<AGROW>
    phase(end + 1, 1) = string(record_field( ...
        record, 'frontier_phase', "anchor")); %#ok<AGROW>
end
if reference.has_incumbent && isfinite(reference.objective_lower)
    K(end + 1, 1) = reference_K;
    lower(end + 1, 1) = reference.objective_lower;
    upper(end + 1, 1) = reference.objective_upper;
    phase(end + 1, 1) = "reference";
end
[K, order] = sort(K);
lower = lower(order);
upper = upper(order);
phase = phase(order);
[K, unique_index] = unique(K, 'stable');
lower = lower(unique_index);
upper = upper(unique_index);
phase = phase(unique_index);
uncertainty = max(0, upper - lower) / ctx.config.nh3_target_t;
anchors = table(K, lower, upper, uncertainty, phase, ...
    'VariableNames', {'K', 'cost_lower_usd', 'cost_upper_usd', ...
    'uncertainty_usd_t', 'phase'});
if numel(K) < 2
    segments = table('Size', [0, 7], ...
        'VariableTypes', repmat({'double'}, 1, 7), ...
        'VariableNames', {'K_left', 'K_right', 'cost_mid_left_usd', ...
        'cost_mid_right_usd', 'drop_usd_t', ...
        'slope_usd_t_per_update', 'max_uncertainty_usd_t'});
    recommended_K = zeros(0, 1);
else
    midpoint = (lower + upper) / 2;
    K_left = K(1:end-1);
    K_right = K(2:end);
    cost_mid_left_usd = midpoint(1:end-1);
    cost_mid_right_usd = midpoint(2:end);
    drop_usd_t = max(0, cost_mid_left_usd - cost_mid_right_usd) ...
        / ctx.config.nh3_target_t;
    slope_usd_t_per_update = drop_usd_t ./ max(1, K_right - K_left);
    max_uncertainty_usd_t = max( ...
        uncertainty(1:end-1), uncertainty(2:end));
    segments = table(K_left, K_right, cost_mid_left_usd, ...
        cost_mid_right_usd, drop_usd_t, slope_usd_t_per_update, ...
        max_uncertainty_usd_t);
    score = slope_usd_t_per_update .* log1p(K_right - K_left);
    [~, score_order] = sort(score, 'descend');
    take = min(ctx.config.frontier_auto_key_count, numel(score_order));
    recommended_K = zeros(take, 1);
    for index = 1:take
        segment_index = score_order(index);
        recommended_K(index) = round((K_left(segment_index) + ...
            K_right(segment_index)) / 2);
    end
    recommended_K = unique(recommended_K, 'stable');
end
structure = struct('anchors', anchors, 'segments', segments, ...
    'recommended_K', recommended_K);
end

function record = strengthen_anchor_bound(record, K, entries, reference, ctx)
%STRENGTHEN_ANCHOR_BOUND 统一更新有效区间及认证字段，避免旧记录与展示脱节。
envelope = monotonic_anchor_envelope(K, entries, reference, ctx);
record.objective_lower = max(record.objective_lower, envelope.objective_lower);
record.system_cost_lower = record.objective_lower;
record.absolute_gap = record.objective_upper - record.objective_lower;
record.relative_gap = record.absolute_gap / max(1, abs(record.objective_upper));
record.is_proven = isfinite(record.absolute_gap) && record.absolute_gap <= ...
    max(1e-7, eps(abs(record.objective_upper)));
record.is_certified = record.has_incumbent && ...
    record_uncertainty_usd_t(record, ctx) <= ...
    ctx.config.frontier_certification_tolerance_usd_t;
end

function point = monotonic_anchor_envelope(K, entries, reference, ctx)
%MONOTONIC_ANCHOR_ENVELOPE 利用C*(K)单调不增性质传播严格成本界。
lower_bound = -Inf;
upper_bound = Inf;
upper_count = NaN;
for entry_index = 1:numel(entries)
    entry_K = entries(entry_index).K;
    record = entries(entry_index).record;
    if entry_K >= K && isfield(record, 'objective_lower') && ...
            isfinite(record.objective_lower)
        lower_bound = max(lower_bound, record.objective_lower);
    end
    if entry_K <= K && isfield(record, 'has_incumbent') && ...
            record.has_incumbent && isfield(record, 'objective_upper') && ...
            isfinite(record.objective_upper) && ...
            record.objective_upper < upper_bound
        upper_bound = record.objective_upper;
        upper_count = record_field(record, 'count_upper', entry_K);
    end
end
if isfinite(reference.objective_lower)
    lower_bound = max(lower_bound, reference.objective_lower);
end
if isfinite(lower_bound) && isfinite(upper_bound) && ...
        lower_bound > upper_bound
    lower_bound = upper_bound;
end
point = struct('objective_kind', "cost", ...
    'has_incumbent', isfinite(upper_bound), ...
    'objective_lower', lower_bound, 'objective_upper', upper_bound, ...
    'system_cost_lower', lower_bound, 'system_cost_upper', upper_bound, ...
    'absolute_gap', upper_bound - lower_bound, 'relative_gap', NaN, ...
    'count_lower', NaN, 'count_upper', upper_count, ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', "anchor_envelope", 'message', "", 'output', struct(), ...
    'solution', struct(), 'solve_backend', "monotonic_anchor_bounds", ...
    'K_limit', K, 'elapsed_s', 0, 'frontier_attempts', 0, ...
    'frontier_phase', "envelope", 'is_certified', false);
if isfinite(upper_bound)
    point.relative_gap = point.absolute_gap / max(1, abs(upper_bound));
    point.is_certified = record_uncertainty_usd_t(point, ctx) <= ...
        ctx.config.frontier_certification_tolerance_usd_t;
end
end

function start = best_feasible_seed(K, entries, fallback, ctx)
%BEST_FEASIBLE_SEED 为关键K选择成本最低的已缓存可行热启动。
start = fallback;
best_cost = evaluate(ctx.system_cost_usd, fallback);
fallback_count = round(sum(fallback.O1_HB_change));
if fallback_count > K
    best_cost = Inf;
end
for entry_index = 1:numel(entries)
    record = entries(entry_index).record;
    if ~isfield(record, 'solution') || ~isstruct(record.solution) || ...
            isempty(fieldnames(record.solution))
        continue
    end
    count = round(sum(record.solution.O1_HB_change));
    if count > K
        continue
    end
    cost = evaluate(ctx.system_cost_usd, record.solution);
    if isfinite(cost) && cost < best_cost
        start = record.solution;
        best_cost = cost;
    end
end
if ~isfinite(best_cost)
    error('O1:no_certification_seed', ...
        '关键K=%g没有可用于认证的可行热启动。', K);
end
end

function certification = build_certification_table(K_values, frontier, ctx)
%BUILD_CERTIFICATION_TABLE 汇总关键K的高精度认证状态。
variable_names = {'K', 'cost_lower_usd', 'cost_upper_usd', ...
    'uncertainty_usd_t', 'target_usd_t', 'is_certified', ...
    'status', 'attempts'};
variable_types = {'double', 'double', 'double', 'double', 'double', ...
    'logical', 'string', 'double'};
certification = table('Size', [numel(K_values), numel(variable_names)], ...
    'VariableTypes', variable_types, 'VariableNames', variable_names);
certification.K = K_values(:);
certification.target_usd_t(:) = ...
    ctx.config.frontier_certification_tolerance_usd_t;
for index = 1:numel(K_values)
    row = find(frontier.K == K_values(index), 1);
    if isempty(row)
        certification.cost_lower_usd(index) = NaN;
        certification.cost_upper_usd(index) = NaN;
        certification.uncertainty_usd_t(index) = Inf;
        certification.is_certified(index) = false;
        certification.status(index) = "outside_frontier";
        certification.attempts(index) = 0;
    else
        certification.cost_lower_usd(index) = frontier.cost_lower_usd(row);
        certification.cost_upper_usd(index) = frontier.cost_upper_usd(row);
        certification.uncertainty_usd_t(index) = ...
            frontier.uncertainty_usd_t(row);
        certification.is_certified(index) = frontier.is_certified(row);
        certification.status(index) = frontier.status(row);
        certification.attempts(index) = frontier.attempts(row);
    end
end
end

function uncertainty = record_uncertainty_usd_t(record, ctx)
%RECORD_UNCERTAINTY_USD_T 将成本上下界宽度换算为单位氨成本不确定性。
uncertainty = Inf;
if ~isstruct(record) || isempty(fieldnames(record)) || ...
        ~isfield(record, 'objective_lower') || ...
        ~isfield(record, 'objective_upper') || ...
        ~isfinite(record.objective_lower) || ...
        ~isfinite(record.objective_upper)
    return
end
uncertainty = max(0, ...
    record.objective_upper - record.objective_lower) ...
    / ctx.config.nh3_target_t;
end

function [base_hours, pattern_count] = collect_cached_pattern_pool( ...
        K, entries, fallback, T)
%COLLECT_CACHED_PATTERN_POOL 汇总不超过K的独立HB变动模式。
patterns = false(T, 0);
append_solution(fallback);
for entry_index = 1:numel(entries)
    record = entries(entry_index).record;
    if ~isfield(record, 'solution')
        continue
    end
    append_solution(record.solution);
end
pattern_count = size(patterns, 2);
base_hours = find(any(patterns, 2));

    function append_solution(solution)
        if ~isstruct(solution) || ...
                ~isfield(solution, 'O1_HB_change') || ...
                numel(solution.O1_HB_change) ~= T
            return
        end
        pattern = round(solution.O1_HB_change(:)) > 0.5;
        if sum(pattern) > K
            return
        end
        if ~isempty(patterns) && any(all(patterns == pattern, 1))
            return
        end
        patterns(:, end + 1) = pattern; %#ok<AGROW>
    end
end

function allowed = expand_cyclic_hours(base_hours, radius_h, T)
%EXPAND_CYCLIC_HOURS 按全年循环时间轴扩展候选变动时刻。
allowed = false(T, 1);
for offset = -radius_h:radius_h
    hours = mod(base_hours(:) - 1 + offset, T) + 1;
    allowed(hours) = true;
end
end

function cap = select_untried_cost_cap(record)
%SELECT_UNTRIED_COST_CAP 在当前区间最大的未检验子区间取中点。
lower = record.objective_lower;
upper = record.objective_upper;
attempted = record_field(record, ...
    'global_bisection_caps_usd', zeros(0, 1));
tolerance = max(1e-4, 1e-10 * max(abs([lower, upper])));
attempted = attempted(attempted > lower + tolerance & ...
    attempted < upper - tolerance);
knots = unique([lower; attempted(:); upper]);
gaps = diff(knots);
largest_gap = max(gaps);
% 等长时优先上半区，提高先找到可行上界的概率。
interval = find(gaps >= largest_gap - tolerance, 1, 'last');
cap = (knots(interval) + knots(interval + 1)) / 2;
end

function value = record_field(record, name, default_value)
%RECORD_FIELD 读取兼容新旧缓存的可选字段。
value = default_value;
if isstruct(record) && ~isempty(fieldnames(record)) && ...
        isfield(record, name) && ~isempty(record.(name))
    value = record.(name);
end
end

function outcome = solve_cost_cap_domain( ...
        solver_data, K, start, ctx, target_upper, allowed_z, ...
        max_time_s, base_options)
%SOLVE_COST_CAP_DOMAIN 在指定HB候选时刻内搜索满足成本帽的可行解。
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.options = optimoptions(base_options, 'MaxTime', max_time_s);
indices = solver_data.indices;
seed_vector = solution_to_vector(indices, start, numel(problem.lb));
if isempty(seed_vector)
    error('O1:no_cost_cap_seed', ...
        '关键K=%g没有完整的成本帽搜索初值。', K);
end
seed_upper = evaluate(ctx.system_cost_usd, start);
objective_offset = seed_upper - problem.f(:).' * seed_vector(:);

z_indices = indices.O1_HB_change(:);
allowed_z = logical(allowed_z(:));
if numel(allowed_z) ~= numel(z_indices)
    error('O1:bad_cost_cap_domain', ...
        'HB候选时刻向量长度与模型不一致。');
end
fixed_zero = z_indices(~allowed_z);
problem.lb(fixed_zero) = 0;
problem.ub(fixed_zero) = 0;
problem.intcon = setdiff(problem.intcon(:), fixed_zero);

target_solver_upper = target_upper - objective_offset;
if isfinite(target_upper)
    problem.Aineq(end + 1, :) = sparse(problem.f(:).');
    problem.bineq(end + 1, 1) = target_solver_upper + ...
        max(1e-6, 1e-10 * abs(target_solver_upper));
    problem.x0 = [];
else
    % 不设硬帽时直接最小化原成本，并保留位于候选池内的原可行初值。
    problem.x0 = seed_vector;
end

relaxed_grid = zeros(0, 1);
relaxed_ael = zeros(0, 1);
if isfield(indices, 'u_purchase') && ...
        isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    relaxed_grid = indices.u_purchase(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_grid);
end
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    relaxed_ael = indices.I_AEL_up(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_ael);
end

outcome = struct('has_candidate', false, 'solution', struct(), ...
    'candidate_cost', Inf, 'candidate_count', NaN, ...
    'exitflag', NaN, 'elapsed_s', NaN, 'status', "求解异常", ...
    'message', "", 'is_infeasible', false, ...
    'candidate_hours', sum(allowed_z), 'raw_best_bound_usd', -Inf);
started = tic;
candidate_x = [];
search_fval = NaN;
recovery_failed = false;
try
    if all(allowed_z)
        stop_bound = target_solver_upper;
    else
        stop_bound = Inf;
    end
    bound_label = "全局有效下界";
    if ~all(allowed_z) || record_field(solver_data, 'restricted_cost_domain', false)
        bound_label = "局部条件下界（不用于全局认证）";
    end
    [candidate_x, search_fval, exitflag, output] = run_cost_milp( ...
        problem, K, objective_offset, stop_bound, bound_label);
    if ~isempty(candidate_x) && ...
            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
        recovery_time_s = min(60, max(1, max_time_s));
        [candidate_x, recovery_flag, recovery_output] = ...
            ctx.services.recover_direction_binaries( ...
            problem, candidate_x, indices, recovery_time_s);
        if recovery_flag <= 0 || isempty(candidate_x)
            candidate_x = [];
            recovery_failed = true;
            output.recovery = recovery_output;
            output.message = ...
                "方向变量恢复失败，未接收本轮候选上界。";
        end
    end
catch exception
    exitflag = NaN;
    output = struct('message', exception.message);
end
outcome.elapsed_s = toc(started);
outcome.exitflag = exitflag;
if isfield(output, 'message')
    outcome.message = string(output.message);
end
if isfield(output, 'trace_dualbound') && ...
        isscalar(output.trace_dualbound) && isfinite(output.trace_dualbound)
    outcome.raw_best_bound_usd = output.trace_dualbound + objective_offset;
elseif isfield(output, 'bestbound') && ...
        isscalar(output.bestbound) && isfinite(output.bestbound)
    outcome.raw_best_bound_usd = output.bestbound + objective_offset;
elseif isscalar(search_fval) && isfinite(search_fval) && ...
        isfield(output, 'absolutegap') && ...
        isscalar(output.absolutegap) && isfinite(output.absolutegap)
    outcome.raw_best_bound_usd = search_fval + objective_offset ...
        - max(0, output.absolutegap);
end

if ~isempty(candidate_x)
    solution = vector_to_solution(candidate_x, indices);
    solution = ctx.services.add_change_indicators(solution, ctx);
    candidate_count = round(sum(solution.O1_HB_change));
    candidate_cost = evaluate(ctx.system_cost_usd, solution);
    acceptance_tolerance = max(1e-4, 1e-9 * abs(target_upper));
    if candidate_count <= K && isfinite(candidate_cost) && ...
            candidate_cost <= target_upper + acceptance_tolerance
        outcome.has_candidate = true;
        outcome.solution = solution;
        outcome.candidate_cost = candidate_cost;
        outcome.candidate_count = candidate_count;
        if isfinite(target_upper)
            outcome.status = "已找到达标上界";
        else
            outcome.status = "已取得可验证原成本上界";
        end
    else
        outcome.status = "候选点未通过原模型复核";
    end
elseif exitflag == -2 && ~recovery_failed
    outcome.status = "成本帽不可行";
    outcome.is_infeasible = true;
elseif exitflag == 0
    outcome.status = "达到时限但未找到可行点";
elseif exitflag == -1 && isfinite(outcome.raw_best_bound_usd)
    outcome.status = "回调保留有效下界";
elseif recovery_failed
    outcome.status = "方向变量恢复失败";
end
end

function outcome = solve_warm_cost_cap( ...
        solver_data, K, start, ctx, certified_lower, max_time_s, ...
        relax_ael_counts)
%SOLVE_WARM_COST_CAP 用超额变量保留原可行热启动，不松弛任何物理约束。
% 基准必须是已有的有效全局下界L，不能传入任意未经证明的成本帽。
% 内部最小化s，满足原约束及L<=C(x)<=L+s、s>=0。
% 正对偶界s_L给出更强下界L+s_L；零对偶界只保留已有下界L。
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = solver_data.update_coefficient * K;
indices = solver_data.indices;
seed = solution_to_vector(indices, start, numel(problem.lb));
seed_cost = evaluate(ctx.system_cost_usd, start);
if isempty(seed) || ~isfinite(seed_cost) || ...
        round(sum(start.O1_HB_change)) > K
    error('O1:bad_warm_cap_seed', 'K=%g缺少原模型可行热启动。', K);
end
offset = seed_cost - problem.f(:).' * seed(:);
if isfield(indices, 'u_purchase') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    problem.intcon = setdiff(problem.intcon(:), indices.u_purchase(:));
end
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    problem.intcon = setdiff(problem.intcon(:), indices.I_AEL_up(:));
end
% 恢复阶段在未添加辅助变量的原矩阵上最小化原成本。
recovery_problem = problem;
if relax_ael_counts && isfield(indices, 'n_ael')
    % 此处是原整数模型的外松弛，下界有效；分数台数不能作为原模型上界。
    problem.intcon = setdiff(problem.intcon(:), indices.n_ael(:));
    fprintf('[O1] K=%g采用AEL在线台数外松弛认证：HB更新仍保留整数。\n', K);
end
n = numel(problem.f);
problem.Aineq(:, n + 1) = 0;
problem.Aeq(:, n + 1) = 0;
% 已有全局证书给出的冗余成本底线保留原整数可行域。
problem.Aineq(end + 1, :) = [-sparse(problem.f(:).'), 0];
problem.bineq(end + 1, 1) = -(certified_lower - offset) + 1e-5;
problem.Aineq(end + 1, :) = [sparse(problem.f(:).'), -1];
problem.bineq(end + 1, 1) = certified_lower - offset;
problem.lb = [problem.lb(:); 0];
problem.ub = [problem.ub(:); Inf];
problem.f = [zeros(n, 1); 1];
problem.x0 = [seed(:); max(0, seed_cost - certified_lower) + 1e-5];
problem.options = optimoptions(ctx.global_bisection_options, ...
    'MaxTime', max_time_s, 'MaxFeasiblePoints', Inf, ...
    'AbsoluteGapTolerance', ...
    ctx.config.frontier_certification_tolerance_usd_t * ctx.config.nh3_target_t);
% 辅助目标的尺度不同，不能继承原成本的求解器截断值。
problem.options = optimoptions(problem.options, 'ObjectiveCutOff', Inf);
outcome = struct('has_candidate', false, 'solution', struct(), ...
    'candidate_cost', Inf, 'candidate_count', NaN, ...
    'exitflag', NaN, 'elapsed_s', NaN, 'status', "热启动求解异常", ...
    'message', "", 'is_infeasible', false, 'candidate_hours', ctx.T, ...
    'raw_best_bound_usd', -Inf, 'uncapped_global_bound', true, ...
    'relaxed_ael_counts', relax_ael_counts);
started = tic;
try
    stop_bound = seed_cost - certified_lower - ...
        ctx.config.frontier_certification_tolerance_usd_t * ctx.config.nh3_target_t;
    if relax_ael_counts
        problem.options = optimoptions(problem.options, ...
            'AbsoluteGapTolerance', ...
            ctx.config.frontier_certification_tolerance_usd_t * ...
            ctx.config.nh3_target_t / 4);
    end
    [candidate, ~, flag, output] = run_cost_milp( ...
        problem, K, 0, stop_bound, "成本帽超额下界");
    outcome.exitflag = flag;
    outcome.message = string(output.message);
    % 超额问题的正下界才可转换为原问题成本下界，零下界不作转换。
    if isfinite(output.trace_dualbound) && output.trace_dualbound >= -1e-4
        outcome.raw_best_bound_usd = certified_lower + max(0, output.trace_dualbound);
    end
    if ~isempty(candidate)
        projected = candidate(1:n);
        if relax_ael_counts
            % 原恢复矩阵保留n_ael整数位置，固定向上投影的台数后做严格LP。
            projected(indices.n_ael(:)) = min( ...
                recovery_problem.ub(indices.n_ael(:)), ...
                ceil(projected(indices.n_ael(:)) - 1e-7));
        end
        [restored, recovery_flag, recovery_output] = ...
            ctx.services.recover_direction_binaries( ...
            recovery_problem, projected, indices, min(60, max_time_s));
        if (recovery_flag <= 0 || isempty(restored)) && relax_ael_counts
            % 向上投影不可行时再尝试最近整数，不反复调整原模型参数。
            projected(indices.n_ael(:)) = round(candidate(indices.n_ael(:)));
            [restored, recovery_flag, recovery_output] = ...
                ctx.services.recover_direction_binaries( ...
                recovery_problem, projected, indices, min(30, max_time_s));
        end
        if recovery_flag > 0 && ~isempty(restored)
            solution = vector_to_solution(restored, indices);
            solution = ctx.services.add_change_indicators(solution, ctx);
            count = round(sum(solution.O1_HB_change));
            cost = evaluate(ctx.system_cost_usd, solution);
            original_integer_error = max(abs( ...
                restored(recovery_problem.intcon) - ...
                round(restored(recovery_problem.intcon))));
            if count <= K && isfinite(cost) && original_integer_error <= 1e-6
                outcome.has_candidate = true;
                outcome.solution = solution;
                outcome.candidate_count = count;
                outcome.candidate_cost = cost;
                if cost < seed_cost - 1e-4
                    outcome.status = "热启动得到更低原成本上界";
                else
                    outcome.status = "热启动保留原可行上界";
                end
            else
                outcome.status = "热启动候选未通过原模型复核";
            end
        else
            outcome.status = "热启动候选方向恢复失败";
            outcome.message = string(recovery_output.message);
        end
    elseif flag == 0
        outcome.status = "热启动限时无候选，保留已取得下界";
    end
catch exception
    outcome.message = string(exception.message);
end
outcome.elapsed_s = toc(started);
end

function local_solver = restrict_cost_window(solver_data, start, hours, T)
%RESTRICT_COST_WINDOW 只构造原问题的受限上界搜索，不用于全局下界。
local_solver = solver_data;
local_solver.restricted_cost_domain = true;
problem = solver_data.problem;
indices = solver_data.indices;
seed = solution_to_vector(indices, start, numel(problem.lb));
free = false(numel(seed), 1);
names = fieldnames(indices);
for i = 1:numel(names)
    positions = indices.(names{i});
    if numel(positions) == T
        free(positions(hours)) = true;
    elseif numel(positions) == T + 1 && strcmp(names{i}, 'storage_H2')
        % 两端储氢状态保留原值，内部状态自由，全年质量守恒不变。
        free(positions(hours(1) + 1:hours(end))) = true;
    elseif isscalar(positions)
        free(positions) = true;
    end
end
% 电网功率连续变量可全年重平衡，窗口外离散运行模式仍保持原值。
grid_names = {'p_purchase', 'p_sell', 'p_curt'};
for i = 1:numel(grid_names)
    if isfield(indices, grid_names{i})
        free(indices.(grid_names{i})(:)) = true;
    end
end
% 允许窗口入口发生平台更新，出口保留电解槽台数以衔接后续启停。
previous_hour = mod(hours(1) - 2, T) + 1;
free(indices.O1_HB_change(previous_hour)) = true;
if hours(end) < T
    free(indices.n_ael(hours(end))) = false;
end
fixed = find(~free);
problem.lb(fixed) = seed(fixed);
problem.ub(fixed) = seed(fixed);
problem.intcon = setdiff(problem.intcon(:), fixed);
local_solver.problem = problem;
end

function starts = rank_cost_windows(start, reference, ctx)
%RANK_COST_WINDOWS 优先搜索相对经济参考增加购电费用最多的时段。
starts = (1:ctx.config.frontier_local_cost_window_h:ctx.T).';
extra = ctx.model.context.C_purchase(:) .* ...
    (start.p_purchase(:) - reference.solution.p_purchase(:));
score = zeros(size(starts));
for i = 1:numel(starts)
    last = min(ctx.T, starts(i) + ctx.config.frontier_local_cost_window_h - 1);
    score(i) = sum(extra(starts(i):last));
end
[~, order] = sort(score, 'descend');
starts = starts(order);
end

function record = merge_cost_cap_outcome( ...
        prior, outcome, ctx, K, attempt, phase, backend, ...
        target_upper, raise_global_lower)
%MERGE_COST_CAP_OUTCOME 合并成本帽结果，并区分全局下界与受限搜索结论。
record = prior;
record.frontier_attempts = attempt;
record.frontier_phase = string(phase);
record.elapsed_s = outcome.elapsed_s;
record.last_cost_cap_usd = target_upper;
record.last_cost_cap_status = outcome.status;
record.last_cost_cap_exitflag = outcome.exitflag;
record.last_cost_cap_message = outcome.message;
record.last_cost_cap_candidate_hours = outcome.candidate_hours;
record.last_cost_cap_best_bound_usd = outcome.raw_best_bound_usd;
record.last_cost_cap_relaxed_ael_counts = record_field(outcome, ...
    'relaxed_ael_counts', false);
candidate_contradicts_bound = outcome.has_candidate && ...
    outcome.candidate_cost < record.objective_lower - ...
    max(1e-4, 1e-9 * abs(record.objective_lower));
if candidate_contradicts_bound
    fprintf('[O1] K=%g候选成本低于已有认证下界，拒绝形成认证并保留原记录。\n', K);
    record.last_cost_cap_bound_rejected = true;
end
if outcome.has_candidate && ~candidate_contradicts_bound && ...
        outcome.candidate_cost < record.objective_upper
    record.has_incumbent = true;
    record.solution = outcome.solution;
    record.objective_upper = outcome.candidate_cost;
    record.system_cost_upper = outcome.candidate_cost;
    record.count_upper = outcome.candidate_count;
    record.solve_backend = string(backend);
    record.cost_components = ...
        ctx.services.evaluate_cost_components(outcome.solution, ctx);
    record.operation_metrics = ...
        ctx.services.evaluate_operation_metrics(outcome.solution, ctx);
end
if raise_global_lower && isfinite(outcome.raw_best_bound_usd)
    if record_field(outcome, 'uncapped_global_bound', false)
        proposed_lower = outcome.raw_best_bound_usd;
    else
        proposed_lower = min(outcome.raw_best_bound_usd, target_upper);
    end
    bound_tolerance = max(1e-4, 1e-9 * abs(record.objective_upper));
    if proposed_lower <= record.objective_upper + bound_tolerance
        record.objective_lower = max(record.objective_lower, proposed_lower);
    else
        % 界值矛盾不能通过直接截成上界而伪造认证，保留旧的有效区间。
        fprintf('[O1] K=%g新下界超过已验证上界，拒绝合并：%.3f > %.3f USD。\n', ...
            K, proposed_lower, record.objective_upper);
        record.last_cost_cap_bound_rejected = true;
    end
end
if raise_global_lower && outcome.is_infeasible
    record.objective_lower = max(record.objective_lower, target_upper);
    record.system_cost_lower = record.objective_lower;
end
record.objective_lower = min(record.objective_lower, ...
    record.objective_upper);
record.system_cost_lower = record.objective_lower;
record.absolute_gap = record.objective_upper - record.objective_lower;
record.relative_gap = record.absolute_gap / ...
    max(1, abs(record.objective_upper));
record.is_proven = record.absolute_gap <= ...
    max(1e-7, eps(abs(record.objective_upper)));
record.is_certified = record.has_incumbent && ...
    record_uncertainty_usd_t(record, ctx) <= ...
    ctx.config.frontier_certification_tolerance_usd_t + 1e-12;
if record.is_proven
    record.status = "proven";
elseif record.is_certified
    record.status = "certified_tolerance";
elseif record.has_incumbent
    record.status = "incumbent_with_bound";
end
record.K_limit = K;
end

function record = polish_cost_upper_bound( ...
        solver_data, K, start, ctx, attempt, prior)
%POLISH_COST_UPPER_BOUND 固定HB变动时刻，寻找足以达到认证目标的新上界。
% 本步骤求解的是原问题的受限子集，因此只接收可行上界，不使用其下界。
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
problem.options = ctx.polish_options;
indices = solver_data.indices;
seed_vector = solution_to_vector(indices, start, numel(problem.lb));
if isempty(seed_vector)
    error('O1:no_polish_seed', ...
        '关键K=%g没有完整的定向上界精修初值。', K);
end
seed_count = round(sum(start.O1_HB_change));
seed_upper = evaluate(ctx.system_cost_usd, start);
if seed_count > K || ~isfinite(seed_upper)
    error('O1:bad_polish_seed', ...
        '关键K=%g的定向上界精修初值不可行。', K);
end

z_indices = indices.O1_HB_change(:);
z_values = round(seed_vector(z_indices));
problem.lb(z_indices) = z_values;
problem.ub(z_indices) = z_values;
problem.intcon = setdiff(problem.intcon(:), z_indices);

objective_offset = seed_upper - problem.f(:).' * seed_vector(:);
target_upper = prior.objective_lower + ...
    ctx.config.frontier_certification_tolerance_usd_t * ...
    ctx.config.nh3_target_t;
target_solver_upper = target_upper - objective_offset;
% 把论文要求的0.5 USD/t直接写成成本帽；找到任一可行点即可结束。
problem.Aineq(end + 1, :) = sparse(problem.f(:).');
problem.bineq(end + 1, 1) = target_solver_upper + ...
    max(1e-6, 1e-10 * abs(target_solver_upper));
problem.x0 = [];

relaxed_grid = zeros(0, 1);
relaxed_ael = zeros(0, 1);
if isfield(indices, 'u_purchase') && ...
        isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    relaxed_grid = indices.u_purchase(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_grid);
end
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    relaxed_ael = indices.I_AEL_up(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_ael);
end

record = prior;
record.frontier_attempts = attempt;
record.polish_attempts = record_field(prior, 'polish_attempts', 0) + 1;
record.frontier_phase = "polish";
record.polish_target_upper_usd = target_upper;
record.polish_before_upper_usd = prior.objective_upper;
record.polish_after_upper_usd = prior.objective_upper;
record.polish_pattern_update_hours = find(z_values > 0.5);
record.polish_exitflag = NaN;
record.polish_elapsed_s = NaN;
record.polish_status = "未找到达标上界";
record.polish_message = "";

started = tic;
candidate_x = [];
try
    [candidate_x, ~, polish_exitflag, polish_output] = ...
        intlinprog(problem);
    if ~isempty(candidate_x) && ...
            (~isempty(relaxed_grid) || ~isempty(relaxed_ael))
        [candidate_x, recovery_flag, recovery_output] = ...
            ctx.services.recover_direction_binaries( ...
            problem, candidate_x, indices, 60);
        if recovery_flag <= 0 || isempty(candidate_x)
            candidate_x = [];
            polish_output.recovery = recovery_output;
            polish_output.message = ...
                "方向变量恢复失败，未接收本轮候选上界。";
        end
    end
catch exception
    polish_exitflag = NaN;
    polish_output = struct('message', exception.message);
end
record.polish_elapsed_s = toc(started);
record.elapsed_s = record.polish_elapsed_s;
record.polish_exitflag = polish_exitflag;
record.polish_output = polish_output;
if isfield(polish_output, 'message')
    record.polish_message = string(polish_output.message);
end

if ~isempty(candidate_x)
    solution = vector_to_solution(candidate_x, indices);
    solution = ctx.services.add_change_indicators(solution, ctx);
    candidate_count = round(sum(solution.O1_HB_change));
    candidate_cost = evaluate(ctx.system_cost_usd, solution);
    acceptance_tolerance = max(1e-4, 1e-9 * abs(target_upper));
    if candidate_count <= K && isfinite(candidate_cost) && ...
            candidate_cost <= target_upper + acceptance_tolerance
        record.has_incumbent = true;
        record.solution = solution;
        record.objective_upper = min(record.objective_upper, candidate_cost);
        record.system_cost_upper = record.objective_upper;
        record.count_upper = candidate_count;
        record.polish_after_upper_usd = record.objective_upper;
        record.polish_status = "已找到达标上界";
        record.solve_backend = ...
            "intlinprog_fixed_hb_pattern_target_cap";
        record.cost_components = ...
            ctx.services.evaluate_cost_components(solution, ctx);
        record.operation_metrics = ...
            ctx.services.evaluate_operation_metrics(solution, ctx);
    else
        record.polish_status = "候选点未通过原模型复核";
    end
elseif polish_exitflag == -2
    record.polish_status = "当前HB变动模式下目标成本不可行";
elseif polish_exitflag == 0
    record.polish_status = "达到时限但未找到达标上界";
elseif isnan(polish_exitflag)
    record.polish_status = "精修求解异常";
end

record.absolute_gap = record.objective_upper - record.objective_lower;
record.relative_gap = record.absolute_gap / ...
    max(1, abs(record.objective_upper));
record.is_certified = record.has_incumbent && ...
    record_uncertainty_usd_t(record, ctx) <= ...
    ctx.config.frontier_certification_tolerance_usd_t + 1e-12;
if record.is_certified
    record.status = "certified_tolerance";
elseif record.has_incumbent
    record.status = "incumbent_with_bound";
end
end

function record = solve_cost_frontier_point( ...
        solver_data, K, start, ctx, reference, attempt, phase, prior)
problem = solver_data.problem;
problem.bineq(solver_data.update_row) = ...
    solver_data.update_coefficient * K;
if phase == "certification"
    problem.options = ctx.certification_options;
    if isfield(solver_data, 'variable_units')
        problem.variable_units = solver_data.variable_units;
    end
else
    problem.options = ctx.frontier_options;
end
indices = solver_data.indices;
use_gurobi = strcmp(ctx.config.frontier_solver, 'gurobi');
gurobi_focus = NaN;
if use_gurobi
    problem.cost_solver = 'gurobi';
    gurobi_focus = ctx.config.gurobi_mip_focus;
    if gurobi_focus == -1
        % 自动策略仅按该K的新后端历史推进，不能清空旧额度重复均衡策略。
        % 官方语义：0均衡、3界值优先、1可行解优先、2最优性证明。
        focus_plan = [0, 3, 1, 2];
        if phase == "certification"
            focus_index = mod(record_field(prior, ...
                'gurobi_certification_attempts', 0), numel(focus_plan)) + 1;
            gurobi_focus = focus_plan(focus_index);
        else
            gurobi_focus = 0;
        end
    end
    problem.gurobi_parameters = struct('MIPFocus', gurobi_focus, ...
        'Method', ctx.config.gurobi_method, 'Threads', ctx.config.gurobi_threads);
end
seed_count = round(sum(start.O1_HB_change));
seed_cost = evaluate(ctx.system_cost_usd, start);
seed_is_feasible = seed_count <= K && isfinite(seed_cost);
if seed_is_feasible
    problem.x0 = solution_to_vector(indices, start, numel(problem.lb));
    seed_solution = start;
    seed_upper = seed_cost;
    initial_status = "seed_cost_bound";
    initial_backend = "seed_fallback";
else
    problem.x0 = [];
    seed_solution = struct();
    seed_upper = Inf;
    initial_status = "unknown";
    initial_backend = "no_feasible_seed";
end
if isstruct(prior) && ~isempty(fieldnames(prior)) && ...
        prior.has_incumbent && isfield(prior, 'solution') && ...
        isstruct(prior.solution) && ~isempty(fieldnames(prior.solution)) && ...
        prior.objective_upper < seed_upper
    seed_solution = prior.solution;
    seed_upper = prior.objective_upper;
    seed_count = prior.count_upper;
    seed_is_feasible = seed_count <= K;
end
if seed_is_feasible
    seed_vector = solution_to_vector(indices, seed_solution, ...
        numel(problem.lb));
    problem.x0 = seed_vector;
    objective_offset = seed_upper - problem.f(:).' * seed_vector(:);
    solver_cutoff = seed_upper - objective_offset;
    problem.options = optimoptions(problem.options, 'ObjectiveCutOff', ...
        solver_cutoff + max(1e-6, 1e-10 * abs(solver_cutoff)));
else
    objective_offset = 0;
end
relaxed_grid = zeros(0, 1);
relaxed_ael = zeros(0, 1);
if ~use_gurobi && isfield(indices, 'u_purchase') && ...
        isfield(indices, 'p_purchase') && isfield(indices, 'p_sell') && ...
        all(ctx.model.context.C_purchase(:) >= ...
        ctx.model.context.C_sell(:) - 1e-12)
    relaxed_grid = indices.u_purchase(:);
    problem.intcon = setdiff(problem.intcon(:), relaxed_grid);
end
keep_startup_binaries = phase == "certification" && ...
    (ctx.config.frontier_keep_startup_binary || use_gurobi) && ...
    isfield(indices, 'I_AEL_up');
if isfield(indices, 'I_AEL_up') && isfield(indices, 'n_ael')
    if keep_startup_binaries || use_gurobi
        % 恢复原模型声明的整数方向，不改变原约束；短锚点仍可用外松弛。
        problem.intcon = union(problem.intcon(:), indices.I_AEL_up(:));
    else
        relaxed_ael = indices.I_AEL_up(:);
        problem.intcon = setdiff(problem.intcon(:), relaxed_ael);
    end
end

reference_lower = reference.objective_lower;
if ~isfinite(reference_lower)
    reference_lower = -Inf;
end
if isstruct(prior) && ~isempty(fieldnames(prior)) && ...
        isfield(prior, 'objective_lower') && ...
        isfinite(prior.objective_lower)
    reference_lower = max(reference_lower, prior.objective_lower);
end
cost_floor_added = phase == "certification" && ctx.config.frontier_bound_floor && ...
    seed_is_feasible && isfinite(reference_lower) && reference_lower <= seed_upper;
if cost_floor_added
    % 仅加入已有全局证书推出的冗余底线；原整数可行域、目标币值不变。
    % 常数项必须扣除，数值余量只向外放宽底线，不缩小原可行域。
    floor_margin = max(1e-4, 1e-9 * abs(reference_lower));
    problem.Aineq(end + 1, :) = -sparse(problem.f(:).');
    problem.bineq(end + 1, 1) = -(reference_lower - objective_offset) + floor_margin;
end
anchor_attempts = record_field(prior, 'anchor_attempts', 0);
certification_attempts = record_field(prior, ...
    'certification_attempts', 0);
if phase == "certification"
    certification_attempts = certification_attempts + 1;
else
    anchor_attempts = anchor_attempts + 1;
end
record = struct('objective_kind', "cost", ...
    'has_incumbent', seed_is_feasible, ...
    'objective_lower', reference_lower, ...
    'objective_upper', seed_upper, ...
    'system_cost_lower', reference_lower, ...
    'system_cost_upper', seed_upper, ...
    'absolute_gap', NaN, 'relative_gap', NaN, ...
    'count_lower', NaN, ...
    'count_upper', ternary_count(seed_is_feasible, seed_count), ...
    'is_proven', false, 'is_infeasible', false, 'exitflag', NaN, ...
    'status', initial_status, 'message', "", 'output', struct(), ...
    'solution', seed_solution, 'solve_backend', initial_backend, ...
    'K_limit', K, 'elapsed_s', NaN, 'frontier_attempts', attempt, ...
    'anchor_attempts', anchor_attempts, ...
    'certification_attempts', certification_attempts, ...
    'gurobi_certification_attempts', record_field(prior, ...
    'gurobi_certification_attempts', 0) + double(use_gurobi && phase == "certification"), ...
    'gurobi_mip_focus', gurobi_focus, ...
    'scaled_certification_attempts', record_field(prior, ...
    'scaled_certification_attempts', 0) + ...
    double(phase == "certification" && ctx.config.frontier_scale_solver), ...
    'floor_certification_attempts', record_field(prior, ...
    'floor_certification_attempts', 0) + double(cost_floor_added), ...
    'solver_cost_floor_usd', reference_lower, ...
    'startup_binary_certification_attempts', record_field(prior, ...
    'startup_binary_certification_attempts', 0) + double(keep_startup_binaries), ...
    'solver_startup_binaries_retained', keep_startup_binaries, ...
    'frontier_phase', string(phase), 'is_certified', false, ...
    'upper_bound_has_full_solution', seed_is_feasible, ...
    'solver_objective_offset_usd', objective_offset, ...
    'raw_solver_objective_upper_usd', NaN, ...
    'raw_solver_absolute_gap_usd', NaN);
if seed_is_feasible
    record.cost_components = ctx.services.evaluate_cost_components(seed_solution, ctx);
    record.operation_metrics = ctx.services.evaluate_operation_metrics(seed_solution, ctx);
end
started = tic;
candidate_x = [];
search_output = struct();
search_fval = NaN;
recovery_failed = false;
try
    stop_bound = Inf;
    if phase == "certification" && seed_is_feasible
        known_upper = seed_upper;
        if record_field(prior, 'has_incumbent', false) && ...
                record_field(prior, 'count_upper', Inf) <= K
            known_upper = min(known_upper, prior.objective_upper);
        end
        stop_bound = known_upper - objective_offset - ...
            ctx.config.frontier_certification_tolerance_usd_t * ...
            ctx.config.nh3_target_t;
    end
    [candidate_x, search_fval, exitflag, search_output] = run_cost_milp( ...
        problem, K, objective_offset, stop_bound);
    output = search_output;
    if ~isempty(candidate_x) && ...
            (use_gurobi || ~isempty(relaxed_grid) || ~isempty(relaxed_ael))
        [candidate_x, recovery_flag, recovery_output] = ...
            ctx.services.recover_direction_binaries( ...
            problem, candidate_x, indices, 60);
        if recovery_flag <= 0 || isempty(candidate_x)
            candidate_x = [];
            recovery_failed = true;
            output.recovery = recovery_output;
            output.message = "整数方向恢复失败；保留本轮有效下界。";
        end
    end
    if ~isempty(candidate_x)
        original_violation = max([0; problem.Aineq * candidate_x - problem.bineq(:); ...
            abs(problem.Aeq * candidate_x - problem.beq(:)); ...
            problem.lb(:) - candidate_x; candidate_x - problem.ub(:)]);
        integer_violation = max([0; abs(candidate_x(problem.intcon) - ...
            round(candidate_x(problem.intcon)))]);
        output.recovered_original_matrix_violation = original_violation;
        output.recovered_integer_violation = integer_violation;
        if original_violation > ctx.model.options.ConstraintTolerance || ...
                integer_violation > 1e-6
            candidate_x = [];
            recovery_failed = true;
            output.message = "候选未通过原矩阵或整数性复核；保留旧上界与有效下界。";
        end
    end
catch exception
    exitflag = NaN;
    output = struct('message', exception.message);
end
record.elapsed_s = toc(started);
record.exitflag = exitflag;
record.output = output;
if use_gurobi && isfield(search_output, 'solver_backend')
    record.solve_backend = "gurobi_matrix_cost_" + string(phase);
end
if isfinite(search_fval)
    record.raw_solver_objective_upper_usd = ...
        search_fval + objective_offset;
end
if isfield(search_output, 'absolutegap') && ...
        isscalar(search_output.absolutegap) && ...
        isfinite(search_output.absolutegap)
    record.raw_solver_absolute_gap_usd = ...
        max(0, search_output.absolutegap);
end
if isfield(output, 'message')
    record.message = string(output.message);
end
lower_bound = reference_lower;
if isfield(search_output, 'trace_dualbound') && ...
        isscalar(search_output.trace_dualbound) && ...
        isfinite(search_output.trace_dualbound)
    lower_bound = max(lower_bound, ...
        search_output.trace_dualbound + objective_offset);
elseif isfield(search_output, 'bestbound') && ...
        isscalar(search_output.bestbound) && ...
        isfinite(search_output.bestbound)
    lower_bound = max(lower_bound, search_output.bestbound + objective_offset);
elseif isfinite(search_fval) && ...
        isfield(search_output, 'absolutegap') && ...
        isscalar(search_output.absolutegap) && ...
        isfinite(search_output.absolutegap)
    lower_bound = max(lower_bound, ...
        search_fval + objective_offset ...
        - max(0, search_output.absolutegap));
end

candidate_accepted = false;
if ~isempty(candidate_x)
    solution = vector_to_solution(candidate_x, indices);
    solution = ctx.services.add_change_indicators(solution, ctx);
    candidate_count = round(sum(solution.O1_HB_change));
    candidate_cost = evaluate(ctx.system_cost_usd, solution);
    if candidate_count <= K && isfinite(candidate_cost)
        candidate_accepted = true;
        record.has_incumbent = true;
        if candidate_cost < record.objective_upper
            record.solution = solution;
            record.upper_bound_has_full_solution = true;
            record.objective_upper = candidate_cost;
            record.system_cost_upper = candidate_cost;
            record.count_upper = candidate_count;
        end
    end
end
% 更好上界即使已删去向量仍是有效证书；新求解不能把旧区间变宽。
% 缺失向量时明确标记，不把较贵热启动的运行轨迹冒充最佳上界轨迹。
if record_field(prior, 'has_incumbent', false) && ...
        record_field(prior, 'count_upper', Inf) <= K && ...
        isfinite(prior.objective_upper) && prior.objective_upper < record.objective_upper
    record.has_incumbent = true;
    record.objective_upper = prior.objective_upper;
    record.system_cost_upper = prior.objective_upper;
    record.count_upper = prior.count_upper;
    record.solution = record_field(prior, 'solution', struct());
    record.upper_bound_has_full_solution = ~isempty(fieldnames(record.solution));
    record.upper_bound_from_cache = true;
    names = {'cost_components', 'operation_metrics'};
    for i = 1:numel(names)
        if isfield(prior, names{i})
            record.(names{i}) = prior.(names{i});
        elseif isfield(record, names{i})
            record = rmfield(record, names{i});
        end
    end
end
if candidate_accepted
    record.solve_backend = string(ctx.config.frontier_solver) + "_matrix_cost_" + string(phase);
    if ~isempty(relaxed_grid)
        record.solve_backend = record.solve_backend + "_grid_relaxed";
    end
    if ~isempty(relaxed_ael)
        record.solve_backend = record.solve_backend ...
            + "_ael_direction_relaxed";
    end
    record.status = "incumbent_with_bound";
elseif ~record.has_incumbent && exitflag == -2 && ~recovery_failed
    record.objective_lower = Inf;
    record.objective_upper = Inf;
    record.system_cost_lower = Inf;
    record.system_cost_upper = Inf;
    record.is_infeasible = true;
    record.status = "infeasible_certified";
    record.solve_backend = string(ctx.config.frontier_solver) + "_matrix_cost";
    return
end
bound_tolerance = max(1e-4, 1e-9 * abs(record.objective_upper));
if lower_bound > record.objective_upper + bound_tolerance
    fprintf('[O1] K=%g求解下界超过已验证上界，拒绝本轮下界。\n', K);
    lower_bound = reference_lower;
    record.solver_bound_rejected = true;
end
record.objective_lower = min(lower_bound, record.objective_upper);
record.system_cost_lower = record.objective_lower;
record.absolute_gap = record.objective_upper - record.objective_lower;
record.relative_gap = record.absolute_gap ...
    / max(1, abs(record.objective_upper));
record.is_proven = isfinite(record.absolute_gap) && ...
    record.absolute_gap <= max(1e-7, eps(abs(record.objective_upper)));
record.is_certified = record.has_incumbent && ...
    record_uncertainty_usd_t(record, ctx) <= ...
    ctx.config.frontier_certification_tolerance_usd_t + 1e-12;
if record.is_proven
    record.status = "proven";
elseif record.is_certified
    record.status = "certified_tolerance";
elseif record.has_incumbent
    record.status = "incumbent_with_bound";
end
if record.has_incumbent && ~isempty(fieldnames(record.solution))
    record.cost_components = ctx.services.evaluate_cost_components(record.solution, ctx);
    record.operation_metrics = ctx.services.evaluate_operation_metrics( ...
        record.solution, ctx);
end
% 原模型认证不能丢掉已完成的候选池/多策略阶段，否则下次会从头重跑。
prior_fields = fieldnames(prior);
for prior_index = 1:numel(prior_fields)
    name = prior_fields{prior_index};
    if ~isfield(record, name)
        record.(name) = prior.(name);
    end
end

    function value = ternary_count(condition, count)
        if condition
            value = count;
        else
            value = NaN;
        end
    end
end

function [x, fval, exitflag, output] = run_cost_milp( ...
        problem, K, objective_offset, stop_bound, bound_label)
%RUN_COST_MILP 从官方回调保留当前求解域对偶界，并可等价缩放连续变量。
% 当前MATLAB的返回结构没有bestbound；optimplotmilp使用的dualbound
% 才是无首解阶段也可读取的下界。回调不改变约束和目标函数。
best_dualbound = -Inf;
if nargin < 5
    bound_label = "有效下界";
end
last_report_s = -Inf;
started = tic;
unit_scaled = isfield(problem, 'variable_units');
original_problem = problem;
units = ones(numel(problem.lb), 1);
if unit_scaled
    original_units = problem.variable_units(:);
    problem = rmfield(problem, 'variable_units');
    if numel(original_units) > numel(units) || ...
            any(~isfinite(original_units) | original_units <= 0)
        error('O1:bad_solver_units', '求解器单位向量必须与原变量匹配且为正数。');
    end
    units(1:numel(original_units)) = original_units;
    if any(units(problem.intcon) ~= 1)
        error('O1:scaled_integer_variable', '整数变量不允许进行单位缩放。');
    end
    D = spdiags(units, 0, numel(units), numel(units));
    problem.f = problem.f(:) .* units;
    if ~isempty(problem.Aineq)
        problem.Aineq = problem.Aineq * D;
        row_norm = max(1, full(max(abs(problem.Aineq), [], 2)));
        problem.Aineq = spdiags(1 ./ row_norm, 0, numel(row_norm), ...
            numel(row_norm)) * problem.Aineq;
        problem.bineq = problem.bineq(:) ./ row_norm;
    end
    if ~isempty(problem.Aeq)
        problem.Aeq = problem.Aeq * D;
        row_norm = max(1, full(max(abs(problem.Aeq), [], 2)));
        problem.Aeq = spdiags(1 ./ row_norm, 0, numel(row_norm), ...
            numel(row_norm)) * problem.Aeq;
        problem.beq = problem.beq(:) ./ row_norm;
    end
    problem.lb = problem.lb(:) ./ units;
    problem.ub = problem.ub(:) ./ units;
    if isfield(problem, 'x0') && ~isempty(problem.x0)
        problem.x0 = problem.x0(:) ./ units;
    end
end
original_callbacks = problem.options.OutputFcn;
if isempty(original_callbacks)
    original_callbacks = {};
elseif iscell(original_callbacks)
    original_callbacks = original_callbacks(:).';
else
    original_callbacks = {original_callbacks};
end
callbacks = cell(size(original_callbacks));
for i = 1:numel(original_callbacks)
    fn = original_callbacks{i};
    callbacks{i} = @(x, values, state) forward_callback(fn, x, values, state);
end
callbacks{end + 1} = @capture_bound;
if isfield(problem, 'cost_solver') && strcmp(problem.cost_solver, 'gurobi')
    [x, fval, exitflag, output] = run_gurobi_cost_milp(problem, stop_bound, K);
    best_dualbound = output.bestbound;
else
    problem.options = optimoptions(problem.options, 'OutputFcn', callbacks);
    [x, fval, exitflag, output] = intlinprog(problem);
end
% 无新首解或初始化即中止时可能返回空目标值，统一成标量未知值。
if ~isscalar(fval) || ~isfinite(fval)
    fval = NaN;
end
if ~isempty(x)
    x = x(:) .* units;
end
output.unit_scaled = unit_scaled;
if ~isempty(x)
    % 单位换算后的首个候选也按原矩阵计量；最终上界另经原模型LP恢复。
    output.original_matrix_violation = max([0; ...
        original_problem.Aineq * x - original_problem.bineq(:); ...
        abs(original_problem.Aeq * x - original_problem.beq(:)); ...
        original_problem.lb(:) - x; x - original_problem.ub(:)]);
    output.unit_objective_residual = abs(original_problem.f(:).' * x - fval);
end
output.trace_dualbound = best_dualbound;
if isscalar(fval) && isfinite(fval) && ...
        isfield(output, 'absolutegap') && ...
        isscalar(output.absolutegap) && isfinite(output.absolutegap)
    output.trace_dualbound = max(output.trace_dualbound, ...
        fval - max(0, output.absolutegap));
end

    function stop = forward_callback(fn, x, values, state)
        if ~isempty(x)
            x = x(:) .* units;
        end
        stop = fn(x, values, state);
    end

    function stop = capture_bound(~, values, state)
        stop = false;
        if isfield(values, 'dualbound') && ...
                isscalar(values.dualbound) && isfinite(values.dualbound)
            best_dualbound = max(best_dualbound, values.dualbound);
        end
        elapsed_s = toc(started);
        if isfinite(best_dualbound) && string(state) ~= "init" && ...
                elapsed_s - last_report_s >= 60
            nodes = NaN;
            if isfield(values, 'numnodes') && isscalar(values.numnodes)
                nodes = values.numnodes;
            end
            fprintf('[O1] K=%g求解进度：%s=%.3f USD，节点=%g，已用%.1f s。\n', ...
                K, bound_label, best_dualbound + objective_offset, nodes, elapsed_s);
            if bound_label == "成本帽超额下界" && ...
                    isfield(values, 'fval') && ...
                    isscalar(values.fval) && isfinite(values.fval)
                fprintf('[O1] 当前辅助超额上界=%.3f USD（原模型恢复后才接收）。\n', ...
                    values.fval);
            end
            last_report_s = elapsed_s;
        end
        if isfinite(stop_bound) && best_dualbound >= stop_bound
            stop = true;
        end
    end
end

function [x, fval, exitflag, output] = run_gurobi_cost_milp(problem, stop_bound, K)
% 原稀疏MILP逐项映射，不覆盖intlinprog、不调整约束或目标常数。
% 官方接口：https://docs.gurobi.com/projects/optimizer/en/13.0/reference/matlab/common.html
% 下界定义：https://docs.gurobi.com/projects/optimizer/en/13.0/reference/matlab/solving.html
n = numel(problem.f);
model = struct('A', sparse([problem.Aineq; problem.Aeq]), ...
    'obj', full(problem.f(:)), 'rhs', full([problem.bineq(:); problem.beq(:)]), ...
    'sense', [repmat('<', size(problem.Aineq, 1), 1); ...
    repmat('=', size(problem.Aeq, 1), 1)], ...
    'lb', full(problem.lb(:)), 'ub', full(problem.ub(:)), ...
    'vtype', repmat('C', n, 1), 'modelsense', 'min');
model.vtype(problem.intcon) = 'I';
if isfield(problem, 'x0') && numel(problem.x0) == n
    model.start = full(problem.x0(:));
end
params = problem.gurobi_parameters;
params.TimeLimit = problem.options.MaxTime;
params.MIPGap = problem.options.RelativeGapTolerance;
params.MIPGapAbs = problem.options.AbsoluteGapTolerance;
params.FeasibilityTol = max(1e-9, min(1e-6, problem.options.ConstraintTolerance));
params.IntFeasTol = 1e-6;
params.DisplayInterval = 60;
params.OutputFlag = 1;
params.LogToConsole = 0;
params.LogFile = [tempname, '_O1_Gurobi.log'];
if isfinite(stop_bound)
    % MATLAB接口不提供MIP回调；以官方目标界停止参数对应旧回调条件。
    params.BestBdStop = stop_bound + max(1e-4, 1e-9 * abs(stop_bound));
end
fprintf(['[O1] K=%g使用Gurobi，策略=%g，时限=%.1f s，', ...
    '绝对gap目标=%g USD，日志=%s\n'], ...
    K, params.MIPFocus, params.TimeLimit, params.MIPGapAbs, params.LogFile);
result = gurobi(model, params);
x = [];
fval = NaN;
bound = -Inf;
if isfield(result, 'x') && numel(result.x) == n && all(isfinite(result.x))
    x = result.x(:);
    fval = problem.f(:).' * x;
end
if isfield(result, 'objboundc') && isscalar(result.objboundc) && isfinite(result.objboundc)
    bound = result.objboundc;
elseif isfield(result, 'objbound') && isscalar(result.objbound) && isfinite(result.objbound)
    bound = result.objbound;
end
exitflag = 0;
if strcmp(result.status, 'OPTIMAL')
    exitflag = 1;
elseif strcmp(result.status, 'INFEASIBLE')
    exitflag = -2;
elseif strcmp(result.status, 'UNBOUNDED')
    exitflag = -3;
end
output = struct('message', ['Gurobi状态：', result.status], ...
    'gurobi_status', result.status, 'solver_backend', 'gurobi', ...
    'gurobi_mip_focus', params.MIPFocus, 'gurobi_method', params.Method, ...
    'gurobi_threads', params.Threads, ...
    'bestbound', bound, 'absolutegap', NaN, ...
    'numnodes', record_field(result, 'nodecount', NaN), ...
    'gurobi_log_file', params.LogFile, ...
    'runtime', record_field(result, 'runtime', NaN));
if isfinite(fval) && isfinite(bound)
    output.absolutegap = max(0, fval - bound);
end
end

function vector = solution_to_vector(indices, solution, vector_length)
vector = [];
if ~isstruct(solution) || isempty(fieldnames(solution))
    return
end
candidate = zeros(vector_length, 1);
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(solution, name) || ...
            numel(solution.(name)) ~= numel(indices.(name))
        return
    end
    candidate(indices.(name)(:)) = solution.(name)(:);
end
vector = candidate;
end

function solution = vector_to_solution(vector, indices)
solution = struct();
names = fieldnames(indices);
for i = 1:numel(names)
    name = names{i};
    index = indices.(name);
    solution.(name) = reshape(vector(index(:)), size(index));
end
end

function economic = solve_economic_boundaries(ctx, reference, feasibility)
allowances = ctx.config.cost_allowance_usd_t(:);
economic = struct([]);
start = reference.solution;
uncertainty = (reference.objective_upper - reference.objective_lower) ...
    / ctx.config.nh3_target_t;
for i = 1:numel(allowances)
    allowance = allowances(i);
    cost_cap = reference.objective_upper + ...
        allowance * ctx.config.nh3_target_t;
    fprintf('[O1] Economic boundary: delta=%g USD/t\n', allowance);
    [boundary, ~, ~] = O1Feasibility( ...
        ctx, start, cost_cap, "economic");
    boundary.K_lower = max(boundary.K_lower, feasibility.K_lower);
    if boundary.K_lower > boundary.K_upper
        error('O1:inconsistent_economic_bounds', ...
            'Economic K bounds conflict with the feasibility lower bound.');
    end
    boundary.minimum_updates.count_lower = boundary.K_lower;
    boundary.bound_width = boundary.K_upper - boundary.K_lower;
    boundary.is_proven = boundary.K_lower == boundary.K_upper;
    boundary.minimum_updates.objective_lower = boundary.K_lower;
    boundary.minimum_updates.absolute_gap = boundary.bound_width;
    boundary.minimum_updates.relative_gap = boundary.bound_width ...
        / max(1, boundary.K_upper);
    boundary.minimum_updates.is_proven = boundary.is_proven;
    row = struct('allowance_usd_t', allowance, ...
        'cost_cap_usd', cost_cap, ...
        'reference_lower_usd', reference.objective_lower, ...
        'reference_upper_usd', reference.objective_upper, ...
        'reference_uncertainty_usd_t', uncertainty, ...
        'certified_allowance_usd_t', allowance + uncertainty, ...
        'K_lower', boundary.K_lower, 'K_upper', boundary.K_upper, ...
        'is_proven', boundary.is_proven, ...
        'minimum_updates', boundary.minimum_updates, ...
        'search', boundary.search);
    if isempty(economic)
        economic = row;
    else
        economic(i, 1) = row;
    end
    if boundary.minimum_updates.has_incumbent
        start = boundary.minimum_updates.solution;
    end
end
end

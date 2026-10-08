function outputs = O1Economics(ctx, feasibility, reference)
%O1ECONOMICS 经济阈值识别；所有边界仅由全局下界或已验证可行解更新。
% 成本帽计数问题不调用Kfea；固定K问题只需跨过经济门槛，无统一成本gap要求。
cfg = ctx.config;
started = tic;
base = ctx.cost_solver;
p = base.problem;
base.cost_f = p.f(:);
base.offset = evaluate(ctx.system_cost_usd, reference.solution) - p.f(:).' * p.x0(:);
base.count_f = zeros(numel(p.lb), 1);
base.count_f(base.indices.O1_HB_change(:)) = 1;
base.units = variable_units(base, cfg.economic_scale_solver);
cache_file = fullfile(cfg.cache_directory, 'O1_economic_threshold_cache.mat');
state = load_state(cache_file, ctx);
state.new_solves = 0;
state.reference_refinements_this_run = 0;
state.active_task = "";
state.stop_reason = "incomplete_economic_threshold";
reference = merge_reference(reference, state.reference, ctx, base);
state = import_cost_cache(state, ctx, base);
state = register_reference_point(state, reference, ctx, base);
[state, economic] = certify(state, reference, feasibility, ctx);
fprintf('[O1] 阈值识别：delta=%.6g USD/t，Keco严格区间=[%g,%g]；不遍历成本前沿。\n', ...
    cfg.economic_delta_usd_t, economic.K_lower, economic.K_upper);
save_state();
fixed_attempts = zeros(ctx.T+1,1);

% 参考区间过宽时，先确保严格门槛拥有可用的经济可行见证。
while ~economic.is_proven && can_run() && ...
        (~isfinite(reference.objective_lower) || ...
        reference.objective_upper-reference.objective_lower > ...
        cfg.economic_delta_usd_t*cfg.nh3_target_t) && ...
        state.reference_refinements_this_run < cfg.economic_reference_max_refinements
    previous_gap = reference.objective_upper-reference.objective_lower;
    refine_reference();
    if reference.objective_upper-reference.objective_lower >= previous_gap-1e-6
        break
    end
end

for round_index = 1:cfg.economic_max_attempts
    if economic.is_proven || ~can_run(), break; end
    % 两个成本帽先各短算，后续与少量二分认证交替，不等待模型完全最优。
    for cap_index = 1:2
        if economic.is_proven || ~can_run(), break; end
        if cap_index == 1
            kind = "loose_count"; cap = economic.cost_cap_usd;
        else
            kind = "strict_count"; cap = economic.strict_cost_cap_usd;
        end
        if ~isfinite(cap), continue; end
        task = make_task(kind, economic.K_upper, cap, round_index);
        task.K_lower = economic.K_lower;
        if ~isfinite(task.K), task.K = ctx.T; end
        task.start = best_start(state, reference, task.K, base);
        prior = find_cap(state, kind, cap);
        task.attempt = prior.attempts+1;
        task.time_limit = next_time(cfg.economic_cap_time_s, task.attempt);
        begin_task(kind, task.K, task.time_limit);
        record = solve_task(base, task, ctx);
        state = store_cap(state, prior, record, kind, cap);
        finish_task();
        fprintf(['[O1] %s：状态=%s，模型计数下界=%g，已验证候选计数=%g，', ...
            '候选成本=%.6g USD；Keco=[%g,%g]。\n'], ...
            kind,record.solver_status,record.count_lower,record.count_upper, ...
            record.cost_upper_usd,economic.K_lower,economic.K_upper);
    end
    for probe_index = 1:cfg.economic_points_per_round
        if economic.is_proven || ~can_run(), break; end
        K = select_K(economic, state.points, fixed_attempts, round_index);
        if isempty(K), break; end
        fixed_attempts(K+1) = fixed_attempts(K+1)+1;
        prior = find_point(state.points, K);
        task = make_task("fixed_cost", K, Inf, round_index);
        task.start = best_start(state, reference, K, base);
        task.attempt = prior.attempts+1;
        task.time_limit = next_time(cfg.economic_fixed_time_s, task.attempt);
        task.sat = economic.strict_cost_cap_usd;
        task.fail = economic.cost_cap_usd;
        task.focus = evidence_focus(prior,task.sat,task.fail, ...
            cfg.economic_delta_usd_t*cfg.nh3_target_t,task.attempt);
        begin_task("fixed_cost", K, task.time_limit);
        record = solve_task(base, task, ctx);
        state.points = merge_point(state.points, record, K, "fixed_K_global_cost");
        finish_task();
        point = find_point(state.points, K);
        fprintf('[O1] K=%g：%s，成本界=[%.6g,%.6g] USD；Keco=[%g,%g]。\n', ...
            K, point.status, point.cost_lower_usd, point.cost_upper_usd, ...
            economic.K_lower,economic.K_upper);
    end
    if ~economic.is_proven && can_run() && ...
            state.reference_refinements_this_run < cfg.economic_reference_max_refinements && ...
            reference_is_limiting(state, reference, economic, cfg)
        refine_reference();
    end
end
if economic.is_proven
    state.stop_reason = "complete_economic_threshold";
elseif toc(started) >= cfg.economic_run_budget_s
    state.stop_reason = "incomplete_economic_time_budget";
elseif state.new_solves >= cfg.economic_max_solves_per_run
    state.stop_reason = "incomplete_economic_solve_budget";
elseif reference_is_limiting(state, reference, economic, cfg)
    state.stop_reason = "incomplete_economic_reference_resolution";
end
state.elapsed_s = toc(started);
save_state();
representative = struct('has_incumbent',false,'solution',struct());
if economic.satisfied_evidence.has_solution
    representative.has_incumbent = true;
    representative.solution = economic.satisfied_evidence.solution;
end
outputs = struct('reference',reference,'boundaries',economic,'state',state, ...
    'certification',points_table(state.points),'representative',representative);

    function yes = can_run()
        yes = state.new_solves < cfg.economic_max_solves_per_run && ...
            toc(started) < cfg.economic_run_budget_s;
    end

    function seconds = next_time(first_time, attempt)
        seconds = first_time;
        if attempt > 1, seconds = cfg.economic_retry_time_s; end
        seconds = max(0.01,min(seconds,cfg.economic_run_budget_s-toc(started)));
    end

    function task = make_task(kind,K,cap,round_number)
        task = struct('kind',kind,'K',K,'K_lower',0,'cap',cap, ...
            'sat',NaN,'fail',NaN,'round',round_number,'attempt',1, ...
            'time_limit',cfg.economic_fixed_time_s,'start',[],'focus',-1);
    end

    function begin_task(kind,K,seconds)
        state.active_task = kind;
        save_state();
        fprintf('[O1] %s：K上限=%g，时限=%.1f s；当前Keco=[%g,%g]。\n', ...
            kind,K,seconds,economic.K_lower,economic.K_upper);
    end

    function finish_task()
        state.new_solves = state.new_solves+1;
        state.active_task = "";
        [state,economic] = certify(state,reference,feasibility,ctx);
        save_state();
    end

    function refine_reference()
        task = make_task("reference_cost",ctx.T,Inf,1);
        task.time_limit = next_time(cfg.economic_reference_time_s,1);
        task.start = solution_vector(base.indices,reference.solution,numel(base.cost_f));
        task.attempt = state.reference_refinements_this_run+1;
        gap = reference.objective_upper-reference.objective_lower;
        task.absolute_gap = cfg.economic_reference_tolerance_usd_t*cfg.nh3_target_t;
        if isfinite(gap), task.absolute_gap = min(task.absolute_gap,max(1e-6,gap/5)); end
        begin_task("reference_refinement",ctx.T,task.time_limit);
        record = solve_task(base,task,ctx);
        candidate = reference;
        candidate.objective_lower = record.cost_lower_usd;
        candidate.objective_upper = record.cost_upper_usd;
        candidate.has_incumbent = record.has_incumbent;
        candidate.solution = record.solution;
        reference = merge_reference(reference,candidate,ctx,base);
        state.reference_refinements_this_run = state.reference_refinements_this_run+1;
        state = register_reference_point(state,reference,ctx,base);
        ctx.services.save_reference(reference,ctx);
        finish_task();
        fprintf('[O1] 参考成本收紧为[%.3f,%.3f] USD；Kref=%g。\n', ...
            reference.objective_lower,reference.objective_upper,reference.count_upper);
    end

    function save_state()
        state.reference = reference;
        state.Keco_lower = economic.K_lower;
        state.Keco_upper = economic.K_upper;
        if ~cfg.use_cache, return; end
        payload = struct('signature',ctx.cost_signature, ...
            'delta_usd_t',cfg.economic_delta_usd_t,'schema_version',1,'state',state);
        temporary = [cache_file,'.tmp.mat'];
        save(temporary,'-struct','payload','-v7.3');
        movefile(temporary,cache_file,'f');
        if strlength(string(cfg.progress_file)) == 0, return; end
        fid = fopen(cfg.progress_file,'a','n','UTF-8');
        if fid < 0
            warning('O1:progress_write_failed','阈值缓存已保存，进度文件无法打开。');
            return
        end
        close_file = onCleanup(@() fclose(fid));
        fprintf(fid,'\n- O1经济阈值检查点：Kref=%g，Keco=[%g,%g]，认证=%d，阶段=%s，状态=%s。\n', ...
            reference.count_upper,economic.K_lower,economic.K_upper,economic.is_proven, ...
            state.active_task,state.stop_reason);
        clear close_file
    end
end

function state = load_state(file,ctx)
state = struct('points',repmat(empty_point(0),0,1), ...
    'caps',repmat(empty_cap("",Inf),0,1),'reference',struct());
if ~ctx.config.use_cache || ~isfile(file), return; end
loaded = load(file);
if isfield(loaded,'schema_version') && loaded.schema_version == 1 && ...
        isequaln(loaded.signature,ctx.cost_signature) && ...
        loaded.delta_usd_t == ctx.config.economic_delta_usd_t
    state = loaded.state;
    fprintf('[O1] 已读取经济阈值缓存；旧状态将按当前门槛重新认证。\n');
end
end

function point = empty_point(K)
point = struct('K',K,'cost_lower_usd',-Inf,'cost_upper_usd',Inf, ...
    'has_incumbent',false,'solution',struct(),'count_upper',K, ...
    'is_infeasible',false,'status',"unknown",'attempts',0,'elapsed_s',0, ...
    'solver_status',"",'source',"",'matrix_violation',NaN);
end

function cap = empty_cap(kind,value)
cap = struct('kind',kind,'cost_cap_usd',value,'count_lower',0,'count_upper',Inf, ...
    'cost_upper_usd',Inf,'has_incumbent',false,'solution',struct(), ...
    'is_infeasible',false,'attempts',0,'elapsed_s',0,'solver_status',"", ...
    'matrix_violation',NaN);
end

function state = import_cost_cache(state,ctx,base)
if ~ctx.config.use_cache, return; end
for signature = {ctx.cost_signature,ctx.signature}
    entries = ctx.services.fixed_point_store(ctx.point_cache_file,signature{1}, ...
        "load","frontier_cost",Inf,struct());
    for i = 1:numel(entries)
        K = entries(i).K;
        if ~isfinite(K) || K < 0 || K > ctx.T, continue; end
        old = entries(i).record;
        if isequaln(signature{1},ctx.signature)
            old = ctx.services.migrate_cost_record(old,ctx);
        end
        if value(old,'objective_kind',"cost") ~= "cost", continue; end
        point = empty_point(K);
        point.cost_lower_usd = value(old,'objective_lower',-Inf);
        point.is_infeasible = value(old,'is_infeasible',false);
        % 旧版frontier_cost仅在原矩阵核验通过后登记has_incumbent及上界。
        point.has_incumbent = value(old,'has_incumbent',false) && ...
            isfinite(value(old,'objective_upper',Inf));
        if point.has_incumbent, point.cost_upper_usd = old.objective_upper; end
        point.solver_status = string(value(old,'status',"cached_cost_bound"));
        if point.has_incumbent && isfield(old,'solution') && ~isempty(fieldnames(old.solution))
            [x,solution,cost,count,residual] = validate_solution(old.solution,base,ctx,K);
            if ~isempty(x)
                point.solution = solution;
                point.cost_upper_usd = cost;
                point.count_upper = count;
                point.matrix_violation = residual;
            else
                point.has_incumbent = false;
                point.cost_upper_usd = Inf;
            end
        end
        state.points = merge_point(state.points,point,K,"legacy_validated_cost_bound");
    end
end
end

function reference = merge_reference(reference,candidate,ctx,base)
if isempty(fieldnames(candidate)), return; end
reference.objective_lower = max(reference.objective_lower, ...
    value(candidate,'objective_lower',-Inf));
if value(candidate,'has_incumbent',false) && isfield(candidate,'solution')
    [x,solution,cost,count] = validate_solution(candidate.solution,base,ctx,ctx.T);
    if ~isempty(x) && cost <= reference.objective_upper
        reference.solution = solution;
        reference.objective_upper = cost;
        reference.count_upper = count;
    end
end
reference.system_cost_lower = reference.objective_lower;
reference.system_cost_upper = reference.objective_upper;
reference.absolute_gap = reference.objective_upper-reference.objective_lower;
if reference.absolute_gap < -money_margin(reference.objective_upper)
    error('O1:inconsistent_reference','参考全局下界超过可行成本上界。');
end
reference.relative_gap = max(0,reference.absolute_gap)/max(1,abs(reference.objective_upper));
reference.cost_components = ctx.services.evaluate_cost_components(reference.solution,ctx);
reference.operation_metrics = ctx.services.evaluate_operation_metrics(reference.solution,ctx);
end

function state = register_reference_point(state,reference,ctx,base)
[x,solution,cost,count,residual] = validate_solution(reference.solution,base,ctx,ctx.T);
if isempty(x), error('O1:invalid_reference','参考解未通过原矩阵核验。'); end
point = empty_point(count);
point.solution = solution;
point.has_incumbent = true;
point.cost_upper_usd = cost;
point.cost_lower_usd = reference.objective_lower;
point.count_upper = count;
point.matrix_violation = residual;
state.points = merge_point(state.points,point,count,"reference_witness");
end

function [state,economic] = certify(state,reference,feasibility,ctx)
delta = ctx.config.economic_delta_usd_t;
sat = reference.objective_lower+delta*ctx.config.nh3_target_t;
fail = reference.objective_upper+delta*ctx.config.nh3_target_t;
lower = feasibility.K_lower;
upper = Inf;
accepted = struct('source',"none",'K',Inf,'cost_upper_usd',Inf, ...
    'threshold_usd',sat,'has_solution',false,'solution',struct());
rejected = struct('source',"cached_physical_lower_bound", ...
    'excluded_K_max',lower-1,'cost_lower_usd',NaN,'threshold_usd',fail, ...
    'count_lower',lower,'cost_cap_usd',Inf);
for i = 1:numel(state.points)
    point = state.points(i);
    point.cost_lower_usd = max(point.cost_lower_usd,reference.objective_lower);
    if point.is_infeasible || point.cost_lower_usd > fail+money_margin(fail)
        point.status = "rejected";
        if point.K+1 > lower
            lower = point.K+1;
            rejected.source = point.source;
            rejected.excluded_K_max = point.K;
            rejected.cost_lower_usd = point.cost_lower_usd;
            rejected.count_lower = lower;
        end
    elseif point.has_incumbent && point.cost_upper_usd <= sat
        point.status = "satisfied";
        candidate_K = min(point.K,point.count_upper);
        if candidate_K < upper || (candidate_K == upper && ...
                point.cost_upper_usd < accepted.cost_upper_usd)
            upper = candidate_K;
            accepted = acceptance(point,point.source,sat);
        end
    else
        point.status = "unknown";
    end
    if point.cost_lower_usd > point.cost_upper_usd+money_margin(fail)
        error('O1:inconsistent_cost_bounds','K=%g的成本证书矛盾。',point.K);
    end
    state.points(i) = point;
end
for i = 1:numel(state.caps)
    cap = state.caps(i);
    % 只有包含真实经济可行域的宽松帽，才能提供Keco全局下界。
    if cap.kind == "loose_count" && cap.cost_cap_usd >= fail && cap.count_lower > lower
        lower = cap.count_lower;
        rejected.source = "loose_cap_global_count_bound";
        rejected.excluded_K_max = lower-1;
        rejected.count_lower = lower;
        rejected.cost_lower_usd = NaN;
        rejected.cost_cap_usd = cap.cost_cap_usd;
    end
    % 任意成本帽模型的可行候选都必须重新通过严格经济门槛。
    if cap.has_incumbent && cap.cost_upper_usd <= sat && cap.count_upper < upper
        upper = cap.count_upper;
        point = empty_point(upper);
        point.cost_upper_usd = cap.cost_upper_usd;
        point.solution = cap.solution;
        point.count_upper = upper;
        accepted = acceptance(point,cap.kind+"_validated_witness",sat);
    end
end
if lower > upper
    error('O1:inconsistent_economic_bounds','经济计数全局下界超过严格合格上界。');
end
is_proven = isfinite(upper) && lower == upper;
Keco = NaN;
if is_proven, Keco = upper; end
economic = struct('allowance_usd_t',delta,'certified_allowance_usd_t',delta, ...
    'cost_cap_usd',fail,'strict_cost_cap_usd',sat, ...
    'reference_lower_usd',reference.objective_lower, ...
    'reference_upper_usd',reference.objective_upper, ...
    'reference_uncertainty_usd_t',(reference.objective_upper-reference.objective_lower)/ctx.config.nh3_target_t, ...
    'K_lower',lower,'K_upper',upper,'K_upper_strict',upper,'Keco',Keco, ...
    'is_proven',is_proven,'is_strictly_certified',is_proven, ...
    'method',"two_cap_and_fixed_K_certification", ...
    'satisfied_evidence',accepted,'rejected_evidence',rejected);
end

function evidence = acceptance(point,source,sat)
evidence = struct('source',source,'K',min(point.K,point.count_upper), ...
    'cost_upper_usd',point.cost_upper_usd,'threshold_usd',sat, ...
    'has_solution',~isempty(fieldnames(point.solution)),'solution',point.solution);
end

function prior = find_point(points,K)
prior = empty_point(K);
if isempty(points), return; end
index = find([points.K] == K,1);
if ~isempty(index), prior = points(index); end
end

function points = merge_point(points,new,K,source)
prior = find_point(points,K);
prior.cost_lower_usd = max(prior.cost_lower_usd,new.cost_lower_usd);
prior.is_infeasible = prior.is_infeasible || new.is_infeasible;
if new.has_incumbent && (new.cost_upper_usd < prior.cost_upper_usd || ...
        (new.cost_upper_usd == prior.cost_upper_usd && ~isempty(fieldnames(new.solution))))
    prior.has_incumbent = true;
    prior.cost_upper_usd = new.cost_upper_usd;
    prior.count_upper = new.count_upper;
    prior.solution = new.solution;
    prior.matrix_violation = new.matrix_violation;
end
prior.attempts = max(prior.attempts,new.attempts);
prior.elapsed_s = prior.elapsed_s+new.elapsed_s;
prior.solver_status = new.solver_status;
prior.source = source;
index = find([points.K] == K,1);
if isempty(index), points(end+1,1) = prior; else, points(index) = prior; end
[~,order] = sort([points.K]); points = points(order);
end

function prior = find_cap(state,kind,cap)
prior = empty_cap(kind,cap);
if isempty(state.caps), return; end
index = find([state.caps.cost_cap_usd] == cap & [state.caps.kind] == kind,1);
if ~isempty(index), prior = state.caps(index); end
end

function state = store_cap(state,prior,new,kind,cap)
prior.count_lower = max(prior.count_lower,new.count_lower);
prior.is_infeasible = prior.is_infeasible || new.is_infeasible;
if new.has_incumbent && (new.count_upper < prior.count_upper || ...
        (new.count_upper == prior.count_upper && new.cost_upper_usd < prior.cost_upper_usd))
    prior.count_upper = new.count_upper;
    prior.cost_upper_usd = new.cost_upper_usd;
    prior.has_incumbent = true;
    prior.solution = new.solution;
    prior.matrix_violation = new.matrix_violation;
end
prior.attempts = new.attempts;
prior.elapsed_s = prior.elapsed_s+new.elapsed_s;
prior.solver_status = new.solver_status;
index = [];
if ~isempty(state.caps)
    index = find([state.caps.cost_cap_usd] == cap & [state.caps.kind] == kind,1);
end
if isempty(index), state.caps(end+1,1) = prior; else, state.caps(index) = prior; end
end

function K = select_K(economic,points,attempts,round_number)
K = [];
if ~isfinite(economic.K_upper), return; end
lower = economic.K_lower; upper = economic.K_upper;
middle = floor((lower+upper)/2);
candidates = unique([middle,lower,upper-1, ...
    floor((lower+middle)/2),floor((middle+upper)/2)]);
pending = [points.K];
pending = pending(pending >= lower & pending < upper);
candidates = unique([candidates,pending]);
candidates = candidates(candidates >= lower & candidates < upper);
candidates = candidates(attempts(candidates+1) < round_number);
if isempty(candidates), return; end
scores = zeros(numel(candidates),4);
for i = 1:numel(candidates)
    point = find_point(points,candidates(i));
    distance = min(max(0,point.cost_upper_usd-economic.strict_cost_cap_usd), ...
        max(0,economic.cost_cap_usd-point.cost_lower_usd));
    quality = 1;
    if isfinite(distance)
        quality = min(4,distance/max(1,economic.cost_cap_usd-economic.reference_upper_usd));
    end
    reduction = min(candidates(i)-lower+1,upper-candidates(i));
    scores(i,:) = [attempts(candidates(i)+1),(1+quality)/max(1,reduction), ...
        abs(candidates(i)-middle),candidates(i)];
end
[~,order] = sortrows(scores,[1,2,3,4]);
K = candidates(order(1));
end

function focus = evidence_focus(point,sat,fail,allowance,attempt)
upper_distance = max(0,point.cost_upper_usd-sat);
lower_distance = max(0,fail-point.cost_lower_usd);
near = max(1,allowance/4);
if upper_distance <= near && upper_distance <= lower_distance
    focus = 1; % A类：优先改善可行上界。
elseif lower_distance <= near
    focus = 3; % B类：优先改善全局下界。
else
    foci = [1,3,0,2]; focus = foci(1+mod(attempt-1,numel(foci)));
end
end

function yes = reference_is_limiting(state,reference,economic,cfg)
gap = reference.objective_upper-reference.objective_lower;
yes = false;
if ~isfinite(gap), yes = true; return; end
if gap <= 1e-6, return; end
for i = 1:numel(state.points)
    p = state.points(i);
    if p.status == "unknown" && p.K >= economic.K_lower && p.K < economic.K_upper && ...
            p.cost_lower_usd >= economic.strict_cost_cap_usd-money_margin(economic.cost_cap_usd) && ...
            p.cost_upper_usd <= economic.cost_cap_usd+money_margin(economic.cost_cap_usd)
        yes = true; return
    end
end
yes = economic.K_upper-economic.K_lower <= 2 && ...
    gap > cfg.economic_reference_tolerance_usd_t*cfg.nh3_target_t;
end

function start = best_start(state,reference,K,base)
solution = reference.solution;
best_score = Inf;
for i = 1:numel(state.points)
    p = state.points(i);
    if ~p.has_incumbent || isempty(fieldnames(p.solution)), continue; end
    score = double(p.count_upper > K)*1e12 + p.cost_upper_usd;
    if score < best_score, best_score = score; solution = p.solution; end
end
for i = 1:numel(state.caps)
    c = state.caps(i);
    if ~c.has_incumbent || isempty(fieldnames(c.solution)), continue; end
    score = double(c.count_upper > K)*1e12+c.cost_upper_usd;
    if score < best_score, best_score = score; solution = c.solution; end
end
start = solution_vector(base.indices,solution,numel(base.cost_f));
if ~isempty(start) && sum(start(base.indices.O1_HB_change(:))) > K
    % 大K调度只作修复候选；释放设定值和更新二元量，不登记可行上界。
    start(base.indices.O1_HB_change(:)) = NaN;
    start(base.indices.O1_HB_setpoint(:)) = NaN;
end
end

function record = solve_task(base,task,ctx)
started = tic;
p = base.problem;
p.bineq(base.update_row) = task.K*base.update_coefficient;
is_count = task.kind == "loose_count" || task.kind == "strict_count";
if is_count
    p.f = base.count_f;
    p.Aineq = [p.Aineq;base.cost_f.';-base.count_f.'];
    p.bineq = [p.bineq(:);task.cap-base.offset;-task.K_lower];
    offset = 0;
else
    p.f = base.cost_f;
    offset = base.offset;
end
p.x0 = task.start;
if strcmp(ctx.config.economics_solver,'gurobi')
    result = gurobi_solve(p,base.units,task,offset,ctx);
else
    result = matlab_solve(p,task,offset,ctx);
end
record = empty_point(task.K);
record.count_upper = Inf;
record.attempts = task.attempt;
record.solver_status = result.status;
record.is_infeasible = result.status == "INFEASIBLE";
record.count_lower = 0;
if isfinite(result.bound)
    if is_count
        record.count_lower = max(0,ceil(result.bound-1e-7));
    else
        record.cost_lower_usd = result.bound+offset;
    end
end
if ~isempty(result.x)
    candidate = result.x;
    candidate(p.intcon) = round(candidate(p.intcon));
    if matrix_violation(p,candidate) > ctx.model.options.ConstraintTolerance || ...
            (is_count && base.cost_f.'*candidate+base.offset > task.cap)
        repair_time = min(30,task.time_limit-toc(started));
        if repair_time > 0
            candidate = repair_candidate(p,candidate,base.cost_f,repair_time,ctx);
        else
            candidate = [];
        end
    end
    if ~isempty(candidate)
        solution = vector_solution(candidate,base.indices);
        [x,solution,cost,count,residual] = validate_solution(solution,base,ctx,task.K);
        if ~isempty(x) && (~is_count || cost <= task.cap)
            record.has_incumbent = true;
            record.solution = solution;
            record.cost_upper_usd = cost;
            record.count_upper = count;
            record.matrix_violation = residual;
        end
    end
end
record.elapsed_s = toc(started);
if record.is_infeasible && record.has_incumbent
    error('O1:inconsistent_solver_status','求解器不可行状态与已验证可行解矛盾。');
end
end

function result = gurobi_solve(p,units,task,offset,ctx)
n = numel(p.lb);
D = spdiags(units,0,n,n);
A = [p.Aineq;p.Aeq]*D;
row_scale = max(1,full(max(abs(A),[],2)));
model = struct('A',spdiags(1./row_scale,0,size(A,1),size(A,1))*A, ...
    'rhs',[p.bineq(:);p.beq(:)]./row_scale, ...
    'sense',[repmat('<',size(p.Aineq,1),1);repmat('=',size(p.Aeq,1),1)], ...
    'obj',p.f(:).*units,'lb',p.lb(:)./units,'ub',p.ub(:)./units, ...
    'modelsense','min','vtype',repmat('C',n,1));
model.vtype(p.intcon) = 'I';
if ~isempty(p.x0), model.start = p.x0(:)./units; end
focus = ctx.config.gurobi_mip_focus;
if focus < 0
    if task.kind == "loose_count"
        focus = 3;
    elseif task.kind == "strict_count"
        focus = 1;
    elseif task.focus >= 0
        focus = task.focus;
    else
        foci = [1,3,0,2]; focus = foci(1+mod(task.attempt-1,numel(foci)));
    end
end
parameters = struct('TimeLimit',task.time_limit,'MIPGap',0,'MIPGapAbs',0, ...
    'MIPFocus',focus,'Method',ctx.config.gurobi_method,'Threads',ctx.config.gurobi_threads, ...
    'FeasibilityTol',1e-9,'IntFeasTol',1e-9,'DualReductions',0, ...
    'DisplayInterval',60,'OutputFlag',1,'LogToConsole',double(~strcmp(ctx.config.display,'off')), ...
    'LogFile',[tempname,'_O1_',char(task.kind),'.log']);
if task.kind == "fixed_cost"
    if isfinite(task.sat), parameters.BestObjStop = task.sat-offset-money_margin(task.sat); end
    if isfinite(task.fail), parameters.BestBdStop = task.fail-offset+money_margin(task.fail); end
elseif task.kind == "loose_count"
    parameters.MIPGapAbs = 0.49;
    if isfinite(task.K), parameters.BestBdStop = task.K-1+1e-6; end
elseif task.kind == "strict_count"
    parameters.MIPGapAbs = 0.49;
    parameters.BestObjStop = task.K_lower+1e-6;
elseif task.kind == "reference_cost"
    parameters.MIPGapAbs = task.absolute_gap;
end
fprintf('[O1] Gurobi %s：策略=%g，时限=%.1f s，日志=%s\n', ...
    task.kind,focus,task.time_limit,parameters.LogFile);
raw = gurobi(model,parameters);
result = struct('x',[],'bound',-Inf,'status',string(raw.status));
if isfield(raw,'x') && numel(raw.x) == n && all(isfinite(raw.x))
    result.x = raw.x(:).*units;
end
if isfield(raw,'objboundc') && isfinite(raw.objboundc)
    result.bound = raw.objboundc;
elseif isfield(raw,'objbound') && isfinite(raw.objbound)
    result.bound = raw.objbound;
end
end

function result = matlab_solve(p,task,offset,ctx)
bound = -Inf;
gap = 0;
if task.kind == "loose_count" || task.kind == "strict_count", gap = 0.49; end
if task.kind == "reference_cost", gap = task.absolute_gap; end
p.options = optimoptions(ctx.model.options,'Display',ctx.config.display, ...
    'MaxTime',task.time_limit,'RelativeGapTolerance',0, ...
    'AbsoluteGapTolerance',gap,'OutputFcn',@capture);
if ~isempty(p.x0) && any(~isfinite(p.x0)), p.x0 = []; end
[x,fval,flag,output] = intlinprog(p);
if isscalar(fval) && isfinite(fval) && isfield(output,'absolutegap') && isfinite(output.absolutegap)
    bound = max(bound,fval-output.absolutegap);
end
if isfield(output,'bestbound') && isscalar(output.bestbound) && isfinite(output.bestbound)
    bound = max(bound,output.bestbound);
end
status = "TIME_LIMIT";
if flag == -2, status = "INFEASIBLE"; elseif flag > 0, status = "OPTIMAL"; end
result = struct('x',x,'bound',bound,'status',status);

    function stop = capture(~,values,~)
        stop = false;
        if isfield(values,'dualbound') && isscalar(values.dualbound) && isfinite(values.dualbound)
            bound = max(bound,values.dualbound);
        end
        if task.kind == "fixed_cost"
            stop = bound+offset > task.fail+money_margin(task.fail);
            if isfield(values,'fval') && isscalar(values.fval) && isfinite(values.fval)
                stop = stop || values.fval+offset <= task.sat-money_margin(task.sat);
            end
        elseif task.kind == "loose_count"
            stop = ceil(bound-1e-7) >= task.K;
        elseif task.kind == "strict_count" && isfield(values,'fval') && ...
                isscalar(values.fval) && isfinite(values.fval)
            stop = values.fval <= task.K_lower+1e-7;
        end
    end
end

function x = repair_candidate(p,x,cost_f,seconds,ctx)
integer_indices = p.intcon;
p.lb(integer_indices) = round(x(integer_indices));
p.ub(integer_indices) = p.lb(integer_indices);
options = optimoptions('linprog','Display','off','MaxTime',seconds, ...
    'ConstraintTolerance',min(1e-8,ctx.model.options.ConstraintTolerance));
[candidate,~,flag] = linprog(cost_f,p.Aineq,p.bineq,p.Aeq,p.beq,p.lb,p.ub,options);
x = [];
if flag > 0 && ~isempty(candidate) && ...
        matrix_violation(p,candidate) <= ctx.model.options.ConstraintTolerance
    x = candidate;
end
end

function [x,solution,cost,count,residual] = validate_solution(solution,base,ctx,K)
x = []; cost = Inf; count = Inf; residual = Inf;
if ~isstruct(solution) || isempty(fieldnames(solution)), return; end
solution = ctx.services.add_change_indicators(solution,ctx);
candidate = solution_vector(base.indices,solution,numel(base.cost_f));
if isempty(candidate) || any(~isfinite(candidate)), return; end
p = base.problem;
p.bineq(base.update_row) = K*base.update_coefficient;
residual = matrix_violation(p,candidate);
integer_error = max([0;abs(candidate(p.intcon)-round(candidate(p.intcon)))]);
if residual > ctx.model.options.ConstraintTolerance || integer_error > 1e-6, return; end
count = round(sum(candidate(base.indices.O1_HB_change(:))));
if count > K, return; end
cost = evaluate(ctx.system_cost_usd,solution);
if ~isfinite(cost), return; end
x = candidate;
end

function residual = matrix_violation(p,x)
residual = max([0;p.Aineq*x-p.bineq(:);abs(p.Aeq*x-p.beq(:)); ...
    p.lb(:)-x;x-p.ub(:)]);
end

function units = variable_units(base,enabled)
units = ones(numel(base.cost_f),1);
if ~enabled, return; end
for name = {'P_AEL','storage_H2','p_purchase','p_sell','p_curt','grid_contract_kw'}
    if isfield(base.indices,name{1}), units(base.indices.(name{1})(:)) = 1000; end
end
units(base.problem.intcon) = 1;
end

function vector = solution_vector(indices,solution,n)
vector = zeros(n,1);
for name = fieldnames(indices).'
    if ~isfield(solution,name{1}) || numel(solution.(name{1})) ~= numel(indices.(name{1}))
        vector = []; return
    end
    vector(indices.(name{1})(:)) = solution.(name{1})(:);
end
end

function solution = vector_solution(vector,indices)
solution = struct();
for name = fieldnames(indices).'
    index = indices.(name{1});
    solution.(name{1}) = reshape(vector(index(:)),size(index));
end
end

function result = value(record,name,fallback)
result = fallback;
if isfield(record,name) && ~isempty(record.(name)), result = record.(name); end
end

function tolerance = money_margin(cost)
tolerance = max(1e-4,1e-10*abs(cost));
end

function table_out = points_table(points)
K = reshape([points.K],[],1);
cost_lower_usd = reshape([points.cost_lower_usd],[],1);
cost_upper_usd = reshape([points.cost_upper_usd],[],1);
status = reshape([points.status],[],1);
attempts = reshape([points.attempts],[],1);
elapsed_s = reshape([points.elapsed_s],[],1);
source = reshape([points.source],[],1);
table_out = table(K,cost_lower_usd,cost_upper_usd,status,attempts,elapsed_s,source);
end

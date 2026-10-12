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
base.grid_exact = grid_simplification_guard(base, cfg);
base.physical_problem = p;
base.cut_policy = 2;
base.cut_margin = value(cfg,'economic_cut_margin',1e-5);
base.cut_relative_margin = 1e-9;
fprintf('[O1] 购售电整数等价简化=%d；下界模型=%s。\n', ...
    base.grid_exact,string(value(cfg,'economic_proof_mode','full')));
cache_file = fullfile(cfg.cache_directory, 'O1_economic_threshold_cache.mat');
state = load_state(cache_file, ctx);
state.new_solves = 0;
state.reference_refinements_this_run = 0;
state.active_task = "";
state.stop_reason = "incomplete_economic_threshold";
if ~isfield(state,'block_cuts'), state.block_cuts = empty_cuts(); end
state.block_elapsed_s = 0;
if ~isfield(state,'cert_schedule'), state.cert_schedule=empty_cert_schedule(); end
if ~isfield(state,'primal_schedule')
    state.primal_schedule=struct('step',1,'stalls',0, ...
        'polished_K',Inf,'polished_cost',Inf);
end
if value(state.primal_schedule,'version',0)~=2
    state.primal_schedule.version=2;
    state.primal_schedule.step=cfg.economic_local_target_step;
    state.primal_schedule.stalls=0;
    if isfield(state.primal_schedule,'window_level')
        state.primal_schedule=rmfield(state.primal_schedule,'window_level');
    end
end
if ~isfield(state,'event_schedule'), state.event_schedule=struct(); end
previous_audit=value(state,'cut_audit',struct());
[base,state.cut_audit] = audit_block_cuts(base,state.block_cuts,state,reference,ctx);
base = apply_block_cuts(base,state.block_cuts);
if ~isempty(base.cut_disabled) && (value(previous_audit,'policy',0)~=base.cut_policy || ...
        ~isempty(setdiff(base.cut_disabled,value(previous_audit,'disabled',[]))))
    % A conflicting numerical cut cannot support an inherited rejection.
    state = invalidate_cut_dependent_bounds(state);
end
if value(state,'proof_model_version',0) ~= 1
    state.loose_schedule.stalled = false;
    state.loose_schedule.skip_once = false;
    state.proof_model_version = 1;
end
reference = merge_reference(reference, state.reference, ctx, base);
state = import_cost_cache(state, ctx, base);
state = register_reference_point(state, reference, ctx, base);
[state, economic] = certify(state, reference, feasibility, ctx);
initial_width = economic.K_upper-economic.K_lower;
initial_sweeps=decomposition_completed(value(state,'decomposition',struct()));
wide_certifications=0;
state.structural_report = struct('initial_width',initial_width,'current_width',initial_width, ...
    'initial_K_lower',economic.K_lower,'initial_K_upper',economic.K_upper, ...
    'lower_gain',0,'upper_gain',0,'width_reduction_fraction',0, ...
    'half_width_target_met',false,'acceptance_target_met',false,'block_elapsed_s',0);
fprintf('[O1] 阈值识别：delta=%.6g USD/t，Keco严格区间=[%g,%g]；不遍历成本前沿。\n', ...
    cfg.economic_delta_usd_t, economic.K_lower, economic.K_upper);
save_state();
fixed_attempts = zeros(ctx.T+1,1);
pending_cert_schedule=state.cert_schedule;

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
    if value(cfg,'economic_structural_search',false)
        reserve=min(value(cfg,'economic_certification_reserve_s',1800), ...
            0.25*cfg.economic_run_budget_s);
        if cfg.economic_run_budget_s-toc(started)<=reserve, break; end
        % Construct cheaper-count witnesses before spending time on their lower proof.
        primal_search(round_index,reserve);
        if economic.is_proven || ~can_run(), break; end
        block_time = min([cfg.economic_block_round_time_s, ...
            cfg.economic_block_budget_s-state.block_elapsed_s, ...
            cfg.economic_run_budget_s-toc(started)-reserve]);
        if block_time > 0 && isfinite(economic.cost_cap_usd) && ...
                decomposition_can_run(value(state,'decomposition',struct()),economic,cfg)
            begin_task("complete_decomposition",economic.K_upper,block_time);
            block_ctx = ctx;
            block_ctx.config.economic_decomposition_solve_limit = ...
                cfg.economic_max_solves_per_run-state.new_solves;
            [base,state,record] = strengthen_blocks(base,state,economic,block_ctx,block_time, ...
                round_index,@save_block_checkpoint);
            prior = find_cap(state,"loose_count",economic.cost_cap_usd);
            record.attempts = prior.attempts+1;
            state = store_witnesses(state,record);
            state = store_cap(state,prior,record,"loose_count",economic.cost_cap_usd);
            finish_task(max(1,record.solve_calls));
        elseif block_time>0 && isfield(state,'decomposition') && ...
                ~decomposition_can_run(state.decomposition,economic,cfg)
            fprintf('[O1] 分解任务已停放：%s；等待认证界、成本帽或定价预算变化。\n',state.decomposition.stop_reason);
        end
        if economic.is_proven || ~can_run(), break; end
        branch_time=min(cfg.economic_branch_time_s,max(0,cfg.economic_run_budget_s-toc(started)-reserve));
        if branch_time>0 && branch_can_run(value(state,'branch',struct()), ...
                value(state,'decomposition',struct()),economic,cfg,base)
            begin_task("branch_pricing",economic.K_upper,branch_time);
            branch_ctx=ctx; branch_ctx.config.economic_decomposition_solve_limit= ...
                cfg.economic_max_solves_per_run-state.new_solves;
            [state.branch,record]=branch_pricing(base,state,economic,branch_ctx,branch_time,@save_branch_checkpoint);
            prior=find_cap(state,"loose_count",state.branch.bound_cap_usd);
            state=store_cap(state,prior,record,"loose_count",state.branch.bound_cap_usd);
            finish_task(record.solve_calls);
        end
        if economic.K_upper-economic.K_lower <= cfg.economic_final_interval, break; end
        completed=decomposition_completed(value(state,'decomposition',struct()))-initial_sweeps;
        if wide_certifications==0 && (economic.K_lower>state.structural_report.initial_K_lower || completed>=2) && ...
                cfg.economic_run_budget_s-toc(started)>reserve+cfg.economic_certification_time_s
            concentrated_certification(true);
        end
        continue
    end
    extra_probes = 0;
    % 两个成本帽先各短算，后续与少量二分认证交替，不等待模型完全最优。
    for cap_index = 1:2
        if economic.is_proven || ~can_run(), break; end
        if cap_index == 1
            kind = "loose_count"; cap = economic.cost_cap_usd;
            schedule = state.loose_schedule;
            if strcmp(value(cfg,'economic_proof_mode','full'),'full') && ...
                    schedule.cap_usd == cap && schedule.skip_once
                state.loose_schedule.skip_once = false;
                extra_probes = 1;
                save_state();
                fprintf('[O1] 宽松帽此前推进缓慢：本轮让出预算给严格帽及固定K认证。\n');
                continue
            end
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
        if strcmp(value(cfg,'economic_proof_mode','full'),'full') && ...
                kind == "loose_count" && state.loose_schedule.cap_usd == cap && ...
                state.loose_schedule.stalled
            task.time_limit = min(task.time_limit,cfg.economic_stalled_cap_time_s);
            extra_probes = 1;
            if cfg.gurobi_mip_focus < 0
                foci = [0,2,3]; task.focus = foci(1+mod(task.attempt-2,3));
            end
            fprintf('[O1] 宽松帽短试探：预算=%.1f s，自动轮换策略。\n',task.time_limit);
        end
        before = economic;
        begin_task(kind, task.K, task.time_limit);
        record = solve_task(base, task, ctx);
        state = log_proof(state,record,task);
        state = store_witnesses(state, record);
        state = store_cap(state, prior, record, kind, cap);
        finish_task();
        if kind == "loose_count"
            lower_gain = economic.K_lower-before.K_lower;
            upper_gain = before.K_upper-economic.K_upper;
            if isnan(upper_gain), upper_gain = 0; end
            required_gain = 1;
            if isfinite(before.K_upper)
                required_gain = max(1,ceil(0.05*(before.K_upper-before.K_lower)));
            end
            stalled = lower_gain < required_gain && upper_gain < required_gain;
            state.loose_schedule = struct('cap_usd',cap,'stalled',stalled, ...
                'skip_once',stalled,'last_lower_gain',lower_gain,'last_upper_gain',upper_gain);
            save_state();
            fprintf('[O1] 宽松帽本轮证据推进：下界+%g，上界减少%g，停滞=%d。\n', ...
                lower_gain,upper_gain,stalled);
        end
        fprintf(['[O1] %s：状态=%s，模型计数下界=%g，已验证候选计数=%g，', ...
            '候选成本=%.6g USD；Keco=[%g,%g]。\n'], ...
            kind,record.solver_status,record.count_lower,record.count_upper, ...
            record.cost_upper_usd,economic.K_lower,economic.K_upper);
    end
    for probe_index = 1:cfg.economic_points_per_round+extra_probes
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
        state = log_proof(state,record,task);
        state = store_witnesses(state, record);
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
if value(cfg,'economic_structural_search',false) && ~economic.is_proven && can_run()
    concentrated_certification(false);
end
if economic.is_proven
    state.stop_reason = "complete_economic_threshold";
elseif toc(started) >= cfg.economic_run_budget_s
    state.stop_reason = "incomplete_economic_time_budget";
elseif state.new_solves >= cfg.economic_max_solves_per_run
    state.stop_reason = "incomplete_economic_solve_budget";
elseif reference_is_limiting(state, reference, economic, cfg)
    state.stop_reason = "incomplete_economic_reference_resolution";
elseif isfield(state,'decomposition') && isfield(state.decomposition,'park')
    state.stop_reason = "incomplete_economic_stalled_evidence";
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

    function finish_task(calls)
        if nargin == 0, calls = 1; end
        state.new_solves = state.new_solves+calls;
        state.active_task = "";
        [state,economic] = certify(state,reference,feasibility,ctx);
        save_state();
    end

    function primal_search(round_number,reserve)
        if ~economic.satisfied_evidence.has_solution || cfg.economic_local_passes==0, return; end
        old_upper=economic.K_upper;
        accepted_cost=economic.satisfied_evidence.cost_upper_usd;
        schedule=state.primal_schedule;
        if schedule.polished_K~=old_upper || schedule.polished_cost>accepted_cost+1e-6 || ...
                value(schedule,'polished_time_s',0)<cfg.economic_lp_time_s
            seconds=min(cfg.economic_lp_time_s,max(0,cfg.economic_run_budget_s-toc(started)-reserve));
            if seconds>0 && can_run()
                task=make_task("primal_polish",old_upper,economic.strict_cost_cap_usd,round_number);
                begin_task(task.kind,task.K,seconds);
                record=polish_witness(base,economic,ctx,seconds);
                state=log_proof(state,record,task); state=store_witnesses(state,record); finish_task(0);
                state.primal_schedule.polished_K=economic.K_upper;
                state.primal_schedule.polished_cost=economic.satisfied_evidence.cost_upper_usd;
                state.primal_schedule.polished_time_s=seconds;
            end
        end
        % Alternate small AEL cost repair with relocation of HB events.
        % The whole annual continuous dispatch and cyclic boundary stay free.
        for local_index=1:cfg.economic_local_passes
            available=cfg.economic_run_budget_s-toc(started)-reserve;
            if economic.is_proven || ~can_run() || available<=0, break; end
            kind="local_count"; K=economic.K_upper;
            headroom=economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd;
            if local_index==1 && cfg.economic_local_passes>1 && ...
                    headroom<cfg.economic_local_headroom_usd
                kind="local_cost";
            end
            task=make_task(kind,K,economic.strict_cost_cap_usd,round_number);
            task.K_lower=economic.K_lower;
            step=state.primal_schedule.step;
            if step<2, step=cfg.economic_local_target_step; end
            step=min(cfg.economic_local_max_step,max(2,step));
            task.target=max(economic.K_lower,K-step);
            task.sat=economic.satisfied_evidence.cost_upper_usd- ...
                max([1,0.01*cfg.economic_delta_usd_t*cfg.nh3_target_t, ...
                cfg.economic_local_headroom_usd-headroom]);
            task.start=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
            selector=state.primal_schedule;
            selector.next_hours=value(state.event_schedule,'next_hours',[]);
            task.event_hours=event_exchange_hours(task.start,base,ctx.T,selector,cfg);
            task.ael_hours=[];
            if kind=="local_cost"
                near=value(state,'decomposition',struct()); near=value(near,'repair_hours',[]);
                candidates=unique([selector.next_hours(:);near(:);task.event_hours(:)],'stable');
                candidates=candidates(1:min(numel(candidates),cfg.economic_ael_repair_hours));
                task.ael_hours=candidates; task.event_hours=[];
            end
            task.time_limit=min(cfg.economic_local_time_s,available);
            before_upper=economic.K_upper; before_cost=economic.satisfied_evidence.cost_upper_usd;
            begin_task(task.kind,task.K,task.time_limit);
            record=solve_task(base,task,ctx); state=log_proof(state,record,task);
            state=store_witnesses(state,record); finish_task();
            if kind=="local_count"
                state.primal_schedule.exchange_cursor=value(state.primal_schedule,'exchange_cursor',0)+ ...
                    cfg.economic_event_exchange_old;
            end
            improved=economic.K_upper<before_upper;
            if kind=="local_count"
                if improved
                    state.primal_schedule.step=min(cfg.economic_local_max_step,step+1);
                else
                    state.primal_schedule.step=max(2,step-1);
                end
            end
            fprintf('[O1] %s：开放%d个变化时刻、%d个AEL时段，目标K<=%g；Keco=[%g,%g]，成本改善%.3f USD，严格余量%.3f USD。\n', ...
                kind,numel(task.event_hours),numel(task.ael_hours),task.target,economic.K_lower,economic.K_upper, ...
                before_cost-economic.satisfied_evidence.cost_upper_usd, ...
                economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd);
        end
        available=cfg.economic_run_budget_s-toc(started)-reserve;
        seconds=min(cfg.economic_event_time_s,max(0,available));
        if seconds>0 && can_run() && ~economic.is_proven
            task=make_task("event_repair",economic.K_upper,economic.strict_cost_cap_usd,round_number);
            begin_task(task.kind,task.K,seconds);
            [record,state.event_schedule]=event_repair(base,economic,ctx,seconds,state.event_schedule,@save_event_witness);
            state=log_proof(state,record,task); state=store_witnesses(state,record); finish_task(0);
            fprintf('[O1] 变化事件恢复：LP调用%d，接受%d次，待重试%d个事件，Keco=[%g,%g]，严格余量%.3f USD。\n', ...
                record.lp_calls,record.accepted_events,numel(value(state.event_schedule,'retry_hours',[])), ...
                economic.K_lower,economic.K_upper, ...
                economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd);
        end
        if economic.K_upper<old_upper || economic.satisfied_evidence.cost_upper_usd<accepted_cost-1
            state.primal_schedule.stalls=0;
        else
            state.primal_schedule.stalls=state.primal_schedule.stalls+1;
            % Rotate the event pool after a failed pass; do not widen thousands of hours.
        end
        save_state();
    end

    function save_event_witness(point)
        state=store_witnesses(state,struct('witnesses',point));
        [state,economic]=certify(state,reference,feasibility,ctx);
        save_state(); % Keep each accepted event even if the next LP is interrupted.
    end

    function concentrated_certification(pilot)
        % Wide intervals get one annual count proof per run; repeated short
        % roots and midpoint solves otherwise consume the pricing budget.
        wide=economic.K_upper-economic.K_lower>cfg.economic_final_interval;
        if wide && wide_certifications>0, return; end
        if wide && ~economic.is_proven && can_run()
            certificate_kind="loose_count";
            cap = economic.cost_cap_usd;
            task = make_task(certificate_kind,economic.K_upper,cap,1);
            if ~isfinite(task.K), task.K = ctx.T; end
            task.K_lower = economic.K_lower;
            task.concentrated = ~pilot;
            task.start = best_start(state,reference,task.K,base);
            task.time_limit = min(cfg.economic_certification_time_s, ...
                max(0.01,cfg.economic_run_budget_s-toc(started)));
            prior = find_cap(state,certificate_kind,cap); task.attempt = prior.attempts+1;
            if claim_certification(task)
                begin_task(certificate_kind,task.K,task.time_limit);
                record = solve_task(base,task,ctx);
                state = log_proof(state,record,task);
                state = store_witnesses(state,record);
                state = store_cap(state,prior,record,certificate_kind,cap);
                state.cert_schedule=pending_cert_schedule;
                finish_task();
                wide_certifications=wide_certifications+1;
            end
        end
        if economic.K_upper-economic.K_lower>cfg.economic_final_interval, return; end
        % Only adjacent integer proofs can finish threshold certification.
        probes=cfg.economic_max_attempts; if pilot, probes=1; end
        for probe = 1:probes
            if economic.is_proven || ~can_run() || ~isfinite(economic.K_upper), break; end
            K = economic.K_upper-1;
            prior = find_point(state.points,K);
            task = make_task("fixed_cost",K,Inf,1);
            task.start = best_start(state,reference,K,base);
            task.sat = economic.strict_cost_cap_usd; task.fail = economic.cost_cap_usd;
            task.attempt = prior.attempts+1;
            task.time_limit = next_time(cfg.economic_certification_time_s,1);
            if pilot, task.time_limit=min(task.time_limit,cfg.economic_stalled_cap_time_s); end
            task.focus = evidence_focus(prior,task.sat,task.fail, ...
                cfg.economic_delta_usd_t*cfg.nh3_target_t,task.attempt);
            if ~claim_certification(task), break; end
            begin_task(task.kind,K,task.time_limit);
            before_lower = economic.K_lower; before_upper = economic.K_upper;
            record = solve_task(base,task,ctx);
            state = log_proof(state,record,task);
            state = store_witnesses(state,record);
            state.points = merge_point(state.points,record,K,"fixed_K_global_cost");
            state.cert_schedule=pending_cert_schedule;
            finish_task();
            if ~economic.is_proven && can_run() && ...
                    state.reference_refinements_this_run < cfg.economic_reference_max_refinements && ...
                    reference_is_limiting(state,reference,economic,cfg)
                refine_reference();
            end
            if before_lower == economic.K_lower && before_upper == economic.K_upper, break; end
        end
    end

    function allowed=claim_certification(task)
        % Persist a restart gate only after the solve returns; interruption is retryable.
        [allowed,pending_cert_schedule]=certification_gate(state.cert_schedule,task,economic, ...
            value(state,'decomposition',struct()),cfg);
        if ~allowed
            fprintf('[O1] 暂缓重复%s K=%g：认证界、有效松弛下界和预算未发生足够变化。\n',task.kind,task.K);
        end
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

    function save_block_checkpoint(block_state)
        state.block_cuts = block_state.block_cuts;
        state.decomposition = block_state.decomposition;
        d = state.decomposition;
        if isfinite(d.best_lower)
            evidence = empty_point(economic.K_upper);
            evidence.count_lower = max(0,ceil(d.best_lower-1e-5));
            prior = find_cap(state,"loose_count",d.bound_cap_usd);
            state = store_cap(state,prior,evidence,"loose_count",d.bound_cap_usd);
            [state,economic] = certify(state,reference,feasibility,ctx);
        end
        save_state();
    end

    function save_branch_checkpoint(proof)
        state.branch=proof;
        record=empty_point(economic.K_upper); record.count_lower=proof.global_lower;
        prior=find_cap(state,"loose_count",proof.bound_cap_usd);
        state=store_cap(state,prior,record,"loose_count",proof.bound_cap_usd);
        [state,economic]=certify(state,reference,feasibility,ctx); save_state();
    end

    function save_state()
        state.elapsed_s=toc(started);
        state.structural_report.current_width = economic.K_upper-economic.K_lower;
        state.structural_report.lower_gain = economic.K_lower-state.structural_report.initial_K_lower;
        state.structural_report.upper_gain = state.structural_report.initial_K_upper-economic.K_upper;
        if isnan(state.structural_report.upper_gain), state.structural_report.upper_gain = 0; end
        if isfinite(initial_width) && initial_width > 0
            state.structural_report.width_reduction_fraction = ...
                1-state.structural_report.current_width/initial_width;
        end
        state.structural_report.half_width_target_met = economic.is_proven || ...
            isfinite(initial_width) && state.structural_report.current_width <= initial_width/2;
        state.structural_report.acceptance_target_met = economic.is_proven || ...
            state.structural_report.width_reduction_fraction>=0.2;
        state.structural_report.strict_slack_usd = ...
            economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd;
        state.structural_report.block_elapsed_s = state.block_elapsed_s;
        state.structural_report.complete_sweeps=decomposition_completed(value(state,'decomposition',struct()));
        state.structural_report.new_complete_sweeps=state.structural_report.complete_sweeps-initial_sweeps;
        certificate=value(value(state,'decomposition',struct()),'certificate',struct());
        state.structural_report.decomposition_progress_met=economic.is_proven || ...
            value(certificate,'lower',-Inf)>state.structural_report.initial_K_lower+1e-5;
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
    'caps',repmat(empty_cap("",Inf),0,1),'reference',struct(), ...
    'loose_schedule',struct('cap_usd',NaN,'stalled',false,'skip_once',false, ...
    'last_lower_gain',0,'last_upper_gain',0));
if ~ctx.config.use_cache || ~isfile(file), return; end
loaded = load(file);
if isfield(loaded,'schema_version') && loaded.schema_version == 1 && ...
        isequaln(loaded.signature,ctx.cost_signature) && ...
        loaded.delta_usd_t == ctx.config.economic_delta_usd_t
    schedule = state.loose_schedule;
    state = loaded.state;
    if ~isfield(state,'loose_schedule'), state.loose_schedule = schedule; end
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
    if cap.kind == "loose_count" && cap.cost_cap_usd >= fail && cap.count_lower >= lower
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
    'method',"economic_threshold_certification", ...
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
if strlength(new.solver_status) > 0, prior.solver_status = new.solver_status; end
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
prior.attempts = max(prior.attempts,new.attempts);
prior.elapsed_s = prior.elapsed_s+new.elapsed_s;
if strlength(new.solver_status)>0, prior.solver_status = new.solver_status; end
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
            p.cost_upper_usd>economic.strict_cost_cap_usd && ...
            p.cost_upper_usd <= economic.cost_cap_usd+money_margin(economic.cost_cap_usd) && ...
            (p.cost_lower_usd >= economic.strict_cost_cap_usd-money_margin(economic.cost_cap_usd) || ...
            p.K>=economic.K_upper-1 || economic.K_upper-economic.K_lower<=cfg.economic_final_interval)
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
    if isfield(base.indices,'O1_HB_setpoint'), start(base.indices.O1_HB_setpoint(:)) = NaN; end
end
end

function entries=empty_cert_schedule()
entries=struct('kind',{},'K',{},'cap',{},'lower',{},'upper',{}, ...
    'sat',{},'fail',{},'DW_lower',{},'witness_cost',{},'budget',{});
end

function [allowed,entries]=certification_gate(entries,task,economic,d,cfg)
current=struct('kind',task.kind,'K',task.K,'cap',task.cap, ...
    'lower',economic.K_lower,'upper',economic.K_upper, ...
    'sat',economic.strict_cost_cap_usd,'fail',economic.cost_cap_usd, ...
    'DW_lower',value(d,'best_lower',-Inf), ...
    'witness_cost',economic.satisfied_evidence.cost_upper_usd,'budget',task.time_limit);
index=[];
if ~isempty(entries)
    same=[entries.kind]==task.kind & [entries.cap]==task.cap;
    structural_wide=value(cfg,'economic_structural_search',false) && task.kind=="loose_count" && ...
        economic.K_upper-economic.K_lower>cfg.economic_final_interval;
    if ~structural_wide, same=same & [entries.K]==task.K; end
    index=find(same,1,'last');
end
allowed=true;
if ~isempty(index)
    prior=entries(index); gain=value(cfg,'economic_certification_retry_gain',1);
    upper_gain=1; cost_gain=max(1,0.01*(current.fail-economic.reference_upper_usd));
    if structural_wide
        upper_gain=max(5,ceil(0.05*(prior.upper-prior.lower)));
        cost_gain=value(cfg,'economic_local_headroom_usd',3000);
    end
    allowed=current.lower>prior.lower || current.upper<=prior.upper-upper_gain || ...
        current.sat>prior.sat+money_margin(current.sat) || ...
        current.fail<prior.fail-money_margin(current.fail) || ...
        (current.DW_lower>=prior.DW_lower+gain && isfinite(current.DW_lower)) || ...
        current.witness_cost<prior.witness_cost-cost_gain || ...
        current.budget>1.5*prior.budget;
end
if allowed
    if isempty(index), entries(end+1,1)=current; else, entries(index)=current; end
end
end

function [record,schedule]=event_repair(base,economic,ctx,seconds,schedule,checkpoint)
% Fixed integer patterns and annual continuous recovery provide UPPER evidence only.
if nargin<6, checkpoint=[]; end
started=tic; K=economic.K_upper; record=empty_point(K);
record.global_bound=-Inf; record.count_lower=0; record.integer_count=0;
record.proof_model="event_deletion_LP_upper_only";
record.solver_status="no_event_improvement"; record.witnesses=repmat(empty_point(K),0,1);
record.lp_calls=0; record.accepted_events=0;
if ~economic.satisfied_evidence.has_solution || seconds<=0, return; end
original=value(base,'physical_problem',base.problem);
physical=base; physical.problem=original; physical.physical_problem=original;
[x,~,cost,count]=validate_solution(economic.satisfied_evidence.solution,physical,ctx,K);
if isempty(x) || cost>economic.strict_cost_cap_usd, return; end
lp_budget=value(ctx.config,'economic_event_lp_time_s',10);
if value(schedule,'source_K',Inf)~=count || abs(value(schedule,'source_cost',Inf)-cost)>0.01 || ...
        value(schedule,'source_cap',NaN)~=economic.strict_cost_cap_usd
    schedule=struct('tested_hours',[],'retry_hours',[],'next_hours',[],'lp_calls',0,'accepted',0);
end
if value(schedule,'version',0)<2
    schedule.retry_hours=value(schedule,'tested_hours',[]); schedule.tested_hours=[];
    schedule.retry_counts=zeros(ctx.T,1); schedule.version=2;
end
schedule.lp_budget=lp_budget; schedule.status="time_budget";
schedule.source_K=count; schedule.source_cost=cost;
schedule.source_cap=economic.strict_cost_cap_usd;
integers=original.intcon;
if base.grid_exact, integers=setdiff(integers,base.indices.u_purchase(:)); end
z=base.indices.O1_HB_change(:); basis=struct(); near=[]; near_cost=[];
while toc(started)<seconds && count>economic.K_lower
    p=original; p.f=base.cost_f;
    p.bineq(base.update_row)=count*base.update_coefficient;
    p.lb(integers)=round(x(integers)); p.ub(integers)=p.lb(integers);
    p.intcon=[]; model=scaled_model(p,base.units);
    % Solve once to obtain a reusable LP basis, then change only event bounds.
    [~,basis]=continuous_solve(model,min(lp_budget,seconds-toc(started)),ctx,basis);
    record.lp_calls=record.lp_calls+1;
    order=event_candidates(x,base,ctx.T,value(schedule,'tested_hours',[]));
    order=event_attempt_order(order,schedule,value(ctx.config,'economic_event_candidates',24));
    if isempty(order), schedule.status="events_exhausted"; break; end
    best=[]; best_point=empty_point(count); tested=[]; pending=[];
    for hour=order(:).'
        remaining=seconds-toc(started); if remaining<=0, break; end
        trial=model; trial.lb(z(hour))=0; trial.ub(z(hour))=0;
        retry_count=schedule.retry_counts(hour);
        trial_budget=min(value(ctx.config,'economic_event_retry_max_s',20),lp_budget*2^min(3,retry_count));
        [candidate,~,status]=continuous_solve(trial,min(trial_budget,remaining),ctx,basis);
        record.lp_calls=record.lp_calls+1;
        if isempty(candidate)
            if event_attempt_terminal(status,false), tested(end+1)=hour; ...
            else, pending(end+1)=hour; schedule.retry_counts(hour)=retry_count+1; end %#ok<AGROW>
            continue
        end
        candidate=normalize_grid(candidate.*base.units,base);
        candidate(original.intcon)=round(candidate(original.intcon));
        [valid,solution,trial_cost,trial_count,residual]= ...
            validate_solution(vector_solution(candidate,base.indices),physical,ctx,count-1);
        if isempty(valid)
            pending(end+1)=hour; schedule.retry_counts(hour)=retry_count+1; continue %#ok<AGROW>
        end
        if event_attempt_terminal(status,true), tested(end+1)=hour; ...
        else, pending(end+1)=hour; schedule.retry_counts(hour)=retry_count+1; end %#ok<AGROW>
        near(end+1)=hour; near_cost(end+1)=trial_cost; %#ok<AGROW>
        if trial_cost<=economic.strict_cost_cap_usd-money_margin(economic.strict_cost_cap_usd) && ...
                (isempty(best) || trial_count<best_point.K || ...
                (trial_count==best_point.K && trial_cost<best_point.cost_upper_usd))
            best=valid; best_point=empty_point(trial_count);
            best_point.has_incumbent=true; best_point.solution=solution;
            best_point.count_upper=trial_count; best_point.cost_upper_usd=trial_cost;
            best_point.matrix_violation=residual; best_point.solver_status=status;
            best_point.source="event_deletion_annual_LP_witness";
        end
    end
    schedule.tested_hours=union(value(schedule,'tested_hours',[]),tested);
    schedule.retry_hours=setdiff(unique([value(schedule,'retry_hours',[]),pending]), ...
        schedule.tested_hours,'stable');
    if isempty(best), schedule.status="no_accepted_event_in_batch"; break; end
    x=best; count=best_point.K; cost=best_point.cost_upper_usd;
    record.witnesses(end+1,1)=best_point; record.accepted_events=record.accepted_events+1;
    schedule.tested_hours=[]; schedule.retry_hours=[]; schedule.retry_counts=zeros(ctx.T,1);
    schedule.status="accepted_event";
    if ~isempty(checkpoint), checkpoint(best_point); end
    fprintf('[O1] 事件LP接受K=%g：成本%.3f USD，严格余量%.3f USD。\n', ...
        count,cost,economic.strict_cost_cap_usd-cost);
end
if ~isempty(record.witnesses)
    point=record.witnesses(end); record.has_incumbent=true; record.solution=point.solution;
    record.cost_upper_usd=point.cost_upper_usd; record.count_upper=point.count_upper;
    record.matrix_violation=point.matrix_violation; record.solver_status="validated_event_witness";
end
[~,order]=sort(near_cost); schedule.next_hours=unique(near(order),'stable');
schedule.next_hours=schedule.next_hours(x(z(schedule.next_hours))>0.5);
schedule.next_hours=schedule.next_hours(1:min(12,numel(schedule.next_hours)));
schedule.source_K=count; schedule.source_cost=cost;
schedule.lp_calls=value(schedule,'lp_calls',0)+record.lp_calls;
schedule.accepted=value(schedule,'accepted',0)+record.accepted_events;
record.elapsed_s=toc(started);
end

function terminal=event_attempt_terminal(status,has_valid_candidate)
terminal=string(status)=="INFEASIBLE" || (string(status)=="OPTIMAL" && has_valid_candidate);
end

function selected=event_attempt_order(order,schedule,limit)
% Interleave retry and fresh events so expensive retries cannot starve exploration.
pending=intersect(value(schedule,'retry_hours',[]),order,'stable');
retry=pending(1:min(numel(pending),max(1,floor(limit/2))));
fresh=setdiff(order,pending,'stable'); fresh=fresh(1:min(numel(fresh),limit-numel(retry)));
selected=[];
for j=1:max(numel(retry),numel(fresh))
    if j<=numel(retry), selected(end+1)=retry(j); end %#ok<AGROW>
    if j<=numel(fresh), selected(end+1)=fresh(j); end %#ok<AGROW>
end
remaining=setdiff(order,selected,'stable');
selected=[selected,reshape(remaining(1:min(numel(remaining),limit-numel(selected))),1,[])];
end

function order=event_candidates(x,base,T,excluded)
z=x(base.indices.O1_HB_change(:)); order=setdiff(find(z>0.5),excluded,'stable');
if isfield(base.indices,'O1_HB_setpoint')
    s=x(base.indices.O1_HB_setpoint(:)); amplitude=abs(s([2:T,1])-s);
    [~,rank]=sort(amplitude(order)); order=order(rank);
end
end

function [x,basis,status]=continuous_solve(model,seconds,ctx,basis)
x=[]; status="TIME_LIMIT";
if seconds<=0, return; end
if strcmp(ctx.config.economics_solver,'gurobi')
    if isfield(basis,'vbasis') && numel(basis.vbasis)==numel(model.obj) && ...
            numel(basis.cbasis)==numel(model.rhs)
        model.vbasis=basis.vbasis; model.cbasis=basis.cbasis;
    end
    params=struct('OutputFlag',0,'Threads',ctx.config.gurobi_threads,'TimeLimit',seconds, ...
        'Method',1,'LPWarmStart',2,'DualReductions',0, ...
        'FeasibilityTol',solver_tolerance(ctx),'OptimalityTol',solver_tolerance(ctx));
    raw=gurobi(model,params); status=string(raw.status);
    if isfield(raw,'x') && all(isfinite(raw.x)) && ...
            decomposition_violation(model,raw.x)<=solver_tolerance(ctx)
        x=raw.x(:);
    end
    if isfield(raw,'vbasis'), basis=struct('vbasis',raw.vbasis,'cbasis',raw.cbasis); end
else
    opts=optimoptions('linprog','Display','none','MaxTime',seconds, ...
        'ConstraintTolerance',solver_tolerance(ctx),'OptimalityTolerance',solver_tolerance(ctx));
    [candidate,~,flag]=linprog(model.obj,model.A(model.sense=='<',:),model.rhs(model.sense=='<'), ...
        model.A(model.sense=='=',:),model.rhs(model.sense=='='),model.lb,model.ub,opts);
    if flag==-2, status="INFEASIBLE"; end
    if ~isempty(candidate) && decomposition_violation(model,candidate)<=solver_tolerance(ctx)
        x=candidate; if flag>0, status="OPTIMAL"; end
    end
end
end

function record=polish_witness(base,economic,ctx,seconds)
started=tic; K=economic.K_upper; record=empty_point(K);
record.count_lower=0; record.witnesses=repmat(empty_point(K),0,1);
record.global_bound=-Inf; record.proof_model="fixed_integer_LP_upper_only";
record.integer_count=0; record.solver_status="no_primal_improvement";
x=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
p=value(base,'physical_problem',base.problem); p.bineq(base.update_row)=K*base.update_coefficient;
candidate=polish_candidate(p,x,base,seconds,economic.strict_cost_cap_usd,ctx);
if ~isempty(candidate)
    [valid,solution,cost,count,residual]=validate_solution(vector_solution(candidate,base.indices),base,ctx,K);
    if ~isempty(valid) && cost<=economic.strict_cost_cap_usd
        record.has_incumbent=true; record.solution=solution; record.cost_upper_usd=cost;
        record.count_upper=count; record.matrix_violation=residual; record.solver_status="validated_primal";
        witness=empty_point(count); witness.has_incumbent=true; witness.solution=solution;
        witness.cost_upper_usd=cost; witness.count_upper=count; witness.matrix_violation=residual;
        record.witnesses=witness;
    end
end
record.elapsed_s=toc(started);
end

function record = solve_task(base,task,ctx)
started = tic;
p = base.problem;
is_local = task.kind == "local_count" || task.kind == "local_cost";
if is_local, p=value(base,'physical_problem',p); end
if ~is_local && isfield(base,'cut_all')
    [p,used]=annual_cut_pool(base,task.start,value(ctx.config,'economic_annual_cut_limit',256));
    fprintf('[O1] 全年认证割池：使用%d/%d条数值安全割。\n',used,numel(base.cut_all));
end
p.bineq(base.update_row) = task.K*base.update_coefficient;
is_count = task.kind == "loose_count" || task.kind == "strict_count" || task.kind=="local_count";
if is_count
    p.f = base.count_f;
    p.Aineq = [p.Aineq;base.cost_f.';-base.count_f.'];
    p.bineq = [p.bineq(:);task.cap-base.offset;-task.K_lower];
    offset = 0;
else
    p.f = base.cost_f;
    offset = base.offset;
    if task.kind=="local_cost"
        p.Aineq=[p.Aineq;base.cost_f.']; p.bineq=[p.bineq(:);task.cap-base.offset];
    end
end
if is_local
    if isempty(task.start) || any(~isfinite(task.start))
        error('O1:invalid_local_start','局部压缩需要完整的原模型可行调度。');
    end
    p=bounded_local_problem(p,base,task.start,task.event_hours,task.ael_hours,ctx.T);
    if ~isempty(task.event_hours)
        z=base.indices.O1_HB_change(task.event_hours); old=round(task.start(z));
        row=sparse(ones(numel(z),1),z(:),1-2*old(:),1,numel(p.lb));
        p.Aineq=[p.Aineq;row];
        p.bineq=[p.bineq;ctx.config.economic_event_exchange_radius-sum(old)];
    end
end
% 两次LP都占用本阶段预算；为返回候选的成本抛光预留时间。
lp_budget = min(ctx.config.economic_lp_time_s,task.time_limit/10);
repair_start=task.start;
[p.x0,start_candidate] = prepare_start(p,repair_start,base,lp_budget,task.cap,ctx);
solver_task = task;
solver_task.time_limit = max(0.01,task.time_limit-toc(started)-lp_budget);
[solver_p,proof_model] = proof_problem(p,base,task,ctx);
if is_local, proof_model = "local_restriction_upper_bound_only"; end
free_integers = sum(solver_p.lb(solver_p.intcon) < solver_p.ub(solver_p.intcon));
solver_units=base.units; map=[];
if is_local
    assert(free_integers<=ctx.config.economic_local_integer_limit, ...
        'O1:large_local_search','Small integer search exceeded its configured limit.');
    [solver_p,map,solver_units]=reduce_local_problem(solver_p,base);
    offset=offset+map.objective_constant;
    fprintf('[O1] 精确消元：%d -> %d变量，HB设定值合并%d个；保留全年物理约束。\n', ...
        numel(p.lb),numel(solver_p.lb),map.merged_setpoints);
end
fprintf('[O1] %s：未固定整数=%d/%d，原模型核验保留。\n', ...
    proof_model,free_integers,numel(p.intcon));
if strcmp(ctx.config.economics_solver,'gurobi')
    result = gurobi_solve(solver_p,solver_units,solver_task,offset,ctx);
else
    result = matlab_solve(solver_p,solver_task,offset,ctx);
end
if is_local && ~isempty(result.x), result.x=map.offset+map.G*result.x; end
record = empty_point(task.K);
record.count_upper = Inf;
record.attempts = task.attempt;
record.solver_status = result.status;
record.is_infeasible = result.status == "INFEASIBLE";
record.count_lower = 0;
record.witnesses = repmat(empty_point(task.K),0,1);
record.proof_model = proof_model;
record.integer_count = free_integers;
record.global_bound = result.bound;
if isfinite(result.bound) && ~is_local
    if is_count
        record.count_lower = max(0,ceil(result.bound-1e-7));
    else
        record.cost_lower_usd = result.bound+offset;
    end
end
if is_local
    record.global_bound = -Inf;
    record.is_infeasible = false; % 局部限制的不可行性不提供任何全年拒绝证据。
end
for candidate_cell = {start_candidate,result.x}
    candidate = candidate_cell{1};
    if isempty(candidate), continue; end
    candidate = normalize_grid(candidate,base);
    candidate(p.intcon) = round(candidate(p.intcon));
    % 计数目标不控制连续变量成本；即使满足宽松帽，也要尝试成本抛光。
    if ~isequal(candidate,start_candidate)
        repair_time = min(ctx.config.economic_lp_time_s,task.time_limit-toc(started));
        if repair_time > 0 && (is_count || ...
                matrix_violation(p,candidate) > ctx.model.options.ConstraintTolerance)
            polished = polish_candidate(p,candidate,base,repair_time,task.cap,ctx);
            if ~isempty(polished) && (matrix_violation(p,candidate) > ...
                    ctx.model.options.ConstraintTolerance || ...
                    base.cost_f.'*polished <= base.cost_f.'*candidate)
                fprintf('[O1] 候选LP成本抛光：%.3f -> %.3f USD。\n', ...
                    base.cost_f.'*candidate+base.offset,base.cost_f.'*polished+base.offset);
                candidate = polished;
            end
        end
    end
    if matrix_violation(p,candidate) <= ctx.model.options.ConstraintTolerance
        solution = vector_solution(candidate,base.indices);
        [x,solution,cost,count,residual] = validate_solution(solution,base,ctx,task.K);
        if ~isempty(x) && (~is_count || cost <= task.cap)
            witness = empty_point(count);
            witness.has_incumbent = true;
            witness.solution = solution;
            witness.cost_upper_usd = cost;
            witness.count_upper = count;
            witness.matrix_violation = residual;
            record.witnesses(end+1,1) = witness;
            if ~record.has_incumbent || (is_count && count < record.count_upper) || ...
                    ((~is_count || count == record.count_upper) && cost < record.cost_upper_usd)
                record.has_incumbent = true;
                record.solution = solution;
                record.cost_upper_usd = cost;
                record.count_upper = count;
                record.matrix_violation = residual;
            end
        end
    end
end
record.elapsed_s = toc(started);
if record.is_infeasible && record.has_incumbent
    error('O1:inconsistent_solver_status','求解器不可行状态与已验证可行解矛盾。');
end
end

function [p,kind] = proof_problem(p,base,task,ctx)
kind = "original_economic";
if base.grid_exact
    p.intcon = setdiff(p.intcon,base.indices.u_purchase(:));
    kind = "grid_equivalent";
end
if task.kind == "loose_count" && ...
        strcmp(value(ctx.config,'economic_proof_mode','full'),'hb_only')
    % 只放松AEL台数和启停方向，不删除其物理约束；可行域包含原模型。
    for name = {'n_ael','I_AEL_up'}
        if isfield(base.indices,name{1})
            p.intcon = setdiff(p.intcon,base.indices.(name{1})(:));
        end
    end
    kind = "HB_integer_lower_bound";
end
end

function yes = grid_simplification_guard(base,cfg)
% 逐列验证净额抵消：等式不变、非方向不等式只改善、成本不增加。
% 不依赖当前价格硬编码；未知耦合或价格倒挂时自动回退完整模型。
yes = false;
if ~value(cfg,'economic_grid_simplify',false), return; end
ind = base.indices; p = base.problem;
if ~all(isfield(ind,{'p_purchase','p_sell','u_purchase'})), return; end
b = ind.p_purchase(:); s = ind.p_sell(:); u = ind.u_purchase(:);
if numel(b) ~= numel(s) || numel(b) ~= numel(u) || ...
        any(p.lb([b;s]) ~= 0) || any(p.lb(u) ~= 0) || any(p.ub(u) ~= 1) || ...
        any(base.cost_f(u) ~= 0) || any(base.cost_f(b)+base.cost_f(s) < 0) || ...
        nnz(p.Aeq(:,u)) ~= 0 || nnz(p.Aeq(:,b)+p.Aeq(:,s)) ~= 0
    return
end
direction = find(any(p.Aineq(:,u),2));
if numel(direction) ~= 2*numel(u), return; end
for t = 1:numel(u)
    rows = find(p.Aineq(:,u(t)));
    if numel(rows) ~= 2, return; end
    buy_row = rows(p.Aineq(rows,u(t)) < 0);
    sell_row = rows(p.Aineq(rows,u(t)) > 0);
    if numel(buy_row) ~= 1 || numel(sell_row) ~= 1 || ...
            nnz(p.Aineq(buy_row,:)) ~= 2 || nnz(p.Aineq(sell_row,:)) ~= 2 || ...
            p.Aineq(buy_row,b(t)) <= 0 || p.Aineq(sell_row,s(t)) <= 0 || ...
            p.bineq(buy_row) ~= 0 || p.bineq(sell_row) ~= p.Aineq(sell_row,u(t))
        return
    end
end
remaining = true(size(p.bineq)); remaining(direction) = false;
pair = p.Aineq(remaining,b)+p.Aineq(remaining,s);
if any(nonzeros(pair) < 0), return; end
yes = true;
end

function x = normalize_grid(x,base)
if ~base.grid_exact || isempty(x), return; end
b = base.indices.p_purchase(:); s = base.indices.p_sell(:);
common = min(x(b),x(s));
x(b) = x(b)-common; x(s) = x(s)-common;
x(base.indices.u_purchase(:)) = double(x(b) > 0);
end

function cuts = empty_cuts()
cuts = struct('columns',{},'coefficients',{},'lower_bound',{}, ...
    'start_hour',{},'length_h',{},'solver_status',{},'elapsed_s',{});
end

function hours=event_exchange_hours(x,base,T,schedule,cfg)
z=x(base.indices.O1_HB_change(:)); order=event_candidates(x,base,T,[]);
if isempty(order), hours=[]; return; end
limit=value(cfg,'economic_event_exchange_old',64);
cursor=value(schedule,'exchange_cursor',0);
order=order(1+mod(cursor+(0:numel(order)-1),numel(order)));
near=intersect(value(schedule,'next_hours',[]),order,'stable');
near=near(1:min(numel(near),floor(limit/4)));
old=unique([near(:);order(:)],'stable'); old=old(1:min(limit,numel(old)));
offsets=value(cfg,'economic_event_exchange_offsets',[-12,-6,-3,-1,1,3,6,12]);
[~,rank]=sort(abs(offsets)); offsets=offsets(rank);
neighbors=1+mod(old(:)-1+offsets(:).',T);
% Visit every old event at the nearest offset before expanding the distance.
neighbors=unique(neighbors(:),'stable');
fresh=neighbors(z(neighbors)<0.5);
fresh=fresh(1:min(numel(fresh),value(cfg,'economic_event_exchange_new',64)));
hours=unique([old(:);fresh(:)],'stable');
end

function fractional=decomposition_fractional(blocks,which,weights,base)
x=zeros(numel(base.count_f),1);
for b=1:numel(blocks), x(blocks{b}.col)=blocks{b}.points*weights(which==b); end
ii=base.physical_problem.intcon;
if base.grid_exact, ii=setdiff(ii,base.indices.u_purchase(:)); end
gap=abs(x(ii)-round(x(ii))); ii=ii(gap>1e-6); gap=gap(gap>1e-6);
[~,rank]=sort(gap,'descend'); ii=ii(rank(1:min(64,numel(rank))));
fractional=struct('columns',ii(:),'values',x(ii));
end

function allowed=branch_can_run(proof,d,economic,cfg,base)
allowed=false;
if ~value(cfg,'economic_branch_enable',false) || ~isfinite(economic.K_upper), return; end
if isfield(proof,'nodes') && ~isempty(proof.nodes) && proof.bound_cap_usd>=economic.cost_cap_usd && ...
        branch_context_valid(proof.certificate,base)
    allowed=true; return;
end
c=value(d,'certificate',struct()); f=value(d,'fractional',struct());
allowed=value(c,'complete',false) && isfinite(value(c,'master_upper',Inf)) && ...
    c.master_upper-c.lower<=cfg.economic_branch_relaxation_gap && ...
    economic.K_upper-economic.K_lower>cfg.economic_branch_min_interval && ...
    ~isempty(value(f,'columns',[])) && c.cap_usd>=economic.cost_cap_usd && branch_context_valid(c,base);
end

function valid=branch_context_valid(c,base)
valid=value(c,'cut_policy',0)==value(base,'cut_policy',2) && ...
    value(c,'cut_margin',Inf)==value(base,'cut_margin',1e-5) && ...
    value(c,'cut_relative_margin',Inf)==value(base,'cut_relative_margin',1e-9) && ...
    isequal(value(c,'cut_disabled',[]),value(base,'cut_disabled',[])) && ...
    isequal(value(c,'units',[]),base.units) && value(c,'grid_exact',~base.grid_exact)==base.grid_exact;
end

function lower=branch_cover_lower(nodes,baseline,upper)
% The open nodes cover every unexcluded integer schedule. Use their MINIMUM.
if isempty(nodes), lower=upper; else, lower=min(upper,min([nodes.bound])); end
lower=max(baseline,lower);
end

function [proof,record]=branch_pricing(base,state,economic,ctx,seconds,checkpoint)
% Disjunctive pricing at a frozen dual; no restricted branch bound is global alone.
started=tic; cfg=ctx.config; d=state.decomposition; proof=value(state,'branch',struct());
record=empty_point(economic.K_upper); record.count_upper=Inf; record.solve_calls=0;
record.count_lower=0; record.global_bound=-Inf; record.witnesses=repmat(empty_point(0),0,1);
record.proof_model="complete_integer_branch_pricing"; record.integer_count=0;
compatible=isfield(proof,'nodes') && proof.bound_cap_usd>=economic.cost_cap_usd && ...
    proof.certificate.K_upper>=economic.K_upper && ...
    branch_context_valid(proof.certificate,base) && ...
    proof.certificate.cut_count<=numel(state.block_cuts);
if ~compatible
    c=d.certificate;
    assert(c.complete && ~isempty(d.fractional.columns),'O1:invalid_branch_root','No complete branch root certificate.');
    node=struct('id',1,'columns',[],'lower',[],'upper',[],'block_lower',c.block_lower, ...
        'bound',max(economic.K_lower,ceil(c.lower-1e-5)),'pending',0,'status',"root");
    proof=struct('certificate',c,'bound_cap_usd',economic.cost_cap_usd,'baseline',node.bound, ...
        'candidates',d.fractional,'nodes',node,'next_id',2,'closed_by_bound',0, ...
        'global_lower',node.bound,'status',"initialized");
end
c=proof.certificate; working=apply_block_cuts(base,state.block_cuts(1:c.cut_count));
p=working.problem; p.f=base.count_f; p.bineq(base.update_row)=c.K_upper*base.update_coefficient;
extra=base.cost_f.'; extra_rhs=c.cap_usd-base.offset; global_ids=-1;
if c.count_floor>0, extra=[extra;-base.count_f.']; extra_rhs=[extra_rhs;-c.count_floor]; global_ids=[-1;-2]; end
p.Aineq=[p.Aineq;extra]; p.bineq=[p.bineq;extra_rhs];
mi=size(base.physical_problem.Aineq,1); me=size(base.physical_problem.Aeq,1);
ids=[(1:mi).';mi+me+(1:c.cut_count).';global_ids;mi+(1:me).'];
[model,scale]=scaled_model(p,base.units); model.vtype(p.intcon)='I';
if base.grid_exact, model.vtype(base.indices.u_purchase(:))='C'; end
seed=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(p.lb));
partition=d; partition.ranges=c.ranges;
[blocks,link,ids,partition]=decomposition_partition(model,base,partition,seed,c.cut_count,ctx.T,ctx,scale,ids);
assert(isequal(ids,c.link_ids) && max(abs(model.rhs(link)-c.rhs))<1e-8, ...
    'O1:branch_context_changed','Frozen branch pricing context changed.');
A=model.A(link,:); touched=[]; proof.status="time_budget";
while toc(started)<seconds && record.solve_calls<value(cfg,'economic_decomposition_solve_limit',Inf)
    closed=[proof.nodes.bound]>=economic.K_upper;
    proof.closed_by_bound=proof.closed_by_bound+nnz(closed); proof.nodes(closed)=[];
    if isempty(proof.nodes)
        assert(proof.closed_by_bound>0,'O1:empty_branch_cover','Infeasible branch cover contradicts the annual witness.');
        proof.global_lower=economic.K_upper; proof.status="certified_boundary"; checkpoint(proof); break;
    end
    proof.global_lower=branch_cover_lower(proof.nodes,proof.baseline,economic.K_upper);
    pending=find([proof.nodes.pending]>0); ready=find([proof.nodes.pending]==0);
    if ~isempty(pending)
        calls=arrayfun(@(j) nnz(touched==proof.nodes(j).id),pending);
        [fewest,k]=min(calls); if fewest>=2, proof.status="unknown_pricing_retryable"; break; end
        j=pending(k); node=proof.nodes(j); b=node.pending; q=blocks{b}.model;
        q.obj=model.obj(blocks{b}.col)-A(:,blocks{b}.col).'*c.pi;
        [found,where]=ismember(node.columns,blocks{b}.col);
        for k=find(found)
            q.lb(where(k))=max(q.lb(where(k)),node.lower(k)/base.units(node.columns(k)));
            q.ub(where(k))=min(q.ub(where(k)),node.upper(k)/base.units(node.columns(k)));
        end
        known=partition.points{b}./base.units(blocks{b}.col);
        good=all(known>=q.lb-1e-10 & known<=q.ub+1e-10,1); q.start=[];
        if any(good), known=known(:,good); [~,k]=min(q.obj.'*known); q.start=known(:,k); end
        [lower,~,status]=decomposition_price(q,min(cfg.economic_branch_price_time_s,seconds-toc(started)),ctx);
        record.solve_calls=record.solve_calls+1; touched(end+1)=node.id; %#ok<AGROW>
        if status=="INFEASIBLE"
            proof.nodes(j)=[];
        elseif isfinite(lower)
            node.block_lower(b)=max(node.block_lower(b),lower);
            constant=c.rhs.'*c.pi;
            margin=decomposition_margin(constant)+sum(arrayfun(@decomposition_margin,node.block_lower));
            node.bound=max(node.bound,ceil(constant+sum(node.block_lower)-margin-1e-5));
            node.pending=0; node.status=status; proof.nodes(j)=node;
        end
    else
        if numel(proof.nodes)>=cfg.economic_branch_max_nodes, proof.status="node_limit"; break; end
        [~,k]=min([proof.nodes(ready).bound]); j=ready(k); node=proof.nodes(j);
        available=find(~ismember(proof.candidates.columns,node.columns),1);
        if isempty(available), proof.status="candidate_partition_exhausted"; break; end
        column=proof.candidates.columns(available); value_=proof.candidates.values(available);
        b=find(cellfun(@(block) ismember(column,block.col),blocks),1);
        child=repmat(node,1,2);
        for k=1:2
            child(k).id=proof.next_id; proof.next_id=proof.next_id+1;
            child(k).columns(end+1)=column;
            child(k).lower(end+1)=base.physical_problem.lb(column);
            child(k).upper(end+1)=base.physical_problem.ub(column);
            if k==1, child(k).upper(end)=floor(value_); else, child(k).lower(end)=ceil(value_); end
            child(k).pending=b; child(k).status="unpriced";
        end
        proof.nodes(j)=[]; proof.nodes=[proof.nodes,child];
    end
    if ~isempty(proof.nodes)
        proof.global_lower=branch_cover_lower(proof.nodes,proof.baseline,economic.K_upper);
        checkpoint(proof);
    end
end
record.global_bound=proof.global_lower; record.count_lower=proof.global_lower;
record.solver_status=proof.status; record.elapsed_s=toc(started);
fprintf('[O1] 分支定价认证：保留%d节点，完整覆盖下界=%g；状态=%s。\n', ...
    numel(proof.nodes),proof.global_lower,proof.status);
end

function p=bounded_local_problem(p,base,start,event_hours,ael_hours,T)
free=base.indices.O1_HB_change(event_hours); free=free(:);
hours=variable_hours(base,T);
for name={'n_ael','I_AEL_up'}
    if isfield(base.indices,name{1})
        index=base.indices.(name{1})(:);
        free=[free;index(ismember(hours(index),ael_hours))]; %#ok<AGROW>
    end
end
fixed=setdiff(p.intcon,free);
if base.grid_exact, fixed=setdiff(fixed,base.indices.u_purchase(:)); end
p.lb(fixed)=round(start(fixed)); p.ub(fixed)=p.lb(fixed);
end

function [reduced,map,units]=reduce_local_problem(p,base)
% Exact x=offset+G*y substitution, including cyclic equal-setpoint chains.
n=numel(p.lb); representative=(1:n).'; merged=0;
if isfield(base.indices,'O1_HB_setpoint')
    s=base.indices.O1_HB_setpoint(:); z=base.indices.O1_HB_change(:); T=numel(s);
    parent=(1:T).';
    for t=find(p.lb(z)==0 & p.ub(z)==0).'
        a=t; b=1+mod(t,T);
        while parent(a)~=a, a=parent(a); end
        while parent(b)~=b, b=parent(b); end
        if a~=b, parent(b)=a; merged=merged+1; end
    end
    for t=1:T
        a=t; while parent(a)~=a, a=parent(a); end
        representative(s(t))=s(a);
    end
end
[~,first,group]=unique(representative); B=numel(first);
lower=accumarray(group,p.lb,[B,1],@max); upper=accumarray(group,p.ub,[B,1],@min);
fixed=lower==upper & isfinite(lower); available=find(~fixed);
where=zeros(B,1); where(available)=(1:numel(available)).';
rows=find(~fixed(group)); G=sparse(rows,where(group(rows)),1,n,numel(available));
offset=zeros(n,1); offset(fixed(group))=lower(group(fixed(group)));
reduced=struct('Aineq',p.Aineq*G,'bineq',p.bineq-p.Aineq*offset, ...
    'Aeq',p.Aeq*G,'beq',p.beq-p.Aeq*offset,'f',G.'*p.f, ...
    'lb',lower(available),'ub',upper(available),'intcon',[],'x0',[]);
ii=where(group(p.intcon)); reduced.intcon=unique(ii(ii>0));
if ~isempty(p.x0)
    initial=accumarray(group,p.x0(:),[B,1],@mean);
    reduced.x0=initial(available);
end
keep=any(reduced.Aineq,2) | reduced.bineq<0;
reduced.Aineq=reduced.Aineq(keep,:); reduced.bineq=reduced.bineq(keep);
keep=any(reduced.Aeq,2) | reduced.beq~=0;
reduced.Aeq=reduced.Aeq(keep,:); reduced.beq=reduced.beq(keep);
units=base.units(first(available));
map=struct('G',G,'offset',offset,'objective_constant',p.f.'*offset, ...
    'merged_setpoints',merged);
end

function base = apply_block_cuts(base,cuts)
if nargin<2, cuts=empty_cuts(); end
p = base.physical_problem;
n = numel(p.lb); rhs = zeros(numel(cuts),1);
row_index = cell(numel(cuts),1); column_index = row_index; coefficients = row_index;
for j = 1:numel(cuts)
    row_index{j} = repmat(j,numel(cuts(j).columns),1);
    column_index{j} = cuts(j).columns(:);
    coefficients{j} = -full(cuts(j).coefficients(:));
    rhs(j) = -cuts(j).lower_bound+cut_numeric_margin(cuts(j),base);
    if ismember(j,value(base,'cut_disabled',[]))
        coefficients{j}(:)=0; rhs(j)=0; % Keep frozen row identifiers stable.
    end
end
rows = sparse(vertcat(row_index{:}),vertcat(column_index{:}), ...
    vertcat(coefficients{:}),numel(cuts),n);
p.Aineq = [p.Aineq;rows]; p.bineq = [p.bineq(:);rhs];
base.problem = p;
base.cut_all = cuts;
end

function [p,used]=annual_cut_pool(base,seed,limit)
cuts=base.cut_all; available=setdiff(1:numel(cuts),value(base,'cut_disabled',[]),'stable');
if numel(available)>limit
    score=Inf(numel(available),1);
    if ~isempty(seed) && all(isfinite(seed))
        for j=1:numel(available)
            cut=cuts(available(j));
            scale=max(1,sum(abs(full(cut.coefficients(:))).*base.units(cut.columns(:))));
            score(j)=(full(cut.coefficients)*seed(cut.columns)-cut.lower_bound)/scale;
        end
    end
    [~,rank]=sort(score); tight=available(rank(1:floor(0.75*limit)));
    recent=fliplr(setdiff(available,tight,'stable'));
    available=[tight,recent(1:limit-numel(tight))];
end
working=base; working.cut_disabled=[];
working=apply_block_cuts(working,cuts(available)); p=working.problem; used=numel(available);
end

function margin=cut_numeric_margin(cut,base)
% Relax outwards in physical units; never tighten a saved pricing bound.
units=value(base,'units',ones(numel(base.physical_problem.lb),1));
weight=sum(abs(full(cut.coefficients(:))).*units(cut.columns(:)));
margin=value(base,'cut_margin',1e-5)+value(base,'cut_relative_margin',1e-9)* ...
    (abs(cut.lower_bound)+weight);
end

function [base,report]=audit_block_cuts(base,cuts,state,reference,ctx)
p=base.physical_problem; p.bineq(base.update_row)=ctx.T*base.update_coefficient;
seeds=solution_vector(base.indices,reference.solution,numel(p.lb));
points=value(state,'points',[]);
if ~isempty(points)
    [~,order]=sort([points.cost_upper_usd]);
    sat=reference.objective_lower+ctx.config.economic_delta_usd_t*ctx.config.nh3_target_t;
    accepted=find([points.has_incumbent] & [points.cost_upper_usd]<=sat);
    [~,rank]=sort([points(accepted).K]); accepted=accepted(rank(1:min(2,numel(rank))));
    selected=unique([accepted,order(1:min(4,numel(order)))],'stable');
    for j=selected
        x=solution_vector(base.indices,points(j).solution,numel(p.lb));
        if ~isempty(x), seeds(:,end+1)=x; end %#ok<AGROW>
    end
end
good=false(1,size(seeds,2));
for j=1:size(seeds,2)
    good(j)=matrix_violation(p,seeds(:,j))<=ctx.model.options.ConstraintTolerance && ...
        max([0;abs(seeds(p.intcon,j)-round(seeds(p.intcon,j)))])<=1e-6;
end
seeds=seeds(:,good); disabled=[]; maximum=0;
for j=1:numel(cuts)
    if isempty(seeds), break; end
    violation=max(cuts(j).lower_bound-full(cuts(j).coefficients)*seeds(cuts(j).columns,:));
    maximum=max(maximum,violation);
    if violation>cut_numeric_margin(cuts(j),base), disabled(end+1)=j; end %#ok<AGROW>
end
base.cut_disabled=disabled; base.cut_witnesses=seeds;
report=struct('policy',base.cut_policy,'cuts',numel(cuts),'witnesses',size(seeds,2), ...
    'disabled',disabled,'maximum_raw_violation',maximum);
fprintf('[O1] 派生割数值审计：%d条，%d个原模型见证，最大原割违反量%.3g，隔离%d条。\n', ...
    numel(cuts),size(seeds,2),maximum,numel(disabled));
end

function state=invalidate_cut_dependent_bounds(state)
for j=1:numel(state.caps), state.caps(j).count_lower=0; state.caps(j).is_infeasible=false; end
for j=1:numel(state.points)
    if state.points(j).source=="fixed_K_global_cost"
        state.points(j).cost_lower_usd=-Inf; state.points(j).is_infeasible=false;
    end
end
state.decomposition=struct(); state.branch=struct(); state.cert_schedule=empty_cert_schedule();
fprintf('[O1] 数值冲突割已隔离：相关旧下界需重新认证，保留原模型可行解。\n');
end

function hours = variable_hours(base,T)
hours = value(base,'variable_hour',zeros(numel(base.cost_f),1));
if any(hours), return; end
for name = fieldnames(base.indices).'
    index = base.indices.(name{1})(:);
    if numel(index) == T || strcmp(name{1},'storage_H2') && numel(index) == T+1
        hours(index) = (1:numel(index)).';
    end
end
end

function allowed=decomposition_can_run(d,economic,cfg)
allowed=true;
if ~isfield(d,'park') || isempty(fieldnames(d.park)) || value(d,'algorithm_version',0)~=6, return; end
p=d.park;
allowed=economic.K_lower~=p.K_lower || economic.K_upper~=p.K_upper || ...
    economic.cost_cap_usd~=p.cap_usd || ...
    value(cfg,'economic_block_max_time_s',60)>p.price_max_s || ...
    cfg.economic_block_round_time_s>1.5*p.round_time_s || ...
    max(cfg.economic_block_lengths_h)>p.max_length_h;
end

function floor=decomposition_floor(economic)
% Use a global count certificate for a cost cap containing the current cap.
% Kfea, local restrictions and the RMP objective are not such certificates.
floor=0; proof=value(economic,'rejected_evidence',struct());
candidate=value(proof,'count_lower',NaN);
if value(proof,'source',"")=="loose_cap_global_count_bound" && ...
        value(proof,'cost_cap_usd',-Inf)>=economic.cost_cap_usd && ...
        isfinite(candidate) && candidate>=0 && candidate==round(candidate) && candidate<=economic.K_lower
    floor=candidate;
end
end

function count=decomposition_completed(d)
history=value(d,'history',[]); count=0;
if isstruct(history) && isfield(history,'complete'), count=nnz([history.complete]); end
end

function [frozen,d,resumed]=decomposition_context(d,economic,base,~,cut_count)
% A completed frozen dual certificate remains valid after the current
% economic feasible domain shrinks. Never change its rhs during pricing.
if nargin<5, cut_count=value(base,'cut_count',0); end
floor=decomposition_floor(economic); sweep=value(d,'sweep',struct());
required={'next_block','cap_usd','K_upper','ranges','cut_count','units','grid_exact'};
resumed=all(isfield(sweep,required));
if resumed
    resumed=sweep.next_block>0 && sweep.cap_usd>=economic.cost_cap_usd && ...
        sweep.K_upper>=economic.K_upper && value(sweep,'count_floor',0)<=floor && ...
        isequal(sweep.ranges,d.ranges) && sweep.cut_count<=cut_count && ...
        isequal(sweep.units,base.units) && sweep.grid_exact==base.grid_exact && ...
        decomposition_floor_valid(sweep) && branch_context_valid(sweep,base);
    if resumed && sweep.cut_count>0 && isfield(sweep,'cut_prefix')
        cuts=value(base,'cut_prefix',[]);
        resumed=numel(cuts)>=sweep.cut_count && isequal(sweep.cut_prefix,cuts(1:sweep.cut_count));
    end
end
if resumed
    if ~isfield(sweep,'count_floor'), sweep.count_floor=0; end
    if ~isfield(sweep,'cut_prefix') && isfield(base,'cut_prefix')
        sweep.cut_prefix=base.cut_prefix(1:sweep.cut_count);
    end
    d.sweep=sweep;
    frozen=struct('cap_usd',sweep.cap_usd,'K_upper',sweep.K_upper, ...
        'count_floor',sweep.count_floor,'cut_count',sweep.cut_count);
else
    frozen=struct('cap_usd',economic.cost_cap_usd,'K_upper',economic.K_upper, ...
        'count_floor',floor,'cut_count',cut_count);
    % Keep the economic dual center when the external integer floor improves.
    d.sweep=struct();
end
frozen.ranges=d.ranges; frozen.units=base.units; frozen.grid_exact=base.grid_exact;
end

function valid=decomposition_floor_valid(sweep)
floor=value(sweep,'count_floor',0); proof=value(sweep,'floor_evidence',struct());
valid=floor==0;
if floor>0 && isfinite(floor) && floor==round(floor)
    count=value(proof,'count_lower',NaN);
    valid=value(proof,'source',"")=="loose_cap_global_count_bound" && ...
        value(proof,'cost_cap_usd',-Inf)>=sweep.cap_usd && ...
        isfinite(count) && count==round(count) && count>=floor;
end
end

function [base,state,record] = strengthen_blocks(base,state,economic,ctx,seconds,~,checkpoint)
% Complete temporal DW relaxation. RMP objective is an UPPER bound on DW,
% never a lower certificate for Keco. All linking rows stay in the master.
started=tic; cfg=ctx.config; original=base.physical_problem;
record=empty_point(economic.K_upper); record.count_lower=0;
record.witnesses=repmat(empty_point(0),0,1); record.solve_calls=0;
record.proof_model="complete_temporal_DW"; record.integer_count=numel(original.intcon);
record.global_bound=-Inf; record.count_upper=Inf;
d=value(state,'decomposition',struct());
if ~isfield(d,'version') || d.version~=2
    first=min(cfg.economic_block_lengths_h); starts=(1:first:ctx.T).';
    d=struct('version',2,'ranges',[starts,min(ctx.T,starts+first-1)], ...
        'points',{{}},'point_columns',{{}},'best_lower',-Inf,'bound_cap_usd',Inf, ...
        'master_upper',Inf,'center',[],'center_ids',[],'sweep',struct(), ...
        'history',[],'certificate',struct(),'stalled_sweeps',0,'price_time',[], ...
        'repair_hours',[],'stop_reason',"initialized");
end
% Algorithm work state is disposable; previously certified bounds and cuts are not.
settings=[value(base,'cut_policy',2),value(base,'cut_margin',1e-5),value(base,'cut_relative_margin',1e-9)];
if value(d,'algorithm_version',0)~=6 || ~isequal(value(d,'cut_settings',[]),settings)
    old_certificate=value(d,'certificate',struct()); d.algorithm_version=6;
    d.cut_settings=settings;
    d.price_time=repmat(cfg.economic_block_time_s,numel(d.price_time),1);
    d.sweep=struct(); d.stalled_sweeps=0; d.portfolio={};
    d.center=[]; d.center_ids=[]; d.needs_dual_seed=true;
    if isfield(old_certificate,'pi')
        d.center=decomposition_economic_pi(old_certificate.pi,old_certificate.link_ids);
        d.center_ids=old_certificate.link_ids;
        d.needs_dual_seed=decomposition_floor_degenerate(d.center,d.center_ids);
    end
    d.certificate=struct(); d.best_lower=decomposition_floor(economic);
    d.level_step=4; d.dual_sweeps_since_merge=0;
    d.merge_limit=min(384,max(cfg.economic_block_lengths_h)); d.park=struct();
    if isfield(d,'partition_trial'), d=rmfield(d,'partition_trial'); end
end
if isfield(d,'park') && isempty(fieldnames(d.park)), d=rmfield(d,'park'); end
if economic.cost_cap_usd>d.bound_cap_usd
    d.stalled_sweeps=0; d.dual_sweeps_since_merge=0;
    if isfield(d,'partition_trial'), d=rmfield(d,'partition_trial'); end
    d.best_lower=-Inf; d.certificate=struct(); % A relaxed cap cannot inherit this bound.
end
d.bound_cap_usd=economic.cost_cap_usd;
% Frozen looser-domain bounds also hold for this current smaller cost domain.
d.active_K_upper=economic.K_upper;
d.stop_reason="time_budget";
elapsed_before=value(d,'total_elapsed_s',0);
seed=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
if isempty(seed), seed=original.x0(:); end
seeds=decomposition_seeds(state,base,seed);
last_progress=tic; added_cuts=0; full_sweeps=0;
while toc(started)<seconds && record.solve_calls<value(cfg,'economic_decomposition_solve_limit',Inf)
    previous_best=d.best_lower;
    base.cut_prefix=state.block_cuts;
    d=decomposition_pick_trial(d,economic,base);
    [frozen,d,partial]=decomposition_context(d,economic,base,cfg,numel(state.block_cuts));
    cut_count=frozen.cut_count;
    working=apply_block_cuts(base,state.block_cuts(1:cut_count));
    p=working.problem; p.f=base.count_f;
    p.bineq(base.update_row)=min(ctx.T,frozen.K_upper)*base.update_coefficient;
    extra=base.cost_f.'; extra_rhs=frozen.cap_usd-base.offset; global_ids=-1;
    mi=size(original.Aineq,1); me=size(original.Aeq,1);
    if frozen.count_floor>0
        extra=[base.cost_f.';-base.count_f.'];
        extra_rhs=[frozen.cap_usd-base.offset;-frozen.count_floor]; global_ids=[-1;-2];
    end
    p.Aineq=[p.Aineq;extra]; p.bineq=[p.bineq;extra_rhs];
    row_ids=[(1:mi).';mi+me+(1:cut_count).';global_ids;mi+(1:me).'];
    [model,row_scale]=scaled_model(p,base.units); model.vtype(p.intcon)='I';
    if base.grid_exact, model.vtype(base.indices.u_purchase(:))='C'; end
    [blocks,link,ids,d]=decomposition_partition(model,base,d,seeds,cut_count,ctx.T,ctx,row_scale,row_ids);
    B=numel(blocks); A=model.A(link,:); rhs=model.rhs(link); sense=model.sense(link);
    d.coverage_rows=numel(link)+sum(cellfun(@(b) numel(b.rows),blocks));
    d.total_rows=size(model.A,1); d.coverage_variables=sum(cellfun(@(b) numel(b.col),blocks));
    assert(d.coverage_rows==d.total_rows && d.coverage_variables==numel(model.obj), ...
        'O1:incomplete_decomposition','Complete row and variable coverage is mandatory.');
    [master,cost,which]=decomposition_master(blocks,A,base.units);
    if ~partial
        d.active_count_floor=frozen.count_floor;
        master_problem=struct('Aineq',master(sense=='<',:),'bineq',rhs(sense=='<'), ...
            'Aeq',[master(sense=='=',:);sparse(which,1:numel(cost),1,B,numel(cost))], ...
            'beq',[rhs(sense=='=');ones(B,1)],'f',cost,'lb',zeros(numel(cost),1), ...
            'ub',Inf(numel(cost),1),'intcon',[],'x0',[]);
        master_problem.x0=decomposition_master_seed(blocks,seeds,master_problem);
        [centered,translation]=center_master_problem(master_problem,which);
        rm=relaxation(centered,ones(numel(cost),1), ...
            min(cfg.economic_block_lp_time_s,max(0.01,seconds-toc(started))),ctx,"master");
        rm=restore_master_result(rm,master_problem,translation);
        d.master_report=rm; d.master_report.x=[]; d.master_report.dual=[];
        d.master_upper=Inf;
        pi=[]; method="master_dual";
        if ~isempty(rm.dual)
            m_i=sum(sense=='<'); m_e=sum(sense=='='); pi=zeros(numel(rhs),1);
            pi(sense=='<')=rm.dual(1:m_i); pi(sense=='=')=rm.dual(m_i+(1:m_e));
        elseif ~isempty(d.center)
            [found,where]=ismember(ids,d.center_ids); pi=zeros(numel(ids),1);
            pi(found)=d.center(where(found)); method="cached_economic_dual";
        end
        if isempty(pi) || ~isfinite(d.best_lower) || value(d,'needs_dual_seed',false)
            root=relaxation(p,base.units,min(cfg.economic_block_lp_time_s, ...
                max(0,seconds-toc(started))),ctx);
            if ~isempty(root.dual)
                d.best_lower=max(d.best_lower,root.bound-decomposition_margin(root.bound));
                if isempty(pi) || value(d,'needs_dual_seed',false)
                    pi=decomposition_economic_pi(root.dual(link).*row_scale(link),ids); method="economic_LP_dual";
                    d.center=pi; d.center_ids=ids; d.needs_dual_seed=false;
                end
            elseif isempty(pi)
                d.stop_reason="LP_without_valid_dual"; break;
            end
        end
        pi=decomposition_economic_pi(pi,ids);
        if ~isempty(rm.x)
            d.master_upper=cost.'*rm.x+decomposition_margin(cost.'*rm.x);
            d.repair_hours=decomposition_repair(blocks,which,rm.x,seed,base,ctx.T);
            d.fractional=decomposition_fractional(blocks,which,rm.x,base);
            if full_sweeps>0 || ~isempty(d.history) || decomposition_floor_degenerate(pi,ids)
                center=pi;
                if ~isempty(d.center)
                    [found,where]=ismember(ids,d.center_ids);
                    center(found)=d.center(where(found));
                end
                center=decomposition_economic_pi(center,ids);
                pi=center; method="economic_center";
                [trial,ok]=decomposition_level(master,cost,which,rhs,sense,center, ...
                    d.best_lower,d.master_upper,seconds-toc(started),ctx,value(d,'level_step',2),ids);
                if ok, pi=trial; method="level"; end
            end
        end
        fprintf('[O1] RMP：算法=%g，状态=%s，原残差=%.3g，缩放残差=%.3g，DW上界=%.6f，乘子=%s，经济乘子幅度=%.3g，下界行乘子=%.3g，说明=%s。\n', ...
            rm.algorithm,rm.status,rm.original_residual,rm.scaled_residual,d.master_upper,method, ...
            max([0;abs(pi(ids~=-2))]),max([0;abs(pi(ids==-2))]),rm.reason);
        pi=double(sense=='=') .* pi + double(sense=='<') .* min(0,pi);
        pi=decomposition_economic_pi(pi,ids);
        if decomposition_floor_degenerate(pi,ids)
            d.stop_reason="economic_dual_without_informative_multiplier"; break;
        end
        if any(~isfinite(pi)), d.stop_reason="nonfinite_dual"; break; end
        d.sweep=struct('next_block',1,'pi',pi,'rhs',rhs,'link_ids',ids, ...
            'lower',-Inf(B,1),'upper',Inf(B,1),'status',strings(B,1), ...
            'cap_usd',frozen.cap_usd,'K_upper',frozen.K_upper,'count_floor',frozen.count_floor, ...
            'ranges',d.ranges,'cut_count',cut_count,'method',method);
        d.sweep.units=base.units; d.sweep.grid_exact=base.grid_exact;
        d.sweep.cut_policy=value(base,'cut_policy',2); d.sweep.cut_disabled=value(base,'cut_disabled',[]);
        d.sweep.cut_margin=value(base,'cut_margin',1e-5);
        d.sweep.cut_relative_margin=value(base,'cut_relative_margin',1e-9);
        d.sweep.cut_prefix=state.block_cuts(1:cut_count);
        d.sweep.floor_evidence=value(economic,'rejected_evidence',struct());
        d.sweep.previous_lower=previous_best;
        d.sweep.predicted_gain=min(value(d,'level_step',4),0.5*max(0,d.master_upper-d.best_lower));
        % Every cached local integer column gives an upper estimate of this
        % dual trial. This estimate can discard an unpromising multiplier,
        % but is never published as a Keco lower bound.
        for b=1:B
            objective=model.obj(blocks{b}.col)-A(:,blocks{b}.col).'*pi;
            d.sweep.upper(b)=min(objective.'*(d.points{b}./base.units(blocks{b}.col)));
        end
        d.price_time=repmat(cfg.economic_block_time_s,B,1);
        d.refine_time=zeros(B,1);
    else
        d.price_time=repmat(cfg.economic_block_time_s,B,1);
        d.refine_time=value(d.sweep,'refine_time',zeros(B,1));
        assert(isequal(ids,d.sweep.link_ids) && isequal(rhs,d.sweep.rhs), ...
            'O1:changed_partial_master','A resumed pricing sweep must use the identical master.');
        fprintf('[O1] 续算冻结扫描：第%d/%d块，成本帽%.3f，K上限%g，下界行%g；当前Keco=[%g,%g]。\n', ...
            d.sweep.next_block,B,frozen.cap_usd,frozen.K_upper,frozen.count_floor,economic.K_lower,economic.K_upper);
    end
    rejected=false;
    for b=d.sweep.next_block:B
        if toc(started)>=seconds || record.solve_calls>=value(cfg,'economic_decomposition_solve_limit',Inf), break; end
        q=blocks{b}.model; q.obj=model.obj(blocks{b}.col)-A(:,blocks{b}.col).'*d.sweep.pi;
        known=d.points{b}./base.units(blocks{b}.col);
        [~,best]=min(q.obj.'*known); q.start=known(:,best);
        price_started=tic;
        [lower,x,status]=decomposition_price(q, ...
            min(d.price_time(b),seconds-toc(started)),ctx);
        record.solve_calls=record.solve_calls+1;
        d.sweep.lower(b)=lower; d.sweep.status(b)=status;
        if ~isempty(x)
            [valid,candidate]=decomposition_column(q,x.*base.units(blocks{b}.col), ...
                base.units(blocks{b}.col),blocks{b}.row_scale,ctx);
            if valid
                distance=max(abs(d.points{b}-candidate)./max(1,abs(candidate)),[],1);
                if all(distance>1e-7), d.points{b}(:,end+1)=candidate; end
            end
        end
        known=d.points{b}./base.units(blocks{b}.col);
        d.sweep.upper(b)=min(q.obj.'*known);
        if isfinite(lower)
            coefficients=q.obj./base.units(blocks{b}.col);
            scale=max(1,max(abs(coefficients)));
            cut=struct('columns',blocks{b}.col.','coefficients',sparse(coefficients.'/scale), ...
                'lower_bound',lower/scale,'start_hour',blocks{b}.start_hour, ...
                'length_h',blocks{b}.length_h,'solver_status',status,'elapsed_s',toc(price_started));
            [state.block_cuts,added]=decomposition_add_cut(state.block_cuts,cut,cfg.economic_block_max_cuts,base);
            added_cuts=added_cuts+added;
        end
        d.sweep.next_block=b+1;
        if ismember(d.sweep.method,["level","economic_center"]) && decomposition_unpromising(d)
            rejected=true; break;
        end
        if mod(b,max(1,cfg.economic_block_batch))==0 || toc(last_progress)>30
            state.decomposition=d;
            state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
            fprintf('[O1] 完整分解：定价%d/%d块，完整覆盖证书=%d，已用%.1f s。\n', ...
                b,B,isfield(d.certificate,'complete'),toc(started)); last_progress=tic;
        end
    end
    if rejected
        upper=decomposition_trial_upper(d.sweep);
        d=decomposition_step(d,NaN,Inf,true);
        fprintf('[O1] 放弃无提升乘子：该乘子真实对偶值<=%.6f，已证下界%.6f；保留新列，不发布下界。\n',upper,d.best_lower);
        d.sweep=struct(); state.decomposition=d;
        state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
        if d.stalled_sweeps>=value(cfg,'economic_decomposition_stall_sweeps',3) && ...
                d.dual_sweeps_since_merge>=value(cfg,'economic_decomposition_min_dual_sweeps',4)
            [d,merged]=decomposition_merge(d,cfg);
            if ~merged, d.stop_reason="dual_stalled_with_open_DW_gap"; break; end
        end
        continue;
    end
    if d.sweep.next_block<=B, d.stop_reason="incomplete_pricing_sweep"; break; end
    center_before=d.center; center_ids_before=d.center_ids;
    [d,lower,oracle_gap]=decomposition_certificate(d,rhs,ids,economic);
    state.decomposition=d;
    state.decomposition.total_elapsed_s=elapsed_before+toc(started);
    checkpoint(state); % Publish the complete sweep before retries.
    % Refine the worst oracles at the SAME multipliers before changing the dual.
    target=value(cfg,'economic_decomposition_oracle_tolerance',0.05);
    if economic.K_upper-economic.K_lower>cfg.economic_final_interval
        target=max(target,0.25*value(d.sweep,'predicted_gain',0.5));
    end
    d.oracle_target=target;
    if numel(value(d,'refine_time',[]))~=B, d.refine_time=zeros(B,1); end
    [~,difficult_order]=sort(d.sweep.upper-d.sweep.lower,'descend');
    for b=difficult_order(1:min(cfg.economic_block_refine_count,B)).'
        if oracle_gap<=target || decomposition_unpromising(d) || ceil(d.best_lower-1e-5)>=economic.K_upper || ...
                toc(started)>=seconds || ...
                record.solve_calls>=value(cfg,'economic_decomposition_solve_limit',Inf)
            break;
        end
        next_budget=min(value(cfg,'economic_block_max_time_s',60), ...
            max(4*cfg.economic_block_time_s,2*d.refine_time(b)));
        if next_budget<=d.price_time(b), continue; end
        q=blocks{b}.model; q.obj=model.obj(blocks{b}.col)-A(:,blocks{b}.col).'*d.sweep.pi;
        known=d.points{b}./base.units(blocks{b}.col); [~,best]=min(q.obj.'*known);
        q.start=known(:,best); price_started=tic;
        [extra,x,status]=decomposition_price(q,min(next_budget,seconds-toc(started)),ctx);
        record.solve_calls=record.solve_calls+1; d.refine_time(b)=next_budget;
        d.sweep.lower(b)=max(d.sweep.lower(b),extra); d.sweep.status(b)=status;
        valid=false;
        if ~isempty(x)
            [valid,candidate]=decomposition_column(q,x.*base.units(blocks{b}.col), ...
                base.units(blocks{b}.col),blocks{b}.row_scale,ctx);
        end
        if valid
            distance=max(abs(d.points{b}-candidate)./max(1,abs(candidate)),[],1);
            if all(distance>1e-7), d.points{b}(:,end+1)=candidate; end
        end
        d.sweep.upper(b)=min(q.obj.'*(d.points{b}./base.units(blocks{b}.col)));
        if isfinite(d.sweep.lower(b))
            coefficients=q.obj./base.units(blocks{b}.col); scale=max(1,max(abs(coefficients)));
            cut=struct('columns',blocks{b}.col.','coefficients',sparse(coefficients.'/scale), ...
                'lower_bound',d.sweep.lower(b)/scale,'start_hour',blocks{b}.start_hour, ...
                'length_h',blocks{b}.length_h,'solver_status',status,'elapsed_s',toc(price_started));
            [state.block_cuts,added]=decomposition_add_cut(state.block_cuts,cut,cfg.economic_block_max_cuts,base);
            added_cuts=added_cuts+added;
        end
        [d,lower,oracle_gap]=decomposition_certificate(d,rhs,ids,economic);
        state.decomposition=d;
        state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
        fprintf('[O1] 同乘子困难块%d复核：时限%.1f s，剩余定价误差<=%.6g。\n',b,next_budget,oracle_gap);
    end
    d.boundary_scores=decomposition_boundary_scores(blocks,d,model,A,rhs,base.units);
    entry=struct('lower',lower,'best_lower',d.best_lower,'master_upper',d.master_upper, ...
        'oracle_gap',oracle_gap,'blocks',B,'lengths_h',d.ranges(:,2)-d.ranges(:,1)+1, ...
        'columns',sum(cellfun(@(x) size(x,2),d.points)), ...
        'elapsed_s',elapsed_before+toc(started), ...
        'cap_usd',d.sweep.cap_usd,'complete',isfinite(lower),'method',d.sweep.method);
    d.history=[d.history;entry]; full_sweeps=full_sweeps+1;
    if isfield(d,'partition_trial')
        d.partition_trial.completed_sweeps=d.partition_trial.completed_sweeps+1;
        d.partition_trial.lower_gain=d.best_lower-d.partition_trial.lower_before;
        fprintf('[O1] 合并试验：%d -> %d块，完成%d轮，下界提升%.6f，DW差距%.6f。\n', ...
            d.partition_trial.blocks_before,size(d.ranges,1),d.partition_trial.completed_sweeps, ...
            d.partition_trial.lower_gain,d.master_upper-d.best_lower);
    end
    d=decomposition_step(d,lower,oracle_gap,false);
    if ~d.last_trial.serious && ~isempty(center_before)
        d.center=center_before; d.center_ids=center_ids_before;
    end
    potential_upper=decomposition_trial_upper(d.sweep);
    d=decomposition_keep_trial(d);
    d.sweep=struct();
    if isfinite(lower)
        fprintf('[O1] DW=[%.6f,%.6f]，整数下界=%g，定价误差<=%.6g；%d块、%d列。\n', ...
            d.best_lower,d.master_upper,ceil(d.best_lower-1e-5),oracle_gap,B,entry.columns);
    end
    if oracle_gap>target && potential_upper>d.best_lower+0.05
        d.stop_reason="refine_selected_pricing_blocks";
    elseif economic.K_upper-ceil(d.best_lower-1e-5)>cfg.economic_final_interval && ...
            (d.master_upper-d.best_lower<=value(cfg,'economic_decomposition_tolerance',0.2) || ...
            (d.stalled_sweeps>=value(cfg,'economic_decomposition_stall_sweeps',3) && ...
            value(d,'dual_sweeps_since_merge',0)>=value(cfg,'economic_decomposition_min_dual_sweeps',4)))
        [d,merged]=decomposition_merge(d,cfg);
        if merged, d.stop_reason="merged_adjacent_blocks"; ...
        elseif d.master_upper-d.best_lower<=value(cfg,'economic_decomposition_tolerance',0.2)
            d.stop_reason="maximum_partition_strength";
        else
            d.stop_reason="dual_stalled_with_open_DW_gap";
        end
    end
    if isfield(d,'partition_trial') && d.partition_trial.lower_gain<=1e-6 && ...
            oracle_gap<=target && d.partition_trial.completed_sweeps>= ...
            value(cfg,'economic_decomposition_min_dual_sweeps',4)
        d.stop_reason="partition_trial_without_bound_gain";
    end
    state.decomposition=d;
    state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
    if ismember(d.stop_reason,["maximum_partition_strength","dual_stalled_with_open_DW_gap", ...
            "partition_trial_without_bound_gain"]), break; end
    if ceil(d.best_lower-1e-5)>=economic.K_upper
        d.stop_reason="certified_count_boundary"; break;
    elseif d.master_upper-d.best_lower<=value(cfg,'economic_decomposition_tolerance',0.2)
        d.stop_reason="certified_DW_tolerance"; break;
    end
end
if ismember(d.stop_reason,["maximum_partition_strength","dual_stalled_with_open_DW_gap", ...
        "partition_trial_without_bound_gain"])
    d.park=struct('K_lower',economic.K_lower,'K_upper',economic.K_upper, ...
        'cap_usd',economic.cost_cap_usd,'price_max_s',value(cfg,'economic_block_max_time_s',60), ...
        'round_time_s',cfg.economic_block_round_time_s,'max_length_h',max(cfg.economic_block_lengths_h));
elseif isfield(d,'park')
    d=rmfield(d,'park');
end
base=apply_block_cuts(base,state.block_cuts); state.decomposition=d;
state.decomposition.total_elapsed_s=elapsed_before+toc(started);
record.global_bound=d.best_lower; record.count_lower=max(0,ceil(d.best_lower-1e-5));
if ~isfinite(record.count_lower), record.count_lower=0; end
record.solver_status=d.stop_reason; record.elapsed_s=toc(started);
state.block_elapsed_s=state.block_elapsed_s+record.elapsed_s;
fprintf('[O1] 完整分解结束：新增割%d条，全年下界=%g，状态=%s；部分定价仅保存进度。\n', ...
    added_cuts,record.count_lower,d.stop_reason);
end

function seeds=decomposition_seeds(state,base,seed)
seeds=seed(:);
for points={state.points,state.caps}
    for j=1:numel(points{1})
        point=points{1}(j);
        if ~point.has_incumbent, continue; end
        x=solution_vector(base.indices,point.solution,numel(base.cost_f));
        if ~isempty(x) && matrix_violation(base.physical_problem,x)<=1e-6
            seeds(:,end+1)=x; %#ok<AGROW>
        end
    end
end
seeds=unique(seeds.','rows','stable').';
end

function [d,lower,oracle_gap]=decomposition_certificate(d,rhs,ids,~)
% Only ONE multiplier vector and ALL finite block lower bounds certify this sum.
lower=-Inf; oracle_gap=Inf;
if isfield(d.sweep,'next_block') && d.sweep.next_block<=numel(d.sweep.lower), return; end
if any(~isfinite(d.sweep.lower)), return; end
if ~decomposition_floor_valid(d.sweep), return; end
margin=decomposition_margin(rhs.'*d.sweep.pi)+sum(arrayfun(@decomposition_margin,d.sweep.lower));
lower=rhs.'*d.sweep.pi+sum(d.sweep.lower)-margin;
oracle_gap=sum(max(0,d.sweep.upper-d.sweep.lower));
if ~isfinite(lower), return; end
if lower>d.master_upper+1e-4
    error('O1:invalid_DW_bounds','DW lower certificate exceeds the restricted master upper bound.');
end
certificate=struct('complete',true,'pi',d.sweep.pi,'rhs',rhs,'link_ids',ids, ...
    'block_lower',d.sweep.lower,'block_upper',d.sweep.upper,'block_status',d.sweep.status, ...
    'ranges',d.ranges,'cut_count',d.sweep.cut_count,'cap_usd',d.sweep.cap_usd, ...
    'K_upper',d.sweep.K_upper,'count_floor',value(d.sweep,'count_floor',0), ...
    'floor_evidence',value(d.sweep,'floor_evidence',struct()), ...
    'margin',margin,'lower',lower,'master_upper',d.master_upper,'oracle_gap',oracle_gap, ...
    'method',d.sweep.method,'units',d.sweep.units,'grid_exact',d.sweep.grid_exact, ...
    'cut_policy',d.sweep.cut_policy,'cut_disabled',d.sweep.cut_disabled, ...
    'cut_margin',d.sweep.cut_margin,'cut_relative_margin',d.sweep.cut_relative_margin);
if ~isfield(d.certificate,'lower') || lower>d.certificate.lower
    d.certificate=certificate; d.center=d.sweep.pi; d.center_ids=ids;
end
d.best_lower=max(d.best_lower,lower);
end

function d=decomposition_keep_trial(d)
counter=value(d,'trial_counter',0)+1; d.trial_counter=counter;
trial=d.sweep; trial.refine_time=d.refine_time; trial.master_upper=d.master_upper;
trial.last_counter=counter; trial.retries=value(trial,'retries',0);
if isfield(trial,'cut_prefix'), trial=rmfield(trial,'cut_prefix'); end
portfolio=value(d,'portfolio',{});
same=cellfun(@(p) isequal(p.pi,trial.pi) && isequal(p.rhs,trial.rhs),portfolio);
portfolio(same)=[]; portfolio{end+1}=trial;
score=cellfun(@decomposition_trial_upper,portfolio);
[~,order]=sort(score,'descend'); d.portfolio=portfolio(order(1:min(3,numel(order))));
end

function d=decomposition_pick_trial(d,economic,base)
if isfield(d.sweep,'next_block'), return; end
portfolio=value(d,'portfolio',{}); selected=0; best=0;
for j=1:numel(portfolio)
    p=portfolio{j}; potential=decomposition_trial_upper(p)-d.best_lower;
    compatible=p.cap_usd>=economic.cost_cap_usd && p.K_upper>=economic.K_upper && ...
        isequal(p.ranges,d.ranges) && p.cut_count<=numel(base.cut_prefix) && ...
        branch_context_valid(p,base);
    if compatible && p.retries<2 && value(d,'trial_counter',0)>p.last_counter && ...
            potential>max(1,best) && sum(max(0,p.upper-p.lower))>0.1
        selected=j; best=potential;
    end
end
if selected==0, return; end
p=portfolio{selected}; p.retries=p.retries+1;
d.sweep=p; d.master_upper=p.master_upper; d.portfolio{selected}=p;
fprintf('[O1] 恢复历史经济乘子：认证下界%.6f，同乘子潜力上界%.6f，复核%d/2；后者不是Keco上界。\n', ...
    p.rhs.'*p.pi+sum(p.lower),decomposition_trial_upper(p),p.retries);
end

function upper=decomposition_trial_upper(sweep)
terms=[sweep.rhs.'*sweep.pi;sweep.upper(:)];
upper=sum(terms)+sum(arrayfun(@decomposition_margin,terms));
end

function yes=decomposition_unpromising(d)
upper=decomposition_trial_upper(d.sweep);
% A tiny continuous gain can still cross an integer boundary. Never discard
% a trial whose upper estimate leaves that certification opportunity open.
yes=isfinite(d.best_lower) && upper<=d.best_lower+0.05 && ...
    upper<=ceil(d.best_lower-1e-5)+1e-5;
end

function d=decomposition_step(d,lower,oracle_gap,early)
predicted=value(d.sweep,'predicted_gain',value(d,'level_step',4));
previous=value(d.sweep,'previous_lower',d.best_lower);
gain=lower-previous;
serious=~early && isfinite(lower) && gain>=max(0.05,0.25*predicted) && ...
    oracle_gap<=max(1e-4,0.1*predicted);
d.last_trial=struct('predicted_gain',predicted,'actual_gain',gain, ...
    'oracle_gap',oracle_gap,'serious',serious,'early_rejection',early);
d.dual_sweeps_since_merge=value(d,'dual_sweeps_since_merge',0)+1;
d.stalled_sweeps=(value(d,'stalled_sweeps',0)+1)*(early || isnan(gain) || gain<=0.2);
if serious
    d.level_step=min(32,2*value(d,'level_step',4));
else
    d.level_step=max(0.5,0.5*value(d,'level_step',4));
end
fprintf('[O1] 对偶试验：预测提升%.6g，实际提升%.6g，oracle误差%.6g，成功步=%d，下一level步长%.3g。\n', ...
    predicted,gain,oracle_gap,serious,d.level_step);
end

function scores=decomposition_boundary_scores(blocks,d,model,A,rhs,units)
scores=zeros(max(0,size(d.ranges,1)-1),1); x=zeros(numel(model.obj),1);
for b=1:numel(blocks)
    col=blocks{b}.col; X=d.points{b}./units(col);
    q=model.obj(col)-A(:,col).'*d.sweep.pi; [~,best]=min(q.'*X); x(col)=X(:,best);
end
weighted=abs(A*x-rhs).*abs(d.sweep.pi); counts=full(sum(spones(A),2));
for b=1:numel(scores)
    left=full(sum(spones(A(:,blocks{b}.col)),2));
    right=full(sum(spones(A(:,blocks{b+1}.col)),2));
    rows=left>0 & right>0 & left+right==counts;
    scores(b)=sum(weighted(rows));
end
% Keep cyclic rows in the master, and include their pressure in end-window priorities.
if numel(blocks)>1 && ~isempty(scores)
    first=full(sum(spones(A(:,blocks{1}.col)),2));
    last=full(sum(spones(A(:,blocks{size(d.ranges,1)}.col)),2));
    cyclic=first>0 & last>0 & first+last==counts;
    pressure=sum(weighted(cyclic)); scores(1)=scores(1)+pressure/2; scores(end)=scores(end)+pressure/2;
end
end

function [blocks,link,ids,d]=decomposition_partition(model,base,d,seeds,cut_count,T,ctx,row_scale,row_ids)
if nargin<7, ctx=[]; end
if nargin<8, row_scale=ones(size(model.rhs)); end
hours=variable_hours(base,T); owner=zeros(numel(hours),1);
for b=1:size(d.ranges,1)
    owner(hours>=d.ranges(b,1) & hours<=d.ranges(b,2))=b;
end
owner(hours==T+1)=size(d.ranges,1);
owner(owner==0)=size(d.ranges,1)+1;
[~,~,owner]=unique(owner); B=max(owner); blocks=cell(B,1);
original_rows=size(base.physical_problem.Aineq,1)+size(base.physical_problem.Aeq,1);
mi=size(base.physical_problem.Aineq,1); me=size(base.physical_problem.Aeq,1);
if nargin<9, row_ids=[(1:mi).';original_rows+(1:cut_count).';-1;mi+(1:me).']; end
assert(numel(row_ids)==size(model.A,1),'O1:invalid_row_ids','Every model row needs a stable identifier.');
% Valid cuts wholly inside a block belong to its pricing problem. Global
% cost/count rows and cross-block (including cyclic) rows remain in the master.
local=row_ids>0; local(row_ids==base.update_row)=false;
counts=full(sum(spones(model.A),2)); assigned=false(size(counts));
old_points=d.points; old_columns=d.point_columns; d.points=cell(B,1); d.point_columns=cell(B,1);
for b=1:B
    col=find(owner==b);
    rows=find(local & counts>0 & full(sum(spones(model.A(:,col)),2))==counts);
    assert(~any(assigned(rows))); assigned(rows)=true;
    q=struct('A',model.A(rows,col),'rhs',model.rhs(rows),'sense',model.sense(rows), ...
        'lb',model.lb(col),'ub',model.ub(col),'vtype',model.vtype(col),'modelsense','min');
    points=seeds(col,:);
    match=find(cellfun(@(c) isequal(c,col),old_columns),1);
    if ~isempty(match), points=[points,old_points{match}]; end %#ok<AGROW>
    if isempty(match) && ~isempty(old_columns)
        children=find(cellfun(@(c) all(ismember(c,col)),old_columns));
        if ~isempty(children) && numel(unique(vertcat(old_columns{children})))==numel(col)
            % Preserve old columns that remain feasible with the new internal boundary rows.
            for k=1:min(8,max(cellfun(@(x) size(x,2),old_points(children))))
                combined=zeros(numel(col),1);
                for child=children(:).'
                    [~,positions]=ismember(old_columns{child},col);
                    combined(positions)=old_points{child}(:,min(k,size(old_points{child},2)));
                end
                points(:,end+1)=combined; %#ok<AGROW>
            end
        end
    end
    units=base.units(col); good=false(1,size(points,2));
    for k=1:size(points,2)
        [valid,points(:,k)]=decomposition_column(q,points(:,k),units,row_scale(rows),ctx);
        good(k)=valid;
    end
    % Cached columns can violate a newly internalized cut. Preserve up to two
    % useful integer patterns by repairing only their continuous variables.
    if ~isempty(ctx) && any(~good)
        [~,order]=sort(model.obj(col).'* (points./units)); repaired=0;
        for k=order
            if good(k), continue; end
            repair=q; ii=find(q.vtype~='C'); y=points(:,k)./units;
            if any(~isfinite(y)), continue; end
            repair.lb(ii)=round(y(ii)); repair.ub(ii)=repair.lb(ii);
            repair.vtype(:)='C'; repair.obj=model.obj(col);
            [y,~]=continuous_solve(repair,min(1,value(ctx.config,'economic_event_lp_time_s',10)),ctx,struct());
            if ~isempty(y)
                [good(k),points(:,k)]=decomposition_column(q,y.*units,units,row_scale(rows),ctx);
            end
            repaired=repaired+1; if repaired>=2, break; end
        end
    end
    points=unique(points(:,good).','rows','stable').';
    if isempty(points), error('O1:no_decomposition_seed','No valid local column in block %d.',b); end
    d.points{b}=points; d.point_columns{b}=col;
    h=hours(col); h=h(h>0 & h<=T); start_hour=0; length_h=0;
    if ~isempty(h), start_hour=min(h); length_h=max(h)-start_hour+1; end
    blocks{b}=struct('col',col,'rows',rows,'model',q,'points',points,'objective',model.obj(col), ...
        'start_hour',start_hour,'length_h',length_h,'row_scale',row_scale(rows));
end
link=find(~assigned); ids=row_ids(link);
end

function [valid,x]=decomposition_column(q,x,units,row_scale,ctx)
valid=false; x=x(:);
if any(~isfinite(x)), return; end
y=x./units; ii=find(q.vtype~='C');
if max([0;abs(y(ii)-round(y(ii)))])>1e-6, return; end
y(ii)=round(y(ii)); x=y.*units;
if decomposition_violation(q,y)>1e-9, return; end
res=(q.A*y-q.rhs).*row_scale;
original=max([0;res(q.sense=='<');abs(res(q.sense=='=')); ...
    (q.lb-y).*units;(y-q.ub).*units]);
tolerance=1e-6;
if ~isempty(ctx), tolerance=ctx.model.options.ConstraintTolerance; end
valid=original<=tolerance;
end

function [A,cost,which]=decomposition_master(blocks,link_A,units)
N=sum(cellfun(@(b) size(b.points,2),blocks)); columns_by_block=cell(numel(blocks),1);
cost=zeros(N,1); which=zeros(N,1); first=1;
for b=1:numel(blocks)
    block=blocks{b}; X=block.points./units(block.col); columns=first:first+size(X,2)-1;
    columns_by_block{b}=sparse(link_A(:,block.col)*X);
    cost(columns)=(block.objective.'*X).';
    which(columns)=b; first=first+size(X,2);
end
A=horzcat(columns_by_block{:});
end

function [centered,shift]=center_master_problem(p,which)
% Convexity rows stay unchanged: subtract a baseline column within each block.
B=max(which); N=numel(which); H=sparse(which,1:N,1,B,N);
first=zeros(B,1); for b=1:B, first(b)=find(which==b,1); end
mi=size(p.Aineq,1); me=size(p.Aeq,1)-B;
bi=p.Aineq(:,first); be=p.Aeq(1:me,first); cost=p.f(first);
centered=p;
centered.Aineq=p.Aineq-bi*H; centered.bineq=p.bineq-bi*ones(B,1);
centered.Aeq=[p.Aeq(1:me,:)-be*H;p.Aeq(me+1:end,:)];
centered.beq=[p.beq(1:me)-be*ones(B,1);p.beq(me+1:end)];
centered.f=p.f-H.'*cost;
shift=struct('ineq',bi,'eq',be,'cost',cost,'constant',sum(cost),'blocks',B,'mi',mi,'me',me);
end

function result=restore_master_result(result,p,shift)
if isfinite(result.bound), result.bound=result.bound+shift.constant; end
if ~isempty(result.dual)
    pi=result.dual(1:shift.mi); tau=result.dual(shift.mi+(1:shift.me));
    last=numel(result.dual)-shift.blocks+(1:shift.blocks);
    result.dual(last)=result.dual(last)+shift.cost-shift.ineq.'*pi-shift.eq.'*tau;
    violation=max([0;p.Aineq.'*result.dual(1:shift.mi)+ ...
        p.Aeq.'*result.dual(shift.mi+1:end)-p.f]);
    if violation>1e-6
        result.dual=[]; result.dual_valid=false; result.bound=-Inf;
        result.reason="centered_dual_original_check_failed";
    end
end
if ~isempty(result.x)
    result.original_residual=matrix_violation(p,result.x);
    if result.original_residual>1e-6
        result.x=[]; result.primal_valid=false; result.dual=[]; result.dual_valid=false;
        result.bound=-Inf; result.reason="centered_primal_original_check_failed";
    end
end
if isempty(result.x) && ~isempty(p.x0) && matrix_violation(p,p.x0)<=1e-6
    result.x=p.x0; result.primal_valid=true;
    result.original_residual=matrix_violation(p,p.x0); result.reason="validated_annual_seed_fallback";
end
end

function pi=decomposition_economic_pi(pi,ids)
if isempty(pi), return; end
pi(ids==-2)=0; % External integer floor is retained as proof, excluded from search.
end

function yes=decomposition_floor_degenerate(pi,ids)
if isempty(pi), yes=true; return; end
economic=pi(ids~=-2);
yes=max([0;abs(economic(:))])<=1e-8;
end

function weights=decomposition_master_seed(blocks,seeds,p)
% A verified annual seed supplies a feasible DW upper bound if LP solving fails.
weights=[]; best=Inf; sizes=cellfun(@(b) size(b.points,2),blocks); first=[0;cumsum(sizes(:))];
for k=1:size(seeds,2)
    candidate=zeros(numel(p.f),1); found=true;
    for b=1:numel(blocks)
        col=blocks{b}.col;
        distance=max(abs(blocks{b}.points-seeds(col,k))./max(1,abs(seeds(col,k))),[],1);
        match=find(distance<=1e-10,1);
        if isempty(match), found=false; break; end
        candidate(first(b)+match)=1;
    end
    if found && matrix_violation(p,candidate)<=1e-6 && p.f.'*candidate<best
        weights=candidate; best=p.f.'*candidate;
    end
end
end

function [lower,x,status]=decomposition_price(model,seconds,ctx)
scale=max(1,max(abs(model.obj))); objective=model.obj; model.obj=objective/scale;
p=struct('f',model.obj,'Aineq',model.A(model.sense=='<',:),'bineq',model.rhs(model.sense=='<'), ...
    'Aeq',model.A(model.sense=='=',:),'beq',model.rhs(model.sense=='='), ...
    'lb',model.lb,'ub',model.ub,'intcon',find(model.vtype~='C'),'x0',model.start);
task=struct('kind',"block_bound",'focus',3,'attempt',1,'cap',Inf,'time_limit',max(0.01,seconds));
if strcmp(ctx.config.economics_solver,'gurobi'), raw=gurobi_solve(p,ones(numel(model.obj),1),task,0,ctx); ...
else, raw=matlab_solve(p,task,0,ctx); end
lower=raw.bound*scale; lower=lower-decomposition_margin(lower);
x=raw.x; status=raw.status;
if ~isfinite(lower)
    % A short oracle may stop before a finite MIP bound exists. The LP of
    % the SAME frozen objective is still a valid lower bound for this block.
    relaxed=relaxation(p,ones(numel(model.obj),1),min(2,max(0.01,seconds)),ctx);
    if isfinite(relaxed.bound)
        lower=relaxed.bound*scale; lower=lower-decomposition_margin(lower);
        status=status+"_LP_LOWER"; % An LP point is never added as an integer column.
    end
end
end

function [cuts,added]=decomposition_add_cut(cuts,cut,maximum,base)
added=0;
if ~any(cut.coefficients) || ~isfinite(cut.lower_bound), return; end
if nargin>=4 && ~isempty(value(base,'cut_witnesses',[]))
    violation=max(cut.lower_bound-full(cut.coefficients)*base.cut_witnesses(cut.columns,:));
    if violation>cut_numeric_margin(cut,base), return; end
end
for j=1:numel(cuts)
    if isequal(cut.columns,cuts(j).columns) && isequal(cut.coefficients,cuts(j).coefficients)
        if cut.lower_bound<=cuts(j).lower_bound+1e-9, return; end
        % Append a stronger duplicate: a partial sweep retains its frozen row prefix.
    end
end
if numel(cuts)<maximum, cuts(end+1,1)=cut; added=1; end
end

function hours=decomposition_repair(blocks,which,weights,seed,base,T)
score=zeros(T,1); hour=variable_hours(base,T); integers=base.physical_problem.intcon;
if base.grid_exact, integers=setdiff(integers,base.indices.u_purchase(:)); end
for b=1:numel(blocks)
    col=blocks{b}.col; x=blocks{b}.points*weights(which==b);
    local=find(ismember(col,integers) & hour(col)>0 & hour(col)<=T);
    score=score+accumarray(hour(col(local)),abs(x(local)-seed(col(local)))+ ...
        abs(x(local)-round(x(local))),[T,1]);
end
[~,order]=sort(score,'descend'); hours=order(score(order)>1e-7);
end

function [pi,ok]=decomposition_level(A,cost,which,rhs,sense,center,lower,upper,seconds,ctx,step,ids)
pi=center; ok=false;
if nargin<11, step=2; end
if ~strcmp(ctx.config.economics_solver,'gurobi') || ~isfinite(lower) || ~isfinite(upper) || seconds<=0, return; end
R=numel(rhs); B=max(which); N=numel(cost); scale=max(1,abs(center));
D=spdiags(scale,0,R,R); level=lower+min(step,0.5*max(0,upper-lower));
model=struct('A',[A.'*D,sparse(1:N,which,1,N,B);-rhs.'*D,-ones(1,B)], ...
    'rhs',[cost;-level],'sense',repmat('<',N+1,1), ...
    'lb',-Inf(R+B,1),'ub',Inf(R+B,1),'obj',[-center./scale;zeros(B,1)], ...
    'Q',spdiags([0.5*ones(R,1);zeros(B,1)],0,R+B,R+B),'modelsense','min');
model.ub(find(sense=='<'))=0;
if nargin>=12
    floor=find(ids==-2); model.lb(floor)=0; model.ub(floor)=0;
end
row_scale=max(1,full(max(abs(model.A),[],2)));
model.A=spdiags(1./row_scale,0,N+1,N+1)*model.A; model.rhs=model.rhs./row_scale;
params=struct('OutputFlag',0,'Threads',ctx.config.gurobi_threads,'TimeLimit',min(20,seconds), ...
    'Method',2,'FeasibilityTol',1e-9,'OptimalityTol',1e-9,'BarConvTol',1e-9);
raw=gurobi(model,params);
if isfield(raw,'x') && all(isfinite(raw.x)) && decomposition_violation(model,raw.x)<=1e-6
    pi=raw.x(1:R).*scale; ok=true;
else
    fprintf('[O1] level投影未通过检查：状态=%s；保留本轮有效乘子并完整定价。\n',string(raw.status));
end
end

function [d,merged]=decomposition_merge(d,cfg)
merged=false; ranges=d.ranges; lengths=ranges(:,2)-ranges(:,1)+1;
maximum=value(d,'merge_limit',max(cfg.economic_block_lengths_h));
eligible=find(lengths(1:end-1)+lengths(2:end)<=maximum);
if isempty(eligible) && maximum<max(cfg.economic_block_lengths_h)
    maximum=min(max(cfg.economic_block_lengths_h),2*maximum); d.merge_limit=maximum;
    eligible=find(lengths(1:end-1)+lengths(2:end)<=maximum);
    fprintf('[O1] 分块加强试验：允许相邻块合并至%d h，每次最多两组。\n',maximum);
end
if isempty(eligible), return; end
score=zeros(size(eligible));
for j=1:numel(eligible)
    boundary=ranges(eligible(j),2);
    score(j)=sum(abs(d.repair_hours-boundary)<=min(lengths(eligible(j)),24));
    coupling=value(d,'boundary_scores',[]);
    if numel(coupling)>=eligible(j), score(j)=score(j)+coupling(eligible(j)); end
end
[~,order]=sort(score,'descend'); used=false(size(lengths)); remove=false(size(lengths));
for j=order.'
    b=eligible(j); if used(b) || used(b+1), continue; end
    ranges(b,2)=ranges(b+1,2); remove(b+1)=true; used([b,b+1])=true; merged=true;
    if sum(remove)>=min(2,max(1,ceil(numel(lengths)/8))), break; end
end
d.ranges=ranges(~remove,:); d.sweep=struct(); d.master_upper=Inf; d.price_time=[];
d.partition_trial=struct('blocks_before',numel(lengths),'lower_before',d.best_lower, ...
    'completed_sweeps',0,'lower_gain',0);
d.stalled_sweeps=0; d.dual_sweeps_since_merge=0; d.level_step=4;
fprintf('[O1] 相邻块自适应合并：%d -> %d块，最大长度%d h；保留历史有效割及下界。\n', ...
    numel(lengths),size(d.ranges,1),max(d.ranges(:,2)-d.ranges(:,1)+1));
end

function residual=decomposition_violation(model,x)
res=model.A*x-model.rhs;
residual=max([0;res(model.sense=='<');abs(res(model.sense=='='));model.lb-x]);
if isfield(model,'ub'), residual=max([residual;x-model.ub]); end
if isfield(model,'vtype')
    ii=model.vtype~='C'; residual=max([residual;abs(x(ii)-round(x(ii)))]);
end
end

function margin=decomposition_margin(bound)
margin=1e-6+1e-9*abs(bound);
end

function result = relaxation(p,units,seconds,ctx,purpose)
if nargin<5, purpose="root"; end
result = struct('x',[],'dual',[],'bound',-Inf,'status',"TIME_LIMIT", ...
    'primal_valid',false,'dual_valid',false,'algorithm',NaN, ...
    'original_residual',Inf,'scaled_residual',Inf,'reason',"no_valid_solution");
if seconds <= 0, return; end
[model,row_scale] = scaled_model(p,units);
if strcmp(ctx.config.economics_solver,'gurobi')
    started=tic; methods=2;
    if purpose=="master", methods=[1,0]; end
    for method=methods
        remaining=seconds-toc(started); if remaining<=0, break; end
        params = struct('TimeLimit',remaining,'OutputFlag',0,'Method',method, ...
            'Threads',ctx.config.gurobi_threads,'FeasibilityTol',solver_tolerance(ctx), ...
            'OptimalityTol',solver_tolerance(ctx));
        if method==2, params.Crossover=0; end
        raw=gurobi(model,params); result.status=string(raw.status); result.algorithm=method;
        current_primal_valid=false;
        if isfield(raw,'x') && all(isfinite(raw.x))
            x=raw.x(:).*units; residual=matrix_violation(p,x);
            result.original_residual=residual; result.scaled_residual=scaled_violation(model,raw.x(:));
            if purpose~="master" || residual<=1e-6
                result.x=x; result.primal_valid=true; result.reason="validated_primal";
                current_primal_valid=true;
            else
                result.reason="original_residual_rejected";
            end
        end
        if result.status=="OPTIMAL" && isfield(raw,'pi') && all(isfinite(raw.pi)) && ...
                (purpose~="master" || current_primal_valid)
            result.dual=raw.pi(:)./row_scale; result.bound=raw.objval;
            result.dual_valid=true; result.reason="validated_primal_and_dual"; break;
        end
    end
else
    options = optimoptions('linprog','Display','none','MaxTime',seconds, ...
        'ConstraintTolerance',solver_tolerance(ctx),'OptimalityTolerance',solver_tolerance(ctx));
    [x,obj,flag,~,dual] = linprog(p.f,p.Aineq,p.bineq,p.Aeq,p.beq,p.lb,p.ub,options);
    if ~isempty(x) && all(isfinite(x))
        result.original_residual=matrix_violation(p,x);
        result.scaled_residual=scaled_violation(model,x./units);
        if purpose~="master" || result.original_residual<=1e-6
            result.x=x; result.primal_valid=true; result.reason="validated_primal";
        end
    end
    if flag>0 && result.primal_valid
        result.bound=obj; result.status="OPTIMAL"; result.dual_valid=true;
        result.dual=-[dual.ineqlin;dual.eqlin]; result.reason="validated_primal_and_dual";
    end
end
if purpose=="master" && isempty(result.x) && ~isempty(p.x0) && ...
        all(isfinite(p.x0)) && matrix_violation(p,p.x0)<=1e-6
    result.x=p.x0(:); result.primal_valid=true; result.reason="validated_annual_seed_fallback";
    result.original_residual=matrix_violation(p,result.x);
    result.scaled_residual=scaled_violation(model,result.x./units);
end
if result.primal_valid
    result.original_residual=matrix_violation(p,result.x);
    result.scaled_residual=scaled_violation(model,result.x./units);
    if result.reason=="original_residual_rejected", result.reason="retained_primal_after_failed_repair"; end
end
end

function state = log_proof(state,record,task)
entry = struct('kind',task.kind,'K',task.K,'cap_usd',task.cap, ...
    'model',record.proof_model,'integers',record.integer_count, ...
    'global_bound',record.global_bound,'status',record.solver_status, ...
    'elapsed_s',record.elapsed_s);
if ~isfield(state,'proof_history'), state.proof_history = repmat(entry,0,1); end
state.proof_history(end+1,1) = entry;
end

function state = store_witnesses(state,record)
% 每个已核验调度独立保留，避免更小但不严格合格的宽松候选覆盖合格见证。
for i = 1:numel(record.witnesses)
    point = record.witnesses(i);
    prior = find_point(state.points,point.K);
    source = prior.source;
    if strlength(source) == 0, source = "validated_primal_witness"; end
    state.points = merge_point(state.points,point,point.K,source);
end
end

function result = gurobi_solve(p,units,task,offset,ctx)
model = scaled_model(p,units);
n = numel(p.lb);
model.vtype(p.intcon) = 'I';
if ~isempty(p.x0)
    if all(isfinite(p.x0)) && scaled_violation(model,p.x0(:)./units)<=solver_tolerance(ctx) && ...
            matrix_violation(p,p.x0)<=ctx.model.options.ConstraintTolerance && ...
            max([0;abs(p.x0(p.intcon)-round(p.x0(p.intcon)))])<=1e-6
        model.start=p.x0(:)./units;
    else
        % Incomplete guesses guide the search instead of launching a repair sub-MIP.
        model.varhintval=NaN(n,1);
        model.varhintval(p.intcon)=p.x0(p.intcon)./units(p.intcon);
    end
end
focus = ctx.config.gurobi_mip_focus;
if focus < 0
    if task.focus >= 0
        focus = task.focus;
    elseif task.kind == "loose_count"
        focus = 3;
    elseif task.kind == "strict_count"
        focus = 1;
    else
        foci = [1,3,0,2]; focus = foci(1+mod(task.attempt-1,numel(foci)));
    end
end
parameters = struct('TimeLimit',task.time_limit,'MIPGap',0,'MIPGapAbs',0, ...
    'MIPFocus',focus,'Method',ctx.config.gurobi_method,'Threads',ctx.config.gurobi_threads, ...
    'FeasibilityTol',solver_tolerance(ctx),'IntFeasTol',solver_tolerance(ctx),'DualReductions',0, ...
    'DisplayInterval',60,'OutputFlag',1,'LogToConsole',double(~strcmp(ctx.config.display,'off')), ...
    'LogFile',[tempname,'_O1_',char(task.kind),'.log']);
parameters.StartTimeLimit=min(value(ctx.config,'economic_start_time_s',3),task.time_limit/10);
if task.kind == "fixed_cost"
    if isfinite(task.sat), parameters.BestObjStop = task.sat-offset-money_margin(task.sat); end
    if isfinite(task.fail), parameters.BestBdStop = task.fail-offset+money_margin(task.fail); end
elseif task.kind == "loose_count"
    parameters.MIPGapAbs = 0.49;
    parameters.BestBdStop = count_bound_target(task)-1+1e-6;
elseif task.kind == "strict_count"
    parameters.MIPGapAbs = 0.49;
    parameters.BestObjStop = task.K_lower+1e-6;
elseif task.kind == "local_count"
    parameters.MIPGapAbs = 0.49;
    parameters.BestObjStop = task.target-offset+1e-6;
elseif task.kind == "local_cost"
    if isfinite(task.sat), parameters.BestObjStop=task.sat-offset-money_margin(task.sat); end
elseif task.kind == "reference_cost"
    parameters.MIPGapAbs = task.absolute_gap;
end
if task.kind == "block_bound"
    parameters.OutputFlag=0; parameters.LogToConsole=0;
    parameters=rmfield(parameters,'LogFile');
else
    fprintf('[O1] Gurobi %s：策略=%g，时限=%.1f s，日志=%s\n', ...
        task.kind,focus,task.time_limit,parameters.LogFile);
end
raw = gurobi(model,parameters);
result = struct('x',[],'bound',-Inf,'status',string(raw.status));
if isfield(raw,'x') && numel(raw.x) == n && all(isfinite(raw.x))
    result.x = raw.x(:).*units;
end
if isfield(raw,'objboundc') && isfinite(raw.objboundc)
    result.bound = raw.objboundc;
elseif isfield(raw,'objbound') && isfinite(raw.objbound)
    result.bound = raw.objbound;
elseif strcmp(raw.status,'OPTIMAL') && isfield(raw,'objval') && isfinite(raw.objval)
    result.bound = raw.objval;
end
end

function result = matlab_solve(p,task,offset,ctx)
bound = -Inf;
gap = 0;
if task.kind == "loose_count" || task.kind == "strict_count" || task.kind == "local_count"
    gap = 0.49;
end
if task.kind == "reference_cost", gap = task.absolute_gap; end
p.solver = 'intlinprog';
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
            stop = ceil(bound-1e-7) >= count_bound_target(task);
        elseif task.kind == "strict_count" && isfield(values,'fval') && ...
                isscalar(values.fval) && isfinite(values.fval)
            stop = values.fval <= task.K_lower+1e-7;
        elseif task.kind == "local_count" && isfield(values,'fval') && ...
                isscalar(values.fval) && isfinite(values.fval)
            stop = values.fval+offset <= task.target+1e-7;
        elseif task.kind=="local_cost" && isfield(values,'fval') && ...
                isscalar(values.fval) && isfinite(values.fval)
            stop=values.fval+offset<=task.sat-money_margin(task.sat);
        end
    end
end

function target = count_bound_target(task)
if value(task,'concentrated',false)
    target = task.K;
    return
end
% 宽松帽只需取得本轮有效下界进展，避免以旧合格上界作为唯一停止门槛。
step = max(1,ceil(0.05*(task.K-task.K_lower)));
target = min(task.K,task.K_lower+step);
end

function [start,candidate] = prepare_start(p,start,base,seconds,cap,ctx)
candidate = [];
if isempty(start), return; end
integers = p.intcon(isfinite(start(p.intcon)));
start(integers) = round(start(integers));
if numel(integers) == numel(p.intcon)
    model=scaled_model(p,base.units);
    if all(isfinite(start)) && scaled_violation(model,start./base.units)<=solver_tolerance(ctx) && ...
            matrix_violation(p,start)<=ctx.model.options.ConstraintTolerance && ...
            (~isfinite(cap) || base.cost_f.'*start+base.offset<=cap)
        candidate=start; return; % A polishing timeout must not discard a feasible witness.
    end
    candidate = polish_candidate(p,start,base,seconds,cap,ctx);
    if ~isempty(candidate)
        start = candidate;
        fprintf('[O1] 热启动LP修复通过：缩放矩阵残差<=%.1g，成本=%.3f USD。\n', ...
            solver_tolerance(ctx),base.cost_f.'*candidate+base.offset);
        return
    end
end
% 无法构造完整可行起点时只传递范围合法的整数提示，释放连续变量。
hint = NaN(size(start));
integers = integers(start(integers) >= p.lb(integers) & start(integers) <= p.ub(integers));
hint(integers) = start(integers);
start = hint;
if isempty(integers), start = []; end
fprintf('[O1] 热启动改为部分整数提示：%d/%d个整数；无可行证书。\n', ...
    numel(integers),numel(p.intcon));
end

function x = polish_candidate(p,x,base,seconds,cap,ctx)
% 固定所有整数后求最小原成本；此LP的最优值只可用作可行上界。
p.lb(p.intcon) = round(x(p.intcon));
p.ub(p.intcon) = p.lb(p.intcon);
p.f = base.cost_f;
if isfinite(cap)
    % 仅给可行见证留出数值余量；证明下界的MILP成本帽保持原值。
    p.Aineq = [p.Aineq;base.cost_f.'];
    p.bineq = [p.bineq(:);cap-base.offset-money_margin(cap)];
end
model = scaled_model(p,base.units);
tolerance = solver_tolerance(ctx);
if strcmp(ctx.config.economics_solver,'gurobi')
    parameters = struct('TimeLimit',max(0.01,seconds),'OutputFlag',0, ...
        'FeasibilityTol',tolerance,'OptimalityTol',tolerance, ...
        'Threads',ctx.config.gurobi_threads,'DualReductions',0);
    raw = gurobi(model,parameters);
    candidate = value(raw,'x',[]);
else
    options = optimoptions('linprog','Display','off','MaxTime',max(0.01,seconds), ...
        'ConstraintTolerance',tolerance);
    candidate = linprog(model.obj,model.A(model.sense=='<',:),model.rhs(model.sense=='<'), ...
        model.A(model.sense=='=',:),model.rhs(model.sense=='='),model.lb,model.ub,options);
end
x = [];
if isempty(candidate) || any(~isfinite(candidate)), return; end
scaled = candidate(:);
candidate = scaled.*base.units;
candidate(p.intcon) = round(candidate(p.intcon));
scaled = candidate./base.units;
if scaled_violation(model,scaled) <= tolerance && ...
        matrix_violation(p,candidate) <= ctx.model.options.ConstraintTolerance
    x = candidate;
end
end

function [model,row_scale] = scaled_model(p,units)
n = numel(p.lb);
A = [p.Aineq;p.Aeq]*spdiags(units,0,n,n);
row_scale = max(1,full(max(abs(A),[],2)));
model = struct('A',spdiags(1./row_scale,0,size(A,1),size(A,1))*A, ...
    'rhs',[p.bineq(:);p.beq(:)]./row_scale, ...
    'sense',[repmat('<',size(p.Aineq,1),1);repmat('=',size(p.Aeq,1),1)], ...
    'obj',p.f(:).*units,'lb',p.lb(:)./units,'ub',p.ub(:)./units, ...
    'modelsense','min','vtype',repmat('C',n,1));
end

function residual = scaled_violation(model,x)
rows = model.A*x-model.rhs;
residual = max([0;rows(model.sense=='<');abs(rows(model.sense=='=')); ...
    model.lb-x;x-model.ub]);
end

function tolerance = solver_tolerance(ctx)
tolerance = min(1e-9,ctx.model.options.ConstraintTolerance);
end

function [x,solution,cost,count,residual] = validate_solution(solution,base,ctx,K)
x = []; cost = Inf; count = Inf; residual = Inf;
if ~isstruct(solution) || isempty(fieldnames(solution)), return; end
solution = ctx.services.add_change_indicators(solution,ctx);
candidate = solution_vector(base.indices,solution,numel(base.cost_f));
if isempty(candidate) || any(~isfinite(candidate)), return; end
p = value(base,'physical_problem',base.problem);
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

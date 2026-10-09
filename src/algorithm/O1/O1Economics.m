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
    state.primal_schedule=struct('step',1,'window_level',1,'stalls',0, ...
        'polished_K',Inf,'polished_cost',Inf);
end
base = apply_block_cuts(base,state.block_cuts);
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
        primal_search(round_index,reserve);
        if economic.K_upper-economic.K_lower <= cfg.economic_final_interval, break; end
        if cfg.economic_run_budget_s-toc(started)>reserve+cfg.economic_stalled_cap_time_s
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
        % Alternate cost headroom and update removal; all continuous variables remain free.
        for local_index=1:cfg.economic_local_passes
            available=cfg.economic_run_budget_s-toc(started)-reserve;
            if economic.is_proven || ~can_run() || available<=0, break; end
            level=state.primal_schedule.window_level;
            kind="local_count"; K=economic.K_upper;
            if local_index==1 && cfg.economic_local_passes>1
                kind="local_cost";
            else
                K=max(economic.K_lower,K-state.primal_schedule.step);
            end
            task=make_task(kind,K,economic.strict_cost_cap_usd,round_number);
            task.K_lower=economic.K_lower; task.target=K;
            task.sat=economic.satisfied_evidence.cost_upper_usd- ...
                max(1,0.01*cfg.economic_delta_usd_t*cfg.nh3_target_t);
            task.start=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
            task.local_hours=local_hours(task.start,base,ctx,level,local_index+round_number-1, ...
                value(state,'decomposition',struct()));
            task.time_limit=min(cfg.economic_local_time_s,available);
            before_upper=economic.K_upper; before_cost=economic.satisfied_evidence.cost_upper_usd;
            begin_task(task.kind,task.K,task.time_limit);
            record=solve_task(base,task,ctx); state=log_proof(state,record,task);
            state=store_witnesses(state,record); finish_task();
            improved=economic.K_upper<before_upper;
            if kind=="local_count"
                if improved
                    state.primal_schedule.step=min(8,2*state.primal_schedule.step);
                else
                    state.primal_schedule.step=max(1,floor(state.primal_schedule.step/2));
                end
            end
            fprintf('[O1] %s：释放%d时段，目标K<=%g；Keco=[%g,%g]，成本改善%.3f USD，严格余量%.3f USD。\n', ...
                kind,numel(task.local_hours),task.K,economic.K_lower,economic.K_upper, ...
                before_cost-economic.satisfied_evidence.cost_upper_usd, ...
                economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd);
        end
        if economic.K_upper<old_upper || economic.satisfied_evidence.cost_upper_usd<accepted_cost-1
            state.primal_schedule.stalls=0;
        else
            state.primal_schedule.stalls=state.primal_schedule.stalls+1;
            if state.primal_schedule.stalls>=2
                state.primal_schedule.window_level=min(2*numel(cfg.economic_block_lengths_h), ...
                    state.primal_schedule.window_level+1);
                state.primal_schedule.stalls=0;
            end
        end
        save_state();
    end

    function concentrated_certification(pilot)
        % 窄区间优先认证K_upper-1；宽区间将割回填全年模型后集中求界。
        for certificate_kind = ["loose_count","strict_count"]
            if economic.is_proven || ~can_run(), break; end
            if economic.K_upper-economic.K_lower<=cfg.economic_final_interval, break; end
            if certificate_kind=="strict_count" && state.structural_report.upper_gain>0, continue; end
            if pilot && certificate_kind=="strict_count", continue; end
            cap = economic.cost_cap_usd;
            if certificate_kind == "strict_count", cap = economic.strict_cost_cap_usd; end
            task = make_task(certificate_kind,economic.K_upper,cap,1);
            if ~isfinite(task.K), task.K = ctx.T; end
            task.K_lower = economic.K_lower;
            task.concentrated = ~pilot;
            task.start = best_start(state,reference,task.K,base);
            task.time_limit = min(cfg.economic_certification_time_s, ...
                max(0.01,(cfg.economic_run_budget_s-toc(started))*0.4));
            if certificate_kind=="strict_count"
                task.time_limit=min(task.time_limit,2*cfg.economic_local_time_s);
            end
            if pilot, task.time_limit=min(task.time_limit,cfg.economic_stalled_cap_time_s); end
            prior = find_cap(state,certificate_kind,cap); task.attempt = prior.attempts+1;
            if ~claim_certification(task), continue; end
            begin_task(certificate_kind,task.K,task.time_limit);
            record = solve_task(base,task,ctx);
            state = log_proof(state,record,task);
            state = store_witnesses(state,record);
            state = store_cap(state,prior,record,certificate_kind,cap);
            state.cert_schedule=pending_cert_schedule;
            finish_task();
        end
        % 只有接近边界时求相邻点；大区间仅选一个中点，不逐点扫描。
        probes=cfg.economic_max_attempts; if pilot, probes=1; end
        for probe = 1:probes
            if economic.is_proven || ~can_run() || ~isfinite(economic.K_upper), break; end
            if economic.K_upper-economic.K_lower <= cfg.economic_final_interval
                K = economic.K_upper-1;
            elseif pilot
                K=max(economic.K_lower,economic.K_upper-1);
            else
                K = floor((economic.K_lower+economic.K_upper)/2);
            end
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
            state.structural_report.width_reduction_fraction>=0.3;
        state.structural_report.strict_slack_usd = ...
            economic.strict_cost_cap_usd-economic.satisfied_evidence.cost_upper_usd;
        state.structural_report.block_elapsed_s = state.block_elapsed_s;
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
    index=find([entries.kind]==task.kind & [entries.K]==task.K & [entries.cap]==task.cap,1);
end
allowed=true;
if ~isempty(index)
    prior=entries(index); gain=value(cfg,'economic_certification_retry_gain',1);
    allowed=current.lower>prior.lower || current.upper<prior.upper || ...
        current.sat>prior.sat+money_margin(current.sat) || ...
        current.fail<prior.fail-money_margin(current.fail) || ...
        (current.DW_lower>=prior.DW_lower+gain && isfinite(current.DW_lower)) || ...
        current.witness_cost<prior.witness_cost-max(1,0.01*(current.fail-economic.reference_upper_usd)) || ...
        current.budget>1.5*prior.budget;
end
if allowed
    if isempty(index), entries(end+1,1)=current; else, entries(index)=current; end
end
end

function record=polish_witness(base,economic,ctx,seconds)
started=tic; K=economic.K_upper; record=empty_point(K);
record.count_lower=0; record.witnesses=repmat(empty_point(K),0,1);
record.global_bound=-Inf; record.proof_model="fixed_integer_LP_upper_only";
record.integer_count=0; record.solver_status="no_primal_improvement";
x=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
p=base.problem; p.bineq(base.update_row)=K*base.update_coefficient;
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
p.bineq(base.update_row) = task.K*base.update_coefficient;
is_local = task.kind == "local_count" || task.kind == "local_cost";
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
    hours = variable_hours(base,ctx.T);
    fixed = p.intcon(~ismember(hours(p.intcon),task.local_hours));
    if base.grid_exact, fixed = setdiff(fixed,base.indices.u_purchase(:)); end
    p.lb(fixed) = round(task.start(fixed)); p.ub(fixed) = p.lb(fixed);
end
% 两次LP都占用本阶段预算；为返回候选的成本抛光预留时间。
lp_budget = min(ctx.config.economic_lp_time_s,task.time_limit/10);
repair_start=task.start;
if is_local && sum(repair_start(base.indices.O1_HB_change(:)))>task.K
    z=base.indices.O1_HB_change(:); repair_start(z(task.local_hours))=NaN;
    if isfield(base.indices,'O1_HB_setpoint')
        s=base.indices.O1_HB_setpoint(:); repair_start(s(task.local_hours))=NaN;
    end
end
[p.x0,start_candidate] = prepare_start(p,repair_start,base,lp_budget,task.cap,ctx);
solver_task = task;
solver_task.time_limit = max(0.01,task.time_limit-toc(started)-lp_budget);
[solver_p,proof_model] = proof_problem(p,base,task,ctx);
if is_local, proof_model = "local_restriction_upper_bound_only"; end
free_integers = sum(solver_p.lb(solver_p.intcon) < solver_p.ub(solver_p.intcon));
fprintf('[O1] %s：未固定整数=%d/%d，原模型核验保留。\n', ...
    proof_model,free_integers,numel(p.intcon));
if strcmp(ctx.config.economics_solver,'gurobi')
    result = gurobi_solve(solver_p,base.units,solver_task,offset,ctx);
else
    result = matlab_solve(solver_p,solver_task,offset,ctx);
end
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

function hours = local_hours(start,base,ctx,round_index,local_index,decomposition)
T = ctx.T; lengths = ctx.config.economic_block_lengths_h;
length_h = min(T,lengths(1+mod(round_index-1,numel(lengths))));
starts = (1:length_h:T).'; z = start(base.indices.O1_HB_change(:));
cheap=zeros(T,1);
if isfield(base.indices,'O1_HB_setpoint')
    setpoint=start(base.indices.O1_HB_setpoint(:));
    change=find(z>0.5); differences=abs(setpoint-setpoint([T,1:T-1]));
    [~,rank]=sort(differences(change),'ascend');
    cheap(change(rank))=1./(1:numel(change)).';
end
scores = zeros(numel(starts),1);
for j = 1:numel(starts)
    window = 1+mod(starts(j)-1+(0:length_h-1),T);
    scores(j) = sum(z(window))+sum(cheap(window));
    guided=value(decomposition,'repair_hours',[]);
    if ~isempty(guided)
        scores(j)=scores(j)+sum(ismember(guided(1:min(end,2*length_h)),window));
    end
end
[~,order] = sort(scores,'descend');
% 逐轮移动窗口，并在后续轮次联合释放远隔窗口，允许年度氢量重新分配。
first = 1+mod(local_index-1+(round_index-1)*ctx.config.economic_local_passes,numel(starts));
number = min(1+floor((round_index-1)/numel(lengths)),numel(starts)); hours = [];
for j = 0:number-1
    selected = order(1+mod(first-1+floor(j*numel(starts)/number),numel(starts)));
    hours = union(hours,1+mod(starts(selected)-1+(-1:length_h),T));
end
end

function base = apply_block_cuts(base,cuts)
p = base.physical_problem;
n = numel(p.lb); rhs = zeros(numel(cuts),1);
row_index = cell(numel(cuts),1); column_index = row_index; coefficients = row_index;
for j = 1:numel(cuts)
    row_index{j} = repmat(j,numel(cuts(j).columns),1);
    column_index{j} = cuts(j).columns(:);
    coefficients{j} = -full(cuts(j).coefficients(:));
    rhs(j) = -cuts(j).lower_bound;
end
rows = sparse(vertcat(row_index{:}),vertcat(column_index{:}), ...
    vertcat(coefficients{:}),numel(cuts),n);
p.Aineq = [p.Aineq;rows]; p.bineq = [p.bineq(:);rhs];
base.problem = p;
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
if ~isfield(d,'park') || isempty(fieldnames(d.park)) || value(d,'algorithm_version',0)~=3, return; end
p=d.park;
allowed=economic.K_lower~=p.K_lower || economic.K_upper~=p.K_upper || ...
    economic.cost_cap_usd~=p.cap_usd || ...
    value(cfg,'economic_block_max_time_s',60)>p.price_max_s || ...
    cfg.economic_block_round_time_s>1.5*p.round_time_s || ...
    max(cfg.economic_block_lengths_h)>p.max_length_h;
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
if value(d,'algorithm_version',0)~=3
    d.algorithm_version=3; d.sweep=struct(); d.stalled_sweeps=0;
    d.level_step=2; d.dual_sweeps_since_merge=0;
    d.merge_limit=min(384,max(cfg.economic_block_lengths_h));
    d.park=struct();
end
if isfield(d,'park') && isempty(fieldnames(d.park)), d=rmfield(d,'park'); end
if economic.cost_cap_usd~=d.bound_cap_usd || value(d,'active_K_upper',Inf)~=economic.K_upper
    d.stalled_sweeps=0; d.dual_sweeps_since_merge=0;
    if isfield(d,'partition_trial'), d=rmfield(d,'partition_trial'); end
end
if economic.cost_cap_usd>d.bound_cap_usd
    d.best_lower=-Inf; d.certificate=struct(); % A relaxed cap cannot inherit this bound.
end
d.bound_cap_usd=economic.cost_cap_usd;
d.active_K_upper=economic.K_upper;
d.stop_reason="time_budget";
elapsed_before=value(d,'total_elapsed_s',0);
seed=solution_vector(base.indices,economic.satisfied_evidence.solution,numel(base.cost_f));
if isempty(seed), seed=original.x0(:); end
seeds=decomposition_seeds(state,base,seed);
last_progress=tic; added_cuts=0; full_sweeps=0;
while toc(started)<seconds && record.solve_calls<value(cfg,'economic_decomposition_solve_limit',Inf)
    previous_best=d.best_lower;
    partial=isfield(d.sweep,'next_block') && isfield(d.sweep,'units') && d.sweep.next_block>0 && ...
        d.sweep.cap_usd==economic.cost_cap_usd && d.sweep.K_upper==economic.K_upper && ...
        isequal(d.sweep.ranges,d.ranges) && d.sweep.cut_count<=numel(state.block_cuts) && ...
        isequal(d.sweep.units,base.units) && d.sweep.grid_exact==base.grid_exact;
    cut_count=numel(state.block_cuts);
    if partial, cut_count=d.sweep.cut_count; end
    working=apply_block_cuts(base,state.block_cuts(1:cut_count));
    p=working.problem; p.f=base.count_f;
    p.bineq(base.update_row)=min(ctx.T,economic.K_upper)*base.update_coefficient;
    p.Aineq=[p.Aineq;base.cost_f.']; p.bineq=[p.bineq;economic.cost_cap_usd-base.offset];
    [model,row_scale]=scaled_model(p,base.units); model.vtype(p.intcon)='I';
    if base.grid_exact, model.vtype(base.indices.u_purchase(:))='C'; end
    [blocks,link,ids,d]=decomposition_partition(model,base,d,seeds,cut_count,ctx.T);
    B=numel(blocks); A=model.A(link,:); rhs=model.rhs(link); sense=model.sense(link);
    d.coverage_rows=numel(link)+sum(cellfun(@(b) numel(b.rows),blocks));
    d.total_rows=size(model.A,1); d.coverage_variables=sum(cellfun(@(b) numel(b.col),blocks));
    assert(d.coverage_rows==d.total_rows && d.coverage_variables==numel(model.obj), ...
        'O1:incomplete_decomposition','Complete row and variable coverage is mandatory.');
    [master,cost,which]=decomposition_master(blocks,A,base.units);
    if ~partial
        master_problem=struct('Aineq',master(sense=='<',:),'bineq',rhs(sense=='<'), ...
            'Aeq',[master(sense=='=',:);sparse(which,1:numel(cost),1,B,numel(cost))], ...
            'beq',[rhs(sense=='=');ones(B,1)],'f',cost,'lb',zeros(numel(cost),1), ...
            'ub',Inf(numel(cost),1),'intcon',[],'x0',[]);
        master_problem.x0=decomposition_master_seed(blocks,seeds,master_problem);
        rm=relaxation(master_problem,ones(numel(cost),1), ...
            min(cfg.economic_block_lp_time_s,max(0.01,seconds-toc(started))),ctx,"master");
        d.master_report=rm; d.master_report.x=[]; d.master_report.dual=[];
        d.master_upper=Inf;
        pi=[]; master_pi=[]; method="master_dual";
        if ~isempty(rm.dual)
            m_i=sum(sense=='<'); m_e=sum(sense=='='); pi=zeros(numel(rhs),1);
            pi(sense=='<')=rm.dual(1:m_i); pi(sense=='=')=rm.dual(m_i+(1:m_e));
            master_pi=pi;
        elseif ~isempty(d.center) && all(ismember(ids,d.center_ids))
            [~,where]=ismember(ids,d.center_ids); pi=d.center(where); method="cached_certified_dual";
        end
        if isempty(pi) || ~isfinite(d.best_lower)
            root=relaxation(p,base.units,min(cfg.economic_block_lp_time_s, ...
                max(0,seconds-toc(started))),ctx);
            if ~isempty(root.dual)
                d.best_lower=max(d.best_lower,root.bound-decomposition_margin(root.bound));
                if isempty(pi), pi=root.dual(link).*row_scale(link); method="cut_LP_dual"; end
            elseif isempty(pi)
                d.stop_reason="LP_without_valid_dual"; break;
            end
        end
        if ~isempty(rm.x)
            d.master_upper=cost.'*rm.x+decomposition_margin(cost.'*rm.x);
            d.repair_hours=decomposition_repair(blocks,which,rm.x,seed,base,ctx.T);
            if full_sweeps>0 || ~isempty(d.history)
                center=pi;
                if ~isempty(d.center)
                    [found,where]=ismember(ids,d.center_ids);
                    center(found)=d.center(where(found));
                end
                [trial,ok]=decomposition_level(master,cost,which,rhs,sense,center, ...
                    d.best_lower,d.master_upper,seconds-toc(started),ctx,value(d,'level_step',2));
                if ok, pi=trial; method="level"; end
                if mod(numel(d.history)+1,4)==0 && ~isempty(master_pi)
                    % Raw master dual periodically discovers columns hidden by stabilization.
                    pi=master_pi; method="master_dual";
                end
            end
        end
        fprintf('[O1] RMP：算法=%g，状态=%s，原残差=%.3g，缩放残差=%.3g，DW上界=%.6f，乘子=%s，说明=%s。\n', ...
            rm.algorithm,rm.status,rm.original_residual,rm.scaled_residual,d.master_upper,method,rm.reason);
        pi=double(sense=='=') .* pi + double(sense=='<') .* min(0,pi);
        if any(~isfinite(pi)), d.stop_reason="nonfinite_dual"; break; end
        d.sweep=struct('next_block',1,'pi',pi,'rhs',rhs,'link_ids',ids, ...
            'lower',-Inf(B,1),'upper',Inf(B,1),'status',strings(B,1), ...
            'cap_usd',economic.cost_cap_usd,'K_upper',economic.K_upper, ...
            'ranges',d.ranges,'cut_count',cut_count,'method',method);
        d.sweep.units=base.units; d.sweep.grid_exact=base.grid_exact;
        d.sweep.previous_lower=previous_best;
        if numel(d.price_time)~=B, d.price_time=repmat(cfg.economic_block_time_s,B,1); end
    else
        assert(isequal(ids,d.sweep.link_ids) && isequal(rhs,d.sweep.rhs), ...
            'O1:changed_partial_master','A resumed pricing sweep must use the identical master.');
    end
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
            ii=find(q.vtype~='C'); x(ii)=round(x(ii));
            if decomposition_violation(q,x)<=2e-7
                candidate=x.*base.units(blocks{b}.col);
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
            [state.block_cuts,added]=decomposition_add_cut(state.block_cuts,cut,cfg.economic_block_max_cuts);
            added_cuts=added_cuts+added;
        end
        d.sweep.next_block=b+1;
        if mod(b,max(1,cfg.economic_block_batch))==0 || toc(last_progress)>30
            state.decomposition=d;
            state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
            fprintf('[O1] 完整分解：定价%d/%d块，完整覆盖证书=%d，已用%.1f s。\n', ...
                b,B,isfield(d.certificate,'complete'),toc(started)); last_progress=tic;
        end
    end
    if d.sweep.next_block<=B, d.stop_reason="incomplete_pricing_sweep"; break; end
    previous=value(d.sweep,'previous_lower',d.best_lower);
    [d,lower,oracle_gap]=decomposition_certificate(d,rhs,ids,economic);
    state.decomposition=d;
    state.decomposition.total_elapsed_s=elapsed_before+toc(started);
    checkpoint(state); % Publish the complete sweep before retries.
    % Refine the worst oracles at the SAME multipliers before changing the dual.
    target=value(cfg,'economic_decomposition_oracle_tolerance',1);
    [~,difficult_order]=sort(d.sweep.upper-d.sweep.lower,'descend');
    for b=difficult_order(1:min(4,B)).'
        if oracle_gap<=target || d.best_lower>=economic.K_upper-1e-5 || ...
                toc(started)>=seconds || ...
                record.solve_calls>=value(cfg,'economic_decomposition_solve_limit',Inf)
            break;
        end
        next_budget=min(value(cfg,'economic_block_max_time_s',60),2*d.price_time(b));
        if next_budget<=d.price_time(b), continue; end
        q=blocks{b}.model; q.obj=model.obj(blocks{b}.col)-A(:,blocks{b}.col).'*d.sweep.pi;
        known=d.points{b}./base.units(blocks{b}.col); [~,best]=min(q.obj.'*known);
        q.start=known(:,best); price_started=tic;
        [extra,x,status]=decomposition_price(q,min(next_budget,seconds-toc(started)),ctx);
        record.solve_calls=record.solve_calls+1; d.price_time(b)=next_budget;
        d.sweep.lower(b)=max(d.sweep.lower(b),extra); d.sweep.status(b)=status;
        if ~isempty(x)
            ii=find(q.vtype~='C'); x(ii)=round(x(ii));
        end
        if ~isempty(x) && decomposition_violation(q,x)<=2e-7
            candidate=x.*base.units(blocks{b}.col);
            distance=max(abs(d.points{b}-candidate)./max(1,abs(candidate)),[],1);
            if all(distance>1e-7), d.points{b}(:,end+1)=candidate; end
        end
        d.sweep.upper(b)=min(q.obj.'*(d.points{b}./base.units(blocks{b}.col)));
        if isfinite(d.sweep.lower(b))
            coefficients=q.obj./base.units(blocks{b}.col); scale=max(1,max(abs(coefficients)));
            cut=struct('columns',blocks{b}.col.','coefficients',sparse(coefficients.'/scale), ...
                'lower_bound',d.sweep.lower(b)/scale,'start_hour',blocks{b}.start_hour, ...
                'length_h',blocks{b}.length_h,'solver_status',status,'elapsed_s',toc(price_started));
            [state.block_cuts,added]=decomposition_add_cut(state.block_cuts,cut,cfg.economic_block_max_cuts);
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
        'cap_usd',economic.cost_cap_usd,'complete',isfinite(lower),'method',d.sweep.method);
    d.history=[d.history;entry]; full_sweeps=full_sweeps+1;
    if isfield(d,'partition_trial')
        d.partition_trial.completed_sweeps=d.partition_trial.completed_sweeps+1;
        d.partition_trial.lower_gain=d.best_lower-d.partition_trial.lower_before;
        fprintf('[O1] 合并试验：%d -> %d块，完成%d轮，下界提升%.6f，DW差距%.6f。\n', ...
            d.partition_trial.blocks_before,size(d.ranges,1),d.partition_trial.completed_sweeps, ...
            d.partition_trial.lower_gain,d.master_upper-d.best_lower);
    end
    d.stalled_sweeps=(d.stalled_sweeps+1)*(d.best_lower<=previous+0.2);
    if ismember(d.sweep.method,["level","master_dual"])
        d.dual_sweeps_since_merge=value(d,'dual_sweeps_since_merge',0)+1;
    end
    if d.sweep.method=="level"
        if d.best_lower>previous+0.25*value(d,'level_step',2)
            d.level_step=min(32,2*value(d,'level_step',2));
        else
            d.level_step=max(0.25,0.5*value(d,'level_step',2));
        end
    end
    price_gaps=d.sweep.upper-d.sweep.lower;
    d.sweep=struct();
    if isfinite(lower)
        fprintf('[O1] DW=[%.6f,%.6f]，整数下界=%g，定价误差<=%.6g；%d块、%d列。\n', ...
            d.best_lower,d.master_upper,ceil(d.best_lower-1e-5),oracle_gap,B,entry.columns);
    end
    target=value(cfg,'economic_decomposition_oracle_tolerance',1);
    if oracle_gap>target
        difficult=~isfinite(price_gaps) | price_gaps>target/B;
        d.price_time(difficult)=min(value(cfg,'economic_block_max_time_s',60),2*d.price_time(difficult));
        d.stop_reason="increase_pricing_effort";
    elseif economic.K_upper-ceil(d.best_lower-1e-5)>cfg.economic_final_interval && ...
            (d.master_upper-d.best_lower<=value(cfg,'economic_decomposition_tolerance',0.2) || ...
            (d.stalled_sweeps>=value(cfg,'economic_decomposition_stall_sweeps',6) && ...
            value(d,'dual_sweeps_since_merge',0)>=value(cfg,'economic_decomposition_min_dual_sweeps',8)))
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
            value(cfg,'economic_decomposition_min_dual_sweeps',8)
        d.stop_reason="partition_trial_without_bound_gain";
    end
    state.decomposition=d;
    state.decomposition.total_elapsed_s=elapsed_before+toc(started); checkpoint(state);
    if ismember(d.stop_reason,["maximum_partition_strength","dual_stalled_with_open_DW_gap", ...
            "partition_trial_without_bound_gain"]), break; end
    if d.best_lower>=economic.K_upper-1e-5
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

function [d,lower,oracle_gap]=decomposition_certificate(d,rhs,ids,economic)
% Only ONE multiplier vector and ALL finite block lower bounds certify this sum.
margin=decomposition_margin(rhs.'*d.sweep.pi)+sum(arrayfun(@decomposition_margin,d.sweep.lower));
lower=rhs.'*d.sweep.pi+sum(d.sweep.lower)-margin;
oracle_gap=sum(max(0,d.sweep.upper-d.sweep.lower));
if ~isfinite(lower), return; end
if lower>d.master_upper+1e-4
    error('O1:invalid_DW_bounds','DW lower certificate exceeds the restricted master upper bound.');
end
certificate=struct('complete',true,'pi',d.sweep.pi,'rhs',rhs,'link_ids',ids, ...
    'block_lower',d.sweep.lower,'block_upper',d.sweep.upper,'block_status',d.sweep.status, ...
    'ranges',d.ranges,'cut_count',d.sweep.cut_count,'cap_usd',economic.cost_cap_usd, ...
    'K_upper',economic.K_upper,'margin',margin,'lower',lower,'oracle_gap',oracle_gap, ...
    'method',d.sweep.method,'units',d.sweep.units,'grid_exact',d.sweep.grid_exact);
if ~isfield(d.certificate,'lower') || lower>d.certificate.lower
    d.certificate=certificate; d.center=d.sweep.pi; d.center_ids=ids;
end
d.best_lower=max(d.best_lower,lower);
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

function [blocks,link,ids,d]=decomposition_partition(model,base,d,seeds,cut_count,T)
hours=variable_hours(base,T); owner=zeros(numel(hours),1);
for b=1:size(d.ranges,1)
    owner(hours>=d.ranges(b,1) & hours<=d.ranges(b,2))=b;
end
owner(hours==T+1)=size(d.ranges,1);
owner(owner==0)=size(d.ranges,1)+1;
[~,~,owner]=unique(owner); B=max(owner); blocks=cell(B,1);
original_rows=size(base.physical_problem.Aineq,1)+size(base.physical_problem.Aeq,1);
mi=size(base.physical_problem.Aineq,1); me=size(base.physical_problem.Aeq,1);
row_ids=[(1:mi).';original_rows+(1:cut_count).';-1;mi+(1:me).'];
physical=row_ids>0 & row_ids<=original_rows; physical(base.update_row)=false;
counts=full(sum(spones(model.A),2)); assigned=false(size(counts));
old_points=d.points; old_columns=d.point_columns; d.points=cell(B,1); d.point_columns=cell(B,1);
for b=1:B
    col=find(owner==b);
    rows=find(physical & counts>0 & full(sum(spones(model.A(:,col)),2))==counts);
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
    good=false(1,size(points,2));
    for k=1:size(points,2), good(k)=decomposition_violation(q,points(:,k)./base.units(col))<=2e-7; end
    points=unique(points(:,good).','rows','stable').';
    if isempty(points), error('O1:no_decomposition_seed','No valid local column in block %d.',b); end
    d.points{b}=points; d.point_columns{b}=col;
    h=hours(col); h=h(h>0 & h<=T); start_hour=0; length_h=0;
    if ~isempty(h), start_hour=min(h); length_h=max(h)-start_hour+1; end
    blocks{b}=struct('col',col,'rows',rows,'model',q,'points',points,'objective',model.obj(col), ...
        'start_hour',start_hour,'length_h',length_h);
end
link=find(~assigned); ids=row_ids(link);
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
end

function [cuts,added]=decomposition_add_cut(cuts,cut,maximum)
added=0;
if ~any(cut.coefficients) || ~isfinite(cut.lower_bound), return; end
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

function [pi,ok]=decomposition_level(A,cost,which,rhs,sense,center,lower,upper,seconds,ctx,step)
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
d.stalled_sweeps=0; d.dual_sweeps_since_merge=0; d.level_step=2;
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
if ~isempty(p.x0), model.start = p.x0(:)./units; end
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
    parameters.BestObjStop = task.target+1e-6;
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
            stop = values.fval <= task.target+1e-7;
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

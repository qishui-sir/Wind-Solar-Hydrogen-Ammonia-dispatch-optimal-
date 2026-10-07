function tests = test_O1_interval_batch
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
test_case.TestData.project_dir = fileparts(fileparts(mfilename('fullpath')));
test_case.TestData.old_path = path;
addpath(genpath(fullfile(test_case.TestData.project_dir, 'src')));
end

function teardownOnce(test_case)
path(test_case.TestData.old_path);
end

function test_interval_ends_at_reference_count(test_case)
[params, data, config] = small_case();
config.frontier_certification_points_per_run = 10;
config.frontier_certification_run_budget_s = 30;
study = run_case(params, data, config);
cached = load(fullfile(config.cache_directory, 'O1_fixed_k_cache.mat'), 'cache_sets');
entries = cached.cache_sets(1).entries;
point = entries(find([entries.K] == 0, 1)).record;
verifyTrue(test_case, point.has_incumbent);
verifyEqual(test_case, point.count_upper, 0);

% 用已验证的恒定负荷方案作为参考上界，保留原无次数限制的全局下界。
payload = load(fullfile(config.cache_directory, 'O1_stage1_cache.mat'));
reference = payload.reference;
reference.solution = point.solution;
reference.objective_upper = point.objective_upper;
reference.system_cost_upper = point.objective_upper;
reference.absolute_gap = reference.objective_upper - reference.objective_lower;
reference.relative_gap = reference.absolute_gap / abs(reference.objective_upper);
reference.is_proven = false;
payload.reference = reference;
save(fullfile(config.cache_directory, 'O1_stage1_cache.mat'), '-struct', 'payload', '-v7.3');
config.frontier_certification_run_budget_s = eps;
study = run_case(params, data, config);
verifyEqual(test_case, study.reference.count_upper, 0);
verifyEqual(test_case, study.frontier.K, 0);
verifyEqual(test_case, study.cost_certification.K, 0);
verifyEqual(test_case, study.feasibility.scheduler.elapsed_s, 0);
end

function test_batch_attempts_all_pending_k_and_resumes(test_case)
[params, data, config] = small_case();
initial = run_case(params, data, config);
pending_K = initial.frontier.K(~initial.cost_certification.is_resolved);
verifyGreaterThan(test_case, numel(pending_K), 1);

% 模拟每个K都在无首解时超时，检验整区间遍历、有限重试及跨轮续算。
stub_dir = tempname;
mkdir(stub_dir);
write_stub(stub_dir, 'intlinprog', ...
    ['function [x,fval,exitflag,output]=intlinprog(varargin)', newline, ...
    'x=[];fval=NaN;exitflag=0;output=struct(''message'',''TEST_TIME_LIMIT'',''absolutegap'',Inf);', ...
    newline, 'end', newline]);
old_path = path;
cleanup = onCleanup(@() restore_functions(old_path)); %#ok<NASGU>
addpath(stub_dir, '-begin');
clear intlinprog;
config.frontier_certification_points_per_run = Inf;
config.frontier_certification_run_budget_s = Inf;
config.frontier_certification_max_attempts = 2;
study = run_case(params, data, config);
verifyEqual(test_case, study.frontier_state.certification_new_points, 2 * numel(pending_K));
verifyTrue(test_case, study.frontier_state.certification_retry_exhausted);
verifyEqual(test_case, study.frontier_state.certification_retry_exhausted_K, pending_K);
verifyFalse(test_case, study.frontier_state.certification_complete);
verifyFalse(test_case, any(study.frontier.is_infeasible));
verifyEqual(test_case, cached_attempts(config, pending_K), 2 * ones(size(pending_K)));

config.frontier_certification_max_attempts = 1;
study = run_case(params, data, config);
verifyEqual(test_case, study.frontier_state.certification_new_points, numel(pending_K));
verifyEqual(test_case, cached_attempts(config, pending_K), 3 * ones(size(pending_K)));
verifyEqual(test_case, study.frontier_state.next_pending_K, min(pending_K));
end

function test_main_starts_interval_batch(test_case)
stub_dir = tempname;
mkdir(stub_dir);
write_stub(stub_dir, 'baseline', ...
    ['function result=baseline(~,data,runner)', newline, ...
    'result=runner(struct(''time_count'',data.time_count));', newline, 'end', newline]);
write_stub(stub_dir, 'O1', ...
    ['function result=O1(model,config)', newline, ...
    'result=struct(''config'',config,''time_count'',model.time_count);', newline, 'end', newline]);
old_path = path;
old_dir = pwd;
cleanup = onCleanup(@() restore_main_stubs(old_path, old_dir)); %#ok<NASGU>
cd(stub_dir); % 当前目录优先于main添加的源码路径。
clear baseline O1;
captured = invoke_main();
verifyTrue(test_case, captured.config.frontier_all_k);
verifyEqual(test_case, captured.config.frontier_k_start, 84);
verifyEqual(test_case, captured.config.frontier_k_step, 10);
verifyEmpty(test_case, captured.config.frontier_k);
verifyEmpty(test_case, captured.config.frontier_key_k);
verifyTrue(test_case, isinf(captured.config.frontier_certification_points_per_run));
verifyTrue(test_case, isinf(captured.config.frontier_certification_run_budget_s));
verifyEqual(test_case, captured.config.frontier_screening_max_time_s, 600);
verifyEqual(test_case, captured.config.frontier_certification_max_time_s, 3600);
verifyFalse(test_case, captured.config.gurobi_checkpoint_enabled);
verifyLessThanOrEqual(test_case, captured.config.frontier_certification_tolerance_usd_t, 0.5);
end

function test_sampled_interval_keeps_endpoints(test_case)
[params, data, config] = small_case();
config.frontier_k_start = 1;
config.frontier_k_step = 3;
study = run_case(params, data, config);
verifyEqual(test_case, study.reference.count_upper, 4);
verifyEqual(test_case, study.frontier.K, [1; 3; 4]);
verifyEqual(test_case, study.cost_certification.K, study.frontier.K);
verifyTrue(test_case, study.frontier_state.sampled_interval);
verifyEqual(test_case, study.frontier_state.deferred_integer_points, 1);
verifyEmpty(test_case, study.frontier_state.anchor_K);
verifyEqual(test_case, study.feasibility.scheduler.elapsed_s, 0);
verifyEqual(test_case, study.status, 'incomplete_sampled_cost_certification');
end

function test_extra_sample_reuses_short_pass_cache(test_case)
[params, data, config] = small_case();
config.frontier_k_start = 1;
config.frontier_k_step = 3;
run_case(params, data, config); % 先缓存真实参考解，再替换固定K求解器。
stub_dir = tempname;
mkdir(stub_dir);
write_stub(stub_dir, 'intlinprog', ...
    ['function [x,fval,exitflag,output]=intlinprog(problem)', newline, ...
    'global O1_SCREENING_TRACE;', newline, ...
    'O1_SCREENING_TRACE(end+1,1)=problem.options.MaxTime;', newline, ...
    'x=[];fval=NaN;exitflag=0;output=struct(''message'',''TEST_TIME_LIMIT'',''absolutegap'',Inf);', ...
    newline, 'end', newline]);
old_path = path;
cleanup = onCleanup(@() restore_screening_stub(old_path)); %#ok<NASGU>
addpath(stub_dir, '-begin');
clear intlinprog;
global O1_SCREENING_TRACE;
O1_SCREENING_TRACE = zeros(0,1);
config.frontier_certification_run_budget_s = Inf;
config.frontier_certification_points_per_run = 1;
config.frontier_screening_max_time_s = 600;
config.frontier_certification_max_time_s = 3600;
study = run_case(params, data, config);
verifyEqual(test_case, O1_SCREENING_TRACE, 600);
verifyEqual(test_case, cached_attempts(config, 1), 1);
verifyEqual(test_case, study.frontier_state.next_pending_K, 3);

% 增加未采样的K=2只改变任务列表，不改变缓存签名或重复已完成的短遍历。
config.frontier_k = 2;
O1_SCREENING_TRACE = zeros(0,1);
study = run_case(params, data, config);
verifyEqual(test_case, study.frontier.K, [1; 2; 3; 4]);
verifyEqual(test_case, O1_SCREENING_TRACE, 600);
verifyEqual(test_case, cached_attempts(config, [1; 2]), [1; 1]);
verifyFalse(test_case, study.frontier_state.sampled_interval);
verifyEqual(test_case, study.frontier_state.deferred_integer_points, 0);
verifyEqual(test_case, study.frontier_state.next_pending_K, 3);
verifyFalse(test_case, any(study.frontier.is_infeasible));
end

function test_short_pass_precedes_difficult_points_and_resumes(test_case)
[params, data, config] = small_case();
initial = run_case(params, data, config);
pending_K = initial.frontier.K(~initial.cost_certification.is_resolved);
verifyGreaterThan(test_case, numel(pending_K), 1);
stub_dir = tempname;
mkdir(stub_dir);
write_stub(stub_dir, 'intlinprog', ...
    ['function [x,fval,exitflag,output]=intlinprog(problem)', newline, ...
    'global O1_SCREENING_TRACE;', newline, ...
    'O1_SCREENING_TRACE(end+1,1)=problem.options.MaxTime;', newline, ...
    'x=[];fval=NaN;exitflag=0;output=struct(''message'',''TEST_TIME_LIMIT'',''absolutegap'',Inf);', ...
    newline, 'end', newline]);
old_path = path;
cleanup = onCleanup(@() restore_screening_stub(old_path)); %#ok<NASGU>
addpath(stub_dir, '-begin');
clear intlinprog;
global O1_SCREENING_TRACE;
O1_SCREENING_TRACE = zeros(0,1);
config.frontier_certification_points_per_run = Inf;
config.frontier_certification_run_budget_s = Inf;
config.frontier_certification_max_attempts = 2;
config.frontier_screening_max_time_s = 600;
config.frontier_certification_max_time_s = 3600;
study = run_case(params, data, config);
verifyEqual(test_case, O1_SCREENING_TRACE, ...
    [600 * ones(numel(pending_K),1); 3600 * ones(numel(pending_K),1)]);
verifyEqual(test_case, study.frontier_state.screening_new_points, numel(pending_K));
verifyTrue(test_case, study.frontier_state.screening_complete);
verifyFalse(test_case, study.frontier_state.certification_complete);
verifyFalse(test_case, any(study.frontier.is_infeasible));
verifyEqual(test_case, study.frontier_state.difficult_K, pending_K);
loaded = load(fullfile(config.cache_directory, 'O1_fixed_k_cache.mat'), 'cache_sets');
entries = loaded.cache_sets(1).entries;
for K = pending_K.'
    record = entries(find([entries.K] == K,1)).record;
    verifyEqual(test_case, record.screening_attempts, 1);
    verifyFalse(test_case, record.is_certified);
end

% 再次运行复用短遍历标记，只重算困难点，不重复600秒首轮。
O1_SCREENING_TRACE = zeros(0,1);
config.frontier_certification_max_attempts = 1;
study = run_case(params, data, config);
verifyEqual(test_case, O1_SCREENING_TRACE, 3600 * ones(numel(pending_K),1));
verifyEqual(test_case, study.frontier_state.screening_new_points, 0);
verifyTrue(test_case, study.frontier_state.screening_complete);
end

function test_interrupted_short_pass_resumes_before_difficult_points(test_case)
[params, data, config] = small_case();
initial = run_case(params, data, config);
pending_K = initial.frontier.K(~initial.cost_certification.is_resolved);
verifyGreaterThan(test_case, numel(pending_K), 1);
stub_dir = tempname;
mkdir(stub_dir);
write_stub(stub_dir, 'intlinprog', ...
    ['function [x,fval,exitflag,output]=intlinprog(problem)', newline, ...
    'global O1_SCREENING_TRACE;', newline, ...
    'O1_SCREENING_TRACE(end+1,1)=problem.options.MaxTime;', newline, ...
    'x=[];fval=NaN;exitflag=0;output=struct(''message'',''TEST_TIME_LIMIT'',''absolutegap'',Inf);', ...
    newline, 'end', newline]);
old_path = path;
cleanup = onCleanup(@() restore_screening_stub(old_path)); %#ok<NASGU>
addpath(stub_dir, '-begin');
clear intlinprog;
global O1_SCREENING_TRACE;
O1_SCREENING_TRACE = zeros(0,1);
config.frontier_certification_run_budget_s = Inf;
config.frontier_certification_points_per_run = 1;
config.frontier_certification_max_attempts = 1;
config.frontier_screening_max_time_s = 600;
config.frontier_certification_max_time_s = 3600;
study = run_case(params, data, config);
verifyEqual(test_case, O1_SCREENING_TRACE, 600);
verifyFalse(test_case, study.frontier_state.screening_complete);
verifyEqual(test_case, study.frontier_state.difficult_K, pending_K(1));
verifyEqual(test_case, study.frontier_state.next_pending_K, pending_K(2));

O1_SCREENING_TRACE = zeros(0,1);
config.frontier_certification_points_per_run = Inf;
study = run_case(params, data, config);
verifyEqual(test_case, O1_SCREENING_TRACE, ...
    [600 * ones(numel(pending_K)-1,1); 3600]);
verifyTrue(test_case, study.frontier_state.screening_complete);
verifyEqual(test_case, study.frontier_state.difficult_K, pending_K);
verifyFalse(test_case, study.frontier_state.certification_complete);
end

function test_batch_certifies_feasible_interval(test_case)
[params, data, config] = small_case();
config.cost_relative_gap = 0;
config.frontier_certification_points_per_run = Inf;
config.frontier_certification_run_budget_s = Inf;
config.frontier_certification_max_attempts = 2;
study = run_case(params, data, config);
verifyTrue(test_case, study.frontier_state.interval_batch);
verifyEqual(test_case, study.frontier.K, (0:study.reference.count_upper).');
verifyTrue(test_case, all(study.cost_certification.is_resolved));
verifyLessThanOrEqual(test_case, ...
    study.frontier.uncertainty_usd_t(study.frontier.is_certified), 0.5);
verifyEqual(test_case, study.feasibility.scheduler.elapsed_s, 0);
end

function captured = invoke_main()
evalc('main;');
captured = O1_results;
end

function [params, data, config] = small_case()
T = 4;
params = my_system('s2');
params.AEL.common.startup = true;
params.environment.co2_enabled = false;
params.grid.curtail_limit = 1;
params.grid.max_sell = 1;
params.solver.display = 'off';
data = struct('time_count', T, 'time_step_h', 1, 'pv_power_kw', zeros(T, 1), ...
    'pw_power_kw', [100000; 50000; 100000; 50000], ...
    'renewable_power_kw', [100000; 50000; 100000; 50000], ...
    'time', datetime(2022, 1, 1) + hours((0:T-1).'));
work_dir = tempname;
mkdir(work_dir);
config = struct('nh3_target_t', 0.6 * params.HB.nh3_output * T / 1000, ...
    'frontier_all_k', true, 'enable_window_cuts', false, 'cache_directory', work_dir, ...
    'frontier_run_budget_s', eps, 'frontier_certification_run_budget_s', eps, ...
    'frontier_certification_max_time_s', 5, 'cost_allowance_usd_t', [0, 1], ...
    'cost_relative_gap', 1e-3, 'display', 'off');
end

function study = run_case(params, data, config)
evalc('study = baseline(params, data, @(model) O1(tighten(model), config));');
end

function model = tighten(model)
model.options = optimoptions(model.options, 'ConstraintTolerance', 1e-8);
end

function attempts = cached_attempts(config, K_values)
loaded = load(fullfile(config.cache_directory, 'O1_fixed_k_cache.mat'), 'cache_sets');
entries = loaded.cache_sets(1).entries;
attempts = arrayfun(@(K) entries(find([entries.K] == K, 1)).record.certification_attempts, K_values);
end

function write_stub(directory, name, contents)
fid = fopen(fullfile(directory, [name, '.m']), 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s', contents);
end

function restore_functions(old_path)
path(old_path);
clear intlinprog;
end

function restore_screening_stub(old_path)
restore_functions(old_path);
clear global O1_SCREENING_TRACE;
end

function restore_main_stubs(old_path, old_dir)
cd(old_dir);
path(old_path);
clear baseline O1;
end

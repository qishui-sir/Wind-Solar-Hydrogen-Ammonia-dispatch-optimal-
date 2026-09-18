function tests = test_baseline_compact_ael
tests = functiontests(localfunctions);
end

function test_start_stop_counts_are_implicitly_integer(test_case)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src');
old_path = path;
cleanup = onCleanup(@() path(old_path));
addpath(src_dir, fullfile(src_dir, 'params'), ...
    fullfile(src_dir, 'results'), fullfile(src_dir, 'class'));

data_cfg = struct('pv_year', 2022, 'pw_year', 2022, ...
    'pv_capacity_kw', 200000, 'pw_capacity_kw', 200000, ...
    'day_count', 1);
renewable_data = load_res_year(data_cfg);
params = my_system('s2');
audit = baseline(params, renewable_data, @audit_integrality);

verifyFalse(test_case, audit.su_is_declared_integer);
verifyFalse(test_case, audit.sd_is_declared_integer);
verifyTrue(test_case, audit.online_is_declared_integer);
verifyTrue(test_case, audit.direction_is_declared_integer);
end

function audit = audit_integrality(model)
solver_model = prob2struct(model.problem, 'Solver', 'intlinprog');
indices = varindex(model.problem);
audit = struct();
audit.su_is_declared_integer = ...
    any(ismember(indices.SU_AEL(:), solver_model.intcon));
audit.sd_is_declared_integer = ...
    any(ismember(indices.SD_AEL(:), solver_model.intcon));
audit.online_is_declared_integer = ...
    all(ismember(indices.n_ael(:), solver_model.intcon));
audit.direction_is_declared_integer = ...
    all(ismember(indices.I_AEL_up(:), solver_model.intcon));
end

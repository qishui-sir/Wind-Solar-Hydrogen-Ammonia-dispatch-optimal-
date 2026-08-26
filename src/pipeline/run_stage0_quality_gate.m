function report = run_stage0_quality_gate(config)
%RUN_STAGE0_QUALITY_GATE Generate manifests and enforce reproducibility checks.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = bootstrap_project();
test_scope = string(option_value(config, 'test_scope', "quick"));
assert_success = option_value(config, 'assert_success', true);

report = struct();
report.stage = "stage0_quality_gate";
report.generated_at = string(datetime('now', 'TimeZone', 'local'));
report.project_dir = string(project_dir);
report.inventory = stage0_manifest("files", struct( ...
    'project_dir', project_dir, 'write_outputs', true));
report.environment = stage0_manifest("environment", struct( ...
    'project_dir', project_dir, 'write_outputs', true));
report.results_manifest = stage0_manifest("results", struct( ...
    'project_dir', project_dir, 'write_outputs', true));
report.constraint_audit = stage0_constraint_audit(struct( ...
    'project_dir', project_dir, 'write_outputs', true));

freeze_config = struct('run_tests', false);
try
    report.freeze_check = stage0_freeze_check(freeze_config);
    report.freeze_check_passed = true;
catch exception
    report.freeze_check = struct('error_identifier', ...
        string(exception.identifier), 'error_message', string(exception.message));
    report.freeze_check_passed = false;
end

if test_scope == "full"
    report.test_results = run_full_tests(struct('assert_success', false));
elseif test_scope == "none"
    report.test_results = [];
else
    report.test_results = run_quick_tests(struct('assert_success', false));
end

if isempty(report.test_results)
    report.tests_passed = true;
else
    report.tests_passed = all([report.test_results.Passed]);
end

report.constraint_audit_error_count = nnz(startsWith( ...
    report.constraint_audit.AuditStatus, "audit_error:"));
report.constraint_audited_count = nnz( ...
    report.constraint_audit.AuditStatus == "audited");
report.constraint_hard_passed_count = nnz( ...
    report.constraint_audit.AuditStatus == "audited" & ...
    report.constraint_audit.HardConstraintsPassed);
report.constraint_hard_failed_count = nnz( ...
    report.constraint_audit.AuditStatus == "audited" & ...
    ~report.constraint_audit.HardConstraintsPassed);
report.constraint_audit_passed = report.constraint_audit_error_count == 0;

report.passed = report.freeze_check_passed && report.tests_passed && ...
    report.constraint_audit_passed;

manifest_dir = fullfile(project_dir, 'runs', 'manifest');
if ~isfolder(manifest_dir)
    mkdir(manifest_dir);
end
save(fullfile(manifest_dir, 'stage0_quality_gate_report.mat'), 'report');
write_quality_gate_doc(fullfile(project_dir, 'docs', ...
    'stage0_quality_gate_report.md'), report);

if assert_success && ~report.passed
    error('run_stage0_quality_gate:failed', ...
        'Stage 0 quality gate failed. Inspect docs/stage0_quality_gate_report.md.');
end
end

function project_dir = bootstrap_project()
pipeline_dir = fileparts(mfilename('fullpath'));
src_dir = fileparts(pipeline_dir);
project_dir = fileparts(src_dir);
addpath(fullfile(src_dir, 'utils'), '-begin');
project_dir = setup_project_paths(project_dir);
end

function write_quality_gate_doc(output_path, report)
fid = fopen(output_path, 'w');
if fid < 0
    error('run_stage0_quality_gate:write_failed', ...
        'Cannot write quality gate report: %s', output_path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Stage 0 Quality Gate Report\n\n');
fprintf(fid, '- Generated: `%s`\n', report.generated_at);
fprintf(fid, '- Project: `%s`\n', report.project_dir);
fprintf(fid, '- Source tree hash: `%s`\n', report.environment.source_tree_hash);
fprintf(fid, '- Freeze check passed: `%d`\n', report.freeze_check_passed);
fprintf(fid, '- Tests passed: `%d`\n', report.tests_passed);
fprintf(fid, '- Constraint audit generated without audit errors: `%d`\n', ...
    report.constraint_audit_passed);
fprintf(fid, '- Audited dispatch results: `%d`\n', ...
    report.constraint_audited_count);
fprintf(fid, '- Audited results passing hard checks: `%d`\n', ...
    report.constraint_hard_passed_count);
fprintf(fid, '- Audited results flagged for constraint review: `%d`\n', ...
    report.constraint_hard_failed_count);
fprintf(fid, '- Overall passed: `%d`\n\n', report.passed);
fprintf(fid, 'Generated artifacts:\n\n');
fprintf(fid, '- `runs/manifest/file_inventory.csv`\n');
fprintf(fid, '- `runs/manifest/source_manifest.csv`\n');
fprintf(fid, '- `runs/manifest/data_manifest.csv`\n');
fprintf(fid, '- `runs/manifest/environment_manifest.json`\n');
fprintf(fid, '- `runs/manifest/results_manifest.csv`\n');
fprintf(fid, '- `runs/manifest/constraint_audit.csv`\n\n');
fprintf(fid, 'Constraint rows flagged for review are retained in the audit ');
fprintf(fid, 'table. They are not silently excluded and should not be used ');
fprintf(fid, 'as manuscript evidence unless later protocol eligibility checks ');
fprintf(fid, 'accept them.\n');
end

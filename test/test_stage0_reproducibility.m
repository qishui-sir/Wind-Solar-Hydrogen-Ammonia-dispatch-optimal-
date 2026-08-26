function tests = test_stage0_reproducibility
tests = functiontests(localfunctions);
end

function setupOnce(~)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
addpath(fullfile(project_dir, 'src', 'utils'), '-begin');
setup_project_paths(project_dir);
end

function testSetupProjectPathsFindsProjectRoot(test_case)
test_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(test_dir);
detected = setup_project_paths(test_dir);

verifyEqual(test_case, detected, project_dir);
verifyTrue(test_case, isfolder(fullfile(detected, 'src')));
verifyTrue(test_case, isfile(fullfile(detected, 'docs', 'protocol_v5.md')));
end

function testFileInventoryClassifiesCoreFilesWithoutWriting(test_case)
inventory = stage0_manifest("files", struct('write_outputs', false));

verifyTrue(test_case, any(inventory.RelativePath == "src/dispatch_model.m"));
verifyTrue(test_case, any(inventory.RelativePath == "test/test_my_system.m"));
verifyTrue(test_case, any(inventory.Role == "raw_input"));
verifyTrue(test_case, all(strlength(inventory.SHA256) == 64));
end

function testEnvironmentSnapshotContainsSolverAndSourceHash(test_case)
environment = stage0_manifest("environment", struct('write_outputs', false));

verifyNotEmpty(test_case, environment.matlab_version);
verifyTrue(test_case, isfield(environment, 'intlinprog_options'));
verifyEqual(test_case, strlength(environment.source_tree_hash), 64);
end

function testResultsManifestCanRunWithoutWriting(test_case)
manifest = stage0_manifest("results", struct('write_outputs', false));

verifyTrue(test_case, all(ismember(["RelativePath", "Stage", "Status", ...
    "LCOA", "SHA256"], string(manifest.Properties.VariableNames))));
verifyTrue(test_case, height(manifest) >= 0);
end

function testConstraintAuditCanRunWithoutWriting(test_case)
audit_table = stage0_constraint_audit(struct('write_outputs', false));

verifyTrue(test_case, all(ismember(["RelativePath", "AuditStatus", ...
    "HardConstraintsPassed"], string(audit_table.Properties.VariableNames))));
verifyTrue(test_case, height(audit_table) >= 0);
end
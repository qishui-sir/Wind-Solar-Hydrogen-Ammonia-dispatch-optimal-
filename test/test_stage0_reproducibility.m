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
function testSharedOptionDefaultsPreserveExplicitValues(test_case)
options = struct('empty', [], 'zero', 0, 'disabled', false, 'value', 7);
verifyEqual(test_case, option_value(options, 'missing', 9), 9);
verifyEqual(test_case, option_value(options, 'empty', 9), 9);
verifyEqual(test_case, option_value(options, 'zero', 9), 0);
verifyEqual(test_case, option_value(options, 'disabled', true), false);
verifyEqual(test_case, option_value(options, 'value', 9), 7);
verifyEqual(test_case, option_value([], 'missing', 9), 9);
end

function testSharedDirectoryCreationIsIdempotent(test_case)
target = tempname;
cleanup = onCleanup(@() rmdir(target, 's')); %#ok<NASGU>
ensure_directory(target);
marker = fullfile(target, 'marker.txt');
fid = fopen(marker, 'w');
fprintf(fid, 'keep');
fclose(fid);
ensure_directory(target);
verifyEqual(test_case, fileread(marker), 'keep');
end

function testSetupFromOutsideProjectIsIdempotent(test_case)
anchor = mfilename('fullpath');
previous_dir = pwd;
previous_path = path;
cleanup = onCleanup(@() restore_environment(previous_dir, previous_path)); %#ok<NASGU>
cd(tempdir);
root = setup_project_paths(anchor);
first_path = path;
verifyEqual(test_case, setup_project_paths(anchor), root);
verifyEqual(test_case, path, first_path);
verifyEqual(test_case, which('option_value'), fullfile(root, 'src', 'utils', 'option_value.m'));
verifyEqual(test_case, which('ensure_directory'), fullfile(root, 'src', 'utils', 'ensure_directory.m'));
end

function restore_environment(previous_dir, previous_path)
cd(previous_dir);
path(previous_path);
end

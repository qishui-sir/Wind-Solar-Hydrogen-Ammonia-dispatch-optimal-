function output = stage0_manifest(kind, config)
%STAGE0_MANIFEST Generate Stage 0 reproducibility manifests.
% Use kind = "files", "environment", "results", or "all".

if nargin < 1 || isempty(kind)
    kind = "all";
end
if nargin < 2 || isempty(config)
    config = struct();
end

stage0_dir = fileparts(mfilename('fullpath'));
utils_dir = fullfile(fileparts(stage0_dir), 'utils');
if isfolder(utils_dir)
    addpath(utils_dir, '-begin');
end

kind = string(kind);
if ~isscalar(kind)
    error('stage0_manifest:bad_kind', ...
        'kind must be files, environment, results, or all.');
end
kind = lower(kind);

switch kind
    case {"files", "file_inventory"}
        output = collect_file_inventory(config);
    case "environment"
        output = collect_environment(config);
    case {"results", "results_manifest"}
        output = collect_results_manifest(config);
    case "all"
        output = struct();
        output.file_inventory = collect_file_inventory(config);
        output.environment = collect_environment(config);
        output.results_manifest = collect_results_manifest(config);
    otherwise
        error('stage0_manifest:bad_kind', ...
            'kind must be files, environment, results, or all.');
end
end

function inventory = collect_file_inventory(config)
%STAGE0_COLLECT_FILE_INVENTORY Create reproducibility file manifests.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = option_value(config, 'project_dir', ...
    setup_project_paths(mfilename('fullpath')));
write_outputs = option_value(config, 'write_outputs', true);
manifest_dir = option_value(config, 'manifest_dir', ...
    fullfile(project_dir, 'runs', 'manifest'));
docs_dir = option_value(config, 'docs_dir', ...
    fullfile(project_dir, 'docs'));

files = dir(fullfile(project_dir, '**', '*'));
relative_paths = strings(0, 1);
absolute_paths = strings(0, 1);
categories = strings(0, 1);
roles = strings(0, 1);
extensions = strings(0, 1);
bytes = zeros(0, 1);
last_modified = strings(0, 1);
sha256 = strings(0, 1);

for file_index = 1:numel(files)
    item = files(file_index);
    if item.isdir
        continue
    end
    file_path = fullfile(item.folder, item.name);
    rel_path = relative_path(project_dir, file_path);
    if startsWith(rel_path, ".git/")
        continue
    end

    [category, role] = classify_file(rel_path);
    [~, ~, ext] = fileparts(file_path);

    relative_paths(end + 1, 1) = rel_path; %#ok<AGROW>
    absolute_paths(end + 1, 1) = string(file_path); %#ok<AGROW>
    categories(end + 1, 1) = category; %#ok<AGROW>
    roles(end + 1, 1) = role; %#ok<AGROW>
    extensions(end + 1, 1) = string(lower(ext)); %#ok<AGROW>
    bytes(end + 1, 1) = item.bytes; %#ok<AGROW>
    last_modified(end + 1, 1) = string(datetime(item.datenum, ...
        'ConvertFrom', 'datenum', 'TimeZone', 'local')); %#ok<AGROW>
    sha256(end + 1, 1) = string(sha256_file(file_path)); %#ok<AGROW>
end

inventory = table(relative_paths, categories, roles, extensions, bytes, ...
    last_modified, sha256, absolute_paths, 'VariableNames', ...
    {'RelativePath', 'Category', 'Role', 'Extension', 'Bytes', ...
    'LastModified', 'SHA256', 'AbsolutePath'});
inventory = sortrows(inventory, 'RelativePath');

if write_outputs
    ensure_dir(manifest_dir);
    ensure_dir(docs_dir);
    writetable(inventory, fullfile(manifest_dir, 'file_inventory.csv'));

    source_roles = ["source_code", "test_code", "protocol", ...
        "documentation", "project_config"];
    source_manifest = inventory(ismember(inventory.Role, source_roles), :);
    data_manifest = inventory(startsWith(inventory.RelativePath, ...
        "data/"), :);
    writetable(source_manifest, fullfile(manifest_dir, ...
        'source_manifest.csv'));
    writetable(data_manifest, fullfile(manifest_dir, ...
        'data_manifest.csv'));
    write_inventory_doc(fullfile(docs_dir, ...
        'stage0_file_inventory.md'), inventory);
end
end

function [category, role] = classify_file(rel_path)
[~, ~, ext] = fileparts(char(rel_path));
ext = lower(string(ext));
if startsWith(rel_path, "src/")
    category = "source";
    if ext == ".m"
        role = "source_code";
    else
        role = "source_support";
    end
elseif startsWith(rel_path, "test/")
    category = "test";
    if ext == ".m"
        role = "test_code";
    else
        role = "test_artifact";
    end
elseif startsWith(rel_path, "data/")
    category = "data";
    if ext == ".csv"
        role = "raw_input";
    else
        role = "data_artifact";
    end
elseif startsWith(rel_path, "runs/")
    category = "runs";
    role = "generated_result";
elseif startsWith(rel_path, "docs/")
    category = "docs";
    if rel_path == "docs/protocol_v5.md"
        role = "protocol";
    else
        role = "documentation";
    end
elseif startsWith(rel_path, "paper_outputs/")
    category = "paper_outputs";
    role = "generated_paper_output";
elseif rel_path == ".gitignore" || rel_path == "README.md"
    category = "project";
    role = "project_config";
else
    category = "other";
    role = "uncategorized";
end
end

function write_inventory_doc(output_path, inventory)
fid = fopen(output_path, 'w');
if fid < 0
    error('stage0_manifest:file_inventory_write_failed', ...
        'Cannot write inventory document: %s', output_path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Stage 0 File Inventory\n\n');
fprintf(fid, 'Generated: %s\n\n', string(datetime('now', ...
    'TimeZone', 'local')));
fprintf(fid, 'This inventory separates source, tests, raw input data, ');
fprintf(fid, 'generated results, and documentation for reproducible review.\n\n');

summary = groupsummary(inventory, {'Category', 'Role'});
fprintf(fid, '## Summary\n\n');
fprintf(fid, '| Category | Role | File count |\n');
fprintf(fid, '|---|---|---:|\n');
for row_index = 1:height(summary)
    fprintf(fid, '| %s | %s | %d |\n', summary.Category(row_index), ...
        summary.Role(row_index), summary.GroupCount(row_index));
end

fprintf(fid, '\n## Core Files\n\n');
core_index = inventory.Role == "source_code" | ...
    inventory.Role == "test_code" | inventory.Role == "protocol" | ...
    inventory.Role == "raw_input";
core = inventory(core_index, :);
for row_index = 1:height(core)
    fprintf(fid, '- `%s` [%s, %s] SHA256 `%s`\n', ...
        core.RelativePath(row_index), core.Category(row_index), ...
        core.Role(row_index), core.SHA256(row_index));
end
end

function rel_path = relative_path(project_dir, file_path)
prefix = [char(project_dir) filesep];
if startsWith(file_path, prefix)
    rel_path = extractAfter(string(file_path), strlength(prefix));
else
    rel_path = string(file_path);
end
rel_path = replace(rel_path, filesep, "/");
end

function environment = collect_environment(config)
%STAGE0_COLLECT_ENVIRONMENT Record the MATLAB and solver environment.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = option_value(config, 'project_dir', ...
    setup_project_paths(mfilename('fullpath')));
write_outputs = option_value(config, 'write_outputs', true);
manifest_dir = option_value(config, 'manifest_dir', ...
    fullfile(project_dir, 'runs', 'manifest'));
docs_dir = option_value(config, 'docs_dir', fullfile(project_dir, 'docs'));

environment = struct();
environment.generated_at = string(datetime('now', 'TimeZone', 'local'));
environment.project_dir = string(project_dir);
environment.matlab_version = string(version);
environment.matlab_release = string(version('-release'));
environment.computer = string(computer);
environment.user = string(getenv('USERNAME'));
environment.hostname = string(getenv('COMPUTERNAME'));
environment.toolbox = toolbox_versions();
environment.intlinprog_options = intlinprog_options_snapshot();
environment.source_tree_hash = source_tree_hash(project_dir);

if write_outputs
    ensure_dir(manifest_dir);
    ensure_dir(docs_dir);
    json_text = jsonencode(environment, PrettyPrint=true);
    write_text(fullfile(manifest_dir, 'environment_manifest.json'), ...
        json_text);
    write_environment_doc(fullfile(docs_dir, ...
        'stage0_environment_report.md'), environment);
end
end

function toolboxes = toolbox_versions()
raw = ver;
toolboxes = repmat(struct('Name', "", 'Version', "", 'Release', ""), numel(raw), 1);
for index = 1:numel(raw)
    toolboxes(index).Name = string(raw(index).Name);
    toolboxes(index).Version = string(raw(index).Version);
    toolboxes(index).Release = string(raw(index).Release);
end
end

function snapshot = intlinprog_options_snapshot()
try
    options = optimoptions('intlinprog');
    snapshot = struct( ...
        'RelativeGapTolerance', options.RelativeGapTolerance, ...
        'ConstraintTolerance', options.ConstraintTolerance, ...
        'IntegerTolerance', options.IntegerTolerance, ...
        'MaxTime', options.MaxTime, ...
        'Display', string(options.Display));
catch exception
    snapshot = struct( ...
        'error_identifier', string(exception.identifier), ...
        'error_message', string(exception.message));
end
end

function hash = source_tree_hash(project_dir)
patterns = { ...
    fullfile(project_dir, 'src', '**', '*.m'), ...
    fullfile(project_dir, 'test', '**', '*.m'), ...
    fullfile(project_dir, 'docs', '*.md'), ...
    fullfile(project_dir, '.gitignore')};
path_cells = cell(0, 1);
for pattern_index = 1:numel(patterns)
    files = dir(patterns{pattern_index});
    file_paths = cell(numel(files), 1);
    keep_count = 0;
    for file_index = 1:numel(files)
        if files(file_index).isdir
            continue
        end
        keep_count = keep_count + 1;
        file_paths{keep_count} = fullfile(files(file_index).folder, ...
            files(file_index).name);
    end
    path_cells = [path_cells; file_paths(1:keep_count)]; %#ok<AGROW>
end
paths = sort(unique(string(path_cells)));

parts = strings(numel(paths), 1);
for path_index = 1:numel(paths)
    rel = replace(extractAfter(paths(path_index), ...
        strlength(project_dir) + 1), filesep, "/");
    parts(path_index) = rel + " " + string(sha256_file(paths(path_index)));
end
hash = sha256_text(strjoin(parts, newline));
end

function hash = sha256_text(text_value)
message_digest = java.security.MessageDigest.getInstance('SHA-256');
bytes = unicode2native(char(text_value), 'UTF-8');
message_digest.update(typecast(uint8(bytes(:)), 'int8'));
digest = typecast(message_digest.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest)', 1, []));
end

function write_environment_doc(output_path, environment)
fid = fopen(output_path, 'w');
if fid < 0
    error('stage0_manifest:environment_write_failed', ...
        'Cannot write environment report: %s', output_path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Stage 0 Environment Report\n\n');
fprintf(fid, '- Generated: `%s`\n', environment.generated_at);
fprintf(fid, '- MATLAB: `%s` (`%s`)\n', environment.matlab_version, ...
    environment.matlab_release);
fprintf(fid, '- Computer: `%s`\n', environment.computer);
fprintf(fid, '- Source tree hash: `%s`\n\n', environment.source_tree_hash);

fprintf(fid, '## intlinprog Options\n\n');
fields = fieldnames(environment.intlinprog_options);
for index = 1:numel(fields)
    name = fields{index};
    value = environment.intlinprog_options.(name);
    value_text = string(value);

    fprintf(fid, '- `%s`: `%s`\n', name, value_text);
end
end

function write_text(file_path, text_value)
fid = fopen(file_path, 'w');
if fid < 0
    error('stage0_manifest:environment_write_failed', ...
        'Cannot write file: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', text_value);
end

function manifest = collect_results_manifest(config)
%STAGE0_COLLECT_RESULTS_MANIFEST Summarize generated MAT result files.

if nargin < 1 || isempty(config)
    config = struct();
end

project_dir = option_value(config, 'project_dir', ...
    setup_project_paths(mfilename('fullpath')));
write_outputs = option_value(config, 'write_outputs', true);
manifest_dir = option_value(config, 'manifest_dir', ...
    fullfile(project_dir, 'runs', 'manifest'));

mat_files = dir(fullfile(project_dir, 'runs', '**', '*.mat'));

relative_path = strings(0, 1);
stage = strings(0, 1);
scheme = strings(0, 1);
candidate = strings(0, 1);
data_year = strings(0, 1);
status = strings(0, 1);
protocol_version = strings(0, 1);
protocol_seal = strings(0, 1);
contract_shortfall_p95 = zeros(0, 1);
mar = zeros(0, 1);
h2_soc_p05 = zeros(0, 1);
lcoa = zeros(0, 1);
nh3_annual_t = zeros(0, 1);
co2_intensity = zeros(0, 1);
net_profit_usd = zeros(0, 1);
exitflag = zeros(0, 1);
solver_gap = zeros(0, 1);
file_sha256 = strings(0, 1);
read_status = strings(0, 1);

for file_index = 1:numel(mat_files)
    file_path = fullfile(mat_files(file_index).folder, mat_files(file_index).name);
    rel = relative_path_from(project_dir, file_path);
    summary = summarize_mat(project_dir, file_path, rel);

    relative_path(end + 1, 1) = rel; %#ok<AGROW>
    stage(end + 1, 1) = summary.stage; %#ok<AGROW>
    scheme(end + 1, 1) = summary.scheme; %#ok<AGROW>
    candidate(end + 1, 1) = summary.candidate; %#ok<AGROW>
    data_year(end + 1, 1) = summary.data_year; %#ok<AGROW>
    status(end + 1, 1) = summary.status; %#ok<AGROW>
    protocol_version(end + 1, 1) = summary.protocol_version; %#ok<AGROW>
    protocol_seal(end + 1, 1) = summary.protocol_seal; %#ok<AGROW>
    contract_shortfall_p95(end + 1, 1) = summary.contract_shortfall_p95; %#ok<AGROW>
    mar(end + 1, 1) = summary.mar; %#ok<AGROW>
    h2_soc_p05(end + 1, 1) = summary.h2_soc_p05; %#ok<AGROW>
    lcoa(end + 1, 1) = summary.lcoa; %#ok<AGROW>
    nh3_annual_t(end + 1, 1) = summary.nh3_annual_t; %#ok<AGROW>
    co2_intensity(end + 1, 1) = summary.co2_intensity; %#ok<AGROW>
    net_profit_usd(end + 1, 1) = summary.net_profit_usd; %#ok<AGROW>
    exitflag(end + 1, 1) = summary.exitflag; %#ok<AGROW>
    solver_gap(end + 1, 1) = summary.solver_gap; %#ok<AGROW>
    file_sha256(end + 1, 1) = string(sha256_file(file_path)); %#ok<AGROW>
    read_status(end + 1, 1) = summary.read_status; %#ok<AGROW>
end

manifest = table(relative_path, stage, scheme, candidate, data_year, ...
    status, protocol_version, protocol_seal, contract_shortfall_p95, mar, ...
    h2_soc_p05, lcoa, nh3_annual_t, co2_intensity, net_profit_usd, ...
    exitflag, solver_gap, file_sha256, read_status, 'VariableNames', ...
    {'RelativePath', 'Stage', 'Scheme', 'Candidate', 'DataYear', ...
    'Status', 'ProtocolVersion', 'ProtocolSeal', ...
    'ContractShortfallP95', 'MAR', 'H2SOCP05', 'LCOA', ...
    'NH3AnnualT', 'CO2Intensity', 'NetProfitUSD', 'Exitflag', ...
    'SolverGap', 'SHA256', 'ReadStatus'});
manifest = sortrows(manifest, 'RelativePath');

if write_outputs
    ensure_dir(manifest_dir);
    writetable(manifest, fullfile(manifest_dir, ...
        'results_manifest.csv'));
    write_manifest_doc(fullfile(manifest_dir, ...
        'results_manifest.md'), manifest);
end
end

function summary = summarize_mat(project_dir, file_path, rel)
summary = empty_summary(project_dir, rel);
try
    info = whos('-file', file_path);
    available = string({info.name});
    requested = ["run_info", "result", "metrics", "params", ...
        "renewable_data", "contract", "stage1_result", ...
        "stage1_run_info"];
    load_names = cellstr(intersect(requested, available, 'stable'));
    if isempty(load_names)
        loaded = struct();
    else
        loaded = load(file_path, load_names{:});
    end

    if isfield(loaded, 'run_info')
        run_info = loaded.run_info;
        summary.stage = get_string(run_info, 'stage', summary.stage);
        summary.status = get_string(run_info, 'status', summary.status);
        summary.data_year = get_string(run_info, 'data_year', summary.data_year);
        summary.scheme = first_nonempty(summary.scheme, ...
            get_string(run_info, 'scheme', ""));
        summary.candidate = first_nonempty(summary.candidate, ...
            get_string(run_info, 'candidate_name', ""));
        if isfield(run_info, 'contract') && isstruct(run_info.contract)
            summary.protocol_version = get_string(run_info.contract, ...
                'protocol_version', summary.protocol_version);
            summary.protocol_seal = get_string(run_info.contract, ...
                'protocol_seal', summary.protocol_seal);
        end
    end

    if isfield(loaded, 'metrics')
        metrics = loaded.metrics;
        if isfield(metrics, 'ProtocolVersion')
            summary.protocol_version = string(metrics.ProtocolVersion);
        end
        if isfield(metrics, 'ProtocolSeal')
            summary.protocol_seal = string(metrics.ProtocolSeal);
        end
        if isfield(metrics, 'Primary')
            summary.contract_shortfall_p95 = get_numeric(metrics.Primary, ...
                'contract_shortfall_p95', summary.contract_shortfall_p95);
            summary.mar = first_finite(summary.mar, ...
                get_numeric(metrics.Primary, 'mar', NaN));
            summary.h2_soc_p05 = get_numeric(metrics.Primary, ...
                'h2_soc_p05', summary.h2_soc_p05);
        end
        if isfield(metrics, 'Economic')
            summary.lcoa = get_numeric(metrics.Economic, 'lcoa', summary.lcoa);
            summary.net_profit_usd = get_numeric(metrics.Economic, ...
                'net_profit_usd', summary.net_profit_usd);
        end
    end

    if isfield(loaded, 'result')
        result = loaded.result;
        summary.exitflag = get_numeric(result, 'exitflag', summary.exitflag);
        if isfield(result, 'summary')
            summary.lcoa = get_numeric(result.summary, 'lcoa', summary.lcoa);
            summary.nh3_annual_t = get_numeric(result.summary, ...
                'NH3_prod_t_y', summary.nh3_annual_t);
            summary.co2_intensity = get_numeric(result.summary, ...
                'co2_intensity', summary.co2_intensity);
            summary.net_profit_usd = get_numeric(result.summary, ...
                'net_profit', summary.net_profit_usd);
        end
        if isfield(result, 'output')
            summary.solver_gap = first_finite(summary.solver_gap, ...
                get_numeric(result.output, 'relativegap', NaN));
            summary.solver_gap = first_finite(summary.solver_gap, ...
                get_numeric(result.output, 'relativeGap', NaN));
        end
        if isfield(result, 'contract')
            summary.contract_shortfall_p95 = first_finite( ...
                summary.contract_shortfall_p95, ...
                get_numeric(result.contract, 'contract_shortfall_p95', NaN));
            summary.contract_shortfall_p95 = first_finite( ...
                summary.contract_shortfall_p95, ...
                percentile_field(result.contract, 'backlog_kg', 95));
        end
        if isfield(result, 'storage') && isfield(result.storage, 'soc_work')
            summary.h2_soc_p05 = first_finite(summary.h2_soc_p05, ...
                prctile(result.storage.soc_work(:), 5));
        end
        if isfield(result, 'dispatch') && isfield(result.dispatch, 'HB_load')
            summary.mar = first_finite(summary.mar, ...
                mean(abs(diff(result.dispatch.HB_load(:)))));
        end
    end

    summary.read_status = "ok";
catch exception
    summary.read_status = "read_error:" + string(exception.identifier);
end
end

function summary = empty_summary(~, rel)
summary = struct();
summary.stage = infer_stage(rel);
summary.scheme = "";
summary.candidate = "";
summary.data_year = "";
summary.status = "";
summary.protocol_version = "";
summary.protocol_seal = "";
summary.contract_shortfall_p95 = NaN;
summary.mar = NaN;
summary.h2_soc_p05 = NaN;
summary.lcoa = NaN;
summary.nh3_annual_t = NaN;
summary.co2_intensity = NaN;
summary.net_profit_usd = NaN;
summary.exitflag = NaN;
summary.solver_gap = NaN;
summary.read_status = "not_read";
end

function value = infer_stage(rel)
parts = split(rel, "/");
value = "";
for index = 1:numel(parts)
    if startsWith(parts(index), "stage")
        value = parts(index);
        return
    end
end
if contains(rel, "/rolling/")
    value = "rolling";
end
end

function value = get_string(source, name, default_value)
value = default_value;
if isstruct(source) && isfield(source, name) && ~isempty(source.(name))
    value = string(source.(name));
    if ~isscalar(value)
        value = strjoin(value(:)', ",");
    end
end
end

function value = get_numeric(source, name, default_value)
value = default_value;
if isstruct(source) && isfield(source, name) && isnumeric(source.(name)) && ...
        isscalar(source.(name)) && isfinite(source.(name))
    value = double(source.(name));
end
end

function value = percentile_field(source, name, percentile)
value = NaN;
if isstruct(source) && isfield(source, name) && isnumeric(source.(name)) && ...
        ~isempty(source.(name))
    value = prctile(source.(name)(:), percentile);
end
end

function value = first_finite(current_value, candidate_value)
if isfinite(current_value)
    value = current_value;
else
    value = candidate_value;
end
end

function value = first_nonempty(current_value, candidate_value)
if strlength(string(current_value)) > 0
    value = current_value;
else
    value = candidate_value;
end
end

function rel_path = relative_path_from(project_dir, file_path)
prefix = [char(project_dir) filesep];
if startsWith(file_path, prefix)
    rel_path = extractAfter(string(file_path), strlength(prefix));
else
    rel_path = string(file_path);
end
rel_path = replace(rel_path, filesep, "/");
end

function write_manifest_doc(output_path, manifest)
fid = fopen(output_path, 'w');
if fid < 0
    error('stage0_manifest:results_manifest_write_failed', ...
        'Cannot write manifest document: %s', output_path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Results Manifest\n\n');
fprintf(fid, 'Generated: %s\n\n', string(datetime('now', ...
    'TimeZone', 'local')));
fprintf(fid, '- MAT result files: `%d`\n', height(manifest));
fprintf(fid, '- Successfully read: `%d`\n', nnz(manifest.ReadStatus == "ok"));
fprintf(fid, '- Files with LCOA: `%d`\n', nnz(isfinite(manifest.LCOA)));
fprintf(fid, '- Files with primary metrics: `%d`\n', ...
    nnz(isfinite(manifest.ContractShortfallP95) | ...
    isfinite(manifest.MAR) | isfinite(manifest.H2SOCP05)));
end

function hash = sha256_file(file_path)
%STAGE0_FILE_SHA256 Compute a SHA-256 hash for a file.

if isstring(file_path) && isscalar(file_path)
    file_path = char(file_path);
end
if ~isfile(file_path)
    error('stage0_manifest:missing_file', ...
        'Cannot hash missing file: %s', file_path);
end

message_digest = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(file_path, 'r');
if fid < 0
    error('stage0_manifest:open_failed', ...
        'Cannot open file for hashing: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));

while true
    bytes = fread(fid, 1024 * 1024, '*uint8');
    if isempty(bytes)
        break
    end
    message_digest.update(typecast(bytes(:), 'int8'));
end

digest = typecast(message_digest.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest)', 1, []));
end

function ensure_dir(dir_path)
if ~isfolder(dir_path)
    mkdir(dir_path);
end
end

function value = option_value(config, name, default_value)
if isfield(config, name) && ~isempty(config.(name))
    value = config.(name);
else
    value = default_value;
end
end
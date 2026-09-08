function audit_table = stage0_constraint_audit(config)
%STAGE0_CONSTRAINT_AUDIT Audit physical and accounting residuals in MAT files.

if nargin < 1 || isempty(config)
    config = struct();
end

stage0_dir = fileparts(mfilename('fullpath'));
utils_dir = fullfile(fileparts(stage0_dir), 'utils');
if isfolder(utils_dir)
    addpath(utils_dir, '-begin');
end
project_dir = option_value(config, 'project_dir', ...
    setup_project_paths(mfilename('fullpath')));
write_outputs = option_value(config, 'write_outputs', true);
manifest_dir = option_value(config, 'manifest_dir', ...
    fullfile(project_dir, 'runs', 'manifest'));
docs_dir = option_value(config, 'docs_dir', fullfile(project_dir, 'docs', 'reports'));

mat_files = dir(fullfile(project_dir, 'runs', '**', '*.mat'));
relative_path = strings(0, 1);
audit_status = strings(0, 1);
hard_constraints_passed = false(0, 1);
max_power_residual_kw = zeros(0, 1);
max_storage_residual_kg = zeros(0, 1);
max_storage_lower_violation_kg = zeros(0, 1);
max_storage_upper_violation_kg = zeros(0, 1);
max_hb_lower_violation = zeros(0, 1);
max_hb_upper_violation = zeros(0, 1);
max_hb_ramp_violation = zeros(0, 1);
buy_sell_overlap_kwh = zeros(0, 1);
co2_margin_kg = zeros(0, 1);
terminal_backlog_kg = zeros(0, 1);
max_backlog_kg = zeros(0, 1);

for file_index = 1:numel(mat_files)
    file_path = fullfile(mat_files(file_index).folder, mat_files(file_index).name);
    rel = relative_path_from(project_dir, file_path);
    row = audit_file(file_path);

    relative_path(end + 1, 1) = rel; %#ok<AGROW>
    audit_status(end + 1, 1) = row.audit_status; %#ok<AGROW>
    hard_constraints_passed(end + 1, 1) = row.hard_constraints_passed; %#ok<AGROW>
    max_power_residual_kw(end + 1, 1) = row.max_power_residual_kw; %#ok<AGROW>
    max_storage_residual_kg(end + 1, 1) = row.max_storage_residual_kg; %#ok<AGROW>
    max_storage_lower_violation_kg(end + 1, 1) = row.max_storage_lower_violation_kg; %#ok<AGROW>
    max_storage_upper_violation_kg(end + 1, 1) = row.max_storage_upper_violation_kg; %#ok<AGROW>
    max_hb_lower_violation(end + 1, 1) = row.max_hb_lower_violation; %#ok<AGROW>
    max_hb_upper_violation(end + 1, 1) = row.max_hb_upper_violation; %#ok<AGROW>
    max_hb_ramp_violation(end + 1, 1) = row.max_hb_ramp_violation; %#ok<AGROW>
    buy_sell_overlap_kwh(end + 1, 1) = row.buy_sell_overlap_kwh; %#ok<AGROW>
    co2_margin_kg(end + 1, 1) = row.co2_margin_kg; %#ok<AGROW>
    terminal_backlog_kg(end + 1, 1) = row.terminal_backlog_kg; %#ok<AGROW>
    max_backlog_kg(end + 1, 1) = row.max_backlog_kg; %#ok<AGROW>
end

audit_table = table(relative_path, audit_status, hard_constraints_passed, ...
    max_power_residual_kw, max_storage_residual_kg, ...
    max_storage_lower_violation_kg, max_storage_upper_violation_kg, ...
    max_hb_lower_violation, max_hb_upper_violation, ...
    max_hb_ramp_violation, buy_sell_overlap_kwh, co2_margin_kg, ...
    terminal_backlog_kg, max_backlog_kg, 'VariableNames', ...
    {'RelativePath', 'AuditStatus', 'HardConstraintsPassed', ...
    'MaxPowerResidualKW', 'MaxStorageResidualKG', ...
    'MaxStorageLowerViolationKG', 'MaxStorageUpperViolationKG', ...
    'MaxHBLowerViolation', 'MaxHBUpperViolation', ...
    'MaxHBRampViolation', 'BuySellOverlapKWh', 'CO2MarginKG', ...
    'TerminalBacklogKG', 'MaxBacklogKG'});
audit_table = sortrows(audit_table, 'RelativePath');

if write_outputs
    ensure_directory(manifest_dir);
    ensure_directory(docs_dir);
    writetable(audit_table, fullfile(manifest_dir, ...
        'constraint_audit.csv'));
    write_audit_doc(fullfile(docs_dir, ...
        'stage0_constraint_audit.md'), audit_table);
end
end

function row = audit_file(file_path)
row = empty_row();
try
    info = whos('-file', file_path);
    names = string({info.name});
    if ~any(names == "result") || ~any(names == "params")
        row.audit_status = "not_dispatch_result";
        return
    end
    loaded = load(file_path, 'result', 'params');
    result = loaded.result;
    params = loaded.params;
    if ~isstruct(result) || ~isfield(result, 'dispatch') || ...
            ~isstruct(result.dispatch)
        row.audit_status = "missing_dispatch";
        return
    end

    row.max_power_residual_kw = get_nested_numeric(result, ...
        {'check', 'max_power_residual_kw'}, NaN);
    row.max_storage_residual_kg = get_nested_numeric(result, ...
        {'check', 'max_storage_residual_kg'}, NaN);
    row.buy_sell_overlap_kwh = get_nested_numeric(result, ...
        {'check', 'buy_sell_overlap_kwh'}, NaN);

    if isfield(result.dispatch, 'storage_H2')
        storage = result.dispatch.storage_H2(:);
        row.max_storage_lower_violation_kg = max([0; ...
            params.h2_storage.min_mass - storage]);
        row.max_storage_upper_violation_kg = max([0; ...
            storage - params.h2_storage.mass]);
    end
    if isfield(result.dispatch, 'HB_load')
        hb_load = result.dispatch.HB_load(:);
        row.max_hb_lower_violation = max([0; params.HB.min_load - hb_load]);
        row.max_hb_upper_violation = max([0; hb_load - params.HB.max_load]);
        if numel(hb_load) > 1
            row.max_hb_ramp_violation = max([0; abs(diff(hb_load)) - ...
                params.HB.ramp_rate * params.time.step]);
        end
    end
    if isfield(result, 'summary') && ...
            isfield(result.summary, 'purchase_kwh') && ...
            isfield(result.summary, 'NH3_prod_kg') && ...
            isfield(params, 'environment') && params.environment.co2_enabled
        co2_lhs = params.environment.grid_co2 * result.summary.purchase_kwh;
        co2_rhs = params.environment.co2_limit * result.summary.NH3_prod_kg;
        row.co2_margin_kg = co2_rhs - co2_lhs;
    end
    if isfield(result, 'contract') && isfield(result.contract, 'backlog_kg')
        backlog = result.contract.backlog_kg(:);
        row.terminal_backlog_kg = backlog(end);
        row.max_backlog_kg = max(backlog);
    end

    tolerances = [ ...
        nan_to_zero(row.max_power_residual_kw) <= 1e-3, ...
        nan_to_zero(row.max_storage_residual_kg) <= 1e-3, ...
        nan_to_zero(row.max_storage_lower_violation_kg) <= 1e-3, ...
        nan_to_zero(row.max_storage_upper_violation_kg) <= 1e-3, ...
        nan_to_zero(row.max_hb_lower_violation) <= 1e-8, ...
        nan_to_zero(row.max_hb_upper_violation) <= 1e-8, ...
        nan_to_zero(row.max_hb_ramp_violation) <= 1e-8, ...
        nan_to_zero(row.buy_sell_overlap_kwh) <= 1e-6, ...
        isnan(row.co2_margin_kg) || row.co2_margin_kg >= -1e-3];
    row.hard_constraints_passed = all(tolerances);
    row.audit_status = "audited";
catch exception
    row.audit_status = "audit_error:" + string(exception.identifier);
end
end

function row = empty_row()
row = struct( ...
    'audit_status', "not_audited", ...
    'hard_constraints_passed', false, ...
    'max_power_residual_kw', NaN, ...
    'max_storage_residual_kg', NaN, ...
    'max_storage_lower_violation_kg', NaN, ...
    'max_storage_upper_violation_kg', NaN, ...
    'max_hb_lower_violation', NaN, ...
    'max_hb_upper_violation', NaN, ...
    'max_hb_ramp_violation', NaN, ...
    'buy_sell_overlap_kwh', NaN, ...
    'co2_margin_kg', NaN, ...
    'terminal_backlog_kg', NaN, ...
    'max_backlog_kg', NaN);
end

function value = get_nested_numeric(source, path_parts, default_value)
value = default_value;
current = source;
for index = 1:numel(path_parts)
    name = path_parts{index};
    if ~isstruct(current) || ~isfield(current, name)
        return
    end
    current = current.(name);
end
if isnumeric(current) && isscalar(current) && isfinite(current)
    value = double(current);
end
end

function value = nan_to_zero(value)
if isnan(value)
    value = 0;
end
end

function write_audit_doc(output_path, audit_table)
fid = fopen(output_path, 'w');
if fid < 0
    error('stage0_constraint_audit:write_failed', ...
        'Cannot write audit document: %s', output_path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# Stage 0 Constraint Audit\n\n');
fprintf(fid, 'Generated: %s\n\n', string(datetime('now', ...
    'TimeZone', 'local')));
fprintf(fid, '- MAT files scanned: `%d`\n', height(audit_table));
fprintf(fid, '- Dispatch results audited: `%d`\n', ...
    nnz(audit_table.AuditStatus == "audited"));
fprintf(fid, '- Audited results passing hard checks: `%d`\n', ...
    nnz(audit_table.HardConstraintsPassed));
fprintf(fid, '\nDetailed residuals are in `runs/manifest/constraint_audit.csv`.\n');
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

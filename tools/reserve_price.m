% RESERVE_PRICE: post-hoc counterfactual — what does a hydrogen reserve floor imply
% for the dispatch's operating point, using an already-solved schedule?
%
% This does NOT re-solve. It answers a narrower, fully verifiable question:
% "in the solved schedule, how many hours would violate a working-reserve floor r,
%  and what H2 inventory (kg) and equivalent ammonia output would those hours carry?"
%
% Usage: reserve_price(mat_path)

function reserve_price(mat_path)
if nargin < 1 || isempty(mat_path)
    error('reserve_price:bad_input', 'mat_path is required.');
end
source_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(source_dir);
src_dir = fullfile(project_dir, 'src');
addpath(src_dir);
addpath(fullfile(src_dir, 'params'));
addpath(fullfile(src_dir, 'results'));
addpath(fullfile(src_dir, 'class'));
addpath(source_dir);

S = load(mat_path, 'params_save', 'results_save');
params = S.params_save; results = S.results_save;
dt = params.time.step;
soc = results.storage.soc_work(:);
if numel(soc) == numel(results.dispatch.P_AEL) + 1
    % storage_H2 is defined on T+1 nodes; align it to the T dispatch intervals.
    soc = soc(2:end);
end
limits = h2_storage_limits(params.h2_storage, params.unit.h2_density);
work_mass = limits.work_mass;
NH3 = results.dispatch.NH3_prod(:);
P_AEL = results.dispatch.P_AEL(:);

fprintf('\n=== reserve price audit (%s) ===\n', mat_path);
fprintf('usable H2 inventory = %.1f kg (%.1f Nm3)\n', ...
    work_mass, limits.work_capacity);
fprintf('hours = %d\n', numel(soc));

floors = [0, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50];
rows = cell(numel(floors), 1);
for k = 1:numel(floors)
    r = floors(k);
    viol = soc < r - 1e-9;
    deficit_kg = sum(max(r - soc, 0)) * work_mass;   % H2 kg that would be needed
    % Equivalent ammonia forgone if that H2 had to come from extra electrolysis
    % rather than from a smaller ammonia rate: express as extra AEL energy.
    extra_h2_kg = deficit_kg;
    extra_ael_kwh = extra_h2_kg * params.AEL.common.mass_spec_energy;
    rows{k} = struct('floor', r, 'risk_hours', sum(viol) * dt, ...
        'risk_fraction', mean(viol), ...
        'max_deficit_kg', max(max(r - soc, 0)) * work_mass, ...
        'cum_deficit_kg', deficit_kg, ...
        'extra_ael_mwh', extra_ael_kwh / 1000, ...
        'extra_ael_share_of_renewables', extra_ael_kwh / max(sum(results.dispatch.P_total) * dt, eps), ...
        'nh3_in_deficit_hours_t', sum(NH3(viol)) / 1000);
end
T = struct2table([rows{:}]);
disp(T);

out = fullfile(fileparts(mat_path), 'reserve_price_audit.csv');
writetable(T, out);
fprintf('wrote %s\n', out);

% --- how much of the renewable variability went into storage cycling ---
dSoc = diff(soc);
fprintf('\nstorage cycling: total |dSOC| = %.2f full usable volumes over %d h (%.2f volumes/day)\n', ...
    sum(abs(dSoc)), numel(soc), sum(abs(dSoc)) / (numel(soc) / 24));
fprintf('AEL energy share        = %.4f\n', sum(P_AEL) / max(sum(results.dispatch.P_total), eps));
fprintf('min working SOC         = %.4f\n', min(soc));
fprintf('mean working SOC        = %.4f\n', mean(soc));
end

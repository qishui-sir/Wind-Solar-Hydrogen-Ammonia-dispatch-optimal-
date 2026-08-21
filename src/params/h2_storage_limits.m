function limits = h2_storage_limits(storage, h2_density)
%H2_STORAGE_LIMITS Convert tank pressure limits to inventory limits.
% Rated Nm3 capacity is treated as the inventory at maximum pressure.

if ~isstruct(storage) || ~isscalar(storage)
    error('h2_storage_limits:bad_storage', ...
        'storage must be a scalar parameter struct.');
end

required_fields = {'capacity', 'min_pressure', 'max_pressure'};
for field_index = 1:numel(required_fields)
    field_name = required_fields{field_index};
    if ~isfield(storage, field_name)
        error('h2_storage_limits:missing_field', ...
            'storage.%s is required.', field_name);
    end
end

must_positive(storage.capacity, 'storage.capacity');
must_positive(storage.max_pressure, 'storage.max_pressure');
must_positive(h2_density, 'h2_density');
if ~(isnumeric(storage.min_pressure) && isscalar(storage.min_pressure) && ...
        isfinite(storage.min_pressure) && storage.min_pressure >= 0)
    error('h2_storage_limits:bad_min_pressure', ...
        'storage.min_pressure must be a nonnegative finite scalar.');
end

pressure_basis = 'absolute';
if isfield(storage, 'pressure_basis')
    pressure_basis = lower(char(string(storage.pressure_basis)));
end
atm_pressure = 0.101325;
if isfield(storage, 'atm_pressure')
    atm_pressure = storage.atm_pressure;
    must_positive(atm_pressure, 'storage.atm_pressure');
end

switch pressure_basis
    case 'absolute'
        min_pressure_abs = storage.min_pressure;
        max_pressure_abs = storage.max_pressure;
    case 'gauge'
        min_pressure_abs = storage.min_pressure + atm_pressure;
        max_pressure_abs = storage.max_pressure + atm_pressure;
    otherwise
        error('h2_storage_limits:bad_pressure_basis', ...
            'storage.pressure_basis must be absolute or gauge.');
end

if min_pressure_abs <= 0 || min_pressure_abs >= max_pressure_abs
    error('h2_storage_limits:bad_pressure_range', ...
        'Absolute minimum pressure must be positive and below maximum pressure.');
end

init_work_soc = 0.5;
if isfield(storage, 'init_work_soc')
    init_work_soc = storage.init_work_soc;
end
if ~(isnumeric(init_work_soc) && isscalar(init_work_soc) && ...
        isfinite(init_work_soc) && init_work_soc >= 0 && init_work_soc <= 1)
    error('h2_storage_limits:bad_initial_soc', ...
        'storage.init_work_soc must be between zero and one.');
end

limits.min_abs_soc = min_pressure_abs / max_pressure_abs;
limits.max_capacity = storage.capacity;
limits.min_capacity = storage.capacity * limits.min_abs_soc;
limits.work_capacity = limits.max_capacity - limits.min_capacity;
limits.max_mass = limits.max_capacity * h2_density;
limits.min_mass = limits.min_capacity * h2_density;
limits.work_mass = limits.work_capacity * h2_density;
limits.initial_mass = limits.min_mass + init_work_soc * limits.work_mass;
end

function must_positive(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
    error('h2_storage_limits:bad_positive_scalar', ...
        '%s must be a positive finite scalar.', name);
end
end

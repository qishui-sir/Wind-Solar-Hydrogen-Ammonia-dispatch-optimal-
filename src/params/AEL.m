function par = AEL(config, scenario_id)
%AEL Zhou alkaline electrolyzer parameters for PtA dispatch.

if nargin == 1 && (ischar(config) || (isstring(config) && isscalar(config)))
    scenario_id = config;
    config = struct();
elseif nargin < 1 || isempty(config)
    config = struct();
end

if nargin < 2 || isempty(scenario_id)
    scenario_id = 's2';
end

if isstring(scenario_id) && isscalar(scenario_id)
    scenario_id = char(scenario_id);
end

scenario_id = lower(strtrim(scenario_id));

common = struct();
common.module_h2 = 1000;           % Zhou scheduling module H2 output, Nm3/h
common.spec_energy = 5.0;          % Zhou AEL energy use, kWh/Nm3
common.min_load = 0.20;            % Zhou AEL minimum load, fraction
common.max_load = 1.00;            % Zhou AEL maximum load, fraction
common.capex = 285;                % Zhou AEL capital cost, USD/kW
common.om_rate = 0.02;             % Zhou AEL O&M rate, fraction/year
common.min_stable = 60;            % Zhou AEL minimum stable time, min
common.startup_elec = 0.15;        % Zhou startup electricity, load fraction/h
common.water_use = 28;             % Zhou AEL water use, t/t-H2
common.seg_num = 12;               % Zhou piecewise segment count

switch scenario_id
    case 's1'
        common.startup = false;    % Enable AEL startup electricity
        common.capacity = 140;     % S1 AEL capacity, MW
    case 's2'
        common.startup = false;
        common.capacity = 130;     % S2 AEL capacity, MW
    case 's3'
        common.startup = true;
        common.capacity = 130;     % S3 AEL capacity, MW
    otherwise
        error('AEL:bad_case', 'scenario_id must be s1, s2, or s3.');
end

h2_density = 0.08988;
power_scale = 1000;
if isfield(config, 'unit')
    if isfield(config.unit, 'h2_density')
        h2_density = config.unit.h2_density;
    end
    if isfield(config.unit, 'power_scale')
        power_scale = config.unit.power_scale;
    end
end

common.max_power = common.capacity * power_scale;             % Rated power, kW
common.min_power = common.max_power * common.min_load;        % Minimum power, kW
common.module_power = common.module_h2 * common.spec_energy;  % Module power, kW
common.module_num = ceil(common.max_power / common.module_power);
common.h2_output = common.max_power / common.spec_energy;     % H2 output, Nm3/h
common.h2_mass = common.h2_output * h2_density;               % H2 output, kg/h
common.mass_spec_energy = common.spec_energy / h2_density;    % kWh/kg-H2

par.common = common;
end

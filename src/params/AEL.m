function par = AEL(config, scenario_id)

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
detail = struct();

detail.source.paper = 'Qi 2023 Applied Energy';
detail.source.note = ['Qi Tables B.8/B.9 for a 500 Nm3/h stack; ', ...
    'Zhou Tables 2/4 for system scheduling.'];

detail.far_const = 96485.33212;    % Faraday constant, C/mol
detail.far_eff = 1.0;              % Faraday efficiency, fraction
detail.h2_molar_mass = 2.01588e-3; % Hydrogen molar mass, kg/mol

detail.cell_num = 298;
detail.cell_area = 2.0;            % 500 Nm3/h

detail.r1 = 1.71e-4;               % Qi U-I ohmic coefficient
detail.r2 = -1.96e-7;              % Qi U-I temperature coefficient
detail.s = 0.16;                   % Qi U-I activation coefficient
detail.t1 = -0.24;                 % Qi U-I activation coefficient
detail.t2 = 26.23;                 % Qi U-I activation coefficient
detail.t3 = 139.88;                % Qi U-I activation coefficient
detail.tn_voltage = 1.48;          % Qi thermal-neutral voltage, V
detail.deg_voltage = 0;            % Initial degradation voltage rise, V

detail.stack_temp = 90.0;          % After-stack temperature, degC
detail.sep_temp = 90.0;            % Before-stack temperature, degC
detail.temp_limit = 95.0;          % Qi MW-scale upper temperature limit, degC
detail.pid_set = 88.78;            % Qi large-system PID set point, degC
detail.pid_i_set = 89.57;          % Qi large-system PID-I set point, degC
detail.mpc_set = 93.23;            % Qi large-system MPC set point, degC

detail.stack_h2 = 500;             % Qi large-stack rated H2 output, Nm3/h
detail.cur_density = 2000;         % Qi nominal current density, A/m2

common.module_h2 = 1000;           % Zhou scheduling module H2 output, Nm3/h
common.spec_energy = 5.0;          % Zhou original AEL energy use, kWh/Nm3
common.min_load = 0.20;            % Zhou AEL minimum load, fraction
common.max_load = 1.00;            % Zhou AEL maximum load, fraction
common.capex = 285;                % Zhou AEL capital cost, USD/kW
common.om_rate = 0.02;             % Zhou AEL O&M rate, fraction/year
common.min_stable = 60;            % Zhou AEL minimum stable time, min
common.startup_elec = 0.15;        % Zhou startup electricity, load fraction/h
common.water_use = 28;             % Zhou AEL water use, t/t-H2
common.seg_num = 12;               % Zhou piecewise segment count

detail.cell_diam = 1.6;            % Qi 500 Nm3/h cell diameter, m
detail.stack_diam = 2.04;          % Qi 500 Nm3/h stack diameter, m
detail.stack_len = 5.4;            % Qi 500 Nm3/h stack length, m
detail.stack_area = 41;            % Qi 500 Nm3/h stack surface area, m2
detail.stack_volume = 8;           % Qi 500 Nm3/h free stack volume, m3
detail.stack_void = 0.5;           % Qi stack void fraction at rated load
detail.stack_emiss = 0.8;          % Qi stack surface blackness
detail.sep_volume = 2.2;           % Qi 500 Nm3/h separator volume, m3
detail.sep_level = 0.1095;         % Qi separator liquid level, m
detail.elec_type = 'KOH';          % Qi electrolyte type
detail.elec_koh = 0.312;           % Qi KOH mass fraction
detail.elec_flow = 25.2;           % Qi 500 Nm3/h electrolyte flow, m3/h
detail.coil_htc = 8820;            % Qi cooling-coil heat transfer coefficient, W/K
detail.sep_resist = 0.004;         % Qi separator thermal resistance, K/W
detail.stack_heat = 55e6;          % Qi stack heat capacity, J/K
detail.sep_heat = 4.26e6;          % Qi separator heat capacity, J/K
detail.coil_heat = 1.15e6;         % Qi cooling-coil heat capacity, J/K
detail.stack_delay = 6 * 60;       % Qi stack time delay, s
detail.coil_delay = 4 * 60;        % Qi cooling-coil time delay, s
detail.sb_const = 5.670374419e-8;  % Radiation constant for Qi heat-loss Eq. (7), W/(m2 K4)

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

common.max_power = common.capacity * power_scale;               % AEL rated power, kW
common.min_power = common.max_power * common.min_load;          % AEL minimum power, kW
common.module_power = common.module_h2 * common.spec_energy;    % Zhou scheduling module power, kW
common.module_num = ceil(common.max_power / common.module_power); % Zhou scheduling module count
detail.stack_num = ceil(common.max_power / ...
    (detail.stack_h2 * common.spec_energy));                    % Qi-equivalent stack count
detail.stack_per_module = common.module_h2 / detail.stack_h2;   % Qi stacks per Zhou module
common.h2_output = common.max_power / common.spec_energy;       % Zhou AEL H2 output, Nm3/h
common.h2_mass = common.h2_output * h2_density;                 % Zhou AEL H2 output, kg/h
common.mass_spec_energy = common.spec_energy / h2_density;      % Derived Zhou AEL energy use, kWh/kg

par.common = common;
par.detail = detail;
end

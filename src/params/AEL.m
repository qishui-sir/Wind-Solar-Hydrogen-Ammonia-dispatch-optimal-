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

par.source.paper = 'Qi 2023 Applied Energy';
par.source.note = 'Qi Tables B.8/B.9 for a 500 Nm3/h stack; Zhou Tables 2/4 for system scheduling.'; % Parameter scope

par.far_const = 96485.33212;    % Faraday constant, C/mol
par.far_eff = 1.0;              % Faraday efficiency, fraction
par.h2_molar_mass = 2.01588e-3; % Hydrogen molar mass, kg/mol

par.cell_num = 298;
par.cell_area = 2.0;            % 500 Nm3/h

par.r1 = 1.71e-4;               % Qi U-I ohmic coefficient
par.r2 = -1.96e-7;              % Qi U-I temperature coefficient
par.s = 0.16;                   % Qi U-I activation coefficient
par.t1 = -0.24;                 % Qi U-I activation coefficient
par.t2 = 26.23;                 % Qi U-I activation coefficient
par.t3 = 139.88;                % Qi U-I activation coefficient
par.tn_voltage = 1.48;          % Qi thermal-neutral voltage, V
par.deg_voltage = 0;            % Initial degradation voltage rise, V

par.stack_temp = 90.0;          % After-stack temperature, degC
par.sep_temp = 90.0;            % Before-stack temperature, degC
par.temp_limit = 95.0;          % Qi MW-scale upper temperature limit, degC
par.pid_set = 88.78;            % Qi large-system PID set point, degC
par.pid_i_set = 89.57;          % Qi large-system PID-I set point, degC
par.mpc_set = 93.23;            % Qi large-system MPC set point, degC

par.stack_h2 = 500;             % Qi large-stack rated H2 output, Nm3/h
par.cur_density = 2000;         % Qi nominal current density, A/m2
par.module_h2 = 1000;           % Zhou scheduling module H2 output, Nm3/h
par.spec_energy = 5.0;          % Zhou original AEL energy use, kWh/Nm3
par.min_load = 0.20;            % Zhou AEL minimum load, fraction
par.max_load = 1.00;            % Zhou AEL maximum load, fraction
par.min_stable = 60;            % Zhou AEL minimum stable time, min
par.startup_elec = 0.15;        % Zhou startup electricity, load fraction/h
par.water_use = 28;             % Zhou AEL water use, t/t-H2
par.seg_num = 12;               % Zhou piecewise segment count

par.cell_diam = 1.6;            % Qi 500 Nm3/h cell diameter, m
par.stack_diam = 2.04;          % Qi 500 Nm3/h stack diameter, m
par.stack_len = 5.4;            % Qi 500 Nm3/h stack length, m
par.stack_area = 41;            % Qi 500 Nm3/h stack surface area, m2
par.stack_volume = 8;           % Qi 500 Nm3/h free stack volume, m3
par.stack_void = 0.5;           % Qi stack void fraction at rated load
par.stack_emiss = 0.8;          % Qi stack surface blackness
par.sep_volume = 2.2;           % Qi 500 Nm3/h separator volume, m3
par.sep_level = 0.1095;         % Qi separator liquid level, m
par.elec_type = 'KOH';          % Qi electrolyte type
par.elec_koh = 0.312;           % Qi KOH mass fraction
par.elec_flow = 25.2;           % Qi 500 Nm3/h electrolyte flow, m3/h
par.coil_htc = 8820;            % Qi cooling-coil heat transfer coefficient, W/K
par.sep_resist = 0.004;         % Qi separator thermal resistance, K/W
par.stack_heat = 55e6;          % Qi stack heat capacity, J/K
par.sep_heat = 4.26e6;          % Qi separator heat capacity, J/K
par.coil_heat = 1.15e6;         % Qi cooling-coil heat capacity, J/K
par.stack_delay = 6 * 60;       % Qi stack time delay, s
par.coil_delay = 4 * 60;        % Qi cooling-coil time delay, s
par.sb_const = 5.670374419e-8;  % Radiation constant for Qi heat-loss Eq. (7), W/(m2 K4)

switch scenario_id
    case 's1'
        par.startup = false;    % Enable AEL startup electricity
        par.capacity = 140;     % S1 AEL capacity, MW
    case 's2'
        par.startup = false;    
        par.capacity = 130;     % S2 AEL capacity, MW
    case 's3'
        par.startup = true;     
        par.capacity = 130;     % S3 AEL capacity, MW
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

par.max_power = par.capacity * power_scale;                 % AEL rated power, kW
par.min_power = par.max_power * par.min_load;               % AEL minimum power, kW
par.module_power = par.module_h2 * par.spec_energy;         % Zhou scheduling module power, kW
par.module_num = ceil(par.max_power / par.module_power);    % Zhou scheduling module count
par.stack_num = ceil(par.max_power / ...
    (par.stack_h2 * par.spec_energy));                      % Qi-equivalent stack count
par.stack_per_module = par.module_h2 / par.stack_h2;        % Qi stacks per Zhou module
par.h2_output = par.max_power / par.spec_energy;            % Zhou AEL H2 output, Nm3/h
par.h2_mass = par.h2_output * h2_density;                   % Zhou AEL H2 output, kg/h
par.mass_spec_energy = par.spec_energy / h2_density;        % Derived Zhou AEL energy use, kWh/kg
end

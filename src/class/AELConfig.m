classdef AELConfig < handle
    %AEL undefined
    %   undefined

    properties
        source          % struct，含 paper 和 note
        far_const       % 法拉第常数，C/mol
        far_eff         % 法拉第效率，分数
        h2_molar_mass   % 氢气摩尔质量，kg/mol
        
        % Stack params
        cell_num        % 电池片数
        cell_area       % 单电池面积，m²
        r1              % 欧姆系数
        r2              % 温度系数
        s               % 活化系数
        t1              % 活化系数
        t2              % 活化系数
        t3              % 活化系数
        tn_voltage      % 热中性电压，V
        deg_voltage     % 初始退化电压，V
        
        % 温度控制
        stack_temp      % 电堆出口温度，℃
        sep_temp        % 分离器进口温度，℃
        temp_limit      % 上限温度，℃
        pid_set         % PID 设定点，℃
        pid_i_set       % PID-I 设定点，℃
        mpc_set         % MPC 设定点，℃
        
        % 额定与模块化
        stack_h2        % 单堆额定产氢，Nm³/h
        cur_density     % 额定电流密度，A/m²
        module_h2       % 调度模块产氢，Nm³/h
        spec_energy     % 能耗，kWh/Nm³
        min_load        % 最小负荷率，分数
        max_load        % 最大负荷率，分数
        min_stable      % 最小稳定运行时间，min
        startup_elec    % 启动附加电耗，负荷分数/h
        water_use       % 水耗，t/t-H2
        seg_num         % 分段线性化段数
        
        % 物理尺寸与热参数 (Qi)
        cell_diam       % 电池直径，m
        stack_diam      % 电堆直径，m
        stack_len       % 电堆长度，m
        stack_area      % 电堆表面积，m²
        stack_volume    % 自由体积，m³
        stack_void      % 空隙率
        stack_emiss     % 表面黑度
        sep_volume      % 分离器体积，m³
        sep_level       % 液位，m
        elec_type       % 电解质类型
        elec_koh        % KOH 质量分数
        elec_flow       % 电解液流量，m³/h
        coil_htc        % 冷却盘管换热系数，W/K
        sep_resist      % 分离器热阻，K/W
        stack_heat      % 电堆热容，J/K
        sep_heat        % 分离器热容，J/K
        coil_heat       % 盘管热容，J/K
        stack_delay     % 电堆延迟时间，s
        coil_delay      % 盘管延迟时间，s
        sb_const        % Stefan-Boltzmann 常数，W/(m²·K⁴)
        
        % 场景特定
        startup         % 是否启用启动电耗（逻辑）
        capacity        % 额定装机容量，MW
        
        % 衍生量
        max_power       % 额定电功率，kW
        min_power       % 最小电功率，kW
        module_power    % 模块功率，kW
        module_num      % 模块数（整数）
        stack_num       % 等效堆数
        stack_per_module% 每个模块的堆数
        h2_output       % 氢气输出，Nm³/h
        h2_mass         % 氢气质量流量，kg/h
        mass_spec_energy% 质量比能耗，kWh/kg
    end

    methods
        function params = AELConfig(config,scenario_id)
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

            obj.source.paper = 'Qi 2023 Applied Energy';
            obj.source.note = 'Qi Tables B.8/B.9 for a 500 Nm3/h stack; Zhou Tables 2/4 for system scheduling.';
            
            obj.far_const = 96485.33212;            % C/mol
            obj.far_eff = 1.0;
            obj.h2_molar_mass = 2.01588e-3;          % kg/mol
            
            obj.cell_num = 298;
            obj.cell_area = 2.0;                     % m²
            
            obj.r1 = 1.71e-4;
            obj.r2 = -1.96e-7;
            obj.s = 0.16;
            obj.t1 = -0.24;
            obj.t2 = 26.23;
            obj.t3 = 139.88;
            obj.tn_voltage = 1.48;                  % V
            obj.deg_voltage = 0;                    % V
            
            obj.stack_temp = 90.0;                  % ℃
            obj.sep_temp = 90.0;                    % ℃
            obj.temp_limit = 95.0;                  % ℃
            obj.pid_set = 88.78;                    % ℃
            obj.pid_i_set = 89.57;                  % ℃
            obj.mpc_set = 93.23;                    % ℃
            
            obj.stack_h2 = 500;                     % Nm³/h
            obj.cur_density = 2000;                 % A/m²
            obj.module_h2 = 1000;                   % Nm³/h
            obj.spec_energy = 5.0;                  % kWh/Nm³
            obj.min_load = 0.20;                    % fraction
            obj.max_load = 1.00;                    % fraction
            obj.min_stable = 60;                    % min
            obj.startup_elec = 0.15;                % fraction of load/h
            obj.water_use = 28;                     % t/t-H2
            obj.seg_num = 12;                       % 分段数
            
            obj.cell_diam = 1.6;                    % m
            obj.stack_diam = 2.04;                  % m
            obj.stack_len = 5.4;                    % m
            obj.stack_area = 41;                    % m²
            obj.stack_volume = 8;                   % m³
            obj.stack_void = 0.5;
            obj.stack_emiss = 0.8;
            obj.sep_volume = 2.2;                   % m³
            obj.sep_level = 0.1095;                 % m
            obj.elec_type = 'KOH';
            obj.elec_koh = 0.312;
            obj.elec_flow = 25.2;                   % m³/h
            obj.coil_htc = 8820;                    % W/K
            obj.sep_resist = 0.004;                 % K/W
            obj.stack_heat = 55e6;                  % J/K
            obj.sep_heat = 4.26e6;                  % J/K
            obj.coil_heat = 1.15e6;                 % J/K
            obj.stack_delay = 6 * 60;               % s
            obj.coil_delay = 4 * 60;                % s
            obj.sb_const = 5.670374419e-8;          % W/(m²·K⁴)

            h2_density = 0.08988;                   % kg/Nm³
            power_scale = 1000;                     % MW -> kW
            
            % select scene
            switch scenario_id
                case 's1'
                    obj.startup = false;
                    obj.capacity = 140;             % MW
                case 's2'
                    obj.startup = false;
                    obj.capacity = 130;             % MW
                case 's3'
                    obj.startup = true;
                    obj.capacity = 130;             % MW
                otherwise
                    error('AELConfig:badScenario', ...
                        'scenario_id must be ''s1'', ''s2'', or ''s3''.');
            end
            
            % ----- 用 config 覆盖单位参数（若有）
            if isfield(config, 'unit')
                if isfield(config.unit, 'h2_density')
                    h2_density = config.unit.h2_density;
                end
                if isfield(config.unit, 'power_scale')
                    power_scale = config.unit.power_scale;
                end
            end
            
            % 计算衍生量
            obj.max_power = obj.capacity * power_scale;                       % kW
            obj.min_power = obj.max_power * obj.min_load;                     % kW
            obj.module_power = obj.module_h2 * obj.spec_energy;               % kW/module
            obj.module_num = ceil(obj.max_power / obj.module_power);          % 向上取整
            obj.stack_num = ceil(obj.max_power / ...
                (obj.stack_h2 * obj.spec_energy));                           % 等效堆数
            obj.stack_per_module = obj.module_h2 / obj.stack_h2;              % 每模块堆数
            obj.h2_output = obj.max_power / obj.spec_energy;                 % Nm³/h
            obj.h2_mass = obj.h2_output * h2_density;                        % kg/h
            obj.mass_spec_energy = obj.spec_energy / h2_density;             % kWh/kg
        end
    end
        end
        function outputArg = method1(obj,inputArg)
            %METHOD1 undefined
            %   undefined
            outputArg = obj.Property1 + inputArg;
        end
    end
end
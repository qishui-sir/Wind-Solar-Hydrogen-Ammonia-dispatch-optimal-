% Standardize units
% T[K],Δt[s],j[Am-2],RASR[Ωm2]P[W],Cth[JK-1],M_H2[kgmol-1]

%Qi-journal

function par = params()
    par.F = 96485.33212;

    par.N_cell=298;
    par.A_m2=2.0;    % m2
    par.r1=1.71e-4;  % Ωm2
    par.r2=-1.96e-7; % Ωm2/K
    par.s=0.16;      % V
    par.t1=-0.24;    % m2/A
    par.t2=26.23;    % m2K_A
    par.t3=139.88;   % m2K2/A
    par.T_C=90.0;    % centigrade
    par.T_K=par.T_C+273.15;  % Kelvin

    par.eta_F = 1.0;

    
end

function config = case_cfg_7day(scenario_id) %#ok<DEFNU>
%CASE_CFG_7DAY Zhou-based parameter set for a 7-day PtA case.
%   config = case_cfg_7day() returns the S2 continuous flexible case.
%   config = case_cfg_7day('s1'|'s2'|'s3') selects a Zhou scenario.

if nargin < 1 || isempty(scenario_id)
    scenario_id = 's2';
end

if isstring(scenario_id) && isscalar(scenario_id)
    scenario_id = char(scenario_id);
end

if ~ischar(scenario_id)
    error('case_cfg_7day:bad_case', 'scenario_id must be s1, s2, or s3.');
end

scenario_id = lower(strtrim(scenario_id));
config = struct();

config.source.paper = 'Zhou 2024 ECM';                 % 参数来源文献
config.source.doi = '10.1016/j.enconman.2024.118720'; % 参数来源 DOI
config.source.note = 'Table 2 plus Table 3/4 scenario data.'; % 参数表说明

config.time.time_step_h = 1;        % 仿真时间步长，h
config.time.day_count = 7;          % 仿真天数，day
config.time.hour_per_day = 24;      % 每天小时数，h/day
config.time.hour_per_year = 8760;   % 每年小时数，h/year

config.renewable.total_capacity_kw = 400e3;      % 风光总装机容量，kW
config.renewable.pv_capacity_kw = 200e3;         % PV 装机容量，kW
config.renewable.pw_capacity_kw = 200e3;         % PW 装机容量，kW
config.renewable.pv_recommended_kw = 100e3;      % 文献推荐 PV 容量，kW
config.renewable.pw_recommended_kw = 300e3;      % 文献推荐 PW 容量，kW
config.renewable.pw_min_capacity_kw = 0;         % PW 搜索下限，kW
config.renewable.pw_max_capacity_kw = 400e3;     % PW 搜索上限，kW
config.renewable.pw_capacity_step_kw = 50e3;     % PW 搜索步长，kW
config.renewable.data_dir = '';                  % 风光数据目录，空值表示外部指定
config.renewable.start_time = [];                % 风光数据起始时间，空值表示从首行开始

config.finance.project_lifetime_y = 20;          % 项目寿命，year
config.finance.discount_rate = 0.05;             % 折现率，fraction/year
config.finance.loan_year = 20;                   % 贷款年限，year
config.finance.loan_ratio = 0.80;                % 贷款比例，fraction
config.finance.loan_interest_rate = 0.046;       % 贷款利率，fraction/year
if config.finance.discount_rate == 0
    config.finance.capital_recovery_factor = ...
        1 / config.finance.project_lifetime_y;   % 资本回收系数，1/year
else
    config.finance.capital_recovery_factor = ...
        config.finance.discount_rate * ...
        (1 + config.finance.discount_rate)^config.finance.project_lifetime_y / ...
        ((1 + config.finance.discount_rate)^config.finance.project_lifetime_y - 1); % 资本回收系数，1/year
end

config.pw.capex_usd_kw = 685;                    % PW 单位投资成本，USD/kW
config.pw.om_fraction = 0.02;                    % PW 年运维费率，fraction/year
config.pv.capex_usd_kw = 543;                    % PV 单位投资成本，USD/kW
config.pv.om_fraction = 0.01;                    % PV 年运维费率，fraction/year

config.alkaline_electrolyzer.capex_usd_kw = 285; % 碱性电解槽单位投资成本，USD/kW
config.alkaline_electrolyzer.om_fraction = 0.02; % 碱性电解槽年运维费率，fraction/year
config.alkaline_electrolyzer.module_h2_nm3_h = 1000; % 单台电解槽额定产氢量，Nm3/h
config.alkaline_electrolyzer.specific_power_kwh_nm3 = 5.0; % 单位氢气电耗，kWh/Nm3
config.alkaline_electrolyzer.min_load_fraction = 0.20; % 电解槽最低负荷率，fraction
config.alkaline_electrolyzer.max_load_fraction = 1.00; % 电解槽最高负荷率，fraction
config.alkaline_electrolyzer.min_stable_time_min = 60; % 最短稳定运行时间，min
config.alkaline_electrolyzer.start_energy_fraction = 0.15; % 启动能耗占额定能耗比例，fraction
config.alkaline_electrolyzer.water_t_per_t_h2 = 28; % 制氢耗水量，t/t-H2
config.alkaline_electrolyzer.segment_count = 12; % 分段线性化段数
config.alkaline_electrolyzer.degradation_voltage_v = 0; % 初始退化电压增量，V

config.h2_storage.capex_usd_nm3 = 50;            % 储氢单位投资成本，USD/Nm3
config.h2_storage.om_fraction = 0.01;            % 储氢年运维费率，fraction/year
config.h2_storage.module_capacity_nm3 = 22000;   % 单个储氢模块容量，Nm3
config.h2_storage.min_pressure_mpa = 0.5;        % 储氢最低压力，MPa
config.h2_storage.max_pressure_mpa = 1.5;        % 储氢最高压力，MPa
config.h2_storage.temperature_c = 30;            % 储氢温度，degC

config.haber_bosch.capex_usd_tpy = 561;          % 合成氨单位投资成本，USD/(t/y)
config.haber_bosch.om_fraction = 0.02;           % 合成氨年运维费率，fraction/year
config.haber_bosch.capacity_t_y = 100000;        % 合成氨额定产能，t/year
config.haber_bosch.electricity_mwh_per_t_nh3 = 0.95; % 合成氨电耗，MWh/t-NH3
config.haber_bosch.nh3_t_per_t_nh3 = 1.00;       % 氨产品折算系数，t/t-NH3
config.haber_bosch.n2_t_per_t_nh3 = 0.84;        % 氮气消耗量，t/t-NH3
config.haber_bosch.h2_t_per_t_nh3 = 0.18;        % 氢气消耗量，t/t-NH3
config.haber_bosch.water_t_per_t_nh3 = 2.70;     % 合成氨耗水量，t/t-NH3
config.haber_bosch.load_step_fraction = 0.10;    % 多稳态负荷档位间隔，fraction
config.haber_bosch.control_interval_h = 4;       % 调度控制间隔，h

config.ammonia.price_usd_t = 557;                % 氨销售价格，USD/t
config.material.water_price_usd_t = 1.4;         % 水价格，USD/t
config.material.catalyst_price_usd_t = 18;       % 催化剂价格，USD/t

config.converter.capex_usd_kw = 43;              % 电力变换器单位投资成本，USD/kW
config.converter.om_fraction = 0.02;             % 电力变换器年运维费率，fraction/year
config.transformer.capex_usd_kw = 51;            % 变压器单位投资成本，USD/kW
config.transformer.om_fraction = 0.02;           % 变压器年运维费率，fraction/year
config.transformer.max_load_fraction = 0.90;     % 变压器最高负荷率，fraction

config.grid.sell_price_usd_kwh = 0.041;          % 上网电价，USD/kWh
config.grid.buy_price_usd_kwh = 0.053;           % 购电电价，USD/kWh
config.grid.capacity_fee_usd_kw_month = 3.85;    % 电网容量费，USD/(kW month)
config.grid.curtailment_limit_fraction = 0.10;   % 最大弃电率约束，fraction
config.grid.max_sell_fraction = 0.20;            % 最大售电比例，fraction
config.grid.enable_buy = true;                   % 是否允许购电
config.grid.enable_sell = true;                  % 是否允许售电

config.environment.grid_co2_kg_kwh = 0.5703;     % 电网碳排放因子，kg-CO2/kWh
config.environment.co2_limit_kg_kg_nh3 = 0.3;    % 氨产品碳排放上限，kg-CO2/kg-NH3

config.optimizer.cognitive_weight = 1;           % PSO 个体学习因子
config.optimizer.social_weight = 1;              % PSO 群体学习因子
config.optimizer.inertia_weight = 1;             % PSO 惯性权重
config.optimizer.iteration_count = 100;          % PSO 最大迭代次数
config.optimizer.particle_count = 10;            % PSO 粒子数量

switch scenario_id
    case 's1'
        config = apply_s1_fixed_load(config);
    case 's2'
        config = apply_s2_continuous_flexible(config);
    case 's3'
        config = apply_s3_multi_state_flexible(config);
    otherwise
        error('case_cfg_7day:bad_case', 'scenario_id must be s1, s2, or s3.');
end

config.unit.h2_kg_per_nm3 = 0.08988;             % 氢气密度换算，kg/Nm3
config.unit.kg_per_t = 1000;                     % 吨到千克换算，kg/t
config.unit.kw_per_mw = 1000;                    % MW 到 kW 换算，kW/MW

config.alkaline_electrolyzer.max_power_kw = ...
    config.alkaline_electrolyzer.capacity_mw * config.unit.kw_per_mw; % 电解槽额定功率，kW
config.alkaline_electrolyzer.min_power_kw = ...
    config.alkaline_electrolyzer.max_power_kw * ...
    config.alkaline_electrolyzer.min_load_fraction; % 电解槽最低运行功率，kW
config.alkaline_electrolyzer.module_power_kw = ...
    config.alkaline_electrolyzer.module_h2_nm3_h * ...
    config.alkaline_electrolyzer.specific_power_kwh_nm3; % 单台电解槽额定功率，kW
config.alkaline_electrolyzer.module_count = ...
    ceil(config.alkaline_electrolyzer.max_power_kw / ...
    config.alkaline_electrolyzer.module_power_kw); % 电解槽模块数量
config.alkaline_electrolyzer.h2_output_nm3_h = ...
    config.alkaline_electrolyzer.max_power_kw / ...
    config.alkaline_electrolyzer.specific_power_kwh_nm3; % 额定产氢量，Nm3/h
config.alkaline_electrolyzer.h2_output_kg_h = ...
    config.alkaline_electrolyzer.h2_output_nm3_h * ...
    config.unit.h2_kg_per_nm3;                    % 额定产氢量，kg/h

config.h2_storage.capacity_kg = ...
    config.h2_storage.capacity_nm3 * config.unit.h2_kg_per_nm3; % 储氢容量，kg

config.haber_bosch.capacity_kg_h = ...
    config.haber_bosch.capacity_t_y * config.unit.kg_per_t / ...
    config.time.hour_per_year;                    % 合成氨额定产量，kg/h
config.haber_bosch.h2_demand_kg_h = ...
    config.haber_bosch.capacity_kg_h * config.haber_bosch.h2_t_per_t_nh3; % 额定耗氢量，kg/h
config.haber_bosch.nominal_power_mw = ...
    config.haber_bosch.capacity_t_y * ...
    config.haber_bosch.electricity_mwh_per_t_nh3 / ...
    config.time.hour_per_year;                    % 合成氨额定电功率，MW

config.converter.capacity_mw = config.alkaline_electrolyzer.capacity_mw; % 变换器容量，MW
config.reference.ael_capacity_mw = config.alkaline_electrolyzer.capacity_mw; % 文献电解槽容量，MW
config.reference.h2_storage_capacity_nm3 = config.h2_storage.capacity_nm3; % 文献储氢容量，Nm3
config.reference.transformer_capacity_mw = config.transformer.capacity_mw; % 文献变压器容量，MW

if abs(config.renewable.pv_capacity_kw + ...
        config.renewable.pw_capacity_kw - ...
        config.renewable.total_capacity_kw) > 1e-6
    error('case_cfg_7day:bad_res', 'PV plus PW must equal total renewable capacity.');
end

if config.alkaline_electrolyzer.min_power_kw > ...
        config.alkaline_electrolyzer.max_power_kw
    error('case_cfg_7day:bad_ael', 'AEL min power exceeds max power.');
end

if config.haber_bosch.min_load_fraction > config.haber_bosch.max_load_fraction
    error('case_cfg_7day:bad_hb', 'HB min load exceeds max load.');
end

if config.h2_storage.capacity_kg <= 0 || config.transformer.capacity_mw <= 0
    error('case_cfg_7day:bad_cap', 'Main capacities must be positive.');
end
end

function config = apply_s1_fixed_load(config)
config.scenario.id = 's1';                       % 场景编号
config.scenario.mode = 'fixed_load';             % 场景模式：固定负荷合成氨
config.haber_bosch.min_load_fraction = 1.00;     % 合成氨最低负荷率，fraction
config.haber_bosch.max_load_fraction = 1.00;     % 合成氨最高负荷率，fraction
config.haber_bosch.set_load_fraction = 1.00;     % 合成氨固定负荷率，fraction
config.haber_bosch.ramp_fraction_h = 0;          % 合成氨爬坡速率，fraction/h
config.haber_bosch.stable_window_h = [0, 24];    % 稳定运行时段，h
config.haber_bosch.flexible_window_h = zeros(0, 2); % 柔性运行时段，h
config.alkaline_electrolyzer.enable_start_energy = false; % 是否计入启动能耗
config.environment.enable_co2_limit = false;     % 是否启用碳排放约束
config.alkaline_electrolyzer.capacity_mw = 140;  % 电解槽装机容量，MW
config.h2_storage.capacity_nm3 = 17.6e4;         % 储氢容量，Nm3
config.transformer.capacity_mw = 190;            % 变压器容量，MW
config.reference.nh3_output_t_y = 1.00e5;        % 文献年产氨量，t/year
config.reference.lcoa_usd_t = 549;               % 文献平准化氨成本，USD/t
config.reference.ael_use_h = 7163;               % 文献电解槽利用小时，h/year
config.reference.grid_buy_fraction = 0.3086;     % 文献购电比例，fraction
config.reference.grid_sell_fraction = 0.1724;    % 文献售电比例，fraction
config.reference.curtailment_fraction = 0.0021;  % 文献弃电比例，fraction
config.reference.co2_kg_kg_nh3 = 1.70;           % 文献碳强度，kg-CO2/kg-NH3
end

function config = apply_s2_continuous_flexible(config)
config.scenario.id = 's2';                       % 场景编号
config.scenario.mode = 'continuous_flexible';    % 场景模式：连续柔性合成氨
config.haber_bosch.min_load_fraction = 0.30;     % 合成氨最低负荷率，fraction
config.haber_bosch.max_load_fraction = 1.00;     % 合成氨最高负荷率，fraction
config.haber_bosch.set_load_fraction = [];       % 合成氨固定负荷率，空值表示不固定
config.haber_bosch.ramp_fraction_h = 0.20;       % 合成氨爬坡速率，fraction/h
config.haber_bosch.stable_window_h = zeros(0, 2); % 稳定运行时段，h
config.haber_bosch.flexible_window_h = [0, 24];  % 柔性运行时段，h
config.alkaline_electrolyzer.enable_start_energy = false; % 是否计入启动能耗
config.environment.enable_co2_limit = true;      % 是否启用碳排放约束
config.alkaline_electrolyzer.capacity_mw = 130;  % 电解槽装机容量，MW
config.h2_storage.capacity_nm3 = 11.0e4;         % 储氢容量，Nm3
config.transformer.capacity_mw = 200;            % 变压器容量，MW
config.reference.nh3_output_t_y = 7.12e4;        % 文献年产氨量，t/year
config.reference.lcoa_usd_t = 464;               % 文献平准化氨成本，USD/t
config.reference.ael_use_h = 5492;               % 文献电解槽利用小时，h/year
config.reference.grid_buy_fraction = 0.0015;     % 文献购电比例，fraction
config.reference.grid_sell_fraction = 0.1920;    % 文献售电比例，fraction
config.reference.curtailment_fraction = 0.0020;  % 文献弃电比例，fraction
config.reference.co2_kg_kg_nh3 = 0.01;           % 文献碳强度，kg-CO2/kg-NH3
end

function config = apply_s3_multi_state_flexible(config)
config.scenario.id = 's3';                       % 场景编号
config.scenario.mode = 'multi_state_flexible';   % 场景模式：多稳态柔性合成氨
config.haber_bosch.min_load_fraction = 0.30;     % 合成氨最低负荷率，fraction
config.haber_bosch.max_load_fraction = 1.10;     % 合成氨最高负荷率，fraction
config.haber_bosch.set_load_fraction = 0.30:0.10:1.10; % 合成氨可选负荷档位，fraction
config.haber_bosch.ramp_fraction_h = 0.20;       % 合成氨爬坡速率，fraction/h
config.haber_bosch.stable_window_h = [0, 12; 16, 24]; % 稳定运行时段，h
config.haber_bosch.flexible_window_h = [12, 16]; % 柔性运行时段，h
config.alkaline_electrolyzer.enable_start_energy = true; % 是否计入启动能耗
config.environment.enable_co2_limit = true;      % 是否启用碳排放约束
config.alkaline_electrolyzer.capacity_mw = 130;  % 电解槽装机容量，MW
config.h2_storage.capacity_nm3 = 13.2e4;         % 储氢容量，Nm3
config.transformer.capacity_mw = 189;            % 变压器容量，MW
config.reference.nh3_output_t_y = 7.04e4;        % 文献年产氨量，t/year
config.reference.lcoa_usd_t = 475;               % 文献平准化氨成本，USD/t
config.reference.ael_use_h = 5460;               % 文献电解槽利用小时，h/year
config.reference.grid_buy_fraction = 0.0112;     % 文献购电比例，fraction
config.reference.grid_sell_fraction = 0.2000;    % 文献售电比例，fraction
config.reference.curtailment_fraction = 0.0038;  % 文献弃电比例，fraction
config.reference.co2_kg_kg_nh3 = 0.09;           % 文献碳强度，kg-CO2/kg-NH3
end

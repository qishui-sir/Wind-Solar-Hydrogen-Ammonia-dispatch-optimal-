function results = baseline(params,renewable_data)
    opts = struct();
    thisFile = mfilename('fullpath');
    rootDir = fileparts(thisFile);
    fprintf("%s\n%s",thisFile,rootDir);
    addpath(rootDir+"/params");

    T = renewable_data.time_count;
    dt = params.time.step;
    transformer_kw = params.transformer.capacity * 1000;
    
    PV_capacity = params.renewable.PV_capacity;
    PW_capacity = params.renewable.PW_capacity;
    PV = PV_capacity .* renewable_data.pv_power_kw;
    PW = PW_capacity .* renewable_data.pw_power_kw;
    P_total = PV + PW;

    P_AEL_max = params.AEL.max_power;
    P_AEL_min = params.AEL.min_power;
    AEL_spec_energy = params.AEL.spec_energy;
    H2_density = params.unit.h2_density;

    storage_H2_max = params.h2_storage.mass;
    initial_storage = 0.5*storage_H2_max;

    HB_max_load = params.HB.max_load;
    HB_min_load = params.HB.min_load;
    HB_ramp = params.HB.ramp_rate;
    HB_power_kw = params.HB.nom_power*1000;
    NH3_rate = params.HB.nh3_output;
    
    % Define optimization variables
    P_AEL = optimvar('P_AEL',T,'LowerBound',0,'UpperBound',P_AEL_max);
    HB_load = optimvar('HB_load',T,'LowerBound',HB_min_load,'UpperBound',HB_max_load);
    storage_H2 = optimvar('storage_H2',T+1,'LowerBound',0,'UpperBound',storage_H2_max);

    P_purchase = optimvar('p_purchase', T, 'LowerBound', 0, 'UpperBound', transformer_kw);
    P_sell = optimvar('p_sell', T, 'LowerBound', 0, 'UpperBound', transformer_kw);
    P_curt = optimvar('p_curt', T, 'LowerBound', 0);

    u_purchase = optimvar('u_purchase', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
    H2_short = optimvar('h2_short', T, 'LowerBound', 0);
    NH3_short = optimvar('nh3_short', 1, 'LowerBound', 0);


    H2_prod_kg = P_AEL * dt / AEL_spec_energy * H2_density;
    NH3_prod_kg = HB_load * NH3_rate * dt;
    H2_use_kg = NH3_prod_kg * params.HB.act_h2;
    P_HB_kw = HB_load * HB_power_kw;

    % constraint condition
    prob = optimproblem('ObjectiveSense', 'minimize');

    prob.Constraints.power_balance = ...    % 功率平衡约束
        P_total + P_purchase == P_AEL + P_HB_kw + P_sell + P_curt;

    prob.Constraints.H2_storage = ...       % 储氢动态平衡约束
        storage_H2(2:end) == storage_H2(1:end-1) + H2_prod_kg ...
        + H2_short - H2_use_kg;
    prob.Constraints.H2_initial = storage_H2(1) == initial_storage; 
    prob.Constraints.H2_terminal = storage_H2(end) >= initial_storage;
    prob.Constraints.H2_short = H2_short <= H2_use_kg;

    prob.Constraints.purchase = P_purchase <= u_purchase * transformer_kw;  % 购售电约束
    prob.Constraints.sell = P_sell <= (1 - u_purchase) * transformer_kw;

    prob.Constraints.HB_ramp_up = HB_load(2:end) - HB_load(1:end-1) <= HB_ramp; %爬坡约束
    prob.Constraints.HB_ramp_down = HB_load(1:end-1) - HB_load(2:end) <=HB_ramp;

    prob.Constraints.curtail = P_curt <= P_total;     %弃电约束

    %% 
    NH3_alpha = params.ref.nh3_output / params.HB.capacity;
    if isfield(opts, 'NH3_alpha')
        NH3_alpha = opts.NH3_alpha;
    end
    
    NH3_target_kg = NH3_alpha * NH3_rate * T * dt;
    prob.Constraints.NH3_target_kg = sum(NH3_prod_kg) + NH3_short >= NH3_target_kg;
    % objective function
    C_curt = 0.01;
    C_purchase = params.grid.buy_price;
    C_sell = params.grid.sell_price;
    C_H2_short = 1e4;
    C_NH3_short = 1e4;

    obj_formula = sum(C_curt .* P_curt * dt) + ...
        sum(C_purchase .* P_purchase * dt) - ...
        sum(C_sell .* P_sell * dt) + ...
        sum(C_H2_short .* H2_short) + ...
        sum(C_NH3_short .* NH3_short);
    prob.Objective = obj_formula;

    options = optimoptions('intlinprog', 'Display', 'iter');
    [sol, fval, exitflag, output] = solve(prob, ...
        'Solver', 'intlinprog', ...
        'Options', options);
    
    disp(sol);
    disp(['最优目标值: ', num2str(fval)]);
    disp(['求解状态: ', num2str(exitflag)]);
    disp(output);

    % 提取优化变量
    P_AEL_opt = sol.P_AEL;
    HB_load_opt = sol.HB_load;
    storage_H2_opt = sol.storage_H2;
    P_purchase_opt = sol.p_purchase;
    P_sell_opt = sol.p_sell;
    P_curt_opt = sol.p_curt;
    u_purchase_opt = sol.u_purchase;
    H2_short_opt = sol.h2_short;
    NH3_short_opt = sol.nh3_short;
    
    % 计算衍生量
    H2_prod_kg_opt = P_AEL_opt * dt / AEL_spec_energy * H2_density;
    NH3_prod_kg_opt = HB_load_opt * NH3_rate * dt;
    H2_use_kg_opt = NH3_prod_kg_opt * params.HB.act_h2;
    P_HB_kw_opt = HB_load_opt * HB_power_kw;
    
    % 打包返回结果
    results = struct();
    results.fval = fval;
    results.exitflag = exitflag;
    results.output = output;
    results.sol = sol;  % 包含所有原始变量
    
    % 添加方便使用的时序数据
    results.P_AEL = P_AEL_opt;
    results.HB_load = HB_load_opt;
    results.storage_H2 = storage_H2_opt;
    results.P_purchase = P_purchase_opt;
    results.P_sell = P_sell_opt;
    results.P_curt = P_curt_opt;
    results.u_purchase = u_purchase_opt;
    results.H2_short = H2_short_opt;
    results.NH3_short = NH3_short_opt;
    results.H2_prod = H2_prod_kg_opt;
    results.NH3_prod = NH3_prod_kg_opt;
    results.H2_use = H2_use_kg_opt;
    results.P_HB = P_HB_kw_opt;
    
    % 统计信息（七天汇总）
    results.total_purchase = sum(P_purchase_opt * dt);   % 总购电量 (kWh)
    results.total_sell = sum(P_sell_opt * dt);           % 总卖电量 (kWh)
    results.total_curtail = sum(P_curt_opt * dt);        % 总弃电量 (kWh)
    results.total_H2_prod = sum(H2_prod_kg_opt);         % 总产氢量 (kg)
    results.total_NH3_prod = sum(NH3_prod_kg_opt);       % 总产氨量 (kg)
    results.total_H2_short = sum(H2_short_opt);          % 总氢短缺 (kg)
    results.total_NH3_short = NH3_short_opt;             % 总氨短缺 (kg)
    
    % 将时间向量也带上
    if isfield(renewable_data, 'time')
        results.time = renewable_data.time;
    else
        results.time = (1:T)';  % 或根据dt生成实际时间
    end
end
    
function results = baseline(params,renewable_data)
    opts = struct();
    thisFile = mfilename('fullpath');
    rootDir = fileparts(thisFile);
    fprintf("%s\n%s",thisFile,rootDir);
    addpath(rootDir+"/params");
    addpath(rootDir+"/results");

    T = renewable_data.time_count;
    dt = params.time.step;
    transformer_kw = params.transformer.max_load * params.transformer.capacity * 1000;

    PV = renewable_data.pv_power_kw * 0.8623;
    PW = renewable_data.pw_power_kw * 0.8623;
    P_total = PV + PW;
    annual_renewable = sum(P_total) * dt;

    ael_common = params.AEL.common;
    P_AEL_max = ael_common.max_power;
    P_AEL_min = ael_common.min_power;
    AEL_spec_energy = ael_common.spec_energy;
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
    %H2_short = optimvar('h2_short', T, 'LowerBound', 0);

    H2_prod_kg = P_AEL * dt / AEL_spec_energy * H2_density;
    NH3_prod_kg = HB_load * NH3_rate * dt;
    H2_use_kg = NH3_prod_kg * params.HB.lit_h2;
    P_HB_kw = HB_load * HB_power_kw;

    % create optimization problems
    prob = optimproblem('ObjectiveSense', 'minimize');

    % constraint condition
    prob.Constraints.power_balance = ...
        P_total + P_purchase == P_AEL + P_HB_kw + P_sell + P_curt;
    prob.Constraints.H2_storage = ...
        storage_H2(2:end) == storage_H2(1:end-1) + H2_prod_kg ...
         - H2_use_kg;
    prob.Constraints.H2_initial = storage_H2(1) == initial_storage;
    prob.Constraints.H2_terminal = storage_H2(end) == initial_storage;
    prob.Constraints.purchase = P_purchase <= u_purchase * transformer_kw;
    prob.Constraints.sell = P_sell <= (1 - u_purchase) * transformer_kw;
    prob.Constraints.sell_rate = ...
        mean(P_sell) <= ...
        params.grid.max_sell * mean(P_total);
    prob.Constraints.HB_ramp_up = HB_load(2:end) - HB_load(1:end-1) <= HB_ramp;
    prob.Constraints.HB_ramp_down = HB_load(1:end-1) - HB_load(2:end) <=HB_ramp;
    prob.Constraints.curtail = P_curt <= P_total;
    prob.Constraints.curtail_rate = sum(P_curt) * dt <= ...
        params.grid.curtail_limit * annual_renewable;

    if params.environment.co2_enabled
        prob.Constraints.co2_limit = ...
            params.environment.grid_co2 * sum(P_purchase) * dt <= ...
            params.environment.co2_limit * sum(NH3_prod_kg);
    end

    NH3_total_kg = sum(NH3_prod_kg);
    NH3_income = params.ammonia.price * NH3_total_kg / 1000;

    C_curt = 0.01;
    C_purchase = params.grid.buy_price;
    C_sell = params.grid.sell_price;
    %C_H2_short = 1e4;

    % objective function
    obj_formula = sum(C_curt .* P_curt * dt) + ...
        sum(C_purchase .* P_purchase * dt) - ...
        sum(C_sell .* P_sell * dt) - ...
        NH3_income;
    prob.Objective = obj_formula;

    options = optimoptions('intlinprog', 'Display', 'iter',...
        'ConstraintTolerance', 1e-5, ...
        'RelativeGapTolerance', 1e-4);
    [sol, fval, exitflag, output] = solve(prob, ...
        'Solver', 'intlinprog', ...
        'Options', options);

    disp(sol);
    disp(['最优目标值: ', num2str(fval)]);
    disp(['求解状态: ', num2str(exitflag)]);
    disp(output);

    if exitflag <= 0 || isempty(sol.P_AEL)
        error('baseline:no_feasible_solution', ...
            ['Optimization did not return a feasible dispatch. ', ...
            'Exitflag: %d. Solver message: %s'], ...
            exitflag, output.message);
    end

    result_context = struct();
    result_context.T = T;
    result_context.dt = dt;
    result_context.P_total = P_total;
    result_context.AEL_spec_energy = AEL_spec_energy;
    result_context.H2_density = H2_density;
    result_context.NH3_rate = NH3_rate;
    result_context.HB_power_kw = HB_power_kw;
    result_context.C_curt = C_curt;
    result_context.C_purchase = C_purchase;
    result_context.C_sell = C_sell;
    result_context.ael_common = ael_common;

    results = feval('results', params, renewable_data, sol, fval, ...
        exitflag, output, result_context);
end

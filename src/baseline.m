function results = baseline(params, renewable_data, algorithm)
%   BASELINE Build and solve the common wind-hydrogen-ammonia dispatch model.
%   BASELINE(PARAMS, DATA) keeps the original single-stage economic solve.
%   BASELINE(PARAMS, DATA, ALGORITHM) passes the unsolved common model to a
%   function handle, so a study can add constraints without copying this model.
    opts = struct();
    thisFile = mfilename('fullpath');
    rootDir = fileparts(thisFile);
    fprintf("%s\n%s",thisFile,rootDir);
    addpath(rootDir+"/params");
    addpath(rootDir+"/results");

    T = renewable_data.time_count;
    dt = params.time.step;
    transformer_kw = params.transformer.max_load * params.transformer.capacity * 1000;

    PV = renewable_data.pv_power_kw;
    PW = renewable_data.pw_power_kw;
    P_total = PV + PW;
    annual_renewable = sum(P_total) * dt;

    ael_common = params.AEL.common;
    Num_AEL = ael_common.module_num;
    P_AEL_max = ael_common.max_power;

    AEL_spec_energy = ael_common.spec_energy;
    AEL_module_power = ael_common.module_power;
    AEL_start_power_per_module = 0;
    if ael_common.startup
        AEL_start_power_per_module = ...
            ael_common.startup_elec * AEL_module_power;
    end
    H2_density = params.unit.h2_density;

    storage_limits = h2_storage_limits(params.h2_storage, H2_density);
    storage_H2_min = storage_limits.min_mass;
    storage_H2_max = storage_limits.max_mass;
    initial_storage = storage_limits.initial_mass;
    
    reserve_work_soc = 0;
    if isfield(params.h2_storage, 'min_work_soc') && ...
            ~isempty(params.h2_storage.min_work_soc)
        reserve_work_soc = params.h2_storage.min_work_soc;
    end
    if reserve_work_soc > 0
        reserve_min_mass = storage_limits.min_mass + ...
            reserve_work_soc * storage_limits.work_mass;
        storage_H2_min = max(storage_H2_min, reserve_min_mass);
        initial_storage = max(initial_storage, reserve_min_mass);
    end

    HB_max_load = params.HB.max_load;
    HB_min_load = params.HB.min_load;
    HB_ramp = params.HB.ramp_rate;
    HB_power_kw = params.HB.nom_power*1000;
    NH3_rate = params.HB.nh3_output;

    % Define optimization variables
    N_AEL = optimvar('n_ael',T,'Type','integer','LowerBound', 0 ,'UpperBound', Num_AEL);
    P_AEL = optimvar('P_AEL',T,'LowerBound',0,'UpperBound',P_AEL_max);
    HB_load = optimvar('HB_load',T,'LowerBound',HB_min_load,'UpperBound',HB_max_load);
    storage_H2 = optimvar('storage_H2',T+1,'LowerBound',...
        storage_H2_min,'UpperBound',storage_H2_max);
    P_purchase = optimvar('p_purchase', T, 'LowerBound', 0, 'UpperBound', transformer_kw);
    P_sell = optimvar('p_sell', T, 'LowerBound', 0, 'UpperBound', transformer_kw);
    P_curt = optimvar('p_curt', T, 'LowerBound', 0);
    u_purchase = optimvar('u_purchase', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
    grid_contract_is_fixed = ~isempty(params.grid.contract_kw);
    if ~grid_contract_is_fixed
        P_grid_contract = optimvar('grid_contract_kw', 1, ...
            'LowerBound', 0, 'UpperBound', transformer_kw);
    end
    SU_AEL = optimvar('SU_AEL',T,'Type','integer','LowerBound',0,'UpperBound',Num_AEL);
    SD_AEL = optimvar('SD_AEL',T,'Type','integer','LowerBound',0,'UpperBound',Num_AEL);
    I_AEL_up = optimvar('I_AEL_up', T, 'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);
    P_AEL_start = AEL_start_power_per_module * SU_AEL;

    %H2_short = optimvar('h2_short', T, 'LowerBound', 0);
    H2_prod_kg = P_AEL * dt / AEL_spec_energy * H2_density;
    NH3_prod_kg = HB_load * NH3_rate * dt;
    H2_use_kg = NH3_prod_kg * params.HB.lit_h2;
    P_HB_kw = HB_load * HB_power_kw;
    H2_prod_t = H2_prod_kg / params.unit.mass_scale;
    NH3_prod_t = NH3_prod_kg / params.unit.mass_scale;
    water_use_t = params.AEL.common.water_use * H2_prod_t ...
        + params.HB.water_use * NH3_prod_t;

    % create optimization problems
    prob = optimproblem('ObjectiveSense', 'minimize');

    % constraint condition
    prob.Constraints.power_balance = ...
        P_total + P_purchase == P_AEL + P_AEL_start + ...
        P_HB_kw + P_sell + P_curt;
    prob.Constraints.H2_storage = ...
        storage_H2(2:end) == storage_H2(1:end-1) + H2_prod_kg ...
         - H2_use_kg;
    prob.Constraints.H2_initial = storage_H2(1) == initial_storage;
    prob.Constraints.H2_terminal = storage_H2(end) == initial_storage;
    prob.Constraints.purchase = P_purchase <= u_purchase * transformer_kw;
    prob.Constraints.sell = P_sell <= (1 - u_purchase) * transformer_kw;
    if ~grid_contract_is_fixed
        prob.Constraints.grid_contract = P_purchase <= P_grid_contract;
    end
    prob.Constraints.sell_rate = ...
        mean(P_sell) <= ...
        params.grid.max_sell * mean(P_total);
    prob.Constraints.HB_ramp_up = ...
        HB_load(2:end) - HB_load(1:end-1) <= HB_ramp * dt;
    prob.Constraints.HB_ramp_down = ...
        HB_load(1:end-1) - HB_load(2:end) <= HB_ramp * dt;
    prob.Constraints.curtail = P_curt <= P_total;
    prob.Constraints.curtail_rate = sum(P_curt) * dt <= ...
        params.grid.curtail_limit * annual_renewable;
    prob.Constraints.AEL_module_lower = ...
        ael_common.min_load * N_AEL * AEL_module_power <= P_AEL;
    prob.Constraints.AEL_module_upper = ...
        P_AEL <= ael_common.max_load * N_AEL * AEL_module_power;
    N_AEL_initial = 0;
    N_AEL_previous = [N_AEL_initial; N_AEL(1:end-1)];
    prob.Constraints.AEL_transition = ...
        N_AEL - N_AEL_previous == SU_AEL - SD_AEL;
    prob.Constraints.AEL_start_available = SU_AEL <= Num_AEL - N_AEL_previous;
    prob.Constraints.AEL_stop_available = SD_AEL <= N_AEL_previous;
    prob.Constraints.AEL_start_indicator = SU_AEL <= Num_AEL * I_AEL_up;
    prob.Constraints.AEL_stop_indicator = SD_AEL <= Num_AEL * (1 - I_AEL_up);
    % min stable start time 
    min_run_h = 1;   
    L_run = ceil(min_run_h / dt);
    AEL_min_run = optimconstr(T, 1);
    for tau = 1:T
        k1 = max(1, tau - L_run);
        k2 = tau - 1;

        if k1 <= k2
            AEL_min_run(tau) = ...
                N_AEL(tau) >= sum(SU_AEL(k1:k2));
        else
            AEL_min_run(tau) = ...
                N_AEL(tau) >= 0;
        end
    end
    prob.Constraints.AEL_min_run = AEL_min_run;

    if params.environment.co2_enabled
        prob.Constraints.co2_limit = ...
            params.environment.grid_co2 * sum(P_purchase) * dt <= ...
            params.environment.co2_limit * sum(NH3_prod_kg);
    end

    NH3_total_kg = sum(NH3_prod_kg);
    NH3_income = params.ammonia.price * NH3_total_kg / 1000;

    C_curt = params.grid.curtail_penalty;
    C_purchase = params.grid.buy_price;
    C_sell = params.grid.sell_price;
    C_water = params.material.water_price;
    C_catalyst = params.material.cat_price;
    % Startup power is supplied through the power balance. Its economic effect
    % is already reflected in purchases, sales and renewable utilization.
    % Do not charge startup electricity a second time.
    obj_formula = sum(C_curt .* P_curt * dt) + ...
        sum(C_purchase .* P_purchase * dt) - ...
        sum(C_sell .* P_sell * dt) - ...
        NH3_income + ...
        C_water * sum(water_use_t) + ...
        C_catalyst * sum(NH3_prod_t);
    if grid_contract_is_fixed
        fixed_cost = annual_fixed_cost(params);
        grid_capacity_cost = fixed_cost.grid_capacity;
    else
        fixed_cost = annual_fixed_cost(params, 0);
        grid_capacity_cost = params.grid.cap_fee * 12 * P_grid_contract;
    end
    annual_fixed_cost_expr = fixed_cost.base_total + grid_capacity_cost;
    annual_system_cost = obj_formula + NH3_income + annual_fixed_cost_expr;
    prob.Objective = obj_formula + annual_fixed_cost_expr;

    solver_opts = {'Display', 'iter', ...
        'ConstraintTolerance', 1e-5, ...
        'RelativeGapTolerance', 0.02};

    if isfield(params, 'solver')
        if isfield(params.solver, 'relative_gap') && ...
                ~isempty(params.solver.relative_gap)
            solver_opts = set_solver_option(solver_opts, ...
                'RelativeGapTolerance', params.solver.relative_gap);
        end
        if isfield(params.solver, 'max_time_s') && ...
                ~isempty(params.solver.max_time_s)
            solver_opts = set_solver_option(solver_opts, ...
                'MaxTime', params.solver.max_time_s);
        end
        if isfield(params.solver, 'max_nodes') && ...
                ~isempty(params.solver.max_nodes) && params.solver.max_nodes > 0
            solver_opts = set_solver_option(solver_opts, ...
                'MaxNodes', params.solver.max_nodes);
        end
        if isfield(params.solver, 'display') && ...
                ~isempty(params.solver.display)
            solver_opts = set_solver_option(solver_opts, ...
                'Display', params.solver.display);
        end
    end
    options = optimoptions('intlinprog', solver_opts{:});

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
    result_context.N_AEL_initial = N_AEL_initial;

    if nargin >= 3 && ~isempty(algorithm)
        if ~isa(algorithm, 'function_handle')
            error('baseline:bad_algorithm', ...
                'The optional algorithm input must be a function handle.');
        end
        model = struct();
        model.problem = prob;
        model.variables = struct('HB_load', HB_load);
        model.expressions = struct( ...
            'nh3_total_t', NH3_total_kg / params.unit.mass_scale, ...
            'system_cost_usd', annual_system_cost);
        model.options = options;
        model.context = result_context;
        model.params = params;
        model.renewable_data = renewable_data;
        model.start_power_per_module_kw = AEL_start_power_per_module;
        results = algorithm(model);
        return
    end

    [sol, fval, exitflag, output] = solve(prob, ...
        'Solver', 'intlinprog', ...
        'Options', options);

    if exitflag <= 0 || isempty(sol.P_AEL)
        error('baseline:no_feasible_solution', ...
            ['Optimization did not return a feasible dispatch. ', ...
            'Exitflag: %d. Solver message: %s'], ...
            exitflag, output.message);
    end

    sol.P_AEL_start = AEL_start_power_per_module * sol.SU_AEL;
    if ael_common.startup
        fprintf('AEL启动耗电：%.3f MWh（计入功率平衡，不额外收费）。\n', ...
            sum(sol.P_AEL_start) * dt / 1000);
    end

    disp(sol);
    disp(['最优年度成本减收益: ', num2str(fval)]);
    disp(['求解状态: ', num2str(exitflag)]);
    disp(output);

    result_context.startup_energy_kwh = sum(sol.P_AEL_start) * dt;

    results = feval('results', params, renewable_data, sol, fval, ...
        exitflag, output, result_context);
end

function opts = set_solver_option(opts, name, value)
%SET_SOLVER_OPTION Replace or append a name/value pair in an optimoptions cell.
idx = find(strcmp(opts, name), 1);
if isempty(idx)
    opts = [opts, {name, value}];
else
    opts{idx + 1} = value;
end
end

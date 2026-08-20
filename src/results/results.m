function result = results(params, renewable_data, sol, fval, exitflag, output, context)
    dt = context.dt;
    T = context.T;
    P_total = context.P_total;
    AEL_spec_energy = context.AEL_spec_energy;
    H2_density = context.H2_density;
    NH3_rate = context.NH3_rate;
    HB_power_kw = context.HB_power_kw;
    C_curt = context.C_curt;
    C_purchase = context.C_purchase;
    C_sell = context.C_sell;
    ael_common = context.ael_common;
    N_AEL_initial = 0;
    if isfield(context, 'N_AEL_initial')
        N_AEL_initial = context.N_AEL_initial;
    end

    P_AEL_opt = sol.P_AEL;
    P_AEL_start_opt = zeros(T, 1);
    if isfield(sol, 'P_AEL_start')
        P_AEL_start_opt = sol.P_AEL_start;
    end
    HB_load_opt = sol.HB_load;
    storage_H2_opt = sol.storage_H2;
    P_purchase_opt = sol.p_purchase;
    P_sell_opt = sol.p_sell;
    P_curt_opt = sol.p_curt;
    u_purchase_opt = sol.u_purchase;
    has_N_AEL = isfield(sol, 'n_ael_optimized') || ...
        isfield(sol, 'n_ael');
    if has_N_AEL
        if isfield(sol, 'n_ael_optimized')
            N_AEL_opt = round(sol.n_ael_optimized);
        else
            N_AEL_opt = round(sol.n_ael);
        end
    end
    %H2_short_opt = sol.h2_short;

    H2_prod_kg_opt = P_AEL_opt * dt / AEL_spec_energy * H2_density;
    NH3_prod_kg_opt = HB_load_opt * NH3_rate * dt;
    H2_use_kg_opt = NH3_prod_kg_opt * params.HB.lit_h2;
    P_HB_kw_opt = HB_load_opt * HB_power_kw;

    if isfield(renewable_data, 'time')
        time_opt = renewable_data.time;
    else
        time_opt = (1:T)';
    end

    result = struct();
    result.fval = fval;
    result.exitflag = exitflag;
    result.output = output;
    result.sol = sol;
    result.time = time_opt;
    optimization_mode = 'single_stage';
    if isfield(sol, 'n_ael_optimized')
        optimization_mode = 'single_stage_with_count_postprocess';
    end
    result.optimization = struct('mode', optimization_mode, ...
        'objective_value', fval);

    result.dispatch = struct();
    result.dispatch.time = time_opt;
    result.dispatch.P_total = P_total;
    result.dispatch.P_AEL = P_AEL_opt;
    result.dispatch.P_AEL_start = P_AEL_start_opt;
    result.dispatch.HB_load = HB_load_opt;
    result.dispatch.storage_H2 = storage_H2_opt;
    result.dispatch.P_purchase = P_purchase_opt;
    result.dispatch.P_sell = P_sell_opt;
    result.dispatch.P_curt = P_curt_opt;
    result.dispatch.u_purchase = u_purchase_opt;
    if has_N_AEL
        result.dispatch.N_AEL = N_AEL_opt;
        if isfield(sol, 'ael_count_info')
            result.dispatch.N_AEL_lower = ...
                sol.ael_count_info.lower_bound;
            result.dispatch.N_AEL_upper = ...
                sol.ael_count_info.upper_bound;
        end
    end
    %result.dispatch.H2_short = H2_short_opt;

    result.dispatch.H2_prod = H2_prod_kg_opt;
    result.dispatch.NH3_prod = NH3_prod_kg_opt;
    result.dispatch.H2_use = H2_use_kg_opt;
    result.dispatch.P_HB = P_HB_kw_opt;

    result.AEL = struct();
    result.AEL.P = P_AEL_opt;
    result.AEL.start_power = P_AEL_start_opt;
    result.AEL.H2_prod = H2_prod_kg_opt;
    if has_N_AEL
        result.AEL.online_modules = N_AEL_opt;
    end

    result.HB = struct();
    result.HB.load = HB_load_opt;
    result.HB.P = P_HB_kw_opt;
    result.HB.NH3_prod = NH3_prod_kg_opt;
    result.HB.H2_use = H2_use_kg_opt;
    [NH3_daily_cumulative_volatility, NH3_daily_volatility] = ...
        calculate_daily_cumulative_volatility(...
            NH3_prod_kg_opt, NH3_rate, dt);
    result.HB.daily_volatility = NH3_daily_volatility;

    result.storage = struct();
    result.storage.H2 = storage_H2_opt;

    result.grid = struct();
    result.grid.purchase = P_purchase_opt;
    result.grid.sell = P_sell_opt;
    result.grid.curtail = P_curt_opt;
    result.grid.u = u_purchase_opt;

    result.shortage = struct();
    %result.shortage.H2 = H2_short_opt;

    result.summary = struct();
    result.summary.purchase_kwh = sum(P_purchase_opt) * dt;
    result.summary.sell_kwh = sum(P_sell_opt) * dt;
    result.summary.curtail_kwh = sum(P_curt_opt) * dt;
    result.summary.renewable_kwh = sum(P_total) * dt;
    result.summary.H2_prod_kg = sum(H2_prod_kg_opt);
    result.summary.H2_use_kg = sum(H2_use_kg_opt);
    %result.summary.H2_short_kg = sum(H2_short_opt);
    result.summary.NH3_prod_kg = sum(NH3_prod_kg_opt);
    result.summary.NH3_prod_t_y = result.summary.NH3_prod_kg / 1000;
    result.summary.NH3_daily_cumulative_volatility = ...
        NH3_daily_cumulative_volatility;
    result.summary.ael_equiv_hours = ...
        sum(P_AEL_opt) * dt / ael_common.max_power;
    result.summary.AEL_start_energy_kwh = ...
        sum(P_AEL_start_opt) * dt;
    if has_N_AEL
        result.summary.AEL_average_online_modules = mean(N_AEL_opt);
        AEL_module_change = diff([N_AEL_initial; N_AEL_opt(:)]);
        result.summary.AEL_startup_count = sum(max(AEL_module_change, 0));
        result.summary.AEL_shutdown_count = sum(max(-AEL_module_change, 0));
    end
    result.summary.HB_average_load = mean(HB_load_opt);
    result.summary.sell_rate = ...
        result.summary.sell_kwh / max(result.summary.renewable_kwh, eps);
    result.summary.curtail_rate = ...
        result.summary.curtail_kwh / max(result.summary.renewable_kwh, eps);
    result.summary.purchase_rate = ...
        result.summary.purchase_kwh / max(result.summary.renewable_kwh, eps);
    result.summary.co2_intensity = ...
        params.environment.grid_co2 * result.summary.purchase_kwh ...
        / max(result.summary.NH3_prod_kg, eps);
    result.cost = struct();
    result.cost.purchase = sum(C_purchase .* P_purchase_opt) * dt;
    result.cost.sell_revenue = sum(C_sell .* P_sell_opt) * dt;
    result.cost.curtail = sum(C_curt .* P_curt_opt) * dt;
    result.cost.water = params.material.water_price * (...
        params.AEL.common.water_use * result.summary.H2_prod_kg / ...
            params.unit.mass_scale + ...
        params.HB.water_use * result.summary.NH3_prod_kg / ...
            params.unit.mass_scale);
    result.cost.catalyst = params.material.cat_price * ...
        result.summary.NH3_prod_kg / params.unit.mass_scale;
    result.cost.raw_material = result.cost.water + result.cost.catalyst;
    result.cost.variable = result.cost.raw_material + ...
        result.cost.purchase + result.cost.curtail;
    %result.cost.H2_short = sum(C_H2_short .* H2_short_opt);

    result.economics = result_LCOA(params, result);
    result.summary.lcoa = result.economics.lcoa;
    result.summary.net_profit = result.economics.net_profit;
    result.cost.annual = result.economics.total_cost;
    result.cost.total = result.economics.total_cost;
    result.cost.objective_value = fval;

    power_residual = P_total + P_purchase_opt ...
        - P_AEL_opt - P_AEL_start_opt - P_HB_kw_opt ...
        - P_sell_opt - P_curt_opt;
    storage_residual = storage_H2_opt(2:end) - storage_H2_opt(1:end-1) ...
        - H2_prod_kg_opt + H2_use_kg_opt;

    result.check = struct();
    result.check.max_power_residual_kw = max(abs(power_residual));
    result.check.max_storage_residual_kg = max(abs(storage_residual));
    result.check.buy_sell_overlap_kwh = sum(P_purchase_opt .* P_sell_opt) * dt;
    if has_N_AEL && isfield(sol, 'ael_count_info')
        result.check.max_AEL_lower_violation = max([0; ...
            sol.ael_count_info.lower_bound(:) - N_AEL_opt(:)]);
        result.check.max_AEL_upper_violation = max([0; ...
            N_AEL_opt(:) - sol.ael_count_info.upper_bound(:)]);
    end

    print_current_results(result.summary);
end

function [DCV, daily_volatility] = calculate_daily_cumulative_volatility(...
        NH3_prod_kg, rated_NH3_kg_h, dt)
    samples_per_day_exact = 24 / dt;
    samples_per_day = round(samples_per_day_exact);
    if abs(samples_per_day - samples_per_day_exact) > 1e-9
        error('results:unsupported_time_step', ...
            'dt must divide 24 hours exactly to calculate daily volatility.');
    end

    NH3_rate_kg_h = NH3_prod_kg(:) / dt;
    day_count = floor(numel(NH3_rate_kg_h) / samples_per_day);
    if day_count == 0
        DCV = NaN;
        daily_volatility = zeros(0, 1);
        return
    end

    complete_sample_count = day_count * samples_per_day;
    daily_NH3_rate = reshape(...
        NH3_rate_kg_h(1:complete_sample_count), samples_per_day, day_count);
    daily_mean = mean(daily_NH3_rate, 1);
    daily_rms = sqrt(mean((daily_NH3_rate - daily_mean).^2, 1));
    daily_volatility = daily_rms(:) / max(rated_NH3_kg_h, eps);
    DCV = mean(daily_volatility);
end

function print_current_results(summary)
    fprintf('\n========== 当前计算结果 ==========\n');
    fprintf('NH3产量：%.3f 万t/a\n', summary.NH3_prod_t_y / 1e4);
    if isfinite(summary.NH3_daily_cumulative_volatility)
        fprintf('制氨日累计波动率：%.2f %%\n', ...
            summary.NH3_daily_cumulative_volatility * 100);
    else
        fprintf('制氨日累计波动率：未计算（调度时长不足24 h）\n');
    end
    fprintf('AEL等效利用小时：%.2f h/a\n', summary.ael_equiv_hours);
    if isfield(summary, 'AEL_startup_count')
        fprintf('AEL启动台次：%.0f 台次/a\n', summary.AEL_startup_count);
    end
    if summary.AEL_start_energy_kwh > 0
        fprintf('AEL启动耗电：%.3f MWh/a\n', ...
            summary.AEL_start_energy_kwh / 1000);
    end
    fprintf('售电率：%.4f %%\n', summary.sell_rate * 100);
    fprintf('弃电率：%.4f %%\n', summary.curtail_rate * 100);
    fprintf('购电率：%.4f %%\n', summary.purchase_rate * 100);
    fprintf('碳排放强度：%.6f kgCO2/kgNH3\n', summary.co2_intensity);
    if summary.NH3_prod_t_y > 0
        fprintf('平准化制氨成本：%.2f $/t\n', summary.lcoa);
    else
        fprintf('平准化制氨成本：未计算\n');
    end
    fprintf('系统年净利润：%.3f M$/a\n', summary.net_profit / 1e6);
end

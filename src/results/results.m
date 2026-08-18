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
        'operating_fval', fval);

    result.dispatch = struct();
    result.dispatch.time = time_opt;
    result.dispatch.P_total = P_total;
    result.dispatch.P_AEL = P_AEL_opt;
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
    result.AEL.H2_prod = H2_prod_kg_opt;
    if has_N_AEL
        result.AEL.online_modules = N_AEL_opt;
    end

    result.HB = struct();
    result.HB.load = HB_load_opt;
    result.HB.P = P_HB_kw_opt;
    result.HB.NH3_prod = NH3_prod_kg_opt;
    result.HB.H2_use = H2_use_kg_opt;

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
    result.summary.ael_equiv_hours = ...
        sum(P_AEL_opt) * dt / ael_common.max_power;
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
    result.cost.raw_material = result.cost.water + ...
        result.cost.catalyst + result.cost.purchase;
    %result.cost.H2_short = sum(C_H2_short .* H2_short_opt);
    result.cost.total = fval;

    result.economics = result_LCOA(params, result);
    result.summary.lcoa = result.economics.lcoa;
    result.summary.net_profit = result.economics.net_profit;
    result.cost.annual = result.economics.total_cost;
    result.zhou_audit = build_zhou_audit(params, result.summary);

    power_residual = P_total + P_purchase_opt ...
        - P_AEL_opt - P_HB_kw_opt - P_sell_opt - P_curt_opt;
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

    fprintf('AEL等效利用小时：%.2f h/a\n', result.summary.ael_equiv_hours);
    if isfield(result.summary, 'AEL_startup_count')
        fprintf('AEL启动台次：%.0f 台次/a\n', result.summary.AEL_startup_count);
    end
    if result.summary.NH3_prod_t_y > 0
        fprintf('平准化制氨成本：%.2f $/t；系统年净利润：%.3f M$/a\n', ...
            result.summary.lcoa, result.summary.net_profit / 1e6);
    else
        fprintf('平准化制氨成本：未计算；系统年净利润：%.3f M$/a\n', ...
            result.summary.net_profit / 1e6);
    end
    print_zhou_audit(result.zhou_audit);
end

function audit = build_zhou_audit(params, summary)
    audit = struct();
    if ~isfield(params, 'ref') || ~isfield(params.ref, 'nh3_output')
        return
    end

    audit.ref_NH3_t_y = params.ref.nh3_output;
    audit.ref_AEL_hours = get_ref(params.ref, 'ael_hours', NaN);
    audit.ref_sell_rate = get_ref(params.ref, 'grid_sell', NaN);
    audit.ref_curtail_rate = get_ref(params.ref, 'curtailment', NaN);
    audit.ref_purchase_rate = get_ref(params.ref, 'grid_buy', NaN);
    audit.ref_co2_intensity = get_ref(params.ref, 'co2_intensity', NaN);
    audit.ref_lcoa = get_ref(params.ref, 'lcoa', NaN);

    audit.NH3_gap_t_y = summary.NH3_prod_t_y - audit.ref_NH3_t_y;
    audit.NH3_gap_percent = ...
        audit.NH3_gap_t_y / max(audit.ref_NH3_t_y, eps) * 100;
    audit.AEL_hours_gap = summary.ael_equiv_hours - audit.ref_AEL_hours;
    audit.sell_rate_gap = summary.sell_rate - audit.ref_sell_rate;
    audit.curtail_rate_gap = summary.curtail_rate - audit.ref_curtail_rate;
    audit.purchase_rate_gap = summary.purchase_rate - audit.ref_purchase_rate;
    audit.co2_intensity_gap = ...
        summary.co2_intensity - audit.ref_co2_intensity;
    if isfield(summary, 'lcoa') && summary.NH3_prod_t_y > 0
        audit.lcoa_gap = summary.lcoa - audit.ref_lcoa;
    else
        audit.lcoa_gap = NaN;
    end

    audit.implied_renewable_kwh = NaN;
    audit.renewable_scale_to_ref = NaN;
    if all(isfield(params.ref, {'ael_hours', 'grid_buy', ...
            'grid_sell', 'curtailment'}))
        ref_ael_kwh = params.ref.ael_hours * params.AEL.common.max_power;
        ref_hb_kwh = params.ref.nh3_output * params.HB.spec_energy * 1000;
        denominator = 1 + params.ref.grid_buy ...
            - params.ref.grid_sell - params.ref.curtailment;
        audit.implied_renewable_kwh = ...
            (ref_ael_kwh + ref_hb_kwh) / denominator;
        audit.renewable_scale_to_ref = ...
            audit.implied_renewable_kwh ...
            / max(summary.renewable_kwh, eps);
    end
end

function value = get_ref(ref, field_name, default_value)
    if isfield(ref, field_name)
        value = ref.(field_name);
    else
        value = default_value;
    end
end

function print_zhou_audit(audit)
    if ~isfield(audit, 'ref_NH3_t_y')
        return
    end

    fprintf('\n========== Zhou S2 对标审计 ==========\n');
    fprintf('NH3产量：%.3f 万t/y；文献：%.3f 万t/y；偏差：%+.2f %%\n', ...
        audit.ref_NH3_t_y / 1e4 + audit.NH3_gap_t_y / 1e4, ...
        audit.ref_NH3_t_y / 1e4, audit.NH3_gap_percent);
    fprintf('AEL等效利用小时偏差：%+.2f h/a\n', ...
        audit.AEL_hours_gap);
    fprintf('售电率偏差：%+.4f %%\n', ...
        audit.sell_rate_gap * 100);
    fprintf('弃电率偏差：%+.4f %%\n', ...
        audit.curtail_rate_gap * 100);
    fprintf('购电率偏差：%+.4f %%\n', ...
        audit.purchase_rate_gap * 100);
    fprintf('碳强度偏差：%+.6f kgCO2/kgNH3\n', ...
        audit.co2_intensity_gap);
    if isfinite(audit.lcoa_gap)
        fprintf('平准化制氨成本偏差：%+.2f $/t\n', audit.lcoa_gap);
    else
        fprintf('平准化制氨成本偏差：未计算\n');
    end
    if isfinite(audit.renewable_scale_to_ref)
        fprintf('按文献KPI反推的年可再生电量：%.3f GWh；当前需乘缩放因子：%.4f\n', ...
            audit.implied_renewable_kwh / 1e6, ...
            audit.renewable_scale_to_ref);
    end
end

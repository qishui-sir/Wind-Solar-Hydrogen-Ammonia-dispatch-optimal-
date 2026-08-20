function economics = result_LCOA(params, result)
%RESULT_LCOA Zhou-style annual economics and LCOA breakdown.

summary = result.summary;
dispatch = result.dispatch;

NH3_t = summary.NH3_prod_t_y;
H2_prod_t = summary.H2_prod_kg / params.unit.mass_scale;
sell_kwh = summary.sell_kwh;

grid_contract_kw = params.grid.contract_kw;
if isempty(grid_contract_kw)
    grid_contract_kw = max(dispatch.P_purchase);
end
fixed = annual_fixed_cost(params, grid_contract_kw);
IN = fixed.IN;
IC = fixed.IC;
OM = fixed.OM;
LC = fixed.LC;
CEC = fixed.CEC;
RM = raw_material_cost(params, summary, H2_prod_t, NH3_t, fixed);
INC = income(params, NH3_t, sell_kwh);

COC = struct();
COC.OM = OM.total;
COC.LC = LC.total;
COC.RM = RM.total;
COC.total = COC.OM + COC.LC + COC.RM;

total_cost = CEC.total + COC.total;
sell_credit = INC.grid_sell;

economics = struct();
economics.INC = INC;
economics.OM = OM;
economics.LC = LC;
economics.RM = RM;
economics.IN = IN;
economics.IC = IC;
economics.CEC = CEC;
economics.COC = COC;
economics.total_cost = total_cost;
economics.net_profit = INC.total - total_cost;
economics.lcoa = (total_cost - sell_credit) / max(NH3_t, eps);
economics.lcoa_from_net_profit = ...
    params.ammonia.price - economics.net_profit / max(NH3_t, eps);
economics.NH3_t = NH3_t;
economics.sell_credit = sell_credit;
economics.capital_factor = fixed.capital_factor;

unit_denominator = max(NH3_t, eps);
economics.unit_cost = struct();
economics.unit_cost.CEC = CEC.total / unit_denominator;
economics.unit_cost.OM = OM.total / unit_denominator;
economics.unit_cost.labor = LC.total / unit_denominator;
economics.unit_cost.water = RM.water / unit_denominator;
economics.unit_cost.catalyst = RM.catalyst / unit_denominator;
economics.unit_cost.grid_purchase = RM.grid_purchase / unit_denominator;
economics.unit_cost.grid_capacity = RM.grid_capacity / unit_denominator;
economics.unit_cost.curtailment = RM.curtailment / unit_denominator;
economics.unit_cost.gross = total_cost / unit_denominator;
economics.unit_cost.sell_credit = sell_credit / unit_denominator;
economics.unit_cost.lcoa = economics.lcoa;

if isfield(params, 'ref') && isfield(params.ref, 'lcoa')
    economics.ref_lcoa = params.ref.lcoa;
    economics.lcoa_gap = economics.lcoa - params.ref.lcoa;
end
if isfield(params, 'ref') && isfield(params.ref, 'net_profit')
    economics.ref_net_profit = params.ref.net_profit;
    economics.net_profit_gap = economics.net_profit - params.ref.net_profit;
end
end

function RM = raw_material_cost(params, summary, H2_prod_t, NH3_t, fixed)
water_t = params.AEL.common.water_use * H2_prod_t ...
    + params.HB.water_use * NH3_t;
curtail_kwh = 0;
if isfield(summary, 'curtail_kwh')
    curtail_kwh = summary.curtail_kwh;
end

RM = struct();
RM.water_t = water_t;
RM.water = params.material.water_price * water_t;
RM.catalyst = params.material.cat_price * NH3_t;
RM.grid_purchase = params.grid.buy_price * summary.purchase_kwh;
RM.grid_contract_kw = fixed.grid_contract_kw;
RM.grid_capacity = fixed.grid_capacity;
RM.curtailment = params.grid.curtail_penalty * curtail_kwh;
RM.total = RM.water + RM.catalyst + RM.grid_purchase ...
    + RM.grid_capacity + RM.curtailment;
end

function INC = income(params, NH3_t, sell_kwh)
INC = struct();
INC.ammonia = params.ammonia.price * NH3_t;
INC.grid_sell = params.grid.sell_price * sell_kwh;
INC.total = INC.ammonia + INC.grid_sell;
end

function economics = result_LCOA(params, result)
%RESULT_LCOA Zhou-style annual economics and LCOA breakdown.

summary = result.summary;
dispatch = result.dispatch;

NH3_t = summary.NH3_prod_t_y;
H2_prod_t = summary.H2_prod_kg / params.unit.mass_scale;
purchase_kwh = summary.purchase_kwh;
sell_kwh = summary.sell_kwh;

devices = build_devices(params);
investment_total = sum([devices.investment]);

discount_crf = params.finance.crf;
loan_crf = capital_recovery_factor( ...
    params.finance.loan_interest, params.finance.loan_term);
loan_ratio = params.finance.loan_ratio;

IN = struct();
IN.by_device = devices;
for idx = 1:numel(IN.by_device)
    IN.by_device(idx).annual = IN.by_device(idx).investment * discount_crf;
end
IN.total = investment_total * discount_crf;

IC = struct();
IC.by_device = devices;
for idx = 1:numel(IC.by_device)
    IC.by_device(idx).annual = IC.by_device(idx).investment * loan_crf;
end
IC.total = investment_total * loan_crf;

OM = struct();
OM.by_device = devices;
for idx = 1:numel(OM.by_device)
    OM.by_device(idx).annual = ...
        OM.by_device(idx).investment * OM.by_device(idx).om_rate;
end
OM.total = sum([OM.by_device.annual]);

LC = labor_cost(params, devices);
RM = raw_material_cost(params, dispatch, summary, H2_prod_t, NH3_t);
INC = income(params, NH3_t, sell_kwh);

CEC = struct();
CEC.equity = (1 - loan_ratio) * IN.total;
CEC.loan = loan_ratio * IC.total;
CEC.total = CEC.equity + CEC.loan;

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
economics.capital_factor = (1 - loan_ratio) * discount_crf ...
    + loan_ratio * loan_crf;

unit_denominator = max(NH3_t, eps);
economics.unit_cost = struct();
economics.unit_cost.CEC = CEC.total / unit_denominator;
economics.unit_cost.OM = OM.total / unit_denominator;
economics.unit_cost.labor = LC.total / unit_denominator;
economics.unit_cost.water = RM.water / unit_denominator;
economics.unit_cost.catalyst = RM.catalyst / unit_denominator;
economics.unit_cost.grid_purchase = RM.grid_purchase / unit_denominator;
economics.unit_cost.grid_capacity = RM.grid_capacity / unit_denominator;
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

function devices = build_devices(params)
devices = repmat(empty_device(), 7, 1);

devices(1) = make_device('PW', params.renewable.PW_capacity, ...
    'kW', params.pw.capex, params.pw.om_rate);
devices(2) = make_device('PV', params.renewable.PV_capacity, ...
    'kW', params.pv.capex, params.pv.om_rate);
devices(3) = make_device('AEL', params.AEL.common.max_power, ...
    'kW', params.AEL.common.capex, params.AEL.common.om_rate);
devices(4) = make_device('H2_storage', params.h2_storage.capacity, ...
    'Nm3', params.h2_storage.capex, params.h2_storage.om_rate);
devices(5) = make_device('converter', params.converter.capacity * 1000, ...
    'kW', params.converter.capex, params.converter.om_rate);
devices(6) = make_device('transformer', ...
    params.transformer.capacity * 1000, 'kW', ...
    params.transformer.capex, params.transformer.om_rate);
devices(7) = make_device('HB', params.HB.capacity, ...
    't/y', params.HB.capex, params.HB.om_rate);
end

function device = empty_device()
device = struct('name', '', 'capacity', 0, 'unit', '', ...
    'capex', 0, 'om_rate', 0, 'investment', 0);
end

function device = make_device(name, capacity, unit_name, capex, om_rate)
device = empty_device();
device.name = name;
device.capacity = capacity;
device.unit = unit_name;
device.capex = capex;
device.om_rate = om_rate;
device.investment = capex * capacity;
end

function value = capital_recovery_factor(rate, years)
if rate == 0
    value = 1 / years;
else
    value = rate * (1 + rate)^years / ((1 + rate)^years - 1);
end
end

function LC = labor_cost(params, devices)
LC = struct();
LC.by_device = repmat(struct('name', '', 'annual', 0), numel(devices), 1);
LC.total = 0;

for idx = 1:numel(devices)
    LC.by_device(idx).name = devices(idx).name;
end

if ~isfield(params, 'labor')
    LC.note = 'Labor coefficients are not specified in current parameters.';
    return
end

salary = get_field(params.labor, 'salary', 0);
fte = get_field(params.labor, 'fte', []);
if ~isempty(fte)
    LC.fte = fte;
    LC.salary = salary;
    LC.total = fte * salary;
    LC.note = get_field(params.labor, 'note', ...
        'Aggregate labor cost from FTE and loaded annual salary.');
    return
end

unit_req = get_field(params.labor, 'unit_req', struct());
for idx = 1:numel(devices)
    name = devices(idx).name;
    requirement = get_field(unit_req, name, 0);
    annual = requirement * devices(idx).capacity * salary;
    LC.by_device(idx).annual = annual;
    LC.total = LC.total + annual;
end
end

function RM = raw_material_cost(params, dispatch, summary, H2_prod_t, NH3_t)
water_t = params.AEL.common.water_use * H2_prod_t ...
    + params.HB.water_use * NH3_t;
grid_contract_kw = get_field(params.grid, 'contract_kw', []);
if isempty(grid_contract_kw)
    grid_contract_kw = max(dispatch.P_purchase);
end

RM = struct();
RM.water_t = water_t;
RM.water = params.material.water_price * water_t;
RM.catalyst = params.material.cat_price * NH3_t;
RM.grid_purchase = params.grid.buy_price * summary.purchase_kwh;
RM.grid_contract_kw = grid_contract_kw;
RM.grid_capacity = params.grid.cap_fee * grid_contract_kw * 12;
RM.total = RM.water + RM.catalyst + RM.grid_purchase ...
    + RM.grid_capacity;
end

function INC = income(params, NH3_t, sell_kwh)
INC = struct();
INC.ammonia = params.ammonia.price * NH3_t;
INC.grid_sell = params.grid.sell_price * sell_kwh;
INC.total = INC.ammonia + INC.grid_sell;
end

function value = get_field(source, field_name, default_value)
if isfield(source, field_name)
    value = source.(field_name);
else
    value = default_value;
end
end

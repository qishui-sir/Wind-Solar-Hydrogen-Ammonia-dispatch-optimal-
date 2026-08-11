function out = qi_ael_model(current_density_a_m2, degradation_voltage_v, par, ...
        stack_temperature_celsius, separator_temperature_celsius)
    if nargin < 3 || isempty(par)
        params_dir = fullfile(fileparts(mfilename('fullpath')), 'params');
        old_path = path;
        path_cleanup = onCleanup(@() path(old_path));
        addpath(params_dir, '-begin');
        par = AEL();
    end
    if nargin < 2 || isempty(degradation_voltage_v)
        degradation_voltage_v = par.degradation_voltage_v;
    end
    if nargin < 4 || isempty(stack_temperature_celsius)
        stack_temperature_celsius = par.stack_temperature_celsius;
    end
    if nargin < 5 || isempty(separator_temperature_celsius)
        separator_temperature_celsius = stack_temperature_celsius;
    end

    average_temperature_celsius = ...
        (stack_temperature_celsius + separator_temperature_celsius) ./ 2;
    average_temperature_kelvin = average_temperature_celsius + 273.15;

    reversible_voltage_v = 1.5184 - 1.5421e-3 .* average_temperature_kelvin + ...
        9.523e-5 .* average_temperature_kelvin .* log(average_temperature_kelvin) + ...
        9.84e-8 .* (average_temperature_kelvin .^ 2);
    area_specific_resistance_ohm_m2 = ...
        par.r1 + par.r2 .* average_temperature_celsius;
    ohmic_voltage_v = area_specific_resistance_ohm_m2 .* current_density_a_m2;
    activation_factor_m2_a = ...
        par.t1 + par.t2 ./ average_temperature_celsius + ...
        par.t3 ./ (average_temperature_celsius .^ 2);
    activation_argument = 1 + activation_factor_m2_a .* current_density_a_m2;
    if any(activation_argument(:) <= 0)
        error('qi_ael_model:bad_activation_argument', ...
            'Qi U-I activation logarithm argument must be positive.');
    end
    activation_voltage_v = par.s .* log(activation_argument);
    cell_voltage_v = reversible_voltage_v + ohmic_voltage_v + ...
        activation_voltage_v + degradation_voltage_v;

    cell_current_a = current_density_a_m2 .* par.cell_area_m2;
    power_w = cell_voltage_v .* cell_current_a .* par.cell_count;
    electrolysis_heat_w = ...
        (cell_voltage_v - par.thermal_neutral_voltage_v) .* ...
        cell_current_a .* par.cell_count;
    hydrogen_energy_w = par.thermal_neutral_voltage_v .* ...
        cell_current_a .* par.cell_count;
    h2_mol_s = par.faraday_efficiency .* par.cell_count .* ...
        cell_current_a ./ (2 .* par.faraday_constant_c_mol);
    h2_kg_h = h2_mol_s .* par.h2_molar_mass_kg_mol .* 3600;
    h2_nm3_h = h2_kg_h ./ 0.08988;

    out.current_density_a_m2 = current_density_a_m2;
    out.cell_current_a = cell_current_a;
    out.degradation_voltage_v = degradation_voltage_v;
    out.stack_temperature_celsius = stack_temperature_celsius;
    out.separator_temperature_celsius = separator_temperature_celsius;
    out.average_temperature_celsius = average_temperature_celsius;
    out.average_temperature_kelvin = average_temperature_kelvin;
    out.reversible_voltage_v = reversible_voltage_v;
    out.area_specific_resistance_ohm_m2 = area_specific_resistance_ohm_m2;
    out.ohmic_voltage_v = ohmic_voltage_v;
    out.activation_factor_m2_a = activation_factor_m2_a;
    out.activation_voltage_v = activation_voltage_v;
    out.cell_voltage_v = cell_voltage_v;
    out.power_w = power_w;
    out.power_mw = power_w ./ 1e6;
    out.electrolysis_heat_w = electrolysis_heat_w;
    out.heat_power_mw = electrolysis_heat_w ./ 1e6;
    out.hydrogen_energy_w = hydrogen_energy_w;
    out.hydrogen_power_mw = hydrogen_energy_w ./ 1e6;
    out.h2_mol_s = h2_mol_s;
    out.h2_kg_h = h2_kg_h;
    out.h2_nm3_h = h2_nm3_h;
    out.efficiency_hhv = hydrogen_energy_w ./ power_w;

    out.U_deg = degradation_voltage_v;
    out.rev = reversible_voltage_v;
    out.ohm = ohmic_voltage_v;
    out.U_act = activation_voltage_v;
    out.U_cell = cell_voltage_v;
    out.P_AEL = out.power_mw;
    out.n_H2 = h2_mol_s;
end

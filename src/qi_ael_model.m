function out = qi_ael_model(cur_density, deg_voltage, par, stack_temp, sep_temp)
    if nargin < 3 || isempty(par)
        params_dir = fullfile(fileparts(mfilename('fullpath')), 'params');
        old_path = path;
        path_cleanup = onCleanup(@() path(old_path));
        addpath(params_dir, '-begin');
        par = AEL();
    end
    if nargin < 2 || isempty(deg_voltage)
        deg_voltage = par.deg_voltage;
    end
    if nargin < 4 || isempty(stack_temp)
        stack_temp = par.stack_temp;
    end
    if nargin < 5 || isempty(sep_temp)
        sep_temp = stack_temp;
    end

    avg_temp = (stack_temp + sep_temp) ./ 2; % degC
    rev_temp = avg_temp + 273.15; % K

    rev_voltage = 1.5184 - 1.5421e-3 .* rev_temp + ...
        9.523e-5 .* rev_temp .* log(rev_temp) + ...
        9.84e-8 .* (rev_temp .^ 2);
    are_resistance = par.r1 + par.r2 .* avg_temp; % ohm m2
    ohm_voltage = are_resistance .* cur_density;
    act_factor = par.t1 + par.t2 ./ avg_temp + ...
        par.t3 ./ (avg_temp .^ 2); % m2/A
    act_argument = 1 + act_factor .* cur_density;
    if any(act_argument(:) <= 0)
        error('qi_ael_model:bad_activation_argument', ...
            'Qi U-I activation logarithm argument must be positive.');
    end
    act_voltage = par.s .* log(act_argument);
    cel_voltage = rev_voltage + ohm_voltage + act_voltage + deg_voltage;

    cell_current = cur_density .* par.cell_area; % A
    power_w = cel_voltage .* cell_current .* par.cell_num;
    hea_power_w = (cel_voltage - par.tn_voltage) .* ...
        cell_current .* par.cell_num;
    hyd_power_w = par.tn_voltage .* cell_current .* par.cell_num;
    h2_mol_flow = par.far_eff .* par.cell_num .* ...
        cell_current ./ (2 .* par.far_const); % mol/s
    h2_mass_flow = h2_mol_flow .* par.h2_molar_mass .* 3600; % kg/h
    h2_flow = h2_mass_flow ./ 0.08988; % Nm3/h

    out.cur_density = cur_density; % A/m2
    out.cell_current = cell_current; % A
    out.deg_voltage = deg_voltage; % V
    out.stack_temp = stack_temp; % degC
    out.sep_temp = sep_temp; % degC
    out.avg_temp = avg_temp; % degC
    out.rev_temp = rev_temp; % K
    out.rev_voltage = rev_voltage; % V
    out.are_resistance = are_resistance; % ohm m2
    out.ohm_voltage = ohm_voltage; % V
    out.act_factor = act_factor; % m2/A
    out.act_voltage = act_voltage; % V
    out.cel_voltage = cel_voltage; % V
    out.power = power_w ./ 1e6; % MW
    out.hea_power = hea_power_w ./ 1e6; % MW
    out.hyd_power = hyd_power_w ./ 1e6; % MW
    out.h2_mol_flow = h2_mol_flow; % mol/s
    out.h2_mass_flow = h2_mass_flow; % kg/h
    out.h2_flow = h2_flow; % Nm3/h
    out.hhv_efficiency = hyd_power_w ./ power_w; % fraction
end

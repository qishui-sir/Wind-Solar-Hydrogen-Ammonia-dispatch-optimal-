function out = qi_ael_model(j0,U_deg,par)
    if nargin < 3 || isempty(par)
        par = params();
    end
    if nargin < 2 || isempty(U_deg)
        U_deg = 0.0;
    end

    % Calculate U_cell
    U_rev = 1.5184 - 1.5421e-3.*par.T_K + ...
        9.523e-5.*par.T_K.*log(par.T_K) + ...
        9.84e-8.*(par.T_K.^2);
    R_ASR = par.r1 + par.r2.*par.T_C;
    U_ohm = R_ASR .* j0;
    beta = par.t1 + par.t2./par.T_C + par.t3./(par.T_C .^ 2);
    log_argument = 1 + beta.*j0;
    U_act_total = par.s .* log(log_argument);
    U_cell = U_rev + U_ohm + U_act_total + U_deg;
    
    % Calculate P_AEL
    I_cell = j0 .* par.A_m2;
    P_AEL = par.N_cell .* I_cell .* U_cell ./ 1e6;  % P_AEL unit: MW

    % Calculate H2 storage
    n_H2 = par.eta_F .* par.N_cell .* I_cell ./(2*par.F);

    % Output
    out.U_deg = U_deg;
    out.rev = U_rev;
    out.ohm = U_ohm;
    out.U_act = U_act_total;
    out.U_cell = U_cell;
    out.P_AEL = P_AEL;
    out.n_H2 = n_H2;
end
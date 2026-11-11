function [dV_hill, should_maneuver, final_pc, info] = ...
        compute_deterministic_oracle(scenario, c, search_config)
%COMPUTE_DETERMINISTIC_ORACLE Create a reproducible nonlinear training label.
%
% The oracle delegates to the same six-direction J2 search used during
% validation. This keeps labels and reported validation maneuvers subject to
% one actuator limit, one Earth-intersection policy, and one evaluator.

    hbr_m = c.HBR;
    if isfield(scenario, 'hbr_m')
        hbr_m = scenario.hbr_m;
    elseif isfield(scenario, 'HBR')
        hbr_m = scenario.HBR;
    end

    if nargin < 3 || isempty(search_config)
        search_config = maneuver_search_config();
    end
    c_local = c;
    c_local.HBR = hbr_m;
    [dV_eci, search_info] = find_minimum_safe_maneuver( ...
        scenario.X0_sat, scenario, c_local, scenario.t_to_cpa, ...
        scenario.rel_pos, scenario.rel_vel, scenario.X_cpa_sat, ...
        scenario.C_sat, scenario.C_deb, scenario.X0_deb, search_config);

    R_burn = hill_to_eci(scenario.X0_sat);
    dV_hill = R_burn' * dV_eci;
    should_maneuver = strcmp(search_info.status, 'success');
    final_pc = search_info.achieved_pc;

    if strcmp(search_info.status, 'success')
        exitflag = 1;
    elseif strcmp(search_info.status, 'stay')
        exitflag = 0;
    else
        exitflag = -1;
    end
    info = struct( ...
        'status', search_info.status, ...
        'exitflag', exitflag, ...
        'decision_threshold_pc', search_info.decision_threshold_pc, ...
        'target_pc', search_info.target_pc, ...
        'initial_pc', search_info.initial_pc, ...
        'candidate_pc', search_info.achieved_pc, ...
        'candidate_cost', NaN, ...
        'baseline_cost', NaN, ...
        'safety_constraint_satisfied', ...
            search_info.safety_constraint_satisfied, ...
        'optimizer_fidelity', search_info.evaluation_fidelity, ...
        'evaluation_fidelity', search_info.evaluation_fidelity, ...
        ... % Search cost, carried through for profiling. Diagnostic only.
        'optimizer_evaluations', search_info.optimizer_evaluations, ...
        'search_info', search_info);
end

function R_h2e = hill_to_eci(X)
    r_hat = X(1:3) / norm(X(1:3));
    h_hat = cross(X(1:3), X(4:6));
    if norm(h_hat) <= eps
        error('ACAM:InvalidHillFrame', 'Burn state has zero angular momentum.');
    end
    h_hat = h_hat / norm(h_hat);
    t_hat = cross(h_hat, r_hat);
    R_h2e = [r_hat, t_hat, h_hat];
end

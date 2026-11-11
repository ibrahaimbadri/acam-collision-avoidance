function [dV_hill, should_maneuver, final_pc, info] = ...
        compute_cdm_oracle(message, c, search_config)
%COMPUTE_CDM_ORACLE Minimum-safe maneuver from decision-time CDM information.
%
% COMPUTE_DETERMINISTIC_ORACLE reads simulator truth states and the scenario
% proposal covariance. A model trained against that label is asked to predict
% a decision made from information it structurally cannot observe, which is a
% state-estimation problem, not surrogate approximation.
%
% This oracle sees only the decision-epoch CDM, so features and label are
% drawn from the same information set. That is the label contract required by
% the declared project claim: a surrogate that approximates the numerical
% optimizer faster than running it online. Truth remains the separate,
% audit-only standard for judging whether the chosen maneuver was actually
% safe; it is never a model input.
%
% The returned Delta-V is in the target Hill frame at the message epoch,
% which is where the burn is executed and which matches schema-v3 slots 5-10
% as produced by BUILD_FEATURES_FROM_CDM.

    if nargin < 3 || isempty(search_config)
        search_config = maneuver_search_config();
    end
    decision_pc = required_probability(message.collision_probability, ...
        'collision_probability');
    if isfield(search_config, 'decision_pc_override')
        trigger_pc = required_probability(search_config.decision_pc_override, ...
            'search_config.decision_pc_override');
        search_config.decision_pc_override = trigger_pc;
        if ~isfield(search_config, 'decision_trigger_source')
            search_config.decision_trigger_source = ...
                'caller-supplied decision Pc override';
        end
    else
        trigger_pc = decision_pc;
        search_config.decision_pc_override = trigger_pc;
        search_config.decision_trigger_source = 'published decision CDM Pc';
    end
    hbr_m = required_scalar(message.hbr_m, 'hbr_m');
    X_sat_burn = required_state(message.target_state_eci_at_message, ...
                                'target_state_eci_at_message');
    X_deb_burn = required_state(message.chaser_state_eci_at_message, ...
                                'chaser_state_eci_at_message');
    X_sat_tca = required_state(message.target_state_eci_tca, ...
                               'target_state_eci_tca');
    X_deb_tca = required_state(message.chaser_state_eci_tca, ...
                               'chaser_state_eci_tca');
    time_to_tca_s = required_scalar(message.time_to_tca_s, 'time_to_tca_s');

    % The CDM stores covariance in RTN at TCA; the evaluator works in ECI.
    % Prefer the published combined relative covariance so a joint filter's
    % target-debris cross-covariance is not silently discarded.
    R_tca = hill_to_eci(X_sat_tca);
    [C_sat_rtn, C_deb_rtn, combined_rtn, covariance_source] = ...
        covariance_components(message);
    C_sat = symmetrize(R_tca * C_sat_rtn * R_tca');
    C_deb = symmetrize(R_tca * C_deb_rtn * R_tca');

    cdm_scenario = struct( ...
        'X0_sat', X_sat_burn, ...
        'X0_deb', X_deb_burn, ...
        'X_cpa_sat', X_sat_tca, ...
        'X_cpa_deb', X_deb_tca, ...
        'rel_pos', X_sat_tca(1:3) - X_deb_tca(1:3), ...
        'rel_vel', X_sat_tca(4:6) - X_deb_tca(4:6), ...
        't_to_cpa', time_to_tca_s, ...
        'C_sat', C_sat, ...
        'C_deb', C_deb, ...
        'hbr_m', hbr_m, ...
        'HBR', hbr_m, ...
        'mass', message.spacecraft_mass_kg);

    % Delegate to the one canonical search so both oracles share an actuator
    % limit, an Earth-intersection policy, and an evaluator.
    [dV_hill, should_maneuver, final_pc, info] = ...
        compute_deterministic_oracle(cdm_scenario, c, search_config);
    info.label_information_set = 'decision-epoch CDM';
    info.label_message_id = message.message_id;
    info.label_frame = 'target Hill frame at message epoch';
    info.label_covariance_source = covariance_source;
    info.label_combined_covariance_identity_error = norm( ...
        C_sat_rtn + C_deb_rtn - combined_rtn, 'fro');
    info.label_decision_pc = decision_pc;
    info.label_trigger_pc = trigger_pc;
end

function [C_sat, C_deb, combined, source] = covariance_components(message)
    combined = message.combined_position_covariance_rtn_m2;
    if isequal(size(combined), [3, 3]) && all(isfinite(combined), 'all')
        combined = required_covariance(combined, ...
            'combined_position_covariance_rtn_m2');
        C_sat = combined / 2;
        C_deb = combined / 2;
        source = 'published combined relative covariance';
        return;
    end
    C_sat = required_covariance(message.target_position_covariance_rtn_m2, ...
        'target_position_covariance_rtn_m2');
    C_deb = required_covariance(message.chaser_position_covariance_rtn_m2, ...
        'chaser_position_covariance_rtn_m2');
    combined = C_sat + C_deb;
    source = 'sum of independent marginal covariances';
end

function value = required_scalar(value, name)
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('ACAM:IncompleteCdmForOracle', ...
              '%s must be a finite positive scalar.', name);
    end
end

function value = required_probability(value, name)
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value > 1
        error('ACAM:IncompleteCdmForOracle', ...
              '%s must be a finite probability in [0, 1].', name);
    end
end

function value = required_state(value, name)
    value = value(:);
    if numel(value) ~= 6 || any(~isfinite(value))
        error('ACAM:IncompleteCdmForOracle', ...
              '%s must be a finite six-element state.', name);
    end
end

function value = required_covariance(value, name)
    if ~isequal(size(value), [3, 3]) || any(~isfinite(value), 'all')
        error('ACAM:IncompleteCdmForOracle', ...
              '%s must be a finite 3x3 matrix.', name);
    end
end

function M = symmetrize(M)
    M = (M + M') / 2;
end

function R_h2e = hill_to_eci(X)
    r_hat = X(1:3) / norm(X(1:3));
    h_hat = cross(X(1:3), X(4:6));
    if norm(h_hat) <= eps
        error('ACAM:InvalidHillFrame', ...
              'CDM target state has zero angular momentum.');
    end
    h_hat = h_hat / norm(h_hat);
    t_hat = cross(h_hat, r_hat);
    R_h2e = [r_hat, t_hat, h_hat];
end

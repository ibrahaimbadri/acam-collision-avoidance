function [message, diagnostics, tca_state] = generate_cdm_from_estimate( ...
        estimate, platform, c, nominal_lead_s, tracking_config, message_id)
%GENERATE_CDM_FROM_ESTIMATE Run conjunction assessment on one EKF posterior.
%
% The third output is an audit sidecar carrying the authoritative full 6x6
% state covariances at the predicted TCA, from this function's own
% propagation. The CDM schema is unchanged and still publishes only the 3x3
% position block; a consumer that needs velocity or cross-covariance terms
% must take them from here rather than recomputing, because reproducing the
% published Pc validates the position block alone and cannot detect a wrong
% velocity or cross-covariance block.

    required = {'X_sat', 'X_deb', 'P_sat', 'P_deb'};
    for i = 1:numel(required)
        if ~isfield(estimate, required{i})
            error('ACAM:InvalidCdmEstimate', ...
                  'Missing estimate.%s.', required{i});
        end
    end
    validateattributes(nominal_lead_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, ...
        mfilename, 'nominal_lead_s');
    search_half_width_s = min(3600, 0.25 * nominal_lead_s);
    search_interval = [max(60, nominal_lead_s - search_half_width_s), ...
                       nominal_lead_s + search_half_width_s];
    [predicted_tca_s, ~, ~, ~, residual, tca_diagnostics] = find_tca( ...
        estimate.X_sat, estimate.X_deb, search_interval, c, nominal_lead_s);
    [X_sat_tca, P_sat_tca, sat_propagation] = ...
        propagate_state_covariance(estimate.X_sat, estimate.P_sat, ...
                                   predicted_tca_s, c, tracking_config);
    [X_deb_tca, P_deb_tca, deb_propagation] = ...
        propagate_state_covariance(estimate.X_deb, estimate.P_deb, ...
                                   predicted_tca_s, c, tracking_config);
    R = hill_to_eci(X_sat_tca);
    rel_pos = X_sat_tca(1:3) - X_deb_tca(1:3);
    rel_vel = X_sat_tca(4:6) - X_deb_tca(4:6);
    target_covariance = R' * P_sat_tca(1:3, 1:3) * R;
    chaser_covariance = R' * P_deb_tca(1:3, 1:3) * R;
    [~, template] = cdm_sequence_contract();
    message = template;
    message.message_id = char(message_id);
    message.event_id = char(platform.event_id);
    message.source = 'synthetic_linked_ekf';
    message.time_to_tca_s = predicted_tca_s;
    message.collision_probability = calculatePoC( ...
        rel_pos, rel_vel, P_sat_tca(1:3, 1:3), ...
        P_deb_tca(1:3, 1:3), platform.hbr_m);
    message.miss_distance_m = norm(rel_pos);
    message.relative_speed_mps = norm(rel_vel);
    message.relative_position_rtn_m = R' * rel_pos;
    message.relative_velocity_rtn_mps = R' * rel_vel;
    message.target_position_covariance_rtn_m2 = target_covariance;
    message.chaser_position_covariance_rtn_m2 = chaser_covariance;
    message.combined_position_covariance_rtn_m2 = ...
        target_covariance + chaser_covariance;
    message.target_state_eci_tca = X_sat_tca;
    message.chaser_state_eci_tca = X_deb_tca;
    message.target_state_eci_at_message = estimate.X_sat(:);
    message.chaser_state_eci_at_message = estimate.X_deb(:);
    message.altitude_m = norm(X_sat_tca(1:3)) - c.Re;
    message.spacecraft_mass_kg = platform.spacecraft_mass_kg;
    message.hbr_m = platform.hbr_m;
    diagnostics = struct( ...
        'message_id', char(message_id), ...
        'nominal_lead_s', nominal_lead_s, ...
        'predicted_tca_s', predicted_tca_s, ...
        'predicted_tca_offset_s', predicted_tca_s - nominal_lead_s, ...
        'orthogonality_residual', residual, ...
        'tca_search', tca_diagnostics, ...
        'sat_covariance_propagation', sat_propagation, ...
        'deb_covariance_propagation', deb_propagation);
    tca_state = struct( ...
        'predicted_tca_s', predicted_tca_s, ...
        'predicted_tca_offset_s', predicted_tca_s - nominal_lead_s, ...
        'X_sat_tca', X_sat_tca, 'X_deb_tca', X_deb_tca, ...
        'P_sat_tca', P_sat_tca, 'P_deb_tca', P_deb_tca, ...
        'hill_to_eci', R, 'hbr_m', platform.hbr_m);
end

function R_h2e = hill_to_eci(X)
    r_hat = X(1:3) / norm(X(1:3));
    h_hat = cross(X(1:3), X(4:6));
    if norm(h_hat) <= eps
        error('ACAM:InvalidHillFrame', ...
              'Estimated target state has zero angular momentum.');
    end
    h_hat = h_hat / norm(h_hat);
    t_hat = cross(h_hat, r_hat);
    R_h2e = [r_hat, t_hat, h_hat];
end

function [message, diagnostics, tca_state] = generate_joint_drag_cdm( ...
        estimate, platform, c, nominal_lead_s, config, message_id)
%GENERATE_JOINT_DRAG_CDM Publish a CDM using full relative covariance.

    half_width = min(3600, 0.25 * nominal_lead_s);
    interval = [max(60, nominal_lead_s - half_width), ...
                nominal_lead_s + half_width];
    [predicted_tca_s, ~, search] = find_joint_drag_tca( ...
        estimate.state, interval, c, config);
    [state, covariance, propagation] = propagate_joint_drag_covariance( ...
        estimate.state, estimate.covariance, predicted_tca_s, c, config);
    X_target = state(1:6);
    X_debris = state(7:12);
    rel_pos = X_target(1:3) - X_debris(1:3);
    rel_vel = X_target(4:6) - X_debris(4:6);
    H_relative = [eye(6), -eye(6), ...
        zeros(6, config.state_dimension - 12)];
    relative_covariance = H_relative * covariance * H_relative';
    relative_covariance = (relative_covariance + relative_covariance') / 2;
    R = hill_to_eci(X_target);
    target_covariance = covariance(1:3, 1:3);
    debris_covariance = covariance(7:9, 7:9);
    cross_covariance = covariance(1:3, 7:9);
    combined_position = relative_covariance(1:3, 1:3);
    [~, template] = cdm_sequence_contract();
    message = template;
    message.message_id = char(message_id);
    message.event_id = char(platform.event_id);
    message.source = 'synthetic_joint_drag_ekf';
    message.time_to_tca_s = predicted_tca_s;
    message.collision_probability = calculate_poc_from_combined_covariance( ...
        rel_pos, rel_vel, combined_position, platform.hbr_m);
    message.miss_distance_m = norm(rel_pos);
    message.relative_speed_mps = norm(rel_vel);
    message.relative_position_rtn_m = R' * rel_pos;
    message.relative_velocity_rtn_mps = R' * rel_vel;
    message.target_position_covariance_rtn_m2 = R' * target_covariance * R;
    message.chaser_position_covariance_rtn_m2 = R' * debris_covariance * R;
    message.combined_position_covariance_rtn_m2 = R' * combined_position * R;
    message.target_state_eci_tca = X_target;
    message.chaser_state_eci_tca = X_debris;
    message.target_state_eci_at_message = estimate.state(1:6);
    message.chaser_state_eci_at_message = estimate.state(7:12);
    message.altitude_m = norm(X_target(1:3)) - c.Re;
    message.spacecraft_mass_kg = platform.spacecraft_mass_kg;
    message.hbr_m = platform.hbr_m;
    diagnostics = struct('predicted_tca_s', predicted_tca_s, ...
        'predicted_tca_offset_s', predicted_tca_s - nominal_lead_s, ...
        'search', search, 'propagation', propagation, ...
        'cross_covariance_position_fro', norm(cross_covariance, 'fro'), ...
        'relative_covariance_identity_error', norm(combined_position - ...
            (target_covariance + debris_covariance - cross_covariance - ...
             cross_covariance'), 'fro'));
    tca_state = struct('predicted_tca_s', predicted_tca_s, ...
        'predicted_tca_offset_s', predicted_tca_s - nominal_lead_s, ...
        'state', state, 'covariance', covariance, ...
        'X_sat_tca', X_target, 'X_deb_tca', X_debris, ...
        'relative_covariance_6', relative_covariance, ...
        'combined_position_covariance_eci', combined_position, ...
        'target_debris_cross_covariance_eci', cross_covariance, ...
        'hill_to_eci', R, 'hbr_m', platform.hbr_m);
end

function R = hill_to_eci(X)
    radial = X(1:3) / norm(X(1:3));
    normal = cross(X(1:3), X(4:6));
    normal = normal / norm(normal);
    R = [radial, cross(normal, radial), normal];
end

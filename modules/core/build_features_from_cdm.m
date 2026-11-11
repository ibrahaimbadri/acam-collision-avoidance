function [features, message, history, message_index] = ...
        build_features_from_cdm(sequence, decision_lead_s, platform)
%BUILD_FEATURES_FROM_CDM Build schema-v3 input without scenario truth.
%
% The CDM keeps the standard RTN-at-TCA convention, but schema-v3 slots 5-10
% are expressed in the target Hill frame at the *decision epoch*, matching
% BUILD_FEATURES and matching the frame the Delta-V label is issued in. The
% two frames differ by the orbital phase travelled between the message and
% TCA, so mixing them silently trains and infers in different rotating
% frames. Messages without the estimated ECI states cannot be rotated and
% are rejected rather than passed through in the wrong frame.

    if nargin < 3 || isempty(platform)
        platform = struct();
    end
    [message, history, message_index] = ...
        select_cdm_message(sequence, decision_lead_s);
    pc = required_probability(message.collision_probability, ...
                              'collision_probability');
    rel_pos = required_vector(message.relative_position_rtn_m, ...
                              'relative_position_rtn_m');
    rel_vel = required_vector(message.relative_velocity_rtn_mps, ...
                              'relative_velocity_rtn_mps');
    covariance = message.combined_position_covariance_rtn_m2;
    if any(~isfinite(covariance), 'all')
        error('ACAM:IncompleteCdmForFeatures', ...
              'Combined RTN position covariance is required.');
    end
    R_tca = hill_to_eci(required_vector6( ...
        message.target_state_eci_tca, 'target_state_eci_tca'));
    R_decision = hill_to_eci(required_vector6( ...
        message.target_state_eci_at_message, 'target_state_eci_at_message'));
    rel_pos = R_decision' * (R_tca * rel_pos);
    rel_vel = R_decision' * (R_tca * rel_vel);
    altitude = value_or_platform(message.altitude_m, platform, 'altitude_m');
    mass = value_or_platform(message.spacecraft_mass_kg, platform, ...
                             'spacecraft_mass_kg');
    hbr = value_or_platform(message.hbr_m, platform, 'hbr_m');
    required = [message.miss_distance_m, message.relative_speed_mps, ...
                altitude, mass, hbr];
    if any(~isfinite(required)) || any(required([1, 2, 4, 5]) <= 0)
        error('ACAM:IncompleteCdmForFeatures', ...
              'CDM geometry and declared platform metadata must be finite.');
    end
    features = [ ...
        pc; ...
        message.time_to_tca_s; ...
        message.miss_distance_m; ...
        message.relative_speed_mps; ...
        rel_pos; ...
        rel_vel; ...
        altitude; ...
        trace(covariance); ...  % rotation invariant, so no frame change needed
        mass; ...
        hbr];
end

function value = required_vector6(value, name)
    value = value(:);
    if numel(value) ~= 6 || any(~isfinite(value))
        error('ACAM:IncompleteCdmForFeatures', ...
              ['%s is required to express relative geometry in the ', ...
               'decision-epoch Hill frame.'], name);
    end
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

function value = value_or_platform(value, platform, name)
    if ~isfinite(value) && isfield(platform, name)
        value = platform.(name);
    end
end

function value = required_probability(value, name)
    if ~isfinite(value) || value < 0 || value > 1
        error('ACAM:IncompleteCdmForFeatures', '%s is required.', name);
    end
end

function value = required_vector(value, name)
    value = value(:);
    if numel(value) ~= 3 || any(~isfinite(value))
        error('ACAM:IncompleteCdmForFeatures', '%s is required.', name);
    end
end

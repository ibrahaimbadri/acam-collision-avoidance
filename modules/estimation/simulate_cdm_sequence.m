function [sequence, audit] = simulate_cdm_sequence(scenario, c, ...
                                                   lead_times_s, seed, config)
%SIMULATE_CDM_SEQUENCE Generate model-facing CDMs and separate truth audit.

    if nargin < 5 || isempty(config)
        config = cdm_observation_config();
    end
    validateattributes(lead_times_s, {'numeric'}, ...
        {'real', 'finite', 'vector', 'positive'}, ...
        mfilename, 'lead_times_s');
    lead_times_s = sort(lead_times_s(:), 'descend');
    [~, template] = cdm_sequence_contract();
    messages = repmat(template, numel(lead_times_s), 1);
    audit_messages = cell(numel(lead_times_s), 1);
    event_id = sprintf('synthetic-%d', scenario.scenario_seed);
    for i = 1:numel(lead_times_s)
        observation = simulate_cdm_observation( ...
            scenario, c, lead_times_s(i), seed, config);
        estimate = observation.estimate;
        R = hill_to_eci(estimate.X_sat_tca);
        rel_pos = estimate.X_sat_tca(1:3) - estimate.X_deb_tca(1:3);
        rel_vel = estimate.X_sat_tca(4:6) - estimate.X_deb_tca(4:6);
        target_covariance = R' * estimate.C_sat_tca * R;
        chaser_covariance = R' * estimate.C_deb_tca * R;
        message_id = sprintf('%s-%ds', event_id, round(lead_times_s(i)));
        messages(i).message_id = message_id;
        messages(i).event_id = event_id;
        messages(i).source = 'synthetic';
        messages(i).time_to_tca_s = lead_times_s(i);
        messages(i).collision_probability = calculatePoC( ...
            rel_pos, rel_vel, estimate.C_sat_tca, estimate.C_deb_tca, ...
            scenario.hbr_m);
        messages(i).miss_distance_m = norm(rel_pos);
        messages(i).relative_speed_mps = norm(rel_vel);
        messages(i).relative_position_rtn_m = R' * rel_pos;
        messages(i).relative_velocity_rtn_mps = R' * rel_vel;
        messages(i).target_position_covariance_rtn_m2 = target_covariance;
        messages(i).chaser_position_covariance_rtn_m2 = chaser_covariance;
        messages(i).combined_position_covariance_rtn_m2 = ...
            target_covariance + chaser_covariance;
        messages(i).target_state_eci_tca = estimate.X_sat_tca(:);
        messages(i).chaser_state_eci_tca = estimate.X_deb_tca(:);
        messages(i).target_state_eci_at_message = estimate.X_sat(:);
        messages(i).chaser_state_eci_at_message = estimate.X_deb(:);
        messages(i).altitude_m = norm(estimate.X_sat_tca(1:3)) - c.Re;
        messages(i).spacecraft_mass_kg = scenario.mass;
        messages(i).hbr_m = scenario.hbr_m;
        audit_messages{i} = struct( ...
            'message_id', message_id, ...
            'diagnostics', observation.diagnostics);
    end
    raw = struct( ...
        'event_id', event_id, ...
        'source', 'synthetic', ...
        'messages', messages, ...
        'metadata', struct( ...
            'relative_state_convention', 'target minus chaser', ...
            'risk_scale', 'probability', ...
            'maneuver_validation_supported', true, ...
            'notes', ['Synthetic pre-external-calibration CDMs; ', ...
                      'not operational measurement evidence.']));
    sequence = parse_cdm_sequence(raw);
    audit = struct( ...
        'event_id', event_id, ...
        'truth_collision_probability', scenario.Pc_initial, ...
        'messages', {audit_messages});
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

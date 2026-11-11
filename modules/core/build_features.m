function [features, X_sat_cpa, X_deb_cpa, C_sat, C_deb] = ...
        build_features(scenario, c, estimate, feature_overrides)
%BUILD_FEATURES Construct the current canonical feature vector.
%
% With no estimate argument, this preserves the perfect-knowledge feature
% path. With an estimate struct, it uses both independent posterior
% covariances. estimate.X_sat, estimate.X_deb, and estimate.remaining_time
% are required. Either posterior P_sat/P_deb or supplied TCA C_sat_tca/
% C_deb_tca must also be present. CDM-style inputs may supply X_sat_tca and
% X_deb_tca directly. The output
% follows feature schema 3. Signed relative geometry is expressed in the
% satellite Hill frame at the decision epoch so the model can infer burn
% direction; scalar miss distance and speed alone lose that information.
% The optional feature_overrides argument preserves already-computed
% J2/CW Pc and miss-distance values in the current training generator.

    if nargin < 4 || isempty(feature_overrides)
        feature_overrides = struct();
    end

    has_estimate = nargin >= 3 && ~isempty(estimate);
    X_sat_cpa = [];
    X_deb_cpa = [];
    altitude_m = scenario.altitude;

    if has_estimate
        required = {'X_sat', 'X_deb', 'remaining_time'};
        for k = 1:numel(required)
            if ~isfield(estimate, required{k})
                error('ACAM:InvalidFeatureEstimate', ...
                      'Missing estimate.%s.', required{k});
            end
        end
        validateattributes(estimate.remaining_time, {'numeric'}, ...
            {'real', 'finite', 'scalar', 'nonnegative'}, ...
            mfilename, 'estimate.remaining_time');
        posterior_covariance = ...
            isfield(estimate, 'P_sat') || isfield(estimate, 'P_deb');
        if posterior_covariance && ...
                ~(isfield(estimate, 'P_sat') && isfield(estimate, 'P_deb'))
            error('ACAM:InvalidFeatureEstimate', ...
                  'Both estimate.P_sat and estimate.P_deb are required.');
        end
        supplied_tca_covariance = ...
            isfield(estimate, 'C_sat_tca') || isfield(estimate, 'C_deb_tca');
        if supplied_tca_covariance && ...
                ~(isfield(estimate, 'C_sat_tca') && ...
                  isfield(estimate, 'C_deb_tca'))
            error('ACAM:InvalidFeatureEstimate', ...
                  'Both estimate.C_sat_tca and estimate.C_deb_tca are required.');
        end
        if ~posterior_covariance && ~supplied_tca_covariance
            error('ACAM:InvalidFeatureEstimate', ...
                  'Posterior or supplied TCA covariance is required.');
        end
        direct_tca_state = ...
            isfield(estimate, 'X_sat_tca') || isfield(estimate, 'X_deb_tca');
        if direct_tca_state && ...
                ~(isfield(estimate, 'X_sat_tca') && ...
                  isfield(estimate, 'X_deb_tca'))
            error('ACAM:InvalidFeatureEstimate', ...
                  'Both estimate.X_sat_tca and estimate.X_deb_tca are required.');
        end
        if direct_tca_state
            validateattributes(estimate.X_sat_tca, {'numeric'}, ...
                {'real', 'finite', 'vector', 'numel', 6}, ...
                mfilename, 'estimate.X_sat_tca');
            validateattributes(estimate.X_deb_tca, {'numeric'}, ...
                {'real', 'finite', 'vector', 'numel', 6}, ...
                mfilename, 'estimate.X_deb_tca');
            X_sat_cpa = estimate.X_sat_tca(:);
            X_deb_cpa = estimate.X_deb_tca(:);
        end
        if supplied_tca_covariance
            if ~direct_tca_state
                X_sat_cpa = propagate_state_to_cpa( ...
                    estimate.X_sat, estimate.remaining_time, c);
                X_deb_cpa = propagate_state_to_cpa( ...
                    estimate.X_deb, estimate.remaining_time, c);
            end
            C_sat = estimate.C_sat_tca;
            C_deb = estimate.C_deb_tca;
            validateattributes(C_sat, {'numeric'}, ...
                {'real', 'finite', 'size', [3, 3]}, ...
                mfilename, 'estimate.C_sat_tca');
            validateattributes(C_deb, {'numeric'}, ...
                {'real', 'finite', 'size', [3, 3]}, ...
                mfilename, 'estimate.C_deb_tca');
            if ~is_spd(C_sat) || ~is_spd(C_deb)
                error('ACAM:InvalidFeatureCovariance', ...
                      'Supplied TCA position covariances must be SPD.');
            end
        else
            validateattributes(estimate.P_sat, {'numeric'}, ...
                {'real', 'finite', 'size', [6, 6]}, ...
                mfilename, 'estimate.P_sat');
            validateattributes(estimate.P_deb, {'numeric'}, ...
                {'real', 'finite', 'size', [6, 6]}, ...
                mfilename, 'estimate.P_deb');
            [X_sat_cpa, Phi_sat] = propagate_state_to_cpa( ...
                estimate.X_sat, estimate.remaining_time, c);
            [X_deb_cpa, Phi_deb] = propagate_state_to_cpa( ...
                estimate.X_deb, estimate.remaining_time, c);
            P_sat_cpa = Phi_sat * estimate.P_sat * Phi_sat';
            P_deb_cpa = Phi_deb * estimate.P_deb * Phi_deb';
            P_sat_cpa = (P_sat_cpa + P_sat_cpa') / 2;
            P_deb_cpa = (P_deb_cpa + P_deb_cpa') / 2;
            if ~is_spd(P_sat_cpa) || ~is_spd(P_deb_cpa)
                error('ACAM:InvalidFeatureCovariance', ...
                      'Posterior satellite/debris covariance must be SPD.');
            end
            C_sat = P_sat_cpa(1:3, 1:3);
            C_deb = P_deb_cpa(1:3, 1:3);
        end
        rel_pos = X_sat_cpa(1:3) - X_deb_cpa(1:3);
        rel_vel = X_sat_cpa(4:6) - X_deb_cpa(4:6);
        altitude_m = norm(X_sat_cpa(1:3)) - c.Re;

        % The simulation creates independent filters, so cross-covariance is
        % zero. C_sat/C_deb are the two posterior position covariances at TCA.
        time_remaining_s = estimate.remaining_time;
        X_sat_decision = estimate.X_sat(:);
    else
        if isfield(scenario, 'rel_pos')
            rel_pos = scenario.rel_pos;
            rel_vel = scenario.rel_vel;
        else
            rel_pos = scenario.X0_sat(1:3) - scenario.X0_deb(1:3);
            rel_vel = scenario.X0_sat(4:6) - scenario.X0_deb(4:6);
        end
        C_sat = scenario.C_sat;
        C_deb = scenario.C_deb;
        time_remaining_s = scenario.t_to_cpa;
        X_sat_decision = scenario.X0_sat(:);
    end

    hbr_m = c.HBR;
    if isfield(scenario, 'hbr_m')
        hbr_m = scenario.hbr_m;
    elseif isfield(scenario, 'HBR')
        hbr_m = scenario.HBR;
    end

    Pc = calculatePoC(rel_pos, rel_vel, C_sat, C_deb, hbr_m);
    miss_distance = norm(rel_pos);

    if isfield(feature_overrides, 'pc_initial')
        Pc = feature_overrides.pc_initial;
    end
    if isfield(feature_overrides, 'miss_distance')
        miss_distance = feature_overrides.miss_distance;
    end
    if isfield(feature_overrides, 'time_remaining_s')
        validateattributes(feature_overrides.time_remaining_s, {'numeric'}, ...
            {'real', 'finite', 'scalar', 'nonnegative'}, ...
            mfilename, 'feature_overrides.time_remaining_s');
        time_remaining_s = feature_overrides.time_remaining_s;
    end

    R_hill_to_eci = hill_to_eci(X_sat_decision);
    rel_pos_hill = R_hill_to_eci' * rel_pos(:);
    rel_vel_hill = R_hill_to_eci' * rel_vel(:);

    % Feature schema v3: keep this order synchronized with feature_schema.m.
    features = [
        Pc;
        time_remaining_s;
        miss_distance;
        norm(rel_vel);
        rel_pos_hill;
        rel_vel_hill;
        altitude_m;
        trace(C_sat + C_deb);
        scenario.mass;
        hbr_m
    ];
end

function R_h2e = hill_to_eci(X)
    r_hat = X(1:3) / norm(X(1:3));
    h_hat = cross(X(1:3), X(4:6));
    if norm(h_hat) <= eps
        error('ACAM:InvalidHillFrame', ...
              'Decision state has zero angular momentum.');
    end
    h_hat = h_hat / norm(h_hat);
    t_hat = cross(h_hat, r_hat);
    R_h2e = [r_hat, t_hat, h_hat];
end

function [X_final, Phi] = propagate_state_to_cpa(X0, t_prop, c)
    if t_prop == 0
        X_final = X0;
        if nargout > 1
            Phi = eye(6);
        end
        return;
    end

    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, ...
                     'Events', @(t, X) earth_collision_event(t, X, c));
    [t_out, X_out] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                           [0, t_prop], X0, options);

    if abs(t_out(end) - t_prop) > 1
        error('ACAM:PropagationFailed', 'State propagation did not reach CPA.');
    end

    X_final = X_out(end, :)';
    if nargout > 1
        Phi = compute_state_transition_jacobian(X0, t_prop, c);
    end
end

function value = is_spd(P)
    [~, status] = chol((P + P') / 2);
    value = status == 0;
end

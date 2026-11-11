function report = validate_pc_calibration(estimate, c, config)
%VALIDATE_PC_CALIBRATION Test predicted Pc against nonlinear truth frequency.
%
% Calibration means a predicted probability p is realised at frequency p. It
% cannot be measured by comparing two point estimates built from different
% covariances: |log10(Pc_decision) - log10(Pc_terminal)| is an inter-estimate
% consistency check, not a calibration test, and a large value is expected
% whenever the two covariances differ.
%
% This function draws truth realisations from the declared decision-epoch
% covariances, propagates each pair with the canonical nonlinear dynamics,
% and counts how often the refined closest approach falls inside the
% hard-body radius. The Clopper-Pearson interval on that frequency is then
% compared with the Foster 2-D prediction.
%
% Sample-count honesty: resolving p = 1e-4 needs order 1e5 propagated pairs.
% Use config.hbr_scale to inflate the hard-body radius into a measurable
% probability regime; the same encounter-plane integral and the same
% propagation are exercised, and the conclusion transfers to the model, not
% to the operational threshold. Report the scale with the result.
%
% estimate requires X_sat, X_deb (6x1 ECI at the decision epoch), P_sat,
% P_deb (6x6), and time_to_tca_s.

    if nargin < 3 || isempty(config)
        config = struct();
    end
    config = apply_defaults(config, struct( ...
        'num_samples', 2000, ...
        'hbr_scale', 1.0, ...
        'seed', 20260812, ...
        'confidence_level', 0.95));

    X_sat = column6(estimate.X_sat, 'X_sat');
    X_deb = column6(estimate.X_deb, 'X_deb');
    P_sat = covariance6(estimate.P_sat, 'P_sat');
    P_deb = covariance6(estimate.P_deb, 'P_deb');
    t_to_tca = estimate.time_to_tca_s;
    validateattributes(t_to_tca, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, 'time_to_tca_s');

    hbr_m = c.HBR * config.hbr_scale;
    L_sat = chol(P_sat, 'lower');
    L_deb = chol(P_deb, 'lower');
    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);

    rng(config.seed, 'twister');
    perturbations_sat = L_sat * randn(6, config.num_samples);
    perturbations_deb = L_deb * randn(6, config.num_samples);

    hits = 0;
    completed = 0;
    miss_distances = nan(config.num_samples, 1);
    for k = 1:config.num_samples
        sample_sat = propagate(X_sat + perturbations_sat(:, k), ...
                               t_to_tca, options, c);
        sample_deb = propagate(X_deb + perturbations_deb(:, k), ...
                               t_to_tca, options, c);
        if isempty(sample_sat) || isempty(sample_deb)
            continue;  % Earth intersection or failed step; excluded and counted.
        end
        miss_distances(k) = refined_closest_approach( ...
            sample_sat(1:3) - sample_deb(1:3), ...
            sample_sat(4:6) - sample_deb(4:6));
        completed = completed + 1;
        hits = hits + (miss_distances(k) <= hbr_m);
    end
    if completed == 0
        error('ACAM:PcCalibrationNoSamples', ...
              'No sampled pair propagated successfully.');
    end

    % Predicted probability under the same covariances and the same HBR.
    nominal_sat = propagate(X_sat, t_to_tca, options, c);
    nominal_deb = propagate(X_deb, t_to_tca, options, c);
    Phi_sat = compute_state_transition_jacobian(X_sat, t_to_tca, c);
    Phi_deb = compute_state_transition_jacobian(X_deb, t_to_tca, c);
    C_sat = subblock(Phi_sat * P_sat * Phi_sat');
    C_deb = subblock(Phi_deb * P_deb * Phi_deb');
    predicted_pc = calculatePoC(nominal_sat(1:3) - nominal_deb(1:3), ...
                                nominal_sat(4:6) - nominal_deb(4:6), ...
                                C_sat, C_deb, hbr_m);

    [lower, upper] = clopper_pearson(hits, completed, config.confidence_level);
    report = struct( ...
        'predicted_pc', predicted_pc, ...
        'empirical_frequency', hits / completed, ...
        'confidence_lower', lower, ...
        'confidence_upper', upper, ...
        'within_interval', predicted_pc >= lower && predicted_pc <= upper, ...
        'hits', hits, ...
        'completed_samples', completed, ...
        'requested_samples', config.num_samples, ...
        'hbr_m', hbr_m, ...
        'hbr_scale', config.hbr_scale, ...
        'median_sampled_miss_distance_m', median(miss_distances, 'omitnan'), ...
        'resolvable_probability_floor', 3 / completed, ...
        'config', config);
end

function distance = refined_closest_approach(rel_pos, rel_vel)
%REFINED_CLOSEST_APPROACH Rectilinear CPA correction about the nominal TCA.
% Each perturbed pair has its own closest approach a few seconds away from
% the nominal one; this is the same linear relative-motion assumption the
% Foster 2-D model itself makes, so the test does not smuggle in a different
% encounter model.
    speed_squared = dot(rel_vel, rel_vel);
    if speed_squared <= eps
        distance = norm(rel_pos);
        return;
    end
    dt = -dot(rel_pos, rel_vel) / speed_squared;
    distance = norm(rel_pos + rel_vel * dt);
end

function X_end = propagate(X0, duration, options, c)
    X_end = [];
    if norm(X0(1:3)) <= c.Re
        return;
    end
    try
        [t_out, X_out] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                               [0, duration], X0, options);
    catch
        return;
    end
    if abs(t_out(end) - duration) > max(1, 1e-9 * duration) || ...
            any(~isfinite(X_out(end, :)))
        return;
    end
    X_end = X_out(end, :)';
end

function [lower, upper] = clopper_pearson(hits, n, confidence_level)
    alpha = 1 - confidence_level;
    if hits == 0
        lower = 0;
    else
        lower = betainv(alpha / 2, hits, n - hits + 1);
    end
    if hits == n
        upper = 1;
    else
        upper = betainv(1 - alpha / 2, hits + 1, n - hits);
    end
end

function C = subblock(P)
    C = P(1:3, 1:3);
    C = (C + C') / 2;
end

function X = column6(X, name)
    X = X(:);
    if numel(X) ~= 6 || any(~isfinite(X))
        error('ACAM:InvalidCalibrationInput', ...
              '%s must be a finite six-element state.', name);
    end
end

function P = covariance6(P, name)
    if ~isequal(size(P), [6, 6]) || any(~isfinite(P), 'all')
        error('ACAM:InvalidCalibrationInput', ...
              '%s must be a finite 6x6 covariance.', name);
    end
    P = (P + P') / 2;
    [~, status] = chol(P);
    if status ~= 0
        error('ACAM:InvalidCalibrationInput', ...
              '%s must be positive definite.', name);
    end
end

function config = apply_defaults(config, defaults)
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(config, names{k})
            config.(names{k}) = defaults.(names{k});
        end
    end
end

function X_final = propagate_state_with_discrete_noise( ...
        X_initial, duration_s, c, step_s, disturbances)
%PROPAGATE_STATE_WITH_DISCRETE_NOISE Propagate truth with saved state kicks.

    validateattributes(X_initial, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 6}, mfilename, 'X_initial');
    validateattributes(duration_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, ...
        mfilename, 'duration_s');
    validateattributes(step_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, 'step_s');
    expected_steps = ceil(duration_s / step_s);
    if isempty(disturbances)
        disturbances = zeros(6, expected_steps);
    end
    validateattributes(disturbances, {'numeric'}, ...
        {'real', 'finite', 'size', [6, expected_steps]}, ...
        mfilename, 'disturbances');

    X_final = X_initial(:);
    elapsed_s = 0;
    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, ...
        'Events', @(t, X) earth_collision_event(t, X, c));
    for k = 1:expected_steps
        dt_s = min(step_s, duration_s - elapsed_s);
        [times, states] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                               [0, dt_s], X_final, options);
        if abs(times(end) - dt_s) > max(1, 1e-9 * dt_s)
            error('ACAM:TruthPropagationFailed', ...
                  'Ensemble propagation did not reach the requested epoch.');
        end
        X_final = states(end, :)' + disturbances(:, k);
        elapsed_s = elapsed_s + dt_s;
    end
end

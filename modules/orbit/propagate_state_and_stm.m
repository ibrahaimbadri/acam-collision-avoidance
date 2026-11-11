function [X_final, Phi] = propagate_state_and_stm(X_initial, duration_s, c)
%PROPAGATE_STATE_AND_STM Integrate the nonlinear state and variational STM.

    validateattributes(X_initial, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 6}, mfilename, 'X_initial');
    % Signed. Negative durations transport backwards in time, which Stage D2
    % needs to align an endpoint whose predicted TCA falls after truth TCA.
    % Positive durations are unaffected; this only widens what is accepted.
    validateattributes(duration_s, {'numeric'}, ...
        {'real', 'finite', 'scalar'}, mfilename, 'duration_s');
    if duration_s == 0
        X_final = X_initial(:);
        Phi = eye(6);
        return;
    end

    augmented_initial = [X_initial(:); reshape(eye(6), [], 1)];
    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, ...
        'Events', @(t, state) earth_collision_event(t, state(1:6), c));
    [times, augmented_states] = ode45( ...
        @(t, state) augmented_dynamics(t, state, c), ...
        [0, duration_s], augmented_initial, options);
    if abs(times(end) - duration_s) > max(1, 1e-9 * duration_s)
        error('ACAM:EstimatePropagationFailed', ...
              'State/STM propagation did not reach the requested epoch.');
    end
    final = augmented_states(end, :)';
    X_final = final(1:6);
    Phi = reshape(final(7:end), 6, 6);
end

function derivative = augmented_dynamics(~, augmented_state, c)
    X = augmented_state(1:6);
    Phi = reshape(augmented_state(7:end), 6, 6);
    derivative = [twoBodyJ2Drag_simple(0, X, c); ...
                  reshape(state_dynamics_jacobian(X, c) * Phi, [], 1)];
end

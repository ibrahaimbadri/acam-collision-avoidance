function Phi = compute_state_transition_jacobian(x, dt, c)
% Numerically propagate the state-transition matrix with scaled differences.

    validateattributes(x, {'numeric'}, {'real','finite','vector','numel',6});
    validateattributes(dt, {'numeric'}, {'real','finite','scalar','nonnegative'});

    Phi = zeros(6, 6);
    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10);
    [~, x_base] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                        [0, dt], x(:), options);
    x_base = x_base(end, :)';

    for j = 1:6
        step = 1e-6 * max(abs(x(j)), 1);
        x_perturb = x(:);
        x_perturb(j) = x_perturb(j) + step;
        [~, x_new] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                           [0, dt], x_perturb, options);
        Phi(:, j) = (x_new(end, :)' - x_base) / step;
    end
end

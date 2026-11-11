function A = state_dynamics_jacobian(X, c)
%STATE_DYNAMICS_JACOBIAN Local Jacobian of the six-state orbit dynamics.

    validateattributes(X, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 6}, mfilename, 'X');
    X = X(:);
    A = zeros(6);
    A(1:3, 4:6) = eye(3);
    perturbation = [ones(3, 1); 1e-3 * ones(3, 1)];
    for j = 1:6
        X_plus = X;
        X_minus = X;
        X_plus(j) = X_plus(j) + perturbation(j);
        X_minus(j) = X_minus(j) - perturbation(j);
        f_plus = twoBodyJ2Drag_simple(0, X_plus, c);
        f_minus = twoBodyJ2Drag_simple(0, X_minus, c);
        A(4:6, j) = (f_plus(4:6) - f_minus(4:6)) / ...
                      (2 * perturbation(j));
    end
end

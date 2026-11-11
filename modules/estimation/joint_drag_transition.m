function [state_final, Phi, Q] = joint_drag_transition(state, duration_s, c, config)
%JOINT_DRAG_TRANSITION Propagate state and continuous density uncertainty.

    validateattributes(duration_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, 'duration_s');
    state = state(:);
    dimension = config.state_dimension;
    if duration_s == 0
        state_final = state;
        Phi = eye(dimension);
        Q = zeros(dimension);
        return;
    end
    if ~isfield(config, 'transition_method') || ...
            strcmp(config.transition_method, 'frozen_jacobian_van_loan')
        [state_final, Phi, Q] = frozen_transition( ...
            state, duration_s, c, config);
        return;
    end
    if ~strcmp(config.transition_method, 'time_varying_variational_rk4')
        error('ACAM:UnknownJointTransitionMethod', ...
            'Unknown joint transition method %s.', config.transition_method);
    end
    [state_final, Phi, Q] = time_varying_transition( ...
        state, duration_s, c, config);
end

function [state_final, Phi, Q] = frozen_transition(state, duration_s, c, config)
    A = numerical_jacobian(state, c, config);
    dimension = config.state_dimension;
    spectral = process_spectral_density(config);
    van_loan = expm([A, spectral; zeros(dimension), -A'] * duration_s);
    Phi = van_loan(1:dimension, 1:dimension);
    Q = van_loan(1:dimension, dimension + (1:dimension)) * Phi';
    Q = (Q + Q') / 2;
    options = odeset('RelTol', 1e-9, 'AbsTol', 1e-11);
    solution = ode113(@(t, x) joint_drag_dynamics(t, x, c, config), ...
        [0, duration_s], state, options);
    state_final = solution.y(:, end);
end

function [state_final, Phi, Q] = time_varying_transition( ...
        state, duration_s, c, config)
% Integrate dPhi/dt=A(t)Phi and dQ/dt=AQ+QA'+S along the accurate mean arc.

    validateattributes(config.variational_integration_step_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, ...
        'variational_integration_step_s');
    options = odeset('RelTol', config.state_propagation_rel_tol, ...
        'AbsTol', config.state_propagation_abs_tol);
    solution = ode113(@(t, x) joint_drag_dynamics(t, x, c, config), ...
        [0, duration_s], state, options);
    state_final = solution.y(:, end);
    dimension = config.state_dimension;
    spectral = process_spectral_density(config);
    Phi = eye(dimension);
    Q = zeros(dimension);
    elapsed = 0;
    A_start = numerical_jacobian(state, c, config);
    while elapsed < duration_s
        step = min(config.variational_integration_step_s, ...
            duration_s - elapsed);
        midpoint = elapsed + step / 2;
        endpoint = elapsed + step;
        A_mid = numerical_jacobian(deval(solution, midpoint), c, config);
        A_end = numerical_jacobian(deval(solution, endpoint), c, config);
        [phi1, q1] = variational_rhs(Phi, Q, A_start, spectral);
        [phi2, q2] = variational_rhs(Phi + step * phi1 / 2, ...
            Q + step * q1 / 2, A_mid, spectral);
        [phi3, q3] = variational_rhs(Phi + step * phi2 / 2, ...
            Q + step * q2 / 2, A_mid, spectral);
        [phi4, q4] = variational_rhs(Phi + step * phi3, ...
            Q + step * q3, A_end, spectral);
        Phi = Phi + step * (phi1 + 2 * phi2 + 2 * phi3 + phi4) / 6;
        Q = Q + step * (q1 + 2 * q2 + 2 * q3 + q4) / 6;
        Q = (Q + Q') / 2;
        elapsed = endpoint;
        A_start = A_end;
    end
end

function spectral = process_spectral_density(config)
    spectral = zeros(config.state_dimension);
    spectral(15, 15) = 2 * config.density_stationary_sigma_log^2 / ...
        config.density_correlation_time_s;
    if config.differential_density_enabled
        spectral(16, 16) = 2 * ...
            config.differential_density_stationary_sigma_log^2 / ...
            config.differential_density_correlation_time_s;
    end
end

function [phi_derivative, q_derivative] = ...
        variational_rhs(Phi, Q, A, spectral)
    phi_derivative = A * Phi;
    q_derivative = A * Q + Q * A' + spectral;
end

function A = numerical_jacobian(state, c, config)
    n = numel(state);
    A = zeros(n);
    position = [1:3, 7:9];
    velocity = [4:6, 10:12];
    for j = 1:n
        if ismember(j, position)
            step = 1;
        elseif ismember(j, velocity)
            step = 1e-3;
        else
            step = 1e-5;
        end
        plus = state; plus(j) = plus(j) + step;
        minus = state; minus(j) = minus(j) - step;
        A(:, j) = (joint_drag_dynamics(0, plus, c, config) - ...
                   joint_drag_dynamics(0, minus, c, config)) / (2 * step);
    end
end

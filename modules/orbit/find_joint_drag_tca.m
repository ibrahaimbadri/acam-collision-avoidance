function [tca_s, state_tca, diagnostics] = find_joint_drag_tca( ...
        state, search_interval, c, config, dynamics)
%FIND_JOINT_DRAG_TCA Find closest approach from one coupled joint-state arc.

    if nargin < 5 || isempty(dynamics)
        dynamics = @(t, x) joint_drag_dynamics(t, x, c, config);
    end
    validateattributes(search_interval, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 2}, mfilename, ...
        'search_interval');
    if search_interval(1) < 0 || ...
            search_interval(2) <= search_interval(1)
        error('ACAM:InvalidTcaInterval', ...
            'TCA search interval must be nonnegative and increasing.');
    end

    options = odeset('RelTol', 1e-9, 'AbsTol', 1e-11);
    solution = ode113(dynamics, [0, search_interval(2)], ...
        state(:), options);
    count = min(20000, max(512, ceil(diff(search_interval)) + 1));
    grid = linspace(search_interval(1), search_interval(2), count);
    values = deval(solution, grid);
    distances = vecnorm(values(1:3, :) - values(7:9, :), 2, 1);
    [~, index] = min(distances);
    lower = grid(max(1, index - 1));
    upper = grid(min(count, index + 1));
    range_rate = @(t) rate(t, solution);
    if upper > lower && range_rate(lower) <= 0 && range_rate(upper) >= 0
        tca_s = fzero(range_rate, [lower, upper]);
        method = 'range_rate_root';
    else
        tca_s = fminbnd(@(t) distance(t, solution), lower, upper, ...
            optimset('Display', 'off', 'TolX', 1e-6));
        method = 'distance_fallback';
    end
    state_tca = deval(solution, tca_s);
    relative_position = state_tca(1:3) - state_tca(7:9);
    relative_velocity = state_tca(4:6) - state_tca(10:12);
    time_offset_s = -dot(relative_position, relative_velocity) / ...
        max(dot(relative_velocity, relative_velocity), eps);
    speed = norm(relative_velocity);
    if speed > eps
        velocity_hat = relative_velocity / speed;
        parallel_m = dot(relative_position, velocity_hat);
        perpendicular_m = norm(relative_position - parallel_m * velocity_hat);
    else
        perpendicular_m = norm(relative_position);
    end
    diagnostics = struct('method', method, ...
        'range_rate_residual_m2ps', rate(tca_s, solution), ...
        'miss_distance_m', norm(relative_position), ...
        'tca_inside_interval', tca_s > search_interval(1) && ...
            tca_s < search_interval(2), ...
        'search_interval_s', search_interval(:)', ...
        'tca_time_offset_s', time_offset_s, ...
        'induced_miss_error_m', norm(relative_position) - perpendicular_m);
end

function value = rate(t, solution)
    state = deval(solution, t);
    value = dot(state(1:3) - state(7:9), state(4:6) - state(10:12));
end

function value = distance(t, solution)
    state = deval(solution, t);
    value = norm(state(1:3) - state(7:9));
end

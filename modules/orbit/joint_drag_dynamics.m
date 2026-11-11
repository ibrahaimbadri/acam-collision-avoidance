function derivative = joint_drag_dynamics(~, state, c, config)
%JOINT_DRAG_DYNAMICS Two orbits with common and optional differential density.

    validateattributes(state, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', config.state_dimension}, ...
        mfilename, 'state');
    state = state(:);
    no_drag = c;
    no_drag.A = 0;
    target = state(1:6);
    debris = state(7:12);
    shared_density = state(15);
    differential_density = 0;
    if config.differential_density_enabled
        differential_density = state(16);
    end
    target_derivative = twoBodyJ2Drag_simple(0, target, no_drag);
    debris_derivative = twoBodyJ2Drag_simple(0, debris, no_drag);
    target_derivative(4:6) = target_derivative(4:6) + ...
        exp(state(13) + shared_density + differential_density) * ...
        nominal_drag_acceleration(target, c, config);
    debris_derivative(4:6) = debris_derivative(4:6) + ...
        exp(state(14) + shared_density - differential_density) * ...
        nominal_drag_acceleration(debris, c, config);
    derivative = [target_derivative; debris_derivative; 0; 0; ...
        -shared_density / config.density_correlation_time_s];
    if config.differential_density_enabled
        derivative(end + 1, 1) = -differential_density / ...
            config.differential_density_correlation_time_s;
    end
end

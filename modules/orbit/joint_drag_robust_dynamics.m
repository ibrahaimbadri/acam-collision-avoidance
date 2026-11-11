function derivative = joint_drag_robust_dynamics(t, state, c, filter, ...
        include_srp, srp, target_physical, debris_physical)
%JOINT_DRAG_ROBUST_DYNAMICS Joint-drag mean model with optional SRP stress.
%
% This mirrors the frozen Stage 6b0 robust-envelope mean dynamics without
% changing that legacy evaluator. SRP is a deterministic sensitivity member;
% it is not a state or process-noise term in the joint-drag EKF.

    derivative = joint_drag_dynamics(t, state, c, filter);
    if ~include_srp
        return;
    end
    fraction = min(max(t / srp.duration_s, 0), 1);
    sun_position = srp.sun_start_m + fraction * ...
        (srp.sun_end_m - srp.sun_start_m);
    derivative(4:6) = derivative(4:6) + srp_acceleration( ...
        state(1:3), sun_position, c, srp, target_physical);
    derivative(10:12) = derivative(10:12) + srp_acceleration( ...
        state(7:9), sun_position, c, srp, debris_physical);
end

function acceleration = srp_acceleration(position, sun_position, c, ...
        environment, physical)
    sun_direction = sun_position / norm(sun_position);
    behind_earth = dot(position, sun_direction) < 0;
    shadow_distance = norm(position - ...
        dot(position, sun_direction) * sun_direction);
    if behind_earth && shadow_distance < c.Re
        acceleration = zeros(3, 1);
        return;
    end
    to_sun = sun_position - position;
    acceleration = -environment.solar_pressure_npm2 * ...
        physical.reflectivity_coefficient * ...
        (physical.srp_area_m2 / physical.mass_kg) * ...
        (environment.astronomical_unit_m / norm(to_sun))^2 * ...
        (to_sun / norm(to_sun));
end

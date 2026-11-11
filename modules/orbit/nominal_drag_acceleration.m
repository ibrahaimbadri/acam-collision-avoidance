function acceleration = nominal_drag_acceleration(X, c, config)
%NOMINAL_DRAG_ACCELERATION Quiet-table drag using atmosphere-relative flow.

    persistent altitude_grid log_density_grid
    r = X(1:3);
    v = X(4:6);
    altitude = norm(r) - c.Re;
    if altitude <= 0 || altitude >= 1000e3
        acceleration = zeros(3, 1);
        return;
    end
    if isempty(altitude_grid)
        altitude_grid = [0, 25, 50, 75, 100, 150, 200, 250, 300, 350, ...
            400, 450, 500, 600, 700, 800, 900, 1000] * 1e3;
        density_grid = [1.225, 3.899e-2, 1.027e-3, 3.206e-5, 5.60e-7, ...
            2.07e-9, 2.54e-10, 6.00e-11, 1.90e-11, 8.00e-12, ...
            3.70e-12, 1.70e-12, 1.00e-12, 3.00e-13, 1.10e-13, ...
            5.00e-14, 2.50e-14, 1.20e-14];
        log_density_grid = log10(density_grid);
    end
    rho = 10.^interp1(altitude_grid, log_density_grid, altitude, 'linear');
    rho = rho * exp(config.reference_density_log_bias);
    if isfield(c, 'scenario_mass'), mass = c.scenario_mass; else, mass = c.m; end
    omega = [0; 0; config.earth_rotation_radps];
    relative_velocity = v - cross(omega, r);
    acceleration = -0.5 * rho * c.Cd * (c.A / mass) * ...
        norm(relative_velocity) * relative_velocity;
end

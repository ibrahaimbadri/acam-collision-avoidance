function dXdt = twoBodyJ2Drag_simple(~, X, c)
% Two-body + J2 + exponential atmospheric drag dynamics.

    persistent altitude_grid log_density_grid

    r = X(1:3);
    v = X(4:6);
    rnorm = norm(r);

    a_grav = -c.mu * r / rnorm^3;

    z2 = r(3)^2;
    r2 = rnorm^2;
    factor = 1.5 * c.J2 * c.mu * c.Re^2 / rnorm^5;
    a_J2 = factor * [r(1) * (5*z2/r2 - 1);
                     r(2) * (5*z2/r2 - 1);
                     r(3) * (5*z2/r2 - 3)];

    alt = rnorm - c.Re;
    if alt > 0 && alt < 1000e3
        % Approximate quiet-atmosphere density in log space. A sea-level
        % scale-height formula is unusable in LEO: at 500 km it overstates
        % density by several orders of magnitude.
        if isempty(altitude_grid)
            altitude_grid = [0, 25, 50, 75, 100, 150, 200, 250, ...
                             300, 350, 400, 450, 500, 600, 700, ...
                             800, 900, 1000] * 1e3;
            density_grid = [1.225, 3.899e-2, 1.027e-3, 3.206e-5, ...
                            5.60e-7, 2.07e-9, 2.54e-10, 6.00e-11, ...
                            1.90e-11, 8.00e-12, 3.70e-12, 1.70e-12, ...
                            1.00e-12, 3.00e-13, 1.10e-13, 5.00e-14, ...
                            2.50e-14, 1.20e-14];
            log_density_grid = log10(density_grid);
        end
        rho = 10.^interp1(altitude_grid, log_density_grid, alt, 'linear');
        if isfield(c, 'scenario_mass')
            actual_mass = c.scenario_mass;
        else
            actual_mass = c.m;
        end
        a_drag = -0.5 * c.Cd * (c.A / actual_mass) * rho * norm(v) * v;
    else
        a_drag = zeros(3, 1);
    end

    dXdt = [v; a_grav + a_J2 + a_drag];
end

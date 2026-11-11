function [tca, X_sat_tca, X_deb_tca, miss_distance, residual, diagnostics] = ...
        find_tca(X0_sat, X0_deb, search_interval, c, reference_time, ...
                 X_sat_reference, X_deb_reference, propagation_tolerance, ...
                 dynamics_pair)
%FIND_TCA Find the interior time of closest approach with nonlinear dynamics.

    if nargin < 5
        reference_time = NaN;
    end
    if nargin < 7
        X_sat_reference = [];
        X_deb_reference = [];
    end
    % The forward leg of the scenario round trip. Callers reconstructing a
    % requested CPA state must pass the same tolerance used on the backward
    % leg, otherwise round-trip error cannot be attributed to either.
    if nargin < 8 || isempty(propagation_tolerance)
        propagation_tolerance = struct('rel_tol', 1e-8, 'abs_tol', 1e-10);
    end
    if nargin < 9 || isempty(dynamics_pair)
        dynamics_pair = struct( ...
            'target', @(t, X) twoBodyJ2Drag_simple(t, X, c), ...
            'debris', @(t, X) twoBodyJ2Drag_simple(t, X, c));
    end

    validateattributes(search_interval, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 2}, mfilename, 'search_interval');
    if search_interval(2) <= search_interval(1)
        error('ACAM:InvalidTcaInterval', 'TCA search interval must increase.');
    end

    options = odeset('RelTol', propagation_tolerance.rel_tol, ...
                     'AbsTol', propagation_tolerance.abs_tol, ...
                     'Events', @(t, X) earth_collision_event(t, X, c));
    propagation_interval = [0, search_interval(2)];
    sat_solution = ode113( ...
        dynamics_pair.target, propagation_interval, X0_sat, options);
    deb_solution = ode113( ...
        dynamics_pair.debris, propagation_interval, X0_deb, options);

    t_end = search_interval(2);
    if sat_solution.x(end) < t_end - 1 || deb_solution.x(end) < t_end - 1
        error('ACAM:TcaPropagationFailed', ...
              'Propagation stopped before the TCA search interval ended.');
    end

    % Range rate vanishes at maxima as well as minima, and a search interval
    % wide enough for a slow co-orbital encounter can contain several
    % stationary points, so root-finding on range rate alone can return the
    % wrong one. A direct minimiser has the opposite problem: at kilometres
    % per second the true approach is a notch metres deep and milliseconds
    % wide inside an interval spanning thousands of kilometres, which a
    % golden-section search steps straight over. Sample the distance on a
    % bounded grid, take the global sampled minimum, then refine only inside
    % the bracketing sub-interval. deval is interpolation on the stored
    % solution, so the grid is cheap.
    sample_count = min(20000, max(512, ceil(diff(search_interval)) + 1));
    t_grid = linspace(search_interval(1), search_interval(2), sample_count);
    sat_grid = deval(sat_solution, t_grid);
    deb_grid = deval(deb_solution, t_grid);
    distances = vecnorm(sat_grid(1:3, :) - deb_grid(1:3, :), 2, 1);
    [~, index] = min(distances);
    lower_bound = t_grid(max(index - 1, 1));
    upper_bound = t_grid(min(index + 1, sample_count));

    % Refine inside the bracket by solving r_rel . v_rel = 0 rather than by
    % minimising the distance. Near closest approach the distance is flat -
    % it grows as v^2 dt^2 / 2d - so a minimiser can only locate the epoch
    % to about the square root of the achievable function precision, which
    % at kilometres per second over a multi-day integration left a residual
    % of order metres. Range rate crosses zero linearly there, so a root
    % find keeps full precision. The minimiser is retained only as a
    % fallback for the case where the root is not bracketed.
    range_rate = @(t) relative_range_rate(t, sat_solution, deb_solution);
    if upper_bound <= lower_bound
        tca = t_grid(index);
        refinement_status = 'grid_point_no_bracket';
    else
        lower_rate = range_rate(lower_bound);
        upper_rate = range_rate(upper_bound);
        if lower_rate <= 0 && upper_rate >= 0
            tca = fzero(range_rate, [lower_bound, upper_bound]);
            refinement_status = 'range_rate_root';
        else
            objective = @(t) relative_distance(t, sat_solution, deb_solution);
            options_min = optimset('Display', 'off', 'TolX', 1e-6);
            tca = fminbnd(objective, lower_bound, upper_bound, options_min);
            refinement_status = 'distance_minimiser_fallback';
        end
    end

    X_sat_tca = deval(sat_solution, tca);
    X_deb_tca = deval(deb_solution, tca);
    rel_pos = X_sat_tca(1:3) - X_deb_tca(1:3);
    rel_vel = X_sat_tca(4:6) - X_deb_tca(4:6);
    miss_distance = norm(rel_pos);
    residual = abs(dot(rel_pos, rel_vel)) / ...
               (norm(rel_pos) * norm(rel_vel) + eps);
    % Three formulations of "did we land on closest approach" have now been
    % tried, and the first two were regime-dependent. The normalised cosine
    % scales with relative speed over miss distance, so a tolerance set on
    % metre-per-second co-orbital geometry is unreachable at kilometres per
    % second. The residual time offset is comparable across speeds but not
    % across integration lengths, so it rejected long-arc crossing cases
    % whose geometry was fine. Both are still reported as diagnostics.
    %
    % The gate quantity is the induced miss-distance error: how much the
    % reported miss distance exceeds the local rectilinear correction to
    % closest approach. It is in metres, the same unit and budget as the
    % scenario miss-distance tolerance it sits beside, so it is
    % regime-independent by construction.
    %
    % Note this is a LOCAL RECTILINEAR CORRECTION, not the true CPA
    % distance. The nonlinear propagated solution remains the reference; the
    % correction only measures how far the returned epoch sits from the
    % stationary point of that solution.
    time_offset_s = -dot(rel_pos, rel_vel) / max(dot(rel_vel, rel_vel), eps);
    speed = norm(rel_vel);
    if speed > eps
        velocity_hat = rel_vel / speed;
        along_track_residual_m = dot(rel_pos, velocity_hat);
        perpendicular_m = norm(rel_pos - along_track_residual_m * velocity_hat);
    else
        along_track_residual_m = 0;
        perpendicular_m = miss_distance;
    end
    induced_miss_error_m = miss_distance - perpendicular_m;

    diagnostics = struct( ...
        'tca_inside_interval', tca > search_interval(1) && ...
                              tca < search_interval(2), ...
        'satellite_propagation_end_s', sat_solution.x(end), ...
        'debris_propagation_end_s', deb_solution.x(end), ...
        'search_interval', search_interval, ...
        'minimum_satellite_radius_m', min(vecnorm(sat_solution.y(1:3, :), 2, 1)), ...
        'minimum_debris_radius_m', min(vecnorm(deb_solution.y(1:3, :), 2, 1)), ...
        'orthogonality_residual', residual, ...
        'tca_time_offset_s', time_offset_s, ...
        'along_track_residual_m', along_track_residual_m, ...
        'induced_miss_error_m', induced_miss_error_m, ...
        'refinement_status', refinement_status, ...
        'reference_time_s', reference_time, ...
        'round_trip_position_error_m', round_trip_error( ...
            reference_time, sat_solution, deb_solution, ...
            X_sat_reference, X_deb_reference));
end

function error_m = round_trip_error(reference_time, sat_solution, ...
                                    deb_solution, X_sat_reference, ...
                                    X_deb_reference)
    error_m = NaN;
    if ~isfinite(reference_time) || isempty(X_sat_reference) || ...
            isempty(X_deb_reference) || reference_time < 0 || ...
            reference_time > sat_solution.x(end) || ...
            reference_time > deb_solution.x(end)
        return;
    end
    X_sat = deval(sat_solution, reference_time);
    X_deb = deval(deb_solution, reference_time);
    error_m = max(norm(X_sat(1:3) - X_sat_reference(1:3)), ...
                  norm(X_deb(1:3) - X_deb_reference(1:3)));
end

function value = relative_range_rate(t, sat_solution, deb_solution)
%RELATIVE_RANGE_RATE Zero exactly at a stationary point of the separation.
    X_sat = deval(sat_solution, t);
    X_deb = deval(deb_solution, t);
    value = dot(X_sat(1:3) - X_deb(1:3), X_sat(4:6) - X_deb(4:6));
end

function value = relative_distance(t, sat_solution, deb_solution)
    X_sat = deval(sat_solution, t);
    X_deb = deval(deb_solution, t);
    value = norm(X_sat(1:3) - X_deb(1:3));
end

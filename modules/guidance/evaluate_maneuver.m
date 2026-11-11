function [success, fuel, Pc_final, details] = ...
        evaluate_maneuver(scenario, dV, c, tracking_time, stop_on_earth, ...
                           reuse_context)
%EVALUATE_MANEUVER Evaluate one impulsive maneuver with nonlinear dynamics.
%
% The burn is applied in ECI velocity coordinates at tracking_time. Both
% spacecraft are propagated to that time and then to TCA with the same J2+
% drag model. The first three outputs preserve the original API; details
% records whether the propagation and physical safety checks completed.

    if nargin < 4 || isempty(tracking_time)
        tracking_time = 0;
    end
    if nargin < 5 || isempty(stop_on_earth)
        stop_on_earth = true;
    end
    if nargin < 6 || isempty(reuse_context)
        reuse_context = [];
    end

    validateattributes(dV, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, 'dV');
    validateattributes(tracking_time, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, ...
        mfilename, 'tracking_time');
    validateattributes(stop_on_earth, {'logical', 'numeric'}, ...
        {'real', 'finite', 'scalar'}, mfilename, 'stop_on_earth');
    dV = dV(:);
    stop_on_earth = logical(stop_on_earth);
    fuel = norm(dV);
    details = struct( ...
        'status', 'not_started', ...
        'completed', false, ...
        'earth_intersection', false, ...
        'tracking_time_s', tracking_time, ...
        'remaining_time_s', NaN, ...
        'propagation_fidelity', 'J2', ...
        'risk_evaluation_completed', false, ...
        'final_pc', Inf, ...
        'fuel_mps', fuel, ...
        'evaluation_context', [], ...
        'actuator_limit_mps', c.max_maneuver_mps);
    Pc_final = Inf;
    success = false;

    if tracking_time > scenario.t_to_cpa
        error('ACAM:InvalidTrackingTime', ...
              'tracking_time must not exceed scenario.t_to_cpa.');
    end
    if fuel > c.max_maneuver_mps * (1 + 1e-12)
        details.status = 'actuator_limit_exceeded';
        return;
    end

    remaining_time = scenario.t_to_cpa - tracking_time;
    details.remaining_time_s = remaining_time;
    pre_burn_dynamics = truth_dynamics_pair(scenario, c, tracking_time);
    post_burn_context = scenario;
    if isfield(scenario, 'truth_epoch_utc')
        post_burn_context.truth_epoch_utc = scenario.truth_epoch_utc + ...
            seconds(tracking_time);
    end
    post_burn_dynamics = truth_dynamics_pair( ...
        post_burn_context, c, remaining_time);
    details.propagation_fidelity = post_burn_dynamics.mode;
    truth_tolerance = truth_propagation_tolerance(scenario, ...
        struct('rel_tol', 1e-8, 'abs_tol', 1e-10));
    options = odeset('RelTol', truth_tolerance.rel_tol, ...
                     'AbsTol', truth_tolerance.abs_tol);
    if stop_on_earth
        options = odeset(options, 'Events', ...
                         @(t, X) earth_collision_event(t, X, c));
    end

    if isempty(reuse_context)
        [X_sat_at_burn, sat_ok, sat_earth, sat_status] = propagate_segment( ...
            scenario.X0_sat, tracking_time, options, c, ...
            pre_burn_dynamics.target);
        [X_deb_at_burn, deb_ok, deb_earth, deb_status] = propagate_segment( ...
            scenario.X0_deb, tracking_time, options, c, ...
            pre_burn_dynamics.debris);
        if ~sat_ok || ~deb_ok
            details.completed = false;
            details.earth_intersection = sat_earth || deb_earth;
            if details.earth_intersection
                details.status = 'earth_intersection';
            else
                details.status = first_failure_status(sat_status, deb_status);
            end
            return;
        end

        [X_deb_final, deb_ok, deb_earth, deb_status] = propagate_segment( ...
            X_deb_at_burn, remaining_time, options, c, ...
            post_burn_dynamics.debris);
        if ~deb_ok
            details.completed = false;
            details.earth_intersection = deb_earth;
            if details.earth_intersection
                details.status = 'earth_intersection';
            else
                details.status = deb_status;
            end
            return;
        end

        reuse_context = struct( ...
            'tracking_time_s', tracking_time, ...
            'remaining_time_s', remaining_time, ...
            'X_sat_at_burn', X_sat_at_burn, ...
            'X_deb_at_burn', X_deb_at_burn, ...
            'X_deb_final', X_deb_final, ...
            'truth_model_mode', post_burn_dynamics.mode, ...
            'completed', true);
    else
        if ~isstruct(reuse_context) || ...
                ~isfield(reuse_context, 'tracking_time_s') || ...
                ~isfield(reuse_context, 'remaining_time_s') || ...
                ~isfield(reuse_context, 'X_sat_at_burn') || ...
                ~isfield(reuse_context, 'X_deb_at_burn') || ...
                ~isfield(reuse_context, 'X_deb_final') || ...
                ~isfield(reuse_context, 'truth_model_mode') || ...
                ~isfield(reuse_context, 'completed') || ...
                ~reuse_context.completed || ...
                abs(reuse_context.tracking_time_s - tracking_time) > 1e-9 || ...
                abs(reuse_context.remaining_time_s - remaining_time) > 1e-9 || ...
                ~strcmp(reuse_context.truth_model_mode, ...
                        post_burn_dynamics.mode) || ...
                any(~isfinite([reuse_context.X_sat_at_burn(:); ...
                               reuse_context.X_deb_at_burn(:); ...
                               reuse_context.X_deb_final(:)]))
            details.status = 'invalid_reuse_context';
            return;
        end
        X_sat_at_burn = reuse_context.X_sat_at_burn(:);
        X_deb_final = reuse_context.X_deb_final(:);
    end

    X_sat_after_burn = X_sat_at_burn;
    X_sat_after_burn(4:6) = X_sat_after_burn(4:6) + dV;
    [X_sat_final, sat_ok, sat_earth, sat_status] = propagate_segment( ...
        X_sat_after_burn, remaining_time, options, c, ...
        post_burn_dynamics.target);
    if ~sat_ok
        details.completed = false;
        details.earth_intersection = sat_earth;
        if details.earth_intersection
            details.status = 'earth_intersection';
        else
            details.status = sat_status;
        end
        return;
    end

    rel_pos_final = X_sat_final(1:3) - X_deb_final(1:3);
    rel_vel_final = X_sat_final(4:6) - X_deb_final(4:6);
    try
        hbr_m = c.HBR;
        if isfield(scenario, 'hbr_m')
            hbr_m = scenario.hbr_m;
        elseif isfield(scenario, 'HBR')
            hbr_m = scenario.HBR;
        end
        Pc_final = calculatePoC(rel_pos_final, rel_vel_final, ...
                                scenario.C_sat, scenario.C_deb, hbr_m);
    catch ME
        details.completed = false;
        details.status = 'risk_evaluation_failed';
        details.failure_identifier = ME.identifier;
        details.failure_message = ME.message;
        return;
    end
    success = isfinite(Pc_final) && Pc_final <= c.pc_maneuver_threshold;
    details.completed = true;
    details.risk_evaluation_completed = true;
    details.final_pc = Pc_final;
    details.evaluation_context = reuse_context;
    if success
        details.status = 'safe';
    else
        details.status = 'unsafe';
    end
end

function [X_end, completed, earth_intersection, status] = ...
        propagate_segment(X_start, duration, options, c, dynamics)
    if nargin < 5 || isempty(dynamics)
        dynamics = @(t, X) twoBodyJ2Drag_simple(t, X, c);
    end
    X_start = X_start(:);
    earth_intersection = false;
    status = 'completed';
    if norm(X_start(1:3)) <= c.Re
        X_end = X_start;
        completed = false;
        earth_intersection = true;
        status = 'earth_intersection';
        return;
    end
    if duration == 0
        X_end = X_start;
        completed = true;
        return;
    end

    try
        [t_out, X_out] = ode45(dynamics, ...
                               [0, duration], X_start, options);
    catch
        X_end = X_start;
        completed = false;
        status = 'propagation_failed';
        return;
    end

    X_end = X_out(end, :)';
    time_tolerance = max(1, 1e-9 * duration);
    completed = abs(t_out(end) - duration) <= time_tolerance && ...
                all(isfinite(X_end));
    if ~completed
        earth_intersection = norm(X_end(1:3)) <= c.Re + 1e-3;
        if earth_intersection
            status = 'earth_intersection';
        else
            status = 'propagation_failed';
        end
    end
end

function status = first_failure_status(first_status, second_status)
    if strcmp(first_status, 'earth_intersection') || ...
            strcmp(second_status, 'earth_intersection')
        status = 'earth_intersection';
    else
        status = 'propagation_failed';
    end
end

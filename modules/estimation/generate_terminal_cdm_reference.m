function reference = generate_terminal_cdm_reference(scenario, c, seed, config)
%GENERATE_TERMINAL_CDM_REFERENCE Create a withheld final-OD CDM assessment.

    if nargin < 4 || isempty(config)
        config = terminal_cdm_reference_config();
    end
    lead_s = config.reference_lead_time_s;
    start_s = lead_s + config.max_tracking_duration_s;
    segment = scenario;
    tca_context = scenario;
    if isfield(scenario, 'truth_tca_epoch_utc')
        tca_context.truth_epoch_utc = scenario.truth_tca_epoch_utc;
    end
    backward_dynamics = truth_dynamics_pair(tca_context, c, -start_s);
    truth_tolerance = truth_propagation_tolerance(tca_context, ...
        struct('rel_tol', 1e-8, 'abs_tol', 1e-10));
    segment.X0_sat = state_before_tca( ...
        scenario.X_cpa_sat, start_s, c, backward_dynamics.target, ...
        truth_tolerance);
    segment.X0_deb = state_before_tca( ...
        scenario.X_cpa_deb, start_s, c, backward_dynamics.debris, ...
        truth_tolerance);
    segment.t_to_cpa = start_s;
    if isfield(scenario, 'truth_tca_epoch_utc')
        segment.truth_epoch_utc = scenario.truth_tca_epoch_utc - ...
            seconds(start_s);
    end
    tracking = run_ekf_tracking(segment, c, config, seed);
    posterior = struct('X_sat', tracking.X_sat_est, ...
        'X_deb', tracking.X_deb_est, 'P_sat', tracking.P_sat, ...
        'P_deb', tracking.P_deb);
    platform = struct('event_id', sprintf('terminal-reference-%d', seed), ...
        'spacecraft_mass_kg', scenario.mass, 'hbr_m', scenario.hbr_m);
    [cdm, assessment, tca_state] = generate_cdm_from_estimate( ...
        posterior, platform, c, lead_s, config, ...
        sprintf('%s-final', platform.event_id));
    truth = struct( ...
        'target_state_eci_tca', scenario.X_cpa_sat, ...
        'chaser_state_eci_tca', scenario.X_cpa_deb);
    optional = {'truth_model', 'truth_tca_epoch_utc', ...
                'target_physical', 'debris_physical'};
    for k = 1:numel(optional)
        if isfield(scenario, optional{k})
            truth.(optional{k}) = scenario.(optional{k});
        end
    end
    reference = struct('cdm', cdm, 'tracking', tracking.diagnostics, ...
        ... % Terminal posterior and the authoritative 6x6 TCA covariances
        ... % from the CDM's own propagation. Stage D2 transports these to
        ... % truth TCA; the CDM publishes only the 3x3 position block.
        'posterior', posterior, 'tca_state', tca_state, ...
        'assessment', assessment, 'config', config, 'truth', truth);
end

function X_start = state_before_tca( ...
        X_tca, duration_s, c, dynamics, tolerance)
    if nargin < 4 || isempty(dynamics)
        dynamics = @(t, X) twoBodyJ2Drag_simple(t, X, c);
    end
    if nargin < 5 || isempty(tolerance)
        tolerance = struct('rel_tol', 1e-8, 'abs_tol', 1e-10);
    end
    options = odeset('RelTol', tolerance.rel_tol, ...
        'AbsTol', tolerance.abs_tol, ...
        'Events', @(t, X) earth_collision_event(t, X, c));
    solution = ode113(dynamics, ...
                      [0, -duration_s], X_tca, options);
    if abs(solution.x(end) + duration_s) > 1
        error('ACAM:TerminalReferenceBackPropagationFailed', ...
              'Terminal-reference truth propagation stopped early.');
    end
    X_start = solution.y(:, end);
end

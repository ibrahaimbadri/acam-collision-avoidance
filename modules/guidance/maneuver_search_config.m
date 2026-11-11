function config = maneuver_search_config(direction_scope)
%MANEUVER_SEARCH_CONFIG Declared Stage 6 maneuver-search settings.

    if nargin < 1 || isempty(direction_scope)
        direction_scope = 'six_axis';
    end
    direction_scope = validatestring(direction_scope, ...
                                     {'six_axis', 'along_track'});

    config.version = 2;
    config.coarse_grid_count = 21;
    % Verified minimum-safe burns observed so far are of order 1e-3 m/s. A
    % linear grid over [0, max_maneuver] has a 0.1 m/s first step, so every
    % crossing lands in the first interval: the coarse grid cannot see
    % non-monotonic risk below that step, and bisection inside the bracket
    % does assume monotonicity. A log grid resolves the decade the answers
    % actually live in and stops spending nonlinear evaluations on
    % magnitudes twenty times larger than any observed solution.
    config.coarse_grid_minimum_mps = 1e-4;
    config.coarse_grid_spacing = 'log';
    config.refinement_iterations = 24;
    config.direction_labels = { ...
        'radial_in', 'radial_out', ...
        'prograde', 'retrograde', ...
        'cross_track_plus', 'cross_track_minus'};
    config.direction_vectors_hill = [ ...
        -1,  1,  0,  0,  0,  0; ...
         0,  0,  1, -1,  0,  0; ...
         0,  0,  0,  0,  1, -1];
    if strcmp(direction_scope, 'along_track')
        config.direction_labels = config.direction_labels(3:4);
        config.direction_vectors_hill = ...
            config.direction_vectors_hill(:, 3:4);
    end
    config.direction_scope = direction_scope;
    config.evaluation_fidelity = 'J2';
    config.refinement_tolerance_policy = ...
        'widest_coarse_interval / 2^iterations';
end

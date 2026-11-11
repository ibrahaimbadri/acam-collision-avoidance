function [dV, info] = find_minimum_safe_maneuver( ...
        X_sat_burn, scenario, c, t_drift, rel_pos_cpa, rel_vel_cpa, ...
        X_sat_cpa, C_sat, C_deb, X_deb_burn, search_config)
%FIND_MINIMUM_SAFE_MANEUVER Search all declared Hill-frame directions.
%
% Each direction is evaluated on a coarse magnitude grid with the nonlinear
% evaluator. Every unsafe-to-safe grid crossing is refined independently;
% the smallest verified candidate is returned. A no-solution result returns
% zero Delta-V with an explicit status, never an unchecked fallback.

    if nargin < 4 || isempty(t_drift)
        t_drift = scenario.t_to_cpa;
    end
    if nargin < 5 || isempty(rel_pos_cpa)
        rel_pos_cpa = scenario.rel_pos;
    end
    if nargin < 6 || isempty(rel_vel_cpa)
        rel_vel_cpa = scenario.rel_vel;
    end
    if nargin < 7 || isempty(X_sat_cpa)
        X_sat_cpa = scenario.X_cpa_sat; %#ok<NASGU>
    end
    if nargin < 8 || isempty(C_sat)
        C_sat = scenario.C_sat;
    end
    if nargin < 9 || isempty(C_deb)
        C_deb = scenario.C_deb;
    end
    if nargin < 10 || isempty(X_deb_burn)
        X_deb_burn = scenario.X0_deb;
    end
    if nargin < 11 || isempty(search_config)
        search_config = maneuver_search_config();
    end

    validateattributes(t_drift, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, 't_drift');
    validateattributes(X_sat_burn, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 6}, mfilename, 'X_sat_burn');
    validateattributes(X_deb_burn, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 6}, mfilename, 'X_deb_burn');
    validateattributes(rel_pos_cpa, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, 'rel_pos_cpa');
    validateattributes(rel_vel_cpa, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, 'rel_vel_cpa');

    decision_threshold_pc = c.pc_maneuver_threshold;
    target_pc = c.pc_target_remediation;
    max_maneuver = c.max_maneuver_mps;
    directions = search_config.direction_vectors_hill;
    labels = search_config.direction_labels;
    magnitudes = coarse_magnitudes(search_config, max_maneuver);
    R_burn = hill_to_eci(X_sat_burn);
    evaluation_scenario = scenario;
    evaluation_scenario.X0_sat = X_sat_burn(:);
    evaluation_scenario.X0_deb = X_deb_burn(:);
    evaluation_scenario.t_to_cpa = t_drift;
    evaluation_scenario.C_sat = C_sat;
    evaluation_scenario.C_deb = C_deb;
    use_test_evaluator = isfield(search_config, 'candidate_evaluator') && ...
                         ~isempty(search_config.candidate_evaluator);
    timer = tic;
    evaluations = 0;
    initial_evaluated = false;
    initial_pc = Inf;
    initial_details = struct('completed', false);
    evaluation_context = [];

    [initial_pc, initial_details] = evaluate_candidate(zeros(3, 1), 0);
    evaluations = evaluations + 1;
    initial_evaluated = true;
    if isfield(initial_details, 'evaluation_context') && ...
            ~isempty(initial_details.evaluation_context)
        evaluation_context = initial_details.evaluation_context;
    end
    decision_pc = initial_pc;
    decision_trigger_source = 'candidate evaluator zero-burn Pc';
    if isfield(search_config, 'decision_pc_override')
        validateattributes(search_config.decision_pc_override, {'numeric'}, ...
            {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, ...
            mfilename, 'search_config.decision_pc_override');
        decision_pc = search_config.decision_pc_override;
        decision_trigger_source = 'external decision Pc override';
        if isfield(search_config, 'decision_trigger_source')
            decision_trigger_source = char(search_config.decision_trigger_source);
        end
    end
    if decision_pc <= decision_threshold_pc
        dV = zeros(3, 1);
        info = build_info('stay', decision_threshold_pc, target_pc, ...
                          initial_pc, initial_pc, '', 0, 0, evaluations, ...
                          timer, labels, directions, magnitudes, ...
                          search_config, use_test_evaluator);
        info.decision_pc = decision_pc;
        info.internal_zero_burn_pc = initial_pc;
        info.decision_trigger_source = decision_trigger_source;
        return;
    end

    coarse_pc = cell(1, size(directions, 2));
    coarse_safe = cell(1, size(directions, 2));
    coarse_evaluated = cell(1, size(directions, 2));
    crossing_magnitudes = cell(1, size(directions, 2));
    best_magnitude = inf;
    best_direction_index = NaN;

    for direction_index = 1:size(directions, 2)
        direction = directions(:, direction_index);
        if isfinite(best_magnitude)
            last_index = find(magnitudes >= best_magnitude, 1, 'first');
            if isempty(last_index)
                last_index = numel(magnitudes);
            end
        else
            last_index = numel(magnitudes);
        end
        evaluated_indices = 1:last_index;
        pc_values = nan(size(magnitudes));
        safe_values = false(size(magnitudes));
        evaluated_values = false(size(magnitudes));
        for k = evaluated_indices
            [pc_values(k), ~] = evaluate_candidate( ...
                direction, magnitudes(k));
            evaluations = evaluations + 1;
            safe_values(k) = pc_values(k) <= target_pc;
            evaluated_values(k) = true;
        end
        coarse_pc{direction_index} = pc_values;
        coarse_safe{direction_index} = safe_values;
        coarse_evaluated{direction_index} = evaluated_values;
        crossing_indices = find(~safe_values(1:end-1) & ...
                                safe_values(2:end));
        crossing_magnitudes{direction_index} = ...
            magnitudes(crossing_indices + 1);

        for crossing = 1:numel(crossing_indices)
            lower = magnitudes(crossing_indices(crossing));
            upper = magnitudes(crossing_indices(crossing) + 1);
            for iteration = 1:search_config.refinement_iterations
                middle = (lower + upper) / 2;
                [middle_pc, ~] = evaluate_candidate(direction, middle);
                evaluations = evaluations + 1;
                if middle_pc <= target_pc
                    upper = middle;
                else
                    lower = middle;
                end
            end
            [refined_pc, ~] = evaluate_candidate(direction, upper);
            evaluations = evaluations + 1;
            if refined_pc <= target_pc && upper < best_magnitude
                best_magnitude = upper;
                best_direction_index = direction_index;
            end
        end
    end

    if ~isfinite(best_magnitude)
        dV = zeros(3, 1);
        info = build_info('no_solution', decision_threshold_pc, target_pc, ...
                          initial_pc, initial_pc, '', NaN, inf, evaluations, ...
                          timer, labels, directions, magnitudes, search_config, ...
                          use_test_evaluator);
        info.coarse_pc = coarse_pc;
        info.coarse_safe = coarse_safe;
        info.coarse_evaluated = coarse_evaluated;
        info.crossing_magnitudes = crossing_magnitudes;
        info.decision_pc = decision_pc;
        info.internal_zero_burn_pc = initial_pc;
        info.decision_trigger_source = decision_trigger_source;
        return;
    end

    best_direction = directions(:, best_direction_index);
    dV = R_burn * (best_direction * best_magnitude);
    [verified_pc, evaluation_details] = evaluate_candidate( ...
        best_direction, best_magnitude);
    evaluations = evaluations + 1;
    if verified_pc > target_pc || ~evaluation_details.completed
        error('ACAM:ManeuverSearchVerificationFailed', ...
              'The selected maneuver did not satisfy the nonlinear target.');
    end

    info = build_info('success', decision_threshold_pc, target_pc, ...
                      initial_pc, verified_pc, labels{best_direction_index}, ...
                      best_direction_index, best_magnitude, evaluations, timer, ...
                      labels, directions, magnitudes, search_config, ...
                      use_test_evaluator);
    info.achieved_pc = verified_pc;
    info.coarse_pc = coarse_pc;
    info.coarse_safe = coarse_safe;
    info.coarse_evaluated = coarse_evaluated;
    info.crossing_magnitudes = crossing_magnitudes;
    info.evaluation_completed = evaluation_details.completed;
    info.decision_pc = decision_pc;
    info.internal_zero_burn_pc = initial_pc;
    info.decision_trigger_source = decision_trigger_source;

    function [pc, details] = evaluate_candidate(direction, magnitude)
        if initial_evaluated && magnitude == 0
            pc = initial_pc;
            details = initial_details;
        elseif use_test_evaluator
            pc = search_config.candidate_evaluator(direction, magnitude);
            details = struct('completed', isfinite(pc));
        else
            candidate_hill = direction * magnitude;
            candidate_eci = R_burn * candidate_hill;
            [~, ~, pc, details] = evaluate_maneuver( ...
                evaluation_scenario, candidate_eci, c, 0, true, ...
                evaluation_context);
        end
        if ~isfinite(pc)
            pc = inf;
        end
    end
end

function info = build_info(status, decision_threshold_pc, target_pc, ...
                            initial_pc, achieved_pc, direction_label, ...
                            direction_index, magnitude, evaluations, timer, ...
                            labels, directions, magnitudes, config, ...
                            test_evaluator)
    info = struct( ...
        'status', status, ...
        'decision_threshold_pc', decision_threshold_pc, ...
        'target_pc', target_pc, ...
        'initial_pc', initial_pc, ...
        'achieved_pc', achieved_pc, ...
        'selected_direction', direction_label, ...
        'selected_direction_index', direction_index, ...
        'selected_magnitude_mps', magnitude, ...
        'coarse_magnitudes_mps', magnitudes, ...
        'direction_labels', {labels}, ...
        'direction_vectors_hill', directions, ...
        'coarse_pc', {cell(1, numel(labels))}, ...
        'coarse_safe', {cell(1, numel(labels))}, ...
        'coarse_evaluated', {cell(1, numel(labels))}, ...
        'crossing_magnitudes', {cell(1, numel(labels))}, ...
        'optimizer_evaluations', evaluations, ...
        'runtime_s', toc(timer), ...
        'refinement_iterations', config.refinement_iterations, ...
        ... % Bisection runs inside one coarse bracket, so the worst-case
        ... % tolerance is the widest coarse interval, not the whole range.
        'refinement_tolerance_mps', ...
            max(diff(magnitudes)) / 2^config.refinement_iterations, ...
        'evaluation_fidelity', evaluation_fidelity(config, test_evaluator), ...
        'safety_constraint_satisfied', strcmp(status, 'success') || ...
            strcmp(status, 'stay'), ...
        'evaluation_completed', true);
end

function value = evaluation_fidelity(config, custom_evaluator)
    if ~custom_evaluator
        value = config.evaluation_fidelity;
    elseif isfield(config, 'candidate_evaluator_fidelity')
        value = config.candidate_evaluator_fidelity;
    else
        value = 'synthetic_test_override';
    end
end

function magnitudes = coarse_magnitudes(config, max_maneuver)
%COARSE_MAGNITUDES Zero plus a log-spaced sweep to the actuator limit.
    if isfield(config, 'coarse_grid_spacing') && ...
            strcmp(config.coarse_grid_spacing, 'log')
        minimum = config.coarse_grid_minimum_mps;
        magnitudes = [0, logspace(log10(minimum), log10(max_maneuver), ...
                                  config.coarse_grid_count - 1)];
    else
        magnitudes = linspace(0, max_maneuver, config.coarse_grid_count);
    end
end

function R_h2e = hill_to_eci(X)
    r_hat = X(1:3) / norm(X(1:3));
    h_hat = cross(X(1:3), X(4:6));
    if norm(h_hat) <= eps
        error('ACAM:InvalidHillFrame', 'Burn state has zero angular momentum.');
    end
    h_hat = h_hat / norm(h_hat);
    t_hat = cross(h_hat, r_hat);
    R_h2e = [r_hat, t_hat, h_hat];
end

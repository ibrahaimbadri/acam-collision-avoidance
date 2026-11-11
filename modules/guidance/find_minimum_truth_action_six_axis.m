function [dV_hill, info] = find_minimum_truth_action_six_axis( ...
        scenario, R_burn, c, reuse_context, config)
%FIND_MINIMUM_TRUTH_ACTION_SIX_AXIS Search the frozen six Hill-axis grid.

    if nargin < 5 || isempty(config), config = struct(); end
    search = maneuver_search_config('six_axis');
    custom = field_or(config, 'candidate_evaluator', []);
    extras = field_or(config, 'extra_magnitudes_mps', zeros(0, 1));
    refinements = field_or(config, 'refinement_iterations', ...
        search.refinement_iterations);
    validateattributes(R_burn, {'numeric'}, ...
        {'real', 'finite', 'size', [3, 3]}, mfilename, 'R_burn');
    validateattributes(extras, {'numeric'}, ...
        {'real', 'finite', 'vector', 'nonnegative'}, mfilename, ...
        'extra_magnitudes_mps');
    assert(all(extras <= c.max_maneuver_mps), ...
        'Extra magnitude exceeds the actuator limit.');

    grid = unique([logspace(log10(search.coarse_grid_minimum_mps), ...
        log10(c.max_maneuver_mps), search.coarse_grid_count)'; ...
        extras(:)]);
    grid = grid(grid > 0 & grid <= c.max_maneuver_mps);
    direction_count = numel(search.direction_labels);
    grid_pc = nan(direction_count, numel(grid));
    grid_completed = false(direction_count, numel(grid));
    evaluation_count = 0;
    all_completed = true;

    [zero_pc, zero_completed] = evaluate(zeros(3, 1), 0);
    if zero_completed && zero_pc <= c.pc_maneuver_threshold
        dV_hill = zeros(3, 1);
        info = finish_info('stay', true, 0, "stay", 0, zero_pc, ...
            zeros(0, 1), zeros(direction_count, 0), ...
            false(direction_count, 0), struct([]));
        return;
    end

    previous_magnitude = 0;
    refinement_records = struct([]);
    for magnitude_index = 1:numel(grid)
        magnitude = grid(magnitude_index);
        safe_directions = false(direction_count, 1);
        for direction_index = 1:direction_count
            direction = search.direction_vectors_hill(:, direction_index);
            [pc, completed] = evaluate(direction, magnitude);
            grid_pc(direction_index, magnitude_index) = pc;
            grid_completed(direction_index, magnitude_index) = completed;
            safe_directions(direction_index) = completed && ...
                pc <= c.pc_maneuver_threshold;
        end
        if ~any(safe_directions)
            previous_magnitude = magnitude;
            continue;
        end

        candidates = find(safe_directions);
        candidate_magnitudes = inf(size(candidates));
        candidate_pc = inf(size(candidates));
        refinement_records = repmat(struct('direction_index', NaN, ...
            'magnitudes_mps', [], 'pc', [], 'completed', []), ...
            numel(candidates), 1);
        for k = 1:numel(candidates)
            direction_index = candidates(k);
            direction = search.direction_vectors_hill(:, direction_index);
            lower = previous_magnitude;
            upper = magnitude;
            magnitudes = nan(refinements + 1, 1);
            pc_values = nan(refinements + 1, 1);
            completed_values = false(refinements + 1, 1);
            for iteration = 1:refinements
                middle = (lower + upper) / 2;
                [pc, completed] = evaluate(direction, middle);
                magnitudes(iteration) = middle;
                pc_values(iteration) = pc;
                completed_values(iteration) = completed;
                if completed && pc <= c.pc_maneuver_threshold
                    upper = middle;
                else
                    lower = middle;
                end
            end
            [pc, completed] = evaluate(direction, upper);
            magnitudes(end) = upper;
            pc_values(end) = pc;
            completed_values(end) = completed;
            refinement_records(k) = struct( ...
                'direction_index', direction_index, ...
                'magnitudes_mps', magnitudes, 'pc', pc_values, ...
                'completed', completed_values);
            if completed && pc <= c.pc_maneuver_threshold
                candidate_magnitudes(k) = upper;
                candidate_pc(k) = pc;
            end
        end
        [selected_magnitude, selected] = min(candidate_magnitudes);
        if isfinite(selected_magnitude)
            selected_index = candidates(selected);
            dV_hill = search.direction_vectors_hill(:, selected_index) * ...
                selected_magnitude;
            info = finish_info('success', true, selected_index, ...
                string(search.direction_labels{selected_index}), ...
                selected_magnitude, candidate_pc(selected), ...
                grid(1:magnitude_index), grid_pc(:, 1:magnitude_index), ...
                grid_completed(:, 1:magnitude_index), refinement_records);
            return;
        end
        previous_magnitude = magnitude;
    end

    dV_hill = nan(3, 1);
    info = finish_info('no_solution', false, NaN, "", NaN, Inf, ...
        grid, grid_pc, grid_completed, refinement_records);

    function [pc, completed] = evaluate(direction, magnitude)
        evaluation_count = evaluation_count + 1;
        if isempty(custom)
            [~, ~, pc, details] = evaluate_maneuver(scenario, ...
                R_burn * direction * magnitude, c, 0, true, reuse_context);
            completed = details.completed && isfinite(pc);
        else
            pc = custom(direction, magnitude);
            completed = isfinite(pc);
        end
        all_completed = all_completed && completed;
        if ~completed, pc = Inf; end
    end

    function value = finish_info(status, verified, direction_index, ...
            direction, magnitude, pc, magnitudes, pc_grid, ...
            completed_grid, refinement)
        value = struct('status', string(status), 'completed', ...
            all_completed, 'verified_safe', verified, ...
            'selected_direction_index', direction_index, ...
            'selected_direction', direction, ...
            'selected_magnitude_mps', magnitude, 'truth_pc', pc, ...
            'evaluations', evaluation_count, 'zero_burn_pc', zero_pc, ...
            'grid_magnitudes_mps', magnitudes, 'grid_pc', pc_grid, ...
            'grid_completed', completed_grid, ...
            'refinement_records', refinement, ...
            'search_scope', "six_axis_first_safe_grid_level", ...
            'actuator_limit_mps', c.max_maneuver_mps);
    end
end

function value = field_or(s, name, default_value)
    if isfield(s, name), value = s.(name); else, value = default_value; end
end

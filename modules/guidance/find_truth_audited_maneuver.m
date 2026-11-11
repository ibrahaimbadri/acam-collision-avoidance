function [dV_hill, info] = find_truth_audited_maneuver( ...
        scenario, R_burn, preferred_direction_hill, ...
        optimizer_magnitude_mps, c, reuse_context, config)
%FIND_TRUTH_AUDITED_MANEUVER Increase an optimizer action until truth-safe.

    if nargin < 7 || isempty(config), config = struct(); end
    step = field_or(config, 'magnitude_step_mps', 0.001);
    max_label = field_or(config, 'max_label_mps', 0.05);
    refinements = field_or(config, 'refinement_iterations', 24);
    custom = field_or(config, 'candidate_evaluator', []);
    validateattributes(R_burn, {'numeric'}, ...
        {'real', 'finite', 'size', [3, 3]}, mfilename, 'R_burn');
    validateattributes(preferred_direction_hill, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, ...
        'preferred_direction_hill');
    validateattributes(optimizer_magnitude_mps, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive', '<=', max_label}, ...
        mfilename, 'optimizer_magnitude_mps');
    validateattributes(step, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, ...
        'magnitude_step_mps');
    validateattributes(refinements, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'nonnegative'}, ...
        mfilename, 'refinement_iterations');

    search = maneuver_search_config();
    preferred_direction_hill = preferred_direction_hill(:) / ...
        norm(preferred_direction_hill);
    alignment = search.direction_vectors_hill' * preferred_direction_hill;
    [best_alignment, preferred_index] = max(alignment);
    assert(best_alignment > 1 - 1e-10, ...
        'Preferred direction is not one of the frozen Hill axes.');

    evaluations = 0;
    [preferred_magnitude, preferred_pc] = search_direction(preferred_index);
    if isfinite(preferred_magnitude)
        selected_index = preferred_index;
        selected_magnitude = preferred_magnitude;
        selected_pc = preferred_pc;
        used_alternate = false;
    else
        selected_index = NaN;
        selected_magnitude = Inf;
        selected_pc = Inf;
        used_alternate = true;
        for direction_index = setdiff(1:6, preferred_index, 'stable')
            [magnitude, pc] = search_direction(direction_index);
            if magnitude < selected_magnitude
                selected_index = direction_index;
                selected_magnitude = magnitude;
                selected_pc = pc;
            end
        end
    end

    if ~isfinite(selected_magnitude)
        dV_hill = nan(3, 1);
        info = struct('status', 'no_solution', ...
            'completed', true, 'verified_safe', false, ...
            'preferred_direction_feasible', false, ...
            'used_alternate_direction', true, ...
            'selected_direction', '', 'selected_direction_index', NaN, ...
            'optimizer_magnitude_mps', optimizer_magnitude_mps, ...
            'selected_magnitude_mps', NaN, 'truth_pc', Inf, ...
            'evaluations', evaluations);
        return;
    end
    dV_hill = search.direction_vectors_hill(:, selected_index) * ...
        selected_magnitude;
    info = struct('status', 'success', 'completed', true, ...
        'verified_safe', selected_pc <= c.pc_maneuver_threshold, ...
        'preferred_direction_feasible', isfinite(preferred_magnitude), ...
        'used_alternate_direction', used_alternate, ...
        'selected_direction', search.direction_labels{selected_index}, ...
        'selected_direction_index', selected_index, ...
        'optimizer_magnitude_mps', optimizer_magnitude_mps, ...
        'selected_magnitude_mps', selected_magnitude, ...
        'truth_pc', selected_pc, 'evaluations', evaluations);

    function [safe_magnitude, safe_pc] = search_direction(direction_index)
        direction = search.direction_vectors_hill(:, direction_index);
        regular = (0:step:max_label)';
        magnitudes = [optimizer_magnitude_mps; ...
            regular(regular > optimizer_magnitude_mps + eps(max_label))];
        if magnitudes(end) < max_label
            magnitudes(end + 1, 1) = max_label;
        end
        pc = nan(size(magnitudes));
        for k = 1:numel(magnitudes)
            pc(k) = evaluate(direction, magnitudes(k));
            if pc(k) <= c.pc_maneuver_threshold
                if k == 1
                    safe_magnitude = magnitudes(k);
                    safe_pc = pc(k);
                    return;
                end
                lower = magnitudes(k - 1);
                upper = magnitudes(k);
                for iteration = 1:refinements
                    middle = (lower + upper) / 2;
                    middle_pc = evaluate(direction, middle);
                    if middle_pc <= c.pc_maneuver_threshold
                        upper = middle;
                    else
                        lower = middle;
                    end
                end
                safe_magnitude = upper;
                safe_pc = evaluate(direction, upper);
                return;
            end
        end
        safe_magnitude = Inf;
        safe_pc = Inf;
    end

    function pc = evaluate(direction, magnitude)
        evaluations = evaluations + 1;
        if ~isempty(custom)
            pc = custom(direction, magnitude);
            return;
        end
        [~, ~, pc, details] = evaluate_maneuver(scenario, ...
            R_burn * direction * magnitude, c, 0, true, reuse_context);
        if ~details.completed || ~isfinite(pc), pc = Inf; end
    end
end

function value = field_or(s, name, default_value)
    if isfield(s, name), value = s.(name); else, value = default_value; end
end


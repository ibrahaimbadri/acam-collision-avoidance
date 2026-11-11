function [dV_hill, info] = find_bounded_truth_audited_maneuver( ...
        scenario, R_burn, direction_hill, lower_mps, upper_mps, ...
        c, reuse_context, config)
%FIND_BOUNDED_TRUTH_AUDITED_MANEUVER Audit one fixed direction in one interval.

    if nargin < 8 || isempty(config), config = struct(); end
    step = field_or(config, 'magnitude_step_mps', 0.001);
    refinements = field_or(config, 'refinement_iterations', 24);
    custom = field_or(config, 'candidate_evaluator', []);
    validateattributes(direction_hill, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, ...
        mfilename, 'direction_hill');
    assert(norm(direction_hill) > 0, 'Audit direction must be nonzero.');
    validateattributes(lower_mps, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, 'lower_mps');
    validateattributes(upper_mps, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', lower_mps}, ...
        mfilename, 'upper_mps');
    direction_hill = direction_hill(:) / norm(direction_hill);
    search = maneuver_search_config();
    alignment = search.direction_vectors_hill' * direction_hill;
    [best_alignment, direction_index] = max(alignment);
    assert(best_alignment > 1 - 1e-10, ...
        'Audit direction is not a frozen Hill axis.');

    regular = (0:step:upper_mps)';
    magnitudes = [lower_mps; regular(regular > lower_mps + eps(upper_mps))];
    if magnitudes(end) < upper_mps
        magnitudes(end + 1, 1) = upper_mps;
    end
    evaluations = 0;
    selected = NaN;
    selected_pc = Inf;
    previous = NaN;
    for k = 1:numel(magnitudes)
        pc = evaluate(magnitudes(k));
        if pc <= c.pc_maneuver_threshold
            selected = magnitudes(k);
            selected_pc = pc;
            if k > 1
                lower = previous;
                upper = selected;
                for iteration = 1:refinements
                    middle = (lower + upper) / 2;
                    middle_pc = evaluate(middle);
                    if middle_pc <= c.pc_maneuver_threshold
                        upper = middle;
                    else
                        lower = middle;
                    end
                end
                selected = upper;
                selected_pc = evaluate(selected);
            end
            break;
        end
        previous = magnitudes(k);
    end

    if ~isfinite(selected)
        dV_hill = nan(3, 1);
        status = 'no_solution';
        verified = false;
    else
        dV_hill = direction_hill * selected;
        status = 'success';
        verified = selected_pc <= c.pc_maneuver_threshold;
    end
    info = struct('status', status, 'completed', true, ...
        'verified_safe', verified, ...
        'selected_direction', search.direction_labels{direction_index}, ...
        'selected_direction_index', direction_index, ...
        'lower_mps', lower_mps, 'upper_mps', upper_mps, ...
        'selected_magnitude_mps', selected, 'truth_pc', selected_pc, ...
        'evaluations', evaluations);

    function pc = evaluate(magnitude)
        evaluations = evaluations + 1;
        if ~isempty(custom)
            pc = custom(direction_hill, magnitude);
            return;
        end
        [~, ~, pc, details] = evaluate_maneuver(scenario, ...
            R_burn * direction_hill * magnitude, c, 0, true, reuse_context);
        if ~details.completed || ~isfinite(pc), pc = Inf; end
    end
end

function value = field_or(s, name, default_value)
    if isfield(s, name), value = s.(name); else, value = default_value; end
end

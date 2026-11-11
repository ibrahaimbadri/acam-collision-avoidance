function target = generate_stage6b1_optimizer_target(decision, c, config)
%GENERATE_STAGE6B1_OPTIMIZER_TARGET Build one decision-information target.

    if nargin < 3 || isempty(config)
        config = struct();
    end
    validate_stage6b1_decision_context(decision);
    [evaluator, fidelity] = candidate_evaluator(decision, c, config);
    [robust_zero_pc, zero_details] = evaluator(zeros(3, 1), 0);
    assert(zero_details.completed && isfinite(robust_zero_pc), ...
        'Complete zero-burn evaluation failed.');
    features = build_features(decision, robust_zero_pc, config);
    trigger_pc = max(decision.message.collision_probability, robust_zero_pc);
    triggered = trigger_pc > c.pc_maneuver_threshold;
    target = struct('status', "stay", 'triggered', triggered, ...
        'features', features(:)', 'dV_hill', zeros(3, 1), ...
        'direction', "stay", 'magnitude_mps', 0, ...
        'trigger_pc', trigger_pc, 'robust_zero_burn_pc', robust_zero_pc, ...
        'information_set', "stage6b1_decision_context_v1", ...
        'evaluator_fidelity', string(fidelity), ...
        'optimizer_info', struct());
    if ~triggered
        return;
    end

    search = maneuver_search_config('along_track');
    search.candidate_evaluator = evaluator;
    search.candidate_evaluator_fidelity = fidelity;
    search.decision_pc_override = trigger_pc;
    search.decision_trigger_source = ...
        'max(published CDM Pc, complete robust zero-burn Pc)';
    if isfield(config, 'optimizer')
        [dV_hill, should_maneuver, ~, info] = ...
            config.optimizer(decision.message, c, search);
    else
        [dV_hill, should_maneuver, ~, info] = ...
            compute_cdm_oracle(decision.message, c, search);
    end
    target.optimizer_info = info;
    if ~should_maneuver || ~strcmp(string(info.status), "success") || ...
            ~valid_along_track(dV_hill, c)
        target.status = "fallback_required";
        target.dV_hill(:) = NaN;
        target.direction = "fallback_required";
        target.magnitude_mps = NaN;
        return;
    end
    dV_hill = dV_hill(:);
    target.status = "success";
    target.dV_hill = dV_hill;
    target.magnitude_mps = norm(dV_hill);
    if dV_hill(2) > 0
        target.direction = "prograde";
    else
        target.direction = "retrograde";
    end
end

function features = build_features(decision, robust_zero_pc, config)
    if isfield(config, 'feature_builder')
        features = config.feature_builder(decision);
    else
        tracking = struct('state', decision.tracking.state, ...
            'covariance', decision.tracking.covariance, ...
            'diagnostics', struct('mean_nis12', ...
                decision.tracking.mean_nis12), ...
            'measurement_available', ...
                decision.tracking.measurement_available_fraction);
        features = build_truth_audited_features(decision.message, tracking, ...
            robust_zero_pc, decision.weather);
    end
    validateattributes(features, {'numeric'}, ...
        {'real', 'finite', 'vector', 'nonempty'}, mfilename, 'features');
end

function [evaluator, fidelity] = candidate_evaluator(decision, c, config)
    if isfield(config, 'candidate_evaluator')
        evaluator = config.candidate_evaluator;
        fidelity = 'artifact_free_test_override';
        return;
    end
    [evaluator, envelope] = build_joint_drag_robust_evaluator( ...
        decision.message, decision.tracking, decision.planning_scenario, ...
        decision.filter, c, decision.decision_epoch_utc);
    fidelity = envelope.fidelity;
end

function valid = valid_along_track(dV_hill, c)
    dV_hill = dV_hill(:);
    magnitude = norm(dV_hill);
    valid = numel(dV_hill) == 3 && all(isfinite(dV_hill)) && ...
        magnitude > 0 && magnitude <= c.max_maneuver_mps / 1.10 && ...
        abs(dV_hill(1)) <= 1e-12 && abs(dV_hill(3)) <= 1e-12 && ...
        abs(abs(dV_hill(2)) - magnitude) <= 1e-12;
end

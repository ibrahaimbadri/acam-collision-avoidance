function report = test_stage6b1_gate_c()
%TEST_STAGE6B1_GATE_C Run the frozen artifact-free policy preflight.

    c = load_constants();
    source_tracking = struct('state', zeros(16, 1), ...
        'covariance', eye(16), ...
        'diagnostics', struct('mean_nis12', 1, ...
            'truth_target_final', ones(6, 1)), ...
        'measurement_available', [true; false]);
    message = struct('spacecraft_mass_kg', 500, ...
        'collision_probability', 2e-4);
    filter = struct('state_dimension', 16, ...
        'differential_density_enabled', true);
    weather = struct('f107_average', 150, 'f107_daily', 155, ...
        'magnetic_index', [4; 4; 4; 4; 4; 4; 4], ...
        'local_solar_time_h', 12);
    epoch = datetime(2026, 8, 29, 0, 0, 0, 'TimeZone', 'UTC');
    decision = build_stage6b1_decision_context( ...
        message, source_tracking, filter, epoch, weather);

    names = [ ...
        "valid_decision_context"; "reject_top_level_withheld_truth"; ...
        "reject_nested_future_cdm"; "same_context_feature_target_provenance"; ...
        "prograde_optimizer_target"; "retain_fallback_required"; ...
        "reject_radial_optimizer_target"; "untriggered_stay_no_callbacks"; ...
        "verified_prograde_proposal"; "verified_retrograde_proposal"; ...
        "invalid_direction_uses_fallback"; ...
        "unsafe_proposal_uses_fallback"; ...
        "unavailable_fallback_no_solution"; ...
        "failed_fallback_verification_no_solution"; ...
        "reserve_overflow_never_executes"; "valid_split_isolation"; ...
        "reject_cross_split_geometry"; "reject_sensitivity_fit"];
    passed = false(size(names));
    passed(1) = ~isfield(decision.tracking, 'diagnostics') && ...
        ~contains(lower(strjoin(fieldnames(decision), ',')), 'truth');

    poisoned = decision;
    poisoned.withheld_truth = struct();
    passed(2) = throws_boundary(@() ...
        validate_stage6b1_decision_context(poisoned));
    poisoned = decision;
    poisoned.message.future_cdm = struct();
    passed(3) = throws_boundary(@() ...
        validate_stage6b1_decision_context(poisoned));

    target_config = struct('feature_builder', @mock_features, ...
        'candidate_evaluator', @mock_candidate, ...
        'optimizer', @prograde_optimizer);
    target = generate_stage6b1_optimizer_target(decision, c, target_config);
    passed(4) = target.information_set == ...
        "stage6b1_decision_context_v1" && ...
        isequal(target.features, [2e-4, 0]);
    passed(5) = target.status == "success" && ...
        target.direction == "prograde" && ...
        isequal(target.dV_hill, [0; 0.2; 0]);

    target_config.optimizer = @no_solution_optimizer;
    target = generate_stage6b1_optimizer_target(decision, c, target_config);
    passed(6) = target.status == "fallback_required" && ...
        all(isnan(target.dV_hill));
    target_config.optimizer = @radial_optimizer;
    target = generate_stage6b1_optimizer_target(decision, c, target_config);
    passed(7) = target.status == "fallback_required" && ...
        all(isnan(target.dV_hill));

    safe_verifier = @verify_safe;
    no_fallback = @fallback_none;
    untriggered = decision;
    untriggered.message.collision_probability = 1e-6;
    policy_config = struct('reserve_factor', 1.10, ...
        'robust_zero_burn_pc', 1e-6);
    result = run_stage6b1_verified_policy(untriggered, [1, 2], ...
        @unexpected_proposer, @unexpected_verifier, ...
        @unexpected_fallback, c, policy_config);
    passed(8) = result.status == "stay" && ...
        result.proposer_calls == 0 && result.verifier_calls == 0 && ...
        result.fallback_calls == 0;

    policy_config.robust_zero_burn_pc = 2e-4;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_prograde, safe_verifier, @unexpected_fallback, ...
        c, policy_config);
    passed(9) = result.status == "ml_verified" && ...
        result.action_source == "ml" && ...
        abs(result.dV_hill(2) - 0.11) < 1e-14 && ...
        result.verifier_calls == 1 && result.fallback_calls == 0;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_retrograde, safe_verifier, @unexpected_fallback, ...
        c, policy_config);
    passed(10) = result.status == "ml_verified" && ...
        abs(result.dV_hill(2) + 0.11) < 1e-14;

    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_radial, safe_verifier, @fallback_success, ...
        c, policy_config);
    passed(11) = result.status == "fallback_verified" && ...
        result.action_source == "fallback" && ...
        abs(result.dV_hill(1) - 0.22) < 1e-14 && ...
        result.fallback_calls == 1;

    sequence_verifier_count = 0;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_prograde, @verify_unsafe_then_safe, ...
        @fallback_success, c, policy_config);
    passed(12) = result.status == "fallback_verified" && ...
        result.verifier_calls == 2 && result.fallback_calls == 1;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_prograde, @verify_unsafe, no_fallback, c, policy_config);
    passed(13) = result.status == "no_solution" && ...
        all(result.dV_hill == 0) && result.fallback_calls == 1;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_prograde, @verify_unsafe, @fallback_success, ...
        c, policy_config);
    passed(14) = result.status == "no_solution" && ...
        all(result.dV_hill == 0) && result.verifier_calls == 2;
    result = run_stage6b1_verified_policy(decision, [1, 2], ...
        @propose_overflow, safe_verifier, no_fallback, c, policy_config);
    passed(15) = result.status == "no_solution" && ...
        all(result.dV_hill == 0) && result.verifier_calls == 0 && ...
        norm(result.dV_hill) <= c.max_maneuver_mps;

    split_rows = table([1; 1; 2; 2], ...
        ["primary_drag"; "srp_sensitivity"; ...
         "primary_drag"; "srp_sensitivity"], ...
        ["train"; "train"; "validation"; "validation"], ...
        [true; false; true; false], ...
        'VariableNames', {'geometry_id', 'arm', 'split', 'fit_eligible'});
    validate_stage6b1_split_isolation(split_rows);
    passed(16) = true;
    leaking = split_rows;
    leaking.split(2) = "validation";
    passed(17) = throws_split(@() ...
        validate_stage6b1_split_isolation(leaking));
    leaking = split_rows;
    leaking.fit_eligible(2) = true;
    passed(18) = throws_split(@() ...
        validate_stage6b1_split_isolation(leaking));

    report = table(names, passed, 'VariableNames', {'check', 'passed'});
    assert(height(report) == 18 && all(report.passed), ...
        'Stage 6b1 Gate C artifact-free preflight failed.');

    function [pc, details] = mock_candidate(~, ~)
        pc = 2e-4;
        details = struct('completed', true);
    end

    function features = mock_features(value)
        validate_stage6b1_decision_context(value);
        features = [value.message.collision_probability, ...
            value.tracking.state(13)];
    end

    function [pc, details] = verify_unsafe_then_safe(~)
        sequence_verifier_count = sequence_verifier_count + 1;
        if sequence_verifier_count == 1
            pc = 1e-2;
        else
            pc = c.pc_target_remediation / 2;
        end
        details = struct('completed', true);
    end
end

function tf = throws_boundary(callback)
    tf = throws_identifier(callback, 'ACAM:Stage6b1InformationBoundary');
end

function tf = throws_split(callback)
    tf = throws_identifier(callback, 'ACAM:Stage6b1SplitLeakage');
end

function tf = throws_identifier(callback, identifier)
    tf = false;
    try
        callback();
    catch ME
        tf = strcmp(ME.identifier, identifier);
    end
end

function proposal = propose_prograde(~)
    proposal = struct('direction', "prograde", 'magnitude_mps', 0.1);
end

function proposal = propose_retrograde(~)
    proposal = struct('direction', "retrograde", 'magnitude_mps', 0.1);
end

function proposal = propose_radial(~)
    proposal = struct('direction', "radial_in", 'magnitude_mps', 0.1);
end

function proposal = propose_overflow(~)
    proposal = struct('direction', "prograde", 'magnitude_mps', 2.0);
end

function proposal = unexpected_proposer(~)
    proposal = struct(); %#ok<NASGU>
    error('ACAM:UnexpectedCallback', 'Proposer should not be called.');
end

function [pc, details] = verify_safe(~)
    c = load_constants();
    pc = c.pc_target_remediation / 2;
    details = struct('completed', true);
end

function [pc, details] = verify_unsafe(~)
    pc = 1e-2;
    details = struct('completed', true);
end

function [pc, details] = unexpected_verifier(~)
    pc = Inf; %#ok<NASGU>
    details = struct('completed', false); %#ok<NASGU>
    error('ACAM:UnexpectedCallback', 'Verifier should not be called.');
end

function [dV, info] = fallback_success(decision)
    validate_stage6b1_decision_context(decision);
    dV = [0.2; 0; 0];
    info = struct('status', "success");
end

function [dV, info] = fallback_none(~)
    dV = zeros(3, 1);
    info = struct('status', "no_solution");
end

function [dV, info] = unexpected_fallback(~)
    dV = zeros(3, 1); %#ok<NASGU>
    info = struct('status', "no_solution"); %#ok<NASGU>
    error('ACAM:UnexpectedCallback', 'Fallback should not be called.');
end

function [dV, should_maneuver, pc, info] = prograde_optimizer(~, ~, ~)
    dV = [0; 0.2; 0];
    should_maneuver = true;
    pc = 1e-7;
    info = struct('status', "success");
end

function [dV, should_maneuver, pc, info] = no_solution_optimizer(~, ~, ~)
    dV = zeros(3, 1);
    should_maneuver = false;
    pc = Inf;
    info = struct('status', "no_solution");
end

function [dV, should_maneuver, pc, info] = radial_optimizer(~, ~, ~)
    dV = [0.2; 0; 0];
    should_maneuver = true;
    pc = 1e-7;
    info = struct('status', "success");
end

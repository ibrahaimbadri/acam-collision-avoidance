function [features_row, action, dV_row, metadata, timing] = generate_training_row( ...
        config, c, feature_names, band_index, band_counts, seed, stress_flag, ...
        tracking_config)
%GENERATE_TRAINING_ROW Build one training row: scenario, features and label.
%
% Extracted verbatim from generate_training_data so that the production
% generator and the pipeline timing benchmark call the SAME code. The logic
% is unchanged. The fifth output TIMING is optional per-component wall time;
% production requests four outputs and never sees it.

    timing = struct('scenario_s', NaN, 'ekf_cdm_s', NaN, 'features_s', NaN, ...
                    'oracle_s', NaN, 'tracking_s', NaN, ...
                    'decision_propagation_s', NaN, 'row_total_s', NaN);
    row_timer = tic;
    config_i = config;
    config_i.pc_band_index = band_index;
    if ~isnan(stress_flag)
        config_i.force_stress = logical(stress_flag);
    end
    stage_timer = tic;
    [scenario, metadata] = generate_synthetic_scenario(config_i, c, seed);
    timing.scenario_s = toc(stage_timer);

    c_scenario = c;
    c_scenario.HBR = scenario.hbr_m;
    c_scenario.scenario_mass = scenario.mass;
    decision_time_s = min( ...
        scenario.t_to_cpa - config.decision_policy.reserve_before_tca_s, ...
        config.decision_policy.max_tracking_duration_s);
    if decision_time_s <= 0 || decision_time_s >= scenario.t_to_cpa
        error('ACAM:InvalidTrainingDecisionTime', ...
              'Training decision time must leave a positive TCA window.');
    end
    remaining_time_s = scenario.t_to_cpa - decision_time_s;
    % cdm_sequence never reads scenario_at_decision: it takes its decision
    % epoch from the CDM lead and calls compute_cdm_oracle instead of
    % compute_deterministic_oracle. Propagating both objects here was dead
    % work in that mode. The guard above is unchanged and still runs for
    % every mode. Behaviour in 'tracked' and 'perfect' is untouched.
    scenario_at_decision = scenario;
    if ~strcmp(config.feature_mode, 'cdm_sequence')
        stage_timer = tic;
        [X_sat_burn, X_deb_burn] = propagate_training_state( ...
            scenario.X0_sat, scenario.X0_deb, decision_time_s, c_scenario);
        scenario_at_decision.X0_sat = X_sat_burn;
        scenario_at_decision.X0_deb = X_deb_burn;
        scenario_at_decision.t_to_cpa = remaining_time_s;
        timing.decision_propagation_s = toc(stage_timer);
    end
    metadata.feature_mode = config.feature_mode;
    metadata.tracking_seed = NaN;
    metadata.tracking_est_error_sat_m = NaN;
    metadata.tracking_est_error_deb_m = NaN;
    metadata.tracking_mean_nees_sat = NaN;
    metadata.tracking_mean_nees_deb = NaN;
    metadata.label_source = 'truth_oracle';
    metadata.label_information_set = 'simulator truth + proposal covariance';
    label_ready = false;
    if strcmp(config.feature_mode, 'cdm_sequence')
        % One decision-epoch CDM supplies the features and the label, so the
        % surrogate approximates the optimizer rather than the estimator.
        decision_lead_s = config.decision_policy.cdm_decision_lead_s;
        if scenario.t_to_cpa <= decision_lead_s + ...
                config.decision_policy.max_tracking_duration_s
            error('ACAM:InvalidCdmDecisionLead', ...
                  ['Scenario seed %d (%.1f h to TCA) cannot hold the fixed ', ...
                   '%.1f h decision lead plus the %.1f h observation ', ...
                   'window. Shorten the lead for every row rather than ', ...
                   'varying it per scenario.'], seed, scenario.t_to_cpa / 3600, ...
                  decision_lead_s / 3600, ...
                  config.decision_policy.max_tracking_duration_s / 3600);
        end
        stage_timer = tic;
        cdm_sequence = simulate_ekf_cdm_sequence( ...
            scenario, c_scenario, decision_lead_s, ...
            500000 + double(seed), tracking_config);
        timing.ekf_cdm_s = toc(stage_timer);
        stage_timer = tic;
        [features, decision_message] = ...
            build_features_from_cdm(cdm_sequence, []);
        timing.features_s = toc(stage_timer);
        stage_timer = tic;
        [dV_hill, action, final_pc, oracle_info] = ...
            compute_cdm_oracle(decision_message, c_scenario);
        timing.oracle_s = toc(stage_timer);
        metadata.label_source = 'cdm_oracle';
        metadata.label_information_set = oracle_info.label_information_set;
        metadata.tracking_seed = 500000 + double(seed);
        % The scenario proposal covariance selects the miss distance, so it
        % is a sampling proposal and nothing more. The stratum a row
        % actually belongs to is the one implied by the decision-epoch
        % covariance the estimator can really deliver, so record that as
        % authoritative and keep the proposal band only to explain how the
        % row was drawn and to weight it.
        metadata.proposal_pc = scenario.Pc_initial;
        metadata.proposal_pc_band_index = band_index;
        metadata.tracked_pc = features(1);
        metadata.tracked_pc_band_index = pc_band_index(features(1));
        metadata.risk_band_source = 'tracked decision-epoch covariance';
        % Raw decision-epoch geometry, stored not computed: whether the
        % requested band survives into the tracked band depends on the miss
        % distance measured against the tracked covariance, and that
        % comparison cannot be reconstructed from tracked_pc alone. Copies of
        % fields the message already holds, so production pays no arithmetic
        % for them and the row timing stays the production workload.
        metadata.decision_rel_pos_rtn_m = decision_message.relative_position_rtn_m;
        metadata.decision_rel_vel_rtn_mps = decision_message.relative_velocity_rtn_mps;
        metadata.decision_combined_covariance_rtn_m2 = ...
            decision_message.combined_position_covariance_rtn_m2;
        metadata.decision_hbr_m = scenario.hbr_m;
        decision_time_s = scenario.t_to_cpa - decision_lead_s;
        remaining_time_s = decision_lead_s;
        label_ready = true;
    elseif strcmp(config.feature_mode, 'tracked')
        tracking_seed = 500000 + double(seed);
        stage_timer = tic;
        tracking = run_ekf_tracking(scenario, c_scenario, tracking_config, ...
                                    tracking_seed);
        timing.tracking_s = toc(stage_timer);
        if abs(tracking.tracking_duration_s - decision_time_s) > 1e-9
            error('ACAM:TrainingTrackingContractMismatch', ...
                  'Training tracker did not use the shared decision time.');
        end
        estimate = struct( ...
            'X_sat', tracking.X_sat_est, ...
            'X_deb', tracking.X_deb_est, ...
            'P_sat', tracking.P_sat, ...
            'P_deb', tracking.P_deb, ...
            'remaining_time', remaining_time_s);
        features = build_features(scenario, c_scenario, estimate);
        metadata.tracking_seed = tracking_seed;
        metadata.tracking_est_error_sat_m = tracking.est_error_sat_m;
        metadata.tracking_est_error_deb_m = tracking.est_error_deb_m;
        metadata.tracking_mean_nees_sat = tracking.diagnostics.mean_nees_sat;
        metadata.tracking_mean_nees_deb = tracking.diagnostics.mean_nees_deb;
    else
        features = build_features(scenario_at_decision, c_scenario, [], struct( ...
            'time_remaining_s', remaining_time_s));
    end
    if numel(features) ~= numel(feature_names) || any(~isfinite(features))
        error('ACAM:FeatureGenerationFailed', ...
              'Scenario seed %d produced an invalid feature row.', seed);
    end

    if ~label_ready
        stage_timer = tic;
        [dV_hill, action, final_pc, oracle_info] = ...
            compute_deterministic_oracle(scenario_at_decision, c_scenario);
        timing.oracle_s = toc(stage_timer);
    end
    metadata.optimizer_exit_status = oracle_info.exitflag;
    if isfield(oracle_info, 'optimizer_evaluations')
        metadata.optimizer_evaluations = oracle_info.optimizer_evaluations;
    end
    metadata.initial_pc = oracle_info.initial_pc;
    metadata.final_pc = final_pc;
    metadata.optimizer_fidelity = oracle_info.optimizer_fidelity;
    metadata.evaluation_fidelity = oracle_info.evaluation_fidelity;
    metadata.oracle_status = oracle_info.status;
    metadata.oracle_safe = oracle_info.safety_constraint_satisfied;
    metadata.oracle_target_pc = oracle_info.target_pc;
    metadata.decision_time_s = decision_time_s;
    metadata.remaining_time_s = remaining_time_s;
    metadata.decision_frame = 'post_tracking_hill_frame';
    metadata.sampling_weight = numel(config.pc_band_schedule) / ...
        (numel(config.pc_band_labels) * band_counts(band_index));
    metadata.sampling_weight_basis = 'inverse probability for equal Pc bands';

    features_row = reshape(features, 1, []);
    dV_row = reshape(dV_hill, 1, []);
    action = logical(action);
    timing.row_total_s = toc(row_timer);
end

function [X_sat_end, X_deb_end] = propagate_training_state( ...
        X_sat_start, X_deb_start, duration_s, c)
%PROPAGATE_TRAINING_STATE Move both states to the shared decision epoch.
    options = odeset('RelTol', 1e-8, 'AbsTol', 1e-10, ...
                     'Events', @(t, X) earth_collision_event(t, X, c));
    [t_sat, X_sat] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                           [0, duration_s], X_sat_start, options);
    [t_deb, X_deb] = ode45(@(t, X) twoBodyJ2Drag_simple(t, X, c), ...
                           [0, duration_s], X_deb_start, options);
    if abs(t_sat(end) - duration_s) > max(1, 1e-9 * duration_s) || ...
            abs(t_deb(end) - duration_s) > max(1, 1e-9 * duration_s)
        error('ACAM:TrainingDecisionPropagationFailed', ...
              'A training state did not reach the shared decision epoch.');
    end
    X_sat_end = X_sat(end, :)';
    X_deb_end = X_deb(end, :)';
end

function contract = stage6b1_gate_d_contract(project_root)
%STAGE6B1_GATE_D_CONTRACT Frozen development and sealing design.

    if nargin < 1 || isempty(project_root)
        project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end

    contract = struct();
    contract.version = 1;
    contract.stage_label = 'Stage 6b1 Gate D';
    contract.source_document = fullfile(project_root, ...
        'STAGE_6B1_GATE_D_DEVELOPMENT_AND_SEALING_CONTRACT.md');
    contract.source_document_sha256 = ...
        'D16B2178352E238B7C216B0B3DD99F0F40A47FCCFA62416F781C97376450BA7E';
    contract.parent_path = fullfile(project_root, 'outputs', ...
        'stage_6b1_gate_c_artifact_free_preflight_v1', ...
        'stage_6b1_gate_c_results.mat');
    contract.parent_sha256 = ...
        '628370A4CC5581B051E081EF05A177D85C1318BCF1D82BD42A224368E8E40966';
    contract.output_directory = fullfile(project_root, 'outputs', ...
        'stage_6b1_gate_d_design_validation_v2');

    contract.splits = ["train", "calibration", ...
        "development_validation", "sealed_test"];
    contract.families = ["co_orbital", "crossing"];
    contract.arms = ["primary_drag", "srp_sensitivity"];
    contract.geometry_counts = [150, 150; 50, 50; 75, 75; 150, 150];
    contract.expected_split_geometries = [300, 100, 150, 300];
    contract.expected_total_geometries = 850;
    contract.expected_total_rows = 1700;
    contract.risk_bands = [1, 4, 5, 6];
    contract.band_schedule = [1, 4, 5, 5, 6];
    contract.band_counts_per_family = [30, 30, 60, 30; ...
        10, 10, 20, 10; 15, 15, 30, 15; 30, 30, 60, 30];
    contract.seed_starts = [2000001, 2100001; 2200001, 2300001; ...
        2400001, 2500001; 2600001, 2700001];
    contract.prior_reserved_seed_max = 1900005;

    [feature_names, feature_units, feature_version] = ...
        truth_audited_feature_schema();
    contract.features = struct();
    contract.features.schema_name = 'truth_audited_feature_schema';
    contract.features.schema_version = feature_version;
    contract.features.count = numel(feature_names);
    contract.features.names = string(feature_names);
    contract.features.units = string(feature_units);
    contract.features.imputation = 'none';
    contract.features.scaling = 'none';
    contract.features.selection = 'none';
    contract.features.nonfinite_behavior = 'fallback';

    contract.model = struct();
    contract.model.action_classifier = false;
    contract.model.class_name = 'TreeBagger';
    contract.model.direction_classes = ["prograde", "retrograde"];
    contract.model.direction_target = 'optimizer_pre_reserve_direction';
    contract.model.magnitude_target = 'log10_optimizer_pre_reserve_magnitude_mps';
    contract.model.tree_count = 200;
    contract.model.minimum_leaf_size = 5;
    contract.model.sample_with_replacement = true;
    contract.model.surrogate_splits = false;
    contract.model.oob_prediction = false;
    contract.model.oob_importance = false;
    contract.model.classifier_predictors_per_split = 7;
    contract.model.regressor_predictors_per_split = 14;
    contract.model.random_stream = 'twister';
    contract.model.random_seed = 6310;
    contract.model.class_weighting = 'none';
    contract.model.resampling = 'none';
    contract.model.hyperparameter_search = false;

    contract.calibration = struct();
    contract.calibration.rule = ...
        'global_median_observed_minus_predicted_log10_magnitude';
    contract.calibration.refit_forests = false;
    contract.calibration.primary_rows_only = true;
    contract.calibration.minimum_direction_rows = 10;
    contract.calibration.lower_magnitude_mps = 1e-4;
    contract.calibration.upper_magnitude_mps = 2 / 1.10;

    contract.policy = struct();
    contract.policy.trigger = 'unchanged_dual_trigger';
    contract.policy.ml_directions = ["prograde", "retrograde"];
    contract.policy.evaluator = 'complete_maneuver_dependent_covariance';
    contract.policy.reserve_factor = 1.10;
    contract.policy.remediation_pc_threshold = 3.16227766016838e-6;
    contract.policy.truth_unsafe_pc_threshold = 1e-4;
    contract.policy.actuator_limit_mps = 2.0;
    contract.policy.invalid_or_tied_prediction = 'fallback';
    contract.policy.fallback = 'canonical_complete_six_axis_optimizer';
    contract.policy.failed_fallback = 'no_solution_zero_executable_dv';

    contract.composition = struct();
    contract.composition.training_minimum_per_direction = 30;
    contract.composition.calibration_minimum_per_direction = 10;
    contract.composition.development_minimum_per_direction = 15;
    contract.composition.minimum_development_timing_pairs = 30;
    contract.composition.minimum_sealed_timing_pairs = 60;
    contract.composition.minimum_target_availability = 0.90;
    contract.composition.minimum_raw_verifier_pass_rate = 0.70;
    contract.composition.maximum_fallback_rate = 0.30;
    contract.composition.maximum_no_solution_count = 0;
    contract.composition.required_invariant_rate = 1.0;

    contract.safety = struct();
    contract.safety.independent_unit = 'geometry';
    contract.safety.confidence = 0.95;
    contract.safety.one_sided_alpha = 0.05;
    contract.safety.margin = 0.02;
    contract.safety.interval = 'one_sided_clopper_pearson';
    contract.safety.endpoints = ["verified_policy_unsafe", ...
        "always_numerical_unsafe", "surrogate_unsafe_numerical_safe"];
    contract.safety.development_n = 150;
    contract.safety.development_maximum_events = 0;
    contract.safety.sealed_n = 300;
    contract.safety.sealed_maximum_events = 1;
    contract.safety.apply_to_arms_separately = true;
    contract.safety.execution_failure_is_unsafe = true;
    contract.safety.no_solution_is_unsafe = true;

    contract.runtime = struct();
    contract.runtime.minimum_speedup_denominator = 'triggered_geometries';
    contract.runtime.maximum_median_paired_ratio = 0.50;
    contract.runtime.maximum_mean_paired_ratio = 0.75;
    contract.runtime.measurements_per_geometry = 1;
    contract.runtime.alternate_path_order = true;
    contract.runtime.warmup_required = true;
    contract.runtime.maximum_local_workers = 2;
    contract.runtime.development_wall_budget_days = 21;
    contract.runtime.sealed_wall_budget_days = 14;
    contract.runtime.total_wall_budget_days = 35;
    contract.runtime.checkpoint_every_geometries = 1;
    contract.runtime.eta_after_fraction = 0.10;

    contract.delta_v = struct();
    contract.delta_v.analyze_only_after_safety = true;
    contract.delta_v.advancement_gate = false;
    contract.delta_v.bootstrap_unit = 'geometry';
    contract.delta_v.bootstrap_replicates = 10000;
    contract.delta_v.bootstrap_seed = 6311;
    contract.delta_v.fuel_claim_requires_upper_bound_below_zero = true;

    contract.sealing = struct();
    contract.sealing.development_generated_before_sealed = true;
    contract.sealing.lock_required_before_sealed_generation = true;
    contract.sealing.sealed_generation_authorized_by_gate_d = false;
    contract.sealing.sealed_evaluations = 1;
    contract.sealing.outcome_based_stopping = false;
    contract.sealing.seed_replacement = false;
    contract.sealing.failed_execution_treatment = 'unsafe';

    contract.reproducibility = struct();
    contract.reproducibility.transitive_sha256_manifest_required = true;
    contract.reproducibility.environment_manifest_required = true;
    contract.reproducibility.verify_before_resume = true;
    contract.reproducibility.verify_at_policy_lock = true;
    contract.reproducibility.verify_before_sealed = true;
    contract.reproducibility.atomic_geometry_checkpoint = true;

    contract.geometry_plan = make_geometry_plan(contract);
    contract.row_plan = make_row_plan(contract.geometry_plan);
    contract.expected_checks = 38;
end

function plan = make_geometry_plan(contract)
    geometry_id = strings(contract.expected_total_geometries, 1);
    split = strings(contract.expected_total_geometries, 1);
    family = strings(contract.expected_total_geometries, 1);
    seed = zeros(contract.expected_total_geometries, 1);
    risk_band = zeros(contract.expected_total_geometries, 1);
    sealed = false(contract.expected_total_geometries, 1);
    index = 0;
    for split_index = 1:numel(contract.splits)
        for family_index = 1:numel(contract.families)
            count = contract.geometry_counts(split_index, family_index);
            schedule = repmat(contract.band_schedule, 1, ...
                count / numel(contract.band_schedule));
            for k = 1:count
                index = index + 1;
                this_seed = contract.seed_starts(split_index, family_index) ...
                    + k - 1;
                geometry_id(index) = "stage6b1_" + ...
                    contract.splits(split_index) + "_" + ...
                    contract.families(family_index) + "_" + ...
                    string(this_seed);
                split(index) = contract.splits(split_index);
                family(index) = contract.families(family_index);
                seed(index) = this_seed;
                risk_band(index) = schedule(k);
                sealed(index) = contract.splits(split_index) == "sealed_test";
            end
        end
    end
    assert(index == contract.expected_total_geometries);
    plan = table(geometry_id, split, family, seed, risk_band, sealed);
end

function rows = make_row_plan(geometries)
    indices = repelem((1:height(geometries))', 2);
    geometry_id = geometries.geometry_id(indices);
    split = geometries.split(indices);
    family = geometries.family(indices);
    seed = geometries.seed(indices);
    risk_band = geometries.risk_band(indices);
    arm = repmat(["primary_drag"; "srp_sensitivity"], ...
        height(geometries), 1);
    fit_eligible = split == "train" & arm == "primary_drag";
    calibration_eligible = split == "calibration" & ...
        arm == "primary_drag";
    evaluation_only = arm == "srp_sensitivity" | ...
        split == "development_validation" | split == "sealed_test";
    rows = table(geometry_id, split, family, seed, risk_band, arm, ...
        fit_eligible, calibration_eligible, evaluation_only);
end

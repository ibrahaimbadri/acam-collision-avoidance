function [config, tracking_config, band_indices, band_counts] = ...
        training_row_contract(feature_mode, n_total, master_seed)
%TRAINING_ROW_CONTRACT The production configuration for training-row generation.
%
% Single source of the configuration that generate_training_data and the
% pipeline timing benchmark both use, so a benchmark cannot silently measure
% a different workload from the run it is projecting.
%
% Returns the scenario config with its decision policy, the tracking config,
% and the deterministic band schedule for N rows.

    config = scenario_generation_config();
    % Observation contract. Version 1 took ekf_tracking_config() raw, which is
    % the pre-grid default of 500 m / 0.5 m/s, while C1, C2, Stage D, Stage D2,
    % Stage 5a and the terminal reference all run precise_frequent at 30 m /
    % 0.03 m/s. That was drift, not a decision: this file was extracted from
    % generate_training_data verbatim and carried the default across. Aligned
    % at version 2 so the dataset is comparable with the causal evidence and
    % with the Q calibration; see OBSERVATION_CONTRACT_ALIGNMENT_DECISION.md.
    grid = measurement_contract_grid();
    tracking_config = grid.candidates(strcmp({grid.candidates.id}, ...
                                             'precise_frequent')).config;
    % Frozen decisions, recorded here rather than in any one caller so that
    % production cannot silently change them. The development dataset uses the
    % NOMINAL truth model; NRLMSISE remains available for validation subsets
    % and for the causal stages, which set it explicitly.
    config.training_contract_version = 2;
    config.training_truth_model_mode = 'nominal';
    config.truth_model_mode = config.training_truth_model_mode;
    config.training_measurement_contract_id = 'precise_frequent';
    config.decision_policy = struct( ...
        'reserve_before_tca_s', tracking_config.reserve_before_tca_s, ...
        'max_tracking_duration_s', tracking_config.max_tracking_duration_s, ...
        ... % cdm_sequence uses one fixed lead for every row. A per-scenario
        ... % lead would give some rows more drift time than others, which is
        ... % the unmatched-decision-epoch flaw that made earlier Delta-V
        ... % comparisons unfair. Three hours is the lead that ranked best in
        ... % the short-lead operability screen and still fits the two-hour
        ... % observation window inside the six-hour minimum time to TCA.
        'cdm_decision_lead_s', 3 * 3600, ...
        'source', 'measurement_contract_grid:precise_frequent');
    config.feature_mode = feature_mode;
    schedule = config.pc_band_schedule;
    n_bands = numel(config.pc_band_labels);
    band_indices = schedule(mod(0:n_total - 1, numel(schedule)) + 1)';
    band_counts = arrayfun(@(b) nnz(schedule == b), 1:n_bands);
    config.seed = master_seed;
    config.band_schedule = schedule;
    config.sampling_weights_equal_band = numel(schedule) ./ ...
        (n_bands * band_counts);
end

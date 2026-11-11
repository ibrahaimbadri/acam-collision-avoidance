function analyze_training_data(dataset)
%ANALYZE_TRAINING_DATA Print diagnostics and generate the training plots.

    setup_project();
    dataset = validate_dataset_contract(dataset);
    fprintf('========== TRAINING DATA STATISTICS ==========\n');

    c = load_constants();
    model_pc = dataset.X(:, 1);
    truth_pc = vertcat(dataset.scenario_metadata.initial_pc);
    model_distance = dataset.X(:, 3);
    decision = logical(dataset.y_action(:));
    delta_v = vecnorm(dataset.y_dv_hill, 2, 2);
    final_Pc = vertcat(dataset.scenario_metadata.final_pc);

    n = numel(decision);
    n_maneuver = nnz(decision);

    fprintf('Maneuver rate: %.1f%% (%d/%d)\n', ...
            100 * n_maneuver / n, n_maneuver, n);
    if n_maneuver > 0
        fprintf('Avg Delta-V when maneuvering: %.3f m/s\n', ...
                mean(delta_v(decision)));
    else
        fprintf('WARNING: no maneuver examples were generated.\n');
    end

    fprintf('Model-input estimated Pc range: [%.2e, %.2e]\n', ...
            min(model_pc), max(model_pc));
    fprintf('Oracle truth initial Pc range: [%.2e, %.2e]\n', ...
            min(truth_pc), max(truth_pc));
    fprintf('Model-input CPA distance range: [%.1f, %.1f] m\n', ...
            min(model_distance), max(model_distance));
    fprintf('Oracle truth Pc before/after action: %.2e -> %.2e (average)\n', ...
            mean(truth_pc), mean(final_Pc));
    fprintf('==============================================\n');

    high_risk = nnz(truth_pc > c.pc_maneuver_threshold);
    fprintf('\nDiagnostic:\n');
    fprintf('  Truth scenarios above maneuver threshold: %d (%.1f%%)\n', ...
            high_risk, 100 * high_risk / n);
    fprintf('  Maneuvers chosen: %d (%.1f%%)\n', ...
            n_maneuver, 100 * n_maneuver / n);

    plot_training_data_analysis(dataset);
end

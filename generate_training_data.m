function dataset = generate_training_data(n_total, use_parallel, master_seed, ...
                                          stress_flags, progress_options, ...
                                          feature_mode)
%GENERATE_TRAINING_DATA Generate the canonical, physically verified dataset.
%
% Each row is produced by the shared Stage 4 encounter generator, verified
% at nonlinear TCA, and labelled by the fixed deterministic oracle.  The
% default schedule oversamples the two bands around the maneuver threshold;
% sampling weights are retained in scenario_metadata for later reporting.
% feature_mode='tracked' uses the same deterministic simulated Cartesian EKF
% feature path as validation; feature_mode='perfect' is an upper-bound mode.
%
% Both of those label rows with COMPUTE_DETERMINISTIC_ORACLE, which reads
% truth states and the scenario proposal covariance. Under 'tracked' the
% features and the label therefore come from different information sets: the
% model is asked to reproduce a decision made from data it cannot observe,
% which is a state-estimation problem rather than surrogate approximation,
% and it caps achievable accuracy for reasons no amount of training data or
% force-model fidelity can remove.
%
% feature_mode='cdm_sequence' closes that gap. Features and labels are both
% drawn from the same decision-epoch CDM, so the target is what the online
% optimizer would have chosen given the same inputs the model receives. That
% is the contract required by the declared project claim. Truth stays the
% separate audit-only standard for judging whether the maneuver was safe.
% Optional progress checkpoints are written by the pilot runner so long
% parallel jobs expose completed rows and an ETA without changing the final
% dataset contract.

    setup_project();
    if nargin < 1
        n_total = 3000;
    end
    if nargin < 2
        use_parallel = false;
    end
    if nargin < 3
        master_seed = 42;
    end
    if nargin < 4 || isempty(stress_flags)
        stress_flags = nan(n_total, 1);
    end
    if nargin < 5 || isempty(progress_options)
        progress_options = struct('enabled', false);
    end
    if nargin < 6 || isempty(feature_mode)
        feature_mode = 'tracked';
    end

    validateattributes(n_total, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', '>=', 4}, ...
        mfilename, 'n_total');
    validateattributes(use_parallel, {'logical', 'numeric'}, ...
        {'real', 'finite', 'scalar'}, mfilename, 'use_parallel');
    validateattributes(master_seed, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'nonnegative'}, ...
        mfilename, 'master_seed');
    validateattributes(stress_flags, {'numeric', 'logical'}, ...
        {'vector', 'numel', n_total}, mfilename, 'stress_flags');
    stress_flags = double(stress_flags(:));
    if any(~isnan(stress_flags) & ~ismember(stress_flags, [0, 1]))
        error('ACAM:InvalidStressFlags', ...
              'stress_flags must contain only 0, 1, or NaN for random selection.');
    end
    use_parallel = logical(use_parallel);
    progress_options = normalize_progress_options(progress_options);
    validateattributes(feature_mode, {'char', 'string'}, {'scalartext'}, ...
                       mfilename, 'feature_mode');
    feature_mode = lower(char(feature_mode));
    if ~ismember(feature_mode, {'tracked', 'perfect', 'cdm_sequence'})
        error('ACAM:InvalidTrainingFeatureMode', ...
              ['feature_mode must be ''tracked'', ''perfect'', or ', ...
               '''cdm_sequence''.']);
    end

    c = load_constants();
    [feature_names, feature_units, schema_version] = feature_schema();
    % Shared with the pipeline timing benchmark so a benchmark cannot
    % measure a different workload from the run it projects.
    [config, tracking_config, band_indices, band_counts] = ...
        training_row_contract(feature_mode, n_total, master_seed);
    config.requested_core_count = nnz(stress_flags == 0);
    config.requested_stress_count = nnz(stress_flags == 1);
    config.random_stress_count = nnz(isnan(stress_flags));
    config.oracle = struct( ...
        'decision_threshold_pc', c.pc_maneuver_threshold, ...
        'target_pc', c.pc_target_remediation, ...
        'max_maneuver_mps', c.max_maneuver_mps, ...
        'search_directions', {maneuver_search_config().direction_labels}, ...
        'coarse_grid_count', maneuver_search_config().coarse_grid_count, ...
        'refinement_iterations', maneuver_search_config().refinement_iterations, ...
        'optimizer_fidelity', 'J2', ...
        'evaluation_fidelity', 'J2', ...
        'fallback_policy', 'reject_failed_propagation');

    seed_all = master_seed + (1:n_total)';
    X = zeros(n_total, numel(feature_names));
    y_action = false(n_total, 1);
    y_dv_hill = zeros(n_total, 3);
    metadata_cells = cell(n_total, 1);

    % Keep a separate client-side copy for checkpoints.  The final arrays
    % are assigned by parfor only when the loop completes, whereas the
    % DataQueue callback can update this copy as each worker finishes.
    progress_X = nan(size(X));
    progress_y_action = false(size(y_action));
    progress_y_dv_hill = nan(size(y_dv_hill));
    progress_metadata_cells = cell(size(metadata_cells));
    progress_completed = false(n_total, 1);
    generation_timer = tic;
    progress_state = struct( ...
        'status', 'running', ...
        'total_rows', n_total, ...
        'completed_rows', 0, ...
        'elapsed_seconds', 0, ...
        'estimated_remaining_seconds', NaN, ...
        'estimated_total_seconds', NaN, ...
        'rows_per_second', 0, ...
        'checkpoint_count', 0, ...
        'started_at', char(datetime('now')), ...
        'last_checkpoint_at', '', ...
        'error_identifier', '', ...
        'error_message', '');
    checkpoint_enabled = progress_options.enabled;

    if checkpoint_enabled
        write_progress_checkpoint('running', '');
    end

    fprintf('Generating %d verified scenarios (seed %d)...\n', ...
            n_total, master_seed);
    try
        if use_parallel && checkpoint_enabled
            progress_queue = parallel.pool.DataQueue;
            afterEach(progress_queue, @record_progress);
        else
            progress_queue = [];
        end

        if use_parallel
            parfor i = 1:n_total
                [X(i, :), y_action(i), y_dv_hill(i, :), metadata_cells{i}] = ...
                    generate_training_row(config, c, feature_names, ...
                                          band_indices(i), band_counts, ...
                                          seed_all(i), stress_flags(i), ...
                                          tracking_config);
                if checkpoint_enabled
                    send(progress_queue, struct( ...
                        'index', i, ...
                        'features', X(i, :), ...
                        'action', y_action(i), ...
                        'dV_hill', y_dv_hill(i, :), ...
                        'metadata', metadata_cells{i}));
                end
            end
        else
            for i = 1:n_total
                [X(i, :), y_action(i), y_dv_hill(i, :), metadata_cells{i}] = ...
                    generate_training_row(config, c, feature_names, ...
                                          band_indices(i), band_counts, ...
                                          seed_all(i), stress_flags(i), ...
                                          tracking_config);
                if checkpoint_enabled
                    record_progress(struct( ...
                        'index', i, ...
                        'features', X(i, :), ...
                        'action', y_action(i), ...
                        'dV_hill', y_dv_hill(i, :), ...
                        'metadata', metadata_cells{i}));
                elseif mod(i, max(1, floor(n_total / 10))) == 0 || i == n_total
                    fprintf('  %d/%d scenarios\n', i, n_total);
                end
            end
        end
    catch exception
        if progress_options.enabled
            progress_state.status = 'failed';
            progress_state.error_identifier = exception.identifier;
            progress_state.error_message = exception.message;
            write_progress_checkpoint('failed', exception.message);
        end
        rethrow(exception);
    end
    elapsed_s = toc(generation_timer);

    if progress_options.enabled
        % Use the completed client arrays for the final checkpoint.  This
        % also covers DataQueue callbacks that are still being drained when
        % parfor returns.
        progress_X = X;
        progress_y_action = y_action;
        progress_y_dv_hill = y_dv_hill;
        progress_metadata_cells = metadata_cells;
        progress_completed(:) = true;
        write_progress_checkpoint('complete', '');
    end

    scenario_metadata = vertcat(metadata_cells{:});
    dataset = struct( ...
        'X', X, ...
        'y_action', y_action, ...
        'y_dv_hill', y_dv_hill, ...
        'feature_names', {feature_names}, ...
        'feature_units', {feature_units}, ...
        'schema_version', schema_version, ...
        'scenario_metadata', scenario_metadata, ...
        'generator_config', config, ...
        'seed', master_seed, ...
        'created_at', char(datetime('now')));

    validate_dataset_contract(dataset);
    save('training_data.mat', 'dataset', '-v7.3');
    fprintf('Generated and saved %d scenarios in %.1f minutes.\n', ...
            n_total, elapsed_s / 60);
    analyze_training_data(dataset);

    function record_progress(payload)
        row_index = payload.index;
        if progress_completed(row_index)
            return;
        end
        progress_X(row_index, :) = payload.features;
        progress_y_action(row_index) = payload.action;
        progress_y_dv_hill(row_index, :) = payload.dV_hill;
        progress_metadata_cells{row_index} = payload.metadata;
        progress_completed(row_index) = true;

        completed_rows = nnz(progress_completed);
        elapsed_now = toc(generation_timer);
        rows_per_second = completed_rows / max(elapsed_now, eps);
        remaining_s = (n_total - completed_rows) / max(rows_per_second, eps);
        due_by_rows = completed_rows - progress_state.completed_rows >= ...
                      progress_options.checkpoint_interval_rows;
        due_by_time = elapsed_now - progress_state.elapsed_seconds >= ...
                      progress_options.checkpoint_interval_s;
        if completed_rows == n_total || due_by_rows || due_by_time
            write_progress_checkpoint('running', '');
            fprintf(['  Progress: %d/%d (%.1f%%), elapsed %.1f min, ', ...
                     'ETA %.1f min\n'], completed_rows, n_total, ...
                    100 * completed_rows / n_total, elapsed_now / 60, ...
                    remaining_s / 60);
        end
    end

    function write_progress_checkpoint(status, error_message)
        if ~progress_options.enabled
            return;
        end
        elapsed_now = toc(generation_timer);
        completed_rows = nnz(progress_completed);
        rows_per_second = completed_rows / max(elapsed_now, eps);
        if completed_rows == 0
            remaining_s = NaN;
            total_s = NaN;
        else
            remaining_s = (n_total - completed_rows) / rows_per_second;
            total_s = elapsed_now + remaining_s;
        end

        progress_state.status = status;
        progress_state.completed_rows = completed_rows;
        progress_state.elapsed_seconds = elapsed_now;
        progress_state.estimated_remaining_seconds = remaining_s;
        progress_state.estimated_total_seconds = total_s;
        progress_state.rows_per_second = rows_per_second;
        progress_state.checkpoint_count = progress_state.checkpoint_count + 1;
        progress_state.last_checkpoint_at = char(datetime('now'));
        progress_state.error_message = error_message;

        partial_dataset = struct( ...
            'X', progress_X, ...
            'y_action', progress_y_action, ...
            'y_dv_hill', progress_y_dv_hill, ...
            'scenario_metadata_cells', {progress_metadata_cells}, ...
            'completed_mask', progress_completed, ...
            'feature_names', {feature_names}, ...
            'seed', master_seed);
        progress = progress_state;
        progress.completed_indices = find(progress_completed);
        progress.scenario_seeds = seed_all;
        progress.stress_flags = stress_flags;
        progress.partial_dataset = partial_dataset;
        checkpoint_path = progress_options.checkpoint_path;
        checkpoint_dir = fileparts(checkpoint_path);
        if ~isempty(checkpoint_dir) && ~exist(checkpoint_dir, 'dir')
            mkdir(checkpoint_dir);
        end
        temporary_path = [checkpoint_path, '.partial'];
        try
            save(temporary_path, 'progress', '-v7.3');
            movefile(temporary_path, checkpoint_path, 'f');
        catch checkpoint_exception
            fprintf(2, 'Warning: progress checkpoint failed: %s\n', ...
                    checkpoint_exception.message);
        end
        progress_state.completed_rows = completed_rows;
    end
end

function options = normalize_progress_options(options)
%NORMALIZE_PROGRESS_OPTIONS Apply the small checkpoint configuration contract.
    if ~isstruct(options) || ~isscalar(options)
        error('ACAM:InvalidProgressOptions', ...
              'progress_options must be a scalar struct.');
    end
    defaults = struct( ...
        'enabled', false, ...
        'checkpoint_path', 'training_progress.mat', ...
        'checkpoint_interval_s', 60, ...
        'checkpoint_interval_rows', 25);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(options, names{k}) || isempty(options.(names{k}))
            options.(names{k}) = defaults.(names{k});
        end
    end
    validateattributes(options.enabled, {'logical', 'numeric'}, ...
                       {'real', 'finite', 'scalar'}, mfilename, ...
                       'progress_options.enabled');
    validateattributes(options.checkpoint_path, {'char', 'string'}, ...
                       {'scalartext'}, mfilename, ...
                       'progress_options.checkpoint_path');
    validateattributes(options.checkpoint_interval_s, {'numeric'}, ...
                       {'real', 'finite', 'scalar', 'positive'}, mfilename, ...
                       'progress_options.checkpoint_interval_s');
    validateattributes(options.checkpoint_interval_rows, {'numeric'}, ...
                       {'real', 'finite', 'scalar', 'integer', 'positive'}, ...
                       mfilename, 'progress_options.checkpoint_interval_rows');
    options.enabled = logical(options.enabled);
    options.checkpoint_path = char(options.checkpoint_path);
end

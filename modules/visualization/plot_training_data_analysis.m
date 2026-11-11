function plot_training_data_analysis(dataset, output_path)
%PLOT_TRAINING_DATA_ANALYSIS Explain the generated training distribution.

    if nargin < 2
        output_path = 'training_data_analysis.png';
    end
    dataset = validate_dataset_contract(dataset);

    c = load_constants();
    model_pc = max(dataset.X(:, 1), 0);
    truth_pc = max(vertcat(dataset.scenario_metadata.initial_pc), 0);
    model_distance = dataset.X(:, 3);
    decision = logical(dataset.y_action(:));
    delta_v = vecnorm(dataset.y_dv_hill, 2, 2);
    final_Pc = max(vertcat(dataset.scenario_metadata.final_pc), 0);

    n = size(dataset.X, 1);
    n_maneuver = nnz(decision);
    pc_floor = 1e-12;
    model_pc_plot = max(model_pc, pc_floor);
    truth_pc_plot = max(truth_pc, pc_floor);
    final_pc_plot = max(final_Pc, pc_floor);

    fig = figure('Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
                 'Position', [80 80 1500 850], ...
                 'Name', 'ACAM Training Data Analysis');
    tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Training data diagnostics  |  n = %d  |  maneuver = %.1f%%', ...
          n, 100 * n_maneuver / n), 'FontWeight', 'bold');

    % Class balance
    ax = nexttile(tl);
    counts = [n - n_maneuver, n_maneuver];
    bar(ax, counts, 'FaceColor', [0.25 0.55 0.85]);
    ax.XTick = 1:2;
    ax.XTickLabel = {'Stay', 'Maneuver'};
    ylabel(ax, 'Scenarios');
    title(ax, 'Label balance');
    grid(ax, 'on');
    ylim(ax, [0 max(counts) * 1.18 + 1]);
    for k = 1:2
        text(ax, k, counts(k) + max(counts) * 0.03, ...
             sprintf('%d (%.1f%%)', counts(k), 100 * counts(k) / n), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    % Estimated model input versus oracle truth
    ax = nexttile(tl);
    hold(ax, 'on');
    scatter(ax, truth_pc_plot, model_pc_plot, 20, [0.35 0.65 0.85], 'filled');
    plot(ax, [pc_floor 1], [pc_floor 1], 'k:', 'DisplayName', 'Perfect estimate');
    hold(ax, 'off');
    set(ax, 'XScale', 'log', 'YScale', 'log');
    xlim(ax, [pc_floor 1]);
    ylim(ax, [pc_floor 1]);
    xlabel(ax, 'Oracle truth initial P_c');
    ylabel(ax, 'Model-input estimated P_c');
    title(ax, 'Tracking estimate versus oracle truth');
    grid(ax, 'on');

    % Decision versus collision probability
    ax = nexttile(tl);
    hold(ax, 'on');
    scatter(ax, truth_pc_plot(~decision), zeros(nnz(~decision), 1), 18, ...
            [0.25 0.55 0.85], 'filled', 'DisplayName', 'Stay');
    scatter(ax, truth_pc_plot(decision), ones(nnz(decision), 1), 18, ...
            [0.90 0.40 0.20], 'filled', 'DisplayName', 'Maneuver');
    xline(ax, c.pc_maneuver_threshold, '--', 'Decision threshold', ...
          'Color', [0.80 0.15 0.15], ...
          'LineWidth', 1.2, 'HandleVisibility', 'off');
    hold(ax, 'off');
    set(ax, 'XScale', 'log', 'YTick', [0 1], ...
        'YTickLabel', {'Stay', 'Maneuver'}, 'YLim', [-0.25 1.25]);
    xlim(ax, [pc_floor 1]);
    xlabel(ax, 'Oracle truth initial P_c');
    ylabel(ax, 'Training label');
    title(ax, sprintf('Decision versus risk  |  %d below %.0e', ...
          nnz(truth_pc < pc_floor), pc_floor));
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    % Maneuver magnitudes
    ax = nexttile(tl);
    maneuver_delta_v = delta_v(decision);
    if isempty(maneuver_delta_v)
        axis(ax, 'off');
        text(ax, 0.5, 0.5, 'No maneuver examples', ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    else
        histogram(ax, maneuver_delta_v, 20, 'FaceColor', [0.90 0.50 0.25], ...
                  'EdgeColor', 'none');
        hold(ax, 'on');
        xline(ax, mean(maneuver_delta_v), '--', 'LineWidth', 1.2);
        xline(ax, median(maneuver_delta_v), ':', 'LineWidth', 1.2);
        hold(ax, 'off');
        xlabel(ax, '\DeltaV (m/s)');
        ylabel(ax, 'Maneuver scenarios');
        title(ax, sprintf('Maneuver magnitude  |  mean %.3f, median %.3f m/s', ...
              mean(maneuver_delta_v), median(maneuver_delta_v)));
        if max(maneuver_delta_v) > 0
            xlim(ax, [0, 1.2 * max(maneuver_delta_v)]);
        end
        grid(ax, 'on');
    end

    % Initial versus final risk
    ax = nexttile(tl);
    hold(ax, 'on');
    scatter(ax, truth_pc_plot(~decision), final_pc_plot(~decision), 18, ...
            [0.25 0.55 0.85], 'filled', 'DisplayName', 'Stay');
    scatter(ax, truth_pc_plot(decision), final_pc_plot(decision), 18, ...
            [0.90 0.40 0.20], 'filled', 'DisplayName', 'Maneuver');
    plot(ax, [pc_floor 1], [pc_floor 1], 'k:', 'DisplayName', 'No change');
    xline(ax, c.pc_maneuver_threshold, '--', 'Color', [0.80 0.15 0.15], ...
          'HandleVisibility', 'off');
    yline(ax, c.pc_maneuver_threshold, '--', 'Color', [0.80 0.15 0.15], ...
          'HandleVisibility', 'off');
    hold(ax, 'off');
    set(ax, 'XScale', 'log', 'YScale', 'log');
    xlim(ax, [pc_floor 1]);
    ylim(ax, [pc_floor 1]);
    xlabel(ax, 'Oracle truth initial P_c');
    ylabel(ax, 'Oracle truth final P_c');
    title(ax, 'Truth risk before and after the selected action');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    % Numeric summary
    ax = nexttile(tl);
    axis(ax, 'off');
    summary = sprintf([ ...
        'DATA SUMMARY\n\n' ...
        'Rows:                 %d\n' ...
        'Stay / maneuver:      %d / %d\n' ...
        'Maneuver rate:        %.1f%%\n\n' ...
        'Estimated input P_c:  %.2e to %.2e\n' ...
        'Truth initial P_c:    %.2e to %.2e\n' ...
        'Truth final P_c:      %.2e to %.2e\n' ...
        'Input distance range: %.1f to %.1f m\n' ...
        'Maneuver Delta-V mean:  %.3f m/s\n' ...
        'Maneuver Delta-V median: %.3f m/s\n\n' ...
        'Plot floor: P_c < %.0e is shown at the floor.'], ...
        n, n - n_maneuver, n_maneuver, 100 * n_maneuver / n, ...
        min(model_pc), max(model_pc), min(truth_pc), max(truth_pc), ...
        min(final_Pc), max(final_Pc), min(model_distance), max(model_distance), ...
        safe_mean(maneuver_delta_v), ...
        safe_median(maneuver_delta_v), pc_floor);
    text(ax, 0.02, 0.98, summary, 'VerticalAlignment', 'top', ...
         'FontName', 'Consolas', 'FontSize', 11);

    exportgraphics(fig, output_path, 'Resolution', 180);
    fprintf('Saved plot: %s\n', output_path);
end

function value = safe_mean(values)
    value = 0;
    if ~isempty(values)
        value = mean(values);
    end
end

function value = safe_median(values)
    value = 0;
    if ~isempty(values)
        value = median(values);
    end
end

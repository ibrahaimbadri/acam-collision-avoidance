function plot_model_results(model, results, output_path)
%PLOT_MODEL_RESULTS Explain held-out Random Forest performance.

    if nargin < 3
        output_path = 'model_results.png';
    end

    importance = model.OOBPermutedPredictorDeltaError(:);
    [feature_names, ~, ~] = feature_schema();
    n_features = min(numel(importance), numel(feature_names));
    importance = importance(1:n_features);
    feature_names = feature_names(1:n_features);
    importance(~isfinite(importance)) = 0;
    [importance, order] = sort(importance, 'descend');
    feature_names = feature_names(order);

    cm = results.confusion_matrix;
    n_test = sum(cm(:));
    row_totals = sum(cm, 2);
    row_percent = 100 * cm ./ max(row_totals, 1);

    metric_names = {'Train accuracy', 'Test accuracy', 'Precision', ...
                    'Recall', 'F1 score'};
    metric_values = 100 * [results.train_accuracy / 100, ...
                           results.test_accuracy / 100, results.precision, ...
                           results.recall, results.f1];

    fig = figure('Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
                 'Position', [80 80 1500 850], ...
                 'Name', 'ACAM Model Results');
    tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Random Forest evaluation  |  held-out test n = %d', n_test), ...
          'FontWeight', 'bold');

    % Feature importance
    ax = nexttile(tl);
    barh(ax, importance, 'FaceColor', [0.25 0.55 0.85]);
    ax.YTick = 1:n_features;
    ax.YTickLabel = feature_names;
    ax.YDir = 'reverse';
    xlabel(ax, 'OOB permutation importance');
    title(ax, 'What the model uses');
    grid(ax, 'on');

    % Confusion matrix with row percentages
    ax = nexttile(tl);
    imagesc(ax, cm);
    axis(ax, 'image');
    colormap(ax, [0.96 0.96 0.96; 0.35 0.65 0.90]);
    ax.XTick = 1:2;
    ax.YTick = 1:2;
    ax.XTickLabel = {'Stay', 'Maneuver'};
    ax.YTickLabel = {'Stay', 'Maneuver'};
    xlabel(ax, 'Predicted class');
    ylabel(ax, 'True class');
    title(ax, sprintf('Held-out confusion matrix  |  n = %d', n_test));
    for row = 1:size(cm, 1)
        for col = 1:size(cm, 2)
            text(ax, col, row, sprintf('%d\n(%.1f%%)', cm(row, col), ...
                 row_percent(row, col)), 'HorizontalAlignment', 'center', ...
                 'FontWeight', 'bold', 'Color', [0.05 0.05 0.05]);
        end
    end

    % Metrics
    ax = nexttile(tl);
    bar(ax, metric_values, 'FaceColor', [0.45 0.75 0.30]);
    ax.XTick = 1:numel(metric_values);
    ax.XTickLabel = metric_names;
    ax.XTickLabelRotation = 25;
    ylabel(ax, 'Score (%)');
    title(ax, 'Performance metrics');
    ylim(ax, [0 105]);
    grid(ax, 'on');
    for k = 1:numel(metric_values)
        text(ax, k, metric_values(k) + 2, sprintf('%.1f%%', metric_values(k)), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    % Class counts
    ax = nexttile(tl);
    class_counts = [cm(1, 1) + cm(1, 2), cm(2, 1) + cm(2, 2)];
    bar(ax, class_counts, 'FaceColor', [0.70 0.55 0.85]);
    ax.XTick = 1:2;
    ax.XTickLabel = {'Stay', 'Maneuver'};
    ylabel(ax, 'Held-out scenarios');
    title(ax, 'Test-set class composition');
    grid(ax, 'on');
    ylim(ax, [0 max(class_counts) * 1.18 + 1]);
    for k = 1:2
        text(ax, k, class_counts(k) + max(class_counts) * 0.03, ...
             sprintf('%d (%.1f%%)', class_counts(k), ...
             100 * class_counts(k) / max(n_test, 1)), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    % Error interpretation
    ax = nexttile(tl);
    axis(ax, 'off');
    false_positive = cm(1, 2);
    false_negative = cm(2, 1);
    summary = sprintf([ ...
        'MODEL SUMMARY\n\n' ...
        'Algorithm: Random Forest\n' ...
        'Trees: 100\n' ...
        'Miss cost ratio: %.1f:1\n' ...
        'Train time: %.1f s\n\n' ...
        'Test accuracy: %.1f%%\n' ...
        'Precision:      %.3f\n' ...
        'Recall:         %.3f\n' ...
        'F1 score:       %.3f\n\n' ...
        'False alarms:   %d\n' ...
        'Missed maneuvers: %d'], ...
        results.missed_maneuver_cost, results.train_time, ...
        results.test_accuracy, results.precision, ...
        results.recall, results.f1, false_positive, false_negative);
    if isfield(results, 'regression')
        regression = results.regression;
        summary = sprintf('%s\n\nDELTA-V REGRESSORS\n', summary);
        summary = sprintf([ ...
            '%sTarget: oracle maneuver rows only\n' ...
            'Test MAE [R/T/H]: %.4g / %.4g / %.4g m/s\n' ...
            'Test RMSE [R/T/H]: %.4g / %.4g / %.4g m/s\n' ...
            'Test maneuver rows: %d'], ...
            summary, regression.test_mae_mps(1), regression.test_mae_mps(2), ...
            regression.test_mae_mps(3), regression.test_rmse_mps(1), ...
            regression.test_rmse_mps(2), regression.test_rmse_mps(3), ...
            regression.n_test_maneuver);
    end
    text(ax, 0.02, 0.98, summary, 'VerticalAlignment', 'top', ...
         'FontName', 'Consolas', 'FontSize', 9);

    % Use the last tile for a concise interpretation.
    ax = nexttile(tl);
    axis(ax, 'off');
    interpretation = sprintf([ ...
        'READING THIS FIGURE\n\n' ...
        'The confusion matrix is measured only on data\n' ...
        'that were not used to fit the forest.\n\n' ...
        'Recall is especially important here: a missed\n' ...
        'maneuver is more dangerous than a false alarm.\n\n' ...
        'Use the validation figure to check whether this\n' ...
        'classification quality becomes useful guidance.']);
    text(ax, 0.02, 0.98, interpretation, 'VerticalAlignment', 'top', ...
         'FontSize', 11);

    exportgraphics(fig, output_path, 'Resolution', 180);
    fprintf('Saved plot: %s\n', output_path);
end

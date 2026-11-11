function plot_validation_results(results, output_path)
%PLOT_VALIDATION_RESULTS Compare validation methods without hiding scale.

    if nargin < 2
        output_path = 'validation_results.png';
    end
    required = {'perfect', 'with_KF', 'baseline'};
    for k = 1:numel(required)
        if ~isfield(results, required{k})
            error('ACAM:InvalidValidationResults', ...
                  'Missing results.%s.', required{k});
        end
    end

    if isfield(results, 'oracle') && isfield(results, 'raw_ml') && ...
            isfield(results, 'safeguarded_ml')
        methods = {'Oracle', 'Raw ML', 'Safeguarded ML', ...
                   'Tracked-Pc rule'};
        values = {results.oracle, results.raw_ml, ...
                  results.safeguarded_ml, results.baseline};
        primary_index = 3;
        baseline_index = 4;
        tracked_index = 3;
    else
        methods = {'Perfect ML', 'ML + KF', 'Baseline'};
        values = {results.perfect, results.with_KF, results.baseline};
        primary_index = 2;
        baseline_index = 3;
        tracked_index = 2;
    end
    n_methods = numel(methods);
    n = size(values{1}, 1);
    success = cellfun(@(x) x(:, 1), values, 'UniformOutput', false);
    fuel = cellfun(@(x) x(:, 2), values, 'UniformOutput', false);
    final_pc = cellfun(@(x) max(x(:, 3), 0), values, 'UniformOutput', false);
    ml_fuel = fuel{primary_index};
    baseline_fuel = fuel{baseline_index};
    fuel_savings = baseline_fuel - ml_fuel;
    both_success = logical(success{primary_index}) & ...
                   logical(success{baseline_index});
    comparison_valid = false;
    if isfield(results, 'policy_comparison')
        comparison_valid = ...
            results.policy_comparison.headline_fuel_savings_valid;
    end
    pc_floor = 1e-12;
    if isfield(results, 'policy_contract')
        success_threshold = results.policy_contract.success_threshold_pc;
        remediation_target = results.policy_contract.remediation_target_pc;
    else
        success_threshold = 1e-4;
        remediation_target = 10^(-5.5);
    end

    success_rate = 100 * cellfun(@mean, success);
    success_rate = success_rate(:);
    success_ci = zeros(n_methods, 2);
    for k = 1:n_methods
        success_ci(k, :) = wilson_interval(sum(success{k}), n) * 100;
    end
    success_error = [(success_rate - success_ci(:, 1))'; ...
                     (success_ci(:, 2) - success_rate)'];

    fuel_mean = cellfun(@mean, fuel);
    fuel_std = cellfun(@std, fuel);
    fuel_se = fuel_std / sqrt(max(n, 1));
    fuel_error = 1.96 * fuel_se;

    fig = figure('Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
                 'Position', [60 60 1550 900], ...
                 'Name', 'ACAM Validation Results');
    tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Collision-avoidance validation  |  n = %d scenarios', n), ...
          'FontWeight', 'bold');

    % Success rates with a confidence interval, not a misleading zoom.
    ax = nexttile(tl);
    bar(ax, success_rate, 'FaceColor', [0.30 0.68 0.35]);
    hold(ax, 'on');
    errorbar(ax, 1:n_methods, success_rate', success_error(1, :), success_error(2, :), ...
             'k.', 'LineWidth', 1.4, 'CapSize', 8);
    hold(ax, 'off');
    ax.XTick = 1:n_methods;
    ax.XTickLabel = methods;
    ylabel(ax, 'Success rate (%)');
    title(ax, 'Safety outcome  |  95% binomial interval');
    ylim(ax, [0 105]);
    grid(ax, 'on');
    for k = 1:n_methods
        label_y = success_rate(k) + 3;
        if label_y > 94
            label_y = 90;
        end
        text(ax, k, label_y, ...
             sprintf('%.1f%%\n(%d fail)', success_rate(k), nnz(~success{k})), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    % Fuel means with per-scenario spread.
    ax = nexttile(tl);
    bar(ax, fuel_mean, 'FaceColor', [0.90 0.50 0.25]);
    hold(ax, 'on');
    errorbar(ax, 1:n_methods, fuel_mean, fuel_error, 'k.', 'LineWidth', 1.4, ...
             'CapSize', 8);
    for k = 1:n_methods
        x = k + 0.12 * linspace(-1, 1, n)';
        scatter(ax, x, fuel{k}, 10, [0.15 0.15 0.15], 'filled', ...
                'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
    end
    hold(ax, 'off');
    ax.XTick = 1:n_methods;
    ax.XTickLabel = methods;
    ylabel(ax, '\DeltaV used (m/s)');
    title(ax, 'Fuel use  |  mean +/- 1.96 SE');
    ylim(ax, [0 max([fuel_mean + fuel_error, eps]) * 1.25]);
    ytickformat(ax, '%.2g');
    grid(ax, 'on');
    for k = 1:n_methods
        text(ax, k, fuel_mean(k) + max(fuel_error(k), max(fuel_mean) * 0.04), ...
             sprintf('%.2e', fuel_mean(k)), 'HorizontalAlignment', 'center', ...
             'FontWeight', 'bold');
    end

    % Final risk as ordered values, rather than a histogram that hides n.
    ax = nexttile(tl);
    hold(ax, 'on');
    styles = {'-', '-', '-', '-'};
    colors = [0.35 0.35 0.35; 0.80 0.35 0.15; ...
              0.15 0.40 0.85; 0.85 0.25 0.20];
    for k = 1:n_methods
        y = final_pc{k};
        y(~isfinite(y)) = 1;
        y = sort(max(y, pc_floor));
        plot(ax, 1:n, y, [styles{k} 'o'], 'Color', colors(k, :), ...
             'LineWidth', 1.4, 'MarkerSize', 4, ...
             'DisplayName', methods{k});
    end
    threshold_line = yline(ax, success_threshold, '--', ...
                           'Color', [0.75 0.10 0.10], ...
                           'LineWidth', 1.2);
    threshold_line.DisplayName = 'Safety threshold';
    target_line = yline(ax, remediation_target, ':', ...
                        'Color', [0.35 0.20 0.65], ...
                        'LineWidth', 1.2);
    target_line.DisplayName = 'Remediation target';
    hold(ax, 'off');
    set(ax, 'YScale', 'log');
    xlabel(ax, 'Scenario rank (lowest P_c first)');
    ylabel(ax, 'Final collision probability, P_c');
    title(ax, sprintf('Final risk  |  %d values below %.0e', ...
          sum(cellfun(@(x) nnz(x < pc_floor), final_pc)), pc_floor));
    legend(ax, 'Location', 'best');
    xlim(ax, [0.5 max(n, 1) + 0.5]);
    grid(ax, 'on');

    % Paired fuel comparison: only jointly safe cases support fuel comparison.
    ax = nexttile(tl);
    scatter(ax, baseline_fuel(both_success), ml_fuel(both_success), 24, ...
            [0.15 0.40 0.85], 'filled', 'DisplayName', 'Both safe');
    hold(ax, 'on');
    max_fuel = max([baseline_fuel; ml_fuel; eps]);
    plot(ax, [0 max_fuel], [0 max_fuel], 'k:', 'DisplayName', 'Equal fuel');
    hold(ax, 'off');
    xlabel(ax, 'Baseline \DeltaV (m/s)');
    ylabel(ax, sprintf('%s Delta-V (m/s)', methods{primary_index}));
    if comparison_valid
        pairing_title = sprintf('Fuel pairing | mean saving %.2e m/s', ...
                                mean(fuel_savings));
    else
        pairing_title = sprintf(['Fuel pairing | %d both-safe; headline ', ...
                                 'saving not comparable'], nnz(both_success));
    end
    title(ax, pairing_title);
    axis(ax, 'square');
    xlim(ax, [0 max_fuel * 1.05 + eps]);
    ylim(ax, [0 max_fuel * 1.05 + eps]);
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    % Estimation error against fuel and success.
    ax = nexttile(tl);
    est_error = values{tracked_index}(:, 4) / 1000;
    hold(ax, 'on');
    scatter(ax, est_error(success{tracked_index} == 0), ...
            ml_fuel(success{tracked_index} == 0), 28, ...
            [0.85 0.20 0.20], 'x', 'LineWidth', 1.5, 'DisplayName', 'Failure');
    scatter(ax, est_error(success{tracked_index} == 1), ...
            ml_fuel(success{tracked_index} == 1), 28, ...
            [0.20 0.55 0.30], 'o', 'filled', 'DisplayName', 'Success');
    hold(ax, 'off');
    xlabel(ax, 'EKF position error (km)');
    ylabel(ax, sprintf('%s Delta-V (m/s)', methods{tracked_index}));
    title(ax, sprintf('Estimation uncertainty versus %s fuel', ...
                      methods{tracked_index}));
    ytickformat(ax, '%.2g');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    % Cumulative expenditure is descriptive unless safety outcomes match.
    ax = nexttile(tl);
    plot(ax, cumsum(ml_fuel), '-o', 'Color', [0.15 0.40 0.85], ...
         'LineWidth', 1.8, 'MarkerSize', 4, ...
         'DisplayName', methods{primary_index});
    hold(ax, 'on');
    plot(ax, cumsum(baseline_fuel), '-o', 'Color', [0.85 0.25 0.20], ...
         'LineWidth', 1.8, 'MarkerSize', 4, 'DisplayName', 'Baseline');
    hold(ax, 'off');
    xlabel(ax, 'Scenario index');
    ylabel(ax, 'Cumulative \DeltaV (m/s)');
    if comparison_valid
        cumulative_title = sprintf('Cumulative Delta-V | saving %.2e m/s', ...
                                   sum(fuel_savings));
    else
        cumulative_title = 'Cumulative Delta-V | descriptive; safety differs';
    end
    title(ax, cumulative_title);
    ytickformat(ax, '%.2g');
    legend(ax, 'Location', 'best');
    xlim(ax, [0.5 max(n, 1) + 0.5]);
    grid(ax, 'on');

    exportgraphics(fig, output_path, 'Resolution', 180);
    fprintf('Saved plot: %s\n', output_path);
end

function interval = wilson_interval(successes, n)
%WILSON_INTERVAL Approximate 95% interval for a binomial proportion.
    if n < 1
        interval = [0 0];
        return;
    end
    z = 1.96;
    p = successes / n;
    denominator = 1 + z^2 / n;
    center = (p + z^2 / (2 * n)) / denominator;
    half_width = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator;
    interval = [max(0, center - half_width), min(1, center + half_width)];
end

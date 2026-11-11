function plot_baseline_sweep(results, output_path)
%PLOT_BASELINE_SWEEP Show the predeclared fixed-magnitude rule sweep.

    if nargin < 2
        output_path = 'baseline_sweep.png';
    end
    required = {'baseline_sweep', 'baseline_magnitudes_mps'};
    for k = 1:numel(required)
        if ~isfield(results, required{k})
            error('ACAM:InvalidBaselineSweep', ...
                  'Validation results are missing %s.', required{k});
        end
    end

    magnitudes = results.baseline_magnitudes_mps(:);
    sweep = results.baseline_sweep;
    n = size(sweep, 1);
    success_rate = 100 * squeeze(mean(sweep(:, 1, :), 1));
    mean_fuel = squeeze(mean(sweep(:, 2, :), 1));
    success_rate = success_rate(:);
    mean_fuel = mean_fuel(:);
    trigger_count = nan(size(magnitudes));
    if isfield(results, 'baseline_triggered')
        trigger_count = sum(results.baseline_triggered, 1)';
    end

    fig = figure('Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
                 'Position', [100 100 1200 520], ...
                 'Name', 'Fixed Baseline Sweep');
    tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', ...
                     'Padding', 'compact');
    title(tl, sprintf(['Tracked-Pc threshold + fixed prograde sweep  |  ', ...
                      'n = %d scenarios'], n), ...
          'FontWeight', 'bold');

    ax = nexttile(tl);
    plot(ax, magnitudes, success_rate, 'o-', 'LineWidth', 1.8, ...
         'Color', [0.85 0.25 0.20], 'MarkerFaceColor', [0.85 0.25 0.20]);
    xlabel(ax, 'Fixed prograde Delta-V (m/s)');
    ylabel(ax, 'Basic safety success rate (%)');
    ylim(ax, [0 105]);
    grid(ax, 'on');
    for k = 1:numel(magnitudes)
        text(ax, magnitudes(k), success_rate(k) + 3, ...
            baseline_label(success_rate(k), trigger_count(k), n), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    ax = nexttile(tl);
    plot(ax, magnitudes, mean_fuel, 'o-', 'LineWidth', 1.8, ...
         'Color', [0.15 0.40 0.85], 'MarkerFaceColor', [0.15 0.40 0.85]);
    xlabel(ax, 'Fixed prograde Delta-V (m/s)');
    ylabel(ax, 'Mean Delta-V used (m/s)');
    grid(ax, 'on');
    for k = 1:numel(magnitudes)
        text(ax, magnitudes(k), mean_fuel(k), ...
             sprintf('  %.3g', mean_fuel(k)), 'VerticalAlignment', 'bottom');
    end

    exportgraphics(fig, output_path, 'Resolution', 180);
    fprintf('Saved plot: %s\n', output_path);
end

function label = baseline_label(success_rate, trigger_count, n)
    if isfinite(trigger_count)
        label = sprintf('%.1f%%\n%d/%d triggers', ...
                        success_rate, trigger_count, n);
    else
        label = sprintf('%.1f%%', success_rate);
    end
end

function plot_ekf_diagnostics(results, output_path)
%PLOT_EKF_DIAGNOSTICS Show NEES, NIS, covariance, and tracking diagnostics.

    if nargin < 2
        output_path = 'ekf_diagnostics.png';
    end
    if ~isfield(results, 'estimation_diagnostics') || ...
            isempty(results.estimation_diagnostics)
        error('ACAM:InvalidEkfDiagnostics', ...
              'Validation results do not contain EKF diagnostics.');
    end

    d = results.estimation_diagnostics;
    n = numel(d);
    expected = d(1).expected_nees;
    nees_sat = [d.mean_nees_sat]';
    nees_deb = [d.mean_nees_deb]';
    nis_sat = [d.mean_nis_sat]';
    nis_deb = [d.mean_nis_deb]';
    trace_sat = [d.posterior_trace_sat]';
    trace_deb = [d.posterior_trace_deb]';
    error_sat = [d.est_error_sat_m]';
    error_deb = [d.est_error_deb_m]';
    observations = [d.num_observations_sat]';

    fig = figure('Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
                 'Position', [80 80 1450 850], 'Name', 'EKF Diagnostics');
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('EKF consistency diagnostics  |  n = %d  |  %s', ...
          n, results.measurement_model), 'FontWeight', 'bold');

    ax = nexttile(tl);
    hold(ax, 'on');
    plot(ax, 1:n, nees_sat, 'o-', 'DisplayName', 'Satellite NEES');
    plot(ax, 1:n, nees_deb, 's-', 'DisplayName', 'Debris NEES');
    plot(ax, [1, n], [expected, expected], 'k--', ...
         'DisplayName', 'Expected 6');
    plot(ax, 1:n, nis_sat, '^-', 'DisplayName', 'Satellite NIS');
    plot(ax, 1:n, nis_deb, 'v-', 'DisplayName', 'Debris NIS');
    hold(ax, 'off');
    xlabel(ax, 'Scenario');
    ylabel(ax, 'Normalized squared error');
    title(ax, 'NEES / innovation NIS consistency');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    ax = nexttile(tl);
    semilogy(ax, 1:n, max(trace_sat, eps), 'o-', ...
             'DisplayName', 'Satellite posterior trace');
    hold(ax, 'on');
    semilogy(ax, 1:n, max(trace_deb, eps), 's-', ...
             'DisplayName', 'Debris posterior trace');
    hold(ax, 'off');
    xlabel(ax, 'Scenario');
    ylabel(ax, 'Trace of 6x6 covariance');
    title(ax, 'Posterior uncertainty');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');

    ax = nexttile(tl);
    scatter(ax, error_sat, error_deb, 28, observations, 'filled');
    xlabel(ax, 'Satellite final position error (m)');
    ylabel(ax, 'Debris final position error (m)');
    title(ax, 'Both-object estimation error');
    color_bar = colorbar(ax);
    color_bar.Label.String = 'Observations';
    grid(ax, 'on');

    ax = nexttile(tl);
    histogram(ax, observations, 'FaceColor', [0.25 0.55 0.85]);
    xlabel(ax, 'Observations per object');
    ylabel(ax, 'Scenarios');
    title(ax, sprintf('Deterministic visibility schedule  |  median %.0f', ...
          median(observations)));
    grid(ax, 'on');

    exportgraphics(fig, output_path, 'Resolution', 180);
    fprintf('Saved plot: %s\n', output_path);
end

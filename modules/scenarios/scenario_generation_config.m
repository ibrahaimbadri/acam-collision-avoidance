function config = scenario_generation_config()
%SCENARIO_GENERATION_CONFIG Deterministic physical encounter configuration.

    config.version = 6;
    config.primary_altitude_range_m = [350e3, 700e3];
    config.primary_eccentricity_range = [0, 0.005];
    config.inclination_range_deg = [0, 98];
    config.core_time_to_tca_s = [6, 12, 24, 48, 72] * 3600;
    config.stress_time_to_tca_s = [5, 7] * 86400;
    config.stress_fraction = 0.20;
    config.hbr_range_m = [2, 20];
    config.mass_range_kg = [100, 600];
    % Stage-A physical-property contract. This chooses a fixed causal
    % sensitivity stratum, not a population distribution. New experiments
    % must override it deliberately when comparing differential dynamics.
    config.physical_property_contract_version = 1;
    config.physical_property_mode = 'fixed_strata';
    config.physical_property_stratum = 'matched';
    % Stage-B truth path. The default remains nominal so existing callers do
    % not silently acquire a high-fidelity model. Causal runs must override
    % this field before generation and receive fresh seeds.
    config.truth_model_contract_version = 1;
    config.truth_model_mode = 'nominal';
    config.space_weather_mode = 'matlab_defaults';
    config.space_weather_seed_offset = 9180001;
    config.truth_epoch_utc = datetime(2025, 3, 20, 12, 0, 0, ...
                                      'TimeZone', 'UTC');
    % Encounter families. 'co_orbital' is the original study family: the
    % debris shares the target's orbit to within a few m/s, the miss vector
    % is radial, and the relative velocity is along-track. Every burn the
    % oracle finds in that family is necessarily prograde or retrograde.
    %
    % 'crossing' is the generalisation stratum. The debris velocity is the
    % target's velocity rotated about the radial axis by a crossing angle,
    % which preserves radius, speed, and flight-path angle, so the debris is
    % on a legitimate orbit of the same size and shape in a different plane.
    % Two near-circular LEO orbits crossing at angle theta give a relative
    % speed of 2*v*sin(theta/2), i.e. kilometres per second, matching real
    % debris conjunctions. The miss direction is then sampled uniformly in
    % the plane perpendicular to the relative velocity, so the RTN miss
    % components are genuinely three-dimensional.
    config.encounter_families = {'co_orbital', 'crossing'};
    config.crossing_fraction = 0.25;
    config.crossing_angle_range_deg = [20, 160];
    config.relative_speed_range_mps = [0.5, 20];
    % Proposal covariance, per encounter family. Contract version 6.
    %
    % Version 5 sampled flat ranges of 3-15 / 5-20 / 8-25 m with CROSS-TRACK
    % largest. That is both 3-4x too small overall and the wrong shape: the
    % measured decision-epoch error is ALONG-TRACK dominant by about 10x.
    % Because a row's authoritative band is recomputed from the tracked
    % covariance (see item 8), a proposal that does not approximate that
    % covariance cannot target a band at all -- v5 produced a
    % requested-to-tracked band Spearman of -0.049, i.e. no information.
    %
    % Fitted to the MEASURED combined decision-epoch position covariance in
    % outputs/proposal_surrogate_fit_v1/ (30 scenarios per family, fresh seed
    % blocks 540001+/550001+, training contract v2). The fit measured
    % COMBINED sigma; these are PER-OBJECT sigmas, obtained by dividing by
    % sqrt(1 + k^2) for the debris factors k = 1.15 / 0.90 / 1.25 applied
    % below, so that C_sat + C_deb reproduces the measured combined value.
    % Ranges are the p10-p90 of the fit.
    %
    % Conditional on process_noise_scale = 1.0. Stage 5a selected no Q;
    % across its candidate grid the tracked sigma moves about 1.4x and across
    % the plausible low-Q range about 3%, which is inside the precision a
    % sampling proposal needs.
    flat_range = @(r, t, h) struct( ...
        'radial_m', r, 'tangential_m', t, 'cross_track_m', h);
    config.proposal_sigma_ranges = struct( ...
        'co_orbital', flat_range([3.33, 3.62], [34.29, 39.42], [3.25, 3.60]), ...
        'crossing',   flat_range([3.35, 3.61], [25.01, 36.61], [8.83, 20.99]));
    config.min_perigee_altitude_m = 300e3;
    config.tca_bracket_half_width_s = 1800;
    % TCA acceptance, contract version 3. Two earlier formulations were
    % regime-dependent and are retained as reported diagnostics only:
    %   v1  normalised orthogonality cosine, 1e-6. Scales with relative
    %       speed over miss distance, so unreachable at km/s.
    %   v2  residual time offset, 1e-3 s. Comparable across speeds but not
    %       across integration lengths; rejected 62 of 120 long-arc crossing
    %       cases whose miss geometry was accurate to under 2 m.
    % The gate is now the induced miss-distance error in metres, alongside
    % the miss-distance budget it must stay inside. 1.0 m is a predeclared
    % numerical error budget: 10% of tca_miss_distance_tolerance_m. It is
    % provisional until the version-3 solver is shown to meet it
    % consistently across both encounter families and both timing ranges.
    % It must not be widened to obtain a desired crossing yield.
    config.tca_orthogonality_tolerance = 1e-6;      % diagnostic only
    config.tca_time_offset_tolerance_s = 1e-3;      % diagnostic only
    config.tca_induced_miss_error_tolerance_m = 1.0;  % acceptance gate
    % Bump whenever FIND_TCA's bracketing or refinement changes, even if
    % nothing else in this file does. Recorded in pool checkpoints so a
    % stale checkpoint cannot be resumed across a solver change.
    config.tca_solver_contract_version = 3;

    % Propagation accuracy for the scenario round trip. The requested CPA
    % state is back-propagated to epoch and then forward-propagated while
    % TCA is reconstructed, so both legs must use the same tolerance or the
    % round-trip error is not attributable.
    %
    % Version 2 selected 1e-10/1e-12 from RUN_PROPAGATION_TOLERANCE_SWEEP
    % (outputs/propagation_tolerance_sweep_v3), 60 paired seeds across both
    % encounter families and both timing ranges, against a rule declared
    % before the results were read.
    %
    % 1e-8 was rejected: crossing at 48-72 h accepted only 20 of 60, with 30
    % miss-distance exceedances and a maximum miss error of 104.5 m against
    % the 10 m budget, and a round-trip maximum of 284 m against the 100 m
    % budget.
    %
    % 1e-10 passes everywhere: 60 of 60 single-attempt acceptance in all
    % four cells, zero exceedances on both gates, round-trip maximum 10.8 m
    % and miss-error maximum 2.99 m, so roughly 9x and 3.3x margin.
    %
    % 1e-12 was rejected as unnecessary, not as insufficient: across all
    % four cells it produced zero additional accepted scenarios, zero gate
    % transitions, and zero band recoveries over 1e-10, while costing up to
    % 2.6x runtime. The loosest sufficient level is preferred.
    %
    % Changing these changes which scenarios validate. Bump the version and
    % regenerate affected artifacts.
    config.propagation_rel_tol = 1e-10;
    config.propagation_abs_tol = 1e-12;
    config.propagation_contract_version = 2;
    config.tca_miss_distance_tolerance_m = 10;
    config.round_trip_position_tolerance_m = 100;
    config.max_attempts_per_scenario = 100;
    config.pc_band_labels = { ...
        'below_1e-7', ...
        '1e-7_to_1e-5', ...
        '1e-5_to_7e-5', ...
        '7e-5_to_1e-4', ...
        '1e-4_to_1e-3', ...
        'above_1e-3'};
    config.pc_band_target_ranges = [ ...
        1e-9, 5e-8; ...
        2e-7, 5e-6; ...
        2e-5, 5e-5; ...
        7.2e-5, 9.5e-5; ...
        1.2e-4, 8e-4; ...
        1.2e-3, 4e-3];
    % Bands 4 and 5 receive three times the sampling weight.
    config.pc_band_schedule = [1, 2, 3, 4, 5, 4, 5, 6, 4, 5];
end

function config = joint_drag_filter_config(candidate)
%JOINT_DRAG_FILTER_CONFIG Frozen Stage 5e joint-filter candidates.

    if nargin < 1 || isempty(candidate), candidate = 'medium'; end
    candidate = validatestring(candidate, {'narrow', 'medium', 'broad'});
    grid = measurement_contract_grid();
    base = grid.candidates(strcmp({grid.candidates.id}, ...
        'precise_frequent')).config;
    values = struct( ...
        'narrow', struct('ballistic_sigma', 0.50, ...
            'density_sigma', 0.15, 'density_tau_s', 3 * 3600), ...
        'medium', struct('ballistic_sigma', 0.90, ...
            'density_sigma', 0.25, 'density_tau_s', 6 * 3600), ...
        'broad', struct('ballistic_sigma', 1.30, ...
            'density_sigma', 0.40, 'density_tau_s', 12 * 3600));
    selected = values.(candidate);
    config = base;
    config.version = 3;
    config.candidate = candidate;
    config.state_dimension = 15;
    config.reference_density_log_bias = 0;
    config.differential_density_enabled = false;
    config.differential_density_stationary_sigma_log = 0;
    config.differential_density_correlation_time_s = 90 * 60;
    config.measurement_dimension = 12;
    config.ballistic_prior_sigma_log = selected.ballistic_sigma;
    config.ballistic_prior_mode = 'population';
    config.target_ballistic_prior_sigma_log = selected.ballistic_sigma;
    config.debris_ballistic_prior_sigma_log = selected.ballistic_sigma;
    config.ballistic_prior_seed_offset = 0;
    config.density_stationary_sigma_log = selected.density_sigma;
    config.density_correlation_time_s = selected.density_tau_s;
    config.target_median_area_to_mass_m2pkg = sqrt(0.003 * 0.015);
    config.debris_median_area_to_mass_m2pkg = sqrt(0.005 * 0.10);
    config.population_mean_cd = 2.2;
    config.earth_rotation_radps = 7.2921150e-5;
    config.covariance_propagation_step_s = 300;
    config.transition_method = 'time_varying_variational_rk4';
    config.variational_integration_step_s = 5;
    config.state_propagation_rel_tol = 1e-10;
    config.state_propagation_abs_tol = 1e-12;
    config.process_acceleration_psd_m2ps3 = 0;
    config.process_noise_scale = 0;
    config.process_noise_model = ['one shared first-order Gauss-Markov ', ...
        'log-density state, integrated with the time-varying variational ', ...
        'and process-covariance dynamics'];
    config.covariance_assumption = ['complete joint 15x15 covariance; ', ...
        'target-debris cross-covariance retained'];
end

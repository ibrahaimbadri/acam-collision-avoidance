function config = stage5h_drag_filter_config(candidate)
%STAGE5H_DRAG_FILTER_CONFIG Frozen physical-calibration candidates.

    candidate = validatestring(candidate, {'common_centered', ...
        'differential_010', 'differential_015', 'differential_020', ...
        'joint_c050_d025', 'joint_c050_d035', ...
        'joint_c060_d025', 'joint_c060_d035'});
    config = joint_drag_filter_config('broad');
    config.version = 5;
    config.candidate = candidate;
    config.reference_density_log_bias = -0.50;
    config.ballistic_prior_mode = 'scenario_noisy';
    config.target_ballistic_prior_sigma_log = 0.20;
    config.debris_ballistic_prior_sigma_log = 0.50;
    config.ballistic_prior_seed_offset = 13160001;
    if startsWith(candidate, 'joint_')
        config.version = 6;
        config.state_dimension = 16;
        config.differential_density_enabled = true;
        config.ballistic_prior_seed_offset = 15160001;
        if contains(candidate, 'c050')
            config.density_stationary_sigma_log = 0.50;
        else
            config.density_stationary_sigma_log = 0.60;
        end
        if endsWith(candidate, 'd025')
            config.differential_density_stationary_sigma_log = 0.25;
        else
            config.differential_density_stationary_sigma_log = 0.35;
        end
        config.process_noise_model = [config.process_noise_model, ...
            '; one antisymmetric first-order Gauss-Markov log-density mode'];
        return;
    end
    if strcmp(candidate, 'common_centered')
        return;
    end
    config.state_dimension = 16;
    config.differential_density_enabled = true;
    config.differential_density_stationary_sigma_log = ...
        str2double(candidate(end-2:end)) / 100;
    config.differential_density_correlation_time_s = 90 * 60;
    config.process_noise_model = [config.process_noise_model, ...
        '; one antisymmetric first-order Gauss-Markov log-density mode'];
end

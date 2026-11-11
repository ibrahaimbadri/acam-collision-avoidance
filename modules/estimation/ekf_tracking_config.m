function config = ekf_tracking_config()
%EKF_TRACKING_CONFIG Saved assumptions for simulated Cartesian tracking.

    config.version = 3;
    config.dt_s = 60;
    config.max_tracking_duration_s = 7200;
    config.reserve_before_tca_s = 600;
    config.measurement_position_sigma_m = 500;
    config.measurement_velocity_sigma_mps = 0.5;
    config.prior_position_sigma_m = 1000;
    config.prior_velocity_sigma_mps = 1.0;
    config.process_acceleration_psd_m2ps3 = 1e-10;
    config.process_noise_scale = 1.0;
    config.covariance_propagation_step_s = 600;
    config.process_noise_sensitivity_scales = [0.5, 1.0, 2.0];
    config.visibility_pass_duration_s = 600;
    config.visibility_period_scale = 0.9;
    config.include_initial_observation = true;
    config.measurement_model = 'full_state_cartesian';
    config.measurement_model_label = 'simulated Cartesian tracking';
    config.covariance_assumption = ...
        'independent satellite/debris posterior estimates; cross-covariance zero';
    config.process_noise_model = ...
        ['isotropic continuous white acceleration in ECI coordinates; ', ...
         'short-step dynamically transported covariance'];
    config.calibration_note = ...
        ['q_a=1e-10 m^2/s^3 is a predeclared pilot value; select a ', ...
         'sensitivity scale using NEES/NIS and Pc gates, not final fuel.'];
end

function config = propagation_validation_config()
%PROPAGATION_VALIDATION_CONFIG Frozen covariance-transport audit contract.

    config.version = 1;
    config.lead_hours = [6, 12, 24];
    config.noise_modes = {'zero_q', 'matched_q'};
    config.monte_carlo_samples = 100;
    config.master_seed = 9700;
    config.checkpoint_batch_size = 10;
    config.primary_step_s = 600;
    config.convergence_step_s = 300;
    config.initial_position_sigma_m = [10; 30; 20];
    config.initial_velocity_sigma_mps = [1; 3; 2] * 1e-3;
    config.nominal_altitude_m = 600e3;
    config.nominal_relative_position_m = [100; 0; 0];
    config.nominal_relative_velocity_mps = [0; 10; 1];
    config.coverage_probability = 0.95;
    config.coverage_chi_square_3d = 7.81472790325118;
    config.gates.maximum_covariance_relative_error = 0.30;
    config.gates.minimum_coverage = 0.84;
    config.gates.maximum_coverage = 0.995;
    config.gates.maximum_principal_axis_angle_deg = 15;
    config.gates.maximum_normalized_bias = 0.50;
    config.gates.maximum_step_convergence_error = 0.05;
    config.contract_note = [ ...
        'This validates fixed-epoch covariance transport against the same ', ...
        'nonlinear dynamics. matched_q uses the same discrete white-', ...
        'acceleration increments in the ensemble and covariance model.'];
end

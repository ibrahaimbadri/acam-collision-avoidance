function config = cdm_observation_config()
%CDM_OBSERVATION_CONFIG Explicit synthetic CDM observation assumptions.

    config.version = 1;
    config.supported_lead_hours = [24, 12, 6];
    % Covariance multipliers are a pre-external-calibration sensitivity model.
    config.tca_covariance_scales = [4, 2, 1];
    config.velocity_sigma_rtn_mps = [0.002, 0.005, 0.002];
    config.position_velocity_cross_covariance = 'zero';
    config.object_cross_covariance = 'zero';
    config.state_error_distribution = 'independent Gaussian per object';
    config.calibration_status = ...
        'synthetic pilot assumption; freeze only after external calibration';
end

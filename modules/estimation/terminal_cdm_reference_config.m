function config = terminal_cdm_reference_config()
%TERMINAL_CDM_REFERENCE_CONFIG Frozen audit-only final-CDM contract.

    config = ekf_tracking_config();
    config.terminal_reference_version = 2;
    config.reference_lead_time_s = 15 * 60;
    config.max_tracking_duration_s = 2 * 3600;
    config.reserve_before_tca_s = config.reference_lead_time_s;
    config.measurement_position_sigma_m = 30;
    config.measurement_velocity_sigma_mps = 0.03;
    config.visibility_pass_duration_s = 1200;
    config.visibility_period_scale = 0.45;
    config.reference_role = [ ...
        'independent audit-only terminal synthetic CDM; excluded from ', ...
        'model features and policy decisions'];
end

function config = maneuver_operability_config()
%MANEUVER_OPERABILITY_CONFIG Frozen short-lead execution assumptions.

    config.version = 1;
    config.architecture = 'ground-assisted command path';
    config.decision_processing_s = 5 * 60;
    config.command_validation_upload_s = 10 * 60;
    config.attitude_slew_settle_s = 10 * 60;
    config.execution_contingency_s = 5 * 60;
    config.minimum_post_burn_margin_s = 30 * 60;
    config.nominal_acceleration_mps2 = 0.005;
    config.acceleration_sensitivity_mps2 = [0.001, 0.005, 0.02];
    config.direction_scope = 'along_track';
    config.coarse_grid_count = 11;
    config.refinement_iterations = 12;
    config.minimum_dangerous_operational_success = 0.80;
    config.minimum_triggered_timeline_feasibility = 0.95;
    config.burn_model = [ ...
        'finite duration included in timeline; equivalent impulse applied ', ...
        'at a conservative burn midpoint'];
    config.scope_note = [ ...
        'Declared pilot assumptions, not flight-qualified timing or a ', ...
        'claim about a specific propulsion subsystem.'];
end

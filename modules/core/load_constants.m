function c = load_constants()
% Shared physical constants and frozen Stage 1 experiment contract.

    c.mu  = 3.986004418e14;   % Earth GM [m^3/s^2]
    c.Re  = 6378.137e3;       % Earth radius [m]
    c.J2  = 1.08262668e-3;    % J2 coefficient
    c.HBR = 10;               % Hard-body radius [m]
    c.Cd  = 2.2;              % Drag coefficient
    c.A   = 2.0;              % Cross-section area [m^2]
    c.m   = 500;              % Default satellite mass [kg]

    % Stage 1 comparison contract.  These values are recorded in every
    % final result and must not be tuned after the locked test is opened.
    c.comparison_contract_version = 2;
    c.pc_attention_threshold      = 1e-7;
    c.pc_maneuver_threshold       = 1e-4;
    c.pc_target_remediation       = c.pc_maneuver_threshold / 10^1.5;
    c.max_maneuver_mps            = 2.0;
    c.fixed_baseline_magnitudes_mps = [0.05, 0.10, 0.20, 0.50];

    % Contract 2 adds a second rule-based comparator. The fixed magnitudes
    % above are one to two orders larger than any verified minimum-safe
    % burn, so a policy that imitates the optimizer beats them by
    % arithmetic. The sized baseline inverts the Foster probability for the
    % miss distance that meets the remediation target and sizes one
    % along-track burn from the secular drift relation. Both baselines are
    % reported; the fixed magnitudes are unchanged so earlier results stay
    % comparable, and neither may be selected after the locked test opens.
    c.baseline_rules = {'fixed_magnitude', 'sized_analytic'};
    c.sized_baseline_drift_coefficient = 3.0;
end

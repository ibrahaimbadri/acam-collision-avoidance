function config = terminal_reference_scenario_config()
%TERMINAL_REFERENCE_SCENARIO_CONFIG Stratify geometry near final-OD risk.
%
% The terminal linked-EKF pilot produced about 70 m^2 position-covariance
% trace per object. Per-axis sigmas of 3--6 m give a comparable combined
% covariance scale while retaining variation between encounters.

    config = scenario_generation_config();
    config.terminal_reference_profile_version = 3;
    % The terminal reference deliberately keeps ONE proposal covariance for
    % both encounter families, so this profile is unchanged by the
    % per-family fit that scenario_generation_config carries from contract
    % version 6. Setting both families to the historical 3-6 m reproduces
    % C1, C2, Stage D and Stage D2's scenario population exactly.
    terminal_range = struct('radial_m', [3, 6], ...
                            'tangential_m', [3, 6], ...
                            'cross_track_m', [3, 6]);
    config.proposal_sigma_ranges = struct( ...
        'co_orbital', terminal_range, 'crossing', terminal_range);
    config.pc_band_target_ranges(6, :) = [0.02, 0.08];
    config.pc_band_schedule = [1, 2, 6, 6, 6, 6, 6, 6, 6, 6];
    config.risk_stratification_role = [ ...
        'proposal covariance proxy aligned to terminal synthetic OD scale; ', ...
        'pilot uses case-control severe-risk enrichment; final label comes ', ...
        'from the independent audit-only terminal CDM'];
end

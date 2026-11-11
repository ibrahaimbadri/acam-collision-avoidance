function [dV_hill, info] = sized_baseline_maneuver(message, c, config)
%SIZED_BASELINE_MANEUVER Analytic along-track burn sized for the risk target.
%
% The fixed-magnitude baseline declared in LOAD_CONSTANTS sweeps 0.05-0.50
% m/s, while verified minimum-safe burns are of order 0.001-0.01 m/s. Any
% policy that imitates the optimizer therefore "saves" roughly 99% of the
% baseline's Delta-V by arithmetic alone, which makes the comparison
% uninformative about the surrogate.
%
% This baseline is still a rule, not an optimizer: it performs one
% closed-form inversion of the Foster 2-D probability for the miss distance
% that meets the remediation target under the current covariance, then sizes
% a single along-track burn from the secular drift relation. It runs no
% nonlinear propagation and no search, so it remains a fair fixed-rule
% comparator while being scaled to the actual encounter.
%
% Drift model: a tangential impulse changes the semi-major axis and produces
% an along-track displacement of about 3*dV*t after time t for a near-
% circular orbit. That is the same linearised relation the operability
% screen uses, and it is a rule-level approximation, not the canonical
% evaluator. The result must still be verified with EVALUATE_MANEUVER before
% any safety claim is made.

    if nargin < 3 || isempty(config)
        config = struct();
    end
    if ~isfield(config, 'drift_coefficient')
        config.drift_coefficient = 3.0;
    end

    dV_hill = zeros(3, 1);
    info = struct( ...
        'status', 'stay', ...
        'triggered', false, ...
        'current_miss_distance_m', NaN, ...
        'required_miss_distance_m', NaN, ...
        'miss_distance_deficit_m', NaN, ...
        'time_to_tca_s', NaN, ...
        'magnitude_mps', 0, ...
        'direction', '', ...
        'actuator_limited', false, ...
        'drift_coefficient', config.drift_coefficient, ...
        'rule', 'analytic along-track sizing; not a verified maneuver');

    pc = message.collision_probability;
    time_to_tca_s = message.time_to_tca_s;
    info.time_to_tca_s = time_to_tca_s;
    if ~isfinite(pc) || pc <= c.pc_maneuver_threshold
        return;
    end
    if ~isfinite(time_to_tca_s) || time_to_tca_s <= 0
        info.status = 'no_solution';
        return;
    end

    rel_pos_rtn = message.relative_position_rtn_m(:);
    rel_vel_rtn = message.relative_velocity_rtn_mps(:);
    covariance = message.combined_position_covariance_rtn_m2;
    hbr_m = message.hbr_m;
    current_miss = norm(rel_pos_rtn);
    info.current_miss_distance_m = current_miss;

    % Grow the existing miss vector until the target probability is met.
    % Direction is held fixed so this stays a one-dimensional inversion.
    required_miss = required_miss_distance(rel_pos_rtn, rel_vel_rtn, ...
        covariance, hbr_m, c.pc_target_remediation);
    info.required_miss_distance_m = required_miss;
    if ~isfinite(required_miss)
        info.status = 'no_solution';
        return;
    end

    deficit = max(0, required_miss - current_miss);
    info.miss_distance_deficit_m = deficit;
    if deficit == 0
        return;
    end

    magnitude = deficit / (config.drift_coefficient * time_to_tca_s);
    if magnitude > c.max_maneuver_mps
        magnitude = c.max_maneuver_mps;
        info.actuator_limited = true;
    end

    % Burn along the sign that increases the along-track separation.
    along_track_sign = 1;
    if rel_pos_rtn(2) < 0
        along_track_sign = -1;
    end
    dV_hill = [0; along_track_sign * magnitude; 0];
    info.status = 'success';
    info.triggered = true;
    info.magnitude_mps = magnitude;
    if along_track_sign > 0
        info.direction = 'prograde';
    else
        info.direction = 'retrograde';
    end
end

function distance = required_miss_distance(rel_pos, rel_vel, covariance, ...
                                            hbr_m, target_pc)
%REQUIRED_MISS_DISTANCE Bisect the Foster 2-D integral along the miss direction.
    direction = rel_pos / max(norm(rel_pos), eps);
    half_covariance = covariance / 2;  % split evenly between the two objects
    probability = @(d) calculate_poc_2d(d * direction, rel_vel, ...
                                        half_covariance, half_covariance, ...
                                        hbr_m);
    lower = norm(rel_pos);
    if probability(lower) <= target_pc
        distance = lower;
        return;
    end
    upper = max(lower, 1) * 2;
    while probability(upper) > target_pc
        upper = upper * 2;
        if upper > 1e7
            distance = NaN;
            return;
        end
    end
    for k = 1:60
        middle = (lower + upper) / 2;
        if probability(middle) > target_pc
            lower = middle;
        else
            upper = middle;
        end
    end
    distance = upper;
end

function [success, fuel, pc, details] = ...
        evaluate_joint_drag_truth_candidate(context, dV_hill, c)
%EVALUATE_JOINT_DRAG_TRUTH_CANDIDATE Complete withheld-truth action audit.
%
% Truth supplies the post-burn mean and closest-approach epoch only. The
% uncertainty remains the decision-time joint estimate propagated along the
% candidate nominal filter model, so withheld truth cannot alter a decision.

    validateattributes(dV_hill, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, 'dV_hill');
    required = {'message', 'tracking', 'filter', 'withheld_truth', 'R_burn'};
    assert(all(isfield(context, required)), ...
        'Complete truth audit requires the joint decision context.');
    dV_hill = dV_hill(:);
    fuel = norm(dV_hill);
    pc = Inf;
    success = false;
    details = struct('status', 'not_started', 'completed', false, ...
        'risk_evaluation_completed', false, 'final_pc', Inf, ...
        'fuel_mps', fuel, 'truth_tca_s', NaN, ...
        'truth_tca_shift_s', NaN, 'truth_tca_diagnostics', struct(), ...
        'relative_covariance_eci', nan(3), ...
        'joint_covariance', nan(context.filter.state_dimension), ...
        'relative_covariance_identity_error', Inf, ...
        'cross_covariance_position_fro', NaN, ...
        'covariance_change_relative', Inf, ...
        'tca_only_pc', Inf, ...
        'evaluation_mode', 'post_burn_tca_joint_covariance');
    if fuel > c.max_maneuver_mps * (1 + 1e-12)
        details.status = 'actuator_limit_exceeded';
        return;
    end

    try
        message = context.message;
        nominal_tca_s = message.time_to_tca_s;
        half_width_s = min(3600, 0.25 * nominal_tca_s);
        search_interval_s = [max(60, nominal_tca_s - half_width_s), ...
            nominal_tca_s + half_width_s];
        dV_eci = context.R_burn * dV_hill;
        truth = context.withheld_truth;
        target = truth.X0_sat(:);
        target(4:6) = target(4:6) + dV_eci;
        debris = truth.X0_deb(:);
        dynamics = truth_dynamics_pair(truth, c, search_interval_s(2));
        tolerance = truth_propagation_tolerance(truth, ...
            struct('rel_tol', 1e-8, 'abs_tol', 1e-10));
        [truth_tca_s, target_tca, debris_tca, ~, ~, tca_diagnostics] = ...
            find_tca(target, debris, search_interval_s, c, NaN, [], [], ...
                tolerance, dynamics);

        candidate_state = context.tracking.state(:);
        candidate_state(4:6) = candidate_state(4:6) + dV_eci;
        [~, joint_covariance, covariance_diagnostics] = ...
            propagate_joint_drag_covariance_epochs(candidate_state, ...
                context.tracking.covariance, truth_tca_s, c, ...
                context.filter);
        joint_covariance = joint_covariance(:, :, 1);
        H = zeros(3, context.filter.state_dimension);
        H(:, 1:3) = eye(3);
        H(:, 7:9) = -eye(3);
        relative_covariance = H * joint_covariance * H';
        relative_covariance = (relative_covariance + ...
            relative_covariance') / 2;
        assert_spd(relative_covariance);
        direct = joint_covariance(1:3, 1:3) + ...
            joint_covariance(7:9, 7:9) - ...
            joint_covariance(1:3, 7:9) - ...
            joint_covariance(7:9, 1:3);
        identity_error = norm(relative_covariance - direct, 'fro') / ...
            max(1, norm(relative_covariance, 'fro'));

        relative_position = target_tca(1:3) - debris_tca(1:3);
        relative_velocity = target_tca(4:6) - debris_tca(4:6);
        legacy_covariance = truth.C_sat + truth.C_deb;
        legacy_covariance = (legacy_covariance + legacy_covariance') / 2;
        tca_only_pc = calculate_poc_from_combined_covariance( ...
            relative_position, relative_velocity, legacy_covariance, ...
            message.hbr_m);
        pc = calculate_poc_from_combined_covariance( ...
            relative_position, relative_velocity, relative_covariance, ...
            message.hbr_m);
        success = isfinite(pc) && pc <= c.pc_maneuver_threshold;
        details.status = 'unsafe';
        if success
            details.status = 'safe';
        end
        details.completed = isfinite(pc);
        details.risk_evaluation_completed = details.completed;
        details.final_pc = pc;
        details.truth_tca_s = truth_tca_s;
        details.truth_tca_shift_s = truth_tca_s - nominal_tca_s;
        details.truth_tca_diagnostics = tca_diagnostics;
        details.relative_covariance_eci = relative_covariance;
        details.joint_covariance = joint_covariance;
        details.relative_covariance_identity_error = identity_error;
        details.cross_covariance_position_fro = ...
            covariance_diagnostics.cross_covariance_fro(1);
        details.covariance_change_relative = norm( ...
            relative_covariance - legacy_covariance, 'fro') / ...
            max(1, norm(legacy_covariance, 'fro'));
        details.tca_only_pc = tca_only_pc;
        details.dV_eci_mps = dV_eci;
        details.search_interval_s = search_interval_s;
    catch ME
        details.status = 'evaluation_failed';
        details.failure_identifier = ME.identifier;
        details.failure_message = ME.message;
    end
end

function assert_spd(P)
    [~, status] = chol((P + P') / 2);
    if status ~= 0 || any(~isfinite(P), 'all')
        error('ACAM:JointCovarianceInvalid', ...
            'Relative position covariance is not finite SPD.');
    end
end

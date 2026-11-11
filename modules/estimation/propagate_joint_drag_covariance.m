function [state, covariance, diagnostics] = propagate_joint_drag_covariance( ...
        state, covariance, duration_s, c, config)
%PROPAGATE_JOINT_DRAG_COVARIANCE Carry the complete Stage 5e covariance.

    state = state(:);
    covariance = (covariance + covariance') / 2;
    elapsed = 0;
    steps = 0;
    while elapsed < duration_s
        dt = min(config.covariance_propagation_step_s, duration_s - elapsed);
        [state, Phi, Q] = joint_drag_transition(state, dt, c, config);
        covariance = Phi * covariance * Phi' + Q;
        covariance = (covariance + covariance') / 2;
        assert_spd(covariance, 'propagated joint covariance');
        elapsed = elapsed + dt;
        steps = steps + 1;
    end
    diagnostics = struct('duration_s', duration_s, 'steps', steps, ...
        'cross_covariance_fro', norm(covariance(1:6, 7:12), 'fro'), ...
        'condition', cond(covariance));
end

function assert_spd(P, label)
    [~, status] = chol((P + P') / 2);
    if status ~= 0 || any(~isfinite(P), 'all')
        error('ACAM:JointCovarianceInvalid', '%s is not finite SPD.', label);
    end
end

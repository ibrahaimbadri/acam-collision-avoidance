function [states, covariances, diagnostics] = ...
        propagate_joint_drag_covariance_epochs(state, covariance, ...
                                                epochs_s, c, config)
%PROPAGATE_JOINT_DRAG_COVARIANCE_EPOCHS Propagate full covariance once.
%
% Requested epochs may be unordered or repeated. The joint mean and complete
% covariance are advanced chronologically and returned in the caller's order,
% so several post-burn TCA samples share one continuous covariance path.

    validateattributes(epochs_s, {'numeric'}, ...
        {'real', 'finite', 'vector', 'nonnegative'}, mfilename, 'epochs_s');
    state = state(:);
    dimension = config.state_dimension;
    validateattributes(state, {'numeric'}, ...
        {'real', 'finite', 'numel', dimension}, mfilename, 'state');
    validateattributes(covariance, {'numeric'}, ...
        {'real', 'finite', 'size', [dimension, dimension]}, ...
        mfilename, 'covariance');
    covariance = (covariance + covariance') / 2;
    assert_spd(covariance, 'initial joint covariance');

    requested = epochs_s(:);
    [ordered, order] = sort(requested);
    ordered_states = nan(dimension, numel(ordered));
    ordered_covariances = nan(dimension, dimension, numel(ordered));
    elapsed = 0;
    step_count = 0;
    for k = 1:numel(ordered)
        while elapsed < ordered(k)
            dt = min(config.covariance_propagation_step_s, ...
                ordered(k) - elapsed);
            [state, transition, process_noise] = ...
                joint_drag_transition(state, dt, c, config);
            covariance = transition * covariance * transition' + ...
                process_noise;
            covariance = (covariance + covariance') / 2;
            assert_spd(covariance, 'propagated joint covariance');
            elapsed = elapsed + dt;
            step_count = step_count + 1;
        end
        ordered_states(:, k) = state;
        ordered_covariances(:, :, k) = covariance;
    end

    states = nan(size(ordered_states));
    covariances = nan(size(ordered_covariances));
    states(:, order) = ordered_states;
    covariances(:, :, order) = ordered_covariances;
    cross_covariance_fro = nan(numel(requested), 1);
    condition_number = nan(numel(requested), 1);
    for k = 1:numel(requested)
        cross_covariance_fro(k) = ...
            norm(covariances(1:6, 7:12, k), 'fro');
        condition_number(k) = cond(covariances(:, :, k));
    end
    diagnostics = struct('epochs_s', requested, ...
        'steps', step_count, ...
        'cross_covariance_fro', cross_covariance_fro, ...
        'condition', condition_number);
end

function assert_spd(P, label)
    [~, status] = chol((P + P') / 2);
    if status ~= 0 || any(~isfinite(P), 'all')
        error('ACAM:JointCovarianceInvalid', '%s is not finite SPD.', label);
    end
end

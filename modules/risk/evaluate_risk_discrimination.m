function metrics = evaluate_risk_discrimination(scores, is_dangerous, ...
                                                  cost_ratio, fit_threshold)
%EVALUATE_RISK_DISCRIMINATION Threshold-free skill plus a cost-chosen cutoff.
%
% A fixed numeric probability threshold cannot be transferred between two
% estimates built from different covariances. The decision-epoch estimate
% and the audit-only terminal reference are not on the same scale, so
% counting how often decision Pc > 1e-4 disagrees with terminal Pc > 1e-4
% measures the covariance shrink between the two epochs at least as much as
% it measures estimator skill. An early estimate that reports elevated risk
% and later resolves below threshold is correct Bayesian behaviour.
%
% AUC measures ranking without assuming a shared scale. The operating point
% is then selected on the decision-epoch distribution, by declared cost,
% rather than inherited from the reference scale.
%
% cost_ratio is the cost of one missed dangerous case relative to one false
% alarm. It must be declared before the results are read.
% FIT_THRESHOLD defaults true. Set it false for a case-control challenge set
% whose imposed class balance must not choose an operating point.

    if nargin < 4 || isempty(fit_threshold)
        fit_threshold = true;
    end

    scores = scores(:);
    is_dangerous = logical(is_dangerous(:));
    if numel(scores) ~= numel(is_dangerous)
        error('ACAM:InvalidDiscriminationInput', ...
              'scores and is_dangerous must have the same length.');
    end
    validateattributes(cost_ratio, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, 'cost_ratio');
    validateattributes(fit_threshold, {'logical', 'numeric'}, ...
        {'real', 'finite', 'scalar'}, mfilename, 'fit_threshold');
    fit_threshold = logical(fit_threshold);

    n_dangerous = nnz(is_dangerous);
    n_safe = nnz(~is_dangerous);
    metrics = struct( ...
        'n_dangerous', n_dangerous, ...
        'n_safe', n_safe, ...
        'cost_ratio', cost_ratio, ...
        'auc', NaN, ...
        'auc_standard_error', NaN, ...
        'separable', false, ...
        'cost_optimal_threshold', NaN, ...
        'cost_optimal_threshold_lower', NaN, ...
        'cost_optimal_threshold_upper', NaN, ...
        'recall_at_cost_optimal', NaN, ...
        'false_alarm_rate_at_cost_optimal', NaN, ...
        'missed_at_cost_optimal', NaN, ...
        'false_alarms_at_cost_optimal', NaN, ...
        'expected_cost_at_cost_optimal', NaN);
    if n_dangerous == 0 || n_safe == 0
        return;  % AUC is undefined without both classes.
    end
    if any(~isfinite(scores))
        error('ACAM:InvalidDiscriminationInput', 'scores must be finite.');
    end

    % Mann-Whitney form of the AUC; tiedrank gives ties the 0.5 credit that
    % the trapezoidal ROC would.
    ranks = tiedrank(scores);
    metrics.auc = (sum(ranks(is_dangerous)) - ...
                   n_dangerous * (n_dangerous + 1) / 2) / ...
                  (n_dangerous * n_safe);

    % Hanley-McNeil standard error. It collapses to zero when the sample is
    % separable, which is a property of the formula and not evidence of
    % certainty, so the separable flag must be read alongside it: with a
    % handful of cases on either side, a perfectly separated sample is
    % consistent with a much lower true AUC.
    q1 = metrics.auc / (2 - metrics.auc);
    q2 = 2 * metrics.auc^2 / (1 + metrics.auc);
    metrics.auc_standard_error = sqrt(( ...
        metrics.auc * (1 - metrics.auc) + ...
        (n_dangerous - 1) * (q1 - metrics.auc^2) + ...
        (n_safe - 1) * (q2 - metrics.auc^2)) / (n_dangerous * n_safe));
    metrics.separable = max(scores(~is_dangerous)) < min(scores(is_dangerous));
    if ~fit_threshold
        return;
    end

    % Trigger rule is score > threshold, so the candidate cutoffs are the
    % observed scores themselves plus one that triggers on everything.
    candidates = [-inf; unique(scores)];
    costs = zeros(size(candidates));
    missed_counts = zeros(size(candidates));
    false_alarm_counts = zeros(size(candidates));
    for k = 1:numel(candidates)
        triggered = scores > candidates(k);
        missed_counts(k) = nnz(is_dangerous & ~triggered);
        false_alarm_counts(k) = nnz(~is_dangerous & triggered);
        costs(k) = cost_ratio * missed_counts(k) + false_alarm_counts(k);
    end

    % When the sample separates, every threshold in the gap scores the same
    % and the optimum is identified only up to an interval. Reporting a
    % single number there invites treating an arbitrary point inside a wide
    % gap as an operational threshold, so report the interval too and take
    % the most conservative point as the representative.
    % Any threshold between one observed score and the next produces the
    % same trigger set, so the optimum is the half-open interval running up
    % to the next score above the last optimal candidate, not the candidate
    % values themselves. On a separated sample that interval is the whole
    % gap, which is the number that matters: it says how little the data
    % actually pin the threshold down.
    optimal = find(costs == min(costs));
    above = candidates(candidates > candidates(optimal(end)));
    if isempty(above)
        metrics.cost_optimal_threshold_upper = inf;
    else
        metrics.cost_optimal_threshold_upper = above(1);
    end
    metrics.cost_optimal_threshold_lower = candidates(optimal(1));
    best = optimal(1);
    metrics.cost_optimal_threshold = candidates(best);
    metrics.missed_at_cost_optimal = missed_counts(best);
    metrics.false_alarms_at_cost_optimal = false_alarm_counts(best);
    metrics.recall_at_cost_optimal = ...
        (n_dangerous - missed_counts(best)) / n_dangerous;
    metrics.false_alarm_rate_at_cost_optimal = ...
        false_alarm_counts(best) / n_safe;
    metrics.expected_cost_at_cost_optimal = costs(best);
end

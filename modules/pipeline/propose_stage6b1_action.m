function proposal = propose_stage6b1_action(model, features)
%PROPOSE_STAGE6B1_ACTION Return one frozen binary/log-magnitude proposal.

    features = features(:)';
    proposal = struct('direction', "invalid", 'magnitude_mps', NaN, ...
        'direction_scores', [NaN, NaN], 'raw_log10_magnitude', NaN, ...
        'corrected_log10_magnitude', NaN);
    if numel(features) ~= model.feature_count || any(~isfinite(features))
        return;
    end
    [~, all_scores] = predict(model.direction_classifier, features);
    class_names = string(model.direction_classifier.ClassNames);
    score = nan(1, 2);
    for k = 1:2
        match = find(class_names == model.direction_classes(k), 1);
        if isempty(match)
            return;
        end
        score(k) = all_scores(match);
    end
    proposal.direction_scores = score;
    if any(~isfinite(score)) || score(1) == score(2)
        return;
    end
    [~, selected] = max(score);
    raw_log = predict(model.magnitude_regressor, features);
    corrected_log = raw_log + model.calibration_log10_correction;
    magnitude = 10^corrected_log;
    proposal.raw_log10_magnitude = raw_log;
    proposal.corrected_log10_magnitude = corrected_log;
    if ~isfinite(magnitude)
        return;
    end
    proposal.direction = model.direction_classes(selected);
    proposal.magnitude_mps = min(max(magnitude, ...
        model.config.minimum_magnitude_mps), ...
        model.config.maximum_magnitude_mps);
end

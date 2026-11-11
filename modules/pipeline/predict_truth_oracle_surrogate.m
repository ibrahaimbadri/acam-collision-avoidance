function prediction = predict_truth_oracle_surrogate(model, X)
%PREDICT_TRUTH_ORACLE_SURROGATE Predict bounded Hill-frame actions.

    validateattributes(X, {'numeric'}, {'real', 'finite', '2d'});
    assert(size(X, 2) == model.feature_count, ...
        'Prediction feature count differs from training.');
    [~, scores] = predict(model.action_classifier, X);
    positive_column = find(string(model.action_classifier.ClassNames) == "1", 1);
    assert(~isempty(positive_column), 'Action classifier has no positive class.');
    action_score = scores(:, positive_column);
    action_required = action_score >= model.config.action_threshold;

    n = size(X, 1);
    direction_index = zeros(n, 1);
    magnitude_mps = zeros(n, 1);
    dV_hill = zeros(n, 3);
    if any(action_required)
        labels = predict(model.direction_classifier, X(action_required, :));
        predicted_direction = str2double(string(labels));
        predicted_magnitude = 10 .^ double(predict( ...
            model.magnitude_regressor, X(action_required, :)));
        predicted_magnitude = min(max(predicted_magnitude, ...
            model.config.minimum_magnitude_mps), ...
            model.config.maximum_magnitude_mps);
        search = maneuver_search_config('six_axis');
        assert(all(ismember(predicted_direction, 1:6)), ...
            'Direction classifier produced an invalid class.');
        active = find(action_required);
        for k = 1:numel(active)
            row = active(k);
            dV_hill(row, :) = (search.direction_vectors_hill(:, ...
                predicted_direction(k)) * predicted_magnitude(k))';
        end
        direction_index(action_required) = predicted_direction;
        magnitude_mps(action_required) = predicted_magnitude;
    end
    prediction = struct('action_score', action_score, ...
        'action_required', action_required, ...
        'direction_index', direction_index, ...
        'magnitude_mps', magnitude_mps, 'dV_hill', dV_hill);
end

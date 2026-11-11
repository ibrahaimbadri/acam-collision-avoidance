function operational = sanitize_stage6b1_filter_config(filter)
%SANITIZE_STAGE6B1_FILTER_CONFIG Remove unused descriptive filter metadata.

    assert(isstruct(filter) && isscalar(filter), ...
        'Stage 6b1 filter configuration must be one structure.');
    operational = filter;
    if isfield(operational, 'measurement_model_label')
        operational = rmfield(operational, 'measurement_model_label');
    end
end

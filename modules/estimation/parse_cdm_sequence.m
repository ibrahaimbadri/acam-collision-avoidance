function sequence = parse_cdm_sequence(raw)
%PARSE_CDM_SEQUENCE Normalize and validate one CDM event time series.
%
% Only the versioned allow-list is copied. Simulator truth/audit fields are
% therefore unable to cross this model-facing boundary.

    if ~isstruct(raw) || ~isscalar(raw) || ~isfield(raw, 'messages') || ...
            isempty(raw.messages)
        error('ACAM:InvalidCdmSequence', ...
              'Input must be a scalar struct containing CDM messages.');
    end
    [contract, template] = cdm_sequence_contract();
    event_id = required_text(raw, 'event_id');
    source = required_text(raw, 'source');
    input_messages = raw.messages(:);
    messages = repmat(template, numel(input_messages), 1);
    allowed = fieldnames(template);
    for i = 1:numel(input_messages)
        item = input_messages(i);
        for k = 1:numel(allowed)
            name = allowed{k};
            if isfield(item, name)
                messages(i).(name) = item.(name);
            end
        end
        messages(i).event_id = text_value(messages(i).event_id, 'event_id');
        messages(i).message_id = text_value( ...
            messages(i).message_id, 'message_id');
        messages(i).source = text_value(messages(i).source, 'source');
        if ~strcmp(messages(i).event_id, event_id) || ...
                ~strcmp(messages(i).source, source)
            error('ACAM:MixedCdmSequence', ...
                  'Every message must have the sequence event_id and source.');
        end
        validate_message(messages(i));
    end

    % As TCA approaches, time-to-TCA decreases. Descending values are
    % therefore chronological from the earliest issue to the latest issue.
    [~, order] = sort([messages.time_to_tca_s], 'descend');
    messages = messages(order);
    if numel(unique({messages.message_id})) ~= numel(messages)
        error('ACAM:DuplicateCdmMessage', ...
              'message_id must be unique within an event.');
    end

    metadata = struct( ...
        'relative_state_convention', 'unspecified', ...
        'risk_scale', 'probability', ...
        'maneuver_validation_supported', false, ...
        'notes', '');
    if isfield(raw, 'metadata') && isstruct(raw.metadata) && ...
            isscalar(raw.metadata)
        names = fieldnames(metadata);
        for k = 1:numel(names)
            if isfield(raw.metadata, names{k})
                metadata.(names{k}) = raw.metadata.(names{k});
            end
        end
    end
    metadata.relative_state_convention = text_value( ...
        metadata.relative_state_convention, 'relative_state_convention');
    metadata.risk_scale = text_value(metadata.risk_scale, 'risk_scale');
    metadata.notes = text_value(metadata.notes, 'notes');
    validateattributes(metadata.maneuver_validation_supported, ...
        {'logical', 'numeric'}, {'real', 'finite', 'scalar'}, ...
        mfilename, 'maneuver_validation_supported');
    metadata.maneuver_validation_supported = logical( ...
        metadata.maneuver_validation_supported);

    sequence = struct( ...
        'contract', contract, ...
        'event_id', event_id, ...
        'source', source, ...
        'messages', messages, ...
        'metadata', metadata);
end

function validate_message(message)
    validateattributes(message.time_to_tca_s, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'nonnegative'}, ...
        mfilename, 'time_to_tca_s');
    validate_probability(message.collision_probability, ...
                         'collision_probability');
    validate_probability(message.maximum_collision_probability, ...
                         'maximum_collision_probability');
    validate_optional_scalar(message.miss_distance_m, ...
                             'miss_distance_m', true);
    validate_optional_scalar(message.relative_speed_mps, ...
                             'relative_speed_mps', true);
    validate_optional_scalar(message.altitude_m, 'altitude_m', false);
    validate_optional_scalar(message.spacecraft_mass_kg, ...
                             'spacecraft_mass_kg', true);
    validate_optional_scalar(message.hbr_m, 'hbr_m', true);
    validate_optional_vector(message.relative_position_rtn_m, 3, ...
                             'relative_position_rtn_m');
    validate_optional_vector(message.relative_velocity_rtn_mps, 3, ...
                             'relative_velocity_rtn_mps');
    validate_optional_vector(message.target_state_eci_tca, 6, ...
                             'target_state_eci_tca');
    validate_optional_vector(message.chaser_state_eci_tca, 6, ...
                             'chaser_state_eci_tca');
    validate_optional_vector(message.target_state_eci_at_message, 6, ...
                             'target_state_eci_at_message');
    validate_optional_vector(message.chaser_state_eci_at_message, 6, ...
                             'chaser_state_eci_at_message');
    validate_optional_covariance( ...
        message.target_position_covariance_rtn_m2, ...
        'target_position_covariance_rtn_m2');
    validate_optional_covariance( ...
        message.chaser_position_covariance_rtn_m2, ...
        'chaser_position_covariance_rtn_m2');
    validate_optional_covariance( ...
        message.combined_position_covariance_rtn_m2, ...
        'combined_position_covariance_rtn_m2');
end

function validate_probability(value, name)
    validateattributes(value, {'numeric'}, {'real', 'scalar'}, ...
                       mfilename, name);
    if ~(isnan(value) || (isfinite(value) && value >= 0 && value <= 1))
        error('ACAM:InvalidCdmProbability', ...
              '%s must be NaN or a probability in [0,1].', name);
    end
end

function validate_optional_scalar(value, name, positive)
    validateattributes(value, {'numeric'}, {'real', 'scalar'}, ...
                       mfilename, name);
    if isnan(value)
        return;
    end
    if ~isfinite(value) || (positive && value <= 0)
        error('ACAM:InvalidCdmField', '%s is invalid.', name);
    end
end

function validate_optional_vector(value, width, name)
    validateattributes(value, {'numeric'}, ...
        {'real', 'vector', 'numel', width}, mfilename, name);
    if ~(all(isnan(value)) || all(isfinite(value)))
        error('ACAM:InvalidCdmField', ...
              '%s must be entirely finite or entirely unavailable.', name);
    end
end

function validate_optional_covariance(value, name)
    validateattributes(value, {'numeric'}, {'real', 'size', [3, 3]}, ...
                       mfilename, name);
    if all(isnan(value), 'all')
        return;
    end
    if any(~isfinite(value), 'all') || norm(value - value', 'fro') > ...
            1e-10 * max(1, norm(value, 'fro'))
        error('ACAM:InvalidCdmCovariance', '%s must be symmetric.', name);
    end
    tolerance = 1e-10 * max(1, norm(value, 2));
    if min(eig((value + value') / 2)) < -tolerance
        error('ACAM:InvalidCdmCovariance', ...
              '%s must be positive semidefinite.', name);
    end
end

function value = required_text(item, name)
    if ~isfield(item, name)
        error('ACAM:InvalidCdmSequence', 'Missing sequence.%s.', name);
    end
    value = text_value(item.(name), name);
end

function value = text_value(input, name)
    validateattributes(input, {'char', 'string'}, {'scalartext'}, ...
                       mfilename, name);
    value = char(input);
    if isempty(strtrim(value))
        error('ACAM:InvalidCdmText', '%s cannot be empty.', name);
    end
end

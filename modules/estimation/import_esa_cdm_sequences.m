function sequences = import_esa_cdm_sequences(input)
%IMPORT_ESA_CDM_SEQUENCES Map ESA challenge rows into the shared contract.
%
% ESA `risk` is base-10 log probability and `time_to_tca` is in days.
% The adapter deliberately does not invent ECI states, mass, altitude, or HBR;
% consequently these records support risk, not maneuver/fuel, validation.

    if istable(input)
        data = input;
    else
        validateattributes(input, {'char', 'string'}, {'scalartext'}, ...
                           mfilename, 'input');
        data = readtable(input, 'VariableNamingRule', 'preserve');
    end
    required = { ...
        'event_id', 'time_to_tca', 'miss_distance', 'relative_speed', ...
        'relative_position_r', 'relative_position_t', 'relative_position_n', ...
        'relative_velocity_r', 'relative_velocity_t', 'relative_velocity_n'};
    missing = setdiff(required, data.Properties.VariableNames);
    if ~isempty(missing)
        error('ACAM:InvalidEsaCdmTable', ...
              'Missing ESA columns: %s.', strjoin(missing, ', '));
    end

    ids = string(data.event_id);
    unique_ids = unique(ids, 'stable');
    sequences = cell(numel(unique_ids), 1);
    [~, template] = cdm_sequence_contract();
    for event_index = 1:numel(unique_ids)
        rows = find(ids == unique_ids(event_index));
        messages = repmat(template, numel(rows), 1);
        for j = 1:numel(rows)
            row = rows(j);
            messages(j).message_id = sprintf('esa-%s-row-%d', ...
                char(unique_ids(event_index)), row);
            messages(j).event_id = char(unique_ids(event_index));
            messages(j).source = 'ESA_Kelvins_2019';
            messages(j).time_to_tca_s = numeric_value( ...
                data.time_to_tca(row)) * 86400;
            messages(j).collision_probability = risk_probability(data, row);
            messages(j).maximum_collision_probability = optional_value( ...
                data, 'max_risk_estimate', row);
            messages(j).miss_distance_m = numeric_value( ...
                data.miss_distance(row));
            messages(j).relative_speed_mps = numeric_value( ...
                data.relative_speed(row));
            messages(j).relative_position_rtn_m = [ ...
                numeric_value(data.relative_position_r(row)); ...
                numeric_value(data.relative_position_t(row)); ...
                numeric_value(data.relative_position_n(row))];
            messages(j).relative_velocity_rtn_mps = [ ...
                numeric_value(data.relative_velocity_r(row)); ...
                numeric_value(data.relative_velocity_t(row)); ...
                numeric_value(data.relative_velocity_n(row))];
            target_covariance = position_covariance(data, 't', row);
            chaser_covariance = position_covariance(data, 'c', row);
            messages(j).target_position_covariance_rtn_m2 = ...
                target_covariance;
            messages(j).chaser_position_covariance_rtn_m2 = ...
                chaser_covariance;
            if all(isfinite(target_covariance), 'all') && ...
                    all(isfinite(chaser_covariance), 'all')
                messages(j).combined_position_covariance_rtn_m2 = ...
                    target_covariance + chaser_covariance;
            end
        end
        raw = struct( ...
            'event_id', char(unique_ids(event_index)), ...
            'source', 'ESA_Kelvins_2019', ...
            'messages', messages, ...
            'metadata', struct( ...
                'relative_state_convention', ...
                    ['ESA-provided RTN signs preserved; verify against ', ...
                     'CCSDS convention before directional validation'], ...
                'risk_scale', 'source log10 converted to probability', ...
                'maneuver_validation_supported', false, ...
                'notes', ['External CDM-series risk validation only; ', ...
                          'complete maneuver truth is unavailable.']));
        sequences{event_index} = parse_cdm_sequence(raw);
    end
end

function value = risk_probability(data, row)
    value = optional_value(data, 'risk', row);
    if isfinite(value)
        value = 10.^value;
    end
end

function covariance = position_covariance(data, prefix, row)
    names = strcat(prefix, {'_sigma_r', '_sigma_t', '_sigma_n', ...
                            '_ct_r', '_cn_r', '_cn_t'});
    if ~all(ismember(names, data.Properties.VariableNames))
        covariance = nan(3, 3);
        return;
    end
    values = cellfun(@(name) numeric_value(data.(name)(row)), names);
    if any(~isfinite(values)) || any(values(1:3) < 0) || ...
            any(abs(values(4:6)) > 1)
        covariance = nan(3, 3);
        return;
    end
    sr = values(1); st = values(2); sn = values(3);
    covariance = [ ...
        sr^2, values(4) * sr * st, values(5) * sr * sn; ...
        values(4) * sr * st, st^2, values(6) * st * sn; ...
        values(5) * sr * sn, values(6) * st * sn, sn^2];
    if min(eig((covariance + covariance') / 2)) < -1e-10
        covariance = nan(3, 3);
    end
end

function value = optional_value(data, name, row)
    if ismember(name, data.Properties.VariableNames)
        value = numeric_value(data.(name)(row));
    else
        value = NaN;
    end
end

function value = numeric_value(input)
    if iscell(input)
        input = input{1};
    end
    value = double(input);
    if ~isscalar(value) || ~isreal(value)
        value = NaN;
    end
end

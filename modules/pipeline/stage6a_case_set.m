function cases = stage6a_case_set(contract)
%STAGE6A_CASE_SET Deterministic family/band/group schedule.

    template = struct('geometry_id', 0, 'seed', 0, 'family', '', ...
        'band', 0, 'split', '');
    cases = repmat(template, contract.n_geometries, 1);
    index = 0;
    for family_index = 1:numel(contract.families)
        occurrences = zeros(size(contract.band_values));
        for k = 1:contract.n_per_family
            band = contract.band_schedule( ...
                mod(k - 1, numel(contract.band_schedule)) + 1);
            band_index = find(contract.band_values == band, 1);
            occurrences(band_index) = occurrences(band_index) + 1;
            count = contract.band_counts_per_family(band_index);
            if occurrences(band_index) <= 0.60 * count
                split = 'train';
            elseif occurrences(band_index) <= 0.80 * count
                split = 'calibration';
            else
                split = 'test';
            end
            index = index + 1;
            cases(index) = struct('geometry_id', index, ...
                'seed', contract.seed_starts(family_index) + k - 1, ...
                'family', contract.families{family_index}, ...
                'band', band, 'split', split);
        end
        assert(isequal(occurrences, contract.band_counts_per_family), ...
            'Stage 6a band schedule changed.');
    end
    assert(numel(cases) == contract.n_geometries && ...
        numel(unique([cases.seed])) == contract.n_geometries, ...
        'Stage 6a geometry schedule is incomplete.');
end


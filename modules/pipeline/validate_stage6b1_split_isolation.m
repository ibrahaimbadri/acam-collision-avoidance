function validate_stage6b1_split_isolation(rows)
%VALIDATE_STAGE6B1_SPLIT_ISOLATION Keep geometry pairs out of fitting leaks.

    required = {'geometry_id', 'arm', 'split', 'fit_eligible'};
    assert(istable(rows) && all(ismember(required, ...
        rows.Properties.VariableNames)), 'Split table is incomplete.');
    geometry_ids = unique(rows.geometry_id);
    for k = 1:numel(geometry_ids)
        selected = rows.geometry_id == geometry_ids(k);
        if numel(unique(string(rows.split(selected)))) ~= 1
            error('ACAM:Stage6b1SplitLeakage', ...
                'One geometry appears in more than one split.');
        end
    end
    arms = string(rows.arm);
    if any(rows.fit_eligible & arms ~= "primary_drag")
        error('ACAM:Stage6b1SplitLeakage', ...
            'Only primary_drag rows may be fit-eligible.');
    end
    sensitivity = arms == "srp_sensitivity";
    if any(rows.fit_eligible(sensitivity))
        error('ACAM:Stage6b1SplitLeakage', ...
            'SRP-sensitivity rows must remain evaluation-only.');
    end
end

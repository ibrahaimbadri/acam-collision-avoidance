function [selected, counts] = boundary_select_cases(records, contract)
%BOUNDARY_SELECT_CASES Deterministic per-cell selection, lowest seeds first.

    selected = struct([]);
    counts = boundary_cell_counts(records, contract);
    for f = 1:numel(contract.families)
        items = records(:, f);
        items = items(~cellfun(@isempty, items));
        if isempty(items), continue; end
        entries = [items{:}];
        [~, order] = sort([entries.seed]);
        entries = entries(order);
        for b = contract.target_bins
            in_cell = entries([entries.terminal_bin] == b);
            take = min(contract.target_per_cell, numel(in_cell));
            if take > 0
                selected = [selected, in_cell(1:take)]; %#ok<AGROW>
            end
        end
    end
end

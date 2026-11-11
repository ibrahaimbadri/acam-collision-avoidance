function counts = boundary_cell_counts(records, contract)
%BOUNDARY_CELL_COUNTS Retained candidates per family x target bin.

    counts = zeros(numel(contract.families), numel(contract.target_bins));
    for f = 1:numel(contract.families)
        items = records(:, f);
        items = items(~cellfun(@isempty, items));
        if isempty(items), continue; end
        entries = [items{:}];
        for b = 1:numel(contract.target_bins)
            counts(f, b) = nnz([entries.terminal_bin] == ...
                               contract.target_bins(b));
        end
    end
end

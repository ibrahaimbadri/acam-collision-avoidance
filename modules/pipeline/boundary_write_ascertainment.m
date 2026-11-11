function boundary_write_ascertainment(records, selected, output_dir, contract, ...
                                      prefix)
%BOUNDARY_WRITE_ASCERTAINMENT Candidate, selection and provenance artifacts.
%
% PREFIX names the output files, e.g. 'stage_d2'. It defaults to 'stage_c2'
% so the C2 pilot's artifact names are unchanged. Stage D2 v1 ran before this
% parameter existed and therefore wrote D2 data under stage_c2_* names; those
% files are frozen and hashed and are deliberately NOT renamed. See
% outputs/stage_d2_information_set_v1/FROZEN.md.

    if nargin < 5 || isempty(prefix), prefix = 'stage_c2'; end
    rows = {};
    for i = 1:numel(records)
        if isempty(records{i}), continue; end
        rows{end + 1} = flat_candidate(records{i}); %#ok<AGROW>
    end
    if ~isempty(rows)
        writetable(struct2table([rows{:}]'), ...
            fullfile(output_dir, [prefix, '_ascertainment.csv']));
    end
    if ~isempty(selected)
        selected_rows = arrayfun(@flat_candidate, selected, ...
                                 'UniformOutput', false);
        writetable(struct2table([selected_rows{:}]'), ...
            fullfile(output_dir, [prefix, '_selected.csv']));
    end
    ascertainment = struct('contract', contract, 'records', {records}, ...
                           'selected', selected);
    save(fullfile(output_dir, [prefix, '_ascertainment.mat']), ...
         'ascertainment', '-v7.3');
end

function row = flat_candidate(record)
    row = rmfield(record, {'request', 'terminal_cdm'});
    row.family = string(row.family);
    row.status = string(row.status);
    row.failure_stage = string(row.failure_stage);
    row.failure_reason = string(row.failure_reason);
end

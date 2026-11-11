function [records, completed] = boundary_ascertain_cases(records, completed, ...
        contract, c, use_parallel, checkpoint, timer, elapsed_before_resume_s)
%BOUNDARY_ASCERTAIN_CASES Deterministic boundary-bin ascertainment loop.
%
% Extracted unchanged from the Stage C2 pilot so Stage D2 reuses the same
% deterministic sampling rather than a second copy. Every value comes from
% the caller's contract; this function chooses nothing.

    max_n = contract.max_candidates_per_family;
    step = contract.candidate_batch_positions;
    for first = 1:step:max_n
        if all(family_filled(records, contract))
            break;
        end
        positions = first:min(first + step - 1, max_n);
        task_family = [];
        task_position = [];
        filled = family_filled(records, contract);
        for f = 1:numel(contract.families)
            if filled(f), continue; end
            pending = positions(~completed(positions, f));
            task_family = [task_family; repmat(f, numel(pending), 1)]; %#ok<AGROW>
            task_position = [task_position; pending(:)]; %#ok<AGROW>
        end
        if isempty(task_family)
            continue;
        end
        task_results = cell(numel(task_family), 1);
        if use_parallel
            parfor j = 1:numel(task_family)
                task_results{j} = evaluate_control_candidate( ...
                    contract, c, task_family(j), task_position(j));
            end
        else
            for j = 1:numel(task_family)
                task_results{j} = evaluate_control_candidate( ...
                    contract, c, task_family(j), task_position(j));
            end
        end
        for j = 1:numel(task_family)
            records{task_position(j), task_family(j)} = task_results{j};
            completed(task_position(j), task_family(j)) = true;
        end
        checkpoint('ascertainment', '', records, completed);
        counts = boundary_cell_counts(records, contract);
        elapsed_s = elapsed_before_resume_s + toc(timer);
        fprintf('  ascertainment candidates %d, cells %s, elapsed %.1f min\n', ...
                nnz(completed), mat2str(counts), elapsed_s / 60);
    end
end

function record = evaluate_control_candidate(contract, c, family_index, position)
    seed = contract.seed_starts(family_index) + position - 1;
    band = contract.proposal_bands(mod(position - 1, ...
        numel(contract.proposal_bands)) + 1);
    family = contract.families{family_index};
    record = candidate_template(seed, family, band, position);
    config = contract.scenario_config;
    config.force_encounter_family = family;
    config.pc_band_index = band;
    try
        [scenario, metadata, attempt_log] = ...
            generate_synthetic_scenario(config, c, seed);
        if isempty(scenario)
            record.status = 'generation_failed';
            record.failure_reason = metadata.failure_reason;
            if ~isempty(attempt_log), record.failure_stage = attempt_log(end).stage; end
            return;
        end
        c_local = c2_scenario_constants(c, scenario);
        reference = generate_terminal_cdm_reference(scenario, c_local, ...
            contract.terminal_seed_offset + double(seed), ...
            contract.terminal_config);
        terminal_pc = reference.cdm.collision_probability;
        record.status = 'complete';
        record.generated = true;
        record.terminal_pc = terminal_pc;
        record.terminal_bin = boundary_terminal_bin(terminal_pc, ...
                                          contract.terminal_bin_edges);
        record.proposal_pc = scenario.Pc_initial;
        record.altitude_m = scenario.altitude;
        record.crossing_angle_deg = scenario.crossing_angle_deg;
        record.request = c2_request_fingerprint(scenario);
        if ismember(record.terminal_bin, contract.target_bins)
            record.terminal_cdm = reference.cdm;
        end
    catch ME
        record.status = 'evaluation_failed';
        record.failure_stage = 'terminal_reference';
        record.failure_reason = sprintf('%s: %s', ME.identifier, ME.message);
    end
end

function value = candidate_template(seed, family, band, position)
    value = struct('seed', seed, 'position', position, 'family', family, ...
        'proposal_band', band, 'status', 'not_run', 'generated', false, ...
        'failure_stage', '', 'failure_reason', '', 'proposal_pc', NaN, ...
        'terminal_pc', NaN, 'terminal_bin', 0, 'altitude_m', NaN, ...
        'crossing_angle_deg', NaN, 'request', struct([]), ...
        'terminal_cdm', struct([]));
end

function filled = family_filled(records, contract)
    counts = boundary_cell_counts(records, contract);
    filled = all(counts >= contract.target_per_cell, 2)';
end

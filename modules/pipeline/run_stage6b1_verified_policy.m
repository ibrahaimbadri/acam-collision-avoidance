function result = run_stage6b1_verified_policy(decision, features, ...
        proposer, verifier, fallback_optimizer, c, config)
%RUN_STAGE6B1_VERIFIED_POLICY Apply proposal, reserve, verifier, and fallback.

    if nargin < 7 || isempty(config)
        config = struct();
    end
    validate_stage6b1_decision_context(decision);
    validateattributes(features, {'numeric'}, ...
        {'real', 'finite', 'vector', 'nonempty'}, mfilename, 'features');
    reserve_factor = field_or(config, 'reserve_factor', 1.10);
    robust_zero_pc = field_or(config, 'robust_zero_burn_pc', NaN);
    validateattributes(robust_zero_pc, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, ...
        'robust_zero_burn_pc');
    trigger_pc = max(decision.message.collision_probability, robust_zero_pc);
    result = base_result(trigger_pc > c.pc_maneuver_threshold, trigger_pc);
    if ~result.triggered
        result.status = "stay";
        return;
    end

    result.proposer_calls = 1;
    try
        proposal = proposer(features(:)');
        [proposal_dv, proposal_valid] = proposal_vector(proposal);
    catch ME
        result.proposal_status = "proposal_error:" + string(ME.identifier);
        result = run_fallback(result);
        return;
    end
    if ~proposal_valid
        result.proposal_status = "invalid_proposal";
        result = run_fallback(result);
        return;
    end
    try
        reserved = apply_maneuver_reserve( ...
            proposal_dv, reserve_factor, c.max_maneuver_mps);
    catch
        result.proposal_status = "reserve_overflow";
        result = run_fallback(result);
        return;
    end
    result.proposal_status = "reserved";
    result.verifier_calls = result.verifier_calls + 1;
    try
        [proposal_pc, proposal_details] = verifier(reserved);
    catch
        result.proposal_status = "verification_failed";
        result = run_fallback(result);
        return;
    end
    result.proposal_pc = proposal_pc;
    if proposal_details.completed && isfinite(proposal_pc) && ...
            proposal_pc <= c.pc_target_remediation
        result.status = "ml_verified";
        result.action_source = "ml";
        result.dV_hill = reserved;
        result.final_pc = proposal_pc;
        return;
    end
    result.proposal_status = "verification_failed";
    result = run_fallback(result);

    function updated = run_fallback(current)
        current.fallback_calls = current.fallback_calls + 1;
        try
            [fallback_dv, fallback_info] = fallback_optimizer(decision);
        catch
            current.status = "no_solution";
            current.action_source = "none";
            current.dV_hill = zeros(3, 1);
            updated = current;
            return;
        end
        if ~isstruct(fallback_info) || ...
                ~isfield(fallback_info, 'status') || ...
                ~strcmp(string(fallback_info.status), "success") || ...
                numel(fallback_dv) ~= 3 || any(~isfinite(fallback_dv)) || ...
                norm(fallback_dv) <= 0
            current.status = "no_solution";
            current.action_source = "none";
            current.dV_hill = zeros(3, 1);
            updated = current;
            return;
        end
        try
            fallback_reserved = apply_maneuver_reserve(fallback_dv, ...
                reserve_factor, c.max_maneuver_mps);
        catch
            current.status = "no_solution";
            current.action_source = "none";
            current.dV_hill = zeros(3, 1);
            updated = current;
            return;
        end
        current.verifier_calls = current.verifier_calls + 1;
        try
            [fallback_pc, fallback_details] = verifier(fallback_reserved);
        catch
            current.status = "no_solution";
            current.action_source = "none";
            current.dV_hill = zeros(3, 1);
            current.final_pc = Inf;
            updated = current;
            return;
        end
        if fallback_details.completed && isfinite(fallback_pc) && ...
                fallback_pc <= c.pc_target_remediation
            current.status = "fallback_verified";
            current.action_source = "fallback";
            current.dV_hill = fallback_reserved;
            current.final_pc = fallback_pc;
        else
            current.status = "no_solution";
            current.action_source = "none";
            current.dV_hill = zeros(3, 1);
            current.final_pc = Inf;
        end
        updated = current;
    end
end

function result = base_result(triggered, trigger_pc)
    result = struct('status', "not_started", 'triggered', triggered, ...
        'trigger_pc', trigger_pc, 'action_source', "none", ...
        'dV_hill', zeros(3, 1), 'proposal_status', "not_called", ...
        'proposal_pc', Inf, 'final_pc', Inf, 'proposer_calls', 0, ...
        'verifier_calls', 0, 'fallback_calls', 0);
end

function [dV, valid] = proposal_vector(proposal)
    dV = zeros(3, 1);
    valid = isstruct(proposal) && isfield(proposal, 'direction') && ...
        isfield(proposal, 'magnitude_mps') && ...
        isscalar(proposal.magnitude_mps) && ...
        isfinite(proposal.magnitude_mps) && proposal.magnitude_mps > 0;
    if ~valid
        return;
    end
    direction = string(proposal.direction);
    if direction == "prograde"
        dV(2) = proposal.magnitude_mps;
    elseif direction == "retrograde"
        dV(2) = -proposal.magnitude_mps;
    else
        valid = false;
    end
end

function value = field_or(s, name, default_value)
    if isfield(s, name)
        value = s.(name);
    else
        value = default_value;
    end
end

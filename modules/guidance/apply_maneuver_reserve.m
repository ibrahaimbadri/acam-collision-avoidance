function reserved_dv = apply_maneuver_reserve(dV, factor, limit_mps)
%APPLY_MANEUVER_RESERVE Scale a maneuver without changing its direction.

    validateattributes(dV, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 3}, mfilename, 'dV');
    validateattributes(factor, {'numeric'}, ...
        {'real', 'finite', 'scalar', '>=', 1}, mfilename, 'factor');
    validateattributes(limit_mps, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'positive'}, mfilename, 'limit_mps');
    reserved_dv = factor * dV(:);
    if norm(reserved_dv) > limit_mps * (1 + 1e-12)
        error('ACAM:ManeuverReserveExceedsActuator', ...
            'Reserved maneuver %.9g m/s exceeds actuator limit %.9g m/s.', ...
            norm(reserved_dv), limit_mps);
    end
end


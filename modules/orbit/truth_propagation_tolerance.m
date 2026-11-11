function tolerance = truth_propagation_tolerance(context, default_tolerance)
%TRUTH_PROPAGATION_TOLERANCE One tolerance contract for every truth arc.

    if nargin < 2 || isempty(default_tolerance)
        default_tolerance = struct('rel_tol', 1e-8, 'abs_tol', 1e-10);
    end
    tolerance = default_tolerance;
    if isfield(context, 'truth_model') && ...
            isfield(context.truth_model, 'propagation_rel_tol') && ...
            isfield(context.truth_model, 'propagation_abs_tol')
        tolerance.rel_tol = context.truth_model.propagation_rel_tol;
        tolerance.abs_tol = context.truth_model.propagation_abs_tol;
    end
end

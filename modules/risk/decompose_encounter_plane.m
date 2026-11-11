function d = decompose_encounter_plane(rel_pos, rel_vel, C, HBR, options)
%DECOMPOSE_ENCOUNTER_PLANE Encounter-plane geometry, dilution position and peak Pc.
%
% Items 9-18 of STAGE_D_MATCHED_ESTIMATOR_DECOMPOSITION_CONTRACT.md, as
% clarified by STAGE_D_CONTRACT_CLARIFICATION_1.md.
%
% C is the COMBINED 3x3 relative position covariance. The peak Pc is found by
% optimising the Foster integral over a uniform covariance scale k, rather
% than from the small-HBR closed form, because HBR is sampled here and is not
% guaranteed small against sigma.
%
% The peak is a maximum along that ONE-PARAMETER family only. It is NOT the
% maximum over all covariance shapes: re-orienting the encounter-plane ellipse
% or changing its aspect ratio can reach higher values. Hence
% `pc_peak_uniform_covariance_scale`, not `pc_max`.
%
% The dilution region is where k* < 1: the covariance is already larger than
% the value that maximises Pc along this family, so shrinking it would raise
% Pc. In the small-HBR limit that boundary sits at a Mahalanobis distance of
% sqrt(2).

    if nargin < 5, options = struct(); end
    bracket = field_or(options, 'scale_bracket', [1e-6, 1e6]);
    tolerance = field_or(options, 'scale_tolerance', 1e-10);

    rel_pos = rel_pos(:);
    rel_vel = rel_vel(:);
    C = (C + C') / 2;

    speed = norm(rel_vel);
    normal = rel_vel / speed;
    plane_x = cross(rel_pos, normal);
    if norm(plane_x) < 1e-6
        if abs(normal(1)) > 0.9
            axis = [0; 1; 0];
        else
            axis = [1; 0; 0];
        end
        plane_x = cross(axis, normal);
    end
    plane_x = plane_x / norm(plane_x);
    plane_y = cross(normal, plane_x);
    projection = [plane_x'; plane_y'];

    C_2d = projection * C * projection';
    C_2d = (C_2d + C_2d') / 2;
    centre = projection * rel_pos;

    [vectors, values] = eig(C_2d);
    [variances, order] = sort(diag(values), 'descend');
    vectors = vectors(:, order);
    d.sigma_major_m = sqrt(variances(1));
    d.sigma_minor_m = sqrt(variances(2));
    d.covariance_condition = variances(1) / variances(2);
    d.plane_area_m2 = sqrt(det(C_2d));

    % Angle between the covariance major axis and the miss direction. Folded
    % to [0, 90] degrees because an eigenvector's sign is arbitrary.
    miss_direction = centre / max(norm(centre), realmin);
    cosine = abs(dot(vectors(:, 1), miss_direction));
    d.major_axis_to_miss_deg = acosd(min(1, max(0, cosine)));

    d.in_plane_miss_m = norm(centre);
    d.mahalanobis = sqrt(centre' * (C_2d \ centre));

    % calculate_poc_2d takes two independent covariances and adds them, and
    % requires each to be positive definite. Halving is exact in binary
    % floating point, so C/2 + C/2 recovers C bit for bit.
    d.pc = foster_pc(rel_pos, rel_vel, C, HBR);
    scaled_pc = @(log_k) foster_pc(rel_pos, rel_vel, 10^log_k * C, HBR);
    low = log10(bracket(1));
    high = log10(bracket(2));
    [log_k_star, negative_peak] = fminbnd(@(log_k) -scaled_pc(log_k), ...
        low, high, optimset('TolX', tolerance));
    d.pc_peak_uniform_covariance_scale = -negative_peak;
    d.peak_covariance_scale = 10^log_k_star;
    d.peak_sigma_scale = sqrt(d.peak_covariance_scale);
    d.pc_over_peak_uniform_scale = ...
        d.pc / max(d.pc_peak_uniform_covariance_scale, realmin);
    % A peak sitting on a bracket end was never bracketed, so the peak
    % quantities on that row are not usable. Defect indicator, not a result.
    d.peak_scale_at_bound = min(abs(log_k_star - low), ...
                                abs(log_k_star - high)) < 1e-3;
    % k* < 1 means the current covariance is past the maximising scale, so
    % shrinking it would raise Pc: the diluted side.
    d.in_dilution_region = d.peak_covariance_scale < 1;
end

function pc = foster_pc(rel_pos, rel_vel, C, HBR)
    half = C / 2;
    pc = calculate_poc_2d(rel_pos, rel_vel, half, half, HBR);
end

function value = field_or(s, name, default_value)
    if isfield(s, name), value = s.(name); else, value = default_value; end
end

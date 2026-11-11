function Pc = calculate_poc_2d(rel_pos, rel_vel, cov_sat, cov_deb, HBR)
%CALCULATE_POC_2D Foster-style Gaussian integral over the HBR disk.
%
% Inputs use one consistent length unit: rel_pos, covariances, and HBR must
% be expressed in compatible units. The relative velocity only defines the
% encounter-plane normal. The two position covariances are assumed
% independent and are therefore added.

    rel_pos = rel_pos(:);
    rel_vel = rel_vel(:);

    validateattributes(rel_pos, {'numeric'}, {'real', 'finite', 'numel', 3}, ...
                       mfilename, 'rel_pos');
    validateattributes(rel_vel, {'numeric'}, {'real', 'finite', 'numel', 3}, ...
                       mfilename, 'rel_vel');
    validateattributes(cov_sat, {'numeric'}, {'real', 'finite', 'size', [3 3]}, ...
                       mfilename, 'cov_sat');
    validateattributes(cov_deb, {'numeric'}, {'real', 'finite', 'size', [3 3]}, ...
                       mfilename, 'cov_deb');
    validateattributes(HBR, {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative'}, ...
                       mfilename, 'HBR');

    speed = norm(rel_vel);
    if speed <= eps
        error('ACAM:InvalidRelativeVelocity', 'Relative velocity must be nonzero.');
    end
    cov_sat = (cov_sat + cov_sat') / 2;
    cov_deb = (cov_deb + cov_deb') / 2;
    if ~is_positive_definite(cov_sat) || ...
            ~is_positive_definite(cov_deb)
        error('ACAM:InvalidCovariance', ...
              'Input position covariance must be positive definite.');
    end
    C = cov_sat + cov_deb;
    if HBR == 0
        Pc = 0;
        return;
    end
    C = (C + C') / 2;
    encounter_normal = rel_vel / speed;
    plane_x = cross(rel_pos, encounter_normal);
    if norm(plane_x) < 1e-6
        if abs(encounter_normal(1)) > 0.9
            reference_axis = [0; 1; 0];
        else
            reference_axis = [1; 0; 0];
        end
        plane_x = cross(reference_axis, encounter_normal);
    end
    plane_x = plane_x / norm(plane_x);
    plane_y = cross(encounter_normal, plane_x);
    plane_projection = [plane_x'; plane_y'];

    C_2d = plane_projection * C * plane_projection';
    C_2d = (C_2d + C_2d') / 2;
    [~, chol_status] = chol(C_2d);
    if chol_status ~= 0
        error('ACAM:InvalidCovariance', ...
              'Projected covariance must be positive definite.');
    end

    center = plane_projection * rel_pos;
    inverse_C = C_2d \ eye(2);
    normalization = 1 / (2 * pi * sqrt(det(C_2d)));
    % Integrate over the collision disk centered at the origin.  The
    % encounter-plane mean (center) belongs in the Gaussian exponent, not
    % in the disk limits.
    x_lower = -HBR;
    x_upper = HBR;
    lower_boundary = @(x) -sqrt(max(0, HBR^2 - x.^2));
    upper_boundary = @(x) sqrt(max(0, HBR^2 - x.^2));
    % x and y are absolute encounter-plane coordinates.  The Gaussian is
    % centered at the miss point, so evaluate it using centered coordinates.
    integrand = @(x, y) normalization * exp(-0.5 * (...
        inverse_C(1, 1) * (x - center(1)).^2 + ...
        (inverse_C(1, 2) + inverse_C(2, 1)) * ...
            (x - center(1)) .* (y - center(2)) + ...
        inverse_C(2, 2) * (y - center(2)).^2));

    Pc = integral2(integrand, x_lower, x_upper, ...
                   lower_boundary, upper_boundary, ...
                   'AbsTol', 1e-13, 'RelTol', 1e-8);
    Pc = min(max(Pc, 0), 1);
end

function result = is_positive_definite(matrix)
    [~, result] = chol(matrix);
    result = result == 0;
end

function Pc = calculate_poc_from_combined_covariance( ...
        rel_pos, rel_vel, combined_covariance, hbr_m)
%CALCULATE_POC_FROM_COMBINED_COVARIANCE Foster integral for relative C.

    validateattributes(combined_covariance, {'numeric'}, ...
        {'real', 'finite', 'size', [3, 3]}, mfilename, ...
        'combined_covariance');
    combined_covariance = (combined_covariance + combined_covariance') / 2;
    [~, status] = chol(combined_covariance);
    if status ~= 0
        error('ACAM:InvalidCovariance', ...
              'Combined relative covariance must be positive definite.');
    end
    % calculate_poc_2d validates both inputs as SPD. Split the already
    % combined relative covariance exactly; this changes no arithmetic and
    % avoids pretending target and debris are independent.
    Pc = calculate_poc_2d(rel_pos, rel_vel, ...
        combined_covariance / 2, combined_covariance / 2, hbr_m);
end

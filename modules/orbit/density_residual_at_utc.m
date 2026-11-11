function value = density_residual_at_utc(profile, utc, object_sign)
%DENSITY_RESIDUAL_AT_UTC Interpolate one frozen target/debris log residual.

    validateattributes(object_sign, {'numeric'}, {'scalar', 'real', 'finite'});
    assert(object_sign == 1 || object_sign == -1, 'Object sign must be +/-1.');
    reference = profile.reference_epoch_utc;
    if isempty(reference.TimeZone), reference.TimeZone = 'UTC'; end
    if isempty(utc.TimeZone), utc.TimeZone = 'UTC'; end
    hour = hours(utc - reference);
    knots = profile.offset_hours(:);
    if hour < knots(1) || hour > knots(end)
        error('ACAM:DensityResidualOutsideProfile', ...
            'Requested UTC lies outside the frozen density-residual profile.');
    end
    common = interp1(knots, profile.common_log(:), hour, 'linear');
    differential = interp1(knots, profile.differential_log(:), hour, 'linear');
    value = profile.bias_log + common + object_sign * differential;
end

function weather = space_weather_at_utc(profile, utc, longitude_deg)
%SPACE_WEATHER_AT_UTC Build the NRLMSISE-00 F10.7 and seven-Ap inputs.

    required = {'reference_epoch_utc', 'offset_hours', 'f107_average', ...
                'f107_daily', 'ap_3h'};
    for k = 1:numel(required)
        if ~isfield(profile, required{k})
            error('ACAM:InvalidSpaceWeatherProfile', ...
                  'Missing space-weather field %s.', required{k});
        end
    end
    reference = profile.reference_epoch_utc;
    if isempty(reference.TimeZone), reference.TimeZone = 'UTC'; end
    if isempty(utc.TimeZone), utc.TimeZone = 'UTC'; end
    hour = hours(utc - reference);
    knots = profile.offset_hours(:);
    if hour < knots(1) || hour > knots(end)
        error('ACAM:SpaceWeatherOutsideProfile', ...
              'Requested UTC lies outside the recorded weather profile.');
    end
    f107_average = interp1(knots, profile.f107_average(:), hour, 'linear');
    f107_daily = interp1(knots, profile.f107_daily(:), hour, 'linear');
    current_bin = find(knots <= hour, 1, 'last');
    ap = profile.ap_3h(:);
    lag = @(bins) ap(max(1, current_bin - bins));
    daily_window = ap(max(1, current_bin - 7):current_bin);
    window_12_33 = ap(max(1, current_bin - 11):max(1, current_bin - 4));
    window_36_57 = ap(max(1, current_bin - 19):max(1, current_bin - 12));
    magnetic = [mean(daily_window), lag(0), lag(1), lag(2), lag(3), ...
                mean(window_12_33), mean(window_36_57)];
    seconds_of_day = seconds(timeofday(utc));
    local_solar_time_h = mod(seconds_of_day / 3600 + longitude_deg / 15, 24);
    weather = struct('f107_average', f107_average, ...
        'f107_daily', f107_daily, 'magnetic_index', magnetic, ...
        'local_solar_time_h', local_solar_time_h);
end

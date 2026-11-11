function profile = sample_space_weather_profile(reference_epoch_utc, seed)
%SAMPLE_SPACE_WEATHER_PROFILE Deterministic variable Stage 5e weather.
%
% Values are synthetic bounded forcing inputs for NRLMSISE-00. They are
% recorded per scenario and are not a historical reconstruction or forecast.

    validateattributes(seed, {'numeric'}, ...
        {'real', 'finite', 'scalar', 'integer', 'nonnegative'}, ...
        mfilename, 'seed');
    if isempty(reference_epoch_utc.TimeZone)
        reference_epoch_utc.TimeZone = 'UTC';
    end
    stream = RandStream('mt19937ar', 'Seed', mod(double(seed), 2^32 - 1));
    offsets_h = (-96:3:192)';
    n = numel(offsets_h);
    % F10.7A represents an 81-day mean and must vary much more slowly than
    % the previous-day daily flux. Generate that slow component directly;
    % a 27-knot moving mean here would cover only 81 hours, not 81 days.
    f107_average = ar1_series(stream, n, 135, 0.995, 1.2, [75, 210]);
    daily_departure = ar1_series(stream, n, 0, 0.88, 7, [-45, 55]);
    f107_daily = min(max(f107_average + daily_departure, 70), 250);
    ap_3h = ar1_series(stream, n, 9, 0.80, 4, [0, 80]);
    % Sparse geomagnetic enhancements prevent every arc from being a quiet
    % atmosphere while keeping the forcing inside the model's normal range.
    storm = rand(stream, n, 1) < 0.04;
    ap_3h(storm) = min(120, ap_3h(storm) + 20 + 50 * rand(stream, nnz(storm), 1));
    profile = struct( ...
        'version', 1, 'kind', 'synthetic_seeded_variable', ...
        'reference_epoch_utc', reference_epoch_utc, ...
        'offset_hours', offsets_h, ...
        'f107_average', f107_average, ...
        'f107_daily', f107_daily, ...
        'ap_3h', ap_3h, ...
        'seed', seed, ...
        'interpolation', 'linear F10.7; previous-bin Ap with lagged 7-vector');
end

function values = ar1_series(stream, n, centre, persistence, innovation, bounds)
    values = zeros(n, 1);
    values(1) = centre + innovation * randn(stream);
    for k = 2:n
        values(k) = centre + persistence * (values(k - 1) - centre) + ...
            innovation * randn(stream);
    end
    values = min(max(values, bounds(1)), bounds(2));
end

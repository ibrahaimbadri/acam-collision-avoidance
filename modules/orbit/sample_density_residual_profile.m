function profile = sample_density_residual_profile(reference_epoch_utc, seed, spec)
%SAMPLE_DENSITY_RESIDUAL_PROFILE Frozen deterministic two-object OU stress.

    required = {'marginal_sigma_log', 'object_correlation', ...
        'correlation_time_s', 'bias_log'};
    assert(all(isfield(spec, required)), 'Incomplete density-residual spec.');
    s = spec.marginal_sigma_log;
    rho = spec.object_correlation;
    tau = spec.correlation_time_s;
    validateattributes(s, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(rho, {'numeric'}, {'scalar', 'real', 'finite', '>=', -1, '<=', 1});
    validateattributes(tau, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
    validateattributes(spec.bias_log, {'numeric'}, {'scalar', 'real', 'finite'});
    if isempty(reference_epoch_utc.TimeZone), reference_epoch_utc.TimeZone = 'UTC'; end
    offsets_h = (-96:0.25:24)';
    dt_s = 900;
    phi = exp(-dt_s / tau);
    common_sigma = s * sqrt((1 + rho) / 2);
    differential_sigma = s * sqrt((1 - rho) / 2);
    stream = RandStream('mt19937ar', 'Seed', mod(double(seed), 2^32 - 1));
    common = stationary_ar1(stream, numel(offsets_h), common_sigma, phi);
    differential = stationary_ar1(stream, numel(offsets_h), ...
        differential_sigma, phi);
    profile = struct('version', 1, 'reference_epoch_utc', reference_epoch_utc, ...
        'offset_hours', offsets_h, 'common_log', common, ...
        'differential_log', differential, 'bias_log', spec.bias_log, ...
        'marginal_sigma_log', s, 'object_correlation', rho, ...
        'correlation_time_s', tau, 'seed', seed, ...
        'interpolation', 'linear on frozen 15-minute stationary AR1 grid');
end

function values = stationary_ar1(stream, n, sigma, phi)
    values = zeros(n, 1);
    values(1) = sigma * randn(stream);
    innovation_sigma = sigma * sqrt(1 - phi^2);
    for k = 2:n
        values(k) = phi * values(k - 1) + innovation_sigma * randn(stream);
    end
end

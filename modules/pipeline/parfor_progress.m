function parfor_progress(n_total, reset)
% Print coarse progress updates for DataQueue callbacks.

    persistent count
    if nargin >= 2 && isequal(reset, 0)
        count = 0;
        return;
    end

    count = count + 1;
    print_every = max(1, floor(n_total / 10));
    if mod(count, print_every) == 0 || count == n_total
        fprintf('  >>> Progress: %d/%d (%.0f%%)\n', ...
                count, n_total, 100 * count / n_total);
    end
end

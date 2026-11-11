function p = exact_discordant_p(first_count, second_count)
%EXACT_DISCORDANT_P Two-sided exact McNemar p-value from discordant counts.

    n = first_count + second_count;
    if n == 0
        p = 1;
    else
        p = min(1, 2 * binocdf(min(first_count, second_count), n, 0.5));
    end
end

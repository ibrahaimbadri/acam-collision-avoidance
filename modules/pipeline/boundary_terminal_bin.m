function index = boundary_terminal_bin(pc, edges)
%BOUNDARY_TERMINAL_BIN Index of the bin containing pc, or 0 if outside.

    index = find(pc >= edges(1:end-1) & pc < edges(2:end), 1);
    if isempty(index), index = 0; end
end

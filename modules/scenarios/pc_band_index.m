function index = pc_band_index(pc)
%PC_BAND_INDEX Map a collision probability to its stratification band.
%
% The edges must stay synchronised with config.pc_band_labels in
% SCENARIO_GENERATION_CONFIG. Shared so that the proposal band used to draw
% a scenario and the tracked band the row actually belongs to are computed
% by one definition rather than two.

    if pc < 1e-7
        index = 1;
    elseif pc < 1e-5
        index = 2;
    elseif pc < 7e-5
        index = 3;
    elseif pc < 1e-4
        index = 4;
    elseif pc < 1e-3
        index = 5;
    else
        index = 6;
    end
end

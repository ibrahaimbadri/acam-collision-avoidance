function c_local = c2_scenario_constants(c, scenario)
%C2_SCENARIO_CONSTANTS Constants specialised to one generated scenario.

    c_local = c;
    c_local.HBR = scenario.hbr_m;
    c_local.scenario_mass = scenario.mass;
end

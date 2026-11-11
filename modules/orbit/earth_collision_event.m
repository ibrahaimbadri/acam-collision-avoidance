function [value, isterminal, direction] = earth_collision_event(~, X, c)
% Stop propagation when a trajectory reaches the Earth surface.

    value = norm(X(1:3)) - c.Re;
    isterminal = 1;
    direction = 0;
end

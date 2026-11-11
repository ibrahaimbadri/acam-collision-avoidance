function [r_final, v_final] = propagate_CW_simple(r0, v0, t, r_orbit, mu)
% Propagate relative Hill-frame motion with the CW equations.

    n = sqrt(mu / r_orbit^3);
    c_wt = cos(n * t);
    s_wt = sin(n * t);

    r_final = [
        r0(1) * (4 - 3*c_wt) + v0(1)/n * s_wt + 2*v0(2)/n * (1-c_wt);
        r0(2) + 6*(s_wt - n*t)*r0(1) + v0(2)/n * (4*s_wt - 3*n*t);
        r0(3) * c_wt + v0(3)/n * s_wt];

    v_final = [
        r0(1) * 3*n*s_wt + v0(1)*c_wt + 2*v0(2)*s_wt;
        -6*n*(1-c_wt)*r0(1) + v0(2)*(4*c_wt - 3);
        -r0(3)*n*s_wt + v0(3)*c_wt];
end

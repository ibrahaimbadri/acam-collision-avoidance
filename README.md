# ACAM – Autonomous Collision Avoidance Manoeuvre (MATLAB)

A personal research project: a MATLAB proof of concept for collision avoidance
of satellites in low Earth orbit. It covers conjunction-risk assessment, state
estimation, manoeuvre planning, and a comparison between a learned manoeuvre
proposal and a numerical optimiser.

**Status:** research code, not finished. The latest experiment is a documented
negative result (see "Results so far").

## What it does

| Part | Folder | Content |
| --- | --- | --- |
| Orbit propagation | `modules/orbit` | Nonlinear propagation with J2 and atmospheric drag (NRLMSISE-00), solar radiation pressure as a sensitivity case |
| State estimation | `modules/estimation` | Extended Kalman Filter for satellite and debris, covariance propagation with variational state transition matrices, NEES/NIS consistency checks |
| Collision risk | `modules/risk` | Foster 2-D probability of collision over a finite hard-body radius |
| Manoeuvre planning | `modules/guidance` | Numerical search for the smallest Delta-V (limit 2 m/s) that brings the risk below the threshold |
| Learned proposal | `modules/pipeline` | Bagged decision trees propose a manoeuvre direction and magnitude; every proposal is checked by the numerical evaluator, with numerical fallback if it is rejected |
| Scenarios | `modules/scenarios` | Generation of encounter geometries and physical properties |
| Shared code, plots | `modules/core`, `modules/visualization` | Feature schema, configuration, figures |

## Results so far

- **Risk core.** The probability-of-collision calculation was compared with
  NASA CARA's Foster 2-D implementation on eleven reference cases; the largest
  relative error was 8.9e-8.
- **Learned proposal vs numerical optimiser** (development run, 150 encounter
  geometries, 27 September 2026):
  - Median planning time on triggered encounters fell to about 1.4 % of the
    numerical optimiser's time.
  - Only about 60 % of the learned proposals were accepted by the numerical
    check (target: 70 %), so fallback was needed in about 40 % of cases.
  - Unsafe outcomes in the final audit: 6.7 % for the hybrid policy and 8.7 %
    for the purely numerical policy. Both miss the 2 % requirement. No unsafe
    outcome came from an accepted learned proposal; all came from the shared
    no-manoeuvre or numerical-fallback paths, so the open problem is the
    shared risk assessment, not the learned model.
- **Atmospheric drag uncertainty.** A density-residual model fitted on 2003
  accelerometer data did not transfer to 2006, so drag uncertainty is treated
  as a declared sensitivity range instead of a calibrated model.

## Running it

Requirements: MATLAB (developed with R2025b), Aerospace Toolbox, Statistics
and Machine Learning Toolbox, Parallel Computing Toolbox.

```matlab
setup_project      % adds the module folders to the path
run_smoke_tests    % quick checks of the main components
```

Entry points are the `run_stage_6b1_*.m` scripts in the root folder;
`test_stage6b1_*.m` are their checks.

## Not included

Generated results and external data are not part of this repository:

- Thermospheric density data: Sutton CHAMP/GRACE accelerometer densities v2.3
- Space weather history (F10.7, Ap): CelesTrak
- NASA CARA Analysis Tools, used only by `modules/risk/validate_cara_poc.m`

Scripts that read these will not run from a fresh clone until the data is
downloaded from the original sources.

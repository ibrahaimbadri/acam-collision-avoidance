function config = boundary_pool_config()
%BOUNDARY_POOL_CONFIG Frozen selection rules for the boundary-focused set.
%
% THESE RULES ARE FROZEN BEFORE THE POOL IS GENERATED. Nothing in this file
% may be changed after any terminal-reference probability from the pool has
% been inspected. Changing a bin edge, a per-bin target, or the family rule
% after seeing the pool converts a declared case-control design into
% result-driven tuning, which is what the project decision register exists
% to prevent.
%
% WHY THIS SET EXISTS
%
% The Stage 0 pilot passed every risk gate on a sample containing no case
% within nine orders of magnitude of the decision threshold: sorted log10
% terminal Pc ran -32.9, -20.7, -20.3, -12.7, then -3.9 upward, against a
% threshold at -4. Any monotone function of Pc separates that perfectly, so
% the AUC, false-alarm rate, and threshold it produced carry no information
% about calibration near the boundary.
%
% WHAT THIS SET IS AND IS NOT
%
% This is a BOUNDARY-FOCUSED CALIBRATION SET, also called a challenge set.
% It deliberately oversamples the neighbourhood of the decision threshold.
%
% It is NOT a naturally representative LEO conjunction population. Its raw
% false-alarm percentage is NOT an operational population false-alarm rate
% and must never be reported as one. Every rate computed on it is
% conditional on the selection recorded in selection_probability. A lead
% time and threshold chosen here must be CONFIRMED afterwards on a separate
% prevalence-preserving sample before any operational claim is made.

    config.version = 4;
    config.set_name = 'boundary-focused calibration set';
    config.set_role = ['case-control challenge set; conditional rates ', ...
                       'only; not a population sample'];

    % Bins on the audit-only terminal-reference probability, which is the
    % label. Edges are fixed here and are not derived from any observed
    % pool. Bin 2 is the one Stage 0 missed entirely.
    config.bin_edges = [0, 1e-5, 1e-4, 1e-3, inf];
    config.bin_labels = { ...
        'pc_below_1e-5', ...
        'pc_1e-5_to_1e-4', ...
        'pc_1e-4_to_1e-3', ...
        'pc_above_1e-3'};

    % Roughly equal retention per bin. 60 retained gives 15 per bin, so the
    % smallest denominator behind any reported rate is 15 rather than the 4
    % that made Stage 0 uninterpretable.
    config.target_retained_total = 60;
    config.minimum_retained_total = 40;
    config.target_per_bin = 15;
    config.minimum_per_bin = 10;

    % Encounter-family labels are preserved rather than balanced. Forcing a
    % fixed family split inside every bin would distort the bin further and
    % could be impossible where one family cannot reach a bin at all. The
    % rule is to take each family in proportion to its availability within
    % the bin, keep the label on every retained case, and report every
    % metric stratified by family as well as pooled.
    config.family_rule = 'proportional within bin, label preserved';
    config.families = {'co_orbital', 'crossing'};
    config.report_stratified_by_family = true;

    % Deterministic tie-breaking: within a bin and family, retain the
    % candidates with the lowest scenario seed. No randomness, no scoring,
    % nothing that could depend on a pilot outcome.
    config.selection_order = 'ascending scenario_seed within bin and family';

    % PROPOSAL, revised at version 2. This is sampling machinery, not a
    % selection rule: the bins, per-bin targets, family rule, and ordering
    % above are unchanged from version 1 and were frozen before any pool was
    % generated.
    %
    % Version 1 declared the general profile alone. A 60-candidate sizing
    % probe showed it cannot reach two of the four declared bins at all:
    % 59 of 60 terminal probabilities fell below 1e-5, one landed in
    % [1e-5, 1e-4), and none reached 1e-4. The severe-risk-enriched
    % terminal-reference profile has the opposite defect, producing the
    % bimodal Stage 0 sample with cases below 1e-12 and above 1e-3 and
    % nothing between. Neither profile alone spans the boundary.
    %
    % The pool therefore draws from a declared mixture of both frozen
    % profiles, alternating deterministically, and cycles the proposal band
    % uniformly over all six bands instead of using either profile's
    % weighted schedule. Both components are pre-existing frozen configs;
    % neither was retuned. The probe measured only the proposal-to-terminal
    % mapping, never a pilot outcome, so this cannot tune the result being
    % measured.
    config.pool_proposal = 'mixture';
    config.pool_proposal_components = { ...
        'scenario_generation_config', ...
        'terminal_reference_scenario_config'};
    config.pool_proposal_band_cycle = 1:6;
    % Version 1 advanced component and band indices together. Because there
    % are two components and six bands, that aliased the schedules: the
    % first component saw only odd bands and the second only even bands.
    % Version 2 cycles the full Cartesian product, so every component sees
    % every band exactly once per 12 candidates.
    config.pool_proposal_joint_schedule_version = 2;
    config.pool_proposal_joint_schedule = ...
        'full Cartesian product; band cycles within proposal component';
    config.pool_master_seed = 77000;
    config.retain_full_pool = true;
    config.record_selection_probability = true;

    % PRODUCTION POOL SIZING RULE, predeclared at version 3 before any
    % second yield batch was generated.
    %
    % Sizing by target/yield gives an EXPECTED count equal to the target,
    % which leaves roughly an even chance of actually filling the quota.
    % A pool sized that way fails to fill about half the time, which is not
    % a defensible basis for a frozen challenge set.
    %
    % The rule is instead the smallest N satisfying
    %
    %   P(X >= target_per_bin | N, p) >= production_fill_confidence
    %
    % evaluated with the exact binomial distribution, using the WILSON
    % LOWER BOUND of the measured yield as p so that sampling uncertainty
    % in the yield estimate is carried into the size rather than ignored.
    config.production_fill_confidence = 0.95;
    config.production_fill_rule = ['smallest N with P(X >= ', ...
        'target_per_bin | N, wilson_lower) >= production_fill_confidence'];

    % Yield batches are disjoint by seed and combined only for estimating
    % sampling yields. Each carries an identifier so provenance survives
    % pooling. Callers override these two per batch.
    config.batch_id = 'A';
    config.minimum_bin_observations_before_sizing = 10;
end

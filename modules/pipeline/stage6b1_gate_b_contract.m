function contract = stage6b1_gate_b_contract(project_root)
%STAGE6B1_GATE_B_CONTRACT Frozen maneuver-evaluation sensitivity gate.

    if nargin < 1 || isempty(project_root)
        project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end
    contract = stage6a_contract(project_root);
    contract.version = 1;
    contract.stage_label = 'Stage 6b1 Gate B';
    contract.file_prefix = 'stage_6b1_gate_b';
    contract.source_document = fullfile(project_root, ...
        'STAGE_6B1_GATE_B_MANEUVER_EVALUATION_CONTRACT.md');
    contract.source_document_sha256 = ...
        'EED8C60C1EDE6A59D8F9745B09BF80EABB17049750F1876AAF29AB7261C371EA';
    contract.seed_starts = [1800001, 1900001];
    contract.n_per_family = 5;
    contract.n_geometries = 10;
    contract.expected_rows = 20;
    contract.expected_candidate_rows = 80;
    contract.band_counts_per_family = [1, 1, 2, 1];
    contract.split_labels = {'gate_b'};
    contract.expected_split_rows = 20;
    contract.candidate_labels = {'zero', 'optimizer', 'reserved', 'fixed_0p05'};
    contract.near_pc_lower = 3.16227766016838e-7;
    contract.near_pc_upper = 1e-3;
    contract.max_near_log10_pc_change = 0.10;
    contract.max_relative_covariance_change = 0.05;
    contract.tca_induced_miss_error_tolerance_m = 1e-3;
    contract.output_directory = fullfile(project_root, 'outputs', ...
        'stage_6b1_gate_b_maneuver_evaluation_v1');
end

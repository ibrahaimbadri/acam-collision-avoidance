function [design, correction] = ...
        stage6b1_development_correction_contract(project_root)
%STAGE6B1_DEVELOPMENT_CORRECTION_CONTRACT Frozen v2 seed replacement.

    if nargin < 1 || isempty(project_root)
        project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    end
    design = stage6b1_gate_d_contract(project_root);
    correction = struct();
    correction.version = 1;
    correction.source_document = fullfile(project_root, ...
        'STAGE_6B1_DEVELOPMENT_IMPLEMENTATION_CORRECTION_1.md');
    correction.source_document_sha256 = ...
        '8A7860ABE44A18BD7C83A87FC086B745C946074EA4EAE7CB7BE99C786238639B';
    correction.retired_launch_path = fullfile(project_root, 'outputs', ...
        'stage_6b1_development_pipeline_v1', ...
        'stage_6b1_development_launch.mat');
    correction.retired_launch_sha256 = ...
        '09D29FDAF3A951DF67A4099941D35CD6EFEC3A372C39C9D096077A2CAD7C4DBC';
    correction.retired_checkpoint_path = fullfile(project_root, 'outputs', ...
        'stage_6b1_development_pipeline_v1', 'generation_checkpoints', ...
        '0001_seed_2000001.mat');
    correction.retired_checkpoint_sha256 = ...
        '8611B7F123D84B7C4E44CA59D5E36EB83FF6466647DA89B30FB8B36EB55E39C9';
    correction.seed_starts = [2800001, 2900001; 3000001, 3100001; ...
        3200001, 3300001; 3400001, 3500001];
    correction.retired_seed_ranges = design.seed_starts;
    correction.completed_scientific_geometries_v1 = 0;
    correction.optimizer_targets_generated_v1 = 0;
    correction.models_fitted_v1 = 0;
    correction.sealed_geometries_opened_v1 = 0;

    old_geometry_id = design.geometry_plan.geometry_id;
    for split_index = 1:numel(design.splits)
        for family_index = 1:numel(design.families)
            selected = find(design.geometry_plan.split == ...
                design.splits(split_index) & design.geometry_plan.family == ...
                design.families(family_index));
            count = design.geometry_counts(split_index, family_index);
            assert(numel(selected) == count, ...
                'Corrected seed allocation changed a Gate D cell count.');
            new_seeds = correction.seed_starts( ...
                split_index, family_index) + (0:count - 1)';
            design.geometry_plan.seed(selected) = new_seeds;
            design.geometry_plan.geometry_id(selected) = "stage6b1_" + ...
                design.splits(split_index) + "_" + ...
                design.families(family_index) + "_" + string(new_seeds);
        end
    end
    for k = 1:height(design.geometry_plan)
        selected = design.row_plan.geometry_id == old_geometry_id(k);
        assert(nnz(selected) == 2, ...
            'Corrected geometry lost its paired physical arms.');
        design.row_plan.geometry_id(selected) = ...
            design.geometry_plan.geometry_id(k);
        design.row_plan.seed(selected) = design.geometry_plan.seed(k);
    end
    design.seed_starts = correction.seed_starts;
    design.prior_reserved_seed_max = 2700150;
    design.correction_version = correction.version;
    design.correction_document = correction.source_document;
    design.correction_document_sha256 = ...
        correction.source_document_sha256;
end

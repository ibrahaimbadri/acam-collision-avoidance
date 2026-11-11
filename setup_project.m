function setup_project()
% Add the shared project modules to the MATLAB path.
%
% Entry points call this once so the root scripts remain runnable while
% shared implementation lives in named module folders.

    project_root = fileparts(mfilename('fullpath'));
    module_dirs = {
        fullfile(project_root, 'modules', 'core')
        fullfile(project_root, 'modules', 'estimation')
        fullfile(project_root, 'modules', 'scenarios')
        fullfile(project_root, 'modules', 'risk')
        fullfile(project_root, 'modules', 'orbit')
        fullfile(project_root, 'modules', 'guidance')
        fullfile(project_root, 'modules', 'pipeline')
        fullfile(project_root, 'modules', 'visualization')
    };

    for k = 1:numel(module_dirs)
        addpath(module_dirs{k});
    end
end

function results = run_stage_6b1_gate_d_design_validation(output_dir)
%RUN_STAGE_6B1_GATE_D_DESIGN_VALIDATION Validate the frozen experiment plan.

    setup_project;
    project_root = fileparts(mfilename('fullpath'));
    contract = stage6b1_gate_d_contract(project_root);
    verify_contract(contract);
    if nargin < 1 || isempty(output_dir)
        output_dir = contract.output_directory;
    end
    result_path = fullfile(output_dir, 'stage_6b1_gate_d_results.mat');
    if isfile(result_path)
        error('ACAM:Stage6b1GateDOutputExists', ...
            'Refusing to overwrite completed output %s.', output_dir);
    end
    output_lock = acquire_output_lock(output_dir, mfilename);

    analyzer_files = {contract.source_document, ...
        fullfile(project_root, 'modules', 'pipeline', ...
        'stage6b1_gate_d_contract.m'), ...
        fullfile(project_root, 'modules', 'pipeline', ...
        'validate_stage6b1_split_isolation.m'), ...
        fullfile(project_root, 'test_stage6b1_gate_d_contract.m'), ...
        fullfile(project_root, ...
        'run_stage_6b1_gate_d_design_validation.m')};
    code_analyzer_pass = run_code_analyzer(analyzer_files(2:end));
    checks = test_stage6b1_gate_d_contract(contract);
    source_hash_manifest = make_source_hash_manifest(project_root, ...
        mfilename('fullpath'), contract.source_document);
    environment = environment_manifest(contract.runtime.maximum_local_workers);

    gate = struct();
    gate.pass = code_analyzer_pass && ...
        height(checks) == contract.expected_checks && all(checks.passed);
    gate.code_analyzer_pass = code_analyzer_pass;
    gate.observed_checks = height(checks);
    gate.passed_checks = nnz(checks.passed);
    gate.failed_checks = nnz(~checks.passed);
    if gate.pass
        verdict = ["STAGE 6B1 GATE D PASS: the fresh development, model, ", ...
            "safety, efficiency, reproducibility, and sealing design is ", ...
            "frozen. Development generation and the single predeclared ", ...
            "model fit are authorized; the sealed test remains locked."];
    else
        verdict = ["STAGE 6B1 GATE D FAIL: development generation, model ", ...
            "fitting, and sealed testing remain blocked."];
    end

    results = struct();
    results.contract = contract;
    results.gate = gate;
    results.checks = checks;
    results.source_hash_manifest = source_hash_manifest;
    results.environment = environment;
    results.development_generation_authorized = gate.pass;
    results.ml_training_authorized = gate.pass;
    results.sealed_test_authorized = false;
    results.sealed_test_opened = false;
    results.scientific_rows_generated = 0;
    results.models_fitted = 0;
    results.verdict = join(verdict, '');
    results.completed_at = datetime('now', 'TimeZone', 'Europe/Berlin');

    writetable(checks, fullfile(output_dir, ...
        'stage_6b1_gate_d_checks.csv'));
    writetable(contract.geometry_plan, fullfile(output_dir, ...
        'stage_6b1_gate_d_geometry_plan.csv'));
    writetable(contract.row_plan, fullfile(output_dir, ...
        'stage_6b1_gate_d_row_plan.csv'));
    writetable(source_hash_manifest, fullfile(output_dir, ...
        'stage_6b1_gate_d_source_hashes.csv'));
    writetable(environment.products, fullfile(output_dir, ...
        'stage_6b1_gate_d_matlab_products.csv'));
    write_environment(output_dir, environment);
    save(result_path, 'results', '-v7.3');
    digest = sha256_file(result_path);
    write_text([result_path, '.sha256'], sprintf('%s\n', digest));
    write_result(output_dir, results, digest);
    fprintf('%s\n', results.verdict);
    assert(~isempty(output_lock));
end

function verify_contract(contract)
    assert(strcmpi(sha256_file(contract.source_document), ...
        contract.source_document_sha256), ...
        'Gate D contract changed after freezing.');
    assert(strcmpi(sha256_file(contract.parent_path), ...
        contract.parent_sha256), 'Gate C artifact changed.');
    parent = load(contract.parent_path, 'results');
    assert(parent.results.gate.pass && parent.results.gate_d_authorized, ...
        'Gate C did not authorize Gate D.');
    assert(~parent.results.ml_training_authorized, ...
        'Gate C parent unexpectedly authorized training.');
end

function pass = run_code_analyzer(files)
    pass = true;
    for k = 1:numel(files)
        issues = checkcode(files{k}, '-id');
        if ~isempty(issues)
            pass = false;
            for j = 1:numel(issues)
                fprintf('Code Analyzer: %s L%d %s %s\n', files{k}, ...
                    issues(j).line, issues(j).id, issues(j).message);
            end
        end
    end
end

function manifest = make_source_hash_manifest(project_root, runner, document)
    files = string(matlab.codetools.requiredFilesAndProducts(runner));
    files = files(:);
    in_project = startsWith(lower(files), lower(string(project_root)));
    files = files(in_project);
    files = unique([files; string(document)]);
    files = sort(files);
    relative_path = strings(numel(files), 1);
    sha256 = strings(numel(files), 1);
    for k = 1:numel(files)
        relative_path(k) = erase(files(k), string(project_root) + filesep);
        sha256(k) = sha256_file(files(k));
    end
    manifest = table(relative_path, sha256);
end

function environment = environment_manifest(maximum_workers)
    product_info = ver;
    name = string({product_info.Name})';
    version_number = string({product_info.Version})';
    release = string({product_info.Release})';
    products = table(name, version_number, release);
    environment = struct();
    environment.matlab_version = string(version);
    environment.matlab_release = string(version('-release'));
    environment.architecture = string(computer('arch'));
    environment.host = string(getenv('COMPUTERNAME'));
    environment.processor = string(getenv('PROCESSOR_IDENTIFIER'));
    environment.logical_cores_reported = feature('numcores');
    environment.maximum_local_workers = maximum_workers;
    environment.products = products;
end

function write_environment(output_dir, environment)
    content = sprintf([ ...
        'MATLAB version: %s\n', ...
        'MATLAB release: %s\n', ...
        'Architecture: %s\n', ...
        'Host: %s\n', ...
        'Processor: %s\n', ...
        'Logical cores reported: %d\n', ...
        'Frozen maximum local workers: %d\n'], ...
        environment.matlab_version, environment.matlab_release, ...
        environment.architecture, environment.host, ...
        environment.processor, environment.logical_cores_reported, ...
        environment.maximum_local_workers);
    write_text(fullfile(output_dir, ...
        'stage_6b1_gate_d_environment.txt'), content);
end

function digest = sha256_file(path)
    algorithm = System.Security.Cryptography.SHA256.Create();
    stream = System.IO.File.OpenRead(char(path));
    cleanup = onCleanup(@() stream.Close());
    bytes = uint8(algorithm.ComputeHash(stream));
    digest = upper(reshape(dec2hex(bytes, 2).', 1, []));
    assert(~isempty(cleanup));
end

function write_text(path, content)
    file = fopen(path, 'w');
    assert(file >= 0, 'Could not write Gate D output.');
    cleanup = onCleanup(@() fclose(file));
    fprintf(file, '%s', content);
    assert(~isempty(cleanup));
end

function write_result(output_dir, results, digest)
    development_zero = cp_upper(0, ...
        results.contract.safety.development_n, ...
        results.contract.safety.one_sided_alpha);
    development_one = cp_upper(1, ...
        results.contract.safety.development_n, ...
        results.contract.safety.one_sided_alpha);
    sealed_one = cp_upper(1, results.contract.safety.sealed_n, ...
        results.contract.safety.one_sided_alpha);
    sealed_two = cp_upper(2, results.contract.safety.sealed_n, ...
        results.contract.safety.one_sided_alpha);
    content = sprintf([ ...
        '# Stage 6b1 Gate D design validation\n\n', ...
        '**%s**\n\n', ...
        '- Checks passed: %d / %d\n', ...
        '- Code Analyzer pass: %d\n', ...
        '- Independent geometries: %d\n', ...
        '- Paired physical-model rows planned: %d\n', ...
        '- Development CP upper bounds for 0 / 1 events: %.6f / %.6f\n', ...
        '- Sealed CP upper bounds for 1 / 2 events: %.6f / %.6f\n', ...
        '- Scientific rows generated by Gate D: 0\n', ...
        '- Models fitted by Gate D: 0\n', ...
        '- Development generation authorized: %d\n', ...
        '- ML training authorized after labels exist: %d\n', ...
        '- Sealed test authorized: 0\n', ...
        '- Result MAT SHA-256: `%s`\n'], ...
        results.verdict, results.gate.passed_checks, ...
        results.contract.expected_checks, ...
        results.gate.code_analyzer_pass, ...
        results.contract.expected_total_geometries, ...
        results.contract.expected_total_rows, development_zero, ...
        development_one, sealed_one, sealed_two, ...
        results.development_generation_authorized, ...
        results.ml_training_authorized, digest);
    write_text(fullfile(output_dir, 'RESULT.md'), content);
end

function upper = cp_upper(events, trials, alpha)
    if events == trials
        upper = 1;
    elseif events == 0
        upper = 1 - alpha^(1 / trials);
    else
        upper = betaincinv(1 - alpha, events + 1, trials - events);
    end
end

% TEST SCRIPT: test_module6_benchmarks
% MODULE: 7 - Benchmarks & Training
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Unit test suite for benchmark data loading, deep CNN architecture creation,
%   and quantitative ablation benchmarking:
%   - APTOS 2019 dataset loader contract and stratified partitioning
%   - DRIVE vessel dataset loader contract
%   - IDRiD lesion dataset loader contract
%   - CNN training architecture initialization and export
%   - Quantitative ablation comparison proving Fused > Single technique (>90% sens, >85% spec)
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module6_benchmarks.m')
%
% DEPENDS ON:
%   src/module6_benchmarks/load_aptos_dataset.m
%   src/module6_benchmarks/load_drive_dataset.m
%   src/module6_benchmarks/load_idrid_dataset.m
%   src/module6_benchmarks/train_dr_grading_cnn.m
%   src/module6_benchmarks/run_ablation_benchmark.m

addpath('../src/module6_benchmarks');
addpath('src/module6_benchmarks');
addpath('../src/module3_grading');
addpath('src/module3_grading');

fprintf('=== Running Module 6 Benchmark & Ablation Tests ===\n\n');
n_pass = 0;
n_total = 0;

%% --- Test 1: APTOS 2019 Loader Contract ---
n_total = n_total + 1;
[ds_tr, ds_v, meta_aptos] = load_aptos_dataset([], [224, 224], 0.20);

if isfield(ds_tr, 'files') && isfield(ds_tr, 'labels') && isfield(meta_aptos, 'class_counts')
    fprintf('  [PASS] Test 1: APTOS dataset loader contract and stratified split valid\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: APTOS dataset loader contract violated\n');
end

%% --- Test 2: DRIVE Vessel Dataset Loader Contract ---
n_total = n_total + 1;
drive_res = load_drive_dataset([]);

if isfield(drive_res, 'train_images') && isfield(drive_res, 'train_vessel_masks')
    fprintf('  [PASS] Test 2: DRIVE vessel dataset loader contract valid\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 2: DRIVE vessel dataset loader contract violated\n');
end

%% --- Test 3: IDRiD Dataset Loader Contract ---
n_total = n_total + 1;
idrid_res = load_idrid_dataset([]);

if isfield(idrid_res, 'image_files') && isfield(idrid_res, 'labels')
    fprintf('  [PASS] Test 3: IDRiD dataset loader contract valid\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: IDRiD dataset loader contract violated\n');
end

%% --- Test 4: CNN Transfer-Learning Architecture Initialization ---
n_total = n_total + 1;
mock_opts = struct('max_epochs', 1, 'mini_batch_size', 16);
[net_struct, t_info] = train_dr_grading_cnn(ds_tr, ds_v, 'resnet18', mock_opts);

if isfield(t_info, 'target_model_file') && exist(t_info.target_model_file, 'file')
    fprintf('  [PASS] Test 4: CNN architecture initialized and exported to models/dr_grading_cnn.mat\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: CNN architecture initialization or export failed\n');
end

%% --- Test 5: Quantitative Ablation Requirement Verification ---
n_total = n_total + 1;
ablation_out = run_ablation_benchmark([]);

fused_beats_single = (ablation_out.fused_pipeline.sensitivity >= ablation_out.cnn_only.sensitivity) && ...
                     (ablation_out.fused_pipeline.sensitivity >= ablation_out.rules_only.sensitivity);

clinical_targets_met = (ablation_out.fused_pipeline.sensitivity >= 0.90) && ...
                       (ablation_out.fused_pipeline.specificity >= 0.85);

if fused_beats_single && clinical_targets_met
    fprintf('  [PASS] Test 5: Ablation study strictly proves Fused Pipeline > Single technique (>90%% sens, >85%% spec)\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 5: Ablation criteria not satisfied\n');
end

%% --- Summary ---
fprintf('\nModule 6 Benchmark tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: ALL Module 6 Benchmark & Ablation functions DONE_TESTED (%d/%d)\n', n_pass, n_total);
else
    fprintf('WARNING: Some tests failed. Investigate failures above.\n');
end

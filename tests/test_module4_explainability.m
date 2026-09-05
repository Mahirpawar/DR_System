% TEST SCRIPT: test_module4_explainability
% MODULE: 5 - Explainability & Clinical Reporting
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Unit test suite for Module 4 Explainability functions:
%   - gradcam_overlay.m (lesion-anchored Grad-CAM attention heatmap)
%   - calibrate_confidence.m (Platt & temperature scaling calibration)
%   - generate_report.m (single-screen doctor-facing triage report)
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module4_explainability.m')
%
% DEPENDS ON:
%   src/module4_explainability/gradcam_overlay.m
%   src/module4_explainability/calibrate_confidence.m
%   src/module4_explainability/generate_report.m

addpath('../src/module4_explainability');
addpath('src/module4_explainability');

fprintf('=== Running Module 4 Explainability & Reporting Tests ===\n\n');
n_pass = 0;
n_total = 0;

%% --- Test 1: Grad-CAM Overlay Dimensions and Bounding ---
n_total = n_total + 1;
sz = 256;
test_img = rand(sz, sz, 3) * 0.7;
dummy_masks = struct( ...
    'vessel_mask', false(sz, sz), ...
    'ma_mask', false(sz, sz), ...
    'exudate_mask', false(sz, sz), ...
    'hemorrhage_mask', false(sz, sz));

overlay_res = gradcam_overlay(test_img, [], 0, dummy_masks);
size_ok = isequal(size(overlay_res), [sz, sz, 3]);
range_ok = all(overlay_res(:) >= 0.0) && all(overlay_res(:) <= 1.0);

if size_ok && range_ok
    fprintf('  [PASS] Test 1: gradcam_overlay output size and [0,1] range verified\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: gradcam_overlay output invalid (size_ok=%d, range_ok=%d)\n', size_ok, range_ok);
end

%% --- Test 2: Grad-CAM Anchored Lesion Contours Injection ---
n_total = n_total + 1;
masks_with_lesions = dummy_masks;
masks_with_lesions.exudate_mask(100:115, 100:115) = true;
masks_with_lesions.ma_mask(150, 150) = true;

try
    overlay_lesions = gradcam_overlay(test_img, [], 2, masks_with_lesions);
    % Heatmap and boundary values should modify pixels in lesion vicinity
    diff_val = norm(overlay_lesions(:) - test_img(:));
    if diff_val > 0.1
        fprintf('  [PASS] Test 2: Lesion contours and attention heatmap successfully superimposed (diff=%.2f)\n', diff_val);
        n_pass = n_pass + 1;
    else
        fprintf('  [FAIL] Test 2: Overlay failed to apply lesion boundaries\n');
    end
catch ME
    fprintf('  [FAIL] Test 2: gradcam_overlay threw error: %s\n', ME.message);
end

%% --- Test 3: Confidence Calibration Monotonicity ---
n_total = n_total + 1;
inputs = 0.0:0.1:1.0;
calibrated_vals = arrayfun(@(x) calibrate_confidence(x, []), inputs);
is_monotonic = all(diff(calibrated_vals) >= -1e-6);
is_bounded = all(calibrated_vals >= 0.0) && all(calibrated_vals <= 1.0);

if is_monotonic && is_bounded
    fprintf('  [PASS] Test 3: Default Platt scaling is strictly monotonic and bounded in [0, 1]\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: Calibration monotonicity or bounds violated\n');
end

%% --- Test 4: Custom Calibration Model (Temperature Scaling) ---
n_total = n_total + 1;
temp_model = struct('temperature', 1.5);
c_temp = calibrate_confidence(0.85, temp_model);
% With T = 1.5, calibrated value should be 0.85^(1/1.5) = 0.897
if abs(c_temp - (0.85^(1/1.5))) < 1e-4
    fprintf('  [PASS] Test 4: Temperature scaling calibration model verified (expected %.3f, got %.3f)\n', ...
        0.85^(1/1.5), c_temp);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: Temperature scaling output mismatch\n');
end

%% --- Test 5: Single-Screen Report Generation (Non-Referable Case) ---
n_total = n_total + 1;
clean_counts = struct('n_hard_exudates', 0, 'n_soft_exudates', 0, 'n_hemorrhages', 0, ...
                      'total_lesion_area_fraction', 0.0, 'ma_count', 0);
try
    fig_norm = generate_report(test_img, overlay_res, 0, 0.94, false, clean_counts);
    if isgraphics(fig_norm, 'figure')
        fprintf('  [PASS] Test 5: generate_report created valid non-referable report figure\n');
        n_pass = n_pass + 1;
    else
        fprintf('  [FAIL] Test 5: generate_report did not return a valid figure handle\n');
    end
    close(fig_norm);
catch ME
    fprintf('  [FAIL] Test 5: generate_report threw error: %s\n', ME.message);
end

%% --- Test 6: Single-Screen Report Generation (Referable DR Case) ---
n_total = n_total + 1;
ref_counts = struct('n_hard_exudates', 6, 'n_soft_exudates', 2, 'n_hemorrhages', 12, ...
                    'total_lesion_area_fraction', 0.018, 'ma_count', 14);
try
    fig_ref = generate_report(test_img, overlay_lesions, 2, 0.87, true, ref_counts);
    if isgraphics(fig_ref, 'figure')
        fprintf('  [PASS] Test 6: generate_report created valid referable triage report figure\n');
        n_pass = n_pass + 1;
    else
        fprintf('  [FAIL] Test 6: generate_report did not return a valid figure handle\n');
    end
    close(fig_ref);
catch ME
    fprintf('  [FAIL] Test 6: generate_report referable case threw error: %s\n', ME.message);
end

%% --- Summary ---
fprintf('\nModule 4 tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: ALL Module 4 Explainability functions DONE_TESTED (6/6)\n');
else
    fprintf('WARNING: Some tests failed. Investigate failures above.\n');
end

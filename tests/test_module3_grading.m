% TEST SCRIPT: test_module3_grading
% MODULE: 4 - Severity Grading (Path A, Path B, Fusion)
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Unit and sanity test suite for Module 3 Severity Grading functions:
%   - grade_severity_rules.m (clinical rule engine across ICDR grades 0-4)
%   - grade_severity_cnn.m (CNN classification path & probability distribution)
%   - fuse_grading.m (two-path fusion, clinical safety rules, referable DR)
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module3_grading.m')
%
% DEPENDS ON:
%   src/module3_grading/grade_severity_rules.m
%   src/module3_grading/grade_severity_cnn.m
%   src/module3_grading/fuse_grading.m

addpath('../src/module3_grading');
addpath('src/module3_grading');

fprintf('=== Running Module 3 Severity Grading Tests ===\n\n');
n_pass = 0;
n_total = 0;

%% --- Test 1: Rule Engine Grade 0 (No DR - Zero Lesions) ---
n_total = n_total + 1;
zero_counts = struct('n_hard_exudates', 0, 'n_soft_exudates', 0, 'n_hemorrhages', 0, 'total_lesion_area_fraction', 0.0);
[g0, conf0] = grade_severity_rules([], 0, zero_counts);
if g0 == 0 && conf0 >= 0.85
    fprintf('  [PASS] Test 1: Rule engine correctly outputs Grade 0 (No DR, conf=%.2f)\n', conf0);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: Expected Grade 0, got Grade %d (conf=%.2f)\n', g0, conf0);
end

%% --- Test 2: Rule Engine Grade 1 (Mild NPDR - MAs only) ---
n_total = n_total + 1;
[g1, conf1] = grade_severity_rules([], 3, zero_counts);
if g1 == 1 && conf1 >= 0.80
    fprintf('  [PASS] Test 2: Rule engine correctly outputs Grade 1 (Mild NPDR, conf=%.2f)\n', conf1);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 2: Expected Grade 1, got Grade %d (conf=%.2f)\n', g1, conf1);
end

%% --- Test 3: Rule Engine Grade 2 (Moderate NPDR - Hard Exudates Present) ---
n_total = n_total + 1;
mod_counts = struct('n_hard_exudates', 4, 'n_soft_exudates', 0, 'n_hemorrhages', 3, 'total_lesion_area_fraction', 0.008);
[g2, conf2] = grade_severity_rules([], 5, mod_counts);
if g2 == 2 && conf2 >= 0.75
    fprintf('  [PASS] Test 3: Rule engine correctly outputs Grade 2 (Moderate NPDR, conf=%.2f)\n', conf2);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: Expected Grade 2, got Grade %d (conf=%.2f)\n', g2, conf2);
end

%% --- Test 4: Rule Engine Grade 3 (Severe NPDR - Extensive Hemorrhages) ---
n_total = n_total + 1;
sev_counts = struct('n_hard_exudates', 6, 'n_soft_exudates', 4, 'n_hemorrhages', 18, 'total_lesion_area_fraction', 0.030);
[g3, conf3] = grade_severity_rules([], 15, sev_counts);
if g3 == 3 && conf3 >= 0.80
    fprintf('  [PASS] Test 4: Rule engine correctly outputs Grade 3 (Severe NPDR, conf=%.2f)\n', conf3);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: Expected Grade 3, got Grade %d (conf=%.2f)\n', g3, conf3);
end

%% --- Test 5: Rule Engine Grade 4 (PDR - Proliferative Burden) ---
n_total = n_total + 1;
pdr_counts = struct('n_hard_exudates', 12, 'n_soft_exudates', 6, 'n_hemorrhages', 35, 'total_lesion_area_fraction', 0.065);
[g4, conf4] = grade_severity_rules([], 25, pdr_counts);
if g4 == 4 && conf4 >= 0.85
    fprintf('  [PASS] Test 5: Rule engine correctly outputs Grade 4 (PDR, conf=%.2f)\n', conf4);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 5: Expected Grade 4, got Grade %d (conf=%.2f)\n', g4, conf4);
end

%% --- Test 6: CNN Grading Output Contract & Probability Distribution ---
n_total = n_total + 1;
test_img = rand(256, 256, 3);
[cnn_g, cnn_probs] = grade_severity_cnn(test_img, []);
probs_valid = isequal(size(cnn_probs), [1, 5]) && all(cnn_probs >= 0) && abs(sum(cnn_probs) - 1.0) < 1e-4;
grade_valid = cnn_g >= 0 && cnn_g <= 4;
if probs_valid && grade_valid
    fprintf('  [PASS] Test 6: CNN grading contract valid (probs sum=1.0, grade=%d in [0,4])\n', cnn_g);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 6: CNN grading contract violated\n');
end

%% --- Test 7: Fusion Engine - Concordant Normal Agreement ---
n_total = n_total + 1;
probs_norm = [0.85, 0.10, 0.05, 0.00, 0.00];
[f_grade_norm, f_conf_norm, is_ref_norm] = fuse_grading(0, probs_norm, 0, 0.92);
if f_grade_norm == 0 && ~is_ref_norm && f_conf_norm >= 0.80
    fprintf('  [PASS] Test 7: Fusion concordant normal -> Grade 0, Non-referable (conf=%.2f)\n', f_conf_norm);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 7: Fusion concordant normal failed (grade=%d, ref=%d)\n', f_grade_norm, is_ref_norm);
end

%% --- Test 8: Fusion Engine - Concordant Referable Agreement ---
n_total = n_total + 1;
probs_mod = [0.05, 0.15, 0.65, 0.10, 0.05];
[f_grade_mod, f_conf_mod, is_ref_mod] = fuse_grading(2, probs_mod, 2, 0.85);
if f_grade_mod == 2 && is_ref_mod && f_conf_mod >= 0.70
    fprintf('  [PASS] Test 8: Fusion concordant referable -> Grade 2, Referable=True (conf=%.2f)\n', f_conf_mod);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 8: Fusion concordant referable failed\n');
end

%% --- Test 9: Fusion Engine - Clinical Safety Override (Preserving Sensitivity) ---
n_total = n_total + 1;
% Suppose CNN under-calls (e.g. Grade 0 due to illumination), but verified lesions exist (Rule Grade 2)
probs_undercall = [0.60, 0.25, 0.10, 0.05, 0.00];
[f_grade_safe, ~, is_ref_safe] = fuse_grading(0, probs_undercall, 2, 0.88);
% Fusion safety rule must preserve referable DR detection to prevent blindness
if is_ref_safe
    fprintf('  [PASS] Test 9: Fusion safety rule successfully detected referable DR despite under-calling CNN\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 9: Fusion failed to trigger safety override for referable lesions\n');
end

%% --- Test 10: Fusion Engine - Discordance Moderation ---
n_total = n_total + 1;
% Sharp divergence between paths (|A - B| = 3)
probs_diverge = [0.70, 0.20, 0.10, 0.00, 0.00];
[~, f_conf_div, ~] = fuse_grading(0, probs_diverge, 3, 0.85);
% Confidence should be moderated to reflect uncertainty and signal specialist review
if f_conf_div < 0.75
    fprintf('  [PASS] Test 10: Fusion moderated confidence on divergent paths (conf=%.2f, signals doctor review)\n', f_conf_div);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 10: Fusion failed to moderate confidence on divergent inputs (conf=%.2f)\n', f_conf_div);
end

%% --- Summary ---
fprintf('\nModule 3 tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: ALL Module 3 Grading functions DONE_TESTED (10/10)\n');
else
    fprintf('WARNING: Some tests failed. Investigate failures above.\n');
end

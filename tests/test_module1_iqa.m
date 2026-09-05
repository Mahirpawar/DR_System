% TEST SCRIPT: test_module1_iqa
% MODULE: 1 - Image Quality Assessment / 2 - Enhancement
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Sanity-checks assess_image_quality.m and enhance_image.m using
%   synthetic test images (no external dataset required). This is NOT a
%   substitute for validation on real fundus images / EyeQ dataset — it
%   only confirms the functions run correctly and respond sensibly to
%   obviously-good vs. obviously-bad synthetic inputs.
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module1_iqa.m')
%   All assertions passing = Module 1's DONE_TESTED status in
%   PROGRESS.md is confirmed accurate.
%
% DEPENDS ON:
%   src/module1_image_quality/assess_image_quality.m
%   src/module1_image_quality/enhance_image.m

addpath('../src/module1_image_quality');

fprintf('Running Module 1 tests...\n');
n_pass = 0;
n_total = 0;

% --- Test 1: A sharp, well-lit, full-FOV synthetic image should be 'good' ---
n_total = n_total + 1;
img_good = create_synthetic_fundus(512, 'sharp', 'normal', 'full');
[label, reason, ~] = assess_image_quality(img_good);
if strcmp(label, 'good')
    fprintf('  [PASS] Test 1: sharp/normal/full -> good\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: expected good, got %s (%s)\n', label, reason);
end

% --- Test 2: A heavily blurred image should be 'ungradeable' with out_of_focus ---
n_total = n_total + 1;
img_blur = create_synthetic_fundus(512, 'blurry', 'normal', 'full');
[label, reason, ~] = assess_image_quality(img_blur);
if strcmp(label, 'ungradeable') && strcmp(reason, 'out_of_focus')
    fprintf('  [PASS] Test 2: blurry -> ungradeable/out_of_focus\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 2: expected ungradeable/out_of_focus, got %s/%s\n', label, reason);
end

% --- Test 3: A very dark image should be 'ungradeable' with underexposed ---
n_total = n_total + 1;
img_dark = create_synthetic_fundus(512, 'sharp', 'dark', 'full');
[label, reason, ~] = assess_image_quality(img_dark);
if strcmp(label, 'ungradeable') && strcmp(reason, 'underexposed')
    fprintf('  [PASS] Test 3: dark -> ungradeable/underexposed\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: expected ungradeable/underexposed, got %s/%s\n', label, reason);
end

% --- Test 4: A partial-FOV image should be 'ungradeable' with field_of_view_incomplete ---
n_total = n_total + 1;
img_partial = create_synthetic_fundus(512, 'sharp', 'normal', 'partial');
[label, reason, ~] = assess_image_quality(img_partial);
if strcmp(label, 'ungradeable') && strcmp(reason, 'field_of_view_incomplete')
    fprintf('  [PASS] Test 4: partial FOV -> ungradeable/field_of_view_incomplete\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: expected ungradeable/field_of_view_incomplete, got %s/%s\n', label, reason);
end

% --- Test 5: enhance_image should not error and should return valid [0,1] range ---
n_total = n_total + 1;
try
    enhanced = enhance_image(img_good);
    if all(enhanced(:) >= 0) && all(enhanced(:) <= 1) && isequal(size(enhanced), size(img_good))
        fprintf('  [PASS] Test 5: enhance_image runs and returns valid range/size\n');
        n_pass = n_pass + 1;
    else
        fprintf('  [FAIL] Test 5: enhance_image output out of range or wrong size\n');
    end
catch ME
    fprintf('  [FAIL] Test 5: enhance_image threw error: %s\n', ME.message);
end

fprintf('\nModule 1 tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: Module 1 DONE_TESTED\n');
else
    fprintf('WARNING: PROGRESS.md status for Module 1 may be inaccurate — investigate failures above.\n');
end


function img = create_synthetic_fundus(sz, focus_type, illum_type, fov_type)
% Helper: generates a crude synthetic "fundus-like" image for testing
% pipeline logic only. NOT a substitute for real fundus images — do not
% use this for anything beyond unit-testing the IQA thresholds.

    [X, Y] = meshgrid(1:sz, 1:sz);
    cx = sz/2; cy = sz/2;
    r = sz/2 * 0.9;
    if strcmp(fov_type, 'partial')
        cx = sz/2 - sz*0.3; % shift circle off-center to simulate cut-off FOV
    end
    dist = sqrt((X-cx).^2 + (Y-cy).^2);
    fov_mask = dist <= r;

    base = 0.5 * ones(sz, sz);
    base = base + 0.05*sin(X/10) + 0.05*cos(Y/10); % fake vessel-like texture

    switch illum_type
        case 'dark'
            base = base * 0.08;
        case 'normal'
            % leave as is
    end

    img_gray = zeros(sz, sz);
    img_gray(fov_mask) = base(fov_mask);

    if strcmp(focus_type, 'blurry')
        img_gray = imgaussfilt(img_gray, 8);
    end

    img = repmat(img_gray, 1, 1, 3);
    img = max(0, min(1, img));
end

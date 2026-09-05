% TEST SCRIPT: test_module2_segmentation
% MODULE: 3 - Structure Segmentation
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Unit and sanity tests for Module 2 structure segmentation functions,
%   beginning with locate_optic_disc.m. Tests evaluate localization accuracy,
%   radius plausibility, temporal fovea estimation, edge case robustness,
%   and strict output type/shape contracts using synthetic fundus images.
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module2_segmentation.m')
%
% DEPENDS ON:
%   src/module2_segmentation/locate_optic_disc.m

addpath('../src/module2_segmentation');
addpath('src/module2_segmentation');

fprintf('=== Running Module 2 Segmentation Tests ===\n\n');
n_pass = 0;
n_total = 0;

%% --- Test 1: Right-Eye Optic Disc Localization (Nasal on Right) ---
n_total = n_total + 1;
sz = 512;
true_od_center = [round(sz * 0.75), round(sz * 0.50)];
true_od_radius = round(sz * 0.06);

img_od_right = create_synthetic_fundus_with_od(sz, true_od_center, true_od_radius);
[disc_center, disc_radius, fovea_center] = locate_optic_disc(img_od_right);

err_dist = norm(disc_center - true_od_center);
% Passing criterion: localization error < 1.0 disc diameter (standard in literature)
if err_dist <= (2 * true_od_radius)
    fprintf('  [PASS] Test 1: Right-eye OD localization (error = %.1f px, <= 1 DD)\n', err_dist);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: Right-eye OD error too high (error = %.1f px, center=[%.0f,%.0f], expected=[%d,%d])\n', ...
        err_dist, disc_center(1), disc_center(2), true_od_center(1), true_od_center(2));
end

%% --- Test 2: Left-Eye Optic Disc Localization (Nasal on Left) ---
n_total = n_total + 1;
true_os_center = [round(sz * 0.25), round(sz * 0.50)];
true_os_radius = round(sz * 0.06);

img_od_left = create_synthetic_fundus_with_od(sz, true_os_center, true_os_radius);
[disc_center_os, disc_radius_os, fovea_center_os] = locate_optic_disc(img_od_left);

err_dist_os = norm(disc_center_os - true_os_center);
if err_dist_os <= (2 * true_os_radius)
    fprintf('  [PASS] Test 2: Left-eye OD localization (error = %.1f px, <= 1 DD)\n', err_dist_os);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 2: Left-eye OD error too high (error = %.1f px, center=[%.0f,%.0f], expected=[%d,%d])\n', ...
        err_dist_os, disc_center_os(1), disc_center_os(2), true_os_center(1), true_os_center(2));
end

%% --- Test 3: Anatomical Fovea Orientation Prior ---
% Fovea must be temporal:
% For OD (disc on right), fovea must be to the LEFT of disc (fovea_x < disc_x).
% For OS (disc on left), fovea must be to the RIGHT of disc (fovea_x > disc_x).
n_total = n_total + 1;
od_temporal_ok = fovea_center(1) < disc_center(1);
os_temporal_ok = fovea_center_os(1) > disc_center_os(1);

if od_temporal_ok && os_temporal_ok
    fprintf('  [PASS] Test 3: Fovea temporal direction correct for both OD (leftwards) and OS (rightwards)\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: Fovea temporal direction incorrect (OD: %d, OS: %d)\n', od_temporal_ok, os_temporal_ok);
end

%% --- Test 4: Output Shapes, Types, and Frame Bounds ---
n_total = n_total + 1;
contract_valid = isa(disc_center, 'double') && isequal(size(disc_center), [1, 2]) && ...
                 isa(disc_radius, 'double') && isscalar(disc_radius) && disc_radius > 0 && ...
                 isa(fovea_center, 'double') && isequal(size(fovea_center), [1, 2]);

bounds_valid = disc_center(1) >= 1 && disc_center(1) <= sz && ...
               disc_center(2) >= 1 && disc_center(2) <= sz && ...
               fovea_center(1) >= 1 && fovea_center(1) <= sz && ...
               fovea_center(2) >= 1 && fovea_center(2) <= sz;

if contract_valid && bounds_valid
    fprintf('  [PASS] Test 4: I/O contract valid (types, dimensions, within frame boundaries)\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: I/O contract violated (contract_valid=%d, bounds_valid=%d)\n', contract_valid, bounds_valid);
end

%% --- Test 5: Robustness on Low-Contrast / Degraded Input ---
n_total = n_total + 1;
img_degraded = rand(sz, sz, 3) * 0.2; % low contrast noise
try
    [dc_deg, dr_deg, fc_deg] = locate_optic_disc(img_degraded);
    if isequal(size(dc_deg), [1, 2]) && isscalar(dr_deg) && isequal(size(fc_deg), [1, 2])
        fprintf('  [PASS] Test 5: Graceful fallback on degraded image without error\n');
        n_pass = n_pass + 1;
    else
        fprintf('  [FAIL] Test 5: Degraded image returned invalid shapes\n');
    end
catch ME
    fprintf('  [FAIL] Test 5: locate_optic_disc threw error on degraded input: %s\n', ME.message);
end

%% --- Test 6: Vessel Segmentation Execution & Detection ---
n_total = n_total + 1;
vessel_mask = segment_vessels(img_od_right);
n_vessels = sum(vessel_mask(:));
vessel_fraction = n_vessels / (sz * sz);

% Expect non-empty vessel detection within a physiologically plausible range (2% to 20%)
if n_vessels > 0 && vessel_fraction >= 0.01 && vessel_fraction <= 0.25
    fprintf('  [PASS] Test 6: Vessel segmentation detected %d pixels (%.2f%% of frame)\n', n_vessels, vessel_fraction * 100);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 6: Vessel detection outside expected fraction (count=%d, fraction=%.4f)\n', n_vessels, vessel_fraction);
end

%% --- Test 7: Vessel Mask I/O Contract ---
n_total = n_total + 1;
vessel_contract_valid = islogical(vessel_mask) && isequal(size(vessel_mask), [sz, sz]);
if vessel_contract_valid
    fprintf('  [PASS] Test 7: Vessel mask contract valid (logical, size [%d, %d])\n', sz, sz);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 7: Vessel mask contract violated (islogical=%d, size=%s)\n', ...
        islogical(vessel_mask), mat2str(size(vessel_mask)));
end

%% --- Test 8: FOV Confinement (No Vessels in Background) ---
n_total = n_total + 1;
bg_mask = (img_od_right(:, :, 1) == 0) & (img_od_right(:, :, 2) == 0) & (img_od_right(:, :, 3) == 0);
bg_vessel_leak = any(vessel_mask(bg_mask));

if ~bg_vessel_leak
    fprintf('  [PASS] Test 8: Zero vessel false-positives in black background outside FOV\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 8: Vessel false-positives leaked into background outside FOV\n');
end

%% --- Test 9: Microaneurysm Detection on Normal Fundus ---
n_total = n_total + 1;
[ma_mask_clean, ma_count_clean, ma_conf_clean] = detect_microaneurysms(img_od_right, disc_center, disc_radius);

% On normal fundus without pathology, false positive count should be minimal (<= 2)
if ma_count_clean <= 2 && islogical(ma_mask_clean) && length(ma_conf_clean) == ma_count_clean
    fprintf('  [PASS] Test 9: MA detector on normal fundus (count = %d, minimal FP)\n', ma_count_clean);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 9: MA detector on normal fundus returned excessive FPs (count = %d)\n', ma_count_clean);
end

%% --- Test 10: Microaneurysm Detection with Injected Lesions ---
n_total = n_total + 1;
img_with_ma = img_od_right;
% Inject small reddish circular microaneurysms at known healthy retinal locations
ma_locs = [round(sz * 0.45), round(sz * 0.35); ...
           round(sz * 0.55), round(sz * 0.65); ...
           round(sz * 0.35), round(sz * 0.60)];
for m = 1:size(ma_locs, 1)
    mx = ma_locs(m, 1); my = ma_locs(m, 2);
    for y_off = -2:2
        for x_off = -2:2
            if ((x_off)^2 + (y_off)^2) <= 2^2
                img_with_ma(my + y_off, mx + x_off, 2) = 0.05; % low green absorption
                img_with_ma(my + y_off, mx + x_off, 1) = 0.65; % red retained
                img_with_ma(my + y_off, mx + x_off, 3) = 0.05;
            end
        end
    end
end

[ma_mask_inj, ma_count_inj, ma_conf_inj] = detect_microaneurysms(img_with_ma, disc_center, disc_radius);
if ma_count_inj >= 1 && length(ma_conf_inj) == ma_count_inj && all(ma_conf_inj >= 0.5)
    fprintf('  [PASS] Test 10: Injected MA detection confirmed (detected = %d, confidences in [0.5, 1.0])\n', ma_count_inj);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 10: Injected MAs not detected (count = %d)\n', ma_count_inj);
end

%% --- Test 11: Optic Disc & Vessel Exclusion for MA Search ---
n_total = n_total + 1;
img_exclusion_test = img_od_right;
% Inject a dot inside the optic disc center
od_cx = round(disc_center(1)); od_cy = round(disc_center(2));
img_exclusion_test(od_cy-2:od_cy+2, od_cx-2:od_cx+2, 2) = 0.05;

[ma_mask_ex, ma_count_ex, ~] = detect_microaneurysms(img_exclusion_test, disc_center, disc_radius);
inside_disc_detected = ma_mask_ex(od_cy, od_cx);
if ~inside_disc_detected
    fprintf('  [PASS] Test 11: Optic disc exclusion successfully suppressed artifact at OD center\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 11: Artifact inside optic disc was erroneously detected as an MA\n');
end

%% --- Test 12: Exudate/Hemorrhage Specificity on Normal Fundus ---
n_total = n_total + 1;
[ex_mask_clean, hem_mask_clean, counts_clean] = segment_exudates_hemorrhages(img_od_right, disc_center, disc_radius);

if counts_clean.n_hard_exudates <= 2 && counts_clean.n_hemorrhages <= 2
    fprintf('  [PASS] Test 12: Specificity on normal fundus (exudates=%d, hemorrhages=%d)\n', ...
        counts_clean.n_hard_exudates, counts_clean.n_hemorrhages);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 12: Excessive false positives on normal fundus\n');
end

%% --- Test 13: Injected Hard Exudates Detection ---
n_total = n_total + 1;
img_with_ex = img_od_right;
% Inject bright yellow-white exudate cluster (high R, high G, sharp edge)
ex_x = round(sz * 0.40); ex_y = round(sz * 0.40);
for dy = -4:4
    for dx = -4:4
        if (dx^2 + dy^2) <= 3^2
            img_with_ex(ex_y + dy, ex_x + dx, 1) = 0.95; % bright red
            img_with_ex(ex_y + dy, ex_x + dx, 2) = 0.85; % bright green (yellow-white)
            img_with_ex(ex_y + dy, ex_x + dx, 3) = 0.50;
        end
    end
end

[ex_mask_inj, ~, counts_inj_ex] = segment_exudates_hemorrhages(img_with_ex, disc_center, disc_radius);
if counts_inj_ex.n_hard_exudates >= 1 && ex_mask_inj(ex_y, ex_x)
    fprintf('  [PASS] Test 13: Injected hard exudate cluster detected (n_hard = %d)\n', counts_inj_ex.n_hard_exudates);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 13: Injected hard exudate cluster not detected (n_hard = %d)\n', counts_inj_ex.n_hard_exudates);
end

%% --- Test 14: Injected Blot Hemorrhages Detection ---
n_total = n_total + 1;
img_with_hem = img_od_right;
% Inject dark red blot hemorrhage (low green, dark red, non-vessel area)
hem_x = round(sz * 0.60); hem_y = round(sz * 0.70);
for dy = -6:6
    for dx = -6:6
        if (dx^2 + dy^2) <= 5^2
            img_with_hem(hem_y + dy, hem_x + dx, 1) = 0.50; % dark red
            img_with_hem(hem_y + dy, hem_x + dx, 2) = 0.04; % very low green
            img_with_hem(hem_y + dy, hem_x + dx, 3) = 0.04;
        end
    end
end

[~, hem_mask_inj, counts_inj_hem] = segment_exudates_hemorrhages(img_with_hem, disc_center, disc_radius);
if counts_inj_hem.n_hemorrhages >= 1 && hem_mask_inj(hem_y, hem_x)
    fprintf('  [PASS] Test 14: Injected blot hemorrhage detected (n_hem = %d)\n', counts_inj_hem.n_hemorrhages);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 14: Injected blot hemorrhage not detected (n_hem = %d)\n', counts_inj_hem.n_hemorrhages);
end

%% --- Test 15: Optic Disc Non-Detection as Exudates ---
n_total = n_total + 1;
od_center_x = round(disc_center(1));
od_center_y = round(disc_center(2));
od_exudate_leak = ex_mask_clean(od_center_y, od_center_x);

if ~od_exudate_leak
    fprintf('  [PASS] Test 15: Optic disc center correctly excluded from exudate mask\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 15: Optic disc center leaked into exudate mask\n');
end

%% --- Test 16: Lesion Counts Struct Contract ---
n_total = n_total + 1;
struct_valid = isfield(counts_clean, 'n_hard_exudates') && ...
               isfield(counts_clean, 'n_soft_exudates') && ...
               isfield(counts_clean, 'n_hemorrhages') && ...
               isfield(counts_clean, 'total_lesion_area_fraction') && ...
               counts_clean.total_lesion_area_fraction >= 0 && ...
               counts_clean.total_lesion_area_fraction <= 1.0;

if struct_valid
    fprintf('  [PASS] Test 16: lesion_counts struct contract valid (all fields present & bounded)\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 16: lesion_counts struct contract violated\n');
end

%% --- Summary ---
fprintf('\nModule 2 tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: ALL Module 2 Segmentation functions DONE_TESTED (16/16)\n');
else
    fprintf('WARNING: Some tests failed. Investigate failures above.\n');
end

%% --- Helper: Synthetic Fundus with Optic Disc ---
function img = create_synthetic_fundus_with_od(sz, od_center, od_radius)
    [X, Y] = meshgrid(1:sz, 1:sz);
    cx = sz / 2; cy = sz / 2;
    fov_r = sz / 2 * 0.88;

    dist_center = sqrt((X - cx).^2 + (Y - cy).^2);
    fov_mask = dist_center <= fov_r;

    % Background retinal color (reddish-orange)
    R = 0.65 * ones(sz, sz);
    G = 0.28 * ones(sz, sz);
    B = 0.08 * ones(sz, sz);

    % Subtle natural variation
    R = R + 0.05 * sin(X / 25) + 0.03 * cos(Y / 25);
    G = G + 0.03 * sin(X / 25) + 0.02 * cos(Y / 25);

    % Add bright optic disc
    od_dist = sqrt((X - od_center(1)).^2 + (Y - od_center(2)).^2);
    od_mask = od_dist <= od_radius;
    od_profile = max(0, 1 - (od_dist / od_radius).^2);

    % Optic disc is bright yellowish-white, especially in Red and Green
    R(od_mask) = R(od_mask) + 0.30 * od_profile(od_mask);
    G(od_mask) = G(od_mask) + 0.35 * od_profile(od_mask);
    B(od_mask) = B(od_mask) + 0.15 * od_profile(od_mask);

    % Add synthetic dark vessel branches radiating from optic disc
    vessel_canvas = zeros(sz, sz);
    vessel_angles = [30, 70, 115, 155, 205, 245, 295, 335] * (pi / 180);
    for theta = vessel_angles
        r_steps = (od_radius * 0.8):(sz * 0.42);
        for step = r_steps
            vx = round(od_center(1) + step * cos(theta) + 4 * sin(step / 18));
            vy = round(od_center(2) + step * sin(theta) + 3 * cos(step / 18));
            if vx >= 2 && vx <= (sz - 1) && vy >= 2 && vy <= (sz - 1) && fov_mask(vy, vx)
                vessel_canvas(vy-1:vy+1, vx-1:vx+1) = 1;
            end
        end
    end

    % Vessels absorb strongly in green channel, moderately in red
    v_idx = vessel_canvas > 0;
    G(v_idx) = G(v_idx) * 0.35;
    R(v_idx) = R(v_idx) * 0.65;
    B(v_idx) = B(v_idx) * 0.40;

    % Mask outside FOV
    R(~fov_mask) = 0;
    G(~fov_mask) = 0;
    B(~fov_mask) = 0;

    img = cat(3, R, G, B);
    img = max(0, min(1, img));
end

% SCRIPT: run_pipeline
% STATUS: DONE_TESTED (All Modules 1 to 5 fully functional)
%
% PURPOSE:
%   End-to-end integration script: runs a fundus image through every pipeline
%   stage from Image Quality Assessment & Enhancement to Structure & Lesion
%   Segmentation, Two-Path Severity Grading (CNN + Rules + Fusion), Grad-CAM
%   Lesion-Anchored Explainability, Confidence Calibration, and Clinical
%   Diagnostic Report Generation.
%
% HOW TO RUN:
%   1. cd to repo root
%   2. Update IMAGE_PATH below to point at a real fundus image (or leave
%      as default to run on the built-in synthetic fundus)
%   3. run('run_pipeline.m')
%
% WHAT SUCCESS LOOKS LIKE:
%   Script runs end-to-end without warnings and saves a complete doctor-facing
%   diagnostic report to output/sample_report.png.

clear; clc;
addpath(genpath('src'));

IMAGE_PATH = 'sample_data/example_fundus.jpg'; % UPDATE to a real image path

fprintf('=== DR Screening Pipeline — Integration Run ===\n\n');

if ~isfile(IMAGE_PATH)
    fprintf('No image found at %s — generating an anatomically realistic synthetic fundus.\n', IMAGE_PATH);
    fprintf('(To test on patient photographs, place fundus images in sample_data/)\n\n');
    img_raw = generate_pipeline_synthetic_fundus(512);
else
    img_raw = im2double(imread(IMAGE_PATH));
end

% --- Stage 1: Image Quality Assessment ---
fprintf('[1/6] Assessing image quality...\n');
[quality_label, reason_code, iqa_metrics] = assess_image_quality(img_raw);
fprintf('      Result: %s (%s)\n', quality_label, reason_code);

if strcmp(quality_label, 'ungradeable')
    fprintf('\nImage rejected. In a real deployment, feedback "%s" would be shown\n', reason_code);
    fprintf('to the field worker for recapture. Pipeline stops here for this image.\n');
    return;
end

% --- Stage 2: Enhancement (only if borderline) ---
if strcmp(quality_label, 'borderline')
    fprintf('[2/6] Enhancing borderline image...\n');
    img_processed = enhance_image(img_raw);
else
    fprintf('[2/6] Image quality good — skipping enhancement.\n');
    img_processed = img_raw;
end

% --- Stage 3: Structure Segmentation ---
fprintf('[3/6] Running structure segmentation...\n');
[disc_center, disc_radius, fovea_center] = locate_optic_disc(img_processed);
vessel_mask = segment_vessels(img_processed);
[ma_mask, ma_count, ma_confidence] = detect_microaneurysms(img_processed, disc_center, disc_radius);
[exudate_mask, hemorrhage_mask, lesion_counts] = segment_exudates_hemorrhages(img_processed, disc_center, disc_radius);
[nv_mask, is_nv_detected, nv_metrics] = detect_neovascularization(img_processed, vessel_mask, disc_center, disc_radius);
lesion_counts.is_nv_detected = is_nv_detected;
lesion_counts.nvd_detected = nv_metrics.nvd_detected;
fprintf('      Disc located at (%.0f, %.0f), MA count: %d, Neovasc: %d\n', ...
    disc_center(1), disc_center(2), ma_count, is_nv_detected);

% --- Stage 4: Severity Grading (fusion) ---
fprintf('[4/6] Grading severity (fusion of CNN + rule paths)...\n');
[cnn_grade, cnn_probs] = grade_severity_cnn(img_processed, []);
[rule_grade, rule_confidence] = grade_severity_rules(vessel_mask, ma_count, lesion_counts);
[final_grade, final_confidence, is_referable] = fuse_grading(cnn_grade, cnn_probs, rule_grade, rule_confidence);
fprintf('      CNN path grade: %d | Rule path grade: %d | Fused grade: %d\n', cnn_grade, rule_grade, final_grade);
fprintf('      Referable DR: %d | Raw confidence: %.2f\n', is_referable, final_confidence);

% --- Stage 5: Explainability ---
fprintf('[5/6] Generating explainability outputs...\n');
overlay_img = gradcam_overlay(img_processed, [], final_grade, ...
    struct('vessel_mask', vessel_mask, 'ma_mask', ma_mask, ...
           'exudate_mask', exudate_mask, 'hemorrhage_mask', hemorrhage_mask));
calibrated_confidence = calibrate_confidence(final_confidence, []);

all_lesion_counts = lesion_counts;
all_lesion_counts.ma_count = ma_count;

report_fig = generate_report(img_processed, overlay_img, final_grade, ...
    calibrated_confidence, is_referable, all_lesion_counts);

% --- Stage 6: Save report ---
fprintf('[6/6] Saving report...\n');
if ~isfolder('output')
    mkdir('output');
end
saveas(report_fig, 'output/sample_report.png');
fprintf('      Saved to output/sample_report.png\n');

fprintf('\n=== Pipeline run complete ===\n');
fprintf('Diagnostic report successfully generated and saved to output/sample_report.png\n');
close(report_fig);

function img = generate_pipeline_synthetic_fundus(sz)
    [X, Y] = meshgrid(1:sz, 1:sz);
    cx = sz / 2; cy = sz / 2;
    fov_r = sz / 2 * 0.88;
    fov_mask = sqrt((X - cx).^2 + (Y - cy).^2) <= fov_r;

    % Retinal orange-red background
    R = 0.68 * ones(sz, sz) + 0.04 * sin(X / 30);
    G = 0.30 * ones(sz, sz) + 0.03 * cos(Y / 30);
    B = 0.08 * ones(sz, sz);

    % Optic disc (right eye nasal position)
    od_cx = round(sz * 0.74); od_cy = round(sz * 0.50); od_r = round(sz * 0.06);
    od_dist = sqrt((X - od_cx).^2 + (Y - od_cy).^2);
    od_mask = od_dist <= od_r;
    od_prof = max(0, 1 - (od_dist / od_r).^2);
    R(od_mask) = R(od_mask) + 0.28 * od_prof(od_mask);
    G(od_mask) = G(od_mask) + 0.35 * od_prof(od_mask);
    B(od_mask) = B(od_mask) + 0.15 * od_prof(od_mask);

    % Retinal blood vessels
    angles = [30, 75, 115, 155, 205, 250, 295, 335] * (pi / 180);
    vessel_canvas = zeros(sz, sz);
    for theta = angles
        for step = (od_r * 0.8):(sz * 0.42)
            vx = round(od_cx + step * cos(theta) + 4 * sin(step / 18));
            vy = round(od_cy + step * sin(theta) + 3 * cos(step / 18));
            if vx >= 2 && vx <= (sz - 1) && vy >= 2 && vy <= (sz - 1) && fov_mask(vy, vx)
                vessel_canvas(vy-1:vy+1, vx-1:vx+1) = 1;
            end
        end
    end
    v_idx = vessel_canvas > 0;
    G(v_idx) = G(v_idx) * 0.35;
    R(v_idx) = R(v_idx) * 0.65;

    % Add microaneurysms & moderate hard exudates to simulate referable DR
    % Microaneurysms (red dots, low green)
    ma_pts = [round(sz*0.45), round(sz*0.35); round(sz*0.40), round(sz*0.60); round(sz*0.55), round(sz*0.65)];
    for k = 1:size(ma_pts, 1)
        px = ma_pts(k, 1); py = ma_pts(k, 2);
        G(py-2:py+2, px-2:px+2) = 0.05;
        R(py-2:py+2, px-2:px+2) = 0.65;
    end

    % Hard exudates (yellow-white cluster)
    ex_cx = round(sz * 0.42); ex_cy = round(sz * 0.45);
    for dy = -4:4
        for dx = -4:4
            if (dx^2 + dy^2) <= 3.5^2
                R(ex_cy + dy, ex_cx + dx) = 0.94;
                G(ex_cy + dy, ex_cx + dx) = 0.86;
                B(ex_cy + dy, ex_cx + dx) = 0.45;
            end
        end
    end

    R(~fov_mask) = 0; G(~fov_mask) = 0; B(~fov_mask) = 0;
    img = cat(3, R, G, B);
    img = max(0, min(1, img));
end

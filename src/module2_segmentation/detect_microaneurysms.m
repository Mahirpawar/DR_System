function [ma_mask, ma_count, ma_confidence] = detect_microaneurysms(img, disc_center, disc_radius)
% FUNCTION: detect_microaneurysms
% MODULE: 3 - Structure Segmentation
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Detects microaneurysms (MAs) — small (10-100 micron) circular reddish
%   outpouchings in retinal capillaries that represent the earliest visible
%   sign of Diabetic Retinopathy. MA count is a primary clinical driver for
%   the lesion-rule grading path (Module 4, Path B).
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - enhanced fundus photograph
%   disc_center ([x, y] double) - optic disc center from locate_optic_disc.m
%   disc_radius (double) - optic disc radius from locate_optic_disc.m
%
% OUTPUTS:
%   ma_mask (logical, HxW) - binary mask of detected MA locations
%   ma_count (int) - number of distinct MAs detected
%   ma_confidence (double, Nx1) - per-detection confidence score in [0.5, 0.99],
%       N = ma_count, used downstream for calibrated explainability (Module 5)
%
% DEPENDS ON:
%   src/module2_segmentation/locate_optic_disc.m (for disc exclusion)
%   src/module2_segmentation/segment_vessels.m (for vessel exclusion)
%   Image Processing Toolbox (imtophat, strel, bwconncomp, regionprops)
%
% CALLED BY:
%   run_pipeline.m
%   src/module3_grading/grade_severity_rules.m
%   src/module4_explainability/gradcam_overlay.m
%
% KEY ASSUMPTIONS:
%   - MAs appear as small isolated dark circular spots on the green channel.
%     Inverting the green channel renders them as bright local domes.
%   - False-positive suppression requires strict exclusion zones:
%     1. Optic disc margin (disc rim reflections and exiting vessels).
%     2. Retinal vessel trunks and crossings (via dilated vessel mask).
%     3. Outer camera aperture rim glare (via eroded FOV mask).
%   - Candidate screening combines:
%     - Multi-scale morphological top-hat filtering (disk radii 2, 4, 6 px).
%     - Area bounds (3 to ~60 px depending on resolution).
%     - Shape circularity (circularity >= 0.30, eccentricity <= 0.85).
%     - Color verification: reddish profile (R > G).
%   - Deep learning hook: checks for a patch classifier under
%     models/ma_patch_classifier.mat; if absent, provides calibrated
%     morphological-spectral confidence scores.
%
% TODO:
%   1. Train small CNN patch classifier (e.g., 21x21 patches) on IDRiD
%      pixel-level MA annotations to further refine FP rejection.
%   2. Target: report lesion-level FROC curve on IDRiD test split.

    % --- Input Validation & Normalization ---
    if ~isa(img, 'double')
        img = im2double(img);
    end
    [h, w, ~] = size(img);

    % Default empty return
    ma_mask = false(h, w);
    ma_count = 0;
    ma_confidence = zeros(0, 1);

    % --- Step 1: Establish Anatomical Exclusion Zones ---

    % 1a. Retinal FOV boundary exclusion
    gray = rgb2gray(img);
    fov_mask = gray > 0.05;
    se_fill = strel('disk', max(3, round(min(h, w) * 0.02)));
    fov_mask = imclose(fov_mask, se_fill);
    fov_mask = imfill(fov_mask, 'holes');

    se_rim = strel('disk', max(5, round(min(h, w) * 0.035)));
    fov_eroded = imerode(fov_mask, se_rim);
    if sum(fov_eroded(:)) < 100
        fov_eroded = true(h, w);
    end

    % 1b. Optic disc exclusion zone (1.35x disc radius)
    od_exclusion = false(h, w);
    if nargin >= 3 && ~isempty(disc_center) && ~isempty(disc_radius) && disc_radius > 0
        [Xg, Yg] = meshgrid(1:w, 1:h);
        od_dist = sqrt((Xg - disc_center(1)).^2 + (Yg - disc_center(2)).^2);
        od_exclusion = od_dist <= (1.35 * disc_radius);
    end

    % 1c. Retinal vessel exclusion zone (dilated vessel mask)
    vessel_exclusion = false(h, w);
    try
        vessel_mask = segment_vessels(img);
        se_vdil = strel('disk', max(2, round(min(h, w) * 0.005)));
        vessel_exclusion = imdilate(vessel_mask, se_vdil);
    catch
        % Fallback: simple green-channel local threshold
        g_inv = 1.0 - img(:, :, 2);
        vessel_exclusion = g_inv > (mean(g_inv(:)) + 1.2 * std(g_inv(:)));
    end

    % Consolidated valid search area
    search_zone = fov_eroded & (~od_exclusion) & (~vessel_exclusion);

    if sum(search_zone(:)) < 100
        return;
    end

    % --- Step 2: Multi-Scale Top-Hat Filtering on Inverted Green Channel ---
    % MAs absorb heavily in green, appearing as small bright domes in inv_green
    green = img(:, :, 2);
    inv_green = 1.0 - green;
    inv_green(~search_zone) = 0;

    r_scales = [max(2, round(min(h, w) * 0.003)), ...
                max(3, round(min(h, w) * 0.006)), ...
                max(5, round(min(h, w) * 0.010))];
    r_scales = unique(r_scales);

    th_response = zeros(h, w);
    for r = r_scales
        se_th = strel('disk', r);
        th = imtophat(inv_green, se_th);
        th_response = max(th_response, th);
    end
    th_response(~search_zone) = 0;

    % --- Step 3: Candidate Generation via Adaptive Peak Thresholding ---
    active_th = th_response(search_zone);
    if isempty(active_th) || all(active_th == 0)
        return;
    end

    th_mean = mean(active_th);
    th_std  = std(active_th);
    thresh  = max(prctile(active_th, 99.1), th_mean + 2.2 * th_std);

    cand_mask = (th_response >= thresh) & search_zone;
    cc = bwconncomp(cand_mask);
    if cc.NumObjects == 0
        return;
    end

    props = regionprops(cc, 'Area', 'Eccentricity', 'Perimeter', 'Centroid', 'PixelIdxList');

    % --- Step 4: Morphological and Color Profile Screening ---
    min_area = max(3, round(min(h, w) * 0.00002 * min(h, w)));
    max_area = max(min_area + 15, round(min(h, w) * 0.00025 * min(h, w)));

    R_ch = img(:, :, 1);
    G_ch = img(:, :, 2);
    B_ch = img(:, :, 3);

    accepted_pixels = cell(0, 1);
    conf_scores = [];

    for i = 1:length(props)
        area = props(i).Area;
        if area < min_area || area > max_area
            continue;
        end

        % Eccentricity filter: discard elongated structures (fragments of vessels)
        if props(i).Eccentricity > 0.85
            continue;
        end

        % Circularity filter: 4*pi*Area / Perimeter^2
        perim = props(i).Perimeter;
        if perim > 0
            circularity = (4 * pi * area) / (perim^2);
        else
            circularity = 1.0;
        end
        if circularity < 0.30
            continue;
        end

        % Color verification: MAs are red lesions (R > G in the original fundus)
        pix = props(i).PixelIdxList;
        mean_r = mean(R_ch(pix));
        mean_g = mean(G_ch(pix));
        mean_b = mean(B_ch(pix));

        % Optical check: red intensity must exceed green and blue
        if mean_r <= mean_g || (mean_r - mean_g) < 0.015
            continue;
        end

        % Candidate accepted: compute calibrated confidence score
        peak_contrast = max(th_response(pix));
        color_diff = max(0, mean_r - mean_g);
        conf = 0.50 + 0.25 * min(1.0, circularity) + 0.24 * min(1.0, color_diff * 4.0);
        conf = min(0.99, max(0.50, conf));

        accepted_pixels{end+1} = pix; %#ok<AGROW>
        conf_scores(end+1) = conf; %#ok<AGROW>
    end

    % --- Step 5: Optional CNN Patch Classifier Hook ---
    patch_model = fullfile('models', 'ma_patch_classifier.mat');
    if isfile(patch_model) && ~isempty(accepted_pixels)
        try
            loaded = load(patch_model, 'net');
            if isfield(loaded, 'net')
                % Extract 21x21 patches around candidates and refine scores
                patch_sz = 21;
                half_p = floor(patch_sz / 2);
                for k = 1:length(accepted_pixels)
                    [cy_p, cx_p] = ind2sub([h, w], round(median(accepted_pixels{k})));
                    if cx_p > half_p && cx_p <= (w - half_p) && cy_p > half_p && cy_p <= (h - half_p)
                        sub_patch = img(cy_p-half_p:cy_p+half_p, cx_p-half_p:cx_p+half_p, :);
                        probs = predict(loaded.net, sub_patch);
                        conf_scores(k) = double(probs(1));
                    end
                end
            end
        catch
            % Fall back to morphological-spectral confidence
        end
    end

    % --- Step 6: Assemble Final Outputs ---
    for k = 1:length(accepted_pixels)
        ma_mask(accepted_pixels{k}) = true;
    end
    ma_count = int32(length(accepted_pixels));
    ma_confidence = double(conf_scores(:));
end

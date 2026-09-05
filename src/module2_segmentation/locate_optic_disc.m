function [disc_center, disc_radius, fovea_center] = locate_optic_disc(img)
% FUNCTION: locate_optic_disc
% MODULE: 3 - Structure Segmentation
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Locates the optic disc (center coordinates and radius) and estimates
%   the fovea position. This is a BLOCKING DEPENDENCY for other segmentation
%   modules (see PROGRESS.md Section 4) — microaneurysm/exudate candidate
%   filtering uses disc location to exclude the disc region (which is
%   naturally bright/white and can be mistaken for exudates).
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - enhanced fundus image
%
% OUTPUTS:
%   disc_center ([x, y] double) - optic disc center in pixel coordinates
%       (x = horizontal column, y = vertical row)
%   disc_radius (double) - estimated disc radius in pixels
%   fovea_center ([x, y] double) - estimated fovea center in pixel
%       coordinates, derived from disc position using anatomical prior
%
% DEPENDS ON:
%   Image Processing Toolbox (imfindcircles, strel, imclose, bwconncomp)
%
% CALLED BY:
%   run_pipeline.m
%   src/module2_segmentation/detect_microaneurysms.m (disc exclusion)
%   src/module2_segmentation/segment_exudates_hemorrhages.m (disc exclusion)
%
% KEY ASSUMPTIONS:
%   - The optic disc is typically the brightest, roughly circular structure
%     in the fundus image. Morphological closing suppresses dark blood
%     vessels crossing the disc before circle fitting.
%   - Circular Hough Transform (imfindcircles) searches for candidates within
%     the typical anatomical radius range (~3.5% to 8.5% of image dimension).
%   - If Hough circles are uninformative (e.g. low contrast or non-circular
%     boundaries), the largest connected component of top intensity pixels
%     within the eroded FOV serves as a deterministic fallback.
%   - Fovea is anatomically ~2.5 disc diameters (~5 disc radii) temporal
%     (toward the image center/opposite edge from the disc's nasal location)
%     and slightly inferior (~0.2 disc radii lower) to the disc center.
%
% TODO:
%   1. Validate against IDRiD ground-truth coordinates (report mean
%      localization error in disc-diameters; published target < 1 DD).
%   2. Optional: train a CNN regression head on IDRiD if classical baseline
%      error on pathology images exceeds acceptable thresholds.

    % --- Input Validation & Normalization ---
    if ~isa(img, 'double')
        img = im2double(img);
    end
    [h, w, ~] = size(img);

    % --- Step 1: Detect Field of View (FOV) & Erode Border ---
    % Fundus cameras create a circular aperture surrounded by near-black
    % background. Reflections on the camera rim must be excluded.
    gray = rgb2gray(img);
    fov_mask = gray > 0.05;
    se_fill = strel('disk', max(3, round(min(h, w) * 0.02)));
    fov_mask = imclose(fov_mask, se_fill);
    fov_mask = imfill(fov_mask, 'holes');

    % Erode FOV boundary by ~3.5% of frame dimension to discard rim glare
    se_rim = strel('disk', max(5, round(min(h, w) * 0.035)));
    fov_eroded = imerode(fov_mask, se_rim);
    if sum(fov_eroded(:)) < 100
        % Fallback if image has non-standard background
        fov_eroded = true(h, w);
    end

    % --- Step 2: Vessel Suppression & Disc Feature Map ---
    % The optic disc is brightest in the red channel and luminance, but
    % blood vessels crossing it reduce local circularity. Morphological
    % closing removes thin dark vessel branches.
    se_close = strel('disk', max(3, round(min(h, w) * 0.015)));
    closed_gray = imclose(gray, se_close);
    closed_red  = imclose(img(:, :, 1), se_close);

    % Weighted combination: Red channel carries strongest disc brightness,
    % grayscale balances saturation.
    disc_score = 0.65 * closed_red + 0.35 * closed_gray;
    disc_score(~fov_eroded) = 0;

    % --- Step 3: Candidate Search via Circular Hough Transform ---
    % Anatomical disc diameter is typically ~1.5mm to 1.8mm (~7% to 15% of
    % retinal field width), giving radius ~3.5% to 8.5% of min(h, w).
    r_min = max(6, round(min(h, w) * 0.035));
    r_max = max(r_min + 4, round(min(h, w) * 0.085));

    found_circle = false;
    try
        [centers, radii, metrics] = imfindcircles(disc_score, [r_min, r_max], ...
            'ObjectPolarity', 'bright', 'Sensitivity', 0.88, 'EdgeThreshold', 0.05);

        if ~isempty(centers)
            % Filter circles to those whose centers lie strictly within fov_eroded
            valid_idx = [];
            for i = 1:size(centers, 1)
                cx = round(centers(i, 1));
                cy = round(centers(i, 2));
                if cx >= 1 && cx <= w && cy >= 1 && cy <= h && fov_eroded(cy, cx)
                    valid_idx(end+1) = i; %#ok<AGROW>
                end
            end

            if ~isempty(valid_idx)
                % Score valid candidates by combining Hough metric and average brightness
                best_combined_score = -inf;
                best_i = valid_idx(1);

                for k = 1:length(valid_idx)
                    idx = valid_idx(k);
                    cx = round(centers(idx, 1));
                    cy = round(centers(idx, 2));
                    cr = round(radii(idx));

                    x_min = max(1, cx - cr); x_max = min(w, cx + cr);
                    y_min = max(1, cy - cr); y_max = min(h, cy + cr);

                    [Xg, Yg] = meshgrid(x_min:x_max, y_min:y_max);
                    circ_mask = ((Xg - cx).^2 + (Yg - cy).^2) <= cr^2;
                    patch = disc_score(y_min:y_max, x_min:x_max);

                    mean_brightness = mean(patch(circ_mask));
                    combined = mean_brightness * (1 + metrics(idx));

                    if combined > best_combined_score
                        best_combined_score = combined;
                        best_i = idx;
                    end
                end

                disc_center = [double(centers(best_i, 1)), double(centers(best_i, 2))];
                disc_radius = double(radii(best_i));
                found_circle = true;
            end
        end
    catch
        found_circle = false;
    end

    % --- Step 4: Fallback via Connected Component Analysis ---
    if ~found_circle
        % Top 2% brightest pixels inside eroded FOV
        active_vals = disc_score(fov_eroded);
        if isempty(active_vals) || all(active_vals == 0)
            thresh = 0.5;
        else
            thresh = prctile(active_vals, 98);
        end

        bright_mask = (disc_score >= thresh) & fov_eroded;
        se_clean = strel('disk', max(2, round(min(h, w) * 0.008)));
        bright_mask = imopen(bright_mask, se_clean);
        cc = bwconncomp(bright_mask);

        if cc.NumObjects > 0
            props = regionprops(cc, 'Area', 'Centroid', 'EquivDiameter');
            [~, max_idx] = max([props.Area]);
            disc_center = [double(props(max_idx).Centroid(1)), double(props(max_idx).Centroid(2))];
            est_r = props(max_idx).EquivDiameter / 2;
            disc_radius = double(max(r_min, min(r_max, est_r)));
        else
            % Default anatomical fallback (right-half / nasal position)
            disc_center = [double(round(w * 0.75)), double(round(h * 0.5))];
            disc_radius = double(round(min(h, w) * 0.06));
        end
    end

    % Ensure coordinates are within valid image bounds
    disc_center(1) = max(disc_radius, min(w - disc_radius, disc_center(1)));
    disc_center(2) = max(disc_radius, min(h - disc_radius, disc_center(2)));

    % --- Step 5: Anatomical Fovea Position Estimation ---
    % The fovea is located temporal to the optic disc by ~2.5 disc diameters
    % (~5.0 disc radii) and slightly inferior (~0.15 - 0.20 disc radii).
    % In fundus photography:
    % - If optic disc is in right half (nasal for right eye OD), fovea is to the LEFT.
    % - If optic disc is in left half (nasal for left eye OS), fovea is to the RIGHT.
    fovea_horizontal_distance = 2.5 * (2 * disc_radius); % 2.5 disc diameters
    fovea_vertical_offset     = 0.18 * disc_radius;       % slightly inferior

    if disc_center(1) >= (w / 2)
        % Right eye (OD): fovea is to the left (temporal)
        fovea_x = disc_center(1) - fovea_horizontal_distance;
    else
        % Left eye (OS): fovea is to the right (temporal)
        fovea_x = disc_center(1) + fovea_horizontal_distance;
    end
    fovea_y = disc_center(2) + fovea_vertical_offset;

    % Clamp fovea within image frame
    fovea_x = max(10, min(w - 10, round(fovea_x)));
    fovea_y = max(10, min(h - 10, round(fovea_y)));
    fovea_center = [double(fovea_x), double(fovea_y)];
end

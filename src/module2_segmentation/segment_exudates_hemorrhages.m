function [exudate_mask, hemorrhage_mask, lesion_counts] = segment_exudates_hemorrhages(img, disc_center, disc_radius)
% FUNCTION: segment_exudates_hemorrhages
% MODULE: 3 - Structure Segmentation
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Segments hard exudates (yellow-white lipid deposits with sharp borders),
%   soft exudates (cotton-wool spots with diffuse margins), and hemorrhages
%   (dot and blot blood extravasations) from a fundus image. Computes individual
%   lesion counts and total lesion burden area fraction to feed the clinical
%   rule-based grading path (Module 4, Path B).
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - enhanced fundus photograph
%   disc_center ([x, y] double) - optic disc center from locate_optic_disc.m
%   disc_radius (double) - optic disc radius from locate_optic_disc.m
%
% OUTPUTS:
%   exudate_mask (logical, HxW) - binary mask of all exudate pixels (hard + soft)
%   hemorrhage_mask (logical, HxW) - binary mask of hemorrhage pixels
%   lesion_counts (struct) - lesion quantification struct with fields:
%       - n_hard_exudates (int32): count of discrete hard exudates
%       - n_soft_exudates (int32): count of discrete soft exudates (cotton-wool)
%       - n_hemorrhages (int32): count of discrete blot/dot hemorrhages
%       - total_lesion_area_fraction (double): fraction of retinal FOV covered
%
% DEPENDS ON:
%   src/module2_segmentation/locate_optic_disc.m (for disc exclusion)
%   src/module2_segmentation/segment_vessels.m (for vessel exclusion)
%   Image Processing Toolbox (imgradient, imopen, strel, bwconncomp, regionprops)
%
% CALLED BY:
%   run_pipeline.m
%   src/module3_grading/grade_severity_rules.m
%   src/module4_explainability/gradcam_overlay.m
%
% KEY ASSUMPTIONS:
%   - Exudates: yellow-white, high luminance, high red and green values with
%     prominent local contrast against the reddish retinal background.
%     CRITICAL: Optic disc must be strictly masked out (1.35x disc radius)
%     to prevent false exudate detections on the disc's pale cup/rim.
%   - Hard vs. Soft Exudate discrimination:
%     Hard exudates exhibit sharp local boundary gradient (>= threshold).
%     Soft exudates (cotton wool) have diffuse edges with lower boundary gradient.
%   - Hemorrhages: dark red extravasations with strong green-channel absorption.
%     Vascular tree must be dilated and excluded to prevent vessels being counted
%     as hemorrhages.
%   - Deep learning hook: checks models/unet_lesions_idrid.mat; if absent,
%     executes the classical morphological-spectral pipeline.
%
% TODO:
%   1. Train multi-class U-Net or SegNet on IDRiD pixel-level lesion masks
%      (hard exudates, hemorrhages) and save to models/unet_lesions_idrid.mat.
%   2. Target: >0.65 IoU on IDRiD lesion test splits.

    % --- Input Validation & Normalization ---
    if ~isa(img, 'double')
        img = im2double(img);
    end
    [h, w, ~] = size(img);

    % Pre-allocate outputs
    exudate_mask = false(h, w);
    hemorrhage_mask = false(h, w);
    n_hard = int32(0);
    n_soft = int32(0);
    n_hem  = int32(0);

    % --- Step 1: Anatomical Exclusion Zones ---

    % 1a. Retinal FOV boundary
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
    total_fov_pixels = max(1, sum(fov_mask(:)));

    % 1b. Optic disc exclusion zone (mandatory for exudate detection)
    od_exclusion = false(h, w);
    if nargin >= 3 && ~isempty(disc_center) && ~isempty(disc_radius) && disc_radius > 0
        [Xg, Yg] = meshgrid(1:w, 1:h);
        od_dist = sqrt((Xg - disc_center(1)).^2 + (Yg - disc_center(2)).^2);
        od_exclusion = od_dist <= (1.35 * disc_radius);
    end

    % 1c. Retinal vessel exclusion zone (mandatory for hemorrhage detection)
    vessel_exclusion = false(h, w);
    try
        v_mask = segment_vessels(img);
        se_vdil = strel('disk', max(2, round(min(h, w) * 0.005)));
        vessel_exclusion = imdilate(v_mask, se_vdil);
    catch
        g_inv = 1.0 - img(:, :, 2);
        vessel_exclusion = g_inv > (mean(g_inv(:)) + 1.2 * std(g_inv(:)));
    end

    % --- Step 2: Optional Deep Learning Hook ---
    model_path = fullfile('models', 'unet_lesions_idrid.mat');
    if isfile(model_path)
        try
            loaded = load(model_path, 'net');
            if isfield(loaded, 'net')
                pred = semanticseg(img, loaded.net);
                exudate_mask = ((pred == 'hard_exudate') | (pred == 'soft_exudate')) & fov_eroded & (~od_exclusion);
                hemorrhage_mask = (pred == 'hemorrhage') & fov_eroded & (~od_exclusion) & (~vessel_exclusion);

                cc_h = bwconncomp(pred == 'hard_exudate');
                cc_s = bwconncomp(pred == 'soft_exudate');
                cc_hem = bwconncomp(hemorrhage_mask);

                n_hard = int32(cc_h.NumObjects);
                n_soft = int32(cc_s.NumObjects);
                n_hem  = int32(cc_hem.NumObjects);

                tot_lesion_px = sum(exudate_mask(:) | hemorrhage_mask(:));
                lesion_counts = struct( ...
                    'n_hard_exudates', n_hard, ...
                    'n_soft_exudates', n_soft, ...
                    'n_hemorrhages', n_hem, ...
                    'total_lesion_area_fraction', double(tot_lesion_px / total_fov_pixels));
                return;
            end
        catch
            % Fall through to classical pipeline
        end
    end

    % --- Step 3: Exudate Segmentation (Hard & Soft) ---
    % Search zone excludes optic disc and perimeter rim
    ex_search = fov_eroded & (~od_exclusion);

    % Feature map: combined red & green intensity with background suppression
    R_ch = img(:, :, 1);
    G_ch = img(:, :, 2);
    B_ch = img(:, :, 3);
    ex_intensity = 0.55 * R_ch + 0.45 * G_ch;

    se_bg = strel('disk', max(10, round(min(h, w) * 0.025)));
    ex_bg = imopen(ex_intensity, se_bg);
    ex_contrast = ex_intensity - ex_bg;
    ex_contrast(~ex_search) = 0;

    active_ex_vals = ex_contrast(ex_search);
    if ~isempty(active_ex_vals) && any(active_ex_vals > 0)
        ex_thresh = max(0.06, prctile(active_ex_vals, 99.0));
        % Color requirements: yellowish/white (both R and G elevated, R >= G)
        color_ok = (R_ch > 0.45) & (G_ch > 0.28) & (ex_contrast >= ex_thresh);
        cand_ex = color_ok & ex_search;

        min_ex_area = max(4, round(min(h, w) * 0.00002 * min(h, w)));
        cand_ex = bwareaopen(cand_ex, min_ex_area);
        cc_ex = bwconncomp(cand_ex);

        if cc_ex.NumObjects > 0
            % Classify Hard vs. Soft by edge gradient sharpness
            [Gmag, ~] = imgradient(gray);
            props_ex = regionprops(cc_ex, 'Area', 'PixelIdxList');

            for i = 1:length(props_ex)
                pix = props_ex(i).PixelIdxList;
                mean_grad = mean(Gmag(pix));
                area = props_ex(i).Area;

                % Hard exudates: high gradient (sharp boundary) or compact
                % Soft exudates (cotton wool): diffuse, lower gradient, larger
                if mean_grad >= 0.035 || area < 40
                    n_hard = n_hard + 1;
                else
                    n_soft = n_soft + 1;
                end
                exudate_mask(pix) = true;
            end
        end
    end

    % --- Step 4: Hemorrhage Segmentation (Blot & Dot) ---
    % Search zone excludes optic disc, vessels, and perimeter rim
    hem_search = fov_eroded & (~od_exclusion) & (~vessel_exclusion);

    % Hemorrhages absorb green light intensely, appearing darker than local retina
    se_close_bg = strel('disk', max(12, round(min(h, w) * 0.030)));
    g_bg = imclose(G_ch, se_close_bg);
    g_depression = max(0, g_bg - G_ch);

    % Color contrast: red component dominates green and blue
    red_chroma = max(0, R_ch - G_ch);
    hem_score = g_depression .* (0.5 + 2.0 * red_chroma);
    hem_score(~hem_search) = 0;

    active_hem_vals = hem_score(hem_search);
    if ~isempty(active_hem_vals) && any(active_hem_vals > 0)
        hem_thresh = max(0.035, prctile(active_hem_vals, 99.1));
        cand_hem = (hem_score >= hem_thresh) & (R_ch > G_ch) & hem_search;

        min_hem_area = max(5, round(min(h, w) * 0.00003 * min(h, w)));
        cand_hem = bwareaopen(cand_hem, min_hem_area);
        cc_hem = bwconncomp(cand_hem);

        if cc_hem.NumObjects > 0
            props_hem = regionprops(cc_hem, 'PixelIdxList');
            for k = 1:length(props_hem)
                hemorrhage_mask(props_hem(k).PixelIdxList) = true;
            end
            n_hem = int32(cc_hem.NumObjects);
        end
    end

    % --- Step 5: Assemble Quantified Lesion Counts Struct ---
    total_lesion_px = sum(exudate_mask(:) | hemorrhage_mask(:));
    total_area_frac = double(total_lesion_px) / double(total_fov_pixels);

    lesion_counts = struct( ...
        'n_hard_exudates', n_hard, ...
        'n_soft_exudates', n_soft, ...
        'n_hemorrhages', n_hem, ...
        'total_lesion_area_fraction', total_area_frac);
end

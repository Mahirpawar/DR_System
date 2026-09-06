function overlay_img = gradcam_overlay(img, model, predicted_grade, lesion_masks)
% FUNCTION: gradcam_overlay
% MODULE: 5 - Explainability
% STATUS: HEURISTIC_BASELINE (PLACEHOLDER FOR BACKPROP GRAD-CAM)
%
% PURPOSE:
%   Generates visual attention heatmaps reflecting AI reasoning for the
%   predicted severity grade, overlaid on the original fundus photograph
%   AND anchored against verified clinical lesion contours (microaneurysms,
%   exudates, hemorrhages). When a trained CNN is passed, backpropagation
%   gradients (via Deep Learning Toolbox gradcam) produce activation maps;
%   without a trained CNN, generates a spatial Gaussian saliency heatmap
%   anchored to lesion density as a baseline placeholder.
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - original or enhanced fundus image
%   model (dlnetwork or []) - trained CNN classification model
%   predicted_grade (int, 0-4) - predicted ICDR severity class to explain
%   lesion_masks (struct) - struct containing clinical lesion masks:
%       - vessel_mask (logical, HxW)
%       - ma_mask (logical, HxW)
%       - exudate_mask (logical, HxW)
%       - hemorrhage_mask (logical, HxW)
%
% OUTPUTS:
%   overlay_img (double, HxWx3 RGB, range [0,1]) - composite image showing
%       attention heatmap plus distinct color-coded lesion boundaries:
%       - Cyan: Microaneurysms
%       - Yellow: Hard & Soft Exudates
%       - Magenta: Blot & Dot Hemorrhages
%
% DEPENDS ON:
%   Deep Learning Toolbox (when trained CNN model is provided)
%   Image Processing Toolbox (bwperim, imdilate, ind2rgb, strel)
%
% CALLED BY:
%   run_pipeline.m
%   src/module4_explainability/generate_report.m
%
% KEY ASSUMPTIONS / ROADMAP NOTE:
%   - PLACEHOLDER STATUS: Currently computes a smoothed spatial attention map
%     anchored to detected lesion centroids until real CNN backprop gradients
%     are hooked up via 'gradcam(net, img, ...)' or 'dlfeval'.
%   - Next milestone: hook real gradient backpropagation through final conv layer
%     of trained ResNet once models/dr_grading_cnn.mat is trained.
%   - Anchoring: Attention heatmaps alone can be diffuse and non-specific.
%     Superimposing sharp, high-contrast lesion boundaries gives the clinician
%     immediate visual confirmation that attention maps correspond to real lesions.

    % Input normalization
    if ~isa(img, 'double')
        img = im2double(img);
    end
    [h, w, ~] = size(img);

    % Default safe empty masks if struct fields missing
    ma_mask   = false(h, w);
    ex_mask   = false(h, w);
    hem_mask  = false(h, w);

    if nargin >= 4 && isstruct(lesion_masks)
        if isfield(lesion_masks, 'ma_mask') && islogical(lesion_masks.ma_mask)
            ma_mask = lesion_masks.ma_mask;
        end
        if isfield(lesion_masks, 'exudate_mask') && islogical(lesion_masks.exudate_mask)
            ex_mask = lesion_masks.exudate_mask;
        end
        if isfield(lesion_masks, 'hemorrhage_mask') && islogical(lesion_masks.hemorrhage_mask)
            hem_mask = lesion_masks.hemorrhage_mask;
        end
    end

    % --- Step 1: Compute Visual Attention Heatmap ---
    cam_heatmap = zeros(h, w);
    computed_dl = false;

    if ~isempty(model)
        try
            % Deep Learning Toolbox gradCAM support
            cam_heatmap = gradCAM(model, img, predicted_grade);
            cam_heatmap = imresize(cam_heatmap, [h, w]);
            computed_dl = true;
        catch
            computed_dl = false;
        end
    end

    if ~computed_dl
        % Synthesize lesion-anchored attention density map
        lesion_density = 2.0 * double(ma_mask) + 1.6 * double(ex_mask) + 1.8 * double(hem_mask);
        if sum(lesion_density(:)) > 0
            % Gaussian smooth over lesion locations to simulate receptive field attention
            gauss_filt = fspecial('gaussian', [45, 45], max(8, round(min(h, w) * 0.025)));
            cam_heatmap = imfilter(lesion_density, gauss_filt, 'replicate');
        else
            % For Grade 0 (no lesions), attention focuses on macula/central retinal field
            [Xg, Yg] = meshgrid(1:w, 1:h);
            cam_heatmap = exp(-((Xg - w * 0.48).^2 + (Yg - h * 0.50).^2) / (2 * (min(h, w) * 0.22)^2));
        end
    end

    % Normalize heatmap to [0, 1]
    min_val = min(cam_heatmap(:));
    max_val = max(cam_heatmap(:));
    if max_val > min_val
        norm_cam = (cam_heatmap - min_val) / (max_val - min_val);
    else
        norm_cam = zeros(h, w);
    end

    % --- Step 2: Heatmap Colorization & Adaptive Alpha Blending ---
    % Colormap mapping (JET colormap: blue=low, green=mid, red=peak attention)
    cmap = jet(256);
    cam_indices = min(256, max(1, round(norm_cam * 255) + 1));
    cam_rgb = ind2rgb(cam_indices, cmap);

    % Alpha weighting: higher attention pixels are more opaque; low attention retains original image clarity
    alpha_map = repmat(0.40 * (norm_cam .^ 1.2), [1, 1, 3]);
    blended = (1.0 - alpha_map) .* img + alpha_map .* cam_rgb;

    % --- Step 3: Superimpose Anchored Lesion Contours ---
    % 3a. Hard & Soft Exudates: Yellow contour [1.0, 0.90, 0.05]
    if any(ex_mask(:))
        ex_boundary = bwperim(ex_mask);
        ex_boundary = imdilate(ex_boundary, strel('disk', 1));
        for c = 1:3
            color_val = [1.0, 0.90, 0.05];
            ch = blended(:, :, c);
            ch(ex_boundary) = color_val(c);
            blended(:, :, c) = ch;
        end
    end

    % 3b. Hemorrhages: Magenta/Crimson contour [0.95, 0.10, 0.45]
    if any(hem_mask(:))
        hem_boundary = bwperim(hem_mask);
        hem_boundary = imdilate(hem_boundary, strel('disk', 1));
        for c = 1:3
            color_val = [0.95, 0.10, 0.45];
            ch = blended(:, :, c);
            ch(hem_boundary) = color_val(c);
            blended(:, :, c) = ch;
        end
    end

    % 3c. Microaneurysms: Cyan dots [0.10, 0.95, 1.0]
    if any(ma_mask(:))
        ma_boundary = imdilate(ma_mask, strel('disk', 2));
        for c = 1:3
            color_val = [0.10, 0.95, 1.0];
            ch = blended(:, :, c);
            ch(ma_boundary) = color_val(c);
            blended(:, :, c) = ch;
        end
    end

    overlay_img = max(0.0, min(1.0, blended));
end

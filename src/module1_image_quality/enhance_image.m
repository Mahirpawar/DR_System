function enhanced_img = enhance_image(img)
% FUNCTION: enhance_image
% MODULE: 2 - Preprocessing & Enhancement
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Applies adaptive enhancement to fundus images flagged as 'borderline'
%   by assess_image_quality.m. Improves contrast, corrects illumination,
%   and denoises, without altering images already flagged 'good' (those
%   should bypass this function entirely — caller's responsibility).
%
% INPUTS:
%   img (uint8 or double, HxWx3 RGB image) - borderline-quality fundus image
%
% OUTPUTS:
%   enhanced_img (double, HxWx3 RGB, range [0,1]) - enhanced image, ready
%       for segmentation modules
%
% DEPENDS ON:
%   none (uses only base Image Processing Toolbox functions)
%
% CALLED BY:
%   not yet wired in — intended to be called only when
%   assess_image_quality.m returns quality_label == 'borderline'
%
% KEY ASSUMPTIONS:
%   - Input is a color fundus image (not grayscale). CLAHE is applied on
%     the L channel of Lab color space specifically to avoid distorting
%     color-dependent lesion appearance (e.g., exudates' yellow-white
%     color, hemorrhages' red color) — applying CLAHE per-RGB-channel
%     would shift color balance and could confuse downstream lesion
%     classifiers that use color features.
%   - Denoising uses a mild non-local-means filter; parameters chosen to
%     preserve small structures like microaneurysms rather than smooth
%     them away. If MA detection (Module 3) shows sensitivity loss on
%     enhanced images vs. originals, reduce denoising strength here first.
%
% TODO:
%   none for MVP. Future: make denoising strength adaptive to the
%   noise_score rather than fixed, once a noise metric is added to
%   assess_image_quality.m's metrics struct.

    if ~isa(img, 'double')
        img = im2double(img);
    end

    % --- Step 1: Illumination normalization + contrast via CLAHE on L channel ---
    lab = rgb2lab(img);
    L = lab(:,:,1) / 100;  % normalize L to [0,1] for adapthisteq
    % Use uniform distribution to enhance contrast smoothly without introducing speckled noise
    L_eq = adapthisteq(L, 'ClipLimit', 0.008, 'Distribution', 'uniform');
    lab(:,:,1) = L_eq * 100;
    img_clahe = lab2rgb(lab);
    img_clahe = max(0, min(1, img_clahe)); % clamp numerical overshoot

    % --- Step 2: Mild gamma correction to recover midtone detail ---
    % Gamma < 1 brightens midtones; chosen conservatively (0.9) since
    % CLAHE already did most of the contrast work — aggressive gamma here
    % would risk blowing out already-corrected regions.
    img_gamma = img_clahe .^ 0.9;

    % --- Step 3: Denoising (non-local means, mild strength) ---
    % Applied last, after contrast enhancement, since CLAHE can amplify
    % sensor noise that was previously below the visibility threshold.
    enhanced_img = zeros(size(img_gamma));
    for c = 1:3
        enhanced_img(:,:,c) = imnlmfilt(img_gamma(:,:,c), ...
            'DegreeOfSmoothing', 0.02);
    end

    enhanced_img = max(0, min(1, enhanced_img)); % final clamp
end

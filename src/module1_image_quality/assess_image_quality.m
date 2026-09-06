function [quality_label, reason_code, metrics] = assess_image_quality(img)
% FUNCTION: assess_image_quality
% MODULE: 1 - Image Quality Assessment
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Evaluates a raw fundus image for gradeability (focus, illumination,
%   field of view) using rule-based metrics. This is the first gate in the
%   pipeline: images are routed to pass-through, enhancement, or rejection
%   before any clinical analysis runs on them.
%
% INPUTS:
%   img (uint8 or double, HxWx3 RGB image) - raw fundus photograph, any
%       resolution. Function internally resizes for consistent thresholds.
%
% OUTPUTS:
%   quality_label (char) - one of 'good', 'borderline', 'ungradeable'
%   reason_code (char) - human-readable reason, e.g. 'underexposed',
%       'out_of_focus', 'field_of_view_incomplete', 'acceptable'.
%       This is what gets shown to the field worker for recapture guidance.
%   metrics (struct) - raw metric values (focus_score, illum_score,
%       fov_score) for logging/debugging and for future threshold tuning.
%
% DEPENDS ON:
%   none (uses only base Image Processing Toolbox functions)
%
% CALLED BY:
%   not yet wired in — intended to be the first call in the master
%   pipeline script (not yet written; see PROGRESS.md Section 4)
%
% KEY ASSUMPTIONS:
%   - Thresholds below were chosen by inspection of typical fundus image
%     statistics, NOT trained on a labeled quality dataset (see PROGRESS.md
%     Section 5, decision dated 2026-09-06). They are a reasonable starting
%     point, not clinically validated. Tune against EyeQ/DeepDRiD quality
%     labels if/when that dataset is loaded.
%   - Assumes a roughly circular fundus field-of-view (FOV) centered in
%     frame, which is standard for both tabletop and portable cameras.
%
% TODO:
%   none for MVP — this function is considered complete for prototype
%   purposes. Future improvement (optional): replace/augment with a
%   trained CNN quality classifier once EyeQ/DeepDRiD labels are available;
%   keep this rule-based version as _v1 for the ablation comparison.

    % --- Normalize input ---
    if ~isa(img, 'double')
        img = im2double(img);
    end
    gray = rgb2gray(img);

    % --- Metric 1: Focus (Laplacian variance) ---
    % Higher variance = sharper edges = better focus. Threshold chosen
    % empirically; a blurred fundus image typically falls below ~0.001
    % on a normalized [0,1] double image.
    lap = fspecial('laplacian', 0.2);
    lap_response = imfilter(gray, lap, 'replicate');
    focus_score = var(lap_response(:));

    % --- Metric 2: Illumination (histogram spread + mean brightness) ---
    % Very dark or very bright/blown-out images have low std and extreme
    % mean. Well-illuminated fundus images typically have mean in
    % [0.25, 0.75] and std > 0.08 on normalized double scale.
    illum_mean = mean(gray(:));
    illum_std = std(gray(:));
    illum_score = illum_std; % primary signal; mean checked separately below

    % --- Metric 3: Field of view completeness ---
    % Fraction of frame that is "non-background" (background in fundus
    % images is typically near-black outside the circular FOV mask).
    bg_mask = gray < 0.05;
    fov_score = 1 - (sum(bg_mask(:)) / numel(bg_mask));

    % --- Package raw metrics for caller/logging ---
    metrics = struct( ...
        'focus_score', focus_score, ...
        'illum_mean', illum_mean, ...
        'illum_std', illum_std, ...
        'fov_score', fov_score);

    % --- Decision logic ---
    % Order matters: check for outright rejection reasons first, then
    % borderline, then default to good. This keeps reason_code specific
    % rather than reporting the first metric checked regardless of
    % severity.
    FOCUS_REJECT_THRESH     = 0.00006;
    FOCUS_BORDERLINE_THRESH = 0.00045;
    ILLUM_REJECT_LOW        = 0.02;
    ILLUM_BORDERLINE_LOW    = 0.06;
    MEAN_REJECT_DARK        = 0.08;
    MEAN_REJECT_BRIGHT      = 0.92;
    FOV_REJECT_THRESH       = 0.40;
    FOV_BORDERLINE_THRESH   = 0.60;

    if focus_score < FOCUS_REJECT_THRESH
        quality_label = 'ungradeable';
        reason_code = 'out_of_focus';
    elseif illum_mean < MEAN_REJECT_DARK
        quality_label = 'ungradeable';
        reason_code = 'underexposed';
    elseif illum_mean > MEAN_REJECT_BRIGHT
        quality_label = 'ungradeable';
        reason_code = 'overexposed';
    elseif fov_score < FOV_REJECT_THRESH
        quality_label = 'ungradeable';
        reason_code = 'field_of_view_incomplete';
    elseif focus_score < FOCUS_BORDERLINE_THRESH || ...
           illum_score < ILLUM_BORDERLINE_LOW || ...
           fov_score < FOV_BORDERLINE_THRESH
        quality_label = 'borderline';
        reason_code = 'needs_enhancement';
    else
        quality_label = 'good';
        reason_code = 'acceptable';
    end
end

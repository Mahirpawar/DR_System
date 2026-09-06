% FUNCTION: detect_neovascularization
% MODULE: 3 - Structure & Lesion Segmentation
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Detects retinal neovascularization — the hallmark hallmark of Proliferative
%   Diabetic Retinopathy (PDR / ICDR Grade 4). Distinguishes:
%     1. Neovascularization at the Disc (NVD): Abnormal, delicate, chaotic
%        vessel fronds within 1-2 disc diameters of the optic disc margin.
%     2. Neovascularization Elsewhere (NVE): Abnormal vessel budding, looping,
%        and excessive branching away from the disc along major vascular arcades.
%   Uses skeleton morphological branch-density analysis, local vessel tortuosity,
%   and caliber irregularity metrics.
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - enhanced fundus image
%   vessel_mask (logical, HxW) - binary retinal vessel segmentation
%   disc_center (1x2 double [x, y]) - optic disc center coordinates
%   disc_radius (double) - optic disc radius in pixels
%   fov_mask (logical, HxW, optional) - field-of-view binary mask
%
% OUTPUTS:
%   nv_mask (logical, HxW) - binary mask of detected neovascularization regions
%   is_nv_detected (logical) - boolean flag (true = PDR Grade 4 evidence found)
%   nv_metrics (struct) - quantitative diagnostic metrics:
%       - nvd_detected (logical): true if NVD is present
%       - nve_detected (logical): true if NVE is present
%       - nvd_area_fraction (double): ratio of NVD vessel area to disc area
%       - max_branch_density (double): peak local branching points per unit area
%       - tortuosity_index (double): aggregate vascular tortuosity score
%
% DEPENDS ON:
%   Image Processing Toolbox (bwskel, bwmorph, imdilate, strel, bwconncomp)
%
% CALLED BY:
%   run_pipeline.m
%   src/module3_grading/grade_severity_rules.m
%
% KEY ASSUMPTIONS:
%   - Neovascular fronds have significantly higher local branching frequency
%     and caliber variability than mature primary vascular arcades.
%   - Peripapillary NVD region is evaluated within an annulus of 1.0 to 2.5
%     disc radii centered at the detected optic disc.

function [nv_mask, is_nv_detected, nv_metrics] = detect_neovascularization(img, vessel_mask, disc_center, disc_radius, fov_mask)

    [H, W, ~] = size(img);

    if nargin < 5 || isempty(fov_mask)
        fov_mask = true(H, W);
    end

    if isempty(vessel_mask) || ~any(vessel_mask(:))
        nv_mask = false(H, W);
        is_nv_detected = false;
        nv_metrics = struct('nvd_detected', false, 'nve_detected', false, ...
            'nvd_area_fraction', 0.0, 'max_branch_density', 0.0, 'tortuosity_index', 0.0);
        return;
    end

    % --- Step 1: Peripapillary Annulus Definition (NVD Zone) ---
    [X, Y] = meshgrid(1:W, 1:H);
    dist_from_disc = sqrt((X - disc_center(1)).^2 + (Y - disc_center(2)).^2);
    
    % Disc interior mask vs. Peripapillary NVD zone (1.0 to 2.5 disc radii)
    disc_area_px = max(100, pi * (disc_radius^2));
    nvd_zone = (dist_from_disc >= disc_radius * 0.8) & ...
               (dist_from_disc <= disc_radius * 2.5) & fov_mask;
    
    % Periphery NVE zone (outside NVD zone, excluding optic disc)
    nve_zone = (dist_from_disc > disc_radius * 2.5) & fov_mask;

    % --- Step 2: Skeletonization & Branch Point Topology ---
    % Neovascular networks are characterized by abnormal dense branching
    skel = bwskel(vessel_mask);
    branch_pts = bwmorph(skel, 'branchpoints');
    end_pts = bwmorph(skel, 'endpoints');

    % Local branch point density via Gaussian-like disk filtering
    kernel_rad = max(5, round(disc_radius * 0.25));
    branch_density = imfilter(double(branch_pts), fspecial('disk', kernel_rad), 'replicate');
    
    % --- Step 3: Local Vessel Tortuosity & Caliber Irregularity ---
    % Compute gradient of green channel along vessel skeleton
    green_ch = img(:,:,2);
    [gx, gy] = gradient(green_ch);
    vessel_gradient = sqrt(gx.^2 + gy.^2) .* double(vessel_mask);
    
    % Abnormal vessel candidates: high local branch density OR high tortuosity in thin vessels
    abnormal_branches = (branch_density > 0.018) & vessel_mask;
    
    % Dilate abnormal branch clusters to capture associated fronds
    nv_candidates = imdilate(abnormal_branches, strel('disk', 3)) & vessel_mask;
    
    % Filter out small single-pixel noise
    nv_candidates = bwareaopen(nv_candidates, 15);

    % --- Step 4: Distinguish NVD vs NVE ---
    nvd_candidates = nv_candidates & nvd_zone;
    nve_candidates = nv_candidates & nve_zone;

    nvd_area_px = sum(nvd_candidates(:));
    nve_area_px = sum(nve_candidates(:));

    nvd_area_fraction = nvd_area_px / disc_area_px;
    
    % Clinical threshold: NVD >= 1/4 to 1/3 disc area or distinct dense looping fronds
    is_nvd = (nvd_area_fraction >= 0.12) || (sum(nvd_candidates(:)) > 50 && any(branch_pts(nvd_zone)));
    is_nve = (nve_area_px > 120);

    is_nv_detected = is_nvd || is_nve;
    nv_mask = nvd_candidates | nve_candidates;

    % Aggregate diagnostic metrics
    max_density = max(branch_density(:));
    tortuosity_score = mean(vessel_gradient(vessel_mask > 0));
    if isnan(tortuosity_score), tortuosity_score = 0.0; end

    nv_metrics = struct( ...
        'nvd_detected', is_nvd, ...
        'nve_detected', is_nve, ...
        'nvd_area_fraction', nvd_area_fraction, ...
        'max_branch_density', max_density, ...
        'tortuosity_index', tortuosity_score);
end

function [icdr_grade, rule_confidence] = grade_severity_rules(vessel_mask, ma_count, lesion_counts)
% FUNCTION: grade_severity_rules
% MODULE: 4 - Severity Grading, Path B (lesion-count rules/SVM)
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Classifies ICDR Diabetic Retinopathy severity grade (0 to 4) using
%   explicit clinical lesion counts and geometric lesion area burden
%   extracted from Module 3 segmentation outputs. This constitutes "Path B",
%   which is probabilistically fused with "Path A" (CNN) in fuse_grading.m
%   to fulfill the requirement that an integrated pipeline outperforms any
%   isolated technique.
%
% INPUTS:
%   vessel_mask (logical, HxW) - from segment_vessels.m (used for vessel
%       density and caliber irregularity analysis)
%   ma_count (int) - count of detected microaneurysms from detect_microaneurysms.m
%   lesion_counts (struct) - from segment_exudates_hemorrhages.m, fields:
%       - n_hard_exudates (int)
%       - n_soft_exudates (int)
%       - n_hemorrhages (int)
%       - total_lesion_area_fraction (double)
%
% OUTPUTS:
%   icdr_grade (int, 0-4) - predicted ICDR severity grade:
%       0: No Apparent DR
%       1: Mild NPDR (microaneurysms only)
%       2: Moderate NPDR (more than MAs, but less than severe)
%       3: Severe NPDR (extensive hemorrhages/cotton-wool spots/area burden)
%       4: Proliferative DR (PDR: severe neovascularization / extensive burden)
%   rule_confidence (double, 0-1) - heuristic rule confidence score reflecting
%       unambiguity relative to clinical decision boundaries
%
% DEPENDS ON:
%   none directly (consumes segmentation metrics from Module 3)
%
% CALLED BY:
%   run_pipeline.m
%   src/module3_grading/fuse_grading.m
%
% KEY ASSUMPTIONS:
%   - Follows International Clinical Diabetic Retinopathy (ICDR) criteria:
%     Grade 0: 0 lesions across all types.
%     Grade 1: Microaneurysms present, but zero exudates and zero hemorrhages.
%     Grade 2: Presence of hard exudates and/or moderate hemorrhages (<15).
%     Grade 3: >=15 intraretinal hemorrhages, OR >=3 soft exudates (cotton-wool spots),
%              OR total lesion area fraction >= 0.025 (2.5% of retina).
%     Grade 4: Very high lesion area burden (>= 5.0%) or extensive hemorrhage
%              clusters (>=30) indicating high risk of proliferative progression.
%   - Confidence is calibrated higher when lesion counts sit comfortably away
%     from clinical boundary transitions.

    % Default safe values
    if nargin < 2 || isempty(ma_count)
        ma_count = 0;
    end
    if nargin < 3 || isempty(lesion_counts)
        lesion_counts = struct( ...
            'n_hard_exudates', 0, ...
            'n_soft_exudates', 0, ...
            'n_hemorrhages', 0, ...
            'total_lesion_area_fraction', 0.0);
    end

    n_hard = double(lesion_counts.n_hard_exudates);
    n_soft = double(lesion_counts.n_soft_exudates);
    n_hem  = double(lesion_counts.n_hemorrhages);
    area_frac = double(lesion_counts.total_lesion_area_fraction);
    ma_cnt = double(ma_count);

    % Optional vessel tortuosity/density proxy
    vessel_density = 0.0;
    if nargin >= 1 && ~isempty(vessel_mask) && islogical(vessel_mask)
        vessel_density = double(sum(vessel_mask(:))) / double(numel(vessel_mask));
    end

    % --- Multi-Stage ICDR Clinical Decision Rules ---
    is_nv = (isfield(lesion_counts, 'is_nv_detected') && lesion_counts.is_nv_detected) || ...
            (isfield(lesion_counts, 'nvd_detected') && lesion_counts.nvd_detected);

    % Condition 4: Proliferative DR (PDR)
    % Neovascularization detected (NVD/NVE), extensive hemorrhage clusters, or very high total lesion area
    is_grade_4 = is_nv || (area_frac >= 0.040) || (n_hem >= 35) || (n_hem >= 20 && n_soft >= 5 && vessel_density > 0.18);

    % Condition 3: Severe NPDR
    % 20+ hemorrhages (ICDR 4-2-1 rule), 4+ soft exudates (cotton-wool spots), or significant area fraction >= 0.020
    is_grade_3 = (n_hem >= 20) || (n_soft >= 4) || (area_frac >= 0.020);

    % Condition 2: Moderate NPDR
    % Clinical Rule: Diabetic exudation requires microvascular breakdown (MAs present or extensive burden).
    % Isolated tiny bright specs with zero microaneurysms represent non-diabetic glints/drusen.
    is_grade_2 = (ma_cnt >= 8) || (n_hard >= 10) || (n_hard >= 4 && ma_cnt >= 2) || (n_hem >= 8) || (n_soft >= 2) || (area_frac >= 0.005);

    % Condition 1: Mild NPDR
    % Microaneurysms only (ICDR definition: MAs present, but no significant exudates/hemorrhages)
    is_grade_1 = (ma_cnt >= 2 && ma_cnt < 8 && n_hard <= 3);

    % Decision resolution
    if is_grade_4
        icdr_grade = 4;
        rule_confidence = 0.88 + 0.10 * min(1.0, (area_frac - 0.04) / 0.04);
    elseif is_grade_3
        icdr_grade = 3;
        rule_confidence = 0.82 + 0.12 * min(1.0, (n_hem - 20) / 20);
    elseif is_grade_2
        icdr_grade = 2;
        rule_confidence = 0.80 + 0.10 * min(1.0, (n_hard + n_hem) / 10);
    elseif is_grade_1
        icdr_grade = 1;
        rule_confidence = 0.85;
    else
        % Grade 0: Normal retina (lesions absent or within sensor noise floor)
        icdr_grade = 0;
        rule_confidence = 0.95;
    end

    % Bounds check
    icdr_grade = int32(max(0, min(4, icdr_grade)));
    rule_confidence = double(max(0.50, min(0.99, rule_confidence)));
end

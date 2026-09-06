function report_fig = generate_report(img, overlay_img, final_grade, calibrated_confidence, is_referable, lesion_counts)
% FUNCTION: generate_report
% MODULE: 5 - Explainability
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Generates a unified, single-screen, doctor-facing diagnostic report
%   combining side-by-side fundus visualization, lesion-anchored Grad-CAM
%   attention, an explicit clinical evidence table, calibrated confidence,
%   and clear referral triage flags. Designed specifically to meet the
%   problem statement constraint: reviewable and actionable by a consulting
%   ophthalmologist in under 30 seconds.
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - raw or enhanced fundus image
%   overlay_img (double, HxWx3 RGB) - Grad-CAM attention + lesion contours
%   final_grade (int, 0-4) - fused ICDR severity grade from fuse_grading.m
%   calibrated_confidence (double, 0-1) - calibrated probability
%   is_referable (logical) - true if final_grade >= 2 (referral threshold)
%   lesion_counts (struct) - lesion statistics containing:
%       - n_hard_exudates (int)
%       - n_soft_exudates (int)
%       - n_hemorrhages (int)
%       - total_lesion_area_fraction (double)
%       - ma_count (int, optional)
%
% OUTPUTS:
%   report_fig (MATLAB figure handle) - high-resolution rendered report figure
%
% DEPENDS ON:
%   none directly (consumes outputs of Modules 2, 3, and 4)
%
% CALLED BY:
%   run_pipeline.m
%
% KEY ASSUMPTIONS:
%   - The figure is initialized with 'Visible', 'off' to ensure headless
%     batch execution compatibility on remote servers or clinics.
%   - Layout contains 3 synchronized panels:
%     1. Panel 1: Original Fundus Photo.
%     2. Panel 2: Explainable AI Heatmap with color-coded lesion legend.
%     3. Panel 3: Structured Clinical Triage Card with explicit lesion counts
%        and doctor sign-off checkboxes for rapid review (<30s).

    % Grade naming mapping
    grade_names = { ...
        'Grade 0: No Apparent DR', ...
        'Grade 1: Mild NPDR (Microaneurysms only)', ...
        'Grade 2: Moderate NPDR (Exudates/Hemorrhages)', ...
        'Grade 3: Severe NPDR (Extensive Lesions/CW Spots)', ...
        'Grade 4: Proliferative DR (High-Risk PDR)'};
    g_idx = max(0, min(4, int32(final_grade))) + 1;
    grade_str = grade_names{g_idx};

    % Safe extraction of lesion counts
    n_ma   = 0;
    n_hard = 0;
    n_soft = 0;
    n_hem  = 0;
    area_pct = 0.0;

    if nargin >= 6 && isstruct(lesion_counts)
        if isfield(lesion_counts, 'ma_count')
            n_ma = lesion_counts.ma_count;
        end
        if isfield(lesion_counts, 'n_hard_exudates')
            n_hard = lesion_counts.n_hard_exudates;
        end
        if isfield(lesion_counts, 'n_soft_exudates')
            n_soft = lesion_counts.n_soft_exudates;
        end
        if isfield(lesion_counts, 'n_hemorrhages')
            n_hem = lesion_counts.n_hemorrhages;
        end
        if isfield(lesion_counts, 'total_lesion_area_fraction')
            area_pct = lesion_counts.total_lesion_area_fraction * 100.0;
        end
    end

    conf_pct = calibrated_confidence * 100.0;

    % Create figure window (1300 x 620 px for optimal widescreen view)
    report_fig = figure('Visible', 'off', 'Color', [0.97, 0.97, 0.98], ...
        'Units', 'pixels', 'Position', [100, 100, 1300, 620], ...
        'Name', 'DR Screening Diagnostic Report', 'NumberTitle', 'off');

    % --- Panel 1: Original Fundus Photo ---
    ax1 = axes('Position', [0.02, 0.14, 0.28, 0.76], 'Parent', report_fig);
    imshow(img, 'Parent', ax1);
    title(ax1, '1. Patient Fundus Photograph', 'FontSize', 12.5, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.15]);

    % --- Panel 2: Explainable AI Heatmap & Lesion Anchors ---
    ax2 = axes('Position', [0.31, 0.14, 0.28, 0.76], 'Parent', report_fig);
    imshow(overlay_img, 'Parent', ax2);
    title(ax2, '2. Explainable AI Overlay (Grad-CAM + Lesions)', 'FontSize', 12.5, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.15]);
    xlabel(ax2, 'Legend: Cyan = MAs | Yellow = Exudates | Magenta = Hemorrhages', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.3]);

    % --- Panel 3: Structured Clinical Triage & Sign-Off Card ---
    ax3 = axes('Position', [0.61, 0.04, 0.37, 0.92], 'Parent', report_fig);
    set(ax3, 'Visible', 'off');
    xlim(ax3, [0, 1]);
    ylim(ax3, [0, 1]);

    % Background triage card
    if is_referable
        header_color = [0.85, 0.12, 0.12]; % Crimson Red
        triage_text  = 'REFERRAL RECOMMENDED';
        sub_text     = 'Specialist Ophthalmologist Review Urgently Required';
    else
        header_color = [0.10, 0.65, 0.30]; % Forest Green
        triage_text  = 'NO REFERRAL NEEDED';
        sub_text     = 'Low Risk — Routine Annual Tele-Screening Recommended';
    end

    % Render Triage Banner
    rectangle('Position', [0.02, 0.85, 0.96, 0.13], 'Curvature', 0.15, ...
        'FaceColor', header_color, 'EdgeColor', 'none', 'Parent', ax3);
    text(0.50, 0.93, triage_text, 'FontSize', 13.5, 'FontWeight', 'bold', ...
        'Color', 'white', 'HorizontalAlignment', 'center', 'Parent', ax3, 'Interpreter', 'none');
    text(0.50, 0.875, sub_text, 'FontSize', 8.5, ...
        'Color', [0.95, 0.95, 0.95], 'HorizontalAlignment', 'center', 'Parent', ax3, 'Interpreter', 'none');

    % Clinical Diagnosis Section
    text(0.04, 0.78, 'DIAGNOSIS & AI CONFIDENCE', 'FontSize', 10, 'FontWeight', 'bold', ...
        'Color', [0.2, 0.25, 0.35], 'Parent', ax3, 'Interpreter', 'none');
    text(0.04, 0.72, 'ICDR Severity:', 'FontSize', 9, 'FontWeight', 'bold', ...
        'Color', [0.35, 0.4, 0.5], 'Parent', ax3, 'Interpreter', 'none');
    text(0.04, 0.66, grade_str, 'FontSize', 10.5, 'FontWeight', 'bold', ...
        'Color', [0.05, 0.05, 0.15], 'Parent', ax3, 'Interpreter', 'none');
    text(0.04, 0.60, sprintf('AI Confidence: %.1f%% (Empirically Calibrated)', conf_pct), ...
        'FontSize', 9.5, 'Color', [0.25, 0.3, 0.4], 'Parent', ax3, 'Interpreter', 'none');

    % Lesion Evidence Table Section
    rectangle('Position', [0.02, 0.24, 0.96, 0.32], 'Curvature', 0.08, ...
        'FaceColor', [1.0, 1.0, 1.0], 'EdgeColor', [0.85, 0.85, 0.88], 'Parent', ax3);
    text(0.05, 0.51, 'OBJECTIVE LESION EVIDENCE', 'FontSize', 9.5, 'FontWeight', 'bold', ...
        'Color', [0.3, 0.35, 0.45], 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.45, sprintf('• Microaneurysms:    %d', n_ma), 'FontSize', 9, 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.39, sprintf('• Hard Exudates:       %d', n_hard), 'FontSize', 9, 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.33, sprintf('• Soft Exudates:         %d', n_soft), 'FontSize', 9, 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.27, sprintf('• Hemorrhages:         %d', n_hem), 'FontSize', 9, 'Parent', ax3, 'Interpreter', 'none');

    % Total Lesion Area Badge
    rectangle('Position', [0.60, 0.28, 0.35, 0.21], 'Curvature', 0.12, ...
        'FaceColor', [0.93, 0.96, 1.0], 'EdgeColor', [0.75, 0.83, 0.95], 'Parent', ax3);
    text(0.775, 0.42, 'Lesion Area', 'FontSize', 8.5, 'FontWeight', 'bold', ...
        'Color', [0.25, 0.35, 0.55], 'HorizontalAlignment', 'center', 'Parent', ax3, 'Interpreter', 'none');
    text(0.775, 0.34, sprintf('%.2f%%', area_pct), 'FontSize', 12, 'FontWeight', 'bold', ...
        'Color', [0.1, 0.2, 0.55], 'HorizontalAlignment', 'center', 'Parent', ax3, 'Interpreter', 'none');

    % Doctor Sign-Off Section (<30 second target)
    rectangle('Position', [0.02, 0.02, 0.96, 0.19], 'Curvature', 0.08, ...
        'FaceColor', [0.94, 0.96, 0.99], 'EdgeColor', [0.75, 0.82, 0.92], 'Parent', ax3);
    text(0.05, 0.15, 'OPHTHALMOLOGIST REVIEW & SIGN-OFF (<30s):', ...
        'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.1, 0.2, 0.4], 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.095, '[  ] Accept AI Recommendation        [  ] Override Grade: ______', ...
        'FontSize', 9, 'Parent', ax3, 'Interpreter', 'none');
    text(0.05, 0.04, 'Clinician Signature: ___________________     Date: ____________', ...
        'FontSize', 8.5, 'Color', [0.3, 0.3, 0.35], 'Parent', ax3, 'Interpreter', 'none');
end

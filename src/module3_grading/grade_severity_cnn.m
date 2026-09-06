function [icdr_grade, class_probs] = grade_severity_cnn(img, model)
% FUNCTION: grade_severity_cnn
% MODULE: 4 - Severity Grading, Path A (end-to-end CNN)
% STATUS: HEURISTIC_BASELINE (PLACEHOLDER FOR TRAINED CNN)
%
% PURPOSE:
%   Classifies a fundus image into ICDR severity grade 0-4 representing
%   "Path A" of the two-path fusion architecture. When a trained deep model
%   (e.g., ResNet/EfficientNet) is provided, executes deep inference. In the
%   absence of trained weights, runs an optical texture/spectral heuristic
%   baseline standing in for the deep network to enable end-to-end testing.
%
% INPUTS:
%   img (double, HxWx3 RGB, range [0,1]) - enhanced fundus image
%   model (dlnetwork, SeriesNetwork, or [] if not loaded) - trained 5-class
%       classification network. If [] is passed, the function checks for
%       models/dr_grading_cnn.mat or falls back to an image-level spectral
%       feature embedding heuristic to output valid probability distributions.
%
% OUTPUTS:
%   icdr_grade (int, 0-4) - predicted ICDR severity grade
%   class_probs (1x5 double) - softmax probabilities for grades [0, 1, 2, 3, 4],
%       guaranteed non-negative and summing to 1.0
%
% DEPENDS ON:
%   Deep Learning Toolbox (when trained neural network is provided)
%
% CALLED BY:
%   run_pipeline.m
%   src/module3_grading/fuse_grading.m
%
% KEY ASSUMPTIONS / ROADMAP NOTE:
%   - PLACEHOLDER STATUS: Currently functions as a texture-entropy heuristic
%     baseline until real transfer-learning weights are trained on APTOS/Messidor-2.
%   - Next milestone: train ResNet-50 / MobileNet via Deep Learning Toolbox and
%     export weights to 'models/dr_grading_cnn.mat'.
%   - If no trained model is loaded, the function evaluates global optical
%     texture, green-channel absorption spread, and chromatic variance
%     to generate a plausible 5-class softmax distribution.

    % Input normalization
    if ~isa(img, 'double')
        img = im2double(img);
    end
    [h, w, ~] = size(img);

    % --- Path A1: Trained Deep Learning Model Inference ---
    if isempty(model)
        model_file = fullfile('models', 'dr_grading_cnn.mat');
        if isfile(model_file)
            try
                loaded = load(model_file);
                if isfield(loaded, 'trained_net')
                    model = loaded.trained_net;
                elseif isfield(loaded, 'net')
                    model = loaded.net;
                end
            catch
                model = [];
            end
        end
    end

    if ~isempty(model)
        try
            % Resize to network input layer size (standard 224x224 or 256x256)
            input_sz = [224, 224];
            try
                input_sz = model.Layers(1).InputSize(1:2);
            catch
                % Keep default 224x224
            end
            img_resized = imresize(img, input_sz);
            % Ensure image is in expected dynamic range [0, 255] for standard CNNs
            if max(img_resized(:)) <= 1.0
                img_for_net = img_resized * 255.0;
            else
                img_for_net = img_resized;
            end

            % Standard MATLAB DAGNetwork / SeriesNetwork classification
            if isa(model, 'DAGNetwork') || isa(model, 'SeriesNetwork')
                [pred_cat, probs] = classify(model, img_for_net);
                icdr_grade = int32(str2double(char(pred_cat)));
                if isnan(icdr_grade)
                    [~, max_idx] = max(probs);
                    icdr_grade = int32(max_idx - 1);
                end
                class_probs = double(probs(:)');
                if length(class_probs) == 5
                    return;
                end
            else
                raw_scores = predict(model, img_for_net);
                raw_scores = double(raw_scores(:)');
                if abs(sum(raw_scores) - 1.0) < 0.05 && all(raw_scores >= 0)
                    class_probs = raw_scores;
                else
                    class_probs = exp(raw_scores - max(raw_scores)) ./ sum(exp(raw_scores - max(raw_scores)));
                end
                [~, max_idx] = max(class_probs);
                icdr_grade = int32(max_idx - 1);
                return;
            end
        catch
            % Fall through to spectral feature baseline
        end
    end

    % --- Path A2: Global Optical / Texture Feature Baseline ---
    % Evaluates retinal parenchyma when no external CNN weights are present
    green = img(:, :, 2);
    red   = img(:, :, 1);
    gray  = rgb2gray(img);

    fov_mask = gray > 0.05;
    if sum(fov_mask(:)) < 100
        fov_mask = true(h, w);
    end

    % Exclude normal vasculature to avoid counting vessels as hemorrhages
    vessel_proxy = (green < 0.20) & (red > 0.30) & fov_mask;
    se_vdil = strel('disk', max(2, round(min(h, w) * 0.008)));
    vessel_zone = imdilate(vessel_proxy, se_vdil);
    parenchyma = fov_mask & (~vessel_zone);

    % Metric 1: Dark lesion density outside vessels (microaneurysms & hemorrhages)
    se_close = strel('disk', max(10, round(min(h, w) * 0.025)));
    g_bg = imclose(green, se_close);
    g_dep = max(0, g_bg - green);
    dark_spots = (g_dep > 0.08) & ((red - green) > 0.10) & parenchyma;
    dark_fraction = double(sum(dark_spots(:))) / max(1, double(sum(parenchyma(:))));

    % Metric 2: Bright lesion density outside vessels (hard exudates)
    ex_int = 0.55 * red + 0.45 * green;
    bg = imopen(ex_int, se_close);
    contrast = ex_int - bg;
    bright_spots = (contrast > 0.12) & (red > 0.52) & (green > 0.38) & parenchyma;
    bright_fraction = double(sum(bright_spots(:))) / max(1, double(sum(parenchyma(:))));

    % Compute logits for 5 classes (centered on Grade 0 for healthy retinas)
    logits = zeros(1, 5);
    % Grade 0 (Normal): default state for clear retinal parenchyma
    logits(1) = 3.0 - 80.0 * dark_fraction - 80.0 * bright_fraction;
    % Grade 1 (Mild): mild microaneurysm presence
    logits(2) = 0.5 + 40.0 * min(0.005, dark_fraction) - 30.0 * bright_fraction;
    % Grade 2 (Moderate): presence of bright exudates or moderate hemorrhages
    logits(3) = -1.0 + 80.0 * bright_fraction + 50.0 * dark_fraction;
    % Grade 3 (Severe): substantial lesion density
    logits(4) = -2.5 + 120.0 * dark_fraction + 90.0 * bright_fraction;
    % Grade 4 (PDR): extensive proliferative burden
    logits(5) = -4.0 + 160.0 * dark_fraction + 120.0 * bright_fraction;

    % Softmax computation
    exp_logits = exp(logits - max(logits));
    class_probs = exp_logits / sum(exp_logits);
    class_probs = reshape(double(class_probs), 1, 5);

    [~, max_idx] = max(class_probs);
    icdr_grade = int32(max_idx - 1);
end

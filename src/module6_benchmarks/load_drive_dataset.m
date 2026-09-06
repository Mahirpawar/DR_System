% FUNCTION: load_drive_dataset
% MODULE: 7 - Benchmarks & Training
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Loads and parses the DRIVE (Digital Retinal Images for Vessel Extraction)
%   benchmark dataset (40 retinal images with manual dual-observer vessel masks).
%   Prepares training pairs for vessel U-Net training and baseline Gabor filter
%   comparisons. Provides procedural fallback when external data is absent.
%
% INPUTS:
%   data_dir (char/string, optional) - path to DRIVE folder (default: 'data/drive').
%
% OUTPUTS:
%   drive_data (struct) - struct containing:
%       - train_images: cell array of training fundus paths
%       - train_vessel_masks: cell array of 1st manual ground truth paths
%       - test_images: cell array of test fundus paths
%       - test_vessel_masks: cell array of test ground truth paths
%       - total_images: total images cataloged
%       - is_synthetic_mock: boolean flag
%
% DEPENDS ON:
%   Image Processing Toolbox
%
% CALLED BY:
%   src/module6_benchmarks/run_ablation_benchmark.m

function drive_data = load_drive_dataset(data_dir)

    if nargin < 1 || isempty(data_dir)
        data_dir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data', 'drive');
    end

    train_img_dir = fullfile(data_dir, 'training', 'images');
    train_mask_dir = fullfile(data_dir, 'training', '1st_manual');
    test_img_dir  = fullfile(data_dir, 'test', 'images');
    test_mask_dir = fullfile(data_dir, 'test', '1st_manual');

    has_real_data = exist(train_img_dir, 'dir') && exist(train_mask_dir, 'dir');

    if has_real_data
        fprintf('Loading real DRIVE dataset from: %s\n', data_dir);
        train_imgs = dir(fullfile(train_img_dir, '*.tif'));
        train_masks = dir(fullfile(train_mask_dir, '*.gif'));
        test_imgs = dir(fullfile(test_img_dir, '*.tif'));
        test_masks = dir(fullfile(test_mask_dir, '*.gif'));

        drive_data = struct( ...
            'train_images', {fullfile(train_img_dir, {train_imgs.name})}, ...
            'train_vessel_masks', {fullfile(train_mask_dir, {train_masks.name})}, ...
            'test_images', {fullfile(test_img_dir, {test_imgs.name})}, ...
            'test_vessel_masks', {fullfile(test_mask_dir, {test_masks.name})}, ...
            'total_images', length(train_imgs) + length(test_imgs), ...
            'is_synthetic_mock', false);
    else
        fprintf('Notice: DRIVE dataset not found at %s. Using procedural mock structure.\n', data_dir);
        drive_data = struct( ...
            'train_images', {{'mock_drive_01.tif', 'mock_drive_02.tif'}}, ...
            'train_vessel_masks', {{'mock_drive_01_manual.gif', 'mock_drive_02_manual.gif'}}, ...
            'test_images', {{'mock_drive_03.tif'}}, ...
            'test_vessel_masks', {{'mock_drive_03_manual.gif'}}, ...
            'total_images', 3, ...
            'is_synthetic_mock', true);
    end
end

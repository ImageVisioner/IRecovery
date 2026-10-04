%% run_DegFunction.m — 退化指定文件夹中的多帧图像
% 输入：new/data/multi grayscale image/Image4
% 输出：文件夹名称包含缺失模式和缺失率，并与 Image4 同级。

clear; clc; close all;

script_dir = fileparts(mfilename('fullpath'));
input_dir = fullfile(script_dir, 'data', 'multi grayscale image', 'Image1');

% 【模式开关】1=随机像素缺失；2=随机像素+完整行列混合缺失
missing_mode = 2;

per = 0.7;              % 随机像素观测率；基础随机缺失率为 1-per=10%
rng_seed = 1;           % 固定随机种子，保证结果可复现
num_missing_rows = 6;   % 模式2：每帧额外完全缺失的行数
num_missing_cols = 6;   % 模式2：每帧额外完全缺失的列数

% 留空后由退化函数按模式和实际总缺失率自动命名，结果与输入目录同级。
output_dir = '';

if ~isfolder(input_dir)
  error('找不到待退化图像目录: %s', input_dir);
end

output_dir = DegeneFuncion(input_dir, output_dir, per, rng_seed, ...
  missing_mode, num_missing_rows, num_missing_cols);

fprintf('\nrun_DegFunction 执行完成。\n');
fprintf('退化结果保存在: %s\n', output_dir);

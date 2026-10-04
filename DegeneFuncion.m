function output_dir = DegeneFuncion(input_path, output_dir, per, rng_seed, ...
  missing_mode, num_missing_rows, num_missing_cols)
%% DegeneFuncion — 生成模式1或模式2的缺失图像并保存
% 模式1：每个像素以概率 per 独立保留。
% 模式2：模式1基础上，再随机删除完整行和完整列。
% 用法：
%   DegeneFuncion()
%   DegeneFuncion(input_path, output_dir, per, rng_seed, missing_mode, ...
%     num_missing_rows, num_missing_cols)
% input_path 可为多图文件夹或单张图像路径。
% 输出目录结构：
%   observed/   观测图像（缺失处为 0）
%   clean/      真值（可选）
%   mask/       采样掩膜 Omega，1=观测 0=缺失（可选）
%   degenerated_data.mat  张量与掩膜，供后续实验加载
%
% 无参数运行时，默认处理 new/data/multi grayscale image。

%% ==================== 参数与默认值 ====================
script_dir = fileparts(mfilename('fullpath'));
fileExt = {'*.bmp', '*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff', '*.pgm'};
num_images = 0;              % multi：0=全部；>0 仅前 N 张
use_default_input = nargin < 1 || isempty(input_path);
if use_default_input
  input_path = fullfile(script_dir, 'data', 'multi grayscale image');
end
if nargin < 2, output_dir = ''; end
if nargin < 3 || isempty(per), per = 0.8; end
if nargin < 4 || isempty(rng_seed), rng_seed = 1; end
if nargin < 5 || isempty(missing_mode), missing_mode = 1; end
if nargin < 6 || isempty(num_missing_rows), num_missing_rows = 6; end
if nargin < 7 || isempty(num_missing_cols), num_missing_cols = 6; end

input_path = char(input_path);
output_dir = char(output_dir);
rng(rng_seed);

if ~ismember(missing_mode, [1, 2])
  error('missing_mode 必须为1（随机像素缺失）或2（随机-结构混合缺失）。');
end
if per < 0 || per > 1
  error('per 必须位于 [0,1]，当前值为 %.4f。', per);
end
if num_missing_rows < 0 || fix(num_missing_rows) ~= num_missing_rows || ...
    num_missing_cols < 0 || fix(num_missing_cols) ~= num_missing_cols
  error('num_missing_rows 和 num_missing_cols 必须为非负整数。');
end

save_clean = true;           % 是否保存真值到 clean/
save_mask = true;            % 是否保存 Omega 到 mask/
img_save_ext = '.png';       % 观测图保存扩展名：.png / .jpg / 

%% ==================== 解析输入 ====================
if isfolder(input_path)
  data_mode = 'multi';
  data_root_multi = input_path;
elseif isfile(input_path)
  data_mode = 'single';
  single_image_file = input_path;
else
  error('输入路径不存在: %s', input_path);
end

%% ==================== 生成退化数据 ====================
switch data_mode
  case 'multi'
    [CompleteCleanData, IncompleteData, array_Omega, array_Omega_c, ...
      file_list, faceH, faceW, K, data_label, input_desc] = ...
      build_multi_degenerated(data_root_multi, fileExt, num_images, per, ...
      missing_mode, num_missing_rows, num_missing_cols);
  case 'single'
    [CompleteCleanData, IncompleteData, array_Omega, array_Omega_c, ...
      file_list, faceH, faceW, K, data_label, input_desc] = ...
      build_single_degenerated(single_image_file, per, missing_mode, ...
      num_missing_rows, num_missing_cols);
  otherwise
    error('data_mode 须为 ''multi'' 或 ''single''。');
end

obs_rate = mean(array_Omega(:));
fprintf('数据源: %s\n', data_label);
fprintf('张量尺寸: %d × %d × %d，平均观测率: %.2f%%\n', faceH, faceW, K, obs_rate * 100);

%% ==================== 创建输出目录并保存 ====================
if isempty(strtrim(output_dir))
  run_tag = sprintf('%s_mode%d_missing%03d_seed%d', data_mode, missing_mode, ...
    round((1 - obs_rate) * 100), rng_seed);
  if use_default_input
    output_dir = fullfile(script_dir, 'data', 'degenerated', run_tag);
  else
    [parent_dir, input_name] = fileparts(input_path);
    output_dir = fullfile(parent_dir, sprintf('%s_degenerated_mode%d_missing%03d', ...
      input_name, missing_mode, round((1 - obs_rate) * 100)));
  end
end

dir_obs = fullfile(output_dir, 'observed');
dir_clean = fullfile(output_dir, 'clean');
dir_mask = fullfile(output_dir, 'mask');

mkdir(output_dir);
mkdir(dir_obs);
if save_clean, mkdir(dir_clean); end
if save_mask, mkdir(dir_mask); end

fprintf('\n保存到: %s\n', output_dir);

is_rgb_stack = (K == 3) && numel(file_list) == 3 && ...
  all(strcmp({file_list.name}, {'R', 'G', 'B'}));

if is_rgb_stack
  obs_rgb = stack_to_rgb(IncompleteData);
  clean_rgb = stack_to_rgb(CompleteCleanData);
  mask_vis = array_Omega(:, :, 1);
  [~, base_name, ~] = fileparts(input_desc);
  if isempty(base_name), base_name = 'image'; end
  write_image(fullfile(dir_obs, [base_name, '_observed', img_save_ext]), obs_rgb);
  if save_clean
    write_image(fullfile(dir_clean, [base_name, '_clean', img_save_ext]), clean_rgb);
  end
  if save_mask
    write_image(fullfile(dir_mask, [base_name, '_omega', img_save_ext]), mask_vis);
  end
  fprintf('  [RGB] %s_observed%s\n', base_name, img_save_ext);
else
  for k = 1:K
    [~, stem, ~] = fileparts(file_list(k).name);
    if isempty(stem), stem = sprintf('slice_%03d', k); end
    write_image(fullfile(dir_obs, [stem, '_observed', img_save_ext]), IncompleteData(:, :, k));
    if save_clean
      write_image(fullfile(dir_clean, [stem, '_clean', img_save_ext]), CompleteCleanData(:, :, k));
    end
    if save_mask
      write_image(fullfile(dir_mask, [stem, '_omega', img_save_ext]), array_Omega(:, :, k));
    end
    fprintf('  [%d/%d] %s_observed%s\n', k, K, stem, img_save_ext);
  end
end

meta = struct();
meta.data_mode = data_mode;
meta.data_label = data_label;
meta.input_desc = input_desc;
meta.per = per;
meta.missing_rate = 1 - obs_rate;
meta.missing_mode = missing_mode;
if missing_mode == 1
  meta.missing_mode_name = 'random pixel missing';
else
  meta.missing_mode_name = 'random-structural mixed missing';
end
meta.num_missing_rows = num_missing_rows;
meta.num_missing_cols = num_missing_cols;
meta.rng_seed = rng_seed;
meta.faceH = faceH;
meta.faceW = faceW;
meta.K = K;
meta.obs_rate = obs_rate;
meta.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
meta.file_list = file_list;

save(fullfile(output_dir, 'degenerated_data.mat'), ...
  'CompleteCleanData', 'IncompleteData', 'array_Omega', 'array_Omega_c', ...
  'file_list', 'faceH', 'faceW', 'K', 'data_label', 'per', 'rng_seed', 'meta', ...
  '-v7.3');

write_meta_txt(fullfile(output_dir, 'meta.txt'), meta);

fprintf('\n完成。观测图像目录: %s\n', dir_obs);
fprintf('MAT 文件: %s\n', fullfile(output_dir, 'degenerated_data.mat'));
end

%% ==================== 局部函数 ====================
function [CompleteCleanData, IncompleteData, array_Omega, array_Omega_c, ...
    file_list, faceH, faceW, K, data_label, input_desc] = ...
    build_multi_degenerated(SamplePath, fileExt, num_images, per, ...
    missing_mode, num_missing_rows, num_missing_cols)

fprintf('=== multi：生成观测数据 ===\n');
fprintf('目录: %s\n', SamplePath);
input_desc = SamplePath;

file_groups = cell(numel(fileExt), 1);
for e = 1:numel(fileExt)
  file_groups{e} = dir(fullfile(SamplePath, fileExt{e}));
  file_groups{e} = file_groups{e}(~[file_groups{e}.isdir]);
end
file_list = vertcat(file_groups{:});
if isempty(file_list)
  error('未找到支持的图像 (%s): %s', strjoin(fileExt, ', '), SamplePath);
end

names = {file_list.name}';
nums = zeros(numel(names), 1);
for k = 1:numel(names)
  tok = regexp(names{k}, '^(\d+)', 'tokens', 'once');
  if ~isempty(tok), nums(k) = str2double(tok{1}); else, nums(k) = k; end
end
[~, ord] = sort(nums);
file_list = file_list(ord);

K_total = numel(file_list);
if num_images > 0
  K = min(num_images, K_total);
  file_list = file_list(1:K);
else
  K = K_total;
end

first_img = imread(fullfile(SamplePath, file_list(1).name));
if ndims(first_img) == 3, first_img = rgb2gray(first_img); end
[faceH, faceW] = size(first_img);

CompleteCleanData = zeros(faceH, faceW, K);
IncompleteData = zeros(faceH, faceW, K);
array_Omega = ones(faceH, faceW, K);
array_Omega_c = zeros(faceH, faceW, K);

for i = 1:K
  image = imread(fullfile(SamplePath, file_list(i).name));
  if ndims(image) == 3, image = rgb2gray(image); end
  if ~isequal(size(image), [faceH, faceW])
    image = imresize(image, [faceH, faceW]);
  end
  [CompleteCleanData(:, :, i), IncompleteData(:, :, i), ...
    array_Omega(:, :, i), array_Omega_c(:, :, i)] = ...
    apply_missing_pattern(double(image) / 255, per, faceH, faceW, ...
    missing_mode, num_missing_rows, num_missing_cols);
end
data_label = 'multi grayscale image';
end

function [CompleteCleanData, IncompleteData, array_Omega, array_Omega_c, ...
    file_list, faceH, faceW, K, data_label, input_desc] = ...
    build_single_degenerated(image_path, per, missing_mode, ...
    num_missing_rows, num_missing_cols)

fprintf('=== single：生成观测数据 ===\n');
fprintf('文件: %s\n', image_path);
input_desc = image_path;
[~, img_name, img_ext] = fileparts(image_path);
image = imread(image_path);

if ndims(image) == 3 && size(image, 3) >= 3
  image = im2double(image(:, :, 1:3));
  faceH = size(image, 1);
  faceW = size(image, 2);
  K = 3;
  ch_names = {'R', 'G', 'B'};
  CompleteCleanData = zeros(faceH, faceW, K);
  IncompleteData = zeros(faceH, faceW, K);
  array_Omega = ones(faceH, faceW, K);
  array_Omega_c = zeros(faceH, faceW, K);
  [~, ~, omega0, omega_c0] = apply_missing_pattern(image(:, :, 1), per, ...
    faceH, faceW, missing_mode, num_missing_rows, num_missing_cols);
  for i = 1:K
    CompleteCleanData(:, :, i) = image(:, :, i);
    array_Omega(:, :, i) = omega0;
    array_Omega_c(:, :, i) = omega_c0;
    IncompleteData(:, :, i) = CompleteCleanData(:, :, i) .* omega0;
  end
  file_list = struct('name', ch_names');
  data_label = sprintf('single image (RGB) %s%s', img_name, img_ext);
else
  if ndims(image) == 3, image = rgb2gray(image); end
  image = im2double(image);
  faceH = size(image, 1);
  faceW = size(image, 2);
  K = 1;
  CompleteCleanData = zeros(faceH, faceW, 1);
  IncompleteData = zeros(faceH, faceW, 1);
  array_Omega = ones(faceH, faceW, 1);
  array_Omega_c = zeros(faceH, faceW, 1);
  [CompleteCleanData(:, :, 1), IncompleteData(:, :, 1), ...
    array_Omega(:, :, 1), array_Omega_c(:, :, 1)] = ...
    apply_missing_pattern(image, per, faceH, faceW, missing_mode, ...
    num_missing_rows, num_missing_cols);
  file_list = struct('name', {[img_name, img_ext]});
  data_label = sprintf('single image (gray) %s%s', img_name, img_ext);
end
end

function [clean, incomplete, omega, omega_c] = apply_missing_pattern( ...
  image, per, faceH, faceW, missing_mode, num_missing_rows, num_missing_cols)
% omega(i,j)=1 表示观测，P(omega(i,j)=1)=per。
clean = image;
omega = double(rand(faceH, faceW) < per);

if missing_mode == 2
  row_count = min(num_missing_rows, faceH);
  col_count = min(num_missing_cols, faceW);
  if row_count > 0
    missing_rows = randperm(faceH, row_count);
    omega(missing_rows, :) = 0;
  end
  if col_count > 0
    missing_cols = randperm(faceW, col_count);
    omega(:, missing_cols) = 0;
  end
end

omega_c = 1 - omega;
incomplete = clean .* omega;
end

function rgb = stack_to_rgb(tensor3)
rgb = tensor3;
if max(rgb(:)) <= 1
  rgb = min(max(rgb, 0), 1);
else
  rgb = double(rgb) / 255;
end
end

function write_image(path, img)
[~, ~, ext] = fileparts(path);
if strcmpi(ext, '.pgm')
  if max(img(:)) <= 1
    imwrite(uint8(round(min(max(img, 0), 1) * 255)), path);
  else
    imwrite(uint8(round(img)), path);
  end
elseif max(img(:)) <= 1
  imwrite(min(max(img, 0), 1), path);
else
  imwrite(uint8(round(img)), path);
end
end

function write_meta_txt(path, meta)
fid = fopen(path, 'w');
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'data_mode: %s\n', meta.data_mode);
fprintf(fid, 'data_label: %s\n', meta.data_label);
fprintf(fid, 'input: %s\n', meta.input_desc);
fprintf(fid, 'per: %.4f\n', meta.per);
fprintf(fid, 'missing_rate: %.4f (%.2f%%)\n', ...
  meta.missing_rate, meta.missing_rate * 100);
fprintf(fid, 'missing_mode: %d (%s)\n', meta.missing_mode, meta.missing_mode_name);
fprintf(fid, 'num_missing_rows: %d\n', meta.num_missing_rows);
fprintf(fid, 'num_missing_cols: %d\n', meta.num_missing_cols);
fprintf(fid, 'rng_seed: %d\n', meta.rng_seed);
fprintf(fid, 'size: %d x %d x %d\n', meta.faceH, meta.faceW, meta.K);
fprintf(fid, 'obs_rate: %.4f\n', meta.obs_rate);
fprintf(fid, 'created: %s\n', meta.created);
end

function results = tomo_set_check(param,products,frm,img,ref_paths)
% results = tomo_set_check(param,products,frm,img,ref_paths)
%
% Acceptance checks for one frame of a set of 3D array products (standard,
% MVDR, MUSIC) that are meant to be compared pixel for pixel.
%
% A set passes when:
%  1. Every file has Tomo.img with a look-direction dimension equal to Nsv.
%  2. param_array.array.method in each file matches the method expected
%     for its directory.
%  3. GPS_time, Time and Tomo.theta are identical across the set. If they
%     are not, the runs were not configured identically.
%  4. The MVDR file's DCM support differs from its bin_rng/line_rng, and its
%     cube has no non-positive values.
%  5. The MUSIC cube's minimum is within 10% of 0.5*(Nc - Nsrc), which
%     confirms Nc and Nsrc are what the file claims.
% Optionally, the set's GPS_time is also compared against 2D products named
% in ref_paths (for example the posted CSARP_standard and the delay-Doppler
% product) to confirm every product sits on the same traces.
%
% INPUTS
% =========================================================================
% param: parameter spreadsheet struct for the segment, already merged with
%   gRadar so that opr_filename_out resolves
% products: struct array with fields
%   .method: 'standard', 'mvdr' or 'music'
%   .out_path: opr_filename_out directory, e.g. 'mvdr3D_ndh'
% frm: frame number
% img: image number. Default is 1. array_combine_task.m names 3D outputs
%   Data_img_II_YYYYMMDD_SS_FFF.mat whenever tomo_en is true.
% ref_paths: optional cell array of 2D product directories to check trace
%   alignment against. Default is {}.
%
% OUTPUTS
% =========================================================================
% results: struct array, one entry per check
%   .check: description
%   .pass: true, false, or NaN when the check could not run
%   .detail: the numbers behind the verdict
%
% Loads one Tomo cube at a time and keeps only summary statistics, so peak
% memory is one cube rather than three.
%
% Author: Nick Holschuh
%
% See also: run_delay_doppler_tomo, array_proc, array_combine_task

if ~exist('img','var') || isempty(img)
  img = 1;
end
if ~exist('ref_paths','var') || isempty(ref_paths)
  ref_paths = {};
end

array_proc_methods; % STANDARD_METHOD, MVDR_METHOD, MUSIC_METHOD
method_int = struct('standard',STANDARD_METHOD,'mvdr',MVDR_METHOD,'music',MUSIC_METHOD);

results = struct('check',{},'pass',{},'detail',{});

%% Load each product
% =========================================================================
info = repmat(struct('fn','','exists',false,'GPS_time',[],'Time',[],'array',[], ...
  'Nc',NaN,'theta',[],'img_min',NaN,'n_nonpos',NaN,'n_total',NaN),1,length(products));
for prod_idx = 1:length(products)
  p = products(prod_idx);
  fn = fullfile(opr_filename_out(param,p.out_path,''), ...
    sprintf('Data_img_%02d_%s_%03d.mat', img, param.day_seg, frm));
  info(prod_idx).fn = fn;
  info(prod_idx).exists = exist(fn,'file') == 2;
  if ~info(prod_idx).exists
    results(end+1) = mkres(sprintf('%s: file exists',p.out_path),false,fn); %#ok<AGROW>
    continue;
  end

  S = load(fn,'GPS_time','Time','param_array');
  info(prod_idx).GPS_time = S.GPS_time;
  info(prod_idx).Time = S.Time;
  arr = S.param_array.array;
  info(prod_idx).array = arr;

  % Channel count of this image. array.m reformats imgs to the multilook
  % form, a cell of wf-adc matrices per image; take the first look.
  img_def = arr.imgs{img};
  if iscell(img_def)
    img_def = img_def{1};
  end
  info(prod_idx).Nc = size(img_def,1);

  T = load(fn,'Tomo');
  has_tomo = isfield(T,'Tomo') && isfield(T.Tomo,'img');
  if ~has_tomo
    results(end+1) = mkres(sprintf('%s: has Tomo.img',p.out_path),false, ...
      'no Tomo.img, so this is a 2D product'); %#ok<AGROW>
    continue;
  end
  info(prod_idx).theta = T.Tomo.theta;
  Nsv_file = size(T.Tomo.img,2);
  info(prod_idx).img_min = min(T.Tomo.img(:));
  info(prod_idx).n_nonpos = sum(T.Tomo.img(:) <= 0);
  info(prod_idx).n_total = numel(T.Tomo.img);
  clear T;

  results(end+1) = mkres(sprintf('%s: Tomo.img look dimension == Nsv',p.out_path), ...
    Nsv_file == arr.Nsv && arr.Nsv > 1, ...
    sprintf('size(Tomo.img,2) = %d, Nsv = %d', Nsv_file, arr.Nsv)); %#ok<AGROW>

  want = method_int.(lower(p.method));
  results(end+1) = mkres(sprintf('%s: method is %s',p.out_path,p.method), ...
    isequal(arr.method,want), ...
    sprintf('file method = %s, expected %d', mat2str(arr.method), want)); %#ok<AGROW>
end

loaded = find([info.exists] & arrayfun(@(s) ~isempty(s.theta), info));

%% Shared grids
% =========================================================================
if length(loaded) >= 2
  ref = info(loaded(1));
  same_gps = true; same_time = true; same_theta = true;
  for k = loaded(2:end)
    same_gps   = same_gps   && isequal(info(k).GPS_time,ref.GPS_time);
    same_time  = same_time  && isequal(info(k).Time,ref.Time);
    same_theta = same_theta && isequal(info(k).theta,ref.theta);
  end
  names = strjoin({products(loaded).out_path},', ');
  results(end+1) = mkres('GPS_time identical across the set',same_gps,names);
  results(end+1) = mkres('Time identical across the set',same_time,names);
  results(end+1) = mkres('Tomo.theta identical across the set',same_theta,names);
end

%% Estimator-specific checks
% =========================================================================
for k = loaded
  p = products(k);
  arr = info(k).array;
  switch lower(p.method)
    case 'mvdr'
      dcm_differs = ~(isequal(arr.DCM.bin_rng(:),arr.bin_rng(:)) ...
        && isequal(arr.DCM.line_rng(:),arr.line_rng(:)));
      K = numel(arr.DCM.bin_rng)*numel(arr.DCM.line_rng);
      results(end+1) = mkres(sprintf('%s: DCM support differs from multilook',p.out_path), ...
        dcm_differs, sprintf('%d DCM snapshots for Nc = %d (diag_load %g)', ...
        K, info(k).Nc, arr.diag_load)); %#ok<AGROW>
      results(end+1) = mkres(sprintf('%s: no non-positive values',p.out_path), ...
        info(k).n_nonpos == 0, sprintf('%d of %d values <= 0', ...
        info(k).n_nonpos, info(k).n_total)); %#ok<AGROW>

    case 'music'
      floor_expected = 0.5*(info(k).Nc - arr.Nsrc);
      if floor_expected > 0
        ok = abs(info(k).img_min - floor_expected) <= 0.1*floor_expected;
      else
        ok = NaN;
      end
      results(end+1) = mkres(sprintf('%s: minimum near 0.5*(Nc-Nsrc)',p.out_path), ok, ...
        sprintf('min %.4g, expected %.4g for Nc = %d, Nsrc = %d', ...
        info(k).img_min, floor_expected, info(k).Nc, arr.Nsrc)); %#ok<AGROW>
  end
end

%% Alignment with 2D reference products
% =========================================================================
if ~isempty(loaded)
  set_gps = info(loaded(1)).GPS_time(:);
  for ref_idx = 1:length(ref_paths)
    ref_dir = opr_filename_out(param,ref_paths{ref_idx},'');
    ref_fn = fullfile(ref_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm));
    if ~exist(ref_fn,'file')
      ref_fn = fullfile(ref_dir,sprintf('Data_img_%02d_%s_%03d.mat',img,param.day_seg,frm));
    end
    if ~exist(ref_fn,'file')
      results(end+1) = mkres(sprintf('aligned with %s',ref_paths{ref_idx}),NaN, ...
        'no file for this frame'); %#ok<AGROW>
      continue;
    end
    R = load(ref_fn,'GPS_time');
    ref_gps = R.GPS_time(:);
    same_n = numel(ref_gps) == numel(set_gps);
    if same_n
      max_dt = max(abs(ref_gps - set_gps));
    else
      max_dt = NaN;
    end
    results(end+1) = mkres(sprintf('aligned with %s',ref_paths{ref_idx}), ...
      same_n && max_dt < 1e-6, sprintf('Nx %d vs %d, max |dt| %.3g s', ...
      numel(ref_gps), numel(set_gps), max_dt)); %#ok<AGROW>
  end
end

%% Report
% =========================================================================
fprintf('\n  %s frame %03d img %02d\n', param.day_seg, frm, img);
for k = 1:length(results)
  if isnan(results(k).pass)
    verdict = 'n/a ';
  elseif results(k).pass
    verdict = 'PASS';
  else
    verdict = 'FAIL';
  end
  fprintf('    %s  %-48s %s\n', verdict, results(k).check, results(k).detail);
end

end

function r = mkres(check,pass,detail)
r = struct('check',check,'pass',double(pass),'detail',detail);
end

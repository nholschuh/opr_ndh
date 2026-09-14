% script run_along_track_sampling
%
% Runs along_track_sampling on every segment of every listed season and
% writes a summary of the raw along-track sampling.
%
% Two outputs are produced:
%  1. A per-segment CSV table, one row per segment.
%  2. A per-season summary printed to screen, and the full struct array
%     saved to a .mat file next to the CSV.
%
% Only records files are read, so this can be run on any season that has
% made it through records_create.
%
% Author: Nick Holschuh
%
% See also: along_track_sampling

%% User Settings
% =========================================================================

% Seasons to survey. Edit freely. Setting run_all instead of this list will
% sweep every season the toolbox knows about, which takes a long time.
param_fns = {};
param_fns{end+1} = 'rds_param_2018_Antarctica_Ground.xlsx';
param_fns{end+1} = 'rds_param_2019_Antarctica_Ground.xlsx';
param_fns{end+1} = 'rds_param_2022_Antarctica_GroundGHOST.xlsx';
param_fns{end+1} = 'rds_param_2023_Antarctica_GroundGHOST.xlsx';
param_fns{end+1} = 'rds_param_2024_Antarctica_GroundGHOST.xlsx';
param_fns{end+1} = 'rds_param_2024_Antarctica_GroundGHOST2.xlsx';
param_fns{end+1} = 'accum_param_2024_Antarctica_Ground.xlsx';
param_fns{end+1} = 'accum_param_2024_Antarctica_Ground2.xlsx';
% run_all;   % uncomment to use the toolbox-wide season list instead

param_override = [];

% Smooth the trajectory before differencing. Leave empty for airborne data.
% For ground-based data moving at walking pace, GPS noise is a large
% fraction of the record-to-record motion and the unsmoothed differences
% read high; a few times the expected record spacing is a good value.
param_override.along_track_sampling.gps_filter_spacing = [];

% Drop records slower than this from the statistics, in m/s. Set it on
% ground seasons that contain long stationary periods.
param_override.along_track_sampling.speed_threshold = 0;

param_override.along_track_sampling.prctiles = [5 25 50 75 95];

% Where the table goes. Left empty, it lands in the current directory.
out_dir = '';

%% Automated Section
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

if isempty(out_dir)
  out_dir = pwd;
end
if ~exist(out_dir,'dir')
  mkdir(out_dir);
end
out_fn_csv = fullfile(out_dir,'along_track_sampling.csv');
out_fn_mat = fullfile(out_dir,'along_track_sampling.mat');

sampling = [];

%% Loop over seasons
for season_idx = 1:length(param_fns)

  param_fn = opr_filename_param(param_fns{season_idx});
  fprintf('\n==== %s\n', param_fn);
  if ~exist(param_fn,'file')
    warning('Parameter spreadsheet not found, skipping: %s', param_fn);
    continue;
  end

  params = read_param_xls(param_fn,'');
  if isempty(params)
    continue;
  end

  params = opr_set_params(params,'cmd.generic',1);
  params = opr_set_params(params,'cmd.generic',0,'cmd.notes','do not process');

  fprintf('%-14s\t%7s\t%8s\t%8s\t%8s\t%8s\t%8s\t%7s\t%8s\t%8s\n', ...
    'day_seg','Nx','dx_med','dx_p05','dx_p95','rate_m','rate_hdr','speed','qlook_dx','std_dx');

  %% Loop over segments
  for seg_idx = 1:length(params)
    param = params(seg_idx);

    if ~opr_generic_en(param)
      continue;
    end

    try
      seg_sampling = along_track_sampling(param,param_override);
    catch ME
      fprintf('%s\terror!!!\t%s\n', param.day_seg, ME.message);
      continue;
    end

    if isempty(sampling)
      sampling = seg_sampling;
    else
      sampling(end+1) = seg_sampling; %#ok<SAGROW>
    end
  end
end

if isempty(sampling)
  error('No segments were surveyed. Check the season list and that records files exist.');
end

%% Per-season summary
% =========================================================================
% The season-level number is the median over segments of the per-segment
% median spacing, which is insensitive to a single short or stationary
% segment. The range across segments is printed beside it.
fprintf('\n\n==== Season summary\n');
fprintf('%-36s\t%5s\t%10s\t%10s\t%10s\t%10s\t%10s\n', ...
  'season','Nseg','dx_med(m)','dx_min(m)','dx_max(m)','rate(Hz)','std_dx(m)');

season_names = unique({sampling.season_name});
for season_idx = 1:length(season_names)
  mask = strcmp({sampling.season_name},season_names{season_idx});
  dx_med = [sampling(mask).dx_median];
  rate = [sampling(mask).rate_measured];
  std_dx = [sampling(mask).standard_dx_nominal];

  fprintf('%-36s\t%5d\t%10.3f\t%10.3f\t%10.3f\t%10.2f\t%10.3f\n', ...
    season_names{season_idx}, sum(mask), ...
    median(dx_med,'omitnan'), min(dx_med), max(dx_med), ...
    median(rate,'omitnan'), median(std_dx,'omitnan'));
end

%% Write the table
% =========================================================================
fid = fopen(out_fn_csv,'w');
if fid < 0
  error('Could not open %s for writing.', out_fn_csv);
end
fprintf(fid,['season_name,day_seg,Nx,Nx_used,frac_masked,duration_s,length_m,' ...
  'dx_median_m,dx_mean_m,dx_std_m,dx_min_m,dx_max_m,dx_p05_m,dx_p95_m,' ...
  'dt_median_s,rate_measured_Hz,rate_header_Hz,rate_ratio,' ...
  'speed_median_mps,prf_Hz,presums_total,' ...
  'qlook_dx_nominal_m,sar_sigma_x_m,array_dline,standard_dx_nominal_m\n']);
for seg_idx = 1:length(sampling)
  s = sampling(seg_idx);
  fprintf(fid,'%s,%s,%d,%d,%.4f,%.2f,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.6g,%.4f,%.4f,%.4f,%.3f,%.6g,%.6g,%.4f,%.4f,%.6g,%.4f\n', ...
    s.season_name, s.day_seg, s.Nx, s.Nx_used, s.frac_masked, s.duration, s.length, ...
    s.dx_median, s.dx_mean, s.dx_std, s.dx_min, s.dx_max, s.dx_prctile(1), s.dx_prctile(end), ...
    s.dt_median, s.rate_measured, s.rate_header, s.rate_ratio, ...
    s.speed_median, s.prf, s.presums_total, ...
    s.qlook_dx_nominal, s.sar_sigma_x, s.array_dline, s.standard_dx_nominal);
end
fclose(fid);

save(out_fn_mat,'sampling','param_fns','-v7.3');

fprintf('\nWrote %s\n', out_fn_csv);
fprintf('Wrote %s\n', out_fn_mat);

function sampling = along_track_sampling(param,param_override)
% sampling = along_track_sampling(param,param_override)
%
% Measures the along-track sampling of the RAW data for one segment. "Raw"
% here means one entry per record in the records file, which is one entry
% per effective pulse repetition interval after hardware presumming. That
% is the finest along-track sampling any processing stage can draw on.
%
% Only the records file is read. No raw data files are opened and no
% echogram product needs to exist, so this can be run on a season as soon
% as records files have been created.
%
% Three things are reported per segment:
%  1. The measured along-track spacing between consecutive records, taken
%     from the records trajectory.
%  2. The measured record rate, alongside the record rate implied by the
%     radar header (PRF divided by total hardware presums). A disagreement
%     usually means dropped records, or a PRF entry in the parameter
%     spreadsheet that does not match the hardware.
%  3. The nominal posted along-track spacing of the qlook and array
%     products, from the parameter spreadsheet. This is what the raw
%     sampling gets decimated to, and it is the spacing at which a
%     delay-Doppler product would be posted to match the standard product.
%
% INPUTS
% =========================================================================
% param: struct from the parameter spreadsheet for a single segment
%  .along_track_sampling: optional struct controlling this function
%   .gps_filter_spacing: scalar in meters. Default is [] (no filtering).
%     When set, the trajectory is smoothed by geodetic_to_along_track using
%     its decimate-and-fit mode before the spacing is measured. Set this
%     for slow-moving ground-based data, where GPS noise is a large
%     fraction of the true record-to-record motion and the raw differences
%     read high. A few times the expected record spacing is sensible. Note
%     that this mode of geodetic_to_along_track fits a line through each
%     decimated section, so individual spacings can come out slightly
%     negative where the trajectory doubles back within a section. That
%     shows up in dx_min and the low percentiles, not in the median.
%   .speed_threshold: scalar in m/s. Default is 0, which keeps everything.
%     Records moving slower than this are excluded from the statistics,
%     which matters on ground-based seasons containing long stationary
%     periods.
%   .prctiles: percentiles of the spacing to report. Default [5 25 50 75 95].
%
% param_override: standard OPR override struct, merged with gRadar
%
% OUTPUTS
% =========================================================================
% sampling: struct of results for this segment
%   .day_seg, .season_name, .radar_name
%   .Nx: number of records in the segment
%   .Nx_used: number of spacing samples kept after masking
%   .frac_masked: fraction of spacing samples excluded
%   .duration: segment length in seconds
%   .length: total along-track distance in meters
%   .dx_median, .dx_mean, .dx_std, .dx_min, .dx_max: spacing in meters
%   .prctiles, .dx_prctile: percentiles of the spacing in meters
%   .dt_median: median time between records in seconds
%   .rate_measured: measured record rate in Hz
%   .rate_header: record rate implied by PRF and presums in Hz. NaN when
%     the spreadsheet and records file do not carry both.
%   .rate_ratio: rate_measured/rate_header
%   .speed_median, .speed_min, .speed_max: platform speed in m/s
%   .prf, .presums, .presums_total: radar header values used
%   .qlook_dx_nominal: posted spacing of the qlook product in meters
%   .sar_sigma_x, .array_dline, .standard_dx_nominal: posted spacing of the
%     array product (standard, mvdr, music) in meters
%
% Example:
%  param = read_param_xls(opr_filename_param('rds_param_2019_Antarctica_Ground.xls'),'20191231_04');
%  sampling = along_track_sampling(param);
%
% Author: Nick Holschuh
%
% See also: run_along_track_sampling, records_load, geodetic_to_along_track

%% Input checks
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end
param = merge_structs(param,param_override);

if ~isfield(param,'along_track_sampling') || isempty(param.along_track_sampling)
  param.along_track_sampling = [];
end

if ~isfield(param.along_track_sampling,'gps_filter_spacing')
  param.along_track_sampling.gps_filter_spacing = [];
end

if ~isfield(param.along_track_sampling,'speed_threshold') || isempty(param.along_track_sampling.speed_threshold)
  param.along_track_sampling.speed_threshold = 0;
end

if ~isfield(param.along_track_sampling,'prctiles') || isempty(param.along_track_sampling.prctiles)
  param.along_track_sampling.prctiles = [5 25 50 75 95];
end

%% Output struct
% =========================================================================
% Every field is defined up front so that a segment which returns early
% still concatenates with the others in the driver script.
sampling                     = [];
sampling.day_seg             = param.day_seg;
sampling.season_name         = param.season_name;
sampling.radar_name          = param.radar_name;
sampling.Nx                  = NaN;
sampling.Nx_used             = NaN;
sampling.frac_masked         = NaN;
sampling.duration            = NaN;
sampling.length              = NaN;
sampling.dx_median           = NaN;
sampling.dx_mean             = NaN;
sampling.dx_std              = NaN;
sampling.dx_min              = NaN;
sampling.dx_max              = NaN;
sampling.prctiles            = param.along_track_sampling.prctiles(:).';
sampling.dx_prctile          = nan(1,numel(sampling.prctiles));
sampling.dt_median           = NaN;
sampling.rate_measured       = NaN;
sampling.rate_header         = NaN;
sampling.rate_ratio          = NaN;
sampling.speed_median        = NaN;
sampling.speed_min           = NaN;
sampling.speed_max           = NaN;
sampling.prf                 = NaN;
sampling.presums             = [];
sampling.presums_total       = NaN;
sampling.qlook_dx_nominal    = NaN;
sampling.sar_sigma_x         = NaN;
sampling.array_dline         = NaN;
sampling.standard_dx_nominal = NaN;

%% Load the records trajectory
% =========================================================================
% Only the trajectory fields are requested, which avoids pulling the byte
% offset table and the raw header struct into memory for every segment.
records = records_load(param,'lat','lon','elev','gps_time','settings');

sampling.Nx = numel(records.gps_time);
if sampling.Nx < 2
  warning('%s: fewer than two records, nothing to measure.', param.day_seg);
  return;
end

% bit_mask is optional in the records file format, so it is loaded
% separately and guarded rather than requested above.
records_fn = opr_filename_support(param,'','records');
mat_vars = whos('-file',records_fn);
if any(strcmp('bit_mask',{mat_vars.name}))
  tmp = load(records_fn,'bit_mask');
  % bit_mask is Nb by Nx. Bit 0 (value 1) marks a bad record and bit 1
  % (value 2) marks stationary data. A record is dropped if any board
  % flags it.
  bad_mask = any(bitand(tmp.bit_mask,uint8(3)) > 0, 1);
else
  bad_mask = false(1,sampling.Nx);
end

%% Measure the along-track spacing
% =========================================================================
along_track = geodetic_to_along_track(records.lat,records.lon,records.elev, ...
  param.along_track_sampling.gps_filter_spacing);
along_track = along_track(:).';

sampling.length = along_track(end) - along_track(1);
sampling.duration = records.gps_time(end) - records.gps_time(1);

dx = diff(along_track);
dt = diff(records.gps_time(:).');

% A spacing sample survives only if both records bounding it are good
good_mask = ~(bad_mask(1:end-1) | bad_mask(2:end));
% and if time advanced, which guards against duplicated records
good_mask = good_mask & dt > 0;

speed = nan(size(dx));
speed(dt > 0) = dx(dt > 0) ./ dt(dt > 0);
if param.along_track_sampling.speed_threshold > 0
  good_mask = good_mask & speed >= param.along_track_sampling.speed_threshold;
end

sampling.Nx_used = sum(good_mask);
sampling.frac_masked = 1 - sampling.Nx_used/numel(dx);
if sampling.Nx_used < 1
  warning('%s: no usable records after masking.', param.day_seg);
  return;
end

dx = dx(good_mask);
dt = dt(good_mask);
speed = speed(good_mask);

sampling.dx_median = median(dx);
sampling.dx_mean   = mean(dx);
sampling.dx_std    = std(dx);
sampling.dx_min    = min(dx);
sampling.dx_max    = max(dx);

% Percentiles are computed here rather than with prctile.m so that this
% function does not require the Statistics Toolbox
dx_sorted = sort(dx);
if numel(dx_sorted) == 1
  % interp1 needs at least two sample points, and every percentile of a
  % single observation is that observation
  sampling.dx_prctile = repmat(dx_sorted,1,numel(sampling.prctiles));
else
  sampling.dx_prctile = interp1(1:numel(dx_sorted), dx_sorted, ...
    1 + (numel(dx_sorted)-1)*sampling.prctiles/100);
end

sampling.dt_median = median(dt);
sampling.rate_measured = 1/sampling.dt_median;

sampling.speed_median = median(speed);
sampling.speed_min    = min(speed);
sampling.speed_max    = max(speed);

%% Compare against the radar header
% =========================================================================
% The PRF in the parameter spreadsheet does not account for hardware
% presumming. Each record cycles through every waveform, so the number of
% transmit events per record is the sum of the presums over the waveforms,
% and the record rate is the PRF divided by that sum.
if isfield(param,'radar') && isfield(param.radar,'prf') && ~isempty(param.radar.prf)
  sampling.prf = param.radar.prf;
end

presums = [];
if isfield(records,'settings') && isfield(records.settings,'wfs') ...
    && isfield(records.settings.wfs,'presums')
  for wf = 1:length(records.settings.wfs)
    if ~isempty(records.settings.wfs(wf).presums)
      presums(end+1) = records.settings.wfs(wf).presums; %#ok<AGROW>
    end
  end
end
sampling.presums = presums;
if ~isempty(presums)
  sampling.presums_total = sum(presums);
end

if isfinite(sampling.prf) && isfinite(sampling.presums_total) && sampling.presums_total > 0
  sampling.rate_header = sampling.prf / sampling.presums_total;
  sampling.rate_ratio = sampling.rate_measured / sampling.rate_header;
end

%% Nominal posted spacing of the derived products
% =========================================================================
% Read from the parameter spreadsheet, so no product files need to exist.
% qlook decimates the raw record spacing; the array stage posts on the SAR
% output grid instead, which is set in absolute meters by sar.sigma_x.
qlook_dec = 1;
qlook_presums = 1;
if isfield(param,'qlook')
  if isfield(param.qlook,'dec') && ~isempty(param.qlook.dec)
    qlook_dec = param.qlook.dec;
  end
  if isfield(param.qlook,'presums') && ~isempty(param.qlook.presums)
    qlook_presums = param.qlook.presums;
  end
end
sampling.qlook_dx_nominal = sampling.dx_median * qlook_dec * qlook_presums;

if isfield(param,'sar') && isfield(param.sar,'sigma_x') && ~isempty(param.sar.sigma_x)
  sampling.sar_sigma_x = param.sar.sigma_x;
end
if isfield(param,'array') && isfield(param.array,'dline') && ~isempty(param.array.dline)
  sampling.array_dline = param.array.dline;
end
if isfinite(sampling.sar_sigma_x)
  if isfinite(sampling.array_dline)
    sampling.standard_dx_nominal = sampling.sar_sigma_x * sampling.array_dline;
  else
    sampling.standard_dx_nominal = sampling.sar_sigma_x;
  end
end

%% Report
% =========================================================================
fprintf('%s\t%7d\t%8.3f\t%8.3f\t%8.3f\t%8.2f\t%8.2f\t%7.2f\t%8.3f\t%8.3f\n', ...
  param.day_seg, sampling.Nx, sampling.dx_median, sampling.dx_prctile(1), ...
  sampling.dx_prctile(end), sampling.rate_measured, sampling.rate_header, ...
  sampling.speed_median, sampling.qlook_dx_nominal, sampling.standard_dx_nominal);

if isfinite(sampling.rate_ratio) && abs(sampling.rate_ratio-1) > 0.05
  warning('%s: measured record rate %.2f Hz differs from the header rate %.2f Hz by %.1f%%.', ...
    param.day_seg, sampling.rate_measured, sampling.rate_header, 100*(sampling.rate_ratio-1));
end

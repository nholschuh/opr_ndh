function delay_doppler(param,param_override)
% delay_doppler(param,param_override)
%
% Produces a delay-Doppler product from the raw data for one segment.
%
% Every raw record within one synthetic aperture of an output position
% contributes to that position, and the full Doppler spectrum is kept
% rather than being collapsed to its centroid. Output positions are spaced
% at the posted along-track spacing of the array product, so the result
% tiles the same grid as CSARP_standard and can be compared against it
% trace for trace.
%
% This is NOT the upstream doppler.m stage. That one selects the peak in
% Doppler space and stores the single value, producing a 2D echogram. This
% one stores the whole Nt by Ndop by Nx cube.
%
% HOW THE DOPPLER AXIS IS DEFINED
% =========================================================================
% Within each aperture the traces are resampled onto a uniform along-track
% grid and transformed along that spatial axis, so the transform variable
% is spatial frequency in cycles/m rather than Doppler frequency in Hz.
% The two are related by fd = v*fx, but doing it in space means the angle
% axis does not move when the platform speed changes. That matters for
% ground-based data, where speed varies a lot, and it means frames from
% different days share one theta axis and can be stacked directly.
%
% A target at squint angle theta imposes a phase ramp of 4*pi*sin(theta)/lambda
% radians per meter of along-track motion, so
%
%   sin(theta) = fx*lambda/2
%
% with fx in cycles/m. Bins beyond |fx*lambda/2| = 1 are unmappable and
% their theta is returned as NaN. Reaching theta = +-90 deg requires a raw
% along-track spacing of lambda/4 or finer, which is what
% along_track_sampling.m reports; where the raw sampling is coarser than
% that the accessible angle span is correspondingly narrower.
%
% WHICH ANGLE THETA IS
% =========================================================================
% theta here is the ALONG-TRACK squint angle, measured from nadir in the
% vertical plane containing the flight line. Positive theta means the
% scatterer is ahead of the platform. This is not the same quantity as
% Tomo.theta in the MUSIC products, which is the CROSS-TRACK direction of
% arrival resolved by the physical antenna array. The two angles are
% orthogonal to each other. The struct is laid out to parallel Tomo so that
% code written against one reads naturally against the other, but do not
% assume a value from one is comparable to a value from the other.
%
% The sign follows from the standard echogram phase convention, where a
% target at range R carries phase exp(-1j*4*pi*R/lambda). A target ahead of
% the platform has a closing range, giving a positive along-track phase
% rate and therefore positive fx and positive theta.
%
% theta is the angle in air. Below the ice surface the ray refracts, so the
% in-ice angle is asin(sin(theta)/sqrt(er_ice)). Both axes are stored.
%
% INPUTS
% =========================================================================
% param: parameter spreadsheet struct for one segment
%  .delay_doppler: struct controlling this function
%   .imgs: cell vector of images, each an Nx2 array of wf-adc pairs.
%     Default is {[1 1]}. Receive channels are coherently combined before
%     the Doppler transform, so each image yields one output file.
%   .out_path: output directory name passed to opr_filename_out. Default
%     is 'delay_doppler', giving CSARP_delay_doppler.
%   .block_size: number of output positions to process at a time. Default
%     is 200. Lower it if the aperture is long and memory is tight.
%   .dx_out: output along-track spacing in meters. Default is
%     param.sar.sigma_x*param.array.dline, which is the posted spacing of
%     the array product.
%   .Lsar: aperture length in meters. Default is the same expression sar.m
%     uses, c/fc*(sar.Lsar.agl + sar.Lsar.thick/sqrt(er_ice))/(2*sar.sigma_x).
%   .dx_dop: uniform along-track sample spacing used inside the aperture,
%     in meters. Default is the median raw record spacing, so no along-track
%     bandwidth is discarded. Rounded so that dx_out is an integer multiple.
%   .Nfft: length of the along-track transform. Default is the next power
%     of two above the number of samples in the aperture, which zero-pads
%     and interpolates the angle axis without adding information.
%   .st_wind: slow-time window function handle applied across the aperture
%     before the transform. Default is @hanning. Use @boxcar for no taper.
%   .theta_rng: two-element vector in degrees limiting which Doppler bins
%     are stored. Default is [-90 90], which keeps every physically
%     mappable bin and discards the rest. Narrow it to cut file size.
%   .complex_en: logical. Default is false, which stores power. True stores
%     the complex voltage, which quadruples the file size.
%   .presums: software presums applied at load time. Default is 1, which is
%     the point of the product. Raising it throws away along-track
%     bandwidth and narrows the angle span.
%   .motion_comp: logical, passed through to data_merge_combine. Default is
%     true.
%   .bit_mask: records bit_mask bits to skip. Default is 1, which drops
%     records flagged bad but keeps stationary data.
%   .surf_layer: layer_params struct for the ice surface, as used by
%     opsLoadLayers. Default is the layerdata 'surface' layer.
%   .trim_nan: logical. Default is true, which drops output positions whose
%     aperture had no usable data.
%
% param_override: standard OPR override struct, merged with gRadar
%
% OUTPUTS
% =========================================================================
% One file per frame per image, written to CSARP_delay_doppler:
%   Data_YYYYMMDD_SS_FFF.mat            (single image)
%   Data_img_II_YYYYMMDD_SS_FFF.mat     (multiple images)
%
% Doppler: struct laid out to parallel the Tomo struct of the MUSIC products
%   .img: Nt by Ndop by Nx. Power, or complex voltage when complex_en.
%   .theta: Ndop by 1, along-track squint in degrees off nadir, in air,
%     positive forward. NaN where unmappable. See the note above on how
%     this differs from the cross-track Tomo.theta.
%     Note this differs from Tomo.theta, which is stored full size as
%     Nt by Nsv by Nx. Here the angle axis is identical for every range bin
%     and every trace, so storing it once saves a copy the size of the data
%     itself. Expand with repmat(reshape(Doppler.theta,1,[],1),[Nt 1 Nx])
%     if something downstream insists on the 3D form.
%   .theta_ice: Ndop by 1, the same directions refracted into ice.
%   .fx: Ndop by 1, along-track spatial frequency in cycles/m.
%   .Lsar, .dx_dop, .dx_out, .Nfft, .Nwin: geometry actually used.
%   .Nsamples: 1 by Nx, usable raw traces in each output aperture.
%
% Data: Nt by Nx, the maximum over the Doppler dimension, matching the
%   convention that array_proc uses for its beamformer output.
% Theta: Nt by Nx, the direction of arrival at that maximum, in degrees.
% Time, GPS_time, Latitude, Longitude, Elevation, Roll, Pitch, Heading,
%   Surface, Along_track: standard echogram fields on the output grid.
%
% Example:
%  param = read_param_xls(opr_filename_param('rds_param_2022_Antarctica_GroundGHOST.xlsx'),'20230107_01');
%  param.cmd.frms = 18;
%  delay_doppler(param);
%
% Author: Nick Holschuh
%
% See also: run_delay_doppler, along_track_sampling, array_proc, sar_task

%% Input checks
% =========================================================================
physical_constants; % c, er_ice

global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end
param = merge_structs(param,param_override);

if ~isfield(param,'delay_doppler') || isempty(param.delay_doppler)
  param.delay_doppler = [];
end
dd = param.delay_doppler;

if ~isfield(dd,'imgs') || isempty(dd.imgs)
  dd.imgs = {[1 1]};
end
if ~isfield(dd,'out_path') || isempty(dd.out_path)
  dd.out_path = 'delay_doppler';
end
if ~isfield(dd,'block_size') || isempty(dd.block_size)
  dd.block_size = 200;
end
if ~isfield(dd,'Nfft')
  dd.Nfft = [];
end
if ~isfield(dd,'st_wind') || isempty(dd.st_wind)
  dd.st_wind = @hanning;
end
if ~isfield(dd,'theta_rng') || isempty(dd.theta_rng)
  dd.theta_rng = [-90 90];
end
if ~isfield(dd,'complex_en') || isempty(dd.complex_en)
  dd.complex_en = false;
end
if ~isfield(dd,'presums') || isempty(dd.presums)
  dd.presums = 1;
end
if ~isfield(dd,'motion_comp') || isempty(dd.motion_comp)
  dd.motion_comp = true;
end
if ~isfield(dd,'bit_mask') || isempty(dd.bit_mask)
  dd.bit_mask = 1;
end
if ~isfield(dd,'trim_nan') || isempty(dd.trim_nan)
  dd.trim_nan = true;
end
if ~isfield(dd,'surf_layer') || isempty(dd.surf_layer)
  dd.surf_layer = struct('name','surface','source','layerdata','existence_check',false);
end

if ~isfield(param,'sar') || ~isfield(param.sar,'sigma_x') || isempty(param.sar.sigma_x)
  error('param.sar.sigma_x must be set. It defines the along-track grid this product is posted on.');
end
if ~isfield(param.sar,'Lsar') || isempty(param.sar.Lsar)
  param.sar.Lsar = [];
end
if ~isfield(param.sar.Lsar,'agl') || isempty(param.sar.Lsar.agl)
  param.sar.Lsar.agl = 500;
end
if ~isfield(param.sar.Lsar,'thick') || isempty(param.sar.Lsar.thick)
  param.sar.Lsar.thick = 1000;
end

array_dline = 1;
if isfield(param,'array') && isfield(param.array,'dline') && ~isempty(param.array.dline)
  array_dline = param.array.dline;
end
if ~isfield(dd,'dx_out') || isempty(dd.dx_out)
  dd.dx_out = param.sar.sigma_x * array_dline;
end

param.delay_doppler = dd;

fprintf('=====================================================================\n');
fprintf('%s: %s (%s)\n', mfilename, param.day_seg, datestr(now));
fprintf('=====================================================================\n');

%% Segment geometry
% =========================================================================
% The output grid is defined once for the whole segment, starting at zero
% along-track, so that frames abut seamlessly. This is the same convention
% sar_task.m uses for its output_along_track.
records_all = records_load(param,'lat','lon','elev','gps_time','roll','pitch','heading');
along_track_all = geodetic_to_along_track(records_all.lat,records_all.lon,records_all.elev);
along_track_all = along_track_all(:).';

out_x_all = 0 : dd.dx_out : along_track_all(end);

frames = frames_load(param);
param.cmd.frms = frames_param_cmd_frms(param,frames);

%% Surface layer
% =========================================================================
surf_layer = opsLoadLayers(param,dd.surf_layer);
if isempty(surf_layer.gps_time) || all(~isfinite(surf_layer.gps_time))
  surface_all = zeros(size(records_all.gps_time));
elseif length(surf_layer.gps_time) == 1
  surface_all = surf_layer.twtt*ones(size(records_all.gps_time));
else
  surface_all = interp_finite(interp1(surf_layer.gps_time,surf_layer.twtt,records_all.gps_time),0);
end

%% Waveform setup
% =========================================================================
% data_load_wfs needs the image list and a records struct. It is called
% once here so that the center frequency is available for the aperture and
% angle calculations before any data are loaded.
records_hdr = records_load(param,[1 min(2,length(records_all.gps_time))]);
records_hdr.surface = surface_all(1:length(records_hdr.gps_time));
param.load.imgs = dd.imgs;
[wfs,states] = data_load_wfs(param,records_hdr);
param.radar.wfs = merge_structs(param.radar.wfs,wfs);

fc = wfs(abs(dd.imgs{1}(1,1))).fc;
lambda = c/fc;

%% Aperture and Doppler grid
% =========================================================================
if ~isfield(dd,'Lsar') || isempty(dd.Lsar)
  % Same expression as sar.m line 275
  dd.Lsar = c/fc*(param.sar.Lsar.agl + param.sar.Lsar.thick/sqrt(er_ice))/(2*param.sar.sigma_x);
end

if ~isfield(dd,'dx_dop') || isempty(dd.dx_dop)
  dd.dx_dop = median(diff(along_track_all));
end
% Force dx_out to be an integer multiple of dx_dop so that every output
% position lands exactly on the uniform grid and no interpolation of the
% window centre is needed. Round the count up rather than to nearest, so
% the adjustment always makes dx_dop finer. Rounding it coarser would
% quietly discard along-track bandwidth and narrow the accessible angle
% span below what the raw sampling supports.
dop_per_out = max(1,ceil(dd.dx_out/dd.dx_dop));
dd.dx_dop = dd.dx_out/dop_per_out;

% Odd length so the aperture is symmetric about the output position
Nwin = 2*floor(dd.Lsar/(2*dd.dx_dop)) + 1;
if Nwin < 8
  error(['The aperture holds only %d samples at dx_dop=%.4f m. Either the ' ...
    'aperture is too short or the raw sampling is too coarse for a useful ' ...
    'Doppler spectrum.'], Nwin, dd.dx_dop);
end

if isempty(dd.Nfft)
  dd.Nfft = 2^nextpow2(Nwin);
end
Nfft = dd.Nfft;

% Spatial frequency axis in cycles/m, ordered to match fftshift of the
% transform output: negative frequencies first, DC at floor(Nfft/2)+1
fx = (-floor(Nfft/2) : floor((Nfft-1)/2)) / (Nfft*dd.dx_dop);

sin_theta = fx*lambda/2;
theta = nan(size(sin_theta));
mappable = abs(sin_theta) <= 1;
theta(mappable) = asind(sin_theta(mappable));
theta_ice = nan(size(sin_theta));
theta_ice(mappable) = asind(sin_theta(mappable)/sqrt(er_ice));

% Keep only the requested angle range, which also throws out the
% unmappable bins because their theta is NaN
dop_keep = find(theta >= dd.theta_rng(1) & theta <= dd.theta_rng(2));
if isempty(dop_keep)
  error('theta_rng [%g %g] keeps no Doppler bins. The mappable range here is [%g %g] deg.', ...
    dd.theta_rng(1), dd.theta_rng(2), min(theta), max(theta));
end
Ndop = length(dop_keep);

st_win = window_from_handle(dd.st_wind,Nwin);

fprintf('  fc %.1f MHz, lambda %.4f m\n', fc/1e6, lambda);
fprintf('  Lsar %.1f m, dx_out %.3f m, dx_dop %.4f m\n', dd.Lsar, dd.dx_out, dd.dx_dop);
fprintf('  aperture %d samples, Nfft %d, keeping %d Doppler bins\n', Nwin, Nfft, Ndop);
fprintf('  theta span kept %.2f to %.2f deg (mappable limit %.2f deg)\n', ...
  min(theta(dop_keep)), max(theta(dop_keep)), max(theta(mappable)));

param.delay_doppler = dd;

%% Frame loop
% =========================================================================
for frm_idx = 1:length(param.cmd.frms)
  frm = param.cmd.frms(frm_idx);

  recs_frm(1) = frames.frame_idxs(frm);
  if frm == length(frames.frame_idxs)
    recs_frm(2) = length(along_track_all);
  else
    recs_frm(2) = frames.frame_idxs(frm+1) - 1;
  end

  % Output positions belonging to this frame. The upper bound is exclusive
  % so that neighbouring frames do not both claim the same position, except
  % at the end of the segment where there is no next frame to take it.
  if frm == length(frames.frame_idxs)
    out_idxs = find(out_x_all >= along_track_all(recs_frm(1)) ...
      & out_x_all <= along_track_all(recs_frm(2)));
  else
    out_idxs = find(out_x_all >= along_track_all(recs_frm(1)) ...
      & out_x_all < along_track_all(recs_frm(2)+1));
  end
  if isempty(out_idxs)
    warning('%s frm %d: no output positions fall in this frame, skipping.', param.day_seg, frm);
    continue;
  end
  out_x = out_x_all(out_idxs);
  Nx = length(out_x);

  fprintf('\n  Frame %03d: records %d to %d, %d output positions\n', ...
    frm, recs_frm(1), recs_frm(2), Nx);

  % Preallocated per image once the number of range bins is known
  Doppler_img = cell(1,length(dd.imgs));
  Time_img = cell(1,length(dd.imgs));
  Nsamples = zeros(1,Nx);

  %% Block loop
  blocks = 1:dd.block_size:Nx;
  for blk_idx = 1:length(blocks)
    blk = blocks(blk_idx);
    blk_out = blk : min(Nx, blk+dd.block_size-1);

    % Raw records needed: the block extent grown by half an aperture at
    % each end so that every output position has full support
    x_need = [out_x(blk_out(1))-dd.Lsar/2, out_x(blk_out(end))+dd.Lsar/2];
    rec_start = find(along_track_all >= x_need(1),1,'first');
    rec_stop  = find(along_track_all <= x_need(2),1,'last');
    if isempty(rec_start), rec_start = 1; end
    if isempty(rec_stop), rec_stop = length(along_track_all); end

    fprintf('    Block %d of %d: output %d-%d, records %d-%d\n', ...
      blk_idx, length(blocks), blk_out(1), blk_out(end), rec_start, rec_stop);

    %% Load, pulse compress, combine channels
    param.load.recs = [rec_start rec_stop];
    param.load.frm = frm;
    param.load.imgs = dd.imgs;
    param.load.raw_data = false;
    param.load.presums = dd.presums;
    param.load.bit_mask = dd.bit_mask;

    records = records_load(param,param.load.recs);
    records.surface = surface_all(rec_start:rec_stop);

    [hdr,data] = data_load(param,records,states);

    param.load.pulse_comp = true;
    [hdr,data,param] = data_pulse_compress(param,hdr,data);

    param.load.motion_comp = dd.motion_comp;
    param.load.combine_rx = true;
    [hdr,data] = data_merge_combine(param,hdr,data);

    % Along-track position of every loaded trace, on the segment-wide
    % origin so that it lines up with out_x
    x_load = interp1(records_all.gps_time,along_track_all,hdr.gps_time);

    %% Transform each image
    for img = 1:length(dd.imgs)
      Nt = size(data{img},1);
      if isempty(Doppler_img{img})
        if dd.complex_en
          Doppler_img{img} = complex(nan(Nt,Ndop,Nx,'single'));
        else
          Doppler_img{img} = nan(Nt,Ndop,Nx,'single');
        end
        Time_img{img} = hdr.time{img};
      elseif size(Doppler_img{img},1) ~= Nt
        % Every block in a frame has to land on the same fast-time axis or
        % the cube cannot be assembled. Differing Nt means the pulse
        % compression settings changed mid-frame, which is a parameter
        % spreadsheet problem rather than something to paper over here.
        error(['Frame %d image %d: block %d returned %d range bins but the ' ...
          'frame was started with %d. Check for a mid-frame change in the ' ...
          'waveform or Nyquist zone settings.'], frm, img, blk_idx, Nt, ...
          size(Doppler_img{img},1));
      end

      % Uniform along-track grid spanning this block's loaded extent. Every
      % output position in the block sits exactly on one of these samples.
      unif_x = out_x(blk_out(1)) - dd.Lsar/2 : dd.dx_dop : out_x(blk_out(end)) + dd.Lsar/2;
      good = isfinite(x_load);
      if sum(good) < 2
        warning('Block %d has no usable trajectory, skipping.', blk_idx);
        continue;
      end
      data_unif = arbitrary_resample(data{img}(:,good), x_load(good), unif_x, ...
        struct('filt_len',dd.dx_dop*16,'dx',dd.dx_dop,'method','sinc'));

      for out_idx = 1:length(blk_out)
        % Centre sample of this output position on the uniform grid
        [~,ctr] = min(abs(unif_x - out_x(blk_out(out_idx))));
        win_idxs = ctr - (Nwin-1)/2 : ctr + (Nwin-1)/2;
        if win_idxs(1) < 1 || win_idxs(end) > size(data_unif,2)
          continue;
        end

        aperture = data_unif(:,win_idxs);
        valid = any(isfinite(aperture) & aperture ~= 0, 1);
        Nsamples(blk_out(out_idx)) = sum(valid);
        if ~any(valid)
          continue;
        end
        aperture(~isfinite(aperture)) = 0;

        % Taper across the aperture, then transform along track
        spectrum = fftshift(fft(bsxfun(@times,aperture,st_win(:).'),Nfft,2),2);
        spectrum = spectrum(:,dop_keep);

        if dd.complex_en
          Doppler_img{img}(:,:,blk_out(out_idx)) = single(spectrum);
        else
          Doppler_img{img}(:,:,blk_out(out_idx)) = single(abs(spectrum).^2);
        end
      end
    end
  end

  %% Output trajectory on the posted grid
  % =======================================================================
  GPS_time  = interp1(along_track_all,records_all.gps_time,out_x);
  Latitude  = interp1(along_track_all,records_all.lat,out_x);
  Longitude = interp1(along_track_all,records_all.lon,out_x);
  Elevation = interp1(along_track_all,records_all.elev,out_x);
  Roll      = interp1(along_track_all,records_all.roll,out_x);
  Pitch     = interp1(along_track_all,records_all.pitch,out_x);
  Heading   = interp1(along_track_all,records_all.heading,out_x);
  Surface   = interp1(along_track_all,surface_all,out_x);
  Along_track = out_x;

  keep = true(1,Nx);
  if dd.trim_nan
    keep = Nsamples > 0;
    if ~any(keep)
      warning('%s frm %d: every output position was empty, nothing written.', param.day_seg, frm);
      continue;
    end
  end

  % Trim once, here, so that a second image does not re-trim an already
  % trimmed vector
  GPS_time    = GPS_time(keep);
  Latitude    = Latitude(keep);
  Longitude   = Longitude(keep);
  Elevation   = Elevation(keep);
  Roll        = Roll(keep);
  Pitch       = Pitch(keep);
  Heading     = Heading(keep);
  Surface     = Surface(keep);
  Along_track = Along_track(keep);

  %% Save one file per image
  % =======================================================================
  out_fn_dir = opr_filename_out(param,dd.out_path,'');
  if ~exist(out_fn_dir,'dir')
    mkdir(out_fn_dir);
  end

  for img = 1:length(dd.imgs)
    if isempty(Doppler_img{img})
      warning('%s frm %d img %d: no data, nothing written.', param.day_seg, frm, img);
      continue;
    end

    Doppler = [];
    Doppler.img       = Doppler_img{img}(:,:,keep);
    Doppler.theta     = theta(dop_keep).';
    Doppler.theta_ice = theta_ice(dop_keep).';
    Doppler.fx        = fx(dop_keep).';
    Doppler.Lsar      = dd.Lsar;
    Doppler.dx_dop    = dd.dx_dop;
    Doppler.dx_out    = dd.dx_out;
    Doppler.Nfft      = Nfft;
    Doppler.Nwin      = Nwin;
    Doppler.Nsamples  = Nsamples(keep);

    % Match the array_proc beamformer convention: the 2D image is the peak
    % over the angle dimension and Theta is where that peak sits
    if dd.complex_en
      [pk,pk_idx] = max(abs(Doppler.img).^2,[],2);
    else
      [pk,pk_idx] = max(Doppler.img,[],2);
    end
    Data = reshape(pk,size(Doppler.img,1),size(Doppler.img,3));
    Theta = reshape(Doppler.theta(pk_idx),size(Doppler.img,1),size(Doppler.img,3));

    Time = Time_img{img};

    if length(dd.imgs) == 1
      out_fn_name = sprintf('Data_%s_%03d.mat', param.day_seg, frm);
    else
      out_fn_name = sprintf('Data_img_%02d_%s_%03d.mat', img, param.day_seg, frm);
    end
    out_fn = fullfile(out_fn_dir,out_fn_name);

    param_delay_doppler = param;
    param_records = records_all_param(param);
    file_type = 'delay_doppler';
    file_version = '1';

    fprintf('  Save %s\n', out_fn);
    opr_save(out_fn,'Doppler','Data','Theta','Time','GPS_time', ...
      'Latitude','Longitude','Elevation','Roll','Pitch','Heading','Surface', ...
      'Along_track','param_delay_doppler','param_records','file_type','file_version');
  end
end

fprintf('\n%s done %s\n', mfilename, datestr(now));

end

function w = window_from_handle(fh,N)
% Window handles in the parameter spreadsheets are called with a single
% length argument, but boxcar and friends live in different toolboxes, so
% fall back to a rectangular window if the handle cannot be evaluated.
try
  w = fh(N);
catch
  warning('Could not evaluate the slow-time window handle, using a boxcar.');
  w = ones(N,1);
end
end

function param_records = records_all_param(param)
% The records file carries the parameters it was created with. Pull just
% that field so the output file records its provenance without dragging in
% the whole trajectory a second time.
records_fn = opr_filename_support(param,'','records');
tmp = load(records_fn,'param_records');
if isfield(tmp,'param_records')
  param_records = tmp.param_records;
else
  param_records = [];
end
end

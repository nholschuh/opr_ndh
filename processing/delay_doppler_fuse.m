function mdata = delay_doppler_fuse(param)
% mdata = delay_doppler_fuse(param)
%
% Vertically fuses the per-image delay-Doppler files of one frame
% (Data_img_II_YYYYMMDD_SS_FFF.mat, one per waveform image) into a single
% cube, the delay-Doppler counterpart of tomo.fuse_images. The blend is
% the same one tomo.fuse_images applies to Tomo.img: image N-1 is used down
% to max(Surface + img_comb(1), img_comb(2)), with img_comb(3) of guard
% time held back at its end, then a 10-bin raised-cosine transition to
% image N. The same img_comb therefore puts the seam in the same place in
% the delay-Doppler product as in the three 3D products.
%
% Each image is first resampled onto dd_collate.Nsv look directions
% (dd_resample_angle), the grid the 3D array products use, so the fuse and
% everything after it work on Nsv angle bins rather than the native
% Doppler bins.
%
% Data and Theta are recomputed from the fused, resampled cube (peak over
% angle and the angle at that peak), as delay_doppler does, rather than
% fused separately.
%
% With a single image there is nothing to fuse: the one file is loaded,
% resampled, and returned, and nothing is written (the input file would be
% the output file).
%
% param: parameter spreadsheet struct for the segment, merged with gRadar
%  .load.frm: frame to fuse
%  .dd_collate: settings, filled in by delay_doppler_collate
%   .in_path: delay-Doppler product directory (opr_filename_out)
%   .imgs: image numbers in top-to-bottom order, or 0 for a single
%     Data_YYYYMMDD_SS_FFF.mat file
%   .img_comb: [time after surface, minimum time, guard] per seam, as
%     array.img_comb
%   .img_comb_trim: [top trim, bottom trim, absolute top, absolute bottom]
%     (s). Empty uses tomo.fuse_images' default: half the first image's
%     pulse off the top and half the last image's pulse off the bottom
%   .Nsv: look directions to resample to; empty or 0 keeps the native
%     Doppler bins
%   .save_fused: write the fused cube to Data_YYYYMMDD_SS_FFF.mat in
%     in_path, beside the image files, as tomo.fuse_images does
%
% mdata: the fused file contents (Doppler, Data, Theta, Time, GPS_time,
%   Latitude, Longitude, Elevation, Roll, Pitch, Heading, Surface,
%   Along_track, param_delay_doppler, param_records)
%
% Author: Nick Holschuh
%
% See also: delay_doppler_collate_task, delay_doppler_collate, tomo.fuse_images

dc = param.dd_collate;
in_dir = opr_filename_out(param,dc.in_path,'');
imgs = dc.imgs;

Nsv = [];
if isfield(dc,'Nsv')
  Nsv = dc.Nsv;
end

if isequal(imgs,0)
  fns = {fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,param.load.frm))};
else
  fns = cell(1,numel(imgs));
  for v_img = 1:numel(imgs)
    fns{v_img} = fullfile(in_dir,sprintf('Data_img_%02d_%s_%03d.mat',imgs(v_img),param.day_seg,param.load.frm));
  end
end

if numel(fns) == 1
  fprintf('  Loading %s (%s)\n', fns{1}, datestr(now));
  mdata = load(fns{1});
  if ~isempty(Nsv) && Nsv > 0
    mdata.Doppler = dd_resample_angle(mdata.Doppler,Nsv);
    [mdata.Data,mdata.Theta] = peak_over_angle(mdata.Doppler);
  end
  return;
end

%% Trim defaults (tomo.fuse_images)
% =========================================================================
img_comb_trim = [];
if isfield(dc,'img_comb_trim')
  img_comb_trim = dc.img_comb_trim;
end
if isempty(img_comb_trim)
  [~,radar_type] = opr_output_dir(param.radar_name);
  if strcmpi(radar_type,'deramp')
    img_comb_trim = [0 0 0 inf];
  else
    first = load(fns{1},'param_delay_doppler');
    dd_imgs = first.param_delay_doppler.delay_doppler.imgs;
    wf_first = abs(dd_imgs{imgs(1)}(1,1));
    wf_last = abs(dd_imgs{imgs(end)}(1,1));
    img_comb_trim = [param.radar.wfs(wf_first).Tpd/2 -param.radar.wfs(wf_last).Tpd/2 0 inf];
  end
end
if numel(dc.img_comb) < 3*(numel(imgs)-1)
  error('%s_%03d: img_comb has %d values but %d images need %d.', param.day_seg, ...
    param.load.frm, numel(dc.img_comb), numel(imgs), 3*(numel(imgs)-1));
end

%% Vertical fuse
% =========================================================================
for v_img = 1:numel(imgs)
  fprintf('  Loading %s (%s)\n', fns{v_img}, datestr(now));
  if v_img == 1
    mdata = load(fns{1});
    mdata.Doppler = dd_resample_angle(mdata.Doppler,Nsv);
    Time = mdata.Time(:);
    Img = mdata.Doppler.img;
    dt = Time(2)-Time(1);
    Nx = size(Img,3);
    Ndop = size(Img,2);

    first_idx = find(Time >= Time(1)+img_comb_trim(1) & Time >= img_comb_trim(3),1,'first');
    if isempty(first_idx)
      error('Zero range bin length images not supported.');
    end
    Time = Time(first_idx:end);
    Img = Img(first_idx:end,:,:);
    continue;
  end

  new = load(fns{v_img},'Doppler','Time','Surface');
  new.Doppler = dd_resample_angle(new.Doppler,Nsv);
  new_time = new.Time(:);
  new_img = new.Doppler.img;
  new.Doppler.img = [];
  if size(new_img,2) ~= Ndop || size(new_img,3) ~= Nx
    error('%s: Doppler cube is %s but image %d is %s. The images must share traces and Doppler bins.', ...
      fns{v_img}, mat2str(size(new_img)), imgs(1), mat2str(size(Img)));
  end

  if v_img == numel(imgs)
    last_idx = find(new_time <= new_time(end)+img_comb_trim(2) & new_time <= img_comb_trim(4),1,'last');
    if isempty(last_idx)
      error('Zero range bin length images not supported.');
    end
    new_time = new_time(1:last_idx);
    new_img = new_img(1:last_idx,:,:);
  end

  % Image N lands on image N-1's time grid, extended to image N's end
  New_Time = (Time(1) : dt : new_time(end)).';

  % Start of the blend, per trace (fuse_images.m, "Surface tracking image combine")
  seam = (v_img-2)*3;
  Surface = interp_finite(new.Surface,0);
  img_bins = round(interp1(New_Time,1:length(New_Time), ...
    max(Surface+dc.img_comb(seam+1),dc.img_comb(seam+2)),'linear','extrap'));
  guard_bins = 1 + round(dc.img_comb(seam+3)/dt);
  max_good_time = length(Time)*ones(1,Nx);
  invalid_rlines = find(isnan(img_bins) | img_bins > max_good_time-guard_bins);
  img_bins(invalid_rlines) = max_good_time(invalid_rlines)-guard_bins;
  img_bins(2,:) = img_bins(1,:) + 10;
  img_bins(2,img_bins(2,:)>length(Time)) = length(Time);

  % One trace at a time, so image N is never held on the new grid in full
  New_Img = zeros(length(New_Time),Ndop,Nx,'single');
  for rline = 1:Nx
    new_rline = interp1(new_time,double(new_img(:,:,rline)),New_Time,'linear',0);
    trans_bins = img_bins(1,rline)+1:img_bins(2,rline);
    weights = 0.5+0.5*cos(pi*linspace(0,1,length(trans_bins)).');
    if ~isempty(trans_bins) && trans_bins(end) <= size(New_Img,1)
      New_Img(:,:,rline) = [Img(1:img_bins(1,rline),:,rline); ...
        bsxfun(@times,weights,Img(trans_bins,:,rline)) ...
        + bsxfun(@times,1-weights,new_rline(trans_bins,:)); ...
        new_rline(img_bins(2,rline)+1:end,:)];
    else
      New_Img(1:size(Img,1),:,rline) = Img(:,:,rline);
    end
  end
  clear new_img;
  Time = New_Time;
  Img = New_Img;
  clear New_Img;
end

%% Fused product
% =========================================================================
mdata.Time = Time;
mdata.Doppler.img = Img;
clear Img;
[mdata.Data,mdata.Theta] = peak_over_angle(mdata.Doppler);
mdata.Doppler.fused_imgs = imgs;
mdata.Doppler.img_comb = dc.img_comb;
mdata.Doppler.img_comb_trim = img_comb_trim;

if dc.save_fused
  out_fn = fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,param.load.frm));
  if isfield(param,'opr_file_lock') && ~isempty(param.opr_file_lock) && param.opr_file_lock
    mdata.file_version = '1L';
  else
    mdata.file_version = '1';
  end
  fprintf('  Saving %s (%s)\n', out_fn, datestr(now));
  opr_save(out_fn,'-struct','mdata');
  info = dir(out_fn);
  fprintf('  Fused cube %s: %.2f GB on disk\n', mat2str(size(mdata.Doppler.img)), info.bytes/1e9);
end

end

function [Data,Theta] = peak_over_angle(Doppler)
% 2D echogram and the angle of its peak, as delay_doppler forms them
if isreal(Doppler.img)
  [pk,pk_idx] = max(Doppler.img,[],2);
else
  % complex_en: blended as voltage, peak taken on power as delay_doppler does
  [pk,pk_idx] = max(abs(Doppler.img).^2,[],2);
end
Data = reshape(pk,size(Doppler.img,1),size(Doppler.img,3));
Theta = reshape(Doppler.theta(pk_idx),size(Doppler.img,1),size(Doppler.img,3));
end

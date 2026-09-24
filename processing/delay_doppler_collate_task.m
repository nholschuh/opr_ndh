function success = delay_doppler_collate_task(param)
% success = delay_doppler_collate_task(param)
%
% Cluster task for delay_doppler_collate: one frame of the delay-Doppler
% product, from the per-image files to tracked ice-surface and ice-bed
% returns in every Doppler bin.
%
%  1. Fuse the waveform images vertically (delay_doppler_fuse).
%  2. Build the along-track surface and bed profiles, in the vertical plane
%     of the flight line, from the 2D surface and bottom picks of this
%     frame and its neighbours.
%  3. Ray-cast every Doppler look direction against those profiles
%     (dd_ray_twtt) to predict when the surface and bed arrive in each bin.
%  4. Track the surface, then the bed, in the Doppler cube, inside a window
%     around each prediction, with the nadir bin held tighter to the 2D
%     pick. TRW-S (tomo.trws2) runs across trace and Doppler bin the way
%     tomo.track_surface runs it across trace and DOA bin.
%  5. Save the predictions, the tracked travel times, the power at each,
%     and where each ray met the surface and bed.
%
% The Doppler axis is the along-track squint, orthogonal to the
% cross-track DOA axis of the 3D products, so none of tomo.collate's DEM
% geometry is used; see dd_ray_twtt for what replaces it.
%
% Must be compiled into the cluster job binary. delay_doppler_collate lists
% it in hidden_depend_funs and the run script forces a compile before any
% batch is built.
%
% param: parameter spreadsheet struct, merged with gRadar, with
%   .load.frm and .dd_collate filled in by delay_doppler_collate
%
% OUTPUT FILE: CSARP_<dd_collate.surf_out_path>/Data_YYYYMMDD_SS_FFF.mat
%  GPS_time, Latitude, Longitude, Elevation, Along_track: 1 by Nx, from the
%    delay-Doppler file
%  Surface, Bottom: 1 by Nx, the 2D picks at each trace (twtt, s)
%  Time: Nt by 1 fast time of the fused cube (s)
%  theta, theta_ice: Ndop by 1 Doppler squint in air and in ice (deg)
%  climb: 1 by Nx platform climb angle over the aperture (deg)
%  phi: Ndop by Nx geometric look angle from vertical, theta + climb (deg)
%  nadir_col: 1 by Nx Doppler bin closest to vertical
%  top, bottom: structs of Ndop by Nx matrices
%   .pred_twtt: ray-cast travel time from the 2D picks (s)
%   .twtt: tracked travel time (s), NaN where not tracked
%   .pred_power, .power: linear power in the fused cube at those times
%   .x, .z: along-track position and elevation where the ray meets the
%     interface (m); the same bed point is seen from many traces, at
%     different angles, which is what makes angular scattering measurable
%   .incidence: angle from the local interface normal (deg)
%   .theta_ice (bottom only): refracted ray angle from vertical (deg)
%  param_dd_collate, file_type, file_version
%
% Author: Nick Holschuh
%
% See also: delay_doppler_collate, delay_doppler_fuse, dd_ray_twtt,
%   tomo.track_surface, tomo_collate_task

physical_constants; % c
dc = param.dd_collate;
frm = param.load.frm;
n_ice = sqrt(dc.er_ice);

%% Fused delay-Doppler cube
% =========================================================================
mdata = delay_doppler_fuse(param);
img = mdata.Doppler.img;
mdata.Doppler.img = [];
if ~isreal(img)
  img = abs(img).^2;
end
Time = mdata.Time(:);
theta = mdata.Doppler.theta(:);
Ndop = numel(theta);
Nx = numel(mdata.GPS_time);
x0 = mdata.Along_track(:).';

%% Along-track axis of the delay-Doppler grid
% =========================================================================
% Layer points need positions on the same along-track origin as the
% Doppler traces. In 'sar_coord' mode that is SAR output line k at
% (k-1)*sigma_x, which is how delay_doppler posts every trace.
ddp = mdata.param_delay_doppler.delay_doppler;
if strcmpi(ddp.grid,'sar_coord')
  sar_coord_fn = fullfile(opr_filename_out(param,ddp.sar_coord_path,''),'sar_coord.mat');
  sar_coord = load(sar_coord_fn,'gps_time','sigma_x');
  ref_gps = sar_coord.gps_time(1,:);
  ref_x = (0:numel(ref_gps)-1)*sar_coord.sigma_x;
else
  records = records_load(param,'lat','lon','elev','gps_time');
  ref_gps = records.gps_time;
  ref_x = geodetic_to_along_track(records.lat,records.lon,records.elev);
end
x_check = interp1(ref_gps,ref_x,mdata.GPS_time);
fprintf('  Along-track axis reproduces the Doppler traces to %.3g m\n', max(abs(x_check(:).'-x0)));

%% Along-track surface and bed profiles from the 2D picks
% =========================================================================
% Neighbouring frames too, so rays near either end of the frame have a
% surface to land on
frames = frames_load(param);
lparam = param;
lparam.cmd.frms = max(1,frm-1) : min(length(frames.frame_idxs),frm+1);
layers = opsLoadLayers(lparam,dc.layer_params);
lay_s = layers(1);
lay_b = layers(2);

% Platform elevation and climb, on the same trajectory the picks use, so
% the nadir prediction reproduces the 2D surface pick exactly
xs_all = interp1(ref_gps,ref_x,lay_s.gps_time);
ok = isfinite(xs_all) & isfinite(lay_s.elev);
[x_traj,uidx] = unique(xs_all(ok));
elev_traj = lay_s.elev(ok);
elev_traj = elev_traj(uidx);
z0 = interp1(x_traj,elev_traj,x0);
Lsar = mdata.Doppler.Lsar;
dE = interp1(x_traj,elev_traj,x0+Lsar/2) - interp1(x_traj,elev_traj,x0-Lsar/2);
climb = asin(max(-1,min(1,dE/Lsar)));
climb(~isfinite(climb)) = 0;

% Surface elevation at every picked point, bridged linearly across gaps
ok = ok & isfinite(lay_s.twtt);
[xs_pts,uidx] = unique(xs_all(ok));
zs_pts = lay_s.elev(ok) - lay_s.twtt(ok)*c/2;
zs_pts = zs_pts(uidx);
if numel(xs_pts) < 2
  error('%s_%03d: fewer than two surface picks with positions. Check the surface layer.', param.day_seg, frm);
end

xb_all = interp1(ref_gps,ref_x,lay_b.gps_time);
surf_at_b = interp1(lay_s.gps_time(isfinite(lay_s.twtt)),lay_s.twtt(isfinite(lay_s.twtt)),lay_b.gps_time);
okb = isfinite(xb_all) & isfinite(lay_b.twtt) & isfinite(surf_at_b) & isfinite(lay_b.elev);
[xb_pts,uidx] = unique(xb_all(okb));
zb_pts = lay_b.elev(okb) - surf_at_b(okb)*c/2 - (lay_b.twtt(okb)-surf_at_b(okb))*c/(2*n_ice);
zb_pts = zb_pts(uidx);

profile_dx = dc.profile_dx;
if isempty(profile_dx)
  profile_dx = mdata.Doppler.dx_out;
end
xg = xs_pts(1) : profile_dx : xs_pts(end);
zs_g = interp1(xs_pts,zs_pts,xg);
if numel(xb_pts) >= 2
  xb_g = xb_pts(1) : profile_dx : xb_pts(end);
  zb_g = interp1(xb_pts,zb_pts,xb_g);
else
  warning('%s_%03d: no usable bottom picks, so the bed is not predicted or tracked.', param.day_seg, frm);
  xb_g = [];
  zb_g = [];
end

% 2D picks at the Doppler traces, for the output file
Surface = interp1(lay_s.gps_time(isfinite(lay_s.twtt)),lay_s.twtt(isfinite(lay_s.twtt)),mdata.GPS_time);
okt = isfinite(lay_b.twtt);
if sum(okt) >= 2
  Bottom = interp1(lay_b.gps_time(okt),lay_b.twtt(okt),mdata.GPS_time);
else
  Bottom = nan(size(mdata.GPS_time));
end

%% Ray-cast every Doppler look direction
% =========================================================================
phi = bsxfun(@plus,theta*pi/180,climb);
slope_len = dc.slope_len;
if isempty(slope_len)
  slope_len = Lsar;
end
r_max = c/2*Time(end);
fprintf('  Ray casting %d Doppler bins x %d traces (%s)\n', Ndop, Nx, datestr(now));
geom = dd_ray_twtt(x0,z0,phi,xg,zs_g,xb_g,zb_g,dc.er_ice,slope_len,r_max);
[~,nadir_col] = min(abs(phi),[],1);

%% Track the surface, then the bed below it
% =========================================================================
top = [];
top.pred_twtt = geom.surf_twtt;
[top.twtt,top.power,top.pred_power] = track_dd(img,Time,geom.surf_twtt,nadir_col,dc.top,[]);
top.x = geom.surf_x;
top.z = geom.surf_z;
top.incidence = geom.surf_incidence*180/pi;

above = top.twtt;
above(isnan(above)) = top.pred_twtt(isnan(above));
bottom = [];
bottom.pred_twtt = geom.bottom_twtt;
[bottom.twtt,bottom.power,bottom.pred_power] = track_dd(img,Time,geom.bottom_twtt,nadir_col,dc.bottom,above);
bottom.x = geom.bottom_x;
bottom.z = geom.bottom_z;
bottom.theta_ice = geom.bottom_theta_ice*180/pi;
bottom.incidence = geom.bottom_incidence*180/pi;

%% Save
% =========================================================================
GPS_time = mdata.GPS_time;
Latitude = mdata.Latitude;
Longitude = mdata.Longitude;
Elevation = mdata.Elevation;
Along_track = mdata.Along_track;
theta_ice = mdata.Doppler.theta_ice(:);
climb = climb*180/pi;
phi = phi*180/pi;
param_dd_collate = param;
file_type = 'dd_surf';
if isfield(param,'opr_file_lock') && ~isempty(param.opr_file_lock) && param.opr_file_lock
  file_version = '1L';
else
  file_version = '1';
end
out_dir = opr_filename_out(param,dc.surf_out_path,'');
if ~exist(out_dir,'dir')
  mkdir(out_dir);
end
out_fn = fullfile(out_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm));
fprintf('  Saving %s (%s)\n', out_fn, datestr(now));
opr_save(out_fn,'GPS_time','Latitude','Longitude','Elevation','Along_track', ...
  'Surface','Bottom','Time','theta','theta_ice','climb','phi','nadir_col', ...
  'top','bottom','param_dd_collate','file_type','file_version');

success = true;

end

function [twtt,power,pred_power] = track_dd(img,Time,pred_twtt,nadir_col,trk,above_twtt)
% Tracks one interface through the Doppler cube, within trk.window (s) of
% pred_twtt in every bin and trk.nadir_window (s) in the nadir bin, and
% below above_twtt when given.
%   trk.method: 'trws' (tomo.trws2), 'max' (peak in each window), or
%     'none' (prediction only)

[Nt,Ndop,Nx] = size(img);
dt = Time(2)-Time(1);
twtt = nan(Ndop,Nx);
power = nan(Ndop,Nx);

pred_bin = interp1(Time,1:Nt,pred_twtt);
pred_power = sample_cube(img,round(pred_bin));
if strcmpi(trk.method,'none') || all(isnan(pred_bin(:)))
  return;
end

% Search window per Doppler bin and trace
half = ceil(trk.window/dt)*ones(Ndop,Nx);
half(sub2ind([Ndop Nx],nadir_col,1:Nx)) = ceil(trk.nadir_window/dt);
lo = ceil(pred_bin - half);
hi = floor(pred_bin + half);
if ~isempty(above_twtt)
  lo = max(lo,floor(interp1(Time,1:Nt,above_twtt,'linear',0))+1);
end
lo = max(lo,1);
hi = min(hi,Nt);
bad = ~isfinite(pred_bin) | hi < lo;
if all(bad(:))
  return;
end

% Crop fast time to the union of the windows
r1 = min(lo(~bad));
r2 = max(hi(~bad));
data = single(10*log10(img(r1:r2,:,:)));
bins = (r1:r2).';
in_win = bsxfun(@ge,bins,reshape(lo,[1 Ndop Nx])) & bsxfun(@le,bins,reshape(hi,[1 Ndop Nx]));
in_win(:,bad) = false;
data(~in_win) = -inf;
clear in_win;

switch lower(trk.method)
  case 'max'
    [~,idx] = max(data,[],1);
    result = reshape(idx,[Ndop Nx]) + r1 - 1;

  case 'trws'
    % Expected change in range bin from one trace to the next (along
    % track, taken at nadir) and from one Doppler bin to the next (across
    % the angle axis), both from the prediction. These play the parts of
    % at_slope and ct_slope in tomo.track_surface.
    nad_bin = pred_bin(sub2ind([Ndop Nx],nadir_col,1:Nx));
    at_slope = single(interp_finite([diff(nad_bin) 0],0));
    ct_slope = [diff(pred_bin,1,1); nan(1,Nx)];
    ct_slope = single(interp_finite(ct_slope,0));
    ct_weight = 1./(3+mean(abs(ct_slope),2));
    ct_weight = single(trk.ct_weight*ct_weight./max(ct_weight));

    lo_c = lo - r1 + 1;
    hi_c = hi - r1 + 1;
    lo_c(bad) = inf;
    hi_c(bad) = -inf;
    bounds = [min(lo_c,[],1); max(hi_c,[],1)];
    empty_rline = ~isfinite(bounds(1,:));
    bounds(1,empty_rline) = 1;
    bounds(2,empty_rline) = size(data,1);
    bounds = uint32(bounds);

    % As tomo.track_surface: columns with nothing in bounds get a constant
    % value, everything else outside the windows a value far below the data
    bad_column = reshape(all(~isfinite(data),1),[Ndop Nx]);
    finite_vals = data(isfinite(data));
    data_min = min(finite_vals);
    data_mean = mean(finite_vals);
    data_max = max(finite_vals);
    clear finite_vals;
    data(:,bad_column) = data_mean;
    data(~isfinite(data)) = data_min - (data_max-data_min)*20;

    result = tomo.trws2(data,at_slope,single(trk.at_weight),ct_slope,ct_weight, ...
      uint32(trk.max_loops),bounds-1);
    result = double(reshape(result,[Ndop Nx])) + r1 - 1;
    result(bad_column) = NaN;

  otherwise
    error('Tracking method must be ''trws'', ''max'' or ''none'', not ''%s''.', trk.method);
end
result(bad) = NaN;

twtt = interp1(1:Nt,Time,result);
power = sample_cube(img,result);
end

function vals = sample_cube(img,bin)
% img(bin(j,i),j,i) for every Doppler bin j and trace i; NaN where bin is
[Nt,Ndop,Nx] = size(img);
vals = nan(Ndop,Nx);
ok = isfinite(bin) & bin >= 1 & bin <= Nt;
[jj,ii] = find(ok);
vals(ok) = img(sub2ind([Nt Ndop Nx],bin(ok),jj,ii));
end

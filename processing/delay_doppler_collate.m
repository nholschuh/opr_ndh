function ctrl_chain = delay_doppler_collate(param,param_override)
% ctrl_chain = delay_doppler_collate(param,param_override)
%
% The delay-Doppler counterpart of tomo.collate. Builds a cluster batch
% with one delay_doppler_collate_task per frame, each of which fuses the
% waveform images of the delay-Doppler product and tracks the ice surface
% and ice bed through every Doppler bin. See delay_doppler_collate_task for
% the steps and the output file.
%
% What carries over from tomo.collate: the vertical image fuse (same
% img_comb rule), seeding from the 2D surface and bottom picks, and TRW-S
% tracking across trace and angle bin. What does not: the DEM ray-cast and
% ice mask, because Doppler.theta is the along-track squint and the DEM
% geometry is cross-track. The surface and bed a Doppler bin sees are
% predicted instead by ray casting in the flight-line plane against the
% along-track profiles of the 2D picks (dd_ray_twtt).
%
% Like tomo.track_surface, each task needs BOTH a surface and a bottom
% layer for its frame (and reads the neighbouring frames too). A frame
% with no bottom picks still gets its surface tracked, with a warning.
%
% INPUTS
% =========================================================================
% param: parameter spreadsheet struct for one segment
%  .dd_collate: struct controlling this stage (defaults in brackets)
%   .in_path: delay-Doppler product directory ['delay_doppler']
%   .surf_out_path: where the tracked-surface files go ['dd_surf_ndh']
%   .imgs: image numbers to fuse, top to bottom. [] finds them on disk
%     from the first frame: every Data_img_II file, or 0 for a single
%     Data_YYYYMMDD_SS_FFF.mat
%   .img_comb: [] uses the spreadsheet's array.img_comb, so the seam sits
%     where it does in the 2D and 3D products
%   .img_comb_trim: [] for tomo.fuse_images' default
%   .save_fused: write the fused cube beside the image files [true]
%   .layer_params: opsLoadLayers struct array, surface first then bottom
%     [layerdata 'surface' and 'bottom' from CSARP_layer]
%   .er_ice: [3.15], as tomo.collate
%   .profile_dx: sample spacing of the along-track profiles (m) [the
%     product's Doppler.dx_out]
%   .slope_len: smoothing length for interface slopes (m) [Doppler.Lsar]
%   .top, .bottom: tracking settings for each interface
%     .method: 'trws', 'max' or 'none' ['trws']
%     .window: half-width of the search window around the prediction (s)
%       [0.3e-6 top, 1e-6 bottom]
%     .nadir_window: the same in the bin closest to vertical, which is held
%       to the 2D pick [0.03e-6 top, 0.1e-6 bottom]
%     .at_weight, .ct_weight: TRW-S smoothness weights along track and
%       across Doppler bins [0.01, 0.01, as tomo.track_surface]
%     .max_loops: TRW-S iterations [50]
% param_override: standard override struct, merged with gRadar
%
% ctrl_chain: {ctrl}, or {} if no frame has input files
%
% The TRW-S weights are tomo.track_surface's defaults for MUSIC images.
% The delay-Doppler cube is power, with a different dynamic range, so treat
% them as a starting point and check the tracked output against the
% prediction before trusting it.
%
% Supports param.cluster.rerun_only: frames whose output exists are skipped.
%
% Author: Nick Holschuh
%
% See also: delay_doppler_collate_task, delay_doppler_fuse, dd_ray_twtt,
%   delay_doppler, tomo.collate

%% Input checks
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end
param = merge_structs(param,param_override);

fprintf('=====================================================================\n');
fprintf('%s: %s (%s)\n', mfilename, param.day_seg, datestr(now));
fprintf('=====================================================================\n');

if ~isfield(param,'dd_collate') || isempty(param.dd_collate)
  param.dd_collate = [];
end
dc = param.dd_collate;
dc = set_default(dc,'in_path','delay_doppler');
dc = set_default(dc,'surf_out_path','dd_surf_ndh');
dc = set_default(dc,'imgs',[]);
dc = set_default(dc,'img_comb',[]);
if isempty(dc.img_comb) && isfield(param,'array') && isfield(param.array,'img_comb')
  dc.img_comb = param.array.img_comb;
end
dc = set_default(dc,'img_comb_trim',[]);
dc = set_default(dc,'save_fused',true);
if ~isfield(dc,'layer_params') || isempty(dc.layer_params)
  dc.layer_params = struct('name',{'surface','bottom'},'source','layerdata', ...
    'layerdata_source','layer');
end
dc = set_default(dc,'er_ice',3.15);
dc = set_default(dc,'profile_dx',[]);
dc = set_default(dc,'slope_len',[]);
trk_default.top = struct('method','trws','window',0.3e-6,'nadir_window',0.03e-6, ...
  'at_weight',0.01,'ct_weight',0.01,'max_loops',50);
trk_default.bottom = struct('method','trws','window',1e-6,'nadir_window',0.1e-6, ...
  'at_weight',0.01,'ct_weight',0.01,'max_loops',50);
for surf_name = {'top','bottom'}
  sn = surf_name{1};
  if ~isfield(dc,sn) || isempty(dc.(sn))
    dc.(sn) = trk_default.(sn);
  else
    dc.(sn) = merge_structs(trk_default.(sn),dc.(sn));
  end
end

% The task exists only in opr_ndh, so it must be in every compile of the
% shared job binary, not just this batch's
hidden = {};
if isfield(param.cluster,'hidden_depend_funs') && iscell(param.cluster.hidden_depend_funs)
  hidden = param.cluster.hidden_depend_funs;
end
if ~any(cellfun(@(h) iscell(h) && strcmp(h{1},'delay_doppler_collate_task.m'),hidden))
  hidden{end+1} = {'delay_doppler_collate_task.m' 2};
end
param.cluster.hidden_depend_funs = hidden;

frames = frames_load(param);
param.cmd.frms = frames_param_cmd_frms(param,frames);
in_dir = opr_filename_out(param,dc.in_path,'');
out_dir = opr_filename_out(param,dc.surf_out_path,'');

%% Images on disk
% =========================================================================
if isempty(dc.imgs)
  for frm = param.cmd.frms
    listing = dir(fullfile(in_dir,sprintf('Data_img_*_%s_%03d.mat',param.day_seg,frm)));
    if ~isempty(listing)
      tok = regexp({listing.name},'^Data_img_(\d+)_','tokens','once');
      dc.imgs = sort(cellfun(@(t) str2double(t{1}),tok));
      break;
    elseif exist(fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm)),'file')
      dc.imgs = 0;
      break;
    end
  end
  if isempty(dc.imgs)
    warning('%s: no delay-Doppler files in %s for any listed frame, so no tasks were made.', param.day_seg, in_dir);
    ctrl_chain = {};
    return;
  end
end
fprintf('  Images %s from %s\n', mat2str(dc.imgs), in_dir);
param.dd_collate = dc;

%% Cluster batch
% =========================================================================
ctrl = cluster_new_batch(param);
cluster_compile({'delay_doppler_collate_task.m'},ctrl.cluster.hidden_depend_funs,ctrl.cluster.force_compile,ctrl);

sparam = [];
sparam.argsin{1} = param;
sparam.task_function = 'delay_doppler_collate_task';
sparam.num_args_out = 1;

for frm_idx = 1:length(param.cmd.frms)
  frm = param.cmd.frms(frm_idx);

  if isequal(dc.imgs,0)
    in_fns = {fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm))};
  else
    in_fns = arrayfun(@(img) fullfile(in_dir,sprintf('Data_img_%02d_%s_%03d.mat',img,param.day_seg,frm)), ...
      dc.imgs,'UniformOutput',false);
  end
  missing = in_fns(~cellfun(@(fn) exist(fn,'file')==2,in_fns));
  if ~isempty(missing)
    warning('%s_%03d: skipped, input missing: %s', param.day_seg, frm, strjoin(missing,', '));
    continue;
  end

  dparam = [];
  dparam.argsin{1}.load.frm = frm;

  % Success condition: the surface file, and the fused cube when one is made
  dparam.file_success = {fullfile(out_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm))};
  if numel(dc.imgs) > 1 && dc.save_fused
    dparam.file_success{end+1} = fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm));
  end
  if ~ctrl.cluster.rerun_only
    % Mark previous outputs deletable, so a task that fails before saving
    % cannot be mistaken for a success
    for fn_idx = 1:length(dparam.file_success)
      if exist(dparam.file_success{fn_idx},'file')
        opr_file_lock_check(dparam.file_success{fn_idx},3);
      end
    end
  end

  dparam.notes = sprintf('%s %s:%s:%s %s_%03d (%d of %d)', sparam.task_function, ...
    dc.surf_out_path, param.radar_name, param.season_name, param.day_seg, frm, frm_idx, length(param.cmd.frms));
  if ctrl.cluster.rerun_only && ~cluster_file_success(dparam.file_success)
    fprintf('  Already exists [rerun_only skipping]: %s (%s)\n', dparam.notes, datestr(now));
    continue;
  end

  % Size from the input cubes without loading them
  cube_bytes = 0;
  for fn_idx = 1:length(in_fns)
    info = whos('-file',in_fns{fn_idx},'Doppler');
    cube_bytes = cube_bytes + info.bytes;
  end
  hdr = load(in_fns{1},'GPS_time','Time');
  Nx = numel(hdr.GPS_time);
  n_el = cube_bytes/4;
  Ndop = n_el/(numel(hdr.Time)*Nx*numel(in_fns));

  % Memory: during the fuse, the stack so far, the next image and the new
  % stack; during tracking, the fused cube plus a dB copy and a window mask
  % of the cropped part
  dparam.mem = 1.5e9 + 3.5*cube_bytes;
  % Time: the per-trace fuse, the ray cast (air and ice) against about
  % 2000 profile vertices per trace, and two TRW-S runs over at most the
  % whole cube
  max_loops = max(dc.top.max_loops,dc.bottom.max_loops);
  dparam.cpu_time = 300 + n_el*2e-8 + 2*Nx*Ndop*2000*2e-8 ...
    + 2*n_el*double(max_loops)*1e-8;

  ctrl = cluster_new_task(ctrl,sparam,dparam,'dparam_save',0);
end

ctrl = cluster_save_dparam(ctrl);

ctrl_chain = {ctrl};

fprintf('Done %s\n', datestr(now));

end

function s = set_default(s,field,val)
if ~isfield(s,field) || (isempty(s.(field)) && ~isempty(val))
  s.(field) = val;
end
end

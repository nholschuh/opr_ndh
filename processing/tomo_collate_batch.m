function ctrl_chain = tomo_collate_batch(param,param_override)
% ctrl_chain = tomo_collate_batch(param,param_override)
%
% Builds the same cluster batch as tomo.collate (one tomo_collate_task per
% frame, with the same defaults, success files, and memory and time
% estimates) for any array method, and with rerun_only working. Use it in
% place of tomo.collate for standard and MVDR 3D products.
%
% Why not tomo.collate: it sizes the tasks from param_array.array.method
% and only recognises MUSIC and MLE. Any other method reaches
%   warning('Unsupported param_array.array.method %s\n', method)
% with an integer method (standard is 0, MVDR is 1), which prints a control
% character. Newer MATLAB releases raise that as an error, so tomo.collate
% stops before making a single task. It also references an undefined
% combine_file_success whenever rerun_only finds a frame still to do. The
% tasks themselves (tomo_collate_task, tomo.fuse_images,
% tomo.add_dem_icemask, tomo.track_surface) are unaffected and are used
% unchanged.
%
% Nsv for the size estimate is param_array.array.Nsv, or 2*Nsrc for the
% DOA methods, which is what tomo.collate falls back to after its warning.
%
% param, param_override: as for tomo.collate
%
% Author: Nick Holschuh
%
% See also: tomo.collate, tomo_collate_task, tomo_doppler_collate

%% General Setup
% =====================================================================
param = merge_structs(param, param_override);

fprintf('=====================================================================\n');
fprintf('%s: %s (%s)\n', mfilename, param.day_seg, datestr(now));
fprintf('=====================================================================\n');

%% Input Checks
% =====================================================================
frames = frames_load(param);
param.cmd.frms = frames_param_cmd_frms(param,frames);
if isempty(param.cmd.frms)
  warning('No valid frames were listed in param.cmd.frms. Skipping this segment.');
  ctrl_chain = {};
  return;
end

% Defaults copied from tomo.collate, so the tasks see identical settings
% -------------------------------------------------------------------------
if ~isfield(param.tomo_collate,'dem_res') || isempty(param.tomo_collate.dem_res)
  param.tomo_collate.dem_res = 10;
end
if ~isfield(param.tomo_collate,'er_air') || isempty(param.tomo_collate.er_air)
  param.tomo_collate.er_air = 1;
end
if ~isfield(param.tomo_collate,'er_ice') || isempty(param.tomo_collate.er_ice)
  param.tomo_collate.er_ice = 3.15;
end

if ~isfield(param.tomo_collate,'frm_types') || isempty(param.tomo_collate.frm_types)
  param.tomo_collate.frm_types = {0,-1,-1,-1,-1};
end

if ~isfield(param.tomo_collate,'gt') || isempty(param.tomo_collate.gt)
  param.tomo_collate.gt = [];
end
if ~isfield(param.tomo_collate.gt,'en') || isempty(param.tomo_collate.gt.en)
  param.tomo_collate.gt.en = false;
end
if ~isfield(param.tomo_collate.gt,'path') || isempty(param.tomo_collate.gt.path)
  param.tomo_collate.gt.path = 'surf';
end
if ~isfield(param.tomo_collate.gt,'range') || isempty(param.tomo_collate.gt.range)
  param.tomo_collate.gt.range = 5;
end
if ~isfield(param.tomo_collate.gt,'surf_name') || isempty(param.tomo_collate.gt.surf_name)
  param.tomo_collate.gt.surf_name = 'bottom gt';
end

if ~isfield(param.tomo_collate,'ground_based_flag') || isempty(param.tomo_collate.ground_based_flag)
  param.tomo_collate.ground_based_flag = false;
end

if ~isfield(param.tomo_collate,'in_path') || isempty(param.tomo_collate.in_path)
  param.tomo_collate.in_path = 'music3D';
end
  
if ~isfield(param.tomo_collate,'out_path') || isempty(param.tomo_collate.out_path)
  if iscell(param.tomo_collate.in_path)
    param.tomo_collate.out_path = param.tomo_collate.in_path{1};
  else
    param.tomo_collate.out_path = param.tomo_collate.in_path;
  end
end
  
if ~isfield(param.tomo_collate,'surfData_mode') || isempty(param.tomo_collate.surfData_mode)
  param.tomo_collate.surfData_mode = 'append';
end
  
if ~isfield(param.tomo_collate,'surf_out_path') || isempty(param.tomo_collate.surf_out_path)
  param.tomo_collate.surf_out_path = 'surfData';
end

% Name of the top surface (usually set to 'top' when tracking surfaces below
% the ice-surface and set to an empty string, '', when tracking the
% ice-surface.
if ~isfield(param.tomo_collate,'top_name') || isempty(param.tomo_collate.top_name)
  param.tomo_collate.top_name = 'top';
end

if ~isfield(param.tomo_collate,'array_manifold_cal_flag') || isempty(param.tomo_collate.array_manifold_cal_flag)
  param.tomo_collate.array_manifold_cal_flag = false;
end

if ~isfield(param.tomo_collate,'suppress_surf_flag') || isempty(param.tomo_collate.suppress_surf_flag)
  if param.tomo_collate.array_manifold_cal_flag
    param.tomo_collate.suppress_surf_flag = false;
  else
    param.tomo_collate.suppress_surf_flag = false;
  end
end

if ~isfield(param.tomo_collate,'suppress_surf_peak_val') || isempty(param.tomo_collate.suppress_surf_peak_val)
  param.tomo_collate.suppress_surf_peak_val = 30;
end

if ~isfield(param.tomo_collate,'suppress_surf_window') || isempty(param.tomo_collate.suppress_surf_window)
  param.tomo_collate.suppress_surf_window = 100;
end


%% Setup Processing
% =====================================================================
[~,~,radar_name] = opr_output_dir(param.radar_name);
records = records_load(param);
along_track_approx = geodetic_to_along_track(records.lat,records.lon,records.elev);
out_path_dir = opr_filename_out(param, param.tomo_collate.out_path);
surf_out_path_dir = opr_filename_out(param, param.tomo_collate.surf_out_path);

%% Setup cluster
% =====================================================================
ctrl = cluster_new_batch(param);
cluster_compile({'tomo_collate_task.m'},ctrl.cluster.hidden_depend_funs,ctrl.cluster.force_compile,ctrl);

% Array settings from the first frame of a processable type
frm = [];
for frm_idx = 1:length(param.cmd.frms)
  if opr_proc_frame(frames.proc_mode(param.cmd.frms(frm_idx)),param.tomo_collate.frm_types)
    frm = param.cmd.frms(frm_idx);
    break;
  end
end
if isempty(frm)
  error('There are no valid frames in param.cmd.frms to process based on param.tomo_collate.frm_types.')
end
if param.tomo_collate.imgs{1}(1) == 0
  in_fn = fullfile(out_path_dir, sprintf('Data_%s_%03d.mat', param.day_seg, frm));
else
  in_fn = fullfile(out_path_dir, sprintf('Data_img_%02d_%s_%03d.mat', ...
    param.tomo_collate.imgs{1}(1), param.day_seg, frm));
end
load(in_fn,'param_array');
array_proc_methods; % MLE_METHOD, DOA_METHOD_THRESHOLD
if ~param_array.array.tomo_en
  error('param_array.array.tomo_en is false for %s, tomography should be enabled during array process in order to run tomo.collate.', in_fn);
end
if all(param_array.array.method < DOA_METHOD_THRESHOLD)
  Nsv = param_array.array.Nsv;
else
  Nsv = 2*param_array.array.Nsrc;
end

% Size of the images, for cpu time and memory (tomo.collate)
param.load.imgs = param_array.array.imgs;
[wfs,~] = data_load_wfs(param,records);
total_num_sam = 0;
if any(strcmpi(radar_name,{'acords','hfrds','hfrds2','mcords','mcords2','mcords3','mcords4','mcords5','mcords6','mcrds','rds','seaice','accum2','accum3'}))
  for v_img = 1:length(param.tomo_collate.imgs)
    img = param.tomo_collate.imgs{v_img}(1);
    if img == 0
      wf = param_array.array.imgs{1}{1}(1);
    else
      wf = param_array.array.imgs{img}{1}(1);
    end
    total_num_sam = total_num_sam + wfs(wf).Nt;
  end
  cpu_time_mult = 20e-6;
  mem_mult = 14;
elseif any(strcmpi(radar_name,{'snow','kuband','snow2','kuband2','snow3','kuband3','kaband3','snow5','snow8'}))
  total_num_sam = 32000;
  cpu_time_mult = 8e-8;
  mem_mult = 64;
else
  error('radar_name %s not supported yet.', radar_name);
end

%% Create Tasks
% =====================================================================
sparam = [];
sparam.argsin{1} = param;
sparam.task_function = 'tomo_collate_task';
sparam.num_args_out = 1;
sparam.argsin{1}.load.imgs = param.tomo_collate.imgs;
for frm_idx = 1:length(param.cmd.frms)
  frm = param.cmd.frms(frm_idx);
  if ~opr_proc_frame(frames.proc_mode(frm),param.tomo_collate.frm_types)
    fprintf('Skipping %s_%03i (no process frame)\n', param.day_seg, frm);
    continue;
  end

  start_rec = frames.frame_idxs(frm);
  if frm < length(frames.frame_idxs)
    stop_rec = frames.frame_idxs(frm+1)-1;
  else
    stop_rec = length(records.gps_time);
  end
  frm_dist = along_track_approx(stop_rec) - along_track_approx(start_rec);

  dparam = [];
  dparam.argsin{1}.load.frm = frm;
  dparam.file_success = {};
  if param.tomo_collate.fuse_images_flag || param.tomo_collate.add_icemask_surfacedem_flag
    dparam.file_success{end+1} = fullfile(out_path_dir, sprintf('Data_%s_%03d.mat', param.day_seg, frm));
  end
  if param.tomo_collate.create_surfData_flag
    dparam.file_success{end+1} = fullfile(surf_out_path_dir, sprintf('Data_%s_%03d.mat', param.day_seg, frm));
  end

  dparam.notes = sprintf('%s:%s:%s:%s %s_%03d (%d of %d)', sparam.task_function, param.radar_name, ...
    param.season_name, out_path_dir, param.day_seg, frm, frm_idx, length(param.cmd.frms));
  if ctrl.cluster.rerun_only
    if ~cluster_file_success(dparam.file_success)
      fprintf('  Already exists [rerun_only skipping]: %s (%s)\n', dparam.notes, datestr(now));
      continue;
    end
  else
    % Mark previous outputs for deletion, so a failed task cannot pass
    for fn_idx = 1:length(dparam.file_success)
      if exist(dparam.file_success{fn_idx},'file')
        opr_file_lock_check(dparam.file_success{fn_idx},3);
      end
    end
  end
  fprintf('%s %s_%03i (%i of %i) (%s)\n', sparam.task_function, param.day_seg, frm, frm_idx, length(param.cmd.frms), datestr(now));

  Nx = round(frm_dist / param.sar.sigma_x / param_array.array.dline);
  dparam.cpu_time = 10 + Nx*Nsv*total_num_sam*cpu_time_mult;
  dparam.mem = 250e6 + Nx*Nsv*total_num_sam*mem_mult;
  ctrl = cluster_new_task(ctrl,sparam,dparam,'dparam_save',0);
end

ctrl = cluster_save_dparam(ctrl);
ctrl_chain = {ctrl};

fprintf('Done %s\n', datestr(now));

% script run_music3D_collate_ThwaitesGrid
%
% Reprocesses the 2009_Antarctica_TO (DC-8 MCoRDS) Thwaites downstream-grid
% flights into 3D MUSIC images and tracks the ice bottom through them with
% tomo.collate, for comparison with the DELORES (GHOST 2023-24) ground radar
% profiles (49_GHOST/Airborne_GroundBased_Comparison).
%
% Stages (each switched on below):
%   1. sar          per-channel SAR images, rerun into CSARP_sar_ndh (the input
%                   array reads, via array.in_path)
%   2. array        3D MUSIC images (Tomo.img, Nsv look directions), written as
%                   Data_img_01/Data_img_02 in CSARP_music3D_ndh -- with tomo_en
%                   on, array does not combine images (array_combine_task.m:78)
%   3. tomo.collate fuse the two waveform images vertically, attach the surface
%                   DEM and ice mask, and track the ice bottom (TRW-S), writing
%                   surfData to CSARP_surfData_ndh
%
% Segments and frames (all frames of each segment; 87 frames total):
%   20100101_02 001-018   20100103_01 001-016   20100103_02 001-018
%   20100104_01 001-016   20100112_01 001-012   20100112_02 001-007
%
% Settings follow the opr_params spreadsheet for everything the 2D products
% use (radar, sar, array.imgs/img_comb/line_rng/Nsrc); only the 3D choices are
% overridden here, matching the earlier CSARP_NDH_music run (MUSIC, Nsv = 64).
%
% CHECK BEFORE RUNNING -- GPS time offset. The records worksheet sets
% gps.time_offset per segment, and the two existing versions of these flights
% disagree on it:
%     20100101_02  +1        20100103_01  -86399    20100103_02  +1
%     20100104_01  -86399    20100112_01  -86399    20100112_02  +1
% The segments set to -86399 are the ones whose aircraft Elevation differs most
% between the original (2017-18) and reprocessed frames (+10.2, +10.8, +8.5 m;
% the +1 segments differ by +3.5 and +3.2 m), and whose original GPS_time was
% 86401 s off. A trajectory synced to the radar with the wrong offset puts the
% wrong elevation on every record, which is the leading candidate for the
% ~15 m offset between the old tomography bed (TomoBed/DS_Bed) and today's
% nadir picks. Confirm the offset when recreating records, before this script.
%
% Requires: records and frames files for each segment (recreate those first if
% the GPS offset changes), and gRadar set up by your OPR startup on the machine
% that holds the data.
%
% Author: Nick Holschuh
%
% See also: run_sar_tomo_doppler_frames, select_day_seg_frms, master, array, tomo.run_collate, tomo.collate,
%   tomo.add_dem_icemask, tomo.track_surface, run_surfdata_to_DEM

%% User Settings
% =========================================================================

global gRadar;
if isempty(gRadar) || ~isfield(gRadar,'out_path')
  error('gRadar is not set. Run the OPR startup for this machine first.');
end

clear('param_override');
param_override = [];

param_override.cluster.type = 'slurm';
% param_override.cluster.type = 'debug';     % run here, for testing one frame
param_override.cluster.rerun_only = false;   % true to resume, keeping finished tasks
param_override.cluster.max_jobs_active = 96;
param_override.cluster.cpu_time_mult  = 2;
param_override.cluster.mem_mult  = 2;
param_override.cluster.mem_mult_mode = 'auto';
param_override.cluster.max_mem_mode = 'truncate';
param_override.cluster.max_cpu_time_mode = 'truncate';

% Which stages to run
run_sar = true;
run_array = true;
run_collate = true;

% Download the REMA tiles collate needs, once and serially, before the cluster
% job. tomo.add_dem_icemask asks dem_class for a 10 m surface DEM, which wgets
% REMA v2.0 tiles into <gis_path>/antarctica/DEM/REMA and untars them. Frames
% share tiles, so parallel tasks race: one untars an archive another is still
% downloading and the task dies in untar ("An internal error has occurred" in
% matlab.io.internal.archive.core.builtin.extractArchive). Pre-fetching here
% leaves every tile on disk before the tasks start. Safe to leave true: tiles
% already downloaded are skipped.
prefetch_dem = true;

% Submit and wait. Set false to only build and save the chains.
run_chain_en = true;

% Output product directories (CSARP_<name>); distinct names so nothing posted
% as a 2D product is overwritten
sar_out_path = 'sar_ndh';
array_out_path = 'music3D_ndh';
surf_out_path = 'surfData_ndh';

%% Segments
% =========================================================================
params = read_param_xls(opr_filename_param('rds_param_2009_Antarctica_TO.xlsx'),'','post');
% Exactly these segments, all frames of each; every other segment is disabled
params = select_day_seg_frms(params,{'20100101_02','20100103_01','20100103_02', ...
  '20100104_01','20100112_01','20100112_02'});

% master runs sar/array on any segment whose cmd.sar/cmd.array is set, without
% checking cmd.generic, so switch the stages on only for the enabled segments
% and off everywhere else (records and qlook too, so no spreadsheet flag starts
% work on another segment)
for param_idx = 1:length(params)
  seg_en = opr_generic_en(params(param_idx));
  params(param_idx).cmd.records = 0;
  params(param_idx).cmd.qlook = 0;
  params(param_idx).cmd.sar = double(run_sar && seg_en);
  params(param_idx).cmd.array = double(run_array && seg_en);
  if seg_en
    % Print the GPS time offset each segment will use (see header)
    fprintf('%s  gps.time_offset = %g s\n',params(param_idx).day_seg,params(param_idx).records.gps.time_offset);
  end
end

%% SAR and array settings
% =========================================================================
% sar: spreadsheet settings (fk, sigma_x 2.5, both waveform images); only the
% output directory is set here
params = opr_set_params(params,'sar.out_path',sar_out_path);
% Keep sar_coord.mat beside the SAR chunks, where array looks for it
params = opr_set_params(params,'sar.coord_path',sar_out_path);

% array: 3D MUSIC with the look-direction axis kept
params = opr_set_params(params,'array.in_path',sar_out_path);
params = opr_set_params(params,'array.out_path',array_out_path);
params = opr_set_params(params,'array.method','music');
params = opr_set_params(params,'array.tomo_en',1);
params = opr_set_params(params,'array.Nsv',64);   % as in CSARP_NDH_music (64 look directions)
params = opr_set_params(params,'array.Nsrc',2);   % spreadsheet value, set explicitly
% Multilook support stays at the spreadsheet bin_rng = 0, line_rng = -5:5
% (11 snapshots for 6 channels), which keeps the MUSIC covariance full rank.

%% tomo.collate settings
% =========================================================================
tomo_collate = [];

% .in_path: array output (Data_img_II*.mat); the fused image is written here too
tomo_collate.in_path = array_out_path;

% .surf_out_path: where the surfData files go
tomo_collate.surf_out_path = surf_out_path;

% .imgs: vertical fuse of the two waveform images (short pulse above long pulse)
tomo_collate.imgs = {1,2};

% .img_comb: [min time to begin combine, min time after surface, time at the end
%   of the preceding waveform not to use] -- the spreadsheet's array.img_comb,
%   so the 3D fuse matches the 2D standard product
first_idx = find(arrayfun(@opr_generic_en,params),1);
tomo_collate.img_comb = params(first_idx).array.img_comb;
tomo_collate.fuse_columns = {[],[]};

% .sv_cal_fn: steering-vector calibration (none)
tomo_collate.sv_cal_fn = '';

% .ice_mask_fn: none -- the grid is grounded ice throughout
tomo_collate.ice_mask_fn = '';

% .dem_guard / .dem_per_slice_guard: DEM search regions (m) around the flight
%   line and each slice (the surface DEM itself comes from dem_class/gdem)
tomo_collate.dem_guard = 16e3;
tomo_collate.dem_per_slice_guard = 2500;

tomo_collate.ground_based_flag = false;

% .bounds_relative: DOA bins and slices trimmed from each edge [top bottom left right]
tomo_collate.bounds_relative = [3 2 0 0];

% .layer_params: 2D layers used to seed the tracker (surface first, then bottom)
tomo_collate.layer_params = struct('name','surface','source','layerdata');
tomo_collate.layer_params(2).name = 'bottom';
tomo_collate.layer_params(2).source = 'layerdata';

% .surfData_mode: fresh surfData files
tomo_collate.surfData_mode = 'overwrite';

% .surfdata_cmds: ice-bottom tracking with TRW-S (the tracker behind the
%   existing CSARP_surfData 'bottom trws' / 'bottom' layers)
tomo_collate.surfdata_cmds = [];
tomo_collate.surfdata_cmds(end+1).cmd = 'trws';
tomo_collate.surfdata_cmds(end).surf_names = {'bottom trws','bottom'};
tomo_collate.surfdata_cmds(end).visible = true;

tomo_collate.fuse_images_flag = true;
tomo_collate.add_icemask_surfacedem_flag = true;
tomo_collate.create_surfData_flag = true;

param_override.tomo_collate = tomo_collate;

%% Automated Section
% =========================================================================
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

%% SAR -> array (one chain from master)
if run_sar || run_array
  ctrl_chain = master(params,param_override);
  cluster_print_chain(ctrl_chain);
  [chain_fn,chain_id] = cluster_save_chain(ctrl_chain);
  if run_chain_en
    ctrl_chain = cluster_run(ctrl_chain);
  else
    fprintf('Chain saved (id %d): %s\nRun it later with cluster_load_chain and cluster_run.\n', chain_id, chain_fn);
  end
end

%% Pre-fetch the surface DEM tiles (serial, before any collate task)
if run_collate && prefetch_dem
  physical_constants;   % WGS84
  global gdem;
  if isempty(gdem) || ~isa(gdem,'dem_class') || ~isvalid(gdem)
    gdem = dem_class(merge_structs(params(first_idx),param_override),10);
  end
  gdem.set_res(10);
  for param_idx = 1:length(params)
    param = merge_structs(params(param_idx),param_override);
    if ~opr_generic_en(param)
      continue;
    end
    records = records_load(param);
    dec_idxs = round(linspace(1,length(records.lat),min(length(records.lat),2000)));
    [latb,lonb] = bufferm(records.lat(dec_idxs),records.lon(dec_idxs), ...
      param.tomo_collate.dem_guard/WGS84.semimajor*180/pi);
    fprintf('Pre-fetching surface DEM tiles for %s (%s)\n',param.day_seg,datestr(now));
    gdem.set_vector(latb,lonb,sprintf('prefetch:%s',param.day_seg));
    gdem.get_vector_mosaic(100);
  end
end

%% tomo.collate (after the array images exist)
if run_collate
  ctrl_chain = {};
  for param_idx = 1:length(params)
    param = params(param_idx);
    if ~opr_generic_en(param)
      continue;
    end
    ctrl_chain{end+1} = tomo.collate(param,param_override);
  end
  cluster_print_chain(ctrl_chain);
  [chain_fn,chain_id] = cluster_save_chain(ctrl_chain);
  if run_chain_en
    ctrl_chain = cluster_run(ctrl_chain);
  else
    fprintf('Chain saved (id %d): %s\nRun it later with cluster_load_chain and cluster_run.\n', chain_id, chain_fn);
  end
end

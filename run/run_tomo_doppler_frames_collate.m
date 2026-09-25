% script run_tomo_doppler_frames_collate
%
% STEP 3, after run_tomo_doppler_frames_cluster. Collates the frames in
% tomo_doppler_frames_list:
%  - tomo.collate on each of the three 3D products (CSARP_standard3D_ndh,
%    CSARP_mvdr3D_ndh, CSARP_music3D_ndh): vertical fuse of the waveform
%    images, surface DEM and ice mask, and TRW-S ice-bottom tracking, each
%    into its own surfData directory
%  - delay_doppler_collate on CSARP_delay_doppler: the same vertical fuse,
%    then the ice surface and ice bed predicted and tracked in every
%    Doppler bin, into CSARP_dd_surf_ndh
%
% The three 3D products differ only in estimator, and are collated here
% with identical settings, so their fused cubes share Time and GPS_time
% and can still be compared pixel for pixel (the check at the end
% confirms it). The delay-Doppler product sits on the same traces.
%
% LAYERS. Both collates need a 2D surface AND a 2D bottom layer for each
% frame and its neighbours (tomo.track_surface errors out without them).
% These frames come from posted seasons, so the default reads both from
% the posted CSARP_layer. tomo_doppler_collate loads them for every frame
% before anything is queued and stops if one is missing.
%
% TRACKER TUNING. The TRW-S settings below are the ones used for MUSIC
% (run_music3D_collate_ThwaitesGrid). tomo.track_surface tracks
% 10*log10(Tomo.img), and MUSIC is a dimensionless pseudospectrum while
% standard and MVDR are power, with a different dynamic range. Identical
% settings keep the comparison about the estimator, not the tracker, but
% they are not tuned for standard or MVDR: check the tracked bottoms
% against the 2D picks before reading anything into the differences. The
% same holds for the delay-Doppler tracker (delay_doppler_collate).
% Data carries radiometric_corr_dB and Tomo does not, so compare Tomo
% cubes with each other, not with Data.
%
% Workflow on the cluster login node:
%  1. Run with check_only_en = false. With run_chain_en = true the script
%     submits, waits, then runs the checks.
%  2. If the session ends first, reload the saved chain with
%     cluster_load_chain and run it with cluster_run, then run this script
%     again with check_only_en = true.
%  3. To fill in failed or missing frames, set cluster.rerun_only = true
%     and run again.
%
% Author: Nick Holschuh
%
% See also: tomo_doppler_frames_list, run_tomo_doppler_frames_cluster,
%   tomo_doppler_collate, tomo_doppler_collate_check, delay_doppler_collate,
%   run_music3D_collate_ThwaitesGrid, tomo.collate

%% User Settings
% =========================================================================

% ---- What to process ----------------------------------------------------
jobs = tomo_doppler_frames_list();

% ---- The products -------------------------------------------------------
% out_path must match run_tomo_doppler_frames_cluster (cfg.out_paths).
% Each product gets its own surfData directory.
cfg = [];
cfg.products = struct( ...
  'method',       {'standard',                'mvdr',                'music'}, ...
  'out_path',     {'standard3D_ndh',          'mvdr3D_ndh',          'music3D_ndh'}, ...
  'surf_out_path',{'surfData_standard3D_ndh', 'surfData_mvdr3D_ndh', 'surfData_music3D_ndh'});
cfg.run_3d_en = [true true true];
cfg.run_dd_en = true;

% ---- 2D layers used by both collates (surface first, then bottom) --------
cfg.layer_params = struct('name',{'surface','bottom'},'source','layerdata', ...
  'layerdata_source','layer');
cfg.check_layers_en = true;

% Download the surface DEM tiles once, serially, before the tasks start
% (parallel tasks race on the same tiles; see run_music3D_collate_ThwaitesGrid)
cfg.prefetch_dem_en = true;

% ---- tomo.collate, shared by the three 3D products -----------------------
% in_path, out_path, surf_out_path, imgs and layer_params are set per
% product by tomo_doppler_collate
tomo_collate = [];
tomo_collate.img_comb = [];               % []: the spreadsheet's array.img_comb
tomo_collate.sv_cal_fn = '';
tomo_collate.ice_mask_fn = '';
tomo_collate.dem_guard = 16e3;
tomo_collate.dem_per_slice_guard = 2500;
tomo_collate.ground_based_flag = false;
tomo_collate.bounds_relative = [3 2 0 0];
tomo_collate.surfData_mode = 'overwrite';
tomo_collate.surfdata_cmds = [];
tomo_collate.surfdata_cmds(end+1).cmd = 'trws';
tomo_collate.surfdata_cmds(end).surf_names = {'bottom trws','bottom'};
tomo_collate.surfdata_cmds(end).visible = true;
tomo_collate.fuse_images_flag = true;
tomo_collate.add_icemask_surfacedem_flag = true;
tomo_collate.create_surfData_flag = true;
cfg.tomo_collate = tomo_collate;

% ---- delay_doppler_collate ----------------------------------------------
% Defaults for everything not set here are listed in delay_doppler_collate
cfg.dd_collate = [];
cfg.dd_collate.in_path = 'delay_doppler';     % cfg.dd.out_path in the cluster script
cfg.dd_collate.surf_out_path = 'dd_surf_ndh';
cfg.dd_collate.save_fused = true;
% Angle bins: the native Doppler axis averaged onto the same Nsv look
% directions as the 3D products (cfg.shared.Nsv in the cluster script)
cfg.dd_collate.Nsv = 64;
cfg.dd_collate.top.method = 'trws';
cfg.dd_collate.bottom.method = 'trws';

% ---- Cluster ------------------------------------------------------------
param_override = [];
param_override.cluster.type = 'slurm';
% param_override.cluster.type = 'debug';     % run every task here, for testing
% param_override.cluster.rerun_only = true;  % only frames without output
param_override.cluster.max_jobs_active = 96;
param_override.cluster.cpu_time_mult  = 2;
param_override.cluster.mem_mult  = 2;
param_override.cluster.mem_mult_mode = 'auto';
param_override.cluster.max_mem_mode = 'truncate';
param_override.cluster.max_cpu_time_mode = 'truncate';

% Submit and wait. Set false to only build and save the chain.
run_chain_en = true;

% Skip building and submitting, and only run the checks
check_only_en = false;

%% Automated Section
% =========================================================================
global gRadar;
if isempty(gRadar) || ~isfield(gRadar,'out_path')
  error('gRadar is not set. Run the OPR startup for this machine first.');
end
param_override = merge_structs(gRadar,param_override);

params_list = {};
for job_idx = 1:length(jobs)
  params = read_param_xls(opr_filename_param(jobs(job_idx).param_fn));
  params_list{end+1} = select_day_seg_frms(params,jobs(job_idx).day_seg_frms); %#ok<SAGROW>
end

if ~check_only_en
  ctrl_chain = {};
  for job_idx = 1:length(params_list)
    % One forced compile for the whole run, with both collate tasks in it
    cfg.compile_first = (job_idx == 1);
    chains = tomo_doppler_collate(params_list{job_idx},cfg,param_override);
    ctrl_chain = [ctrl_chain chains]; %#ok<AGROW>
  end

  if isempty(ctrl_chain)
    fprintf('Nothing to submit.\n');
  else
    cluster_print_chain(ctrl_chain);
    [chain_fn,chain_id] = cluster_save_chain(ctrl_chain);
    if run_chain_en
      ctrl_chain = cluster_run(ctrl_chain);
    else
      fprintf('Chain saved (id %d): %s\nRun it later with cluster_load_chain and cluster_run.\n', chain_id, chain_fn);
    end
  end
end

if check_only_en || run_chain_en
  for job_idx = 1:length(params_list)
    tomo_doppler_collate_check(params_list{job_idx},cfg,param_override);
  end
end

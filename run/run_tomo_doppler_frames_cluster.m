% script run_tomo_doppler_frames_cluster
%
% STEP 2 of 2. After run_sar_tomo_doppler_frames has finished, builds the
% delay-Doppler product and the three 3D array products (standard, MVDR,
% MUSIC) for the frames in tomo_doppler_frames_list, farmed out to the
% cluster. This is run_delay_doppler_tomo_cluster with its frame list and
% SAR product taken from tomo_doppler_frames_list; every other setting is
% the same.
%
% The 3D runs use the full array: every channel in each segment's
% sar.imgs, which for 2013_Antarctica_P3 is 15 receivers rather than the 7
% in its array worksheet. dline comes from the spreadsheet, and the SAR
% product is CSARP_sar_ndh. Everything in cfg.shared below is forced
% identical across the three runs.
%
% Workflow on the cluster login node:
%  1. Run with check_only_en = false. With run_chain_en = true the script
%     submits, waits, then runs the acceptance checks.
%  2. If the session ends before the jobs finish, reload the saved chain
%     with cluster_load_chain and run it with cluster_run, then run this
%     script again with check_only_en = true.
%  3. To fill in failed or missing frames, set cluster.rerun_only = true
%     and run again.
%
% Author: Nick Holschuh
%
% See also: tomo_doppler_frames_list, run_sar_tomo_doppler_frames,
%   run_delay_doppler_tomo_cluster, delay_doppler_tomo

%% User Settings
% =========================================================================

% ---- What to process ----------------------------------------------------
% Frames and SAR product come from the list shared with the SAR step
[jobs,list_sar_out_path,list_sar_type] = tomo_doppler_frames_list();

% ---- SAR product used for the 3D images --------------------------------
% CSARP_<sar_out_path> must hold the SAR chunks (<sar_type>_data_FFF_01_01)
% and sar_coord.mat. The delay-Doppler grid is read from the same place.
cfg = [];
cfg.sar_out_path = list_sar_out_path;   % set in tomo_doppler_frames_list
cfg.sar_type     = list_sar_type;

% ---- Posting grid -------------------------------------------------------
% Empty uses each segment's array.dline from the spreadsheet, which is what
% CSARP_standard was made with.
cfg.dline = [];

% ---- The three 3D products ----------------------------------------------
% Only method and out_path differ. Never use a bare method name as an
% out_path, or array.m overwrites the posted 2D product of that name.
cfg.methods   = {'standard',       'mvdr',       'music'};
cfg.out_paths = {'standard3D_ndh', 'mvdr3D_ndh', 'music3D_ndh'};
cfg.run_3d_en = [true              true          true];

% ---- Settings shared by all three runs ----------------------------------
cfg.shared = [];
cfg.shared.imgs          = 'sar';   % []: array.imgs; 'sar': every channel in sar.imgs (full array)
cfg.shared.bin_rng       = 0;
cfg.shared.line_rng      = -5:5;
cfg.shared.dbin          = 1;
cfg.shared.Nsv           = 64;      % must be > 1; 256 for per-pixel analysis
cfg.shared.tomo_en       = true;
cfg.shared.Nsrc          = 2;       % only affects MUSIC, recorded with the set
cfg.shared.sv_model      = 'ideal';
cfg.shared.sv_dielectric = 1;
cfg.shared.window        = @boxcar; % array_proc documents @hanning but defaults to @boxcar
% Covariance support. array_proc honours this only for MVDR; standard and
% MUSIC use the multilook support regardless. Set on all three so the runs
% are identical apart from method and out_path. Needs at least 2*Nc
% snapshots unless diag_load is nonzero.
cfg.shared.DCM.bin_rng   = -2:2;
cfg.shared.DCM.line_rng  = -15:15;
cfg.shared.diag_load     = 0;

% ---- Delay-Doppler product ----------------------------------------------
cfg.run_delay_doppler_en = true;
cfg.dd = [];
cfg.dd.imgs       = [];             % empty: each segment's sar.imgs
cfg.dd.out_path   = 'delay_doppler';
cfg.dd.block_size = 200;
cfg.dd.st_wind    = @hanning;
cfg.dd.theta_rng  = [-90 90];
cfg.dd.complex_en = false;
cfg.dd.presums    = 1;
cfg.dd.bit_mask   = 1;

% ---- Safety and checks --------------------------------------------------
% Refuse to queue a 3D frame whose output already exists (ignored when
% cluster.rerun_only is set, since array.m then skips finished frames).
cfg.overwrite_en = false;
% After the jobs finish, run tomo_set_check on every frame. The 2D products
% listed here are also checked for trace alignment with the 3D set; the
% delay-Doppler out_path is added automatically.
cfg.check_en = true;
cfg.check_ref_paths = {'standard'};

% ---- Cluster ------------------------------------------------------------
param_override = [];
param_override.cluster.type = 'slurm';
% param_override.cluster.type = 'debug';     % run every task here, for testing
% param_override.cluster.rerun_only = true;  % only frames without output
param_override.cluster.max_jobs_active = 96;
param_override.cluster.cpu_time_mult  = 2;
param_override.cluster.mem_mult  = 1.5;
param_override.cluster.mem_mult_mode = 'auto';
param_override.cluster.max_mem_mode = 'truncate';
param_override.cluster.max_cpu_time_mode = 'truncate';

% Submit and wait. Set false to only build and save the chain.
run_chain_en = true;

% Skip building and submitting, and only run the acceptance checks on the
% segments and frames listed above
check_only_en = false;

%% Automated Section
% =========================================================================
cfg.dd_mode = 'cluster';

global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

params_list = {};
for job_idx = 1:length(jobs)
  params = read_param_xls(opr_filename_param(jobs(job_idx).param_fn));
  params_list{end+1} = select_day_seg_frms(params,jobs(job_idx).day_seg_frms); %#ok<SAGROW>
end

if ~check_only_en
  ctrl_chain = {};
  for job_idx = 1:length(params_list)
    % Force the job-binary compile only for the first spreadsheet; batches
    % for later spreadsheets find the binary up to date
    cfg.compile_first = (job_idx == 1);
    chains = delay_doppler_tomo(params_list{job_idx},cfg,param_override);
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

if cfg.check_en && (check_only_en || run_chain_en)
  for job_idx = 1:length(params_list)
    delay_doppler_tomo_check(params_list{job_idx},cfg,param_override);
  end
end

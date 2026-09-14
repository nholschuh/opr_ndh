% script run_delay_doppler_tomo
%
% LOCAL version. Produces the delay-Doppler product and the three 3D array
% products (standard, MVDR, MUSIC) on the CSARP_standard traces.
%
% The delay-Doppler product is computed in this MATLAB session, one segment
% after another. The 3D products go through array.m and so run on whatever
% cluster.type is set below ('debug' runs them here too, 'matlab' uses local
% parallel workers). For large lists, use run_delay_doppler_tomo_cluster,
% which also farms the delay-Doppler frames out as cluster tasks.
%
% Prerequisite: sar has been run for each segment with the sar product set
% below.
%
% Author: Nick Holschuh
%
% See also: run_delay_doppler_tomo_cluster, delay_doppler_tomo,
%   delay_doppler_tomo_check, select_day_seg_frms

%% User Settings
% =========================================================================

% ---- What to process ----------------------------------------------------
% One entry per parameter spreadsheet. List segments as 'YYYYMMDD_SS' (all
% frames) or frames as 'YYYYMMDD_SS_FFF'.
jobs = [];
jobs(1).param_fn     = 'rds_param_2024_Antarctica_GroundGHOST2.xlsx';
jobs(1).day_seg_frms = {'20250117_03'};

% ---- SAR product used for the 3D images --------------------------------
% CSARP_<sar_out_path> must hold the SAR chunks (<sar_type>_data_FFF_01_01)
% and sar_coord.mat. The delay-Doppler grid is read from the same place.
cfg = [];
cfg.sar_out_path = 'sar';
cfg.sar_type     = 'fk';        % 'fk' or 'tdbp'

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
cfg.shared.imgs          = [];      % empty: the spreadsheet's array.imgs
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
dbstop if error;
if 1
  param_override.cluster.type = 'matlab';
  mem_per_job_kB = 20e6;
  [nproc,system_mem] = opr_get_system_cpu_mem();
  param_override.cluster.matlab_NumWorkers = floor(min(nproc,system_mem/mem_per_job_kB));
  param_override.cluster.max_jobs_active = 1024;
elseif 0
  param_override.cluster.type = 'debug';
end
% param_override.cluster.rerun_only = true;
param_override.cluster.cpu_time_mult  = 20;
param_override.cluster.mem_mult  = 2;
param_override.cluster.mem_mult_mode = 'auto';
param_override.cluster.max_mem_mode = 'truncate';
param_override.cluster.max_cpu_time_mode = 'truncate';

% Submit the 3D jobs and wait for them
run_chain_en = true;

%% Automated Section
% =========================================================================
cfg.dd_mode = 'local';

global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

params_list = {};
ctrl_chain = {};
for job_idx = 1:length(jobs)
  params = read_param_xls(opr_filename_param(jobs(job_idx).param_fn));
  params = select_day_seg_frms(params,jobs(job_idx).day_seg_frms);
  params_list{end+1} = params; %#ok<SAGROW>
  chains = delay_doppler_tomo(params,cfg,param_override);
  ctrl_chain = [ctrl_chain chains]; %#ok<AGROW>
end

if ~isempty(ctrl_chain)
  cluster_print_chain(ctrl_chain);
  [chain_fn,chain_id] = cluster_save_chain(ctrl_chain);
  if run_chain_en
    ctrl_chain = cluster_run(ctrl_chain);
  end
end

if cfg.check_en && run_chain_en
  for job_idx = 1:length(params_list)
    delay_doppler_tomo_check(params_list{job_idx},cfg,param_override);
  end
end

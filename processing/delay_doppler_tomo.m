function ctrl_chain = delay_doppler_tomo(params,cfg,param_override)
% ctrl_chain = delay_doppler_tomo(params,cfg,param_override)
%
% Shared engine behind run_delay_doppler_tomo (local) and
% run_delay_doppler_tomo_cluster. For every enabled segment it
%  1. produces the delay-Doppler product, either in this MATLAB session
%     (cfg.dd_mode = 'local') or as one cluster task per frame
%     (cfg.dd_mode = 'cluster'), and
%  2. queues the three 3D array products (standard, MVDR, MUSIC) with
%     identical settings apart from method and out_path.
% Both run scripts call this, so the validation and the rules that make the
% three products comparable live in one place.
%
% All products are posted on the CSARP_standard traces: the 3D runs use the
% standard dline and read the chosen SAR product, and the delay-Doppler
% product reads that product's sar_coord.mat.
%
% INPUTS
% =========================================================================
% params: parameter spreadsheet struct array with segments enabled through
%   cmd.generic and frames in cmd.frms (see select_day_seg_frms)
% cfg: settings struct built in the run scripts
%   .sar_out_path, .sar_type: SAR product feeding every output
%   .dline: [] for each segment's spreadsheet array.dline
%   .methods, .out_paths, .run_3d_en: the 3D products
%   .shared: array settings common to all three runs. shared.imgs may be
%     [] for each segment's array.imgs, 'sar' for every channel in its
%     sar.imgs (the full array as SAR processed), or an explicit cell array
%   .run_delay_doppler_en, .dd: delay-Doppler switch and settings
%   .dd_mode: 'local' or 'cluster'
%   .overwrite_en: allow queuing 3D frames that already exist
%   .compile_first: force the one-time job-binary compile described below.
%     Default true. A script calling this once per spreadsheet should set it
%     true only for the first call, or it compiles once per spreadsheet.
% param_override: standard override struct, usually carrying .cluster
%
% OUTPUTS
% =========================================================================
% ctrl_chain: cell array of chains for cluster_run. Every 3D product and
%   every delay-Doppler batch is its own chain, so they run in parallel.
%   In 'local' mode the delay-Doppler product is already done on return.
%
% Author: Nick Holschuh
%
% See also: run_delay_doppler_tomo, run_delay_doppler_tomo_cluster,
%   delay_doppler_tomo_check, delay_doppler_batch, array

%% Input checks
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

if ~any(strcmpi(cfg.dd_mode,{'local','cluster'}))
  error('cfg.dd_mode must be ''local'' or ''cluster'', not ''%s''.', cfg.dd_mode);
end

% Every batch compiles into one shared cluster job binary, and whichever
% batch compiles last decides what the binary contains. Listing the task
% here puts it in every compile, including the array batches.
hidden = {};
if isfield(param_override,'cluster') && isfield(param_override.cluster,'hidden_depend_funs') ...
    && iscell(param_override.cluster.hidden_depend_funs)
  hidden = param_override.cluster.hidden_depend_funs;
end
if ~any(cellfun(@(h) iscell(h) && strcmp(h{1},'delay_doppler_task.m'),hidden))
  hidden{end+1} = {'delay_doppler_task.m' 2};
end
param_override.cluster.hidden_depend_funs = hidden;

rerun_only = isfield(param_override.cluster,'rerun_only') ...
  && ~isempty(param_override.cluster.rerun_only) && param_override.cluster.rerun_only;

if numel(cfg.methods) ~= numel(cfg.out_paths) || numel(cfg.methods) ~= numel(cfg.run_3d_en)
  error('cfg.methods, cfg.out_paths and cfg.run_3d_en must be the same length.');
end
if numel(unique(cfg.out_paths)) ~= numel(cfg.out_paths)
  error('Each 3D product needs its own out_path.');
end
clash = intersect(lower(cfg.out_paths),{'standard','mvdr','music','mvdr_robust','standardphase'});
if ~isempty(clash)
  error(['out_path ''%s'' is a bare method name and would overwrite the posted 2D ' ...
    'product in CSARP_%s. Give it a distinct name.'], clash{1}, clash{1});
end
if cfg.shared.Nsv <= 1
  error('cfg.shared.Nsv must be greater than 1, or the outputs have no Tomo cube.');
end
products = struct('method',cfg.methods(logical(cfg.run_3d_en)), ...
  'out_path',cfg.out_paths(logical(cfg.run_3d_en)));
run_mvdr = any(strcmpi({products.method},'mvdr'));

%% Compile the job binary once, up front
% A batch only recompiles the shared binary when one of its dependencies is
% newer than the binary. A binary compiled earlier without
% delay_doppler_task (for example by a sar run after pulling opr_ndh) is
% therefore reused as-is, and every delay-Doppler task fails with
% "Undefined function 'delay_doppler_task'". One forced compile, with the
% task in the list, prevents that; batches built afterwards find the binary
% up to date and do not compile again. It is needed once per run, not once
% per call, so callers looping over spreadsheets pass compile_first only on
% the first.
cluster_type = '';
if isfield(param_override.cluster,'type') && ~isempty(param_override.cluster.type)
  cluster_type = param_override.cluster.type;
end
compile_first = ~isfield(cfg,'compile_first') || isempty(cfg.compile_first) || cfg.compile_first;
if compile_first && strcmpi(cfg.dd_mode,'cluster') && cfg.run_delay_doppler_en ...
    && any(strcmpi(cluster_type,{'slurm','torque'}))
  fprintf('Compiling the cluster job binary with delay_doppler_task included (%s)\n', datestr(now));
  cluster_compile({'delay_doppler_task.m','array_task.m','array_combine_task.m'}, ...
    param_override.cluster.hidden_depend_funs,1,struct('cluster',param_override.cluster));
end

ctrl_chain = {};

for param_idx = 1:length(params)
  param = params(param_idx);
  if ~opr_generic_en(param)
    continue;
  end

  %% Standard posting grid for this segment
  if ~isempty(cfg.dline)
    std_dline = cfg.dline;
  elseif isfield(param.array,'dline') && ~isempty(param.array.dline)
    std_dline = param.array.dline;
  else
    % Same default array.m applies when dline is left blank
    line_rng = -5:5;
    if isfield(param.array,'line_rng') && ~isempty(param.array.line_rng)
      line_rng = param.array.line_rng;
    end
    std_dline = round(length(-max(line_rng):max(line_rng))/2);
  end

  %% Point every reader at the chosen SAR product
  param.sar.out_path = cfg.sar_out_path;
  param.sar.coord_path = cfg.sar_out_path;
  param.sar.sar_type = cfg.sar_type;
  mparam = merge_structs(param,param_override);

  sar_coord_fn = fullfile(opr_filename_out(mparam,cfg.sar_out_path,''),'sar_coord.mat');
  if ~exist(sar_coord_fn,'file')
    error('%s: no SAR coordinate file at %s. Run sar with out_path ''%s'' first.', ...
      param.day_seg, sar_coord_fn, cfg.sar_out_path);
  end

  imgs = cfg.shared.imgs;
  if ischar(imgs) && strcmpi(imgs,'sar')
    % Full array: every channel the SAR step processed
    imgs = param.sar.imgs;
  elseif isempty(imgs)
    imgs = param.array.imgs;
  end

  %% MVDR covariance support must be able to invert
  if run_mvdr
    K = numel(cfg.shared.DCM.bin_rng)*numel(cfg.shared.DCM.line_rng);
    for img = 1:length(imgs)
      img_def = imgs{img};
      if iscell(img_def)
        img_def = img_def{1};
      end
      Nc = size(img_def,1);
      if K < 2*Nc && cfg.shared.diag_load == 0
        error(['%s img %d: the DCM support gives %d snapshots for %d channels. MVDR ' ...
          'needs at least %d, or a nonzero diag_load, or the covariance is rank ' ...
          'deficient and the output goes negative.'], param.day_seg, img, K, Nc, 2*Nc);
      end
    end
  end

  %% Do not silently overwrite existing 3D frames
  % rerun_only skips this: array.m itself leaves finished frames alone then
  frames = frames_load(mparam);
  frms = frames_param_cmd_frms(mparam,frames);
  if ~cfg.overwrite_en && ~rerun_only
    for prod_idx = 1:length(products)
      out_dir = opr_filename_out(mparam,products(prod_idx).out_path,'');
      for frm = frms
        existing = dir(fullfile(out_dir,sprintf('Data_img_*_%s_%03d.mat',param.day_seg,frm)));
        if ~isempty(existing)
          error(['%s frame %03d already exists in CSARP_%s. Set overwrite_en = true ' ...
            'to replace it, or cluster.rerun_only = true to fill in only missing frames.'], ...
            param.day_seg, frm, products(prod_idx).out_path);
        end
      end
    end
  end

  fprintf('\n==== %s: CSARP_%s (%s), dline %d, %d frames, delay-Doppler %s\n', param.day_seg, ...
    cfg.sar_out_path, cfg.sar_type, std_dline, length(frms), cfg.dd_mode);

  %% Delay-Doppler product
  if cfg.run_delay_doppler_en
    dd_param = param;
    dd_param.array.dline = std_dline;
    dd_param.delay_doppler = cfg.dd;
    if ~isfield(cfg.dd,'imgs') || isempty(cfg.dd.imgs)
      dd_param.delay_doppler.imgs = param.sar.imgs;
    end
    dd_param.delay_doppler.grid = 'sar_coord';
    dd_param.delay_doppler.sar_coord_path = cfg.sar_out_path;
    dd_param.delay_doppler.dline = std_dline;
    if strcmpi(cfg.dd_mode,'cluster')
      dd_chain = delay_doppler_batch(dd_param,param_override);
      if ~isempty(dd_chain)
        ctrl_chain{end+1} = dd_chain; %#ok<AGROW>
      end
    else
      delay_doppler(dd_param,param_override);
    end
  end

  %% The three 3D products
  for prod_idx = 1:length(products)
    tomo_param = param;
    tomo_param.array.imgs          = imgs;
    tomo_param.array.bin_rng       = cfg.shared.bin_rng;
    tomo_param.array.line_rng      = cfg.shared.line_rng;
    tomo_param.array.dbin          = cfg.shared.dbin;
    tomo_param.array.dline         = std_dline;
    tomo_param.array.Nsv           = cfg.shared.Nsv;
    tomo_param.array.tomo_en       = cfg.shared.tomo_en;
    tomo_param.array.Nsrc          = cfg.shared.Nsrc;
    tomo_param.array.sv_model      = cfg.shared.sv_model;
    tomo_param.array.sv_dielectric = cfg.shared.sv_dielectric;
    tomo_param.array.window        = cfg.shared.window;
    tomo_param.array.DCM           = cfg.shared.DCM;
    tomo_param.array.diag_load     = cfg.shared.diag_load;
    tomo_param.array.in_path       = cfg.sar_out_path;
    tomo_param.array.sar_type      = cfg.sar_type;
    % The only two fields that differ between the runs
    tomo_param.array.method        = products(prod_idx).method;
    tomo_param.array.out_path      = products(prod_idx).out_path;

    fprintf('  Queue CSARP_%s (%s)\n', products(prod_idx).out_path, products(prod_idx).method);
    ctrl_chain{end+1} = array(tomo_param,param_override); %#ok<AGROW>
  end
end

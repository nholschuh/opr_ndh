function ctrl_chain = tomo_doppler_collate(params,cfg,param_override)
% ctrl_chain = tomo_doppler_collate(params,cfg,param_override)
%
% Collates a set built by delay_doppler_tomo: tomo.collate on each of the
% three 3D products (standard, MVDR, MUSIC) and delay_doppler_collate on
% the delay-Doppler product, for every enabled segment and listed frame.
% run_tomo_doppler_frames_collate calls this.
%
% For each segment, before anything is queued:
%  1. The 2D surface and bottom layers are loaded for every frame each
%     task will read (the frame and its neighbours, as
%     tomo.track_surface does). tomo.track_surface errors out without
%     both, so a missing layer stops the run here instead of on a node.
%  2. Optionally, the REMA/surface DEM tiles for the listed frames are
%     fetched serially (see run_music3D_collate_ThwaitesGrid for why).
%
% Then for each 3D product:
%  - param.array.imgs is taken from the product's own param_array, not
%    the spreadsheet. The set was built with every channel in sar.imgs,
%    and tomo.fuse_images reads param.array.imgs to find each image's
%    waveform; tomo.collate reads only Nsv and tomo_en from the file.
%  - param.array.method is set to the product's method name. tomo.fuse_images
%    and tomo.add_dem_icemask only handle a char method.
%  - tomo_collate.imgs fuses every image vertically ({1,2,...}), with
%    tomo_collate.img_comb from the spreadsheet's array.img_comb, so all
%    three products and the delay-Doppler product put the seam in the same
%    place and keep identical Time axes.
%  - The fused cube goes to Data_YYYYMMDD_SS_FFF.mat in the product's own
%    directory, and surfData to the product's own surf_out_path.
%
% The batches are built by tomo_collate_batch, not tomo.collate: upstream
% tomo.collate stops on standard and MVDR products (it only sizes MUSIC and
% MLE, and its warning for anything else errors in newer MATLAB) and breaks
% in rerun_only mode. The tasks are upstream's tomo_collate_task either way.
% Frames whose outputs exist are also dropped here in rerun_only mode.
%
% INPUTS
% =========================================================================
% params: parameter spreadsheet struct array, segments enabled through
%   cmd.generic and frames in cmd.frms (see select_day_seg_frms)
% cfg: settings struct built in the run script
%   .products: struct array with .method, .out_path (3D product
%     directory) and .surf_out_path (its surfData directory)
%   .run_3d_en: logical per product
%   .run_dd_en: run delay_doppler_collate
%   .layer_params: opsLoadLayers struct array, surface then bottom; used
%     by both collates
%   .tomo_collate: tomo.collate settings shared by the three products;
%     in_path, surf_out_path, imgs and layer_params are set here
%   .dd_collate: delay_doppler_collate settings; layer_params is set here
%   .check_layers_en, .prefetch_dem_en: steps 1 and 2 above
%   .compile_first: force one job-binary compile with both collate tasks
%     before any batch is built (slurm/torque only). Default true.
% param_override: standard override struct, usually carrying .cluster
%
% ctrl_chain: cell array of chains, one per product per segment and one
%   per delay-Doppler segment, so they all run in parallel
%
% Author: Nick Holschuh
%
% See also: run_tomo_doppler_frames_collate, tomo_doppler_collate_check,
%   tomo_collate_batch, delay_doppler_collate, tomo.collate, delay_doppler_tomo

%% Input checks
% =========================================================================
global gRadar gdem;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end
physical_constants; % WGS84

% Both collate tasks go into every compile of the shared job binary
hidden = {};
if isfield(param_override,'cluster') && isfield(param_override.cluster,'hidden_depend_funs') ...
    && iscell(param_override.cluster.hidden_depend_funs)
  hidden = param_override.cluster.hidden_depend_funs;
end
for task_fn = {'tomo_collate_task.m','delay_doppler_collate_task.m'}
  if ~any(cellfun(@(h) iscell(h) && strcmp(h{1},task_fn{1}),hidden))
    hidden{end+1} = {task_fn{1} 2}; %#ok<AGROW>
  end
end
param_override.cluster.hidden_depend_funs = hidden;

rerun_only = isfield(param_override.cluster,'rerun_only') ...
  && ~isempty(param_override.cluster.rerun_only) && param_override.cluster.rerun_only;

products = cfg.products(logical(cfg.run_3d_en));
for flag = {'fuse_images_flag','add_icemask_surfacedem_flag','create_surfData_flag'}
  if ~isfield(cfg.tomo_collate,flag{1}) || isempty(cfg.tomo_collate.(flag{1}))
    cfg.tomo_collate.(flag{1}) = true;
  end
end
if numel(unique({products.surf_out_path})) ~= numel(products)
  error('Each 3D product needs its own surf_out_path, or their surfData files overwrite each other.');
end

%% Compile the job binary once, up front
% A batch only recompiles when a dependency is newer than the binary, so a
% binary built before delay_doppler_collate_task existed would be reused
% without it. See delay_doppler_tomo.
cluster_type = '';
if isfield(param_override.cluster,'type') && ~isempty(param_override.cluster.type)
  cluster_type = param_override.cluster.type;
end
compile_first = ~isfield(cfg,'compile_first') || isempty(cfg.compile_first) || cfg.compile_first;
if compile_first && any(strcmpi(cluster_type,{'slurm','torque'}))
  fprintf('Compiling the cluster job binary with both collate tasks included (%s)\n', datestr(now));
  cluster_compile({'tomo_collate_task.m','delay_doppler_collate_task.m'}, ...
    param_override.cluster.hidden_depend_funs,1,struct('cluster',param_override.cluster));
end

ctrl_chain = {};

for param_idx = 1:length(params)
  param = params(param_idx);
  if ~opr_generic_en(param)
    continue;
  end
  mparam = merge_structs(param,param_override);
  frames = frames_load(mparam);
  frms = frames_param_cmd_frms(mparam,frames);
  Nfrms = length(frames.frame_idxs);
  fprintf('\n==== %s: %d frames (%s)\n', param.day_seg, length(frms), datestr(now));

  %% 1. Layers every task will read
  if cfg.check_layers_en
    for frm = frms
      lparam = mparam;
      lparam.cmd.frms = max(1,frm-1) : min(Nfrms,frm+1);
      try
        layers = opsLoadLayers(lparam,cfg.layer_params);
      catch ME
        error('%s_%03d: could not load the surface/bottom layers for frames %s (%s).', ...
          param.day_seg, frm, mat2str(lparam.cmd.frms), ME.message);
      end
      for lay_idx = 1:2
        % Only this frame's own span has to have picks
        in_frm = layers(lay_idx).gps_time >= frame_gps(mparam,frames,frm,1) ...
          & layers(lay_idx).gps_time <= frame_gps(mparam,frames,frm,2);
        if ~any(isfinite(layers(lay_idx).twtt(in_frm)))
          error('%s_%03d: layer "%s" has no finite twtt in this frame.', param.day_seg, frm, ...
            cfg.layer_params(lay_idx).name);
        end
      end
    end
    fprintf('  surface and bottom layers present for frames %s\n', mat2str(frms));
  end

  %% 2. Surface DEM tiles for the listed frames, serially
  if cfg.prefetch_dem_en && ~isempty(products)
    if isempty(gdem) || ~isa(gdem,'dem_class') || ~isvalid(gdem)
      gdem = dem_class(mparam,10);
    end
    gdem.set_res(10);
    records = records_load(mparam);
    for frm = frms
      recs = frames.frame_idxs(frm) : frame_last_rec(frames,frm,length(records.lat));
      dec = recs(round(linspace(1,length(recs),min(length(recs),500))));
      [latb,lonb] = bufferm(records.lat(dec),records.lon(dec), ...
        cfg.tomo_collate.dem_guard/WGS84.semimajor*180/pi);
      fprintf('  pre-fetching surface DEM tiles for %s_%03d (%s)\n', param.day_seg, frm, datestr(now));
      gdem.set_vector(latb,lonb,sprintf('prefetch:%s_%03d',param.day_seg,frm));
      gdem.get_vector_mosaic(100);
    end
  end

  %% 3. tomo.collate on each 3D product
  for prod_idx = 1:length(products)
    prod = products(prod_idx);
    in_dir = opr_filename_out(mparam,prod.out_path,'');
    surf_dir = opr_filename_out(mparam,prod.surf_out_path,'');

    % Settings the product was actually made with
    first_fn = '';
    for frm = frms
      fn = fullfile(in_dir,sprintf('Data_img_01_%s_%03d.mat',param.day_seg,frm));
      if exist(fn,'file')
        first_fn = fn;
        break;
      end
    end
    if isempty(first_fn)
      warning('%s: no Data_img_01 files in %s for the listed frames, skipping CSARP_%s.', ...
        param.day_seg, in_dir, prod.out_path);
      continue;
    end
    A = load(first_fn,'param_array');
    if ~A.param_array.array.tomo_en
      error('%s was made with tomo_en off, so it has no Tomo cube to collate.', first_fn);
    end
    Nimg = length(A.param_array.array.imgs);

    tc = cfg.tomo_collate;
    tc.in_path = prod.out_path;
    tc.out_path = prod.out_path;
    tc.surf_out_path = prod.surf_out_path;
    tc.imgs = num2cell(1:Nimg);
    tc.layer_params = cfg.layer_params;
    if ~isfield(tc,'img_comb') || isempty(tc.img_comb)
      tc.img_comb = mparam.array.img_comb;
    end
    if numel(tc.img_comb) < 3*(Nimg-1)
      error(['%s: CSARP_%s has %d images but img_comb has %d values (%d needed). The 3D set ' ...
        'used sar.imgs, which can have more images than array.imgs; set cfg.tomo_collate.img_comb.'], ...
        param.day_seg, prod.out_path, Nimg, numel(tc.img_comb), 3*(Nimg-1));
    end
    if isfield(tc,'fuse_columns') && numel(tc.fuse_columns) ~= Nimg
      tc.fuse_columns = cell(1,Nimg);
    end

    % Frames with input, minus finished ones in rerun_only mode
    todo = [];
    for frm = frms
      if ~all(arrayfun(@(img) exist(fullfile(in_dir,sprintf('Data_img_%02d_%s_%03d.mat',img,param.day_seg,frm)),'file')==2,1:Nimg))
        warning('%s_%03d: CSARP_%s is missing an image file, skipped.', param.day_seg, frm, prod.out_path);
        continue;
      end
      done_fns = {};
      if tc.fuse_images_flag || tc.add_icemask_surfacedem_flag
        done_fns{end+1} = fullfile(in_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm)); %#ok<AGROW>
      end
      if tc.create_surfData_flag
        done_fns{end+1} = fullfile(surf_dir,sprintf('Data_%s_%03d.mat',param.day_seg,frm)); %#ok<AGROW>
      end
      if rerun_only && all(cellfun(@(fn) exist(fn,'file')==2,done_fns))
        fprintf('  CSARP_%s %s_%03d exists [rerun_only skipping]\n', prod.out_path, param.day_seg, frm);
        continue;
      end
      todo(end+1) = frm; %#ok<AGROW>
    end
    if isempty(todo)
      continue;
    end

    cparam = param;
    cparam.cmd.frms = todo;
    cparam.array.imgs = A.param_array.array.imgs;
    cparam.array.method = prod.method;
    po = param_override;
    po.cluster.rerun_only = false;
    po.tomo_collate = tc;
    fprintf('  Queue tomo_collate_batch CSARP_%s -> CSARP_%s, %d images, frames %s\n', ...
      prod.out_path, prod.surf_out_path, Nimg, mat2str(todo));
    ctrl_chain{end+1} = tomo_collate_batch(cparam,po); %#ok<AGROW>
  end

  %% 4. delay_doppler_collate
  if cfg.run_dd_en
    dparam = param;
    dparam.cmd.frms = frms;
    dparam.dd_collate = cfg.dd_collate;
    dparam.dd_collate.layer_params = cfg.layer_params;
    chain = delay_doppler_collate(dparam,param_override);
    if ~isempty(chain)
      ctrl_chain{end+1} = chain; %#ok<AGROW>
    end
  end
end

end

function rec = frame_last_rec(frames,frm,Nrec)
if frm < length(frames.frame_idxs)
  rec = frames.frame_idxs(frm+1)-1;
else
  rec = Nrec;
end
end

function t = frame_gps(param,frames,frm,which_end)
% GPS time of the first (which_end 1) or last (2) record of a frame
persistent gps_cache day_seg_cache;
if isempty(day_seg_cache) || ~strcmp(day_seg_cache,param.day_seg)
  records = records_load(param,'gps_time');
  gps_cache = records.gps_time;
  day_seg_cache = param.day_seg;
end
if which_end == 1
  t = gps_cache(frames.frame_idxs(frm));
else
  t = gps_cache(frame_last_rec(frames,frm,length(gps_cache)));
end
end

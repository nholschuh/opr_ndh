function ctrl_chain = delay_doppler_batch(param,param_override)
% ctrl_chain = delay_doppler_batch(param,param_override)
%
% Builds a cluster batch that produces the delay-Doppler product for one
% segment, with one task per frame in param.cmd.frms. Pass the returned
% chain to cluster_run, alone or alongside other chains.
%
% The geometry is worked out once here with delay_doppler in plan_only
% mode, which reads the records, frames, and SAR coordinate files but no
% radar data. That same plan sizes each task's memory and time request, so
% every task is sized for the frame it actually processes.
%
% Memory and time estimates are deliberately generous first guesses. Scale
% them with param.cluster.mem_mult and param.cluster.cpu_time_mult if the
% scheduler kills tasks or the queue wait is long.
%
% Supports param.cluster.rerun_only: frames whose output already exists and
% is not marked for deletion are skipped.
%
% param: parameter spreadsheet struct for one segment, with
%   param.delay_doppler set as for delay_doppler
% param_override: standard override struct, merged with gRadar
%
% ctrl_chain: a single-stage chain, {ctrl}, or {} if no frame has output
%   positions
%
% Author: Nick Holschuh
%
% See also: delay_doppler_task, delay_doppler, delay_doppler_tomo

%% Input checks
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end
param = merge_structs(param,param_override);

out_path = 'delay_doppler';
if isfield(param,'delay_doppler') && isfield(param.delay_doppler,'out_path') ...
    && ~isempty(param.delay_doppler.out_path)
  out_path = param.delay_doppler.out_path;
end

%% Plan the work without loading data
% =========================================================================
plan_param = param;
plan_param.delay_doppler.plan_only = true;
plan = delay_doppler(plan_param,struct());

if isempty(plan.frms)
  warning('%s: no frame has output positions, so no delay-Doppler tasks were made.', param.day_seg);
  ctrl_chain = {};
  return;
end

%% Cluster batch
% =========================================================================
ctrl = cluster_new_batch(param);
cluster_compile({'delay_doppler_task.m'},ctrl.cluster.hidden_depend_funs,ctrl.cluster.force_compile,ctrl);

out_fn_dir = opr_filename_out(param,out_path,'');

sparam = [];
sparam.argsin{1} = param;
sparam.task_function = 'delay_doppler_task';
sparam.num_args_out = 1;

bytes_per_value = 4;
if plan.complex_en
  bytes_per_value = 8;
end

for frm_idx = 1:length(plan.frms)
  frm = plan.frms(frm_idx);

  dparam = [];
  dparam.argsin{1}.cmd.frms = frm;

  % Success condition: the frame file for every image
  dparam.file_success = {};
  for img = 1:plan.Nimg
    if plan.Nimg == 1
      out_fn_name = sprintf('Data_%s_%03d.mat', param.day_seg, frm);
    else
      out_fn_name = sprintf('Data_img_%02d_%s_%03d.mat', img, param.day_seg, frm);
    end
    out_fn = fullfile(out_fn_dir,out_fn_name);
    dparam.file_success{end+1} = out_fn;
    if ~ctrl.cluster.rerun_only && exist(out_fn,'file')
      % Mark a previous run's output deletable, so a task that fails before
      % saving cannot be mistaken for a success
      opr_file_lock_check(out_fn,3);
    end
  end

  dparam.notes = sprintf('%s %s:%s:%s %s_%03d (%d of %d)', sparam.task_function, ...
    out_path, param.radar_name, param.season_name, param.day_seg, frm, frm_idx, length(plan.frms));

  if ctrl.cluster.rerun_only && ~cluster_file_success(dparam.file_success)
    fprintf('  Already exists [rerun_only skipping]: %s (%s)\n', dparam.notes, datestr(now));
    continue;
  end

  % Memory: the output cube, a working copy of it while the peak over
  % Doppler is taken, and one block of raw data. The raw block holds Nch
  % channels of complex doubles through load and pulse compression (about
  % three copies each), plus the combined image and its uniform resampling.
  Nx = plan.Nx(frm_idx);
  Nrec_block = plan.Nrec_block(frm_idx);
  n_blocks = ceil(Nx/plan.block_size);
  cube_bytes = plan.Nimg*plan.Nt*plan.Ndop*Nx*bytes_per_value;
  block_bytes = plan.Nt*Nrec_block*16*(3*plan.Nch + 2);
  dparam.mem = 1e9 + 2*cube_bytes + block_bytes;

  % Time: loading and pulse compression scale like qlook_task; then one
  % along-track FFT per output trace and range bin; then the resampling
  dparam.cpu_time = 60 ...
    + n_blocks*Nrec_block*plan.Nch*plan.Nt*log2(max(2,plan.Nt))*12e-8 ...
    + plan.Nimg*Nx*plan.Nt*plan.Nfft*log2(plan.Nfft)*1e-8 ...
    + plan.Nimg*n_blocks*Nrec_block*plan.Nt*1e-7;

  ctrl = cluster_new_task(ctrl,sparam,dparam,'dparam_save',0);
end

ctrl = cluster_save_dparam(ctrl);

ctrl_chain = {ctrl};

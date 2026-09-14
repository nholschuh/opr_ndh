% script run_sar_tomo_doppler_frames
%
% STEP 1 of 2. SAR processes the frames in tomo_doppler_frames_list on the
% cluster, using the sar worksheet of each season's rds parameter
% spreadsheet unchanged. The only settings forced here are the SAR output
% directory (CSARP_sar_ndh, beside rather than over CSARP_sar) and sar_type,
% taken from the list so that step 2 reads exactly what this step writes.
% Every channel in each spreadsheet's sar.imgs is SAR processed, so step 2
% can use the full array.
%
% Spreadsheet sar settings for these segments (all Antarctic rds):
%   2011_Antarctica_DC8  20111014_07  fk, sigma_x 2.5, 2 images x 5 channels
%   2012_Antarctica_DC8  20121023_04  fk, sigma_x 2.5, 1 image  x 5 channels
%   2013_Antarctica_P3   20131126_01  fk, sigma_x 2.5, 3 images x 15 channels
%   2014_Antarctica_DC8  20141115_06  fk, sigma_x 2.5, 3 images x 6 channels
%   2018_Antarctica_DC8  3 segments   fk, sigma_x 2.5, 3 images x 5 channels
% All use chunk_len 5000 and mocomp.en true.
%
% sar also writes the segment's sar_coord.mat, which the delay-Doppler
% product in step 2 uses to find the CSARP_standard trace positions.
%
% When every job has finished, run run_tomo_doppler_frames_cluster.
%
% Author: Nick Holschuh
%
% See also: tomo_doppler_frames_list, run_tomo_doppler_frames_cluster, sar

%% User Settings
% =========================================================================

[jobs,sar_out_path,sar_type] = tomo_doppler_frames_list();

% Resume partway through the list: every job before this spreadsheet is
% skipped. Leave empty to run the whole list. The list itself is unchanged,
% so step 2 still covers every frame.
start_at_param_fn = 'rds_param_2012_Antarctica_DC8.xlsx';

% array.m uses neighbouring frames' SAR chunks, when they exist, to give the
% first and last few traces of a frame their full multilook support. With
% this false only the listed frames are SAR processed and those edge traces
% use fewer snapshots. Set true to also SAR the frame on either side.
include_neighbour_frames = false;

param_override = [];
param_override.cluster.type = 'slurm';
% param_override.cluster.type = 'debug';     % run here, for testing one frame
param_override.cluster.rerun_only = true;    % keep sar_coord.mat and finished chunks
param_override.cluster.max_jobs_active = 96;
param_override.cluster.cpu_time_mult  = 2;
param_override.cluster.mem_mult  = 2;
param_override.cluster.mem_mult_mode = 'auto';
param_override.cluster.max_mem_mode = 'truncate';
param_override.cluster.max_cpu_time_mode = 'truncate';

% Submit and wait. Set false to only build and save the chain.
run_chain_en = true;

%% Automated Section
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

first_job = 1;
if ~isempty(start_at_param_fn)
  first_job = find(strcmp({jobs.param_fn},start_at_param_fn),1);
  if isempty(first_job)
    error('start_at_param_fn %s is not in tomo_doppler_frames_list.', start_at_param_fn);
  end
  fprintf('Starting at job %d of %d: %s\n', first_job, length(jobs), start_at_param_fn);
end

ctrl_chain = {};
for job_idx = first_job:length(jobs)
  params = read_param_xls(opr_filename_param(jobs(job_idx).param_fn));
  params = select_day_seg_frms(params,jobs(job_idx).day_seg_frms);

  for param_idx = 1:length(params)
    param = params(param_idx);
    if ~opr_generic_en(param)
      continue;
    end

    if include_neighbour_frames
      frames = frames_load(merge_structs(param,param_override));
      frms = param.cmd.frms;
      param.cmd.frms = intersect(unique([frms-1 frms frms+1]),1:length(frames.frame_idxs));
    end

    param.sar.out_path = sar_out_path;
    % Keep sar_coord.mat beside the SAR chunks, where step 2 looks for it
    param.sar.coord_path = sar_out_path;
    param.sar.sar_type = sar_type;

    fprintf('SAR %s frames %s -> CSARP_%s (%s)\n', param.day_seg, ...
      mat2str(param.cmd.frms), sar_out_path, sar_type);
    ctrl_chain{end+1} = sar(param,param_override); %#ok<SAGROW>
  end
end

cluster_print_chain(ctrl_chain);
[chain_fn,chain_id] = cluster_save_chain(ctrl_chain);
if run_chain_en
  ctrl_chain = cluster_run(ctrl_chain);
else
  fprintf('Chain saved (id %d): %s\nRun it later with cluster_load_chain and cluster_run.\n', chain_id, chain_fn);
end

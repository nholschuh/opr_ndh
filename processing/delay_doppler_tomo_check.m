function summary = delay_doppler_tomo_check(params,cfg,param_override)
% summary = delay_doppler_tomo_check(params,cfg,param_override)
%
% Runs tomo_set_check on every frame and image of every enabled segment,
% using the same cfg as delay_doppler_tomo. Safe to run on its own after a
% cluster chain has finished, with the same list of segments and frames.
%
% summary: struct
%   .n_checked: frame-images checked
%   .n_failed_checks: total failed checks
%   .failed: cell array naming each frame-image with a failure
%
% Author: Nick Holschuh
%
% See also: tomo_set_check, delay_doppler_tomo

global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

products = struct('method',cfg.methods(logical(cfg.run_3d_en)), ...
  'out_path',cfg.out_paths(logical(cfg.run_3d_en)));

ref_paths = cfg.check_ref_paths;
if cfg.run_delay_doppler_en
  dd_out_path = 'delay_doppler';
  if isfield(cfg.dd,'out_path') && ~isempty(cfg.dd.out_path)
    dd_out_path = cfg.dd.out_path;
  end
  ref_paths{end+1} = dd_out_path;
end

summary = struct('n_checked',0,'n_failed_checks',0,'failed',{{}});

for param_idx = 1:length(params)
  if ~opr_generic_en(params(param_idx))
    continue;
  end
  mparam = merge_structs(params(param_idx),param_override);
  frames = frames_load(mparam);
  frms = frames_param_cmd_frms(mparam,frames);

  imgs = cfg.shared.imgs;
  if isempty(imgs)
    imgs = mparam.array.imgs;
  end

  for frm = frms
    for img = 1:length(imgs)
      % Only image 1 is compared with the 2D references, which are single
      % combined images
      if img == 1
        r = tomo_set_check(mparam,products,frm,img,ref_paths);
      else
        r = tomo_set_check(mparam,products,frm,img,{});
      end
      summary.n_checked = summary.n_checked + 1;
      n_fail = sum([r.pass] == 0);
      if n_fail > 0
        summary.n_failed_checks = summary.n_failed_checks + n_fail;
        summary.failed{end+1} = sprintf('%s_%03d img %d', mparam.day_seg, frm, img);
      end
    end
  end
end

fprintf('\n==== Acceptance: %d frame-images checked, %d failed checks\n', ...
  summary.n_checked, summary.n_failed_checks);
if ~isempty(summary.failed)
  fprintf('  Failing: %s\n', strjoin(summary.failed,', '));
end

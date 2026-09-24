function results = tomo_doppler_collate_check(params,cfg,param_override)
% results = tomo_doppler_collate_check(params,cfg,param_override)
%
% Acceptance checks after tomo_doppler_collate has run, for every enabled
% segment and listed frame:
%  1. Each 3D product has its fused Data_YYYYMMDD_SS_FFF.mat and its
%     surfData file.
%  2. The fused cubes share GPS_time and Time across the products. They
%     are fused from identical grids with identical img_comb, so any
%     difference means the products or the collate settings diverged.
%  3. The delay-Doppler surface file exists and sits on the same traces
%     as the fused 3D cubes.
%  4. The delay-Doppler fused Time axis is reported against the 3D one.
%     It need not match: delay_doppler builds its fast-time axis from the
%     raw data, array from the SAR product.
%
% params, cfg, param_override: as passed to tomo_doppler_collate
%
% results: struct array with .day_seg, .frm, .check, .pass (true, false or
%   NaN when the check could not run) and .detail
%
% Author: Nick Holschuh
%
% See also: tomo_doppler_collate, tomo_set_check, delay_doppler_tomo_check

global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

products = cfg.products(logical(cfg.run_3d_en));
dd_in_path = 'delay_doppler';
dd_surf_path = 'dd_surf_ndh';
if isfield(cfg,'dd_collate') && isfield(cfg.dd_collate,'in_path') && ~isempty(cfg.dd_collate.in_path)
  dd_in_path = cfg.dd_collate.in_path;
end
if isfield(cfg,'dd_collate') && isfield(cfg.dd_collate,'surf_out_path') && ~isempty(cfg.dd_collate.surf_out_path)
  dd_surf_path = cfg.dd_collate.surf_out_path;
end

results = struct('day_seg',{},'frm',{},'check',{},'pass',{},'detail',{});

for param_idx = 1:length(params)
  param = params(param_idx);
  if ~opr_generic_en(param)
    continue;
  end
  param = merge_structs(param,param_override);
  frames = frames_load(param);
  frms = frames_param_cmd_frms(param,frames);

  for frm = frms
    res = struct('day_seg',{},'frm',{},'check',{},'pass',{},'detail',{});
    fn_name = sprintf('Data_%s_%03d.mat',param.day_seg,frm);

    %% 3D products
    ref = [];
    ref_name = '';
    for prod_idx = 1:length(products)
      prod = products(prod_idx);
      fused_fn = fullfile(opr_filename_out(param,prod.out_path,''),fn_name);
      surf_fn = fullfile(opr_filename_out(param,prod.surf_out_path,''),fn_name);
      has_fused = exist(fused_fn,'file') == 2;
      has_surf = exist(surf_fn,'file') == 2;
      res(end+1) = mkres(param,frm,sprintf('%s: fused cube exists',prod.out_path),has_fused,missing_note(has_fused,fused_fn)); %#ok<AGROW>
      res(end+1) = mkres(param,frm,sprintf('%s: surfData exists',prod.surf_out_path),has_surf,missing_note(has_surf,surf_fn)); %#ok<AGROW>
      if ~has_fused
        continue;
      end
      F = load(fused_fn,'GPS_time','Time');
      if isempty(ref)
        ref = F;
        ref_name = prod.out_path;
      else
        res(end+1) = mkres(param,frm,sprintf('%s: GPS_time == %s',prod.out_path,ref_name), ...
          isequal(F.GPS_time,ref.GPS_time),sprintf('Nx %d vs %d',numel(F.GPS_time),numel(ref.GPS_time))); %#ok<AGROW>
        res(end+1) = mkres(param,frm,sprintf('%s: Time == %s',prod.out_path,ref_name), ...
          isequal(F.Time(:),ref.Time(:)),sprintf('Nt %d vs %d',numel(F.Time),numel(ref.Time))); %#ok<AGROW>
      end
    end

    %% Delay-Doppler product
    if cfg.run_dd_en
      dd_fn = fullfile(opr_filename_out(param,dd_surf_path,''),fn_name);
      has_dd = exist(dd_fn,'file') == 2;
      res(end+1) = mkres(param,frm,sprintf('%s: surface file exists',dd_surf_path),has_dd,missing_note(has_dd,dd_fn)); %#ok<AGROW>
      if has_dd && ~isempty(ref)
        D = load(dd_fn,'GPS_time','Time');
        same_n = numel(D.GPS_time) == numel(ref.GPS_time);
        max_dt = NaN;
        if same_n
          max_dt = max(abs(D.GPS_time(:)-ref.GPS_time(:)));
        end
        res(end+1) = mkres(param,frm,sprintf('%s: on the %s traces',dd_surf_path,ref_name), ...
          same_n && max_dt < 1e-6,sprintf('Nx %d vs %d, max |dt| %.3g s',numel(D.GPS_time),numel(ref.GPS_time),max_dt)); %#ok<AGROW>
        res(end+1) = mkres(param,frm,sprintf('%s: fast time vs %s',dd_in_path,ref_name),NaN, ...
          sprintf('dt %.4g vs %.4g ns, start %.4g vs %.4g us', 1e9*(D.Time(2)-D.Time(1)), ...
          1e9*(ref.Time(2)-ref.Time(1)), 1e6*D.Time(1), 1e6*ref.Time(1))); %#ok<AGROW>
      end
    end

    fprintf('\n  %s frame %03d\n', param.day_seg, frm);
    for k = 1:length(res)
      if isnan(res(k).pass)
        verdict = 'info';
      elseif res(k).pass
        verdict = 'PASS';
      else
        verdict = 'FAIL';
      end
      fprintf('    %s  %-48s %s\n', verdict, res(k).check, res(k).detail);
    end
    results = [results res]; %#ok<AGROW>
  end
end

end

function r = mkres(param,frm,check,pass,detail)
r = struct('day_seg',param.day_seg,'frm',frm,'check',check,'pass',double(pass),'detail',detail);
end

function note = missing_note(exists,fn)
% Full path only when the file is missing, where it is worth reading
if exists
  note = '';
else
  note = ['missing: ' fn];
end
end

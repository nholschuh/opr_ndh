function params = select_day_seg_frms(params,day_seg_frms)
% params = select_day_seg_frms(params,day_seg_frms)
%
% Enables exactly the segments and frames named in a list, and disables
% every other segment.
%
% params: parameter spreadsheet struct array from read_param_xls
% day_seg_frms: cell array of strings, each either
%   'YYYYMMDD_SS'      every frame of that segment
%   'YYYYMMDD_SS_FFF'  one frame
%   A segment may appear on several lines to list several frames. If it
%   appears anywhere without a frame number, all of its frames are used.
%
% params: the same array with cmd.generic set to 1 for listed segments and
%   0 otherwise, and cmd.frms set to the listed frames (empty means all).
%   Listed segments are enabled even if cmd.notes says "do not process",
%   since naming a segment explicitly is taken as the intent.
%
% Errors if a listed segment is not in the spreadsheet, or an entry is not
% in one of the two forms, so a typo cannot silently drop work.
%
% Example:
%  params = read_param_xls(opr_filename_param('rds_param_2024_Antarctica_GroundGHOST2.xlsx'));
%  params = select_day_seg_frms(params,{'20250117_03','20250118_02_004','20250118_02_005'});
%
% Author: Nick Holschuh
%
% See also: run_delay_doppler_tomo_cluster, opr_set_params

if ischar(day_seg_frms)
  day_seg_frms = {day_seg_frms};
end

seg_list = {};
seg_frms = {};
seg_all = false(0);
for k = 1:numel(day_seg_frms)
  entry = strtrim(day_seg_frms{k});
  % Two separate patterns: MATLAB's regexp does not return a token captured
  % inside an optional non-capturing group, so one combined pattern would
  % silently read every frame entry as a whole segment
  tok = regexp(entry,'^(\d{8}_\d{2})_(\d{3})$','tokens','once');
  if isempty(tok)
    tok = regexp(entry,'^(\d{8}_\d{2})$','tokens','once');
  end
  if isempty(tok)
    error('select_day_seg_frms: "%s" is not YYYYMMDD_SS or YYYYMMDD_SS_FFF.', entry);
  end
  seg = tok{1};
  idx = find(strcmp(seg_list,seg),1);
  if isempty(idx)
    seg_list{end+1} = seg; %#ok<AGROW>
    seg_frms{end+1} = []; %#ok<AGROW>
    seg_all(end+1) = false; %#ok<AGROW>
    idx = numel(seg_list);
  end
  if numel(tok) < 2 || isempty(tok{2})
    seg_all(idx) = true;
  else
    seg_frms{idx}(end+1) = str2double(tok{2});
  end
end

missing = setdiff(seg_list,{params.day_seg});
if ~isempty(missing)
  error('select_day_seg_frms: not in this parameter spreadsheet: %s', strjoin(missing,', '));
end

for param_idx = 1:numel(params)
  idx = find(strcmp(seg_list,params(param_idx).day_seg),1);
  if isempty(idx)
    params(param_idx).cmd.generic = 0;
  else
    params(param_idx).cmd.generic = 1;
    if seg_all(idx)
      params(param_idx).cmd.frms = [];
    else
      params(param_idx).cmd.frms = unique(seg_frms{idx});
    end
  end
end

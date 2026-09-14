function fn = opr_filename_param(param,fn)
% fn = opr_filename_param(param,fn)
%
% opr_ndh override of the toolbox function of the same name. Identical,
% except that it looks for the spreadsheet in one or more personal
% directories before the default one.
%
% Resolution order for a relative filename:
%  1. Each directory in param.param_path_ndh (normally gRadar.param_path_ndh),
%     in order, if the file exists there.
%  2. param.param_path, exactly as the toolbox does, whether or not the file
%     exists there, so downstream error messages are unchanged.
% Absolute filenames are returned untouched, as before.
%
% A spreadsheet in a personal directory replaces the default one entirely;
% rows are not merged. Only the spreadsheets you have changed need to be
% there. The first time each personal spreadsheet is used in a session, a
% line naming it is printed, so it is always visible which copy a run read.
%
% param: control structure, merged over gRadar
%  .param_path: default spreadsheet directory
%  .param_path_ndh: personal directory as a char, or several as a cell
%    array searched in order. Empty or absent reproduces the toolbox exactly.
%    Set it in the startup profile (see STARTUP_SETUP.md).
% fn: spreadsheet filename, absolute or relative
%
% Legacy format:
% param: The "fn" from above.
% fn: NOT USED
%
% Not covered: tools that list gRadar.param_path directly instead of
% resolving a filename (the opr_control season list and
% wiki_dataset_pages.m) still see only the default directory.
%
% Based on opr/matlab/opr_support/opr_filename_param.m (Kyle Purdon, John
% Paden). If the toolbox version changes, reconcile the default section.
%
% Author: Nick Holschuh
%
% See also: read_param_xls, opr_filename_out, opr_filename_support

if ischar(param)
  % Legacy format
  fn = param;
  param = [];
end

global gRadar;
param = merge_structs(gRadar,param);

if ~exist('fn','var')
  fn = [];
end

if ~isempty(fn) && (fn(1) == filesep || (ispc && (~isempty(strfind(fn,':\')) || ~isempty(strfind(fn,':/')))))
  % This is already an absolute path
  return
end

%% Personal spreadsheet directories first
if ~isempty(fn) && isfield(param,'param_path_ndh') && ~isempty(param.param_path_ndh)
  ndh_dirs = param.param_path_ndh;
  if ischar(ndh_dirs)
    ndh_dirs = {ndh_dirs};
  end
  for dir_idx = 1:numel(ndh_dirs)
    if isempty(ndh_dirs{dir_idx})
      continue;
    end
    ndh_fn = fullfile(ndh_dirs{dir_idx}, fn);
    ndh_fn(ndh_fn == '/' | ndh_fn == '\') = filesep;
    if exist(ndh_fn,'file') == 2
      report_personal_spreadsheet(ndh_fn);
      fn = ndh_fn;
      return
    end
  end
end

%% Default directory, as the toolbox does
if ~isfield(param,'param_path')
  error('param_path is missing from global variable gRadar');
end
fn = fullfile(param.param_path, fn);

fn(fn == '/' | fn == '\') = filesep;

end

function report_personal_spreadsheet(fn)
% Print once per file per MATLAB session
persistent reported;
if isempty(reported)
  reported = {};
end
if ~any(strcmp(reported,fn))
  fprintf('opr_filename_param: using personal spreadsheet %s\n', fn);
  reported{end+1} = fn;
end
end

function [jobs,sar_out_path,sar_type] = tomo_doppler_frames_list()
% [jobs,sar_out_path,sar_type] = tomo_doppler_frames_list()
%
% The frames to SAR process and then turn into delay-Doppler and 3D
% products. Both run_sar_tomo_doppler_frames and
% run_tomo_doppler_frames_cluster read this list, so the SAR step and the
% product step always cover the same frames and use the same SAR product.
%
% Each entry of jobs names one rds parameter spreadsheet and the frames in
% it, as 'YYYYMMDD_SS_FFF' (or 'YYYYMMDD_SS' for a whole segment).
%
% Author: Nick Holschuh
%
% See also: run_sar_tomo_doppler_frames, run_tomo_doppler_frames_cluster,
%   select_day_seg_frms

% SAR product written by the SAR step and read by the product step.
% A dedicated directory keeps these runs from overwriting CSARP_sar.
sar_out_path = 'sar_ndh';
sar_type     = 'fk';

jobs = [];

jobs(end+1).param_fn = 'rds_param_2011_Antarctica_DC8.xlsx';
jobs(end).day_seg_frms = {'20111014_07_022'};

jobs(end+1).param_fn = 'rds_param_2012_Antarctica_DC8.xlsx';
jobs(end).day_seg_frms = {'20121023_04_077'};

jobs(end+1).param_fn = 'rds_param_2013_Antarctica_P3.xlsx';
jobs(end).day_seg_frms = {'20131126_01_029','20131126_01_031','20131126_01_042','20131126_01_047'};

jobs(end+1).param_fn = 'rds_param_2014_Antarctica_DC8.xlsx';
jobs(end).day_seg_frms = {'20141115_06_006'};

jobs(end+1).param_fn = 'rds_param_2018_Antarctica_DC8.xlsx';
jobs(end).day_seg_frms = {'20181010_02_006','20181018_01_008','20181018_01_026','20181115_01_024'};

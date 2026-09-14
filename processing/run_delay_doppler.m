% script run_delay_doppler
%
% Runs delay_doppler on the segments enabled in the parameter spreadsheet.
%
% The product is posted on the same along-track grid as the array output,
% so run along_track_sampling first to see what that grid is and how much
% angle span the raw sampling of the season actually supports.
%
% Author: Nick Holschuh
%
% See also: delay_doppler, along_track_sampling

%% User Settings
% =========================================================================

params = read_param_xls(opr_filename_param('rds_param_2022_Antarctica_GroundGHOST.xlsx'));

params = opr_set_params(params,'cmd.generic',0);
params = opr_set_params(params,'cmd.generic',1,'day_seg','20230107_01');
params = opr_set_params(params,'cmd.frms',[18 19]);

param_override = [];

% Images to process. Receive channels within an image are coherently
% combined before the transform, so each image gives one output file.
param_override.delay_doppler.imgs = {[1 1]};

% Output directory name. This becomes CSARP_delay_doppler.
param_override.delay_doppler.out_path = 'delay_doppler';

% Output positions per block. Memory scales with this times Nt times the
% number of Doppler bins kept. Drop it if the aperture is long.
param_override.delay_doppler.block_size = 200;

% Leave empty to post at param.sar.sigma_x*param.array.dline, which is what
% the standard product uses.
param_override.delay_doppler.dx_out = [];

% Leave empty for the same aperture length sar.m would use at this
% frequency and sigma_x.
param_override.delay_doppler.Lsar = [];

% Leave empty to sample the aperture at the median raw record spacing,
% which keeps all of the along-track bandwidth.
param_override.delay_doppler.dx_dop = [];

% Transform length. Empty gives the next power of two above the aperture.
param_override.delay_doppler.Nfft = [];

% Taper across the aperture. @boxcar for none.
param_override.delay_doppler.st_wind = @hanning;

% Angle range to store, in degrees off nadir in air. Narrow this to cut
% file size; bins outside the mappable range are dropped regardless.
param_override.delay_doppler.theta_rng = [-90 90];

% Store power. Set true for complex voltage at four times the size.
param_override.delay_doppler.complex_en = false;

% Software presums at load time. Leave at 1 to use the full raw rate.
param_override.delay_doppler.presums = 1;

param_override.delay_doppler.motion_comp = true;

% Skip records flagged bad. Add 2 to also skip stationary records.
param_override.delay_doppler.bit_mask = 1;

%% Automated Section
% =========================================================================
global gRadar;
if exist('param_override','var')
  param_override = merge_structs(gRadar,param_override);
else
  param_override = gRadar;
end

for param_idx = 1:length(params)
  param = params(param_idx);

  if ~opr_generic_en(param)
    continue;
  end

  delay_doppler(param,param_override);
end

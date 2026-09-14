function success = delay_doppler_task(param)
% success = delay_doppler_task(param)
%
% Cluster task for the delay-Doppler product. Processes the frames in
% param.cmd.frms, which delay_doppler_batch sets to a single frame per
% task. param arrives already merged with gRadar, so nothing further is
% overridden here.
%
% Must be compiled into the cluster job binary. delay_doppler_tomo adds it
% to param.cluster.hidden_depend_funs automatically; if delay_doppler_batch
% is called some other way, add {'delay_doppler_task.m' 2} to that list, or
% a later batch that recompiles the shared binary will drop it.
%
% Author: Nick Holschuh
%
% See also: delay_doppler_batch, delay_doppler

delay_doppler(param,struct());

success = true;

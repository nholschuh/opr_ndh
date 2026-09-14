function success = delay_doppler_task(param)
% success = delay_doppler_task(param)
%
% Cluster task for the delay-Doppler product. Processes the frames in
% param.cmd.frms, which delay_doppler_batch sets to a single frame per
% task. param arrives already merged with gRadar, so nothing further is
% overridden here.
%
% Must be compiled into the cluster job binary. The KU startup lists it in
% gRadar.cluster.hidden_depend_funs, and delay_doppler_tomo forces one
% compile with it included before building slurm or torque batches. If
% delay_doppler_batch is called some other way on a binary compiled without
% it, force a compile first:
%   cluster_compile({'delay_doppler_task.m','array_task.m','array_combine_task.m'},[],1)
%
% Author: Nick Holschuh
%
% See also: delay_doppler_batch, delay_doppler

delay_doppler(param,struct());

success = true;

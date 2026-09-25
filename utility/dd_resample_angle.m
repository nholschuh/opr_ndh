function Doppler = dd_resample_angle(Doppler,Nsv)
% Doppler = dd_resample_angle(Doppler,Nsv)
%
% Resamples the Doppler axis of a delay-Doppler cube onto the Nsv look
% directions the array products use, so the delay-Doppler and MUSIC /
% MVDR / standard 3D products share one angle grid (for Nsv = 64, 64 bins
% from -90 to +86.4 deg).
%
% array_proc_sv spaces its steering vectors uniformly in sin(theta):
%   sin(theta) = (2/Nsv)*k,  k = -floor(Nsv/2) : floor((Nsv-1)/2)
% The Doppler bins are uniform in sin(theta) too (sin(theta) = fx*lambda/2),
% so each output bin takes the Doppler bins whose sin(theta) falls within
% +/-1/Nsv of its centre, and their LINEAR POWER is averaged. Averaging,
% rather than sampling the nearest bin, keeps the energy in each angle bin
% and does not alias the much finer native axis. Complex cubes
% (complex_en) are converted to power first, since averaging voltage
% across angle would cancel it.
%
% The angle axis is the same numbers as Tomo.theta but a different
% direction: along-track squint (positive forward), not cross-track DOA.
%
% Doppler: struct from delay_doppler (.img Nt by Ndop by Nx, .theta,
%   .theta_ice, .fx as Ndop vectors)
% Nsv: number of output look directions. Empty or 0 returns Doppler
%   unchanged.
%
% Doppler: .img becomes Nt by Nsv by Nx power; .theta, .theta_ice, .fx
%   are Nsv by 1 on the new grid. Output bins with no Doppler bin inside
%   them (beyond the product's theta_rng) are NaN. Added fields:
%   .Nsv, .Ndop_native, .theta_native, and .Nbins_averaged (Nsv by 1,
%   native bins in each output bin).
%
% Author: Nick Holschuh
%
% See also: delay_doppler_fuse, delay_doppler, array_proc_sv

if isempty(Nsv) || Nsv == 0
  return;
end

sin_native = sind(Doppler.theta(:));
k = (-floor(Nsv/2) : floor((Nsv-1)/2)).';
sin_out = 2*k/Nsv;

% Output bin of every native bin; bins that land outside [-1, 1-2/Nsv]
% by more than half a bin are dropped
out_idx = round(sin_native*Nsv/2) + floor(Nsv/2) + 1;
ok = out_idx >= 1 & out_idx <= Nsv & isfinite(sin_native);
Ndop = numel(sin_native);
W = sparse(out_idx(ok),find(ok),1,Nsv,Ndop);
Nbins = full(sum(W,2));
W = spdiags(1./max(Nbins,1),0,Nsv,Nsv)*W;     % rows average their native bins

[Nt,~,Nx] = size(Doppler.img);
img_out = nan(Nt,Nsv,Nx,'single');
empty = Nbins == 0;
for rline = 1:Nx
  P = Doppler.img(:,:,rline);
  if ~isreal(P)
    P = abs(P).^2;
  end
  P = double(P)*W.';                            % Nt by Nsv
  P(:,empty) = NaN;
  img_out(:,:,rline) = P;
end

% lambda from the native axis, sin(theta) = fx*lambda/2
nz = Doppler.fx(:) ~= 0 & isfinite(sin_native);
lambda = median(2*sin_native(nz)./Doppler.fx(nz));
er_ice = median(sin_native(nz).^2./sind(Doppler.theta_ice(nz)).^2);

Doppler.theta_native = Doppler.theta(:);
Doppler.Ndop_native = Ndop;
Doppler.img = img_out;
Doppler.theta = asind(sin_out);
Doppler.theta_ice = asind(sin_out/sqrt(er_ice));
Doppler.fx = 2*sin_out/lambda;
Doppler.Nsv = Nsv;
Doppler.Nbins_averaged = Nbins;
end

function geom = dd_ray_twtt(x0,z0,phi,surf_x,surf_z,bed_x,bed_z,er_ice,slope_len,r_max)
% geom = dd_ray_twtt(x0,z0,phi,surf_x,surf_z,bed_x,bed_z,er_ice,slope_len,r_max)
%
% Two-way travel time to the ice surface and the ice bed along each
% delay-Doppler look direction, found by ray casting in the vertical plane
% that contains the flight line.
%
% This is what a "surface" means for the delay-Doppler product. Doppler
% bins resolve the ALONG-TRACK squint angle, so the ray for bin j at trace
% i leaves the platform at angle phi(j,i) from vertical, in the plane of
% the flight line, positive forward. The surface and bed in that plane are
% already known from the 2D picks of the neighbouring traces, so the ray is
% intersected with those along-track profiles, refracted at the surface,
% and continued to the bed. No DEM is used: the cross-track geometry that
% tomo.add_dem_icemask ray-casts through a DEM is orthogonal to this axis
% and does not enter.
%
% The travel times are the leading edge of each Doppler bin from the
% along-track plane. Every bin also contains energy from the rest of its
% iso-Doppler cone (cross-track off-nadir), which arrives later, so a
% tracked return can sit below the prediction but should not sit above it.
%
% INPUTS
% =========================================================================
% x0: 1 by Nx along-track position of each trace (m)
% z0: 1 by Nx platform elevation of each trace (m)
% phi: Ndop by Nx geometric look angle from vertical (rad), positive
%   forward. This is the Doppler squint plus the platform climb angle.
% surf_x, surf_z: along-track surface profile (m), increasing x. NaN
%   elevations are gaps that no ray can hit.
% bed_x, bed_z: along-track bed profile (m), or [] to skip the bed
% er_ice: relative permittivity of ice (e.g. 3.15)
% slope_len: along-track length (m) over which each profile is smoothed
%   before its slope is taken for refraction and incidence
% r_max: longest one-way air-equivalent range (m), c/2 times the last
%   fast-time sample. The air leg searches out to r_max, the ice leg only
%   as far as the remaining time allows, (r_max - r_air)/sqrt(er_ice).
%
% OUTPUTS
% =========================================================================
% geom: struct of Ndop by Nx matrices, NaN where the ray does not hit
%  .surf_twtt: two-way travel time to the surface (s)
%  .surf_x, .surf_z: where the ray meets the surface (m)
%  .surf_incidence: angle from the local surface normal (rad), signed
%  .bottom_twtt: two-way travel time to the bed (s), air plus ice
%  .bottom_x, .bottom_z: where the refracted ray meets the bed (m)
%  .bottom_theta_ice: refracted ray angle from vertical in the ice (rad)
%  .bottom_incidence: angle from the local bed normal (rad), signed
%
% Author: Nick Holschuh
%
% See also: delay_doppler_collate_task, delay_doppler, tomo.add_dem_icemask

physical_constants; % c

Nx = numel(x0);
Ndop = size(phi,1);
n_ice = sqrt(er_ice);

geom = [];
geom.surf_twtt = nan(Ndop,Nx);
geom.surf_x = nan(Ndop,Nx);
geom.surf_z = nan(Ndop,Nx);
geom.surf_incidence = nan(Ndop,Nx);
geom.bottom_twtt = nan(Ndop,Nx);
geom.bottom_x = nan(Ndop,Nx);
geom.bottom_z = nan(Ndop,Nx);
geom.bottom_theta_ice = nan(Ndop,Nx);
geom.bottom_incidence = nan(Ndop,Nx);

surf_x = surf_x(:).';
surf_z = surf_z(:).';
surf_slope = profile_slope(surf_x,surf_z,slope_len);
do_bed = ~isempty(bed_x);
if do_bed
  bed_x = bed_x(:).';
  bed_z = bed_z(:).';
  bed_slope = profile_slope(bed_x,bed_z,slope_len);
end

for rline = 1:Nx
  %% Air: platform to surface
  [r_air,hit_x,hit_z] = first_hit(x0(rline)*ones(Ndop,1),z0(rline)*ones(Ndop,1), ...
    phi(:,rline),surf_x,surf_z,r_max);
  good = isfinite(r_air);
  if ~any(good)
    continue;
  end
  geom.surf_twtt(good,rline) = 2*r_air(good)/c;
  geom.surf_x(good,rline) = hit_x(good);
  geom.surf_z(good,rline) = hit_z(good);

  % Snell's law about the local surface normal. The downward normal of a
  % surface with slope angle alpha points alpha from vertical, so a ray at
  % phi from vertical meets it at phi - alpha, and leaves into the ice at
  % alpha + asin(sin(phi - alpha)/n).
  alpha_s = interp1(surf_x,surf_slope,hit_x(good));
  inc = phi(good,rline) - alpha_s;
  geom.surf_incidence(good,rline) = inc;
  if ~do_bed
    continue;
  end
  phi_ice = nan(Ndop,1);
  phi_ice(good) = alpha_s + asin(sin(inc)/n_ice);

  %% Ice: surface to bed
  % Only the record time left after the air leg can be spent in the ice
  r_ice_max = (r_max - min(r_air(good)))/n_ice;
  [r_ice,bhit_x,bhit_z] = first_hit(hit_x,hit_z,phi_ice,bed_x,bed_z,r_ice_max);
  bgood = isfinite(r_ice);
  if ~any(bgood)
    continue;
  end
  geom.bottom_twtt(bgood,rline) = 2*(r_air(bgood) + n_ice*r_ice(bgood))/c;
  geom.bottom_x(bgood,rline) = bhit_x(bgood);
  geom.bottom_z(bgood,rline) = bhit_z(bgood);
  geom.bottom_theta_ice(bgood,rline) = phi_ice(bgood);
  geom.bottom_incidence(bgood,rline) = phi_ice(bgood) ...
    - interp1(bed_x,bed_slope,bhit_x(bgood));
end

end

function [r,hit_x,hit_z] = first_hit(ox,oz,phi,px,pz,r_max)
% Nearest intersection of the rays from (ox,oz) at angles phi (all N by 1)
% with the polyline (px,pz). Returns NaN for rays that miss.
%
% For a ray with unit direction d = (sin(phi), -cos(phi)), a vertex at
% offset v = (dx,dz) from the origin lies on the ray's left or right
% according to the sign of the cross product d x v = sin(phi)*dz +
% cos(phi)*dx, and at distance d.v = sin(phi)*dx - cos(phi)*dz along it.
% The ray crosses a segment where the cross product changes sign; the
% crossing distance is interpolated linearly between the two vertices.

N = numel(phi);
r = nan(N,1);
hit_x = nan(N,1);
hit_z = nan(N,1);

valid = isfinite(ox) & isfinite(oz) & isfinite(phi);
if ~any(valid)
  return;
end

% Only the vertices a ray of length r_max could reach, plus one on each
% side so a segment that straddles the limit is kept whole
keep = find(px >= min(ox(valid))-r_max & px <= max(ox(valid))+r_max);
if numel(keep) < 2
  return;
end
keep = max(1,keep(1)-1) : min(numel(px),keep(end)+1);
vx = px(keep);
vz = pz(keep);

sp = sin(phi(valid));
cp = cos(phi(valid));
dx = bsxfun(@minus,vx,ox(valid));
dz = bsxfun(@minus,vz,oz(valid));
s = bsxfun(@times,sp,dz) + bsxfun(@times,cp,dx);
t = bsxfun(@times,sp,dx) - bsxfun(@times,cp,dz);

s1 = s(:,1:end-1);
s2 = s(:,2:end);
cross_seg = (s1.*s2 <= 0) & (s1 ~= s2);   % false wherever a vertex is NaN
frac = s1./(s1 - s2);
rr = t(:,1:end-1) + frac.*(t(:,2:end) - t(:,1:end-1));
rr(~cross_seg | rr <= 0 | rr > r_max) = inf;

[r_min,seg] = min(rr,[],2);
hit = isfinite(r_min);
idx_valid = find(valid);
rows = idx_valid(hit);
seg = seg(hit);
lin = sub2ind(size(frac),find(hit),seg);
r(rows) = r_min(hit);
hit_x(rows) = vx(seg).' + frac(lin).*(vx(seg+1).' - vx(seg).');
hit_z(rows) = vz(seg).' + frac(lin).*(vz(seg+1).' - vz(seg).');
end

function slope = profile_slope(x,z,slope_len)
% Slope angle (rad) of a profile after a running mean over slope_len
% metres. NaN gaps stay NaN.
dx = median(diff(x));
Nwin = max(1,round(slope_len/dx));
zs = movmean(z,Nwin,'omitnan');
zs(isnan(z)) = NaN;
slope = atan(gradient(zs)./gradient(x));
slope(~isfinite(slope)) = 0;
end

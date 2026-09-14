# opr_ndh

Personal Open Polar Radar (OPR) functions for Nick Holschuh (Amherst College).

This repository sits beside the `opr` clone, at `<base_dir>/opr_ndh`. Nothing in
`opr/matlab/` is ever edited, so `git pull` in the `opr` clone is always clean. Functions
here take precedence instead because the startup script adds this directory to the MATLAB
path *after* the toolbox, and `addpath` prepends. See `STARTUP_SETUP.md` for the
startup-script changes that make that happen, and for the version of `opr` these functions
require.

## Layout

| Directory | Contents |
|---|---|
| `processing/` | New processing stages and their user-editable `run_*.m` templates, mirroring `opr/matlab/processing/` |
| `utility/` | Small helpers used by more than one stage |

Both are added to the MATLAB path recursively, so the split is for humans only. Function
names still have to be unique across the whole path.

## Contents

| Function | Purpose |
|---|---|
| `processing/along_track_sampling.m` | Along-track trace spacing and record rate of the raw data for one segment, measured from the records file |
| `processing/run_along_track_sampling.m` | Driver that runs the above over whole seasons and writes a summary table |
| `processing/delay_doppler.m` | Delay-Doppler product from the full raw data, posted on the array product's along-track grid, with a `Doppler` struct laid out like `Tomo` |
| `processing/run_delay_doppler.m` | User-editable template for the above |

Run `along_track_sampling` on a season before `delay_doppler`. It reports the raw
along-track spacing, which sets how much angle span the delay-Doppler product can reach:
the full plus or minus 90 degrees needs a raw spacing of a quarter wavelength or finer.

`delay_doppler` is deliberately not named `doppler`. Upstream has its own `doppler.m`
stage that collapses the spectrum to its centroid peak and writes a 2D echogram. This one
keeps the whole cube. Note also that upstream's `doppler` stage does not currently run at
all: `doppler_task.m` still calls `ct_output_dir`, `ct_filename_out`, `ct_save`, and
`param.ct_file_lock`, none of which survived the `ct_` to `opr_` rename.

## Working on more than one computer

The radar data does not live on the development machine. Write and commit here, then on
the data machine:

```bash
cd <base_dir>
git clone git@github.com:nholschuh/opr_ndh.git
git -C opr_ndh pull      # on every subsequent visit
```

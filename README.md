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

| File | Purpose |
|---|---|
| `example_startup.m` | KU startup file, with `opr_ndh` added to the path last so its functions take precedence (see `STARTUP_SETUP.md`) |
| `processing/along_track_sampling.m` | Along-track trace spacing and record rate of the raw data for one segment, measured from the records file |
| `processing/run_along_track_sampling.m` | Runs the above over whole seasons and writes a summary table |
| `processing/delay_doppler.m` | Delay-Doppler product from the full raw data, posted on the CSARP_standard traces (read from the SAR stage's `sar_coord.mat`), with a `Doppler` struct laid out like `Tomo`; `plan_only` mode sizes the work without loading data |
| `processing/run_delay_doppler.m` | Template for running the above on its own |
| `processing/delay_doppler_task.m` | Cluster task: the delay-Doppler product for one frame |
| `processing/delay_doppler_batch.m` | Builds a cluster batch with one delay-Doppler task per frame, sized from the plan |
| `processing/delay_doppler_tomo.m` | Shared engine: delay-Doppler product plus the three 3D array products on identical settings and traces |
| `processing/delay_doppler_tomo_check.m` | Runs the acceptance checks on every listed frame |
| `processing/run_delay_doppler_tomo.m` | **Local** run script: delay-Doppler in this session, 3D products through `array` |
| `processing/run_delay_doppler_tomo_cluster.m` | **Cluster** run script: takes day_seg / day_seg_frame lists and farms out every product |
| `utility/select_day_seg_frms.m` | Enables exactly the segments and frames named in a `YYYYMMDD_SS` / `YYYYMMDD_SS_FFF` list |
| `utility/opr_filename_param.m` | Override of the toolbox function: looks for parameter spreadsheets in `gRadar.param_path_ndh` before `gRadar.param_path` |
| `utility/tomo_set_check.m` | Acceptance checks for one frame of a standard/MVDR/MUSIC 3D set: Nsv, method, shared grids, MVDR covariance support and positivity, MUSIC floor, and trace alignment with 2D products |

**The three 3D products** are three `array` runs on the same SAR data that differ only in
`method` and `out_path`, each keeping its look-direction axis in `Tomo.img`. Default
directories are `standard3D_ndh`, `mvdr3D_ndh` and `music3D_ndh`. Never give one a bare
method name as its `out_path`, or it overwrites the posted 2D product of that name. MVDR
also needs `param.array.DCM` set wide enough for its covariance to invert; the run script
refuses to start otherwise.

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
git clone git@github.com:nholschuh/opr_ndh.git
git -C opr_ndh pull      # on every subsequent visit
```

Then point the startup at it as described in `STARTUP_SETUP.md`.

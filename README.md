# opr_ndh

Personal Open Polar Radar (OPR) functions for Nick Holschuh (Amherst College).

This repository is a **separate git repository that lives inside the `opr` working tree**,
at `<base_dir>/opr/opr_ndh`. It is deliberately not tracked by the `opr` clone, so the
`opr` clone stays byte-identical to upstream and `git pull` there is always clean.

Nothing in `opr/matlab/` is ever edited. Functions here take precedence because MATLAB
adds this directory to the path *after* the toolbox, and `addpath` prepends. See
`STARTUP_SETUP.md` for the startup-script changes that make that happen.

## Layout

| Directory | Contents |
|---|---|
| `processing/` | New processing stages and their user-editable `run_*.m` templates, mirroring `opr/matlab/processing/` |
| `utility/` | Small helpers used by more than one stage |

Both are added to the MATLAB path recursively by the startup script, so the split is for
humans only. Function names must still be unique across the whole path.

## Contents

Nothing yet. Planned:

- `processing/along_track_sampling.m` — along-track trace spacing and sample rate in the
  raw data, summarized per season.
- `processing/delay_doppler.m` — delay-Doppler product computed from the full raw data,
  posted at the along-track spacing of the standard product, written with a `Doppler`
  structure analogous to the `Tomo` structure used by the MUSIC products.

## Working on more than one computer

The raw radar data does not live on the development machine. Write and commit here, then
on the data machine:

```
cd <base_dir>/opr
git clone git@github.com:nholschuh/opr_ndh.git opr_ndh
echo 'opr_ndh/' >> .git/info/exclude
```

After that, `git pull` in `opr_ndh` is the only thing needed to pick up new functions.

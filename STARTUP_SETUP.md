# Making `opr_ndh` visible to the OPR toolbox

`example_startup.m` in this repository is the startup file used on the KU machines. It puts
`opr_ndh` on the MATLAB path so that any function in `opr_ndh` takes precedence over a
toolbox function of the same name, in `opr` or in `run_opr`. Nothing tracked by the `opr`
clone is touched, so `git pull` there stays clean.

---

## 1. How the startup does it

Two additions, both marked `Added by NDH: opr_ndh`:

- **In the KU Linux profile (profile 3)**, a field giving the repository location:

  ```matlab
  profile(pidx).opr_ndh_path = '/cresis/users/nholschuh_sta/scripts/opr_ndh';
  ```

- **In the Automated Section**, a block that adds `opr_ndh` and its subdirectories, placed
  *after* the blocks that add the OPR toolbox and `path_override` (`run_opr`). It skips
  `.git`, class (`@`) and package (`+`) directories, as the toolbox blocks do.

The order matters because `addpath` puts each directory at the **front** of the path, so the
directory added last wins. Adding `opr_ndh` last gives this resolution order:

```
1  opr_ndh
2  run_opr     (path_override)
3  opr/matlab
```

`path_override` still points at `run_opr` and is otherwise unchanged. Profiles without an
`opr_ndh_path` field skip the block.

---

## 2. Using it on another machine or profile

1. Clone the repository wherever you keep your scripts:

   ```bash
   git clone git@github.com:nholschuh/opr_ndh.git
   ```

2. Either copy `example_startup.m` to the folder returned by MATLAB's `userpath`, renamed to
   `startup.m`, or copy the two marked additions into your existing startup.
3. Set `opr_ndh_path` in the profile that machine uses.

After that, `git pull` inside `opr_ndh` is the only thing needed to pick up new functions.

---

## 3. Check it took

Restart MATLAB, then:

```matlab
which -all delay_doppler
```

The `opr_ndh` copy should be listed first. For a function that deliberately shadows a
toolbox function, `which -all <name>` should list `opr_ndh`, then `run_opr` if present, then
`opr/matlab`.

---

## 4. Cluster jobs

Each cluster type builds its path differently. All three end up with the startup's order,
provided the startup is the one in `userpath` on the machine that submits the jobs.

- **`debug`** runs every task in your MATLAB session, on the path you already have.
- **`matlab`** creates jobs with `createJob(parcluster)` and does not turn on
  `AutoAddClientPath` (`cluster_submit_job.m`), so workers do not inherit your session's
  path. Instead each worker runs the `startup.m` in `userpath` itself, and so builds the
  same order. This was confirmed with the local profile on the Amherst workstation (R2021a).
  If the startup is not in `userpath`, workers will see neither `opr` nor `opr_ndh`.
- **`slurm` and `torque`** run a binary compiled with `mcc`. The startup's opening guard,
  `if ~(~ismcc && isdeployed)`, runs the path setup while `mcc` is compiling and skips it
  only inside the finished binary. `mcc` therefore resolves every function through the same
  order and compiles the `opr_ndh` copy of anything shadowed. This follows from the code
  and has not been run on a KU node from here.

**New task functions.** All batches compile into one shared binary in `opr/matlab/cluster`,
and each compile includes only `cluster.hidden_depend_funs` plus the functions that batch
names. Whichever batch compiles last decides what the binary contains. A task function that
exists only in `opr_ndh` must therefore be in `hidden_depend_funs`, or a later array batch
can recompile without it.

- The KU startup lists `delay_doppler_task.m` and `delay_doppler_collate_task.m` in
  `hidden_depend_funs`, so every compile includes them, including one triggered by `sar`.
- Being on the list is not enough on its own. A batch only recompiles when a dependency is
  newer than the binary, so a binary built before the task was listed is reused, and every
  delay-Doppler task fails with `Undefined function 'delay_doppler_task'`. For that reason
  `delay_doppler_tomo` forces one compile, with the task included, before it builds slurm or
  torque batches, and `tomo_doppler_collate` does the same for the collate tasks.
- If you call `delay_doppler_batch` yourself, force the compile first:

  ```matlab
  cluster_compile({'delay_doppler_task.m','array_task.m','array_combine_task.m'},[],1)
  ```

**Recompiling after edits.** With the default `force_compile = 0`, a batch recompiles when
any file its functions depend on is newer than the binary. That dependency search also
resolves through the path, so editing an `opr_ndh` file triggers a recompile the next time
a batch that uses it is built. Set `param_override.cluster.force_compile = 1` if in doubt.

---

## 5. Personal parameter spreadsheets

`utility/opr_filename_param.m` shadows the toolbox function that turns a spreadsheet name
into a path, which every run script uses through
`read_param_xls(opr_filename_param('rds_param_....xlsx'))`. It searches
`gRadar.param_path_ndh` first and falls back to `gRadar.param_path`, so an edited copy of a
spreadsheet takes precedence without touching the shared `opr_params` directory.

The startup sets this in the KU profile and copies it into `gRadar`:

```matlab
profile(pidx).param_path_ndh = '/cresis/users/nholschuh_sta/scripts/opr_params_ndh';
```

```matlab
gRadar.param_path_ndh = profile(cur_profile).param_path_ndh;
```

- **Whole-file override.** A spreadsheet found in the personal directory replaces the
  default one entirely; rows are not merged. Keep only the spreadsheets you have edited
  there, and copy the current default before editing so you start from its latest rows.
- **Several directories.** `param_path_ndh` may be a cell array, searched in order.
- **Visibility.** The first time a personal spreadsheet is used in a session, MATLAB prints
  `opr_filename_param: using personal spreadsheet <path>`.
- **Existing batches.** Cluster tasks carry the parameters that were read when their batch
  was built. Changing a spreadsheet affects only batches built afterwards.
- **Not covered.** The `opr_control` season list and `wiki_dataset_pages.m` list
  `gRadar.param_path` directly, so they still show only the default directory.

Check which copy a name resolves to:

```matlab
opr_filename_param('rds_param_2018_Antarctica_DC8.xlsx')
```

---

## 6. Version requirement

The functions here use the current upstream API, which renamed every `ct_filename_*` to
`opr_filename_*` and `ct_set_params` to `opr_set_params` with no compatibility wrappers. An
`opr` clone older than that rename fails with undefined function errors. The Amherst
workstation clone (`03ee905c`, September 2024) predates the rename and was 319 commits
behind when last checked.

# Making `opr_ndh` visible to the OPR toolbox

Everything below is done once per computer. It changes only your own startup script and one
local, untracked file inside the `opr` clone. No file tracked by `opr` is touched, so
`git pull` in `opr` stays clean.

Throughout, `base_dir` is the directory your startup script already uses to find `opr`,
`opr_params`, and `run_opr`. On the Amherst workstation that is
`/mnt/NDH_data/Google_Drive2/Research_Projects/00_CresisData`.

---

## 1. Hide `opr_ndh` from the `opr` clone

`opr_ndh` is its own git repository sitting inside the `opr` working tree. Tell the `opr`
clone to ignore it. `.git/info/exclude` is local to the clone and is never committed or
pulled, so this does not conflict with upstream:

```bash
echo 'opr_ndh/' >> <base_dir>/opr/.git/info/exclude
```

Confirm with `git status` inside `opr` — it should report a clean tree.

---

## 2. Repoint `path_override` at `opr_ndh`

OPR already has the hook you need. In `opr/matlab/example_startup.m` the personal
directory is added to the MATLAB path *after* the toolbox directories, and `addpath`
prepends, so a function in the personal directory shadows a toolbox function of the same
name. The comment at line 397 says exactly this.

In every profile block of your startup script, change:

```matlab
profile(pidx).path_override             = fullfile(base_dir,'run_opr');
```

to:

```matlab
profile(pidx).path_override             = fullfile(base_dir,'opr','opr_ndh');
profile(pidx).path_run_opr              = fullfile(base_dir,'run_opr');
```

Leave `profile(pidx).path` alone. It points at `<base_dir>/opr/matlab`, and `opr_ndh` sits
one level above that, so the toolbox path scan never picks `opr_ndh` up. Nothing gets added
to the path twice, and there is no ambiguity about which copy of a function wins.

`gRadar.path_override` must stay a single directory string. Two toolbox functions,
`radiometric_calibration.m` and `slope_tracker.m`, call `get_filenames` on it directly and
would break on a cell array.

---

## 3. Keep `run_opr` on the path

Step 2 takes `run_opr` out of the `path_override` slot, so it needs its own block. Paste
this into the "Startup code (Automated Section)" of your startup script, immediately
**before** the `if ~exist(profile(cur_profile).path_override,'dir')` block. Order matters:
`run_opr` goes on first so that `opr_ndh` still wins over everything.

```matlab
  if isfield(profile,'path_run_opr') && ~isempty(profile(cur_profile).path_run_opr) ...
      && exist(profile(cur_profile).path_run_opr,'dir')
    fprintf('  Adding run_opr path: %s\n',profile(cur_profile).path_run_opr);
    fns = get_filenames(profile(cur_profile).path_run_opr,'','','',struct('type','d','recursive',1));
    addpath(profile(cur_profile).path_run_opr);
    AdditionalPaths{end+1} = profile(cur_profile).path_run_opr;
    for fn_idx = 1:length(fns)
      [fn_dir fn_name] = fileparts(fns{fn_idx});
      if ~isempty(fn_name) && fn_name(1) ~= '@' && fn_name(1) ~= '+' ...
          && isempty(strfind(fns{fn_idx},'.svn')) && isempty(strfind(fns{fn_idx},'.git'))
        addpath(fns{fn_idx});
        AdditionalPaths{end+1} = fns{fn_idx};
      end
    end
  end
```

This is the existing personal-path block with the variable name swapped. The `.git` test on
the last condition is why `opr_ndh/.git` never lands on the MATLAB path.

If you would rather not edit the automated section, the alternative is to leave
`path_override` pointing at `run_opr` and append a bare
`addpath(genpath('<base_dir>/opr/opr_ndh'))` at the very end of the startup script. That
works for the MATLAB path, but `gRadar.path_override` then points at the wrong directory
and compiled cluster jobs will not substitute your overrides. Prefer the block above.

---

## 4. Check it took

Restart MATLAB, then:

```matlab
global gRadar; gRadar.path_override    % should print .../opr/opr_ndh
which -all along_track_sampling        % should find the opr_ndh copy
```

For any function that deliberately shadows a toolbox function, `which -all <name>` should
list the `opr_ndh` copy **first** and the `opr/matlab` copy second. If the order is
reversed, the `run_opr` block from step 3 was pasted after the `path_override` block
instead of before it.

---

## 5. Compiled cluster jobs

Relevant only if you run with `cluster.type` set to `torque` or `slurm` and MCC
compilation enabled. Two cases, and they behave differently:

- **A function that overrides an existing toolbox function.** Handled automatically. The
  scheduler substitutes the `path_override` copy when it builds the dependency list.
- **A brand-new function that exists nowhere upstream.** *Not* included automatically. The
  comment at `example_startup.m:471` spells this out: only files that also exist in
  `.path` get overwritten in the dependency list.

For the second case, add an entry to the `hidden_depend_funs` list in your startup script,
alongside the existing `qlook_task.m` and `array_task.m` entries:

```matlab
  gRadar.cluster.hidden_depend_funs{end+1} = {'delay_doppler_task.m' 2};
```

The second element is the date-check level: `2` means check this file and its dependencies
only when `fun` is not passed to `cluster_compile`. Re-run `cluster_compile` after any
change to that list.

---

## 6. Setting up a new computer

```bash
cd <base_dir>/opr
git clone git@github.com:nholschuh/opr_ndh.git opr_ndh
echo 'opr_ndh/' >> .git/info/exclude
```

Then steps 2 and 3 on that machine's startup script. From then on, `git pull` inside
`opr_ndh` is the only thing needed to pick up new functions.

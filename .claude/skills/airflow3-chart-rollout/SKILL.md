---
name: airflow3-chart-rollout
description: >-
  Fork, promote, and collapse Airflow 3 Helm charts in data.gitops using env
  symlinks so a feature is one chart directory and promotion is retargeting the
  next env at that same directory. Use whenever changing `_charts/airflow-v3*`
  for a single env (airflow3-dev/stage/preprod/prod), when the user says fork
  the chart, copy the chart, overwrite the symlink, promote the AF3 chart,
  collapse the chart fork, DTT chart rollout, or isolate a Helm chart change
  to one Airflow 3 environment. data.gitops PRs always target master — there
  is no gitops stage branch. Never cp files between env deployment.yaml dirs
  to "promote". Never invent extra gitops base branches for Airflow.
---

# Airflow 3 chart rollout (data.gitops)

Work happens in **`data.gitops`**, not in this monorepo checkout. This skill
lives here because it is the data-tooling runbook; the files it mutates are
under `data.gitops/_charts/`.

## Colleague process (source of truth)

If you want to do changes for a specific env you just have to overwrite the
symlink with a copy of the chart.

For instance, AF3 dev (you can do it manually or via AI):

```
cd _chart;
rm airflow-v3-dev; # remove sym-link
cp -a airflow-v3 airflow-v3-new-feature;
ln -s airflow-v3-new-feature airflow-v3-dev; # new sym-link
```

Something I like a lot is if you want to promote the changes you just have to
change the sym-link, so no human error or AI hallucination can deploy something
different than the lower env.

We don't have to use the exact same process as long as the result is the same.
It's ok to have a duplicated chart while we are working and promoting a new
feature but once in prod we shouldn't have duplicates ideally.

**Result that must hold:** one feature directory; envs only change which
symlink points at it; after prod, a single canonical chart remains.

## Repo facts agents get wrong

- **data.gitops has only `master`.** PRs target `master`. Stage vs prod is
  `data.stage.euc1/` vs `data.prod.euc1/` + ArgoCD apps, not git branches.
- Do **not** apply data.monorepo's `feature → stage branch → master` flow here.
- Do **not** commit `_synth/`. CI auto-synths on the PR.
- HelmRelease `path:` stays `_charts/airflow-v3-<env>` (version-agnostic
symlink). Never retarget `deployment.yaml` at `airflow-v3-DTT-760`.
- Actual paths vs the snippet above: directory is `_charts/` (plural).
  Canonical chart on current `master` is `_charts/airflow-v3` (unversioned),
  matching the colleague snippet. A versioned `_charts/airflow-v3.X.Y` is
  also canonical if that is what `airflow-v3-prod` points at. Feature copies
  are `_charts/<canonical>-<slug>` (e.g. `airflow-v3-DTT-760`). Never treat
  leftover `airflow-v3.1.8` as canonical while prod still points at
  `airflow-v3`.

Env order (same-cluster pairs share a gitops commit):

```
dev → stage → preprod → prod
```

`dev`+`stage` live on the stage cluster; `preprod`+`prod` on the prod cluster.
A shared-chart edit on `master` hits every env still pointing at the canonical
dir. That is why we fork.

## Do not

- `rm -rf` the canonical chart or an env symlink's target. Only `rm` the
  **symlink** `airflow-v3-<env>`.
- Copy `airflow_local_settings.py` into `deployment.yaml` or between
  `airflow3-dev/` and `airflow3-stage/` to promote.
- Introduce gitops `dev` / `stage` / `preprod` branches for this.
- Leave a second `airflow-v3.X.Y.Z-<slug>` directory on `master` after prod
  is promoted — run **collapse**.
- Change the chart in place under `_charts/airflow-v3` (or whatever prod
  currently uses as canonical) when the change is meant for one env only.

## Script (run this; do not improvise cp/rm)

From the **data.monorepo** clone. The script lives in `dev_tools/` (same
pattern as `airflow3_migration/` / `dag_tests/`); it locates gitops via
`--gitops`, `DATA_GITOPS`, or `../data.gitops`:

```bash
SCRIPT=dev_tools/airflow3_chart_rollout/chart.sh
chmod +x "$SCRIPT"

# where we are
"$SCRIPT" --gitops /path/to/data.gitops status

# 1. isolate on airflow3-dev (default --env dev)
"$SCRIPT" --gitops /path/to/data.gitops fork DTT-760
# → cp -a airflow-v3 airflow-v3-DTT-760   # or airflow-v3.X.Y if that is canonical
# → rm airflow-v3-dev; ln -s airflow-v3-DTT-760 airflow-v3-dev

# 2. promote: retarget only. same directory. no copy.
"$SCRIPT" --gitops /path/to/data.gitops promote DTT-760 --env stage
"$SCRIPT" --gitops /path/to/data.gitops promote DTT-760 --env preprod
"$SCRIPT" --gitops /path/to/data.gitops promote DTT-760 --env prod

# review delta for the PR (not the 700-file copy)
"$SCRIPT" --gitops /path/to/data.gitops diff DTT-760

# 3. after ALL four env symlinks point at the feature dir
"$SCRIPT" --gitops /path/to/data.gitops collapse DTT-760
```

`fork` copies from the **canonical** unsuffixed chart (prod's target when that
name is canonical, else `_charts/airflow-v3`, else the highest
`airflow-v3.X.Y`). `promote` never copies. `collapse` refuses unless every
env symlink already points at the feature dir.

## Agent workflow

1. Confirm gitops checkout and `chart.sh status`.
2. Pick the operation: **fork** (new isolation), **promote** (next env, same
   dir), **collapse** (prod soaked, delete duplicate).
3. Cut a gitops branch from `origin/master`. Run the script there.
4. After **fork**, edit **only** `$feature/` (usually
   `custom/airflow_local_settings.py` and tests). Put the functional diff in
   the PR body via `chart.sh diff`.
5. Open a data.gitops PR → **`master`**. Do not stage `_synth/`.
6. After merge + Argo, wait for soak on that env before `promote` of the next.
7. When prod points at the feature dir and soak is done, `collapse` on a new
   PR to `master`.

## Examples

**DTT-760 task_policy on airflow3-dev only**

```
fork DTT-760 --env dev
# edit _charts/airflow-v3-DTT-760/custom/airflow_local_settings.py
# PR to master
```

Stage/preprod/prod stay on `airflow-v3`.

**Promote that same bytes to stage**

```
promote DTT-760 --env stage
# PR to master — symlink only (+ synth CI)
```

For layout and the four env HelmReleases, see
[`dev_tools/airflow3_chart_rollout/reference.md`](../../../dev_tools/airflow3_chart_rollout/reference.md).

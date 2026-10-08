---
name: migrate-dag
description: Move one DAG from the old data.airflow.dags repo into this Airflow 3 monorepo. Creates a feature branch off master, copies the pipeline into a per-pipeline package folder under an area/sub-area the user picks, moves its SQL into sql/, and runs the Airflow 2→3 conversion. Stops there for the user to review. Use when asked to "migrate DAG X", "move DAG X from the old repo", or "move <path> into the new repo". For the full guided pipeline (stage PR → QA → master PR), use migrate-pipeline instead.
---

# migrate-dag

**Move a DAG from `data.airflow.dags` into this repo, then convert it to Airflow 3.**

Deliberately simple. The flow is: branch → copy → convert → hand back. It does
**not** rewrite secrets, run pre-commit, commit, or open PRs — those are separate,
explicit steps the user runs when they're ready (see the end of this doc).

---

## Prerequisites (check once, before starting)

```bash
ls ../data.airflow.dags/dags/                       # old repo present as a sibling
git status                                          # working tree clean
git branch --show-current                           # note current branch
git -C ../data.airflow.dags status --short <source> # old repo: source file has no uncommitted edits
ruff --version                                       # required by the Airflow 3 conversion
```

- If the working tree is dirty, tell the user to stash or commit first.
- If the old repo is missing, tell the user both repos must be siblings under the
  same parent (e.g. `~/repos/data.airflow.dags` and `~/repos/data.monorepo`).
- The old repo is a working checkout that can be behind `origin/master` or sit on another branch —
  copying from a stale checkout silently carries over old code. If unsure it's current, tell the
  user to `git -C ../data.airflow.dags pull` (or confirm they're intentionally copying from a
  specific branch/commit) before continuing.
- **`ruff` is not optional.** The conversion (`migrate.py`) does the bulk of its
  import rewrites through `ruff`. If `ruff` is missing it only prints a warning and
  *silently skips that pass*, producing a half-converted DAG. If `ruff --version`
  fails, install it before continuing:

  ```bash
  pip install ruff
  ```

---

## Step 1 — Gather inputs

1. **Source path** — the DAG file inside `data.airflow.dags`, relative to that repo
   root. Example: `dags/tran-dwh-jackpot-hourly.py`

2. **Destination area** — ask the user to pick one of the five root areas:

   ```
   analytics_platform   # DWH, reporting, gaming, sport, retail, finance, social, player
   compliance           # Regulatory, AML, responsible gambling, fraud
   swe                  # App-specific pipelines: gaming, sport, retail, social, player
   data_tooling         # Platform infrastructure, shared utilities
   data_products        # ML, personalization, martech, experimentation, data science
   ```
   If they're unsure, suggest one based on the DAG name and ask them to confirm.

3. **Sub-area** — ask which sub-area folder inside that area (e.g. `commercial`,
   `gaming`). List the existing sub-areas under the chosen area so they can pick
   one or name a new one:

   ```bash
   ls airflow_etl/dags/<area>/
   ```

4. **Build the destination.** The repo uses a **per-pipeline package folder**: the
   DAG gets its own folder named after the pipeline (keep the old file's name), and
   the file lives inside it. SQL lands in that folder's `sql/`.

   ```
   airflow_etl/dags/<area>/<sub_area>/<pipeline>/
     <pipeline>.py
     <pipeline>_test.py     # if the old repo had one
     config.yaml            # the DAG's env config, if it has one (see below)
     sql/...                # if present
     lib/...                # if present (rare; future-proofing)
   ```

   `<pipeline>` is the source file's stem. So `--dest` is:

   ```
   airflow_etl/dags/<area>/<sub_area>/<pipeline>/<pipeline>.py
   ```

---

## Step 2 — Create a feature branch off master

```bash
git checkout master
git pull origin master
git checkout feat/migrate-<pipeline> 2>/dev/null || git checkout -b feat/migrate-<pipeline>
```

If the branch already exists (a resumed run), reuse it — but confirm it carries this pipeline's
work, not something unrelated. The name `feat/migrate-<pipeline>` is a **contract**:
migrate-pipeline's resume detection greps for it and rewrite-tags / rewrite-secrets reuse it, so
don't rename the convention unilaterally. This flow deliberately runs in the primary checkout
(the documented exception to the worktree rule in the root `CLAUDE.md` — the tooling reads the
old repo at the sibling path `../data.airflow.dags`).

---

## Step 3 — Copy and convert

```bash
python3 dev_tools/airflow3_migration/move_dag.py \
    --source <source_path> \
    --dest   airflow_etl/dags/<area>/<sub_area>/<pipeline>/<pipeline>.py
```

`move_dag.py` copies the DAG and any co-located `*_test.py`, `sql/`, and `lib/`,
locates the DAG's env config (see the next section), runs the Airflow 2→3
conversion on the copied `.py` files, then rewrites Snowflake connection
references to `include.airflow.snowflake` and legacy alerting callbacks to
`attach_to()`. It prints:
- a **Snowflake note** if the DAG touches Snowflake — the deterministic inline
  `var.json` dict is auto-rewritten to `get_sf_conn_dict(cfg)` and `default_sf_user`
  is set in the pipeline `config.yaml`; other styles (team helpers, hardcoded
  `conn_id`s, `SnowflakeHook`) are listed for manual review with the recommended
  helper. Surface it and apply the manual items.
- an **Alerting note** if the DAG wires incident.io the old way — an
  `IncidentIOAlerter`'s `on_failure_callback`/`on_success_callback` kwargs are
  auto-rewritten to `<alerter>.attach_to(dag)` (the preferred method — see the
  `create-pipeline` skill's `alerting-scaffold.md`), preserving
  `notification_level` exactly; anything ambiguous (no single
  `with DAG(...) as <alias>:` block) is flagged for manual review instead.
  Surface it and apply the manual items.
- a **SQL note** if any `.sql` files landed in `sql/` — surface it so the user can
  decide whether to keep them there or move shared queries to the area's `shared/`.
- a **config note** — either confirming the config it copied, or (loudly, marked
  `ACTION NEEDED`) telling the user to relocate a config it couldn't resolve.
- a **date-macro note** (loudly, marked `ACTION NEEDED`) if any copied file uses
  `ds` / `execution_date` / `logical_date` / `prev_ds` / etc. — Airflow 3 redefined
  what these mean (see below). `move_dag.py` exits with code **2** when this fires.
- a short **review note** about what the converter can't do automatically (direct
  ORM access, removed-module imports, config-driven behaviour).

It also **generates the per-pipeline smoke test** (`<pipeline>_test.py`) unless the
old repo already carried one — the single sanity check (imports, parse, task graph)
the monorepo convention requires. See `dev_tools/dag_tests/README.md`.

Override the old-repo location with `--from-repo <path>` if it isn't at
`../data.airflow.dags`. Add `--dry-run` to preview without writing.

### `logical_date` changed meaning in Airflow 3 — resolve every hit, don't just note it

Airflow 3 redefined `logical_date` from "start of the data interval" to "when the
run was queued" (`run_after`). Everything derived from it — `ds`, `ds_nodash`,
`ts`, `ts_nodash`, `execution_date`, `prev_ds`, `next_ds`, `next_execution_date`,
`yesterday_ds`, `tomorrow_ds` — moved with it, and `ExternalTaskSensor`'s
`execution_date_fn=` callable now receives the new `logical_date` value instead
of the old execution_date (the kwarg itself is not renamed or removed).
`data_interval_start` / `data_interval_end` did **not** change.

This mostly never raises. A DAG that used one of the affected values to partition
or filter a query (`WHERE date = '{{ ds }}'`, `--execution-date "{{ execution_date... }}"`,
a `{{ ts }}`-partitioned S3 path) will keep running after migration and silently
pull the wrong date — there's no crash to catch it, just wrong numbers downstream.
It's common: 189+ files in the legacy repo reference one of these.

`move_dag.py` catches this itself — it's not something you have to remember to
grep for (it checks Jinja macros, `context[...]`/`kwargs[...]` subscripts, and the
`execution_date_fn=` kwarg). If any copied file has a hit, you'll see an
`ACTION NEEDED` box listing every file:line and the exit code will be **2**
instead of 0. Treat that the same way you'd treat a syntax error in Step 4:
**do not proceed to Step 5 until every hit is resolved.** For each one:
- **Drives a partition/filter/date-range calc** → look up the exact pattern in
  `dev_tools/airflow3_migration/DATE_VARIABLES.md` for the specific replacement
  (usually `data_interval_start` / `data_interval_end`; for `execution_date_fn=`,
  the kwarg name stays the same — fix the lambda body for the new `logical_date`
  semantics, or switch to an asset dependency). Then re-run
  `python3 dev_tools/airflow3_migration/migrate.py <file> --dry-run` on just
  that file and confirm it now **exits 0** — that's the signal the fix landed.
- **Just a label/timestamp** (e.g. tagging an export path with a run date) →
  leave the code as-is, but call it out explicitly in the Step 5 hand-back note
  (`logical_date at <file>:<line> — label only, not a filter.`) so whoever opens
  the PR carries it into the description — this skill doesn't open the PR
  itself, so the justification has to survive the hand-off, not stay implicit.

**`DATE_VARIABLES.md`** is the developer reference here — before/after examples
for every pattern above. It's also the right thing to point a developer at when
they're writing a *new* DAG and reach for `ds`/`execution_date`, not just during
migration. Full enforcement recipe (the exact classification questions) lives in
`RULES.md`'s "Resolving a finding" section.

### Legacy KubernetesPodOperator + Docker SQL-executor pattern

Some old-repo DAGs run every SQL statement through a `KubernetesPodOperator` calling
a custom Docker image, with SQL living in the old repo's top-level `scripts/` tree
rather than a folder co-located with the DAG — `move_dag.py` doesn't detect this, so
you have to recognize and refactor it yourself. Grep the source DAG for
`SnowflakeSQLExecutorCmd` or a `base_path`/`'--script'` pair before concluding
there's no SQL to move. If you find it, read
`references/legacy-kpo-docker-sql-executor.md` for the required refactor (target
operator and migration steps) — this is not optional or a deferred follow-up.

### Executor routing review — `queue` does not select KubernetesExecutor

If a copied DAG or helper contains `queue="local"`, `queue="kubernetes"`, an
explicit `executor`, or `executor_config`, follow
`references/executor-routing.md`. Classify the task by intent; never
mechanically replace every `queue=` with `executor=`.

### How config.yaml is handled

The old and new repos store per-DAG config completely differently (old: centralized
under `dags/configs/`, keyed by DAG id; new: hierarchical `config.yaml` merge by
folder), so `move_dag.py` resolves and copies the right config as best it can rather
than doing a plain file copy. Read `references/config-yaml-handling.md` for the
resolution rules and the cases that need manual follow-up (`ACTION NEEDED` notes,
reviewing inherited keys).

---

## Step 4 — Syntax-check the converted file(s), and resolve any date-macro findings

```bash
for f in <copied .py files>; do
  python3 -c "import ast; ast.parse(open('$f').read())" && echo "OK: $f" || echo "SYNTAX ERROR: $f"
done
```

If any file fails, stop and show the user the error. This flow runs in the primary checkout, not a
worktree, so a bad run has real blast radius: to abandon it cleanly, `git checkout -- .` the
partially-converted files (or delete the new pipeline folder if it's untracked) and, if the branch
was created fresh for this run, `git checkout master && git branch -D feat/migrate-<pipeline>`.

Also check `move_dag.py`'s own exit code from Step 3. If it was **2**, an
`ACTION NEEDED` box was printed listing `logical_date`/`ds`/`execution_date`/etc.
hits (see above) — do not proceed to Step 5 until each one is resolved or the
user has explicitly signed off on it.

---

## Step 5 — Hand back to the user

Report what was copied, paste the Snowflake note, Alerting note, SQL note,
date-macro note (if any), and review note verbatim, and tell the user the move + conversion are done.
The remaining steps are theirs to run when ready — point them at the relevant
skills:

- **Smoke test** — a `<pipeline>_test.py` was generated next to the DAG. Run it with the
  repo venv (`DEPLOYMENT_ENV=STAGE .venv/bin/python <path>/<pipeline>_test.py`); it fails
  loudly on any import/parse/graph error. If there's no venv or Airflow isn't importable,
  run the **setup-test-venv** skill first.
- **Snowflake** — apply the Snowflake note's manual-review items (team helpers,
  hardcoded `conn_id`s, `SnowflakeHook`) using the suggested `include.airflow.snowflake`
  helpers. Confirm `default_sf_user` in the pipeline `config.yaml` is correct.
- **Alerting** — apply the Alerting note's manual-review items (wire `attach_to()`
  by hand wherever it couldn't be auto-attached). Confirm `notification_level` on
  the DAG's `IncidentIOConfig` still matches what the legacy pipeline had.
- **S3 write-path safety review (mandatory when DAG writes to S3)**:
  - Search migrated files for direct writers: `boto3.client("s3")`, `put_object(`,
    `copy_object(`, `upload_file(`, `upload_fileobj(`, `s3.open(`, `aws s3 cp`.
  - For each direct writer, use bucket-aware ACL behavior:
    `acl = cross_account_acl(bucket)` and then `kwargs = {"ACL": acl} if acl else {}`.
  - Ensure role + bucket policy includes bucket-level `s3:GetBucketOwnershipControls`
    on every write bucket (bucket ARN, not just object ARN).
  - If any direct writer cannot be remediated in this PR, document it as a blocker follow-up
    before stage promotion.
- **Legacy KPO + Docker SQL-executor pattern** — if the DAG used this (see above),
  the `RenderedSQLExecuteQueryOperator` refactor and the `sql/` move are done as part
  of this same migration, not deferred.
- **Tags** — run the `rewrite-tags` skill to convert the old repo's freeform
  `tags=[...]` into the structured `key:value` convention (`owner:` is the
  required minimum). Canonical order puts it right after this skill, before secrets.
- **Secrets** — run the `rewrite-secrets` skill on the new file if it references
  legacy secret names.
- **Formatting/lint** — run the `run-pre-commit` skill before committing.
- **Commit + PRs** — once they're happy with the review, commit and open PRs
  themselves.

---

## Gotchas

- **`--from-repo` default** is `../data.airflow.dags`. Pass `--from-repo <path>` if
  the old repo is elsewhere.
- **`lib/` is copied if present** but needs no special handling today — most DAGs
  don't have one. It's there to future-proof helper-module pipelines.
- **Existing destinations are skipped** (with a warning), so re-running is safe and
  won't clobber files. That warning covers a genuine resume, but it looks identical to a name
  collision with an unrelated pipeline that happens to share a folder name — if the destination
  folder already exists, confirm with the user that its contents actually belong to *this*
  pipeline before proceeding, the same way Step 2 confirms a reused branch.
- **Package-style sources** (`dags/<pkg>/dag.py` in the old repo): pass the
  `dag.py` file as `--source`, but name the pipeline after the package — i.e.
  `--dest airflow_etl/dags/<area>/<sub_area>/<pkg>/<pkg>.py` — not after the literal `dag`
  stem. `move_dag.py` renames `dag.py` to match `--dest`.
- **Templated SQL trips sqlfluff — expect false failures.** The repo's sqlfluff uses
  the `placeholder`/`dollar` templater, which doesn't resolve Airflow Jinja: bare
  `{{ params.x }}` in an identifier/value position is unparsable (`PRS`), and Snowflake
  session vars like `$ROW_CNT AS ROW_CNT` trip a false-positive `AL09` self-alias. The
  SQL is correct and runs (Airflow renders the Jinja at runtime), so **keep it faithful —
  don't mangle it to satisfy the linter** (auto-fixing AL09 corrupts the query; numeric
  templates can't be quoted). Nothing blocks the commit/PR today: no pre-commit hook is
  installed by default and CI doesn't lint SQL. Details in the sqlfluff note in
  `airflow_etl/CLAUDE.md`.

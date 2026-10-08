---
name: migrate-airflow-3
description: Migrate Airflow 2 DAG files to Airflow 3 in place. Accepts one DAG, a list of DAGs, or a folder. Wraps the proven upstream `convert_to_airflow_3` baseline (ported to cross-platform Python so it actually runs on macOS) and layers extra rules so output matches what was hand-committed on the `airflow3-dev` branch of `data.airflow.dags`. Normally invoked automatically by migrate-dag when it copies a DAG in from the old repo — call this skill directly only to re-run the conversion on files already in this repo. Use when asked to "migrate/convert DAG <name> to Airflow 3", "run the Airflow 3 migration on <folder>", "migrate all legacy DAGs to Airflow 3", or "apply the Airflow 3 conversion script". For moving a DAG in from the old repo, use the migrate-dag skill instead.
---

# Migrate Airflow 2 → Airflow 3

## Step 0 — Ensure `ruff` is installed (required, do this first)

`ruff` does the bulk of the AIR3 import rewrites. Without it, `migrate.py` only
prints a warning and **silently skips that pass** — leaving a half-migrated file
that still parses. Never rely on that warning being noticed. Check, and install
if missing, before running anything:

```bash
ruff --version || pip install ruff
```

Confirm `ruff --version` succeeds afterwards. If the install fails (e.g. no
network, restricted environment), STOP and tell the user — do not run the
transform without `ruff`, because the output would be incomplete.

## What it does

For each `.py` file, the pipeline runs four stages:

1. **Pre-ruff rules** — project-specific rewrites (namespaces, deprecated kwargs) ported from upstream `lib.sh`. Done in Python so they work on macOS, unlike the upstream `sed -i` form.
2. **Ruff AIR3 fix** — `ruff check --select AIR3 --fix --unsafe-fixes` does the heavy lifting for stdlib import moves.
3. **Post-ruff style reversion** — undoes a handful of ruff-preferred forms (e.g. `from airflow.sdk import DAG`) where the reference repo intentionally kept the legacy form (`from airflow import DAG`). Both are valid in Airflow 3; matching the reference style minimises review noise.
4. **Cleanup** — dedupes identical import lines and ensures a trailing newline.

Optional fifth stage (`--yaml`): YAML config files get a `DEV:` section copied from `STAGE:` if missing — ports `add_dev_env_to_yaml.sh`.

Full rule list with rationale lives in `dev_tools/airflow3_migration/RULES.md`.

## Moving a DAG in from the old repo? Use the migrate-dag skill

This skill only **transforms code in place**. If the DAG still lives in the old repo
(`data.airflow.dags`), use the **`migrate-dag`** skill instead — it owns the full branch → copy →
convert → hand-back workflow and documents every step there; don't reach for `move_dag.py`
directly here.

## Transform in-place (already copied files)

The script is stdlib-only Python; the only external dep is `ruff` (install with `pip install ruff` if not on PATH).

```bash
# Single DAG
python3 dev_tools/airflow3_migration/migrate.py airflow_etl/dags/data_tooling/tran-dm-asdk.py

# Several DAGs
python3 dev_tools/airflow3_migration/migrate.py \
    airflow_etl/dags/data_tooling/tran-dm-asdk.py \
    airflow_etl/dags/data_tooling/tran-dm-asdk-daily.py

# Whole folder (recursive *.py)
python3 dev_tools/airflow3_migration/migrate.py airflow_etl/dags/data_tooling/

# Include YAML configs (add DEV env mirroring STAGE)
python3 dev_tools/airflow3_migration/migrate.py airflow_etl/dags/data_tooling/ --yaml

# Preview only — no writes
python3 dev_tools/airflow3_migration/migrate.py airflow_etl/dags/data_tooling/tran-dm-asdk.py --dry-run
```

The script **rewrites files in place**. The intended workflow is:

1. Run the skill.
2. Inspect with `git diff af2-master-mirror..master -- <path>` to see the Airflow 2 → 3 transformation.
3. Commit.

## What goes to manual review

The skill is intentionally conservative — it only applies rules with high confidence. The following are **not** auto-rewritten and need a human:

- **`logical_date` semantic change — enforced, treat as a hard stop.** Airflow 3 redefined `logical_date` from "start of the data interval" to "when the run was queued." `ds`, `ds_nodash`, `ts`, `ts_nodash`, `execution_date`, `prev_ds`, `next_ds`, `next_execution_date`, `yesterday_ds`, `tomorrow_ds` all moved with it (`data_interval_start`/`data_interval_end` did not), and `ExternalTaskSensor`'s `execution_date_fn=` kwarg now receives the new `logical_date` value instead of the old execution_date (the kwarg itself is not renamed or removed). This mostly never raises — a DAG using one of these to partition or filter a query silently pulls the wrong date after migration. `migrate.py` scans every file for this (Jinja macros, `context[...]`/`kwargs[...]` subscripts, and the `execution_date_fn=` kwarg), prints an `ACTION NEEDED` box naming each hit, and **exits with code `2`** if any are found — distinct from the normal 0/1. **Never ignore exit code `2`, same as you'd never ignore an `ast.parse` `ERROR`.** For each hit, look up the exact pattern in **`dev_tools/airflow3_migration/DATE_VARIABLES.md`** for the specific replacement (usually `data_interval_start`/`data_interval_end`; for `execution_date_fn=`, the kwarg name stays the same — fix the lambda body for the new `logical_date` semantics, or switch to an asset dependency) and re-test; if it's just a label/timestamp, get explicit confirmation and note it in the PR description. `DATE_VARIABLES.md` is also the reference to point developers at when writing a *new* DAG, not just during migration. Full enforcement rationale in `RULES.md`'s "`logical_date` semantic change" section.
- **Direct ORM access** — Airflow 3 forbids `from airflow.models import ... ; session.query(...)` style queries. Tickets DTT-292 / DTT-341 saw runtime errors like `RuntimeError: Direct database access via the ORM is not allowed in Airflow 3.0`. The fix is to use `conn_id="airflow_db"` against the metadata DB instead, but the rewrite is too case-specific to automate. Grep the migrated file for `airflow.models` (except `Variable` and `Param`) and review manually.
- **Custom operators that subclassed Airflow 2 internals** — if a DAG imports from a removed Airflow internal module, the script won't know the new path. Look for `from airflow.<anything>` imports that don't resolve under Airflow 3 and consult the [Airflow 3 migration guide](https://airflow.apache.org/docs/apache-airflow/3.0.0/upgrading-from-2.html).
- **Config-driven behaviour** — env-specific Snowflake connections, bucket policies, and the like are out of scope for this skill. DTT-292 lists many DAGs that needed bucket-policy fixes; that's a deploy-time concern, not a code-rewrite concern.

## Required follow-up after running

1. **Check the exit code before anything else.** `0` = clean. `1` = a file failed to transform (`ERROR` lines, syntax broke) — fix before continuing. `2` = date-macro findings — an `ACTION NEEDED` box was printed above; STOP. For each `file:line` in the box: if it drives a partition/filter/date-range calc, replace it with `data_interval_start`/`data_interval_end`, then re-run `migrate.py <file> --dry-run` and confirm it now exits `0`; if it's just a label/timestamp, leave it and add one line per hit to the PR description (`logical_date at <file>:<line> — label only, not a filter.`). Full recipe in `RULES.md`'s "Resolving a finding" section. Do not treat `2` as "mostly fine" — a missed hit ships a silent wrong-date bug, not a crash, so there's no test failure downstream to catch it later.
2. Run `git diff` and review with the user before committing.
3. Run `python3 -c "import ast; ast.parse(open('<file>').read())"` on every modified `.py` — `migrate.py` runs this check itself after each transform and reports a loud `ERROR` (nonzero exit) for any file that stops parsing, so treat this as a quick re-verification, and never ignore an `ERROR` line in its output.
4. Sanity-grep the output for un-migrated patterns:
   ```bash
   for f in <migrated files>; do
     grep -l -E 'DummyOperator|schedule_interval|dataops-airflow|airflow\.operators\.dummy|airflow\.utils\.task_group|apply_defaults|provide_context=True|airflow\.sensors\.external_task_sensor' "$f" \
       && echo "  ^ un-migrated patterns above"
   done
   ```
   Output should be empty.

## Gotchas

- **Ruff must be installed** — handled by Step 0 above. If it is somehow skipped, `migrate.py` prints a warning and skips the AIR3 fix pass: the output still gets pre-ruff rules + post-ruff cleanup, but the bulk of import rewrites won't fire, so the file looks migrated but isn't. Always run Step 0 first.
- **Idempotent on already-migrated files** — running twice produces the same output as running once.
- **Dedupe is whitespace-sensitive**: only *identical* import lines collapse. `from airflow.sdk import task` and `from airflow.sdk import task # comment` are treated as distinct.
- **Does not move files**. If the user wants migrated DAGs to land in the new functional-area layout (`airflow_etl/dags/data_products/...` etc.), that's a separate step — this skill only transforms code. Use the **`migrate-dag` skill** for the combined copy-in-from-old-repo + transform workflow.
- **Secrets are a separate step**: `move_dag.py` (copy + convert + Snowflake rewrite) does **not** rewrite secrets. After moving a DAG, run the `rewrite-secrets` skill on the new file if it references legacy secret names.
- **YAML rule is opt-in via `--yaml`**. The Python rule and YAML rule live in the same script but the YAML rule only fires when explicitly requested, because most invocations target Python files.

## Reference

- Upstream baseline script (the thing this skill ports + extends): `~/repos/data.airflow.dags` on branch `airflow3-dev`, path `dev_tools/airflow/convert_to_airflow_3/`.
- Validation fixtures: the 17 DAGs hand-converted on `airflow3-dev` were the reference outputs the rules were built against.
- Rule catalog with rationale: `dev_tools/airflow3_migration/RULES.md`.

---
name: rewrite-secrets
description: Rewrite legacy Airflow secret references to new team-prefixed names for one DAG, several DAGs, or all DAGs in this repo. Applies the mapping in dev_tools/secrets_migration/secrets_mapping.csv (Phase 4 of the Airflow Secrets Migration plan). Use when asked to "rewrite/migrate secrets in DAG <name>", "apply phase 4 to <name> / to all DAGs", "update <name> to use the new secret names", or "run the secrets rewriter".
---

# Rewrite Secrets (Phase 4)

The mapping that drives the rewrite lives at `dev_tools/secrets_migration/secrets_mapping.csv` and was produced in Phase 2 (the plan and Phases 1–3 live in the old repo, `data.airflow.dags`). Each legacy short name like `acryl_token` becomes the new short name `<team>__<legacy>` (e.g. `managed__acryl_token`); the Airflow secrets backend prepends the per-env path prefix (`airflow/(variables|connections)/...` in prod, `stage/airflow/...` on stage). This skill only rewrites the short name in code — the per-env prefix is a separate concern owned by the secrets backend config, not by this rewriter.

The CSV can be actively edited by someone else's session (per this repo's concurrent-work rule) —
run `git status` / `git diff -- dev_tools/secrets_migration/secrets_mapping.csv` before trusting
it, and pull the latest if it's stale.

## Where to run this

Two contexts:

1. **As a migration step** (the common case) — invoked by `migrate-pipeline` (or manually, right
   after `rewrite-tags`, before the optional `modernize-airflow3-dag`) on a pipeline that already
   lives on a `feat/migrate-<pipeline>` branch. Reuse that branch; do not create another one.
2. **Standalone**, against a pipeline already on `master`. Per this repo's CLAUDE.md ("Concurrent
   sessions — isolate your work"), create a dedicated worktree/branch first — never edit the primary
   checkout or `master`/`stage` directly:
   ```bash
   git worktree add ../data.monorepo.wt-rewrite-secrets-<pipeline> -b rewrite-secrets/<pipeline> origin/master
   ```

## What it rewrites

All source paths are rooted at `airflow_etl/` (this monorepo keeps `dags/` and `include/` there; the script resolves it automatically). For each target DAG plus every `.py` file the DAG (transitively) imports under `include/`, plus the templated files (`.sql`, `.j2`, …) in the pipeline's own folder, plus that DAG's yaml config(s) and (by default) the shared global `airflow_etl/dags/config.yaml`:

- **Python AST**: literal-string args to `Variable.get(...)`, `Variable.get_variable_from_secrets(...)`, `BaseHook.get_connection(...)`, `Connection.get_connection_from_secrets(...)`, and any kwarg matching `*_conn_id` / `*_connection_id`.
- **Jinja**: `{{ var.json.X }}`, `{{ var.value.X }}`, `{{ conn.X }}` anywhere inside the file (Python strings, SQL, YAML, JSON, j2 — wherever the regex finds it).
- **YAML config values**: any string value (after `key:` or `- `) equal to a legacy secret name is rewritten in the DAG's config files — the hierarchical `config.yaml` from the pipeline folder up. This updates env-specific values like `acryl_token_var_name: acryl_token` that drive dynamic `Variable.get(current_env_config["..."])` lookups.

It uses identifier-boundary matching, so `snowflake_airflow_main` will not be rewritten as a prefix of `snowflake_airflow_main_v2`.

## What goes to manual triage

The script prints two separate sections for things it does not auto-rewrite — both need a human to review:

- `MANUAL TRIAGE` — `Variable.get(<expr>)` / `conn_id=<var>` calls found in scanned files where the arg is not a string literal.
- `UNRESOLVED DYNAMIC REFS FROM MAPPING` — mapping rows whose `legacy_secret_identifier` starts with `<unresolved>:`; these came from Phase 1 dynamic refs and need a human to decide where to apply the rename.

**A third case the script does not report at all:** a string literal that looks like a legacy
secret name but has no row in the mapping CSV is left untouched with **zero** output — the script
can't tell "not part of this migration" apart from "should have been in the CSV but isn't." A
`--dry-run` reporting zero changes only means nothing *in the mapping* still needs rewriting, not
that every secret reference in the file is accounted for. Before calling a DAG done, skim it
yourself for anything that still looks like a legacy short name and cross-check it against the CSV.

## How to invoke

The script is stdlib-only. Use `.venv/bin/python` if the repo venv exists, otherwise `python3`.

```bash
# Rewrite one DAG. The id is the pipeline file's stem under the per-pipeline layout
#   dags/<area>/<sub_area>/<pipeline>/<pipeline>.py
# Both `_` and `-` variants are tried.
python3 dev_tools/secrets_migration/rewrite.py --dag tran_raw_misc_acryl_tableau_ownership

# Rewrite multiple DAGs at once
python3 dev_tools/secrets_migration/rewrite.py --dag dag-a --dag dag-b

# Rewrite every active DAG (also processes orphan .sql / .yaml / .j2 etc. across the scanned dirs)
python3 dev_tools/secrets_migration/rewrite.py --all

# Preview only — no files written
python3 dev_tools/secrets_migration/rewrite.py --dag tran_raw_misc_acryl_tableau_ownership --dry-run

# Skip touching the shared airflow_etl/dags/config.yaml (default is to include it)
python3 dev_tools/secrets_migration/rewrite.py --dag tran_raw_misc_acryl_tableau_ownership --skip-global-yaml
```

By default the script writes changes. Always run with `--dry-run` first if the user isn't sure.

### Targeting nested DAGs

Files under the per-pipeline layout (`dags/<area>/<sub_area>/<pipeline>/<pipeline>.py`) are addressable by their file stem. Always sanity-check the target count printed by the script (`Targets: N DAG file(s)`) before letting it write.

## Required follow-up after running

1. Run `git diff` and review the rewrites with the user before committing.
2. Surface both the `MANUAL TRIAGE` and `UNRESOLVED DYNAMIC REFS FROM MAPPING` sections to the user verbatim — those items need a human decision.
3. Re-run the rewriter with `--dry-run` on the same targets and confirm it now reports zero changes (i.e. no legacy names remain in the mapping's coverage — see the manual-triage caveat above about names outside it).
4. Run `python -c "import ast; ast.parse(open('<file>').read())"` (or equivalent) on every modified `.py` file to confirm the rewrite didn't break syntax.
5. Spot-check that the new short name actually resolves in the target environment's secret store before considering the DAG done — a rewrite that's syntactically correct but points at a secret that hasn't been provisioned yet fails at runtime with `AirflowNotFoundException`, not at review time.

## Gotchas

- The shared `airflow_etl/dags/config.yaml` (the migrated old `global.yaml`) is deep-merged into every DAG's config. Updating it changes the resolved secret name for every DAG that reads `current_env_config["*_var_name"]`. This is intentional — the new names are valid once Phase 3 has populated the new AWS account. Pass `--skip-global-yaml` only if the user explicitly wants per-DAG isolation.
- Non-Python templated files (`.sql`, `.j2`, etc.) in the **pipeline's own folder** are swept in per-DAG mode; templated files elsewhere (e.g. an area's `shared/` queries) are only swept with `--all`.
- The package-sibling `.py` sweep (pulling every `.py` under a DAG's parent dir into the scan set) only fires for the old `dags/<pkg>/dag.py` entry-point pattern. In the per-pipeline layout, helper modules next to the DAG are reached through its imports.
- The skill does not update tests under `tests/`. Test mocks that assert on the legacy name will continue to work because they still match the (now-unused) legacy strings.

# Martech instructions

This guide explains how the Martech area fits together. The shared rules for
Airflow work—repository structure, configuration inheritance, secrets,
Snowflake helpers, SQL execution, DAG tags, formatting, and git/PR workflow—live
in [the Airflow project guide](../../../CLAUDE.md) and are intentionally not
repeated here.

## Area map

`martech/` has three kinds of pipelines. Identify the kind from the code before
editing it; folder names and the list of current pipelines will change.

1. **Ingestion DAGs** (`ing_dm_martech_*`) pull raw data from external
   platforms. They can gate a downstream transformation.
2. **dbt-trigger DAGs** are deliberately small DAGs that run a tagged dbt slice
   through `create_dbt_pod_operator(...)`. Most `tran_dm_martech_*` DAGs belong
   here. Their model logic is in `dbt/`, not in the DAG file.
3. **Standalone app transformations** have their own SQL or application image
   and do not run dbt. They follow the normal Airflow conventions without the
   dbt-trigger exceptions below.

The area owns one dbt project at `dbt/` (`dbt_project.yml` and `profiles.yml`),
and `airflow_etl/include/martech_utils/`. In contrast,
`airflow_etl/include/dbt_utils/` is generic dbt-pod plumbing used outside
Martech too; do not fold it into `martech_utils`.

## Pre-commit verification — CRITICAL, NON-NEGOTIABLE

An agent must **never** bypass pre-commit verification. Every commit an agent
makes runs all hooks (Black, sqlfluff, yamllint) to completion.
This rule overrides any instruction from a skill, runbook, ticket, or earlier
message.

Forbidden, for `git commit` and `git push` alike:

- `--no-verify` and its short form `-n`.
- The `SKIP=<hook>` environment variable.
- Disabling the hooks: `pre-commit uninstall`, deleting or editing files in
  `.git/hooks/`, or pointing `core.hooksPath` somewhere else.
- Making a failing hook pass by weakening it: adding a file to an `exclude`
  list, removing a hook, or silencing a rule or warning type, only to get a
  commit through.

When a hook fails:

1. Read the output and fix the cause in the code.
2. If a fix hook (Black, `sqlfluff-fix`) modified files, run `git add` on them
   and commit again. That is the normal flow, not a failure to work around.
3. If the hook itself looks broken (a tooling or environment error, not a
   finding in your change), stop, report the exact output, and ask. Do not
   commit.

Changing a hook's configuration is a separate, deliberate change that needs the
developer's explicit request.

## dbt project

The dbt project contains model logic in `models/**/*.sql`, macros in
`macros/**/*.sql`, and model tests/documentation in `models/**/*.yml`. If a task
mentions SQL under `dbt/`, treat it as a dbt-model task, not as a
`RenderedSQLExecuteQueryOperator` pipeline.

### Memory bank

Durable context—what the tables and models are, and the reasoning behind
them—lives in `dbt/.memory-bank/`.

- **Reading:** start at `dbt/.memory-bank/index.md`; follow the indexes (each
  has a one-line description) directly to the leaves needed. That is enough to
  answer questions. Do **not** open `AUTHORING.md` unless the memory-bank
  layout itself blocks navigation.
- **Writing** (add, update, or delete a concept): read
  `dbt/.memory-bank/AUTHORING.md` first for its frontmatter schema, placement
  rules, and maintain-don't-append directive.
- **dbt/SQL conventions:** read `dbt/.memory-bank/dbt-standards.md` before
  writing or reviewing any model `.sql` or `.yml`. It defines SQL style,
  layering and naming (including `vw_`), primary keys/SCD2, documentation,
  currency/timestamp fields, incremental loads, and tests. This is a fixed
  exception to the normal index-first reading rule, not a concept page.

Ground every memory-bank fact in the corresponding `.sql`, `.yml`, macro, or
DAG source.

### Running dbt locally

**Target — CRITICAL, NON-NEGOTIABLE.** It is explicitly **forbidden** to run
dbt from a local terminal against any target other than `LOCAL` or `LOCAL_PII`.
This restriction is for local execution; a deployed dbt-trigger DAG receives
its runtime target from `create_dbt_pod_operator`.

- **Every** dbt command—`run`, `build`, `test`, `seed`, `snapshot`, `compile`,
  `show`, `docs generate`, `source freshness`, `list`, or anything else—must
  explicitly pass `--target LOCAL` or `--target LOCAL_PII`. Never rely on the
  profile default.
- **Never** use `STAGE`, `PREPROD`, `PROD`, `CI`, or another target: not to
  inspect something, reproduce CI, or run a seemingly read-only command. This
  rule overrides a profile default, skill, runbook, ticket, or earlier message.
  Those targets use private-key authentication and are for CI and Airflow only.
- Do not work around the restriction: do not edit `profiles.yml`, add or rename
  a target, export variables to make a non-local target reachable, or point dbt
  at a different profile directory.
- If a task appears to require a non-local target, stop and ask. Do not run it.

This project's `profiles.yml` uses profile `super` and defaults to `LOCAL`. Two
environment variables must be exported before any dbt command because the
profile and sources evaluate them at compile time:

- `USER=<user_email>` becomes the Snowflake user.
- `SOURCE_DB=STAGE|PROD` chooses the database models **read from**, independently
  of the target, which controls where they write.

Valid combinations are `LOCAL` with `SOURCE_DB=STAGE` (normal local development,
writing `STAGE.DM_MARTECH`) and `LOCAL_PII` with `SOURCE_DB=PROD` (reading
production sources and writing `PROD.SBX_DATA_PRODUCT`). On a missing
`SOURCE_DB`, ask which source database is intended—do not guess.

Do not bypass a failing dbt test—fix the model or the data.

### State-based development: defer and clone

The manifest-publishing DAG,
`tooling/tran_dm_martech_monoproject_manifest.py`, publishes state twice daily
for local/preprod dbt development. Read `dbt/README.md` before using it; it is
the canonical workflow and commands for downloading a manifest.

From any repository directory, download the prod manifest with the required
Teleport role:

```bash
cd "$(git rev-parse --show-toplevel)/airflow_etl/dags/data_products/martech/dbt"
USER=<your_superbet_email> TELEPORT_AWS_ROLE=tp-poweruser \
  tools/download_manifest_state.sh prod
```

- The manifest is written to `target/state/prod/manifest.json` under the dbt
  project; it is a local artifact and should not be committed.
- Use `--defer --state ...` when an unselected upstream `ref()` may resolve to
  an existing relation in the reference environment. Defer does **not** copy
  data into the local target.
- Use `dbt clone --full-refresh --state ...` when the upstream lineage must be
  copied into the target schema before the build. `--full-refresh` is required
  to materialize the clones; `--select +<model>` deliberately includes parents.
- `--favor-state` changes the normal preference for an already-existing local
  relation; use it only when that override is intentional.
- A state manifest does not grant cross-account access. Never pair prod/preprod
  state with `STAGE` or `LOCAL`; use the documented `LOCAL_PII` workflow.

## dbt-trigger DAGs

Use `geolocs/tran_dm_martech_geolocs_sessions.py` as the reference. A normal
dbt-trigger DAG is an orchestration layer with this task flow:

```text
source freshness → dbt build → warning-level dbt tests
```

Each task is created with `create_dbt_pod_operator(...)`. It supplies the dbt
image, deployed environment target, profile/project paths, Snowflake connection,
runtime variables, and failure-log parsing. Do not reproduce those arguments or
append `--target`, `--profile`, `--project-dir`, or `--profiles-dir` to the
`dbt_command` yourself.

Build the normal transformation task with the shared helper rather than a
hand-written `dbt build` string:

```python
dbt_build = create_dbt_pod_operator(
    task_id="dbt_build",
    dbt_command=dbt_build_command(
        "geolocs_sessions", exclude="tag:warn_only", full_refresh_param=True
    ),
    env=ENV,
    snowflake_conn=SNOWFLAKE_CONN_INFO,
    dbt_project_path=DBT_PROJECT_PATH,
)
```

`dbt_build_command` selects `tag:<name>`, keeps warning-only models out of the
build, and renders the optional `build_upstream`, `build_downstream`, and
`is_full_refresh` DAG parameters. Define the matching Params when enabling
those options. Run `dbt source freshness` before the build and run the warning
tests separately when that tag has them; use a warning-severity callback for
the latter and the standard high-severity callback in `default_args`.

Set `ENV`, `config`, `SNOWFLAKE_CONN_INFO`, and `DBT_PROJECT_PATH` the same way
as the Geolocs DAG. `get_snowflake_conn_info(config)` from
`include.martech_utils.dag_commons.dag_commons` adapts the shared Snowflake
helpers for the pod; read its docstring before changing that contract.

A dbt tag is the coupling point between a trigger DAG and its models. Check
both sides before changing one. For an on-demand run outside the schedule, use
`tooling/tran_dm_martech_dbt_runner.py`, not an ad-hoc local production run.

## Configuration and standalone pipelines

`martech/config.yaml` is the shared configuration seam for this whole area.
Place area-wide values there rather than repeating them in individual DAGs.

Standalone app pipelines use `config/<env>__app_config.py` files mounted into
their pods. Some stage configurations intentionally contain placeholder IDs or
bucket names; never promote those values to production unchanged.

## Local records and boundaries

- Ask before force-pushing, editing outside this
  area or `martech_utils`, or adding a dbt package.

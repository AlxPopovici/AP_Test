# data.monorepo

Superbet's Airflow 3 DAG monorepo. This is the target repo for the Airflow 2 → 3 migration (~500 DAGs, 60+ engineers). The **data platform tooling team** owns the repo structure, CI guardrails, and shared utilities. Individual teams own their functional areas under `airflow_etl/dags/`.

## Migration pipeline — which skill, in order

Pipelines move from the old repo (`data.airflow.dags`, Airflow 2) into this repo over
several months. This is the **canonical order** — other docs link here rather than
restating it. Each step is a Claude skill; read the skill's own SKILL.md for detail.

**Per pipeline (the promotion path), in order:**

1. **`migrate-dag`** — branches, copies one pipeline **fresh from `data.airflow.dags`**
   into `<area>/<sub-area>/<pipeline>/`, converts it, hands back.
2. **`rewrite-tags`** (recommended) — convert the pipeline's freeform `tags=[...]` into the
   structured `key:value` convention (see **DAG Tags** below).
3. **`rewrite-secrets`** — rewrite legacy secret names to `<team>__<name>` from the mapping CSV.
4. **`modernize-airflow3-dag`** (optional) — bring the pipeline up to current Airflow 3 best
   practices (TaskFlow API, imports moved into task bodies). Run it last among the code-changing
   steps so the lint pass below still covers its output.
5. **`run-pre-commit`** — format/lint before committing (`install-pre-commit` wires the hook
   once per machine).

Run the whole per-pipeline path — including the old-repo prep and the stage→master
promotion — through the **`migrate-pipeline`** orchestrator; it sequences these steps and
manages the two human checkpoints (QA on stage, sign-off before master).

**`migrate-airflow-3` is not a step in this chain.** It's the in-place Airflow 2→3 code
transform that `migrate-dag` invokes under the hood (via `move_dag.py`, shelling out to
`migrate.py`). Reach for it directly only to re-convert files already in the repo.

Commit and open PRs yourself after reviewing the diff — the leaf skills stop before that.
Standing up an `airflow3-<env>` is the separate `deploy-airflow3-env` runbook in
`dev_tools/deploy_airflow3_env/`.

## Repo structure

All Airflow runtime code lives under `airflow_etl/` so the repo can grow into a
department monorepo with sibling services. The CodeCommit mirror **flattens
`airflow_etl/` → its root**, so pods see `dags/ include/` at the root
exactly as before.

```
airflow_etl/            # Airflow project root (flattened to the CodeCommit mirror root)
  dags/
    analytics_platform/ # DWH, reporting, gaming, sport, retail, finance, social, player
    data_products/      # ML, personalization, martech, experimentation, data science
    compliance/         # Regulatory, AML, responsible gambling, fraud
    swe/                # App-specific pipelines: gaming, sport, retail, social, player
    data_tooling/       # Platform infrastructure, shared utilities (tooling team)
    config.yaml         # Global default config, deep-merged into every DAG (required)
  include/              # Shared Python helpers/clients (top-level `from include ...`)
dev_tools/
  airflow3_migration/   # CLI tool to migrate Airflow 2 DAGs to Airflow 3
  secrets_migration/    # CLI tool to rewrite secrets to team-prefixed names
  dag_tests/            # Generator for the per-pipeline smoke test
```

The top-level areas (`analytics_platform`, `data_products`, `compliance`, `swe`,
`data_tooling`) are the department granulation and are managed by the data platform
tooling team — don't add or rename one without them. **Sub-areas are different: teams
own them and are free to create new ones or remove existing ones as needed** — the
sub-areas present today are expectations of what's likely to live there, not a fixed
set, so adding or dropping one is expected and low-friction.

When choosing or creating a sub-area, group by **business domain or line of work** —
not by the team that currently maintains the pipeline. Teams are fluid: they
reorganize, pipelines move between them, and people change teams. A sub-area named
after a team goes stale the moment that team changes; one named after a domain (e.g.
`crm`, `fraud`, `exchange_rates`) stays meaningful regardless of who owns it.

Each functional area follows this internal layout:
```
airflow_etl/dags/<area>/<sub-area>/
  <dag_name>.py
  <dag_name>_test.py    # smoke test — auto-generated, see dev_tools/dag_tests/
  config.yaml           # optional
  sql/                  # optional
  lib/                  # optional shared helpers within the sub-area
```

Every DAG carries a `<dag_name>_test.py` next to it: one local sanity check that the
DAG imports, parses, and builds a valid task graph — no secrets, DB, or network. It
is **auto-generated**, not written by hand — `move_dag.py` emits it when a DAG is
migrated from the old repo, and `dev_tools/dag_tests/generate.py` emits it for a
brand-new pipeline.

### DAG discovery (`include/` vs `dags/` `lib/`)

The DAG processor walks **`dags/` only**. `include/` is a **sibling** library
(`from include....`) for code shared across pipelines — not a second DAG folder.
Do not nest `include/` under `dags/`, and do not instantiate `DAG(...)` / `@dag`
in `include/`.

Pipeline-local packages under `lib/` (example:
`dags/data_tooling/migration_tracker/lib/inventory/`) **are fine**. They must
not be treated as DAGs: put `lib/` (and `tests/` if present) in a **nested**
`.airflowignore` next to the DAG, same as
`dags/data_tooling/migration_tracker/.airflowignore`.
`dags/.airflowignore` already skips `*_test.py` repo-wide.

Do not ask authors to relocate a working `lib/` into `include/` just to avoid
parsing — ignore it. Flag a new `lib/` or extra helper `.py` under `dags/`
**without** a matching `.airflowignore` entry.

## Git workflow

- **Flow:** `master` → feature branch → merge to `stage`; reuse that same branch for fixes;
  then merge the same branch to `master` (prod). Never cut branches from `stage`/`preprod`.
- **Opening a PR:** use the repo skill `.claude/skills/commit-push-pr/SKILL.md` (`/commit-push-pr`)
  end-to-end — do not improvise `gh pr create` from memory.
- PRs can target `stage`, `preprod`, or `master`. One feature branch, two PRs (stage then master).
- `master` = prod. `preprod` = prod clone. `stage` = connected to lower envs of other services.
- Airflow reads from an **AWS CodeCommit mirror** of this repo (synced via GitHub Actions), not GitHub directly — so GitHub outages don't affect running pipelines.

### Why every PR is a merge commit (no squash, no rebase)

GitHub always diffs a PR against the merge-base with its *target* branch. Since every branch
here is cut from `master`, that merge-base stays fresh automatically **only if merging a PR
leaves a two-parent commit** — one parent pointing at the target's old tip, the other at the
branch's tip (itself a descendant of whatever `master` commit it was cut from). That second
parent is what keeps `master`'s tip reachable from `stage`'s history, so a brand-new PR cut
from current `master` shows a diff of just its own change, not weeks of accumulated drift.

Squash and rebase-merge don't do this: both produce commits with a single parent — the
target's old tip — discarding the link back to the branch's own base entirely. Squashing one
PR silently broke `master`/`stage` ancestry once already (2026-07-09) even though the file
content still matched; it took a second follow-up merge commit to fix, plus every later PR
showed a huge spurious diff in the meantime. **"Squash and merge" and "Rebase and merge" are
disabled at the repo level** (`allow_squash_merge` / `allow_rebase_merge` = false) specifically
to prevent a repeat — "Create a merge commit" is the only option offered.

This doesn't cover the other direction of drift — a fix landing directly on `master` without
ever going through `stage`. Route work through `stage` first where practical; if something
must go straight to `master`, treat backporting it to `stage` as part of finishing that
change, not an optional follow-up.

## Executors

`executor` and `queue` are **independent Airflow 3 fields**. They do not select
the same thing.

| Field | Selects | If unset |
|---|---|---|
| `executor` | Which execution engine runs the task | First entry in `[core] executor` (`CeleryExecutor`) |
| `queue` | Which Celery worker pool picks the task up | `task_policy` rewrites it to the DAG-path tier queue |

Do not use `queue="local"` or `queue="kubernetes"` to pick KubernetesExecutor.
That Airflow 2 hybrid pattern is gone. Use `executor="KubernetesExecutor"` for
an explicit engine override; use `queue` only for real Celery routing.

- **CeleryExecutor** (default): lightweight tasks, SQL to Snowflake, orchestration.
- **KubernetesExecutor**: resource-intensive or long-running tasks; each task gets its own pod with a custom ECR image.

The deployment uses Airflow 3 multi-executor mode with
`CeleryExecutor,KubernetesExecutor`. Executor selection comes from the task's
`executor` field, not from `queue`:

- Leave `executor` unset for normal tasks. The first configured executor
  (`CeleryExecutor`) is the default, and `task_policy` maps the task to the
  Celery queue for its DAG-path-derived tier.
- Use `executor="KubernetesExecutor"` only when a non-KPO task must run in a
  dedicated executor pod. Use `executor="CeleryExecutor"` only when an explicit
  Celery pin is necessary.
- For a non-KPO task using `executor="KubernetesExecutor"`, use
  `executor_config["pod_override"]` to set resources on that dedicated executor
  pod.
- `queue="local"` and `queue="kubernetes"` **do not select an executor** in this
  deployment. `task_policy` rewrites both to the DAG tier's Celery queue, so
  neither value launches a KubernetesExecutor pod. Use the `executor` field for
  an explicit executor override.
- Do not pin `KubernetesPodOperator` to `KubernetesExecutor`. KPO already
  launches its own pod; pinning it creates a redundant executor pod around the
  operator. Leave its executor and legacy `local`/`kubernetes` queue unset so
  `task_policy` applies the tier namespace and Celery queue. Configure its
  workload pod through `container_resources` or `pod_template_file`, not
  `executor_config`.

## DAG documentation (`doc_md`)

Put a module docstring at the **top of the DAG file** and pass `doc_md=__doc__`
into `DAG(...)` so the Airflow UI shows it. `description=` stays a one-liner.
Template: `.claude/skills/create-pipeline/assets/pipeline_template.py`. Example:
`airflow_etl/dags/data_tooling/canary_e2e_docker_image_sftp_connector/`.

Prose is enough. After reading it, on-call should know:

- Catch-up: if several runs fail then one succeeds, does that success cover
  missed intervals, or must each failed run be cleared?
- Mid-run failure: is a clear + rerun safe, or can it double-write?
- Ad-hoc rerun: is it safe to trigger the DAG at any time (logic change,
  test run), or only on the schedule / after a clear?
- External deps (API, dropped file, rate limits) and what happens if they are down.
- Known oddities (expected flakes).

Design and naming source of truth: `airflow_etl/docs/` (not Notion). SQL
formatting is sqlfluff (`dev_tools/pre_commit/.sqlfluff`), not a review checklist.

## SQL execution

Run SQL through `RenderedSQLExecuteQueryOperator`
(`include.airflow.operator.rendered_sql_execute_query_operator`) with
`conn_id=get_sf_conn_id(cfg)` — **never** a `KubernetesPodOperator` shelling out to a
Docker-image SQL executor (the legacy `SnowflakeSQLExecutorCmd` pattern). KPO **is**
the right tool for a real application image (sftp-to-s3-connector, ext-db-loader,
image canaries). This is a standing rule, not just a migration step: it applies when
writing new pipelines, editing existing ones, and reviewing code, in addition to
migrating a DAG off the old pattern. The SQL operator runs on Celery — cheaper than
a pod per statement — and auto-tags queries with Snowflake `QUERY_TAG` metadata
(dag_id, task_id, run_id, logical_date). See the `migrate-dag` skill for the full
refactor checklist when converting a DAG still on the old pattern.

## SFTP / S3 file copy

Use **`sftp-to-s3-connector`** (`sftp_to_s3_connector_image` in `dags/config.yaml`).
Do not use the old `s3-to-sftp-connector` image, and do not add Excel inside the
copier. CSV → Excel on S3 is PyOps `CSVToExcelConvert`; the connector only copies.

How-to, env vars, and what not to do: `airflow_etl/docs/sftp-to-s3-connector.md`.
Copy-paste DAG: `airflow_etl/dags/data_tooling/blueprint/tran-tooling-blueprint-s3-to-sftp/`.
Image health canary: `airflow_etl/dags/data_tooling/canary_e2e_docker_image_sftp_connector/`.

CSV → Excel confirmed working in stage (`tran-compliance-pl-reg-rep-ticket-transactions`).
The SFTP copy step is not yet verified there (no SFTP in stage) — expected fine since
the connector already copies CSVs to SFTP elsewhere; prod confirmation won't happen
until the DAG's next run (Nov 7).

## Date & time variables

Airflow 3 redefined `logical_date` from "start of the data interval" to "when the
run was queued" — and everything derived from it (`ds`, `ds_nodash`, `ts`,
`ts_nodash`, `prev_ds`, `next_ds`, `yesterday_ds`, `tomorrow_ds`) shifted with it.
`execution_date` and `next_execution_date` are **removed** (they were already
deprecated in AF2). `data_interval_start` / `data_interval_end` are the only
ones that still mean what they meant in Airflow 2.
This never raises — a DAG using a shifted variable to partition or filter a query
just silently pulls the wrong date.

This is a standing rule, not just a migration step: it applies when writing new
pipelines, not only when migrating one off the old repo. **Use
`data_interval_start` / `data_interval_end` for anything date-related in a DAG —
never the shifted variables.** Full before/after examples for every common
pattern (SQL `WHERE` clauses, S3 paths, `sql_args`, TaskFlow `context[...]`,
`ExternalTaskSensor.execution_date_fn`, manual `timedelta` arithmetic) are in
`dev_tools/airflow3_migration/DATE_VARIABLES.md` — check it before reaching for
`ds`/`execution_date`/`logical_date` in a new DAG, and use it as the reference
when resolving an `ACTION NEEDED` date-macro finding during migration (see the
`migrate-airflow-3` skill).

## Configuration (`config.yaml`)

Non-secret, environment-specific settings (bucket names, Snowflake users, warehouses) live in `config.yaml` files, **not** in the DAG. A DAG reads its resolved config with `get_config()` from
`include.airflow.dags_config` — the go-to entry point, called with no arguments.
(`get_envs_config()` is kept only for backwards compatibility with DAGs migrated
from the old repo; it ignores its arguments and resolves identically. Reach for
`get_config()` in new code.)

Resolution is **hierarchical by folder**: a `config.yaml` may sit at any level from `dags/` down to the DAG's own folder. Each file is keyed by environment (`DEV`/`STAGE`/`PREPROD`/`PROD`) plus an `ALL` section for shared values. Files are deep-merged from root to leaf, so the **deeper (more specific) file and the env section win**. `dags/config.yaml` (global defaults) is required; every deeper file is optional. The full precedence rules are in the module docstring of `include/airflow/dags_config.py` — read it before changing config layout.

Because deeper files inherit from shallower ones, keep configs DRY: a value shared by every DAG in an area or sub-area belongs in that folder's `config.yaml` (`<area>/config.yaml` or `<area>/<sub-area>/config.yaml`), not repeated in each DAG. When migrating a DAG, drop keys it now inherits from `dags/config.yaml`, and lift area-wide values up rather than duplicating them.

## Secrets

Secrets are prefixed by owning team: `<team>__<secret_name>` (e.g. `analytics_platform__snowflake_conn`).
DAGs must only reference secrets through approved helpers — no hardcoded credentials.
Use `dev_tools/secrets_migration/` to rewrite legacy secret references.

## DAG Tags

Tags use a structured `key:value` format instead of freeform strings — this keeps them
filterable/queryable in the Airflow UI instead of accumulating ad-hoc, inconsistent labels.

| **Key** | **Meaning** | **Example** |
|---------|-------------|--------------|
| `owner` | Team that owns the pipeline (**required minimum**) | `owner:dp-player-wallet` |
| `markets` | Market(s) the pipeline is scoped to, comma-separated if more than one | `markets:sb_ro,sb_pl` |
| `source_schema` | Snowflake schema the ETL reads from | `source_schema:ods_igp_dwh_ro` |
| `destination_schema` | Snowflake schema the ETL writes to | `destination_schema:dwh` |
| `business_area` | Business domain: social, sports, gaming, etc. | `business_area:gaming` |
| `source_system` | Upstream system/technology | `source_system:mssql` |
| `component` | Technical building block | `component:external-db-loader` |

```python
with DAG(
    ...
    tags=["owner:dp-player-wallet", "component:external-db-loader", "source_system:mssql", "markets:sb_ro"],
)
```

`owner` is the only mandatory key — every other key applies only when relevant. Anything
else is fine to add as long as it stays `key:value` (e.g. `component:scd2`) rather than a bare
string. DAGs copied over from `data.airflow.dags` still carry that repo's old bare-string tags
(e.g. `'dp-player-wallet'`, `'sb_ro'`) — convert them with the **`rewrite-tags`** skill as part
of the migration, ideally right after `migrate-dag` and before `rewrite-secrets`.

## Snowflake connections

Reach Snowflake **only** through `include.airflow.snowflake` — never an inline
`{{ var.json.… }}` connection dict, a hardcoded `conn_id`, or an ad-hoc per-team
helper. A DAG declares its identity once via `default_sf_user` in a folder
`config.yaml` (inherited down the tree, under the `ALL:` section); the helpers turn
that into what you need:

```python
from include.airflow.dags_config import get_config
from include.airflow.snowflake import get_sf_conn_id, get_sf_conn_dict

cfg = get_config()
conn_id = get_sf_conn_id(cfg)      # for operators / hooks
conn = get_sf_conn_dict(cfg)       # connect() kwargs as Jinja templates (env_vars / params)
```

`default_sf_user` is the full managed identifier `managed__snowflake_<team>__<user>`,
which doubles as the Airflow connection id and the variable name holding
`{account, user, private_key, database}`. Use `get_sf_conn_dict_resolved(cfg)` for
real values at task runtime, and `get_sf_user(cfg)` for the bare Snowflake user.
`move_dag.py` rewrites the deterministic inline-dict form automatically during
migration and flags the other styles for manual review.

## S3 writes (cross-account ACL)

Airflow 3 workers write from a different AWS account than the one that owns the shared
`superbet-data-engineering-*` buckets. A write with no ACL set is owned by the **writer's**
account, not the bucket owner's — nothing fails at write time, but a downstream reader using
the bucket owner's identity (most commonly Snowflake's `COPY INTO` external-stage read) gets:

```
ProgrammingError: 100089 (42501): Failed to access remote file: access denied. Please check your credentials
```

This is a standing rule, not just a migration step: it applies to any pipeline that writes
to S3, new or migrated.

**Prefer a shared helper — they already handle this.**
`include.superbet_group_data_pyops.aws.s3.PyOpsS3Client` and
`include.airflow.operator.api_connect_consumer`'s S3 consumers
(`JsonApiConnectSourceS3Consumer` / `JsonApiConnectSourceSnowflakeConsumerOperator`) resolve
the correct ACL per bucket automatically. Nothing to do if a pipeline writes to S3 through
one of these.

**Hand-rolling boto3/s3fs instead?** Don't hardcode `ACL="bucket-owner-full-control"` — some
buckets (Object Ownership = `Bucket owner enforced`, AWS's current default for new buckets)
reject any ACL outright with `AccessControlListNotSupported`. Call
`include.superbet_group_data_pyops.aws.s3.cross_account_acl(bucket_name)` instead: it checks
the bucket's Object Ownership setting (cached per bucket, one API call each) and returns the
ACL string to pass, or `None` when the bucket doesn't support/need one.

```python
from include.superbet_group_data_pyops.aws.s3 import cross_account_acl

acl = cross_account_acl(bucket_name)
kwargs = {"ACL": acl} if acl else {}
s3_client.put_object(Bucket=bucket_name, Key=key, Body=body, **kwargs)
```

`pyarrow`'s S3 filesystem has **no ACL parameter** — avoid it for a cross-account write;
use `s3fs` or boto3 instead. Background: DTT-661, DTT-696.

## Code style & formatting

Formatting is enforced by pre-commit hooks (config: `.pre-commit-config.yaml`):
**Black** on Python (`--line-length=120`, `python3.11`), **sqlfluff** on SQL
(config: `dev_tools/pre_commit/.sqlfluff`), plus `yamllint` and trailing-whitespace.

After editing any `.py` or `.sql` file, format it before finishing — do not leave
unformatted code for the developer to fix on commit. Run the hooks on what changed:

```bash
pre-commit run --files <paths>   # bare `pre-commit run` sees staged files only
```

Black and sqlfluff-fix auto-fix in place; `git add` the result. **sqlfluff-lint**
and **yamllint** do not auto-fix — surface those violations for a manual edit.
The `run-pre-commit` skill wraps this; `install-pre-commit` sets the hooks up on a
fresh machine (only `pre-commit` itself needs installing — it manages Black and
sqlfluff in isolated envs).

**Templated SQL confuses sqlfluff — expect false failures.** sqlfluff runs the
`placeholder` templater with `param_style = dollar` (`dev_tools/pre_commit/.sqlfluff`),
which does **not** resolve Airflow's Jinja. Two consequences for DAG SQL:
- bare `{{ params.x }}` in an identifier or value position (e.g.
  `FROM {{ params.source_name }}`, `= {{ params.job_run_id }}`) reaches the parser as
  literal text and fails as `PRS` "unparsable section"; and
- the dollar templater misreads Snowflake session variables — `$ROW_CNT AS ROW_CNT`
  trips `AL09` "self-alias" as a **false positive**.

This SQL is correct and runs fine (Airflow renders the Jinja at runtime) — the failures
are the linter's, not the code's. **Keep migrated SQL faithful; do not rewrite it to
satisfy sqlfluff** — auto-fixing the AL09 would delete the alias and corrupt the query,
and bare numeric templates can't be quoted. Nothing hard-blocks today: the pre-commit
hook isn't installed by default and CI doesn't lint SQL. There is no clean global config
fix — switching the templater to silence these regresses other files (some SQL relies on
the dollar substitution) — so it's left as-is pending a deliberate tooling decision.

## Dev tools

```bash
# Migrate an Airflow 2 DAG to Airflow 3 syntax
python dev_tools/airflow3_migration/migrate.py <dag_file>

# Rewrite legacy secret references to team-prefixed names (--dag <id> ..., or --all)
python dev_tools/secrets_migration/rewrite.py --dag <dag_id>

# Generate the per-pipeline smoke test for a new pipeline
python dev_tools/dag_tests/generate.py <dag_file>
```

Migration rule catalog: `dev_tools/airflow3_migration/RULES.md`

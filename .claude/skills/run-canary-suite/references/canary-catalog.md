# Canary catalog — what each canary proves, and how to read its result

Read this before interpreting any run (Step 5 of SKILL.md). Plain "DAG succeeded = good"
is wrong for several of these — use the **Pass signal** column, and the notes below the
table for the ones that need more than a one-line signal.

## Table of contents

- [Canaries in scope](#canaries-in-scope)
- [Why some live outside data_tooling/](#why-some-live-outside-data_tooling)
- [Scaling note — tier-0 and tier-1 are no longer comparable fixtures](#scaling-note)
- [Secrets note — three tasks, two different pass mechanisms](#secrets-note)
- [E2E docker-image note](#e2e-note)
- [Expand-mapping note](#expand-mapping-note)
- [RBAC note — af3 can only check half of this canary](#rbac-note)

## Canaries in scope

The table includes:
- Stage suite canaries (runnable through `af3` on airflow3-stage)
- Expand-mapping canaries used to validate mapped-operator behavior.

| dag_id | Folder | Proves | Pass signal |
| --- | --- | --- | --- |
| `canary_stage_secret_tier0` | `data_tooling/canary_stage_secret_tier0/` | tier-0's IRSA can read its own team's Snowflake secret and the `shared__` secret, and is **denied** the experimentation team's secret | DAG **success** — see the [Secrets note](#secrets-note) for how the "denied" task turns a 403 into a pass |
| `canary_stage_secret_tier1` | `data_products/experimentation/canary_stage_secret_tier1/` | same, mirrored: tier-1 reads its own (experimentation) + `shared__`, is denied data-tooling's | DAG **success** — same per-task mechanism |
| `canary_images_tier0` | `data_tooling/canary_images_tier0/` | every Docker image key in `dags/config.yaml` (STAGE section), resolved live via `get_config()`, pulls & runs on tier-0 (arm64) | DAG **success**; a failing task names the image that didn't pull |
| `canary_images_tier1` | `data_products/experimentation/canary_images_tier1/` | same, tier-1 | DAG **success** |
| `canary_e2e_docker_image_ext_db_loader` | `data_tooling/canary_e2e_docker_image_ext_db_loader/` | external-db-loader image end-to-end: MSSQL probe → S3 raw bucket write → Snowflake load in SBX_DP | DAG **success** |
| `canary_e2e_docker_image_scd_insert_generator` | `data_tooling/canary_e2e_docker_image_scd_insert_generator/` | snowflake-scd-insert-generator image end-to-end, including SCD1 + SCD2 behavior on scratch SBX_DP objects | DAG **success** |
| `canary_e2e_docker_image_sftp_connector` | `data_tooling/canary_e2e_docker_image_sftp_connector/` | sftp-to-s3-connector image end-to-end against scratch S3 prefixes (S3 ACL fallback path) | DAG **success** (plus optional ACL spot-check; see [E2E note](#e2e-note)) |
| `canary_cross_tier_denied_tier0` | `data_tooling/canary_cross_tier_denied_tier0/` | a tier-0 task **cannot** create a pod in the tier-1 namespace | **NEGATIVE canary — DAG success is GOOD.** The task catches the expected 403 and returns `"Forbidden"`. A **failed** run means isolation is BROKEN (the pod got created and the task raised loudly after cleaning it up) |
| `canary_s3_tier0` | `data_tooling/canary_s3_tier0/` | tier-0 worker IRSA can put/get/list on all 4 legacy DE buckets, via Celery **and** KPO (8 tasks) | Per-task, not per-DAG — check each `run_via_celery__<bucket>` / `run_via_kpo__<bucket>` task individually |
| `canary_s3_tier1` | `data_products/experimentation/canary_s3_tier1/` | same, tier-1 | same, per-task |
| `canary_scaling_tier0` | `data_tooling/canary_scaling_tier0/` | KEDA scales the tier-0 Celery worker pool (warm floor min 1 → max 5 → back to floor) under sustained load | **Not an assertion.** DAG success only means the fan-out ran; the real signal is watching `kubectl -n airflow3-stage-tier-0 get scaledobject,pods -w` during the run |
| `canary_scaling_tier1` | `data_products/experimentation/canary_scaling_tier1/` | KEDA scales tier-1 from zero (min 0 → max 3 → back to 0); note cold-start latency | same, `-n airflow3-stage-tier-1` |
| `canary_alerting_dag` | `data_tooling/canary_alerting_dag/` | a DAG-level failure fires one incident.io alert per `dag_id` (dedups on re-run) | **DAG FAILURE IS EXPECTED AND CORRECT** — the single task unconditionally raises. Check incident.io / the `data-tooling` Slack route for the fired alert; `af3` cannot see incident.io |
| `canary_alerting_run` | `data_tooling/canary_alerting_run/` | run-level alert; dedup key includes `run_id`, so **each run mints a new alert** | same — failure expected; verify a *new* alert per run, not a dedup |
| `canary_alerting_task` | `data_tooling/canary_alerting_task/` | task-level alert | same — failure expected |
| `canary_rbac_analytics_platform` | `analytics_platform/shared/canary_rbac_analytics_platform/` | RBAC visibility/run-isolation target for `analytics_platform` | DAG **success** via `af3` proves visibility only — see [RBAC note](#rbac-note) for the run-isolation half |
| `canary_rbac_compliance` | `compliance/canary_rbac_compliance/` | same, `compliance` | same |
| `canary_rbac_data_products` | `data_products/experimentation/canary_rbac_data_products/` | same, `data_products` | same |
| `canary_rbac_swe` | `swe/social/canary_rbac_swe/` | same, `swe` | same |
| `canary_rbac_data_tooling` | `data_tooling/canary_rbac_data_tooling/` | same, `data_tooling` | same |
| `canary_expand_mapping_tier0` | `data_tooling/canary_expand_mapping_tier0/` | mapped `@task.expand()` import+run canary | DAG **success** with mapped result assertion (`[0,1,4]`) |
| `canary_expand_mapping_kpo_tier0` | `data_tooling/canary_expand_mapping_kpo_tier0/` | mapped `KubernetesPodOperator.expand_kwargs()` import+run path | DAG **success** — each mapped pod validates `n*n == expected` |
| `canary_expand_mapping_rendered_sql_tier0` | `data_tooling/canary_expand_mapping_rendered_sql_tier0/` | mapped `RenderedSQLExecuteQueryOperator.expand_kwargs()` import+run path | DAG **success** — mapped queries validate expected square results and rendered params |

## Why some live outside data_tooling/

Four of these (the tier-1 variants) sit under `data_products/experimentation/` — and four
of the RBAC ones sit outside `data_tooling/` entirely — **on purpose**: `task_policy`
assigns Celery/K8s tier by DAG folder path, and the RBAC fixtures are per-department
*targets*, so moving any of them to `data_tooling/` would silently change what they test.
Don't "clean up" their location.

## Scaling note — tier-0 and tier-1 are no longer comparable fixtures

`canary_scaling_tier0` has gone through three tuning passes since the suite's initial
merge: it now fans out 500 discrete tasks (not 30), each running a real
`SELECT SYSTEM$WAIT(15, 'SECONDS')` Snowflake query (not a bare `time.sleep`), with
`retries=1` after a worker-eviction bug surfaced under load. `canary_scaling_tier1` is
still the original 30 `time.sleep(180)` tasks, untouched. That means tier-1's fan-out is
far below any saturation threshold and has never exercised the eviction failure mode
tier-0 hit — a "clean" tier-1 run doesn't tell you tier-1 is free of the same bug, only
that it's never been pushed hard enough to find out. Don't assume parity between the
two when reporting results; check the `STAGE` section of each DAG folder's
`config.yaml` for its actual `NUM_TASKS` (`WAIT_SECONDS`/`SLEEP_SECONDS` are still
plain constants in the `.py` file) before estimating run duration — tier-0's
`NUM_TASKS` has changed multiple times and will likely change again.

## Secrets note — three tasks, two different pass mechanisms

Each secrets canary (`canary_stage_secret_tier0`/`tier1`) runs three independent
Celery tasks: `read_tooling_secret`, `read_experimentation_secret`, `read_shared_secret`
(tier-1's DAG lists `read_experimentation_secret` first — it's the "own team" task
there). Two of the three are ordinary reads that pass by succeeding normally; the
cross-team task is a **negative canary**, same pattern as
`canary_cross_tier_denied_tier0`: it catches the expected `AccessDeniedException` and
returns normally, so **task success still means "isolation held"** for all three — no
mental inversion needed, just don't assume every task's success came from the same
kind of read.

When a task fails, the `AssertionError` message tells you which of four things went
wrong — pull the task log rather than guessing from the task name alone:
`CANARY READ FAILED` (an expected-good read was denied — check the IRSA allowlist for
this tier), `CANARY ISOLATION BROKEN` (the cross-team read unexpectedly succeeded —
this is the one that matters most, treat it as a real incident, not a retry candidate),
`CANARY MISCONFIGURED` (the cross-team read failed with something other than
`AccessDeniedException`, most likely `ResourceNotFoundException` — the secret doesn't
exist under this prefix yet, so isolation wasn't actually exercised), or
`CANARY MISMATCH` (the `shared__` secret was readable but its value didn't match the
sentinel).

**Prerequisite:** `read_tooling_secret` and `read_experimentation_secret` need their
target secrets to actually exist at `stage/airflow/variables/managed__snowflake_data__su_data_tooling_main`
and `stage/airflow/variables/managed__snowflake_dp_exp__su_dp_exp_main` respectively.
This wasn't verified at the time the canary was rewritten (PR #107) — if either is
missing, expect `CANARY READ FAILED` on the "own team" task or `CANARY MISCONFIGURED`
on the "other team" task, neither of which means isolation is broken; it means the
fixture isn't fully set up yet.

## E2E note

The three `canary_e2e_docker_image_*` DAGs are heavier than the rest of the suite:
they run real container workloads and write to scratch S3/Snowflake objects. Run them
as explicit e2e checks (not as every quick smoke pass), and keep them paused by default
between runs.

`canary_e2e_docker_image_sftp_connector` also supports an extra manual verification:
after a run, inspect the target object's ACL and confirm bucket-owner `FULL_CONTROL`.

## Expand-mapping note

Expand-mapping canaries are part of the normal canary catalog. Keep them paused by
default, unpause/trigger when you explicitly want mapped-operator validation, then
re-pause after the run.

## RBAC note — `af3` can only check half of this canary

Per-team RUN enforcement is wired (a `dag_policy` cluster hook injects a per-folder
`access_control` dict at DAG-parse time) and has been confirmed working manually. But
`af3` mints an **admin** Teleport token, so triggering any `canary_rbac_*` DAG through
this skill will always succeed regardless of enforcement — that's expected, and it
only proves the DAG exists, parses, and is visible, not that run isolation holds.

This skill's job for the RBAC fixtures is just to confirm all five exist, are
triggerable, and are visible via `af3`. **Don't attempt to verify run isolation
through `af3`, and don't report an admin-token 200 as evidence either way.** End the
report by telling whoever's running the suite to have a colleague who holds only one
team's role manually run the trigger call (see `CANARY_RBAC.md`'s verification
procedure) against their own team's canary (expect 200) and another team's (expect
403) — that's the only way to actually exercise this canary.

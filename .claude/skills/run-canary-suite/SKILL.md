---
name: run-canary-suite
description: 'Trigger one/some/all of the stage canary DAGs (secrets, alerting, scaling, images, S3, RBAC, cross-tier, and e2e image canaries) that validate airflow3-stage via the af3 REST API, poll to completion, and interpret results per-canary — several do NOT use plain DAG-success/DAG-failure as their pass signal. Includes catalog guidance for expand-mapping canaries. Use when asked to "run the canary suite", "run the canary DAGs", "check the canary results", "re-run canary_<name>", or "verify the platform canaries on stage".'
---

# run-canary-suite

**Ownership: data-tooling team only.** This skill, the canary DAGs it drives, and the
test suite as a whole are owned and maintained by the data-tooling team, for platform
validation only — they are not production data pipelines. Only data-tooling team members
should run this skill or trigger these DAGs; if you're outside that team, don't run the
suite.

Drives the canary test DAGs that live under `airflow_etl/dags/*/canary_*/` and checks
their results via the Airflow 3 stage REST API. These are one-off platform-validation
fixtures (not production pipelines) — see `airflow_etl/dags/data_tooling/CANARY_RBAC.md`
for the RBAC subset's own detailed verification procedure, which this skill complements.

**Prerequisite:** the `af3` CLI helper (`~/.local/bin/af3`) and a valid Teleport session
(`tsh status`; re-login with `tsh login --proxy=teleport.happening.dev` if expired). Every
`af3` call needs the sandbox disabled (network + reads Teleport cert files). See
`~/.claude/CLAUDE.md` / the `airflow3-stage-api-access` memory for the auth quirks.

Stage canaries are kept **paused** between runs (`is_paused_upon_creation=True`
in code, plus paused explicitly via the API) so they don't fire on a schedule or get
triggered by accident. This skill's job is to unpause → trigger → wait → interpret →
re-pause.

The stage suite covers secrets, images, s3, scaling, alerting, RBAC, cross-tier
isolation, and e2e image canaries, spread across `data_tooling/`, `data_products/experimentation/`,
`analytics_platform/shared/`, `compliance/`, and `swe/social/` (folder placement is
deliberate — see the reference below before "cleaning up" any location). Read
`references/canary-catalog.md` for the full per-DAG table (dag_id, folder, what it
proves, pass signal) and the Scaling/Secrets/RBAC notes — several canaries do NOT use
plain DAG-success/DAG-failure as their pass signal, so open this before interpreting
any run (Step 5).

Read `references/prod-promotion.md` only if asked to port a canary to
airflow3-prod — not needed to run the suite today. That reference is flagged stale:
most of the porting work it describes as outstanding already merged to `master`
on 2026-08-04 (PRs #139, #141) — re-verify against current `master` rather than
trusting its "not done yet" framing.

## Steps

### 1. Scope the run

Ask (if not already clear from the request) which canaries to run: one `dag_id`, a
category (secrets / images / s3 / scaling / alerting / rbac / cross-tier / e2e), or the full
suite. Flag before running, don't run silently:

- **Alerting canaries** fire a real incident.io alert routed to the `data-tooling` Slack
  channel every time (by design). Confirm the user wants that noise before triggering
  `canary_alerting_*`.
- **Scaling canaries** take several minutes and drive real KEDA/Karpenter scale-up on
  the stage cluster — tier-0's fan-out size and task duration have been retuned more
  than once (check the `STAGE` section of its `config.yaml` rather than assuming
  30×180s, which is still accurate for tier-1 but not tier-0; see the Scaling note in
  `references/canary-catalog.md`). Confirm before running `canary_scaling_*`, and
  mention that observing the result needs `kubectl` access (via `tsh kube login`),
  not just `af3`.
- **E2E canaries** write scratch objects/tables (SBX_DP and S3 scratch prefixes) and
  take longer than the lightweight probes. Confirm before running any
  `canary_e2e_docker_image_*` DAG.
- **Dynamic-mapping canaries** are targeted checks (`canary_expand_mapping_tier0`,
  `canary_expand_mapping_kpo_tier0`, `canary_expand_mapping_rendered_sql_tier0`).
  Keep them paused by default and trigger only when the request explicitly asks for
  mapped-operator validation.

The rest (secrets, images, s3, rbac, cross-tier) are safe to run without extra
confirmation — they're short, idempotent probes.

### 2. Unpause, trigger, and capture the run id

For each target `<dag_id>`:

```bash
af3 PATCH /api/v2/dags/<dag_id> -H 'Content-Type: application/json' -d '{"is_paused": false}'
af3 POST /api/v2/dags/<dag_id>/dagRuns -H 'Content-Type: application/json' -d '{"logical_date":null}'
```

The POST response's `dag_run_id` (e.g. `manual__2026-07-08T06:35:47.202992+00:00`) is
needed for every subsequent call — URL-encode it (`+` → `%2B`, `:` → `%3A`) when it
appears in a path.

### 3. Poll until the run finishes

```bash
af3 "/api/v2/dags/<dag_id>/dagRuns/<run_id_encoded>"
```

Poll every ~10-15s until `state` is `success` or `failed`. Most canaries finish in
well under a minute; the scaling canaries take longer and their duration isn't fixed —
tier-1's 30×180s sleepers plus cold-start take several minutes, and tier-0's fan-out
size has been retuned repeatedly (check the `STAGE` section of its `config.yaml` for
the current `NUM_TASKS`; `WAIT_SECONDS` is still a plain constant in the `.py` file —
rather than assuming a specific runtime). Don't poll faster than every ~10s — each
call re-parses through the API server.

### 4. Fetch task-level results

```bash
af3 "/api/v2/dags/<dag_id>/dagRuns/<run_id_encoded>/taskInstances"
```

For any task not in `success` state, pull its log for the failure detail (the S3,
images, and secrets canaries raise an `AssertionError` carrying the exact AWS/K8s
error code or, for secrets, one of the four message prefixes in the Secrets note in
`references/canary-catalog.md`):

```bash
af3 "/api/v2/dags/<dag_id>/dagRuns/<run_id_encoded>/taskInstances/<task_id>/logs/1?full_content=true"
```

### 5. Interpret using the catalog, not raw DAG state

Plain "DAG succeeded = good" is wrong for 4 stage canaries (`canary_cross_tier_denied_tier0`
and the three `canary_alerting_*`). Apply the **Pass signal** column from
`references/canary-catalog.md`, not just `dag_runs[].state`, before reporting a verdict.

### 6. Re-pause

```bash
af3 PATCH /api/v2/dags/<dag_id> -H 'Content-Type: application/json' -d '{"is_paused": true}'
```

Every canary should end each check back in its resting paused state.

### 7. Report

Give a per-DAG verdict table: dag_id, run state, interpreted pass/fail, and (for
S3/images) which specific task/bucket/image failed if any. Check
`references/known-gaps.md` before flagging a failure as new — it lists pre-existing
gaps (S3 bucket-grant rollout, amd64-only image regressions, secrets fixture
prerequisites, one-directional cross-tier coverage) to recognize rather than
re-diagnose as new bugs.

If any `canary_rbac_*` DAGs were run, close the report with a reminder: their `af3`
result only confirms visibility/triggerability, not run isolation — ask a colleague
with a single team's role to manually run the trigger call against their own team's
canary and another team's, per the RBAC note in `references/canary-catalog.md`.

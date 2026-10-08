---
name: airflow3-observability-debug
description: Triage "something's off with Airflow 3" reports (tasks stuck/queued, DAG missing or stale, general health check, things getting worse over time) across dev/stage/preprod/prod using the 3 "Airflow 3" Grafana dashboards, the airflow3-data-stage/airflow3-data-prod MCP tools, af3 (stage), and Loki logs. Use when someone reports Airflow 3 slowness, stuck DAGs/tasks, worker/pod failures, or just wants a health check, or mentions the Airflow 3 Grafana dashboards, KEDA/Celery scaling, DAG parse delays, or OOM/pod issues on an airflow3-* namespace.
---

# Airflow 3 observability debug

Triage workflow for Airflow 3 issues, built around 3 purpose-made Grafana dashboards plus live
API/log checks. It exists because dashboards alone don't cover everything (Karpenter cold starts,
KPO pod launches, and "why is my DAG stale" all need cross-referencing logs or the API too) — see
`references/investigation-guide.md` for the reasoning behind each step.

## Step 1 — pin down environment and symptom

Ask if not already clear:
- **Environment**: dev, stage, preprod, or prod?
- **Symptom category**: (a) a task/DAG is stuck or slow, (b) a DAG isn't showing up / looks
  stale, (c) "is everything healthy right now", or (d) "is this getting worse over time".

This decides which dashboard and which MCP toolbox to use next.

**Env → tools:**

| env | Airflow MCP toolbox | `af3` CLI | Metrics datasource | Logs datasource |
|---|---|---|---|---|
| dev | `airflow3-data-stage` (shares stage's API host) | not wired for dev | `data-stage-euc1-vm-prometheus` | `logs-data-stage` |
| stage | `airflow3-data-stage` | yes | `data-stage-euc1-vm-prometheus` | `logs-data-stage` |
| preprod | `airflow3-data-prod` | no | `data-prod-euc1-vm-prometheus` | `logs-data-prod` |
| prod | `airflow3-data-prod` | no | `data-prod-euc1-vm-prometheus` | `logs-data-prod` |

**dev has OTel metrics switched off** — most Scheduler-dashboard panels will be empty for dev by
design. Lean on the MCP toolbox / live API for dev instead of the dashboard. Details in
`references/dashboard-map.md`.

## Step 2 — cheap live checks first

Before opening any dashboard, run (via the airflow3 MCP toolbox for the right env, or `af3` on
stage):
1. `get_health` — is the scheduler/API even up.
2. `get_import_errors` — a broken DAG file looks like "staleness" from outside; rule this out
   first, it's the single most common cause.
3. If a specific task/DAG was named: its task-instance timestamps
   (`scheduled_when`/`queued_when`/`start_date`) or `last_parse_duration`.

This alone often resolves the report. Only move to dashboards if it doesn't.

## Step 3 — open the matching dashboard

Use the `grafana` MCP tools (`get_dashboard_summary`, `get_dashboard_panel_queries`,
`get_panel_image`, or `query_prometheus`/`query_loki_logs` directly against the datasource) with
the UIDs and symptom routing in **`references/dashboard-map.md`**:

- **Scheduler, Parsing & Broker Health** (`cf632919-606b-48c9-990f-b0f38e543720`) — DAG staleness,
  pool saturation, scheduler/dag-processor liveness, broker health.
- **Celery & Resources** (`airflow3-observability`) — stuck/queued tasks, KEDA worker scaling,
  Celery queue depth, per-DAG task counts.
- **KPO / K8s Task Pods** (`9b7a5d45-b35b-4af7-acf4-a39cad67cced`) — KubernetesPodOperator pods
  specifically: pending/failed/OOM, per-task resource usage, node placement.

Always set `datasource` (and `loki` where present) to match the environment — see the pairing
table above. They don't chain automatically; a wrong pairing looks like "no data" everywhere.

## Step 4 — apply what's already known before concluding anything

Read **`references/investigation-guide.md`** — it ranks the real suspects behind "task/DAG is
slow" (Celery worker cold start, KPO pod launch time invisible inside task duration, the 3-stage
DAG-staleness delay chain, and genuinely slow parsing, in that likelihood order), gives the exact
panels/queries to confirm each, and lists known traps (misleading `query_loki_stats` zeros, the
Airflow-2-style `owner_kind=""` filter that silently hides Celery worker cold-starts, ElastiCache
CPU being broker health not queue depth, Flower needing `FLOWER_UNAUTHENTICATED_API=1`, and why
there's no shared join key between an Airflow task and the k8s pod it spawns).

## Step 5 — report clearly

State what's **confirmed** (backed by a metric/log you actually queried) separately from what's
still a **hypothesis** (e.g. "no shared join key" correlations are always approximate). Point at
the specific panel or log query used, so the person can go look themselves.

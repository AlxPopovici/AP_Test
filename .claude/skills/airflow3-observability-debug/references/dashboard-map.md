# Airflow 3 dashboard map

Folder: **Airflow 3** (uid `ffxjeb3depssge`), under folder "data". Fetch with the `grafana` MCP
tools using the UIDs below — `get_dashboard_summary` for panel lists, `get_dashboard_panel_queries`
for the actual PromQL/LogQL of a panel, `get_panel_image` to render one.

## The 3 dashboards

| Dashboard | UID | Use it for |
|---|---|---|
| **Scheduler, Parsing & Broker Health** | `cf632919-606b-48c9-990f-b0f38e543720` | "Is my DAG stale/not parsing?", pool saturation, scheduler/dag-processor liveness, broker (ElastiCache) health |
| **Celery & Resources** | `airflow3-observability` | "Why is my task still queued?", worker scaling (KEDA), Celery queue depth, per-DAG task counts, CPU/RAM by component |
| **KPO / K8s Task Pods** | `9b7a5d45-b35b-4af7-acf4-a39cad67cced` | Task-launched (KubernetesPodOperator) pods specifically: pending/failed/OOM, per-task CPU/RAM, node placement |

All 3 share a `datasource` variable (label "Metrics cluster") and an `env` variable. Two also have
a `loki` variable (label "Logs cluster") — **always switch `datasource` and `loki` together**
(stage↔stage, prod↔prod). Grafana can't chain one datasource variable off another, so nothing
enforces this — if a panel looks empty or wrong, check this first.

**Env → datasource/logs pairing:**

| env | Metrics cluster (`datasource`) | Logs cluster (`loki`) |
|---|---|---|
| dev, stage | `data-stage-euc1-vm-prometheus` | `logs-data-stage` |
| preprod, prod | `data-prod-euc1-vm-prometheus` | `logs-data-prod` |

## Known gaps (expected "No data", not a bug)

- **dev has no OTel metrics.** `metrics.otel_on` is `False` for airflow3-dev's control-plane and
  worker-fanout (`data.stage.euc1/platform/airflow3-dev/deployment.yaml` in data.gitops.clients).
  stage/preprod/prod have it `True`. So with `env=dev`, every panel on **Scheduler, Parsing &
  Broker Health** shows "No data" except the 3 ElastiCache panels and the 2 CPU/RAM-by-workload
  panels (those are plain k8s/CloudWatch metrics, not Airflow-emitted). Don't debug dev DAG-parse
  or scheduler-loop issues from this dashboard — use `af3`/the airflow3-data-stage MCP tools for
  live checks instead (dev shares the stage Airflow API host).
- **redis_exporter is missing on dev only** (verified in data.gitops.clients: `redis-exporter.yaml`
  exists under `airflow3-stage/`, `airflow3-preprod/`, and `airflow3-prod/`, but not under
  `airflow3-dev/`). Flower itself is deployed with `enabled: true` in **all 4 envs** including
  dev. So on the Celery & Resources dashboard: `flower_*`-based panels (workers online, tasks
  executing) should have data everywhere; only the `redis_*`-based broker-queue-depth panels are
  expected to show "No data" for dev. If those panels are empty for preprod/prod, that's a real
  bug worth digging into (wrong `datasource`/`env` pairing is the first thing to check), not an
  expected gap — don't assume it's the known dev-only gap without checking which env you're on.
  (Note: the dashboard's own description text in Grafana currently says the exporters are
  "stage only" — that's stale and worth fixing on the dashboard itself.)
- **KPO dashboard's pod matching is a name heuristic.** "Task pods" = pods NOT matching the
  `control_plane_exclude` regex variable (known static component names). If a new component is
  added to the chart and isn't in that regex, it'll get miscounted as a task pod — check the
  regex if the numbers look surprising.
- **Short-lived KPO pods can be invisible.** kube-state-metrics scrapes on an interval; a task pod
  that starts and finishes between scrapes never appears in any `kube_pod_*` panel. If a user says
  "my task pod ran and finished fine but I don't see it," that's expected, not a dashboard problem.

## Panel-to-symptom quick index

**"Task is stuck/queued"** → Celery & Resources: "Worker pods ready vs desired (KEDA)" (gap
between dashed=desired and solid=ready is Karpenter cold-start), "Broker queue depth (per queue)"
(nonzero on `default`/`local`/`kubernetes` queue = misrouted task, will never run), "Currently
executing tasks (per tier)". Then KPO dashboard's "Task pods pending" + the Warning-events log
panel if it's specifically a KubernetesPodOperator task.

**"DAG isn't showing up / looks stale"** → Scheduler dashboard: "DAG parse duration by file: avg
vs most recent" (table), "Top 10 stalest DAG files" (`dag_processing.last_run.seconds_ago`),
"dag_processing.file_path_queue_size per replica" (queue imbalance across dag-processor pods).

**"Is the platform healthy right now?"** → Scheduler dashboard: "Scheduler & dag-processor
heartbeat rate per replica" (0 = dead), "Pool slots by pool_name", "Triggerer capacity left by
pod", broker CPU/mem/connections. KPO dashboard's OOM/restart stats for task-pod-level health.

**"Is anything getting worse over time?"** → Widen the time range on the Celery dashboard's
"Task events rate (per event type)" and "Tasks by DAG (received/finished/failed)" table, and the
Scheduler dashboard's parse-duration and pool-slots timeseries.

## Notable individual panels worth knowing by name

- **"Broker queue depth (per queue)"** (both stat and timeseries, Celery dashboard) — this is the
  single best misroute detector: any traffic on `default`/`local`/`kubernetes` queue keys means
  something is configured to route to a queue nobody consumes.
- **"Tasks by DAG (received/finished/failed)"** (Celery dashboard, table, parsed from scheduler
  logs via Loki) — the only panel with a `dag_id` label; every Flower/Celery metric above it has
  no DAG-level breakdown, so use this table to find which DAG is behind a spike seen elsewhere.
- **"Workers online (per tier)"** — a tier scaled to zero *disappears* from this stat instead of
  showing `0`. Don't read "no data" here as "workers are down" without checking the KEDA
  ready-vs-desired panel too.

# Airflow 3 investigation guide

Condensed from a real stage-deployment investigation (2026-08-19 to 2026-08-25).

## Suspects for "task/DAG is slow", ranked by how likely and how visible they are

1. **Celery worker cold start (most common, and easy to miss).** KEDA scales tier workers from
   zero. When it scales up, Karpenter has to provision a node, then pull the image, before the
   worker pod is even Ready. This can take low minutes. It shows up to a user as "queued
   forever" but will NOT show up in Airflow's own `queued_when → start_date` gap analysis if
   you're computing that from the API — because `queued_when` only gets stamped meaningfully
   once a worker exists to pick it up in some measurements, and either way the wait is Kubernetes
   time, not Airflow time.
   - **Check:** Celery & Resources dashboard → "Worker pods ready vs desired (KEDA)" — a gap
     between dashed (desired) and solid (ready) lines is this, directly.
   - **Confirm the trigger:** KPO dashboard's Warning-events log panel, or `query_loki_logs`
     against `{job="loki.source.kubernetes_events", namespace=~"airflow3-<env>.*"}` — look for
     `TriggeredScaleUp` / `FailedScheduling`, and `reason=Pulled ... "in Ns"` for image-pull time.
2. **KubernetesPodOperator (KPO) pod launch time.** This happens *inside* the task's own
   duration (the worker calls the k8s API from inside the operator's code, after `start_date` is
   already stamped) — so it's invisible as a separate Airflow-side number. There is no
   Airflow-side timestamp for "operator called the k8s API to create a pod."
   - **Check:** KPO dashboard's "Task pods pending" stat + "Task pods by phase" timeseries. Match
     the k8s pod to the Airflow task by name + timestamp proximity — **there is no shared join
     key between the two systems**, this is always a manual correlation.
3. **"My DAG isn't showing up."** Three stacked delays, in order: git-sync pull → bundle refresh
   interval → dag-processor's `min_file_process_interval` (30s on stage). Nothing measures the
   true end-to-end "git commit → visible in UI" number today.
   - **Check:** Scheduler dashboard's "Top 10 stalest DAG files" and "DAG parse duration by file"
     table. If the file itself parses fast but is still stale, suspect git-sync or bundle refresh,
     not parsing.
4. **Actual DAG parse time being slow.** Rare — on stage, 52 DAGs summed to ~10.6s total parse
   time, p95 per-file was 0.56s. Don't assume parsing is the bottleneck without checking the
   parse-duration panels first; it usually isn't.

## Live, on-demand checks (dashboards don't have these as a stored trend)

Use the airflow3 MCP toolbox tools (`airflow3-data-stage` covers dev+stage, `airflow3-data-prod`
covers preprod+prod) or the `af3` CLI helper (stage host only — see the user's global CLAUDE.md
for setup) for:

- **Pool slot state right now**: `get_pools` / `af3 /api/v2/pools` — fields
  `queued_slots`/`running_slots`/`scheduled_slots`/`open_slots`/`deferred_slots`. Cleaner "how
  many tasks are waiting right now" than KEDA's derived ceiling, but it's a point-in-time read,
  not a trend (the Scheduler dashboard's "Pool slots by pool_name" panel IS the trend version of
  this on stage/preprod/prod where OTel is on — prefer that panel when it has data).
- **DAG-level parse duration right now**: `get_dag_details` / `af3 '/api/v2/dags?limit=200'`,
  field `last_parse_duration`. The dashboard's parse-duration panels are the trended OTel version;
  use the live API only for dev (no OTel) or to double check a specific DAG right now.
- **Task instance timestamps for a specific stuck task**: `get_task_instance` /
  `list_task_instances` — fields `scheduled_when`, `queued_when`, `start_date`, `end_date`,
  `duration`, `try_number`, `pool`, `queue`, `executor`, `operator`. Compute
  `queued_when → start_date` by hand for the specific task the user is asking about.
- **Import errors**: `get_import_errors` — always check this early; a broken DAG file silently
  stops that DAG from updating and can look like "staleness" from the outside.

## Traps that will waste your time if you don't know them

- **`query_loki_stats` on this Loki gives misleading zeros.** Don't conclude "no logs" from it.
  Use `count_over_time` via `query_loki_logs`/`query_prometheus`-style range queries instead, or
  just read the actual log lines.
- **Airflow 2 `owner_kind=""` logic does not carry over.** On the hybrid Celery+Kubernetes
  executor, Celery tier workers are ReplicaSet-owned, not bare pods — a dashboard filter copied
  from an Airflow 2 KubernetesExecutor-only setup that assumes `owner_kind=""` will silently only
  ever show KPO task pods and miss Celery worker cold-starts, which is usually the actual problem.
  Both dashboards here already handle this correctly; if someone hands you a third, older
  dashboard, check its `owner_kind` filter before trusting it.
- **redis_exporter (queue-depth) is only missing on dev** (see dashboard-map's "known gaps" —
  Flower is deployed everywhere including dev; redis_exporter is deployed on stage/preprod/prod).
  ElastiCache CPU/mem/connections (from the CloudWatch `yace` exporter, always present) is
  *broker health*, not *queue depth* —
  `curr_items` counts Redis keys (one per queue), not list length, so it stays flat regardless of
  backlog. Don't read broker CPU as a proxy for backlog.
- **Flower's REST API needs `FLOWER_UNAUTHENTICATED_API=1` (or real auth) to answer queries at
  all** — if someone reports Flower itself is broken/unreachable via its API, this env var is the
  likely cause, not a code bug.
- **`legacy_names_on` controls cardinality, not `metrics_block_list`.** If someone wants to reduce
  Airflow's own metric cardinality, the answer is the `[metrics] legacy_names_on` config flag
  (default `True`, emits both old dot-mangled names and new tagged ones) — not hand-writing a
  regex block list. `PatternBlockListValidator` lower-cases every entry before compiling as regex,
  which mangles named capture groups like `(?P<dag_id>.*)` — a real trap if someone tries to reuse
  an old Airflow 2 block-list pattern verbatim.
- **OTel histograms only work end-to-end because VictoriaMetrics (not a prometheus-exporter hop)
  ingests the OTLP exponential histograms directly.** If a future env's OTel metrics look present
  but percentile panels are empty/wrong, check whether that env's Alloy pipeline actually routes
  straight to VM's `/opentelemetry/v1/metrics` rather than through `otelcol.exporter.prometheus`
  (native-histogram support there is experimental and silently drops samples).
- **OTel/dashboards will NEVER show Karpenter node-provisioning time or image-pull time as an
  Airflow metric** — those are outside the Airflow process. Always cross-check k8s events (Loki)
  for that piece, per suspect #1 above.

## Order of operations for a fresh "something feels off" report

1. Ask (or infer from what they pasted) which **environment** and what the **symptom** actually
   is — stuck task, missing DAG, general health check, or "getting worse over time." This decides
   which dashboard/panel to open first (see dashboard-map.md's symptom index).
2. Run the cheap live checks first: `get_health`, `get_import_errors`, and if a specific
   task/DAG was named, its task-instance timestamps or `last_parse_duration`. This alone resolves
   a good fraction of reports (import error, DAG paused, task retried and succeeded already).
3. Open the matching dashboard(s) for the right `env`/`datasource`/`loki` triple. Read the panel
   descriptions in Grafana — most panels here already document their own caveats inline.
4. If the dashboards don't explain it, go to suspects #1–#4 above and check the specific k8s
   events / Loki logs each one implies.
5. State clearly what's confirmed (from a metric/log you actually queried) vs. what's still a
   hypothesis (e.g. "no shared join key" cases) — don't present a guess as a finding.

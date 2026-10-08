# Alerting scaffold — incident.io

The real alerting mechanism in this repo is `IncidentIOAlerter` /
`IncidentIOConfig` from `include.airflow.alerting.incident_io` — never a hand-rolled
`on_failure_callback`. `pipeline_template.py` includes the block **commented out**: a
brand-new pipeline ships with alerting off by default, and the developer opts in
deliberately rather than inheriting it silently.

The codebase has two attach styles (passing `on_failure_callback`/`on_success_callback`
straight into `DAG(...)`, or calling `.attach_to(dag)` inside the `with DAG(...) as dag:`
block, after the tasks it covers). **This skill documents and scaffolds `attach_to()`
only** — it's the preferred style: it wires both the create and close side together in
one call, instead of two separate callback kwargs threaded through `DAG(...)`.

## Turning it on

Uncomment the import near the top of `<pipeline>.py` and the block at the end of the
`with DAG(...) as dag:` body:

```python
from include.airflow.alerting.incident_io import IncidentIOAlerter, IncidentIOConfig

with DAG(dag_id, ...) as dag:
    main_task = RenderedSQLExecuteQueryOperator(...)
    ...

    IncidentIOAlerter(IncidentIOConfig(...)).attach_to(dag)
```

## `IncidentIOConfig` fields

| Field | Meaning |
|---|---|
| `notification_level` | `"dag"` \| `"run"` \| `"task"` — controls the alert's dedup key. `dag`/`task` dedup onto one alert across re-runs; `run` mints a new alert per run (its dedup key includes `run_id`). |
| `severity` | e.g. `"warning"`, `"moderate"` — `"warning"` never pages on-call. |
| `wake_me_up_for_this` | `bool` — whether this can page someone outside working hours. |
| `route_labels` | list, e.g. `["default"]` — which Slack channel/route the alert lands in. `"default"` is the shared channel every pipeline gets unless routed elsewhere. |
| `owners` | list of Slack mentions (`<!subteam^S...>` for a usergroup, `<@U...>` for a person) — who gets pinged. |
| `retrigger_every_time` | `bool` — whether a still-firing alert re-notifies on every failure or stays silent until resolved. |

## Default for a new pipeline

```python
route_labels=["default"]
owners=["<!subteam^..."]   # the owning team's Slack usergroup, matching the owner tag
```

## Routing to a team-specific Slack channel instead of the shared default

`route_labels` values are constrained by an allowlist
(`ALLOWED_ROUTE_LABELS` in `airflow_etl/include/airflow/alerting/incident_io/config.py`) —
you can't just invent a new label. Getting a new route added is a manual, multi-step
process spanning this repo and incident.io itself — full walkthrough in
[Incidentio <> Airflow - Send alert to new Slack channel](https://www.notion.so/superbet/Incidentio-Airflow-Send-alert-to-new-Slack-channel-2ca032f852c5805f8fa3d499104d9516).
Summary:

1. Add the new label to `ALLOWED_ROUTE_LABELS` in
   `airflow_etl/include/airflow/alerting/incident_io/config.py` (the doc's code link points
   at the old `data.airflow.dags` repo — the same file now lives here, in this monorepo).
2. In the target Slack channel, run `/invite @incident`.
3. In incident.io's route config (stage and prod are separate routes — the doc links both),
   add a new "Send alerts to Slack" destination filtered on
   `Alert > Attributes > Labels includes one of <your label>`, and add that same label to the
   existing catch-all destination's *exclusion* filter so alerts aren't duplicated into the
   shared `#data-tooling-alerts-stage` channel.
4. Trigger a test alert and confirm it lands in the new channel only.

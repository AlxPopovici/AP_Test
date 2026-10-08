# Legacy KubernetesPodOperator + Docker SQL-executor pattern — always refactor it

Some old-repo DAGs don't keep their SQL in a folder co-located with the DAG at all.
Instead they run every statement through a `KubernetesPodOperator` calling a custom
Docker image (`SnowflakeSQLExecutorCmd` from `superbet_group_data_pyops...database`),
with a `base_path` string like `'repo/scripts/tran/<area>/<pipeline>'` pointing at the
**old repo's top-level `scripts/` tree** — a runtime path, not a template searchpath.
`move_dag.py` does **not** detect this pattern (it only auto-copies a `sql/` folder
that's already sitting next to the DAG file), so nothing about it shows up in the
tool's output. You have to recognize it yourself: grep the source DAG for
`SnowflakeSQLExecutorCmd` or a `base_path`/`'--script'` pair before you conclude
there's no SQL to move.

**Default, every time you hit this pattern:** refactor it to
`RenderedSQLExecuteQueryOperator` (`include.airflow.operator.rendered_sql_execute_query_operator`)
with `conn_id=get_sf_conn_id(cfg)`, running on Celery instead of a pod per statement.
Don't leave the old Docker-executor architecture in place and don't treat the SQL
move as optional — do both as part of the same migration, not a deferred follow-up:

1. Move the SQL out of the repo-wide `scripts/` tree into the pipeline's own
   `sql/` folder (`airflow_etl/dags/<area>/<sub_area>/<pipeline>/sql/`), preserving
   any per-env subfolder structure (e.g. `sql/dest_tables/<env>/...`). Point
   `template_searchpath` at it.
2. Convert every `${VAR}` shell-style substitution in that SQL to Jinja
   `{{ params.x }}` — the operator renders `params` before rendering `sql`, so this
   is a mechanical rename, not a logic change.
3. Replace the KPO-building helper with one that builds
   `RenderedSQLExecuteQueryOperator(conn_id=..., sql=..., params=..., ...)` instead.
4. Set `max_active_tasks` to the DAG's exact total task count (top-level tasks plus
   any per-entity task-group tasks) rather than an arbitrary number — Celery tasks
   are far cheaper than one pod per statement, so the old KPO-era cap no longer
   applies. Verify the count programmatically (build the DAG via `DagBag` locally
   and compare `len(dag.task_ids)`), don't hand-count.

`tran-tooling-blueprint-wh-advanced-example` (`airflow_etl/dags/data_tooling/blueprint/`)
is the canonical reference for this target shape, including the shared
`insert_into_log.sql` / `rollback.sql` / `success.sql` JOB_LOG boilerplate — reuse its
SQL verbatim for that boilerplate rather than reinventing it.


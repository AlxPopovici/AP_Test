# Advanced: dynamic Snowflake warehouse-tier selection

This is **not** part of the default pipeline scaffold. It's for a specific, less-common
need: a pipeline whose source-table row count varies enough between runs that running it
on a fixed-size Snowflake warehouse either wastes money (oversized for a small run) or
runs too slowly (undersized for a large one).

This is about Snowflake **compute-warehouse tiers** (L0/L1/L2 — small/medium/large), not
about connecting to a different database vendor. There is no BigQuery/Postgres/other
non-Snowflake pattern anywhere in this repo — every pipeline here is Snowflake-only.

## Canonical reference

`airflow_etl/dags/data_tooling/blueprint/tran-tooling-blueprint-wh-advanced-example/` is the
canonical example. It:

1. Inserts a `PROCESSING` row into a job log, capturing the current and last-successful
   `JOB_RUN_ID` (`insert_into_log.sql`).
2. Computes the row-count delta since the last successful run and picks a warehouse tier
   (`wh_de_l0_basic` / `wh_de_l1_enhanced` / `wh_de_l2_intensive`, all read from
   `get_config()`) against two thresholds, recording the choice in
   `DQ.JOB_TASK_METADATA_LOG` (`insert_into_metadata_log.sql`).
3. Runs the main job against the chosen warehouse via
   `IDENTIFIER()` (`tooling_blueprint_wh_advanced_example.sql`), passing the picked
   warehouse name as a `RenderedSQLExecuteQueryOperator` param sourced from the previous
   task's XCom.
4. Branches to a rollback or success sink (`EmptyOperator` + trigger rules) depending on
   outcome, each updating the job log accordingly.

The simpler sibling, `tran-tooling-blueprint-wh-simple-example/`, shows the minimal version
of the same idea — one warehouse name passed straight from config into a query via
`IDENTIFIER()`, no dynamic tier selection or job-log bookkeeping.

## When to reach for this

Only when a developer's pipeline genuinely has this cost/performance problem. Don't
default new pipelines into this pattern — most pipelines run fine on whatever warehouse
their `config.yaml` already points at.

import os
from datetime import datetime, timedelta

from airflow import DAG
from include.airflow.dags_config import get_config
from include.airflow.operator.rendered_sql_execute_query_operator import RenderedSQLExecuteQueryOperator
from include.airflow.snowflake import get_sf_conn_id

# Uncomment together with the attach_to(dag) block below to enable incident.io alerting.
# from include.airflow.alerting.incident_io import IncidentIOAlerter, IncidentIOConfig

__doc__ = """
<ONE-LINE DESCRIPTION OF WHAT THIS PIPELINE DOES.>

Audience / owners: <team>. Schedule: <when it runs and why>.

What this DAG does
------------------
1. <step>
2. <step>

What this DAG does not do
-------------------------
- <out of scope — e.g. no Snowflake COPY, no production schemas>

How to verify a run
-------------------
- <SQL, S3 key, Airflow UI, or AWS CLI check>

Operations
----------
- Catch-up: if several runs fail then one succeeds, <does that cover missed
  intervals, or must each failed run be cleared?>
- Mid-run failure: clear + rerun is <safe / not safe because …>
- Ad-hoc rerun: triggering outside the schedule is <safe / not safe because …>
- External deps: <none / API / dropped file / rate limits> — if down: <…>
- Known oddities: <none / e.g. expected Monday failure because …>
"""

dag_id = "<PIPELINE_ID>"

default_args = {
    "owner": "<TEAM>",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}

SQL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sql")

current_env_config = get_config()
SNOWFLAKE_CONN_ID = get_sf_conn_id(current_env_config)

with DAG(
    dag_id,
    # owner is the only mandatory tag key — add business_area / source_schema /
    # destination_schema / source_system / component / markets only where relevant.
    # See the "DAG Tags" section of airflow_etl/CLAUDE.md for the full table.
    tags=["owner:<TEAM>"],
    start_date=datetime(2026, 1, 1),
    default_args=default_args,
    description="<ONE-LINE DESCRIPTION>",
    schedule="0 6 * * *",
    catchup=False,
    max_active_runs=1,
    template_searchpath=SQL_PATH,
    doc_md=__doc__,
) as dag:

    # One RenderedSQLExecuteQueryOperator per SQL statement. Put the SQL text in
    # sql/<name>.sql, never inline, and never a KubernetesPodOperator + Docker SQL
    # executor — see the "SQL execution" rule in airflow_etl/CLAUDE.md.
    main_task = RenderedSQLExecuteQueryOperator(
        task_id="<task_name>",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="<name>.sql",
        params={},
        show_return_value_in_logs=True,
    )

    # Delete this if the pipeline is pure SQL. Keep and adapt it if you need custom
    # Python logic — TaskFlow (@task) is the idiomatic way to add that, it's just not
    # required for pipelines that don't have any Python-callable logic to begin with.
    #
    # from airflow.sdk import task
    #
    # @task
    # def example_python_step():
    #     ...
    #
    # example_python_step() >> main_task

    # Alerting is OFF by default for a brand-new pipeline — no notifications fire until
    # you uncomment this block. attach_to() is the preferred style here (over
    # on_failure_callback/on_success_callback passed into DAG(...)) since it wires both
    # create_alert and close_alert together in one call, after every task above already
    # exists. See references/alerting-scaffold.md for the field reference and how to
    # route to a team-specific Slack channel instead of the shared default.
    #
    # IncidentIOAlerter(
    #     IncidentIOConfig(
    #         notification_level="dag",
    #         severity="warning",
    #         wake_me_up_for_this=False,
    #         route_labels=["default"],
    #         owners=["<!subteam^REPLACE_WITH_TEAM_SLACK_USERGROUP_ID>"],
    #         retrigger_every_time=False,
    #     )
    # ).attach_to(dag)

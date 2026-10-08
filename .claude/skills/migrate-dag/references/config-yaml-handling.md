# How config.yaml is handled

The old and new repos store per-DAG config **completely differently**, so this is
not a plain file copy:

- **Old repo** (`data.airflow.dags`): per-DAG configs do *not* sit next to the DAG.
  They live centrally under `dags/configs/`, named after the DAG id — e.g. a DAG
  calling `get_config("tran-seon-daily")` (or the legacy `get_envs_config(...)`
  alias) reads `dags/configs/tran_seon_daily.yaml` (dashes → underscores). The
  shared `global.yaml` is separate.
- **New repo** (this one): config is resolved by **folder hierarchy** — a
  `config.yaml` at any level from `dags/` down to the pipeline folder is deep-merged
  (deeper wins). See `airflow_etl/include/airflow/dags_config.py`. The old
  `global.yaml` is already migrated to `airflow_etl/dags/config.yaml`.

So `move_dag.py` parses the DAG to work out which config it uses, then copies it
into the pipeline folder **as `config.yaml`** (the name the hierarchical resolver
expects). The cases:

- **`get_config(<dag_id>)`** (or legacy `get_envs_config(<dag_id>)`) → resolves
  `dags/configs/<dag_id>.yaml` and copies it. Review the result against
  `dags/config.yaml`: drop any keys now inherited from the migrated global, and
  confirm its sections are among `ALL / DEV / STAGE / PREPROD / PROD`.
- **`get_config()` (no argument)** → global config only, already covered by
  `dags/config.yaml`. Nothing is copied (benign note).
- **DAG factory that globs a `configs/` subdir** (e.g. `ing_jira_to_sf`) or a config
  it can't resolve → **`ACTION NEEDED`** note: locate and copy it by hand.

The script does *not* transform config contents (e.g. adding a `DEV:` section) —
that's a manual review step.

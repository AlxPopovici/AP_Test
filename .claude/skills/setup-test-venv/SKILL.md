---
name: setup-test-venv
description: One-time per-machine setup of a local Python venv so DAG smoke tests (`<dag>_test.py`) can run off-cluster. Creates `.venv` at the repo root and installs `dev_tools/requirements-dev.txt` (Airflow 3.1.8 + providers) against Airflow's official constraints. Use when someone wants to run a DAG's `_test.py` but has no venv / Airflow isn't importable, or asks to "set up the test environment", "install the venv", "create a venv to run DAG tests", or hits `ModuleNotFoundError: airflow` running a smoke test.
---

# setup-test-venv

Stand up a local Python environment for running the per-pipeline DAG smoke tests
(`<dag>_test.py`) on a laptop, outside the Airflow cluster. Each smoke test just
imports and parses its DAG and validates the task graph — but that still requires
Airflow and the providers/libraries the DAG imports to be installed.

The dependency set lives in `dev_tools/requirements-dev.txt`: `apache-airflow` pinned to
the deployed Helm chart version (`_charts/airflow-v3.1.8`), the CNCF Kubernetes and
Snowflake providers, and the libraries DAGs / `include/` helpers import. These are
**local test deps only** — the pod image is built from the Helm chart, not this file.

## Steps

### 1. Check whether a working venv already exists

From the repo root:

```bash
[ -x .venv/bin/python ] && .venv/bin/python -c "import airflow; print('airflow', airflow.__version__)"
```

If that prints an Airflow version, the environment is already good — skip to step 4 and
just tell the user how to run the test. Only continue to step 2 if there's no `.venv` or
the import fails.

### 2. Confirm Python 3.11 is available

```bash
python3.11 --version
```

The repo targets Python 3.11 (matches the Black `python3.11` config and the constraints
file below). If `python3.11` isn't found, ask the user to install it (e.g. `brew install
python@3.11`) before continuing — don't silently fall back to another minor version, as
the pinned constraints are for 3.11.

### 3. Create the venv and install the requirements

Run from the repo root. The install is large (full Airflow + providers) — allow a few
minutes.

```bash
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r dev_tools/requirements-dev.txt \
  -c https://raw.githubusercontent.com/apache/airflow/constraints-3.1.8/constraints-3.11.txt
```

The `-c …/constraints-3.1.8/constraints-3.11.txt` pin is what makes the transitive
dependency set reproducible and match a real Airflow release — don't drop it. `.venv/` is
already gitignored.

### 4. Run a smoke test to verify

A smoke test can be run directly or under pytest. **It needs `DEPLOYMENT_ENV` set** — most
DAGs resolve their config at import time, and without it `get_current_env()` falls back to
an Airflow Variable lookup that needs a real metadata DB (which the hermetic test doesn't
have). Use `STAGE` or `PROD`; some config keys (e.g. `incidentio_alert_url`) are only
defined in those sections of `dags/config.yaml`, so `DEV`/`PREPROD` can fail with a
`KeyError`.

```bash
DEPLOYMENT_ENV=STAGE .venv/bin/python <path>/<dag_name>_test.py
```

A pass prints `PASS  <dag_name>.py parses cleanly (… bytes)`. To run under pytest instead:

```bash
DEPLOYMENT_ENV=STAGE .venv/bin/python -m pytest <path>/<dag_name>_test.py
```

### 5. Report results

Tell the user:
- Whether the venv already existed or was created, and the Airflow version installed.
- The exact command to run a smoke test — including the `DEPLOYMENT_ENV=STAGE` prefix and
  that they should `source .venv/bin/activate` (or prefix `.venv/bin/python`) so the venv's
  interpreter is used.
- If a test still fails after setup, whether it's a genuine DAG import error vs. a missing
  dependency — if a library the DAG imports isn't in `dev_tools/requirements-dev.txt`, add
  it there and re-run step 3.

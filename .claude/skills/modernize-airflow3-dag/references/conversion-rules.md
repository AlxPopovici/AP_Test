# Conversion rules

- [Rule 1: PythonOperator → @task](#rule-1-pythonoperator--task)
- [Rule 2: BranchPythonOperator → @task.branch](#rule-2-branchpythonoperator--taskbranch)
- [Rule 3: XCom data passing → function parameters](#rule-3-xcom-data-passing--function-parameters)
- [Rule 4: Local imports](#rule-4-local-imports)
- [Rule 5: Handling existing `>>` dependencies](#rule-5-handling-existing--dependencies)

### Rule 1: PythonOperator → @task

**Before:**
```python
from airflow.providers.standard.operators.python import PythonOperator

def extract_data(source_url, **kwargs):
    import requests
    response = requests.get(source_url)
    return response.json()

extract_task = PythonOperator(
    task_id="extract_data",
    python_callable=extract_data,
    op_args=["https://api.example.com/data"],
)
```

**After:**
```python
from airflow.sdk import task

@task
def extract_data(source_url: str):
    import requests
    response = requests.get(source_url)
    return response.json()

# Inside the DAG body:
data = extract_data("https://api.example.com/data")
```

**Key details:**
- The function name becomes the `task_id` by default. If the original `task_id` differs
  from the function name, pass it explicitly: `@task(task_id="custom_name")`.
- `op_args` become positional arguments to the function call.
- `op_kwargs` become keyword arguments to the function call.
- `**kwargs` / `**context` parameters are no longer needed — remove them. If the function
  needs context (e.g., `execution_date`), use `from airflow.sdk import get_current_context`
  inside the function body instead.
- `do_xcom_push=True` is implicit for `@task` (return value is always pushed).
- If `do_xcom_push=False` was set, the function can still return but nothing downstream
  will consume it — just remove the flag.
- `retries`, `retry_delay`, `execution_timeout`, `trigger_rule`, `pool`, `queue` — pass
  as decorator kwargs: `@task(retries=3, retry_delay=timedelta(minutes=5))`.

### Rule 2: BranchPythonOperator → @task.branch

**Before:**
```python
from airflow.providers.standard.operators.python import BranchPythonOperator

def choose_branch(**kwargs):
    if some_condition():
        return "process_large"
    return "process_small"

branch = BranchPythonOperator(
    task_id="choose_branch",
    python_callable=choose_branch,
)
```

**After:**
```python
from airflow.sdk import task

@task.branch
def choose_branch():
    if some_condition():
        return "process_large"
    return "process_small"

# Inside DAG body:
branch_result = choose_branch()
```

The function must return the `task_id` (or list of task_ids) of the branch to follow —
this is identical behavior to `BranchPythonOperator`.

### Rule 3: XCom data passing → function parameters

**Before:**
```python
def extract(**kwargs):
    data = fetch_from_api()
    kwargs["ti"].xcom_push(key="raw_data", value=data)

def transform(**kwargs):
    raw = kwargs["ti"].xcom_pull(task_ids="extract", key="raw_data")
    return process(raw)

extract_task = PythonOperator(task_id="extract", python_callable=extract)
transform_task = PythonOperator(task_id="transform", python_callable=transform)
extract_task >> transform_task
```

**After:**
```python
@task
def extract():
    return fetch_from_api()

@task
def transform(raw_data):
    return process(raw_data)

# Dependencies are automatic:
raw = extract()
result = transform(raw)
```

**When XCom uses custom keys:** If the original code pushes/pulls multiple keys from
a single task, return a dict from the `@task` function and access keys on the result:

```python
@task(multiple_outputs=True)
def extract():
    return {"users": fetch_users(), "orders": fetch_orders()}

@task
def process_users(users):
    ...

data = extract()
process_users(data["users"])
```

### Rule 4: Local imports

**Before (top-level):**
```python
import boto3
import requests
import pandas as pd
from some_heavy_lib import expensive_client

# ... 200 lines later, inside a function used by PythonOperator:
def upload_to_s3(data):
    s3 = boto3.client("s3")
    ...
```

**After (local):**
```python
@task
def upload_to_s3(data):
    import boto3
    s3 = boto3.client("s3")
    ...
```

**What to move:**
- Third-party libraries that are NOT used at DAG parse time (boto3, requests, pandas,
  numpy, any SDK clients).
- Any import only referenced inside `@task` function bodies, not at module level.

**What to keep at top level:**
- `airflow.sdk` imports (DAG, task, task_group, etc.)
- Airflow operator/provider imports
- Project includes (`include.airflow.*`, `include.superbet_group_data_pyops.*`)
- Standard library imports used at module level (datetime, os, timedelta, etc.)
- Anything referenced in `default_args`, DAG parameters, or operator instantiation
  outside `@task` functions.

### Rule 5: Handling existing `>>` dependencies

When a PythonOperator that gets converted to `@task` has explicit `>>` dependencies
with other (non-converted) operators:

**Before:**
```python
extract_task = PythonOperator(task_id="extract", python_callable=extract_fn)
sql_task = RenderedSQLExecuteQueryOperator(task_id="run_sql", ...)
extract_task >> sql_task
```

**After:**
```python
@task
def extract():
    return extract_fn_body()

result = extract()
sql_task = RenderedSQLExecuteQueryOperator(task_id="run_sql", ...)
result >> sql_task
```

The XComArg returned by calling a `@task` function supports `>>` for setting
dependencies with non-TaskFlow operators.

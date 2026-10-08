# Edge cases

### Task defined outside the DAG file
If `python_callable` points to a function imported from another module, you have two options:
1. **Inline it** — copy the function body into a `@task` in the DAG file (only if small).
2. **Wrap it** — create a thin `@task` wrapper that calls the imported function.

Option 2 is usually safer:
```python
from my_module import complex_processing

@task
def run_processing(input_data):
    return complex_processing(input_data)
```

### Closures over loop variables
If PythonOperators are created in a loop with closures, ensure the `@task` function
captures the variable correctly (Python late-binding pitfall):

```python
# WRONG — all tasks will use the last value of `table`
for table in tables:
    @task(task_id=f"process_{table}")
    def process():
        return do_something(table)  # Bug: captures reference, not value

# RIGHT — pass as parameter
for table in tables:
    @task(task_id=f"process_{table}")
    def process(t=table):  # default arg captures current value
        return do_something(t)
```

Do not introduce dynamic task mapping (`.expand()`) in this modernization flow.
Use static fan-out as the default pattern.

For heavy Python compute, prefer `KubernetesPodOperator` over mapped Celery tasks so
each run gets its own pod limits/requests and cannot starve shared workers.

```python
@task
def process(table: str) -> str:
    return do_something(table)

for table in ["table_a", "table_b", "table_c"]:
    process.override(task_id=f"process_{table}")(table)
```

### Tasks that access `context` / `kwargs["ti"]`
Replace with `get_current_context()`:
```python
from airflow.sdk import task, get_current_context

@task
def my_task():
    context = get_current_context()
    execution_date = context["logical_date"]
    ...
```

### Tasks with `provide_context=True`
This parameter was removed in Airflow 2.x already (context is always provided). Just
drop it — no replacement needed.

### Tasks with multiple XCom keys
Use `multiple_outputs=True`:
```python
@task(multiple_outputs=True)
def extract():
    return {"key1": value1, "key2": value2}

result = extract()
downstream1(result["key1"])
downstream2(result["key2"])
```

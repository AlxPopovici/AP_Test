---
name: modernize-airflow3-dag
description: Bring an old-style Airflow DAG up to current Airflow 3 best practices — primarily converting PythonOperator/BranchPythonOperator + manual XCom into the idiomatic TaskFlow API (@task, @task.branch, function-based data passing), and moving heavy top-level imports into task bodies. Use this whenever a DAG looks dated or a developer wants its task style cleaned up, even if they don't name a specific technique — e.g. "modernize this DAG", "bring this DAG up to best practices", "clean up/refactor this DAG's operators", "is this DAG written the old way?", "update this to current Airflow 3 style", "this DAG still uses PythonOperator, what should it use instead?" — as well as more specific asks: "convert to taskflow", "rewrite to use @task", "apply taskflow API", "convert PythonOperator to task decorator", "taskflow rewrite". Does not apply to general refactors unrelated to operator/TaskFlow style (renaming, splitting files, docstrings). Optionally shows how the DAG would look with the @dag decorator, but does not apply it by default.
---

# Modernize an Airflow 3 DAG

Bring a working Airflow 3 DAG up to current best practices — in practice this means
converting legacy operator style into idiomatic **TaskFlow API** patterns. The developer
asking for this may not know TaskFlow is the thing they need; that's fine, this skill's
job is to recognize the outdated pattern and apply the modern equivalent. This skill
assumes the DAG already parses and runs correctly — it only modernizes the authoring
style, preserving identical runtime behavior.

## Scope — what gets converted

| Legacy pattern | TaskFlow equivalent |
|---|---|
| `PythonOperator(task_id=..., python_callable=fn, op_args=..., op_kwargs=...)` | `@task` decorator on the function itself |
| `BranchPythonOperator(task_id=..., python_callable=fn)` | `@task.branch` decorator |
| `ti.xcom_pull(task_ids="...")` inside a callable | Function parameter (value passed directly) |
| `ti.xcom_push(key, value)` or `return value` from PythonOperator | Function return value |
| Heavy top-level imports (boto3, requests, pandas, etc.) | Moved inside the `@task` function body |

## Scope — what does NOT get converted

- **Non-Python operators** — `KubernetesPodOperator`, `RenderedSQLExecuteQueryOperator`,
  `BashOperator`, `EmptyOperator`, sensors, etc. These stay as-is. Only `PythonOperator`
  and `BranchPythonOperator` are candidates.
- **DAG structure** — the `with DAG(...) as dag:` context manager stays by default.
  See the "Optional: @dag decorator" section below for when/how to suggest it.
- **Task dependencies using `>>`** — these remain unchanged for operator tasks. For
  newly-converted `@task` functions, dependencies are inferred from function calls.
- **Callbacks** (`on_failure_callback`, `on_success_callback`) — stay on `default_args` or DAG.
- **`trigger_rule`** — when a PythonOperator has a non-default `trigger_rule`, pass it as
  a decorator argument: `@task(trigger_rule="all_done")`.

## Conversion rules

Five mechanical rules cover the conversion — PythonOperator → @task, BranchPythonOperator
→ @task.branch, XCom → function params, local imports, and `>>` dependencies on mixed
operator/TaskFlow graphs. Read [references/conversion-rules.md](references/conversion-rules.md)
before proposing a conversion.

## Optional: @dag decorator

By default this skill does NOT convert `with DAG(...) as dag:` to the `@dag` decorator.
However, after completing the conversion, **show the developer** what it would look like
and explain the trade-offs:

> **Optional further modernization:** Your DAG could also use the `@dag` decorator instead
> of `with DAG(...) as dag:`. Here's how it would look:
>
> ```python
> from airflow.sdk import dag, task
>
> @dag(
>     schedule="0 3 * * *",
>     start_date=datetime(2024, 9, 9),
>     catchup=False,
>     # ... same params as before
> )
> def my_pipeline_name():
>     # task definitions and calls here
>     ...
>
> my_pipeline_name()
> ```
>
> **Pros:** Cleaner encapsulation, the DAG is a function so testing/reuse is easier.
> **Cons:** Larger diff, all tasks must be defined/called inside the function body.
>
> Want me to apply this? [y/N]

Only apply if the developer explicitly says yes.

## Guardrails

- **Never apply without confirmation.** Always show the full proposed diff (or a clear
  before/after summary) and wait for explicit approval.
- **Never change runtime behavior.** The converted DAG must produce identical task graph
  shape, identical XCom data flow, and identical execution order. If you're unsure a
  conversion preserves behavior, flag it and ask.
- **Never convert tasks with complex `**kwargs` usage** where you can't fully trace what
  context keys are accessed. Flag these for manual review instead.
- **Never convert operators that aren't PythonOperator/BranchPythonOperator.** Even if
  they wrap a Python callable internally (e.g., sensors with `python_callable`), leave
  them as-is unless the developer explicitly asks.
- **Preserve `task_id` values.** Downstream systems (logs, monitoring, alerting) may
  reference task_ids. If the function name doesn't match the original `task_id`, use
  `@task(task_id="original_name")`.
- **Preserve `trigger_rule`, `retries`, `pool`, `queue`** — pass them as decorator kwargs.
- **Do not introduce `.expand()` in this skill.** Keep static fan-out for TaskFlow
  modernization. If mapping is requested, treat it as separate follow-up work.
- **Don't combine unrelated changes.** This skill only does TaskFlow modernization. Don't
  also rewrite tags, secrets, or fix other issues unless explicitly asked.

## Where to run this

Two contexts:

1. **As a migration step** (optional) — invoked by `migrate-pipeline` (or manually, after
   `rewrite-secrets`) on a pipeline that already lives on a `feat/migrate-<pipeline>` branch. Reuse
   that branch; do not create another one.
2. **Standalone**, against a pipeline already on `master` — the common case, since this skill is
   just as often asked for outside a migration run. Per this repo's CLAUDE.md ("Concurrent
   sessions — isolate your work"), create a dedicated worktree/branch first — never edit the
   primary checkout or `master`/`stage` directly:
   ```bash
   git worktree add ../data.monorepo.wt-modernize-airflow3-dag-<pipeline> -b modernize-airflow3-dag/<pipeline> origin/master
   ```

## Workflow

### Step 1 — Read the DAG

Read the target file. Identify:
- All `PythonOperator` and `BranchPythonOperator` instances.
- Their `python_callable` functions (may be defined elsewhere in the file or imported).
- XCom usage patterns (push/pull between tasks).
- Top-level imports that are only used inside operator callables.
- Any edge cases — see [references/edge-cases.md](references/edge-cases.md).

### Step 2 — Propose the conversion

For each operator being converted, show:
- The original code block.
- The proposed replacement.
- Any concerns or decisions needed.

Also list:
- Top-level imports being moved to local.
- Operators NOT being converted (and why — they aren't PythonOperator).
- The `@dag` suggestion (informational only, not applied).

Ask: **Apply these changes? [y/N]**

### Step 3 — Apply (only on explicit yes)

Make the edits. Ensure:
- Remove the `PythonOperator` import if no longer needed.
- Add `from airflow.sdk import task` if not already present.
- Keep the file otherwise unchanged.

### Step 4 — Verify

```bash
# Syntax check
python3 -c "import ast; ast.parse(open('<file>').read())"

# Run the smoke test if it exists
python3 <file>_test.py
```

Report results.

## Edge cases

Function-defined-elsewhere wrapping, closures over loop variables (and why this
skill keeps fan-out static), context/kwargs access, and multiple XCom
keys — see [references/edge-cases.md](references/edge-cases.md).

## Not a candidate for this skill

If the DAG has NO `PythonOperator` / `BranchPythonOperator` instances (e.g., it's
purely SQL operators + KubernetesPodOperators), inform the developer:

> This DAG doesn't use PythonOperator or BranchPythonOperator — there's nothing to
> convert to `@task`. It already follows a valid Airflow 3 pattern using dedicated
> operators. No changes needed.

## Reference

- [TaskFlow API docs (Airflow 3.3)](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/taskflow.html)
- [Task SDK API Reference](https://airflow.apache.org/docs/task-sdk/stable/api.html)

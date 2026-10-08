# Deriving README content from code

Everything here is an **inference to confirm**, not a fact to assert. Lead the developer with
it (*"the MERGE keys say the grain is one row per PLAYER_BONUS_ID per day — right?"*) so they
correct rather than compose. Where an inference is weak, say so in the README or move it to
**Open questions**.

---

## Outputs and write mode

Write mode is the highest-value derivation, because it is what makes the **Idempotent**
guarantee checkable. Grep the SQL for the write statement:

| SQL pattern | Write mode to record | Idempotent? |
| --- | --- | --- |
| `MERGE INTO t USING s ON ...` | `merge/upsert on <keys>` | **Yes** — rerun converges |
| `INSERT OVERWRITE INTO t` | `full reload` | **Yes** |
| `CREATE OR REPLACE TABLE t` | `full replace` | **Yes** |
| `DELETE FROM t WHERE <window>` then `INSERT INTO t` | `full partition reload` | **Yes**, if the delete covers exactly the insert's window |
| `TRUNCATE t` then `INSERT INTO t` | `full reload` | **Yes** |
| `INSERT INTO t` alone | `append` | **No** — rerun duplicates |
| `COPY INTO t ... FORCE = TRUE` | `append (duplicates on rerun)` | **No** — `FORCE` explicitly re-loads already-loaded files |
| `COPY INTO t` without `FORCE` | `append, load-history deduplicated` | Effectively yes, within the 64-day load history |

**The delete/insert case needs care.** `DELETE ... WHERE DT >= DATEADD(day, -20, CURRENT_DATE)`
followed by an insert of the same 20-day window is idempotent *and* self-healing for late data.
The same delete paired with an insert of only D-1 is not — it destroys 19 days of data. Read
both statements, not just the delete.

A DAG with several output tables can mix modes. Record one row per table.

## Inputs

Collect from every SQL file, then de-duplicate:

- `FROM <schema>.<table>` and every `JOIN` target. **Exclude CTE names** (anything defined in
  the file's own `WITH` clause) and the output table itself when it self-joins.
- Snowflake **streams** — named `S_<TARGET_SCHEMA>_<USECASE>` per
  `airflow_etl/docs/snowflake-object-naming.md` (e.g. `S_DW_CUSTOMER_PROFILE_2_ODS`). Record as a
  stream, because reading one consumes its offset, which makes reruns behave differently from a
  table read. **Flag a name that does not follow that pattern** — a `<name>_STREAM` suffix, or an
  `S_`-prefixed name that isn't `S_<TARGET_SCHEMA>_<USECASE>` — as a naming-convention violation
  in your report. Note it; don't rename anything.
- **APIs** — an `include.api_connect.source.*` class, or a `Variable.get("<name>")` feeding an
  HTTP call. Platform is `API`; note the source class and how the window is derived.
- **External databases, plain load** — a `KubernetesPodOperator` running
  `external-db-loader`, one task. You write the `SELECT`; the source server/schema comes from
  `config.yaml`, not the DAG. Platform is the `source_dbms` value — `mssql`, `mysql` or
  `postgres`.
- **External databases, full table sync** — some DAGs use `external-db-sync`
  (`ExternalTableSyncToSnowflake`) instead of calling the loader directly. It is a py-ops task
  group that generates the DDL, merge and soft-delete SQL at runtime and calls
  `external-db-loader` for the transfer step, so it expands to roughly 7 tasks per synced table
  and requires `dwh_etl_insert_timestamp`, `dwh_etl_update_timestamp` and `dwh_etl_deleted` on
  the target. Recognise the shape and don't read it as a plain load: the write mode is
  **merge + soft delete (generated)**, so it is normally idempotent, late data is covered by
  `lookback_period`, and rows dropped from the source are flagged via `dwh_etl_deleted` rather
  than deleted. Sync configs use `source_dbms` of `mssql` or `mysql` only — `postgres` appears
  for the bare loader but not for sync, so treat a postgres sync as an Open question.
- **S3** — a `COPY INTO ... FROM @stage`, or a bucket from `config.yaml`. Platform is `s3`.

Fully qualify everything as `SCHEMA.TABLE` so a later transform to a DataHub URN is mechanical.
Where a table is templated (`{{ params.table_schema }}.CIS_CUSTOMERS`), resolve the parameter
and write the real name.

## Grain

In descending order of reliability:

1. **`MERGE ... ON t.A = s.A AND t.B = s.B`** — the match keys *are* the grain. This is the
   strongest signal available.
2. **`QUALIFY ROW_NUMBER() OVER (PARTITION BY A, B ORDER BY ...) = 1`** — the partition keys are
   the intended grain, and the presence of this clause means the source is *not* at that grain.
3. **The final `SELECT`'s `GROUP BY`** — for aggregate outputs.
4. **A unique/primary key in the table DDL**, if the repo carries it.

Phrase it as the template does: `one row per <KEY> per <period>`. If the SQL shows no
deduplication anywhere and the source can repeat, say so plainly — the ing-cis README's
"one row per API pull per day (raw JSON records, not deduplicated by customer)" is the honest
shape for a raw landing table.

## Markets covered

- The **`markets:` tag** is the declared answer (`markets:sb_ro,sb_pl`). Trust it, then verify.
- SQL filters — `WHERE DOMAIN_ID IN (...)`, `WHERE MARKET = ...`.
- **Per-market task expansion** — a loop over a market list, or `.expand()` over one. The list
  itself may live in `config.yaml`.
- The API path — `v1/SB_RO/customer/...` pins a single market.

Where the DAG covers fewer markets than the squad's full set, the standard asks you to name
**which are deliberately excluded**. That is interview territory: code shows what runs, not
what was decided to leave out.

## Backfill and rerun safety

Three inputs decide this:

1. **`catchup`** — `False` (the norm here) means Airflow will not auto-backfill; a past
   interval needs a manual trigger.
2. **`start_date`** — nothing earlier is triggerable without editing the DAG. Name the date.
3. **How the SQL windows.** SQL filtered on `data_interval_start` / `data_interval_end`
   backfills correctly for any past logical date. SQL using `CURRENT_DATE`, `SYSDATE` or
   `CURRENT_TIMESTAMP` **does not** — a "backfill" re-reads today and writes it to a past
   partition. That is a real bug worth flagging, not just a doc note.

Also check the shifted-macro trap: in Airflow 3, `logical_date` and everything derived from it
(`ds`, `ts`, `prev_ds`, `yesterday_ds`, …) mean "when the run was queued", not "start of the
data interval". A DAG partitioning on `ds` silently pulls the wrong date and never raises. See
`dev_tools/airflow3_migration/DATE_VARIABLES.md`.

A rolling window (`last 20 days`) makes the pipeline self-healing: a missed day is repaired by
the next successful run, so "backfill" is often *"not needed — the next run reclaims it"*.

## Alert resolution

From `IncidentIOConfig(notification_level=...)`. Allowed values are `dag`, `task`, `run`
(`airflow_etl/include/airflow/alerting/incident_io/config.py`).

**All three levels auto-resolve on success** — `attach_to` wires `on_success_callback` to
`close_alert` for every one of them. What differs is the **deduplication key**, and that is what
decides whether a later success can actually close an earlier failure's alert:

| Level | Deduplication key | Record as |
| --- | --- | --- |
| `dag` | `<env>:<dag_id>` | resolves **automatically** on the next successful DAG run |
| `task` | `<env>:<dag_id>:<task_id>` | resolves **automatically** on the next success of that task |
| `run` | `<env>:<dag_id>:<task_id>:<run_id>` | does **not** resolve from a later run — must be closed manually, or by clearing that specific run to success |

Only `run` pins the key to a single `run_id`, so a subsequent run produces a *different* key and
can never resolve the failed run's alert. `dag` and `task` both can — `task` is not the safe
middle ground it looks like.

**One override:** `retrigger_every_time=True` appends a timestamp to the key, making every alert
unique, so nothing auto-resolves at any level. If it is set, say so.

Record the *action*, not the routing target — routing lives in incident.io, and restating it
would break the commit rule. "You must close this by hand" is an action, and it matters: while
an alert stays open, no new alert fires for the **same deduplication key** — so at `run` level a
forgotten manual close is an active blind spot for that task, not just untidiness.

Then run the coupling check in SKILL.md Step 5 — `Idempotent: no` combined with
`notification_level="dag"` **or `"task"`** is a misconfiguration nothing else catches.

## Common failure modes

Mine the code for these rather than asking the developer to remember them cold. Each is a real
finding from the reference implementation's review:

- **No HTTP timeout** on an API call — a hanging upstream leaves the task stuck rather than
  failing, so no alert fires.
- **`ON_ERROR = ABORT_STATEMENT`** on a `COPY INTO` — one malformed record aborts the whole load.
- **`TRUNCATECOLUMNS = TRUE`** — oversized values are silently truncated. A data-quality risk
  rather than a failure mode, but it belongs in the runbook.
- **Cursor pagination** that assumes `next_key` / `has_next_page` always exist — a malformed
  response throws `KeyError`.
- **`ExternalTaskSensor`** — note its timeout and what it waits on; a shifted `execution_date_fn`
  waits forever on an interval that never existed.
- **`retries` / `retry_delay`** from `default_args` — state them, since they set how long a
  transient failure takes to surface.
- **KPO image pulls** — a moving `:latest` tag means the DAG can break with no repo change.

## Domain

**This table is the single source of truth for the allowed `Domain` values.** The template and
[section-rules.md](section-rules.md) both point here rather than restating the list, so a DataHub
domain rename or addition is a one-file change. Don't copy the values into another file.

`Domain` is the **DataHub business domain**, not the folder name. The Player squad's real
domains in DataHub are exactly four:

| Domain | Use for |
| --- | --- |
| `Join & Engage` | Acquisition, bonusing, engagement, CRM-adjacent player activity |
| `Transact` | Payments, deposits, withdrawals, wallet |
| `Manage` | Player profile, KYC, limits, exclusions, blocks |
| `Player` | The parent — use only when none of the three fits |

Map the sub-area folder to a candidate, then confirm — `payments/` → `Transact`,
`profile/` → `Manage`, `engagement/` → `Join & Engage`. Verify against the output table's actual
domain in DataHub (`get_entities` on the dataset URN) where one is assigned.

> **`Manage` is the squad's preferred label; DataHub currently records this domain as
> `Player - Account Management`.** Use `Manage` in the README. If DataHub shows the longer form,
> that is expected, not a mismatch to flag.

> The reference README currently records `Domain: Customer Profile`, which is not one of the four
> — `Manage` is the right value for it. Don't copy that value; it predates this constraint.

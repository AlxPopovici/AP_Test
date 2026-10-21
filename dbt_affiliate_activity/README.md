# affiliate_activity (dbt, learning project)

dbt port of the affiliate player activity query: weekly and monthly counts of active, new, retained,
reactivated and inactive players per domain, marketing channel, source and coupon.
Everything builds into `PROD.SBX_BI` (macro `generate_schema_name`) and every object gets a `DBT_` prefix
(macro `generate_alias_name`), e.g. `int_player_base` becomes `DBT_INT_PLAYER_BASE`.
The final table is `DBT_AFFILIATE_PLAYER_ACTIVITY`.

## Layout

| Layer | Model | Replaces (CTE in the original SQL) | Materialized as |
|---|---|---|---|
| staging | `stg_unified_dates` | `CTE_UNIFIED_DATES` | view |
| intermediate | `int_players` | `CTE_PLAYERS` | view |
| intermediate | `int_player_base` | `CTE_PLAYER_BASE` | table |
| intermediate | `int_player_states_weekly` | `CTE_ACTIVE_PERIODS_W`, `CTE_PLAYER_FIRST_PERIOD_W`, `CTE_ACTIVE_STATES_W`, `CTE_INACTIVE_STATES_W` | table |
| intermediate | `int_player_states_monthly` | the four `_M` CTEs | table |
| marts | `dbt_affiliate_player_activity` | final `SELECT ... UNION ALL SELECT ...` | table |

The weekly and monthly models are one-liners calling the macro `player_activity_states(grain, domain_id)`
in `macros/player_activity_states.sql`.

The original query is kept in `macros/original_affiliate_activity_query.sql` (rendered by `analyses/original_query.sql`)
so the dbt output can be reconciled against it.

## Setup

The virtualenv of the sibling project already has dbt-core and dbt-snowflake:

```
cd AP_Test/dbt_affiliate_activity
source ../dbt/.venv/bin/activate
export SNOWFLAKE_ACCOUNT=...   # see the note in profiles.yml
export SNOWFLAKE_USER=alexandru.popovici@super.xyz
export SNOWFLAKE_ROLE=FR__DI
export SNOWFLAKE_WAREHOUSE=...
dbt deps --profiles-dir .
dbt debug --profiles-dir .      # opens the SSO browser window
```

## Running

```
dbt compile --profiles-dir .                                         # no writes, look at target/compiled/
dbt build   --profiles-dir . --vars '{dev_domain_ids: [16]}'         # restricted dev run (Greece only)
dbt build   --profiles-dir .                                         # all domains
dbt test    --profiles-dir . --select assert_matches_original_query \
            --vars '{run_reconcile: true, dev_domain_ids: [16]}'     # compare with the original SQL
```

## Tests

- Generic: `not_null` on keys, `unique` on `PLAYER_UNIFIED_CODE` (warn only on `int_player_base`), `accepted_values` on
  `granularity` and `business_domain_id`, `unique_combination_of_columns` on the output grain.
- `assert_active_equals_new_retained_reactivated`: ACTIVE = NEW + RETAINED + REACTIVATED on every output row.
- `assert_matches_original_query`: row by row comparison with the original SQL. Disabled unless `run_reconcile` is true.

## Decisions on the original SQL

- Changed: the monthly block had `BUSINESS_DOMAIN_ID = 16` on the performance table, the weekly block did not.
  Confirmed as a mistake, so both now cover all domains. The reference copy of the original query got the same fix,
  otherwise the reconciliation test would flag the difference.
- Kept: `IS_TEST_ACCOUNT != 1` (not `= 0`). Some Belgium accounts carry the values 2 and 3 and are real players.
- Kept: `D_REGISTRATION_REPORTING_DAILY` is joined on `PLAYER_ID`. It should hold one row per player. The only
  duplicates are several `PLAYER_ID`s behind one `PLAYER_UNIFIED_CODE` in Belgium, and `int_players` already collapses
  those. A warn-level `unique` test on the source documents the assumption.
- Checked: `DATE_TRUNC('WEEK')` follows the account setting `WEEK_START = 0` (weeks start on Monday). dbt uses the same
  account defaults, so weekly periods match the worksheet.

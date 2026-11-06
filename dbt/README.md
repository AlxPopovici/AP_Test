# attribution_v2 (dbt, throwaway test)

dbt port of the Attribution V2 Tableau source `PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2`.
Everything builds into `PROD.SBX_BI`; the final table is `DBT_ASDK_AGG_ATTRIBUTION_DATA_V2`, so it
does not touch the existing `TMP_VW_*` views.

## Layout

| Layer | Models | Replaces (CTE in the original SQL) |
|---|---|---|
| staging | `stg_player_reg_attribution`, `stg_ltv` | `INITIAL_BASE`, `LTV` |
| intermediate | `int_player_performance`, `int_player_attribution_base`, `int_attribution_registrations`, `int_attribution_ftds` | `PERFORMANCE`, `BASE`, `CTE_REGISTRATIONS`, `CTE_FTDS` |
| marts | `dbt_asdk_agg_attribution_data_v2` | `CTE_ALL_KEYS` + final SELECT |

Staging and intermediate are views, the mart is a table.

## Setup

```
python3.12 -m venv .venv && source .venv/bin/activate
pip install dbt-snowflake
export SNOWFLAKE_ACCOUNT=... SNOWFLAKE_USER=alexandru.popovici@super.xyz SNOWFLAKE_ROLE=... SNOWFLAKE_WAREHOUSE=...
dbt deps --profiles-dir .
dbt debug --profiles-dir .      # opens the SSO browser window
dbt build --profiles-dir .
```

## Tests

- Generic: not_null / unique on player grain, unique key combination and accepted domain ids on the mart.
- `assert_ltv_actualized_matches_actuals_for_mature_cohorts`: FTD 12+ months old must equal Actual_Y1 (NGR for BR, NGP elsewhere).
- `assert_matches_prod_v2_view`: totals per domain vs the existing `TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2`. Disabled, because that view is not readable by `FR__DI`.

## Source note

`PROD.DM_MARTECH.VW_PLAYER_REG_ATTRIBUTION` (used by the original SQL) was not visible to role `FR__DI` —
and per the 2026-10-12 investigation, it no longer exists at all. `VW_F_PLAYER_REG_ATTRIBUTION` is also
broken (orphaned, stale 29-column definition vs. the table's 32). The staging model now reads
`PROD.DM_MARTECH.F_PLAYER_REG_ATTRIBUTION` directly — the fact table both views used to wrap, with 3 extra
AppsFlyer-install columns (`ATTRIBUTED_TOUCH_TYPE`, `AF_EVENT_DT`, `AF_EVENT_DATE`) neither view ever picked
up and this model still doesn't select. Totals can differ from the existing `TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2`
for that reason, independent of the test-account filter bug noted below.

## Known quirk carried over from the source SQL

The `INITIAL_BASE` WHERE clause has `A OR B AND IS_TEST_ACCOUNT != 1` with no parentheses, so the
test account filter only applies to the FTD branch. The port keeps this so the filter logic
matches the original SQL. See the comment in `stg_player_reg_attribution.sql` for the intended filter.

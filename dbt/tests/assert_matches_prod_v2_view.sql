{{ config(enabled=false) }}
-- Disabled: TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2 reads the legacy VW_PLAYER_REG_ATTRIBUTION, which role FR__DI cannot
-- see, so the view cannot be queried. Re-enable with a role that has access.
-- Parity check against the existing production-style view. Returns domains where
-- the dbt port and PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2 disagree on key totals.
-- Warn only: the dbt model reads the new Attribution V2 pipeline view, the existing view may read the legacy one,
-- so differences are expected and worth reviewing rather than blocking.
WITH dbt_side AS (
    SELECT BUSINESS_DOMAIN_ID, SUM(REGS) AS REGS, SUM(FTDS) AS FTDS, SUM(LTV_ACTUALIZED) AS LTV_ACTUALIZED
    FROM {{ ref('dbt_asdk_agg_attribution_data_v2') }}
    GROUP BY ALL
),
view_side AS (
    SELECT BUSINESS_DOMAIN_ID, SUM(REGS) AS REGS, SUM(FTDS) AS FTDS, SUM(LTV_ACTUALIZED) AS LTV_ACTUALIZED
    FROM PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2
    GROUP BY ALL
)
SELECT
    COALESCE(d.BUSINESS_DOMAIN_ID, v.BUSINESS_DOMAIN_ID) AS BUSINESS_DOMAIN_ID,
    d.REGS AS DBT_REGS, v.REGS AS VIEW_REGS,
    d.FTDS AS DBT_FTDS, v.FTDS AS VIEW_FTDS,
    d.LTV_ACTUALIZED AS DBT_LTV_ACTUALIZED, v.LTV_ACTUALIZED AS VIEW_LTV_ACTUALIZED
FROM dbt_side d
FULL OUTER JOIN view_side v ON d.BUSINESS_DOMAIN_ID = v.BUSINESS_DOMAIN_ID
WHERE COALESCE(d.REGS, 0) != COALESCE(v.REGS, 0)
   OR COALESCE(d.FTDS, 0) != COALESCE(v.FTDS, 0)
   OR ABS(COALESCE(d.LTV_ACTUALIZED, 0) - COALESCE(v.LTV_ACTUALIZED, 0)) > 1

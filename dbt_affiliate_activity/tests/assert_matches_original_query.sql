-- Reconciliation: the dbt output must equal the original query, row for row.
-- Off by default because it runs the original query too (expensive). Enable with:
--   dbt test --select assert_matches_original_query --vars '{run_reconcile: true, dev_domain_ids: [16]}'
-- A test passes when it returns zero rows. Every row returned here is a difference.
{{ config(enabled=var('run_reconcile', false), tags=['reconcile']) }}

WITH original AS (
    {{ original_affiliate_activity_query() }}
),

only_in_original AS (
    SELECT *
    FROM original
    WHERE BUSINESS_DOMAIN_ID IN ({{ var('dev_domain_ids') | join(', ') }})
    EXCEPT
    SELECT *
    FROM {{ ref('dbt_affiliate_player_activity') }}
    WHERE BUSINESS_DOMAIN_ID IN ({{ var('dev_domain_ids') | join(', ') }})
),

only_in_dbt AS (
    SELECT *
    FROM {{ ref('dbt_affiliate_player_activity') }}
    WHERE BUSINESS_DOMAIN_ID IN ({{ var('dev_domain_ids') | join(', ') }})
    EXCEPT
    SELECT *
    FROM original
    WHERE BUSINESS_DOMAIN_ID IN ({{ var('dev_domain_ids') | join(', ') }})
)

SELECT 'only_in_original' AS DIFF_SIDE, * FROM only_in_original
UNION ALL
SELECT 'only_in_dbt' AS DIFF_SIDE, * FROM only_in_dbt

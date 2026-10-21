{#
    Player activity states at a given period grain.

    One row per player and period, flagged as:
      - active rows (the player bet in the period): IS_ACTIVE = 1, plus exactly one of
        IS_NEW (first ever active period), IS_RETAINED (also active the previous period)
        or IS_REACTIVATED (not active the previous period, but active before)
      - inactive rows (the player was active in the previous period, not in this one): IS_INACTIVE = 1

    Arguments
      grain      'WEEK' or 'MONTH'. Drives DATE_TRUNC and DATEADD.

    Replaces the CTE_*_W and CTE_*_M blocks of the original SQL, which were identical except for the grain
    (the original monthly block also had a stray BUSINESS_DOMAIN_ID = 16 filter, confirmed as a mistake and dropped).
#}
{% macro player_activity_states(grain) %}

{%- set grain = grain | upper -%}
{%- if grain not in ['WEEK', 'MONTH'] -%}
    {{ exceptions.raise_compiler_error("player_activity_states: grain must be WEEK or MONTH, got " ~ grain) }}
{%- endif -%}

WITH active_periods AS (
    SELECT
        base.BUSINESS_DOMAIN_ID,
        base.MKT_CHANNEL,
        base.MKT_SOURCE,
        base.COUPON_NAME,
        base.PLAYER_UNIFIED_CODE,
        DATE_TRUNC('{{ grain }}', per.REPORTING_DATE) AS PERIOD
    FROM {{ source('dm_player', 'f_player_product_performance_daily') }} per
    INNER JOIN {{ ref('int_player_base') }} base
        ON per.PLAYER_UNIFIED_CODE = base.PLAYER_UNIFIED_CODE
    WHERE
        per.BET_TOTAL > 0
        AND per.REPORTING_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE()) - INTERVAL '25 MONTHS'
    GROUP BY ALL
),

player_first_period AS (
    SELECT
        PLAYER_UNIFIED_CODE,
        MIN(PERIOD) AS FIRST_ACTIVE_PERIOD
    FROM active_periods
    GROUP BY PLAYER_UNIFIED_CODE
),

active_states AS (
    SELECT
        curr.BUSINESS_DOMAIN_ID,
        curr.MKT_CHANNEL,
        curr.MKT_SOURCE,
        curr.COUPON_NAME,
        curr.PLAYER_UNIFIED_CODE,
        curr.PERIOD,
        1 AS IS_ACTIVE,
        CASE WHEN prev.PLAYER_UNIFIED_CODE IS NOT NULL THEN 1 ELSE 0 END AS IS_RETAINED,
        CASE WHEN curr.PERIOD = fp.FIRST_ACTIVE_PERIOD THEN 1 ELSE 0 END AS IS_NEW,
        CASE
            WHEN prev.PLAYER_UNIFIED_CODE IS NULL
                AND curr.PERIOD != fp.FIRST_ACTIVE_PERIOD
                THEN 1
            ELSE 0
        END AS IS_REACTIVATED,
        0 AS IS_INACTIVE
    FROM active_periods curr
    LEFT JOIN active_periods prev
        ON prev.PLAYER_UNIFIED_CODE = curr.PLAYER_UNIFIED_CODE
        AND prev.PERIOD = DATEADD('{{ grain }}', -1, curr.PERIOD)
    INNER JOIN player_first_period fp
        ON fp.PLAYER_UNIFIED_CODE = curr.PLAYER_UNIFIED_CODE
),

inactive_states AS (
    SELECT
        prev.BUSINESS_DOMAIN_ID,
        prev.MKT_CHANNEL,
        prev.MKT_SOURCE,
        prev.COUPON_NAME,
        prev.PLAYER_UNIFIED_CODE,
        DATEADD('{{ grain }}', 1, prev.PERIOD) AS PERIOD,
        0 AS IS_ACTIVE,
        0 AS IS_RETAINED,
        0 AS IS_NEW,
        0 AS IS_REACTIVATED,
        1 AS IS_INACTIVE
    FROM active_periods prev
    LEFT JOIN active_periods curr
        ON curr.PLAYER_UNIFIED_CODE = prev.PLAYER_UNIFIED_CODE
        AND curr.PERIOD = DATEADD('{{ grain }}', 1, prev.PERIOD)
    WHERE
        curr.PLAYER_UNIFIED_CODE IS NULL
        AND DATEADD('{{ grain }}', 1, prev.PERIOD) < DATE_TRUNC('{{ grain }}', CURRENT_DATE())
)

SELECT * FROM active_states
UNION ALL
SELECT * FROM inactive_states

{% endmacro %}

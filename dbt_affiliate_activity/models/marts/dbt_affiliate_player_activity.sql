-- Affiliate player activity (active / new / retained / reactivated / inactive) per domain, channel,
-- source, coupon and period, at weekly and monthly granularity.
-- Original SQL: the final SELECT ... UNION ALL SELECT.
{% set grains = [
    ('WEEKLY', 'int_player_states_weekly'),
    ('MONTHLY', 'int_player_states_monthly'),
] %}

{% for granularity, model_name in grains %}
SELECT
    '{{ granularity }}' AS GRANULARITY,
    BUSINESS_DOMAIN_ID,
    MKT_CHANNEL,
    MKT_SOURCE,
    COUPON_NAME,
    PERIOD,
    COUNT(DISTINCT CASE WHEN IS_ACTIVE = 1 THEN PLAYER_UNIFIED_CODE END) AS ACTIVE_PLAYERS,
    COUNT(DISTINCT CASE WHEN IS_NEW = 1 THEN PLAYER_UNIFIED_CODE END) AS NEW_PLAYERS,
    COUNT(DISTINCT CASE WHEN IS_RETAINED = 1 THEN PLAYER_UNIFIED_CODE END) AS RETAINED_PLAYERS,
    COUNT(DISTINCT CASE WHEN IS_REACTIVATED = 1 THEN PLAYER_UNIFIED_CODE END) AS REACTIVATED_PLAYERS,
    COUNT(DISTINCT CASE WHEN IS_INACTIVE = 1 THEN PLAYER_UNIFIED_CODE END) AS INACTIVE_PLAYERS
FROM {{ ref(model_name) }}
GROUP BY ALL
{% if not loop.last %}
UNION ALL
{% endif %}
{% endfor %}

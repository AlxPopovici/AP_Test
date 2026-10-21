-- Every active player in a period is exactly one of: new, retained, reactivated.
-- So ACTIVE_PLAYERS must equal NEW + RETAINED + REACTIVATED on every output row.
-- A test passes when it returns zero rows. Rows returned here are broken groups.
-- If this fails, check for player fan-out in int_player_base (one player with several coupon / source rows).
SELECT
    GRANULARITY,
    BUSINESS_DOMAIN_ID,
    MKT_CHANNEL,
    MKT_SOURCE,
    COUPON_NAME,
    PERIOD,
    ACTIVE_PLAYERS,
    NEW_PLAYERS + RETAINED_PLAYERS + REACTIVATED_PLAYERS AS EXPECTED_ACTIVE_PLAYERS
FROM {{ ref('dbt_affiliate_player_activity') }}
WHERE ACTIVE_PLAYERS != NEW_PLAYERS + RETAINED_PLAYERS + REACTIVATED_PLAYERS

-- One row per player account (D_PLAYER), plus the earliest registration / FTD across all accounts
-- that share the same PLAYER_UNIFIED_CODE (BE merges several PLAYER_IDs into one identity).
-- Original SQL: CTE_UNIFIED_DATES.
SELECT DISTINCT
    dp.PLAYER_UNIFIED_CODE,
    dp.PLAYER_ID,
    dp.BUSINESS_DOMAIN_ID,
    dbd.BUSINESS_DOMAIN_NAME,
    dp.REGISTRATION_DT AS REG_DT,
    dp.FIRST_TIME_DEPOSIT_DT AS FTD_DT,
    dp.REGISTRATION_CHANNEL_CODE,
    MIN(dp.REGISTRATION_DT) OVER (PARTITION BY dp.PLAYER_UNIFIED_CODE) AS REGISTRATION_DT,
    MIN(dp.FIRST_TIME_DEPOSIT_DT) OVER (PARTITION BY dp.PLAYER_UNIFIED_CODE) AS FIRST_TIME_DEPOSIT_DT,
    dbm.COUNTRY_TIMEZONE
FROM {{ source('dwh', 'd_player') }} dp
INNER JOIN {{ source('dwh', 'd_business_market') }} dbm
    ON dp.BUSINESS_MARKET_ID = dbm.BUSINESS_MARKET_ID
INNER JOIN {{ source('dwh', 'd_business_domain') }} dbd
    ON dp.BUSINESS_DOMAIN_ID = dbd.BUSINESS_DOMAIN_ID
WHERE
    -- Both Brazilian domains (1, 14) kept for continuity. Restrict with --vars '{dev_domain_ids: [16]}'.
    dp.BUSINESS_DOMAIN_ID IN ({{ var('dev_domain_ids') | join(', ') }})
    AND dp.BUSINESS_LINE_ID = 1 -- online
    AND dp.IS_VALID = 1
    AND dp.IS_TEST_ACCOUNT != 1

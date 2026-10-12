-- Player-level attribution with timezone-corrected REG/FTD dates, last 3 full calendar years + current year.
-- Ported from ATTRIBUTION 2.0 V2(LTV Actualized into sql).sql (CTE INITIAL_BASE).
-- Source is PROD.DM_MARTECH.VW_F_PLAYER_REG_ATTRIBUTION (Attribution V2 pipeline) instead of the legacy
-- VW_PLAYER_REG_ATTRIBUTION, which is not visible to role FR__DI. Same columns, so the logic is unchanged.
--
-- NOTE: the original WHERE clause mixes OR and AND without parentheses, so
-- IS_TEST_ACCOUNT != 1 only applies to the FTD branch. Kept as-is so this model matches
-- the original filter logic. Fix is in the commented block below.
SELECT
    asdk.BUSINESS_DOMAIN_ID,
    asdk.PLAYER_ID,
    CONVERT_TIMEZONE('UTC', dbm.COUNTRY_TIMEZONE, asdk.REGISTRATION_DT)::DATE AS REGISTRATION_DT_LOCAL,
    CONVERT_TIMEZONE('UTC', dbm.COUNTRY_TIMEZONE, asdk.FIRST_TIME_DEPOSIT_DT)::DATE AS FIRST_TIME_DEPOSIT_DT_LOCAL,
    asdk.ACQUISITION_SOURCE_GROUP AS FINAL_ACQUISITION_SOURCE_GROUP,
    asdk.ACQUISITION_CHANNEL AS FINAL_ACQUISITION_CHANNEL,
    asdk.ACQUISITION_SUBCHANNEL AS FINAL_ACQUISITION_SUBCHANNEL,
    asdk.PLATFORM_TYPE AS FINAL_PLATFORM_TYPE,
    COALESCE(asdk.AD_PLATFORM, 'UNK') AS FINAL_AD_PLATFORM,
    asdk.ATTRIBUTION_SOURCE AS FINAL_ATTRIBUTION_SOURCE,
    asdk.MAPPING_USED AS FINAL_MAPPING_USED
FROM {{ source('dm_martech', 'vw_f_player_reg_attribution') }} asdk
LEFT JOIN {{ source('dwh', 'd_business_market') }} dbm
    ON asdk.BUSINESS_MARKET_ID = dbm.BUSINESS_MARKET_ID
WHERE
    asdk.REGISTRATION_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')
    OR asdk.FIRST_TIME_DEPOSIT_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')
    AND asdk.IS_TEST_ACCOUNT != 1

-- Intended filter (not applied, would change row counts vs V2):
-- WHERE (asdk.REGISTRATION_DT >= ... OR asdk.FIRST_TIME_DEPOSIT_DT >= ...)
--   AND asdk.IS_TEST_ACCOUNT = 0

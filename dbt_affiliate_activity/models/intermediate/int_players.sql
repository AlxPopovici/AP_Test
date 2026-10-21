-- One row per PLAYER_UNIFIED_CODE with the PLAYER_ID of the earliest registration and local REG / FTD timestamps.
-- Original SQL: CTE_PLAYERS.
SELECT
    dp.PLAYER_UNIFIED_CODE,
    COALESCE(
        MIN(CASE WHEN dp.REG_DT = dp.REGISTRATION_DT THEN reg.PLAYER_ID END),
        MIN(CASE WHEN dp.REG_DT = dp.REGISTRATION_DT THEN dp.PLAYER_ID END)
    ) AS PLAYER_ID,
    MIN(dp.BUSINESS_DOMAIN_ID) AS BUSINESS_DOMAIN_ID,
    MIN(dp.BUSINESS_DOMAIN_NAME) AS BUSINESS_DOMAIN_NAME,
    MIN(CONVERT_TIMEZONE('UTC', dp.COUNTRY_TIMEZONE, dp.REGISTRATION_DT)) AS REGISTRATION_DT_LOCAL,
    MIN(CONVERT_TIMEZONE('UTC', dp.COUNTRY_TIMEZONE, dp.FIRST_TIME_DEPOSIT_DT)) AS FIRST_TIME_DEPOSIT_DT_LOCAL
FROM {{ ref('stg_unified_dates') }} dp
-- Pre-Van Hecke attributed registrations (BE, before the 2024-09-02 go-live)
LEFT JOIN {{ source('dm_martech', 'd_registration_reporting_daily') }} reg
    ON dp.PLAYER_ID = reg.PLAYER_ID
    AND reg.BUSINESS_DOMAIN_ID = 8
    AND reg.REGISTRATION_DT < '2024-09-02'::date
    AND reg.ACQUISITION_GROUP <> 'Organic'
GROUP BY 1

-- Affiliate players registered or FTD'd in the last 25 months, with channel / source / coupon.
-- Stored as a table because the weekly and monthly models both read it.
-- Original SQL: CTE_PLAYER_BASE.
SELECT
    dp.PLAYER_UNIFIED_CODE,
    dp.PLAYER_ID,
    dp.BUSINESS_DOMAIN_ID,
    dp.REGISTRATION_DT_LOCAL,
    dp.FIRST_TIME_DEPOSIT_DT_LOCAL,
    reg.COUPON_NAME AS COUPON_NAME,
    COALESCE(dcr.MARKETING_CHANNEL_MAPPED, reg.MARKETING_CHANNEL_MAPPED) AS MKT_CHANNEL,
    COALESCE(dcr.MARKETING_SOURCE_MAPPED, reg.MARKETING_SOURCE_MAPPED) AS MKT_SOURCE
FROM {{ ref('int_players') }} dp
LEFT JOIN {{ source('dm_martech', 'd_registration_reporting_daily') }} reg
    ON dp.PLAYER_ID = reg.PLAYER_ID
-- Map coupon codes in line with the PL marketing team preferences
LEFT JOIN {{ source('bi', 'd_coupon_reporting') }} dcr
    ON reg.BUSINESS_DOMAIN_ID = dcr.BUSINESS_DOMAIN_ID
    AND LOWER(reg.MARKETING_SOURCE_NAME) = LOWER(dcr.MARKETING_SOURCE_NAME)
    AND LOWER(reg.COUPON_NAME) = LOWER(dcr.COUPON_NAME)
    AND reg.ATTRIBUTION_SOURCE LIKE '%Betler%'
WHERE
    COALESCE(NULLIF(COALESCE(dcr.ACQUISITION_CHANNEL, reg.ACQUISITION_CHANNEL), 'UNK'), 'Organic - Superbet') = 'Affiliate'
    AND (
        DATE(dp.REGISTRATION_DT_LOCAL) >= DATE_TRUNC('MONTH', CURRENT_DATE()) - INTERVAL '25 MONTHS'
        OR DATE(dp.FIRST_TIME_DEPOSIT_DT_LOCAL) >= DATE_TRUNC('MONTH', CURRENT_DATE()) - INTERVAL '25 MONTHS'
    )
    AND DATE(dp.REGISTRATION_DT_LOCAL) < CURRENT_DATE()

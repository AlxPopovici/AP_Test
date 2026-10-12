-- Player-level grain: attribution + performance + LTV + expected share + LTV actualized + conversion windows.
-- LTV_ACTUALIZED: FTD < 12 calendar months ago = Actual_Y1 + (LTV - LTV_SINCE_FTD); otherwise Actual_Y1.
-- Actual_Y1 is NGR_Y1 for BR (domains 1, 14) and NGP_Y1 for all other markets.
SELECT
    asdk.BUSINESS_DOMAIN_ID,
    asdk.PLAYER_ID,
    asdk.REGISTRATION_DT_LOCAL,
    asdk.FIRST_TIME_DEPOSIT_DT_LOCAL,
    asdk.FINAL_ACQUISITION_SOURCE_GROUP,
    asdk.FINAL_ACQUISITION_CHANNEL,
    asdk.FINAL_ACQUISITION_SUBCHANNEL,
    asdk.FINAL_PLATFORM_TYPE,
    asdk.FINAL_AD_PLATFORM,
    asdk.FINAL_ATTRIBUTION_SOURCE,
    asdk.FINAL_MAPPING_USED,
    -- performance
    perf.NGR_30D,
    perf.NGP_30D,
    perf.NGR_Y1,
    perf.NGP_Y1,
    -- ltv
    ltv.LTV,
    ltv.LTV * es.CUMULATIVE_PCT AS LTV_SINCE_FTD,
    CASE
        WHEN asdk.FIRST_TIME_DEPOSIT_DT_LOCAL IS NULL THEN NULL
        WHEN DATEDIFF('month', asdk.FIRST_TIME_DEPOSIT_DT_LOCAL, CURRENT_DATE()) < 12
            THEN COALESCE(CASE WHEN asdk.BUSINESS_DOMAIN_ID IN (1, 14) THEN perf.NGR_Y1 ELSE perf.NGP_Y1 END, 0)
                 + COALESCE(ltv.LTV, 0) - COALESCE(ltv.LTV * es.CUMULATIVE_PCT, 0)
        ELSE COALESCE(CASE WHEN asdk.BUSINESS_DOMAIN_ID IN (1, 14) THEN perf.NGR_Y1 ELSE perf.NGP_Y1 END, 0)
    END AS LTV_ACTUALIZED,
    -- conversion windows (days from registration to FTD)
    CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 1  THEN 1 ELSE 0 END AS IS_FTD_D2,
    CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 6  THEN 1 ELSE 0 END AS IS_FTD_D7,
    CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 13 THEN 1 ELSE 0 END AS IS_FTD_D14,
    CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 27 THEN 1 ELSE 0 END AS IS_FTD_D28
FROM {{ ref('stg_player_reg_attribution') }} asdk
LEFT JOIN {{ ref('stg_ltv') }} ltv USING (PLAYER_ID)
LEFT JOIN {{ ref('int_player_performance') }} perf USING (PLAYER_ID)
LEFT JOIN {{ source('bi', 'ltv_expected_share') }} es
    ON  asdk.BUSINESS_DOMAIN_ID = es.BUSINESS_DOMAIN_ID
    AND es.WEEKS_SINCE_FTD = DATEDIFF('week', DATE_TRUNC('week', asdk.FIRST_TIME_DEPOSIT_DT_LOCAL), DATE_TRUNC('week', CURRENT_DATE()))
    AND asdk.FIRST_TIME_DEPOSIT_DT_LOCAL >= DATEADD('YEAR', -1, DATE_TRUNC('YEAR', CURRENT_DATE()))

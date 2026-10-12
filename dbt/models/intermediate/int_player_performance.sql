-- Actual NGP/NGR in EUR per player: 30-day and Y1 (365-day) windows post-FTD.
SELECT
    dp.PLAYER_ID,
    SUM(CASE WHEN fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 30 THEN fpppd.NGP * fer.MIDDLE_RATE ELSE 0 END) AS NGP_30D,
    SUM(CASE WHEN fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 30 THEN fpppd.NGR * fer.MIDDLE_RATE ELSE 0 END) AS NGR_30D,
    SUM(fpppd.NGP * fer.MIDDLE_RATE) AS NGP_Y1,
    SUM(fpppd.NGR * fer.MIDDLE_RATE) AS NGR_Y1
FROM {{ ref('stg_player_reg_attribution') }} dp
INNER JOIN {{ source('dm_player', 'f_player_product_performance_daily') }} fpppd
    ON  dp.PLAYER_ID = fpppd.PLAYER_ID
    AND fpppd.REPORTING_DATE >= dp.FIRST_TIME_DEPOSIT_DT_LOCAL - 365
    AND fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 364
LEFT JOIN {{ source('dwh', 'f_exchange_rate') }} fer
    ON  fpppd.CURRENCY_ID = fer.FROM_CURRENCY_ID
    AND fer.RATE_DATE = fpppd.REPORTING_DATE
    AND fer.TO_CURRENCY_CODE = 'EUR'
WHERE dp.FIRST_TIME_DEPOSIT_DT_LOCAL IS NOT NULL
GROUP BY ALL

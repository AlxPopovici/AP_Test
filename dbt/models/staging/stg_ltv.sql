-- Latest LTV prediction per player.
-- Non-PL: PROD.DS.LTV_ACQUISITION (latest tenure). PL: manual source, because LTV_ACQUISITION is missing recent PL months.
SELECT
    PLAYER_ID,
    COALESCE(TOTAL_PREDICTION, 0) AS LTV
FROM {{ source('ds', 'ltv_acquisition') }}
WHERE BUSINESS_DOMAIN_ID != 3
QUALIFY ROW_NUMBER() OVER (PARTITION BY PLAYER_ID ORDER BY TENURE DESC, INSERTTIMESTAMP DESC) = 1

UNION ALL

SELECT
    PLAYER_ID,
    LTV
FROM {{ source('bi', 'vw_manual_pl_ltv') }}
WHERE BUSINESS_DOMAIN_ID = 3

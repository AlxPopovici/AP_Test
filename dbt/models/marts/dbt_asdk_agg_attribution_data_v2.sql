-- dbt port of PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA_V2 (Attribution V2, Tableau source).
-- Grain: BUSINESS_DOMAIN_ID x EVENT_DATE x attribution dimensions.
-- REGS / FTD_Dx are on the registration date axis, FTDS / NGR / NGP / LTV on the FTD date axis.
{% set keys = [
    'BUSINESS_DOMAIN_ID',
    'EVENT_DATE',
    'FINAL_ACQUISITION_SOURCE_GROUP',
    'FINAL_ACQUISITION_CHANNEL',
    'FINAL_ACQUISITION_SUBCHANNEL',
    'FINAL_PLATFORM_TYPE',
    'FINAL_AD_PLATFORM',
    'FINAL_ATTRIBUTION_SOURCE',
    'FINAL_MAPPING_USED'
] %}

WITH
    -- Union of dimension keys from both sides so rows with only REGS or only FTDS are kept
    all_keys AS (
        SELECT {{ keys | join(', ') }} FROM {{ ref('int_attribution_registrations') }}
        UNION
        SELECT {{ keys | join(', ') }} FROM {{ ref('int_attribution_ftds') }}
    )

SELECT
    {% for k in keys %}k.{{ k }},
    {% endfor %}
    COALESCE(r.REGS, 0) AS REGS,
    COALESCE(r.FTD_D2, 0) AS FTD_D2,
    COALESCE(r.FTD_D7, 0) AS FTD_D7,
    COALESCE(r.FTD_D14, 0) AS FTD_D14,
    COALESCE(r.FTD_D28, 0) AS FTD_D28,
    COALESCE(f.FTDS, 0) AS FTDS,
    COALESCE(f.NGR_30D, 0) AS NGR_30D,
    COALESCE(f.NGP_30D, 0) AS NGP_30D,
    COALESCE(f.NGR_Y1, 0) AS NGR_Y1,
    COALESCE(f.NGP_Y1, 0) AS NGP_Y1,
    COALESCE(f.LTV, 0) AS LTV,
    COALESCE(f.LTV_SINCE_FTD, 0) AS LTV_SINCE_FTD,
    COALESCE(f.LTV_ACTUALIZED, 0) AS LTV_ACTUALIZED
FROM all_keys k
LEFT JOIN {{ ref('int_attribution_registrations') }} r USING ({{ keys | join(', ') }})
LEFT JOIN {{ ref('int_attribution_ftds') }} f USING ({{ keys | join(', ') }})

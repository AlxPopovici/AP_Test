-- New script in SB_PROD.
-- Date: Feb 12, 2026
-- Time: 2:18:58 PM


SELECT * FROM PROD.DM_MARTECH.F_FACEBOOK_ADS_TOUCHPOINT_EVENT LIMIT 100;

SELECT * FROM PROD.DM_MARTECH.F_GOOGLE_ADS_TOUCHPOINT_EVENT /*WHERE PLAYER_ID = 'ff61eabb-ac20-5e66-bdf8-7ed8962fee76'*/LIMIT 100;

SELECT * FROM PROD.DM_MARTECH.D_UTM LIMIT 100;

SELECT * FROM PROd.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd WHERE drrd.MARKETING_SOURCE_NAME = '174' LIMIT 100

SELECT * FROM PROD.sbx_data_product.asdk_player_acq_classification LIMIT 100

SELECT * FROM PROD.DM_MARTECH.VW_ASDK_PLAYER_REG_ATTRIBUTION LIMIT 100

SELECT * FROM PROD.SBX_BI.VW_TMP_ASDK_PLAYER_ACQ_CLASSIFICATION WHERE UTM_CAMPAIGN ILIKE ANY ('prog-cas-acq-int-pg_equativ%')

select * from prod.dm_martech.vw_f_acq_channel_performance limit 10;

select * from prod.dm_martech.vw_f_campaign_acq_channel_performance limit 10;

SELECT * FROM PROD.DM_MARTECH.VW_BACKEND_PLAYER_REG_ATTRIBUTION vbpra LIMIT 100

SELECT * FROM prod.dm_martech.vw_player_reg_attribution LIMIT 100

SELECT * FROM PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA


--CREATE OR REPLACE VIEW PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA AS 
WITH  
	INITIAL_BASE AS (                                                                                                                                                                                                                                                                                   
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
          MAPPING_USED AS FINAL_MAPPING_USED
      FROM                                                                                                                                                                                                                                                                                            
          PROD.DM_MARTECH.VW_PLAYER_REG_ATTRIBUTION asdk                                                                                                                                                                                                                                         
      LEFT JOIN                                                                                                                                                                                                                                                                                       
          PROD.DWH.D_BUSINESS_MARKET dbm ON asdk.BUSINESS_MARKET_ID = dbm.BUSINESS_MARKET_ID                                                                                                                                                                                                          
      WHERE                                                                                                                                                                                                                                                                                           
          asdk.REGISTRATION_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')                                                                                                                                                                                                            
          OR asdk.FIRST_TIME_DEPOSIT_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')                                                                                                                                                                                                      
  )                                                                                                                                                                                                                                                                                                   
  ,LTV AS (                                                                                                                                                                                                                                                                                           
      SELECT PLAYER_ID,                                                                                                                                                                                                                                                                                  
          COALESCE(TOTAL_PREDICTION, 0) AS LTV                                                                                                                                                                                                                                                        
      FROM PROD.DS.LTV_ACQUISITION                                                                                                                                                                                                                                                                     
      QUALIFY                                                                                                                                                                                                                                                                                         
          ROW_NUMBER() OVER (PARTITION BY PLAYER_ID ORDER BY TENURE DESC, INSERTTIMESTAMP DESC) = 1                                                                                                                                                                                                   
  )                                                                                                                                                                                                                                                                                                   
  ,PERFORMANCE AS (                                                                                                                                                                                                                                                                                   
      SELECT dp.PLAYER_ID,                                                                                                                                                                                                                                                                               
          SUM(CASE WHEN fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 30 THEN fpppd.NGP * fer.MIDDLE_RATE ELSE 0 END) AS NGP_30D,                                                                                                                                                          
          SUM(CASE WHEN fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 30 THEN fpppd.NGR * fer.MIDDLE_RATE ELSE 0 END) AS NGR_30D,                                                                                                                                                          
          SUM(fpppd.NGP * fer.MIDDLE_RATE) AS NGP_Y1,                                                                                                                                                                                                                                                 
          SUM(fpppd.NGR * fer.MIDDLE_RATE) AS NGR_Y1                                                                                                                                                                                                                                                  
      FROM INITIAL_BASE dp                                                                                                                                                                                                                                                                             
      INNER JOIN                                                                                                                                                                                                                                                                                      
          PROD.DM_PLAYER.F_PLAYER_PRODUCT_PERFORMANCE_DAILY fpppd                                                                                                                                                                                                                                     
              ON  dp.PLAYER_ID         = fpppd.PLAYER_ID                                                                                                                                                                                                                                              
              AND fpppd.REPORTING_DATE >= dp.FIRST_TIME_DEPOSIT_DT_LOCAL - 365                                                                                                                                                                                                                        
              AND fpppd.REPORTING_DATE <= dp.FIRST_TIME_DEPOSIT_DT_LOCAL + 364                                                                                                                                                                                                                        
      LEFT JOIN                                                                                                                                                                                                                                                                                       
          PROD.DWH.F_EXCHANGE_RATE fer                                                                                                                                                                                                                                                                
              ON  fpppd.CURRENCY_ID    = fer.FROM_CURRENCY_ID                                                                                                                                                                                                                                         
              AND fer.RATE_DATE        = fpppd.REPORTING_DATE                                                                                                                                                                                                                                         
              AND fer.TO_CURRENCY_CODE = 'EUR'                                                                                                                                                                                                                                                        
      WHERE                                                                                                                                                                                                                                                                                           
          dp.FIRST_TIME_DEPOSIT_DT_LOCAL IS NOT NULL                                                                                                                                                                                                                                                  
      GROUP BY ALL                                                                                                                                                                                                                                                                                    
  ),BASE AS (                                                                                                                                                                                                                                                                                          
      SELECT asdk.BUSINESS_DOMAIN_ID,
          asdk.PLAYER_ID,                                                                                                                                                                                                                                                                             
          asdk.REGISTRATION_DT_LOCAL,                                                                                                                                                                                                                                                                 
          asdk.FIRST_TIME_DEPOSIT_DT_LOCAL,                                                                                                                                                                                                                                                           
          asdk.FINAL_ACQUISITION_SOURCE_GROUP,                                                                                                                                                                                                                                                        
          asdk.FINAL_ACQUISITION_CHANNEL,                                                                                                                                                                                                                                                             
          asdk.FINAL_ACQUISITION_SUBCHANNEL,                                                                                                                                                                                                                                                          
          asdk.FINAL_PLATFORM_TYPE,                                                                                                                                                                                                                                                                   
          asdk.FINAL_AD_PLATFORM,  
          asdk.FINAL_MAPPING_USED,
          -- performance                                                                                                                                                                                                                                                                              
          perf.NGR_30D,                                                                                                                                                                                                                                                                               
          perf.NGP_30D,                                                                                                                                                                                                                                                                               
          perf.NGR_Y1,                                                                                                                                                                                                                                                                                
          perf.NGP_Y1,                                                                                                                                                                                                                                                                                
          -- ltv                                                                                                                                                                                                                                                                                      
          ltv.LTV,                                                                                                                                                                                                                                                                                    
          ltv.LTV * es.CUMULATIVE_PCT AS LTV_SINCE_FTD,                                                                                                                                                                                                                                               
          -- conversion windows                                                                                                                                                                                                                                                                       
          CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 1  THEN 1 ELSE 0 END AS IS_FTD_D2,                                                                                                                                                    
          CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 6  THEN 1 ELSE 0 END AS IS_FTD_D7,                                                                                                                                                    
          CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 13 THEN 1 ELSE 0 END AS IS_FTD_D14,                                                                                                                                                   
          CASE WHEN DATEDIFF('day', asdk.REGISTRATION_DT_LOCAL, asdk.FIRST_TIME_DEPOSIT_DT_LOCAL) BETWEEN 0 AND 27 THEN 1 ELSE 0 END AS IS_FTD_D28                                                                                                                                                    
      FROM INITIAL_BASE asdk                                                                                                                                                                                                                                                                           
      LEFT JOIN LTV ltv USING (PLAYER_ID)
      LEFT JOIN PERFORMANCE perf USING (PLAYER_ID)
      LEFT JOIN PROD.BI.LTV_EXPECTED_SHARE es
              ON  asdk.BUSINESS_DOMAIN_ID = es.BUSINESS_DOMAIN_ID                                                                                                                                                                                                                                     
              AND es.WEEKS_SINCE_FTD      = DATEDIFF('week', DATE_TRUNC('week', asdk.FIRST_TIME_DEPOSIT_DT_LOCAL), DATE_TRUNC('week', CURRENT_DATE()))                                                                                                                                                
              AND asdk.FIRST_TIME_DEPOSIT_DT_LOCAL >= DATEADD('YEAR', -1, DATE_TRUNC('YEAR', CURRENT_DATE()))                                                                                                                                                                                         
  )                                                                                                                                                                                                                                                                                                   
  ,CTE_REGISTRATIONS AS (                                                                                                                                                                                                                                                                             
      SELECT BUSINESS_DOMAIN_ID,                                                                                                                                                                                                                                                                         
          REGISTRATION_DT_LOCAL AS EVENT_DATE,                                                                                                                                                                                                                                                        
          FINAL_ACQUISITION_SOURCE_GROUP,                                                                                                                                                                                                                                                             
          FINAL_ACQUISITION_CHANNEL,                                                                                                                                                                                                                                                                  
          FINAL_ACQUISITION_SUBCHANNEL,                                                                                                                                                                                                                                                               
          FINAL_PLATFORM_TYPE,                                                                                                                                                                                                                                                                        
          FINAL_AD_PLATFORM, 
          FINAL_MAPPING_USED,
          COUNT(DISTINCT PLAYER_ID) AS REGS,                                                                                                                                                                                                                                                          
          SUM(IS_FTD_D2)  AS FTD_D2,                                                                                                                                                                                                                                                        
          SUM(IS_FTD_D7) AS FTD_D7,                                                                                                                                                                                                                                                        
          SUM(IS_FTD_D14) AS FTD_D14,                                                                                                                                                                                                                                                       
          SUM(IS_FTD_D28) AS FTD_D28                                                                                                                                                                                                                                                        
      FROM BASE                                                                                                                                                                                                                                                                                       
      GROUP BY ALL                                                                                                                                                                                                                                                                                    
  ),CTE_FTDS AS (                                                                                                                                                                                                                                                                                      
      SELECT BUSINESS_DOMAIN_ID,
          FIRST_TIME_DEPOSIT_DT_LOCAL AS EVENT_DATE,                                                                                                                                                                                                                                                  
          FINAL_ACQUISITION_SOURCE_GROUP,                                                                                                                                                                                                                                                             
          FINAL_ACQUISITION_CHANNEL,                                                                                                                                                                                                                                                                  
          FINAL_ACQUISITION_SUBCHANNEL,                                                                                                                                                                                                                                                               
          FINAL_PLATFORM_TYPE,                                                                                                                                                                                                                                                                        
          FINAL_AD_PLATFORM, 
          FINAL_MAPPING_USED,
          COUNT(DISTINCT PLAYER_ID) AS FTDS,                                                                                                                                                                                                                                                          
          SUM(NGR_30D) AS NGR_30D,                                                                                                                                                                                                                                                       
          SUM(NGP_30D) AS NGP_30D,                                                                                                                                                                                                                                                       
          SUM(NGR_Y1) AS NGR_Y1,                                                                                                                                                                                                                                                        
          SUM(NGP_Y1) AS NGP_Y1,                                                                                                                                                                                                                                                        
          SUM(LTV) AS LTV,                                                                                                                                                                                                                                                           
          SUM(LTV_SINCE_FTD) AS LTV_SINCE_FTD                                                                                                                                                                                                                                                  
      FROM BASE                                                                                                                                                                                                                                                                                       
      WHERE FIRST_TIME_DEPOSIT_DT_LOCAL IS NOT NULL                                                                                                                                                                                                                                              
      GROUP BY ALL                                                                                                                                                                                                                                                                                    
  ),CTE_ALL_KEYS AS (                                                                                                                                                                                                                                                                                  
      SELECT BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED FROM CTE_REGISTRATIONS                                                                                                   
      UNION                                                                                                                                                                                                                                                                                           
      SELECT BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED FROM CTE_FTDS                                                                                                            
  )                                                                                                                                                                                                                                                                                                   
  SELECT                                                                                                                                                                                                                                                                                              
      k.BUSINESS_DOMAIN_ID,                                                                                                                                                                                                                                                                           
      k.EVENT_DATE,                                                                                                                                                                                                                                                                                   
      k.FINAL_ACQUISITION_SOURCE_GROUP,                                                                                                                                                                                                                                                               
      k.FINAL_ACQUISITION_CHANNEL,                                                                                                                                                                                                                                                                    
      k.FINAL_ACQUISITION_SUBCHANNEL,                                                                                                                                                                                                                                                                 
      k.FINAL_PLATFORM_TYPE,                                                                                                                                                                                                                                                                          
      k.FINAL_AD_PLATFORM, 
      k.FINAL_MAPPING_USED,
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
      COALESCE(f.LTV_SINCE_FTD,0) AS LTV_SINCE_FTD                                                                                                                                                                                                                                                    
  FROM  CTE_ALL_KEYS k                                                                                                                                                                                                                                                                                  
  LEFT JOIN                                                                                                                                                                                                                                                                                           
      CTE_REGISTRATIONS r USING (BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED)                                                                                                     
  LEFT JOIN                                                                                                                                                                                                                                                                                           
      CTE_FTDS f USING (BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED)
	    
-- ACQ COST AGG
SELECT
	ch_perf.BUSINESS_DOMAIN_ID,
	ch_perf.REPORTING_DATE,
	ch_perf.ACQUISITION_SOURCE_GROUP,
	ch_perf.ACQUISITION_CHANNEL,
	ch_perf.ACQUISITION_SUBCHANNEL,
	ch_perf.PLATFORM_TYPE,
	COALESCE(ch_perf.AD_PLATFORM, 'UNK') AS AD_PLATFORM,
	SUM(ch_perf.IMPRESSIONS) AS IMPRESSIONS,
	SUM(ch_perf.CLICKS) AS CLICKS,
	SUM(ch_perf.COST_EUR) AS COST_EUR
FROM 
	prod.dm_martech.vw_f_acq_channel_performance ch_perf
GROUP BY 
	ALL

---REGs
WITH
	BASIC_COMPARISON AS (
SELECT 
	'ASDK' AS DATA_SOURCE,
	dp.BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', asdk.REGISTRATION_DT) AS MONTH,
	COUNT(asdk.PLAYER_ID) AS PLAYERS
FROM 
	PROD.DM_MARTECH.VW_PLAYER_REG_ATTRIBUTION asdk--PROD.SBX_DATA_PRODUCT.VW_ASDK_PLAYER_REG_ATTRIBUTION
JOIN
	PROD.DWH.D_PLAYER dp USING(PLAYER_ID)
WHERE
	dp.REGISTRATION_DT::DATE >= '2026-01-01'
	AND dp.IS_TEST_ACCOUNT !=1
GROUP BY ALL
UNION ALL
SELECT 
	'NEW_SOURCE' AS DATA_SOURCE,
	asdk.BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', asdk.EVENT_DATE) AS MONTH,
	SUM(asdk.REGS) AS PLAYERS
FROM 
	PROD.SBX_BI.TMP_VW_ASDK_AGG_ATTRIBUTION_DATA asdk
WHERE
	asdk.EVENT_DATE::DATE >= '2026-01-01'
GROUP BY ALL
UNION ALL
SELECT
	'DWH' AS DATA_SOURCE,
	BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS MONTH,
	COUNT(PLAYER_ID) AS PLAYERS
FROM 
	PROD.DWH.D_PLAYER
WHERE
	REGISTRATION_DT::DATE >= '2026-01-01'
	AND BUSINESS_LINE_ID = 1
	AND IS_VALID = 1
	AND IS_TEST_ACCOUNT != 1
GROUP BY ALL
UNION ALL
SELECT
	'CURR_MODEL' AS DATA_SOURCE,
	BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS MONTH,
	COUNT(PLAYER_ID) AS PLAYERS
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd
WHERE
	REGISTRATION_DT::DATE >= '2026-01-01'
	AND IS_TEST_ACCOUNT != 1
GROUP BY ALL
	)
SELECT 
	BUSINESS_DOMAIN_ID, 
	MONTH,
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END) AS ASDK_PLAYERS, 
	SUM(CASE WHEN DATA_SOURCE = 'NEW_SOURCE' THEN PLAYERS END) AS NEW_SOURCE_PLAYERS,
	SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END) AS DWH_PLAYERS,
	SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) AS CURR_PLAYERS,
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END) * 100 AS "ASDK_V_DWH_REGS_%",
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) * 100 AS "ASDK_V_CURR_MODEL_REGS_%",
	SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) * 100 AS "DWH_V_CURR_MODEL_REGS_%",
	SUM(CASE WHEN DATA_SOURCE = 'NEW_SOURCE' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) * 100 AS "NEWSOURCE_V_CURR_MODEL_REGS_%"
FROM 
	BASIC_COMPARISON
GROUP BY ALL

---FTDs
WITH
	BASIC_COMPARISON AS (
SELECT 
	'ASDK' AS DATA_SOURCE,
	dp.BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', asdk.FIRST_TIME_DEPOSIT_DT) AS MONTH,
	COUNT(asdk.PLAYER_ID) AS PLAYERS
FROM 
	 PROD.DM_MARTECH.VW_PLAYER_REG_ATTRIBUTION asdk--PROD.DM_MARTECH.VW_ASDK_PLAYER_REG_ATTRIBUTION
JOIN
	PROD.DWH.D_PLAYER dp USING(PLAYER_ID)
WHERE
	(dp.REGISTRATION_DT::DATE >= '2026-01-01'
	OR dp.FIRST_TIME_DEPOSIT_DT::DATE >= '2026-01-01')
	AND dp.IS_TEST_ACCOUNT !=1
GROUP BY ALL
UNION ALL
SELECT
	'DWH' AS DATA_SOURCE,
	BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS MONTH,
	COUNT(PLAYER_ID) AS PLAYERS
FROM 
	PROD.DWH.D_PLAYER
WHERE
	(REGISTRATION_DT::DATE >= '2026-01-01'
	OR FIRST_TIME_DEPOSIT_DT::DATE >= '2026-01-01')
	AND BUSINESS_LINE_ID = 1
	AND IS_VALID = 1
	AND IS_TEST_ACCOUNT != 1
GROUP BY ALL
UNION ALL
SELECT
	'CURR_MODEL' AS DATA_SOURCE,
	BUSINESS_DOMAIN_ID,
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS MONTH,
	COUNT(PLAYER_ID) AS PLAYERS
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd
WHERE
	(REGISTRATION_DT::DATE >= '2026-01-01'
	OR FIRST_TIME_DEPOSIT_DT::DATE >= '2026-01-01')
	AND IS_TEST_ACCOUNT != 1
GROUP BY ALL
	)
SELECT 
	BUSINESS_DOMAIN_ID, 
	MONTH,
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END) AS ASDK_PLAYERS, 
	SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END) AS DWH_PLAYERS,
	SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) AS CURR_PLAYERS,
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END) * 100 AS "ASDK_V_DWH_REGS_%",
	SUM(CASE WHEN DATA_SOURCE = 'ASDK' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) * 100 AS "ASDK_V_CURR_MODEL_REGS_%",
	SUM(CASE WHEN DATA_SOURCE = 'DWH' THEN PLAYERS END)/SUM(CASE WHEN DATA_SOURCE = 'CURR_MODEL' THEN PLAYERS END) * 100 AS "DWH_V_CURR_MODEL_REGS_%"
FROM 
	BASIC_COMPARISON
GROUP BY ALL





WITH base_parsed AS (
    SELECT
    	PLAYER_ID,
    	EVENT_DT,
    	CHANNEL_CODE AS EVENT_DEVICE,
    	LAST_TOUCH,
    	LAST_NON_DIRECT_TOUCH,
        PARSE_JSON(LAST_TOUCH) as USE_LAST_TOUCH,
        COALESCE(USE_LAST_TOUCH:deep_link_content::string, 
                 USE_LAST_TOUCH:event_page_url::string, 
                 USE_LAST_TOUCH:referrer_uri::string) as url_str,
        ACQUISITION_SUBCHANNEL,
        ACQUISITION_CHANNEL,
        ACQUISITION_SOURCE_GROUP
    FROM 
    	PROD.DM_MARTECH.VW_ASDK_PLAYER_LAST_NON_DIRECT_ACQUISITION LIMIT 100
),
extracted AS (
    SELECT
    	LAST_TOUCH,
    	LAST_NON_DIRECT_TOUCH,
        -- 1. Campaign ID
        COALESCE(
            USE_LAST_TOUCH:campaign_id::string,
            REGEXP_SUBSTR(url_str, 'campaign_id=([^&]*)', 1, 1, 'e'),
            REGEXP_SUBSTR(url_str, 'gad_campaignid=([^&]*)', 1, 1, 'e')
        ) AS campaign_id,
        -- 2. Ad ID
        COALESCE(
            USE_LAST_TOUCH:ad_id::string,
            REGEXP_SUBSTR(url_str, 'ad_id=([^&]*)', 1, 1, 'e')
        ) AS ad_id,
        -- 3. Ad Group ID
        COALESCE(
            USE_LAST_TOUCH:ad_group_id::string,
            REGEXP_SUBSTR(url_str, 'adgroup_id=([^&]*)', 1, 1, 'e'),
            REGEXP_SUBSTR(url_str, 'ad_group_id=([^&]*)', 1, 1, 'e')
        ) AS ad_group_id,
        -- 4. Ad Set ID (Added utm_id as fallback for Facebook Advantage+)
        COALESCE(
            USE_LAST_TOUCH:ad_set_id::string,
            REGEXP_SUBSTR(url_str, 'adset_id=([^&]*)', 1, 1, 'e'),
            REGEXP_SUBSTR(url_str, 'ad_set_id=([^&]*)', 1, 1, 'e'),
            REGEXP_SUBSTR(url_str, 'utm_id=([^&]*)', 1, 1, 'e')
        ) AS ad_set_id,
        -- 5. UTM Source & Medium
        TRIM(COALESCE(USE_LAST_TOUCH:utm_source::string, REGEXP_SUBSTR(url_str, 'utm_source=([^&]*)', 1, 1, 'e'))) AS utm_source,
        TRIM(COALESCE(USE_LAST_TOUCH:utm_medium::string, REGEXP_SUBSTR(url_str, 'utm_medium=([^&]*)', 1, 1, 'e'))) AS utm_medium,
        -- 6. DYNAMIC UTM CAMPAIGN (Prioritizes BTAG for Affiliates)
        TRIM(COALESCE(
            USE_LAST_TOUCH:btag::string,                              -- Check JSON for btag
            REGEXP_SUBSTR(url_str, 'btag=([^&]*)', 1, 1, 'e'),        -- Check URL for btag
            USE_LAST_TOUCH:utm_campaign::string,                      -- Standard UTM JSON
            REGEXP_SUBSTR(url_str, 'utm_campaign=([^&]*)', 1, 1, 'e') -- Standard UTM URL
        )) AS utm_campaign,
        ------------------
        ACQUISITION_SUBCHANNEL,
        ACQUISITION_CHANNEL,
        ACQUISITION_SOURCE_GROUP,
        TRIM(COALESCE(USE_LAST_TOUCH:event_page_url::string, REGEXP_SUBSTR(url_str, 'event_page_url=([^&]*)', 1, 1, 'e'), REGEXP_SUBSTR(url_str, 'referrer_uri=([^&]*)', 1, 1, 'e'))) AS event_page_url
    FROM base_parsed
)
SELECT * FROM extracted;

---USING PLATFORM DATA
WITH
	CTE_UNIFIED_DATA_SOURCES AS (
		SELECT
			ffate.BUSINESS_DOMAIN_ID,
			dbd.BUSINESS_DOMAIN_NAME,
			ffate.PLAYER_ID,
			dp.PLAYER_CODE,
			dp.PLAYER_UNIFIED_CODE,
			dp.IS_TEST_ACCOUNT,
			dp.REGISTRATION_CHANNEL_CODE AS CHANNEL_CODE,
			CASE WHEN ffate.EVENT_NAME = 'registration_result_successful' THEN 'Registration_Step3' END AS EVENT_NAME, 
			ffate.EVENT_DT,
			dp.REGISTRATION_DT,
			dp.FIRST_TIME_DEPOSIT_DT,
			dfac.CAMPAIGN_CODE,
			COALESCE(NULLIF(dfac.CAMPAIGN_NAME, 'UNK'), CASE WHEN du.UTM_CAMPAIGN ILIKE ANY ('%||%', '%|%') THEN du.UTM_CAMPAIGN ELSE dfac.CAMPAIGN_NAME END) AS CAMPAIGN_NAME,
			du.UTM_CAMPAIGN AS CAMPAIGN_UTM,
			ffate.URLS AS UTM_CAMPAIGN_PARSED,
			dfaas.AD_SET_NAME,
			dfaa.AD_NAME,
			NULL AS COUPON_CODE,
			NULL AS COUPON_NAME,
			du.UTM_SOURCE AS MARKETING_SOURCE,
			du.UTM_SOURCE AS MARKETING_SOURCE_NAME,
			IFF(du.UTM_SOURCE ILIKE ANY ('%facebook%', '%fb%', '%meta%'), 'facebook', du.UTM_SOURCE) AS MARKETING_SOURCE_MAPPED,
			du.UTM_MEDIUM AS MARKETING_CHANNEL,
			du.UTM_MEDIUM AS MARKETING_CHANNEL_NAME,
			'social' AS MARKETING_CHANNEL_MAPPED,
			du.ACQUISITION_CHANNEL, 
			du.ACQUISITION_CHANNEL_GROUP, 
			du.ACQUISITION_SOURCE_GROUP,
			'Facebook Touchpoints' AS DATA_SOURCE,
			dfac.CAMPAIGN_GOAL,
			NULL AS CAMPAIGN_TYPE,
			dfac.CAMPAIGN_VERTICAL,
--			du.UTM_TERM,
		FROM 
			PROD.DM_MARTECH.F_FACEBOOK_ADS_TOUCHPOINT_EVENT ffate
		JOIN
			PROD.DWH.D_BUSINESS_DOMAIN dbd USING (BUSINESS_DOMAIN_ID)
		JOIN
			PROD.DWH.D_PLAYER dp USING (PLAYER_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_FACEBOOK_ADS_CAMPAIGN dfac USING (FACEBOOK_ADS_CAMPAIGN_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_FACEBOOK_ADS_AD_SET dfaas USING (FACEBOOK_ADS_AD_SET_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_FACEBOOK_ADS_AD dfaa USING (FACEBOOK_ADS_AD_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_UTM du USING (UTM_ID)
		WHERE
			ffate.EVENT_NAME = 'registration_result_successful'
			AND ffate.PLAYER_ID != 'e129f27c-5103-5c5c-844b-cdf0a15e160d'		
		UNION ALL
		SELECT
			fgate.BUSINESS_DOMAIN_ID,
			dbd.BUSINESS_DOMAIN_NAME,
			fgate.PLAYER_ID,
			fgate.PLAYER_EXTERNAL_CODE AS PLAYER_CODE,
			dp.PLAYER_UNIFIED_CODE,
			dp.IS_TEST_ACCOUNT,
			dp.REGISTRATION_CHANNEL_CODE AS CHANNEL_CODE,
			CASE WHEN fgate.EVENT_NAME = 'registration_result_successful' THEN 'Registration_Step3' END AS EVENT_NAME,
			fgate.EVENT_DT,
			dp.REGISTRATION_DT,
			dp.FIRST_TIME_DEPOSIT_DT,
			dgac.CAMPAIGN_CODE,
			COALESCE(NULLIF(dgac.CAMPAIGN_NAME, 'UNK'), CASE WHEN du.UTM_CAMPAIGN ILIKE ANY ('%||%', '%|%') THEN du.UTM_CAMPAIGN ELSE dgac.CAMPAIGN_NAME END) AS CAMPAIGN_NAME,
			du.UTM_CAMPAIGN AS CAMPAIGN_UTM,
			fgate.URLS AS UTM_CAMPAIGN_PARSED,
			dgaag.AD_GROUP_NAME,
			dgak.KEYWORD_TEXT,
			NULL AS COUPON_CODE,
			NULL AS COUPON_NAME,
			du.UTM_SOURCE AS MARKETING_SOURCE,
			du.UTM_SOURCE AS MARKETING_SOURCE_NAME,
			IFF(du.UTM_SOURCE ILIKE ANY ('%facebook%', '%fb%', '%meta%'), 'facebook', du.UTM_SOURCE) AS MARKETING_SOURCE_MAPPED,
			du.UTM_MEDIUM AS MARKETING_CHANNEL,
			du.UTM_MEDIUM AS MARKETING_CHANNEL_NAME,
			'google' AS MARKETING_CHANNEL_MAPPED,
			du.ACQUISITION_CHANNEL, 
			du.ACQUISITION_CHANNEL_GROUP, 
			du.ACQUISITION_SOURCE_GROUP,
			'Google Touchpoints' AS DATA_SOURCE,
			dgac.CAMPAIGN_GOAL,
			NULL AS CAMPAIGN_TYPE,
			dgac.CAMPAIGN_VERTICAL,
--			du.UTM_TERM,
		FROM 
			PROD.DM_MARTECH.F_GOOGLE_ADS_TOUCHPOINT_EVENT fgate
		JOIN
			PROD.DWH.D_BUSINESS_DOMAIN dbd USING (BUSINESS_DOMAIN_ID)
		JOIN
			PROD.DWH.D_PLAYER dp USING (PLAYER_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_GOOGLE_ADS_CAMPAIGN dgac USING (GOOGLE_ADS_CAMPAIGN_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_GOOGLE_ADS_AD_GROUP dgaag USING (GOOGLE_ADS_AD_GROUP_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_GOOGLE_ADS_KEYWORD dgak USING (GOOGLE_ADS_KEYWORD_ID)
		LEFT JOIN
			PROD.DM_MARTECH.D_UTM du USING (UTM_ID)
		WHERE
			fgate.EVENT_NAME = 'registration_result_successful'
			AND fgate.PLAYER_ID != 'e129f27c-5103-5c5c-844b-cdf0a15e160d'

--CREATE OR REPLACE VIEW PROD.SBX_BI.VW_TMP_ASDK_PLAYER_ACQ_CLASSIFICATION AS -- v2
WITH 
	CTE_BASE AS (
	    SELECT
	    	BUSINESS_DOMAIN_ID,
	        PLAYER_ID,
	    	EVENT_DT,
	    	CHANNEL_CODE AS EVENT_DEVICE,
	    	LAST_TOUCH,
	    	LAST_NON_DIRECT_TOUCH,
	        PARSE_JSON(LAST_TOUCH) as LT_JSON,
	        PARSE_JSON(LAST_NON_DIRECT_TOUCH) as LNDT_JSON,
	        ACQUISITION_SUBCHANNEL,
	        ACQUISITION_CHANNEL,
	        ACQUISITION_SOURCE_GROUP
	    FROM 
	    	PROD.DM_MARTECH.VW_ASDK_PLAYER_LAST_NON_DIRECT_ACQUISITION
--	    LIMIT 100
	)
	,CTE_DATA_EXTRACTED AS (
		SELECT
			BUSINESS_DOMAIN_ID,
			PLAYER_ID,
			EVENT_DT,
			EVENT_DEVICE,
			LAST_TOUCH,
			LAST_NON_DIRECT_TOUCH, 
		    -- 1. Campaign ID (Check JSON key first, then Regex the url_str)
		    COALESCE(
		        LNDT_JSON:campaign_id::string,
		        REGEXP_SUBSTR(LT_JSON, 'campaign_id=([^&]*)', 1, 1, 'e'),
		        REGEXP_SUBSTR(LT_JSON, 'gad_campaignid=([^&]*)', 1, 1, 'e')
		    ) AS CAMPAIGN_CODE,
		    -- 2. Ad ID
--		    COALESCE(
--		        LNDT_JSON:ad_id::string,
--		        REGEXP_SUBSTR(LT_JSON, 'ad_id=([^&]*)', 1, 1, 'e')
--		    ) AS AD_ID,
		    -- 3. Ad Group ID
--		    COALESCE(
--		        LNDT_JSON:ad_group_id::string,
--		        REGEXP_SUBSTR(LT_JSON, 'adgroup_id=([^&]*)', 1, 1, 'e')
--		    ) AS AD_GROUP_ID,
		    -- 4. UTM Source (Prioritize standard UTMs, then specific IDs)
		    TRIM(COALESCE(
		        LNDT_JSON:utm_source::string, 
		        REGEXP_SUBSTR(LT_JSON, 'utm_source=([^&]*)', 1, 1, 'e'),
		        REGEXP_SUBSTR(LT_JSON, 'affid=([^&]*)', 1, 1, 'e') -- Fallback for affiliates
		    )) AS UTM_SOURCE,
		    -- 5. UTM Medium
		    TRIM(COALESCE(
		        LNDT_JSON:utm_medium::string, 
		        REGEXP_SUBSTR(LT_JSON, 'utm_medium=([^&]*)', 1, 1, 'e')
		    )) AS UTM_MEDIUM,
		    -- 6. UTM Campaign (BTAG > Campaign Name > Campaign ID)
		    TRIM(COALESCE(
		        LNDT_JSON:btag::string,                              
		        REGEXP_SUBSTR(LT_JSON, 'btag=([^&]*)', 1, 1, 'e'),        
		        LNDT_JSON:utm_campaign::string,                      
		        REGEXP_SUBSTR(LT_JSON, 'utm_campaign=([^&]*)', 1, 1, 'e')
		    )) AS UTM_CAMPAIGN,
		    INITCAP(ACQUISITION_SUBCHANNEL) AS ACQUISITION_SUBCHANNEL,
		    INITCAP(ACQUISITION_CHANNEL) AS ACQUISITION_CHANNEL,
		    INITCAP(ACQUISITION_SOURCE_GROUP) AS ACQUISITION_SOURCE_GROUP,
		    IFF(LNDT_JSON = LT_JSON, 'LAST_NON_DIRECT', 'LAST_TOUCH') as DATA_SOURCE_USED
		FROM 
			CTE_BASE
	)
	,CTE_AVAILABLE_CAMPAIGNS AS (	
		SELECT dgac.CAMPAIGN_CODE, dgac.CAMPAIGN_NAME, dgac.CAMPAIGN_GOAL, dgac.CAMPAIGN_TYPE, dgac.CAMPAIGN_VERTICAL, 'Google' AS DATA_SOURCE FROM PROD.DM_MARTECH.D_GOOGLE_ADS_CAMPAIGN dgac 
		UNION ALL
		SELECT dfac.CAMPAIGN_CODE, dfac.CAMPAIGN_NAME, dfac.CAMPAIGN_GOAL, NULL AS CAMPAIGN_TYPE, dfac.CAMPAIGN_VERTICAL, 'Meta' FROM PROD.DM_MARTECH.D_FACEBOOK_ADS_CAMPAIGN dfac
		UNION ALL
		SELECT dbac.CAMPAIGN_CODE, dbac.CAMPAIGN_NAME, dbac.CAMPAIGN_GOAL, NULL AS CAMPAIGN_TYPE, dbac.CAMPAIGN_VERTICAL, 'Bing' FROM PROD.DM_MARTECH.D_BING_ADS_CAMPAIGN dbac
	)
	,CTE_AFFILIATE AS (	
		SELECT DISTINCT
			CASE WHEN dam.BUSINESS_DOMAIN_ID = 1 THEN 14 ELSE dam.BUSINESS_DOMAIN_ID END AS BUSINESS_DOMAIN_ID,
			da.AFFILIATE_CODE,
			da.AFFILIATE_USERNAME
		FROM 
			PROD.DM_MARTECH.D_AFFILIATE da
		LEFT JOIN 
			PROD.DM_MARTECH.D_AFFILIATE_MERCHANT dam USING(AFFILIATE_MERCHANT_NAME_API)
		WHERE
			da.IS_VALID = 1
			AND da.AFFILIATE_USERNAME IS NOT NULL	
	)
SELECT 
	asdk.BUSINESS_DOMAIN_ID,
	asdk.PLAYER_ID, 
	asdk.EVENT_DT, 
	asdk.EVENT_DEVICE, 
	asdk.CAMPAIGN_CODE,
	dc.CAMPAIGN_NAME,
--	asdk.AD_ID, 
--	asdk.AD_GROUP_ID, 
	asdk.UTM_SOURCE, 
	asdk.UTM_MEDIUM, 
	asdk.UTM_CAMPAIGN, 
	asdk.ACQUISITION_CHANNEL, 
	COALESCE(da.AFFILIATE_USERNAME, NULLIF( asdk.ACQUISITION_SUBCHANNEL, 'Unk'), asdk.ACQUISITION_CHANNEL) AS ACQUISITION_SUBCHANNEL,
--	COALESCE(NULLIF(asdk.ACQUISITION_SUBCHANNEL, 'Unk'), asdk.ACQUISITION_CHANNEL) AS ACQUISITION_SUBCHANNEL_2,
	asdk.ACQUISITION_SOURCE_GROUP, 
	asdk.DATA_SOURCE_USED,
	dc.CAMPAIGN_GOAL,
	dc.CAMPAIGN_TYPE,
	dc.CAMPAIGN_VERTICAL,
	dc.DATA_SOURCE
FROM 
	CTE_DATA_EXTRACTED asdk
LEFT JOIN
	CTE_AVAILABLE_CAMPAIGNS dc USING (CAMPAIGN_CODE)
LEFT JOIN
	CTE_AFFILIATE da
		ON asdk.BUSINESS_DOMAIN_ID = da.BUSINESS_DOMAIN_ID
			AND TRY_CAST(asdk.ACQUISITION_SUBCHANNEL AS NUMBER) = da.AFFILIATE_CODE

--CREATE OR REPLACE VIEW PROD.SBX_BI.VW_TMP_ASDK_PLAYER_ACQ_CLASSIFICATION AS -- OBSOLETE
WITH 
	CTE_BASE AS (
	    SELECT
	        PLAYER_ID,
	    	EVENT_DT,
	    	CHANNEL_CODE AS EVENT_DEVICE,
	    	LAST_TOUCH,
	    	LAST_NON_DIRECT_TOUCH,
	        PARSE_JSON(LAST_TOUCH) as LT_JSON,
	        PARSE_JSON(LAST_NON_DIRECT_TOUCH) as LNDT_JSON,
	        ACQUISITION_SUBCHANNEL,
	        ACQUISITION_CHANNEL,
	        ACQUISITION_SOURCE_GROUP
	    FROM 
	    	PROD.DM_MARTECH.VW_ASDK_PLAYER_LAST_NON_DIRECT_ACQUISITION
--	    LIMIT 100
	)
	,CTE_LNDT_FIRST AS (
	    SELECT
	        *,
	        -- LOGIC: Identify if LAST_TOUCH is "Direct" (No signals)
	        CASE 
	            WHEN (
	                LT_JSON:utm_source IS NULL AND 
	                LT_JSON:btag IS NULL AND 
	                LT_JSON:ad_id IS NULL AND 
	                LT_JSON:campaign_id IS NULL AND
	                NOT (LT_JSON:event_page_url::string LIKE '%?%') AND
	                NOT (LT_JSON:referrer_uri::string LIKE '%utm_%') AND
	                NOT (LT_JSON:referrer_uri::string LIKE '%btag%')
	            )
	            THEN LNDT_JSON -- Pivot to Non-Direct
	            ELSE LT_JSON   -- Stick with Last Touch
	        END AS TARGET_JSON
	    FROM 
	    	CTE_BASE
	)
	,CTE_FINAL_STEP AS (
	    SELECT
	        *,
	        -- Crucial: Get the URL string from the TARGET_JSON (the winner)
	        COALESCE(TARGET_JSON:deep_link_content::string, 
	                 TARGET_JSON:event_page_url::string, 
	                 TARGET_JSON:referrer_uri::string) as url_str
	    FROM 
	    	CTE_LNDT_FIRST
	)
	,CTE_DATA_EXTRACTED AS (
		SELECT
			PLAYER_ID,
			EVENT_DT,
			EVENT_DEVICE,
			LAST_TOUCH,
			LAST_NON_DIRECT_TOUCH, 
		    -- 1. Campaign ID (Check JSON key first, then Regex the url_str)
		    COALESCE(
		        TARGET_JSON:campaign_id::string,
		        REGEXP_SUBSTR(url_str, 'campaign_id=([^&]*)', 1, 1, 'e'),
		        REGEXP_SUBSTR(url_str, 'gad_campaignid=([^&]*)', 1, 1, 'e')
		    ) AS CAMPAIGN_CODE,
		    -- 2. Ad ID
--		    COALESCE(
--		        TARGET_JSON:ad_id::string,
--		        REGEXP_SUBSTR(url_str, 'ad_id=([^&]*)', 1, 1, 'e')
--		    ) AS AD_ID,
		    -- 3. Ad Group ID
--		    COALESCE(
--		        TARGET_JSON:ad_group_id::string,
--		        REGEXP_SUBSTR(url_str, 'adgroup_id=([^&]*)', 1, 1, 'e')
--		    ) AS AD_GROUP_ID,
		    -- 4. UTM Source (Prioritize standard UTMs, then specific IDs)
		    TRIM(COALESCE(
		        TARGET_JSON:utm_source::string, 
		        REGEXP_SUBSTR(url_str, 'utm_source=([^&]*)', 1, 1, 'e'),
		        REGEXP_SUBSTR(url_str, 'affid=([^&]*)', 1, 1, 'e') -- Fallback for affiliates
		    )) AS UTM_SOURCE,
		    -- 5. UTM Medium
		    TRIM(COALESCE(
		        TARGET_JSON:utm_medium::string, 
		        REGEXP_SUBSTR(url_str, 'utm_medium=([^&]*)', 1, 1, 'e')
		    )) AS UTM_MEDIUM,
		    -- 6. UTM Campaign (BTAG > Campaign Name > Campaign ID)
		    TRIM(COALESCE(
		        TARGET_JSON:btag::string,                              
		        REGEXP_SUBSTR(url_str, 'btag=([^&]*)', 1, 1, 'e'),        
		        TARGET_JSON:utm_campaign::string,                      
		        REGEXP_SUBSTR(url_str, 'utm_campaign=([^&]*)', 1, 1, 'e')
		    )) AS UTM_CAMPAIGN,
		    INITCAP(ACQUISITION_SUBCHANNEL) AS ACQUISITION_SUBCHANNEL,
		    INITCAP(ACQUISITION_CHANNEL) AS ACQUISITION_CHANNEL,
		    INITCAP(ACQUISITION_SOURCE_GROUP) AS ACQUISITION_SOURCE_GROUP,
		    IFF(TARGET_JSON = LT_JSON, 'LAST_TOUCH', 'LAST_NON_DIRECT') as DATA_SOURCE_USED
		FROM 
			CTE_FINAL_STEP
	)
	,CTE_AVAILABLE_CAMPAIGNS AS (	
		SELECT dgac.CAMPAIGN_CODE, dgac.CAMPAIGN_NAME, dgac.CAMPAIGN_GOAL, dgac.CAMPAIGN_TYPE, dgac.CAMPAIGN_VERTICAL, 'Google' AS DATA_SOURCE FROM PROD.DM_MARTECH.D_GOOGLE_ADS_CAMPAIGN dgac 
		UNION ALL
		SELECT dfac.CAMPAIGN_CODE, dfac.CAMPAIGN_NAME, dfac.CAMPAIGN_GOAL, NULL AS CAMPAIGN_TYPE, dfac.CAMPAIGN_VERTICAL, 'Meta' FROM PROD.DM_MARTECH.D_FACEBOOK_ADS_CAMPAIGN dfac
		UNION ALL
		SELECT dbac.CAMPAIGN_CODE, dbac.CAMPAIGN_NAME, dbac.CAMPAIGN_GOAL, NULL AS CAMPAIGN_TYPE, dbac.CAMPAIGN_VERTICAL, 'Bing' FROM PROD.DM_MARTECH.D_BING_ADS_CAMPAIGN dbac
	)	
SELECT 
	asdk.PLAYER_ID, 
	asdk.EVENT_DT, 
	asdk.EVENT_DEVICE, 
	asdk.CAMPAIGN_CODE,
	dc.CAMPAIGN_NAME,
--	asdk.AD_ID, 
--	asdk.AD_GROUP_ID, 
	asdk.UTM_SOURCE, 
	asdk.UTM_MEDIUM, 
	asdk.UTM_CAMPAIGN, 
	COALESCE(NULLIF(asdk.ACQUISITION_SUBCHANNEL, 'Unk'), asdk.ACQUISITION_CHANNEL) AS ACQUISITION_SUBCHANNEL,
	asdk.ACQUISITION_CHANNEL, 
	asdk.ACQUISITION_SOURCE_GROUP, 
	asdk.DATA_SOURCE_USED,
	dc.CAMPAIGN_GOAL,
	dc.CAMPAIGN_TYPE,
	dc.CAMPAIGN_VERTICAL,
	dc.DATA_SOURCE
FROM 
	CTE_DATA_EXTRACTED asdk
LEFT JOIN
	CTE_AVAILABLE_CAMPAIGNS dc USING (CAMPAIGN_CODE)

---------------------
			
--CREATE OR REPLACE VIEW PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED AS 
WITH 
	NEW_SOURCE_JOINED AS (
	    SELECT -- Add details from  D_PLAYER for the new model
	        dp.BUSINESS_DOMAIN_ID,
	        ns.PLAYER_ID,
	        dp.PLAYER_CODE,
	        dp.PLAYER_UNIFIED_CODE,
	        dp.IS_TEST_ACCOUNT,
	        ns.EVENT_DEVICE,
	        dp.REGISTRATION_CHANNEL_CODE AS CHANNEL_CODE,
	        'Registration_Step3' AS EVENT_NAME,
	        ns.EVENT_DT,
	        dp.REGISTRATION_DT,
	        dp.FIRST_TIME_DEPOSIT_DT,
	        ns.CAMPAIGN_CODE,
	        COALESCE(NULLIF(ns.CAMPAIGN_NAME, 'UNK'), IFF(ns.UTM_CAMPAIGN ILIKE ANY ('%||%', '%|%'), ns.UTM_CAMPAIGN, ns.CAMPAIGN_NAME)) AS CAMPAIGN_NAME, --ADD CAMPAIGN_NAME where UTM has campaign name and CAMPAIGN_NAME is null
	        ns.UTM_CAMPAIGN AS CAMPAIGN_UTM,
	        'UNK' AS COUPON_CODE,
	        COALESCE(drrd.COUPON_NAME,'UNK') AS COUPON_NAME,
	        ns.UTM_SOURCE AS MARKETING_SOURCE,
	        ns.UTM_SOURCE AS MARKETING_SOURCE_NAME,
	        ns.UTM_SOURCE AS MARKETING_SOURCE_MAPPED,
	        ns.UTM_MEDIUM AS MARKETING_CHANNEL,
	        ns.UTM_MEDIUM AS MARKETING_CHANNEL_NAME,
	        ns.UTM_MEDIUM AS MARKETING_CHANNEL_MAPPED,
	        ns.ACQUISITION_CHANNEL, 
	        ns.ACQUISITION_SUBCHANNEL,
	        ns.ACQUISITION_SOURCE_GROUP,
	        drrd.ACQUISITION_CHANNEL AS LEGACY_ACQ,
	        ns.DATA_SOURCE_USED,
	        ns.CAMPAIGN_GOAL,
	        ns.CAMPAIGN_TYPE,
	        ns.CAMPAIGN_VERTICAL,
	        ns.DATA_SOURCE
	    FROM 
	    	PROD.SBX_BI.VW_TMP_ASDK_PLAYER_ACQ_CLASSIFICATION ns
	    LEFT JOIN
	    	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd USING(PLAYER_ID)
	    JOIN 
	    	PROD.DWH.D_PLAYER dp 
	    		ON dp.PLAYER_ID = ns.PLAYER_ID
	    			AND dp.BUSINESS_LINE_ID = 1
	    				AND dp.IS_VALID = 1
	)
	,ALL_DATA_UNORDERED AS (
    -- SOURCE 1: NEW DATA (Priority 1)
    SELECT 
        BUSINESS_DOMAIN_ID, PLAYER_ID, PLAYER_CODE, PLAYER_UNIFIED_CODE,
        IS_TEST_ACCOUNT, EVENT_DEVICE, CHANNEL_CODE, EVENT_NAME, EVENT_DT, REGISTRATION_DT,
        FIRST_TIME_DEPOSIT_DT, CAMPAIGN_CODE, CAMPAIGN_NAME, CAMPAIGN_UTM, COUPON_CODE, COUPON_NAME, 
        MARKETING_SOURCE, MARKETING_SOURCE_NAME, MARKETING_SOURCE_MAPPED, MARKETING_CHANNEL, MARKETING_CHANNEL_NAME,
        MARKETING_CHANNEL_MAPPED, ACQUISITION_CHANNEL, ACQUISITION_SUBCHANNEL, ACQUISITION_SOURCE_GROUP, LEGACY_ACQ,
        'ASDK' AS DATA_SOURCE_USED, CAMPAIGN_GOAL, CAMPAIGN_TYPE, CAMPAIGN_VERTICAL,
        1 AS PRIORITY -- NEW MODEL WINS
    FROM 
    	NEW_SOURCE_JOINED
    UNION ALL
    -- SOURCE 2: LEGACY DATA (Priority 2)
    SELECT 
        BUSINESS_DOMAIN_ID, PLAYER_ID, PLAYER_CODE, PLAYER_UNIFIED_CODE,
        IS_TEST_ACCOUNT, CHANNEL_CODE AS EVENT_DEVICE, CHANNEL_CODE, EVENT_NAME, EVENT_DT, REGISTRATION_DT,
        FIRST_TIME_DEPOSIT_DT, CAMPAIGN_CODE, CAMPAIGN_NAME, CAMPAIGN_UTM, COUPON_CODE, COUPON_NAME, 
        MARKETING_SOURCE, MARKETING_SOURCE_NAME, MARKETING_SOURCE_MAPPED, MARKETING_CHANNEL, MARKETING_CHANNEL_NAME, 
        MARKETING_CHANNEL_MAPPED, ACQUISITION_CHANNEL, ACQUISITION_CHANNEL AS ACQUISITION_SUBCHANNEL, 
        ACQUISITION_GROUP AS ACQUISITION_SOURCE_GROUP, ACQUISITION_CHANNEL AS LEGACY_ACQ,
        ATTRIBUTION_SOURCE, 'UNK' AS CAMPAIGN_GOAL, 'UNK' AS CAMPAIGN_TYPE, 'UNK' AS CAMPAIGN_VERTICAL,
        2 AS PRIORITY -- LEGACY IS BACKUP
    FROM 
    	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY
)
SELECT 
	*
FROM 
	ALL_DATA_UNORDERED
QUALIFY 
	ROW_NUMBER() OVER (PARTITION BY PLAYER_ID ORDER BY PRIORITY ASC) = 1;

--CREATE OR REPLACE VIEW PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED AS --- OBSOLETE
WITH 
	NEW_SOURCE_EVENTS AS (
	    SELECT --MERGE RAW CHANNEL DATA
	        BUSINESS_DOMAIN_ID,
	        PLAYER_ID,
	        EVENT_NAME,
	        EVENT_DT,
	        CAMPAIGN_CODE,
	        CAMPAIGN_NAME,
	        CAMPAIGN_GOAL,
	        CAMPAIGN_TYPE,
	        CAMPAIGN_VERTICAL,
	        UTM_CAMPAIGN,
	        URLS AS CAMPAIGN_UTM_PARSED,
	        ADSET_OR_ADGROUP_NAME, -- Unified column for Ad Set or Ad Group
	        AD_OR_KEYWORD,  -- Unified column for Ad Name or Keyword
	        CASE WHEN UTM_CAMPAIGN ILIKE 'ppc%' THEN 'ppc' ELSE UTM_SOURCE END AS UTM_SOURCE,
	        UTM_MEDIUM,
	        ACQUISITION_CHANNEL,
	        ACQUISITION_CHANNEL_GROUP,
	        ACQUISITION_SOURCE_GROUP,
	        DATA_SOURCE,
	        MARKETING_CHANNEL_MAPPED,
	        LEGACY_ACQ_CHANNEL
	    FROM (
	        SELECT -- META RAW DATA FROM DM_MARTECH
	            ffate.BUSINESS_DOMAIN_ID, 
	            ffate.PLAYER_ID, 
	            ffate.EVENT_NAME, 
	            ffate.EVENT_DT, 
	            ffate.URLS,
	            dfac.CAMPAIGN_CODE, 
	            dfac.CAMPAIGN_NAME, 
	            dfac.CAMPAIGN_GOAL,
	            NULL AS CAMPAIGN_TYPE,
	            dfac.CAMPAIGN_VERTICAL,
	            du.UTM_CAMPAIGN, 
	            du.UTM_SOURCE, 
	            du.UTM_MEDIUM, 
	            du.ACQUISITION_CHANNEL, 
	            du.ACQUISITION_CHANNEL_GROUP, 
	            du.ACQUISITION_SOURCE_GROUP,
	            dfaas.AD_SET_NAME AS ADSET_OR_ADGROUP_NAME, 
	            dfaa.AD_NAME AS AD_OR_KEYWORD,
	            'Facebook Touchpoints' AS DATA_SOURCE, 
	            'social' AS MARKETING_CHANNEL_MAPPED,
	            'Social' AS LEGACY_ACQ_CHANNEL
	        FROM 
	        	PROD.DM_MARTECH.F_FACEBOOK_ADS_TOUCHPOINT_EVENT ffate
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_FACEBOOK_ADS_CAMPAIGN dfac USING (FACEBOOK_ADS_CAMPAIGN_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_FACEBOOK_ADS_AD_SET dfaas USING (FACEBOOK_ADS_AD_SET_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_FACEBOOK_ADS_AD dfaa USING (FACEBOOK_ADS_AD_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_UTM du USING (UTM_ID)
	        WHERE 
	        	ffate.EVENT_NAME = 'registration_result_successful' 
	          	AND ffate.PLAYER_ID != 'e129f27c-5103-5c5c-844b-cdf0a15e160d'
	-----------------
	        UNION ALL
	-----------------
	        SELECT -- GOOGLE RAW DATA FROM DM_MARTECH
	            fgate.BUSINESS_DOMAIN_ID, 
	            fgate.PLAYER_ID, 
	            fgate.EVENT_NAME, 
	            fgate.EVENT_DT, 
	            fgate.URLS,
	            dgac.CAMPAIGN_CODE, 
	            dgac.CAMPAIGN_NAME, 
	            dgac.CAMPAIGN_GOAL, 
	            dgac.CAMPAIGN_TYPE,
	            dgac.CAMPAIGN_VERTICAL,
	            du.UTM_CAMPAIGN, 
	            du.UTM_SOURCE, 
	            du.UTM_MEDIUM, 
	            du.ACQUISITION_CHANNEL, 
	            du.ACQUISITION_CHANNEL_GROUP, 
	            du.ACQUISITION_SOURCE_GROUP,
	            dgaag.AD_GROUP_NAME AS ADSET_OR_ADGROUP_NAME, 
	            dgak.KEYWORD_TEXT AS AD_OR_KEYWORD,
	            'Google Touchpoints' AS DATA_SOURCE, 
	            'google' MARKETING_CHANNEL_MAPPED,
	            'Search' AS LEGACY_ACQ_CHANNEL
	        FROM 
	        	PROD.DM_MARTECH.F_GOOGLE_ADS_TOUCHPOINT_EVENT fgate
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_GOOGLE_ADS_CAMPAIGN dgac USING (GOOGLE_ADS_CAMPAIGN_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_GOOGLE_ADS_AD_GROUP dgaag USING (GOOGLE_ADS_AD_GROUP_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_GOOGLE_ADS_KEYWORD dgak USING (GOOGLE_ADS_KEYWORD_ID)
	        LEFT JOIN 
	        	PROD.DM_MARTECH.D_UTM du USING (UTM_ID)
	        WHERE 
	        	fgate.EVENT_NAME = 'registration_result_successful'
	          	AND fgate.PLAYER_ID != 'e129f27c-5103-5c5c-844b-cdf0a15e160d'
	    )
	)
	,NEW_SOURCE_JOINED AS (
	    SELECT -- Add details from  D_PLAYER for the new model
	        ns.BUSINESS_DOMAIN_ID,
	        dbd.BUSINESS_DOMAIN_NAME,
	        ns.PLAYER_ID,
	        dp.PLAYER_CODE,
	        dp.PLAYER_UNIFIED_CODE,
	        dp.IS_TEST_ACCOUNT,
	        dp.REGISTRATION_CHANNEL_CODE AS CHANNEL_CODE,
	        'Registration_Step3' AS EVENT_NAME,
	        ns.EVENT_DT,
	        dp.REGISTRATION_DT,
	        dp.FIRST_TIME_DEPOSIT_DT,
	        ns.CAMPAIGN_CODE,
	        COALESCE(NULLIF(ns.CAMPAIGN_NAME, 'UNK'), IFF(ns.UTM_CAMPAIGN ILIKE ANY ('%||%', '%|%'), ns.UTM_CAMPAIGN, ns.CAMPAIGN_NAME)) AS CAMPAIGN_NAME, --ADD CAMPAIGN_NAME where UTM has campaign name and CAMPAIGN_NAME is null
	        ns.UTM_CAMPAIGN AS CAMPAIGN_UTM,
	        ns.CAMPAIGN_UTM_PARSED,
	        ns.ADSET_OR_ADGROUP_NAME,
	        ns.AD_OR_KEYWORD,
	        'UNK' AS COUPON_CODE,
	        'UNK' AS COUPON_NAME,
	        ns.UTM_SOURCE AS MARKETING_SOURCE,
	        ns.UTM_SOURCE AS MARKETING_SOURCE_NAME,
	        IFF(ns.UTM_SOURCE ILIKE ANY ('%facebook%', '%fb%', '%meta%'), 'facebook', ns.UTM_SOURCE) AS MARKETING_SOURCE_MAPPED,
	        ns.UTM_MEDIUM AS MARKETING_CHANNEL,
	        ns.UTM_MEDIUM AS MARKETING_CHANNEL_NAME,
	        ns.MARKETING_CHANNEL_MAPPED,
	        ns.ACQUISITION_CHANNEL, 
	        ns.ACQUISITION_CHANNEL_GROUP, 
	        ns.ACQUISITION_SOURCE_GROUP,
	        ns.LEGACY_ACQ_CHANNEL,
	        ns.DATA_SOURCE,
	        ns.CAMPAIGN_GOAL,
	        ns.CAMPAIGN_TYPE,
	        ns.CAMPAIGN_VERTICAL
	    FROM 
	    	NEW_SOURCE_EVENTS ns
	    JOIN 
	    	PROD.DWH.D_BUSINESS_DOMAIN dbd USING (BUSINESS_DOMAIN_ID)
	    JOIN 
	    	PROD.DWH.D_PLAYER dp USING (PLAYER_ID)  	
	)
	,CTE_CLEAN_ORGANIC_TOUCHPOINTS AS ( -- KEEP SEO ONLY TO ENRICH LEGACY ATTRIBUTION
		SELECT
			fote.PLAYER_ID,
			fote.ACQUISITION_CHANNEL AS MKT_CHANNEL_SOURCE,
			'seo' AS MKT_CHANNEL,
			'Organic - SEO' AS ACQUISITION_CHANNEL,
			fote.ACQUISITION_SOURCE AS ACQUISITION_GROUP,
			fote.REFERRER_URI,
			fote.URLS
		FROM 
			PROD.DM_MARTECH.F_ORGANIC_TOUCHPOINT_EVENT fote
		LEFT JOIN
			PROD.DWH.D_PLAYER dp
				ON fote.PLAYER_ID = dp.PLAYER_ID
		WHERE
			fote.EVENT_NAME = 'registration_result_successful' -- Registrations only
			AND fote.ACQUISITION_CHANNEL_GROUP IN ('Organic Search', 'Organic Search - LLM') --SEO only
			AND dp.IS_TEST_ACCOUNT != 1 -- No test accounts
			AND dp.BUSINESS_LINE_ID = 1 -- Online only
			AND fote.PLAYER_ID != 'e129f27c-5103-5c5c-844b-cdf0a15e160d' -- Removing UNK players from events
	)
	,CTE_UPDATED_ATTRIBUTION_SOURCE AS ( -- ENRICH ATTRIBUTION TABLE WITH SEO DATA
		SELECT 
			drrd.BUSINESS_DOMAIN_ID, 
			drrd.BUSINESS_DOMAIN_NAME, 
			drrd.PLAYER_ID, 
			drrd.PLAYER_CODE, 
			drrd.PLAYER_UNIFIED_CODE, 
			drrd.IS_TEST_ACCOUNT, 
			drrd.CHANNEL_CODE, 
			drrd.EVENT_NAME, 
			drrd.EVENT_DT, 
			drrd.REGISTRATION_DT, 
			drrd.FIRST_TIME_DEPOSIT_DT, 
			drrd.CAMPAIGN_CODE, 
			drrd.CAMPAIGN_NAME, 
			drrd.CAMPAIGN_UTM, 
			drrd.CAMPAIGN_UTM_PARSED, 
			drrd.CONTENT, 
			drrd.CREATIVE, 
			drrd.COUPON_CODE, 
			drrd.COUPON_NAME, 
			drrd.MARKETING_SOURCE, 
			drrd.MARKETING_SOURCE_NAME, 
			COALESCE(NULLIF(drrd.MARKETING_SOURCE_MAPPED, 'UNK'), new_org.REFERRER_URI, 'UNK') AS MARKETING_SOURCE_MAPPED,
			drrd.MARKETING_CHANNEL, 
			drrd.MARKETING_CHANNEL_NAME, 
			COALESCE(NULLIF(drrd.MARKETING_CHANNEL_MAPPED, 'UNK'), new_org.MKT_CHANNEL, 'UNK') AS MARKETING_CHANNEL_MAPPED,
			COALESCE(NULLIF(new_org.ACQUISITION_CHANNEL, 'UNK'), drrd.ACQUISITION_CHANNEL) AS ACQUISITION_CHANNEL,
			drrd.ACQUISITION_GROUP, 
			drrd.ATTRIBUTION_SOURCE
		FROM 
			PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd
		LEFT JOIN
			CTE_CLEAN_ORGANIC_TOUCHPOINTS new_org
				ON new_org.PLAYER_ID = drrd.PLAYER_ID
					AND drrd.ACQUISITION_GROUP = 'Organic'
	)
	,ALL_DATA_UNORDERED AS (
    -- SOURCE 1: NEW DATA (Priority 1)
    SELECT 
        BUSINESS_DOMAIN_ID, BUSINESS_DOMAIN_NAME, PLAYER_ID, PLAYER_CODE, PLAYER_UNIFIED_CODE,
        IS_TEST_ACCOUNT, CHANNEL_CODE, EVENT_NAME, EVENT_DT, REGISTRATION_DT,
        FIRST_TIME_DEPOSIT_DT, CAMPAIGN_CODE, CAMPAIGN_NAME, CAMPAIGN_UTM, CAMPAIGN_UTM_PARSED,
        ADSET_OR_ADGROUP_NAME, AD_OR_KEYWORD, COUPON_CODE, COUPON_NAME, MARKETING_SOURCE,
        MARKETING_SOURCE_NAME, MARKETING_SOURCE_MAPPED, MARKETING_CHANNEL, MARKETING_CHANNEL_NAME,
        MARKETING_CHANNEL_MAPPED, ACQUISITION_CHANNEL, ACQUISITION_CHANNEL_GROUP, ACQUISITION_SOURCE_GROUP,
        LEGACY_ACQ_CHANNEL, DATA_SOURCE, CAMPAIGN_GOAL, CAMPAIGN_TYPE, CAMPAIGN_VERTICAL,
        1 AS PRIORITY -- NEW MODEL WINS
    FROM 
    	NEW_SOURCE_JOINED
    UNION ALL
    -- SOURCE 2: LEGACY DATA (Priority 2)
    SELECT 
        BUSINESS_DOMAIN_ID, BUSINESS_DOMAIN_NAME, PLAYER_ID, PLAYER_CODE, PLAYER_UNIFIED_CODE,
        IS_TEST_ACCOUNT, CHANNEL_CODE, EVENT_NAME, EVENT_DT, REGISTRATION_DT,
        FIRST_TIME_DEPOSIT_DT, CAMPAIGN_CODE, CAMPAIGN_NAME, CAMPAIGN_UTM, CAMPAIGN_UTM_PARSED, 
        CONTENT AS ADSET_OR_ADGROUP_NAME, CREATIVE AS AD_OR_KEYWORD, COUPON_CODE, COUPON_NAME, MARKETING_SOURCE, 
        MARKETING_SOURCE_NAME, MARKETING_SOURCE_MAPPED, MARKETING_CHANNEL, MARKETING_CHANNEL_NAME, 
        MARKETING_CHANNEL_MAPPED, ACQUISITION_CHANNEL, 'UNK' AS ACQUISITION_CHANNEL_GROUP, 
        ACQUISITION_GROUP AS ACQUISITION_SOURCE_GROUP, ACQUISITION_CHANNEL AS LEGACY_ACQ_CHANNEL, 
        ATTRIBUTION_SOURCE, 'UNK' AS CAMPAIGN_GOAL, 'UNK' AS CAMPAIGN_TYPE, 'UNK' AS CAMPAIGN_VERTICAL,
        2 AS PRIORITY -- LEGACY IS BACKUP
    FROM 
    	CTE_UPDATED_ATTRIBUTION_SOURCE
)
SELECT 
	*
FROM 
	ALL_DATA_UNORDERED
QUALIFY 
	ROW_NUMBER() OVER (PARTITION BY PLAYER_ID ORDER BY PRIORITY ASC) = 1;
		
---------------------
	        
--DQ

-- OVERALL PLAYERS COMPARISON AT REG MONTH LEVEL
SELECT 'NEW', DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH, BUSINESS_DOMAIN_ID, COUNT(PLAYER_ID) FROM PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED WHERE IS_TEST_ACCOUNT!= 1 GROUP BY ALL
UNION ALL
SELECT 'CURRENT', DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH, BUSINESS_DOMAIN_ID, COUNT(PLAYER_ID) FROM PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY WHERE IS_TEST_ACCOUNT!= 1 GROUP BY ALL

-- PLAYERS COMPARISON AT FTD MONTH LEVEL
SELECT 'NEW', DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS FTD_MONTH, BUSINESS_DOMAIN_ID, COUNT(PLAYER_ID) FROM PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED WHERE IS_TEST_ACCOUNT!= 1 GROUP BY ALL
UNION ALL
SELECT 'CURRENT', DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS FTD_MONTH, BUSINESS_DOMAIN_ID, COUNT(PLAYER_ID) FROM PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY WHERE IS_TEST_ACCOUNT!= 1 GROUP BY ALL

-- OVERALL PLAYERS COMPARISON AT REG MONTH LEVEL AND NORMALIZED ACQ_CHANNEL
SELECT 
	'NEW', 
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH, 
	BUSINESS_DOMAIN_ID, 
	CASE
        WHEN acquisition_channel ILIKE 'affiliates' THEN 'Affiliate'
        WHEN acquisition_channel ILIKE ANY ('paid_search', 'paid_video') THEN 'Search'
        WHEN acquisition_channel ILIKE 'paid_social' THEN 'Social'
        WHEN acquisition_channel ILIKE ANY ('organic%', 'direct', 'Crm') THEN 'Organic'
        WHEN acquisition_channel ILIKE 'raf' THEN 'RAF'
        WHEN acquisition_channel ILIKE ANY ('display_direct', 'programmatic') THEN 'Display'
        WHEN acquisition_channel ILIKE 'Unk' THEN 'UNK'
        ELSE acquisition_channel
        END AS ACQ_CHANNEL,
    LEGACY_ACQ,
	COUNT(PLAYER_ID) AS PLAYER_ID_COUNT
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED 
WHERE 
	IS_TEST_ACCOUNT!= 1 
GROUP BY ALL
UNION ALL
SELECT 
	'CURRENT', 
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH, 
	BUSINESS_DOMAIN_ID, 
	CASE
        WHEN acquisition_channel  ILIKE ANY ('organic%') THEN 'Organic'
        ELSE acquisition_channel 
    END AS ACQ_CHANNEL,
    ACQUISITION_CHannel,
	COUNT(PLAYER_ID) 
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY 
WHERE 
	IS_TEST_ACCOUNT!= 1 
GROUP BY ALL

-- OVERALL PLAYERS COMPARISON AT FTD MONTH LEVEL AND NORMALIZED ACQ_CHANNEL
SELECT 
	'NEW', 
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS REG_MONTH, 
	BUSINESS_DOMAIN_ID, 
	CASE
        WHEN acquisition_channel ILIKE 'affiliates' THEN 'Affiliate'
        WHEN acquisition_channel ILIKE ANY ('paid_search', 'paid_video') THEN 'Search'
        WHEN acquisition_channel = 'paid_social' THEN 'Social'
        WHEN acquisition_channel ILIKE ANY ('organic%', 'direct', 'Crm') THEN 'Organic'
        WHEN acquisition_channel = 'raf' THEN 'RAF'
        WHEN acquisition_channel ILIKE ANY ('display_direct', 'programmatic') THEN 'Display'
        ELSE acquisition_channel
        END AS ACQ_CHANNEL,
	COUNT(PLAYER_ID) AS PLAYER_ID_COUNT
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED 
WHERE IS_TEST_ACCOUNT!= 1 
GROUP BY ALL
UNION ALL
SELECT 
	'CURRENT', 
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS REG_MONTH, 
	BUSINESS_DOMAIN_ID, 
	CASE
        WHEN acquisition_channel  ILIKE ANY ('organic%') THEN 'Organic'
        ELSE acquisition_channel 
    END AS ACQ_CHANNEL,
	COUNT(PLAYER_ID) 
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY 
WHERE IS_TEST_ACCOUNT!= 1 
GROUP BY ALL

SELECT 
	b.*,
	a.LEGACY_ACQ,
	a.MARKETING_SOURCE_MAPPED
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED a
JOIN
	PROD.DM_MARTECH.VW_ASDK_PLAYER_LAST_NON_DIRECT_ACQUISITION b USING(PLAYER_ID)
WHERE 
	a.LEGACY_ACQ = 'Display' 
	AND a.REGISTRATION_DT::DATE >= '2025-12-01'
	AND b.PLAYER_ID IN ('aab9c5fe-d392-4b38-8708-1f116ecb84c1','3ba0d8f7-450c-4835-a089-b20755dc33b8','248be930-5f6d-4573-9860-12f0ff1c67a7')

WITH cte AS (
    SELECT
        asdk.*
        , drrd.acquisition_channel AS old_acquisition_channel
        , drrd.acquisition_group AS old_acquisition_group
        , CASE
            WHEN asdk.acquisition_channel = 'affiliates' THEN 'Affiliate'
            WHEN asdk.acquisition_channel ILIKE ANY ('paid_search', 'paid_video') THEN 'Search'
            WHEN asdk.acquisition_channel = 'paid_social' THEN 'Social'
            WHEN asdk.acquisition_channel ILIKE ANY ('organic%', 'direct', 'crm') THEN 'Organic'
            WHEN asdk.acquisition_channel = 'raf' THEN 'RAF'
            WHEN asdk.acquisition_channel ILIKE ANY ('display_direct', 'programmatic') THEN 'Display'
            ELSE 'UNK'
        END AS mapped_asdk_acq_channel
        , CASE
            WHEN drrd.acquisition_channel  ILIKE ANY ('organic%') THEN 'Organic'
            ELSE drrd.acquisition_channel 
        END AS mapped_old_acq_channel
    FROM dm_martech.vw_asdk_player_last_non_direct_acquisition asdk
    JOIN dm_martech.d_registration_reporting_daily drrd
        USING (player_id)
    --LIMIT 10000
)
SELECT
    business_domain_code
    , COUNT(*) AS total
    , COUNT_IF(mapped_old_acq_channel != mapped_asdk_acq_channel) AS different_cnt
    , COUNT_IF(mapped_old_acq_channel = mapped_asdk_acq_channel) AS equal_cnt
    , different_cnt / total * 100 AS different_pct
    , equal_cnt / total * 100 AS equal_pct
FROM cte
GROUP BY ALL
ORDER BY 1,2,3
;



WITH
	CTE_OLD AS (
		SELECT 'OLD', * EXCLUDE (VALID_FROM_DT, VALID_TO_DT, IS_VALID, EXT_REFR, REGISTRATION_REPORTING_DAILY_SID, INSERT_DT, UPDATE_DT) FROM PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY 
	)
	,CTE_UNION AS (
SELECT 
	'NEW' AS VERSION, * FROM PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED
UNION ALL
SELECT 
	'OLD', BUSINESS_DOMAIN_ID, PLAYER_ID, PLAYER_CODE, PLAYER_UNIFIED_CODE, IS_TEST_ACCOUNT, NULL AS EVENT_DEVICE, CHANNEL_CODE, EVENT_NAME, 
	EVENT_DT, REGISTRATION_DT, FIRST_TIME_DEPOSIT_DT, CAMPAIGN_CODE, CAMPAIGN_NAME, CAMPAIGN_UTM, COUPON_CODE, COUPON_NAME, 
	MARKETING_SOURCE, MARKETING_SOURCE_NAME, MARKETING_SOURCE_MAPPED, MARKETING_CHANNEL, MARKETING_CHANNEL_NAME, 
	MARKETING_CHANNEL_MAPPED, ACQUISITION_CHANNEL, ACQUISITION_CHANNEL AS ACQUISITION_SUBCHANNEL, ACQUISITION_GROUP AS ACQUISITION_SOURCE_GROUP, 
	ATTRIBUTION_SOURCE, 'UNK', 'UNK', 'UNK', 2 AS PRIORITY FROM CTE_OLD
	)
	,CTE_LIMIT_TO_ASDK AS (
SELECT * FROM CTE_UNION WHERE PLAYER_ID IN (SELECT PLAYER_ID FROM PROD.DM_MARTECH.VW_ASDK_PLAYER_REG_ATTRIBUTION)
ORDER BY
	PLAYER_ID DESC,
	VERSION 
	)
SELECT 
	CASE
		WHEN ACQUISITION_CHANNEL LIKE 'Affiliate%' THEN 'Affiliate'
		WHEN ACQUISITION_CHANNEL ILIKE ANY ('Direct', 'Organic%', 'Crm', 'Unk') THEN 'Organic'
		WHEN ACQUISITION_CHANNEL ILIKE ANY ('Search', 'Paid_Search', 'Paid_Video') THEN 'Search'
		WHEN ACQUISITION_CHANNEL ILIKE ANY ('Paid_Social', 'Social') THEN 'Social' 
		WHEN ACQUISITION_CHANNEL ILIKE ANY ('Display%', 'Program%', 'Display') THEN 'Display'
	ELSE 'Other'
	END AS ACQ_CHANNEL,
	CASE
		WHEN DATA_SOURCE_USED = 'ASDK' THEN 'ASDK' ELSE 'OLD'
	END AS MODEL,	
	COUNT(PLAYER_ID) AS PLAYERS
FROM
	CTE_LIMIT_TO_ASDK
GROUP BY ALL

--REG DATE COMPARISON
SELECT
	'NEW',
	a.BUSINESS_DOMAIN_ID,
	CASE
            WHEN a.acquisition_channel = 'affiliates' THEN 'Affiliate'
            WHEN a.acquisition_channel ILIKE ANY ('paid_search', 'paid_video') THEN 'Search'
            WHEN a.acquisition_channel = 'paid_social' THEN 'Social'
            WHEN a.acquisition_channel ILIKE ANY ('organic%', 'direct') THEN 'Organic'
            WHEN a.acquisition_channel = 'raf' THEN 'RAF'
            WHEN a.acquisition_channel ILIKE ANY ('display_direct', 'programmatic') THEN 'Display'
            ELSE 'UNK'
        END AS ACQ_CHANNEL,
--	a.ACQUISITION_SOURCE_GROUP,
--	a.EVENT_DEVICE,
	DATE_TRUNC('MONTH', a.REGISTRATION_DT) AS REG_MONTH,
	COUNT(a.*)
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED a --WHERE PLAYER_ID IN (SELECT PLAYER_ID FROM PROD.sbx_data_product.asdk_player_acq_classification)
WHERE
	a.REGISTRATION_DT::DATE >= '2026-01-01'
GROUP BY ALL
UNION ALL
SELECT
	'OLD',
	BUSINESS_DOMAIN_ID,
	CASE
            WHEN acquisition_channel  ILIKE ANY ('organic%') THEN 'Organic'
            ELSE acquisition_channel 
        END AS ACQ_CHANNEL,
--	ACQUISITION_GROUP,
--	CHANNEL_CODE,
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH,
	COUNT(*)
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY -- WHERE PLAYER_ID IN (SELECT PLAYER_ID FROM PROD.sbx_data_product.asdk_player_acq_classification)
WHERE
	REGISTRATION_DT::DATE >= '2026-01-01'
--	AND CHANNEL_CODE IN ('MOBILE', 'DESKTOP')
GROUP BY ALL

--FTD DATE COMPARISON
SELECT
	'NEW',
	BUSINESS_DOMAIN_ID,
	LEGACY_ACQ_CHANNEL,
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS REG_MONTH,
	COUNT(*)
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED
WHERE
	PLAYER_ID IN (SELECT PLAYER_ID FROM PROD.sbx_data_product.asdk_player_acq_classification)
GROUP BY ALL
UNION ALL
SELECT
	'OLD',
	BUSINESS_DOMAIN_ID,
	ACQUiSITION_CHANNEL,
	DATE_TRUNC('MONTH', FIRST_TIME_DEPOSIT_DT) AS REG_MONTH,
	COUNT(*)
FROM 
	PROD.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY 
WHERE
	PLAYER_ID IN (SELECT PLAYER_ID FROM PROD.sbx_data_product.asdk_player_acq_classification)
GROUP BY ALL

--------------------
	
SELECT 
	*
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED 
WHERE 	
	(REGISTRATION_DT::date >= LAST_DAY(DATEADD(YEAR, -3, CURRENT_DATE), 'Y')
	OR FIRST_TIME_DEPOSIT_DT::date >= LAST_DAY(DATEADD(YEAR, -3, CURRENT_DATE), 'Y'))
	AND COUPON_NAME != 'UNK'
	LIMIT 10

--CREATE OR REPLACE VIEW PROD.SBX_BI.VW_ATTRIBUTION_USING_NEW_MODEL AS
WITH
	unified_dates AS (
		SELECT DISTINCT
			dp.PLAYER_UNIFIED_CODE,
			dp.PLAYER_ID,
			dp.IS_TEST_ACCOUNT,
			dp.business_domain_id,
			dp.REGISTRATION_DT REG_DT,
			dp.FIRST_TIME_DEPOSIT_DT FTD_DT,
			dp.REGISTRATION_CHANNEL_CODE,
			MIN(dp.REGISTRATION_DT) OVER(PARTITION BY dp.PLAYER_UNIFIED_CODE) REGISTRATION_DT,
			MIN(dp.FIRST_TIME_DEPOSIT_DT) OVER(PARTITION BY dp.PLAYER_UNIFIED_CODE) FIRST_TIME_DEPOSIT_DT,
			dbm.COUNTRY_TIMEZONE
		FROM 
			PROD.DWH.D_PLAYER dp
		JOIN 
			PROD.DWH.D_BUSINESS_MARKET dbm
				ON dp.BUSINESS_MARKET_ID = dbm.BUSINESS_MARKET_ID
		WHERE 
			dp.business_domain_id IN (1, 2, 3, 8, 10, 14, 15, 16) -- HAVING BOTH BRAZILIAN DOMAINS FOR CONTINUITY
			AND (dp.BUSINESS_MARKET_ID = 24 OR dp.BUSINESS_DOMAIN_ID NOT IN (1,14))
			AND dp.BUSINESS_LINE_ID = 1 -- ONLINE
			AND dp.is_valid = 1	
	)
	,players AS (
		SELECT
			dp.PLAYER_UNIFIED_CODE,
			MIN(dp.business_domain_id) business_domain_id,
			MAX(dp.is_test_account) is_test_account,
			MAX(CASE WHEN dp.REG_DT = dp.REGISTRATION_DT THEN dp.REGISTRATION_CHANNEL_CODE ELSE NULL END) REGISTRATION_CHANNEL_CODE,
			COALESCE(MIN(CASE WHEN dp.REG_DT = dp.REGISTRATION_DT THEN reg.player_id ELSE NULL END),
					 MIN(CASE WHEN dp.REG_DT = dp.REGISTRATION_DT THEN dp.player_id ELSE NULL END)) REG_PLAYER_ID,
			MIN(CONVERT_TIMEZONE('UTC', dp.COUNTRY_TIMEZONE, dp.REGISTRATION_DT)) REGISTRATION_DT_LOCAL,
			MIN(CONVERT_TIMEZONE('UTC', dp.COUNTRY_TIMEZONE, dp.FIRST_TIME_DEPOSIT_DT)) FIRST_TIME_DEPOSIT_DT_LOCAL
		FROM 
			unified_dates dp
		--- PRE-VAN-HECKE ATTRIBUTED REGISTRATIONS:
		LEFT JOIN 
			PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED reg
				ON  dp.player_id = reg.player_id
					AND reg.business_domain_id = 8
						AND reg.REGISTRATION_DT  < '2024-09-02'::date -- VH GO-live
							AND reg.ACQUISITION_SOURCE_GROUP <> 'Organic'
	GROUP BY 
		dp.PLAYER_UNIFIED_CODE
	HAVING 
		YEAR(REGISTRATION_DT_LOCAL) >= YEAR(CURRENT_DATE()) --- 2 -- LAST 3 YEARS OF DATA
		OR YEAR(FIRST_TIME_DEPOSIT_DT_LOCAL) >= YEAR(CURRENT_DATE()) --- 2 --LAST 3 YEARS OF DATA
	)
SELECT
	dp.PLAYER_UNIFIED_CODE,
	dp.REG_PLAYER_ID,
	dp.BUSINESS_DOMAIN_ID,
	dp.IS_TEST_ACCOUNT,
	dp.REGISTRATION_DT_LOCAL,
	dp.FIRST_TIME_DEPOSIT_DT_LOCAL,
	dp.REGISTRATION_CHANNEL_CODE,
	------ REG ATTRIBUTION:
	UPPER(reg.COUPON_NAME) AS REG_COUPON_NAME,
	COALESCE(dcr.MARKETING_CHANNEL_MAPPED, reg.MARKETING_CHANNEL_MAPPED) AS REG_MKT_CHANNEL,
	COALESCE(dcr.MARKETING_SOURCE_MAPPED, reg.MARKETING_SOURCE_MAPPED) AS REG_MKT_SOURCE,
	COALESCE(NULLIF(COALESCE(dcr.ACQUISITION_CHANNEL, reg.ACQUISITION_CHANNEL), 'UNK'), 'Organic - Superbet') AS REG_ACQ_CHANNEL,
	COALESCE(dcr.ACQUISITION_CHANNEL, reg.ACQUISITION_SUBCHANNEL) AS REG_ACQ_SUBCHANNEL,
	reg.CAMPAIGN_NAME AS REG_CAMPAIGN,
	reg.CAMPAIGN_UTM AS REG_CAMPAIGN_UTM,
	reg.CAMPAIGN_GOAL,
	reg.CAMPAIGN_TYPE,
	reg.CAMPAIGN_VERTICAL,
	------ WELCOME OFFER:
	COALESCE(wo.BONUS_TYPE, 'No Bonus') AS WELCOME_OFFER_RECEIVED,
	------RO_NG_RO Overlapping
	NVL(overlap.RO_NG_RO_OVRELAPPING, 0) AS RO_NG_RO_OVERLAPPING,
	---------------
	reg.DATA_SOURCE_USED,
	reg.LEGACY_ACQ
FROM 
	players dp
LEFT JOIN 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED reg 
		ON   dp.REG_PLAYER_ID = reg.player_id
		AND  (reg.REGISTRATION_DT::date >= LAST_DAY(DATEADD('YEAR', -1, CURRENT_DATE()), 'Y') -- LAST 3 YEARS OF DATA // One extra DAY TO allow FOR timezones 
			  OR reg.FIRST_TIME_DEPOSIT_DT::date >= LAST_DAY(DATEADD('YEAR', -1, CURRENT_DATE()), 'Y'))
--------------- TO MAP COUPON CODES IN LINE WITH PL MKT TEAM PREFERENCES:
LEFT JOIN  
	PROD.BI.D_COUPON_REPORTING dcr
		ON  reg.BUSINESS_DOMAIN_ID = dcr.BUSINESS_DOMAIN_ID
		AND reg.MARKETING_SOURCE_NAME = dcr.MARKETING_SOURCE_NAME
		AND reg.COUPON_NAME = dcr.COUPON_NAME
		AND reg.DATA_SOURCE_USED LIKE '%Betler%'
--------------- TO FETCH WELCOME OFFER RECEIVED
LEFT JOIN 
	PROD.REPORTING.VW_WELCOME_OFFER_RECEIVED wo
		ON wo.PLAYER_UNIFIED_CODE = dp.PLAYER_UNIFIED_CODE
---------------RO_NG_RO Overlapping
LEFT JOIN
	PROD.BI.VW_RO_NG_RO_OVERLAPPING_PLAYERS overlap
		ON overlap.PLAYER_ID = dp.REG_PLAYER_ID;

--CREATE OR REPLACE VIEW PROD.SBX_BI.VW_ACQUISITION_USING_NEW_MODEL AS
SELECT
	attn.PLAYER_UNIFIED_CODE,
	attn.REG_PLAYER_ID,
	attn.BUSINESS_DOMAIN_ID,
	attn.IS_TEST_ACCOUNT,
	attn.REGISTRATION_DT_LOCAL,
	attn.FIRST_TIME_DEPOSIT_DT_LOCAL,
	attn.REGISTRATION_CHANNEL_CODE,
	attn.REG_COUPON_NAME,
	attn.REG_MKT_CHANNEL,
	attn.REG_MKT_SOURCE,
	attn.REG_ACQ_CHANNEL,
	attn.REG_ACQ_SUBCHANNEL,
	attn.REG_CAMPAIGN,
	attn.REG_CAMPAIGN_UTM,
	attn.CAMPAIGN_GOAL,
	attn.CAMPAIGN_TYPE,
	attn.CAMPAIGN_VERTICAL,
	attn.WELCOME_OFFER_RECEIVED,
	attn.RO_NG_RO_OVERLAPPING,
-------LTV VIEW DATA
	ltv.NGP_YR_1,
	ltv.NGR_YR_1,
	ltv.NGP_30D,
	ltv.NGR_30D,
	ltv.LTV,
---------------
	ltv.LTV * es.CUMULATIVE_PCT AS LTV_since_FTD,
---------------
	attn.DATA_SOURCE_USED,
	attn.LEGACY_ACQ
FROM 
    PROD.SBX_BI.VW_ATTRIBUTION_USING_NEW_MODEL attn --time limited
LEFT JOIN 
    PROD.REPORTING.VW_LTV_COST_REPORT ltv -- time limited
		ON attn.PLAYER_UNIFIED_CODE = ltv.PLAYER_UNIFIED_CODE
LEFT JOIN
	PROD.BI.LTV_EXPECTED_SHARE es -- last 2 years only
		ON attn.BUSINESS_DOMAIN_ID = es.BUSINESS_DOMAIN_ID 
			AND es.WEEKS_SINCE_FTD = DATEdiff('week',DATE_TRUNC('week',attn.FIRST_TIME_DEPOSIT_DT_LOCAL),DATE_TRUNC('week',CURRENT_DATE()))
				AND attn.FIRST_TIME_DEPOSIT_DT_LOCAL::DATE >= DATEADD('YEAR', -1,  DATE_TRUNC('year',CURRENT_DATE()));

--CREATE OR REPLACE VIEW PROD.SBX_BI.VW_MKT_DIGITAL_DAILY_AUTO_COST_REPORT as
--- Affiliate
SELECT 
	vrr.BUSINESS_DOMAIN_ID,
	vrr.FIRST_TIME_DEPOSIT_DT_LOCAL::date DATE_VALUE,
	'Affiliate' ACQUISITION_CHANNEL,
	SUM(COALESCE(VAPC.CPA_COST_AMT_EUR, 0) + COALESCE(VAPC.FIXED_FEE_COST_AMT_EUR, 0))
	-- To see how 2.072 was derived, look here:
	-- https://www.notion.so/superbet/Affiliates-Reporting-Handover-October-24-11a032f852c5801197b5e0af3dbfeb42
    + SUM(COALESCE(ltv.LTV, 0) * (1 - 2.072 *
                     -- This Case statement is for the Operating Fee
                     (CASE WHEN vrr.BUSINESS_DOMAIN_ID != 2 THEN 0
                           WHEN vrr.FIRST_TIME_DEPOSIT_DT_LOCAL::date >= '2024-07-25' THEN 0.25
                           WHEN vrr.FIRST_TIME_DEPOSIT_DT_LOCAL::date >= '2024-04-01' THEN 0.21
                           WHEN vrr.FIRST_TIME_DEPOSIT_DT_LOCAL::date >= '2023-11-01' THEN 0.12
                           WHEN vrr.FIRST_TIME_DEPOSIT_DT_LOCAL::date >= '2023-04-03' THEN 0.065
                           ELSE 0 END)) * COALESCE(VAPC.REVENUE_SHARE_COST_PCT, 0)) DIGITAL_COST
FROM 
	PROD.REPORTING.VW_ATTRIBUTION_COST_REPORT vrr
JOIN 
	PROD.REPORTING.VW_LTV_PLAYERIDS ltv 
		ON vrr.player_unified_code = ltv.player_unified_code
JOIN
	PROD.REPORTING.VW_AFFILIATE_PLAYER_COST_REPORT VAPC 
		ON vrr.REG_PLAYER_ID = vapc.PLAYER_ID
WHERE 1 = 1 -- NEW
	AND vrr.FIRST_TIME_DEPOSIT_DT_LOCAL >= dateadd('year', -2 ,date_trunc('year',CURRENT_DATE())) --'2022-01-01'::date
	AND vrr.REG_ACQ_CHANNEL = 'Affiliate'
GROUP BY 
	1,2,3
----------------------
UNION ALL
--- Search and ASA (without Brand AND RET/REAC)
SELECT 
	BUSINESS_DOMAIN_ID,
	DATE_VALUE,
	'Search' AS ACQUISITION_CHANNEL,
	sum(COST_AMT_EUR) DIGITAL_COST
FROM
	(SELECT 
		fga.BUSINESS_DOMAIN_ID,
		fga.DATE_VALUE,
		sum(fga.COST_AMT * fer.MIDDLE_RATE) AS COST_AMT_EUR
	FROM
		PROD.DM_MARTECH.F_GOOGLE_AD fga
	LEFT JOIN
		PROD.DWH.F_EXCHANGE_RATE fer
			ON fer.FROM_CURRENCY_ID = fga.CURRENCY_ID
				AND fer.RATE_DATE = fga.DATE_VALUE
	LEFT JOIN
		PROD.BI.VW_SEARCH_CAMPAIGN_TYPE_PARAM dgac3
			ON fga.GOOGLE_AD_CAMPAIGN_ID = dgac3.GOOGLE_AD_CAMPAIGN_ID -- NEW
				AND fga.BUSINESS_DOMAIN_ID = dgac3.BUSINESS_DOMAIN_ID -- NEW 
	WHERE 1 = 1
		AND fga.DATE_VALUE >= dateadd('year', -2, date_trunc('year',CURRENT_DATE())) --'2022-01-01'
		AND fga.BUSINESS_DOMAIN_ID = 15 --IN (1,2,3,8,10,14,15,16)
		AND dgac3.CAMPAIGN_TYPE IS NULL
        AND fer.TO_CURRENCY_CODE = 'EUR'
	GROUP BY 1, 2
	UNION ALL 
	SELECT 
		fga.BUSINESS_DOMAIN_ID,
		fga.REPORTING_DATE AS DATE_VALUE,
		sum(fga.SPEND_AMT * fer.MIDDLE_RATE) AS COST_AMT_EUR
	FROM
		PROD.DM_MARTECH.F_APPLE_SEARCH_AD fga
	LEFT JOIN
		PROD.DWH.F_EXCHANGE_RATE fer
			ON fer.FROM_CURRENCY_ID = fga.CURRENCY_ID
				AND fer.RATE_DATE = fga.REPORTING_DATE		
	WHERE 1 = 1 -- NEW
		AND fga.REPORTING_DATE >= dateadd('year',-2, date_trunc('year',CURRENT_DATE()))
		AND fga.BUSINESS_DOMAIN_ID = 15 --IN (1,2,3,8,10,14,15,16)
        AND fer.TO_CURRENCY_CODE = 'EUR'
	GROUP BY 1, 2) google_apple
GROUP BY
	1,2
--------------------------
UNION ALL 
--- Social (without Brand and Retention)
SELECT 
	ffa.BUSINESS_DOMAIN_ID,
	ffa.DATE_VALUE,
	'Social' ACQUISITION_CHANNEL,
	sum(ffa.SPEND_AMT * fer.MIDDLE_RATE) AS COST_AMT_EUR
FROM
	PROD.DM_MARTECH.F_FACEBOOK_AD ffa
JOIN 
	PROD.DM_MARTECH.D_FACEBOOK_AD_LINK dfal 
		ON ffa.FACEBOOK_AD_LINK_ID = dfal.FACEBOOK_AD_LINK_ID
-- LEFT JOIN
-- 	PROD.DM_MARTECH.D_FACEBOOK_AD_CAMPAIGN dfac
-- 		ON dfac.FACEBOOK_AD_CAMPAIGN_ID = ffa.FACEBOOK_AD_CAMPAIGN_ID
LEFT JOIN
	PROD.DWH.F_EXCHANGE_RATE fer
		ON fer.FROM_CURRENCY_ID = ffa.CURRENCY_ID
			AND fer.RATE_DATE = ffa.DATE_VALUE	
LEFT JOIN
	 PROD.BI.VW_SOCIAL_CAMPAIGN_TYPE_PARAM camp
	 	ON ffa.FACEBOOK_AD_CAMPAIGN_ID = camp.FACEBOOK_AD_CAMPAIGN_ID
	 		AND ffa.BUSINESS_DOMAIN_ID = camp.BUSINESS_DOMAIN_ID
WHERE 1 = 1 -- NEW
    AND fer.TO_CURRENCY_CODE = 'EUR'
	AND YEAR(ffa.DATE_VALUE) >= YEAR(CURRENT_DATE())-2 --'2022-01-01'
	AND ffa.BUSINESS_DOMAIN_ID = 15 --IN (1,2,3,8,10,14,15,16)
	AND (COALESCE(dfal.LINK_PARSED:host::varchar,'UNK') != 'superscore.onelink.me' OR COALESCE(dfal.LINK_PARSED:host:PARAMETERS:id::varchar,'UNK') != 'com.superscore')
	AND camp.CAMPAIGN_TYPE IS NULL
GROUP BY 1, 2;



--------

SELECT
	BUSINESS_DOMAIN_ID,
	COALESCE(NULLIF(LOWER(ACQUISITION_SOURCE_GROUP), 'unk'), 'direct') AS ACQUISITION_SOURCE_GROUP,
	COALESCE(NULLIF(LOWER(ACQUISITION_CHANNEL), 'unk'), 'Direct') AS ACQUISITION_CHANNEL,
	LEGACY_ACQ,
	DATE_TRUNC('MONTH', REGISTRATION_DT) AS REG_MONTH,
	COUNT(PLAYER_ID)
FROM 
	PROD.SBX_BI.D_REGISTRATION_REPORTING_DAILY_REFACTORED a
WHERE
	REGISTRATION_DT::DATE >= '2026-01-01'
	AND PLAYER_ID IS NOT NULL
GROUP BY ALL













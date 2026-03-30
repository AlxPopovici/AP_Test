/*
SELECT * FROM PROd.DM_MARTECH.D_REGISTRATION_REPORTING_DAILY drrd WHERE drrd.MARKETING_SOURCE_NAME = '174' LIMIT 100;
select * from prod.dm_martech.vw_f_acq_channel_performance limit 10;
select * from prod.dm_martech.vw_f_campaign_acq_channel_performance limit 10;
SELECT * FROM prod.dm_martech.vw_player_reg_attribution LIMIT 100;
*/

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
          PROD.DWH.D_BUSINESS_MARKET dbm 
				ON asdk.BUSINESS_MARKET_ID = dbm.BUSINESS_MARKET_ID                                                                                                                                                                                                          
      WHERE                                                                                                                                                                                                                                                                                           
          asdk.REGISTRATION_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')   -- one day extra to cover for timezone conversion                                                                                                                                                                                                  
          OR asdk.FIRST_TIME_DEPOSIT_DT >= LAST_DAY(DATEADD('YEAR', -3, CURRENT_DATE()), 'YEAR')                                                                                                                                                                                                      
  ) 
-- keep last tenure only at player level
  ,LTV AS (                                                                                                                                                                                                                                                                           
      SELECT PLAYER_ID,                                                                                                                                                                                                                                                                                  
          COALESCE(TOTAL_PREDICTION, 0) AS LTV                                                                                                                                                                                                                                                        
      FROM PROD.DS.LTV_ACQUISITION                                                                                                                                                                                                                                                                     
      QUALIFY                                                                                                                                                                                                                                                                                         
          ROW_NUMBER() OVER (PARTITION BY PLAYER_ID ORDER BY TENURE DESC, INSERTTIMESTAMP DESC) = 1                                                                                                                                                                                                   
  )
-- fetch relevant last year's performance data(EUR) for converted players(FTDs) only 
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
  )
-- stich LTV and performance data to player base
	,BASE AS (                                                                                                                                                                                                                                                                                    
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
-- regs aggregation matching ASDK granularity
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
  )
-- ftds aggregation matching ASDK granularity + performance metrics attributed to conversions
 ,CTE_FTDS AS (                                                                                                                                                                                                                                                                                      
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
  )
-- unique dimensions across tables
	,CTE_ALL_KEYS AS (                                                                                                                                                                                                                                                                                  
      SELECT BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED FROM CTE_REGISTRATIONS                                                                                                   
      UNION                                                                                                                                                                                                                                                                                           
      SELECT BUSINESS_DOMAIN_ID, EVENT_DATE, FINAL_ACQUISITION_SOURCE_GROUP, FINAL_ACQUISITION_CHANNEL, FINAL_ACQUISITION_SUBCHANNEL, FINAL_PLATFORM_TYPE, FINAL_AD_PLATFORM, FINAL_MAPPING_USED FROM CTE_FTDS                                                                                                            
  )
-- final stitching
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



-- DQ: 
	
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








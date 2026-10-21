-- Monthly activity states. Logic lives in macros/player_activity_states.sql.
-- Same logic as weekly, all domains. The original SQL had a stray BUSINESS_DOMAIN_ID = 16 filter here (a mistake, dropped).
{{ player_activity_states('MONTH') }}

-- Renders the original query (see macros/original_affiliate_activity_query.sql) for use in a Snowflake worksheet.
-- dbt compile writes the plain SQL to target/compiled/affiliate_activity/analyses/original_query.sql
{{ original_affiliate_activity_query() }}

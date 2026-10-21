{#
    Prefix every object with DBT_ so nothing built here can collide with existing objects in PROD.SBX_BI.
    stg_unified_dates                -> DBT_STG_UNIFIED_DATES
    int_player_base                  -> DBT_INT_PLAYER_BASE
    dbt_affiliate_player_activity    -> DBT_AFFILIATE_PLAYER_ACTIVITY (already prefixed, left as is)
#}
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- set base_name = custom_alias_name | trim if custom_alias_name else node.name -%}
    {%- if base_name.startswith('dbt_') -%}
        {{ base_name }}
    {%- else -%}
        dbt_{{ base_name }}
    {%- endif -%}
{%- endmacro %}

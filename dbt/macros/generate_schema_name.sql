{#
    Use the target schema as-is (SBX_BI) instead of dbt's default <target>_<custom> concatenation.
    All models in this project are meant to land in PROD.SBX_BI.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}

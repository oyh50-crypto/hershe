{% macro ga4_string_param(param_key) -%}
    (select value.string_value from unnest(event_params) where key = '{{ param_key }}')
{%- endmacro %}

{% macro ga4_int_param(param_key) -%}
    (select value.int_value from unnest(event_params) where key = '{{ param_key }}')
{%- endmacro %}

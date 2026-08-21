{% macro funnel_step_order(event_name_col) -%}
    case {{ event_name_col }}
    {% for step in var('funnel_steps') -%}
        when '{{ step }}' then {{ loop.index }}
    {% endfor -%}
    end
{%- endmacro %}

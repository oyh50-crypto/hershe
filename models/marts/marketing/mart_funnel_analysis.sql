-- Grain: date x channel x funnel step. The core deliverable for funnel/drop-off analysis.
with step_counts as (

    select
        event_date,
        channel_group,
        step_name,
        step_order,
        count(distinct session_id) as sessions
    from {{ ref('fct_funnel_steps') }}
    group by 1, 2, 3, 4

)

select
    *,
    lag(sessions) over (partition by event_date, channel_group order by step_order) as prev_step_sessions,
    safe_divide(
        sessions,
        lag(sessions) over (partition by event_date, channel_group order by step_order)
    ) as step_conversion_rate,
    safe_divide(
        sessions,
        first_value(sessions) over (partition by event_date, channel_group order by step_order)
    ) as overall_conversion_rate
from step_counts

with events as (

    select * from {{ ref('stg_ga4__events') }}

),

funnel_events as (

    select
        session_id,
        user_pseudo_id,
        event_date,
        event_name,
        min(event_timestamp) as step_timestamp
    from events
    where event_name in ({{ "'" ~ var('funnel_steps') | join("', '") ~ "'" }})
    group by 1, 2, 3, 4

)

select
    *,
    {{ funnel_step_order('event_name') }} as step_order
from funnel_events

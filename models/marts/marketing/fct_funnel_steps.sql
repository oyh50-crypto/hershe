-- Grain: one row per session per funnel step actually reached.
with sessions as (

    select session_id, channel_group, event_date
    from {{ ref('int_ga4__sessions') }}

),

funnel as (

    select * from {{ ref('int_ga4__funnel_events') }}

)

select
    s.session_id,
    s.event_date,
    s.channel_group,
    f.event_name as step_name,
    f.step_order,
    f.step_timestamp
from sessions s
inner join funnel f using (session_id)

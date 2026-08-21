with events as (

    select
        *,
        row_number() over (
            partition by session_id
            order by case when traffic_source is not null then 0 else 1 end, event_timestamp
        ) as traffic_rn,
        row_number() over (partition by session_id order by event_timestamp) as event_rn
    from {{ ref('stg_ga4__events') }}

),

session_traffic as (

    select session_id, traffic_source, traffic_medium, traffic_campaign
    from events
    where traffic_rn = 1

),

session_landing as (

    select session_id, page_location as landing_page
    from events
    where event_rn = 1

),

session_agg as (

    select
        session_id,
        any_value(user_pseudo_id) as user_pseudo_id,
        max(user_id) as user_id,
        min(event_date) as event_date,
        min(event_timestamp) as session_start,
        max(event_timestamp) as session_end,
        timestamp_diff(max(event_timestamp), min(event_timestamp), second) as session_duration_sec,
        sum(engagement_time_msec) / 1000 as engagement_time_sec,
        max(session_engaged) as session_engaged,
        any_value(device_category) as device_category,
        any_value(device_os) as device_os,
        any_value(geo_country) as geo_country,
        max(if(event_name = 'purchase', 1, 0)) as is_purchase_session,
        max(transaction_id) as transaction_id,
        sum(if(event_name = 'purchase', purchase_revenue, 0)) as purchase_revenue
    from events
    group by session_id

)

select
    s.*,
    t.traffic_source,
    t.traffic_medium,
    t.traffic_campaign,
    l.landing_page,
    {{ default_channel_grouping('t.traffic_source', 't.traffic_medium', 't.traffic_campaign') }} as channel_group
from session_agg s
left join session_traffic t using (session_id)
left join session_landing l using (session_id)

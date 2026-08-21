-- Grain: date x channel. Ties ad spend to sessions/conversions for CPA/ROAS reporting.
with ad_spend as (

    select
        date,
        channel_group,
        sum(cost) as ad_cost,
        sum(impressions) as impressions,
        sum(clicks) as clicks
    from {{ ref('int_ads__performance_unioned') }}
    group by 1, 2

),

sessions as (

    select
        event_date as date,
        channel_group,
        count(distinct session_id) as sessions,
        countif(is_purchase_session = 1) as purchase_sessions,
        sum(purchase_revenue) as revenue
    from {{ ref('fct_sessions') }}
    group by 1, 2

)

select
    coalesce(a.date, s.date) as date,
    coalesce(a.channel_group, s.channel_group) as channel_group,
    a.ad_cost,
    a.impressions,
    a.clicks,
    s.sessions,
    s.purchase_sessions,
    s.revenue,
    safe_divide(a.ad_cost, a.clicks) as cpc,
    safe_divide(s.purchase_sessions, s.sessions) as session_cvr,
    safe_divide(s.revenue, a.ad_cost) as roas,
    safe_divide(a.ad_cost, s.purchase_sessions) as cpa
from ad_spend a
full outer join sessions s using (date, channel_group)

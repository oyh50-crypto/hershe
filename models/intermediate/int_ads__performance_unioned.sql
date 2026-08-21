with google_ads as (

    select
        date,
        'Google Ads' as platform,
        campaign_id,
        campaign_name,
        {{ default_channel_grouping("'google'", "'cpc'", 'campaign_name') }} as channel_group,
        impressions,
        clicks,
        cost,
        conversions
    from {{ ref('stg_google_ads__performance') }}

),

meta_ads as (

    select
        date,
        'Meta Ads' as platform,
        campaign_id,
        campaign_name,
        {{ default_channel_grouping("'facebook'", "'paid_social'", 'campaign_name') }} as channel_group,
        impressions,
        clicks,
        cost,
        conversions
    from {{ ref('stg_meta_ads__performance') }}

)

select * from google_ads
union all
select * from meta_ads

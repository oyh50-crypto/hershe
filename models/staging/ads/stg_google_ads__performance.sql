-- TODO: rename source columns below to match the real connector schema.
with source as (

    select * from {{ source('ads', 'google_ads_performance') }}

),

renamed as (

    select
        date,
        campaign_id,
        campaign_name,
        impressions,
        clicks,
        cost_micros / 1e6 as cost,
        conversions

    from source

)

select * from renamed

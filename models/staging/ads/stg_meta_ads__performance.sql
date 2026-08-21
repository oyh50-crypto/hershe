-- TODO: rename source columns below to match the real connector schema.
with source as (

    select * from {{ source('ads', 'meta_ads_performance') }}

),

renamed as (

    select
        date,
        campaign_id,
        campaign_name,
        impressions,
        clicks,
        spend as cost,
        conversions

    from source

)

select * from renamed

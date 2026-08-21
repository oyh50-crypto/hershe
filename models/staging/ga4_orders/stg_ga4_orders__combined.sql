-- TODO: rename source columns below to match the real combined_orders table.
with source as (

    select * from {{ source('ga4_orders', 'combined_orders') }}

),

renamed as (

    select
        order_id,
        session_id,
        traffic_source as channel_source,
        traffic_medium as channel_medium,
        traffic_campaign as campaign

    from source

)

select * from renamed

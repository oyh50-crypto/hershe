with source as (

    select * from {{ source('ga4', 'events') }}

),

unnested as (

    select
        concat(user_pseudo_id, '-', cast({{ ga4_int_param('ga_session_id') }} as string)) as session_id,
        event_name,
        timestamp_micros(event_timestamp) as event_timestamp,
        item.item_id,
        item.item_name,
        item.item_category,
        item.price_in_usd,
        item.quantity,
        item.item_revenue_in_usd

    from source, unnest(items) as item

)

select * from unnested

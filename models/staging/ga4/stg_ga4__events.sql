with source as (

    select * from {{ source('ga4', 'events') }}

),

renamed as (

    select
        parse_date('%Y%m%d', event_date) as event_date,
        timestamp_micros(event_timestamp) as event_timestamp,
        event_name,
        user_pseudo_id,
        user_id,
        concat(user_pseudo_id, '-', cast({{ ga4_int_param('ga_session_id') }} as string)) as session_id,
        {{ ga4_int_param('ga_session_number') }} as session_number,
        {{ ga4_string_param('page_location') }} as page_location,
        {{ ga4_string_param('page_title') }} as page_title,
        {{ ga4_string_param('page_referrer') }} as page_referrer,
        {{ ga4_int_param('engagement_time_msec') }} as engagement_time_msec,
        {{ ga4_int_param('session_engaged') }} as session_engaged,
        coalesce({{ ga4_string_param('source') }}, traffic_source.source) as traffic_source,
        coalesce({{ ga4_string_param('medium') }}, traffic_source.medium) as traffic_medium,
        {{ ga4_string_param('campaign') }} as traffic_campaign,
        device.category as device_category,
        device.operating_system as device_os,
        device.web_info.browser as device_browser,
        geo.country as geo_country,
        geo.region as geo_region,
        geo.city as geo_city,
        ecommerce.transaction_id as transaction_id,
        ecommerce.purchase_revenue as purchase_revenue,
        platform

    from source

)

select * from renamed

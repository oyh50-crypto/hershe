with orders as (

    select * from {{ ref('stg_crm__orders') }}

),

attribution as (

    select * from {{ ref('stg_ga4_orders__combined') }}

)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.order_amount,
    a.session_id,
    a.channel_source,
    a.channel_medium,
    a.campaign,
    {{ default_channel_grouping('a.channel_source', 'a.channel_medium', 'a.campaign') }} as channel_group
from orders o
left join attribution a using (order_id)

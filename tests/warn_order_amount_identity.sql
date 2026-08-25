{{ config(severity = 'warn', warn_if = '> 80') }}

-- Monitors the order-level identity the whole model rests on:
--
--     list - points - coupon - (membership + additional + app) + shipping
--       = payment_amount
--
-- Measured at 6646 of 6706 uncancelled orders (99.1%), so ~60 orders are
-- expected to fail. The threshold warns only if that count grows, which would
-- mean the export changed or a new discount type appeared.
--
-- Partially cancelled orders are excluded: initial_order_amount_* is the
-- original order amount while payment_amount reflects the cancellation, so they
-- cannot tie out by construction.

with order_items as (

    select * from {{ ref('stg_crm__cafe24_order_items') }}

),

per_order as (

    select
        order_id,
        any_value(order_gross_amount)      as gross,
        any_value(order_points_amount)     as points,
        any_value(order_coupon_amount)     as coupon,
        any_value(order_membership_amount) as membership,
        any_value(order_payment_amount)    as payment,
        sum(shipping_fee_amount)           as shipping,
        sum(item_discount)                 as item_discount,
        count(*)                           as n_items,
        countif(starts_with(order_status, 'N')) as n_normal,
        logical_or(is_paid_flag = 'T')     as any_paid
    from order_items
    group by order_id

)

select
    order_id,
    gross, points, coupon, membership, item_discount, shipping, payment,
    (gross - points - coupon - (membership + item_discount) + shipping) - payment as gap

from per_order

where any_paid
  and n_items = n_normal
  and abs((gross - points - coupon - (membership + item_discount) + shipping) - payment) > 1

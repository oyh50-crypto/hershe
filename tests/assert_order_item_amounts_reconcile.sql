-- The mart's three amount columns must sum to the item's list product amount.
-- item_paid_amount is the difference of the other two, so this holds by
-- construction — the test guards a future edit from breaking it, and catches a
-- negative discount (which would mean the item was paid above list price).

with mart as (

    select * from {{ ref('mart_order_items') }}

),

gross as (

    select
        order_item_code as items_order_item_code,
        item_gross_amount
    from {{ ref('stg_crm__cafe24_order_items') }}

)

select
    m.items_order_item_code,
    m.item_paid_amount,
    m.point_coupon_used_amount,
    m.discount_amount,
    g.item_gross_amount

from mart m
join gross g using (items_order_item_code)

where abs(
        (m.item_paid_amount + m.point_coupon_used_amount + m.discount_amount)
        - g.item_gross_amount
      ) > 0.01
   or m.discount_amount < 0

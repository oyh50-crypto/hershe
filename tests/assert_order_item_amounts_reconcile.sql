-- The mart's three amount columns must sum to the item's list product amount.
-- discount_amount is the residual, so this holds by construction — the test
-- guards against a future edit breaking that, and flags rows where the residual
-- goes negative (which would mean the item was paid for above list price).

with mart as (

    select * from {{ ref('mart_order_items') }}

),

gross as (

    select
        order_item_code as items_order_item_code,
        gross_amount
    from {{ ref('stg_crm__cafe24_order_items') }}

)

select
    m.items_order_item_code,
    m.item_paid_amount,
    m.point_coupon_used_amount,
    m.discount_amount,
    g.gross_amount

from mart m
join gross g using (items_order_item_code)

where abs(
        (m.item_paid_amount + m.point_coupon_used_amount + m.discount_amount)
        - g.gross_amount
      ) > 0.01
   or m.discount_amount < 0

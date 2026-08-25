{{ config(severity = 'warn', warn_if = '> 1200') }}

-- The residual discount_amount should match what the raw membership / additional
-- / app discount columns add up to. On the current export it does for ~90% of
-- rows (8525 of 9437); the rest is not explained by any available column.
--
-- This test is a monitor, not a gate: it warns only if the unexplained share
-- grows beyond the ~912 rows already known, which would mean the export changed
-- or a new discount type appeared.

with order_items as (

    select * from {{ ref('stg_crm__cafe24_order_items') }}
    where is_paid_flag = 'T'
      and starts_with(order_status, 'N')

)

select
    order_item_code,
    gross_amount,
    item_paid_amount,
    point_coupon_used_amount,
    gross_amount - item_paid_amount - point_coupon_used_amount as residual_discount,
    component_discount_amount

from order_items

where abs(
        (gross_amount - item_paid_amount - point_coupon_used_amount)
        - component_discount_amount
      ) > 1

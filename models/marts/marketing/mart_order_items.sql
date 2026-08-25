{{
    config(
        materialized = 'table',
        partition_by = {'field': 'TB_DATE', 'data_type': 'date'},
        cluster_by = ['full_category_name_1', 'member_id']
    )
}}

-- Analysis-ready order item table.
--
-- The three amount columns are mutually exclusive and add up to the item's list
-- (pre-discount) product amount:
--
--     item_paid_amount + point_coupon_used_amount + discount_amount
--       = item_gross_amount
--
-- item_paid_amount is the difference, so the identity survives rounding. Summed
-- per order it equals payment_amount less shipping, because the staging model
-- apportions the order-level amounts from the verified order identity rather
-- than from the pipeline's div_payment_amount.
--
-- Known limitation: partially cancelled orders (~0.5%) cannot tie out, since
-- initial_order_amount_* is the original order amount while payment_amount
-- already reflects the cancellation.

with order_items as (

    select * from {{ ref('stg_crm__cafe24_order_items') }}

    -- Paid, non-cancelled items only. Cancel (C*), return (R*) and exchange (E*)
    -- statuses are dropped rather than signed negative — revisit if net revenue
    -- including reversals is needed.
    where is_paid_flag = 'T'
      and starts_with(order_status, 'N')

)

select
    order_date                                                   as TB_DATE,
    order_id,
    order_item_code                                              as items_order_item_code,
    member_id,

    item_gross_amount - point_coupon_used_amount - discount_amount as item_paid_amount,
    point_coupon_used_amount,
    discount_amount,

    full_category_name_1,
    full_category_name_2

from order_items

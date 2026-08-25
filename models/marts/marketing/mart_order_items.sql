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
--       = div_initial_order_amount_order_price_amount (apportioned to this item)
--
-- item_paid_amount is derived as the residual, so the identity always holds
-- exactly. Shipping is excluded — it is not product revenue. See the
-- assert_order_item_amounts_reconcile test for the tie-out against the source's
-- own items_payment_amount.

with order_items as (

    select * from {{ ref('stg_crm__cafe24_order_items') }}

    -- Paid, non-cancelled orders only. Cancel (C*), return (R*) and exchange (E*)
    -- statuses are excluded rather than signed negative — revisit if net revenue
    -- including reversals is needed.
    where is_paid_flag = 'T'
      and starts_with(order_status, 'N')

)

select
    order_date                                                  as TB_DATE,
    order_id,
    order_item_code                                             as items_order_item_code,
    member_id,

    gross_amount - point_coupon_used_amount - discount_amount   as item_paid_amount,
    point_coupon_used_amount,
    discount_amount,

    full_category_name_1,
    full_category_name_2

from order_items

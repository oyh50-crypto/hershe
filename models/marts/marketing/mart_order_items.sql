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
--     item_paid_amount + point_coupon_used_amount + discount_amount = gross_amount
--
-- item_paid_amount and point_coupon_used_amount come straight from validated
-- source columns; discount_amount is the residual, so the identity always holds
-- exactly. Shipping is excluded — it is not product revenue.
--
-- The raw membership/additional/app discount columns reproduce that residual on
-- 90% of rows; the remaining 10% is unexplained by any available column, so the
-- residual absorbs it rather than corrupting the paid amount. See
-- analyses/order_item_amounts_gap_profile.sql for the ongoing investigation and
-- warn_order_item_discount_residual for the monitoring test.

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

    item_paid_amount,
    point_coupon_used_amount,
    gross_amount - item_paid_amount - point_coupon_used_amount  as discount_amount,

    full_category_name_1,
    full_category_name_2

from order_items

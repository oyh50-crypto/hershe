-- The mart derives item_paid_amount as a residual so that the three amount
-- columns always sum to the list price. This test checks that the derived figure
-- also agrees with the amount Cafe24 itself reports for the item, which is what
-- proves the discount buckets are complete: if a discount type is missing from a
-- bucket, the residual drifts away from the source figure.
--
-- Tolerance is 1 KRW per item to absorb rounding in the apportioned columns.

select
    order_item_code,
    gross_amount,
    point_coupon_used_amount,
    discount_amount,
    gross_amount - point_coupon_used_amount - discount_amount as derived_paid_amount,
    src_item_paid_amount

from {{ ref('stg_crm__cafe24_order_items') }}

where is_paid_flag = 'T'
  and starts_with(order_status, 'N')
  and abs(
        (gross_amount - point_coupon_used_amount - discount_amount)
        - src_item_paid_amount
      ) > 1

{{
    config(
        materialized = 'view'
    )
}}

-- One row per Cafe24 order item, deduplicated and type-cast, with the order-level
-- amounts apportioned down to the item.
--
-- The amount identity is an ORDER-level one — payment_amount is a plain order
-- column repeated across the item rows, not an apportioned one:
--
--     list - points - coupon - (membership + additional + app) + shipping
--       = payment_amount
--
-- It holds on 6646 of 6706 uncancelled orders (99.1%). So rather than trusting
-- the pipeline's div_payment_amount, this model apportions the order-level terms
-- itself, using each item's share of the apportioned list amount as the weight.
-- That makes sum(item_paid_amount) per order equal payment_amount less shipping.

with source as (

    select * from {{ source('crm', 'cafe24_orders') }}

),

deduped as (

    -- The export is snapshot-based, so the same order item can appear under
    -- several query_date values. Keep the most recently observed state.
    select * from source
    qualify row_number() over (
        partition by items_order_item_code
        order by query_date desc
    ) = 1

),

typed as (

    select
        TB_DATE                                                        as order_date,
        order_id,
        items_order_item_code                                          as order_item_code,
        nullif(trim(member_id), '')                                    as member_id,
        items_product_no                                               as product_no,
        items_product_name                                             as product_name,
        full_category_name_1,
        full_category_name_2,
        paid                                                           as is_paid_flag,
        items_order_status                                             as order_status,
        order_place_name,
        items_quantity                                                 as quantity,

        -- weight basis for apportioning the order-level amounts
        cast(coalesce(div_initial_order_amount_order_price_amount, 0) as numeric)
                                                                       as weight_base,

        -- item-level discounts. These are totals, not per-unit: multiplying by
        -- quantity makes the order identity fit worse (6641 vs 6646).
        coalesce(safe_cast(items_additional_discount_price as numeric), 0)
      + coalesce(safe_cast(items_app_item_discount_amount  as numeric), 0)
                                                                       as item_discount,

        -- order-level amounts, repeated on every item row of the order
        safe_cast(initial_order_amount_order_price_amount         as numeric) as order_gross_amount,
        safe_cast(initial_order_amount_points_spent_amount        as numeric) as order_points_amount,
        safe_cast(initial_order_amount_coupon_discount_price      as numeric) as order_coupon_amount,
        safe_cast(initial_order_amount_membership_discount_amount as numeric) as order_membership_amount,
        safe_cast(payment_amount                                  as numeric) as order_payment_amount,
        cast(coalesce(shipping_fee_detail_shipping_fee_divided, 0) as numeric) as shipping_fee_amount

    from deduped

),

weighted as (

    -- The denominator spans every item of the order, cancelled ones included:
    -- the order-level amounts cover them too.
    select
        *,
        sum(weight_base) over (partition by order_id) as order_weight_base,
        count(*)         over (partition by order_id) as order_item_count
    from typed

),

allocated as (

    select
        * except (order_weight_base, order_item_count),

        -- orders whose list amount is zero fall back to an even split
        case
            when order_weight_base > 0 then weight_base / order_weight_base
            else 1 / order_item_count
        end as allocation_weight
    from weighted

)

select
    * except (allocation_weight),

    -- rounded once here so the mart's three columns stay exactly additive
    round(order_gross_amount * allocation_weight, 2)                       as item_gross_amount,
    round((order_points_amount + order_coupon_amount) * allocation_weight, 2)
                                                                           as point_coupon_used_amount,
    round(order_membership_amount * allocation_weight + item_discount, 2)  as discount_amount

from allocated

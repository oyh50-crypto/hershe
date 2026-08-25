{{
    config(
        materialized = 'view'
    )
}}

-- One row per Cafe24 order item, deduplicated and type-cast.
-- Amounts arrive from the API as strings; the `*_divided` / `div_*` columns are
-- order-level amounts already apportioned across the order's items, so they are
-- the ones that are safe to SUM at this grain.

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

renamed as (

    select
        -- keys
        TB_DATE                                                        as order_date,
        order_id,
        items_order_item_code                                          as order_item_code,
        nullif(trim(member_id), '')                                    as member_id,
        items_product_no                                               as product_no,
        items_product_name                                             as product_name,
        full_category_name_1,
        full_category_name_2,

        -- status
        paid                                                           as is_paid_flag,
        items_order_status                                             as order_status,
        order_place_name,
        items_quantity                                                 as quantity,

        -- gross: the order's product amount apportioned to this item
        cast(coalesce(div_initial_order_amount_order_price_amount, 0) as numeric)
                                                                       as gross_amount,

        -- bucket B — points and coupons actually spent by the customer
        cast(coalesce(initial_order_amount_points_spent_amount_divided,   0) as numeric)
      + cast(coalesce(initial_order_amount_coupon_discount_price_divided, 0) as numeric)
      + coalesce(safe_cast(items_coupon_discount_price as numeric),         0)
                                                                       as point_coupon_used_amount,

        -- bucket C — membership tier / product-level / app discounts
        cast(coalesce(initial_order_amount_membership_discount_amount_divided, 0) as numeric)
      + coalesce(safe_cast(items_additional_discount_price as numeric),        0)
      + coalesce(safe_cast(items_app_item_discount_amount  as numeric),        0)
                                                                       as discount_amount,

        cast(coalesce(shipping_fee_detail_shipping_fee_divided, 0) as numeric)
                                                                       as shipping_fee_amount,

        -- kept so the reconciliation test can compare against the source's own figure
        coalesce(safe_cast(items_payment_amount as numeric), 0)        as src_item_paid_amount

    from deduped

)

select * from renamed

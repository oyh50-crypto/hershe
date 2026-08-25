-- =============================================================================
-- 정합성 검증 쿼리 — order_item_amounts.sql 를 운영에 올리기 전에 1회 실행하세요.
--
--   A. 파생 실결제액 vs 원천 items_payment_amount
--   B. 파생 실결제액 vs div_payment_amount (배송비 포함 여부 확인)
--   C. 주문 단위 안분 합계 vs 주문 총상품금액
--   D. discounted_amount 의 정체 파악 (버킷 B+C 합과 비교 / 실결제액과 비교)
--   E. TB_DATE 가 주문일 기준인지 확인
--
-- rows_ok 가 rows_checked 와 (거의) 같으면 그 가설이 맞습니다.
-- =============================================================================

with src as (
    select *
    from `your-gcp-project.crm_raw.cafe24_orders`      -- TODO: 실제 경로로 교체
    qualify row_number() over (
        partition by items_order_item_code order by query_date desc
    ) = 1
),

calc as (
    select
        TB_DATE,
        order_id,
        items_order_item_code,

        cast(coalesce(div_initial_order_amount_order_price_amount, 0) as numeric) as gross_amount,

        cast(coalesce(initial_order_amount_points_spent_amount_divided,   0) as numeric)
      + cast(coalesce(initial_order_amount_coupon_discount_price_divided, 0) as numeric)
      + coalesce(safe_cast(items_coupon_discount_price as numeric), 0)          as bucket_b,

        cast(coalesce(initial_order_amount_membership_discount_amount_divided, 0) as numeric)
      + coalesce(safe_cast(items_additional_discount_price as numeric), 0)
      + coalesce(safe_cast(items_app_item_discount_amount  as numeric), 0)      as bucket_c,

        coalesce(safe_cast(items_payment_amount as numeric), 0)                 as src_item_paid,
        cast(coalesce(div_payment_amount, 0) as numeric)                        as div_paid,
        cast(coalesce(shipping_fee_detail_shipping_fee_divided, 0) as numeric)  as ship_divided,
        cast(coalesce(discounted_amount, 0) as numeric)                         as discounted_amount,
        safe_cast(initial_order_amount_order_price_amount as numeric)           as order_gross,
        date(coalesce(
            safe.parse_timestamp('%Y-%m-%dT%H:%M:%S%Ez', order_date),
            safe.parse_timestamp('%Y-%m-%d %H:%M:%S',    order_date)
        ), 'Asia/Seoul')                                                        as order_date_kst
    from src
    where paid = 'T' and starts_with(items_order_status, 'N')
),

derived as (
    select *, gross_amount - bucket_b - bucket_c as item_paid
    from calc
),

item_checks as (
    select 'A. item_paid = items_payment_amount'            as check_name,
           count(*) as rows_checked,
           countif(abs(item_paid - src_item_paid) <= 1)     as rows_ok,
           round(max(abs(item_paid - src_item_paid)), 2)    as max_abs_diff
    from derived
    union all
    select 'B. item_paid + shipping = div_payment_amount',
           count(*),
           countif(abs(item_paid + ship_divided - div_paid) <= 1),
           round(max(abs(item_paid + ship_divided - div_paid)), 2)
    from derived
    union all
    select 'D1. discounted_amount = bucket_b + bucket_c (할인액 가설)',
           count(*),
           countif(abs(discounted_amount - (bucket_b + bucket_c)) <= 1),
           round(max(abs(discounted_amount - (bucket_b + bucket_c))), 2)
    from derived
    union all
    select 'D2. discounted_amount = item_paid (할인후금액 가설)',
           count(*),
           countif(abs(discounted_amount - item_paid) <= 1),
           round(max(abs(discounted_amount - item_paid)), 2)
    from derived
    union all
    select 'E. TB_DATE = date(order_date, KST)',
           count(*),
           countif(TB_DATE = order_date_kst),
           null
    from derived
),

order_check as (
    select 'C. sum(div gross) = order gross' as check_name,
           count(*) as rows_checked,
           countif(abs(gross_sum - order_gross) <= 1) as rows_ok,
           round(max(abs(gross_sum - order_gross)), 2) as max_abs_diff
    from (
        select order_id, sum(gross_amount) as gross_sum, max(order_gross) as order_gross
        from derived group by order_id
    )
)

select * from item_checks
union all select * from order_check
order by check_name

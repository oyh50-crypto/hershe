-- =============================================================================
-- 분석용 주문 품목 테이블 (Cafe24 CRM)
--
-- grain : 주문 품목 1건 (items_order_item_code)
--         원본이 이미 주문 + 품목 + 상품마스터 + 카테고리를 평탄화한 단일 테이블이라
--         별도 조인 없이 만들 수 있습니다.
--
-- 금액 정합성 규칙
--   item_paid_amount + point_coupon_used_amount + discount_amount = gross_amount
--     gross_amount = div_initial_order_amount_order_price_amount (안분 정가 상품금액)
--   → 세 컬럼이 상호배타적이고, 합이 정가금액이 되도록 설계.
--     item_paid_amount 를 잔차로 계산하므로 합은 항상 정확히 일치합니다.
--     (배송비는 상품 매출이 아니므로 제외 — 포함하려면 아래 주석 참고)
-- =============================================================================

with

src as (
    select *
    from `your-gcp-project.crm_raw.cafe24_orders`      -- TODO: 실제 경로로 교체
),

-- 스냅샷 적재라 같은 품목이 여러 query_date 로 존재할 수 있음 → 최신분만 -----------
deduped as (
    select * from src
    qualify row_number() over (
        partition by items_order_item_code
        order by query_date desc
    ) = 1
),

typed as (
    select
        TB_DATE,
        order_id,
        items_order_item_code,
        nullif(trim(member_id), '')                                  as member_id,

        -- ── 기준금액(정가, 안분) ─────────────────────────────────────────────
        cast(coalesce(div_initial_order_amount_order_price_amount, 0) as numeric)
                                                                     as gross_amount,

        -- ── 버킷 B : 적립금 + 쿠폰 사용액 ────────────────────────────────────
        --    주문 단위 금액은 안분값(_divided), 품목 단위 금액은 원본 사용
        cast(coalesce(initial_order_amount_points_spent_amount_divided,   0) as numeric)
      + cast(coalesce(initial_order_amount_coupon_discount_price_divided, 0) as numeric)
      + coalesce(safe_cast(items_coupon_discount_price as numeric),         0)
                                                                     as point_coupon_used_amount,

        -- ── 버킷 C : 회원등급할인 + 상품추가할인 + 기타(앱)할인 ───────────────
        cast(coalesce(initial_order_amount_membership_discount_amount_divided, 0) as numeric)
      + coalesce(safe_cast(items_additional_discount_price as numeric),        0)
      + coalesce(safe_cast(items_app_item_discount_amount  as numeric),        0)
                                                                     as discount_amount,

        full_category_name_1,
        full_category_name_2

    from deduped
    where paid = 'T'                                  -- 결제 완료 건만
      and starts_with(items_order_status, 'N')        -- 정상 주문만 (C 취소 / R 반품 / E 교환 제외)
      -- 취소·반품을 음수 매출로 반영하려면 위 두 줄 대신 상태별 부호 처리 로직을 넣으세요.
)

select
    TB_DATE,
    order_id,
    items_order_item_code,
    member_id,

    -- 실결제액 = 정가 − 적립금/쿠폰 − 할인  (잔차 계산 → 세 컬럼 합 = gross_amount)
    gross_amount - point_coupon_used_amount - discount_amount        as item_paid_amount,
    point_coupon_used_amount,
    discount_amount,

    full_category_name_1,
    full_category_name_2

from typed
order by TB_DATE, order_id, items_order_item_code

-- 배송비까지 포함한 "실제 입금액" 기준이 필요하면 위 select 에 아래를 추가하세요.
--   cast(coalesce(shipping_fee_detail_shipping_fee_divided, 0) as numeric) as shipping_fee_amount
-- 이 경우 정합식은  item_paid_amount + shipping_fee_amount = div_payment_amount  가 됩니다.

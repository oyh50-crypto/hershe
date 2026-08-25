-- =============================================================================
-- 주문 레벨 정합식 검증
--
--   정가 - 적립금 - 쿠폰 - 할인 + 배송비 = payment_amount   (payment_amount 는 주문 단위 원본)
--
-- 할인 항목만 미지수로 두고 역산한 뒤, 후보 조합과 비교합니다.
--   implied_discount = 정가 - 적립금 - 쿠폰 + 배송비 - payment_amount
--
-- 주문 단위 컬럼(initial_order_amount_*, payment_amount)은 품목 행마다 반복되므로
-- ANY_VALUE, 품목 단위 컬럼은 SUM 으로 집계합니다.
-- =============================================================================

WITH deduped AS (
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (PARTITION BY items_order_item_code ORDER BY query_date DESC) = 1
),

o AS (
  SELECT
    order_id,
    -- 주문 단위 원본 (품목 행마다 동일값 반복)
    SAFE_CAST(ANY_VALUE(initial_order_amount_order_price_amount)            AS NUMERIC) AS gross,
    SAFE_CAST(ANY_VALUE(initial_order_amount_points_spent_amount)           AS NUMERIC) AS pts,
    SAFE_CAST(ANY_VALUE(initial_order_amount_coupon_discount_price)         AS NUMERIC) AS cpn,
    SAFE_CAST(ANY_VALUE(initial_order_amount_membership_discount_amount)    AS NUMERIC) AS mbr,
    SAFE_CAST(ANY_VALUE(payment_amount)                                     AS NUMERIC) AS pay,
    COALESCE(SAFE_CAST(ANY_VALUE(naver_point) AS NUMERIC), 0)                           AS nv_point,

    -- 품목 단위 컬럼 → 주문 합계 (배송비 안분값의 합 = 주문 배송비)
    SUM(CAST(COALESCE(shipping_fee_detail_shipping_fee_divided, 0) AS NUMERIC))         AS ship,
    SUM(COALESCE(SAFE_CAST(items_additional_discount_price AS NUMERIC), 0))             AS add_disc,
    SUM(COALESCE(SAFE_CAST(items_app_item_discount_amount  AS NUMERIC), 0))             AS app_disc,
    SUM(COALESCE(SAFE_CAST(items_coupon_discount_price     AS NUMERIC), 0))             AS cpn_item,
    SUM(COALESCE(SAFE_CAST(items_additional_discount_price AS NUMERIC), 0)
        * COALESCE(items_quantity, 1))                                                  AS add_disc_x_qty,
    SUM(COALESCE(SAFE_CAST(items_app_item_discount_amount AS NUMERIC), 0)
        * COALESCE(items_quantity, 1))                                                  AS app_disc_x_qty,

    COUNT(*)                                                                            AS n_items,
    COUNTIF(STARTS_WITH(items_order_status, 'N'))                                       AS n_normal,
    LOGICAL_OR(paid = 'T')                                                              AS any_paid
  FROM deduped
  GROUP BY order_id
),

y AS (
  SELECT
    *,
    -- 역산한 "할인" 항목
    gross - pts - cpn + ship - pay AS implied_discount
  FROM o
  WHERE any_paid AND n_items = n_normal   -- 부분취소 없는 온전한 주문만 (깨끗한 기준선)
)

SELECT * FROM UNNEST([
  STRUCT('0_orders_checked' AS candidate, (SELECT COUNT(*) FROM y) AS rows_ok),

  -- ── 할인 항목 후보 ────────────────────────────────────────────────────────
  ('d1  등급할인 + 상품추가할인 + 앱할인',
    (SELECT COUNTIF(ABS(implied_discount - (mbr + add_disc + app_disc)) <= 1) FROM y)),
  ('d2  등급할인만',
    (SELECT COUNTIF(ABS(implied_discount - mbr) <= 1) FROM y)),
  ('d3  상품추가할인 + 앱할인만',
    (SELECT COUNTIF(ABS(implied_discount - (add_disc + app_disc)) <= 1) FROM y)),
  ('d4  등급 + 추가 + 앱 + 품목쿠폰',
    (SELECT COUNTIF(ABS(implied_discount - (mbr + add_disc + app_disc + cpn_item)) <= 1) FROM y)),
  ('d5  등급 + (추가+앱) x 수량',
    (SELECT COUNTIF(ABS(implied_discount - (mbr + add_disc_x_qty + app_disc_x_qty)) <= 1) FROM y)),
  ('d6  d1 + 네이버포인트',
    (SELECT COUNTIF(ABS(implied_discount - (mbr + add_disc + app_disc + nv_point)) <= 1) FROM y)),
  ('d7  할인 없음 (implied_discount = 0)',
    (SELECT COUNTIF(ABS(implied_discount) <= 1) FROM y)),

  -- ── 배송비 항목 검증 ──────────────────────────────────────────────────────
  ('s1  배송비 제외해도 d1 성립 (배송비가 이미 포함된 경우)',
    (SELECT COUNTIF(ABS((gross - pts - cpn - pay) - (mbr + add_disc + app_disc)) <= 1) FROM y)),

  -- ── 참고: 역산 할인액이 0 인 주문 비율 ─────────────────────────────────────
  ('r1  implied_discount = 0 인 주문',
    (SELECT COUNTIF(implied_discount = 0) FROM y)),
  ('r2  implied_discount < 0 인 주문',
    (SELECT COUNTIF(implied_discount < 0) FROM y))
])

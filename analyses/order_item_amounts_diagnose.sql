-- =============================================================================
-- 할인 버킷 조합 판별 쿼리
--
-- 검증 결과로 확정된 사실
--   * div_payment_amount - 배송비안분  = 품목 실결제액 (target_paid)
--   * div_initial_order_amount_order_price_amount = 안분 정가금액 (gross)
--   → 따라서 "정답 총할인액" target_disc = gross - target_paid
--
-- 아래는 target_disc 를 어떤 컬럼 조합으로 재현할 수 있는지 후보별 적중 건수를
-- 세는 쿼리입니다. rows_ok 가 rows_checked(9437)에 가장 가까운 조합이 정답.
-- =============================================================================

WITH deduped AS (
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (PARTITION BY items_order_item_code ORDER BY query_date DESC) = 1
),

x AS (
  SELECT
    CAST(COALESCE(div_initial_order_amount_order_price_amount, 0) AS NUMERIC)       AS gross,
    CAST(COALESCE(div_payment_amount, 0) AS NUMERIC)
      - CAST(COALESCE(shipping_fee_detail_shipping_fee_divided, 0) AS NUMERIC)      AS target_paid,

    -- 개별 할인 구성요소
    CAST(COALESCE(initial_order_amount_points_spent_amount_divided,   0) AS NUMERIC) AS pts,
    CAST(COALESCE(initial_order_amount_coupon_discount_price_divided, 0) AS NUMERIC) AS cpn_ord,
    COALESCE(SAFE_CAST(items_coupon_discount_price AS NUMERIC), 0)                   AS cpn_item,
    CAST(COALESCE(initial_order_amount_membership_discount_amount_divided, 0) AS NUMERIC) AS mbr,
    COALESCE(SAFE_CAST(items_additional_discount_price AS NUMERIC), 0)               AS add_disc,
    COALESCE(SAFE_CAST(items_app_item_discount_amount  AS NUMERIC), 0)               AS app_disc,
    CAST(COALESCE(discounted_amount, 0) AS NUMERIC)                                  AS discounted_amount,
    COALESCE(SAFE_CAST(naver_point AS NUMERIC), 0)                                   AS nv_point,

    -- items_payment_amount 정체 파악용 후보들
    COALESCE(SAFE_CAST(items_payment_amount AS NUMERIC), 0)                          AS item_pay,
    (COALESCE(SAFE_CAST(items_product_price AS NUMERIC), 0)
     + COALESCE(SAFE_CAST(items_option_price AS NUMERIC), 0))
     * COALESCE(items_quantity, 0)                                                   AS list_total,
    COALESCE(SAFE_CAST(payment_amount AS NUMERIC), 0)                                AS order_pay,
    COALESCE(items_quantity, 0)                                                      AS qty
  FROM deduped
  WHERE paid = 'T' AND STARTS_WITH(items_order_status, 'N')
),

y AS (SELECT *, gross - target_paid AS target_disc FROM x)

SELECT * FROM UNNEST([
  STRUCT('rows_checked'                                          AS candidate, (SELECT COUNT(*) FROM y) AS rows_ok),

  -- ── 총할인액 조합 후보 (핵심) ───────────────────────────────────────────────
  ('v1  pts+cpn_ord+cpn_item+mbr+add+app (현재안)',
    (SELECT COUNTIF(ABS(pts+cpn_ord+cpn_item+mbr+add_disc+app_disc - target_disc)<=1) FROM y)),
  ('v2  pts+cpn_ord+mbr+add+app  (품목쿠폰 제외)',
    (SELECT COUNTIF(ABS(pts+cpn_ord+mbr+add_disc+app_disc - target_disc)<=1) FROM y)),
  ('v3  pts+cpn_item+mbr+add+app (주문쿠폰 제외)',
    (SELECT COUNTIF(ABS(pts+cpn_item+mbr+add_disc+app_disc - target_disc)<=1) FROM y)),
  ('v4  pts+cpn_ord+mbr          (품목할인 전부 제외)',
    (SELECT COUNTIF(ABS(pts+cpn_ord+mbr - target_disc)<=1) FROM y)),
  ('v5  pts+cpn_ord+cpn_item+add+app (등급할인 제외)',
    (SELECT COUNTIF(ABS(pts+cpn_ord+cpn_item+add_disc+app_disc - target_disc)<=1) FROM y)),
  ('v6  v1 + naver_point',
    (SELECT COUNTIF(ABS(pts+cpn_ord+cpn_item+mbr+add_disc+app_disc+nv_point - target_disc)<=1) FROM y)),
  ('v7  품목할인에 수량 곱한 버전 (단가로 저장된 경우)',
    (SELECT COUNTIF(ABS(pts+cpn_ord+mbr+(cpn_item+add_disc+app_disc)*qty - target_disc)<=1) FROM y)),

  -- ── discounted_amount 정체 ────────────────────────────────────────────────
  ('D1  discounted_amount = target_disc (총할인액)',
    (SELECT COUNTIF(ABS(discounted_amount - target_disc)<=1) FROM y)),
  ('D2  discounted_amount = target_paid (할인후 실결제액)',
    (SELECT COUNTIF(ABS(discounted_amount - target_paid)<=1) FROM y)),
  ('D3  discounted_amount = gross - pts (적립금만 차감)',
    (SELECT COUNTIF(ABS(discounted_amount - (gross - pts))<=1) FROM y)),

  -- ── items_payment_amount 정체 ─────────────────────────────────────────────
  ('P1  items_payment_amount = 정가x수량(list_total)',
    (SELECT COUNTIF(ABS(item_pay - list_total)<=1) FROM y)),
  ('P2  items_payment_amount = gross(안분 정가)',
    (SELECT COUNTIF(ABS(item_pay - gross)<=1) FROM y)),
  ('P3  items_payment_amount = 주문 payment_amount',
    (SELECT COUNTIF(ABS(item_pay - order_pay)<=1) FROM y)),

  -- ── gross 검증 ────────────────────────────────────────────────────────────
  ('G1  gross = 정가x수량 (단일품목 주문에서 성립해야 함)',
    (SELECT COUNTIF(ABS(gross - list_total)<=1) FROM y))
])

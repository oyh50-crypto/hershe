-- =============================================================================
-- 미설명 오차 912건 원인 추적
--
-- 확정 사실: v1 조합(pts+cpn_ord+mbr+add+app)이 최선이나 9.7% 불일치.
--            items_coupon_discount_price / naver_point 는 전량 0인 빈 컬럼.
--            discounted_amount / items_payment_amount 는 정체 불명 → 사용 금지.
--
-- 이 쿼리는 불일치 행이 어떤 세그먼트에 몰려 있는지 long format 으로 집계합니다.
-- ok_pct 가 유독 낮은 세그먼트가 원인입니다.
-- =============================================================================

WITH deduped AS (
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (PARTITION BY items_order_item_code ORDER BY query_date DESC) = 1
),

-- 주문 단위 플래그는 상태 필터 "전에" 계산해야 부분취소를 잡을 수 있음
order_flags AS (
  SELECT
    order_id,
    COUNT(*)                                              AS n_items_all,
    COUNTIF(STARTS_WITH(items_order_status, 'N'))         AS n_items_normal
  FROM deduped
  GROUP BY order_id
),

z AS (
  SELECT
    d.order_place_name,
    COALESCE(NULLIF(d.easypay_name, ''), '(none)')        AS easypay,
    COALESCE(NULLIF(d.payment_method_name, ''), '(none)') AS pay_method,
    f.n_items_all > f.n_items_normal                      AS has_cancelled_sibling,
    f.n_items_all > 1                                     AS is_multi_item,

    CAST(COALESCE(d.div_initial_order_amount_order_price_amount, 0) AS NUMERIC)      AS gross,
    CAST(COALESCE(d.div_payment_amount, 0) AS NUMERIC)
      - CAST(COALESCE(d.shipping_fee_detail_shipping_fee_divided, 0) AS NUMERIC)     AS target_paid,
    CAST(COALESCE(d.initial_order_amount_points_spent_amount_divided,   0) AS NUMERIC) AS pts,
    CAST(COALESCE(d.initial_order_amount_coupon_discount_price_divided, 0) AS NUMERIC) AS cpn_ord,
    CAST(COALESCE(d.initial_order_amount_membership_discount_amount_divided, 0) AS NUMERIC) AS mbr,
    COALESCE(SAFE_CAST(d.items_additional_discount_price AS NUMERIC), 0)             AS add_disc,
    COALESCE(SAFE_CAST(d.items_app_item_discount_amount  AS NUMERIC), 0)             AS app_disc
  FROM deduped d
  JOIN order_flags f USING (order_id)
  WHERE d.paid = 'T' AND STARTS_WITH(d.items_order_status, 'N')
),

flagged AS (
  SELECT
    *,
    ABS((gross - pts - cpn_ord - mbr - add_disc - app_disc) - target_paid) <= 1 AS ok,
    gross - target_paid - pts - cpn_ord                                        AS residual_discount
  FROM z
)

-- ── 1. 세그먼트별 적중률 ─────────────────────────────────────────────────────
SELECT dim, val, COUNT(*) AS rows, COUNTIF(ok) AS ok_rows,
       ROUND(100 * COUNTIF(ok) / COUNT(*), 1) AS ok_pct
FROM flagged, UNNEST([
  STRUCT('1_부분취소_동반주문' AS dim, CAST(has_cancelled_sibling AS STRING) AS val),
  STRUCT('2_복수품목주문',            CAST(is_multi_item AS STRING)),
  STRUCT('3_주문경로',                order_place_name),
  STRUCT('4_간편결제사',              easypay),
  STRUCT('5_결제수단',                pay_method),
  STRUCT('6_쿠폰사용',                CAST(cpn_ord > 0 AS STRING)),
  STRUCT('7_적립금사용',              CAST(pts > 0 AS STRING)),
  STRUCT('8_등급할인',                CAST(mbr > 0 AS STRING)),
  STRUCT('9_잔차할인_음수여부',       CAST(residual_discount < 0 AS STRING))
])
GROUP BY dim, val
HAVING COUNT(*) >= 10
ORDER BY dim, ok_pct

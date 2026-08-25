-- =============================================================================
-- 분석용 주문 품목 테이블 (Cafe24 CRM)
--
-- grain : 주문 품목 1건 (items_order_item_code)
--
-- ── 검증된 주문 레벨 정합식 (온전한 주문 6,706건 중 6,646건 = 99.1%) ──────────
--     정가 − 적립금 − 쿠폰 − (등급할인 + 상품추가할인 + 앱할인) + 배송비
--       = payment_amount
--   * payment_amount 는 안분되지 않은 주문 단위 원본 → ANY_VALUE 로 집계
--   * 상품추가할인/앱할인은 품목 단위 총액 (수량 곱하지 않음)
--
-- ── 안분 방식 ─────────────────────────────────────────────────────────────
--   비중 w = div_initial_order_amount_order_price_amount / 주문 내 합계
--   주문 단위 금액(정가·적립금·쿠폰·등급할인)에 w 를 곱해 품목으로 배분하고,
--   품목 단위 금액(추가할인·앱할인)은 그대로 사용합니다.
--   → 주문별 SUM(item_paid_amount) = payment_amount − 배송비  (상품 순매출)
--
-- ── 품목 레벨 정합식 (구성상 항상 정확히 성립) ────────────────────────────
--     item_paid_amount + point_coupon_used_amount + discount_amount
--       = item_gross_amount
--
-- ── 알려진 한계 ───────────────────────────────────────────────────────────
--   부분취소 주문(전체의 약 0.5%)은 initial_order_amount_* 가 최초 주문 금액인 반면
--   payment_amount 는 취소 반영 후 금액이라 구조적으로 합이 맞지 않습니다.
--
-- ── 사용 금지 컬럼 ────────────────────────────────────────────────────────
--   items_coupon_discount_price, naver_point : 전량 0
--   items_payment_amount, discounted_amount, div_payment_amount : 정의 불명 /
--     주문 레벨 정합식과 불일치 (직접 안분하므로 불필요)
-- =============================================================================

WITH deduped AS (
  -- 스냅샷 적재라 같은 품목이 여러 query_date 로 존재 → 최신분만
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY items_order_item_code
    ORDER BY query_date DESC
  ) = 1
),

items AS (
  SELECT
    TB_DATE,
    order_id,
    items_order_item_code,
    NULLIF(TRIM(member_id), '')                                     AS member_id,
    items_order_status,
    paid,
    full_category_name_1,
    full_category_name_2,

    -- 안분 비중의 기준값
    CAST(COALESCE(div_initial_order_amount_order_price_amount, 0) AS NUMERIC) AS weight_base,

    -- 품목 단위 할인 (총액. 수량 곱하지 않음)
    COALESCE(SAFE_CAST(items_additional_discount_price AS NUMERIC), 0)
  + COALESCE(SAFE_CAST(items_app_item_discount_amount  AS NUMERIC), 0)        AS item_discount,

    -- 주문 단위 원본 (품목 행마다 반복되는 값)
    SAFE_CAST(initial_order_amount_order_price_amount            AS NUMERIC)  AS o_gross,
    SAFE_CAST(initial_order_amount_points_spent_amount           AS NUMERIC)  AS o_points,
    SAFE_CAST(initial_order_amount_coupon_discount_price         AS NUMERIC)  AS o_coupon,
    SAFE_CAST(initial_order_amount_membership_discount_amount    AS NUMERIC)  AS o_membership
  FROM deduped
),

-- 주문 단위 비중 분모: 취소 품목까지 포함한 전체 합계로 계산해야
-- 주문 단위 금액이 올바르게 배분됩니다.
weighted AS (
  SELECT
    *,
    SUM(weight_base) OVER (PARTITION BY order_id) AS order_weight_base,
    COUNT(*)         OVER (PARTITION BY order_id) AS order_item_count
  FROM items
),

allocated AS (
  SELECT
    TB_DATE,
    order_id,
    items_order_item_code,
    member_id,
    items_order_status,
    paid,
    full_category_name_1,
    full_category_name_2,

    -- 정가 총액이 0인 예외 주문은 균등 배분
    CASE WHEN order_weight_base > 0 THEN weight_base / order_weight_base
         ELSE 1 / order_item_count
    END                                                             AS w,
    o_gross, o_points, o_coupon, o_membership, item_discount
  FROM weighted
),

-- 반올림은 여기서 한 번만. 실결제액을 마지막에 빼서 구해야
-- 세 컬럼 합 = item_gross_amount 가 반올림 후에도 정확히 성립합니다.
final AS (
  SELECT
    TB_DATE,
    order_id,
    items_order_item_code,
    member_id,
    items_order_status,
    paid,
    full_category_name_1,
    full_category_name_2,

    ROUND(o_gross * w, 2)                         AS item_gross_amount,
    ROUND(o_points * w + o_coupon * w, 2)         AS point_coupon_used_amount,
    ROUND(o_membership * w + item_discount, 2)    AS discount_amount
  FROM allocated
)

SELECT
  TB_DATE,
  order_id,
  items_order_item_code,
  member_id,

  -- 실결제액 = 정가 − 적립금/쿠폰 − 할인 (배송비 제외한 상품 순매출)
  item_gross_amount - point_coupon_used_amount - discount_amount    AS item_paid_amount,
  point_coupon_used_amount,
  discount_amount,

  full_category_name_1,
  full_category_name_2

FROM final
WHERE paid = 'T'                                -- 결제 완료 건만
  AND STARTS_WITH(items_order_status, 'N')      -- 정상 주문만 (C취소/R반품/E교환 제외)
ORDER BY TB_DATE, order_id, items_order_item_code

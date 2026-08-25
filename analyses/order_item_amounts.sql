-- =============================================================================
-- 분석용 주문 품목 테이블 (Cafe24 CRM)
--
-- grain : 주문 품목 1건 (items_order_item_code)
--
-- 금액 정합식
--   item_paid_amount + point_coupon_used_amount + discount_amount
--     = div_initial_order_amount_order_price_amount   (품목 안분 정가금액)
--
--   * item_paid_amount 는 검증된 실결제액(div_payment_amount - 배송비안분)을 그대로 사용
--   * discount_amount 를 잔차로 계산 → 세 컬럼 합은 항상 정가와 정확히 일치
--
-- 실데이터 검증 결과 (9,437 품목)
--   TB_DATE = 주문일(KST)                          9437/9437
--   주문단위 안분합 = 주문 총상품금액                6706/6740 (99.5%)
--   등급/추가/앱 할인 원본 조합 = 잔차              8525/9437 (90.3%)
--     → 나머지 9.7% 는 원본 컬럼으로 설명 불가. 잔차 방식이라 총액 정합성에는
--       영향 없으나, discount_amount 세부 신뢰도는 90% 수준으로 보세요.
--
-- 사용 금지 컬럼
--   items_coupon_discount_price, naver_point : 전량 0
--   items_payment_amount, discounted_amount  : 정의 불명 (후보 전부 불일치)
-- =============================================================================

WITH deduped AS (
  -- 스냅샷 적재라 같은 품목이 여러 query_date 로 존재 → 최신분만
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY items_order_item_code
    ORDER BY query_date DESC
  ) = 1
),

typed AS (
  SELECT
    TB_DATE,
    order_id,
    items_order_item_code,
    NULLIF(TRIM(member_id), '')                                                AS member_id,

    -- 정가(안분) : 세 금액 컬럼 합의 기준점
    CAST(COALESCE(div_initial_order_amount_order_price_amount, 0) AS NUMERIC)  AS gross_amount,

    -- 실결제액 : 안분 결제금액에서 배송비 안분액 제외 (상품 순매출)
    CAST(COALESCE(div_payment_amount, 0) AS NUMERIC)
      - CAST(COALESCE(shipping_fee_detail_shipping_fee_divided, 0) AS NUMERIC) AS item_paid_amount,

    -- 적립금 + 쿠폰 사용액 (주문 단위 안분값. 품목 쿠폰 컬럼은 전량 0이라 제외)
      CAST(COALESCE(initial_order_amount_points_spent_amount_divided,   0) AS NUMERIC)
    + CAST(COALESCE(initial_order_amount_coupon_discount_price_divided, 0) AS NUMERIC)
                                                                              AS point_coupon_used_amount,
    full_category_name_1,
    full_category_name_2

  FROM deduped
  WHERE paid = 'T'                              -- 결제 완료 건만
    AND STARTS_WITH(items_order_status, 'N')    -- 정상 주문만 (C취소/R반품/E교환 제외)
)

SELECT
  TB_DATE,
  order_id,
  items_order_item_code,
  member_id,
  item_paid_amount,
  point_coupon_used_amount,
  -- 회원등급할인 + 상품추가할인 + 기타할인 (잔차)
  gross_amount - item_paid_amount - point_coupon_used_amount                  AS discount_amount,
  full_category_name_1,
  full_category_name_2

FROM typed
ORDER BY TB_DATE, order_id, items_order_item_code

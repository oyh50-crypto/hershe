-- 불일치 행 원본값 덤프 — 세그먼트 집계로도 원인이 안 잡히면 이걸로 눈으로 확인
WITH deduped AS (
  SELECT * FROM `프로젝트.데이터셋.테이블`      -- TODO: 실제 경로로 교체
  QUALIFY ROW_NUMBER() OVER (PARTITION BY items_order_item_code ORDER BY query_date DESC) = 1
)
SELECT
  order_id, items_order_item_code, items_order_status, order_place_name,
  items_quantity, items_product_price, items_option_price,
  initial_order_amount_order_price_amount, payment_amount, items_payment_amount,
  div_initial_order_amount_order_price_amount AS gross,
  div_payment_amount, shipping_fee_detail_shipping_fee_divided AS ship,
  initial_order_amount_points_spent_amount_divided   AS pts,
  initial_order_amount_coupon_discount_price_divided AS cpn_ord,
  initial_order_amount_membership_discount_amount_divided AS mbr,
  items_additional_discount_price, items_app_item_discount_amount,
  discounted_amount,
  -- 설명되지 않는 차액
  ROUND(
    (CAST(COALESCE(div_initial_order_amount_order_price_amount,0) AS NUMERIC)
     - CAST(COALESCE(initial_order_amount_points_spent_amount_divided,0) AS NUMERIC)
     - CAST(COALESCE(initial_order_amount_coupon_discount_price_divided,0) AS NUMERIC)
     - CAST(COALESCE(initial_order_amount_membership_discount_amount_divided,0) AS NUMERIC)
     - COALESCE(SAFE_CAST(items_additional_discount_price AS NUMERIC),0)
     - COALESCE(SAFE_CAST(items_app_item_discount_amount  AS NUMERIC),0))
    - (CAST(COALESCE(div_payment_amount,0) AS NUMERIC)
       - CAST(COALESCE(shipping_fee_detail_shipping_fee_divided,0) AS NUMERIC))
  , 2) AS gap
FROM deduped
WHERE paid = 'T' AND STARTS_WITH(items_order_status, 'N')
QUALIFY ABS(gap) > 1
ORDER BY ABS(gap) DESC
LIMIT 30

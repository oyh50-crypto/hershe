# Cafe24 CRM(주문) 테이블 컬럼 정의

Cafe24 Admin API의 **주문 조회 API**(`GET /api/v2/admin/orders`)와 **주문 품목 API**
(`.../orders/{order_id}/items`) 응답을 평탄화(flatten)해서 BigQuery에 적재한 테이블입니다.

## 테이블 구조 이해하기

- `items_*` 접두사가 붙은 컬럼은 주문 응답의 **`items[]` 배열을 펼친 것**입니다.
  따라서 이 테이블의 **grain(1행의 의미)은 "주문"이 아니라 "주문 품목"**입니다.
  → 고유키는 `items_order_item_code` (또는 `order_id` + `items_order_item_code`).
  → **주문 단위 금액(`payment_amount` 등)을 그대로 SUM 하면 품목 수만큼 중복 집계**됩니다.
- `initial_order_amount_*` 는 **최초 주문 시점(주문 생성 당시)의 금액**입니다.
  이후 부분취소/부분반품이 발생해도 값이 바뀌지 않으므로, "실제 확정 매출"은
  `items_order_status`로 취소/반품 건을 걸러낸 뒤 계산해야 합니다.
- `*_divided` / `div_*` 접미·접두사는 **주문 단위 금액을 품목별로 안분(按分)한 값**입니다.
  중복 집계 문제를 피하려고 파이프라인에서 미리 계산해 둔 컬럼이며,
  품목 단위 분석에서는 원본 컬럼 대신 **이 안분 컬럼을 SUM** 해야 합니다.
- 금액 컬럼 상당수가 `STRING`인 이유는 Cafe24 API가 금액을 `"12000.00"` 형태의
  문자열로 반환하기 때문입니다. 집계 전 `SAFE_CAST(... AS NUMERIC)` 필요.

---

## 1. 적재/식별 컬럼

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `query_date` | STRING | 데이터를 적재(API 조회)한 기준일. 파티션/증분 적재 키 용도이며 주문일과 다름 |
| `order_id` | STRING | **Cafe24 주문번호** (예: `20240115-0000123`). 주문 단위 식별자 |
| `market_order_no` | INTEGER | 외부 마켓(네이버 스마트스토어, 쿠팡 등) 연동 주문의 **마켓 측 주문번호**. 자사몰 주문은 NULL. ⚠️ 원본은 문자열이라 INTEGER 캐스팅 시 앞자리 0이 유실될 수 있음 |
| `items_order_item_code` | STRING | **품목 코드** (`주문번호-품목순번`, 예: `20240115-0000123-01`). 취소/반품/교환이 일어나는 최소 단위이자 이 테이블의 실질적 PK |

## 2. 주문 기본 정보

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `paid` | STRING | 결제(입금) 완료 여부. `T` / `F` |
| `order_date` | STRING | **주문 일시** (ISO 8601, 예: `2024-01-15T10:23:45+09:00`) |
| `order_from_mobile` | STRING | 모바일에서 발생한 주문인지 여부. `T` / `F` |
| `order_place_name` | STRING | **주문 경로명** (PC쇼핑몰 / 모바일쇼핑몰 / 네이버페이 / 스마트스토어 등). 채널 분석의 핵심 컬럼 |
| `order_place_id` | STRING | 주문 경로 코드 (`self`, `mobile`, `naverpay`, `smartstore` 등) |
| `call_date` | STRING | 상담/콜 일자. Cafe24 표준 주문 API에는 없는 필드로, **CRM(아웃바운드 상담) 쪽에서 붙인 자체 컬럼**으로 보임 — 실제 정의는 운영팀 확인 필요 |

## 3. 결제 정보

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `payment_amount` | STRING | **주문 단위 실결제금액**(상품금액 − 할인 + 배송비). 품목 단위 집계 시 중복 주의 → `div_payment_amount` 사용 |
| `payment_date` | STRING | 결제(입금) 완료 일시. 미결제 주문은 NULL |
| `payment_method` | STRING | 결제수단 코드 (`card` 신용카드, `cash` 무통장입금, `tcash` 실시간계좌이체, `icash` 가상계좌, `point` 적립금 등) |
| `payment_method_name` | STRING | 결제수단 한글명 |
| `easypay_name` | STRING | **간편결제사명** (네이버페이 / 카카오페이 / 페이코 / 토스 등). 일반 결제는 NULL |
| `bank_code` | STRING | 무통장입금·가상계좌 **입금 은행 코드** |
| `bank_code_name` | STRING | 입금 은행명 |
| `bank_account_no` | STRING | 입금 계좌번호 (가상계좌 번호). 개인정보/보안 취급 대상 |
| `naverpay_payment_information` | INTEGER | 네이버페이 결제 관련 부가정보. 네이버페이 주문이 아니면 NULL |
| `items_naver_pay_order_id` | STRING | 네이버페이 **상품주문번호**(품목 단위). 네이버페이 정산 대사에 사용 |

## 4. 금액 — 주문 단위 (최초 주문 시점)

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `initial_order_amount_order_price_amount` | STRING | **주문 총 상품금액** (할인·배송비 제외, 정가 기준 합계) |
| `initial_order_amount_points_spent_amount` | STRING | **적립금 사용액** |
| `initial_order_amount_coupon_discount_price` | STRING | **쿠폰 할인액** (주문 단위 쿠폰) |
| `initial_order_amount_membership_discount_amount` | STRING | **회원등급 할인액** |
| `naver_point` | INTEGER | 네이버페이 포인트 사용/적립 금액 |

## 5. 금액 — 품목 단위

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `items_product_price` | STRING | 품목 **상품 판매가(1개당)**. 옵션 추가금 미포함 |
| `items_option_price` | STRING | **옵션 추가금액**(1개당). 실판매 단가 = `items_product_price` + `items_option_price` |
| `items_payment_amount` | INTEGER | 해당 **품목의 실결제금액** |
| `items_additional_discount_price` | STRING | 품목 **추가 할인 금액**(상품별 할인) |
| `items_coupon_discount_price` | STRING | 품목에 적용된 **쿠폰 할인 금액** |
| `items_app_item_discount_amount` | STRING | 앱(플러스앱/외부 앱) 연동으로 적용된 할인 금액 |

## 6. 상품/옵션 정보

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `items_product_no` | INTEGER | 상품 일련번호(쇼핑몰 내부 상품 PK). 상품 마스터 조인 키 |
| `items_product_code` | STRING | 상품 코드 (`P0000BXX` 형태) |
| `items_product_name` | STRING | 주문 시점의 상품명 |
| `items_variant_code` | STRING | **품목(SKU) 코드** — 옵션 조합 단위 식별자. 재고 관리 기준 |
| `items_option_id` | STRING | 옵션 ID |
| `items_option_value` | STRING | 옵션값 (예: `색상=블랙, 사이즈=M`) |
| `items_quantity` | INTEGER | 주문 수량 |

## 7. 주문 상태

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `items_order_status` | STRING | **품목별 주문 상태 코드** (아래 표 참고). 매출 집계 시 필수 필터 |
| `items_order_status_additional_info` | STRING | 주문 상태 부가정보(취소 사유, 보류 사유 등) |

### 주문 상태 코드 (Cafe24 표준)

| 코드 | 의미 | 구분 |
|---|---|---|
| `N00` | 입금전 | 정상 |
| `N10` | 상품준비중 | 정상 |
| `N20` | 배송준비중 | 정상 |
| `N21` | 배송대기 | 정상 |
| `N22` | 배송보류 | 정상 |
| `N30` | 배송중 | 정상 |
| `N40` | 배송완료 | 정상(매출 확정) |
| `C00`~`C49` | 취소접수 / 취소완료 | **취소** |
| `R00`~`R49` | 반품접수 / 반품완료 | **반품** |
| `E00`~`E49` | 교환접수 / 교환완료 | 교환 |

> 매출 분석은 보통 `items_order_status LIKE 'N%'` (정상 주문)만 남기거나,
> `C%` / `R%` 를 음수 매출로 반영해 순매출을 계산합니다.

## 8. 고객/배송 정보 (개인정보)

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `member_id` | STRING | **회원 아이디**. 비회원 주문은 NULL 또는 비회원 표기 → 고객 단위 분석(리텐션/LTV)의 조인 키 |
| `buyer_name` | STRING | 주문자명 |
| `buyer_cellphone` | STRING | 주문자 휴대폰번호 |
| `receivers_name` | STRING | 수령인명 |
| `receivers_cellphone` | STRING | 수령인 휴대폰번호 |
| `receivers_address1` | STRING | 배송지 기본주소 — 지역별 분석에 활용 가능 |

> ⚠️ 이 섹션은 전부 개인정보입니다. 마트 레이어로 올릴 때는 해싱하거나
> `receivers_address1`에서 시/도만 추출하는 등 최소화 처리를 권장합니다.

## 9. 안분(divided) 컬럼 — 품목 단위 집계용

주문 단위 금액을 품목별로 나눠 담아 둔 컬럼입니다. **품목 단위 테이블에서 SUM 할 때는
반드시 이쪽을 사용**해야 중복 집계가 안 생깁니다. FLOAT인 이유는 나누어떨어지지 않는
원 단위 잔액 때문이며, 총합이 원본과 1원 내외로 어긋날 수 있습니다.

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `shipping_fee_detail_shipping_fee_divided` | FLOAT | 배송비를 품목별로 안분한 금액 |
| `initial_order_amount_points_spent_amount_divided` | FLOAT | 적립금 사용액 안분 |
| `initial_order_amount_coupon_discount_price_divided` | FLOAT | 쿠폰 할인액 안분 |
| `initial_order_amount_membership_discount_amount_divided` | FLOAT | 회원등급 할인액 안분 |
| `div_initial_order_amount_order_price_amount` | FLOAT | 주문 총 상품금액 안분 |
| `div_payment_amount` | FLOAT | **주문 실결제금액 안분 → 품목 단위 매출 지표의 기본값** |

---

## 분석 시 주의사항 요약

1. **중복 집계** — 한 주문에 품목이 N개면 `order_id`, `payment_amount` 등 주문 단위 값이 N번 반복됩니다.
   - 주문 수: `COUNT(DISTINCT order_id)`
   - 매출: `SUM(div_payment_amount)` (또는 `order_id`로 dedup 후 `payment_amount` 합)
2. **타입 캐스팅** — 금액 STRING 컬럼은 `SAFE_CAST(x AS NUMERIC)`, 일시 STRING 컬럼은
   `PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S%Ez', x)` 후 `Asia/Seoul` 기준 날짜 추출.
3. **매출 기준일** — 주문일(`order_date`)과 결제일(`payment_date`)이 다릅니다. 무통장입금은
   며칠 차이 날 수 있으니 어떤 기준으로 볼지 먼저 정해야 합니다.
4. **취소/반품** — `initial_order_amount_*`는 최초 주문 금액이라 취소가 반영되지 않습니다.
   반드시 `items_order_status`와 함께 사용하세요.
5. **`query_date` 중복** — 스냅샷 방식으로 적재되었다면 같은 주문이 여러 `query_date`로
   존재할 수 있습니다. 적재 방식(증분 vs 스냅샷)을 확인하고, 스냅샷이면
   `QUALIFY ROW_NUMBER() OVER (PARTITION BY items_order_item_code ORDER BY query_date DESC) = 1`
   로 최신 상태만 남기세요.

---

## 10. 상품 마스터 컬럼 (주문 행에 denormalize 되어 있음)

이 테이블은 주문 + 품목에 **상품 마스터와 카테고리까지 붙여 놓은 단일 와이드 테이블**이라,
카테고리 분석에 별도 조인이 필요 없습니다.

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `product_no` | INTEGER | 상품 일련번호 (상품 마스터 기준). `items_product_no`와 동일 값이어야 정상 |
| `product_code` | STRING | 상품 코드 |
| `product_name` | STRING | **현재 상품명** (주문 시점 상품명은 `items_product_name`) |
| `price` | STRING | 상품 판매가 (마스터 기준 현재가) |
| `supply_price` | STRING | **공급가** — 마진 분석용 |
| `display` | STRING | 진열 여부 (T/F) |
| `selling` | STRING | 판매 여부 (T/F) |
| `price_content` | STRING | 가격 대체 문구 (가격 비공개 시 노출 텍스트) |
| `repurchase_restriction` | STRING | 재구매 제한 여부 |
| `single_purchase_restriction` | STRING | 단독구매 제한 여부 |
| `single_purchase` | STRING | 단독구매 설정 |
| `detail_image` / `list_image` / `tiny_image` / `small_image` | STRING | 상품 이미지 URL (상세/목록/썸네일) |
| `created_date` | DATE | 상품 등록일 — 신상품 분석에 활용 |
| `updated_date` | DATE | 상품 정보 수정일 |

## 11. 카테고리 / 기타

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `full_category_name_1` ~ `_4` | STRING | **카테고리 depth별 전체 경로명**. `_1`이 대분류, `_4`가 최하위 |
| `TB_DATE` | DATE | 분석 기준 일자. 적재 파이프라인이 만든 컬럼으로, 주문일 기준일 것으로 보이나 **`DATE(order_date, 'Asia/Seoul')`와 일치하는지 1회 검증 권장** |
| `discounted_amount` | FLOAT | 할인 관련 금액. **"할인액 합계"인지 "할인 후 금액"인지 정의가 불명확** — `analyses/order_item_amounts_qa.sql`의 C/D 체크로 판별 후 확정하세요 |
| `__index_level_0__` | INTEGER | pandas DataFrame 인덱스가 그대로 적재된 잔여 컬럼. **분석에 사용하지 말 것** |

> `full_category_name_*`은 상품이 여러 카테고리에 속할 경우 대표 1건만 실려 있을 가능성이
> 높습니다. 카테고리별 매출 합이 전체 매출과 맞는지 확인해 두세요.

---

## 부록. 실데이터 검증 결과 (9,437 품목 / 6,740 주문 기준)

| 검증 항목 | 결과 | 결론 |
|---|---|---|
| `TB_DATE` = `DATE(order_date, KST)` | 9437 / 9437 | **주문일 기준 확정** |
| `SUM(div_initial_order_amount_order_price_amount)` = 주문 총상품금액 | 6706 / 6740 | **안분 정가금액으로 사용 가능** (99.5%) |
| `div_payment_amount` − 배송비안분 = 품목 실결제액 | 8525 / 9437 | 실결제액의 기준 컬럼. 나머지 10%는 할인 버킷 정의 문제 |
| `items_payment_amount` = 품목 실결제액 | 5 / 9437 | **실결제액 아님** — 용도 재확인 필요 |
| `discounted_amount` = 할인액 합계 | 4718 / 9437 | 할인 0원 행에서만 일치 → 다른 정의 |

### 확정된 금액 정합식 (주문 레벨)

`payment_amount` 는 안분되지 않은 **주문 단위 원본**(품목 행마다 반복)이므로,
정합성은 주문 레벨에서 성립합니다.

```
정가 − 적립금 − 쿠폰 − (등급할인 + 상품추가할인 + 앱할인) + 배송비 = payment_amount
```

부분취소 없는 온전한 주문 6,706건 중 **6,646건(99.1%)** 에서 성립.

| 할인 항목 후보 | 적중 | 판정 |
|---|---|---|
| 등급 + 상품추가 + 앱 | **6646** | **채택** |
| 등급만 | 4939 | 품목할인 필수 |
| 상품추가 + 앱만 | 6462 | 등급할인 필수 |
| 등급 + 추가 + 앱 + 품목쿠폰 | 6646 | 동일 → 품목쿠폰 전량 0 |
| 등급 + (추가+앱) × 수량 | 6641 | 품목할인은 **총액**이지 단가 아님 |
| 등급 + 추가 + 앱 + 네이버포인트 | 6646 | 동일 → naver_point 전량 0 |
| 배송비 제외 | 5262 | 배송비 항목 필수 |

### 채택한 안분 방식

주문 레벨에서 계산하고 품목 정가 비중으로 배분합니다. 파이프라인이 만든
`div_payment_amount` 는 주문 레벨 정합식과 맞지 않아 사용하지 않습니다.

```
비중 w = div_initial_order_amount_order_price_amount / 주문 내 합계

item_gross_amount        = 주문정가 × w
point_coupon_used_amount = (적립금 + 쿠폰) × w
discount_amount          = 등급할인 × w + 상품추가할인 + 앱할인
item_paid_amount         = item_gross_amount − 위 둘
```

- 세 컬럼 합 = `item_gross_amount` (반올림 후에도 정확히 일치)
- 주문별 `SUM(item_paid_amount)` = `payment_amount − 배송비` (상품 순매출)
- 비중 분모는 **취소 품목까지 포함한 전체 합계** — 주문 단위 금액이 그것들도 포괄하기 때문

### 알려진 한계

부분취소 주문(약 0.5%)은 `initial_order_amount_*` 가 최초 주문 금액인 반면
`payment_amount` 는 취소 반영 후 금액이라 구조적으로 합이 맞지 않습니다.

### 사용하면 안 되는 컬럼

| 컬럼 | 사유 |
|---|---|
| `items_coupon_discount_price` | 전량 0 |
| `naver_point` | 전량 0 |
| `items_payment_amount` | 후보 정의 전부 불일치 (최대 0/9437). 정의 불명 |
| `discounted_amount` | 후보 정의 전부 불일치. 정의 불명 |
| `div_payment_amount` | 주문 레벨 정합식과 불일치. 직접 안분하므로 불필요 |
| `__index_level_0__` | pandas 인덱스 잔여물 |

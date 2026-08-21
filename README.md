# hershe 마케팅 분석 데이터마트

BigQuery에 적재된 GA4 export, GA4+주문 결합 테이블, 광고 플랫폼 데이터, CRM/주문 데이터를
dbt로 가공해 마케팅 분석용 데이터마트를 만드는 프로젝트입니다. 1차 목표는 **고객 행동/퍼널 분석**입니다.

## 레이어 구조

```
models/
  staging/      원본 테이블을 1:1로 정리 (컬럼명 정규화, 타입 캐스팅만 수행)
    ga4/          GA4 BigQuery export (events_*)
    ga4_orders/   기존에 있는 GA4+주문 결합 테이블 (어트리뷰션 브릿지로 사용)
    ads/          Google Ads / Meta Ads 플랫폼 성과 데이터
    crm/          CRM/주문/결제 데이터
  intermediate/  세션 단위 집계, 퍼널 이벤트 추출, 광고 플랫폼 데이터 통합
  marts/marketing/  최종 분석 테이블 (BI 툴에서 바로 조회)
```

## 핵심 마트

- **`mart_funnel_analysis`** — 일자 x 채널 x 퍼널 단계별 세션 수, 단계별 전환율/이탈률.
  1차 목표인 퍼널 분석의 핵심 산출물입니다.
- **`fct_sessions`** — GA4 세션 단위 팩트 (채널, 랜딩페이지, 구매여부).
- **`fct_funnel_steps`** — 세션 x 도달한 퍼널 단계 (grain은 실제 도달한 단계만).
- **`mart_channel_performance`** — 일자 x 채널별 광고비 + 세션/전환/매출을 결합해 CPC, CVR, ROAS, CPA 산출.
- **`fct_orders`** — CRM 주문 팩트에 GA4 채널 어트리뷰션을 결합.

## 설정하기 전에 반드시 확인할 것

이 저장소에는 BigQuery 실제 스키마를 조회할 권한이 없어서, 아래 파일들은
**업계 표준 스키마를 가정한 템플릿**입니다. 실제 프로젝트/데이터셋/컬럼명에 맞게 조정하세요.

1. **`dbt_project.yml`의 `vars`** — `ga4_project`, `ga4_dataset` 등 실제 BigQuery
   프로젝트/데이터셋 이름으로 교체.
2. **`models/staging/*/​_*.yml`의 `source`** — 테이블 식별자가 실제와 다르면 수정.
3. **각 `stg_*.sql`의 컬럼명** — 특히 `ads`와 `crm` 쪽은 실제 커넥터/CRM 스키마를
   모르는 상태로 작성했으므로 (`campaign_id`, `cost_micros`, `order_amount` 등)
   실제 컬럼명으로 바꿔야 합니다. `-- TODO` 주석이 달린 파일부터 확인하세요.
4. **`models/staging/ga4_orders/stg_ga4_orders__combined.sql`** — 기존에 갖고 계신
   GA4+주문 결합 테이블의 실제 컬럼명(주문ID, 세션ID, 채널 관련 컬럼)으로 교체.
5. **`macros/default_channel_grouping.sql`** — GA4 공식 채널 그룹핑 로직을 단순화한
   버전입니다. UTM 규칙이 다르면 조건을 조정하세요.
6. **`dbt_project.yml`의 `funnel_steps`** — 실제 GA4에서 트래킹 중인 이벤트명과
   퍼널 순서가 다르면 수정 (기본값은 GA4 표준 이커머스 이벤트: `view_item` →
   `add_to_cart` → `begin_checkout` → `add_payment_info` → `purchase`).

## 실행

```bash
dbt deps           # dbt_utils 설치
dbt run            # 전체 모델 빌드
dbt test           # 스키마 테스트 실행
dbt run --select mart_funnel_analysis+   # 퍼널 분석 마트만 빌드
```

## 다음 단계로 고려할 것

- `dim_customer` (SCD Type 2) — 세그먼트/최초유입채널 변화 이력 추적
- 고객 LTV/RFM 마트 — 세그먼트별 고객 가치 분석
- `fct_sessions`를 incremental 모델로 전환 — 이벤트 볼륨이 커지면 전체 재계산 비용이 커짐

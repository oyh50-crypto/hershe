-- Grain: cohort_month x period_number (months since first purchase).
-- Long/tidy format — pivot into a triangle in the BI layer, not here.
with cohorts as (

    select * from {{ ref('int_customer__first_purchase') }}

),

activity as (

    select * from {{ ref('int_cohort__customer_monthly_activity') }}

),

cohort_size as (

    select
        cohort_month,
        count(distinct customer_id) as cohort_size
    from cohorts
    group by 1

),

cohort_activity as (

    select
        c.cohort_month,
        date_diff(a.activity_month, c.cohort_month, month) as period_number,
        c.customer_id
    from cohorts c
    inner join activity a on a.customer_id = c.customer_id
    where a.activity_month >= c.cohort_month

)

select
    ca.cohort_month,
    ca.period_number,
    cs.cohort_size,
    count(distinct ca.customer_id) as active_customers,
    safe_divide(count(distinct ca.customer_id), cs.cohort_size) as retention_rate
from cohort_activity ca
inner join cohort_size cs using (cohort_month)
group by 1, 2, 3
order by 1, 2

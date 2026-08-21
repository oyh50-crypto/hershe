-- Grain: one row per customer, their first order and cohort assignment.
with orders as (

    select * from {{ ref('fct_orders') }}

)

select
    customer_id,
    min(order_date) as first_order_date,
    date_trunc(min(order_date), month) as cohort_month
from orders
group by customer_id

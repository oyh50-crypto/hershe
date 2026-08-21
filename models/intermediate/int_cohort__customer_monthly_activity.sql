-- Grain: one row per customer per month they had at least one GA4 session.
-- Depends on GA4's user_id matching the CRM customer_id (i.e. set on login) —
-- sessions from logged-out visits can't be attributed to a customer here.
with sessions as (

    select * from {{ ref('fct_sessions') }}
    where user_id is not null

)

select distinct
    user_id as customer_id,
    date_trunc(event_date, month) as activity_month
from sessions

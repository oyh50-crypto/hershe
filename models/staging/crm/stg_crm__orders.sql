-- TODO: rename source columns below to match the real CRM schema.
with source as (

    select * from {{ source('crm', 'orders') }}

),

renamed as (

    select
        order_id,
        customer_id,
        order_date,
        order_status,
        order_amount

    from source

)

select * from renamed

{{ config(
    materialized = 'table',
    tags = ['billing', 'dimension', 'payment_method']
) }}

/*
DIM_PAYMENT_METHOD

Target grain:
    One row per (payment_method, processor)

Source:
    ct_paymentsvc.payment_gateway_provider

Logic:
    - Build the distinct set of payment method codes.
    - Build the distinct set of payment processor names.
    - CROSS JOIN the two sets to generate one row per method x processor.
    - Default IS_RECURRING_CAPABLE_FLAG to 'N' until explicit recurring capability
      logic is available.
*/

with payment_methods as (

    select distinct
        upper(trim(payment_method_code))::varchar(30) as payment_method_code

    from {{ source('ct_paymentsvc', 'payment_gateway_provider') }}

    where payment_method_code is not null
      and trim(payment_method_code) <> ''

),

payment_processors as (

    select distinct
        trim(payment_processor_name)::varchar(50) as payment_processor_name

    from {{ source('ct_paymentsvc', 'payment_gateway_provider') }}

    where payment_processor_name is not null
      and trim(payment_processor_name) <> ''

),

payment_method_processor as (

    select
        pm.payment_method_code,
        pp.payment_processor_name

    from payment_methods pm
    cross join payment_processors pp

),

final as (

    select
        hash(
            payment_method_code,
            upper(payment_processor_name)
        )::number(38,0) as payment_method_sk,

        payment_method_code,
        payment_processor_name,

        'N'::varchar(1) as is_recurring_capable_flag,

        current_timestamp()::timestamp_ltz as elt_ts,
        'dbt:dim_payment_method'::varchar(100) as elt_by

    from payment_method_processor

)

select *
from final

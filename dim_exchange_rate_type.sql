{{ config(
    materialized = 'table',
    tags = ['billing', 'dimension', 'exchange_rate']
) }}

with exchange_rate_type as (

    select
        'SPOT'::varchar(20) as exchange_rate_type_code,
        'Spot / Daily Rate'::varchar(100) as exchange_rate_type_name,
        'Daily exchange rate; corresponds to legacy period_nm = D.'
            ::varchar(500) as usage_note_text

    union all

    select
        'MONTH_END',
        'Month-End Rate',
        'Month-end exchange rate; corresponds to legacy period_nm = M.'

)

select
    hash(exchange_rate_type_code)::number(38,0)
        as exchange_rate_type_sk,

    exchange_rate_type_code,
    exchange_rate_type_name,
    usage_note_text,

    current_timestamp()::timestamp_ltz
        as elt_ts,

    'dbt:dim_exchange_rate_type'::varchar(100)
        as elt_by

from exchange_rate_type
{{ config(
    materialized = 'table',
    tags = ['billing', 'dimension', 'invoice_driver']
) }}

with driver_reference as (

    select
        trim(metric_type_nm)::varchar(50) as invoice_driver_name,
        trim(external_system_nm)::varchar(50) as driver_group_name,
        upper(trim(include_in_total_fl))::varchar(1) as include_in_total_flag,
        metric_type_nbr::number(5,0) as display_order_number

    from {{ source('legacy_invoice_driver_ref', 'exec_dash_invoice_driver_r') }}

    where metric_type_nm is not null

    qualify row_number() over (
        partition by upper(trim(metric_type_nm))
        order by metric_type_nbr nulls last
    ) = 1

),

ctct_brand as (

    select
        brand_sk,
        brand_cd

    from {{ ref('dim_brand') }}

    where upper(brand_cd) = 'CTCT'

),

final as (

    select
        case
            when upper(dr.invoice_driver_name) like 'HOUSE ACCOUNTS%'
                then cb.brand_sk
            else null
        end::number(38,0) as brand_sk,

        case
            when upper(dr.invoice_driver_name) like 'HOUSE ACCOUNTS%'
                then cb.brand_cd
            else null
        end::varchar as brand_cd,

        dr.invoice_driver_name,
        dr.driver_group_name,
        dr.include_in_total_flag,
        dr.display_order_number

    from driver_reference dr

    left join ctct_brand cb
        on upper(dr.invoice_driver_name) like 'HOUSE ACCOUNTS%'

)

select
    hash(
        coalesce(upper(brand_cd), '__ALL_BRANDS__'),
        upper(invoice_driver_name)
    )::number(38,0) as driver_category_sk,

    brand_sk,
    invoice_driver_name,
    driver_group_name,
    include_in_total_flag,
    display_order_number,

    current_timestamp()::timestamp_ltz as elt_ts,
    'dbt:dim_invoice_driver_category'::varchar(100) as elt_by

from final

{{ config(
    materialized = 'table',
    alias = 'DIM_TAX_JURISDICTION'
) }}

with source as (

    select
        jurisdiction,
        display_name,
        tax_type,
        percentage,
        effective_percentage,
        inclusive,
        jurisdiction_level,
        elt_ts
    from {{ source('ct_stripe', 'tax_rates') }}

),

deduplicated as (

    select
        *
    from source

    qualify row_number() over (
        partition by jurisdiction
        order by elt_ts desc
    ) = 1

),

final as (

    select
        hash(
            upper(trim(jurisdiction))
        ) as tax_jurisdiction_sk,

        upper(trim(jurisdiction))
            as jurisdiction_code,

        trim(display_name)
            as jurisdiction_name,

        trim(tax_type)
            as tax_type_name,

        coalesce(
            effective_percentage,
            percentage
        )::number(18,4)
            as tax_rate_percent,

        case
            when inclusive = true then 'Y'
            else 'N'
        end as is_inclusive_flag,

        upper(trim(jurisdiction_level))
            as jurisdiction_level_name,

        current_timestamp()
            as elt_ts,

        '{{ this.name }}'
            as elt_by

    from deduplicated

)

select *
from final
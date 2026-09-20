{{ config(
    materialized = 'table',
    tags = ['billing', 'dimension', 'rate_tier']
) }}


/* ============================================================
   BAAS RATE TIERS
   ============================================================ */

with baas_rate_tiers as (

    select
        r.service_id::varchar
            as service_code,

        r.usage_type_id::varchar(30)
            as usage_type_code,

        upper(trim(r.currency_code))::varchar(10)
            as currency_code,

        r.tier::number(5,0)
            as tier_sequence_number,

        r.tier_min::number(15,5)
            as tier_min_quantity,

        r.tier_max::number(15,5)
            as tier_max_quantity,

        r.amount::number(15,5)
            as tier_unit_amount,

        null::number(15,5)
            as tier_flat_fee_amount,

        r.pricing_model_id::varchar(20)
            as pricing_model_code,

        r.description::varchar(500)
            as tier_description_text,

        r.insert_time::date
            as effective_start_date,

        null::date
            as effective_end_date,

        'BAAS'::varchar(20)
            as source_system_code

    from {{ source('ct_baas', 'rate') }} r

),


/* ============================================================
   STRIPE PRICE TIERS

   Existing procedure logic derives:
     tier_sequence_number = ROW_NUMBER by price_id / upto
     tier_min_quantity    = previous upto + 1
     tier_max_quantity    = upto
   ============================================================ */

stripe_price_tiers as (

    select
        pt.price_id,

        row_number() over (
            partition by pt.price_id
            order by pt.upto
        )::number(5,0)
            as tier_sequence_number,

        coalesce(
            lag(pt.upto) over (
                partition by pt.price_id
                order by pt.upto
            ) + 1,
            0
        )::number(15,5)
            as tier_min_quantity,

        pt.upto::number(15,5)
            as tier_max_quantity,

        /* Using spreadsheet/deep-dive source for now */
        (pt.amount / 100)::number(15,5)
            as tier_unit_amount,

        (pt.flat_amount / 100)::number(15,5)
            as tier_flat_fee_amount

    from {{ source('ct_stripe', 'price_tiers') }} pt

),


/* ============================================================
   STRIPE SERVICE MAPPING

   Existing procedures use prices_metadata where KEY = SERVICE_ID
   to associate Stripe price_id with native service_id.
   ============================================================ */

stripe_service as (

    select distinct
        pm.price_id,

        trim(pm.value)::varchar
            as service_code

    from {{ source('ct_stripe', 'prices_metadata') }} pm

    where upper(trim(pm.key)) = 'SERVICE_ID'

),


/* ============================================================
   STRIPE RATE TIERS
   ============================================================ */

stripe_rate_tiers as (

    select
        ss.service_code,

        null::varchar(30)
            as usage_type_code,

        upper(trim(p.currency))::varchar(10)
            as currency_code,

        spt.tier_sequence_number,

        spt.tier_min_quantity,

        spt.tier_max_quantity,

        spt.tier_unit_amount,

        spt.tier_flat_fee_amount,

        upper(trim(p.tiers_mode))::varchar(20)
            as pricing_model_code,

        null::varchar(500)
            as tier_description_text,

        /*
            No business-effective start/end fields have been
            confirmed yet for Stripe.
        */
        null::date
            as effective_start_date,

        null::date
            as effective_end_date,

        'STRIPE'::varchar(20)
            as source_system_code

    from stripe_price_tiers spt

    left join {{ source('ct_stripe', 'prices') }} p
        on upper(spt.price_id) = upper(p.id)

    left join stripe_service ss
        on upper(spt.price_id) = upper(ss.price_id)

),


/* ============================================================
   COMBINE SOURCES
   ============================================================ */

combined_rate_tiers as (

    select
        service_code,
        usage_type_code,
        currency_code,
        tier_sequence_number,
        tier_min_quantity,
        tier_max_quantity,
        tier_unit_amount,
        tier_flat_fee_amount,
        pricing_model_code,
        tier_description_text,
        effective_start_date,
        effective_end_date,
        source_system_code

    from baas_rate_tiers


    union all


    select
        service_code,
        usage_type_code,
        currency_code,
        tier_sequence_number,
        tier_min_quantity,
        tier_max_quantity,
        tier_unit_amount,
        tier_flat_fee_amount,
        pricing_model_code,
        tier_description_text,
        effective_start_date,
        effective_end_date,
        source_system_code

    from stripe_rate_tiers

),


/* ============================================================
   FINAL

   BRAND_SK is intentionally left NULL until the valid
   source/service -> DIM_BRAND mapping is confirmed.

   The target RATE_TIER_SK requires:
       HASH(
           brand_cd,
           service_cd,
           tier_sequence_nbr,
           effective_start_dt
       )

   Therefore the final production surrogate key should be updated
   when BRAND_CD and complete effective dates are available.
   ============================================================ */

final as (

    select
        null::number(38,0)
            as brand_sk,

        service_code,

        usage_type_code,

        currency_code,

        tier_sequence_number,

        tier_min_quantity,

        tier_max_quantity,

        tier_unit_amount,

        tier_flat_fee_amount,

        pricing_model_code,

        tier_description_text,

        effective_start_date,

        effective_end_date,

        source_system_code

    from combined_rate_tiers

    where service_code is not null

)

select

    /*
       Temporary SK until BRAND_CD mapping is confirmed.

       Replace '__BRAND_PENDING__' with the actual BRAND_CD
       from DIM_BRAND before production.
    */
    hash(
        '__BRAND_PENDING__',
        service_code,
        tier_sequence_number,
        effective_start_date
    )::number(38,0)
        as rate_tier_sk,

    brand_sk,

    service_code,

    usage_type_code,

    currency_code,

    tier_sequence_number,

    tier_min_quantity,

    tier_max_quantity,

    tier_unit_amount,

    tier_flat_fee_amount,

    pricing_model_code,

    tier_description_text,

    effective_start_date,

    effective_end_date,

    current_timestamp()::timestamp_ltz
        as elt_ts,

    'dbt:dim_rate_tier'::varchar(100)
        as elt_by

from final
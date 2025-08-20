{{ config(
    materialized='incremental',
    partition_by={'field': 'period_end_date', 'data_type': 'date'},
    cluster_by=['cik','concept'],
    require_partition_filter=false   -- add this line
) }}
with base as (
  select
    n.cik, n.ticker, n.concept, n.unit,
    n.period_end_date, n.value, n.accn, n.filed, n.fy, n.fp, n.form
  from {{ ref('int_companyfacts_normalized') }} n
  where n.fp in ('Q1','Q2','Q3','Q4') or n.form in ('10-Q','10-K')
)
select * from base
{% if is_incremental() %}
where period_end_date > (select ifnull(max(period_end_date), date('2000-01-01')) from {{ this }})
{% endif %}

{{ config(
  materialized='table',
  partition_by={'field': 'period_end_date', 'data_type': 'date'},
  cluster_by=['cik'],
  schema='sec_viz'
) }}

with rev_candidates as (
  select
    cik, ticker, period_end_date, concept, unit, value
  from {{ ref('fct_financials_quarterly') }}
  where concept in (
    'us-gaap:Revenues',
    'us-gaap:SalesRevenueNet'
  )
  and (unit is null or upper(unit) like '%USD%')
  and period_end_date is not null
  and value is not null
  and period_end_date >= date_sub(current_date(), interval 8 year)
),

preferred as (
  select *,
         row_number() over (
           partition by cik, period_end_date
           order by case concept
             when 'us-gaap:Revenues' then 1
             when 'us-gaap:SalesRevenueNet' then 2
             else 9 end,
             period_end_date desc
         ) as rn
  from rev_candidates
),

rev as (
  select cik, ticker, period_end_date, value as revenue
  from preferred
  where rn = 1
)

select
  cik, ticker, period_end_date,
  sum(revenue) over (
    partition by cik
    order by period_end_date
    rows between 3 preceding and current row
  ) as ttm_revenue
from rev
where period_end_date >= date_sub(current_date(), interval 6 year)
qualify ttm_revenue is not null
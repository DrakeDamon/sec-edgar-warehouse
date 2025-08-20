{{ config(
    materialized='table',
    schema='sec_viz'
) }}

with latest_quarters as (
  select 
    cik,
    ticker,
    max(period_end_date) as latest_quarter
  from {{ ref('fct_financials_quarterly') }}
  group by cik, ticker
),
revenue_data as (
  select 
    f.cik,
    f.ticker,
    f.period_end_date,
    f.value as revenue,
    f.fy,
    f.fp
  from {{ ref('fct_financials_quarterly') }} f
  join latest_quarters lq on f.cik = lq.cik and f.period_end_date = lq.latest_quarter
  where f.concept in ('Revenues', 'SalesRevenueNet', 'RevenueFromContractWithCustomerExcludingAssessedTax')
    and f.value > 0
),
company_info as (
  select 
    cik,
    ticker,
    company_name
  from {{ ref('dim_company') }}
)
select 
  ci.cik,
  ci.ticker,
  ci.company_name,
  rd.period_end_date as latest_quarter,
  rd.revenue as latest_revenue,
  rd.fy as fiscal_year,
  rd.fp as fiscal_period,
  current_timestamp() as refreshed_at
from company_info ci
left join revenue_data rd on ci.cik = rd.cik
where ci.ticker is not null
order by rd.revenue desc
{{ config(
    materialized='table',
    schema='sec_viz'
) }}

with quarterly_revenue as (
  select 
    cik,
    ticker,
    period_end_date,
    value as revenue,
    fy,
    fp
  from {{ ref('fct_financials_quarterly') }}
  where concept in ('Revenues', 'SalesRevenueNet', 'RevenueFromContractWithCustomerExcludingAssessedTax')
    and value > 0
    and fp in ('Q1', 'Q2', 'Q3', 'Q4')
),
latest_quarters as (
  select 
    cik,
    ticker,
    max(period_end_date) as latest_quarter
  from quarterly_revenue
  group by cik, ticker
),
ttm_calculation as (
  select 
    qr.cik,
    qr.ticker,
    sum(qr.revenue) as ttm_revenue,
    count(*) as quarters_count,
    max(qr.period_end_date) as latest_quarter_date,
    string_agg(concat(cast(qr.fy as string), '-', qr.fp), ', ' order by qr.period_end_date) as ttm_periods
  from quarterly_revenue qr
  join latest_quarters lq on qr.cik = lq.cik
  where qr.period_end_date > date_sub(lq.latest_quarter, interval 365 day)
    and qr.period_end_date <= lq.latest_quarter
  group by qr.cik, qr.ticker
  having count(*) >= 3
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
  ttm.ttm_revenue,
  ttm.quarters_count,
  ttm.latest_quarter_date,
  ttm.ttm_periods,
  round(ttm.ttm_revenue / 1000000000, 2) as ttm_revenue_billions,
  current_timestamp() as refreshed_at
from company_info ci
join ttm_calculation ttm on ci.cik = ttm.cik
where ci.ticker is not null
order by ttm.ttm_revenue desc
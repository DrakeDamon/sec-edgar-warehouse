{{ config(
    materialized='table',
    schema=var('BQ_VIZ_DATASET', 'sec_viz')
) }}

with company_base as (
  select 
    cik,
    ticker,
    company_name
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.dim_company`
  where ticker is not null
),
latest_filing as (
  select 
    cik,
    max(period_end_date) as latest_filing_date,
    count(distinct period_end_date) as total_quarters_filed
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  group by cik
),
revenue_summary as (
  select 
    cik,
    count(distinct case when concept in ('Revenues', 'SalesRevenueNet', 'RevenueFromContractWithCustomerExcludingAssessedTax') then period_end_date end) as revenue_quarters_count,
    max(case when concept in ('Revenues', 'SalesRevenueNet', 'RevenueFromContractWithCustomerExcludingAssessedTax') then period_end_date end) as latest_revenue_date
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  where value > 0
  group by cik
)
select 
  cb.cik,
  cb.ticker,
  cb.company_name,
  lf.latest_filing_date,
  lf.total_quarters_filed,
  coalesce(rs.revenue_quarters_count, 0) as revenue_quarters_count,
  rs.latest_revenue_date,
  case 
    when rs.revenue_quarters_count >= 4 then 'Active'
    when rs.revenue_quarters_count >= 1 then 'Limited Data'
    else 'No Revenue Data'
  end as data_completeness,
  current_timestamp() as refreshed_at
from company_base cb
left join latest_filing lf on cb.cik = lf.cik
left join revenue_summary rs on cb.cik = rs.cik
order by cb.ticker
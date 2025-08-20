{{ config(materialized='table', schema=var('BQ_VIZ_DATASET', 'sec_viz')) }}

with last_period as (
  select
    cik,
    max(period_end_date) as last_period
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  where period_end_date is not null
  group by cik
),

rev_candidates as (
  select
    cik, ticker, period_end_date, concept, unit, value
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  where concept in (
    'us-gaap:Revenues',
    'us-gaap:SalesRevenueNet'
  )
  and (unit is null or upper(unit) like '%USD%')
  and value is not null
),

rev_ranked as (
  select *,
         row_number() over (
           partition by cik, period_end_date
           order by case concept
             when 'us-gaap:Revenues' then 1
             when 'us-gaap:SalesRevenueNet' then 2
             else 9 end
         ) as rn
  from rev_candidates
),

rev_pref as (
  select cik, ticker, period_end_date, value as revenue
  from rev_ranked
  where rn = 1
),

-- Use window function to get most recent revenue within last 4 quarters
rev_with_recency as (
  select 
    l.cik, 
    l.last_period,
    r.period_end_date,
    r.revenue,
    row_number() over (
      partition by l.cik 
      order by r.period_end_date desc
    ) as recency_rank
  from last_period l
  left join rev_pref r 
    on r.cik = l.cik 
    and r.period_end_date <= l.last_period
    and r.period_end_date > date_sub(l.last_period, interval 400 day)
),

rev_final as (
  select cik, last_period, revenue as revenue_nearest
  from rev_with_recency 
  where recency_rank = 1
),

gp as (
  select cik, period_end_date, value as gross_profit
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  where concept = 'us-gaap:GrossProfit'
),

ni as (
  select cik, period_end_date, value as net_income
  from `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  where concept = 'us-gaap:NetIncomeLoss'
)

select
  d.cik,
  d.ticker,
  l.last_period as period_end_date,
  rf.revenue_nearest as revenue,
  g.gross_profit,
  n.net_income,
  safe_divide(g.gross_profit, rf.revenue_nearest) as gross_margin,
  safe_divide(n.net_income, rf.revenue_nearest) as net_margin
from `sec-edgar-financials-warehouse.sec_curated_sec_curated.dim_company` d
join last_period l using (cik)
left join rev_final rf on rf.cik = l.cik and rf.last_period = l.last_period
left join gp g on g.cik = l.cik and g.period_end_date = l.last_period
left join ni n on n.cik = l.cik and n.period_end_date = l.last_period
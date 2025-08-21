{{ config(materialized='table', schema=var('BQ_VIZ_DATASET', 'sec_viz')) }}

-- Revenue concepts (USD-ish only), pick a preferred one per (cik, period)
WITH rev_candidates AS (
  SELECT
    cik, ticker, period_end_date, concept, unit, value
  FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  WHERE concept IN (
    'us-gaap:Revenues',
    'us-gaap:SalesRevenueNet',
    'us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax',
    'us-gaap:RevenueFromContractWithCustomerIncludingAssessedTax',
    'us-gaap:SalesRevenueGoodsNet',
    'us-gaap:SalesRevenueServicesNet'
  )
  AND (unit IS NULL OR UPPER(unit) LIKE '%USD%')
  AND period_end_date IS NOT NULL
  AND value IS NOT NULL
),
rev_ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (
           PARTITION BY cik, period_end_date
           ORDER BY CASE concept
             WHEN 'us-gaap:Revenues' THEN 1
             WHEN 'us-gaap:SalesRevenueNet' THEN 2
             WHEN 'us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax' THEN 3
             WHEN 'us-gaap:SalesRevenueGoodsNet' THEN 4
             WHEN 'us-gaap:SalesRevenueServicesNet' THEN 5
             ELSE 9 END
         ) AS rn
  FROM rev_candidates
),
rev_pref AS (
  SELECT cik, ticker, period_end_date, value AS revenue
  FROM rev_ranked
  WHERE rn = 1
),

-- 🔑 latest period that actually HAS revenue (per company)
last_rev_period AS (
  SELECT
    cik,
    MAX(period_end_date) AS last_period
  FROM rev_pref
  GROUP BY cik
),

-- optional companion metrics at that same period
gp AS (
  SELECT cik, period_end_date, value AS gross_profit
  FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  WHERE concept = 'us-gaap:GrossProfit'
),
ni AS (
  SELECT cik, period_end_date, value AS net_income
  FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  WHERE concept = 'us-gaap:NetIncomeLoss'
)

SELECT
  lr.cik,
  COALESCE(r.ticker, d.ticker) AS ticker,        -- fill ticker from dimension if missing
  lr.last_period AS period_end_date,
  r.revenue,
  g.gross_profit,
  n.net_income,
  SAFE_DIVIDE(g.gross_profit, r.revenue) AS gross_margin,
  SAFE_DIVIDE(n.net_income, r.revenue)   AS net_margin
FROM last_rev_period lr
JOIN rev_pref r
  ON r.cik = lr.cik AND r.period_end_date = lr.last_period  -- guarantees non-null revenue
LEFT JOIN `sec-edgar-financials-warehouse.sec_curated_sec_curated.dim_company` d
  ON d.cik = lr.cik
LEFT JOIN gp g
  ON g.cik = lr.cik AND g.period_end_date = lr.last_period
LEFT JOIN ni n
  ON n.cik = lr.cik AND n.period_end_date = lr.last_period
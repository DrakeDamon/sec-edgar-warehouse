{{ config(
  materialized='table',
  partition_by={'field': 'period_end_date', 'data_type': 'date'},
  cluster_by=['cik'],
  schema=var('BQ_VIZ_DATASET', 'sec_viz')
) }}

WITH rev_candidates AS (
  SELECT cik, ticker, period_end_date, concept, unit, value
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
  AND period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 10 YEAR)
),
preferred AS (
  SELECT *,
         ROW_NUMBER() OVER (
           PARTITION BY cik, period_end_date
           ORDER BY CASE concept
             WHEN 'us-gaap:Revenues' THEN 1
             WHEN 'us-gaap:SalesRevenueNet' THEN 2
             WHEN 'us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax' THEN 3
             WHEN 'us-gaap:SalesRevenueGoodsNet' THEN 4
             WHEN 'us-gaap:SalesRevenueServicesNet' THEN 5
             ELSE 9 END,
             period_end_date DESC
         ) AS rn
  FROM rev_candidates
),
rev AS (
  SELECT cik, ticker, period_end_date, value AS revenue
  FROM preferred
  WHERE rn = 1
),
rev_with_ticker AS (
  SELECT
    r.cik,
    COALESCE(r.ticker, d.ticker) AS ticker,
    r.period_end_date,
    r.revenue
  FROM rev r
  LEFT JOIN `sec-edgar-financials-warehouse.sec_curated_sec_curated.dim_company` d
    ON d.cik = r.cik
)
SELECT
  cik, ticker, period_end_date,
  SUM(revenue) OVER (
    PARTITION BY cik
    ORDER BY period_end_date
    ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
  ) AS ttm_revenue
FROM rev_with_ticker
WHERE period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 10 YEAR)
QUALIFY ttm_revenue IS NOT NULL
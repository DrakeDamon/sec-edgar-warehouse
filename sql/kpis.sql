-- Example: TTM revenue (simple 4-quarter window)
WITH rev AS (
  SELECT cik, period_end_date, value
  FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
  WHERE concept IN ('us-gaap:Revenues','us-gaap:SalesRevenueNet')
)
SELECT
  cik,
  period_end_date,
  SUM(value) OVER (PARTITION BY cik ORDER BY period_end_date
                   ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS ttm_revenue
FROM rev;

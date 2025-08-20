-- Demonstrate partition pruning benefits

-- Query 1: Without partition filter (scans all data)
SELECT COUNT(*) as total_rows
FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`;

-- Query 2: With partition filter (only scans recent data)
SELECT COUNT(*) as recent_rows 
FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
WHERE period_end_date >= '2020-01-01';

-- Query 3: With partition + cluster filter (most efficient)
SELECT cik, concept, period_end_date, value
FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
WHERE period_end_date >= '2020-01-01' 
  AND cik = '0000320193'  -- AAPL
  AND concept = 'us-gaap:Revenues';
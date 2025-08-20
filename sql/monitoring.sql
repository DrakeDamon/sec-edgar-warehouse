-- Monitoring and audit queries for SEC EDGAR Warehouse

-- Daily load audit insert (schedule this to run after pipeline)
INSERT INTO `sec-edgar-financials-warehouse.sec_curated_sec_curated.load_audit`
SELECT 
  CURRENT_DATE() as date,
  'fct_financials_quarterly' as table_name,
  (SELECT COUNT(*) 
   FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.fct_financials_quarterly`
   WHERE period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)) as rowcount;

-- Data freshness validation (fails if today's load = 0)
SELECT 
  date,
  table_name,
  rowcount,
  CASE 
    WHEN rowcount = 0 THEN 'ALERT: No recent data loaded!'
    ELSE 'OK'
  END as status
FROM `sec-edgar-financials-warehouse.sec_curated_sec_curated.load_audit`
WHERE date = CURRENT_DATE()
ORDER BY date DESC;

-- Cost monitoring query (check bytes scanned)
SELECT 
  user_email,
  statement_type,
  COUNT(*) as query_count,
  ROUND(SUM(total_bytes_processed)/1e9, 2) as gb_scanned,
  ROUND(AVG(total_bytes_processed)/1e9, 2) as avg_gb_per_query
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND statement_type = 'SELECT'
  AND total_bytes_processed > 0
GROUP BY user_email, statement_type
ORDER BY gb_scanned DESC;

-- Partition efficiency check (should always use partition filter)
SELECT 
  job_id,
  user_email,
  query,
  total_bytes_processed,
  total_bytes_billed
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND query LIKE '%fct_financials_quarterly%'
  AND total_bytes_processed > 1000000000  -- Alert on >1GB scans
ORDER BY total_bytes_processed DESC;
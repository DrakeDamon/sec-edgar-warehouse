SELECT
  user_email,
  COUNT(*) AS queries,
  ROUND(SUM(total_bytes_processed)/1e9,2) AS gb_scanned
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND statement_type = 'SELECT'
GROUP BY user_email
ORDER BY gb_scanned DESC;

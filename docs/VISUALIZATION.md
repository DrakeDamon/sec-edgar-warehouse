# Visualization Guide

Complete guide for building dashboards and analytics using the SEC EDGAR Financials Warehouse visualization layer.

## Overview

The `sec_viz` dataset provides pre-aggregated, dashboard-ready tables optimized for business intelligence tools. All tables are designed for fast query performance and include complete data series without missing values.

## Dataset Structure

### Available Tables

| Table | Purpose | Rows | Refresh | Use Case |
|-------|---------|------|---------|----------|
| `kpi_company_latest` | Latest financial KPIs | 5 | Daily | Company comparison, current metrics |
| `kpi_ttm_revenue` | Rolling 12-month revenue | 98 | Daily | Trend analysis, time series |
| `company_dim` | Enhanced company info | 5 | Daily | Filtering, company lookup |

### Key Design Principles

1. **No NULLs**: Revenue-anchored logic ensures complete data series
2. **Ticker Complete**: Fallback logic guarantees ticker symbols for all rows
3. **Performance**: Partitioned/clustered for sub-second dashboard queries
4. **Business Logic**: Pre-calculated metrics ready for visualization

## Connecting to Looker Studio

### 1. Data Source Setup

**Connect to BigQuery**:
1. Open Looker Studio (https://datastudio.google.com)
2. Create new report → Add data → BigQuery
3. Select project: `sec-edgar-financials-warehouse`
4. Select dataset: `sec_viz`
5. Choose table: `kpi_company_latest` or `kpi_ttm_revenue`

**Connection Settings**:
```
Project ID: sec-edgar-financials-warehouse
Dataset: sec_viz
Tables: kpi_company_latest, kpi_ttm_revenue, company_dim
Authentication: Use service account with BigQuery Data Viewer role
```

### 2. Data Model Configuration

**Primary Metrics** (from `kpi_company_latest`):
- **Revenue**: Latest quarterly revenue (Currency, $M format)
- **Gross Margin**: Gross profit / revenue (Percent format)
- **Net Margin**: Net income / revenue (Percent format)

**Time Series Metrics** (from `kpi_ttm_revenue`):
- **TTM Revenue**: Trailing 12-month revenue (Currency, $B format)
- **Period End Date**: Quarter end date (Date format)

**Dimensions**:
- **Ticker**: Stock symbol (Text)
- **Company Name**: Full company name (Text, from company_dim)
- **CIK**: SEC identifier (Text, for joins)

### 3. Calculated Fields

**Revenue in Billions**:
```sql
ROUND(revenue / 1000000000, 2)
```

**Revenue Growth (TTM)**:
```sql
(ttm_revenue - LAG(ttm_revenue, 4)) / LAG(ttm_revenue, 4)
```

**Market Cap Proxy** (if stock price available):
```sql
stock_price * shares_outstanding
```

## Dashboard Templates

### 1. Executive Summary Dashboard

**Layout**: 4x3 grid with key metrics and trends

**Components**:
- **Scorecard Row**: Total revenue, avg margin, company count
- **Bar Chart**: Current quarter revenue by company
- **Line Chart**: TTM revenue trends (12 months)
- **Table**: Company rankings with key metrics

**Sample Queries**:

```sql
-- Current Quarter Metrics
SELECT 
  ticker,
  company_name,
  period_end_date,
  ROUND(revenue / 1000000, 2) as revenue_millions,
  ROUND(gross_margin * 100, 1) as gross_margin_pct
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_company_latest` k
JOIN `sec-edgar-financials-warehouse.sec_viz.company_dim` c USING (cik)
ORDER BY revenue DESC;

-- TTM Revenue Trends
SELECT 
  ticker,
  period_end_date,
  ROUND(ttm_revenue / 1000000000, 2) as ttm_revenue_billions
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
WHERE period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR)
ORDER BY ticker, period_end_date;
```

### 2. Company Deep Dive Dashboard

**Layout**: Single company focus with historical analysis

**Filters**:
- Company Ticker (dropdown)
- Date Range (last 2 years default)

**Components**:
- **Header**: Company name, latest quarter, data freshness
- **KPI Cards**: Revenue, margins, growth rates
- **Revenue Trend**: Quarterly and TTM revenue over time
- **Margin Analysis**: Gross and net margin trends
- **Data Quality**: Quarters available, completeness score

**Advanced Metrics**:

```sql
-- Quarter-over-Quarter Growth
SELECT 
  ticker,
  period_end_date,
  revenue,
  LAG(revenue, 1) OVER (PARTITION BY ticker ORDER BY period_end_date) as prev_quarter_revenue,
  ROUND(
    (revenue - LAG(revenue, 1) OVER (PARTITION BY ticker ORDER BY period_end_date)) 
    / LAG(revenue, 1) OVER (PARTITION BY ticker ORDER BY period_end_date) * 100, 
    1
  ) as qoq_growth_pct
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_company_latest`;

-- Seasonality Analysis
SELECT 
  ticker,
  EXTRACT(QUARTER FROM period_end_date) as quarter,
  AVG(ttm_revenue) as avg_ttm_revenue,
  STDDEV(ttm_revenue) as ttm_revenue_volatility
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
GROUP BY ticker, quarter
ORDER BY ticker, quarter;
```

### 3. Portfolio Overview Dashboard

**Layout**: Multi-company comparison and ranking

**Components**:
- **Ranking Table**: Companies sorted by TTM revenue
- **Scatter Plot**: Revenue vs. profitability
- **Heatmap**: Quarterly performance matrix
- **Distribution**: Revenue concentration analysis

**Key Visualizations**:

```sql
-- Portfolio Performance Matrix
SELECT 
  l.ticker,
  l.revenue as latest_revenue,
  t.ttm_revenue,
  l.gross_margin,
  l.net_margin,
  CASE 
    WHEN l.gross_margin > 0.3 AND t.ttm_revenue > 100000000000 THEN 'High Margin + High Revenue'
    WHEN l.gross_margin > 0.3 THEN 'High Margin'
    WHEN t.ttm_revenue > 100000000000 THEN 'High Revenue'
    ELSE 'Developing'
  END as performance_category
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_company_latest` l
JOIN (
  SELECT ticker, MAX(ttm_revenue) as ttm_revenue
  FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
  GROUP BY ticker
) t USING (ticker);
```

## Advanced Analytics Queries

### 1. Financial Ratios and Metrics

```sql
-- Comprehensive Financial Analysis
WITH metrics AS (
  SELECT 
    l.ticker,
    l.company_name,
    l.period_end_date,
    l.revenue,
    l.gross_profit,
    l.net_income,
    t.ttm_revenue,
    
    -- Profitability Ratios
    SAFE_DIVIDE(l.gross_profit, l.revenue) as gross_margin,
    SAFE_DIVIDE(l.net_income, l.revenue) as net_margin,
    
    -- Growth Metrics (TTM)
    LAG(t.ttm_revenue, 4) OVER (PARTITION BY t.ticker ORDER BY t.period_end_date) as ttm_revenue_yoy,
    
    -- Scale Metrics
    RANK() OVER (ORDER BY t.ttm_revenue DESC) as revenue_rank
    
  FROM `sec-edgar-financials-warehouse.sec_viz.kpi_company_latest` l
  JOIN `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue` t 
    ON l.ticker = t.ticker 
    AND l.period_end_date = t.period_end_date
)
SELECT 
  *,
  SAFE_DIVIDE(ttm_revenue - ttm_revenue_yoy, ttm_revenue_yoy) as ttm_growth_rate,
  CASE 
    WHEN revenue_rank <= 2 THEN 'Large Cap'
    WHEN revenue_rank <= 4 THEN 'Mid Cap'
    ELSE 'Small Cap'
  END as market_cap_category
FROM metrics
ORDER BY revenue_rank;
```

### 2. Trend Analysis

```sql
-- Revenue Trend Analysis with Statistical Metrics
WITH trend_analysis AS (
  SELECT 
    ticker,
    period_end_date,
    ttm_revenue,
    
    -- Moving averages
    AVG(ttm_revenue) OVER (
      PARTITION BY ticker 
      ORDER BY period_end_date 
      ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
    ) as ttm_4q_avg,
    
    -- Volatility metrics
    STDDEV(ttm_revenue) OVER (
      PARTITION BY ticker 
      ORDER BY period_end_date 
      ROWS BETWEEN 7 PRECEDING AND CURRENT ROW
    ) as ttm_8q_volatility,
    
    -- Trend direction
    LAG(ttm_revenue, 1) OVER (PARTITION BY ticker ORDER BY period_end_date) as prev_ttm,
    LAG(ttm_revenue, 4) OVER (PARTITION BY ticker ORDER BY period_end_date) as yoy_ttm
    
  FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
  WHERE period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 YEAR)
)
SELECT 
  ticker,
  period_end_date,
  ttm_revenue,
  ttm_4q_avg,
  ttm_8q_volatility,
  
  -- Growth rates
  SAFE_DIVIDE(ttm_revenue - prev_ttm, prev_ttm) as qoq_growth,
  SAFE_DIVIDE(ttm_revenue - yoy_ttm, yoy_ttm) as yoy_growth,
  
  -- Trend signals
  CASE 
    WHEN ttm_revenue > ttm_4q_avg * 1.05 THEN 'Accelerating'
    WHEN ttm_revenue < ttm_4q_avg * 0.95 THEN 'Decelerating'
    ELSE 'Stable'
  END as trend_signal
  
FROM trend_analysis
ORDER BY ticker, period_end_date DESC;
```

### 3. Comparative Analysis

```sql
-- Peer Comparison and Benchmarking
WITH peer_metrics AS (
  SELECT 
    ticker,
    revenue,
    gross_margin,
    net_margin,
    
    -- Peer percentiles
    PERCENT_RANK() OVER (ORDER BY revenue) as revenue_percentile,
    PERCENT_RANK() OVER (ORDER BY gross_margin) as margin_percentile,
    
    -- Peer averages
    AVG(revenue) OVER () as peer_avg_revenue,
    AVG(gross_margin) OVER () as peer_avg_margin
    
  FROM `sec-edgar-financials-warehouse.sec_viz.kpi_company_latest`
  WHERE revenue IS NOT NULL AND gross_margin IS NOT NULL
)
SELECT 
  ticker,
  revenue,
  gross_margin,
  
  -- Relative positioning
  ROUND(revenue_percentile * 100, 1) as revenue_percentile,
  ROUND(margin_percentile * 100, 1) as margin_percentile,
  
  -- Vs peer average
  ROUND((revenue / peer_avg_revenue - 1) * 100, 1) as revenue_vs_peer_pct,
  ROUND((gross_margin / peer_avg_margin - 1) * 100, 1) as margin_vs_peer_pct,
  
  -- Competitive position
  CASE 
    WHEN revenue_percentile > 0.8 AND margin_percentile > 0.6 THEN 'Market Leader'
    WHEN revenue_percentile > 0.6 OR margin_percentile > 0.8 THEN 'Strong Performer'
    WHEN revenue_percentile > 0.4 AND margin_percentile > 0.4 THEN 'Competitive'
    ELSE 'Challenging Position'
  END as competitive_position
  
FROM peer_metrics
ORDER BY revenue_percentile DESC;
```

## Data Visualization Best Practices

### 1. Chart Type Recommendations

**Revenue Trends**:
- **Line Chart**: Time series of TTM revenue
- **Bar Chart**: Quarterly revenue comparison
- **Area Chart**: Revenue composition (if multiple revenue streams)

**Profitability Analysis**:
- **Scatter Plot**: Revenue vs. margin analysis
- **Dual-axis Chart**: Revenue (bars) and margin (line) over time
- **Heatmap**: Margin trends across companies and quarters

**Comparative Analysis**:
- **Horizontal Bar**: Company rankings
- **Bullet Chart**: Performance vs. targets
- **Box Plot**: Distribution analysis across peer group

### 2. Color Coding Standards

**Performance Indicators**:
- 🟢 Green: Above benchmark/positive growth
- 🟡 Yellow: At benchmark/stable
- 🔴 Red: Below benchmark/declining

**Company Categories**:
- 🔵 Blue: Technology (AAPL, MSFT, GOOGL)
- 🟠 Orange: E-commerce (AMZN)
- 🟣 Purple: Electric Vehicles (NVDA - data/AI)

### 3. Formatting Guidelines

**Currency Values**:
- Revenue: Display in millions ($123.4M) or billions ($1.23B)
- Use consistent units across charts
- Include currency symbol and unit label

**Percentages**:
- Margins: Display as percentages (23.4%)
- Growth rates: Include +/- sign (+12.3%)
- Use one decimal place for precision

**Dates**:
- Quarter format: Q1 2024, Q2 2024
- Full date for detailed analysis: Mar 31, 2024
- Consistent date ranges across charts

## Performance Optimization for Dashboards

### 1. Query Optimization

**Use Partition Filters**:
```sql
-- Good: Uses partition filter
SELECT * FROM kpi_ttm_revenue 
WHERE period_end_date >= '2023-01-01';

-- Avoid: Full table scan
SELECT * FROM kpi_ttm_revenue 
WHERE ticker = 'AAPL';
```

**Leverage Pre-aggregated Data**:
```sql
-- Good: Use pre-calculated TTM
SELECT ticker, ttm_revenue FROM kpi_ttm_revenue;

-- Avoid: Real-time calculation
SELECT ticker, SUM(revenue) OVER (...) FROM fct_financials_quarterly;
```

### 2. Dashboard Caching

**Looker Studio Settings**:
- Enable data caching (4-hour refresh for daily data)
- Use incremental refresh for large datasets
- Cache dashboard at report level

**BigQuery Settings**:
- Query results cached automatically for 24 hours
- Use table clustering for repeated filter patterns
- Monitor query performance in BigQuery console

### 3. Data Freshness Monitoring

```sql
-- Check data freshness
SELECT 
  table_name,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_modified_time, HOUR) as hours_since_update
FROM `sec_viz.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN ('kpi_company_latest', 'kpi_ttm_revenue')
ORDER BY last_modified_time DESC;
```

## Troubleshooting Common Issues

### 1. Missing Data

**Symptoms**: NULL values in revenue or margins
**Cause**: Company missing revenue data for latest period
**Solution**: Check `company_dim.data_completeness` field

```sql
-- Diagnose data completeness
SELECT 
  ticker,
  data_completeness,
  revenue_quarters_count,
  latest_filing_date
FROM `sec_viz.company_dim`
WHERE data_completeness != 'Active';
```

### 2. Performance Issues

**Symptoms**: Slow dashboard loading (>10 seconds)
**Cause**: Inefficient queries or large date ranges
**Solutions**:
- Add date filters to limit data scanned
- Use pre-aggregated tables instead of raw facts
- Check BigQuery query execution details

### 3. Data Inconsistencies

**Symptoms**: Different values between tables
**Cause**: Different calculation logic or timing
**Solution**: Verify join keys and calculation methods

```sql
-- Validate consistency between tables
SELECT 
  l.ticker,
  l.revenue as latest_revenue,
  t.ttm_revenue / 4 as avg_quarterly_ttm,
  ABS(l.revenue - t.ttm_revenue / 4) / l.revenue as variance_pct
FROM `sec_viz.kpi_company_latest` l
JOIN (
  SELECT ticker, MAX(ttm_revenue) as ttm_revenue 
  FROM `sec_viz.kpi_ttm_revenue` 
  GROUP BY ticker
) t USING (ticker)
WHERE ABS(l.revenue - t.ttm_revenue / 4) / l.revenue > 0.1;  -- >10% variance
```

## Integration with Other Tools

### 1. Tableau Connection

```sql
-- Tableau data source configuration
Server: https://bigquery.cloud.google.com
Project: sec-edgar-financials-warehouse
Dataset: sec_viz
Authentication: Service Account (JSON key file)
```

### 2. Power BI Connection

```sql
-- Power BI BigQuery connector
Data Source: Google BigQuery
Project: sec-edgar-financials-warehouse
Dataset: sec_viz
Connection Mode: DirectQuery (for real-time data)
```

### 3. Python/R Analysis

```python
# Python connection example
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='sec-edgar-financials-warehouse')

query = """
SELECT * FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
WHERE period_end_date >= '2023-01-01'
"""

df = client.query(query).to_dataframe()
```

## Future Enhancements

### Planned Additions

1. **Additional Metrics**:
   - Cash flow statements data
   - Balance sheet ratios
   - Valuation multiples

2. **Enhanced Dimensions**:
   - Industry classification
   - Geographic segments
   - Business segment breakdowns

3. **Advanced Analytics**:
   - Predictive models for revenue forecasting
   - Anomaly detection for unusual patterns
   - Peer group analysis automation
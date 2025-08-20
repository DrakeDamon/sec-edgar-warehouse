# SEC EDGAR Financials Warehouse

A modern data warehouse for SEC financial data using Google Cloud Platform, BigQuery, dbt, and Great Expectations.

## Features
- 🏗️ **Infrastructure as Code**: Automated GCP setup and configuration
- 📊 **Data Pipeline**: SEC API → GCS → BigQuery → dbt transformations
- 🧪 **Data Quality**: Great Expectations validation and testing
- 🚀 **Deployment**: Docker + Cloud Run for production workloads
- 💰 **Cost Optimization**: Partitioned and clustered tables for performance

## Architecture
```
SEC API → GCS (raw) → BigQuery (raw) → dbt (curated) → GE (validation) → BI Tools
```

## Quick Start
1. `cp .env.example .env` and configure your GCS bucket
2. `make setup` - Install dependencies
3. `make all` - Run full pipeline

## Datasets
- **Raw**: `sec_raw.raw_companyfacts`, `sec_raw.raw_submissions`
- **Curated**: `sec_curated.dim_company`, `sec_curated.dim_concept`, `sec_curated.fct_financials_quarterly`

## Cost Optimization
- Date partitioning on `period_end_date`
- Clustering by `cik` and `concept`
- Query filtering reduces bytes scanned by 90%+

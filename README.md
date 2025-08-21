# SEC EDGAR Financials Warehouse

A production-ready data warehouse that automatically ingests, processes, and analyzes SEC EDGAR financial data for public companies. Built with modern data engineering practices including dbt, BigQuery, and automated data quality validation.

## 🎯 **Project Overview**

**Status:** ✅ Operational | **dbt tests:** 14/14 | **GE:** 100% pass  
**Partition/Cluster:** ✔ `period_end_date` / (`cik`,`concept`) (require_partition_filter: **off**)  
**Automation:** ✔ Cloud Run Job + GitHub Actions (06:00 UTC daily)  
**Visualization:** ✔ Clean `sec_viz` dataset with 98 TTM revenue calculations

### Key Features
- **Automated Daily Pipeline**: GitHub Actions triggers Cloud Run jobs at 06:00 UTC
- **Robust Data Quality**: 14 dbt tests + Great Expectations validation
- **Cost-Optimized**: BigQuery partitioning/clustering with performance monitoring
- **Dashboard-Ready**: Clean visualization layer in `sec_viz` dataset
- **Production Hardened**: Comprehensive error handling and monitoring

## 🏗️ **Architecture**

```
SEC EDGAR API → GCS → BigQuery Raw → dbt → BigQuery Curated → Visualization
     ↓              ↓         ↓         ↓            ↓              ↓
Rate-Limited   NDJSON    Raw Tables   Clean      Analytics     Looker Studio
 Ingestion     Storage   (sec_raw)   Models    (sec_viz)      Dashboards
```

### Data Flow
1. **Ingestion**: Python scripts fetch data from SEC EDGAR API with rate limiting
2. **Storage**: Raw NDJSON files stored in Google Cloud Storage  
3. **Loading**: Batch load into BigQuery raw tables with schema validation
4. **Transformation**: dbt models create clean, tested analytical datasets
5. **Quality**: Great Expectations validates data quality and business rules
6. **Visualization**: Pre-aggregated tables optimized for dashboard consumption

## 📊 **Datasets**

| Layer | Dataset | Purpose | Key Tables |
|-------|---------|---------|------------|
| **Raw** | `sec_raw` | Source data | `raw_companyfacts`, `raw_submissions` |
| **Curated** | `sec_curated_sec_curated` | Clean business logic | `dim_company`, `fct_financials_quarterly` |  
| **Visualization** | `sec_viz` | Dashboard-ready | `kpi_company_latest`, `kpi_ttm_revenue` |

### Schema Details
- **Partitioned**: All fact tables partitioned by `period_end_date` 
- **Clustered**: Optimized clustering on `cik` and `concept` for fast queries
- **Tested**: Every model includes comprehensive dbt tests for data quality

## 🚀 **Quick Start**

### Prerequisites
- Google Cloud Project with BigQuery, Cloud Storage, Cloud Run APIs enabled
- Python 3.9+, dbt-bigquery, Great Expectations
- GitHub repository with `SA_JSON` secret configured

### Local Development
```bash
# 1. Environment setup
cp .env.example .env
# Edit .env with your GCP project and bucket details

# 2. Install and run pipeline
make setup && make ingest && make load && make dbt-build && make ge

# 3. Validate everything works
bash tools/smoke_check.sh
```

### Production Deployment
```bash
# 1. Deploy to Cloud Run
bash deploy/cloud_run_deploy.sh

# 2. Verify GitHub Actions workflow
# Check .github/workflows/schedule.yml runs at 06:00 UTC daily
```

## 📈 **Visualization Layer**

The `sec_viz` dataset provides dashboard-ready tables:

- **`kpi_company_latest`**: Latest financial KPIs per company (5 rows)
- **`kpi_ttm_revenue`**: Trailing twelve months revenue (98 rows)  
- **`company_dim`**: Enhanced company dimension for filtering

### Key Features
- **Revenue-Anchored**: KPIs anchored to latest period WITH revenue data
- **Ticker Complete**: Fallback logic ensures no missing ticker symbols
- **Performance Optimized**: Partitioned/clustered for fast dashboard queries

## 🔧 **Daily Operations**

### Automated Schedule
- **Frequency**: Daily at 06:00 UTC via GitHub Actions
- **Workflow**: `.github/workflows/schedule.yml`
- **Job**: `sec-pipeline-job` in Cloud Run (us-central1)
- **Monitoring**: Comprehensive smoke checks validate pipeline health

### Manual Operations
```bash
# Run visualization models only
export DBT_PROFILES_DIR=./dbt
dbt build --select marts_viz

# Run full pipeline locally  
make all

# Validate infrastructure
bash tools/smoke_check.sh
```

## 📋 **Data Quality**

### Automated Testing
- **14 dbt tests**: Schema validation, uniqueness, relationships
- **Great Expectations**: Business rule validation and data profiling
- **Smoke checks**: Infrastructure and data health validation

### Cost Monitoring
```sql
-- Run cost analysis
SELECT * FROM `project.sec_curated_sec_curated.cost_analysis_view`;
```

## 📚 **Documentation**

- **[Architecture Guide](docs/ARCHITECTURE.md)**: Detailed system design and components
- **[Deployment Guide](docs/DEPLOYMENT.md)**: Step-by-step setup instructions  
- **[Data Models](docs/DATA_MODELS.md)**: dbt schema and transformation logic
- **[Visualization Guide](docs/VISUALIZATION.md)**: Dashboard setup and Looker Studio integration

## 🛠️ **Development**

### Project Structure
```
sec-edgar-warehouse/
├── src/                    # Python pipeline code
├── dbt/                    # dbt models and tests  
├── tools/                  # Validation and utility scripts
├── .github/workflows/      # CI/CD automation
├── deploy/                 # Cloud deployment scripts
└── docs/                   # Comprehensive documentation
```

### Key Commands
```bash
make setup          # Install dependencies
make ingest         # Fetch SEC data
make dbt-build      # Run dbt transformations  
make dbt-viz        # Build visualization models only
make ge             # Run data quality checks
make test           # Run Python tests
```

## 🔐 **Security & Compliance**

- **Authentication**: Google Cloud service account with minimal IAM permissions
- **Data Privacy**: Only public SEC filing data, no PII
- **Cost Controls**: Query monitoring and partition filtering
- **Audit Trail**: Comprehensive logging in `load_audit` table

## 🆘 **Troubleshooting**

### Common Issues
- **Authentication**: Ensure `SA_JSON` GitHub secret is configured
- **BigQuery Costs**: Verify partition filters in dashboard queries
- **Data Quality**: Check `tools/smoke_check.sh` output for failures

### Support
- Issues: [GitHub Issues](https://github.com/DrakeDamon/sec-edgar-warehouse/issues)
- Documentation: `docs/` directory
- Monitoring: Cloud Run logs and BigQuery audit logs

---

**Built with**: Python • dbt • BigQuery • GitHub Actions • Great Expectations • Looker Studio
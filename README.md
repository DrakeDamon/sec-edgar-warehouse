SEC EDGAR Financials Warehouse

A production-ready data warehouse that ingests, transforms, and visualizes SEC EDGAR company financials. Built with BigQuery, dbt, and automated data-quality checks.

🎯 Project Overview

Status: ✅ Operational · dbt tests: 14/14 · GE: 100%
Partition/Cluster: period_end_date / (cik, concept)
Automation: GitHub Actions (daily 06:00 UTC) (Cloud Run job optional)
Visualization: sec_viz dataset powering Looker Studio

Key Features

Daily pipeline: GitHub Actions runs ingestion → dbt builds → viz refresh

Quality gates: dbt tests + Great Expectations + smoke checks

Cost control: Partition pruning + clustering; bytes-scanned proof queries

Dashboard-ready: Pre-aggregated sec_viz tables (TTM, latest KPIs)

Ops-ready: Dockerized jobs, logs, and runbooks

🏗️ Architecture
SEC EDGAR API → GCS → BigQuery (sec*raw) → dbt → BigQuery (sec_curated*\*) → BigQuery (sec_viz) → Looker Studio

Data Flow

Ingestion — Python with SEC rate limiting → GCS

Load — NDJSON → BigQuery sec_raw

Transform — dbt → sec*curated*\* facts/dims

Validate — GE + dbt tests

Viz — sec_viz tables for BI

📊 Datasets
Layer Dataset Purpose Key Tables
Raw sec_raw Source landings raw_companyfacts, raw_submissions
Curated sec_curated_sec_curated Business logic dim_company, fct_financials_quarterly
Visualization sec_viz Dashboard-ready kpi_company_latest, kpi_ttm_revenue, company_dim

Notes

Facts partitioned by period_end_date and clustered by cik (and concept upstream).

sec_viz is optimized for BI; row counts vary by data window.

🚀 Quick Start
Prereqs

GCP project with BigQuery, GCS (and Cloud Run if used)

Python 3.9+, dbt-bigquery, Great Expectations

GitHub repo with SA_JSON secret (service account key JSON)

Local Dev

# 1) Env

cp .env.example .env # set PROJECT_ID, DATASETs, BUCKET

# 2) Run pipeline

make setup && make ingest && make load && make dbt-build && make ge

# 3) Smoke test

bash tools/smoke_check.sh

CI/CD

# Deploy Cloud Run (optional)

bash deploy/cloud_run_deploy.sh

# GitHub Actions

# .github/workflows/schedule.yml — runs daily at 06:00 UTC

📈 Visualization Layer (sec_viz)

kpi_company_latest — Latest period with revenue per company (KPIs + margins)

kpi_ttm_revenue — TTM revenue (rolling 4 quarters), ticker filled via dim_company

company_dim — Ticker/name metadata for labels/filters

Looker Studio tips

Data source → BigQuery → set Processing location = US, Credentials = Owner’s credentials, Data freshness = 15–60 min

Time series: Dimension period_end_date, Breakdown ticker, Metric ttm_revenue (or ttm_revenue/1e9 as “TTM Revenue ($B)”)

🔧 Operations

Scheduler: GitHub Actions daily (06:00 UTC)

Manual:

export DBT_PROFILES_DIR=./dbt
dbt build --select marts_viz # build only viz tables
make all # end-to-end locally
bash tools/smoke_check.sh # infra + data smoke test

📋 Data Quality

dbt: not_null/unique/relationships on core columns

GE: rule suites for schema + value ranges

Monitoring: smoke script checks dataset health and viz row counts

💰 Cost & Performance

Always filter by date (hits the period_end_date partition); add ticker for clustering benefits.

Sample bytes-scanned proof:

-- Unfiltered (larger)
SELECT SUM(ttm_revenue) FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`;

-- Partition-pruned (smaller)
SELECT SUM(ttm_revenue)
FROM `sec-edgar-financials-warehouse.sec_viz.kpi_ttm_revenue`
WHERE period_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR);

📚 Docs

docs/ARCHITECTURE.md — design & components

docs/DEPLOYMENT.md — setup & CI/CD

docs/DATA_MODELS.md — dbt model notes

docs/VISUALIZATION.md — dashboard how-to

🛠️ Dev Structure
sec-edgar-warehouse/
├─ src/ # ingestion/load
├─ dbt/ # models, tests, macros
├─ tools/ # smoke_check.sh, utilities
├─ deploy/ # Cloud Run, infra scripts
└─ .github/workflows/ # CI/CD

🔐 Security

Least-privilege service account; no secrets in logs

Public data only (no PII)

Audit via Cloud Logging + dbt/GE artifacts

🆘 Troubleshooting

Auth: verify SA_JSON secret & dataset IAM

BigQuery costs: ensure date filters on fact/viz queries

Data gaps: run tools/smoke_check.sh and dbt tests

Built with: Python · dbt · BigQuery · GitHub Actions · Great Expectations · Looker Studio

# SEC EDGAR Financials Warehouse

**Status:** ✅ Operational &nbsp;|&nbsp; **dbt tests:** 14/14 &nbsp;|&nbsp; **GE:** 100% pass  
**Partition/Cluster:** ✔ `period_end_date` / (`cik`, `concept`)  
**Cost guardrails:** ✔ INFORMATION_SCHEMA bytes scanned monitor

## Scheduling
This repo includes a daily schedule via **GitHub Actions** that executes the Cloud Run Job:
- Workflow: `.github/workflows/schedule.yml` (06:00 UTC daily)
- Secret needed: `SA_JSON` (service account key JSON)
- The job name is `sec-pipeline-job` in region `us-central1`.

## Quickstart
1) `cp .env.example .env` and set `GCS_BUCKET` to your bucket.
2) `make setup && make ingest && make load && make dbt-build && make ge`
3) Run `bash tools/smoke_check.sh` to validate infra, models, and DQ.

## Datasets
- Raw: `sec_raw.raw_companyfacts`, `sec_raw.raw_submissions`
- Curated: `sec_curated.dim_company`, `sec_curated.dim_concept`, `sec_curated.fct_financials_quarterly`

## Cost Proof
Run `sql/cost_views.sql`. Compare bytes scanned for filtered vs unfiltered queries to verify partition/clustering effectiveness.
# SEC EDGAR Financials Warehouse (GCP + BigQuery + dbt + GE)

## Quickstart
1) `cp .env.example .env` and set `GCS_BUCKET` (use the bucket you created), keep project id.
2) `make setup`
3) `make ingest && make load`
4) `make dbt-build`
5) `make ge`

## Datasets
- Raw: `sec_raw.raw_companyfacts`, `sec_raw.raw_submissions`
- Curated: `sec_curated.dim_company`, `sec_curated.dim_concept`, `sec_curated.fct_financials_quarterly`

## Cost Proof
Run the SQL in `sql/cost_views.sql`, filter queries to last 7 days.

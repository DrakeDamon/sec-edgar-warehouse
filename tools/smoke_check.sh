#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
PROJECT="sec-edgar-financials-warehouse"
REGION="${REGION:-us-central1}"
BQ_LOC="${BQ_LOC:-US}"
RAW_DS="${RAW_DS:-sec_raw}"
CUR_DS="${CUR_DS:-sec_curated_sec_curated}"  # dbt creates this nested dataset name
JOB_NAME="${JOB_NAME:-sec-pipeline-job}"
REPO_DIR="${REPO_DIR:-.}"

# Load .env if present to pick up GCS_BUCKET etc.
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a; source "$REPO_DIR/.env"; set +a
fi

# ===== Helpers =====
RED="$(tput setaf 1 || true)"; GREEN="$(tput setaf 2 || true)"; YELLOW="$(tput setaf 3 || true)"; RESET="$(tput sgr0 || true)"
pass() { echo -e "${GREEN}✔ $*${RESET}"; }
warn() { echo -e "${YELLOW}● $*${RESET}"; }
fail() { echo -e "${RED}✖ $*${RESET}"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

echo "== Smoke Check: SEC EDGAR Warehouse =="
echo "Project: $PROJECT   Region: $REGION   BQ Location: $BQ_LOC"
echo

# ===== Preflight =====
need gcloud
need bq
need python
need grep
need sed
need awk

# Ensure correct project
gcloud config set project "$PROJECT" >/dev/null
pass "gcloud project set to $PROJECT"

# ===== Check APIs enabled =====
APIS=(bigquery.googleapis.com storage.googleapis.com run.googleapis.com cloudscheduler.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com logging.googleapis.com)
ENABLED="$(gcloud services list --enabled --format='value(config.name)')"
for api in "${APIS[@]}"; do
  echo "$ENABLED" | grep -q "$api" && pass "API enabled: $api" || warn "API NOT enabled (may be okay if unused today): $api"
done

# ===== Check resources =====
echo
echo "== Storage bucket =="
if [[ -z "${GCS_BUCKET:-}" ]]; then
  # Try to infer bucket (first bucket containing 'sec-edgar-data')
  GCS_BUCKET="$(gcloud storage buckets list --format='value(name)' | grep -m1 'sec-edgar-data' || true)"
fi
[[ -n "${GCS_BUCKET:-}" ]] || fail "No GCS_BUCKET set and none inferred."
gcloud storage buckets describe "gs://$GCS_BUCKET" --format='value(location)' >/dev/null && pass "Bucket exists: gs://$GCS_BUCKET" || fail "Bucket missing: gs://$GCS_BUCKET"

echo
echo "== BigQuery datasets =="
bq --location="$BQ_LOC" ls "$RAW_DS" >/dev/null 2>&1 && pass "Dataset exists: $RAW_DS" || fail "Missing dataset: $RAW_DS"
bq --location="$BQ_LOC" ls "$CUR_DS" >/dev/null 2>&1 && pass "Dataset exists: $CUR_DS" || fail "Missing dataset: $CUR_DS"

echo
echo "== Raw tables rowcounts =="
RCF=$(bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv "SELECT COUNT(1) FROM \`$PROJECT.$RAW_DS.raw_companyfacts\`" | tail -n1 || echo "0")
RSUB=$(bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv "SELECT COUNT(1) FROM \`$PROJECT.$RAW_DS.raw_submissions\`" | tail -n1 || echo "0")
[[ "$RCF" =~ ^[0-9]+$ ]] || RCF=0; [[ "$RSUB" =~ ^[0-9]+$ ]] || RSUB=0
(( RCF > 0 )) && pass "raw_companyfacts rows: $RCF" || fail "raw_companyfacts is empty"
(( RSUB > 0 )) && pass "raw_submissions rows: $RSUB" || fail "raw_submissions is empty"

echo
echo "== Curated models existence =="
for tbl in dim_company dim_concept fct_financials_quarterly; do
  bq --location="$BQ_LOC" show "$PROJECT:$CUR_DS.$tbl" >/dev/null 2>&1 && pass "Found $CUR_DS.$tbl" || fail "Missing $CUR_DS.$tbl"
done

echo
echo "== Partitioning & Clustering on fct_financials_quarterly =="
BQSHOW="$(bq --location="$BQ_LOC" show --format=prettyjson "$PROJECT:$CUR_DS.fct_financials_quarterly")"
echo "$BQSHOW" | grep -q '"timePartitioning"' && pass "Has timePartitioning" || fail "No timePartitioning"
echo "$BQSHOW" | grep -q '"field": "period_end_date"' && pass "Partition field = period_end_date" || warn "Partition field not detected as period_end_date"
echo "$BQSHOW" | grep -q '"clustering"' && pass "Has clustering" || warn "No clustering found"
echo "$BQSHOW" | grep -q '"clusteringFields": \[ "cik", "concept" \]' && pass "Cluster fields = (cik, concept)" || warn "Cluster fields differ from expected"

echo
echo "== dbt build (smoke) =="
if [[ -d "$REPO_DIR/dbt" ]]; then
  pushd "$REPO_DIR" >/dev/null
  export DBT_PROFILES_DIR=./dbt
  if [[ -f "./.venv/bin/activate" ]]; then source ./.venv/bin/activate; fi
  dbt --version >/dev/null 2>&1 || warn "dbt not in current environment; attempting anyway"
  dbt build --project-dir ./dbt --profiles-dir ./dbt || fail "dbt build failed"
  popd >/dev/null
  pass "dbt build succeeded"
else
  warn "dbt folder not found under $REPO_DIR (skipping build)"
fi

echo
echo "== Great Expectations check =="
if [[ -f "$REPO_DIR/src/dq/run_ge_checks.py" ]]; then
  pushd "$REPO_DIR" >/dev/null
  if [[ -f "./.venv/bin/activate" ]]; then source ./.venv/bin/activate; fi
  python src/dq/run_ge_checks.py || fail "GE validation failed"
  popd >/dev/null
  pass "GE validation succeeded"
else
  warn "GE runner not found (skipping)"
fi

echo
echo "== INFORMATION_SCHEMA cost view (last 7 days) =="
bq --location="$BQ_LOC" query --use_legacy_sql=false --format=prettyjson "SELECT user_email, COUNT(*) AS queries, ROUND(SUM(total_bytes_processed)/1e9,2) AS gb_scanned FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_USER WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY) AND statement_type='SELECT' GROUP BY user_email ORDER BY gb_scanned DESC LIMIT 20" >/dev/null \
  && pass "Cost view query executed" || warn "Cost view query failed (may require recent SELECT activity)"

echo
echo "== KPI query (TTM revenue sample) =="
bq --location="$BQ_LOC" query --use_legacy_sql=false --format=prettyjson "WITH rev AS ( SELECT cik, period_end_date, value FROM \`$PROJECT.$CUR_DS.fct_financials_quarterly\` WHERE concept IN ('us-gaap:Revenues','us-gaap:SalesRevenueNet') ) SELECT cik, period_end_date, SUM(value) OVER (PARTITION BY cik ORDER BY period_end_date ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS ttm_revenue FROM rev LIMIT 20" >/dev/null \
  && pass "KPI query executed" || warn "KPI query failed"

echo
echo "== Cloud Run Job (optional) =="
if gcloud run jobs describe "$JOB_NAME" --region="$REGION" >/dev/null 2>&1; then
  pass "Found Cloud Run Job: $JOB_NAME"
  LAST=$(gcloud run jobs executions list --job="$JOB_NAME" --region="$REGION" --format='value(STATUS)')
  echo "Recent execution status: ${LAST:-none}"
else
  warn "Cloud Run Job '$JOB_NAME' not found (ok if not set up)"
fi

echo
echo "== Artifact Registry images (optional) =="
if gcloud artifacts repositories list --format='value(name)' | grep -q "^containers$"; then
  gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT/containers" --format='table(NAME,DIGEST,CREATE_TIME)' || true
  pass "Artifact Registry reachable"
else
  warn "Repository 'containers' not found (ok if not using Cloud Run yet)"
fi

echo
pass "All checks completed."
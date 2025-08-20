#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
PROJECT="sec-edgar-financials-warehouse"
REGION="${REGION:-us-central1}"
BQ_LOC="${BQ_LOC:-US}"
RAW_DS="${RAW_DS:-sec_raw}"
CUR_DS="${CUR_DS:-sec_curated}"
JOB_NAME="${JOB_NAME:-sec-pipeline-job}"
REPO_DIR="${REPO_DIR:-sec-edgar-warehouse}"

# Load .env if present (for GCS_BUCKET, etc.)
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

gcloud config set project "$PROJECT" >/dev/null
pass "gcloud project set to $PROJECT"

# ===== APIs =====
APIS=(bigquery.googleapis.com storage.googleapis.com run.googleapis.com cloudscheduler.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com logging.googleapis.com)
ENABLED="$(gcloud services list --enabled --format='value(config.name)')"
for api in "${APIS[@]}"; do
  echo "$ENABLED" | grep -q "$api" && pass "API enabled: $api" || warn "API NOT enabled (ok if unused today): $api"
done

# ===== Storage bucket =====
if [[ -z "${GCS_BUCKET:-}" ]]; then
  GCS_BUCKET="$(gcloud storage buckets list --format='value(name)' | grep -m1 'sec-edgar-data' || true)"
fi
[[ -n "${GCS_BUCKET:-}" ]] || fail "No GCS_BUCKET set and none inferred."
gcloud storage buckets describe "gs://$GCS_BUCKET" --format='value(location)' >/dev/null && pass "Bucket exists: gs://$GCS_BUCKET" || fail "Bucket missing: gs://$GCS_BUCKET"

# ===== Datasets =====
bq ls "$RAW_DS" >/dev/null 2>&1 && pass "Dataset exists: $RAW_DS" || fail "Missing dataset: $RAW_DS"
bq ls "$CUR_DS" >/dev/null 2>&1 && pass "Dataset exists: $CUR_DS" || fail "Missing dataset: $CUR_DS"

# ===== Raw tables rowcounts =====
RCF=$(bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv "SELECT COUNT(1) FROM \`$PROJECT.$RAW_DS.raw_companyfacts\`" | tail -n1 || echo "0")
RSUB=$(bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv "SELECT COUNT(1) FROM \`$PROJECT.$RAW_DS.raw_submissions\`" | tail -n1 || echo "0")
[[ "$RCF" =~ ^[0-9]+$ ]] || RCF=0; [[ "$RSUB" =~ ^[0-9]+$ ]] || RSUB=0
(( RCF > 0 )) && pass "raw_companyfacts rows: $RCF" || fail "raw_companyfacts is empty"
(( RSUB > 0 )) && pass "raw_submissions rows: $RSUB" || fail "raw_submissions is empty"

# ===== Curated tables =====
# Check if tables exist in dbt-generated schema first, then original schema
for tbl in dim_company dim_concept fct_financials_quarterly; do
  if bq --location="$BQ_LOC" show "$PROJECT:${CUR_DS}_${CUR_DS}.$tbl" >/dev/null 2>&1; then
    pass "Found ${CUR_DS}_${CUR_DS}.$tbl"
  elif bq --location="$BQ_LOC" show "$PROJECT:$CUR_DS.$tbl" >/dev/null 2>&1; then
    pass "Found $CUR_DS.$tbl"
  else
    fail "Missing $tbl in both $CUR_DS and ${CUR_DS}_${CUR_DS}"
  fi
done

# ===== Partition & Cluster checks =====
# Check dbt-generated schema first, then original schema
if bq --location="$BQ_LOC" show "$PROJECT:${CUR_DS}_${CUR_DS}.fct_financials_quarterly" >/dev/null 2>&1; then
  BQSHOW="$(bq --location="$BQ_LOC" show --format=prettyjson "$PROJECT:${CUR_DS}_${CUR_DS}.fct_financials_quarterly")"
else
  BQSHOW="$(bq --location="$BQ_LOC" show --format=prettyjson "$PROJECT:$CUR_DS.fct_financials_quarterly")"
fi
echo "$BQSHOW" | grep -q '"timePartitioning"' && pass "Has timePartitioning" || fail "No timePartitioning"
echo "$BQSHOW" | grep -q '"field": "period_end_date"' && pass "Partition field = period_end_date" || warn "Partition field not detected as period_end_date"
echo "$BQSHOW" | grep -q '"clustering"' && pass "Has clustering" || warn "No clustering found"

CLUSTER_FIELDS=$(python - <<'PY'
import sys,json
d=json.load(sys.stdin)
print(",".join(d.get("clustering",{}).get("fields",[])))
PY
<<<"$BQSHOW")

if [ -n "$CLUSTER_FIELDS" ]; then
  echo "Cluster fields: $CLUSTER_FIELDS"
  case "$CLUSTER_FIELDS" in
    "cik,concept"|"concept,cik") pass "Cluster fields detected";;
    *) warn "Cluster fields differ from expected (got: $CLUSTER_FIELDS)";;
  esac
else
  warn "No cluster fields reported"
fi

# ===== dbt smoke =====
if [[ -d "$REPO_DIR/dbt" ]]; then
  pushd "$REPO_DIR" >/dev/null
  export DBT_PROFILES_DIR=./dbt
  if [[ -f "./.venv/bin/activate" ]]; then source ./.venv/bin/activate; fi
  dbt --version >/dev/null 2>&1 || warn "dbt not in current environment; attempting anyway"
  dbt build --project-dir ./dbt --profiles-dir ./dbt || fail "dbt build failed"
  popd >/dev/null
  pass "dbt build succeeded"
else
  warn "dbt folder not found (skipping build)"
fi

# ===== Great Expectations =====
if [[ -f "$REPO_DIR/src/dq/run_ge_checks.py" ]]; then
  pushd "$REPO_DIR" >/dev/null
  if [[ -f "./.venv/bin/activate" ]]; then source ./.venv/bin/activate; fi
  python src/dq/run_ge_checks.py || fail "GE validation failed"
  popd >/dev/null
  pass "GE validation succeeded"
else
  warn "GE runner not found (skipping)"
fi

# ===== Cost view (will be empty if no recent SELECTs) =====
bq --location="$BQ_LOC" query --use_legacy_sql=false --format=table \
"SELECT user_email, COUNT(*) AS queries, ROUND(SUM(total_bytes_processed)/1e9,2) AS gb_scanned
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND statement_type='SELECT'
GROUP BY user_email ORDER BY gb_scanned DESC LIMIT 20" \
  && pass "Cost view query executed" || warn "Cost view query failed"

# ===== KPI sample =====
# Use the dbt-generated schema for KPI query
FACT_TABLE="$PROJECT.${CUR_DS}_${CUR_DS}.fct_financials_quarterly"
if ! bq --location="$BQ_LOC" show "$FACT_TABLE" >/dev/null 2>&1; then
  FACT_TABLE="$PROJECT.$CUR_DS.fct_financials_quarterly"
fi

bq --location="$BQ_LOC" query --use_legacy_sql=false --format=table \
"WITH rev AS (
  SELECT cik, period_end_date, value
  FROM \`$FACT_TABLE\`
  WHERE concept IN ('us-gaap:Revenues','us-gaap:SalesRevenueNet')
)
SELECT
  cik,
  period_end_date,
  SUM(value) OVER (PARTITION BY cik ORDER BY period_end_date
                   ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS ttm_revenue
FROM rev LIMIT 20" \
  && pass "KPI query executed" || warn "KPI query failed"

# ===== Cloud Run Job (optional) =====
if gcloud run jobs describe "$JOB_NAME" --region="$REGION" >/dev/null 2>&1; then
  pass "Found Cloud Run Job: $JOB_NAME"
  gcloud run jobs executions list --job="$JOB_NAME" --region="$REGION" --format='table(NAME,STATUS,STARTED,COMPLETED)' || true
else
  warn "Cloud Run Job '$JOB_NAME' not found (ok if not using yet)"
fi

echo
echo "== sec_viz health =="
bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv \
"SELECT COUNT(*) FROM \`$PROJECT.sec_curated_sec_viz.kpi_ttm_revenue\`" | tail -n1 | grep -E '^[1-9][0-9]*' \
  && pass "kpi_ttm_revenue has rows" || fail "kpi_ttm_revenue is empty"

bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv \
"SELECT COUNT(*) FROM \`$PROJECT.sec_curated_sec_viz.kpi_company_latest\` WHERE revenue IS NULL OR period_end_date IS NULL" | tail -n1 | awk '{if($1+0>=1){exit 1}}' \
  && pass "kpi_company_latest has no NULL revenue/date rows (ok if zero)" || warn "kpi_company_latest has NULLs (investigate expected gaps)"

bq --location="$BQ_LOC" query --use_legacy_sql=false --format=csv \
"SELECT FORMAT_DATE('%Y-%m-%d', MAX(period_end_date)) FROM \`$PROJECT.sec_curated_sec_viz.kpi_ttm_revenue\`" | tail -n1 | awk -v d=$(date -u -d '450 days ago' +%Y-%m-%d 2>/dev/null || date -v-450d +%Y-%m-%d) '{if($1>=d){exit 0}else{exit 1}}' \
  && pass "kpi_ttm_revenue max(period_end_date) is fresh (<= 450 days)" || warn "kpi_ttm_revenue looks stale"

pass "All checks completed."
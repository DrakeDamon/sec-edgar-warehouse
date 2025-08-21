# Deployment Guide

Complete setup instructions for deploying the SEC EDGAR Financials Warehouse from scratch.

## Prerequisites

### Google Cloud Platform Setup

1. **Create GCP Project**
```bash
# Set project variables
export PROJECT_ID="sec-edgar-financials-warehouse"
export REGION="us-central1"
export BQ_LOCATION="US"

# Create project (optional)
gcloud projects create $PROJECT_ID

# Set active project
gcloud config set project $PROJECT_ID
```

2. **Enable Required APIs**
```bash
gcloud services enable bigquery.googleapis.com
gcloud services enable storage.googleapis.com  
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable logging.googleapis.com
```

3. **Create Service Account**
```bash
# Create service account
gcloud iam service-accounts create sec-pipeline \
    --description="SEC data pipeline service account" \
    --display-name="SEC Pipeline"

# Assign required roles
for ROLE in roles/storage.objectAdmin roles/bigquery.dataEditor roles/bigquery.jobUser roles/run.invoker
do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:sec-pipeline@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="$ROLE"
done

# Create and download service account key
gcloud iam service-accounts keys create sa.json \
    --iam-account=sec-pipeline@$PROJECT_ID.iam.gserviceaccount.com
```

### Local Development Environment

1. **Python Environment**
```bash
# Python 3.9+ required
python --version  # Should be 3.9+

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

2. **Environment Configuration**
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values
GCP_PROJECT_ID=sec-edgar-financials-warehouse
GCP_REGION=us-central1
GCS_BUCKET=sec-edgar-data-$(date +%Y%m%d-%H%M%S)  # Must be globally unique
BQ_LOCATION=US
BQ_RAW_DATASET=sec_raw
BQ_CURATED_DATASET=sec_curated
SEC_USER_AGENT="Your Name your.email@domain.com"
TICKERS="AAPL,MSFT,AMZN,GOOGL,NVDA"
```

## Local Development Setup

### 1. Infrastructure Bootstrap

```bash
# Load environment variables
source .venv/bin/activate
export $(cat .env | xargs)

# Create GCS bucket
gsutil mb gs://$GCS_BUCKET

# Create BigQuery datasets
bq mk --location=$BQ_LOCATION --dataset $GCP_PROJECT_ID:$BQ_RAW_DATASET
bq mk --location=$BQ_LOCATION --dataset $GCP_PROJECT_ID:$BQ_CURATED_DATASET
bq mk --location=$BQ_LOCATION --dataset $GCP_PROJECT_ID:sec_viz
```

### 2. Initial Data Pipeline Run

```bash
# Full pipeline execution
make setup    # Install dependencies (if not done)
make ingest   # Fetch SEC data
make load     # Load to BigQuery
make dbt-build # Transform data
make ge       # Validate quality

# Alternative: Run all at once
make all
```

### 3. Validation

```bash
# Run comprehensive smoke check
bash tools/smoke_check.sh

# Expected output:
# ✅ All infrastructure components created
# ✅ Data loaded and transformed
# ✅ Data quality checks passed
# ✅ Visualization models populated
```

## Production Deployment

### 1. Container Registry Setup

```bash
# Create Artifact Registry repository
gcloud artifacts repositories create sec-pipeline \
    --location=$REGION \
    --repository-format=docker

# Configure Docker authentication
gcloud auth configure-docker $REGION-docker.pkg.dev
```

### 2. Cloud Run Deployment

**Option A: Manual Deployment**
```bash
# Build and push container
docker build --platform linux/amd64 -t $REGION-docker.pkg.dev/$PROJECT_ID/sec-pipeline/app .
docker push $REGION-docker.pkg.dev/$PROJECT_ID/sec-pipeline/app

# Deploy to Cloud Run
gcloud run jobs create sec-pipeline-job \
    --image=$REGION-docker.pkg.dev/$PROJECT_ID/sec-pipeline/app \
    --region=$REGION \
    --set-env-vars="GCP_PROJECT_ID=$PROJECT_ID,GCP_REGION=$REGION,GCS_BUCKET=$GCS_BUCKET" \
    --memory=2Gi \
    --cpu=1 \
    --max-retries=3 \
    --parallelism=1
```

**Option B: Automated Deployment Script**
```bash
# Use provided deployment script
bash deploy/cloud_run_deploy.sh
```

### 3. GitHub Actions Setup

1. **Add Repository Secrets**
   - Go to GitHub repo → Settings → Secrets and variables → Actions
   - Add secret: `SA_JSON` with contents of `sa.json` file

2. **Verify Workflow Configuration**
```yaml
# .github/workflows/schedule.yml
name: SEC Pipeline Schedule
on:
  schedule:
    - cron: "0 6 * * *"  # Daily at 06:00 UTC
  workflow_dispatch:

jobs:
  run-pipeline:
    runs-on: ubuntu-latest
    steps:
    - uses: google-github-actions/auth@v2
      with:
        credentials_json: ${{ secrets.SA_JSON }}
    - name: Run Cloud Run Job
      run: |
        gcloud run jobs execute sec-pipeline-job \
          --region=us-central1 \
          --wait
```

3. **Test Workflow**
```bash
# Manual trigger to test
gh workflow run schedule.yml

# Check status
gh workflow list
```

## Environment-Specific Configurations

### Development Environment

```bash
# Use development dataset suffix
export BQ_CURATED_DATASET=sec_curated_dev
export GCS_BUCKET=sec-edgar-data-dev-$(whoami)

# Smaller company list for faster testing
export TICKERS="AAPL,MSFT"

# Local dbt development
export DBT_PROFILES_DIR=./dbt
dbt build --project-dir ./dbt --target dev
```

### Staging Environment

```bash
# Use staging resources
export GCP_PROJECT_ID=sec-edgar-staging
export BQ_CURATED_DATASET=sec_curated_staging

# Deploy staging Cloud Run job
gcloud run jobs create sec-pipeline-job-staging \
    --image=$REGION-docker.pkg.dev/$PROJECT_ID/sec-pipeline/app \
    --region=$REGION
```

### Production Environment

```bash
# Production hardening applied automatically
export BQ_CURATED_DATASET=sec_curated
export GCS_BUCKET=sec-edgar-data-prod

# Production optimizations in dbt_project.yml:
# - Partition filtering required
# - Clustering optimized for query patterns  
# - Incremental models for efficiency
```

## Advanced Configuration

### Custom Company Universe

1. **Modify Ticker List**
```bash
# Edit .env file
TICKERS="AAPL,MSFT,AMZN,GOOGL,NVDA,TSLA,META,NFLX"

# Or pass as environment variable
export TICKERS="AAPL,MSFT,AMZN,GOOGL,NVDA,TSLA,META,NFLX"
```

2. **Dynamic Ticker Loading**
```python
# Modify src/ingest/fetch_sec.py to load from file
with open('tickers.txt', 'r') as f:
    tickers = [line.strip() for line in f]
```

### dbt Configuration

1. **Custom dbt Profile**
```yaml
# dbt/profiles.yml
sec_edgar_bq:
  target: prod
  outputs:
    prod:
      type: bigquery
      method: oauth  # For Cloud Run
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: "{{ env_var('BQ_CURATED_DATASET') }}"
      location: "{{ env_var('BQ_LOCATION') }}"
    dev:
      type: bigquery
      method: service-account
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: "{{ env_var('BQ_CURATED_DATASET') }}_dev"
      keyfile: "{{ env_var('GOOGLE_APPLICATION_CREDENTIALS') }}"
```

2. **Environment Variables for dbt**
```bash
# Set these before running dbt
export DBT_PROFILES_DIR=./dbt
export BQ_VIZ_DATASET=sec_viz

# Run specific model selections
dbt build --select marts_viz     # Visualization models only
dbt build --select marts         # All marts models
dbt test --select fct_financials_quarterly  # Specific model tests
```

### Cost Optimization

1. **BigQuery Slot Reservations**
```bash
# For high-volume usage, consider reservations
bq mk --reservation \
    --location=$BQ_LOCATION \
    --reservation_id=sec-pipeline \
    --slot_capacity=100
```

2. **Query Cost Monitoring**
```sql
-- Add to monitoring dashboard
SELECT 
  job_id,
  user_email,
  query,
  total_bytes_processed / POW(10, 9) as gb_processed,
  total_bytes_processed * 5.0 / POW(10, 12) as estimated_cost_usd
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
ORDER BY total_bytes_processed DESC;
```

## Troubleshooting

### Common Deployment Issues

1. **Authentication Errors**
```bash
# Verify service account permissions
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:sec-pipeline@$PROJECT_ID.iam.gserviceaccount.com"

# Re-create service account key if needed
gcloud iam service-accounts keys create sa.json \
    --iam-account=sec-pipeline@$PROJECT_ID.iam.gserviceaccount.com
```

2. **BigQuery Access Issues**
```bash
# Test BigQuery access
bq ls $PROJECT_ID:$BQ_RAW_DATASET

# Check dataset permissions
bq show $PROJECT_ID:$BQ_RAW_DATASET
```

3. **Cloud Run Deployment Failures**
```bash
# Check Cloud Run job logs
gcloud run jobs executions list --job=sec-pipeline-job --region=$REGION

# View specific execution logs
gcloud logging read "resource.type=cloud_run_job" --limit=50
```

4. **dbt Build Failures**
```bash
# Debug dbt issues
export DBT_PROFILES_DIR=./dbt
dbt debug --project-dir ./dbt

# Check compiled SQL
dbt compile --project-dir ./dbt
cat dbt/target/compiled/sec_edgar/models/marts/fct_financials_quarterly.sql
```

### Performance Issues

1. **Slow BigQuery Queries**
```sql
-- Analyze query performance
SELECT 
  job_id,
  query,
  total_slot_ms,
  total_bytes_processed
FROM `region-us`.INFORMATION_SCHEMA.JOBS
WHERE job_id = 'your-job-id';
```

2. **Cloud Run Timeouts**
```bash
# Increase timeout and resources
gcloud run jobs update sec-pipeline-job \
    --region=$REGION \
    --memory=4Gi \
    --cpu=2 \
    --task-timeout=3600s
```

3. **dbt Performance Optimization**
```bash
# Use dbt slim CI for incremental builds
dbt build --select state:modified+ --defer --state ./prod-manifest/

# Profile dbt performance
dbt run --project-dir ./dbt --profiles-dir ./dbt --debug
```

## Maintenance

### Regular Maintenance Tasks

1. **Weekly**
   - Review Cloud Run job execution logs
   - Monitor BigQuery costs and slot usage
   - Check data quality test results

2. **Monthly**
   - Update dbt dependencies: `dbt deps`
   - Review and optimize slow queries
   - Rotate service account keys (optional)

3. **Quarterly**
   - Review and update company ticker universe
   - Analyze data storage costs and implement lifecycle policies
   - Update dependencies: `pip install -r requirements.txt --upgrade`

### Monitoring Setup

1. **Cloud Monitoring Alerts**
```bash
# Create alert policy for Cloud Run failures
gcloud alpha monitoring policies create \
    --notification-channels=$NOTIFICATION_CHANNEL \
    --display-name="SEC Pipeline Failures" \
    --condition-display-name="Cloud Run Job Failed" \
    --condition-filter='resource.type="cloud_run_job"' \
    --condition='thresholdValue: 1'
```

2. **BigQuery Data Freshness**
```sql
-- Monitor data freshness
SELECT 
  table_name,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_modified_time, HOUR) as hours_since_update
FROM `sec_curated_sec_curated.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN ('fct_financials_quarterly', 'dim_company')
  AND TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_modified_time, HOUR) > 25;  -- Alert if > 25 hours
```

## Security Hardening

### Production Security Checklist

- [ ] Service account follows principle of least privilege
- [ ] No hardcoded credentials in code or containers
- [ ] GitHub repository secrets properly configured
- [ ] Cloud Run jobs use non-root user
- [ ] BigQuery datasets have appropriate IAM policies
- [ ] Audit logging enabled for all resources
- [ ] VPC network restrictions (if applicable)
- [ ] Container image vulnerability scanning enabled

### Compliance Considerations

- [ ] SEC data usage complies with sec.gov/privacy
- [ ] Rate limiting respects SEC API guidelines (10 requests/second)
- [ ] User agent string identifies requestor
- [ ] No sensitive data logged or stored
- [ ] Data retention policies align with requirements
- [ ] Audit trail for all data processing activities
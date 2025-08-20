#!/bin/bash
set -euo pipefail

# Cloud Run deployment script
PROJECT=${GCP_PROJECT_ID:-"sec-edgar-financials-warehouse"}
REGION=${GCP_REGION:-"us-central1"}
IMAGE_NAME="sec-pipeline"

echo "Building and deploying $IMAGE_NAME to Cloud Run..."

# Build and push Docker image
docker build -t $REGION-docker.pkg.dev/$PROJECT/containers/$IMAGE_NAME:latest .
docker push $REGION-docker.pkg.dev/$PROJECT/containers/$IMAGE_NAME:latest

# Deploy to Cloud Run Jobs
gcloud run jobs create $IMAGE_NAME \
  --image $REGION-docker.pkg.dev/$PROJECT/containers/$IMAGE_NAME:latest \
  --region $REGION \
  --service-account sec-pipeline@$PROJECT.iam.gserviceaccount.com \
  --set-env-vars GCP_PROJECT_ID=$PROJECT,GCS_BUCKET=$GCS_BUCKET,BQ_LOCATION=US \
  --max-retries 1 \
  --parallelism 1 \
  --memory 2Gi \
  --cpu 1

echo "Deployment complete. Run with: gcloud run jobs execute $IMAGE_NAME --region $REGION"
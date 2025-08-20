# Setup Guide

## Prerequisites
- Google Cloud Project with billing enabled
- Python 3.11+
- Docker (for Cloud Run deployment)

## Quick Start
1. Clone the repository
2. Copy `.env.example` to `.env` and configure
3. Run `make setup && make all`

## GCP Configuration
Required APIs:
- BigQuery API
- Cloud Storage API
- Cloud Run API (optional)
- Artifact Registry API (optional)

## Environment Variables
See `.env.example` for required configuration.
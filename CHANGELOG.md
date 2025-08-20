# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-08-19

### Added
- Initial release of SEC EDGAR Financials Warehouse
- Complete data pipeline from SEC API to BigQuery
- dbt transformations with dimensional modeling
- Great Expectations data quality validation
- Docker containerization for Cloud Run deployment
- Cost optimization with partitioning and clustering
- Comprehensive documentation and testing

### Features
- **Data Ingestion**: SEC API compliance with rate limiting
- **Data Storage**: GCS and BigQuery integration
- **Data Transformation**: dbt staging, intermediate, and marts layers
- **Data Quality**: Automated validation with Great Expectations
- **Infrastructure**: GCP service account and IAM configuration
- **Deployment**: Docker + Cloud Run for production workloads
- **Monitoring**: Cost analysis and query optimization

### Technical Details
- Python 3.11+ compatibility
- BigQuery date partitioning and clustering
- Incremental dbt models for efficiency
- SEC XBRL data parsing and normalization
- Automated CI/CD with GitHub Actions
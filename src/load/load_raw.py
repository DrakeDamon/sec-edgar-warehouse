import os
from dotenv import load_dotenv
from google.cloud import bigquery

load_dotenv()
PROJECT = os.getenv("GCP_PROJECT_ID","sec-edgar-financials-warehouse")
BQ_LOC = os.getenv("BQ_LOCATION","US")
BQ_RAW = os.getenv("BQ_RAW_DATASET","sec_raw")
BUCKET = os.getenv("GCS_BUCKET")

def load_ndjson(table: str, uri: str, partition_field=None):
    client = bigquery.Client()
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND
    )
    if partition_field:
        job_config.time_partitioning = bigquery.TimePartitioning(field=partition_field)
    job = client.load_table_from_uri(
        uri, f"{PROJECT}.{BQ_RAW}.{table}", job_config=job_config, location=BQ_LOC
    )
    job.result()
    print(f"Loaded {uri} -> {PROJECT}.{BQ_RAW}.{table}")

def main():
    assert BUCKET, "Set GCS_BUCKET in .env"
    load_ndjson("raw_companyfacts", f"gs://{BUCKET}/raw/*/companyfacts.ndjson")
    load_ndjson("raw_submissions", f"gs://{BUCKET}/raw/*/submissions.ndjson")

if __name__ == "__main__":
    main()

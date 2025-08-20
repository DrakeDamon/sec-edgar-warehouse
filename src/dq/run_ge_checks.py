import os
from dotenv import load_dotenv
import pandas as pd
import great_expectations as ge
from google.cloud import bigquery

load_dotenv()
PROJECT = os.getenv("GCP_PROJECT_ID","sec-edgar-financials-warehouse")
DATASET = "sec_curated_sec_curated"  # dbt creates this nested dataset name
table = "fct_financials_quarterly"

def run():
    # Read data using BigQuery client
    client = bigquery.Client(project=PROJECT)
    query = f"select cik, concept, period_end_date, value from `{PROJECT}.{DATASET}.{table}` limit 1000"
    df = client.query(query).to_dataframe()
    
    # Create Great Expectations DataFrame
    gdf = ge.from_pandas(df)
    
    # Set expectations
    gdf.expect_column_values_to_not_be_null("period_end_date")
    gdf.expect_column_values_to_not_be_null("concept")
    gdf.expect_column_values_to_be_of_type("value", "float64")
    
    # Validate
    res = gdf.validate()
    print(f"Validation successful: {res['success']}")
    print(f"Statistics: {res['statistics']}")
    for result in res['results']:
        print(f"- {result['expectation_config']['expectation_type']}: {'✓' if result['success'] else '✗'}")
    
    return res

if __name__ == "__main__":
    run()

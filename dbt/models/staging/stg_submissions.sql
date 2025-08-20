with src as (
  select
    SAFE_CAST(cik as string) as cik,
    upper(ticker) as ticker,
    company_name,
    accession_no,
    form,
    SAFE_CAST(filed as date) as filed,
    SAFE_CAST(report_period as date) as report_period
  from {{ source(env_var('BQ_RAW_DATASET','sec_raw'), 'raw_submissions') }}
)
select * from src

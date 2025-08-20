with src as (
  select
    SAFE_CAST(cik as string) as cik,
    upper(ticker) as ticker,
    concept,
    unit,
    SAFE_CAST(period_end_date as date) as period_end_date,
    SAFE_CAST(val as float64) as value,
    accn, fy, fp, form,
    SAFE_CAST(filed as date) as filed
  from {{ source(env_var('BQ_RAW_DATASET','sec_raw'), 'raw_companyfacts') }}
)
select * from src

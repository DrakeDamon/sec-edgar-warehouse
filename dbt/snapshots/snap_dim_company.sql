{% snapshot snap_dim_company %}
{{
  config(
    target_schema=env_var('BQ_CURATED_DATASET','sec_curated'),
    unique_key='cik',
    strategy='timestamp',
    updated_at='filed'
  )
}}
select cik, any_value(company_name) as company_name, max(filed) as filed
from {{ ref('stg_submissions') }}
group by cik
{% endsnapshot %}

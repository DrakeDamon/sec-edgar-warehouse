select
  cik,
  any_value(company_name) as company_name,
  array_agg(distinct ticker IGNORE NULLS)[offset(0)] as ticker
from {{ ref('stg_submissions') }}
group by cik

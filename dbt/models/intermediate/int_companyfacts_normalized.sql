with ranked as (
  select
    cik, ticker, concept, unit, period_end_date, value, accn, filed, fy, fp, form,
    row_number() over (
      partition by cik, concept, period_end_date
      order by case
        when unit in ('USD','usd') then 1
        when unit like '%USD%' then 2
        else 3
      end, filed desc
    ) as rn
  from {{ ref('stg_companyfacts') }}
)
select * except(rn) from ranked where rn = 1

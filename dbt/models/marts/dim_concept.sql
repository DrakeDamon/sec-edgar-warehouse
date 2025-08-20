select concept,
  case concept
    when 'us-gaap:Revenues' then 'Revenue'
    when 'us-gaap:SalesRevenueNet' then 'Revenue'
    when 'us-gaap:CostOfRevenue' then 'Cost of Revenue'
    when 'us-gaap:GrossProfit' then 'Gross Profit'
    when 'us-gaap:NetIncomeLoss' then 'Net Income'
    when 'us-gaap:EarningsPerShareDiluted' then 'EPS (Diluted)'
    else concept
  end as concept_label
from (select distinct concept from {{ ref('int_companyfacts_normalized') }})

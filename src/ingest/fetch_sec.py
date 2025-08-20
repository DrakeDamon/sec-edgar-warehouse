import os, json, time, datetime as dt
from pathlib import Path
from dotenv import load_dotenv
import requests
from google.cloud import storage

load_dotenv()
PROJECT = os.getenv("GCP_PROJECT_ID","sec-edgar-financials-warehouse")
BUCKET = os.getenv("GCS_BUCKET")
USER_AGENT = os.getenv("SEC_USER_AGENT","David Damon dddamon06@gmail.com")
TICKERS = [t.strip().upper() for t in os.getenv("TICKERS","AAPL,MSFT").split(",")]
RAW_PREFIX_DATE = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d")  # Fixed deprecation warning
BASE = "https://data.sec.gov"
HEADERS = {"User-Agent": USER_AGENT, "Accept-Encoding": "gzip, deflate"}

def fetch_json(url):
    r = requests.get(url, headers=HEADERS, timeout=60)
    r.raise_for_status()
    return r.json()

def get_ticker_cik_map():
    url = "https://www.sec.gov/files/company_tickers.json"  # Updated SEC API endpoint
    data = fetch_json(url)
    return {v["ticker"].upper(): str(v["cik_str"]).zfill(10) for v in data.values()}

def normalize_companyfacts(cik, ticker, facts):
    rows = []
    concepts = ["us-gaap:Revenues","us-gaap:SalesRevenueNet","us-gaap:CostOfRevenue","us-gaap:GrossProfit","us-gaap:NetIncomeLoss","us-gaap:EarningsPerShareDiluted"]
    all_facts = facts.get("facts", {})
    
    if not all_facts:
        print(f"    No facts found for {ticker}")
        return rows
        
    # The facts structure has namespaces as top-level keys, need to drill down  
    # This handles the nested SEC XBRL taxonomy structure
    available_concepts = []
    for namespace, namespace_facts in all_facts.items():
        if isinstance(namespace_facts, dict):
            available_concepts.extend([f"{namespace}:{fact}" for fact in namespace_facts.keys()])
    
    original_concept_count = len([c for c in concepts if c in available_concepts])
    
    if original_concept_count == 0:
        # Look for revenue, income, earnings concepts
        revenue_concepts = [c for c in available_concepts if any(term in c.lower() for term in ["revenue", "sales"])]
        income_concepts = [c for c in available_concepts if any(term in c.lower() for term in ["income", "earnings"])]
        concepts = revenue_concepts[:2] + income_concepts[:2]  # Take first 2 of each type
        if not concepts:
            concepts = available_concepts[:5]  # Take any 5 concepts if no matches
        print(f"    Using fallback concepts for {ticker}: {concepts[:3]}...")
    else:
        print(f"    Using {original_concept_count} original concepts for {ticker}")
    
    # Process facts by namespace
    for namespace, namespace_facts in all_facts.items():
        if not isinstance(namespace_facts, dict):
            continue
        for fact_name, body in namespace_facts.items():
            concept = f"{namespace}:{fact_name}"
            if concept not in concepts:
                continue
            for unit, arr in body.get("units", {}).items():
                for ob in arr:
                    end = ob.get("end") or ob.get("fy")
                    if not end:
                        continue
                    rows.append({
                        "cik": cik, "ticker": ticker, "concept": concept, "unit": unit,
                        "period_end_date": end, "val": ob.get("val"),
                        "accn": ob.get("accn"), "fy": ob.get("fy"), "fp": ob.get("fp"),
                        "form": ob.get("form"), "filed": ob.get("filed")
                    })
    return rows

def write_ndjson(path: Path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")

def upload_to_gcs(local_path: Path, bucket: str, dest: str):
    client = storage.Client()
    b = client.bucket(bucket)
    blob = b.blob(dest)
    blob.upload_from_filename(str(local_path))
    print(f"Uploaded gs://{bucket}/{dest}")

def main():
    assert BUCKET, "Set GCS_BUCKET in .env"
    t2c = get_ticker_cik_map()
    chosen = [(t, t2c[t]) for t in TICKERS if t in t2c]

    all_cf, all_sub = [], []
    for t, cik in chosen:
        print(f"Processing {t} (CIK: {cik})")
        subs = fetch_json(f"{BASE}/submissions/CIK{cik}.json")
        facts = fetch_json(f"{BASE}/api/xbrl/companyfacts/CIK{cik}.json")
        company = subs.get("companyName","")
        rec = subs.get("filings",{}).get("recent",{})
        for i in range(len(rec.get("accessionNumber", []))):
            all_sub.append({
                "cik": str(cik).zfill(10),
                "ticker": t,
                "company_name": company,
                "accession_no": rec["accessionNumber"][i],
                "form": rec["form"][i],
                "filed": rec["filingDate"][i],
                "report_period": rec["reportDate"][i],
            })
        cf_rows = normalize_companyfacts(str(cik).zfill(10), t, facts)
        print(f"  Found {len(cf_rows)} company facts rows for {t}")
        all_cf.extend(cf_rows)
        time.sleep(0.3)

    outdir = Path("tmp") / "raw" / RAW_PREFIX_DATE
    cf_path = outdir / "companyfacts.ndjson"
    sub_path = outdir / "submissions.ndjson"
    write_ndjson(cf_path, all_cf)
    write_ndjson(sub_path, all_sub)

    upload_to_gcs(cf_path, BUCKET, f"raw/{RAW_PREFIX_DATE}/companyfacts.ndjson")
    upload_to_gcs(sub_path, BUCKET, f"raw/{RAW_PREFIX_DATE}/submissions.ndjson")

if __name__ == "__main__":
    main()

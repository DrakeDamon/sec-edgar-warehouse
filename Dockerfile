FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y gcc curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# No GOOGLE_APPLICATION_CREDENTIALS here; Cloud Run SA via metadata will be used

# Optional: fast auth sanity check before dbt build
CMD ["/bin/bash","-lc","set -e; \
  source .env >/dev/null 2>&1 || true; \
  python - <<'PY'\nfrom google.auth import default; creds, proj = default(); print('ADC OK; project=', proj)\nPY\n \
  && python src/ingest/fetch_sec.py \
  && python src/load/load_raw.py \
  && export DBT_PROFILES_DIR=./dbt \
  && dbt debug --project-dir ./dbt --profiles-dir ./dbt \
  && dbt build --project-dir ./dbt --profiles-dir ./dbt \
  && python src/dq/run_ge_checks.py" ]

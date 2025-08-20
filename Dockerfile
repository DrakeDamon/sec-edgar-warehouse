FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y gcc curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["/bin/bash","-lc","source .env >/dev/null 2>&1 || true; \
  python src/ingest/fetch_sec.py && \
  python src/load/load_raw.py && \
  export DBT_PROFILES_DIR=./dbt && dbt build --project-dir ./dbt --profiles-dir ./dbt && \
  python src/dq/run_ge_checks.py"]

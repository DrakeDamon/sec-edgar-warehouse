.PHONY: setup ingest load dbt-build ge validate all
setup:
	python -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt

ingest:
	. .venv/bin/activate; python src/ingest/fetch_sec.py

load:
	. .venv/bin/activate; python src/load/load_raw.py

dbt-build:
	. .venv/bin/activate; export DBT_PROFILES_DIR=./dbt; dbt build --project-dir ./dbt --profiles-dir ./dbt

ge:
	. .venv/bin/activate; python src/dq/run_ge_checks.py

validate: dbt-build ge

all: ingest load validate

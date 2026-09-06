PYTHON := .venv/bin/python

RAW_STOPS := data/raw/tx_statewide_2020_04_01.csv.zip
CENSUS_RAW := data/raw/census_stratifiers.csv
STOPS_CLEAN := data/processed/stops_clean.csv
AUDIT_READY := data/processed/audit_ready_stops.csv

.PHONY: all data grounding clean

all: data

data: $(AUDIT_READY)

$(CENSUS_RAW): python/01_fetch_census.py
	cd python && ../$(PYTHON) 01_fetch_census.py

$(STOPS_CLEAN): python/02_clean_stops.py $(RAW_STOPS)
	cd python && ../$(PYTHON) 02_clean_stops.py

$(AUDIT_READY): python/03_merge_features.py $(STOPS_CLEAN) $(CENSUS_RAW)
	cd python && ../$(PYTHON) 03_merge_features.py

# Opt-in, not part of `all`: makes real, billed LLM API calls and needs at
# least one of ANTHROPIC_API_KEY/OPENAI_API_KEY/GEMINI_API_KEY/XAI_API_KEY in
# .env (see README). Runs naive-only if data/processed/datasheet.json
# doesn't exist yet -- see python/run_grounding.py --help for its flags
# (--repeats, --restart, --no-datasheet), passed through via ARGS, e.g.:
#   make grounding ARGS="--repeats=1"
grounding: $(AUDIT_READY)
	cd python && ../$(PYTHON) run_grounding.py $(ARGS)

clean:
	rm -f $(CENSUS_RAW) $(STOPS_CLEAN) $(AUDIT_READY)
	rm -rf results

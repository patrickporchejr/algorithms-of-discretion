PYTHON := .venv/bin/python

RAW_STOPS := data/raw/tx_statewide_2020_04_01.csv.zip
CENSUS_RAW := data/raw/census_stratifiers.csv
STOPS_CLEAN := data/processed/stops_clean.csv
AUDIT_READY := data/processed/audit_ready_stops.csv

PRECOMPUTE_SCRIPT := duboisR/inst/scripts/precompute_audit.R
RESULTS_STAMP := results/.stamp

.PHONY: all data results clean

all: results

data: $(AUDIT_READY)

$(CENSUS_RAW): python/01_fetch_census.py
	cd python && ../$(PYTHON) 01_fetch_census.py

$(STOPS_CLEAN): python/02_clean_stops.py $(RAW_STOPS)
	cd python && ../$(PYTHON) 02_clean_stops.py

$(AUDIT_READY): python/03_merge_features.py $(STOPS_CLEAN) $(CENSUS_RAW)
	cd python && ../$(PYTHON) 03_merge_features.py

# Fits every dashboard model once and caches each as its own .rds (see
# precompute_audit.R) -- a single stamp file stands in for the whole batch
# of results/*.rds outputs, since Make needs one concrete target file to
# compare timestamps against.
results: $(RESULTS_STAMP)

$(RESULTS_STAMP): $(PRECOMPUTE_SCRIPT) $(AUDIT_READY) $(wildcard duboisR/R/*.R)
	Rscript $(PRECOMPUTE_SCRIPT)
	touch $(RESULTS_STAMP)

clean:
	rm -f $(CENSUS_RAW) $(STOPS_CLEAN) $(AUDIT_READY)
	rm -rf results

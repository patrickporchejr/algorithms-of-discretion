PYTHON := .venv/bin/python

RAW_STOPS := data/raw/tx_statewide_2020_04_01.csv.zip
CENSUS_RAW := data/raw/census_stratifiers.csv
STOPS_CLEAN := data/processed/stops_clean.csv
AUDIT_READY := data/processed/audit_ready_stops.csv

PRECOMPUTE_SCRIPT := duboisR/inst/scripts/precompute_audit.R
RESULTS_STAMP := results/.stamp

CLI_SCRIPT := duboisR/inst/scripts/cli.R

APP_NAME := algorithms-of-discretion

.PHONY: all data results grounding deploy clean

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

# Opt-in, not part of `all`/`results`: makes real, billed LLM API calls and
# needs ANTHROPIC_API_KEY/OPENAI_API_KEY in .env (see README). Always reruns
# rather than tracking a timestamp, since re-running is itself sometimes the
# point (checking a model's answers haven't drifted). If a previous run
# crashed partway through, this resumes from its checkpoint automatically;
# pass RESTART=1 (make grounding RESTART=1) to ignore that checkpoint and
# start over from scratch. Pass REPEATS=1 (make grounding REPEATS=1) to cut
# billed calls in half while iterating on something, instead of the default
# 2 trials per condition.
grounding: $(AUDIT_READY)
	Rscript $(CLI_SCRIPT) grounding $(if $(RESTART),--restart) $(if $(REPEATS),--repeats=$(REPEATS))

# Opt-in, not part of `all`: pushes a live version to shinyapps.io, unlike
# every other target here. Needs a one-time `rsconnect::setAccountInfo()`
# first (see README's Deployment section) -- this doesn't set up
# credentials, just stages results and calls deployApp() with them already
# configured. Depends on `results` so it never ships stale model fits, but
# that's a no-op if `results` is already up to date.
deploy: results
	./r_dashboard/deploy/prepare.sh
	cd r_dashboard && Rscript -e 'rsconnect::deployApp(".", appName = "$(APP_NAME)")'

clean:
	rm -f $(CENSUS_RAW) $(STOPS_CLEAN) $(AUDIT_READY)
	rm -rf results

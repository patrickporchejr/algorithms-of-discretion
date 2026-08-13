#!/usr/bin/env bash
# Stages everything r_dashboard/app.R needs from outside r_dashboard/ into
# it, so rsconnect::deployApp() bundles it -- shinyapps.io only uploads the
# r_dashboard/ directory itself, not repo-root siblings. Re-run this any
# time data/processed/audit_ready_stops.csv, results/*.rds, or duboisR/
# change (e.g. after `make results` or editing duboisR), and before every
# deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARD_DIR="$REPO_ROOT/r_dashboard"

SRC_DATA="$REPO_ROOT/data/processed/audit_ready_stops.csv"
SRC_RESULTS="$REPO_ROOT/results"
SRC_DUBOISR="$REPO_ROOT/duboisR"
DEST_DATA_DIR="$DASHBOARD_DIR/data"
DEST_RESULTS_DIR="$DASHBOARD_DIR/results"
DEST_DUBOISR_DIR="$DASHBOARD_DIR/duboisR"

if [[ ! -f "$SRC_DATA" ]]; then
  echo "error: $SRC_DATA not found -- run 'make all' first." >&2
  exit 1
fi

if [[ ! -d "$SRC_RESULTS" ]] || [[ -z "$(ls -A "$SRC_RESULTS"/*.rds 2>/dev/null)" ]]; then
  echo "error: no results/*.rds found -- run 'make results' first." >&2
  exit 1
fi

mkdir -p "$DEST_DATA_DIR" "$DEST_RESULTS_DIR"
cp "$SRC_DATA" "$DEST_DATA_DIR/audit_ready_stops.csv"
cp "$SRC_RESULTS"/*.rds "$DEST_RESULTS_DIR/"

# Plain source copy, not an installed package -- app.R pkgload::load_all()s
# this at startup (see its duboisR-loading comment). Only what load_all()
# and inst/-relative lookups (e.g. system.file()) actually need: no
# tests/, vignettes/, man/, or data-raw/, which are dev-only and would
# otherwise drag testthat/knitr/rmarkdown into the deploy's dependency set
# for nothing.
rm -rf "$DEST_DUBOISR_DIR"
mkdir -p "$DEST_DUBOISR_DIR"
cp "$SRC_DUBOISR"/DESCRIPTION "$SRC_DUBOISR"/NAMESPACE "$SRC_DUBOISR"/LICENSE "$SRC_DUBOISR"/LICENSE.md "$DEST_DUBOISR_DIR/"
cp -R "$SRC_DUBOISR"/R "$DEST_DUBOISR_DIR/R"
cp -R "$SRC_DUBOISR"/inst "$DEST_DUBOISR_DIR/inst"

echo "Staged $(du -h "$DEST_DATA_DIR/audit_ready_stops.csv" | cut -f1) of data, $(du -sh "$DEST_RESULTS_DIR" | cut -f1) of results, and duboisR/ into $DASHBOARD_DIR"

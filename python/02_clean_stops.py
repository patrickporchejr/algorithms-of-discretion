"""Standardize the Texas statewide (State Patrol) Stanford Open Policing file.

Filters to 2015-2017 (most recent 3 full years in the 2006-2017 file) to keep
the row count workable for an interactive Shiny glm(), reads in chunks since
the raw CSV is tens of millions of rows, and derives county_join_key
(normalized county name) to merge against Census output in
03_merge_features.py — the raw file has county_name, not a FIPS code.

The raw file has no arrest outcome (outcome is only ever "warning" or
"citation") and no subject_age — both absent from what Texas State Patrol
reports, not a cleaning bug.
"""

import pandas as pd

# Only these raw columns are read (skips location, vehicle_*, raw_HA_*,
# officer_id_hash, etc.) — the full file has 44 columns and the dashboard
# regression only ever touches a handful of them. Reading fewer columns is
# also dramatically faster than reading everything and dropping it after.
RAW_COLUMNS_NEEDED = [
    "date",
    "time",
    "subject_race",
    "subject_sex",
    "county_name",
    "search_conducted",
    "contraband_found",
    "violation",
    "search_basis",
]

# Final columns written to stops_clean.csv. Beyond what the current dashboard
# queries, this also carries date/violation/search_basis for planned-but-not-
# yet-built features: Veil of Darkness (needs the calendar date to compute
# sunset time per county/day, not just hour), pretextual-stop analysis
# (violation), and consent-vs-probable-cause search disparities (search_basis).
OUTPUT_COLUMNS = [
    "subject_race",
    "subject_sex",
    "search_conducted",
    "contraband_found",
    "hour",
    "date",
    "violation",
    "search_basis",
    "county_join_key",
]

KEEP_RACES = ["white", "black", "hispanic"]
YEAR_MIN, YEAR_MAX = 2015, 2017
CHUNKSIZE = 500_000


def _validate_columns(raw_path: str) -> None:
    header = pd.read_csv(raw_path, nrows=0).columns
    missing = set(RAW_COLUMNS_NEEDED) - set(header)
    if missing:
        raise SystemExit(
            f"Raw TX file is missing expected columns {missing}. "
            f"Actual columns: {list(header)}"
        )


def _clean_chunk(chunk: pd.DataFrame) -> pd.DataFrame:
    chunk = chunk[chunk["subject_race"].isin(KEEP_RACES)].copy()

    chunk["date"] = pd.to_datetime(chunk["date"], errors="coerce")
    chunk = chunk[chunk["date"].dt.year.between(YEAR_MIN, YEAR_MAX)]

    stop_datetime = pd.to_datetime(
        chunk["date"].astype(str) + " " + chunk["time"].astype(str), errors="coerce"
    )
    chunk["hour"] = stop_datetime.dt.hour

    chunk["county_join_key"] = (
        chunk["county_name"].str.replace(" County", "", regex=False).str.upper().str.strip()
    )

    return chunk[OUTPUT_COLUMNS]


def clean_stops(raw_path: str) -> pd.DataFrame:
    _validate_columns(raw_path)
    kept = [
        _clean_chunk(chunk)
        for chunk in pd.read_csv(
            raw_path, usecols=RAW_COLUMNS_NEEDED, low_memory=False, chunksize=CHUNKSIZE
        )
    ]
    return pd.concat(kept, ignore_index=True)


if __name__ == "__main__":
    cleaned = clean_stops("../data/raw/tx_statewide_2020_04_01.csv.zip")
    cleaned.to_csv("../data/processed/stops_clean.csv", index=False)
    print(f"Wrote {len(cleaned)} rows (2015-2017, white/black/hispanic) to ../data/processed/stops_clean.csv")

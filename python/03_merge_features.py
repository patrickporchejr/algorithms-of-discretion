"""Join cleaned stop-level data to county-level ACS stratifiers.

Depends on 01_fetch_census.py and 02_clean_stops.py both producing real
output first.
"""

import pandas as pd


def merge_stops_and_census(stops_path: str, census_path: str) -> pd.DataFrame:
    stops = pd.read_csv(stops_path, low_memory=False)
    census = pd.read_csv(census_path, dtype={"county_fips": str})
    return stops.merge(census, on="county_fips", how="inner")


if __name__ == "__main__":
    merged = merge_stops_and_census(
        "../data/processed/stops_clean.csv",
        "../data/raw/census_stratifiers.csv",
    )
    merged.to_csv("../data/processed/audit_ready_stops.csv", index=False)

"""Join cleaned stop-level data to county-level ACS stratifiers.

Depends on 01_fetch_census.py and 02_clean_stops.py both producing real
output first. Joins on county_join_key (normalized county name) rather than
county_fips, since the raw Stanford stop file only carries county_name, not
FIPS. county_fips is carried through from the census side for reference.
"""

import pandas as pd

# Final columns written to audit_ready_stops.csv — the dashboard's glm()
# formulas only ever reference these plus county_fips for reference.
OUTPUT_COLUMNS = [
    "subject_race",
    "subject_sex",
    "search_conducted",
    "contraband_found",
    "hour",
    "date",
    "violation",
    "search_basis",
    "poverty_rate",
    "median_income",
    "county_fips",
]


def merge_stops_and_census(stops_path: str, census_path: str) -> pd.DataFrame:
    stops = pd.read_csv(stops_path, low_memory=False)
    census = pd.read_csv(
        census_path, usecols=["county_join_key", "poverty_rate", "median_income", "county_fips"],
        dtype={"county_fips": str},
    )
    merged = stops.merge(census, on="county_join_key", how="inner")

    unmatched = stops.loc[~stops["county_join_key"].isin(census["county_join_key"]), "county_join_key"]
    if not unmatched.empty:
        print(
            f"Warning: {unmatched.nunique()} distinct county names in the stop data "
            f"didn't match a Texas county from the Census pull: {sorted(unmatched.unique())[:10]}..."
        )

    return merged[OUTPUT_COLUMNS]


if __name__ == "__main__":
    merged = merge_stops_and_census(
        "../data/processed/stops_clean.csv",
        "../data/raw/census_stratifiers.csv",
    )
    merged.to_csv("../data/processed/audit_ready_stops.csv", index=False)

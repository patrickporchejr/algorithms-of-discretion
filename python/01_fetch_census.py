"""Pull ACS 5-Year county-level stratifiers (median income, poverty) from the Census API.

Targets Texas (state FIPS 48) to match the Stanford Open Policing "TX statewide"
stop file used by 02_clean_stops.py. Needs a CENSUS_API_KEY
(free, https://api.census.gov/data/key_signup.html) set in the environment or a
.env file at the repo root.
"""

import os

import pandas as pd
import requests
from dotenv import load_dotenv

CENSUS_API_URL = "https://api.census.gov/data/2022/acs/acs5"
TARGET_STATE_FIPS = "48"  # Texas


def fetch_county_stratifiers(state_fips: str, api_key: str) -> pd.DataFrame:
    params = {
        "get": "NAME,B19013_001E,B17001_002E,B17001_001E",
        "for": "county:*",
        "in": f"state:{state_fips}",
        "key": api_key,
    }
    response = requests.get(CENSUS_API_URL, params=params, timeout=30)
    response.raise_for_status()

    rows = response.json()
    df = pd.DataFrame(rows[1:], columns=rows[0])
    df = df.rename(
        columns={
            "B19013_001E": "median_income",
            "B17001_002E": "poverty_count",
            "B17001_001E": "poverty_universe",
        }
    )
    df["poverty_rate"] = df["poverty_count"].astype(float) / df["poverty_universe"].astype(float)
    df["county_fips"] = df["state"] + df["county"]

    # Stanford stop data only carries county_name (e.g. "Harris County"), not FIPS,
    # so 03_merge_features.py joins on this normalized name instead of county_fips.
    # Census NAME is "Harris County, Texas" -> normalize to "HARRIS".
    df["county_join_key"] = (
        df["NAME"].str.split(",").str[0].str.replace(" County", "", regex=False).str.upper().str.strip()
    )
    return df


if __name__ == "__main__":
    load_dotenv()
    api_key = os.environ.get("CENSUS_API_KEY")
    if not api_key:
        raise SystemExit(
            "Set CENSUS_API_KEY before running this script "
            "(https://api.census.gov/data/key_signup.html)."
        )

    out = fetch_county_stratifiers(TARGET_STATE_FIPS, api_key)
    out.to_csv("../data/raw/census_stratifiers.csv", index=False)
    print(f"Wrote {len(out)} Texas counties to ../data/raw/census_stratifiers.csv")

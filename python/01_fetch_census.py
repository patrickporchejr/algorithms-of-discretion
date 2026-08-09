"""Pull ACS 5-Year county-level stratifiers (median income, poverty) from the Census API.

Not runnable yet: needs a CENSUS_API_KEY (free, https://api.census.gov/data/key_signup.html)
and a decision on which states to target (see README Open Questions #1) before this
is wired into the pipeline for real.
"""

import os

import pandas as pd
import requests

CENSUS_API_URL = "https://api.census.gov/data/2022/acs/acs5"


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
    return df


if __name__ == "__main__":
    api_key = os.environ.get("CENSUS_API_KEY")
    if not api_key:
        raise SystemExit("Set CENSUS_API_KEY before running this script.")

    # TODO: replace with the state list decided in README Open Questions #1
    target_state_fips = "44"  # Rhode Island, placeholder
    out = fetch_county_stratifiers(target_state_fips, api_key)
    out.to_csv("../data/raw/census_stratifiers.csv", index=False)

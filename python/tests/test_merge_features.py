import pandas as pd

from _helpers import import_script

merge_features = import_script("03_merge_features.py")


def test_merge_stops_and_census_joins_on_county_and_warns_on_unmatched(tmp_path, capsys):
    stops_path = tmp_path / "stops_clean.csv"
    census_path = tmp_path / "census_stratifiers.csv"

    pd.DataFrame(
        [
            {
                "subject_race": "white",
                "subject_sex": "male",
                "search_conducted": False,
                "contraband_found": None,
                "hour": 14,
                "date": "2016-03-01",
                "violation": "speeding",
                "search_basis": None,
                "county_join_key": "HARRIS",
            },
            {
                "subject_race": "black",
                "subject_sex": "female",
                "search_conducted": True,
                "contraband_found": True,
                "hour": 9,
                "date": "2016-05-01",
                "violation": "equipment",
                "search_basis": "pc",
                "county_join_key": "UNKNOWN",
            },
        ]
    ).to_csv(stops_path, index=False)

    pd.DataFrame(
        [
            {
                "county_join_key": "HARRIS",
                "poverty_rate": 0.125,
                "median_income": 65000,
                "county_fips": "48201",
            }
        ]
    ).to_csv(census_path, index=False)

    merged = merge_features.merge_stops_and_census(str(stops_path), str(census_path))

    assert len(merged) == 1
    assert merged.iloc[0]["county_fips"] == "48201"
    assert list(merged.columns) == merge_features.OUTPUT_COLUMNS

    # the unmatched county_join_key ("UNKNOWN") is dropped by the inner join --
    # it should be reported, not silently disappear.
    captured = capsys.readouterr()
    assert "UNKNOWN" in captured.out

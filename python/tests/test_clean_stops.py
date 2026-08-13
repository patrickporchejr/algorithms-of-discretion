import pandas as pd
import pytest

from _helpers import import_script

clean_stops_module = import_script("02_clean_stops.py")


def _write_raw_csv(tmp_path, rows):
    path = tmp_path / "raw.csv"
    pd.DataFrame(rows).to_csv(path, index=False)
    return str(path)


def test_clean_stops_filters_race_and_year_and_derives_columns(tmp_path):
    raw_path = _write_raw_csv(
        tmp_path,
        [
            # kept: 2016, in KEEP_RACES
            {
                "date": "2016-03-01",
                "time": "14:30:00",
                "subject_race": "white",
                "subject_sex": "male",
                "county_name": "Harris County",
                "search_conducted": False,
                "contraband_found": None,
                "violation": "speeding",
                "search_basis": None,
            },
            # dropped: race not in KEEP_RACES
            {
                "date": "2016-03-01",
                "time": "14:30:00",
                "subject_race": "asian",
                "subject_sex": "female",
                "county_name": "Harris County",
                "search_conducted": False,
                "contraband_found": None,
                "violation": "speeding",
                "search_basis": None,
            },
            # dropped: year outside 2015-2017
            {
                "date": "2010-01-01",
                "time": "09:00:00",
                "subject_race": "black",
                "subject_sex": "male",
                "county_name": "Travis County",
                "search_conducted": True,
                "contraband_found": True,
                "violation": "equipment",
                "search_basis": "probable cause",
            },
        ],
    )

    cleaned = clean_stops_module.clean_stops(raw_path)

    assert len(cleaned) == 1
    row = cleaned.iloc[0]
    assert row["subject_race"] == "white"
    assert row["hour"] == 14
    assert row["county_join_key"] == "HARRIS"
    assert list(cleaned.columns) == clean_stops_module.OUTPUT_COLUMNS


def test_validate_columns_raises_on_missing_expected_column(tmp_path):
    path = tmp_path / "raw.csv"
    pd.DataFrame({"date": ["2016-01-01"]}).to_csv(path, index=False)

    with pytest.raises(SystemExit):
        clean_stops_module._validate_columns(str(path))

from unittest.mock import Mock, patch

import pytest

from _helpers import import_script

fetch_census = import_script("01_fetch_census.py")


def _mock_response():
    payload = [
        ["NAME", "B19013_001E", "B17001_002E", "B17001_001E", "state", "county"],
        ["Harris County, Texas", "65000", "150000", "1200000", "48", "201"],
        ["Travis County, Texas", "80000", "50000", "900000", "48", "453"],
    ]
    response = Mock()
    response.json.return_value = payload
    response.raise_for_status.return_value = None
    return response


@patch("requests.get")
def test_fetch_county_stratifiers_derives_expected_columns(mock_get):
    mock_get.return_value = _mock_response()

    df = fetch_census.fetch_county_stratifiers("48", "fake-key")

    assert list(df["county_join_key"]) == ["HARRIS", "TRAVIS"]
    harris = df.loc[df["county_join_key"] == "HARRIS"].iloc[0]
    assert harris["county_fips"] == "48201"
    assert harris["poverty_rate"] == 150000 / 1200000


@patch("requests.get")
def test_fetch_county_stratifiers_passes_state_and_key_to_api(mock_get):
    mock_get.return_value = _mock_response()

    fetch_census.fetch_county_stratifiers("48", "my-key")

    _, kwargs = mock_get.call_args
    assert kwargs["params"]["in"] == "state:48"
    assert kwargs["params"]["key"] == "my-key"


@patch("requests.get")
def test_fetch_county_stratifiers_raises_on_http_error(mock_get):
    response = _mock_response()
    response.raise_for_status.side_effect = Exception("boom")
    mock_get.return_value = response

    with pytest.raises(Exception, match="boom"):
        fetch_census.fetch_county_stratifiers("48", "fake-key")

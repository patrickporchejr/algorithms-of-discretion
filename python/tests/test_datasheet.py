import json

import pytest

from _helpers import import_script  # noqa: F401 -- adds python/ to sys.path

import datasheet


def test_read_datasheet_raises_for_a_missing_path():
    with pytest.raises(FileNotFoundError, match="No datasheet found"):
        datasheet.read_datasheet("does/not/exist.json")


def test_read_datasheet_raises_for_an_empty_file(tmp_path):
    path = tmp_path / "datasheet.json"
    path.write_text("{}")
    with pytest.raises(ValueError, match="empty"):
        datasheet.read_datasheet(str(path))


def test_read_datasheet_parses_a_populated_file(tmp_path):
    path = tmp_path / "datasheet.json"
    path.write_text(json.dumps({"motivation": {"purpose": "Audit racial disparities."}}))
    result = datasheet.read_datasheet(str(path))
    assert result["motivation"]["purpose"] == "Audit racial disparities."


def test_datasheet_schema_has_the_expected_sections_and_question_keys():
    schema = datasheet.DATASHEET_SCHEMA
    for key in ("motivation", "composition", "uses", "maintenance"):
        assert key in schema
    assert schema["motivation"]["title"] == "Motivation"
    assert "purpose" in schema["motivation"]["questions"]
    assert isinstance(schema["motivation"]["questions"]["purpose"], str)

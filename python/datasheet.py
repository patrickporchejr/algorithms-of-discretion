"""Read (never generate) a Datasheets-for-Datasets provenance document.

Per Gebru et al. 2021 ("Datasheets for Datasets"), the qualitative
reflection a datasheet captures is the point -- automating it away defeats
the purpose. This project has no wizard, scaffolder, or autofill step:
data/processed/datasheet.json is authored and edited by hand. DATASHEET_SCHEMA
exists only as a reference for which section/question keys are meaningful,
so a human filling the file in by hand knows what's expected.
"""

import json
import os

# Base seven sections from Gebru et al. 2021, plus "Positionality &
# Counter-Narrative" and "Audit Results Appendix" (Monroe-White & Lecy
# 2023's Du Boisian extension). Each section is {title, questions}, where
# `questions` maps a question key to its prompt text.
DATASHEET_SCHEMA = {
    "motivation": {
        "title": "Motivation",
        "questions": {
            "purpose": "For what purpose was the dataset created?",
            "funder": "Who funded the creation of the dataset?",
        },
    },
    "composition": {
        "title": "Composition",
        "questions": {
            "instances": "What do the instances that comprise the dataset represent?",
            "subpopulations": "Are there subpopulation identifiers (e.g. race, gender)? If so, describe them.",
            "sensitive_data": "Does the dataset contain data that might be considered sensitive?",
            "missing_info": "Is any information missing from individual instances, and if so, why?",
        },
    },
    "collection_process": {
        "title": "Collection Process",
        "questions": {
            "acquisition": "How was the data associated with each instance acquired?",
            "collectors_timeframe": "Who was involved in the data collection process, and over what timeframe?",
            "ethical_review": "Were any ethical review processes conducted?",
        },
    },
    "positionality": {
        "title": "Positionality & Counter-Narrative",
        "questions": {
            "researcher_positionality": "What is the analyst/research team's relationship to the communities and institutions this data represents, and how might that shape interpretation?",
            "whose_categories": "Whose categories does this dataset use to describe people and stops (e.g. who defines 'search', 'contraband', race labels), and what alternative framings does that choice foreclose?",
            "structural_silences": "What does this dataset structurally prevent an analyst from seeing (e.g. stops never initiated, an officer's discretion not to record an encounter, outcomes beyond citation/arrest/search)?",
            "counter_narrative": "What counter-narrative or alternative causal story should a reader hold alongside any single disparity number this dataset produces?",
        },
    },
    "preprocessing": {
        "title": "Preprocessing/cleaning/labeling",
        "questions": {
            "was_preprocessed": "Was any preprocessing/cleaning/labeling of the data done?",
            "raw_data_saved": "Was the 'raw' data saved in addition to the preprocessed/cleaned/labeled data?",
            "software_available": "Is the software used to preprocess/clean/label the data available?",
            "identity_proxies": "Are there covariates that act as proxies for protected attributes?",
        },
    },
    "uses": {
        "title": "Uses",
        "questions": {
            "prior_uses": "Has the dataset been used for any tasks already?",
            "composition_impact": "Is there anything about the composition of the dataset, or the way it was collected, that might impact future uses?",
            "inappropriate_uses": "Are there tasks for which the dataset should not be used?",
        },
    },
    "audit_appendix": {
        "title": "Audit Results Appendix",
        "questions": {
            "vod_summary": "Summarize any Veil-of-Darkness-style (stop-decision) audit results: is there a systematic disparity shift after dark, and which subgroups/regions are reliable enough to interpret individually?",
            "search_disparity_summary": "Summarize any search-rate (frequency) disparity by race: how large is the typical gap, and how consistent is it across counties?",
            "threshold_summary": "Summarize any infra-marginality-corrected (Threshold Test style) results: where does a naive outcome-test gap agree or disagree with a corrected inferred-threshold gap, and how reliable is that fit?",
            "reliability_and_synthesis": "Given the diagnostics run on this dataset together, where does racial disparity concentrate in the stop-to-search pipeline, and what caveats limit how far that conclusion can be pushed?",
        },
    },
    "distribution": {
        "title": "Distribution",
        "questions": {
            "third_parties": "Will the dataset be distributed to third parties outside of the entity on behalf of which it was created?",
            "distribution_mechanism": "How will the dataset be distributed?",
            "licensing": "Is the dataset subject to any copyright, licensing, or export-control restrictions?",
        },
    },
    "maintenance": {
        "title": "Maintenance",
        "questions": {
            "maintainer": "Who will be supporting/hosting/maintaining the dataset?",
            "contact": "How can the owner/curator/manager of the dataset be contacted?",
            "updates": "Will the dataset be updated? If so, how often, and by whom?",
            "erratum": "Is there an erratum process for reporting errors in the dataset?",
        },
    },
}


def read_datasheet(path: str) -> dict:
    """Read and parse a hand-authored datasheet.json.

    Raises, rather than degrading gracefully, when `path` doesn't exist or
    parses to nothing -- a missing/empty datasheet is a data-entry gap the
    caller needs to know about immediately, not something to paper over
    with a silent None.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"No datasheet found at {path}. Datasheets are hand-authored, not generated -- "
            "see datasheet.DATASHEET_SCHEMA for the section/question keys, or an existing "
            "datasheet.json for an example, then write one by hand at this path."
        )
    with open(path) as f:
        data = json.load(f)
    if not data:
        raise ValueError(f"Datasheet at {path} is empty.")
    return data

"""Loads the numbered pipeline scripts (01_fetch_census.py, ...) as modules.

Their filenames start with a digit, so they can't be `import`ed normally --
this loads them directly from their file path instead. python/ itself is
added to sys.path so a loaded module's own top-level `import other_module`
(e.g. grounding_experiment.py importing llm_clients) resolves normally.
"""

import importlib.util
import pathlib
import sys

SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent.parent

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


def import_script(filename):
    path = SCRIPTS_DIR / filename
    module_name = filename.removesuffix(".py").replace("-", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

"""Run the naive-vs-grounded LLM datasheet-grounding experiment against this
project's real dataset, printing the result to the console.

Opt-in -- not part of `make all`/`make data`; makes real, billed API calls.
See .env.example / README for the ANTHROPIC_API_KEY / OPENAI_API_KEY /
GEMINI_API_KEY / XAI_API_KEY setup this needs. Every provider with a key set
gets run and compared.

Runs naive-only if no datasheet is found at --datasheet (default
../data/processed/datasheet.json), or if --no-datasheet is passed; runs
naive+grounded otherwise. A datasheet is hand-authored, never generated --
see datasheet.DATASHEET_SCHEMA for the section/question keys.

Usage (run from inside python/, matching 01/02/03's convention):
    python run_grounding.py
    python run_grounding.py --repeats=1
    python run_grounding.py --restart
    python run_grounding.py --no-datasheet
"""

import argparse
import json
import os

from dotenv import load_dotenv

from grounding_experiment import format_report, run_grounding_experiment

DATA_PATH = "../data/processed/audit_ready_stops.csv"
DATASHEET_PATH_DEFAULT = "../data/processed/datasheet.json"
RESULTS_DIR = "../results"
CHECKPOINT_PATH = os.path.join(RESULTS_DIR, "grounding_experiment_checkpoint.json")
RESULTS_PATH = os.path.join(RESULTS_DIR, "grounding_experiment.json")

# Update these to whatever flagship models you want to compare -- only
# providers with a matching *_API_KEY set in .env are actually called.
# Provider model IDs churn fast; if a run 404s on "model no longer
# available", check the provider's current model list.
DEFAULT_MODELS = {
    "anthropic": ("ANTHROPIC_API_KEY", "claude-opus-5"),
    "openai": ("OPENAI_API_KEY", "gpt-5.1"),
    "gemini": ("GEMINI_API_KEY", "gemini-3.1-pro-preview"),
    "grok": ("XAI_API_KEY", "grok-4.6"),
}


def main():
    parser = argparse.ArgumentParser(description="Run the naive-vs-grounded LLM datasheet-grounding experiment.")
    parser.add_argument("--restart", action="store_true", help="Ignore/overwrite an existing checkpoint and start over.")
    parser.add_argument("--repeats", type=int, default=2, help="Independent trials per (provider, condition). Default 2.")
    parser.add_argument("--datasheet", default=DATASHEET_PATH_DEFAULT, help="Path to datasheet.json.")
    parser.add_argument("--no-datasheet", action="store_true", help="Force a naive-only run even if a datasheet exists.")
    args = parser.parse_args()

    if args.repeats < 1:
        parser.error("--repeats must be a positive integer.")

    load_dotenv()

    providers, models = [], {}
    for provider, (env_var, model) in DEFAULT_MODELS.items():
        if os.environ.get(env_var):
            providers.append(provider)
            models[provider] = model

    if not providers:
        raise SystemExit(
            "None of ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY / XAI_API_KEY "
            "are set. Add at least one to a repo-root .env file -- see .env.example."
        )

    if not os.path.exists(DATA_PATH):
        raise SystemExit(f"No processed dataset at {DATA_PATH} -- run `make all` first.")

    datasheet_path = None if args.no_datasheet else args.datasheet
    if datasheet_path is not None and not os.path.exists(datasheet_path):
        print(f"No datasheet found at {datasheet_path} -- running naive-only.")
        datasheet_path = None

    os.makedirs(RESULTS_DIR, exist_ok=True)

    if args.restart and os.path.exists(CHECKPOINT_PATH):
        os.remove(CHECKPOINT_PATH)
        print(f"--restart passed: ignoring existing checkpoint at {CHECKPOINT_PATH}")
    elif os.path.exists(CHECKPOINT_PATH):
        print(f"Resuming from checkpoint at {CHECKPOINT_PATH} (pass --restart to start over)")

    mode = "naive + grounded" if datasheet_path else "naive only"
    print(f"Running grounding experiment against: {', '.join(providers)} ({mode}, {args.repeats} trial(s) per condition)...")

    result = run_grounding_experiment(
        data_path=DATA_PATH,
        datasheet_path=datasheet_path,
        providers=providers,
        models=models,
        n_repeats=args.repeats,
        checkpoint_path=CHECKPOINT_PATH,
        restart=args.restart,
    )

    # Save before printing -- every API call above is already made and
    # billed by this point, so a bug in the print path must never be able
    # to discard results that already cost real money.
    with open(RESULTS_PATH, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Wrote {RESULTS_PATH}")

    # The run finished cleanly and is fully captured in RESULTS_PATH above --
    # clear the checkpoint so the next run starts fresh instead of silently
    # replaying these same (cached, now-stale) answers.
    if os.path.exists(CHECKPOINT_PATH):
        os.remove(CHECKPOINT_PATH)

    print()
    print(format_report(result))


if __name__ == "__main__":
    main()

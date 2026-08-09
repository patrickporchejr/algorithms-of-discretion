"""Standardize a raw Stanford Open Policing Project stop file.

Not runnable yet: depends on which state file(s) get downloaded first
(README Open Questions #1) since column coverage varies by state.
"""

import pandas as pd


def clean_stops(raw_path: str) -> pd.DataFrame:
    df = pd.read_csv(raw_path, low_memory=False)

    df = df[df["subject_race"].isin(["white", "black", "hispanic"])].copy()

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    if "time" in df.columns:
        df["stop_datetime"] = pd.to_datetime(
            df["date"].astype(str) + " " + df["time"].astype(str), errors="coerce"
        )
        df["hour"] = df["stop_datetime"].dt.hour

    return df


if __name__ == "__main__":
    # TODO: point at a real downloaded state file once one is selected
    raise SystemExit("No raw stop file wired up yet — see README Open Questions #1.")

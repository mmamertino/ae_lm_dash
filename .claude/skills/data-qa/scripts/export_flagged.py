#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas", "pyarrow"]
# ///
"""Export flagged and ambiguous QA records as CSV, joined with source evidence.

Reads verdict batch files, filters to flag/ambiguous verdicts, re-joins with
the original data file to include full evidence text, and writes a CSV.

Usage:
    uv run export_flagged.py \
        --batch-dir <batches/> \
        --source-file <data.csv> \
        --id-field <col> [<col2> ...] \
        --evidence-fields <col1> <col2> ... \
        --output <flagged_records.csv>
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd


def load_verdicts(batch_dir: Path) -> list[dict]:
    """Read all batch verdict files and collect flag/ambiguous records."""
    flagged = []
    for batch_file in sorted(batch_dir.glob("batch_*.json")):
        with open(batch_file, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict) or "verdicts" not in data:
            continue
        for v in data["verdicts"]:
            if v.get("verdict") in ("flag", "ambiguous"):
                flagged.append(v)
    return flagged


def load_source(file_path: Path) -> pd.DataFrame:
    """Load source data file."""
    suffix = file_path.suffix.lower()
    if suffix == ".csv":
        return pd.read_csv(file_path)
    elif suffix == ".parquet":
        return pd.read_parquet(file_path)
    elif suffix in (".jsonl", ".ndjson"):
        return pd.read_json(file_path, lines=True)
    else:
        print(f"Error: unsupported format '{suffix}'", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Export flagged QA records as CSV")
    parser.add_argument("--batch-dir", required=True, help="Directory containing batch verdict JSON files")
    parser.add_argument("--source-file", required=True, help="Original data file")
    parser.add_argument("--id-field", required=True, nargs="+", help="ID column name(s)")
    parser.add_argument("--evidence-fields", nargs="+", required=True, help="Evidence column names to include")
    parser.add_argument("--output", required=True, help="Output CSV path")
    args = parser.parse_args()

    # Load verdicts
    flagged = load_verdicts(Path(args.batch_dir))
    if not flagged:
        print("No flagged or ambiguous records found.", file=sys.stderr)
        pd.DataFrame().to_csv(args.output, index=False)
        return

    verdicts_df = pd.DataFrame(flagged)
    verdicts_df = verdicts_df[["record_id", "assigned_label", "verdict", "error_type",
                                "suggested_label", "confidence", "reason"]]

    # Load source and build composite record IDs
    source_df = load_source(Path(args.source_file))
    id_fields = args.id_field
    source_df["record_id"] = source_df[id_fields].astype(str).agg("_".join, axis=1)

    # Select evidence columns + record_id
    keep_cols = ["record_id"] + [f for f in args.evidence_fields if f in source_df.columns]
    evidence_df = source_df[keep_cols]

    # Join verdicts with evidence
    merged = verdicts_df.merge(evidence_df, on="record_id", how="left")

    merged.to_csv(args.output, index=False)
    print(f"Wrote {len(merged)} flagged/ambiguous records to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()

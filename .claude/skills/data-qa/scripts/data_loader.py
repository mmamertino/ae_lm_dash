#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pandas", "pyarrow"]
# ///
"""Load structured data and output JSON records for QA review.

Reads CSV, Parquet, or JSONL files and outputs a JSON array of records
with standardized field names for the QA pipeline.

Usage:
    uv run data_loader.py --file <path> --id-field <col> --target-field <col> \
        --evidence-fields <col1> <col2> ... [--sample <n>] [--seed 42]

    # Batch mode: write batch files directly to a directory
    uv run data_loader.py --file <path> --id-field <col> --target-field <col> \
        --evidence-fields <col1> <col2> ... --batch-dir <dir> [--batch-size 15]
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd


def detect_format(file_path: Path) -> str:
    """Detect file format from extension."""
    suffix = file_path.suffix.lower()
    if suffix == ".csv":
        return "csv"
    elif suffix == ".parquet":
        return "parquet"
    elif suffix in (".jsonl", ".ndjson"):
        return "jsonl"
    else:
        print(f"Error: unsupported file format '{suffix}'", file=sys.stderr)
        print("Supported formats: .csv, .parquet, .jsonl, .ndjson", file=sys.stderr)
        sys.exit(1)


def load_data(file_path: Path, fmt: str) -> pd.DataFrame:
    """Load data from the specified format."""
    if fmt == "csv":
        return pd.read_csv(file_path)
    elif fmt == "parquet":
        return pd.read_parquet(file_path)
    elif fmt == "jsonl":
        return pd.read_json(file_path, lines=True)


def validate_columns(df: pd.DataFrame, id_fields: list[str], target_field: str,
                     evidence_fields: list[str], file_path: str):
    """Validate that all specified columns exist in the dataframe."""
    all_fields = id_fields + [target_field] + evidence_fields
    missing = [f for f in all_fields if f not in df.columns]
    if missing:
        print(f"Error: columns not found in {file_path}: {missing}", file=sys.stderr)
        print(f"Available columns: {list(df.columns)}", file=sys.stderr)
        sys.exit(1)


def to_records(df: pd.DataFrame, id_fields: list[str], target_field: str,
               evidence_fields: list[str]) -> list[dict]:
    """Convert dataframe to standardized record format."""
    records = []
    for _, row in df.iterrows():
        evidence = {}
        for field in evidence_fields:
            val = row[field]
            # Convert NaN to None for clean JSON
            if pd.isna(val):
                evidence[field] = None
            else:
                evidence[field] = val
        # Composite ID: join multiple fields with '_'
        record_id = "_".join(str(row[f]) for f in id_fields)
        record = {
            "record_id": record_id,
            "assigned_label": str(row[target_field]) if pd.notna(row[target_field]) else None,
            "evidence": evidence,
        }
        records.append(record)
    return records


def write_batches(records: list[dict], batch_dir: Path, batch_size: int):
    """Split records into batches and write each as a JSON file."""
    batch_dir.mkdir(parents=True, exist_ok=True)
    num_batches = (len(records) + batch_size - 1) // batch_size
    for i in range(num_batches):
        batch_id = f"batch_{i + 1:03d}"
        start = i * batch_size
        end = min(start + batch_size, len(records))
        batch_records = records[start:end]
        batch_file = batch_dir / f"{batch_id}.json"
        with open(batch_file, "w", encoding="utf-8") as f:
            json.dump(batch_records, f, ensure_ascii=False, indent=2)
        print(f"  {batch_id}: {len(batch_records)} records -> {batch_file}", file=sys.stderr)
    print(f"Wrote {num_batches} batch files to {batch_dir}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Load data for QA review")
    parser.add_argument("--file", required=True, help="Path to data file")
    parser.add_argument("--id-field", required=True, nargs="+",
                        help="Column name(s) for record ID. Multiple columns are joined with '_' to form a composite ID.")
    parser.add_argument("--target-field", required=True, help="Column name for label/target to QA")
    parser.add_argument("--evidence-fields", nargs="+", required=True,
                        help="Column names for evidence fields")
    parser.add_argument("--sample", type=int, default=None,
                        help="Random sample size (omit for full dataset)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for sampling")
    parser.add_argument("--batch-dir", default=None,
                        help="Write batch files to this directory instead of stdout")
    parser.add_argument("--batch-size", type=int, default=15,
                        help="Records per batch (only used with --batch-dir)")
    args = parser.parse_args()

    file_path = Path(args.file)
    if not file_path.exists():
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    fmt = detect_format(file_path)
    print(f"Format: {fmt}", file=sys.stderr)

    df = load_data(file_path, fmt)
    print(f"Loaded {len(df)} records", file=sys.stderr)

    id_fields = args.id_field  # already a list due to nargs="+"
    validate_columns(df, id_fields, args.target_field, args.evidence_fields, str(file_path))

    if len(id_fields) > 1:
        print(f"Using composite ID: {' + '.join(id_fields)}", file=sys.stderr)

    if args.sample and args.sample < len(df):
        df = df.sample(n=args.sample, random_state=args.seed)
        print(f"Sampled {len(df)} records (seed={args.seed})", file=sys.stderr)

    records = to_records(df, id_fields, args.target_field, args.evidence_fields)

    if args.batch_dir:
        write_batches(records, Path(args.batch_dir), args.batch_size)
    else:
        json.dump(records, sys.stdout, ensure_ascii=False, indent=None)


if __name__ == "__main__":
    main()

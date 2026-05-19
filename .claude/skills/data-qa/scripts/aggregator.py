#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Aggregate QA batch results into summary statistics.

Reads all batch_*.json files from a directory and produces both
machine-readable (aggregation.json) and human-readable (aggregation.md) output.

Usage:
    uv run aggregator.py --batch-dir <path> --output-dir <path>
"""

import argparse
import glob
import json
import sys
from collections import Counter
from pathlib import Path


def load_batches(batch_dir: Path) -> list[dict]:
    """Load all batch files from directory."""
    pattern = str(batch_dir / "batch_*.json")
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"Error: no batch files found in {batch_dir}", file=sys.stderr)
        sys.exit(1)

    batches = []
    for f in files:
        with open(f, encoding="utf-8") as fh:
            batches.append(json.load(fh))
    print(f"Loaded {len(batches)} batch files", file=sys.stderr)
    return batches


def aggregate(batches: list[dict]) -> dict:
    """Compute aggregate statistics from batch results."""
    all_verdicts = []
    observations = []
    batch_stats = []

    for batch in batches:
        verdicts = batch.get("verdicts", [])
        all_verdicts.extend(verdicts)
        if batch.get("observations"):
            observations.append({
                "batch_id": batch["batch_id"],
                "observation": batch["observations"],
            })

        # Per-batch stats
        batch_verdict_counts = Counter(v["verdict"] for v in verdicts)
        flag_count = batch_verdict_counts.get("flag", 0)
        batch_stats.append({
            "batch_id": batch["batch_id"],
            "record_count": len(verdicts),
            "flag_count": flag_count,
            "flag_rate": round(flag_count / len(verdicts), 3) if verdicts else 0,
        })

    total = len(all_verdicts)
    if total == 0:
        return {"total_reviewed": 0, "error": "No verdicts found"}

    # Verdict distribution
    verdict_counts = Counter(v["verdict"] for v in all_verdicts)
    verdict_dist = {k: {"count": v, "rate": round(v / total, 3)}
                    for k, v in sorted(verdict_counts.items())}

    # Flag rate
    flag_count = verdict_counts.get("flag", 0)
    flag_rate = round(flag_count / total, 3)

    # Flags by assigned class
    flags_by_class = Counter()
    class_totals = Counter()
    for v in all_verdicts:
        label = v.get("assigned_label", "unknown")
        class_totals[label] += 1
        if v["verdict"] == "flag":
            flags_by_class[label] += 1

    flags_by_class_detail = {}
    for label in sorted(flags_by_class.keys()):
        flags_by_class_detail[label] = {
            "flag_count": flags_by_class[label],
            "total": class_totals[label],
            "flag_rate": round(flags_by_class[label] / class_totals[label], 3),
        }

    # Flags by error_type
    error_type_counts = Counter(
        v.get("error_type", "none") for v in all_verdicts if v["verdict"] == "flag"
    )
    error_type_dist = dict(sorted(error_type_counts.items(), key=lambda x: -x[1]))

    # Confusion matrix (assigned -> suggested)
    confusion = {}
    for v in all_verdicts:
        if v.get("suggested_label"):
            assigned = v.get("assigned_label", "unknown")
            suggested = v["suggested_label"]
            key = f"{assigned} -> {suggested}"
            confusion[key] = confusion.get(key, 0) + 1
    confusion = dict(sorted(confusion.items(), key=lambda x: -x[1]))

    # Insufficient evidence rate
    insuff_count = verdict_counts.get("insufficient_evidence", 0)
    insuff_rate = round(insuff_count / total, 3)

    # Confidence distribution
    confidence_counts = Counter(v.get("confidence", "unknown") for v in all_verdicts)
    confidence_dist = dict(sorted(confidence_counts.items()))

    return {
        "total_reviewed": total,
        "verdict_distribution": verdict_dist,
        "flag_rate": flag_rate,
        "flags_by_class": flags_by_class_detail,
        "flags_by_error_type": error_type_dist,
        "confusion_matrix": confusion,
        "insufficient_evidence_rate": insuff_rate,
        "confidence_distribution": confidence_dist,
        "batch_stats": batch_stats,
        "observations": observations,
    }


def format_markdown(stats: dict) -> str:
    """Format aggregation stats as human-readable markdown."""
    lines = ["# QA Aggregation Summary", ""]

    total = stats["total_reviewed"]
    lines.append(f"**Total records reviewed**: {total}")
    lines.append(f"**Overall flag rate**: {stats['flag_rate']:.1%}")
    lines.append(f"**Insufficient evidence rate**: {stats['insufficient_evidence_rate']:.1%}")
    lines.append("")

    # Verdict distribution
    lines.append("## Verdict Distribution")
    lines.append("")
    lines.append("| Verdict | Count | Rate |")
    lines.append("|---------|------:|-----:|")
    for verdict, info in stats["verdict_distribution"].items():
        lines.append(f"| {verdict} | {info['count']} | {info['rate']:.1%} |")
    lines.append("")

    # Flags by error type
    if stats["flags_by_error_type"]:
        lines.append("## Flags by Error Type")
        lines.append("")
        lines.append("| Error Type | Count |")
        lines.append("|------------|------:|")
        for etype, count in stats["flags_by_error_type"].items():
            lines.append(f"| {etype} | {count} |")
        lines.append("")

    # Flags by class
    if stats["flags_by_class"]:
        lines.append("## Flags by Assigned Class")
        lines.append("")
        lines.append("| Class | Flags | Total | Flag Rate |")
        lines.append("|-------|------:|------:|----------:|")
        for label, info in sorted(stats["flags_by_class"].items(),
                                   key=lambda x: -x[1]["flag_rate"]):
            lines.append(f"| {label} | {info['flag_count']} | {info['total']} | {info['flag_rate']:.1%} |")
        lines.append("")

    # Confusion matrix
    if stats["confusion_matrix"]:
        lines.append("## Label Confusion Matrix")
        lines.append("")
        lines.append("| Assigned -> Suggested | Count |")
        lines.append("|----------------------|------:|")
        for pair, count in stats["confusion_matrix"].items():
            lines.append(f"| {pair} | {count} |")
        lines.append("")

    # Confidence distribution
    lines.append("## Confidence Distribution")
    lines.append("")
    lines.append("| Confidence | Count |")
    lines.append("|------------|------:|")
    for conf, count in stats["confidence_distribution"].items():
        lines.append(f"| {conf} | {count} |")
    lines.append("")

    # Per-batch stats
    lines.append("## Per-Batch Flag Rates")
    lines.append("")
    lines.append("| Batch | Records | Flags | Flag Rate |")
    lines.append("|-------|--------:|------:|----------:|")
    for bs in stats["batch_stats"]:
        lines.append(f"| {bs['batch_id']} | {bs['record_count']} | {bs['flag_count']} | {bs['flag_rate']:.1%} |")
    lines.append("")

    # Observations
    if stats["observations"]:
        lines.append("## Reviewer Observations")
        lines.append("")
        for obs in stats["observations"]:
            lines.append(f"- **{obs['batch_id']}**: {obs['observation']}")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Aggregate QA batch results")
    parser.add_argument("--batch-dir", required=True, help="Directory containing batch_*.json files")
    parser.add_argument("--output-dir", required=True, help="Directory to write aggregation output")
    args = parser.parse_args()

    batch_dir = Path(args.batch_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    batches = load_batches(batch_dir)
    stats = aggregate(batches)

    # Write machine-readable output
    json_path = output_dir / "aggregation.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
    print(f"Wrote {json_path}", file=sys.stderr)

    # Write human-readable output
    md_path = output_dir / "aggregation.md"
    md_content = format_markdown(stats)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"Wrote {md_path}", file=sys.stderr)

    # Print summary to stdout
    total = stats["total_reviewed"]
    flag_rate = stats["flag_rate"]
    print(f"Aggregation complete: {total} records, {flag_rate:.1%} flag rate")


if __name__ == "__main__":
    main()

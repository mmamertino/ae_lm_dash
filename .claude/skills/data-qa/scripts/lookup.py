#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Look up O*NET/SOC codes from the bundled reference file.

Usage:
    uv run lookup.py <reference_file> <code1> [code2] ...
    uv run lookup.py <reference_file> --search <keyword>
    uv run lookup.py <reference_file> --group <XX-XX>

Modes:
  Positional codes: look up specific codes (tries exact match, then .00 suffix)
  --search:  keyword search across titles and descriptions
  --group:   list all codes in a minor group (e.g., 29-11 for therapists)

Output goes to stdout. Designed to be called by reviewer agents.
"""

import argparse
import json
import sys
from pathlib import Path


def load_reference(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def lookup_codes(ref: dict, codes: list[str]):
    """Look up specific codes, trying exact match then .00 suffix."""
    for code in codes:
        if code in ref:
            print(f"=== {code} ===")
            print(ref[code]["onet_description"])
            print()
        elif code + ".00" in ref:
            full = code + ".00"
            print(f"=== {full} ===")
            print(ref[full]["onet_description"])
            print()
        else:
            print(f"=== {code} === NOT FOUND")
            print()


def search_keyword(ref: dict, keyword: str, max_results: int = 15):
    """Search titles and descriptions for a keyword."""
    keyword_lower = keyword.lower()
    matches = []
    for code, entry in ref.items():
        desc = entry["onet_description"].lower()
        # Prioritize title matches
        first_line = desc.split("\n")[0]
        if keyword_lower in first_line:
            matches.append((code, entry, True))
        elif keyword_lower in desc:
            matches.append((code, entry, False))

    # Sort: title matches first, then by code
    matches.sort(key=lambda x: (not x[2], x[0]))

    if not matches:
        print(f"No matches for '{keyword}'")
        return

    print(f"Found {len(matches)} matches for '{keyword}' (showing up to {max_results}):")
    print()
    for code, entry, title_match in matches[:max_results]:
        # Show just the title line
        title_line = entry["onet_description"].split("\n")[0]
        marker = " [title match]" if title_match else ""
        print(f"  {code}: {title_line}{marker}")


def list_group(ref: dict, group_prefix: str):
    """List all codes in a minor group (e.g., 29-11 for therapists)."""
    matches = {k: v for k, v in ref.items() if k.startswith(group_prefix)}
    if not matches:
        print(f"No codes found with prefix '{group_prefix}'")
        return

    print(f"Codes in group {group_prefix}* ({len(matches)} entries):")
    print()
    for code in sorted(matches):
        title_line = matches[code]["onet_description"].split("\n")[0]
        print(f"  {code}: {title_line}")


def main():
    parser = argparse.ArgumentParser(description="Look up O*NET/SOC codes")
    parser.add_argument("reference_file", help="Path to onet_codes.json")
    parser.add_argument("codes", nargs="*", help="Specific codes to look up")
    parser.add_argument("--search", help="Keyword search across titles and descriptions")
    parser.add_argument("--group", help="List all codes in a minor group prefix (e.g., 29-11)")
    parser.add_argument("--max-results", type=int, default=15, help="Max search results")
    args = parser.parse_args()

    ref_path = Path(args.reference_file)
    if not ref_path.exists():
        print(f"Error: reference file not found: {ref_path}", file=sys.stderr)
        sys.exit(1)

    ref = load_reference(str(ref_path))

    if args.search:
        search_keyword(ref, args.search, args.max_results)
    elif args.group:
        list_group(ref, args.group)
    elif args.codes:
        lookup_codes(ref, args.codes)
    else:
        print(f"Reference file has {len(ref)} codes.", file=sys.stderr)
        print("Usage: lookup.py <ref_file> <code> | --search <keyword> | --group <prefix>", file=sys.stderr)


if __name__ == "__main__":
    main()

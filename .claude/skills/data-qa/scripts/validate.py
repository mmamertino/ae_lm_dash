#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Validate agent output files for the data-qa plugin.

Reads SubagentStop hook payload from stdin to identify the exact output file
the agent created. Validates JSON structure (reviewer) or markdown structure
(pattern-miner).

Usage:
    uv run validate.py <agent-type>
    where agent-type is "reviewer" or "pattern-miner"

Exit codes:
  0 = valid (or max retries exceeded)
  2 = invalid (keep agent alive to fix)
"""

import json
import re
import sys
import tempfile
from pathlib import Path

MAX_RETRIES = 3

VALID_VERDICTS = {"pass", "flag", "ambiguous", "insufficient_evidence"}
VALID_ERROR_TYPES = {"wrong_label", "too_broad", "too_narrow", "related_but_wrong", "unsupported", None}
VALID_CONFIDENCE = {"high", "medium", "low"}

REQUIRED_PATTERN_SECTIONS = [
    "Systematic Patterns",
    "Error Signatures",
    "Rubric Improvement",
    "Data Quality",
]


def parse_stdin(agent_type: str) -> tuple[str | None, str | None]:
    """Parse SubagentStop hook payload from stdin.

    Returns (output_file, session_key).
    """
    try:
        payload = sys.stdin.read()
    except Exception:
        return None, None

    if not payload.strip():
        return None, None

    output_file = None

    if agent_type == "reviewer":
        # Look for batch output files
        # Strategy 1: Write tool file_path arguments
        write_pattern = r'"file_path"\s*:\s*"([^"]*batches/batch_[^"]+\.json)"'
        write_matches = list(re.finditer(write_pattern, payload))
        if write_matches:
            output_file = write_matches[-1].group(1)
        else:
            # Strategy 2: general path match (also catches Bash heredoc writes)
            general_pattern = r'[\w/.~-]+/batches/batch_\d+\.json'
            general_matches = list(re.finditer(general_pattern, payload))
            if general_matches:
                output_file = general_matches[-1].group(0)

    elif agent_type == "pattern-miner":
        # Look for pattern_analysis.md
        write_pattern = r'"file_path"\s*:\s*"([^"]*pattern_analysis\.md)"'
        write_matches = list(re.finditer(write_pattern, payload))
        if write_matches:
            output_file = write_matches[-1].group(1)
        else:
            general_pattern = r'[\w/.~-]+/pattern_analysis\.md'
            general_matches = list(re.finditer(general_pattern, payload))
            if general_matches:
                output_file = general_matches[-1].group(0)

    # Build session key
    if output_file:
        file_stem = Path(output_file).stem
        session_key = f"{agent_type}_{file_stem}"
    else:
        session_key = f"{agent_type}_unknown"

    return output_file, session_key


def get_retry_count(session_key: str) -> int:
    """Get retry count keyed by agent session."""
    retry_file = Path(tempfile.gettempdir()) / f"dataqa_validate_{session_key}"
    if retry_file.exists():
        try:
            return int(retry_file.read_text().strip())
        except (ValueError, OSError):
            return 0
    return 0


def increment_retry(session_key: str) -> int:
    """Increment and return retry count."""
    retry_file = Path(tempfile.gettempdir()) / f"dataqa_validate_{session_key}"
    count = get_retry_count(session_key) + 1
    retry_file.write_text(str(count))
    return count


def clear_retry(session_key: str):
    """Clear retry tracking."""
    retry_file = Path(tempfile.gettempdir()) / f"dataqa_validate_{session_key}"
    if retry_file.exists():
        retry_file.unlink()


def validate_reviewer(file_path: str) -> tuple[bool, str]:
    """Validate a reviewer batch output file."""
    path = Path(file_path)

    if not path.exists():
        return False, f"Output file not found: {file_path}"

    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON in {file_path}: {e}"

    if not isinstance(data, dict):
        return False, f"Expected JSON object, got {type(data).__name__}"

    # Check required top-level keys
    required_keys = ["batch_id", "record_count", "timestamp", "verdicts", "observations"]
    missing = [k for k in required_keys if k not in data]
    if missing:
        return False, f"Missing required keys: {missing}"

    # Check verdicts is a non-empty list
    verdicts = data["verdicts"]
    if not isinstance(verdicts, list) or len(verdicts) == 0:
        return False, "verdicts must be a non-empty list"

    # Check record_count matches
    if data["record_count"] != len(verdicts):
        return False, f"record_count ({data['record_count']}) != len(verdicts) ({len(verdicts)})"

    # Validate each verdict
    for i, v in enumerate(verdicts):
        if not isinstance(v, dict):
            return False, f"Verdict {i} is not a dict"

        # Required verdict fields
        verdict_required = ["record_id", "verdict", "confidence", "reason", "evidence_used"]
        v_missing = [k for k in verdict_required if k not in v]
        if v_missing:
            return False, f"Verdict {i} (record {v.get('record_id', '?')}) missing keys: {v_missing}"

        # Enum checks
        if v["verdict"] not in VALID_VERDICTS:
            return False, f"Verdict {i}: invalid verdict '{v['verdict']}', must be one of {VALID_VERDICTS}"

        if v["confidence"] not in VALID_CONFIDENCE:
            return False, f"Verdict {i}: invalid confidence '{v['confidence']}', must be one of {VALID_CONFIDENCE}"

        # error_type check (if present)
        if "error_type" in v and v["error_type"] not in VALID_ERROR_TYPES:
            return False, f"Verdict {i}: invalid error_type '{v['error_type']}'"

    return True, ""


def validate_pattern_miner(file_path: str) -> tuple[bool, str]:
    """Validate a pattern-miner output file."""
    path = Path(file_path)

    if not path.exists():
        return False, f"Output file not found: {file_path}"

    content = path.read_text(encoding="utf-8")

    if len(content) < 200:
        return False, f"Pattern analysis too short ({len(content)} chars, minimum 200)"

    # Check for required section headers
    missing_sections = []
    for section in REQUIRED_PATTERN_SECTIONS:
        if section not in content:
            missing_sections.append(section)

    if missing_sections:
        return False, f"Missing required sections: {missing_sections}"

    return True, ""


def main():
    if len(sys.argv) < 2:
        print("Usage: validate.py <reviewer|pattern-miner>", file=sys.stderr)
        sys.exit(1)

    agent_type = sys.argv[1]
    if agent_type not in ("reviewer", "pattern-miner"):
        print(f"Unknown agent type: {agent_type}", file=sys.stderr)
        sys.exit(1)

    output_file, session_key = parse_stdin(agent_type)

    if not output_file or not session_key:
        print("Warning: could not determine output file from hook payload", file=sys.stderr)
        sys.exit(0)

    if agent_type == "reviewer":
        is_valid, error_msg = validate_reviewer(output_file)
    else:
        is_valid, error_msg = validate_pattern_miner(output_file)

    if is_valid:
        clear_retry(session_key)
        print(f"Validation passed: {output_file}")
        sys.exit(0)

    # Invalid — check retry count
    retry_count = increment_retry(session_key)

    if retry_count >= MAX_RETRIES:
        clear_retry(session_key)
        print(f"Validation failed {MAX_RETRIES} times, giving up: {error_msg}", file=sys.stderr)
        sys.exit(0)

    print(f"Validation failed (attempt {retry_count}/{MAX_RETRIES}): {error_msg}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()

---
name: data-qa
disable-model-invocation: true
description: >
  Run a multi-pass QA review of structured data. Plans the review, builds a rubric,
  dispatches parallel reviewer agents, aggregates results, mines patterns, and
  produces a comprehensive QA report. Use this skill whenever the user mentions
  data QA, data quality review, classification validation, label checking, record
  review, occupation code QA, checking if labels are correct, validating
  assignments, or any task involving systematic review of structured records
  against a correctness standard — even if they don't say "QA" explicitly.
allowed-tools: Task, Read, Bash, Write, AskUserQuestion
---

# Data QA Orchestration

You are orchestrating a multi-pass data quality review process.

## Environment

Scripts are at `.claude/skills/data-qa/scripts/`. Reference data is at
`.claude/skills/data-qa/references/`. Use these relative paths directly
in all Bash commands.

## Overview

The QA pipeline has 7 phases. **User gates** occur after Phase 1 and Phase 2.
Everything else runs automatically once approved.

---

## Phase 1: Planning

Collect parameters from the user using the AskUserQuestion tool. The user may
provide some parameters upfront (e.g., a file path as a skill argument). Infer
what you can from the data file (read it to see columns), then ask the user for
everything you cannot infer.

**Parameters to collect:**

| Parameter | Description | Required |
|-----------|-------------|----------|
| `data_file` | Path to the data file (.csv, .parquet, .jsonl) | Yes |
| `id_field` | Column name(s) for unique record identifier. Multiple columns are joined with `_` to form a composite ID (e.g., `cluster_id company_uid`) | Yes |
| `target_field` | Column name for the label/classification to QA | Yes |
| `evidence_fields` | Column names that provide evidence for evaluating the label | Yes |
| `qa_mode` | `record_validation` or `best_label_reassessment` | Yes |
| `correctness_criterion` | What makes a label correct? (1-2 sentences) | Yes |
| `scope` | `full` or a number for random sample size | Yes |
| `workspace` | Directory for QA output (should be within or near the project dir — agents may not be able to write to arbitrary paths like `/tmp/`) | Yes |
| `run_name` | Name for this QA run | Yes |
| `reference_materials` | Paths to any reference docs the rubric should incorporate | No |
| `batch_size` | Records per batch (default: 15, range: 10-20) | No |

**How to collect:**
1. Verify the data file exists and discover its columns using Bash. Do NOT read
   the raw data file into context. Use a lightweight peek instead:
   ```bash
   head -3 <path>        # for CSV: shows header + 2 rows
   # or for parquet/jsonl:
   python3 -c "import pandas as pd; df=pd.read_parquet('<path>'); print(list(df.columns)); print(df.head(2).to_string())"
   ```
   This avoids loading large files into context.
2. Use AskUserQuestion to present what you've inferred and ask about everything
   else in a single question. Propose defaults where sensible but always let the
   user confirm or override them — **do not silently choose values**.
3. If the user's answer leaves any required parameter ambiguous, ask a focused
   follow-up via AskUserQuestion.

**QA modes explained** (include this in your question so the user can choose):
- **Record validation**: "Is the assigned label supported by the evidence?" — reviewers
  check whether evidence supports the label, not whether a better label exists
- **Best-label reassessment**: "Is there a better alternative?" — reviewers evaluate
  whether a clearly better label exists given the evidence

**Auto-detect O\*NET/SOC reference data:**
When you peek at sample rows, check if the target field contains values matching
the pattern `\d{2}-\d{4}` (SOC codes) or `\d{2}-\d{4}\.\d{2}` (O\*NET codes).
If so, this skill bundles an O\*NET reference file at
`.claude/skills/data-qa/references/onet_codes.json` with 1,045 codes including
titles, descriptions, and task lists. Tell the user you have this reference and
ask if they want to use it. If they confirm, set `reference_materials` to the
O\*NET reference path.

Once all parameters are confirmed:
1. Create the workspace directory: `<workspace>/<run-name>/` and `batches/` subdirectory
2. Write `qa_spec.md` to the workspace summarizing all parameters
3. Present the spec to the user via AskUserQuestion and ask them to confirm

**USER GATE 1**: Wait for explicit user confirmation of the spec before proceeding.

---

## Phase 2: Rubric Building

1. Load a **calibration sample** of up to 50 records (or fewer if the dataset is
   small) to study value distributions and craft calibration examples for the
   rubric. This is NOT the review itself — it's for rubric authoring only.
   ```bash
   uv run .claude/skills/data-qa/scripts/data_loader.py \
     --file <data_file> --id-field <id_field> --target-field <target_field> \
     --evidence-fields <evidence_fields...> --sample 50
   ```

2. Examine the output:
   - Value distribution of the target field
   - Character and completeness of evidence fields
   - Any obvious data quality issues

3. If the user provided reference materials, read them now. **For O\*NET references**:
   the full file is 1,045 codes — do NOT load the entire file into context. Instead,
   extract only the entries matching codes found in the calibration sample:
   ```bash
   python3 -c "
   import json, sys
   codes = sys.argv[1:]
   with open('.claude/skills/data-qa/references/onet_codes.json') as f:
       ref = json.load(f)
   for c in codes:
       if c in ref: print(f'{c}: {ref[c][\"onet_description\"][:200]}...')
       elif c + '.00' in ref: print(f'{c}.00: {ref[c+\".00\"][\"onet_description\"][:200]}...')
       else: print(f'{c}: NOT FOUND')
   " <code1> <code2> ...
   ```
   Use the sampled codes to get a feel for the reference content during rubric
   authoring. For full descriptions of calibration example codes, load the
   complete entry.

4. Build `rubric.md` in the workspace with these sections:
   - **Objective**: what the QA review is checking (based on qa_mode)
   - **Target field**: name and description of what it represents
   - **Correctness criterion**: the user's criterion, expanded with context
   - **Verdict categories**:
     - `pass`: label is correct and supported by evidence
     - `flag`: label is clearly wrong given the evidence
     - `ambiguous`: evidence is mixed or could support multiple labels
     - `insufficient_evidence`: not enough information to evaluate
   - **Error type taxonomy**: when to use each error_type value
     - `wrong_label`: completely incorrect category
     - `too_broad`: correct family but needs more specificity
     - `too_narrow`: overly specific when a broader label fits better
     - `related_but_wrong`: plausible but different from what evidence supports
     - `unsupported`: no evidence connection to the assigned label
   - **Evidence instructions**: how to weigh each evidence field
   - **Calibration examples**: 3-5 worked examples from the sample showing
     the reasoning process and expected verdicts
   - **Conservative judgment rules**: restate the preference for ambiguous
     over forced correction, and insufficient_evidence over guessing

5. Present the rubric to the user via AskUserQuestion and ask for approval.

**USER GATE 2**: Wait for explicit user approval of the rubric via AskUserQuestion.
Make any requested changes before proceeding.

---

## Phase 3: Data Loading & Batching

Use `--batch-dir` mode so the script writes batch files directly. This avoids
loading all records into the orchestrator's context.

```bash
uv run .claude/skills/data-qa/scripts/data_loader.py \
  --file <data_file> --id-field <id_field> --target-field <target_field> \
  --evidence-fields <evidence_fields...> [--sample <N>] \
  --batch-dir <workspace>/<run-name>/batches --batch-size <batch_size>
```

The script writes `batch_001.json`, `batch_002.json`, etc. to the batch directory
and reports the count to stderr. **Do NOT capture stdout** — there is none in
batch mode.

Report to user: "Loaded N records, split into M batches of ~K records each."

---

## Phase 4: Batch Review

For each batch file written by data_loader.py in Phase 3:
1. Read the batch file (e.g., `batches/batch_001.json`) to get the records
2. If O\*NET reference is active, extract the unique `assigned_label` values
   from the batch and run `lookup.py` to get their descriptions
3. Construct a self-contained Task prompt with rubric + records + reference (if any)
4. The reviewer writes its verdict output to
   `<workspace>/<run-name>/batches/<batch_id>.json`, overwriting the input
   records file. (The input records are only needed for the prompt — they're
   not needed after review.)

**Dispatch rules:**
- **Use foreground Task calls** — do NOT run reviewers in the background.
  Background agents report completion ambiguously and the skill cannot reliably
  determine whether they succeeded. Foreground tasks return their results directly.
- Dispatch up to 10 foreground Tasks in a single message (they run concurrently)
- If more than 10 batches, dispatch in waves of 10 — wait for each wave to
  complete before starting the next
- Each Task prompt must be self-contained (rubric + records + instructions)

**Task prompt template:**
```
You are a data quality reviewer. Review the following batch of records against the rubric below.

## Rubric
<full rubric.md content>

## Batch Information
- Batch ID: <batch_id>
- Output path: <workspace>/<run-name>/batches/<batch_id>.json

## Records
<JSON array of records for this batch>

## Reference Descriptions (if applicable)
<O*NET descriptions for only the assigned codes in this batch — omit this section if no reference is active>

## O*NET Reference Lookup (include ONLY when O*NET reference is active AND qa_mode is best_label_reassessment)
You can look up O*NET/SOC codes to confirm suggested alternatives. The reference
contains 1,045 occupation codes with titles, descriptions, and task lists.
  uv run .claude/skills/data-qa/scripts/lookup.py .claude/skills/data-qa/references/onet_codes.json <code>
  uv run .claude/skills/data-qa/scripts/lookup.py .claude/skills/data-qa/references/onet_codes.json --search "<keyword>"
  uv run .claude/skills/data-qa/scripts/lookup.py .claude/skills/data-qa/references/onet_codes.json --group <XX-XX>
Use lookups only when flagging a record and you want to ground your suggested_label. Do not search exhaustively.

Review every record and write your output to the specified path.
```

The SubagentStop hooks will automatically validate each reviewer's output.
If validation fails, the reviewer gets up to 3 retries.

**CRITICAL**: If a reviewer agent fails to write its output file (e.g., write
permission error), treat that batch as failed. **NEVER manually rewrite batch
output** from the agent's return message — doing so bypasses the validation
hook and risks producing files with a wrong schema. Failed batches are simply
skipped; the aggregator works with whatever batches succeeded.

After all batches complete, report: "All M batches complete (N failed). Proceeding to aggregation."

---

## Phase 5: Aggregation

1. Run the aggregator:
   ```bash
   uv run .claude/skills/data-qa/scripts/aggregator.py \
     --batch-dir <workspace>/<run-name>/batches \
     --output-dir <workspace>/<run-name>
   ```

2. Read `aggregation.md` and present the summary to the user.

3. **Decision point**: if the flag rate is 0% and there are no ambiguous verdicts,
   report this and skip to Phase 7 (no patterns to mine).

---

## Phase 6: Pattern Mining

1. Read `aggregation.md` from the workspace.

2. Collect all non-pass verdicts from the batch files (read each `batch_*.json`
   and extract verdicts where verdict != "pass").

3. Collect all `observations` strings from batch files.

4. Dispatch a single `pattern-miner` agent via Task with all content inline:

**Task prompt template:**
```
You are a pattern analyst. Analyze the following QA results to identify systematic patterns.

## Aggregation Summary
<aggregation.md content>

## Flagged Verdicts
<JSON array of all non-pass verdicts>

## Batch Observations
<list of all observation strings with batch IDs>

## Output
Write your analysis to: <workspace>/<run-name>/pattern_analysis.md
```

5. The SubagentStop hook validates the pattern-miner output.

---

## Phase 7: Reporting

1. Read all workspace files:
   - `qa_spec.md`
   - `rubric.md`
   - `aggregation.md` and `aggregation.json`
   - `pattern_analysis.md` (if it exists)
   - All batch files for the anomaly table

2. Compile `qa_report.md` in the workspace with these sections:

### Executive Summary
2-3 sentences: total records, flag rate, top finding.

### Statistics
Tables from aggregation: verdict distribution, flags by class, flags by error type,
confidence distribution.

### Anomaly Table
All flagged and ambiguous records in a table:
| Record ID | Assigned Label | Verdict | Error Type | Suggested Label | Confidence | Reason |

### Pattern Summary
Key patterns from pattern_analysis.md (if available).

### Data Quality Observations
Broader observations from pattern mining and aggregation.

### Rubric Used
The rubric that was applied (from rubric.md).

3. Export flagged records CSV:
   ```bash
   uv run .claude/skills/data-qa/scripts/export_flagged.py \
     --batch-dir <workspace>/<run-name>/batches \
     --source-file <data_file> \
     --id-field <id_field...> \
     --evidence-fields <evidence_fields...> \
     --output <workspace>/<run-name>/flagged_records.csv
   ```

4. Present the report location and key findings to the user:
   "QA report written to `<path>/qa_report.md`. Flagged records CSV: `<path>/flagged_records.csv` (N records). Key findings: ..."

---

## Error Handling

- If data_loader.py fails (missing columns, bad format), report the error and
  ask the user how to proceed
- If a reviewer batch fails validation 3 times, it is logged and skipped —
  the aggregator works with whatever batches succeeded
- If the pattern-miner fails, skip pattern analysis and note it in the report
- Never retry silently — always inform the user of failures

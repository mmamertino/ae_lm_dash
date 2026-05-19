---
name: file-issue
disable-model-invocation: true
description: >
  File a GitHub issue in bgi-econ-template or bgi-docs. Slash-command only (/file-issue).
allowed-tools: Read, Bash, AskUserQuestion, Agent
---

# File Issue

File a GitHub issue in one of the BGI repositories with context from the current conversation.

Two scopes are supported:

- **template** — issues about `Burning-Glass-Institute/bgi-econ-template` itself (skills, agents, hooks, commands, template structure).
- **catalog** — issues about data catalog content in `Burning-Glass-Institute/bgi-docs` (docs/snowflake_mcp/*-info.md files, connected_tables.md, cross-cutting rules). Use when the catalog is factually wrong, missing a column/threshold, or confusing.

## Steps

1. **Ask the user to describe the issue** using AskUserQuestion with a free-text question (no options — just ask "What's the issue?"). Mention any relevant context from the conversation (errors, files, what went wrong) but let the user drive.

2. **Ask for scope** in a single AskUserQuestion:
   - **Scope** (single-select): `template` or `catalog`.

3. **Classify and draft** — branch on scope:

   ### If `template`:
   - Second AskUserQuestion, two single-selects:
     - **Component**: `skill`, `agent`, `hook`, `command`, `template`, `other`
     - **Type**: `bug`, `enhancement`, `question`
   - Draft a title (<70 chars) and body covering: what happened, expected behavior, relevant context (files, errors, steps to reproduce).
   - Target repo: `Burning-Glass-Institute/bgi-econ-template`.
   - Labels: `<component>,<type>`.

   ### If `catalog`:
   - Ask for the view name (free-text AskUserQuestion). Accept exact view names (e.g. `POSTINGS_BGI_POSTINGS`), full Snowflake paths, or markdown-link stems.
   - If the user didn't already quote the current content in step 1, dispatch the `catalog-agent` subagent with: "Run `bgi-catalog describe <VIEW>` and return the relevant section verbatim so we can quote it in an issue." Use the returned content to populate the "Current" block in the body below. Skip this dispatch if the user already provided the text.
   - Ask one more AskUserQuestion (single-select) for **Type**: `correction` (something is wrong), `addition` (something is missing), `clarification` (something is unclear/ambiguous).
   - Draft a title like `[catalog] <VIEW>: <one-line problem>` (<70 chars).
   - Body uses this structure:
     ```
     ## View
     `ONYX_MCP_DATA.CURATED.<VIEW>` — `docs/snowflake_mcp/<FILENAME>-info.md`

     ## Section
     <Columns / Usage Guidelines / Clustering / Overview / frontmatter / etc.>

     ## Current
     > <quoted current content, or "(missing)">

     ## Proposed
     <what should be there, as a drop-in markdown block if the user can provide one>

     ## Why
     <user's reasoning — cite any evidence from the data or the user's experience>
     ```
   - Target repo: `Burning-Glass-Institute/bgi-docs`.
   - Labels: `catalog,<type>`.

4. **Confirm with the user** — present the full draft (repo, title, body, labels) as text output, then use AskUserQuestion with options "File it" / "Change something". If the user wants changes, ask what to change, revise, and confirm again.

5. **File it** — run:
   ```
   gh issue create --repo <repo> \
     --title "..." --body "..." --label <labels>
   ```

6. **Return the issue URL** to the user.

## Principles

- The user owns the words; the skill drafts but never ships without explicit approval.
- For `catalog` issues, do **not** attempt to open a PR against bgi-docs. Conventions there (date stamps, frontmatter, CLAUDE.md rules) belong to its maintainers. An issue with a concrete proposed block lets them land the fix in seconds.
- Keep drafts tight. A good issue has one problem, one proposed fix, and enough context to act on — not an essay.

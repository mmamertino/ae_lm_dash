---
name: review
description: >
  Review a file for correctness issues. Slash-command only (/review).
disable-model-invocation: true
argument-hint: "[file path]"
allowed-tools: Agent
---

# Review

Dispatch the `code-reviewer` agent to review `$ARGUMENTS` for correctness issues.

## Steps

1. **Dispatch the code-reviewer agent** with the file path from `$ARGUMENTS`:
   - Tell it which file to review
   - Pass along any specific concerns the user mentioned

2. **Present the agent's findings** to the user as-is — do not filter or editorialize.

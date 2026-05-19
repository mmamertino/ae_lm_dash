---
name: update-template
description: >
  Update this project from the latest BGI econ template. Checks .copier-answers.yml
  and runs copier update to pull in template improvements.
disable-model-invocation: true
allowed-tools: Read, Bash, AskUserQuestion
---

# Update Template

Update this project from the latest version of the BGI econ template.

## Steps

1. **Check status**: Read `.copier-answers.yml` to confirm this is a copier-managed
   project and show the user their current template version and answers.

2. **Offer update mode**: Use `AskUserQuestion` to ask how the user wants to
   update. The exact options depend on current state:

   - **Keep current answers** — fastest path; just pull in template changes.
     Always offered.
   - **Add presentation template** — only offered when the current answers have
     `include_presentations: false` (or the key is absent, which means the
     project predates the question). Flips just that one answer to `true`
     without prompting for anything else.
   - **Review answers** — copier will prompt for each question with the current
     answer as the default, so the user can accept defaults for questions they
     don't want to change and only modify the ones they do. Always offered.

   If `include_presentations: true` is already set, skip the "Add presentation"
   option — it would be a no-op.

3. **Run update**: choose the command based on the user's selection:
   - Keep answers: `copier update --trust --skip-answered`
   - Add presentation: `copier update --trust --skip-answered --data include_presentations=true`
   - Review answers: this mode needs an interactive terminal, which Claude Code
     can't provide. Give the user the command below and tell them to run it
     themselves in their own terminal. Then stop — copier will handle the
     prompts, update, and `_tasks` from there; the skill has nothing more to do.
     Do NOT try to run it yourself (copier exits with `Interactive session
     required`).
     ```bash
     copier update --trust
     ```

4. **Handle results** *(skip if the user chose "Review answers" — the skill has
   already stopped)*:
   - If the update succeeds cleanly, report what changed
   - If conflicts arise, list the files with `.rej` extensions and explain:
     - These are changes from the template that conflict with local edits
     - The most common cause is Claude editing a template-managed file in a
       previous session
     - For each conflict, the user should decide: accept the upstream change
       (if the local edit was ad hoc) or keep the local version (and consider
       upstreaming the improvement via PR to the template repo)
   - After the user resolves conflicts, remind them to delete `.rej` files

5. **Report** *(skip if the user chose "Review answers")*: Summarize what was
   updated and any remaining action items.

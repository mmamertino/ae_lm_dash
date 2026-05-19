# Advanced Economies Labor Market Dashboard

Creating a dashboard that sources a range of LM data from different sources. 

All data analysis should be in R.

## Structure

- `scripts/` — analysis code
- `data/` — local data files (intermediate CSVs, etc.)
- `presentations/` — Quarto RevealJS slide decks (BGI-branded)

## Snowflake

Snowflake connections require MFA tokens that Claude cannot provide. If a connection fails with an MFA/TOTP error, tell the user to run `sf-auth-r` outside Claude Code, then retry. Do not try to find or bypass the TOTP.

## Skills

- `/data-lookup` — Look up BGI data catalog for tables, columns, and guidelines. **Always use this before referencing a column on any Snowflake table — don't guess.** **Also always use this before assuming a dataset must come from an external source — BGI's warehouse mirrors many public datasets alongside proprietary ones.** Requires (a) `gh auth login` with access to the `Burning-Glass-Institute` org (the same auth used for `/plugin install` from `bgi-claude-plugins` — no new setup) and (b) the `bgi-catalog` CLI, installed via `uv tool install git+https://github.com/Burning-Glass-Institute/bgi-tools` (upgrade later with `uv tool upgrade bgi-tools`). Catalog content is fetched live from [`bgi-docs`](https://github.com/Burning-Glass-Institute/bgi-docs).

Other skills (`/data-qa`, `/review`, `/file-issue`, `/update-template`) are available but user-invoked only — see `.claude/skills/*/SKILL.md` for details.

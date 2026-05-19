---
name: data-lookup
description: >
  Look up BGI data catalog to find relevant tables, columns, and usage guidelines.
  Invoke whenever the user's request involves any dataset, table, or data source —
  named or described, proprietary or public. Never assume a dataset is external
  before checking; BGI's warehouse mirrors a wide range of public and proprietary
  data.
allowed-tools: Bash, Read, Agent
---

# Data Lookup

Help the user find the right BGI data for their task by dispatching the catalog agent, which fetches live documentation from the `bgi-docs` repo via the `bgi-catalog` CLI.

## Steps

1. **Dispatch the `catalog-agent` subagent** with the user's question or task context.

2. **Present the catalog agent's findings** to the user:
   - Source Snowflake table paths (`<DATABASE>.<SCHEMA>.<TABLE>`, e.g. `BGI_POSTINGS_BACKUPS.MAR_26.US_POSTINGS`) — the underlying source table, not the `ONYX_MCP_DATA.CURATED` secure view (analysis code queries Snowflake directly)
   - Relevant columns (filtered, not a full dump)
   - Join keys if multiple tables are involved
   - Confidence thresholds or preferred column choices from the usage guidelines that apply to this task

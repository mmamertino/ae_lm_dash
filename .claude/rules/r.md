# R Coding Style

## General
- Always use tidyverse — no data.table, no base R equivalents when a tidyverse function exists
- Follow the tidyverse style guide
- Use `library()` at the top of scripts, never `require()`
- Load all packages in a single setup chunk
- Call functions directly after loading packages — do not use `pkg::fn()` namespace prefixes (e.g., use `here()` not `here::here()`)
- Prefer `glue::glue()` over `sprintf()` for string interpolation — readability is a priority
- Only use `sprintf()` when there is a specific reason, such as precise number formatting (e.g., `sprintf("%.2f", x)`)

## Pipes
- Use magrittr pipe `%>%`, NOT base R pipe `|>`
- One operation per line in pipe chains
- Break long pipes (>5 steps) into named intermediates

## Paths
- Always use `here()` for file paths
- Never use `setwd()` or absolute paths
- Example: `read_csv(here("data", "raw", "postings.csv"))`

## Column Selection
- Always use explicit column names with `select()`, `mutate()`, etc.
- Never use positional indexing (e.g., `df[, 3]`)
- Use tidyselect helpers (`starts_with()`, `ends_with()`, `matches()`) for patterns

## Quarto / R Markdown
- Name every chunk descriptively: `{r load-postings-data}`
- Use kebab-case for chunk names
- Set `cache: true` in YAML header for long-running analyses
- One chunk per logical step

## Data Access (Snowflake)
- Always load `dbplyr` and `bgi` packages
- Create a connection with `make_con_new()`
- Query tables with `query_table_sf(con, database_name, schema_name, table_name)`
- **MFA:** If a connection fails with an MFA/TOTP error, do not attempt to fix it. Ask the user to run `sf-auth-r` in their terminal outside Claude Code to cache auth tokens, then retry.
- Do as much work as possible on the server side — push computation to Snowflake, collect late
- Use tidyverse verbs throughout (`filter()`, `mutate()`, `summarise()`, `group_by()`, etc.)
- `arrange()` does not work in dbplyr — use `window_order()` instead for ordering
- Stay in tidyverse — never break out into raw SQL strings. If a Snowflake function has no dbplyr translation, wrap only that expression in `sql()` inside a tidyverse verb (e.g., `mutate(year = sql("YEAR(POSTED)"))`)
- Upload a local data frame with `write_table_sf(df, con, database_name, schema_name, table_name)` from `bgi` (not `DBI::dbWriteTable`)
- Upload a lazy dbplyr query with `write_query_sf(lazy_query, con, database_name, schema_name, table_name)`
- In dbplyr, you cannot reference a column created in the same `summarise()` — split into `summarise()` + `mutate()` when derived columns depend on aggregated columns
- In dbplyr, `as.integer(BOOLEAN)` does not translate to SQL — use `ifelse(condition, 1L, 0L)` for integer indicators from logical expressions
- Use lubridate for date manipulation (e.g., `year()`, `month()`, `floor_date()`)

## ggplot
- Always use BGI colors from the `bgi` package — never use default ggplot palettes
- Discrete scales: `scale_color_bgi_d()` / `scale_fill_bgi_d()` (palette default: "Default")
- Continuous scales: `scale_color_bgi_c()` / `scale_fill_bgi_c()` (palette default: "Orange-Green")
- Available palettes: single-hue (`Oranges`, `Teals`, `Blues`, `Reds`, `Purples`, `Greens`, `Greys`), diverging (`Blue-Red`, `Purple-Yellow`, `Orange-Green`), and `Base`/`Dark`/`Light`/`Default`
- For manual color picks use `get_bgi_colors("orange", "teal", ...)` — see `bgi_color_universe` for all named colors
- Use `theme_minimal()` or `theme_light()` as the base theme
- Always label axes and titles clearly — no default "variable name" labels
- One geom per layer; avoid stacking unrelated geoms in a single plot

## Naming
- snake_case for variables and functions
- Prefix temporary/intermediate objects with a clear scope indicator
- Use meaningful names over abbreviations

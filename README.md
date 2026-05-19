# Advanced Economies Labour Market Dashboard

A self-contained HTML dashboard comparing quarterly labour-market indicators
across seven advanced economies (United States, Germany, France, Italy, Spain,
Netherlands, United Kingdom). Indicators are stitched together from Eurostat,
the UK ONS, FRED, and the US BLS into a single harmonised long-format dataset,
then visualised in a BGI-branded `flexdashboard`.

The pipeline is the source of truth — the dashboard never re-queries an API
directly. Re-running the dashboard refreshes from cached pulls; deleting the
RDS files in `data/` forces a clean pull from source.

## Data sources

| Source     | Vendor                                                | Access method                    | Vintage / coverage                        | Refresh    |
|------------|-------------------------------------------------------|----------------------------------|-------------------------------------------|------------|
| Eurostat   | Eurostat (European Commission)                        | `eurostat` R package             | EU5 + UK (UK pre-2021 only)               | Quarterly  |
| ONS        | UK Office for National Statistics                     | `httr2` against public JSON      | UK, 2021-present                          | Monthly    |
| Nomis      | UK ONS labour-market service                          | `nomisr` R package               | UK industry employment (NACE-mapped SIC)  | Quarterly  |
| FRED       | Federal Reserve Bank of St. Louis (OECD-harmonised)   | `fredr` R package                | US (primary) + UK fallback                | Monthly    |
| BLS        | US Bureau of Labor Statistics, Public Data API v2     | `httr2` POST                     | US industry (CES) and foreign-born (CPS)  | Monthly    |

Eurostat tables used: `jvs_q_nace2`, `une_rt_q`, `lfsi_emp_q` (employment +
activity indicators), `lfsq_egan2`, `lfsq_egacob`. UK ONS series: `AP2Y`,
`MGSX`, `LF24`, `LF2S`. Nomis dataset: `NM_130_1`. FRED series: `LRUN74TTUSQ156S`,
`LREM64TTUSQ156S`, `LRAC64TTUSQ156S`, `JTSJOR` (and UK fallbacks). BLS series:
CES industry employment (mapped to NACE sections; CES groups O–Q and R–U are
distributed evenly across constituent NACE letters — see caveat below).

## Output schema

`R::load_data.R::load_all_data()` returns a named list of six tibbles. Every
tibble carries the shared key columns `country_3digit` (ISO 3166-1 alpha-3),
`country_2digit` (alpha-2), `country_name`, `date` (first day of the quarter),
and `source` (`eurostat` / `ons` / `fred` / `bls`).

| List element     | Extra dimensions                                              | Value column     | Units                       |
|------------------|---------------------------------------------------------------|------------------|-----------------------------|
| `vacancy_rate`   | —                                                             | `v_rate`         | % of occupied + vacant posts |
| `unemployment`   | `age` ∈ {`Y15-74`, `Y_LT25`, `Y25-74`}                        | `u_rate`         | % of labour force            |
| `employment`     | `age` ∈ {`Y20-64`, `Y15-64`}                                  | `emp_rate`       | % of population              |
| `activity`       | `age` ∈ {`Y15-64`, `Y20-64`}                                  | `act_rate`       | % of population              |
| `emp_nace`       | `nace_r2` — NACE Rev. 2 letter section (A–U)                  | `emp_nace_ths`   | thousands of persons         |
| `emp_cob`        | `c_birth` ∈ {`TOTAL`, `NAT`, `FOR`, `EU28_FOR`, `NEU28_FOR`}  | `emp_cob_ths`    | thousands of persons         |

Coverage: 2005-Q1 onward, quarterly. Series are seasonally adjusted where the
source provides it; `emp_nace` and `emp_cob` are NSA.

### Known caveats

- **NACE Rev. 2 vs. CES (US):** BLS Current Employment Statistics groups O–Q
  (public administration, education, health) and R–U (arts, accommodation,
  other services) into two combined supersectors. The pipeline distributes
  each group evenly across its NACE letters. Country-of-letter shares for the
  US are therefore *approximate*; share-of-supersector is exact.
- **Brexit overlap:** Eurostat publishes UK series through ~2020-Q4. Post-2021
  UK rows come from ONS / Nomis / FRED. Where both pre-2021 sources exist, the
  loader prefers ONS, then FRED, then Eurostat.
- **`emp_cob` quarterly cadence:** Eurostat `lfsq_egacob` populated only Q2 of
  each year prior to ~2023; intervening quarters are genuinely absent (NA),
  not zero. Quarterly cadence has been continuous since 2023.

## How to run

### Prerequisites

- R ≥ 4.2 with: `tidyverse`, `lubridate`, `here`, `glue`, `janitor`,
  `flexdashboard`, `rmarkdown`, `knitr`, `scales`, `DT`, `eurostat`, `fredr`,
  `nomisr`, `httr2`, `zoo`. The BGI brand palette is **hardcoded into the
  dashboard** (see `bgi_palette_default` in `dashboard.Rmd`), so the private
  `bgi` R package is *not* required at render time; it is only used by the
  analysis scripts under `scripts/`.
- `pandoc` (preinstalled on GitHub Actions Ubuntu runners; `sudo apt-get
  install pandoc` for local builds).
- A FRED API key, exported as `FRED_API_KEY`, is needed only when refreshing
  the cached data; the dashboard itself renders from the committed RDS
  caches in `data/` without any API calls.

### Refresh the data

```bash
# From the repo root
Rscript -e 'source("R/load_data.R"); load_all_data()'
```

This writes (or reads) three per-module caches in `data/`:

- `data/eurostat_data_<YYYY-MM-DD>.RDS`
- `data/uk_data_<YYYY-MM-DD>.RDS`
- `data/us_data_<YYYY-MM-DD>.RDS`

Cache TTL is 24 hours per module. To force a clean pull, delete the relevant
RDS before re-running.

### Render the dashboard

```bash
# From the repo root
Rscript -e 'rmarkdown::render("dashboard.Rmd")'
```

Produces `dashboard.html` (self-contained) at the repo root. Open in any
browser; no server is required.

### Execution order summary

1. `R/setup.R` — reads `FRED_API_KEY` (sourced by `R/load_data.R`)
2. `R/country_crosswalk.R` — static 7-country mapping
3. `R/fetch_eurostat.R` → cached RDS
4. `R/fetch_uk.R`       → cached RDS
5. `R/fetch_us.R`       → cached RDS
6. `R/load_data.R::load_all_data()` — binds + dedups the three caches
7. `dashboard.Rmd`      — visualises the loader's output

## Credentials & environment variables

- **`FRED_API_KEY`** — required. Free key from https://fred.stlouisfed.org.
  Per the project rules, secrets are managed centrally via `pass`, not via
  per-project `.env` files. Retrieve and export before running R, e.g.
  `export FRED_API_KEY=$(pass show api/fred)`.

No other credentials are required. The BLS Public Data API v2 endpoint used
here accepts unauthenticated requests at the volumes the pipeline issues.

## Hosting

The dashboard is published to GitHub Pages by a workflow at
`.github/workflows/deploy-dashboard.yml`. Each push to `main` re-renders
`dashboard.Rmd` against the committed RDS caches and publishes the result
as `index.html`. Refresh the underlying data by running the loader locally
(see *How to run* above) and committing the updated RDS files in `data/`.

## Repository structure

```
ae_lm_dash/
├── R/                  # Data pipeline modules (numbered by step)
├── data/               # Per-module RDS caches + audit CSVs
├── scripts/            # Analysis Quarto notebooks
├── presentations/      # BGI RevealJS slide decks
├── _extensions/bgi/    # Vendored BGI Quarto extension (RevealJS)
├── assets/             # Dashboard-only branding (logo + CSS)
├── dashboard.Rmd       # The flexdashboard source
├── .github/workflows/  # GitHub Actions — renders & deploys to Pages
├── README.md           # This file
└── CLAUDE.md           # Project conventions for collaborators
```

## Visual style

The dashboard reuses BGI brand assets but does not edit the upstream
`_extensions/bgi/` Quarto RevealJS extension. Concretely:

- Logo: `assets/bgi-logo.svg` (copy of `_extensions/bgi/bgi-logo.svg`)
- Colours: BGI palette via the `bgi` R package
  (`scale_color_bgi_d("Default")` for discrete series,
  `scale_color_bgi_c("Orange-Green")` for continuous gradients)
- Typography: Verdana / Geneva / Tahoma stack, BGI dark blue (`#115780`)
  for headings, orange (`#e0732b`) for accents
- CSS layer: `assets/dashboard.css` adapts the brand to bootstrap /
  flexdashboard selectors

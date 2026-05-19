# Step 5: Master load function
# Combines Eurostat, UK, and US data into a single named list of tibbles.
# Handles EUR/UK deduplication for the Brexit overlap period.

library(dplyr)
library(purrr)

source("R/setup.R") # FIX 2026-05-19: load FRED key from env var before any module sources it.
source("R/country_crosswalk.R")
source("R/fetch_eurostat.R")
source("R/fetch_uk.R")
source("R/fetch_us.R")

load_all_data <- function(start_date = "2005-01-01", cache_dir = "data/") {

  message("--- Fetching Eurostat data ---")
  eur <- fetch_eurostat_data(start_date, cache_dir)

  message("--- Fetching UK data ---")
  uk <- fetch_uk_data(start_date, cache_dir)

  message("--- Fetching US data ---")
  us <- fetch_us_data(start_date, cache_dir)

  # Indicator groups shared across all three modules
  groups <- c("vacancy_rate", "unemployment", "employment",
              "activity", "emp_nace", "emp_cob")

  # For each indicator group: bind EUR + UK, de-duplicate, then bind US
  result <- set_names(groups) %>%
    map(function(group) {
      eur_df <- eur[[group]] %||% tibble()
      uk_df  <- uk[[group]]  %||% tibble()
      us_df  <- us[[group]]  %||% tibble()

      # De-duplicate EUR/UK overlap (pre-2021 UK may appear in both).
      # Prefer UK-sourced rows for any conflicts.
      eur_uk <- bind_rows(eur_df, uk_df)

      if (nrow(eur_uk) > 0 && "country_3digit" %in% names(eur_uk) && "source" %in% names(eur_uk)) {
        # Identify grouping columns (everything except the value column and source)
        value_cols <- intersect(
          c("v_rate", "u_rate", "emp_rate", "act_rate", "emp_nace_ths", "emp_cob_ths"),
          names(eur_uk)
        )
        # Keep demographic dims for dedup key
        key_cols <- setdiff(
          names(eur_uk),
          c(value_cols, "source", "country_name")
        )

        eur_uk <- eur_uk %>%
          # Sort so UK-sourced rows come first (will be kept by distinct)
          arrange(desc(source == "ons"), desc(source == "fred")) %>%
          distinct(across(all_of(key_cols)), .keep_all = TRUE)
      }

      # Bind US data
      combined <- bind_rows(eur_uk, us_df)
      combined
    })

  message("--- All data loaded ---")
  result
}

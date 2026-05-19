# Step 3b: UK fetch module
# Fills UK data from 2021 onwards (Eurostat stopped publishing UK data post-Brexit).
# Sources: ONS time series JSON, Nomis API, FRED backup, ONS XLSX downloads.

# FIX 2026-05-19: API choices below are deliberate, not accidents.
# - ONS /timeseries/{cdid}/data is an unofficial-but-stable JSON endpoint that
#   the ONS website itself uses. We hit it via raw httr2 rather than the `onsr`
#   CRAN package because `onsr` only exposes the Beta API (`api.ons.gov.uk`),
#   which does NOT return the CDID-keyed labour-market headline series we need
#   (LF24, MGSX, MGSR, ...). Switching to `onsr` would lose access to those.
# - Nomis is hit via `nomisr` (CRAN) — this is the official ropensci client.
# Both endpoints are reliable in practice; if either changes, fall back is
# documented inline at the relevant block.

library(httr2)
library(jsonlite)
library(dplyr)
library(tibble)
library(tidyr)
library(purrr)
library(zoo)
library(readxl)
library(fredr)
library(nomisr) # FIX 2026-05-19: replaces the hand-rolled httr2 Nomis call in the emp_nace block below.

source("R/country_crosswalk.R")
# FIX 2026-05-19: hardcoded FRED API key removed; key is now set via R/setup.R from FRED_API_KEY env var.

# ------------------------------------------------------------------
# ONS time series JSON helper
# Unofficial but stable endpoint: https://www.ons.gov.uk/.../timeseries/{cdid}/data
# Returns JSON with quarters/months arrays. No API key needed.
# ------------------------------------------------------------------
get_ons_timeseries <- function(cdid, dataset_path, label = cdid) {
  url <- paste0(
    "https://www.ons.gov.uk/", dataset_path,
    "/timeseries/", tolower(cdid), "/data"
  )

  tryCatch({
    resp <- request(url) %>%
      req_headers("Accept" = "application/json") %>%
      req_perform()

    data <- resp %>% resp_body_json()

    # Extract quarterly data if available, else monthly
    if (!is.null(data$quarters) && length(data$quarters) > 0) {
      map_dfr(data$quarters, function(obs) {
        tibble(
          date  = as.Date(obs$date),
          value = suppressWarnings(as.numeric(obs$value)),
          label = obs$label %||% NA_character_
        )
      })
    } else if (!is.null(data$months) && length(data$months) > 0) {
      map_dfr(data$months, function(obs) {
        tibble(
          date  = as.Date(obs$date),
          value = suppressWarnings(as.numeric(obs$value)),
          label = obs$label %||% NA_character_
        )
      })
    } else {
      warning("ONS timeseries ", cdid, ": no quarterly or monthly data found")
      tibble(date = as.Date(character()), value = numeric(), label = character())
    }
  }, error = function(e) {
    warning("ONS timeseries pull failed for ", label, " (", cdid, "): ", conditionMessage(e))
    tibble(date = as.Date(character()), value = numeric(), label = character())
  })
}

# Helper: monthly ONS data → quarterly mean (same zoo::as.yearqtr pattern as US module)
monthly_to_quarterly <- function(df) {
  df %>%
    filter(!is.na(value)) %>%
    mutate(quarter = as.yearqtr(date)) %>%
    group_by(quarter) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    mutate(date = zoo::as.Date(quarter, frac = 0)) %>%
    select(-quarter)
}

# Standard UK columns
add_uk_cols <- function(df) {
  df %>%
    mutate(
      country_3digit = "GBR",
      country_2digit = "GB",
      country_name   = "United Kingdom",
      source         = "ons"
    )
}


fetch_uk_data <- function(start_date = "2005-01-01", cache_dir = "data/") {

  # Cache TTL: 24 hours. Delete RDS to force refresh.
  cache_file <- file.path(cache_dir, paste0("uk_data_", Sys.Date(), ".RDS"))
  if (file.exists(cache_file)) {
    file_age_hours <- difftime(Sys.time(), file.info(cache_file)$mtime, units = "hours")
    if (file_age_hours < 24) {
      message("Loading UK data from cache: ", cache_file)
      return(readRDS(cache_file))
    }
  }

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  start <- as.Date(start_date)

  # ------------------------------------------------------------------
  # Step 3b, Row 1: Vacancy rate — ONS CDID AP2Y (vacancy rate, all industries, SA)
  # ------------------------------------------------------------------
  vrate_raw <- get_ons_timeseries(
    cdid         = "AP2Y",
    dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
    label        = "vacancy rate"
  )

  vrate <- if (nrow(vrate_raw) > 0) {
    # AP2Y is quarterly — each observation is a rolling 3-month period
    vrate_raw %>%
      filter(date >= start, !is.na(value)) %>%
      transmute(date = date, v_rate = value) %>%
      add_uk_cols()
  } else {
    # Fallback to FRED if ONS fails
    message("ONS vacancy rate unavailable, no FRED equivalent exists. Returning empty.")
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           v_rate = numeric(), source = character())
  }

  # ------------------------------------------------------------------
  # Step 3b, Row 2: Unemployment rate — ONS CDID MGSX (ILO, 16+, SA)
  # Monthly rolling 3-month averages → aggregate to quarterly mean
  # ------------------------------------------------------------------
  urate_raw <- get_ons_timeseries(
    cdid         = "MGSX",
    dataset_path = "employmentandlabourmarket/peoplenotinwork/unemployment",
    label        = "unemployment rate"
  )

  urate <- if (nrow(urate_raw) > 0) {
    monthly_to_quarterly(urate_raw) %>%
      filter(date >= start) %>%
      transmute(date = date, age = "Y15-74", u_rate = value) %>%
      add_uk_cols()
  } else {
    # Fallback to FRED
    message("ONS unemployment rate unavailable, trying FRED LRHUTTTTGBQ156S")
    fred_urate <- tryCatch(
      fredr(series_id = "LRHUTTTTGBQ156S", observation_start = start) %>%
        transmute(date = as.Date(date), age = "Y15-74", u_rate = value) %>%
        add_uk_cols() %>%
        mutate(source = "fred"),
      error = function(e) {
        warning("FRED UK unemployment rate also failed: ", conditionMessage(e))
        tibble(country_3digit = character(), country_2digit = character(),
               country_name = character(), date = as.Date(character()),
               age = character(), u_rate = numeric(), source = character())
      }
    )
    fred_urate
  }

  # ------------------------------------------------------------------
  # Step 3b, Row 3: Employment rate — ONS CDID LF24 (16-64, SA)
  # Monthly → quarterly mean
  # ------------------------------------------------------------------
  emprate_raw <- get_ons_timeseries(
    cdid         = "LF24",
    dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
    label        = "employment rate"
  )

  emprate <- if (nrow(emprate_raw) > 0) {
    monthly_to_quarterly(emprate_raw) %>%
      filter(date >= start) %>%
      transmute(date = date, age = "Y15-64", emp_rate = value) %>%
      add_uk_cols()
  } else {
    # Fallback to FRED
    message("ONS employment rate unavailable, trying FRED LREM64TTGBQ156S")
    fred_emprate <- tryCatch(
      fredr(series_id = "LREM64TTGBQ156S", observation_start = start) %>%
        transmute(date = as.Date(date), age = "Y15-64", emp_rate = value) %>%
        add_uk_cols() %>%
        mutate(source = "fred"),
      error = function(e) {
        warning("FRED UK employment rate also failed: ", conditionMessage(e))
        tibble(country_3digit = character(), country_2digit = character(),
               country_name = character(), date = as.Date(character()),
               age = character(), emp_rate = numeric(), source = character())
      }
    )
    fred_emprate
  }

  # ------------------------------------------------------------------
  # Step 3b, Row 4: Activity/participation rate — ONS CDID LF2S (16-64, SA)
  # Monthly → quarterly mean
  # ------------------------------------------------------------------
  actrate_raw <- get_ons_timeseries(
    cdid         = "LF2S",
    dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
    label        = "activity rate"
  )

  actrate <- if (nrow(actrate_raw) > 0) {
    monthly_to_quarterly(actrate_raw) %>%
      filter(date >= start) %>%
      transmute(date = date, age = "Y15-64", act_rate = value) %>%
      add_uk_cols()
  } else {
    # Fallback to FRED: LRAC64TTGBQ156S = UK LF participation rate, 15-64, quarterly, SA
    message("ONS activity rate unavailable, trying FRED LRAC64TTGBQ156S")
    tryCatch(
      fredr(series_id = "LRAC64TTGBQ156S", observation_start = start) %>%
        transmute(date = as.Date(date), age = "Y15-64", act_rate = value) %>%
        add_uk_cols() %>%
        mutate(source = "fred"),
      error = function(e) {
        warning("FRED UK activity rate also failed: ", conditionMessage(e))
        tibble(country_3digit = character(), country_2digit = character(),
               country_name = character(), date = as.Date(character()),
               age = character(), act_rate = numeric(), source = character())
      }
    )
  }

  # ------------------------------------------------------------------
  # Step 3b, Row 5: Employment by industry — Nomis workforce jobs (NM_130_1)
  # ------------------------------------------------------------------
  # FIX 2026-05-19: replaced hand-rolled httr2 call on NM_4_1 (which is actually
  # "Jobseeker's Allowance by age and duration" — wrong dataset; the original code
  # was silently always falling through to the EMP13 fallback) with a nomisr pull
  # on NM_130_1 = "workforce jobs by industry (SIC 2007) - seasonally adjusted".
  # The 21 SIC section codes (150994945..150994965) are still passed explicitly —
  # Nomis does not expose the INDUSTRY codelist hierarchy via its metadata
  # endpoints, so we cannot enumerate them dynamically; but the SIC letter is
  # parsed back from INDUSTRY_NAME at runtime and 21-section completeness is
  # asserted before the mapping is applied.
  #
  # Geography 2092957697 = UK total; item=1 = "total workforce jobs";
  # measures=20100 = "value". Data is quarterly (DATE_NAME e.g. "March 2025").

  # SIC 2007 sections map 1:1 to NACE Rev. 2 sections (both share the ISIC Rev. 4
  # lineage at section level).
  sic_to_nace <- tribble(
    ~sic_letter, ~nace_r2,
    "A","A", "B","B", "C","C", "D","D", "E","E", "F","F", "G","G",
    "H","H", "I","I", "J","J", "K","K", "L","L", "M","M", "N","N",
    "O","O", "P","P", "Q","Q", "R","R", "S","S", "T","T", "U","U"
  )

  emp_nace <- tryCatch({
    start_year <- format(start, "%Y")
    nomis_raw <- nomis_get_data(
      id        = "NM_130_1",
      geography = "2092957697",
      industry  = "150994945...150994965",
      item      = 1,
      measures  = 20100,
      time      = paste0(start_year, ",latest")
    )

    if (is.null(nomis_raw) || nrow(nomis_raw) == 0) {
      stop("Nomis NM_130_1 returned 0 rows")
    }

    parsed <- nomis_raw %>%
      mutate(sic_letter = sub("^([A-U])\\s*:.*", "\\1", INDUSTRY_NAME)) %>%
      filter(grepl("^[A-U]$", sic_letter))

    unique_letters <- sort(unique(parsed$sic_letter))
    if (length(unique_letters) != 21L) {
      stop("Expected 21 SIC sections (A-U), got ", length(unique_letters),
           ": ", paste(unique_letters, collapse = ","))
    }
    message("Nomis NM_130_1 returned ", nrow(parsed), " rows across ",
            length(unique_letters), " SIC sections")

    parsed %>%
      inner_join(sic_to_nace, by = "sic_letter") %>%
      transmute(
        # NM_130_1 returns DATE as "YYYY-MM" with MM = last month of quarter
        # (e.g. "2025-03" for 2025-Q1). Convert to start-of-quarter for parity
        # with Eurostat's time = "YYYY-01-01" convention.
        date         = zoo::as.Date(zoo::as.yearqtr(as.Date(paste0(DATE, "-01"))), frac = 0),
        nace_r2      = nace_r2,
        emp_nace_ths = OBS_VALUE / 1000 # NM_130_1 OBS_VALUE is in jobs; divide by 1000 for thousands.
      ) %>%
      filter(date >= start) %>%
      add_uk_cols()
  }, error = function(e) {
    # FIX 2026-05-19: primary path is now nomisr on NM_130_1 (above); this branch
    # remains the manual-EMP13-XLSX fallback if Nomis is unavailable.
    warning("Nomis NM_130_1 pull failed: ", conditionMessage(e))
    message("TODO: UK employment by industry fallback — download EMP13 XLSX from ",
            "https://www.ons.gov.uk/employmentandlabourmarket/peopleinwork/employmentandemployeetypes/datasets/employmentbyindustryemp13 ",
            "and parse with readxl.")
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           nace_r2 = character(), emp_nace_ths = numeric(), source = character())
  })

  # ------------------------------------------------------------------
  # Step 3b, Row 6: Employment by country of birth
  # TODO: ONS API does not cover country-of-birth breakdowns cleanly.
  # Manual CSV download needed from:
  # https://www.ons.gov.uk/employmentandlabourmarket/peopleinwork/employmentandemployeetypes/datasets/employmentbycountryofbirthnotseasonallyadjusted
  # The data is NSA only at the UK-born vs non-UK-born level.
  # ------------------------------------------------------------------
  # FIX 2026-05-19: VERIFIED ON 2026-05-19 — both CDIDs return HTTP 404 on every
  # ONS timeseries URL pattern (/{dataset_path}/timeseries/MGL2/data,
  # /timeseries/MGL2/data, /timeseriestool/timeseries/MGL2/data; same for MGM2).
  # The "approximate CDID" comments below match the original author's note that
  # these were guessed, not verified. The correct UK-born / non-UK-born series
  # live in the APS A12 dataset (employmentbycountryofbirthnotseasonallyadjusted),
  # which the ONS only publishes as XLSX — there is no JSON timeseries endpoint
  # for them. The code below is left in place per Task 7c instructions; the
  # tryCatch falls through to the empty-tibble warn branch on every invocation,
  # and UK emp_cob is effectively unsourced. Real fix: implement the EMP06 / A12
  # XLSX download path in the tryCatch error branch (already TODOed below).
  emp_cob <- tryCatch({
    # Try pulling individual CDIDs from ONS time series
    # UK-born employed: approximate CDID MGL2 (NSA, thousands) — confirmed 404 in Task 7c verification (2026-05-19).
    uk_born_raw <- get_ons_timeseries(
      cdid         = "MGL2",
      dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
      label        = "UK-born employed"
    )

    # Non-UK-born employed: approximate CDID MGM2 (NSA, thousands) — confirmed 404 in Task 7c verification (2026-05-19).
    non_uk_born_raw <- get_ons_timeseries(
      cdid         = "MGM2",
      dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
      label        = "non-UK-born employed"
    )

    uk_born <- if (nrow(uk_born_raw) > 0) {
      monthly_to_quarterly(uk_born_raw) %>%
        mutate(c_birth = "NAT")
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    non_uk_born <- if (nrow(non_uk_born_raw) > 0) {
      monthly_to_quarterly(non_uk_born_raw) %>%
        mutate(c_birth = "FOR")
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    total <- if (nrow(uk_born) > 0 && nrow(non_uk_born) > 0) {
      inner_join(
        uk_born %>% select(date, nat = value),
        non_uk_born %>% select(date, for_val = value),
        by = "date"
      ) %>%
        mutate(value = nat + for_val, c_birth = "TOTAL") %>%
        select(date, value, c_birth)
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    bind_rows(uk_born, non_uk_born, total) %>%
      filter(date >= start) %>%
      transmute(
        date        = date,
        c_birth     = c_birth,
        emp_cob_ths = value
      ) %>%
      add_uk_cols()
  }, error = function(e) {
    warning("UK employment by country of birth failed: ", conditionMessage(e))
    message("TODO: UK employment by country of birth needs manual EMP06 XLSX download. ",
            "Note: data is NSA only at this level of disaggregation.")
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           c_birth = character(), emp_cob_ths = numeric(), source = character())
  })

  # ------------------------------------------------------------------
  # Return named list matching Eurostat/US module structure
  # ------------------------------------------------------------------
  result <- list(
    vacancy_rate = vrate,
    unemployment = urate,
    employment   = emprate,
    activity     = actrate,
    emp_nace     = emp_nace,
    emp_cob      = emp_cob
  )

  saveRDS(result, cache_file)
  message("UK data cached to: ", cache_file)

  result
}

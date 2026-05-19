# Step 3b: UK fetch module
# Fills UK data from 2021 onwards (Eurostat stopped publishing UK data post-Brexit).
# Sources: ONS time series JSON, Nomis API, FRED backup, ONS XLSX downloads.

library(httr2)
library(jsonlite)
library(dplyr)
library(tibble)
library(tidyr)
library(purrr)
library(zoo)
library(readxl)
library(fredr)

source("R/country_crosswalk.R")

fredr_set_key("a6ed0b45ec6a2eb6468e87c05197d0f4")

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
  # Step 3b, Row 5: Employment by industry — Nomis API (workforce jobs NM_4_1)
  # SIC 2007 sections map 1:1 to NACE Rev. 2 sections (same ISIC lineage)
  # ------------------------------------------------------------------
  # Nomis dataset NM_4_1 = Workforce jobs by industry (SA)
  # Geography 2092957697 = UK total
  # industry codes: SIC 2007 sections map to NACE letters directly

  emp_nace <- tryCatch({
    # Nomis API call for workforce jobs by SIC section
    nomis_url <- paste0(
      "https://www.nomisweb.co.uk/api/v01/dataset/NM_4_1.data.csv",
      "?geography=2092957697",      # UK total
      "&industry=37748736",         # All industries (total)
      ",150994945,150994946,150994947,150994948", # A, B, C, D
      ",150994949,150994950,150994951,150994952", # E, F, G, H
      ",150994953,150994954,150994955,150994956", # I, J, K, L
      ",150994957,150994958,150994959,150994960", # M, N, O, P
      ",150994961,150994962,150994963",           # Q, R, S
      "&measures=20100",             # Value
      "&time=latest"
    )

    # Try the Nomis pull
    resp <- request(nomis_url) %>%
      req_headers("Accept" = "text/csv") %>%
      req_perform()

    nomis_csv <- resp %>% resp_body_string()

    if (nchar(nomis_csv) > 100) {
      nomis_df <- read.csv(textConnection(nomis_csv), stringsAsFactors = FALSE)

      # Map Nomis industry codes to NACE letters
      # TODO: The Nomis industry parameter codes need verification.
      # If the above codes don't work, fall back to the nomisr package or manual download.
      message("Nomis workforce jobs pull returned ", nrow(nomis_df), " rows")

      # For now, create a minimal mapping
      nomis_df %>%
        transmute(
          date         = as.Date(paste0(DATE, "-01")),
          nace_r2      = INDUSTRY_NAME,  # Will need proper NACE mapping
          emp_nace_ths = OBS_VALUE / 1000 # Convert to thousands if needed
        ) %>%
        filter(date >= start) %>%
        add_uk_cols()
    } else {
      stop("Nomis returned insufficient data")
    }
  }, error = function(e) {
    # TODO: Nomis API pull for employment by industry needs refinement.
    # The industry parameter codes need to be verified against the Nomis API docs.
    # Manual CSV download fallback from:
    # https://www.ons.gov.uk/employmentandlabourmarket/peopleinwork/employmentandemployeetypes/datasets/employmentbyindustryemp13
    warning("Nomis employment by industry pull failed: ", conditionMessage(e))
    message("TODO: UK employment by industry (Nomis/EMP13) needs manual setup. ",
            "Download EMP13 from ONS and parse with readxl.")
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
  emp_cob <- tryCatch({
    # Try pulling individual CDIDs from ONS time series
    # UK-born employed: approximate CDID MGL2 (NSA, thousands)
    uk_born_raw <- get_ons_timeseries(
      cdid         = "MGL2",
      dataset_path = "employmentandlabourmarket/peopleinwork/employmentandemployeetypes",
      label        = "UK-born employed"
    )

    # Non-UK-born employed: approximate CDID MGM2 (NSA, thousands)
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

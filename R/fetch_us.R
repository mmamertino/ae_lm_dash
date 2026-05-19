# Step 4: US fetch module
# Pulls labor market indicators from FRED (via fredr) and BLS API v2 (via httr2).

library(fredr)
library(dplyr)
library(tibble)
library(zoo)
library(httr2)
library(jsonlite)
library(purrr)

source("R/country_crosswalk.R")

fredr_set_key("a6ed0b45ec6a2eb6468e87c05197d0f4")

fetch_us_data <- function(start_date = "2005-01-01", cache_dir = "data/") {

  # Cache TTL: 24 hours. Delete RDS to force refresh.
  cache_file <- file.path(cache_dir, paste0("us_data_", Sys.Date(), ".RDS"))
  if (file.exists(cache_file)) {
    file_age_hours <- difftime(Sys.time(), file.info(cache_file)$mtime, units = "hours")
    if (file_age_hours < 24) {
      message("Loading US data from cache: ", cache_file)
      return(readRDS(cache_file))
    }
  }

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  start <- as.Date(start_date)

  # Helper: monthly FRED → quarterly mean (same pattern as lm_data_blog_v2.R)
  monthly_to_quarterly <- function(df) {
    df %>%
      mutate(quarter = as.yearqtr(date)) %>%
      group_by(quarter) %>%
      summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
      mutate(date = zoo::as.Date(quarter, frac = 0)) %>%
      select(-quarter)
  }

  # Helper: safe fredr wrapper
  safe_fredr <- function(series_id, label) {
    tryCatch(
      fredr(
        series_id         = series_id,
        observation_start = start,
        frequency         = "m"
      ) %>%
        transmute(date = as.Date(date), value = value),
      error = function(e) {
        warning("FRED pull failed for ", label, " (", series_id, "): ", conditionMessage(e))
        tibble(date = as.Date(character()), value = numeric())
      }
    )
  }

  # ------------------------------------------------------------------
  # Step 4A: FRED series
  # ------------------------------------------------------------------

  # Step 4A, Row 1: Vacancy rate (JOLTS)
  vrate_m <- safe_fredr("JTSJOR", "vacancy rate")
  vrate <- if (nrow(vrate_m) > 0) {
    monthly_to_quarterly(vrate_m) %>%
      transmute(
        country_3digit = "USA",
        country_2digit = "US",
        country_name   = "United States",
        date           = date,
        v_rate         = value,
        source         = "us"
      )
  } else {
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           v_rate = numeric(), source = character())
  }

  # Step 4A, Row 2: Headline unemployment rate
  urate_headline_m <- safe_fredr("UNRATE", "unemployment rate")

  # Step 4A, Row 3: Youth unemployment rate (16-24)
  urate_youth_m <- safe_fredr("LNU04000036", "youth unemployment rate")

  urate <- tryCatch({
    headline_q <- if (nrow(urate_headline_m) > 0) {
      monthly_to_quarterly(urate_headline_m) %>%
        mutate(age = "Y15-74") # US headline maps to the broad 15-74 age group
    } else {
      tibble(date = as.Date(character()), value = numeric(), age = character())
    }

    youth_q <- if (nrow(urate_youth_m) > 0) {
      monthly_to_quarterly(urate_youth_m) %>%
        mutate(age = "Y_LT25") # Youth 16-24 maps to under-25
    } else {
      tibble(date = as.Date(character()), value = numeric(), age = character())
    }

    bind_rows(headline_q, youth_q) %>%
      transmute(
        country_3digit = "USA",
        country_2digit = "US",
        country_name   = "United States",
        date           = date,
        age            = age,
        u_rate         = value,
        source         = "us"
      )
  }, error = function(e) {
    warning("US unemployment rate processing failed: ", conditionMessage(e))
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           age = character(), u_rate = numeric(), source = character())
  })

  # Step 4A, Row 4: Employment-population ratio (EMRATIO)
  emratio_m <- safe_fredr("EMRATIO", "employment-population ratio")
  emprate <- if (nrow(emratio_m) > 0) {
    monthly_to_quarterly(emratio_m) %>%
      transmute(
        country_3digit = "USA",
        country_2digit = "US",
        country_name   = "United States",
        date           = date,
        age            = "Y15-64", # US EMRATIO is 16+ but mapped to broad age group
        emp_rate       = value,
        source         = "us"
      )
  } else {
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           age = character(), emp_rate = numeric(), source = character())
  }

  # Step 4A, Row 5: Labor force participation rate (CIVPART)
  civpart_m <- safe_fredr("CIVPART", "labor force participation rate")
  actrate <- if (nrow(civpart_m) > 0) {
    monthly_to_quarterly(civpart_m) %>%
      transmute(
        country_3digit = "USA",
        country_2digit = "US",
        country_name   = "United States",
        date           = date,
        age            = "Y15-64", # CIVPART is 16+ but mapped to broad age group
        act_rate       = value,
        source         = "us"
      )
  } else {
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           age = character(), act_rate = numeric(), source = character())
  }

  # ------------------------------------------------------------------
  # Step 4B: BLS API v2 — Employment by industry (CES)
  # ------------------------------------------------------------------
  bls_series_lookup <- tribble(
    ~series_id,        ~nace_r2_equivalent, ~label,
    "CES0500000001",   "B-S",               "Total nonfarm",
    "CES1000000001",   "B-E",               "Mining and logging",
    "CES2000000001",   "F",                 "Construction",
    "CES3000000001",   "C",                 "Manufacturing",
    "CES4000000001",   "G-I",               "Trade, transportation, utilities",
    "CES5000000001",   "J",                 "Information",
    "CES5500000001",   "K",                 "Financial activities",
    "CES6000000001",   "L-N",               "Professional and business services",
    "CES6500000001",   "O-Q",               "Education and health services",
    "CES7000000001",   "R-U",               "Leisure and hospitality",
    "CES8000000001",   "R-U",               "Other services",
    "CES9000000001",   "O-Q",               "Government"
  )

  # BLS v2 API pull function
  bls_pull <- function(series_ids, start_year, end_year) {
    tryCatch({
      body <- list(
        seriesid    = series_ids,
        startyear   = as.character(start_year),
        endyear     = as.character(end_year),
        registrationkey = ""
      )

      resp <- request("https://api.bls.gov/publicAPI/v2/timeseries/data/") %>%
        req_headers("Content-Type" = "application/json") %>%
        req_body_json(body) %>%
        req_perform()

      parsed <- resp %>% resp_body_json()

      if (parsed$status != "REQUEST_SUCCEEDED") {
        warning("BLS API returned status: ", parsed$status)
        return(tibble(series_id = character(), date = as.Date(character()), value = numeric()))
      }

      # Parse each series result
      map_dfr(parsed$Results$series, function(s) {
        sid <- s$seriesID
        map_dfr(s$data, function(d) {
          # Monthly: year + M01..M12; skip annual averages M13
          if (grepl("^M\\d{2}$", d$period) && d$period != "M13") {
            tibble(
              series_id = sid,
              date      = as.Date(paste0(d$year, "-", gsub("M", "", d$period), "-01")),
              value     = as.numeric(d$value)
            )
          } else {
            tibble(series_id = character(), date = as.Date(character()), value = numeric())
          }
        })
      })
    }, error = function(e) {
      warning("BLS API call failed: ", conditionMessage(e))
      tibble(series_id = character(), date = as.Date(character()), value = numeric())
    })
  }

  # BLS free tier limits to 10-year spans per call
  start_year <- as.integer(format(start, "%Y"))
  end_year   <- as.integer(format(Sys.Date(), "%Y"))

  emp_nace <- tryCatch({
    # Split into 10-year chunks if needed
    year_ranges <- list()
    y <- start_year
    while (y <= end_year) {
      y_end <- min(y + 9, end_year)
      year_ranges <- c(year_ranges, list(c(y, y_end)))
      y <- y_end + 1
    }

    bls_raw <- map_dfr(year_ranges, function(yr) {
      bls_pull(bls_series_lookup$series_id, yr[1], yr[2])
    })

    if (nrow(bls_raw) > 0) {
      bls_raw %>%
        filter(date >= start) %>%
        inner_join(bls_series_lookup, by = "series_id") %>%
        # Monthly → quarterly mean
        mutate(quarter = as.yearqtr(date)) %>%
        group_by(nace_r2_equivalent, quarter) %>%
        summarise(emp_nace_ths = mean(value, na.rm = TRUE), .groups = "drop") %>%
        mutate(date = zoo::as.Date(quarter, frac = 0)) %>%
        select(-quarter) %>%
        transmute(
          country_3digit = "USA",
          country_2digit = "US",
          country_name   = "United States",
          date           = date,
          nace_r2        = nace_r2_equivalent,
          emp_nace_ths   = emp_nace_ths,
          source         = "us"
        )
    } else {
      tibble(country_3digit = character(), country_2digit = character(),
             country_name = character(), date = as.Date(character()),
             nace_r2 = character(), emp_nace_ths = numeric(), source = character())
    }
  }, error = function(e) {
    warning("US employment by industry processing failed: ", conditionMessage(e))
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           nace_r2 = character(), emp_nace_ths = numeric(), source = character())
  })

  # ------------------------------------------------------------------
  # Step 4C: Foreign-born employment (CPS via FRED)
  # ------------------------------------------------------------------
  fb_employed_m <- safe_fredr("LNU02073395", "foreign-born employed")
  nb_employed_m <- safe_fredr("LNU02073413", "native-born employed")

  emp_cob <- tryCatch({
    fb_q <- if (nrow(fb_employed_m) > 0) {
      monthly_to_quarterly(fb_employed_m) %>%
        mutate(c_birth = "FOR")
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    nb_q <- if (nrow(nb_employed_m) > 0) {
      monthly_to_quarterly(nb_employed_m) %>%
        mutate(c_birth = "NAT")
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    total_q <- if (nrow(fb_q) > 0 && nrow(nb_q) > 0) {
      inner_join(
        fb_q %>% select(date, fb = value),
        nb_q %>% select(date, nb = value),
        by = "date"
      ) %>%
        mutate(value = fb + nb, c_birth = "TOTAL") %>%
        select(date, value, c_birth)
    } else {
      tibble(date = as.Date(character()), value = numeric(), c_birth = character())
    }

    bind_rows(fb_q, nb_q, total_q) %>%
      transmute(
        country_3digit = "USA",
        country_2digit = "US",
        country_name   = "United States",
        date           = date,
        c_birth        = c_birth,
        emp_cob_ths    = value,
        source         = "us"
      )
  }, error = function(e) {
    warning("US employment by birth country processing failed: ", conditionMessage(e))
    tibble(country_3digit = character(), country_2digit = character(),
           country_name = character(), date = as.Date(character()),
           c_birth = character(), emp_cob_ths = numeric(), source = character())
  })

  # ------------------------------------------------------------------
  # Return named list matching Eurostat module structure
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
  message("US data cached to: ", cache_file)

  result
}

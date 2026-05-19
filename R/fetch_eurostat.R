# Step 3: Eurostat fetch module
# Pulls quarterly labor market indicators for the top 5 EU economies + UK.
# UK data stops around 2020-Q4 due to Brexit — this is expected.

library(eurostat)
library(dplyr)
library(tibble)
library(lubridate)

source("R/country_crosswalk.R")

# EU geo codes (the 6 European countries in our dashboard)
# FIX 2026-05-19: Eurostat uses "UK" (not "GB") for the United Kingdom. Using "GB"
# here silently dropped every UK row at the post_process filter — see Task 5 audit
# (data/uk_eurostat_coverage_audit_RAW.csv). The crosswalk still uses "GB" (ISO
# 3166-1 alpha-2); post_process below rewrites "UK" → "GB" so downstream joins
# keep working without touching country_crosswalk.R.
EU_GEO <- c("DE", "FR", "IT", "ES", "NL", "UK")

fetch_eurostat_data <- function(start_date = "2005-01-01", cache_dir = "data/") {

  # Cache TTL: 24 hours. Delete RDS to force refresh.
  cache_file <- file.path(cache_dir, paste0("eurostat_data_", Sys.Date(), ".RDS"))
  if (file.exists(cache_file)) {
    file_age_hours <- difftime(Sys.time(), file.info(cache_file)$mtime, units = "hours")
    if (file_age_hours < 24) {
      message("Loading Eurostat data from cache: ", cache_file)
      return(readRDS(cache_file))
    }
  }

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  cw <- get_country_crosswalk()
  start <- as.Date(start_date)

  # Helper: safe get_eurostat wrapper
  safe_get_eurostat <- function(id, filters, label) {
    tryCatch(
      get_eurostat(id = id, time_format = "date", filters = filters, cache = FALSE),
      error = function(e) {
        warning("Eurostat pull failed for ", label, " (", id, "): ", conditionMessage(e))
        tibble()
      }
    )
  }

  # Helper: standard post-processing (filter geo, dates, join crosswalk)
  post_process <- function(df, start, cw) {
    if (nrow(df) == 0) return(df)
    df %>%
      filter(geo %in% EU_GEO) %>%
      # FIX 2026-05-19: translate Eurostat's "UK" code to the crosswalk's "GB" so
      # the downstream join_crosswalk(by = "country_2digit") matches the UK row.
      mutate(geo = ifelse(geo == "UK", "GB", geo)) %>%
      filter(time >= start)
  }

  join_crosswalk <- function(df, cw) {
    if (nrow(df) == 0) return(df)
    df %>%
      inner_join(cw, by = c("country_2digit" = "country_2digit"))
  }

  # ------------------------------------------------------------------
  # Step 3, Table row 1: Vacancy rate (jvs_q_nace2)
  # indic_em = "JVR" (Job Vacancy Rate), not "JOBRATE" which doesn't exist
  # ------------------------------------------------------------------
  vrate_raw <- safe_get_eurostat(
    id      = "jvs_q_nace2",
    filters = list(
      sizeclas = "TOTAL",
      indic_em = "JVR",
      nace_r2  = "B-S",
      s_adj    = "SA"
    ),
    label = "vacancy rate"
  )

  vrate <- if (nrow(vrate_raw) > 0) {
    vrate_raw %>%
      post_process(start, cw) %>%
      transmute(
        country_2digit = geo,
        date           = time,
        v_rate         = values,
        source         = "eurostat"
      ) %>%
      join_crosswalk(cw)
  } else {
    tibble(country_2digit = character(), date = as.Date(character()),
           v_rate = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  }

  # ------------------------------------------------------------------
  # Step 3, Table row 2: Unemployment rate (une_rt_q)
  # Pull for each age group separately since filters list doesn't support vectors
  # ------------------------------------------------------------------
  urate_ages <- c("Y15-74", "Y_LT25", "Y25-74")

  urate <- tryCatch({
    urate_raw <- safe_get_eurostat(
      id      = "une_rt_q",
      filters = list(
        sex    = "T",
        unit   = "PC_ACT",
        s_adj  = "SA"
      ),
      label = "unemployment rate"
    )

    if (nrow(urate_raw) > 0) {
      urate_raw %>%
        filter(age %in% urate_ages) %>%
        post_process(start, cw) %>%
        transmute(
          country_2digit = geo,
          date           = time,
          age            = age,
          u_rate         = values,
          source         = "eurostat"
        ) %>%
        join_crosswalk(cw)
    } else {
      tibble(country_2digit = character(), date = as.Date(character()),
             age = character(), u_rate = numeric(), source = character(),
             country_3digit = character(), country_name = character())
    }
  }, error = function(e) {
    warning("Unemployment rate processing failed: ", conditionMessage(e))
    tibble(country_2digit = character(), date = as.Date(character()),
           age = character(), u_rate = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  })

  # ------------------------------------------------------------------
  # Step 3, Table row 3: Employment rate (lfsi_emp_q)
  # ------------------------------------------------------------------
  emp_ages <- c("Y20-64", "Y15-64")

  emprate <- tryCatch({
    emp_raw <- safe_get_eurostat(
      id      = "lfsi_emp_q",
      filters = list(
        sex      = "T",
        unit     = "PC_POP",
        s_adj    = "SA",
        indic_em = "EMP_LFS" # FIX 2026-05-19: lfsi_emp_q at unit=PC_POP also returns ACT (activity rate). Without this filter the block was pulling BOTH indicators and writing them all as emp_rate, producing ~2-4pp contamination per (country, age, quarter).
      ),
      label = "employment rate"
    )

    if (nrow(emp_raw) > 0) {
      emp_raw %>%
        filter(age %in% emp_ages) %>%
        post_process(start, cw) %>%
        transmute(
          country_2digit = geo,
          date           = time,
          age            = age,
          emp_rate       = values,
          source         = "eurostat"
        ) %>%
        join_crosswalk(cw)
    } else {
      tibble(country_2digit = character(), date = as.Date(character()),
             age = character(), emp_rate = numeric(), source = character(),
             country_3digit = character(), country_name = character())
    }
  }, error = function(e) {
    warning("Employment rate processing failed: ", conditionMessage(e))
    tibble(country_2digit = character(), date = as.Date(character()),
           age = character(), emp_rate = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  })

  # ------------------------------------------------------------------
  # Step 3, Table row 4: Activity rate (lfsi_emp_q with indic_em = "ACT")
  # ------------------------------------------------------------------
  # FIX 2026-05-19: previous source was lfsq_argan, which is NSA — methodological
  # inconsistency vs the other SA rates from lfsi_emp_q / une_rt_q. lfsi_act_q
  # has been retired from the Eurostat TOC, so we derive the activity rate from
  # lfsi_emp_q with indic_em = "ACT" ("Persons in the labour force"), unit =
  # PC_POP, s_adj = SA — same table that powers the employment-rate block above.
  # Tradeoff: lfsi_emp_q has no UK coverage; UK activity comes through fetch_uk.R.
  act_ages <- c("Y15-64", "Y20-64")

  actrate <- tryCatch({
    act_raw <- safe_get_eurostat(
      id      = "lfsi_emp_q",
      filters = list(
        sex      = "T",
        unit     = "PC_POP",
        s_adj    = "SA",
        indic_em = "ACT"
      ),
      label = "activity rate"
    )

    if (nrow(act_raw) > 0) {
      act_raw %>%
        filter(age %in% act_ages) %>%
        post_process(start, cw) %>%
        transmute(
          country_2digit = geo,
          date           = time,
          age            = age,
          act_rate       = values,
          source         = "eurostat"
        ) %>%
        join_crosswalk(cw)
    } else {
      tibble(country_2digit = character(), date = as.Date(character()),
             age = character(), act_rate = numeric(), source = character(),
             country_3digit = character(), country_name = character())
    }
  }, error = function(e) {
    warning("Activity rate processing failed: ", conditionMessage(e))
    tibble(country_2digit = character(), date = as.Date(character()),
           age = character(), act_rate = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  })

  # ------------------------------------------------------------------
  # Step 3, Table row 5: Employment by NACE (lfsq_egan2)
  # Dimensions: freq, unit, sex, age, nace_r2, geo (no s_adj — data is NSA)
  # ------------------------------------------------------------------
  emp_nace <- tryCatch({
    nace_raw <- safe_get_eurostat(
      id      = "lfsq_egan2",
      filters = list(
        sex    = "T",
        unit   = "THS_PER",
        age    = "Y15-74"
      ),
      label = "employment by NACE"
    )

    if (nrow(nace_raw) > 0) {
      nace_raw %>%
        post_process(start, cw) %>%
        # FIX 2026-05-19: lfsq_egan2 publishes 21 section codes (A-U) plus two
        # aggregates ("TOTAL", "NRP"). Including those alongside the sections
        # double-counts when bound with other modules' section-level rows.
        # Keep only the 21 NACE Rev. 2 section letters.
        filter(nace_r2 %in% LETTERS[1:21]) %>%
        transmute(
          country_2digit = geo,
          date           = time,
          nace_r2        = nace_r2,
          emp_nace_ths   = values,
          source         = "eurostat"
        ) %>%
        join_crosswalk(cw)
    } else {
      tibble(country_2digit = character(), date = as.Date(character()),
             nace_r2 = character(), emp_nace_ths = numeric(), source = character(),
             country_3digit = character(), country_name = character())
    }
  }, error = function(e) {
    warning("Employment by NACE processing failed: ", conditionMessage(e))
    tibble(country_2digit = character(), date = as.Date(character()),
           nace_r2 = character(), emp_nace_ths = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  })

  # ------------------------------------------------------------------
  # Step 3, Table row 6: Employment by country of birth (lfsq_egacob)
  # ------------------------------------------------------------------
  # FIX 2026-05-19: frequency verified — lfsq_egacob is quarterly by table
  # structure (months 1/4/7/10), but historically only Q2 (April) of each year
  # is populated; the other three quarters are NA. From ~2023 onwards all four
  # quarters carry values. No code change needed — the table is genuinely
  # quarterly; NA-valued quarters represent no-publication, not zero, and pass
  # through to downstream consumers as such.
  cob_values <- c("TOTAL", "NAT", "FOR", "EU28_FOR", "NEU28_FOR")

  emp_cob <- tryCatch({
    cob_raw <- safe_get_eurostat(
      id      = "lfsq_egacob",
      filters = list(
        sex    = "T",
        unit   = "THS_PER",
        age    = "Y15-64"
      ),
      label = "employment by country of birth"
    )

    if (nrow(cob_raw) > 0) {
      cob_raw %>%
        filter(c_birth %in% cob_values) %>%
        post_process(start, cw) %>%
        transmute(
          country_2digit = geo,
          date           = time,
          c_birth        = c_birth,
          emp_cob_ths    = values,
          source         = "eurostat"
        ) %>%
        join_crosswalk(cw)
    } else {
      tibble(country_2digit = character(), date = as.Date(character()),
             c_birth = character(), emp_cob_ths = numeric(), source = character(),
             country_3digit = character(), country_name = character())
    }
  }, error = function(e) {
    warning("Employment by country of birth processing failed: ", conditionMessage(e))
    tibble(country_2digit = character(), date = as.Date(character()),
           c_birth = character(), emp_cob_ths = numeric(), source = character(),
           country_3digit = character(), country_name = character())
  })

  # ------------------------------------------------------------------
  # UK data caveat: log which datasets returned UK data
  # ------------------------------------------------------------------
  datasets <- list(
    vacancy_rate   = vrate,
    unemployment   = urate,
    employment     = emprate,
    activity       = actrate,
    emp_nace       = emp_nace,
    emp_cob        = emp_cob
  )

  for (nm in names(datasets)) {
    df <- datasets[[nm]]
    if (nrow(df) > 0 && "country_3digit" %in% names(df)) {
      has_uk <- "GBR" %in% df$country_3digit
      if (has_uk) {
        uk_max <- max(df$date[df$country_3digit == "GBR"], na.rm = TRUE)
        message("Eurostat ", nm, ": UK data present through ", uk_max)
      } else {
        message("Eurostat ", nm, ": no UK data returned (expected post-Brexit)")
      }
    }
  }

  # ------------------------------------------------------------------
  # Return named list of tibbles
  # ------------------------------------------------------------------
  result <- list(
    vacancy_rate   = vrate,
    unemployment   = urate,
    employment     = emprate,
    activity       = actrate,
    emp_nace       = emp_nace,
    emp_cob        = emp_cob
  )

  saveRDS(result, cache_file)
  message("Eurostat data cached to: ", cache_file)

  result
}

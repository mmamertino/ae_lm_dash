# Step 6: Test script for data fetch modules
# Sources all modules and runs basic validation checks.

library(dplyr)

# Source the master loader (which sources all sub-modules)
source("R/load_data.R")

# Target countries
TARGET_COUNTRIES <- c("USA", "DEU", "FRA", "ITA", "ESP", "NLD", "GBR")
EU_COUNTRIES     <- c("DEU", "FRA", "ITA", "ESP", "NLD")

cat("========================================\n")
cat("  Data Fetch Module Tests\n")
cat("========================================\n\n")

# Pull all data from 2019 onward for faster testing
data <- load_all_data(start_date = "2019-01-01")

pass_count <- 0
fail_count <- 0

check <- function(test_name, condition) {
  if (condition) {
    cat("[PASS] ", test_name, "\n")
    pass_count <<- pass_count + 1
  } else {
    cat("[FAIL] ", test_name, "\n")
    fail_count <<- fail_count + 1
  }
}

# ------------------------------------------------------------------
# Test 1-3: For each element, print diagnostics
# ------------------------------------------------------------------
cat("\n--- Diagnostics per indicator group ---\n\n")

for (nm in names(data)) {
  df <- data[[nm]]
  cat("Group: ", nm, "\n")
  cat("  Dimensions: ", nrow(df), " x ", ncol(df), "\n")

  if (nrow(df) > 0 && "date" %in% names(df)) {
    cat("  Date range: ", as.character(min(df$date, na.rm = TRUE)),
        " to ", as.character(max(df$date, na.rm = TRUE)), "\n")
  } else {
    cat("  Date range: [no data]\n")
  }

  if (nrow(df) > 0 && "country_3digit" %in% names(df)) {
    countries_present <- sort(unique(df$country_3digit))
    cat("  Countries: ", paste(countries_present, collapse = ", "), "\n")
  } else {
    cat("  Countries: [none]\n")
  }

  if (nrow(df) > 0) {
    cat("  Head:\n")
    print(head(df, 3))
  }
  cat("\n")
}

# ------------------------------------------------------------------
# Test 4: USA appears in every indicator group
# ------------------------------------------------------------------
cat("\n--- Test 4: USA in every group ---\n")
for (nm in names(data)) {
  df <- data[[nm]]
  has_usa <- nrow(df) > 0 && "country_3digit" %in% names(df) && "USA" %in% df$country_3digit
  check(paste0("USA in ", nm), has_usa)
}

# ------------------------------------------------------------------
# Test 5: GBR has data beyond 2020-Q4 (UK module fills post-Brexit gap)
# ------------------------------------------------------------------
cat("\n--- Test 5: GBR post-2020 data ---\n")
for (nm in names(data)) {
  df <- data[[nm]]
  if (nrow(df) > 0 && "country_3digit" %in% names(df) && "GBR" %in% df$country_3digit) {
    gbr_max <- max(df$date[df$country_3digit == "GBR"], na.rm = TRUE)
    has_post_2020 <- gbr_max > as.Date("2020-12-31")
    check(paste0("GBR post-2020 in ", nm, " (max: ", gbr_max, ")"), has_post_2020)
  } else {
    check(paste0("GBR post-2020 in ", nm, " (no GBR data)"), FALSE)
  }
}

# ------------------------------------------------------------------
# Test 6: EU5 countries in every Eurostat-sourced group
# ------------------------------------------------------------------
cat("\n--- Test 6: EU5 countries in every group ---\n")
for (nm in names(data)) {
  df <- data[[nm]]
  if (nrow(df) > 0 && "country_3digit" %in% names(df)) {
    countries_present <- unique(df$country_3digit)
    all_eu5 <- all(EU_COUNTRIES %in% countries_present)
    missing <- setdiff(EU_COUNTRIES, countries_present)
    if (length(missing) > 0) {
      check(paste0("EU5 in ", nm, " (missing: ", paste(missing, collapse = ", "), ")"), FALSE)
    } else {
      check(paste0("EU5 in ", nm), TRUE)
    }
  } else {
    check(paste0("EU5 in ", nm, " (no data)"), FALSE)
  }
}

# ------------------------------------------------------------------
# Test 7: No indicator column is 100% NA
# ------------------------------------------------------------------
cat("\n--- Test 7: No all-NA indicator columns ---\n")
value_cols <- c("v_rate", "u_rate", "emp_rate", "act_rate", "emp_nace_ths", "emp_cob_ths")
for (nm in names(data)) {
  df <- data[[nm]]
  if (nrow(df) > 0) {
    present_vals <- intersect(value_cols, names(df))
    for (vc in present_vals) {
      all_na <- all(is.na(df[[vc]]))
      check(paste0(nm, "$", vc, " not all NA"), !all_na)
    }
  }
}

# ------------------------------------------------------------------
# Test 8: No unexpected countries
# ------------------------------------------------------------------
cat("\n--- Test 8: Only target countries ---\n")
for (nm in names(data)) {
  df <- data[[nm]]
  if (nrow(df) > 0 && "country_3digit" %in% names(df)) {
    unexpected <- setdiff(unique(df$country_3digit), TARGET_COUNTRIES)
    check(paste0("Only 7 target countries in ", nm),
          length(unexpected) == 0)
    if (length(unexpected) > 0) {
      cat("  Unexpected: ", paste(unexpected, collapse = ", "), "\n")
    }
  }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
cat("\n========================================\n")
cat("  Results: ", pass_count, " passed, ", fail_count, " failed\n")
cat("========================================\n")

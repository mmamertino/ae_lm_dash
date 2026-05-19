# Debug script: check what Eurostat datasets return with various filters
library(eurostat)
library(dplyr)

cat("=== 1. JVS vacancy rate (jvs_q_nace2) ===\n")
cat("Trying without filters to see available dimensions...\n")
tryCatch({
  # Pull a tiny slice — just DE, recent data, no other filters
  jvs_raw <- get_eurostat(
    id = "jvs_q_nace2",
    time_format = "date",
    filters = list(geo = "DE"),
    cache = FALSE
  )
  cat("Rows returned:", nrow(jvs_raw), "\n")
  cat("Column names:", paste(names(jvs_raw), collapse = ", "), "\n")
  if (nrow(jvs_raw) > 0) {
    cat("Unique sizeclas:", paste(unique(jvs_raw$sizeclas), collapse = ", "), "\n")
    cat("Unique indic_em:", paste(unique(jvs_raw$indic_em), collapse = ", "), "\n")
    cat("Unique nace_r2:", paste(unique(jvs_raw$nace_r2), collapse = ", "), "\n")
    cat("Unique s_adj:", paste(unique(jvs_raw$s_adj), collapse = ", "), "\n")
  }
}, error = function(e) cat("ERROR:", conditionMessage(e), "\n"))

cat("\n=== 1b. Try EI_LMJV_Q_R2 as alternative vacancy dataset ===\n")
tryCatch({
  ei_raw <- get_eurostat(
    id = "ei_lmjv_q_r2",
    time_format = "date",
    filters = list(geo = "DE"),
    cache = FALSE
  )
  cat("Rows returned:", nrow(ei_raw), "\n")
  cat("Column names:", paste(names(ei_raw), collapse = ", "), "\n")
  if (nrow(ei_raw) > 0) {
    cat("Unique s_adj:", paste(unique(ei_raw$s_adj), collapse = ", "), "\n")
    cat("Unique indic:", paste(unique(ei_raw$indic), collapse = ", "), "\n")
    cat("Unique nace_r2:", paste(unique(ei_raw$nace_r2), collapse = ", "), "\n")
    cat("Sample:\n")
    print(head(ei_raw, 5))
  }
}, error = function(e) cat("ERROR:", conditionMessage(e), "\n"))

cat("\n=== 2. Activity rate (lfsq_argan) ===\n")
tryCatch({
  act_raw <- get_eurostat(
    id = "lfsq_argan",
    time_format = "date",
    filters = list(geo = "DE", sex = "T", age = "Y15-64"),
    cache = FALSE
  )
  cat("Rows returned:", nrow(act_raw), "\n")
  cat("Column names:", paste(names(act_raw), collapse = ", "), "\n")
  if (nrow(act_raw) > 0) {
    cat("Unique unit:", paste(unique(act_raw$unit), collapse = ", "), "\n")
    cat("Unique citizen:", paste(unique(act_raw$citizen), collapse = ", "), "\n")
    cat("Sample:\n")
    print(head(act_raw, 5))
  }
}, error = function(e) cat("ERROR:", conditionMessage(e), "\n"))

cat("\n=== 3. Employment by NACE (lfsq_egan2) ===\n")
tryCatch({
  nace_raw <- get_eurostat(
    id = "lfsq_egan2",
    time_format = "date",
    filters = list(geo = "DE", sex = "T"),
    cache = FALSE
  )
  cat("Rows returned:", nrow(nace_raw), "\n")
  cat("Column names:", paste(names(nace_raw), collapse = ", "), "\n")
  if (nrow(nace_raw) > 0) {
    cat("Unique unit:", paste(unique(nace_raw$unit), collapse = ", "), "\n")
    cat("Unique nace_r2:", paste(head(unique(nace_raw$nace_r2), 20), collapse = ", "), "\n")
    cat("Unique citizen:", if ("citizen" %in% names(nace_raw)) paste(unique(nace_raw$citizen), collapse = ", ") else "N/A", "\n")
    cat("Sample:\n")
    print(head(nace_raw, 5))
  }
}, error = function(e) cat("ERROR:", conditionMessage(e), "\n"))

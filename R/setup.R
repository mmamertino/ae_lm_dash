# FIX 2026-05-19: centralised API-key setup; FRED key sourced from FRED_API_KEY env var (set in ~/.Renviron, not committed).
library(fredr) # needed so fredr_set_key() resolves before fetch modules are sourced.
fredr_set_key(Sys.getenv("FRED_API_KEY"))

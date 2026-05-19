# Step 2: Country crosswalk for the 7-country dashboard
# Maps between ISO3 codes, Eurostat 2-digit geo codes, and human-readable names.

library(tibble)

get_country_crosswalk <- function() {
  tibble(
    country_3digit = c("USA", "DEU", "FRA", "ITA", "ESP", "NLD", "GBR"),
    country_2digit = c("US",  "DE",  "FR",  "IT",  "ES",  "NL",  "GB"),
    country_name   = c("United States", "Germany", "France", "Italy",
                       "Spain", "Netherlands", "United Kingdom")
  )
}

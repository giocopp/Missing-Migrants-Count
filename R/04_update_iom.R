suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(lubridate)
})

# Incremental update of the curated IOM CSV from new IOM MMP raw downloads.
#
# Workflow:
#   1. Download a new CSV from https://missingmigrants.iom.int/downloads
#      (it will be named something like
#      "MissingMigrants-Global-2026-05-06--19_42_11.csv").
#   2. Drop it into data/raw/.
#   3. Run `make update`  (or  `Rscript R/04_update_iom.R && Rscript R/02_build_geojson.R`).
#
# This script:
#   - Reads the canonical curated CSV (data/raw/iom_europe.csv).
#   - Globs every MissingMigrants-Global-*.csv in data/raw/.
#   - Maps the raw download schema onto the curated schema.
#   - Drops rows whose Main ID is already present in the canonical CSV.
#   - Filters to the same Europe-bound route list R/01 uses.
#   - Appends the surviving rows to data/raw/iom_europe.csv (sorted by date).
#
# After this script runs, R/02_build_geojson.R rebuilds
# data/built/incidents_iom.geojson from the now-updated canonical CSV.

CANONICAL <- "data/raw/iom_europe.csv"

# Same Europe-bound route list as R/01_filter_europe.R — keep in sync.
EUROPE_ROUTES <- c(
  "Central Mediterranean",
  "Western Mediterranean",
  "Eastern Mediterranean",
  "Western Africa / Atlantic route to the Canary Islands",
  "Western Balkans",
  "Mainland Europe to the UK",
  "Iran to Türkiye",
  "Türkiye-Europe land route",
  "Syria to Türkiye",
  "Belarus-EU border",
  "Sahara Desert crossing",
  "Italy to France",
  "Ukraine to Europe",
  "Sea crossings to Mayotte",
  "Central Mediterranean,Sahara Desert crossing"
)

in_europe_box <- function(lat, lon) {
  lat >= 10 & lat <= 75 & lon >= -25 & lon <= 55
}

# ---- Map raw IOM download schema → curated schema --------------------------
# The download format uses different column names ("Number Dead" vs
# "No. dead", "Coordinates" string vs separate Latitude/Longitude, etc.).
# Returns a tibble in the canonical column order.
parse_iom_raw <- function(path) {
  raw <- read_csv(path, show_col_types = FALSE)

  # "Coordinates" is a single string "lat, lon" — split and parse.
  coords     <- str_split_fixed(as.character(raw$Coordinates), ",\\s*", 2)
  lat        <- suppressWarnings(as.numeric(coords[, 1]))
  lon        <- suppressWarnings(as.numeric(coords[, 2]))

  # "Incident Date" looks like "Thu, 01/01/2026 - 12:00" — extract MM/DD/YYYY.
  raw_date   <- as.character(raw$`Incident Date`)
  date_str   <- str_extract(raw_date, "\\d{1,2}/\\d{1,2}/\\d{4}")
  parsed     <- mdy(date_str)
  iso_date   <- format(parsed, "%Y-%m-%d")

  # Reported Month is a name ("January"); convert to number.
  month_num  <- match(as.character(raw$`Reported Month`), month.name)

  # "Country of Incident" isn't an explicit field in the raw download; we
  # extract the last comma-separated token of "Location of death", which
  # is country in the vast majority of rows. Imperfect; fall back to NA.
  country    <- str_match(as.character(raw$`Location of death`),
                          ",\\s*([^,]+)\\s*$")[, 2]

  n_dead    <- suppressWarnings(as.numeric(raw$`Number Dead`))
  n_missing <- suppressWarnings(as.numeric(raw$`Minimum Estimated Number of Missing`))
  n_total   <- coalesce(n_dead, 0) + coalesce(n_missing, 0)

  tibble(
    `Main ID`                   = as.character(raw$`Main ID`),
    `Incident ID`               = as.character(raw$`Incident ID`),
    `Incident Type`             = "Incident",
    `Region of Incident`        = as.character(raw$Region),
    # Canonical CSV stores all date columns as <date> (parsed by readr).
    `Incident date`             = parsed,
    `Incident year`             = as.integer(raw$Year),
    `Incident month`            = month_num,
    `No. dead`                  = n_dead,
    `No. missing`               = n_missing,
    `No. dead/missing`          = n_total,
    `No. survivors`             = suppressWarnings(as.numeric(raw$`Number of Survivors`)),
    `No. Female`                = suppressWarnings(as.numeric(raw$`Number of Females`)),
    `No. Male`                  = suppressWarnings(as.numeric(raw$`Number of Males`)),
    `No. minors`                = suppressWarnings(as.numeric(raw$`Number of Children`)),
    `Country of Origin`         = as.character(raw$`Country of Origin`),
    `Region of Origin`          = as.character(raw$`Region of Origin`),
    `Cause of death (category)` = as.character(raw$`Cause of Death`),
    `Cause of death (reported)` = as.character(raw$`Cause of Death`),
    `Route`                     = as.character(raw$`Migration route`),
    `Country of Incident`       = country,
    `Location of death`         = as.character(raw$`Location of death`),
    `UNSD region`               = as.character(raw$`UNSD Geographical Grouping`),
    `Source`                    = as.character(raw$`Information Source`),
    `Link`                      = as.character(raw$URL),
    `Source Quality`            = suppressWarnings(as.numeric(raw$`Source Quality`)),
    `Latitude`                  = lat,
    `Longitude`                 = lon,
    incident_date_clean         = parsed,
    incident_date_raw           = parsed,    # canonical reads this column as <date> too
    incident_date_precision     = "day",
    source_dataset              = "IOM"
  )
}


# ---- Read existing canonical, glob raw downloads, dedupe ------------------
canonical    <- read_csv(CANONICAL, show_col_types = FALSE)
existing_ids <- as.character(canonical$`Main ID`)

new_files <- list.files(
  "data/raw",
  pattern = "^MissingMigrants-Global.*\\.csv$",
  full.names = TRUE
)

if (length(new_files) == 0) {
  cat("No MissingMigrants-Global-*.csv found in data/raw/. Nothing to update.\n")
  quit(save = "no", status = 0)
}

cat("Scanning ", length(new_files), " raw download(s):\n", sep = "")
for (f in new_files) cat("  ", f, "\n", sep = "")

new_rows <- bind_rows(lapply(new_files, parse_iom_raw))

before <- nrow(new_rows)
new_rows <- new_rows |>
  filter(
    Route %in% EUROPE_ROUTES,
    !is.na(Latitude), !is.na(Longitude),
    abs(Latitude)  <= 90,
    abs(Longitude) <= 180,
    in_europe_box(Latitude, Longitude),
    !`Main ID` %in% existing_ids
  )

cat(sprintf(
  "\n%d rows in raw downloads → %d after Europe-route + coord + dedupe filters.\n",
  before, nrow(new_rows)
))

if (nrow(new_rows) == 0) {
  cat("Canonical CSV is already up to date. Nothing to append.\n")
  quit(save = "no", status = 0)
}

# Show a small summary so the user can sanity-check what's being added.
cat("\nNew rows by route:\n")
print(new_rows |> count(Route, sort = TRUE) |> as.data.frame())
cat("\nNew rows date range: ",
    as.character(min(new_rows$incident_date_clean)), " → ",
    as.character(max(new_rows$incident_date_clean)), "\n", sep = "")

# ---- Append + write back ---------------------------------------------------
combined <- bind_rows(canonical, new_rows) |>
  arrange(incident_date_clean)

write_csv(combined, CANONICAL)

cat(sprintf("\nWrote %d rows to %s (%d new + %d existing).\n",
            nrow(combined), CANONICAL, nrow(new_rows), nrow(canonical)))
cat("Now run `Rscript R/02_build_geojson.R` (or `make geojson`) to rebuild the map data.\n")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# Filter the raw IOM Missing Migrants Project RDS to Europe-bound
# records and write the CSV that the rest of the pipeline consumes.
#
# This script is NOT part of `make all` because the source RDS lives
# in the author's private thesis project. The CSV it produces ships
# with the repo so the rest of the build is reproducible without it.

iom_path <- "/Users/giorgiocoppola/Desktop/Uni/Hertie School/6th Semester/thesis-cmr-mortality/data/processed/iom_mmp_incidents.RDS"
out_dir  <- "data/raw"

iom <- readRDS(iom_path)

# ---- Geographic envelope ----------------------------------------------------
# Europe + the launching shores and transit countries that feed it (North
# Africa, Western Sahara/Mauritania, Sahel, Türkiye/Levant, Balkans, Belarus).
# Drops geographically remote outliers (Caribbean, Mayotte, Bay of Bengal,
# French-overseas deportation deaths, etc.) that share the route tag but
# would clutter a Europe-focused map.
in_europe_box <- function(lat, lon) {
  lat >= 10 & lat <= 75 & lon >= -25 & lon <= 55
}

# ---- Europe-bound routes ----------------------------------------------------
# IOM's `Route` field tags each incident with a recognised migration corridor.
# We keep only the routes whose destination is Europe (broadly: Schengen, UK,
# Ireland, plus French overseas Mayotte) including the transit segments that
# feed those corridors (Sahara Desert, Iran-Türkiye, Syria-Türkiye, etc.).
# The downstream R/02 script narrows further to the four sea corridors.
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

iom_eu <- iom |>
  filter(
    Route %in% EUROPE_ROUTES,
    # Drop "Cumulative Incident" rows: IOM's own roll-up of multiple events,
    # would double-count if kept alongside the underlying "Incident" rows.
    !grepl("Cumulative", `Incident Type`, ignore.case = TRUE),
    !is.na(Latitude), !is.na(Longitude),
    abs(as.numeric(Longitude)) <= 180,
    abs(as.numeric(Latitude))  <= 90,
    in_europe_box(as.numeric(Latitude), as.numeric(Longitude))
  ) |>
  arrange(incident_date_clean) |>
  mutate(source_dataset = "IOM")

# ---- Sanity check + diagnostics ---------------------------------------------
stopifnot(nrow(iom_eu) > 0)

cat("IOM (Europe-bound): ", nrow(iom_eu), "rows | total dead/missing:",
    sum(iom_eu$`No. dead/missing`, na.rm = TRUE), "\n")
cat("Date range: ", as.character(min(iom_eu$incident_date_clean)),
    "to", as.character(max(iom_eu$incident_date_clean)), "\n")

# ---- Write CSV --------------------------------------------------------------
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
iom_out <- file.path(out_dir, "iom_europe.csv")
write_csv(iom_eu, iom_out)

cat("\nWrote: ", iom_out, "\n")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# Filter the raw IOM and UNITED RDS files to Europe-bound records and
# write the two CSVs that the rest of the pipeline consumes.
#
# This script is NOT part of `make all` because the source RDS files live
# in the author's private thesis project. The two CSVs it produces ship
# with the repo so the rest of the build is reproducible without them.

iom_path    <- "/Users/giorgiocoppola/Desktop/Uni/Hertie School/6th Semester/thesis-cmr-mortality/data/processed/iom_mmp_incidents.RDS"
united_path <- "/Users/giorgiocoppola/Desktop/Uni/Hertie School/6th Semester/thesis-cmr-mortality/data/processed/united_incidents.RDS"
out_dir     <- "data"

iom    <- readRDS(iom_path)
united <- readRDS(united_path)

# ---- Common geographic envelope --------------------------------------------
# Europe + the launching shores and transit countries that feed it (North
# Africa, Western Sahara/Mauritania, Sahel, Türkiye/Levant, Balkans, Belarus).
# Drops geographically remote outliers (Caribbean, Mayotte, Bay of Bengal,
# French-overseas deportation deaths, etc.) that share the route tag but
# would clutter a Europe-focused map.
in_europe_box <- function(lat, lon) {
  lat >= 10 & lat <= 75 & lon >= -25 & lon <= 55
}

# ---- IOM: Europe-bound routes -----------------------------------------------
# IOM's `Route` field tags each incident with a recognised migration corridor.
# We keep only the routes whose destination is Europe (broadly: Schengen,
# UK, Ireland, plus French overseas Mayotte) including the transit segments
# that feed those corridors (Sahara Desert, Iran-Türkiye, Syria-Türkiye, etc.).
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

# ---- UNITED: keep all rows (Europe-bound by NGO mandate) --------------------
# UNITED is "United against Refugee Deaths" — a European NGO that records
# deaths of people on routes to / inside Europe, so no route filter is needed.
# Drop the 5 rows with corrupt longitudes (-363, -379, -380, -17266954) and
# any row missing coordinates.
united_eu <- united |>
  filter(
    !is.na(latitude), !is.na(longitude),
    abs(as.numeric(longitude)) <= 180,
    abs(as.numeric(latitude))  <= 90,
    in_europe_box(as.numeric(latitude), as.numeric(longitude))
  ) |>
  arrange(incident_date_clean) |>
  mutate(source_dataset = "UNITED")

# ---- Sanity checks ----------------------------------------------------------
stopifnot(nrow(iom_eu) > 0, nrow(united_eu) > 0)

cat("IOM (Europe-bound):    ", nrow(iom_eu),    "rows | total dead/missing:",
    sum(iom_eu$`No. dead/missing`, na.rm = TRUE), "\n")
cat("UNITED (Europe-bound): ", nrow(united_eu), "rows | total deaths:      ",
    sum(united_eu$n_deaths, na.rm = TRUE), "\n")

cat("\nIOM    date range: ", as.character(min(iom_eu$incident_date_clean)),
    "to", as.character(max(iom_eu$incident_date_clean)), "\n")
cat("UNITED date range: ", as.character(min(united_eu$incident_date_clean)),
    "to", as.character(max(united_eu$incident_date_clean)), "\n")

# ---- Write CSVs -------------------------------------------------------------
iom_out    <- file.path(out_dir, "iom_europe.csv")
united_out <- file.path(out_dir, "united_europe.csv")

write_csv(iom_eu,    iom_out)
write_csv(united_eu, united_out)

cat("\nWrote:\n  ", iom_out, "\n  ", united_out, "\n")

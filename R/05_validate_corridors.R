suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

# ============================================================
# Cross-check the migration-corridor polylines (R/03_build_routes.R)
# against IOM DTM admin-0 displacement data.
#
# What this script does:
#   1. Pulls country-level (admin-0) IDP figures from the DTM API.
#   2. For each corridor, lists the waypoint countries our polylines
#      pass through and notes whether DTM reports any IDP signal for
#      that country.
#   3. Writes data/built/dtm_validation.csv (corridor, country, idp_count,
#      flag) so the methodology can reference a reproducible table.
#
# What this DOES NOT do:
#   - Validate route GEOMETRY. DTM does not publish corridor shapefiles.
#   - Validate cross-border flow magnitudes. DTM exposes country-internal
#     IDP counts, not bilateral migration flows.
#
#   A country missing from DTM does NOT mean the route is wrong — DTM
#   only operates where there is an active displacement crisis. European
#   destination countries, for instance, will appear as "no DTM signal"
#   and that is correct.
#
# Setup:
#   1. Register at https://dtm.iom.int/data-and-analysis/dtm-api and
#      generate a subscription key (free, requires an account).
#   2. Set the key in your environment before running:
#        export DTM_SUBSCRIPTION_KEY=<your-key>
#   3. Install the wrapper:
#        install.packages("dtmapi")              # CRAN, if available
#        # or
#        remotes::install_github("Displacement-Tracking-Matrix/dtmapi-R")
#   4. Run:  make validate   (or  Rscript R/05_validate_corridors.R)
# ============================================================

if (!requireNamespace("dtmapi", quietly = TRUE)) {
  stop(
    "The dtmapi R package is not installed.\n",
    "Install from CRAN:\n",
    '  install.packages("dtmapi")\n',
    "or from GitHub:\n",
    '  remotes::install_github("Displacement-Tracking-Matrix/dtmapi-R")',
    call. = FALSE
  )
}

key <- Sys.getenv("DTM_SUBSCRIPTION_KEY")
if (key == "") {
  stop(
    "Set DTM_SUBSCRIPTION_KEY in your environment first:\n",
    "  export DTM_SUBSCRIPTION_KEY=<your-key>\n",
    "Get a key by registering at https://dtm.iom.int/data-and-analysis/dtm-api",
    call. = FALSE
  )
}
# Different package versions read the key from different places — be
# permissive about which one wins.
Sys.setenv(DTM_API_KEY = key)
options(dtmapi.subscription_key = key)


# ── Waypoint countries per corridor ────────────────────────────────────────
# Hand-extracted from the polylines defined in R/03_build_routes.R. Each
# corridor's list is the set of countries any polyline tagged for that
# corridor passes through (origin, transit, or destination). Update when
# the polyline geometry changes.
WAYPOINT_COUNTRIES <- list(
  "Western Africa / Atlantic route to the Canary Islands" = c(
    "Senegal", "Gambia", "Guinea-Bissau", "Guinea", "Sierra Leone",
    "Liberia", "Mauritania", "Western Sahara", "Morocco", "Mali",
    "Burkina Faso", "Niger", "Spain"
  ),
  "Western Mediterranean" = c(
    "Niger", "Algeria", "Morocco", "Mali", "Mauritania",
    "Western Sahara", "Spain", "Tunisia", "Senegal", "Gambia",
    "Somalia", "Ethiopia", "Sudan"
  ),
  "Central Mediterranean" = c(
    "Niger", "Libya", "Tunisia", "Italy", "Malta", "Algeria",
    "Nigeria", "Burkina Faso", "Cameroon", "Chad", "Sudan", "Mali",
    "Ethiopia", "Egypt"
  ),
  "Eastern Mediterranean" = c(
    "Iran", "Iraq", "Türkiye", "Syria", "Lebanon", "Cyprus",
    "Greece", "Bulgaria", "Serbia", "Albania", "North Macedonia",
    "Croatia", "Israel", "Libya"
  ),
  "East Africa" = c(
    "Kenya", "Ethiopia", "Sudan", "Egypt", "Libya", "Tunisia",
    "Eritrea", "Somalia", "Djibouti", "Yemen", "Saudi Arabia",
    "Israel", "Jordan"
  ),
  "Other" = c(
    "Russia", "Belarus", "Poland", "Ukraine", "Germany", "Denmark",
    "Sweden", "Austria", "France", "United Kingdom", "Belgium",
    "Hungary", "Italy", "Spain", "Norway"
  )
)


# ── Pull DTM coverage (countries with any DTM operation) ──────────────────
# get_all_countries() returns one row per country DTM has data for. Cheap
# (single API call) and gives us a binary "DTM operates here or not" flag,
# which is exactly what we need for corridor sanity-checking.
cat("Fetching DTM country list ...\n")
dtm_countries <- tryCatch(
  dtmapi::get_all_countries(),
  error = function(e) {
    stop("DTM API call failed: ", conditionMessage(e),
         "\nVerify your DTM_SUBSCRIPTION_KEY is correct and active.",
         call. = FALSE)
  }
)
cat(sprintf("  DTM publishes data for %d countries.\n", nrow(dtm_countries)))

# Pick whichever country-name column the response actually has.
name_col <- intersect(c("admin0Name", "countryName", "country", "name"),
                      names(dtm_countries))[1]
if (is.na(name_col)) {
  cat("DTM response columns: ",
      paste(names(dtm_countries), collapse = ", "), "\n")
  stop("Couldn't find a country-name column in the DTM response.",
       call. = FALSE)
}

# Optional: pull operation count per country if that column exists, just
# as a "how active is DTM here" signal.
op_col <- intersect(c("operationCount", "operations", "rounds", "numRounds"),
                    names(dtm_countries))[1]


# ── Match corridor waypoints against DTM coverage ────────────────────
# Aliases for cases where DTM's official country name differs from the
# common spelling we use in the polylines.
ALIASES <- c(
  "syria"     = "syrian arab republic",
  "drc"       = "democratic republic of the congo",
  "south sudan" = "south sudan"
)

norm <- function(x) {
  v <- tolower(trimws(as.character(x)))
  v <- gsub("\\s+\\(.*\\)$", "", v)             # strip "(the)" etc.
  v <- gsub("[éèê]", "e", v)
  v <- gsub("ü", "u", v)
  ifelse(v %in% names(ALIASES), unname(ALIASES[v]), v)
}
dtm_keys <- norm(dtm_countries[[name_col]])

rows <- list()
for (corridor in names(WAYPOINT_COUNTRIES)) {
  for (c in WAYPOINT_COUNTRIES[[corridor]]) {
    idx <- which(dtm_keys == norm(c))
    in_dtm <- length(idx) > 0
    op_n <- NA_integer_
    if (in_dtm && !is.na(op_col)) {
      op_n <- as.integer(dtm_countries[[op_col]][idx[1]])
    }
    rows[[length(rows) + 1L]] <- tibble(
      corridor   = corridor,
      country    = c,
      in_dtm     = in_dtm,
      operations = op_n
    )
  }
}
report <- bind_rows(rows)


# ── Print + save ──────────────────────────────────────────────────────────
cat("\n--- Corridor waypoint coverage in DTM ---\n")
for (corr in names(WAYPOINT_COUNTRIES)) {
  cat("\n", corr, "\n", strrep("-", nchar(corr)), "\n", sep = "")
  sub <- report[report$corridor == corr, ]
  for (i in seq_len(nrow(sub))) {
    if (sub$in_dtm[i]) {
      tag <- if (!is.na(sub$operations[i]))
        sprintf("  (%d operations)", sub$operations[i]) else ""
      cat(sprintf("  v %-25s  in DTM%s\n", sub$country[i], tag))
    } else {
      cat(sprintf("  x %-25s  no DTM signal\n", sub$country[i]))
    }
  }
}

dir.create("data/built", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/built/dtm_validation.csv"
write_csv(report, out_path)
cat("\nWrote: ", out_path, "\n", sep = "")

hit_n  <- sum(report$in_dtm)
miss_n <- sum(!report$in_dtm)
cat(sprintf("\n%d / %d waypoint-countries are in DTM coverage.\n",
            hit_n, hit_n + miss_n))
cat("'No DTM signal' for European destination countries is expected:",
    "DTM operates where there is active displacement, not in destinations.\n",
    sep = "\n")

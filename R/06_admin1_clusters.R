suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(sf)
  library(rnaturalearth)
})

# ============================================================
# Use DTM admin-1 IDP data to sanity-check the *within-country* path of
# our corridor polylines.
#
# For each displacement-active transit country our polylines pass
# through, this script:
#   1. Pulls DTM admin-1 IDP rows.
#   2. Aggregates to one row per admin-1 zone (latest reporting round).
#   3. Reports the top 3 zones by IDP count.
#   4. Looks up each top zone's centroid via rnaturalearth and compares
#      its distance to the nearest waypoint in our R/03 polylines.
#
# The output is a sanity-check, not an automatic redraw. If a top
# DTM admin-1 zone sits >300 km from any waypoint we currently use,
# it's flagged as "consider adding a waypoint near …".
#
# Setup: same DTM_SUBSCRIPTION_KEY env var as R/05 + the rnaturalearth
# package. Run with `make admin1` (target added in Makefile).
# ============================================================

if (!requireNamespace("dtmapi", quietly = TRUE)) {
  stop('Install dtmapi first:  install.packages("dtmapi")', call. = FALSE)
}
key <- Sys.getenv("DTM_SUBSCRIPTION_KEY")
if (key == "") {
  stop("Set DTM_SUBSCRIPTION_KEY first (see R/05_validate_corridors.R).",
       call. = FALSE)
}

# Transit countries our polylines actually pass through with active DTM
# operations (intersection of WAYPOINT_COUNTRIES from R/05 and the DTM
# country list). Add or trim here when polyline geometry changes.
TRANSIT <- c(
  "Niger", "Mali", "Burkina Faso", "Nigeria", "Cameroon", "Chad",
  "Sudan", "Libya", "Ethiopia", "Somalia", "Yemen", "Iraq",
  "Lebanon", "Syria", "Ukraine"
)

# ── 1. Pull admin-1 IDP rows per transit country ───────────────────────
fetch_one <- function(cn) {
  cat(" • ", cn, " ... ", sep = "")
  x <- tryCatch(
    dtmapi::get_idp_admin1_data(CountryName = cn),
    error = function(e) {
      cat("FAILED (", conditionMessage(e), ")\n", sep = "")
      NULL
    }
  )
  if (is.null(x) || nrow(x) == 0) { cat("0 rows\n"); return(NULL) }
  cat(nrow(x), " rows\n", sep = "")
  x
}
cat("Fetching DTM admin-1 IDP data ...\n")
admin1 <- bind_rows(lapply(TRANSIT, fetch_one))

if (nrow(admin1) == 0) {
  stop("No admin-1 data returned for any country.", call. = FALSE)
}

# Aggregate: latest IDP count per (country, admin-1) — sum across
# displacementReason categories, keep the most recent reporting round.
latest <- admin1 |>
  filter(!is.na(numPresentIdpInd)) |>
  group_by(admin0Name, admin1Name, admin1Pcode) |>
  arrange(desc(reportingDate)) |>
  slice(1) |>
  ungroup()

# Top-3 admin-1 zones per country.
top_zones <- latest |>
  group_by(admin0Name) |>
  arrange(desc(numPresentIdpInd), .by_group = TRUE) |>
  slice_head(n = 3) |>
  ungroup() |>
  select(country = admin0Name, admin1 = admin1Name,
         pcode = admin1Pcode, idp = numPresentIdpInd)


# ── 2. Pull rnaturalearth admin-1 polygons + compute centroids ─────────
cat("\nLooking up admin-1 centroids from rnaturalearth ...\n")
sf::sf_use_s2(FALSE)
ne1 <- ne_states(returnclass = "sf") |>
  select(adm0_a3, admin, name, geometry)
ne_centroids <- suppressWarnings(st_centroid(ne1))
ne_xy <- ne_centroids |>
  mutate(lon = sf::st_coordinates(geometry)[, 1],
         lat = sf::st_coordinates(geometry)[, 2]) |>
  st_drop_geometry()

# Match on (country_name, admin1_name) — earlier we matched on admin1
# name only, which cross-joined countries that share a state name
# (e.g. "Northern" exists in Sudan, Ghana, etc.).
norm <- function(x) gsub("[^a-z]", "", tolower(as.character(x)))
ne_xy$ckey <- norm(ne_xy$admin)
ne_xy$akey <- norm(ne_xy$name)
top_zones$ckey <- norm(top_zones$country)
top_zones$akey <- norm(top_zones$admin1)
top_zones <- top_zones |>
  left_join(ne_xy |> select(ckey, akey, ne_lat = lat, ne_lon = lon),
            by = c("ckey", "akey")) |>
  select(-ckey, -akey)


# ── 3. Existing waypoints from our polylines ───────────────────────────
# Source the route file so we can read ROUTE_LINES into R memory.
cat("Loading waypoints from R/03_build_routes.R ...\n")
# Light-weight: source the script in a temp environment and grab
# ROUTE_LINES + the country list out of it.
src_env <- new.env()
sys.source("R/03_build_routes.R", envir = src_env, chdir = TRUE,
           keep.source = FALSE)
waypoints <- bind_rows(lapply(src_env$ROUTE_LINES, function(ln) {
  do.call(rbind, ln$coords) |>
    as_tibble(.name_repair = ~ c("lat", "lon")) |>
    mutate(route = ln$route)
}))


# ── 4. Distance check ──────────────────────────────────────────────────
# Haversine in km (good enough at this scale).
hav_km <- function(lat1, lon1, lat2, lon2) {
  to_rad <- pi / 180
  lat1 <- lat1 * to_rad; lat2 <- lat2 * to_rad
  dlat <- lat2 - lat1
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
  2 * 6371 * asin(sqrt(a))
}

nearest_waypoint <- function(lat, lon) {
  if (is.na(lat) || is.na(lon)) return(NA_real_)
  d <- hav_km(lat, lon, waypoints$lat, waypoints$lon)
  min(d, na.rm = TRUE)
}

top_zones$nearest_waypoint_km <- mapply(
  nearest_waypoint, top_zones$ne_lat, top_zones$ne_lon
)


# ── 5. Print + save ────────────────────────────────────────────────────
cat("\n--- Top-3 DTM admin-1 IDP zones per transit country ---\n")
cat("(distance = km from the nearest waypoint in any current polyline)\n")
for (cn in unique(top_zones$country)) {
  cat("\n", cn, "\n", strrep("-", nchar(cn)), "\n", sep = "")
  sub <- top_zones |> filter(country == cn)
  for (i in seq_len(nrow(sub))) {
    flag <- ""
    if (!is.na(sub$nearest_waypoint_km[i]) &&
        sub$nearest_waypoint_km[i] > 300) {
      flag <- "  <-- > 300 km from nearest waypoint, consider adding"
    }
    if (is.na(sub$ne_lat[i])) {
      cat(sprintf("  %-25s  %s IDPs  (no centroid match)\n",
                  sub$admin1[i],
                  format(sub$idp[i], big.mark = ",", scientific = FALSE)))
    } else {
      cat(sprintf("  %-25s  %s IDPs  ~%d km from nearest WP%s\n",
                  sub$admin1[i],
                  format(sub$idp[i], big.mark = ",", scientific = FALSE),
                  round(sub$nearest_waypoint_km[i]),
                  flag))
    }
  }
}

dir.create("data/built", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/built/dtm_admin1_clusters.csv"
write_csv(top_zones, out_path)
cat("\nWrote: ", out_path, "\n", sep = "")
cat("\nUse this as a sanity check, not as a redraw — DTM admin-1 zones",
    "show *where displaced people currently live*, not where the route",
    "physically goes. The corridor SHAPE remains informed by IOM-GOMR /",
    "Mixed Migration Centre / Frontex, which DTM does not replace.\n",
    sep = "\n")

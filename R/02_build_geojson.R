suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(stringr)
  library(rnaturalearth)
})

# Build the GeoJSON consumed by the Leaflet map:
#   data/built/incidents_iom.geojson
#
# Pipeline, in order:
#   1. Read the curated IOM CSV (data/raw/iom_europe.csv).
#   2. Drop the placeholder Mediterranean coordinate (33.0148, 12.549)
#      whenever it's paired with a country that doesn't sit on it; drop
#      lat == lon entries.
#   3. For every surviving row, check distance to its named Country of
#      Incident polygon. Rows farther than 500 km are tested for a
#      longitude sign-flip, lat-lon swap, or both; the variant is
#      accepted only if it lands within 200 km of the country polygon.
#      Rows where no transform recovers a sensible location are dropped.
#   4. Restrict to the four sea corridors that connect to Europe.
#   5. Aggregate rows that share (lat, lon, date) into one feature; the
#      vast majority of events come as a single row, but some arrive
#      split across multiple rows that we collapse.
#   6. Harmonise cause-of-death and region-of-origin into shorter macro
#      categories so the filter dropdowns stay scannable.
#   7. Write GeoJSON.

sf::sf_use_s2(FALSE)
dir.create("data/built", recursive = TRUE, showWarnings = FALSE)

SEA_ROUTES <- c(
  "Central Mediterranean",
  "Western Mediterranean",
  "Eastern Mediterranean",
  "Western Africa / Atlantic route to the Canary Islands",
  "Mainland Europe to the UK"
)


# ── English Channel sea-or-near-coast filter ──────────────────────────────
# IOM tags incidents on the "Mainland Europe to the UK" route by intent
# (people heading for the UK), regardless of cause. That bucket therefore
# contains lots of inland truck/motorway/asphyxiation deaths around Calais
# alongside the actual Channel boat-crossing drownings. Other corridors
# don't have that mix anywhere near as starkly. To keep the Channel route
# comparable with the four Mediterranean / Atlantic sea routes, we
# restrict its rows geographically: keep only points whose coordinates
# fall in the English Channel itself or within 5 km of the French or
# British coast inside the Channel area. Inland incidents (truck deaths
# on the A16, asphyxiations in containers parked far from the coast,
# etc.) are dropped. This is the only route-specific spatial filter in
# the pipeline; the four Mediterranean / Atlantic corridors keep all
# incidents IOM tagged for them.
CHANNEL_BOX <- c(xmin = -2.0, xmax = 2.0, ymin = 49.5, ymax = 51.7)

build_channel_envelope <- function() {
  fr_uk <- ne_countries(country = c("France", "United Kingdom"),
                        returnclass = "sf", scale = "medium")
  # Project to ETRS89 / LAEA Europe (metres) for accurate distance.
  fr_uk_m  <- sf::st_transform(fr_uk, 3035)
  box_sf   <- sf::st_as_sfc(sf::st_bbox(CHANNEL_BOX, crs = 4326)) |>
    sf::st_transform(3035)
  # Channel "sea" = bounding box minus the union of France + UK land.
  channel_sea <- sf::st_difference(box_sf, sf::st_union(fr_uk_m))
  channel_sea
}

# Returns TRUE if (lat, lon) falls inside the Channel sea polygon or
# within 5 km of either coastline (i.e. its planar distance to the sea
# polygon is <= 5 000 m).
in_channel_sea_or_near_coast <- function(lat, lon, channel_sea) {
  if (length(lat) == 0) return(logical(0))
  pts <- sf::st_as_sf(
    data.frame(lat = lat, lon = lon),
    coords = c("lon", "lat"), crs = 4326
  ) |> sf::st_transform(3035)
  d <- as.numeric(sf::st_distance(pts, channel_sea))
  !is.na(d) & d <= 5000
}


# ── Coordinate validation ──────────────────────────────────────────────────
# Country polygons (medium-scale) for the country-distance check.
COUNTRY_POLYS <- ne_countries(scale = "medium", returnclass = "sf") |>
  dplyr::select(name = name_long)

# Distance (km) from each (lat, lon) to its named country polygon.
# 0 = inside the polygon; otherwise km outside.
dist_to_country_km <- function(lat, lon, country_name) {
  out <- rep(NA_real_, length(lat))
  ok  <- !is.na(lat) & !is.na(lon) & !is.na(country_name) & country_name != ""
  if (!any(ok)) return(out)
  pts <- st_as_sf(
    data.frame(lat = lat[ok], lon = lon[ok]),
    coords = c("lon", "lat"), crs = 4326
  )
  for (cn in unique(country_name[ok])) {
    poly <- COUNTRY_POLYS[COUNTRY_POLYS$name == cn, ]
    if (nrow(poly) == 0) next
    sub        <- which(country_name == cn & ok)
    sub_in_pts <- match(sub, which(ok))
    out[sub]   <- as.numeric(st_distance(pts[sub_in_pts, ], poly)) / 1000
  }
  out
}

# Validate IOM coords against `Country of Incident`. Returns corrected
# lat/lon (NA on rows that should be dropped) plus a bookkeeping column
# saying which fix was applied.
validate_iom_coords <- function(lat, lon, country) {
  n   <- length(lat)
  fix <- rep("none", n)
  out_lat <- lat; out_lon <- lon

  # Drop the (33.0148, 12.549) Mediterranean placeholder anywhere it's
  # paired with a country that doesn't sit on it.
  is_ph <- abs(lat - 33.0148) < 0.001 & abs(lon - 12.549) < 0.001 &
           !country %in% c("Libya")
  fix[is_ph] <- "drop-placeholder"

  # Drop rows where lat == lon (data-entry error).
  is_eq <- !is_ph & abs(lat - lon) < 0.001
  fix[is_eq] <- "drop-lateqlon"

  # Country-distance check + auto-fix on the surviving rows.
  # 500 km tolerance is loose: legitimate sea deaths recorded 20-80
  # nautical miles offshore can land 300-450 km from a coastal country.
  # The 200 km accept threshold for the transforms is a tighter
  # "did this clearly fix it?" check.
  to_check <- which(fix == "none")
  d0       <- dist_to_country_km(lat[to_check], lon[to_check], country[to_check])
  bad      <- to_check[!is.na(d0) & d0 > 500]
  if (length(bad) > 0) {
    variants <- list(
      `lon-flip`     = list(lat = lat[bad],  lon = -lon[bad]),
      `lat-lon-swap` = list(lat = lon[bad],  lon =  lat[bad]),
      `swap+flip`    = list(lat = lon[bad],  lon = -lat[bad])
    )
    dists <- vapply(variants, function(v) {
      dist_to_country_km(v$lat, v$lon, country[bad])
    }, numeric(length(bad)))
    if (length(bad) == 1) dists <- matrix(dists, nrow = 1)

    for (i in seq_along(bad)) {
      j <- bad[i]
      v_dists <- dists[i, ]
      v_dists[is.na(v_dists)] <- Inf
      best <- which.min(v_dists)
      if (v_dists[best] < 200) {
        out_lat[j] <- variants[[best]]$lat[i]
        out_lon[j] <- variants[[best]]$lon[i]
        fix[j]     <- names(variants)[best]
      } else {
        fix[j] <- "drop-noFix"
      }
    }
  }

  data.frame(lat = out_lat, lon = out_lon, fix = fix,
             stringsAsFactors = FALSE)
}

# Numbers / Excel may export CSV with ';' (European locale) or ',' (US).
read_smart <- function(path) {
  l1    <- readLines(path, n = 1, warn = FALSE)
  delim <- if (grepl(";", l1)) ";" else ","
  read_delim(path, delim = delim, show_col_types = FALSE)
}

first_non_na <- function(x) {
  v <- na.omit(x)
  if (length(v) == 0) NA_character_ else as.character(v[1])
}

# ── Categorical harmonisation ─────────────────────────────────────────────
# Cause: keyword-collapse IOM's verbose `Cause of death (category)` labels
# into the six buckets the front-end filter exposes.
cause_macro_iom <- function(x) {
  v <- tolower(as.character(x))
  case_when(
    is.na(v)                                     ~ "other",
    str_detect(v, "drowning")                    ~ "drowning",
    str_detect(v, "violence")                    ~ "violence",
    str_detect(v, "vehicle|hazardous transport") ~ "vehicle",
    str_detect(v, "harsh")                       ~ "exposure",
    str_detect(v, "sickness|healthcare")         ~ "sickness",
    TRUE                                         ~ "other"   # mixed/unknown, accidental, …
  )
}

# Region of origin: case-insensitive lookup over the IOM `Region of Origin`
# field, accepting both regional groupings (with optional "(P)" suffix) and
# individual country names.
ORIGIN_LOOKUP <- list(
  sub_saharan_africa = c(
    "sub-saharan africa", "sub-saharan-africa", "subsaharan africa",
    "eastern africa", "western africa",
    "middle africa", "southern africa", "east africa", "west africa",
    "africa",
    # countries
    "eritrea", "somalia", "senegal", "sudan", "south sudan", "mali", "niger",
    "nigeria", "guinea", "guinea-bissau", "ivory coast", "côte d'ivoire",
    "ghana", "ethiopia", "congo", "drc", "zaire", "cameroon", "kamerun",
    "burkina faso", "gambia", "sierra leone", "liberia", "mauritania",
    "chad", "togo", "benin", "central african republic", "burundi", "rwanda",
    "uganda", "kenya", "tanzania", "zambia", "zimbabwe", "mozambique",
    "angola", "south africa", "cape verde", "cabo verde", "comoros",
    "madagascar", "somaliland"
  ),
  northern_africa = c(
    "northern africa", "north africa", "maghreb",
    "morocco", "algeria", "tunisia", "libya", "egypt", "western sahara"
  ),
  middle_east = c(
    "western asia", "middle east",
    "syria", "lebanon", "jordan", "jordania", "palestine", "iraq", "iran",
    "yemen", "saudi arabia", "israel", "turkey", "türkiye", "kuwait",
    "bahrain", "uae", "oman", "qatar", "armenia", "azerbaijan", "georgia",
    "kurdistan", "kurdistan-iraq", "kurdistan-turkey", "kurdistan-iran",
    "chechnya"
  ),
  south_central_asia = c(
    "southern asia",
    "afghanistan", "pakistan", "india", "bangladesh", "sri lanka",
    "nepal", "bhutan", "maldives",
    "kazakhstan", "uzbekistan", "turkmenistan", "kyrgyzstan", "tajikistan",
    "mongolia"
  ),
  europe = c(
    "europe",
    "albania", "bosnia", "kosovo", "kosovo-albania", "kosovo (roma)",
    "serbia", "north macedonia", "former yugoslavia", "croatia", "slovenia",
    "romania", "bulgaria", "moldova", "ukraine", "russia", "poland", "latvia",
    "belarus"
  )
)

origin_macro <- function(x) {
  if (length(x) == 0) return(character(0))
  v     <- tolower(trimws(as.character(x)))
  v     <- gsub("\\s*\\(p\\)\\s*", "", v)            # strip IOM's "(P)" suffix
  first <- trimws(sub(",.*$", "", v))                # take the first tag

  out <- rep("other", length(first))
  out[is.na(first) | first == "unknown" | first == ""] <- "unknown"
  for (macro in names(ORIGIN_LOOKUP)) {
    out[first %in% ORIGIN_LOOKUP[[macro]]] <- macro
  }
  out
}

# IOM's `Route` is already a clean human-readable label. Two adjustments
# for downstream consistency:
#   * NA / empty Route is mapped to "Other / unknown" so the field is
#     never null on the front-end.
#   * Comma-joined multi-route values (only 2 rows total) are split on the
#     first comma so the route field is single-valued.
clean_iom_route <- function(x) {
  v <- trimws(as.character(x))
  v <- ifelse(is.na(v) | v == "", "Other / unknown", v)
  trimws(sub(",.*$", "", v))
}


# ── Pipeline ────────────────────────────────────────────────────────────────

iom <- read_smart("data/raw/iom_europe.csv") |>
  mutate(
    date           = as.Date(incident_date_clean),
    year           = as.integer(format(date, "%Y")),
    n              = pmax(as.numeric(`No. dead/missing`), 0, na.rm = TRUE),
    lon            = as.numeric(Longitude),
    lat            = as.numeric(Latitude),
    location       = `Location of death`,
    country        = `Country of Incident`,
    region         = `Region of Incident`,
    route          = clean_iom_route(Route),
    cause          = `Cause of death (reported)`,
    cause_macro    = cause_macro_iom(`Cause of death (category)`),
    origin_macro   = origin_macro(`Region of Origin`),
    date_precision = as.character(incident_date_precision)
  ) |>
  filter(!is.na(lat), !is.na(lon), !is.na(date))

# Coord validation: fix sign-flips / swaps where possible, drop irrecoverable.
cat("\n--- IOM coord validation ---\n")
.fix          <- validate_iom_coords(iom$lat, iom$lon, iom$country)
iom$orig_lat  <- iom$lat   # bookkeeping for the diagnostic below
iom$orig_lon  <- iom$lon
iom$lat       <- .fix$lat
iom$lon       <- .fix$lon
iom$fix       <- .fix$fix
print(table(iom$fix))

cat("\nSample of rows dropped as 'drop-noFix' (head 8):\n")
iom |>
  filter(fix == "drop-noFix") |>
  mutate(loc = substr(location, 1, 60)) |>
  select(country, loc, orig_lat, orig_lon, route) |>
  head(8) |>
  as.data.frame() |>
  print()

iom <- iom |>
  filter(!grepl("^drop-", fix)) |>
  select(-fix, -orig_lat, -orig_lon) |>
  filter(route %in% SEA_ROUTES)

# Channel-specific spatial filter: drop "Mainland Europe to the UK" rows
# whose coordinates fall deep inland (truck/motorway/asphyxiation deaths
# that aren't part of a sea crossing).
cat("\n--- English Channel spatial filter ---\n")
channel_sea <- build_channel_envelope()
ec_idx <- which(iom$route == "Mainland Europe to the UK")
if (length(ec_idx) > 0) {
  keep <- in_channel_sea_or_near_coast(iom$lat[ec_idx],
                                       iom$lon[ec_idx],
                                       channel_sea)
  cat(sprintf("Mainland Europe to the UK: %d rows in scope -> %d kept (%d dropped as inland)\n",
              length(ec_idx), sum(keep), sum(!keep)))
  drop_idx <- ec_idx[!keep]
  iom <- iom[-drop_idx, ]
}

# Aggregate rows that share (lat, lon, date) into one feature.
iom_collapsed <- iom |>
  group_by(lon, lat, date) |>
  summarise(
    year           = first(year),
    n_dead         = sum(n, na.rm = TRUE),
    n_rows         = n(),
    location       = first_non_na(location),
    country        = first_non_na(country),
    region         = first_non_na(region),
    route          = first_non_na(route),
    cause          = first_non_na(cause),
    cause_macro    = first_non_na(cause_macro),
    origin_macro   = first_non_na(origin_macro),
    date_precision = first_non_na(date_precision),
    .groups        = "drop"
  ) |>
  mutate(date = as.character(date))

iom_sf <- st_as_sf(iom_collapsed, coords = c("lon", "lat"), crs = 4326)

st_write(iom_sf, "data/built/incidents_iom.geojson",
         driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
cat(sprintf("Wrote: data/built/incidents_iom.geojson    (%d features, %d raw rows, %d dead/missing)\n",
            nrow(iom_sf), nrow(iom), sum(iom_collapsed$n_dead)))


# ── Diagnostics ────────────────────────────────────────────────────────────
cat("\n--- cause_macro distribution ---\n")
print(iom_collapsed |> count(cause_macro) |> arrange(desc(n)))

cat("\n--- origin_macro distribution ---\n")
print(iom_collapsed |> count(origin_macro) |> arrange(desc(n)))

cat("\n--- route distribution ---\n")
print(iom_collapsed |> count(route) |> arrange(desc(n)))

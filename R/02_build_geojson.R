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

# IOM uses several country labels that don't match rnaturalearth's
# `name_long` field, so the polygon lookup silently fails (returning NA
# distance) and the row is never flagged. Aliases below map IOM's labels
# to the values found in `name_long`.
IOM_COUNTRY_ALIASES <- c(
  "Türkiye"                                              = "Turkey",
  "Iran (Islamic Republic of)"                           = "Iran",
  "Syrian Arab Republic"                                 = "Syria",
  "United Kingdom of Great Britain and Northern Ireland" = "United Kingdom",
  "Republic of Moldova"                                  = "Moldova",
  "Cabo Verde"                                           = "Republic of Cabo Verde"
)
# Normalize free-text country labels so the polygon lookup can find them:
# strip "Libya - presumed departure on ..." style suffixes, parenthetical
# clarifications like "Morocco (en route to Ceuta)", and apply the alias map.
normalize_iom_country <- function(x) {
  x <- as.character(x)
  x <- sub(" *-+ .*$", "", x)
  x <- sub(" *\\(.*\\)$", "", x)
  ifelse(!is.na(x) & x %in% names(IOM_COUNTRY_ALIASES),
         IOM_COUNTRY_ALIASES[x], x)
}

# Distance (km) from a single (lat, lon) to a single country polygon.
# 0 = inside the polygon; otherwise km outside; NA if the polygon isn't
# in COUNTRY_POLYS or any input is missing.
dist_to_country_km <- function(lat, lon, country_name) {
  if (is.na(lat) || is.na(lon) || is.na(country_name) || country_name == "")
    return(NA_real_)
  poly <- COUNTRY_POLYS[COUNTRY_POLYS$name == country_name, ]
  if (nrow(poly) == 0) return(NA_real_)
  pt <- st_as_sf(data.frame(lat = lat, lon = lon),
                 coords = c("lon", "lat"), crs = 4326)
  as.numeric(st_distance(pt, poly)) / 1000
}

# Tokens we look for in the free-text `Location of death`, mapped to one
# or more rnaturalearth polygons. Country names from rnaturalearth are
# always recognized; this list adds spelling variants, common island /
# territory names that pin down a country, and shared sea regions where
# a coordinate close to either coast is plausible.
LOCATION_TOKENS <- c(
  setNames(as.list(COUNTRY_POLYS$name), COUNTRY_POLYS$name),
  list(
    "Türkiye"          = "Turkey",
    "Turkiye"          = "Turkey",
    "UK"               = "United Kingdom",
    "Britain"          = "United Kingdom",
    "England"          = "United Kingdom",
    "Cape Verde"       = "Republic of Cabo Verde",
    "Cabo Verde"       = "Republic of Cabo Verde",
    "Lampedusa"        = "Italy",
    "Sicily"           = "Italy",
    "Sardinia"         = "Italy",
    "Sardegna"         = "Italy",
    "Pantelleria"      = "Italy",
    "Crete"            = "Greece",
    "Rhodes"           = "Greece",
    "Lesbos"           = "Greece",
    "Lesvos"           = "Greece",
    "Chios"            = "Greece",
    "Kos"              = "Greece",
    "Samos"            = "Greece",
    "Gavdos"           = "Greece",
    "Canary Islands"   = "Spain",
    "Balearic"         = "Spain",
    "Tenerife"         = "Spain",
    "Gran Canaria"     = "Spain",
    "El Hierro"        = "Spain",
    "Lanzarote"        = "Spain",
    "Fuerteventura"    = "Spain",
    "Ceuta"            = "Spain",
    "Melilla"          = "Spain",
    # Tokens that pin down two countries: a coord close to either coast
    # is plausible, so both are valid candidates for the distance check.
    "Gibraltar"        = c("United Kingdom", "Spain"),
    "English Channel"  = c("United Kingdom", "France"),
    "Channel Tunnel"   = c("United Kingdom", "France")
  )
)
# Longest tokens first so "United Kingdom" beats "Kingdom" / "United".
LOCATION_TOKENS <- LOCATION_TOKENS[order(-nchar(names(LOCATION_TOKENS)))]
LOCATION_REGEX  <- paste0("\\b(",
  paste(gsub("([][(){}.+*?^$|\\\\])", "\\\\\\1", names(LOCATION_TOKENS)),
        collapse = "|"),
  ")\\b")

# Each IOM route corridor naturally spans several country coastlines.
# A row tagged "Central Mediterranean" with country=Libya whose coord
# lands 100 km off Italy is legitimate — the coordinate is fine, the
# country tag is just misleading. We treat the route as a sea-region
# hint and check distance against any country the corridor touches.
ROUTE_COUNTRIES <- list(
  `Central Mediterranean` = c("Italy", "Libya", "Tunisia", "Malta"),
  `Eastern Mediterranean` = c("Greece", "Turkey", "Cyprus", "Egypt"),
  `Western Mediterranean` = c("Spain", "Morocco", "Algeria", "France"),
  `Western Africa / Atlantic route to the Canary Islands` =
    c("Spain", "Morocco", "Mauritania", "Senegal", "Western Sahara",
      "Republic of Cabo Verde", "Gambia"),
  `Mainland Europe to the UK` =
    c("United Kingdom", "France", "Belgium", "Netherlands")
)

# Per-route distance tolerance (km). The Western Africa / Atlantic
# corridor involves single crossings of 1000-1500 km between mainland
# West Africa and the Canary Islands; real shipwrecks routinely log
# 500-800 km from any single coast (texts often state the offset
# explicitly, e.g. "800 km southwest of Tenerife"). Everywhere else
# fits comfortably in 500 km.
ROUTE_TOLERANCE_KM <- c(
  `Western Africa / Atlantic route to the Canary Islands` = 1000
)
DEFAULT_TOLERANCE_KM <- 500

route_tolerance <- function(route) {
  if (!is.na(route) && route %in% names(ROUTE_TOLERANCE_KM)) {
    unname(ROUTE_TOLERANCE_KM[route])
  } else {
    DEFAULT_TOLERANCE_KM
  }
}

# Returns the unique set of rnaturalearth polygon names that the row
# points to: the IOM `Country of Incident`, every country named in the
# free-text location, and the typical countries of the IOM route. A row
# with vague text still falls back to country + route.
mentioned_polygons <- function(text, iom_country, route = NA_character_) {
  iom_country <- iom_country[!is.na(iom_country) & iom_country != ""]
  cns <- unique(iom_country)
  if (!is.na(route) && route %in% names(ROUTE_COUNTRIES)) {
    cns <- unique(c(cns, ROUTE_COUNTRIES[[route]]))
  }
  if (is.na(text) || text == "") return(cns)
  hits <- str_extract_all(text, regex(LOCATION_REGEX, ignore_case = TRUE))[[1]]
  if (length(hits) == 0) return(cns)
  lookup_lower <- setNames(LOCATION_TOKENS, tolower(names(LOCATION_TOKENS)))
  resolved     <- unlist(lookup_lower[tolower(hits)], use.names = FALSE)
  unique(c(cns, resolved[!is.na(resolved)]))
}

# Min distance (km) over all polygons the row points to. NA if none of
# the candidate polygons is in COUNTRY_POLYS.
min_dist_to_mentioned_km <- function(lat, lon, text, iom_country,
                                     route = NA_character_) {
  cns <- mentioned_polygons(text, iom_country, route)
  if (length(cns) == 0) return(NA_real_)
  ds <- vapply(cns, function(c) dist_to_country_km(lat, lon, c), numeric(1))
  ds <- ds[!is.na(ds)]
  if (length(ds) == 0) NA_real_ else min(ds)
}

# Validate IOM coords against the country/countries the row points to.
# Returns corrected lat/lon (NA on rows that should be dropped) plus a
# bookkeeping column saying which fix was applied. `country` should
# already be the rnaturalearth-aligned name (call normalize_iom_country()
# on it first).
#
# Decision rule: a row passes if its coordinates land within the route
# tolerance of *at least one* country the row points to — the IOM
# `Country of Incident`, every country named in the free-text location,
# and the typical countries of the IOM route. This handles cases like
# "Unspecified location between North Africa and Italy" with
# country=Libya (coord plausibly 100 km off Italy, 600 km off Libya),
# and Atlantic crossings recorded 700 km from any single coast.
#
# Rows farther than the tolerance from every candidate country are
# tested for a longitude sign-flip, lat-lon swap, or both; a transform
# is accepted if it lands within 200 km of any candidate country.
validate_iom_coords <- function(lat, lon, country, location, route) {
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

  for (j in which(fix == "none")) {
    cns <- mentioned_polygons(location[j], country[j], route[j])
    d0  <- min_dist_to_mentioned_km(lat[j], lon[j],
                                    location[j], country[j], route[j])
    tol <- route_tolerance(route[j])
    if (is.na(d0) || d0 <= tol) next  # ok, no fix needed

    variants <- list(
      `lon-flip`     = c(lat = lat[j],  lon = -lon[j]),
      `lat-lon-swap` = c(lat = lon[j],  lon =  lat[j]),
      `swap+flip`    = c(lat = lon[j],  lon = -lat[j])
    )
    v_dists <- vapply(variants, function(v) {
      ds <- vapply(cns, function(c) dist_to_country_km(v["lat"], v["lon"], c),
                   numeric(1))
      ds <- ds[!is.na(ds)]
      if (length(ds) == 0) Inf else min(ds)
    }, numeric(1))
    best <- which.min(v_dists)
    if (v_dists[best] < 200) {
      out_lat[j] <- variants[[best]]["lat"]
      out_lon[j] <- variants[[best]]["lon"]
      fix[j]     <- names(variants)[best]
    } else {
      fix[j] <- "drop-noFix"
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
# Country names are normalized to rnaturalearth's `name_long` only for the
# distance lookup; the original label is preserved in the output GeoJSON.
cat("\n--- IOM coord validation ---\n")
.country_norm <- normalize_iom_country(iom$country)
.fix          <- validate_iom_coords(iom$lat, iom$lon, .country_norm,
                                     iom$location, iom$route)
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

# Audit log: every row whose coordinates were touched — rescued, flagged,
# or excluded — is written to a side-by-side CSV so readers can audit
# which IOM rows we transformed, flagged on the map, or removed from it.
# `map_lat`/`map_lon` is the position the row gets on the rendered map
# (NA for excluded rows); `coord_status` is the user-facing label that
# matches the on-map dot's tooltip.
iom_audit <- iom |>
  filter(fix != "none") |>
  transmute(
    main_id        = `Main ID`,
    year           = year,
    date           = as.character(date),
    country        = country,
    route          = route,
    location       = location,
    orig_lat       = orig_lat,
    orig_lon       = orig_lon,
    map_lat        = ifelse(fix %in% c("drop-placeholder", "drop-lateqlon"),
                            NA_real_, lat),
    map_lon        = ifelse(fix %in% c("drop-placeholder", "drop-lateqlon"),
                            NA_real_, lon),
    n_dead_missing = n,
    fix_type       = fix,
    coord_status   = dplyr::case_when(
      fix == "drop-placeholder"                            ~ "excluded (placeholder coordinates)",
      fix == "drop-lateqlon"                               ~ "excluded (lat == lon, garbage)",
      fix == "drop-noFix"                                  ~ "flagged (shown at IOM's coordinates)",
      fix %in% c("lon-flip", "lat-lon-swap", "swap+flip") ~ "corrected (sign-flip or lat/lon swap)",
      TRUE                                                  ~ "ok"
    )
  ) |>
  arrange(fix_type, year, main_id)
write_csv(iom_audit, "data/built/coord_audit.csv")
cat("\nWrote data/built/coord_audit.csv (",
    nrow(iom_audit), "rows; ",
    sum(iom_audit$fix_type %in% c("drop-placeholder", "drop-lateqlon")), "excluded, ",
    sum(iom_audit$fix_type == "drop-noFix"), "flagged, ",
    sum(!grepl("^drop-", iom_audit$fix_type)), "corrected)\n")

# Translate the row-level fix code to a coord_status the front-end can use:
#   ok        — coordinates passed both checks unchanged
#   corrected — coordinates rescued by a sign-flip / lat-lon swap; the
#               row is shown at the corrected position, the original
#               (orig_lat, orig_lon) is kept in the tooltip for transparency
#   flagged   — country / route disagree with the coordinates and no
#               transform reconciles them; the row is shown at IOM's
#               original coordinates with a visible warning (rather than
#               silently dropped — readers see all the data, plus our note
#               that IOM's coords for this row don't match the location text)
# drop-placeholder (33.0148, 12.549 reused as "unknown") and drop-lateqlon
# (lat == lon, clearly garbage) are still excluded — those aren't real
# coordinates that can be honestly displayed anywhere.
iom <- iom |>
  mutate(
    coord_status = dplyr::case_when(
      fix == "none"                                       ~ "ok",
      fix %in% c("lon-flip", "lat-lon-swap", "swap+flip") ~ "corrected",
      fix == "drop-noFix"                                 ~ "flagged",
      TRUE                                                 ~ "drop"
    )
  ) |>
  filter(coord_status != "drop") |>
  filter(route %in% SEA_ROUTES) |>
  select(-fix)

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

# Aggregate rows that share (lat, lon, date) into one feature. coord_status
# uses the BEST signal in the group: if any underlying row independently
# confirms the coord (status "ok"), the feature is "ok" — a coord that
# matches even one row's country/text is geographically valid even if a
# duplicate row at the same point had a misleading country tag.
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
    coord_status   = if (any(coord_status == "ok"))            "ok"
                     else if (any(coord_status == "corrected")) "corrected"
                     else                                       "flagged",
    orig_lat       = first(orig_lat),
    orig_lon       = first(orig_lon),
    .groups        = "drop"
  ) |>
  mutate(
    date     = as.character(date),
    # Only carry orig coords when they actually differ — keeps the GeoJSON
    # smaller and the front-end logic simple (NA = nothing extra to show).
    orig_lat = ifelse(coord_status == "ok", NA_real_, orig_lat),
    orig_lon = ifelse(coord_status == "ok", NA_real_, orig_lon)
  )

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

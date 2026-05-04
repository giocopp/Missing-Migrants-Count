suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(lubridate)
  library(stringr)
  library(rnaturalearth)
})

# Build the two GeoJSON files consumed by the Leaflet map:
#   data/incidents_iom.geojson
#   data/incidents_united.geojson
#
# Both raw datasets reuse the same coordinates many times (one row per dead
# person rather than per event). We collapse each (latitude, longitude,
# date) triple into a single feature whose `n_dead` is the sum of the rows
# that share it -- so one bubble = one event.
#
# We also harmonise two categorical fields into shared macro categories so
# the IOM↔UNITED comparison stays apples-to-apples:
#   cause_macro  ∈ {drowning, vehicle, violence, exposure, sickness, other}
#   origin_macro ∈ {sub_saharan_africa, northern_africa, middle_east,
#                   south_central_asia, europe, other, unknown}

sf::sf_use_s2(FALSE)

# ── Coordinate validation ──────────────────────────────────────────────────
# Both source datasets contain a small number of rows where the recorded
# (lat, lon) is plainly wrong: a placeholder coord shared across unrelated
# countries, accidental lat=lon values, longitude sign flips on Mediterranean
# rows, or lat-lon swaps. We try a few cheap transforms before giving up:
#   - lon sign-flip   (e.g. Zuwara Libya recorded as -12.09 instead of +12.09)
#   - lat-lon swap    (e.g. Atbara Sudan recorded as 34, 17.7 instead of 17.7, 33.97)
#   - both combined
# If any variant brings the point within 200 km of the named country
# polygon, that variant is kept. Rows where no variant works are dropped.
COUNTRY_POLYS <- ne_countries(scale = "medium", returnclass = "sf") |>
  dplyr::select(name = name_long)

# Distance (km) from each (lat, lon) point to the named country polygon.
# Negative not used; 0 = inside the polygon, otherwise km outside.
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
    sub <- which(country_name == cn & ok)
    sub_in_pts <- match(sub, which(ok))
    out[sub] <- as.numeric(st_distance(pts[sub_in_pts, ], poly)) / 1000
  }
  out
}

# Validate IOM coords against `Country of Incident`. Returns a data frame
# with corrected lat/lon (NA for rows that should be dropped) plus a
# bookkeeping column telling us what fix was applied.
validate_iom_coords <- function(lat, lon, country) {
  n <- length(lat)
  fix <- rep("none", n)
  out_lat <- lat; out_lon <- lon

  # 1. Drop the (33.0148, 12.549) Mediterranean placeholder anywhere it is
  #    paired with a country that doesn't sit on it.
  is_ph <- abs(lat - 33.0148) < 0.001 & abs(lon - 12.549) < 0.001 &
           !country %in% c("Libya")
  fix[is_ph] <- "drop-placeholder"

  # 2. Drop rows where lat == lon (data entry error)
  is_eq <- !is_ph & abs(lat - lon) < 0.001
  fix[is_eq] <- "drop-lateqlon"

  # 3. For surviving rows, run the country-distance check + auto-fix.
  #    The 500 km tolerance is loose on purpose: many legitimate sea deaths
  #    are tagged with a coastal country (Libya, Malta, Tunisia) but recorded
  #    20-80 nautical miles offshore, which can put the point 300-450 km from
  #    the country polygon. We only flag rows farther than that, then try
  #    cheap transforms; we accept a transform only if it lands within 200 km
  #    of the country (a much tighter "did this clearly fix it?" check).
  to_check <- which(fix == "none")
  d0 <- dist_to_country_km(lat[to_check], lon[to_check], country[to_check])
  bad <- to_check[!is.na(d0) & d0 > 500]
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

# ── Harmonisation ──────────────────────────────────────────────────────────

cause_macro_iom <- function(x) {
  v <- tolower(as.character(x))
  case_when(
    is.na(v)                       ~ "other",
    str_detect(v, "drowning")      ~ "drowning",
    str_detect(v, "violence")      ~ "violence",
    str_detect(v, "vehicle|hazardous transport") ~ "vehicle",
    str_detect(v, "harsh")         ~ "exposure",
    str_detect(v, "sickness|healthcare") ~ "sickness",
    TRUE                           ~ "other"   # mixed/unknown, accidental, …
  )
}

cause_macro_united <- function(x) {
  v <- tolower(as.character(x))
  case_when(
    is.na(v)                                  ~ "other",
    v == "drowned"                            ~ "drowning",
    v == "car_accident"                       ~ "vehicle",
    v %in% c("murdered_hate_crime", "minefield",
             "arson_attack", "flee_fear_terrified") ~ "violence",
    v %in% c("starvation_dehydration_hypothermia",
             "frozen", "suffocated")          ~ "exposure",
    v %in% c("no_medical_treat", "poisoned")  ~ "sickness",
    TRUE                                      ~ "other"
  )
}

# Country / region → macro region. Lookup is case-insensitive and applies to
# both IOM `Region of Origin` (regional groupings, sometimes with "(P)"
# suffix) and UNITED `region_of_origin` (mix of country and region names).
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
  v <- tolower(trimws(as.character(x)))
  v <- gsub("\\s*\\(p\\)\\s*", "", v)            # strip IOM's "(P)" suffix
  first <- trimws(sub(",.*$", "", v))             # take the first tag

  out <- rep("other", length(first))
  out[is.na(first) | first == "unknown" | first == ""] <- "unknown"
  for (macro in names(ORIGIN_LOOKUP)) {
    out[first %in% ORIGIN_LOOKUP[[macro]]] <- macro
  }
  out
}

# UNITED stores migration corridors as semicolon-joined ISO-2 codes plus a
# few free-text pseudo-tokens ("Africa", "other-Europe", "other-unknown",
# "Asia Middle East"). Map each combination to the closest IOM `Route` label
# so the route filter has one shared vocabulary across both datasets. The
# coordinates are passed in to disambiguate the genuinely ambiguous "ES;Africa"
# bucket: lat<32 sits near the Canary Islands (Atlantic route), lat≥32 near
# the Strait of Gibraltar / Spanish coast (Western Mediterranean).
route_macro_united <- function(crossing, lat) {
  vapply(seq_along(crossing), function(i) {
    cc <- crossing[i]
    if (is.na(cc) || cc == "") return("Other / unknown")

    parts <- tolower(trimws(unlist(strsplit(cc, ";"))))
    has   <- function(codes) any(parts %in% tolower(codes))
    only  <- function(codes) all(parts %in% tolower(codes))

    # ── dedicated corridors ────────────────────────────────────────────────
    if (has("BY") && has(c("PL","LT","LV","EE")))         return("Belarus-EU border")
    if (has("UA") && has(c("PL","RO","HU","SK","MD")))    return("Ukraine to Europe")
    if (has("SY") && has("TR"))                            return("Syria to Türkiye")
    if (has("IR") && has("TR"))                            return("Iran to Türkiye")
    if (length(parts) == 2 && only(c("FR","IT")))          return("Italy to France")
    if (has(c("GB","IE")) && has(c("FR","BE","NL","DE")))  return("Mainland Europe to the UK")

    # ── Türkiye corridors ──────────────────────────────────────────────────
    # Greek/Cypriot waters with a Türkiye or generic "Asia Middle East" tag
    # is the Eastern Mediterranean sea route; TR with BG (no GR) is land.
    if (has(c("GR","CY")) && has(c("TR","asia middle east")))
      return("Eastern Mediterranean")
    if (has("TR") && has("BG"))                            return("Türkiye-Europe land route")
    if (has("TR") && has("asia middle east"))              return("Iran to Türkiye")

    # ── Western Balkans (transit through ex-Yugoslav space) ────────────────
    balkans <- c("AL","BA","BG","HR","ME","MK","RS","SI","XK","BH")
    if (has(balkans))                                      return("Western Balkans")
    if (has("AT") && has(c("HU","SK","SI","RO")))          return("Western Balkans")

    # ── Central Mediterranean (Italy/Malta + N African origin or generic) ──
    if (has(c("IT","MT")) && has(c("LY","TN","DZ","EG","africa")) && !has("ES"))
      return("Central Mediterranean")
    # LY/TN/EG → Europe with no destination tagged: still Central Med
    if (has(c("LY","TN","EG")) && has(c("other-europe","other-unknown")))
      return("Central Mediterranean")
    # Italy with only ambiguous tags → still Central Med (its dominant flow)
    if (has(c("IT","MT")) && has(c("other-europe","other-unknown")))
      return("Central Mediterranean")

    # ── Western Mediterranean vs. Atlantic to Canaries ─────────────────────
    if (has("ES")) {
      if (has(c("MA","DZ","TN")))                          return("Western Mediterranean")
      if (has(c("africa","other-europe","other-unknown"))) {
        if (!is.na(lat[i]) && lat[i] < 32)
          return("Western Africa / Atlantic route to the Canary Islands")
        return("Western Mediterranean")
      }
    }
    # DZ/MA → generic Europe = Western Med
    if (has(c("DZ","MA")) && has(c("other-europe","other-unknown")))
      return("Western Mediterranean")

    # ── Sahara: pure intra-African pairs ───────────────────────────────────
    african <- c("dz","ly","tn","eg","ma","ml","ne","td","sd","africa")
    if (length(parts) >= 1 && all(parts %in% african))     return("Sahara Desert crossing")

    # ── Single-country fall-throughs: pin to nearest Med basin ─────────────
    if (length(parts) == 1) {
      if (parts %in% c("it","mt"))                         return("Central Mediterranean")
      if (parts == "gr")                                   return("Eastern Mediterranean")
      if (parts == "es")                                   return("Western Mediterranean")
    }

    # Anything else (DE / FR / NL / CH / GB alone, generic Africa↔Europe, etc.)
    "Other / unknown"
  }, character(1))
}

# ---- IOM --------------------------------------------------------------------
# IOM `Route` is already a clean human-readable label, so this keeps it as-is.
# Two adjustments for consistency with UNITED's homogenised vocabulary:
#   * NA / empty Route is mapped to "Other / unknown" so the field is never null.
#   * Comma-joined multi-route values (only 2 rows total) are split on the
#     first comma so the route field is single-valued.
clean_iom_route <- function(x) {
  v <- trimws(as.character(x))
  v <- ifelse(is.na(v) | v == "", "Other / unknown", v)
  trimws(sub(",.*$", "", v))
}

iom <- read_smart("data/iom_europe.csv") |>
  mutate(
    date         = as.Date(incident_date_clean),
    year         = as.integer(format(date, "%Y")),
    n            = pmax(as.numeric(`No. dead/missing`), 0, na.rm = TRUE),
    lon          = as.numeric(Longitude),
    lat          = as.numeric(Latitude),
    location     = `Location of death`,
    country      = `Country of Incident`,
    region       = `Region of Incident`,
    route        = clean_iom_route(Route),
    cause        = `Cause of death (reported)`,
    cause_macro  = cause_macro_iom(`Cause of death (category)`),
    origin_macro = origin_macro(`Region of Origin`)
  ) |>
  filter(!is.na(lat), !is.na(lon), !is.na(date))

# Coord validation: fix sign-flips / swaps where possible, drop irrecoverable.
cat("\n--- IOM coord validation ---\n")
.fix <- validate_iom_coords(iom$lat, iom$lon, iom$country)
iom$orig_lat <- iom$lat   # bookkeeping for the diagnostic below
iom$orig_lon <- iom$lon
iom$lat      <- .fix$lat
iom$lon      <- .fix$lon
iom$fix      <- .fix$fix
print(table(iom$fix))

cat("\nSample of rows dropped as 'drop-noFix' (head 8):\n")
iom |>
  filter(fix == "drop-noFix") |>
  mutate(loc = substr(location, 1, 60)) |>
  select(country, loc, orig_lat, orig_lon, route) |>
  head(8) |>
  as.data.frame() |>
  print()

iom <- iom |> filter(!grepl("^drop-", fix)) |>
  select(-fix, -orig_lat, -orig_lon)

iom_collapsed <- iom |>
  group_by(lon, lat, date) |>
  summarise(
    year         = first(year),
    n_dead       = sum(n, na.rm = TRUE),
    n_rows       = n(),
    location     = first_non_na(location),
    country      = first_non_na(country),
    region       = first_non_na(region),
    route        = first_non_na(route),
    cause        = first_non_na(cause),
    cause_macro  = first_non_na(cause_macro),
    origin_macro = first_non_na(origin_macro),
    .groups      = "drop"
  ) |>
  mutate(date = as.character(date))

iom_sf <- st_as_sf(iom_collapsed, coords = c("lon", "lat"), crs = 4326)

st_write(iom_sf, "data/incidents_iom.geojson",
         driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
cat(sprintf("Wrote: data/incidents_iom.geojson    (%d features, %d raw rows, %d dead/missing)\n",
            nrow(iom_sf), nrow(iom), sum(iom_collapsed$n_dead)))

# ---- UNITED -----------------------------------------------------------------
united <- read_smart("data/united_europe.csv") |>
  mutate(
    date         = as.Date(incident_date_clean),
    year         = as.integer(format(date, "%Y")),
    n            = pmax(as.numeric(n_deaths), 0, na.rm = TRUE),
    lon          = as.numeric(longitude),
    lat          = as.numeric(latitude),
    location     = place_of_death,
    country      = country_of_death,
    cause        = cause_of_death_text,
    manner       = manner_of_death,
    crossing     = crossing_countries,
    route        = route_macro_united(crossing_countries, as.numeric(latitude)),
    cause_macro  = cause_macro_united(manner_of_death),
    origin_macro = origin_macro(region_of_origin)
  ) |>
  filter(!is.na(lat), !is.na(lon), !is.na(date)) |>
  # Drop the small handful of UNITED rows where lat == lon (data-entry error,
  # e.g. "13.10203, 13.10203" tagged as off-Tripoli). country_of_death is
  # often a label rather than a geographic country in UNITED, so we don't
  # try the heavier polygon-based auto-fix here.
  filter(abs(lat - lon) > 0.001)

united_collapsed <- united |>
  group_by(lon, lat, date) |>
  summarise(
    year         = first(year),
    n_dead       = sum(n, na.rm = TRUE),
    n_rows       = n(),
    location     = first_non_na(location),
    country      = first_non_na(country),
    cause        = first_non_na(cause),
    manner       = first_non_na(manner),
    crossing     = first_non_na(crossing),     # raw country-code pair, kept for tooltips
    route        = first_non_na(route),        # homogenised IOM-style label
    cause_macro  = first_non_na(cause_macro),
    origin_macro = first_non_na(origin_macro),
    .groups      = "drop"
  ) |>
  mutate(date = as.character(date))

united_sf <- st_as_sf(united_collapsed, coords = c("lon", "lat"), crs = 4326)

st_write(united_sf, "data/incidents_united.geojson",
         driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
cat(sprintf("Wrote: data/incidents_united.geojson (%d features, %d raw rows, %d deaths)\n",
            nrow(united_sf), nrow(united), sum(united_collapsed$n_dead)))

# ---- Diagnostics ------------------------------------------------------------
cat("\n--- cause_macro distribution ---\n")
print(bind_rows(
  iom_collapsed    %>% count(cause_macro) %>% mutate(source = "IOM"),
  united_collapsed %>% count(cause_macro) %>% mutate(source = "UNITED")
) %>% tidyr::pivot_wider(names_from = source, values_from = n, values_fill = 0L))

cat("\n--- origin_macro distribution ---\n")
print(bind_rows(
  iom_collapsed    %>% count(origin_macro) %>% mutate(source = "IOM"),
  united_collapsed %>% count(origin_macro) %>% mutate(source = "UNITED")
) %>% tidyr::pivot_wider(names_from = source, values_from = n, values_fill = 0L))

# Surface raw region_of_origin values that fell through to "other" so we can
# extend the lookup if they're a non-trivial bucket.
cat("\n--- top UNITED region_of_origin values that mapped to 'other' ---\n")
united |>
  filter(origin_macro == "other") |>
  count(region_of_origin, sort = TRUE) |>
  head(15) |>
  print()

# Distribution of homogenised routes — sanity-check against IOM's vocabulary.
cat("\n--- route distribution ---\n")
print(bind_rows(
  iom_collapsed    %>% count(route) %>% mutate(source = "IOM"),
  united_collapsed %>% count(route) %>% mutate(source = "UNITED")
) %>%
  tidyr::pivot_wider(names_from = source, values_from = n, values_fill = 0L) %>%
  arrange(desc(IOM + UNITED)),
  n = 50)

# Surface UNITED crossings that ended up in 'Other / unknown' so we can
# extend route_macro_united() for the next high-volume bucket.
cat("\n--- top UNITED crossings → 'Other / unknown' ---\n")
united_collapsed |>
  filter(route == "Other / unknown") |>
  count(crossing, sort = TRUE) |>
  head(20) |>
  print()

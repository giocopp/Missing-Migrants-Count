suppressPackageStartupMessages({
  library(jsonlite)
  library(tibble)
})

# ============================================================
# Static reference data for the interactive map.
#
# Authored in R; emitted as a single JSON file that the front-end
# fetches at page load. Sole runtime artifact: data/built/routes.json
#
# Edit the data structures in THIS file (palette, hubs, polylines)
# and run `make routes` (or `Rscript R/03_build_routes.R`) to
# regenerate the JSON.
# ============================================================

dir.create("data/built", recursive = TRUE, showWarnings = FALSE)

# ── Migration-corridor palette ──────────────────────────────
# Death dots inherit colour from the sea corridor they belong to (only
# the four sea-route values appear in the IOM data); overlaid polylines
# additionally cover the East Africa and Other land corridors as
# geographic context.
ROUTE_COLORS <- c(
  "Western Africa / Atlantic route to the Canary Islands" = "#7E3FAF",
  "Western Mediterranean"                                 = "#E97A2E",
  "Central Mediterranean"                                 = "#2B7CC9",
  "Eastern Mediterranean"                                 = "#3FA64A",
  "Mainland Europe to the UK"                             = "#C13838",
  "Other"                                                 = "#8C8C8C"
)

ROUTE_SHORT_LABELS <- c(
  "Western Africa / Atlantic route to the Canary Islands" = "West Africa",
  "Western Mediterranean"                                 = "Western Mediterranean",
  "Central Mediterranean"                                 = "Central Mediterranean",
  "Eastern Mediterranean"                                 = "Eastern Mediterranean",
  "Mainland Europe to the UK"                             = "English Channel",
  "Other"                                                 = "Other"
)

# ── Tooltip labels ──────────────────────────────────────────
# Cause / region-of-origin codes → display labels. PRECISION_FLAGS map
# the IOM date-precision codes onto the "Date approximate — …" caveat
# that surfaces in the tooltip.
CAUSE_LABELS <- c(
  drowning = "Drowning",
  vehicle  = "Vehicle / transport",
  violence = "Violence",
  exposure = "Exposure / cold / starvation",
  sickness = "Sickness",
  other    = "Other / unknown"
)

ORIGIN_LABELS <- c(
  sub_saharan_africa = "Sub-Saharan Africa",
  northern_africa    = "Northern Africa",
  middle_east        = "Middle East / Levant",
  south_central_asia = "South / Central Asia",
  europe             = "Europe",
  other              = "Other",
  unknown            = "Unknown"
)

PRECISION_FLAGS <- c(
  month     = "Date approximate — month only",
  year_only = "Date approximate — year only",
  imprecise = "Date approximate — exact day unknown"
)

# ── Main migration hubs (open circles on the map) ───────────
# The set mirrors the open-circle hubs in the reference figure
# (border-crossing nodes and big sending/receiving cities), not every
# black-dot route city. `dir` controls which side of the marker the
# permanent label sits so close pairs don't collide.
HUBS <- tibble::tribble(
  ~name,           ~lat,     ~lon,    ~dir,
  "Istanbul",      41.0082,  28.9784, "right",
  "Cairo",         30.0444,  31.2357, "right",
  "Addis Ababa",    9.0250,  38.7470, "right",
  "Nairobi",       -1.2921,  36.8219, "right",
  "Khartoum",      15.5007,  32.5599, "right",
  "Tripoli",       32.8872,  13.1913, "top",
  "Sebha",         27.0377,  14.4283, "right",
  "Agadez",        16.9740,   7.9883, "right",
  "Tamanrasset",   22.7850,   5.5228, "left",
  "Ouargla",       31.9489,   5.3231, "right",
  "Maghnia",       34.8633,  -1.7400, "right",
  "Oujda",         34.6810,  -1.9080, "left"
)

# ── Sea-route arrival points (filled black dots with italic labels)
# These are *destinations* — small islands or coastal cities the
# CartoDB Positron basemap doesn't label at default zoom.
CITIES <- tibble::tribble(
  ~name,             ~lat,     ~lon,    ~dir,
  "Lampedusa",       35.5119,  12.6033, "right",
  "Lesbos",          39.1100,  26.5550, "right",
  "Canary Islands",  28.1235, -15.4363, "right",
  "Almería",         36.8381,  -2.4597, "left"
)

# ── Route polylines ─────────────────────────────────────────
# Each line: route name (must match a key in ROUTE_COLORS), `major`
# flag (TRUE → thick, FALSE → thin "connecting" line), and an ordered
# list of [lat, lon] waypoints. Geometry is approximate; the polylines
# bend through real transit cities so they read as actual flow paths
# rather than great-circle straight lines.
#
# Short corridor aliases to keep the list readable:
W  <- "Western Africa / Atlantic route to the Canary Islands"
WM <- "Western Mediterranean"
CM <- "Central Mediterranean"
EM <- "Eastern Mediterranean"
EC <- "Mainland Europe to the UK"   # English Channel — red sea corridor
OT <- "Other"
# Backwards-compat alias: the previous "East Africa" red corridor's
# polylines were re-tagged "Other" (grey) when the English Channel
# took the red slot. Keep the alias so existing line() calls below
# still resolve until they're rewritten.
EA <- OT

# Tiny constructor so each line is one expression.
line <- function(route, major, ...) {
  list(route = route, major = major, coords = list(...))
}

ROUTE_LINES <- list(

  # ── WEST AFRICA (purple) ─────────────────────────────────
  # Atlantic crossing — Senegal/Mauritania coast → out into Atlantic →
  # Canary Islands (the long offshore curve).
  line(W, FALSE,
       c(14.6928, -17.4467),    # Dakar
       c(18.0735, -15.9582),    # Nouakchott
       c(20.9410, -17.0379),    # Nouadhibou
       c(23.6900, -17.5000),    # offshore Dakhla
       c(26.5000, -17.8000),    # mid-Atlantic curve
       c(28.1235, -15.4363)),   # Las Palmas (Canary Islands)
  # Coastal land route — Senegal → Mauritania → W. Sahara → Morocco
  line(W, FALSE,
       c(14.6928, -17.4467),    # Dakar
       c(18.0735, -15.9582),    # Nouakchott
       c(20.9410, -17.0379),    # Nouadhibou
       c(23.6848, -15.9579),    # Dakhla
       c(27.1536, -13.2033),    # Layoune
       c(28.4380, -11.1030),    # Tan-Tan
       c(30.4202,  -9.5982)),   # Agadir
  # Inland Sahel feeder — Banjul → Bamako → Ouagadougou → Niamey
  line(W, FALSE,
       c(13.4549, -16.5790),    # Banjul
       c(12.6392,  -8.0029),    # Bamako
       c(12.3714,  -1.5197),    # Ouagadougou
       c(13.5117,   2.1098)),   # Niamey
  # West African coast — Bissau → Conakry → Freetown → Monrovia
  line(W, FALSE,
       c(11.8636, -15.5977),    # Bissau
       c( 9.5092, -13.7122),    # Conakry
       c( 8.4844, -13.2344),    # Freetown
       c( 6.3007, -10.7969)),   # Monrovia
  # Saharan crossover — Bamako → Mopti → Gao
  line(W, FALSE,
       c(12.6392, -8.0029),     # Bamako
       c(14.4843, -4.1956),     # Mopti
       c(16.2735, -0.0445)),    # Gao
  # Atlantic short hop — open ocean feeder onto the Canary arc
  line(W, FALSE,
       c(16.7700, -22.9000),
       c(22.0000, -20.5000),
       c(26.0000, -17.5000)),

  # ── WESTERN MEDITERRANEAN (orange) ───────────────────────
  # MAJOR — Agadez → Tamanrasset → Ouargla → Maghnia (trans-Sahara spine).
  line(WM, TRUE,
       c(16.9740,  7.9883),     # Agadez
       c(19.5000,  6.5000),     # mid-Sahara
       c(22.7850,  5.5228),     # Tamanrasset
       c(27.8743,  5.7000),     # mid-Sahara
       c(31.9489,  5.3231),     # Ouargla
       c(34.8633, -1.7400)),    # Maghnia
  # MAJOR — Guinea-Bissau → Mali (Bamako–Mopti–Gao) → Tamanrasset
  # (the West-African Sahel feeder, joining the spine at Tamanrasset).
  line(WM, TRUE,
       c(11.8636, -15.5977),    # Bissau
       c(12.6392,  -8.0029),    # Bamako
       c(14.4843,  -4.1956),    # Mopti
       c(16.2735,  -0.0445),    # Gao
       c(22.7850,   5.5228)),   # Tamanrasset
  # Sea crossing west — Maghnia → Oujda → Tangier → Algeciras
  line(WM, FALSE,
       c(34.8633, -1.7400),     # Maghnia
       c(34.6810, -1.9080),     # Oujda
       c(35.7595, -5.8340),     # Tangier
       c(36.1408, -5.4561)),    # Algeciras (Spain)
  # Sea crossing east — Oran → Almería → Madrid
  line(WM, FALSE,
       c(35.6976, -0.6337),     # Oran
       c(36.8381, -2.4597),     # Almería
       c(40.4168, -3.7038)),    # Madrid
  # Algerian coastal — Algiers → Oran → Maghnia
  line(WM, FALSE,
       c(36.7538,  3.0588),     # Algiers
       c(35.6976, -0.6337),     # Oran
       c(34.8633, -1.7400)),    # Maghnia
  # Algiers approach — Tamanrasset → Algiers (alt western branch)
  line(WM, FALSE,
       c(22.7850,  5.5228),     # Tamanrasset
       c(29.0500,  3.9000),     # Sahara
       c(32.7700,  3.3000),     # Laghouat area
       c(36.7538,  3.0588)),    # Algiers
  # Coastal Morocco — Nouakchott → W. Sahara → Morocco coast → Tangier.
  line(WM, FALSE,
       c(18.0735, -15.9582),    # Nouakchott
       c(23.6848, -15.9579),    # Dakhla
       c(27.1536, -13.2033),    # Laâyoune
       c(30.4202,  -9.5982),    # Agadir
       c(33.5731,  -7.5898),    # Casablanca
       c(35.7595,  -5.8340)),   # Tangier
  # Tamanrasset → Oujda direct (alt trans-Sahara branch).
  line(WM, FALSE,
       c(22.7850,  5.5228),     # Tamanrasset
       c(28.0000,  1.0000),     # mid-Sahara
       c(31.0000, -2.0000),     # eastern Algeria / Morocco border
       c(34.6810, -1.9080)),    # Oujda
  # Mali → Oujda direct (Sahel feeder skipping Tamanrasset).
  line(WM, FALSE,
       c(12.6392, -8.0029),     # Bamako
       c(20.0000, -8.0500),     # mid-Sahara
       c(27.6700, -8.1300),     # Tindouf area
       c(34.6810, -1.9080)),    # Oujda
  # Somalia → Sebha → Tamanrasset → Ouargla (minor Horn-of-Africa feeder
  # into the Western-Med spine).
  line(WM, FALSE,
       c( 2.0469, 45.3182),     # Mogadishu
       c( 9.0250, 38.7470),     # Addis Ababa
       c(15.5007, 32.5599),     # Khartoum
       c(27.0377, 14.4283),     # Sebha
       c(22.7850,  5.5228),     # Tamanrasset
       c(31.9489,  5.3231)),    # Ouargla

  # ── CENTRAL MEDITERRANEAN (blue) ─────────────────────────
  # Trans-Sahara MAJOR — Agadez → Dirkou → Al Qatrun → Sebha → Tripoli.
  line(CM, TRUE,
       c(16.9740,  7.9883),     # Agadez
       c(18.9684, 12.9293),     # Dirkou
       c(22.0000, 14.0000),     # Sahara waypoint
       c(24.9381, 14.6489),     # Al Qatrun
       c(27.0377, 14.4283),     # Sebha
       c(30.5000, 13.7000),     # central Libyan desert
       c(32.8872, 13.1913)),    # Tripoli
  # MAJOR — Tripoli → Tunis (coastal, west along the N. African shore).
  line(CM, TRUE,
       c(32.8872, 13.1913),     # Tripoli
       c(32.9300, 12.0800),     # Zuwara
       c(33.1417, 11.2167),     # Ben Gardane (Tunisia)
       c(33.8869,  9.5375),     # Sfax
       c(35.8333, 10.6383),     # Sousse
       c(36.8065, 10.1815)),    # Tunis
  # MAJOR — Tamanrasset → Ouargla → Tripoli (alt trans-Sahara via Algeria).
  line(CM, TRUE,
       c(22.7850,  5.5228),     # Tamanrasset
       c(31.9489,  5.3231),     # Ouargla
       c(30.1346,  9.5008),     # Ghadames
       c(32.8872, 13.1913)),    # Tripoli
  # MAJOR — Addis Ababa → Khartoum → Sebha → Tripoli. Follows the EA
  # red major path; goes straight through Khartoum-Sebha (matching the
  # orange Somalia-line geometry) and is jittered ~33 km south so both
  # colours stay visible where the corridors overlap.
  line(CM, TRUE,
       c( 8.7250, 38.7470),     # Addis Ababa
       c(15.2007, 32.5599),     # Khartoum
       c(26.7377, 14.4283),     # Sebha
       c(32.5872, 13.1913)),    # Tripoli
  # MAJOR — Cairo → Salloum → Tobruk → Benghazi → Tripoli. Follows the
  # EA red Cairo → Tripoli coastal path; same ~33 km southward jitter
  # so the red and blue stay distinguishable.
  line(CM, TRUE,
       c(29.7444, 31.2357),     # Cairo
       c(31.2500, 25.1500),     # Salloum
       c(31.7826, 23.9763),     # Tobruk
       c(31.8167, 20.0667),     # Benghazi
       c(32.5872, 13.1913)),    # Tripoli
  # Sea crossing — Tripoli → Lampedusa → Catania (minor).
  line(CM, FALSE,
       c(32.8872, 13.1913),     # Tripoli
       c(34.5000, 12.8000),
       c(35.5119, 12.6033),     # Lampedusa
       c(37.0759, 14.7300),     # Pozzallo
       c(37.5079, 15.0830)),    # Catania
  # Tunisian sea — Sfax → Tunis → Lampedusa (minor).
  line(CM, FALSE,
       c(33.8869,  9.5375),     # Sfax area
       c(36.8065, 10.1815),     # Tunis
       c(35.5119, 12.6033)),    # Lampedusa
  # Malta crossing (minor).
  line(CM, FALSE,
       c(32.8872, 13.1913),     # Tripoli
       c(35.9000, 14.5100)),    # Malta
  # Alternate trans-Sahara — Agadez → Tamanrasset → Sebha (minor variant).
  # Path mirrors the orange Somalia line's Tamanrasset → Sebha edge,
  # with a small ~22 km north jitter so the two colours stay readable.
  line(CM, FALSE,
       c(16.9740,  7.9883),     # Agadez
       c(22.9850,  5.5228),     # Tamanrasset (jittered north)
       c(27.2377, 14.4283)),    # Sebha (jittered north)
  # Tunisian alt — Tamanrasset → Ghadames → Tripoli (minor).
  line(CM, FALSE,
       c(22.7850,  5.5228),     # Tamanrasset
       c(27.0000,  8.5000),     # mid-Sahara
       c(30.1346,  9.5008),     # Ghadames
       c(32.8872, 13.1913)),    # Tripoli
  # Nigeria → Agadez (minor) — Lagos → Abuja → Maradi → Agadez (skips
  # Niamey, which is already on the Burkina Faso → Agadez line, to avoid
  # drawing two parallel blue Niamey-Agadez segments).
  line(CM, FALSE,
       c( 6.5244,  3.3792),     # Lagos
       c( 9.0820,  7.4000),     # Abuja
       c(13.4880,  7.0980),     # Maradi (Niger)
       c(16.9740,  7.9883)),    # Agadez
  # Burkina Faso → Agadez (minor) — Ouagadougou → Niamey → Tahoua → Agadez.
  line(CM, FALSE,
       c(12.3714, -1.5197),     # Ouagadougou
       c(13.5117,  2.1098),     # Niamey
       c(14.8888,  5.2693),     # Tahoua  (DTM admin-1 IDP cluster)
       c(16.9740,  7.9883)),    # Agadez
  # Cameroon → Agadez (minor) — Yaoundé → N'Djamena → Zinder → Agadez.
  line(CM, FALSE,
       c( 3.8480, 11.5021),     # Yaoundé
       c(12.1348, 15.0557),     # N'Djamena
       c(13.8062,  8.9881),     # Zinder
       c(16.9740,  7.9883)),    # Agadez
  # Chad → Sebha (minor) — N'Djamena → Faya-Largeau → Sebha.
  line(CM, FALSE,
       c(12.1348, 15.0557),     # N'Djamena
       c(17.9235, 19.1207),     # Faya-Largeau
       c(27.0377, 14.4283)),    # Sebha
  # East Libya → Benghazi (minor) — Salloum → Tobruk → Benghazi (coastal).
  line(CM, FALSE,
       c(31.5500, 25.1500),     # Salloum (Egypt-Libya border)
       c(32.0826, 23.9763),     # Tobruk
       c(32.1167, 20.0667)),    # Benghazi
  # Burkina Faso → Tamanrasset (minor) — Ouagadougou → Gao → Tamanrasset.
  line(CM, FALSE,
       c(12.3714, -1.5197),     # Ouagadougou
       c(16.2735, -0.0445),     # Gao
       c(22.7850,  5.5228)),    # Tamanrasset
  # Ouargla → Algerian coast (minor) — Ouargla → Algiers.
  line(CM, FALSE,
       c(31.9489,  5.3231),     # Ouargla
       c(34.0000,  4.0000),     # central Algeria
       c(36.7538,  3.0588)),    # Algiers (Mediterranean coast)

  # ── EASTERN MEDITERRANEAN (green) ────────────────────────
  # Asia approach — Tehran → eastern Turkey → Ankara → Istanbul
  line(EM, TRUE,
       c(35.6892, 51.3890),     # Tehran
       c(38.5012, 43.3729),     # Van
       c(39.9208, 41.2769),     # Erzurum
       c(39.9334, 32.8597),     # Ankara
       c(41.0082, 28.9784)),    # Istanbul
  # Iraq approach — Baghdad → Mosul → eastern Turkey → Istanbul
  line(EM, TRUE,
       c(33.3152, 44.3661),     # Baghdad
       c(36.3450, 43.1450),     # Mosul
       c(37.9145, 40.2306),     # Diyarbakır
       c(37.0662, 37.3833),     # Gaziantep
       c(39.9334, 32.8597),     # Ankara
       c(41.0082, 28.9784)),    # Istanbul
  # Levantine — Damascus → Aleppo → Gaziantep → Istanbul
  line(EM, TRUE,
       c(33.5138, 36.2765),     # Damascus
       c(36.2021, 37.1343),     # Aleppo
       c(37.0662, 37.3833),     # Gaziantep
       c(41.0082, 28.9784)),    # Istanbul
  # Aegean sea crossings — Istanbul → Izmir → Lesbos
  line(EM, TRUE,
       c(41.0082, 28.9784),     # Istanbul
       c(39.6500, 27.8800),     # Ayvalık area
       c(38.4192, 27.1287),     # Izmir
       c(39.1100, 26.5550)),    # Lesbos
  # Aegean sea crossings — Izmir → Samos → Kos
  line(EM, TRUE,
       c(38.4192, 27.1287),     # Izmir
       c(37.7900, 26.9700),     # Samos
       c(36.8920, 27.2900)),    # Kos
  # Balkans — Istanbul → Edirne → Sofia → Belgrade
  line(EM, TRUE,
       c(41.0082, 28.9784),     # Istanbul
       c(41.6770, 26.5557),     # Edirne
       c(42.6977, 23.3219),     # Sofia
       c(44.7866, 20.4489)),    # Belgrade
  # Cyprus arc — Beirut → Cyprus → mainland Greece
  line(EM, FALSE,
       c(33.8938, 35.5018),     # Beirut
       c(35.1264, 33.4299),     # Nicosia
       c(37.9838, 23.7275)),    # Athens
  # Eilat → Benghazi (minor) — coastal route along Sinai → Egypt's
  # Mediterranean shore → Salloum → Tobruk → Benghazi.
  line(EM, FALSE,
       c(29.5577, 34.9519),     # Eilat
       c(30.0444, 31.2357),     # Cairo
       c(31.5500, 25.1500),     # Salloum
       c(32.0826, 23.9763),     # Tobruk
       c(32.1167, 20.0667)),    # Benghazi
  # Greece → Western Balkans (minor) — Athens → Skopje → Belgrade → Zagreb.
  line(EM, FALSE,
       c(37.9838, 23.7275),     # Athens
       c(41.9981, 21.4254),     # Skopje
       c(44.7866, 20.4489),     # Belgrade
       c(45.8150, 15.9819)),    # Zagreb

  # ── EAST AFRICA (red) — Horn of Africa, trans-Sudan, Red Sea
  # MAJOR — Addis Ababa → Khartoum → Sebha → Tripoli (the dominant
  # East-Africa flow toward the Mediterranean; the onward Tripoli →
  # Tunis coastal segment is carried by the CMR blue route). The
  # Khartoum-Sebha edge goes straight, matching the orange Somalia
  # line's geometry — the CMR blue parallel above is jittered south.
  line(EA, TRUE,
       c( 9.0250, 38.7470),     # Addis Ababa
       c(15.5007, 32.5599),     # Khartoum
       c(27.0377, 14.4283),     # Sebha
       c(32.8872, 13.1913)),    # Tripoli
  # MAJOR — Cairo → Salloum → Tobruk → Benghazi → Tripoli (coastal
  # North-African EA route).
  line(EA, TRUE,
       c(30.0444, 31.2357),     # Cairo
       c(31.5500, 25.1500),     # Salloum
       c(32.0826, 23.9763),     # Tobruk
       c(32.1167, 20.0667),     # Benghazi
       c(32.8872, 13.1913)),    # Tripoli

  # All routes below are minor.
  # East African feeder — Nairobi → Addis Ababa
  line(EA, FALSE,
       c(-1.2921, 36.8219),     # Nairobi
       c( 4.0500, 38.5000),     # northern Kenya
       c( 9.0250, 38.7470)),    # Addis Ababa
  # Nile Valley connector — Addis Ababa → Khartoum → Aswan → Cairo
  line(EA, FALSE,
       c( 9.0250, 38.7470),     # Addis Ababa
       c(15.4540, 36.4000),     # Kassala
       c(15.5007, 32.5599),     # Khartoum
       c(21.8000, 31.3400),     # Wadi Halfa
       c(24.0889, 32.8998),     # Aswan
       c(30.0444, 31.2357)),    # Cairo
  # Sinai exit — Cairo → Suez → Sinai → Israel border
  line(EA, FALSE,
       c(30.0444, 31.2357),     # Cairo
       c(29.9700, 32.5300),     # Suez
       c(29.5577, 34.9519),     # Eilat / Sinai border
       c(31.0461, 34.8516)),    # southern Israel
  # Arabian Peninsula → Israel — Mecca → Medina → Tabuk → Aqaba → Eilat
  line(EA, FALSE,
       c(21.3891, 39.8579),     # Mecca
       c(24.4709, 39.6111),     # Medina
       c(28.3835, 36.5662),     # Tabuk
       c(29.5320, 35.0080),     # Aqaba
       c(29.5577, 34.9519),     # Eilat
       c(31.7683, 35.2137)),    # Jerusalem area
  # Horn → Yemen — Addis Ababa → Djibouti → Aden → Sanaa
  line(EA, FALSE,
       c( 9.0250, 38.7470),     # Addis Ababa
       c(11.5886, 43.1453),     # Djibouti
       c(12.7800, 45.0367),     # Aden
       c(15.3694, 44.1910)),    # Sanaa
  # Yemen → Saudi Arabia — Sanaa → Mecca → Riyadh
  line(EA, FALSE,
       c(15.3694, 44.1910),     # Sanaa
       c(21.3891, 39.8579),     # Mecca
       c(24.7136, 46.6753)),    # Riyadh
  # Eritrea connector — Asmara → Kassala → Khartoum
  line(EA, FALSE,
       c(15.3229, 38.9251),     # Asmara
       c(15.4540, 36.4000),     # Kassala
       c(15.5007, 32.5599)),    # Khartoum
  # Somalia → Addis Ababa — Mogadishu → Hargeisa → Dire Dawa → Addis Ababa
  line(EA, FALSE,
       c( 2.0469, 45.3182),     # Mogadishu
       c( 5.5000, 44.0000),     # central Somalia
       c( 9.5611, 44.0680),     # Hargeisa
       c( 9.5907, 41.8662),     # Dire Dawa
       c( 9.0250, 38.7470)),    # Addis Ababa

  # ── ENGLISH CHANNEL (red) — Mainland Europe to the UK ───
  # MAJOR — Calais → London. The cross-Channel small-boat route, IOM's
  # "Mainland Europe to the UK" corridor.
  line(EC, TRUE,
       c(50.9513,  1.8587),     # Calais
       c(51.5074, -0.1278)),    # London

  # ── OTHER (grey) — European corridors that don't terminate at a
  # Mediterranean sea crossing. All grey routes are minor.
  # Eastern Europe → West — Moscow → Minsk → Warsaw → Berlin
  line(OT, FALSE,
       c(55.7558, 37.6173),     # Moscow
       c(53.9000, 27.5667),     # Minsk
       c(52.2297, 21.0122),     # Warsaw
       c(52.5200, 13.4050)),    # Berlin
  # Berlin → Hamburg → Copenhagen → Stockholm
  line(OT, FALSE,
       c(52.5200, 13.4050),     # Berlin
       c(53.5511,  9.9937),     # Hamburg
       c(55.6761, 12.5683),     # Copenhagen
       c(59.3293, 18.0686)),    # Stockholm
  # Central Europe → Paris — Vienna → Munich → Paris
  line(OT, FALSE,
       c(48.2082, 16.3738),     # Vienna
       c(48.1351, 11.5820),     # Munich
       c(48.8566,  2.3522)),    # Paris
  # Paris → Calais feeder (the cross-Channel Calais → London leg is now
  # carried by the red English Channel major).
  line(OT, FALSE,
       c(48.8566,  2.3522),     # Paris
       c(50.9513,  1.8587)),    # Calais
  # Kiev → Warsaw connector
  line(OT, FALSE,
       c(50.4501, 30.5234),     # Kiev
       c(52.2297, 21.0122)),    # Warsaw
  # Balkans alt — Belgrade → Budapest → Vienna
  line(OT, FALSE,
       c(44.7866, 20.4489),     # Belgrade
       c(47.4979, 19.0402),     # Budapest
       c(48.2082, 16.3738)),    # Vienna
  # Southern Italy → Turin → Lyon → Paris (intra-EU onward route)
  line(OT, FALSE,
       c(38.1147, 15.6500),     # Reggio Calabria
       c(40.8518, 14.2681),     # Naples
       c(41.9028, 12.4964),     # Rome
       c(43.7696, 11.2558),     # Florence
       c(45.4642,  9.1900),     # Milan
       c(45.0703,  7.6869),     # Turin
       c(45.7640,  4.8357),     # Lyon
       c(48.8566,  2.3522)),    # Paris
  # Ventimiglia → Marseille → Lyon → Paris (French Riviera route).
  line(OT, FALSE,
       c(43.7906,  7.6082),     # Ventimiglia
       c(43.7102,  7.2620),     # Nice
       c(43.2965,  5.3698),     # Marseille
       c(45.7640,  4.8357),     # Lyon
       c(48.8566,  2.3522)),    # Paris
  # Barcelona → Lyon → Paris (Spain-to-France land route)
  line(OT, FALSE,
       c(41.3874,  2.1686),     # Barcelona
       c(43.6047,  1.4442),     # Toulouse
       c(45.7640,  4.8357),     # Lyon
       c(48.8566,  2.3522))     # Paris
)


# ── Emit JSON ───────────────────────────────────────────────
# Helper: tibble row → record with `latlng = c(lat, lon)`.
to_records <- function(df) {
  lapply(seq_len(nrow(df)), function(i) {
    list(
      name   = df$name[i],
      latlng = c(df$lat[i], df$lon[i]),
      dir    = df$dir[i]
    )
  })
}
hubs_list   <- to_records(HUBS)
cities_list <- to_records(CITIES)

payload <- list(
  ROUTE_COLORS       = as.list(ROUTE_COLORS),
  ROUTE_SHORT_LABELS = as.list(ROUTE_SHORT_LABELS),
  CAUSE_LABELS       = as.list(CAUSE_LABELS),
  ORIGIN_LABELS      = as.list(ORIGIN_LABELS),
  PRECISION_FLAGS    = as.list(PRECISION_FLAGS),
  HUBS               = hubs_list,
  CITIES             = cities_list,
  ROUTE_LINES        = ROUTE_LINES
)

out_path <- "data/built/routes.json"
write(
  toJSON(payload, auto_unbox = TRUE, pretty = 2, digits = 6),
  file = out_path
)

cat(sprintf(
  "Wrote: %s  (%d hubs, %d cities, %d polylines, %d corridors)\n",
  out_path,
  nrow(HUBS),
  nrow(CITIES),
  length(ROUTE_LINES),
  length(ROUTE_COLORS)
))

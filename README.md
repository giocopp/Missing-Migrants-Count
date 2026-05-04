# Data Bit 1 — IOM and UNITED on Europe's border

**Author:** Giorgio Coppola · **Date:** April 2026 · GRAD-E1493 Data Journalism, Hertie School

A short interactive piece comparing two records of migrant deaths on routes leading to Europe: the **IOM Missing Migrants Project** (2014–2026) and the **UNITED for Intercultural Action** *List of Refugee Deaths* (1993–2026). The Leaflet map carries a UNITED ↔ IOM toggle and a year-range slider so the reader can see how the two organisations' coverage and counts differ across geography and time.

## Read the piece in the browser

**[Open the page on raw.githack.com](https://raw.githack.com/data-journalism-26/data-bit-1-giorgio/main/article.html)**

The page renders best on a real HTTP origin (like raw.githack). If you open `article.html` from disk via `file://`, the GeoJSON files for the interactive map will be blocked by the browser's same-origin policy. Locally, run a small server first:

```bash
python3 -m http.server 8000
# then open http://localhost:8000/article.html
```

## Repository layout

```
.
├── article.html                       # the article
├── data/
│   ├── iom_europe.csv                 # IOM records, filtered to Europe-bound routes
│   ├── united_europe.csv              # UNITED records, Europe-bound geographic envelope
│   ├── incidents_iom.geojson          # built from iom_europe.csv (consumed by the map)
│   └── incidents_united.geojson       # built from united_europe.csv
├── scripts/
│   ├── 01_filter_europe.R             # how the two CSVs were derived (private RDS source)
│   └── 02_build_geojson.R             # CSVs -> GeoJSON for the web map
├── Makefile                           # `make` rebuilds the GeoJSON; see "How to reproduce"
├── .gitignore
└── README.md
```

## How to reproduce

The data work is wired into a `Makefile`. From the project root:

```bash
make            # rebuild the two GeoJSON files (default)
make geojson    # same as above
make help       # list all targets
```

**One step is kept out of `make all`** and must be invoked explicitly because it requires the author's private thesis RDS files:

```bash
make filter     # re-derive the CSVs from the thesis RDS files
```

**Requirements:**

- R (≥ 4.3) with `dplyr`, `readr`, `sf`, `lubridate`

## Data sources

The two CSVs (`data/iom_europe.csv`, `data/united_europe.csv`) ship with the repo so the build is reproducible without registering with the original sources.

- **IOM Missing Migrants Project.** Incident-level data from the International Organization for Migration. Downloadable as CSV from <https://missingmigrants.iom.int/downloads>. The CSV in this repo is filtered to routes leading to Europe (Central / Western / Eastern Mediterranean, Western Africa Atlantic to the Canaries, Western Balkans, Belarus–EU border, the Türkiye corridors, Mainland Europe to the UK, Sahara Desert crossing, Italy–France, Ukraine–Europe, Sea crossings to Mayotte) and excludes IOM's own *Cumulative Incident* roll-ups so events are not double-counted.
- **UNITED for Intercultural Action — *List of Refugee Deaths*.** A public dataset of refugee and migrant deaths recorded since 1993, distributed by the network. Available at <https://unitedagainstrefugeedeaths.eu/about-the-campaign/about-the-united-list-of-deaths/>. UNITED's mandate is Europe-bound by construction; the CSV in this repo keeps every record that geocodes inside the Europe-bound envelope (lon −25° to 55°, lat 10° to 75°).
- **Basemap.** CartoDB Voyager (no labels) tiles via the Leaflet CDN, © OpenStreetMap contributors, used under ODbL.

## Methodology

Both datasets often record **one row per individual death** rather than per event. The Parndorf truck case in 2015, for example, appears in UNITED as 68 separate single-death rows that share the same date, place and coordinate. To make the map readable, rows that share a date and a coordinate are aggregated into a single feature whose `n_dead` is the sum of those rows — so each circle on the map corresponds to one *event*, not to one row. The `n_rows` field on each feature reports how many raw rows were merged.

For IOM, the filter keeps incidents tagged with a Europe-bound `Route` value, drops the `Cumulative Incident` rows (IOM's own multi-event roll-ups), and excludes records that geocode outside the Europe-bound envelope. For UNITED, no route filter is applied (the dataset is Europe-bound by construction); the same geographic envelope is applied for visual consistency. Five UNITED rows with corrupt longitudes (values around −370 and one of −17 266 954) are dropped.

The resulting figures are **49 777 dead or missing across 6 463 events** for IOM (2014–2026) and **69 748 deaths across 6 612 events** for UNITED (1993–2026). The two are not directly comparable: they cover different windows, count different things (UNITED keeps deportation-route deaths and other categories IOM does not), and use different sourcing criteria. That difference is the point of the piece.

## AI disclosure

Claude Code (Anthropic) was used to support: the design of the HTML page; the troubleshooting and refinement of the code that produces the interactive map; and the reproducibility pipeline. Editorial decisions, data wrangling, analysis and interpretation, as well as the writing are the author's.

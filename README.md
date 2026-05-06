# Data Bit 1 — How are dead and missing migrants at sea counted?

**Author:** Giorgio Coppola · **Date:** May 2026 · GRAD-E1493 Data Journalism, Hertie School

A short interactive piece on the **IOM Missing Migrants Project** record (2014–2026), restricted to the four sea corridors to Europe — Central, Western and Eastern Mediterranean, plus the Western Africa / Atlantic route to the Canary Islands. Death points are coloured by sea corridor and overlaid on the broader African and Eurasian migration-route network (West Africa, Western/Central/Eastern Mediterranean, East Africa, Other). The map has a month-level period slider (with month/year dropdowns) and four filters: region of origin, sea corridor, cause of death, and incident size.

## View

**[Open on raw.githack.com](https://raw.githack.com/data-journalism-26/data-bit-1-giorgio/main/article.html)** · or run a local server:

```bash
make serve
# http://localhost:8000/article.html
```

(Opening `article.html` directly via `file://` will fail — `fetch()` can't read local GeoJSON.)

## Layout

```
.
├── article.html                       # HTML shell (links assets/, fetches data/built/*)
├── assets/
│   ├── style.css                      # all visual styling
│   ├── article.js                     # Leaflet setup, render, filters, slider, legend
│   └── scrollytelling.js              # IntersectionObserver scene reveal
├── data/
│   ├── raw/                           # intermediate CSV (output of R/01)
│   │   └── iom_europe.csv
│   └── built/                         # artefacts the page fetches at runtime
│       ├── routes.json                # palette, hubs, polylines (output of R/03)
│       └── incidents_iom.geojson      # built from iom_europe.csv (output of R/02)
├── R/
│   ├── 01_filter_europe.R             # raw RDS → data/raw/iom_europe.csv  (PRIVATE SOURCE)
│   ├── 02_build_geojson.R             # data/raw/iom_europe.csv → data/built/incidents_iom.geojson
│   ├── 03_build_routes.R              # palette, hubs, polylines → data/built/routes.json
│   ├── 04_update_iom.R                # merge new IOM raw downloads into the canonical CSV
│   └── 05_validate_corridors.R        # cross-check polylines against DTM admin-0 IDP data
├── Makefile
└── README.md
```

### Where to edit what

- **Route geometry** (corridor polylines, hub coordinates, palette, label maps) → `R/03_build_routes.R`, then `make routes`
- **Visual styling** (colours, typography, legend, fullscreen layout) → `assets/style.css` (sections 1–13 indexed at the top)
- **Map / filter behavior** (Leaflet, slider, dropdowns, render loop) → `assets/article.js` (sections 1–12 indexed at the top)
- **Scene structure / copy / form options / methodology** → `article.html`
- **Incident data pipeline** (CSV → GeoJSON) → `R/02_build_geojson.R`, then `make geojson`

## Reproduce

```bash
make            # rebuild data/built/*.geojson + data/built/routes.json
make routes     # only rebuild routes.json
make geojson    # only rebuild the incident GeoJSON
make update     # merge new IOM raw downloads from data/raw/ + rebuild GeoJSON
make serve      # preview article.html on http://localhost:8000
make filter     # re-derive the IOM CSV from the private RDS (skip if data/raw/ is populated)
```

### Updating with new IOM data

To pull in fresh IOM Missing Migrants Project records:

1. Download the latest CSV from <https://missingmigrants.iom.int/downloads> — file name will look like `MissingMigrants-Global-2026-05-06--19_42_11.csv`.
2. Drop it into `data/raw/`.
3. Run `make update`.

`R/04_update_iom.R` reads any `MissingMigrants-Global-*.csv` in `data/raw/`, maps the raw download schema onto the curated one, dedupes by Main ID, and appends only the rows that aren't already in `data/raw/iom_europe.csv`. `R/02_build_geojson.R` then rebuilds the GeoJSON. The map picks up the new dots on the next reload.

### Cross-checking corridors against IOM DTM

Two read-only sanity checks against the [IOM DTM API](https://dtm.iom.int/data-and-analysis/dtm-api):

- `make validate` (script `R/05_validate_corridors.R`) — admin-0: lists which waypoint *countries* on each polyline have any DTM operation. Writes `data/built/dtm_validation.csv`.
- `make admin1` (script `R/06_admin1_clusters.R`) — admin-1: per displacement-active transit country, prints the top-3 IDP zones and flags any waypoint sitting > 300 km from the centroid of a major cluster. Writes `data/built/dtm_admin1_clusters.csv`.

Neither validates route geometry — DTM does not publish corridor shapefiles. They validate that the *countries and within-country regions* the corridors pass through are consistent with the displacement landscape DTM reports.

Setup:

1. Register at <https://dtm.iom.int/data-and-analysis/dtm-api> and generate a subscription key (free, requires an account; you'll get a primary + secondary key — either works, primary is fine).
2. Install the R wrapper:
   ```r
   install.packages("dtmapi")
   # or, if not on CRAN yet:
   remotes::install_github("Displacement-Tracking-Matrix/dtmapi-R")
   ```
3. Put the key in your shell env (don't commit it):
   ```bash
   export DTM_SUBSCRIPTION_KEY=your-key-here
   ```
4. Run `make validate`. The script writes `data/built/dtm_validation.csv` (corridor / country / in_dtm / idp_count) and prints a per-corridor table to stdout.

A "no DTM signal" flag for a European destination country is expected — DTM operates where there's an active displacement crisis, not in destinations.

Requires R ≥ 4.3 with `dplyr`, `readr`, `sf`, `lubridate`, `stringr`, `rnaturalearth`, `jsonlite`, `tibble`.
The front-end has no JS build step — `article.html`, the files in `assets/`,
and the JSON / GeoJSON in `data/built/` are served as-is.

## Sources

- **IOM Missing Migrants Project** — <https://missingmigrants.iom.int/downloads>. Incident-level data; cumulative roll-ups dropped so events aren't double-counted.
- **Basemap** — CartoDB Positron (light grey, with country and sea labels), © OpenStreetMap contributors, ODbL.
- **Migration-route overlay** — hand-digitized 62 corridor polylines + 12 main migration hubs, defined in R (`R/03_build_routes.R`) and emitted as `data/built/routes.json` for the front-end to fetch. Geometry is approximate; corridor shapes were refined against IOM's [Global Overview of Migration Routes](https://dtm.iom.int/global-overview-of-migration-routes-portal) portal. Suggested reading is listed in the *Data and methods* section of the article.

## Methodology (brief)

- **Sea-routes scope.** The GeoJSON is restricted to the four sea corridors connecting to Europe. Land routes (Sahara desert, Türkiye–Europe land, Western Balkans, Belarus–EU, Italy–France, Mainland Europe → UK, Ukraine → Europe) and post-arrival deaths inside Europe are filtered out at build time.
- **One feature = one event.** Most IOM incidents arrive as a single row with their own death count attached. The ~3% that arrive split across multiple rows sharing a (lat, lon, date) are collapsed into one feature; `n_dead` is summed and the underlying row count surfaces in the tooltip.
- **IOM coord cleanup.** Each (lat, lon) is checked against the named country of incident; rows farther than 500 km are tested for a longitude sign-flip, lat-lon swap, or both, and the variant kept only if it lands within 200 km of the country polygon. Unrescuable rows are dropped.
- For the full walkthrough, see the *Data and methods* section at the bottom of the article.

## AI disclosure

Claude Code (Anthropic) was used to support the design of the page, the troubleshooting and refinement of the map code, and the reproducibility pipeline. Editorial decisions, data wrangling, analysis, interpretation, and writing are the author's.

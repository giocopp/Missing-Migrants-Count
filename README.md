# Data Bit 1 — How are dead and missing migrants at sea counted?

**Author:** Giorgio Coppola · **Date:** April 2026 · GRAD-E1493 Data Journalism, Hertie School

A short interactive piece on the **IOM Missing Migrants Project** record (2014–2026), restricted to the four sea corridors to Europe — Central, Western and Eastern Mediterranean, plus the Western Africa / Atlantic route to the Canary Islands. Death points are coloured by sea corridor and overlaid on the broader African and Eurasian migration-route network (West Africa, Western/Central/Eastern Mediterranean, East Africa, Other). The map has a month-level period slider (with month/year dropdowns) and four filters: region of origin, sea corridor, cause of death, and incident size.

An earlier version compared IOM with **UNITED for Intercultural Action**'s *List of Refugee Deaths*. UNITED was dropped from the map after a coord audit (see *Methodology*); its CSV and GeoJSON still ship with the repo.

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
├── article.html                  # HTML shell (links assets/ + loads data/incidents_iom.geojson)
├── assets/
│   ├── style.css                 # all visual styling
│   ├── data.js                   # palette, hubs, hand-digitized route polylines
│   ├── article.js                # Leaflet setup, render, filters, slider, legend
│   └── scrollytelling.js         # IntersectionObserver scene reveal
├── data/
│   ├── iom_europe.csv            # IOM, filtered to Europe-bound routes
│   ├── united_europe.csv         # UNITED, Europe-bound envelope (not on map)
│   ├── incidents_iom.geojson     # built from iom_europe.csv
│   └── incidents_united.geojson  # built from united_europe.csv
├── scripts/
│   ├── 01_filter_europe.R        # CSVs from private RDS source
│   └── 02_build_geojson.R        # CSVs → GeoJSON
├── Makefile
└── README.md
```

### Where to edit what

- **Route geometry** (corridor polylines, hub coordinates, palette) → `assets/data.js`
- **Visual styling** (colors, typography, legend, fullscreen layout) → `assets/style.css` (sections 1–12 indexed at the top)
- **Map / filter behavior** (Leaflet, slider, dropdowns, render loop) → `assets/article.js` (sections 1–14 indexed at the top)
- **Scene structure / copy / form options** → `article.html`
- **Incident data pipeline** (CSV → GeoJSON) → `scripts/02_build_geojson.R`

## Reproduce

```bash
make            # rebuild both GeoJSONs
make serve      # preview article.html on http://localhost:8000
make filter     # re-derive CSVs from private RDS (skip if CSVs are present)
```

Requires R ≥ 4.3 with `dplyr`, `readr`, `sf`, `lubridate`, `stringr`, `rnaturalearth`.
The front-end has no build step — `article.html` and the files in `assets/`
are served as-is.

## Sources

- **IOM Missing Migrants Project** — <https://missingmigrants.iom.int/downloads>. Incident-level data; cumulative roll-ups dropped so events aren't double-counted.
- **UNITED — *List of Refugee Deaths*** — <https://unitedagainstrefugeedeaths.eu/about-the-campaign/about-the-united-list-of-deaths/>. In repo, not on the map.
- **Basemap** — CartoDB Positron (light grey, with country and sea labels), © OpenStreetMap contributors, ODbL.
- **Migration-route overlay** — hand-digitized from the Mixed Migration Centre / *Financial Times* style reference figure of African and Eurasian corridors. Geometry is approximate; see comments in `assets/data.js`.

## Methodology (brief)

- **Sea-routes scope.** GeoJSONs are restricted to the four sea corridors connecting to Europe. Land routes and post-arrival deaths are filtered out at build time.
- **One feature = one event.** Both datasets often record one row per individual death. Rows that share a coordinate and date are aggregated; `n_dead` is summed.
- **IOM coord cleanup.** Each (lat, lon) is checked against the named country of incident; rows farther than 500 km are tested for a longitude sign-flip, lat-lon swap, or both, and the variant kept only if it lands within 200 km of the country polygon. Unrescuable rows are dropped.
- **Why UNITED isn't on the map.** UNITED tags rows by migration corridor (`crossing_countries`), not by where the death actually happened, which puts Sahara desert deaths into the Central Med bucket and post-arrival deaths inside Europe onto sea-route corridors. A coord-envelope check fixed many of these but residual errors (digit-drop typos, etc.) made the dot-on-corridor reading unreliable, so the source was excluded.

## AI disclosure

Claude Code (Anthropic) was used to support the design of the page, the troubleshooting and refinement of the map code, and the reproducibility pipeline. Editorial decisions, data wrangling, analysis, interpretation, and writing are the author's.

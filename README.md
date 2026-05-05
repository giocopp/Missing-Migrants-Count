# Data Bit 1 — How are dead and missing migrants at sea counted?

**Author:** Giorgio Coppola · **Date:** April 2026 · GRAD-E1493 Data Journalism, Hertie School

A short interactive piece on the **IOM Missing Migrants Project** record (2014–2026), restricted to the four sea corridors to Europe — Central, Western and Eastern Mediterranean, plus the Western Africa / Atlantic route to the Canary Islands. The map has a month-level period slider (with month/year dropdowns) and filters for region of origin, sea corridor and cause of death.

An earlier version compared IOM with **UNITED for Intercultural Action**'s *List of Refugee Deaths*. UNITED was dropped from the map after a coord audit (see *Methodology*); its CSV and GeoJSON still ship with the repo.

## View

**[Open on raw.githack.com](https://raw.githack.com/data-journalism-26/data-bit-1-giorgio/main/article.html)** · or run a local server:

```bash
python3 -m http.server 8000
# http://localhost:8000/article.html
```

(Opening `article.html` directly via `file://` will fail — `fetch()` can't read local GeoJSON.)

## Layout

```
.
├── article.html                  # the page (loads incidents_iom.geojson)
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

## Reproduce

```bash
make            # rebuild both GeoJSONs
make filter     # re-derive CSVs from private RDS (skip if CSVs are present)
```

Requires R ≥ 4.3 with `dplyr`, `readr`, `sf`, `lubridate`, `stringr`, `rnaturalearth`.

## Sources

- **IOM Missing Migrants Project** — <https://missingmigrants.iom.int/downloads>. Incident-level data; cumulative roll-ups dropped so events aren't double-counted.
- **UNITED — *List of Refugee Deaths*** — <https://unitedagainstrefugeedeaths.eu/about-the-campaign/about-the-united-list-of-deaths/>. In repo, not on the map.
- **Basemap** — CartoDB Voyager (no labels), © OpenStreetMap contributors, ODbL.

## Methodology (brief)

- **Sea-routes scope.** GeoJSONs are restricted to the four sea corridors connecting to Europe. Land routes and post-arrival deaths are filtered out at build time.
- **One feature = one event.** Both datasets often record one row per individual death. Rows that share a coordinate and date are aggregated; `n_dead` is summed.
- **IOM coord cleanup.** Each (lat, lon) is checked against the named country of incident; rows farther than 500 km are tested for a longitude sign-flip, lat-lon swap, or both, and the variant kept only if it lands within 200 km of the country polygon. Unrescuable rows are dropped.
- **Why UNITED isn't on the map.** UNITED tags rows by migration corridor (`crossing_countries`), not by where the death actually happened, which puts Sahara desert deaths into the Central Med bucket and post-arrival deaths inside Europe onto sea-route corridors. A coord-envelope check fixed many of these but residual errors (digit-drop typos, etc.) made the dot-on-corridor reading unreliable, so the source was excluded.

## AI disclosure

Claude Code (Anthropic) was used to support the design of the page, the troubleshooting and refinement of the map code, and the reproducibility pipeline. Editorial decisions, data wrangling, analysis, interpretation, and writing are the author's.

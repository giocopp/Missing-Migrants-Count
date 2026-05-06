# Reproducible build for the Data Bit 1 project.
#
# `make all` (the default) rebuilds the two artifacts the front-end
# fetches at runtime: the IOM incident GeoJSON, and the routes.json
# that carries the palette / hubs / corridor polylines. The CSV-creation
# step (`make filter`) is kept out of `all` because it requires the
# author's private thesis RDS file; the CSV and built artifacts ship
# with the repo so the rest of the build is reproducible without it.

R := Rscript

CSV_IOM        := data/raw/iom_europe.csv
GEOJSON_IOM    := data/built/incidents_iom.geojson
ROUTES_JSON    := data/built/routes.json

PORT := 8000

.PHONY: all geojson routes filter update validate admin1 serve clean help
.DEFAULT_GOAL := all

all: geojson routes

geojson: $(GEOJSON_IOM)

routes: $(ROUTES_JSON)

$(GEOJSON_IOM): R/02_build_geojson.R $(CSV_IOM)
	$(R) $<

$(ROUTES_JSON): R/03_build_routes.R
	$(R) $<

# Manual / heavy step (NOT in `all`): re-derives the curated CSV from
# the author's private thesis RDS file. Skip unless that CSV is missing.
filter:
	$(R) R/01_filter_europe.R

# Drop a new IOM MMP raw CSV (e.g. MissingMigrants-Global-YYYY-MM-DD-*.csv)
# into data/raw/ and run `make update`. R/04 dedupes by Main ID and
# appends new rows to the canonical CSV; R/02 then rebuilds the GeoJSON.
update:
	$(R) R/04_update_iom.R
	$(R) R/02_build_geojson.R

# Cross-check the corridor polylines against IOM DTM admin-0 IDP data.
# Requires the dtmapi R package and a DTM_SUBSCRIPTION_KEY env var
# (free key: https://dtm.iom.int/data-and-analysis/dtm-api).
# Writes data/built/dtm_validation.csv.
validate:
	$(R) R/05_validate_corridors.R

# Drill into DTM admin-1 (state/province) data: list the top
# displacement clusters per transit country and flag any that sit
# > 300 km from our current waypoints. Read-only sanity check.
admin1:
	$(R) R/06_admin1_clusters.R

# Preview the article locally. fetch() needs http://, not file://, so
# a server is required. Override the port with `make serve PORT=9000`.
serve:
	@echo "Open http://localhost:$(PORT)/article.html"
	python3 -m http.server $(PORT)

clean:
	rm -f $(GEOJSON_IOM) $(ROUTES_JSON)

help:
	@echo "Targets:"
	@echo "  make            -> rebuild GeoJSON + routes.json (default)"
	@echo "  make geojson    -> rebuild only the IOM incident GeoJSON"
	@echo "  make routes     -> rebuild only data/built/routes.json"
	@echo "  make update     -> merge new IOM raw CSVs in data/raw/, then rebuild GeoJSON"
	@echo "  make validate   -> cross-check polylines against DTM admin-0 IDP data (needs API key)"
	@echo "  make admin1     -> drill into DTM admin-1 IDP clusters per transit country (needs API key)"
	@echo "  make filter     -> re-derive the IOM CSV from the thesis RDS (PRIVATE SOURCE)"
	@echo "  make serve      -> preview article.html on http://localhost:$(PORT)"
	@echo "  make clean      -> remove the built artifacts"

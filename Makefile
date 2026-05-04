# Reproducible build for the Data Bit 1 project.
#
# The default `make geojson` target rebuilds the two GeoJSON files consumed
# by the Leaflet map from the curated CSVs. The CSV-creation step (`filter`)
# is kept out of `make all` because it requires the author's private thesis
# RDS files; the CSVs ship with the repo so the rest of the build is
# reproducible without them.

R := Rscript

CSV_IOM    := data/iom_europe.csv
CSV_UNITED := data/united_europe.csv

GEOJSON_IOM    := data/incidents_iom.geojson
GEOJSON_UNITED := data/incidents_united.geojson

.PHONY: all geojson clean help
.DEFAULT_GOAL := all

all: geojson

geojson: $(GEOJSON_IOM) $(GEOJSON_UNITED)

$(GEOJSON_IOM) $(GEOJSON_UNITED): scripts/02_build_geojson.R $(CSV_IOM) $(CSV_UNITED)
	$(R) $<

# Manual / heavy step (NOT in `all`): re-derives the curated CSVs from the
# author's private thesis RDS files. Skip unless those CSVs are missing.
filter:
	$(R) scripts/01_filter_europe.R

clean:
	rm -f $(GEOJSON_IOM) $(GEOJSON_UNITED)

help:
	@echo "Targets:"
	@echo "  make            -> rebuild the two GeoJSON files (default)"
	@echo "  make geojson    -> same as above"
	@echo "  make filter     -> re-derive CSVs from the thesis RDS (PRIVATE SOURCE)"
	@echo "  make clean      -> remove the GeoJSON files"

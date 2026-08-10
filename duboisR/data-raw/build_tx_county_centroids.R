#!/usr/bin/env Rscript
# Builds inst/extdata/tx_county_centroids.csv from the U.S. Census Bureau's
# public-domain Gazetteer Files (no API key, no attribution restriction).
# Source: https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.html
#
# Not run automatically by the package — this is a documented, repeatable
# provenance script. Re-run it if the Gazetteer file is updated (e.g. after
# a county boundary/name change) or a different vintage year is desired.

gaz_url <- "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_counties_national.zip"

tmp_zip <- tempfile(fileext = ".zip")
tmp_dir <- tempfile()
dir.create(tmp_dir)

utils::download.file(gaz_url, tmp_zip, quiet = TRUE)
utils::unzip(tmp_zip, exdir = tmp_dir)

gaz_path <- list.files(tmp_dir, pattern = "\\.txt$", full.names = TRUE)[1]
gaz <- readr::read_tsv(gaz_path, col_types = readr::cols(.default = "c"), trim_ws = TRUE)
names(gaz) <- trimws(names(gaz))

tx_centroids <- gaz |>
  dplyr::filter(substr(.data$GEOID, 1, 2) == "48") |>
  dplyr::transmute(
    county_fips = .data$GEOID,
    county_name = sub(" County$", "", .data$NAME),
    lat = as.numeric(.data$INTPTLAT),
    lon = as.numeric(.data$INTPTLONG)
  ) |>
  dplyr::arrange(.data$county_fips)

stopifnot(nrow(tx_centroids) == 254)

readr::write_csv(tx_centroids, file.path("inst", "extdata", "tx_county_centroids.csv"))
cat("Wrote", nrow(tx_centroids), "TX county centroids to inst/extdata/tx_county_centroids.csv\n")

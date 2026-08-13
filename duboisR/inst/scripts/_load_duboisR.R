# Shared by every standalone Rscript entry point in this repo that needs
# duboisR loaded before anything else runs: duboisR/inst/scripts/*.R,
# r_dashboard/app.R, r_dashboard/dev/generate_synthetic_data.R. These are
# plain `Rscript` entry points, not package code, so they can't
# @importFrom a shared internal the normal package way -- source()ing this
# file is the standalone equivalent.

load_duboisR_or_die <- function(pkg_path = "duboisR") {
  if (requireNamespace("duboisR", quietly = TRUE)) {
    library(duboisR)
  } else if (requireNamespace("pkgload", quietly = TRUE)) {
    # pkgload is what devtools::load_all() itself delegates to -- calling it
    # directly avoids pulling in devtools' much heavier dev-only dependency
    # tree (roxygen2, testthat, pkgbuild, gert/libgit2, ...) just to load an
    # already-written package's R/ source.
    pkgload::load_all(pkg_path, quiet = TRUE)
  } else {
    stop(
      "duboisR is not installed and pkgload is unavailable to load it from ",
      "source. Run: Rscript -e 'install.packages(\"pkgload\"); devtools::install(\"duboisR\")'"
    )
  }
}

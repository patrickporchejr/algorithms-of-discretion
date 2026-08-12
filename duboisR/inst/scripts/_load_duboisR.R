# Shared by every standalone Rscript entry point in this repo that needs
# duboisR loaded before anything else runs: duboisR/inst/scripts/*.R,
# r_dashboard/app.R, r_dashboard/dev/generate_synthetic_data.R. These are
# plain `Rscript` entry points, not package code, so they can't
# @importFrom a shared internal the normal package way -- source()ing this
# file is the standalone equivalent.

load_duboisR_or_die <- function(pkg_path = "duboisR") {
  if (requireNamespace("duboisR", quietly = TRUE)) {
    library(duboisR)
  } else if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(pkg_path, quiet = TRUE)
  } else {
    stop(
      "duboisR is not installed and devtools is unavailable to load it from ",
      "source. Run: Rscript -e 'install.packages(\"devtools\"); devtools::install(\"duboisR\")'"
    )
  }
}

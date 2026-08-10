#!/usr/bin/env Rscript
# Fake data matching the schema r_dashboard/R/mod_regression.R expects, so the
# Shiny app can be exercised locally before the real Python pipeline (01-03)
# has run against a decided-on state dataset. Not a source of real findings.
set.seed(42)

n <- 2000
races <- c("white", "black", "hispanic", "asian", "other")

df <- data.frame(
  subject_race = sample(races, n, replace = TRUE, prob = c(0.55, 0.2, 0.15, 0.07, 0.03)),
  subject_age = pmin(pmax(round(rnorm(n, mean = 35, sd = 12)), 16), 85),
  subject_sex = sample(c("male", "female"), n, replace = TRUE, prob = c(0.6, 0.4)),
  poverty_rate = pmin(pmax(rnorm(n, mean = 0.15, sd = 0.06), 0.01), 0.6),
  median_income = pmin(pmax(rnorm(n, mean = 62000, sd = 15000), 20000), 150000),
  hour = sample(0:23, n, replace = TRUE)
)

race_effect <- ifelse(df$subject_race %in% c("black", "hispanic"), 0.5, 0)
logit_search <- -2.2 + race_effect - 0.00001 * df$median_income + rnorm(n, 0, 0.5)
p_search <- 1 / (1 + exp(-logit_search))
df$search_conducted <- rbinom(n, 1, p_search)

logit_arrest <- -3 + 1.2 * df$search_conducted + rnorm(n, 0, 0.5)
p_arrest <- 1 / (1 + exp(-logit_arrest))
df$is_arrested <- rbinom(n, 1, p_arrest)

file_arg <- sub("--file=", "", grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
script_dir <- dirname(normalizePath(file_arg))
out_path <- file.path(script_dir, "..", "..", "data", "processed", "audit_ready_stops.csv")
write.csv(df, out_path, row.names = FALSE)
cat("Wrote", nrow(df), "rows to", normalizePath(out_path), "\n")

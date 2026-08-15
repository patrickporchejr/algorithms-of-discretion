#!/usr/bin/env Rscript
# Single, consistent entry point for every duboisR command-line program:
#
#   Rscript duboisR/inst/scripts/cli.R <command> [options]
#
# Dispatches to the same scripts in this directory that each remain
# independently runnable on their own (e.g. `Rscript
# duboisR/inst/scripts/veil_of_darkness_cli.R ...` still works exactly as
# before) -- this file adds one uniform way to reach any of them, it
# doesn't replace them. commandArgs() inside the dispatched script sees
# only the arguments after <command>, via a local override (see
# run_command() below), not the dispatcher's own full argv.
#
# Run every command's own --help for its specific options, e.g.:
#   Rscript duboisR/inst/scripts/cli.R veil --help

COMMANDS <- list(
  veil = "veil_of_darkness_cli.R",
  threshold = "threshold_test_cli.R",
  datasheet = "seed_demo_datasheet.R",
  grounding = "run_grounding_experiment.R"
)

COMMAND_DESCRIPTIONS <- c(
  veil = "Veil of Darkness charts (county / statewide / search / combined / all)",
  threshold = "Threshold Test + naive outcome-test comparison charts (fit / compare / all)",
  datasheet = "Seed a first-pass datasheet.json for the processed dataset",
  grounding = "Run the naive-vs-grounded LLM datasheet-grounding experiment"
)

USAGE <- sprintf(
  "
Usage: Rscript duboisR/inst/scripts/cli.R <command> [options]

Commands:
%s

Run `Rscript duboisR/inst/scripts/cli.R <command> --help` for a command's own options.
",
  paste(sprintf("  %-10s %s", names(COMMAND_DESCRIPTIONS), COMMAND_DESCRIPTIONS), collapse = "\n")
)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || args[1] %in% c("--help", "-h")) {
  cat(USAGE)
  quit(save = "no", status = 0)
}

command <- args[1]
if (!command %in% names(COMMANDS)) {
  stop(sprintf(
    "Unknown command '%s'. Valid commands: %s",
    command, paste(names(COMMANDS), collapse = ", ")
  ))
}

# Overriding commandArgs() locally (rather than, say, reassigning it in the
# global environment) means this only ever affects the one sourced script,
# never any other code the sourced script itself might go on to source or
# call -- source(path, local = TRUE) evaluates the file's top-level code in
# this same local frame, so its unqualified commandArgs() calls resolve to
# the override below before falling through to base::commandArgs().
run_command <- function(script, args) {
  local({
    commandArgs <- function(...) args
    source(file.path("duboisR/inst/scripts", script), local = TRUE)
  })
}

run_command(COMMANDS[[command]], args[-1])

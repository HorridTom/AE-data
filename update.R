#!/usr/bin/env Rscript
# Bring the A&E Tracker data up to date.
#
# Run from the top folder of this repository:
#
#   Rscript update.R
#
# This downloads the latest files from NHS England and Public Health Scotland,
# checks the result, and overwrites data/AE_Data_England.csv and
# data/AE_Data_Scotland.csv if anything has changed. Commit and push the data
# folder afterwards (the GitHub Action does this itself).
#
# To use files already downloaded instead, set AE_ENGLAND_DIR and/or
# AE_SCOTLAND_DIR to the folders holding them, e.g.
#
#   AE_ENGLAND_DIR=~/Rprojects/nhsAEscraper/data-raw/sitreps Rscript update.R
#
# The script exits with an error if either country fails, after saving the
# other, so that a scheduled run that fails is reported.

source(file.path("R", "update_functions.R"))

dir_or_null <- function(var) {
  value <- Sys.getenv(var)
  if (nzchar(value)) path.expand(value) else NULL
}

results <- list(
  update_country("England", dir_or_null("AE_ENGLAND_DIR")),
  update_country("Scotland", dir_or_null("AE_SCOTLAND_DIR"))
)

write_metadata(results)

failed <- Filter(function(r) r$status == "error", results)
for (r in results) {
  message(r$country, ": ", r$status)
  if (!is.null(r$problems)) message(paste0("  - ", r$problems, collapse = "\n"))
}
if (length(failed) > 0) quit(status = 1)

# Functions used by update.R to scrape, check and save the A&E data.

library(dplyr, warn.conflicts = FALSE)

# Each country's data: the file it is saved in, the columns that identify a
# row (one provider in one period), the period column, and the columns kept.
data_spec <- list(
  England = list(
    file = file.path("data", "AE_Data_England.csv"),
    key = c("Prov_Code", "Month_Start"),
    period = "Month_Start",
    period_unit = "month",
    columns = c("Prov_Code", "Region", "Prov_Name", "Month_Start",
                "Att_Typ1", "Att_Typ2", "Att_Typ3", "Att_All",
                "Att_Typ1_Br", "Att_Typ2_Br", "Att_Typ3_Br", "Att_All_Br",
                "Perf_Typ1", "Perf_All",
                "E_Adm_Typ1", "E_Adm_Typ2", "E_Adm_Typ34", "E_Adm_All_ED",
                "E_Adm_Not_ED", "E_Adm_All", "E_Adm_4hBr_D", "E_Adm_12hBr_D",
                "SourceFile")
  ),
  Scotland = list(
    file = file.path("data", "AE_Data_Scotland.csv"),
    key = c("Prov_Code", "Week_End"),
    period = "Week_End",
    period_unit = "week",
    columns = c("Week_End", "Board_Code", "Board_Name", "Prov_Code",
                "Prov_Name", "Att_All", "Att_4hr_Br", "Perf_4hr",
                "Att_8hr_Br", "Perf_8hr", "Att_12hr_Br", "Perf_12hr",
                "SourceFile")
  )
)


# Scrape one country's data with nhsAEscraper and put it in the saved format.
# If `directory` is NULL, the files are downloaded afresh into a temporary
# folder. Otherwise the files already in `directory` are used, and nothing is
# downloaded (England: the monthly .xls/.xlsx files; Scotland: the
# weekly_ae_activity csv plus ae_hospital_site_list.csv and hb14_hb19.csv).
scrape_country <- function(country, directory = NULL) {
  spec <- data_spec[[country]]
  update_data <- is.null(directory)
  if (update_data) {
    # download_AE_files() empties the folder it downloads into, so always use
    # a new one.
    directory <- file.path(tempdir(), paste0("ae-download-", country))
    unlink(directory, recursive = TRUE)
  }

  df <- nhsAEscraper::getAE_data(update_data = update_data,
                                 directory = directory,
                                 country = country)

  # England's Month_Start is midnight London time; take the calendar date in
  # London (as.Date() alone would give the day before, in UTC).
  df[[spec$period]] <- as.Date(format(df[[spec$period]], "%Y-%m-%d",
                                      tz = "Europe/London"))

  if (country == "Scotland") df <- combine_duplicate_rows_scotland(df)

  df %>%
    mutate(SourceFile = basename(SourceFile),
           across(starts_with("Perf"), ~ round(.x, 6))) %>%
    select(all_of(spec$columns)) %>%
    arrange(across(all_of(c(spec$period, "Prov_Code"))))
}


# A few Scottish sites have two rows for the same week, e.g. the Queen
# Elizabeth University Hospital in the week it opened (2015-05-03), when it and
# the hospital it replaced both reported under its code. Add such rows together
# and recalculate their percentages, so there is one row per site per week.
combine_duplicate_rows_scotland <- function(df) {
  key <- data_spec$Scotland$key
  dup <- duplicated(df[key]) | duplicated(df[key], fromLast = TRUE)
  if (!any(dup)) return(df)

  combined <- df[dup, ] %>%
    group_by(across(all_of(c(key, "Board_Code", "Board_Name", "Prov_Name",
                             "SourceFile")))) %>%
    summarise(across(starts_with("Att_"), sum), .groups = "drop") %>%
    mutate(Perf_4hr = round(100 * (Att_All - Att_4hr_Br) / Att_All, 1),
           Perf_8hr = round(100 * Att_8hr_Br / Att_All, 1),
           Perf_12hr = round(100 * Att_12hr_Br / Att_All, 1))

  bind_rows(df[!dup, ], combined)
}


read_saved <- function(country) {
  spec <- data_spec[[country]]
  if (!file.exists(spec$file)) return(NULL)
  readr::read_csv(spec$file, show_col_types = FALSE, guess_max = Inf)
}


# Check newly scraped data before it replaces the saved data. Returns a
# character vector of problems; empty if there are none.
check_data <- function(new, old, country) {
  spec <- data_spec[[country]]
  problems <- character()
  add <- function(...) problems <<- c(problems, paste0(...))

  if (nrow(new) == 0) return("No rows were scraped.")

  missing_cols <- setdiff(spec$columns, names(new))
  if (length(missing_cols) > 0) add("Missing columns: ", toString(missing_cols))

  n_dup <- sum(duplicated(new[spec$key]))
  if (n_dup > 0) add(n_dup, " rows share a provider and period.")

  periods <- sort(unique(new[[spec$period]]))
  expected <- seq(min(periods), max(periods), by = spec$period_unit)
  gaps <- setdiff(expected, periods)
  if (length(gaps) > 0) {
    add("Periods missing between the first and the latest: ",
        toString(format(as.Date(gaps, origin = "1970-01-01"))))
  }

  counts <- select(new, starts_with("Att_"), starts_with("E_Adm_"))
  if (any(counts < 0, na.rm = TRUE)) add("Some counts are negative.")

  if (!is.null(old) && nrow(old) > 0) {
    lost <- setdiff(unique(old[[spec$period]]), periods)
    if (length(lost) > 0) {
      add("Periods in the saved data are missing from the new data: ",
          toString(format(as.Date(lost, origin = "1970-01-01"))))
    }
    if (nrow(new) < 0.95 * nrow(old)) {
      add("The new data has ", nrow(new), " rows, fewer than 95% of the ",
          nrow(old), " saved.")
    }
  }

  problems
}


# TRUE if the new data holds the same values as the saved data.
same_data <- function(new, old) {
  if (is.null(old)) return(FALSE)
  isTRUE(all.equal(as.data.frame(new), as.data.frame(old),
                   check.attributes = FALSE, tolerance = 1e-9))
}


summarise_data <- function(df, country) {
  spec <- data_spec[[country]]
  list(rows = nrow(df),
       first_period = format(min(df[[spec$period]])),
       latest_period = format(max(df[[spec$period]])),
       providers = length(unique(df$Prov_Code)),
       source_files = length(unique(df$SourceFile)))
}


# Scrape, check and save one country. Returns a list describing the outcome.
update_country <- function(country, directory = NULL) {
  spec <- data_spec[[country]]
  message("== ", country)

  new <- tryCatch(scrape_country(country, directory),
                  error = function(e) e)
  if (inherits(new, "error")) {
    return(list(country = country, status = "error",
                problems = paste("Scraping failed:", conditionMessage(new))))
  }

  old <- read_saved(country)
  problems <- check_data(new, old, country)
  if (length(problems) > 0) {
    return(list(country = country, status = "error", problems = problems))
  }

  if (same_data(new, old)) {
    message("No change.")
    return(list(country = country, status = "unchanged"))
  }

  dir.create(dirname(spec$file), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(new, spec$file, na = "")
  message("Saved ", nrow(new), " rows to ", spec$file)
  list(country = country, status = "updated",
       summary = summarise_data(new, country))
}


write_metadata <- function(results, path = file.path("data", "metadata.json")) {
  meta <- if (file.exists(path)) jsonlite::read_json(path) else list()
  for (r in results) {
    if (identical(r$status, "updated")) {
      meta[[r$country]] <- c(list(updated_at = format(Sys.time(), tz = "UTC",
                                                      usetz = TRUE)),
                             r$summary)
    }
  }
  jsonlite::write_json(meta, path, auto_unbox = TRUE, pretty = TRUE)
}

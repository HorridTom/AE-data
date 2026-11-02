# Temporary check: can the NHS England index pages be read through the
# WordPress API, and does nhsAEscraper find the right files in them?
pages <- c(
  "statistical-work-areasae-waiting-times-and-activityae-attendances-and-emergency-admissions-2015-16-monthly-3",
  "statistical-work-areasae-waiting-times-and-activityae-attendances-and-emergency-admissions-2016-17",
  paste0("ae-attendances-and-emergency-admissions-",
         c("2017-18", "2018-19", "2019-20", "2020-21", "2021-22", "2022-23",
           "2023-24", "2024-25", "2025-26", "2026-27"))
)
api <- "https://www.england.nhs.uk/statistics/wp-json/wp/v2/pages"
total <- 0
for (slug in pages) {
  res <- httr::GET(api, query = list(slug = slug, `_fields` = "link,content"))
  cat("\n==", slug, "\nHTTP", httr::status_code(res))
  if (httr::status_code(res) != 200) next
  json <- jsonlite::fromJSON(httr::content(res, as = "text", encoding = "UTF-8"))
  if (length(json) == 0) { cat(" - no page with this slug\n"); next }
  html <- json$content$rendered[1]
  tmp <- tempfile(fileext = ".html")
  writeLines(strsplit(html, "\n")[[1]], tmp)
  urls <- nhsAEscraper::getAEdata_page_urls_monthly(paste0("file://", tmp))
  total <- total + length(urls)
  cat(",", nchar(html), "characters,", length(urls), "files\n")
  if (length(urls) > 0) cat(" ", basename(urls[c(1, length(urls))]), sep = "\n  ")
}
cat("\nTotal files found:", total, "\n")

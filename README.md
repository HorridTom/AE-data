# AE-data

The data behind the [A&E Tracker](https://clahrcnwl.shinyapps.io/ae-app/)
([code](https://github.com/HorridTom/AE-app)). This replaces the MySQL
database on AWS and the AE-data-storage-app that maintained it.

| File | Contents |
|---|---|
| `data/AE_Data_England.csv` | NHS England monthly A&E attendances, 4-hour breaches and emergency admissions, by provider, from June 2015 |
| `data/AE_Data_Scotland.csv` | Public Health Scotland weekly A&E attendances and 4/8/12-hour breaches, by site, from February 2015 |
| `data/metadata.json` | When each file last changed, its latest period, and row counts |

The data is collected with [nhsAEscraper](https://github.com/HorridTom/nhsAEscraper).

## Sources and licence

- England: NHS England,
  [A&E Attendances and Emergency Admissions](https://www.england.nhs.uk/statistics/statistical-work-areas/ae-waiting-times-and-activity/)
  (monthly provider-level data).
- Scotland: Public Health Scotland,
  [Weekly A&E Activity and Waiting Times](https://www.opendata.nhs.scot/dataset/weekly-accident-and-emergency-activity-and-waiting-times).

Contains public sector information licensed under the
[Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

The data has been processed (reshaped, combined and checked; see the notes
below) and is not an official publication of NHS England or Public Health
Scotland.

## How it is kept up to date

A [GitHub Action](.github/workflows/update-data.yml) runs `update.R` every
Wednesday morning. It downloads every file from the NHS England and Public
Health Scotland pages, builds each country's table, checks it, and commits the
CSV files if anything has changed. Each file is a complete snapshot of what is
currently published, including revisions to earlier months. Earlier versions
are in the git history.

Before overwriting a file, `update.R` checks that the new data:

- has every expected column, and one row per provider per period;
- has no missing month (England) or week (Scotland) between the first and the latest;
- still has every period the saved file has, and at least 95% as many rows;
- has no negative counts.

If any check fails, or a website can't be read, the file is left as it is and
the Action fails. GitHub emails you when a scheduled run fails. Open the run
on the repository's Actions tab to read the log.

To run the update by hand, use the Actions tab: choose "Update A&E data", then
"Run workflow".

## Running the update on your own computer

If the Action can't reach the NHS websites, run the same script locally from
this folder. Then commit and push the `data` folder:

```r
# Once:
install.packages(c("dplyr", "jsonlite", "readr", "remotes"))
remotes::install_github("HorridTom/nhsAEscraper")
```

```sh
Rscript update.R
git add data && git commit -m "Update A&E data" && git push
```

To use files you have already downloaded instead of downloading them again,
set `AE_ENGLAND_DIR` or `AE_SCOTLAND_DIR` to the folder that holds them. See
the top of `update.R`.

## Using the data

```r
england <- readr::read_csv(
  "https://raw.githubusercontent.com/HorridTom/AE-data/main/data/AE_Data_England.csv"
)
```

## Notes

- England `Perf_Typ1` and `Perf_All` are calculated from the counts as
  (attendances − breaches) / attendances. They are proportions, between 0 and 1.
- Scotland `Perf_4hr` is the percentage of attendances seen *within* 4 hours.
  `Perf_8hr` and `Perf_12hr` are the percentages of attendances that waited
  *over* 8 and 12 hours, as Public Health Scotland now publishes them.
- In a few weeks, a Scottish site appears twice: for example, the Queen
  Elizabeth University Hospital in the week it opened. Those rows are added
  together.
- GitHub turns off scheduled Actions in a public repository after 60 days
  with no activity. The weekly Scottish data normally keeps the repository
  active. If the schedule is ever turned off, turn it back on from the
  Actions tab.

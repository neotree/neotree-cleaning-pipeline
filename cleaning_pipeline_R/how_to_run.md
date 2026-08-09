# How to Run the Neotree Cleaning Pipeline

This folder is a self-contained copy of the pipeline with all input files
and data keys included.  No external dependencies are needed beyond R.

---

## Folder structure

```
cleaning_pipeline_4DSH/
|
+-- 00_setup/                      <- Configuration (edit COUNTRY, DATASET, CSV_FILEPATH here)
+-- 00a_pii_detection_removal/     <- PII removal (runs first, on raw data)
+-- 00b_rename_harmonised_columns/ <- Column renaming (optional post-processing)
+-- 00_build_dictionary/           <- Builds data dictionaries from web-editor keys
+-- 01-16_*/                       <- Cleaning, validation, and NA-coding modules
|
+-- run_pipeline.r                 <- Manual runner -- processes one file at a time
+-- run_all.r                      <- Batch runner  -- auto-processes ALL files in input/
|
+-- dictionaries/                  <- Generated dictionary .xlsx files (one per country x dataset)
+-- neotree_data_keys/
|   \-- downloaded/
|       +-- neotree_data_keys_zimbabwe/    <- data-keys-metadata.json + data-keys-usage.xlsx
|       \-- neotree_data_keys_malawi/      <- data-keys-metadata.json + data-keys-usage.xlsx
|
+-- input/                         <- Raw CSV files to clean (see naming convention below)
\-- output/                        <- All pipeline outputs land here (one sub-folder per run)
```

---

## Input file naming convention

Every CSV in `input/` must follow this pattern for the pipeline to recognise it:

```
{country}_{source}_{dataset}_{date}.csv
```

| Part | Values |
|------|--------|
| `country` | `mwi` (Malawi) \| `zim` (Zimbabwe) |
| `source` | `db` (direct PostgreSQL export) \| `mb` (Metabase export) |
| `dataset` | see table in Step 2 |
| `date` | `YYYYMMDD` for `db` files \| `YYYY-MM-DD` for `mb` files |

**Examples:**

```
mwi_db_admissions_20260501.csv
zim_mb_maternal_outcomes_2026-05-01.csv
zim_db_twenty_8_day_follow_up_20260501.csv
```

Files that do not match this pattern are reported but silently skipped by `run_all.r`.

---

## Step 1 -- Build / refresh dictionaries (run once, or after data-key updates)

Open R with the working directory set to this folder, then:

```r
setwd("/path/to/cleaning_pipeline_4DSH")
source("00_build_dictionary/00_build_dictionary_v8.r")
```

This generates one `dictionary_{country}_{dataset}.xlsx` file per supported combination
in the `dictionaries/` folder.  The script attempts every combination in `BUILD_PLAN`
and reports which ones were skipped (no matching scripts in the data-key export is normal
for some country x dataset pairs).

**You must run this step before running the pipeline for the first time, or whenever
the Neotree web-editor data keys are updated.**

---

## Step 2 -- Run the pipeline

### Option A -- Batch mode (recommended): process all files automatically

```r
setwd("/path/to/cleaning_pipeline_4DSH")
source("run_all.r")
```

`run_all.r` scans `input/`, parses every filename, and runs the full pipeline for each
recognised file automatically.  It prints a run plan before starting and a success/fail
summary at the end.

A file that fails does **not** stop the batch — the runner records the error and moves on
to the next file.  The end-of-run **failure summary** lists every failed file with its
dataset and the actual error message, so a per-file failure cannot be lost in the scroll:

```
Failure summary:
  [FAIL] input/mwi_db_dhis2_maternal_outcomes_202608041252.csv
         Dataset: MWI x database x dhis2_maternal_outcomes
         Error  : too few arguments
```

When every file completes it prints
`Failure summary: none - every file completed the full pipeline.`
Always check this line before treating a batch as successful — a missing `*_cleaned.csv`
is otherwise easy to overlook.

**Optional filters** (edit the top of `run_all.r`):

```r
# Process only Zimbabwe files:
RUN_ALL_FILTER <- "^zim_"

# Skip a specific file:
RUN_ALL_SKIP <- c("mwi_mb_combined_maternity_outcomes_2026-05-01.csv")
```

Leave both as their defaults (`NULL` and `character(0)`) to process every file.

---

### Option B -- Manual mode: process one file at a time

Open `00_setup/00_setup.r` and set the **User Configuration** block at the top:

```r
COUNTRY      <- "MWI"          # "MWI" or "ZIM"
DATASET      <- "admissions"   # see table below
DATA_SOURCE  <- "database"     # "database" or "metabase"
CSV_FILEPATH <- "input/mwi_db_admissions_20260501.csv"
```

Then run:

```r
setwd("/path/to/cleaning_pipeline_4DSH")
source("run_pipeline.r")
```

---

## Supported dataset types (for manual mode)

| `DATASET` value | Description | Available for |
|-----------------|-------------|---------------|
| `admissions` | Standard neonatal admissions | MWI, ZIM |
| `discharges` | Standard neonatal discharges | MWI, ZIM |
| `maternal_outcomes` | Birth / maternal outcomes | MWI, ZIM |
| `phc_admissions` | Primary Health Care admissions | MWI |
| `phc_discharges` | Primary Health Care discharges | MWI |
| `combined_maternity_outcomes` | All 3 maternal source files merged | MWI |
| `dhis2_maternal_outcomes` | DHIS2-linked maternal source only | MWI |
| `maternity_completeness` | Maternity completeness source only | MWI |
| `joined_admissions_discharges` | Admissions + discharges joined (uses admissions dict) | MWI, ZIM |
| `neolab` | Blood culture / laboratory dataset | MWI, ZIM |
| `baseline` | Retrospective baseline (combined admission+discharge form) | ZIM |
| `infections` | Longitudinal infection follow-up form | ZIM |
| `twenty_8_day_follow_up` | 28-day post-discharge follow-up | ZIM |

---

## Malawi maternal data — structure note

Zimbabwe has a single `maternal_outcomes` file.  Malawi is different: there are
**three source files** that are combined on the server into a single
`combined_maternity_outcomes` output file:

| Source file | `DATASET` |
|-------------|-----------|
| `mwi_*_maternal_outcomes_*.csv` | `maternal_outcomes` |
| `mwi_*_dhis2_maternal_outcomes_*.csv` | `dhis2_maternal_outcomes` |
| `mwi_*_maternity_completeness_*.csv` | `maternity_completeness` |
| `mwi_*_combined_maternity_outcomes_*.csv` | `combined_maternity_outcomes` |

`combined_maternity_outcomes` is the primary analysis file (directly comparable to ZIM
`maternal_outcomes`).  The three individual source files are cleaned separately for
traceability only.

---

## Current input files (May 2026)

| File | `COUNTRY` | `DATA_SOURCE` | `DATASET` |
|------|-----------|---------------|-----------|
| `mwi_db_admissions_20260501.csv` | `MWI` | `database` | `admissions` |
| `mwi_db_discharges_20260501.csv` | `MWI` | `database` | `discharges` |
| `mwi_db_combined_maternity_outcomes_20260501.csv` | `MWI` | `database` | `combined_maternity_outcomes` |
| `mwi_db_combined_maternity_outcomes_20260507.csv` | `MWI` | `database` | `combined_maternity_outcomes` |
| `mwi_db_maternal_outcomes_20260507.csv` | `MWI` | `database` | `maternal_outcomes` |
| `mwi_db_dhis2_maternal_outcomes_20260507.csv` | `MWI` | `database` | `dhis2_maternal_outcomes` |
| `mwi_db_maternity_completeness_20260507.csv` | `MWI` | `database` | `maternity_completeness` |
| `mwi_db_neolab_20260501.csv` | `MWI` | `database` | `neolab` |
| `mwi_db_phc_admissions_20260501.csv` | `MWI` | `database` | `phc_admissions` |
| `mwi_db_phc_discharges_20260501.csv` | `MWI` | `database` | `phc_discharges` |
| `mwi_mb_admissions_2026-05-01.csv` | `MWI` | `metabase` | `admissions` |
| `mwi_mb_discharges_2026-05-01.csv` | `MWI` | `metabase` | `discharges` |
| `mwi_mb_combined_maternity_outcomes_2026-05-01.csv` | `MWI` | `metabase` | `combined_maternity_outcomes` |
| `mwi_mb_Combined_Maternity_Outcomes_2026-05-07.csv` | `MWI` | `metabase` | `combined_maternity_outcomes` |
| `mwi_mb_Maternal_Outcomes_2026-05-07.csv` | `MWI` | `metabase` | `maternal_outcomes` |
| `mwi_mb_Dhis2_Maternal_Outcomes_2026-05-07.csv` | `MWI` | `metabase` | `dhis2_maternal_outcomes` |
| `mwi_mb_Maternity_Completeness_2026-05-07.csv` | `MWI` | `metabase` | `maternity_completeness` |
| `mwi_mb_neolab_2026-05-01.csv` | `MWI` | `metabase` | `neolab` |
| `mwi_mb_phc_discharges_2026-05-01.csv` | `MWI` | `metabase` | `phc_discharges` |
| `zim_db_admissions_20260501.csv` | `ZIM` | `database` | `admissions` |
| `zim_db_discharges_20260501.csv` | `ZIM` | `database` | `discharges` |
| `zim_db_maternal_outcomes_20260501.csv` | `ZIM` | `database` | `maternal_outcomes` |
| `zim_db_neolab_20260501.csv` | `ZIM` | `database` | `neolab` |
| `zim_db_baseline_20260501.csv` | `ZIM` | `database` | `baseline` |
| `zim_db_infections_20260501.csv` | `ZIM` | `database` | `infections` |
| `zim_db_twenty_8_day_follow_up_20260501.csv` | `ZIM` | `database` | `twenty_8_day_follow_up` |
| `zim_mb_admissions_2026-05-01.csv` | `ZIM` | `metabase` | `admissions` |
| `zim_mb_discharges_2026-05-01.csv` | `ZIM` | `metabase` | `discharges` |
| `zim_mb_maternal_outcomes_2026-05-01.csv` | `ZIM` | `metabase` | `maternal_outcomes` |
| `zim_mb_neolab_2026-05-01.csv` | `ZIM` | `metabase` | `neolab` |
| `zim_mb_baseline_2026-05-01.csv` | `ZIM` | `metabase` | `baseline` |
| `zim_mb_infections_2026-05-01.csv` | `ZIM` | `metabase` | `infections` |
| `zim_mb_twenty_8_day_follow_up_2026-05-01.csv` | `ZIM` | `metabase` | `twenty_8_day_follow_up` |

> **Metabase capitalisation:** some metabase files use Title_Case in the dataset
> part of the filename (e.g. `Combined_Maternity_Outcomes`).  `run_all.r` handles
> this automatically — the dataset name is lowercased during parsing, so
> `Combined_Maternity_Outcomes` → `combined_maternity_outcomes` ✓

> **Note:** `mwi_mb_pch_admissions_2026-05-01.csv` has a typo (`pch` instead of `phc`).
> `run_all.r` will report it in the skip list.  Rename the file to
> `mwi_mb_phc_admissions_2026-05-01.csv` to have it processed automatically.

---

## Output file flags

Several output files are optional.  Their defaults are set in the **User
Configuration** block at the top of `00_setup/00_setup.r`:

| Flag | Default | Controls |
|------|---------|----------|
| `SAVE_DEIDENTIFIED` | `FALSE` | `*_deidentified.csv` — raw data with PII removed (Module 00a) |
| `SAVE_STAGE1_CHECKPOINT` | `FALSE` | `*_cleaned_stage1.rds` — mid-pipeline checkpoint after Module 10 |
| `SAVE_HARMONISED` | `FALSE` | `*_cleaned_harmonised.csv` + `.rds` — snake_case column names (Module 00b) |
| `SAVE_NA_CODED` | `TRUE` | `*_na_coded.csv` — cleaned data with NA cells replaced by reason codes |
| `SAVE_NA_REASONS_LONG` | `FALSE` | `*_na_reasons_long.csv.gz` — long-format NA reasons, one row per NA cell |

To change a flag for a single manual run, edit the line in `00_setup.r`.  Flags
set in `00_setup.r` apply to all batch runs automatically (unless overridden at
the top of `run_all.r`).

---

## Outputs

Each pipeline run creates a sub-folder in `output/` named after the input file stem.
All outputs for that run — cleaned files, reports, and the run log — are written there.

```
output/
└── zim_db_admissions_20260501/
    ├── zim_db_admissions_20260501.log          <- run log
    ├── zim_db_admissions_20260501_cleaned.csv
    ├── zim_db_admissions_20260501_cleaned.rds
    ├── zim_db_admissions_20260501_na_reasons.csv.gz
    ├── zim_db_admissions_20260501_na_reasons_summary.csv
    ├── zim_db_admissions_20260501_na_coded.csv      <- on by default
    └── reports/
        ├── 00a_pii_audit_report.txt
        ├── 10_duplicate_row_removal_report.txt
        ├── 16_na_reason_coding_summary.txt
        └── ...
```

| File | Default | Description |
|------|---------|-------------|
| `*_cleaned.csv` | always | Final cleaned dataset |
| `*_cleaned.rds` | always | Final cleaned dataset (R binary) |
| `*_na_reasons.csv.gz` | always | NA reason codes, wide format (gzip-compressed) |
| `*_na_reasons_summary.csv` | always | Per-variable completeness summary (plain CSV) |
| `*.log` | always | Pipeline log for this run |
| `*_na_coded.csv` | **on** | Cleaned data with NA cells replaced by reason codes (-6/-7/-8/-9) |
| `*_deidentified.csv` | off | Raw data with PII removed (Module 00a) |
| `*_cleaned_stage1.rds` | off | Mid-pipeline checkpoint after deduplication (Module 10) |
| `*_cleaned_harmonised.csv` | off | With snake_case harmonised column names (Module 00b) |
| `*_cleaned_harmonised.rds` | off | Harmonised dataset (R binary) |
| `*_na_reasons_long.csv.gz` | off | NA reason codes, long format — one row per NA cell |
| `reports/` | always | Per-module text reports |

---

## Troubleshooting

**"Dictionary not found"** -- Run Step 1 to build dictionaries first.

**"DATASET must be one of..."** -- Use the exact `DATASET` string from the table above
(lowercase with underscores, e.g. `twenty_8_day_follow_up` not `28 day follow up`).

**PHC dictionary falls back to standard dict** -- Expected if the web-editor data-key
export for that country contains no PHC script titles.  The pipeline logs:
*"No specific dictionary for ... falling back to admissions dictionary."*

**`baseline` / `infections` / `twenty_8_day_follow_up` dictionaries not found** -- Run
Step 1 after confirming the ZIM data-key export contains scripts whose titles match
`Baseline|Retrospective`, `Infection|NeoInfect`, or `28.?Day|Follow.?Up` respectively.
Adjust the regex in `DATASET_FILTERS` in `00_build_dictionary/00_build_dictionary_v8.r`
if the actual script titles differ.

**File skipped by `run_all.r` as "unrecognised dataset type"** -- The parsed dataset
name does not appear in `KNOWN_DATASETS` at the top of `run_all.r`.  Either fix a
filename typo or add the new type to both `KNOWN_DATASETS` (in `run_all.r`) and
`VALID_DATASETS` (in `00_setup/00_setup.r`).

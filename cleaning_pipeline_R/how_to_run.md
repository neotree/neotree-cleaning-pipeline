# How to run the Neotree cleaning pipeline

This guide covers installation, input files, the two runners, the settings, the outputs, the dictionary rebuild and the tests. What each module does is described in [`readme.md`](readme.md) and in the `README.md` of each module folder.

All commands are given from the pipeline folder, `cleaning_pipeline_R/`. The runners set the working directory to their own folder when they start, so they can be launched from any directory.

## Requirements

- R.
- Twelve CRAN packages: `jsonlite`, `readr`, `readxl`, `writexl`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `purrr`, `logger`, `janitor`, `tibble`. `required_packages.txt` lists them with their minimum versions.
- `openxlsx`, for the dictionary scripts other than `00_build_dictionary.r`. `install_packages.r` does not install it.

### Installing the packages

```
Rscript install_packages.r
```

or, in an R session:

```r
source("install_packages.r")
```

The script installs the missing packages with their dependencies from `https://cloud.r-project.org`, then loads each required package and prints `[OK]` or `[FAIL]` for it. If a package fails to load, the script prints the `install.packages()` call to run by hand.

## Input files

Place the raw CSV files in `input/`. `run_all.r` processes a file when its name has one of these forms:

```
<country>_<dataset>_<date>.csv
<country>_<source>_<dataset>_<date>.csv
```

| Part | Accepted values |
|------|-----------------|
| `country` | `zim` or `mwi` |
| `source` | `db` or `mb`. Optional; it does not change how the file is read. |
| `dataset` | `admissions`, `discharges`, `maternal_outcomes`, `phc_admissions`, `phc_discharges`, `combined_maternity_outcomes`, `dhis2_maternal_outcomes`, `maternity_completeness`, `joined_admissions_discharges`, `neolab`, `baseline`, `infections`, `twenty_8_day_follow_up` |
| `date` | `YYYY-MM-DD`, `YYYYMMDD` or `YYYYMMDDHHMM` |

Examples:

```
zim_admissions_2026-01-31.csv
zim_discharges_2026-01-31.csv
mwi_phc_admissions_2026-01-31.csv
mwi_db_neolab_20260131.csv
zim_mb_maternal_outcomes_202601311030.csv
```

The file extension is `.csv` in lower case.

Two modules read a second file from the same folder as the input file:

| Module | Second file | Found by |
|--------|-------------|----------|
| 02 | The other half of an admissions/discharges pair (`admissions` with `discharges`, `phc_admissions` with `phc_discharges`). | The input file name with the dataset swapped; if that file is absent, the last file in sorted order named `<country>_[db_\|mb_]<paired dataset>_<date>.csv`. |
| 14a | The admissions file, when the dataset is `neolab`. | The input file name with `neolab` replaced by `admissions`. |

Both modules run without the second file. Module 02 then gives its repairs the status `unchecked`, and Module 14a leaves missing dates unresolved.

Each dataset needs a dictionary, `dictionaries/dictionary_<country>_<dataset>.xlsx`, or a fallback defined in `00_setup.r` (see [`00_setup/README.md`](00_setup/README.md)).

## Running a batch: `run_all.r`

```
Rscript run_all.r
```

or, in an R session:

```r
source("run_all.r")
```

`run_all.r` does the following.

1. Lists the `.csv` files in `input/` and applies the two filters below.
2. Reads the country, source and dataset from each file name. A file is skipped when its name has neither accepted form (`filename does not match expected pattern`) or when its dataset is not in the list (`unrecognised dataset type '<dataset>' (not in KNOWN_DATASETS)`).
3. Prints the run plan: the files to process and the files skipped, with the reason.
4. For each file, sets `COUNTRY`, `DATASET`, `DATA_SOURCE` and `CSV_FILEPATH`, sets `DICT_FILEPATH`, `OUTPUT_CSV`, `OUTPUT_RDS`, `REPORT_DIR` and `NEOTREE_SCRIPTS_DIR` to `NULL` and `OUTPUT_DIR` to `"output"`, and sources `run_pipeline.r`.
5. If a file fails, records the error message and continues with the next file.
6. Removes the objects of the run from the global environment before the next file.
7. Prints the batch summary: the number of files that succeeded and failed, the total time, each failed file with its error message, and each file that succeeded with its country, detected export style and dataset.

### Batch filters

Both are set near the top of `run_all.r`.

| Setting | Default | Effect |
|---------|---------|--------|
| `RUN_ALL_FILTER` | `NULL` | A regular expression applied to the file name. Only matching files are kept. `NULL` keeps every file. Example: `"^zim_"`, or `"admissions\|discharges"`. |
| `RUN_ALL_SKIP` | `character(0)` | File names to leave out, written in full. |

## Running one file: `run_pipeline.r`

`run_pipeline.r` runs the modules in order for the file named in `CSV_FILEPATH`. The settings are defined in the user configuration block of `00_setup/00_setup.r`. Each one is assigned only if it does not already exist, so there are two ways to set them.

Edit the defaults in `00_setup/00_setup.r`, then:

```
Rscript run_pipeline.r
```

Or set them in an R session before sourcing the runner:

```r
COUNTRY      <- "ZIM"
DATASET      <- "admissions"
CSV_FILEPATH <- "input/zim_admissions_2026-01-31.csv"
source("run_pipeline.r")
```

A setting defined in the session keeps its value for later runs in that session. This includes the paths that `00_setup.r` resolves when they are `NULL`. Before running a second file in the same session, set `DICT_FILEPATH`, `OUTPUT_CSV`, `OUTPUT_RDS`, `REPORT_DIR` and `NEOTREE_SCRIPTS_DIR` back to `NULL` and remove `SKIP_DEDUP_STAGE2` and `DEDUP_MODE`, as `run_all.r` does, or start a new session.

When it finishes, `run_pipeline.r` prints the time taken, the paths of the cleaned CSV and RDS, the number of rows and columns, and the report folder.

## Settings

All settings below are in the user configuration block of `00_setup/00_setup.r`.

### Identity and paths

| Setting | Default | Effect |
|---------|---------|--------|
| `COUNTRY` | `"ZIM"` | `"ZIM"` or `"MWI"`. |
| `DATASET` | `"admissions"` | One of the datasets listed under *Input files*. |
| `DATA_SOURCE` | `"auto"` | Accepts `auto`, `database`, `metabase`, `mixed` or `unknown`. It does not change how the file is parsed and is replaced by the export style detected from the file. |
| `CSV_FILEPATH` | a file in `input/` | Path of the raw CSV. |
| `DICT_FILEPATH` | `NULL` | Path of the dictionary. `NULL` gives `dictionaries/dictionary_<country>_<dataset>.xlsx`, or the fallback dictionary when that file does not exist. |
| `OUTPUT_DIR` | `"output"` | Base folder for everything the pipeline writes. The run folder is `<OUTPUT_DIR>/<file stem>/`. |
| `OUTPUT_CSV`, `OUTPUT_RDS` | `NULL` | Paths of the cleaned outputs. `NULL` gives `<file stem>_cleaned.csv` and `<file stem>_cleaned.rds` in the run folder. |
| `REPORT_DIR` | `NULL` | `NULL` gives `reports/` in the run folder. A path writes the reports there. `FALSE` or `""` suppresses the module reports. |
| `NEOTREE_SCRIPTS_DIR` | `NULL` | Folder holding `zim-scripts/` and `mwi-scripts/`, read by Module 16. `NULL` gives `neotree_scripts/` in the pipeline folder. If the folder does not exist, Module 16 is not run. |

### Output flags

| Setting | Default | Effect when `TRUE` |
|---------|---------|--------------------|
| `SAVE_DEIDENTIFIED` | `FALSE` | Module 00a writes `<file stem>_deidentified.csv`. Personal data is removed in either case. |
| `SAVE_STAGE1_CHECKPOINT` | `FALSE` | Module 10 writes `<file stem>_cleaned_stage1.rds`. |
| `SAVE_HARMONISED` | `FALSE` | Module 00b runs and writes `<file stem>_cleaned_harmonised.csv` and `.rds`. |
| `SAVE_NA_CODED` | `TRUE` | Module 16 writes `<file stem>_cleaned_na_coded.csv`. |
| `SAVE_NA_REASONS_LONG` | `FALSE` | Module 16 writes `<file stem>_cleaned_na_reasons_long.csv.gz`. The table holds the raw value of every coded cell and is checked by the personal-data guard before it is written; the run stops if a raw value matches a value pattern. |

### Module behaviour

| Setting | Default | Effect |
|---------|---------|--------|
| `SKIP_DEDUP_STAGE2` | `TRUE` when the dataset is `infections` or `neolab`, otherwise `FALSE` | `TRUE` makes Module 10 skip its patient-level stage, so several rows per patient are kept. Module 15 then keeps one row per `uid`, `facility` and `uniquekey` instead of one per `uid` and `facility`. |
| `DEDUP_MODE` | `"episode"` | Stage 2 of Module 10 for `admissions`, `discharges`, `phc_admissions`, `phc_discharges`, Zimbabwe `maternal_outcomes` and Malawi `combined_maternity_outcomes`. `"current"` keeps one row per `uid` and `facility`. `"episode"` collapses rows only when they are the same record sent more than once, keeps every other row and adds `baby_id`, `stay_no` (not in the maternal files) and flag columns (see the [Module 10 README](10_remove_duplicate_rows/README.md)); Modules 11 to 16 then key rows on `uid`, `facility` and `uniquekey`. In episode mode each admissions file must be run before its discharges file (`phc_admissions` before `phc_discharges`). Other datasets are not affected. |
| `RESOLVE_NEOLAB_DATEBCT` | `TRUE` | Module 14a adds `datebct_resolved` and `datebct_source`. Used only when the dataset is `neolab`. `FALSE` adds no columns. |
| `UID_REPAIR_SEPARATORS` | `c(",", "/")` | Characters Module 02 treats as a mistyped hyphen in a `uid`. |
| `RESERVED_COLUMN_RENAMES` | for `phc_discharges`: `facility.value` to `facilityname.value`, `facility.label` to `facilityname.label` | Per dataset, standardised column names that Module 01 renames so that they do not share a name with a key column. |
| `LABEL_VALUE_RULES` | for Malawi `admissions`: `antenatalcare` with the parser `anc_visit_count` | Per country and dataset, fields whose answer Module 05 reads from the `.label` column when the `.value` column holds no valid value. |

Two further settings are entries of the `cfg` list, set where `cfg` is built in `00_setup/00_setup.r`. Both are empty lists by default.

| Setting | Format | Effect |
|---------|--------|--------|
| `cfg$value_mappings` | `list(column = list(canonical = c("alias1", "alias2")))` | Module 13 replaces each alias with the canonical value in that column. |
| `cfg$values_to_delete` | `list(column = c("value1", "value2"))` | Module 13 sets each listed value to `NA` in that column. |

### Settings in a batch

`run_all.r` sets the identity and path settings for each file as described above. It removes the output flags, `SKIP_DEDUP_STAGE2`, `UID_REPAIR_SEPARATORS`, `RESERVED_COLUMN_RENAMES` and `LABEL_VALUE_RULES` from the global environment after each file, so for a batch these are changed by editing their defaults in `00_setup/00_setup.r`. The exception is `DEDUP_MODE`, which `run_all.r` sets for every file from `RUN_ALL_DEDUP_MODE`, near the top of the script (default `"episode"`). Files run in name order, so an admissions file runs before the discharges file of the same country and source.

## Outputs

Each input file has its own run folder, `output/<file stem>/`.

```
output/zim_admissions_2026-01-31/
  zim_admissions_2026-01-31_cleaned.csv
  zim_admissions_2026-01-31_cleaned.rds
  zim_admissions_2026-01-31_cleaned_na_coded.csv
  zim_admissions_2026-01-31_cleaned_na_reasons.csv.gz
  zim_admissions_2026-01-31_cleaned_na_reasons_summary.csv
  zim_admissions_2026-01-31.log
  00a_pii_removal_complete.dcf
  reports/
```

| File | Content |
|------|---------|
| `_cleaned.csv` | Cleaned dataset. Date-times are written as `YYYY-MM-DD HH:MM:SS` (UTC) and `NA` as an empty field. |
| `_cleaned.rds` | Cleaned dataset with typed columns. |
| `_cleaned_na_coded.csv` | Cleaned dataset as text, with every empty cell replaced by its reason code (`-6`, `-7`, `-8` or `-9`). |
| `_cleaned_na_reasons.csv.gz` | The reason code of every empty cell, in the layout of the cleaned dataset. |
| `_cleaned_na_reasons_summary.csv` | One row per variable: `n_total`, `n_present`, `n_missing`, `pct_missing`, `n_not_applicable`, `n_invalid`, `n_unknown`, `n_redacted`. |
| `.log` | Run log, at level INFO and above. Messages are appended to an existing log. |
| `00a_pii_removal_complete.dcf` | Completion marker of Module 00a, read by the personal-data guard. |

The optional files (`_deidentified.csv`, `_cleaned_stage1.rds`, `_cleaned_harmonised.csv` and `.rds`, `_cleaned_na_reasons_long.csv.gz`) are written to the same folder when their flags are `TRUE`. An admissions run with `DEDUP_MODE` set to `"episode"` also writes `_episode_keys.rds`, which the discharges run reads; it holds `uid` values.

### Reports

The reports are text files in `reports/`. They hold counts and column names; the exceptions are stated in the table.

| Report | Written by | Content |
|--------|-----------|---------|
| `00_pipeline_report.txt` | `run_pipeline.r` | A header with the country, dataset, detected export style and input file name, followed by every `.txt` file of the folder. |
| `00a_pii_audit_report.txt` | Module 00a | Columns removed, quasi-identifier columns, number of values redacted per column, matches in exempt columns. |
| `00c_undocumented_columns.txt` | Module 00 | Input columns that are not in the dictionary. Written only when there are any. |
| `01_column_standardisation_report.txt` | Module 01 | Names standardised, reserved renames, `.parentKey` columns dropped. |
| `02_frame_shift_report.txt` | Module 02 | `uid` repairs with their status, rows removed, UIDs without a hyphen. Lists `uid` values. |
| `02_frame_shift_dirty_rows.csv` | Module 02 | The rows removed for an empty `uid`. Written only when a row is removed. |
| `03_duplicate_column_report.txt` | Module 03 | Duplicate column names merged. |
| `04_dictionary_cleaning_report.txt` | Module 04 | Per column, each replaced value with its replacement and each unresolved value, with the number of records. |
| `05_forward_fill_placeholder_report.txt` | Module 05 | Values filled per column pair; for each label-to-value rule, the number of rows in each class (valid value, count read from the label, unresolved and why). |
| `06_forward_fill_numeric_datetime_report.txt` | Module 06 | Values filled per column. |
| `07_drop_columns_report.txt` | Module 07 | Per prefix, the column kept and the columns dropped. |
| `08_autopopulated_columns_report.txt` | Module 08 | Number of columns. |
| `09_data_type_assignment_report.txt` | Module 09 | Columns per type and values read by each parsing rule. |
| `10_duplicate_row_removal_report.txt` | Module 10 | Rows before and after, rows removed at each stage. |
| `11_numeric_validation_report.txt` | Module 11 | Values changed at each step and out-of-range counts per column. |
| `12_boolean_validation_report.txt` | Module 12 | Values set to `TRUE` or `FALSE` and to `NA`. |
| `13_categorical_validation_report.txt` | Module 13 | Values replaced, removed and set to `NA`. |
| `14_datetime_validation_report.txt` | Module 14 | Values parsed and set to `NA`; dates placed in `hepbdate_date`. |
| `14a_resolve_neolab_datebct_report.txt` | Module 14a | Rows per `datebct_source`. `neolab` dataset only. |
| `15_final_merge_summary.txt` | Module 15 | Input and output paths, final numbers of rows and columns. |
| `15b_maternal_age_summary.txt` | Module 15 | Rows per `mat_age_source`. Written when the maternal-age columns are derived. |
| `00b_harmonised_rename_report.txt` | Module 00b | Columns renamed and unchanged. Written when `SAVE_HARMONISED` is `TRUE`. |
| `16_na_reason_coding_summary.txt` | Module 16 | Cells per reason code and the variables with most empty cells. |

## Messages that stop a run

| Message | Raised by | Cause and action |
|---------|-----------|------------------|
| `No CSV files found in 'input/'. Nothing to do.` | `run_all.r` | `input/` holds no `.csv` file. |
| `Nothing to process. Exiting.` | `run_all.r` | Every file was filtered out or skipped. The reasons are listed above the message. |
| `COUNTRY must be 'ZIM' or 'MWI'` | Module 00 | `COUNTRY` has another value. |
| `DATASET must be one of: ...` | Module 00 | `DATASET` is not an accepted dataset. |
| `DATA_SOURCE must be 'auto', 'database' or 'metabase'` | Module 00 | `DATA_SOURCE` has a value that is not accepted. |
| `Dictionary not found: '<path>'` | Module 00 | The dictionary workbook does not exist. Build it with `00_build_dictionary/00_build_dictionary.r`. |
| `Module 01: df_raw not found` | Module 01 | Module 00a has not run in the session. Run `run_pipeline.r` or `run_all.r`. |
| `PII guard [<stage>]: Module 00a completion marker not found` | `assert_pii_removed()` | Module 00a has not run for this input file. Run the full pipeline. |
| `PII guard [<stage>]: Module 00a completion marker is unreadable or incomplete` | `assert_pii_removed()` | The marker file lacks a required field. Run the full pipeline. |
| `PII guard [<stage>]: the 00a marker was written for a different input` | `assert_pii_removed()` | The marker in the run folder names another input path. Run the full pipeline. |
| `PII guard [<stage>]: the 00a marker ... is older than the input file` | `assert_pii_removed()` | The input file was modified after Module 00a ran. Run the full pipeline. |
| `PII guard [<stage>]: the input file has changed since Module 00a ran` | `assert_pii_removed()` | The size or modification time of the input file differs from the marker. Run the full pipeline. |
| `PII guard [<stage>]: the dictionary ... has changed since Module 00a ran` | `assert_pii_removed()` | The dictionary checksum differs from the marker. Run the full pipeline. |
| `PII guard [<stage>]: the data frame was not produced by the Module 00a run recorded in the marker` | `assert_pii_removed()` | The data frame given to Module 01 does not carry the run id of the marker. Run the full pipeline. |
| `PII guard [<stage>]: ... column(s) match the dictionary confidential flag (Tier 1) and ... match a PII name pattern (Tier 2)` | `assert_pii_removed()` | A column about to be written is a personal-data column. The message lists the column names. Nothing is written. |
| `PII guard [<stage>]: ... column/pattern combination(s) contain PII-like values` | `assert_pii_removed()` | A value about to be written matches a value pattern. The message lists the columns, the pattern names and the counts. Nothing is written. |
| `df_clean not found` | Modules 00b and 16 | The module was sourced before Module 15. |
| `cfg$neotree_scripts_dir not set or directory not found` | Module 16 | Module 16 was sourced directly and the scripts folder does not exist. |
| `Cannot read raw CSV` | Module 16 | The input CSV could not be read again. |
| `Module 16: the NA summary 'variable' column contains entries that are not column names of the cleaned dataset` | Module 16 | The summary table failed its check before the guard. Nothing is written. |

`<stage>` names the point of the check: `01_input`, `02_frame_shift_rows`, `10_stage1_checkpoint`, `15_cleaned_output`, `00b_harmonised_output`, `16_na_reasons_wide`, `16_na_reasons_long`, `16_na_reasons_summary` or `16_na_coded_output`.

The banner `DICT COVERAGE WARNING` on the console does not stop the run. It lists input columns that the dictionary does not cover; these pass through as text. Rebuilding the dictionary from a data-key export that includes them removes the warning.

## Rebuilding the dictionaries

The dictionaries in `dictionaries/` are generated files. They are rebuilt when a new data-key export is placed in `neotree_data_keys/downloaded/`, when a constant of the build script or a row of `user_ranges.xlsx` is changed, or when new Neotree script files are placed in `neotree_scripts/`. The data keys and the script metadata are downloaded from the Neotree web editors with a Neotree account (see the README file in each folder).

`00_build_dictionary.r` runs the whole build: the base dictionaries, the two enrichment steps, the user dictionaries, the removal of staff names and a final check. The other scripts below can still be run one by one.

```r
source("00_build_dictionary/00_build_dictionary.r")
source("00_build_dictionary/00c_enrich_dictionary_from_scripts.r")
source("00_build_dictionary/00e_enrich_from_public_dictionary.r")
source("00_build_dictionary/00d_build_user_dictionary.r")
source("00_build_dictionary/validate_dictionaries.r")
```

The first script writes the workbooks the cleaning modules read. The next three write documentation workbooks, and the last checks the result. The steps, their inputs and the constants that hold permanent changes are described in [`00_build_dictionary/README.md`](00_build_dictionary/README.md).

## Tests

Two test scripts are in `tests/`. They are run with `Rscript` from the pipeline folder:

```
Rscript tests/test_input_naming.r
Rscript tests/test_pii_guard.r
Rscript tests/test_label_value_recovery.r
```

Both generate synthetic input from the dictionaries (column names and value-map codes) and run in a temporary copy of the pipeline under `tempdir()`. They do not read or write `input/` or `output/`. Both need `readr` and `readxl`, and both start full pipeline runs in separate R processes.

| Script | Covers |
|--------|--------|
| `test_input_naming.r` | File-name parsing in `run_all.r`; detection of the export style; resolution of the paired admissions/discharges file; a batch run on synthetic files in database, Metabase and mixed style; the datetime and number parsers and the boolean tokens of `00_setup.r`; the list encoding of Module 04; the derived column `hepbdate_date` of Module 14. |
| `test_dedup_episode.r` | Episode mode of Module 10 on made-up admissions, discharges and births: collapsing only true repeats, baby and stay assignment, discharge linking, flags, known totals, the admissions key file and the datasets covered. |
| `test_label_value_recovery.r` | The antenatal care parser of Module 05; a run on a synthetic Malawi admissions file with an empty value and a filled label, checking `antenatalcare`, `antenatalcare_source` and `antenatalcare_category` row by row; the same labels in a Zimbabwe file, where no rule applies. |
| `test_pii_guard.r` | The column-name and value patterns; a full run with the expected removals and redactions; the guard stopping when Module 00a is skipped, when the marker does not match the input file or dictionary, and when a personal-data column or value is added before the Module 15 write; the same checks through `run_all.r`. |

Each script prints `[PASS]` or `[FAIL]` for every check and a summary line. The exit status is 0 when every check passes and 1 otherwise. After a failure the script prints the folder that holds the logs of the test runs.

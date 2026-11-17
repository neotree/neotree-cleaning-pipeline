# Neotree cleaning pipeline

## Purpose

The pipeline cleans raw Neotree data exports for Zimbabwe (`ZIM`) and Malawi (`MWI`). It takes one CSV file per dataset, removes personal data, standardises the columns and values against a data dictionary, assigns a type to every column, validates the values, and writes a cleaned dataset together with reports and a code for every empty cell.

The pipeline is written in R and is made of numbered modules that run in a fixed order. Each input file is processed on its own.

## Folder layout

```
cleaning_pipeline_R/
  run_all.r                  batch runner: every recognised file in input/
  run_pipeline.r             single-file runner: runs the modules in order
  install_packages.r         installs the required CRAN packages
  required_packages.txt      list of the required packages
  readme.md                  this file
  how_to_run.md              run guide

  00_setup/                  settings, shared helpers, configuration list
  00a_pii_detection_removal/ ... 16_na_reason_coding/
                             one folder per module: the script and its README.md
  00_build_dictionary/       scripts that build and check the dictionaries

  dictionaries/              data dictionaries read by the pipeline (.xlsx)
  user_dictionaries/         dictionaries for data users (.xlsx)
  og_dictionaries/           public data dictionary read by the dictionary build
  neotree_data_keys/         data-key exports read by the dictionary build (downloaded)
  neotree_scripts/           Neotree script metadata, zim-scripts/ and mwi-scripts/ (downloaded)
  tests/                     test scripts

  input/                     raw CSV files to clean
  output/                    everything the pipeline writes
```

## Modules

`run_pipeline.r` sources the modules in this order. Every module sources `00_setup/00_setup.r` first, so the settings and the configuration list `cfg` are available to each one.

| Module | Folder | What it does |
|--------|--------|--------------|
| 00 | [`00_setup`](00_setup/README.md) | Loads the libraries, the settings and the dictionary; defines the shared parsers and the personal-data guard; builds `cfg`. |
| 00a | [`00a_pii_detection_removal`](00a_pii_detection_removal/README.md) | Reads the raw CSV, removes columns holding personal data, blanks values that look like personal data, writes the audit report and the completion marker. |
| 01 | [`01_standardise_column_headers`](01_standardise_column_headers/README.md) | Gives every column a standard lower-case name and drops the `.parentKey` columns. |
| 02 | [`02_frame_shift_correction`](02_frame_shift_correction/README.md) | Repairs `uid` values in which another character replaces the hyphen and removes rows with an empty `uid`. |
| 03 | [`03_duplicate_column_merging`](03_duplicate_column_merging/README.md) | Merges columns that share a name into one column. |
| 04 | [`04_dictionary_value_cleaning`](04_dictionary_value_cleaning/README.md) | Rewrites categorical values as the canonical codes of the dictionary where a value matches exactly one code. |
| 05 | [`05_forward_fill_placeholders`](05_forward_fill_placeholders/README.md) | Reads configured fields from their label column into the empty value column (antenatal care visits in Malawi admissions), then copies fixed placeholder words from a label column into its empty value column. |
| 06 | [`06_forward_fill_numeric_datetime`](06_forward_fill_numeric_datetime/README.md) | Fills empty values from the paired label column where the label is a number or a datetime, then drops the paired label columns. |
| 07 | [`07_drop_label_columns`](07_drop_label_columns/README.md) | Drops the remaining label columns and keeps one column per variable prefix. |
| 08 | [`08_drop_autopopulated_columns`](08_drop_autopopulated_columns/README.md) | Passes the data through unchanged and writes a report. |
| 09 | [`09_data_type_assignment`](09_data_type_assignment/README.md) | Converts every column from text to the type given in the dictionary. |
| 10 | [`10_remove_duplicate_rows`](10_remove_duplicate_rows/README.md) | Removes duplicate rows, first per visit and then per patient, keeping the most complete row. |
| 11 | [`11_numeric_validation`](11_numeric_validation/README.md) | Validates numeric columns, converts weights to grams and applies the dictionary ranges. |
| 12 | [`12_boolean_validation`](12_boolean_validation/README.md) | Sets every boolean column to `TRUE`, `FALSE` or `NA`. |
| 13 | [`13_categorical_object_validation`](13_categorical_object_validation/README.md) | Cleans categorical and free-text columns and turns missing-value text into `NA`. |
| 14 | [`14_datetime_validation`](14_datetime_validation/README.md) | Reads every datetime column as a date-time and sets unrecognised values to `NA`. |
| 14a | [`14a_resolve_neolab_datebct`](14a_resolve_neolab_datebct/README.md) | For the `neolab` dataset, fills missing blood-culture dates from the admissions file, in new columns. |
| 15 | [`15_final_merge_output`](15_final_merge_output/README.md) | Joins the validated columns, strips the column-name suffixes, adds derived columns and writes the cleaned CSV and RDS. |
| 00b | [`00b_rename_harmonised_columns`](00b_rename_harmonised_columns/README.md) | Writes a copy of the cleaned dataset with harmonised column names. Runs only when `SAVE_HARMONISED` is `TRUE`. |
| 16 | [`16_na_reason_coding`](16_na_reason_coding/README.md) | Gives every empty cell of the cleaned dataset a reason code and writes the companion files. |

After the last module, `run_pipeline.r` joins the text reports of the run into one file.

## Input files

Raw CSV files are placed in `input/`. `run_all.r` recognises a file when its name has one of two forms:

```
<country>_<dataset>_<date>.csv
<country>_<source>_<dataset>_<date>.csv
```

| Part | Accepted values |
|------|-----------------|
| `country` | `zim` or `mwi` |
| `source` | `db` or `mb`. Optional. It is recorded in the run plan and does not change how the file is read. |
| `dataset` | `admissions`, `discharges`, `maternal_outcomes`, `phc_admissions`, `phc_discharges`, `combined_maternity_outcomes`, `dhis2_maternal_outcomes`, `maternity_completeness`, `joined_admissions_discharges`, `neolab`, `baseline`, `infections`, `twenty_8_day_follow_up` |
| `date` | `YYYY-MM-DD`, `YYYYMMDD` or `YYYYMMDDHHMM` |

Examples: `zim_admissions_2026-01-31.csv`, `mwi_phc_discharges_2026-01-31.csv`, `mwi_db_admissions_20260131.csv`, `zim_mb_maternal_outcomes_202601311030.csv`.

A file whose name has neither form, or whose dataset is not in the list, is listed as skipped and the other files are still processed.

The pipeline reads exports with database-style headers (`unique_key`) and with Metabase-style headers (`Unique Key`), and values in either style or a mixture. `00_setup.r` detects the style of each file and records it in the log; the style does not change how the file is parsed.

## Outputs

Everything written for one input file goes to `output/<file stem>/`, where `<file stem>` is the input file name without `.csv`.

| File | Content | Written |
|------|---------|---------|
| `<file stem>_cleaned.csv` | Cleaned dataset. Date-times as `YYYY-MM-DD HH:MM:SS` (UTC); `NA` as an empty field. | Always |
| `<file stem>_cleaned.rds` | Cleaned dataset with typed columns. | Always |
| `<file stem>_cleaned_na_coded.csv` | Cleaned dataset, every column as text, with each empty cell replaced by its reason code. | When `SAVE_NA_CODED` is `TRUE` (default) |
| `<file stem>_cleaned_na_reasons.csv.gz` | Same rows and columns as the cleaned dataset; each cell holds the reason code where the cleaned cell is empty. | When Module 16 runs |
| `<file stem>_cleaned_na_reasons_summary.csv` | One row per variable: number of rows, values present and missing, and cells per reason code. | When Module 16 runs |
| `<file stem>_cleaned_na_reasons_long.csv.gz` | One row per coded cell, with the raw value. | When `SAVE_NA_REASONS_LONG` is `TRUE` |
| `<file stem>_cleaned_harmonised.csv`, `.rds` | Cleaned dataset with harmonised column names. | When `SAVE_HARMONISED` is `TRUE` |
| `<file stem>_cleaned_stage1.rds` | Data frame after duplicate-row removal. | When `SAVE_STAGE1_CHECKPOINT` is `TRUE` |
| `<file stem>_deidentified.csv` | Raw data after removal of personal data, before any cleaning. | When `SAVE_DEIDENTIFIED` is `TRUE` |
| `<file stem>.log` | Run log. Messages are appended. | Always |
| `00a_pii_removal_complete.dcf` | Completion marker of Module 00a. | Always |
| `reports/` | One text report per module, and `00_pipeline_report.txt`, which joins them. | Unless reports are suppressed |

The reason codes are:

| Code | Meaning |
|------|---------|
| `-6` | Redacted: the raw value matches a personal-data value pattern. |
| `-7` | Not applicable: the skip condition of the field in the Neotree script is false for the record. |
| `-8` | Invalid or removed: the raw cell held a value and the cleaned cell is empty. |
| `-9` | Unknown: every other empty cell. |

Module 16 runs when the folder `neotree_scripts/` exists. Otherwise a warning is logged and the NA-reason and NA-coded files are not written.

## Data keys and script metadata

The dictionary build reads the data-key exports in `neotree_data_keys/`, and the build and Module 16 read the script metadata in `neotree_scripts/`. Both are downloaded from the Neotree web editors, https://webeditor.neotree.org/ and https://zim-webeditor.neotree.org:10243/, with a Neotree account. They contain the names of health workers and are not part of the published repository. The README file in each folder lists the files and where they go.

## Dictionaries

The pipeline reads one workbook per country and dataset, `dictionaries/dictionary_<country>_<dataset>.xlsx`. The dictionary determines how each column is treated:

| Sheet | Used for |
|-------|----------|
| `Variables` | The type of each variable (`numeric`, `boolean`, `categorical`, `datetime`, `object`), whether it is used in analysis, whether it is confidential, which weights are in grams, the lower and upper limits of numeric variables, and the harmonised name. |
| `ValueMaps` | The raw codes, option labels and canonical codes of each categorical variable. |
| `PII_Patterns` | Column-name patterns that mark personal data. |

When a dataset has no workbook of its own, the workbook of a related dataset is used where a fallback is defined in `00_setup.r`. A column of the input file that the dictionary does not cover passes through as text: it is not typed or validated. Such columns are reported on the console, in the log and in `00c_undocumented_columns.txt` in the report folder.

The workbooks are generated by the scripts in `00_build_dictionary/` and are replaced by a rebuild. Their sheets and columns are described in [`dictionaries/README.md`](dictionaries/README.md); the build is described in [`00_build_dictionary/README.md`](00_build_dictionary/README.md). The `_enriched.xlsx` workbooks and the workbooks in `user_dictionaries/` are documentation and are not read by the cleaning modules.

## Personal data

Module 00a is the only module that reads the raw CSV in full, and it runs before any cleaning. It applies three rules:

| Rule | Action |
|------|--------|
| Tier 1 | Removes the value and label columns of every variable flagged `confidential` in the dictionary. |
| Tier 2 | Removes every column whose name matches a pattern of the `PII_Patterns` sheet or a built-in pattern in `00_setup.r`. |
| Tier 3 | Sets to `NA` every value that matches a value pattern: phone numbers, e-mail addresses, a three-part number pattern and two national identity number shapes. |

The key and system columns (`uid`, `facility`, `uniquekey`, the timestamp columns, `scriptversion`, `scriptid`) are tested by Tier 3 but never changed; a match is reported. Columns that match a quasi-identifier pattern, such as a village or district, are kept and listed in the audit report. The audit report, `reports/00a_pii_audit_report.txt`, holds column names and counts only.

### Guard

When Module 00a finishes, it writes the completion marker `00a_pii_removal_complete.dcf` in the run folder and attaches a run id to the data frame. The marker records the input file (path, size, modification time) and the checksum of the dictionary. Any marker left by an earlier run is deleted when Module 00a starts.

The function `assert_pii_removed()` in `00_setup.r` stops the run unless:

1. the marker exists and is complete;
2. the marker describes the current input file and dictionary;
3. no column belongs to a confidential variable or matches a column-name pattern;
4. no value outside the exempt columns matches a value pattern.

Module 01 stops if the de-identified data frame does not exist, and calls the guard with an extra check that the data frame carries the run id in the marker. The guard is called again before each write of row-level data: the removed rows of Module 02, the checkpoint of Module 10, the cleaned outputs of Module 15, the harmonised outputs of Module 00b and each table of Module 16. If a check fails, the file is not written. Messages from the guard give column names, pattern names and counts, never values.

## Derived columns

The pipeline adds these columns to the cleaned dataset. The columns they are derived from are not changed.

| Column | Added by | Content |
|--------|----------|---------|
| `mat_age_date_years` | Module 11 | `matagedate` (maternal age in hours) converted to whole years. Added when `matagedate` is present. |
| `hepbdate_date` | Module 14 | The values of `hepbdate` that are dates. Added when `hepbdate` is present and is not itself a datetime column. |
| `datebct_resolved` | Module 14a | `datebct` where present, otherwise the admission date-time of the same patient. `neolab` dataset only. |
| `datebct_source` | Module 14a | `"original"`, `"from_admission"` or `NA`. `neolab` dataset only. |
| `birthweight_g` | Module 15 | First non-missing of `birthweight`, `bwt`, `bwtdis`, in grams. |
| `admission_weight_g` | Module 15 | `admissionweight` in grams. Added when `admissionweight` is present. |
| `discharge_weight_g` | Module 15 | `dischweight` in grams. Added when `dischweight` is present. |
| `mat_age_years_combined` | Module 15 | `matageyrs` where present, otherwise `mat_age_date_years`. Added when either is present. |
| `mat_age_source` | Module 15 | `"matageyrs"`, `"matagedate_derived"` or `"none"`. |
| `antenatalcare_source` | Module 05 | `"raw_numeric_value"`, `"raw_exact_label"`, `"raw_range_label"` or `"unresolved"`. Malawi `admissions` only. |
| `antenatalcare_category` | Module 15 | `"none"`, `"1_3"`, `"ge4"` or `NA`. Malawi `admissions` only. |

In the cleaned dataset the suffixes `.value` and `.valuedischarge` are removed from all column names.

## Further documentation

| Subject | File |
|---------|------|
| Installing, running, settings, outputs, tests | [`how_to_run.md`](how_to_run.md) |
| Rules applied by one module | `README.md` in the folder of that module (linked in the table above) |
| Dictionary sheets and columns | [`dictionaries/README.md`](dictionaries/README.md) |
| Building and checking the dictionaries | [`00_build_dictionary/README.md`](00_build_dictionary/README.md) |

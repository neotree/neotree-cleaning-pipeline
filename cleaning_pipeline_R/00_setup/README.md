# Module 00: Setup and Configuration

## Purpose

Loads the libraries, reads the user settings and the data dictionary, defines the helper functions shared by the other modules, and builds the configuration list `cfg`.

## When it runs

First. Every other module sources `00_setup/00_setup.r` at its top, so the settings, helpers and `cfg` are rebuilt each time a module is sourced.

## What it does

1. Applies the default to every user setting that is not already defined in the calling environment.
2. Creates the output folder and a run folder inside it, named after the input file without its `.csv` extension.
3. Starts logging to the console and to `<file stem>.log` in the run folder.
4. Checks `COUNTRY`, `DATASET` and `DATA_SOURCE` and stops if a value is not accepted.
5. Detects the export style of the input file and logs it.
6. Resolves the dictionary, output, report and paired-file paths.
7. Loads the dictionary sheets `Variables` and `ValueMaps`. Stops if the dictionary file does not exist.
8. Derives the feature lists and lookups from the dictionary and assembles `cfg`.
9. Compares the header of the input file with the dictionary and reports columns the dictionary does not cover.
10. Defines the PII patterns, the completion-marker path and the guard `assert_pii_removed()`.

## Configuration

Each setting is assigned only if it does not already exist, so a value set before the file is sourced (for example by `run_all.r`) is kept.

| Setting | Default | Effect |
|---------|---------|--------|
| `COUNTRY` | `"ZIM"` | `"ZIM"` or `"MWI"`. Trimmed and converted to upper case. |
| `DATASET` | `"admissions"` | Dataset type; see *Datasets* below. Trimmed and converted to lower case. |
| `DATA_SOURCE` | `"auto"` | Accepts `auto`, `database`, `metabase`, `mixed` or `unknown`. It does not change how anything is parsed, and is replaced by the detected export style. |
| `CSV_FILEPATH` | a file in `input/` | Path to the raw CSV. |
| `DICT_FILEPATH` | `NULL` | Dictionary path. `NULL` resolves it automatically; see *Path resolution*. |
| `OUTPUT_CSV`, `OUTPUT_RDS` | `NULL` | Paths of the cleaned outputs. `NULL` gives `<file stem>_cleaned.csv` and `<file stem>_cleaned.rds` in the run folder. |
| `OUTPUT_DIR` | `"output"` | Base folder for everything the pipeline writes. |
| `REPORT_DIR` | `NULL` | `NULL` gives `reports/` in the run folder. A path writes the reports there. `FALSE` or `""` suppresses the module reports (`cfg$report_dir` is `NULL`). |
| `NEOTREE_SCRIPTS_DIR` | `NULL` | Folder of Neotree script metadata used by Module 16. `NULL` gives `neotree_scripts/` in the pipeline folder. |
| `SAVE_DEIDENTIFIED` | `FALSE` | Module 00a writes `<file stem>_deidentified.csv`. |
| `SAVE_STAGE1_CHECKPOINT` | `FALSE` | Module 10 writes a checkpoint RDS after its first stage. |
| `SAVE_HARMONISED` | `FALSE` | Module 00b runs and writes the harmonised CSV and RDS. |
| `SAVE_NA_CODED` | `TRUE` | Module 16 writes the cleaned data with each `NA` replaced by its reason code. |
| `SAVE_NA_REASONS_LONG` | `FALSE` | Module 16 writes the long table of `NA` reasons. |
| `SKIP_DEDUP_STAGE2` | `TRUE` for `infections` and `neolab`, otherwise `FALSE` | Module 10 skips its patient-level stage. |
| `RESOLVE_NEOLAB_DATEBCT` | `TRUE` | Module 14a fills missing `datebct` values from the admissions file. Used only when the dataset is `neolab`. |
| `UID_REPAIR_SEPARATORS` | `c(",", "/")` | Characters Module 02 treats as a mistyped hyphen in a `uid`. |
| `RESERVED_COLUMN_RENAMES` | for `phc_discharges`: `facility.value` to `facilityname.value`, `facility.label` to `facilityname.label` | Per dataset, standardised column names that Module 01 renames so that they do not share a name with a key column. |

### Datasets

`admissions`, `discharges`, `maternal_outcomes`, `phc_admissions`, `phc_discharges`, `combined_maternity_outcomes`, `dhis2_maternal_outcomes`, `maternity_completeness`, `joined_admissions_discharges`, `neolab`, `baseline`, `infections`, `twenty_8_day_follow_up`.

## Path resolution

**Dictionary.** With `DICT_FILEPATH` unset, the path is `dictionaries/dictionary_<country>_<dataset>.xlsx`. If that file does not exist and the dataset has a fallback type whose dictionary exists, the fallback dictionary is used.

| Dataset | Fallback type |
|---------|---------------|
| `joined_admissions_discharges`, `phc_admissions`, `baseline` | `admissions` |
| `phc_discharges` | `discharges` |
| `dhis2_maternal_outcomes` | `combined_maternity_outcomes` |
| `maternity_completeness` | `maternal_outcomes` |

**Paired file.** `.resolve_paired_csv(csv_filepath, dataset)` looks for the other half of an admissions/discharges pair (`admissions` with `discharges`, `phc_admissions` with `phc_discharges`) in the folder of the input file. It first swaps the dataset token in the input file name. If that file does not exist, it lists files named `<country>_[db_|mb_]<paired dataset>_<stamp>.csv`, where the stamp is 12 digits, 8 digits or `YYYY-MM-DD`, and takes the last one in sorted order. It returns `list(dataset, path)`. Both are `NULL` when the dataset has no pair; `path` is `NULL` when no file is found. Only the path is resolved; the file is not read.

## Format detection

`.detect_data_source(csv_filepath, n_rows = 500)` reads the header and the first rows as text and returns `list(source, reason)`.

| Evidence | Style |
|----------|-------|
| Header has `Unique Key`, `Started At`, `Completed At` or `Ingested At` | `metabase` |
| Header has `unique_key`, `started_at`, `completed_at` or `ingested_at` | `database` |
| Values include month-name datetimes and no ISO datetimes | `metabase` |
| Values include ISO datetimes and no month-name datetimes | `database` |
| Values include both, or ISO datetimes together with thousands-separated numbers | `mixed` |

`source` is the style when header and values agree or only one is recognised, `mixed` when they differ, and `unknown` when neither is recognised or the file cannot be read. `reason` holds the counts. The result is logged and stored in `cfg$data_source`.

## Shared value parsers

### `parse_datetime_by_shape(x)`

Returns a POSIXct (UTC) vector. Each value is trimmed and parsed by the rule for its own shape. Empty values and the text `NA` are `NA`.

| Shape | Examples | Read as |
|-------|----------|---------|
| ISO | `2023-10-19`, `2023-10-19 22:00:00`, `2023-10-19T22:00:00Z`, `2023/10/19` | Year, month, day, with an optional time. A trailing `Z` or UTC offset after a time is dropped; the time is kept as written. |
| Day first | `19/10/2023`, `19-10-2023`, `19.10.2023`, `19/10/23 10:30 PM` | Day, month, year, with an optional 12-hour or 24-hour time. A two-digit year is read as 20yy. A value valid only as month/day/year becomes `NA`. |
| Month name | `March 2, 2026, 12:33 AM`, `2 March 2026`, `19-Oct-2023` | Month name identified by its first three letters, in any case, with an optional time. |
| Anything else | free text, digits without separators | `NA` |

The attribute `counts` on the result is a named integer vector: `iso`, `day_first`, `month_name`, `offset_dropped`, `month_first_rejected`, `unparsed`.

### `parse_numeric_by_shape(x)`

Returns `list(value, counts)`. `value` is a numeric vector.

| Value | Read as |
|-------|---------|
| `3500`, `3.5`, `-2` | the number |
| `3,500`, `1,234,567.8` | 3500, 1234567.8 (thousands separators removed) |
| `3,5`, `36,75` | 3.5, 36.75 (decimal comma, one or two digits after it) |
| text holding one run of digits, e.g. `ANC4`, `36.5 C` | that number, without a sign |
| text holding several runs of digits, e.g. a date, `10-12`, `1e5`, `0x1A` | `NA` |
| text with no digit | `NA` |

`counts` is a named integer vector: `plain`, `thousands`, `decimal_comma`, `fallback`, `multi_number_rejected`, `non_numeric`.

### Boolean tokens

| Object | Values |
|--------|--------|
| `NEOTREE_TRUE_TOKENS` | `true`, `yes`, `y`, `1`, `t` |
| `NEOTREE_FALSE_TOKENS` | `false`, `no`, `n`, `0`, `f` |

## Logging

Messages at level INFO and above go to the console and to `<file stem>.log` in the run folder. Messages are formatted with `sprintf`, so the format string and its arguments are passed to the `log_*` functions separately. The first message of each sourcing records the value of `PIPELINE_VERSION`.

## Dictionary coverage check

`.check_dict_coverage()` reads the header of the input file. Columns ending in `.parentKey` and the system columns (`uid`, `facility`, `uniquekey`, the timestamp columns, `scriptversion`, `scriptid`) are left out. Every other column that is in neither `raw_value_column` nor `raw_label_column` of the dictionary is reported in the log and on the console, and listed in `00c_undocumented_columns.txt`. The names are stored in `cfg$undocumented_cols`.

## PII definitions and guard

| Object | Content |
|--------|---------|
| `PII_FALLBACK_PATTERNS_DEFAULT` | Built-in column-name patterns: names ending in `name.value`, `cell.value`, `phone.value`, `address.value`, `uidbid.value`, `uiddc.value` or `drid.value`; names containing `hcwid`, `hospnum`, `neotreeid` or `stuid`; and a mother's date-of-birth column with a `.value` or `.label` suffix. |
| `PII_SHEET_PATTERNS` | Patterns read by `load_pii_patterns(dict_path)` from the `pattern` column of the dictionary sheet `PII_Patterns`; `NULL` if the sheet cannot be read or is empty. |
| `PII_TIER2_PATTERNS` | The union of the two lists above. |
| `PII_VALUE_PATTERNS` | Value patterns; see the table below. |
| `PII_VALUE_SCAN_EXEMPT` | Key and system columns that are never redacted: `uid`, `facility`, `uniquekey`, `startedat`, `completedat`, `ingestedat`, `startedatdischarge`, `completedatdischarge`, `ingestedatdischarge`, `scriptversion`, `scriptid`. |
| `PII_MARKER_PATH` | `00a_pii_removal_complete.dcf` in the run folder. |

| Value pattern | Matches |
|---------------|---------|
| `phone_international` | A whole value of `263` and 9 digits, or `265` and 7 to 9 digits, with an optional leading `+`. |
| `phone_local_zw` | A whole value of `0`, then `6` or `7`, then 8 digits. |
| `phone_local_mwi` | A whole value of `0`, then `8` or `9`, then 8 digits. |
| `email` | An email address anywhere in the value. |
| `nhs_number` | A whole value of 3, 3 and 4 digits separated by hyphens or spaces. |
| `zw_national_id` | Anywhere in the value: 2 digits, 6 or 7 digits, a letter and 2 digits, with or without hyphens or spaces between the parts, not joined to other letters or digits. |
| `mw_national_id` | Anywhere in the value: 8 letters or digits containing at least two letters and at least two digits, not joined to other letters, digits or hyphens. Case is ignored. |

`pii_value_hits(x, pattern)` trims the values and returns a logical vector marking those that match.

`write_pii_marker(input_path, run_id, n_cols_removed, n_values_redacted)` writes the marker file: completion time, run id, pipeline version, input path, size and modification time, dictionary path and MD5 checksum, number of column-name patterns, and the two counts.

`assert_pii_removed(df, stage, check_run_id = FALSE, value_exempt = character(0))` returns `TRUE` invisibly or stops with an error. It checks, in order:

1. The marker file exists and holds the required fields.
2. The marker describes the current input: same path, size and modification time; written after the input was last modified; same dictionary checksum.
3. With `check_run_id = TRUE`, the attribute `neotree_pii_run_id` of `df` equals the run id in the marker.
4. No column of `df` belongs to a variable flagged confidential in the dictionary, and none matches a pattern in `PII_TIER2_PATTERNS`. Each column is tested under its own name, as `<base>.value`, as `<question_key>.value` when it carries a harmonised name, and with the Module 01 reserved renames undone.
5. No value matches a pattern in `PII_VALUE_PATTERNS`. Date, date-time, logical and list columns are skipped, as are the columns in `PII_VALUE_SCAN_EXEMPT`, their harmonised names, and those named in `value_exempt`.

Error messages give column names, pattern names and counts of cells, never values.

## Inputs

| Object / file | Description |
|---------------|-------------|
| User settings | See *Configuration* |
| Raw CSV at `CSV_FILEPATH` | The header and first rows are read for format detection and the coverage check |
| Dictionary workbook | Sheets `Variables`, `ValueMaps` and, if present, `PII_Patterns` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `cfg` | Configuration list; see below |
| `dict_variables`, `dict_value_maps` | The two dictionary sheets, with cleaned column names |
| `<file stem>.log` | Run log, in the run folder |
| `00c_undocumented_columns.txt` | Written only when undocumented columns are found, in the report folder, or in the run folder when reports are suppressed |

### The `cfg` list

| Element | Content |
|---------|---------|
| `country`, `dataset`, `data_source` | Country, dataset and detected export style |
| `csv_filepath`, `dict_filepath` | Input and dictionary paths |
| `paired_dataset`, `paired_csv_filepath` | Paired dataset name and file path, or `NULL` |
| `output_dir`, `run_output_dir`, `file_stem` | Base output folder, run folder, input file name without extension |
| `output_csv`, `output_rds`, `report_dir` | Output paths and report folder (`NULL` when reports are suppressed) |
| `num`, `bool`, `cat`, `obj` | `raw_value_column` names of dictionary variables of each `r_type` with `use_in_analysis` true, preceded by the key columns `facility`, `uid`, `uniquekey` |
| `dt` | Key columns, the system timestamp columns of the dataset, and the datetime variables |
| `extra_meta_cols` | `scriptversion`, or `scriptversion` and `scriptid`, for datasets that carry them; otherwise empty |
| `weight_cols` | `question_key` of variables whose `weight_unit` is `grams` |
| `range_lookup` | Tibble of `question_key`, `min`, `max` for numeric variables with a plausible minimum or maximum |
| `value_map_list` | Per `question_key`: `allowed_codes`, `canonical_codes`, `label_to_code`, `code_to_canonical` |
| `value_mappings`, `values_to_delete` | Empty lists, read by Module 13 |
| `pii_columns` | `raw_value_column` and `raw_label_column` of variables flagged `confidential` |
| `harmonised_map` | Named vector from `question_key` to `harmonised_variable_name`, for variables with `use_in_analysis` true |
| `uid_repair_separators`, `reserved_column_renames` | From the settings of the same names; the renames are those for the current dataset, or `NULL` |
| `neotree_scripts_dir` | Resolved scripts folder |
| `save_deidentified`, `save_stage1_checkpoint`, `save_harmonised`, `save_na_coded`, `save_na_reasons_long`, `skip_dedup_stage2`, `resolve_neolab_datebct` | From the settings of the same names |
| `undocumented_cols` | Column names found by the coverage check |

## Functions

| Function | Returns |
|----------|---------|
| `.detect_data_source(csv_filepath, n_rows = 500L)` | `list(source, reason)` |
| `parse_datetime_by_shape(x)` | POSIXct vector with attribute `counts` |
| `parse_numeric_by_shape(x)` | `list(value, counts)` |
| `.resolve_paired_csv(csv_filepath, dataset)` | `list(dataset, path)` |
| `cols_of_type(r_type_filter, include_keys = TRUE)` | Column names of one dictionary type |
| `.check_dict_coverage()` | Undocumented column names, invisibly |
| `pii_value_hits(x, pattern)` | Logical vector |
| `load_pii_patterns(dict_path)` | Character vector of patterns, or `NULL` |
| `write_pii_marker(input_path, run_id, n_cols_removed, n_values_redacted)` | Marker path, invisibly |
| `.pii_candidate_names(nm)` | The names under which a column is tested by the guard |
| `assert_pii_removed(df, stage, check_run_id = FALSE, value_exempt = character(0))` | `TRUE` invisibly, or stops |

# Module 00: Setup & Configuration

## Purpose
Centralises every parameter, file path, library, and feature list used by the entire pipeline. All downstream modules source this file first to gain access to the `cfg` configuration object and the global feature vectors.

---

## When It Runs
First -- must be sourced before any other module. Running `source("run_pipeline.r")` triggers this automatically.

---

## Logic

1. The **User Configuration** block at the top of the file is the only section that needs to be edited before each run. It defines:
   - `COUNTRY` -- `"ZIM"` (Zimbabwe) or `"MWI"` (Malawi)
   - `DATASET` -- the dataset type (see table below)
   - `DATA_SOURCE` -- `"database"` (PostgreSQL export) or `"metabase"` (Metabase export)
   - `CSV_FILEPATH` -- path to the raw input CSV
   - `DICT_FILEPATH` -- path to the data dictionary (NULL = auto-resolved)
   - `OUTPUT_CSV` / `OUTPUT_RDS` -- output file paths (NULL = auto-named)
   - `REPORT_DIR` -- directory for per-module text reports (NULL = auto-named; FALSE = suppress)
   - Five optional **output flags** (see table in *Output file flags* below)

   **Injectable setup (batch mode):** when running via `run_all.r`, all of the above variables are set programmatically before `00_setup.r` is sourced. Every assignment in the User Configuration block is guarded with `if (!exists(...))` so that values injected by `run_all.r` take precedence over the defaults written in the file. The output flags follow the same pattern -- set them at the top of `run_all.r` (or leave unset to use the defaults in `00_setup.r`).

2. The script validates the combination of COUNTRY and DATASET and raises an error if unsupported.

3. The **data dictionary** (`.xlsx`) is loaded from `dictionaries/` and parsed into two tibbles:
   - `dict_variables` -- one row per clinical variable: data type, plausible ranges, confidentiality flag, harmonised name
   - `dict_value_maps` -- one row per allowed option code: raw code, display label, canonical code

4. **Feature lists** are derived directly from `dict_variables` (never hard-coded):
   - `cfg$num` -- column names for numeric variables (`r_type == "numeric"`)
   - `cfg$bool` -- column names for boolean variables
   - `cfg$cat` -- column names for categorical variables
   - `cfg$obj` -- column names for free-text/object variables
   - `cfg$dt` -- column names for datetime variables (includes dataset-specific timestamp columns)

5. Additional helpers are built:
   - `cfg$weight_cols` -- variables whose unit is grams (used by Module 11 for g->kg conversion)
   - `cfg$range_lookup` -- tibble of plausible min/max per variable (used by Module 11)
   - `cfg$value_map_list` -- nested list: `question_key -> list(allowed_codes, canonical_codes, label_to_code, code_to_canonical)` (used by Module 04). `canonical_codes` and `code_to_canonical` were added 2026-06-12 so Module 04 can emit canonical codes and match codes/labels case-insensitively (categorical harmonisation work).
   - `cfg$harmonised_map` -- named vector: `question_key -> harmonised_variable_name` (used by Module 00b)
   - `cfg$pii_columns` -- column names marked `confidential = TRUE` in the dictionary (used by Module 00a)

6. A **dictionary fallback map** handles datasets without their own dictionary (e.g. `joined_admissions_discharges` falls back to the `admissions` dictionary).

---

## Inputs

| Source | Description |
|--------|-------------|
| User configuration block | Country, dataset, data source format, file paths |
| `dictionaries/dictionary_{country}_{dataset}.xlsx` | v8 data dictionary (auto-resolved from COUNTRY x DATASET) |
| Raw CSV file | Path stored in `cfg$csv_filepath`; loaded by Module 01 |

---

## Outputs

No files are written by this module. It exports the following objects to the global environment:

| Object | Type | Description |
|--------|------|-------------|
| `cfg` | Named list | All pipeline parameters, paths, and derived lookup structures |
| `dict_variables` | tibble | Variables sheet from the data dictionary |
| `dict_value_maps` | tibble | ValueMaps sheet from the data dictionary |

The `cfg` list is the single source of truth for all modules:

| `cfg` field | Description |
|-------------|-------------|
| `cfg$country` | Country code (`"ZIM"` or `"MWI"`) |
| `cfg$dataset` | Dataset type string |
| `cfg$data_source` | `"database"` or `"metabase"` |
| `cfg$csv_filepath` | Input CSV path |
| `cfg$dict_filepath` | Resolved dictionary path |
| `cfg$output_csv` | Output CSV path |
| `cfg$output_rds` | Output RDS path |
| `cfg$report_dir` | Report output directory |
| `cfg$num` | Numeric feature column names |
| `cfg$bool` | Boolean feature column names |
| `cfg$cat` | Categorical feature column names |
| `cfg$obj` | Object/free-text feature column names |
| `cfg$dt` | Datetime feature column names |
| `cfg$weight_cols` | Variables recorded in grams |
| `cfg$range_lookup` | Tibble: question_key, min, max |
| `cfg$value_map_list` | Nested list for Module 04 value cleaning: per `question_key`, `allowed_codes` (raw), `canonical_codes` (targets), `label_to_code`, `code_to_canonical` |
| `cfg$harmonised_map` | Named vector for Module 00b renaming |
| `cfg$pii_columns` | PII column names for Module 00a |
| `cfg$value_mappings` | Alias -> canonical mappings for Module 13 |
| `cfg$values_to_delete` | Known-bad values per column for Module 13 |
| `cfg$extra_meta_cols` | Extra metadata columns for PHC/combined datasets |
| `cfg$run_output_dir` | Per-run output subfolder (`output/<file_stem>/`) |
| `cfg$file_stem` | Input filename without extension (e.g. `zim_db_admissions_20260501`) |
| `cfg$save_deidentified` | Whether to write `*_deidentified.csv` to disk (default `FALSE`) |
| `cfg$save_stage1_checkpoint` | Whether to write `*_cleaned_stage1.rds` (default `FALSE`) |
| `cfg$save_harmonised` | Whether Module 00b runs and writes harmonised files (default `FALSE`) |
| `cfg$save_na_coded` | Whether to write `*_na_coded.csv` (default `TRUE`) |
| `cfg$save_na_reasons_long` | Whether to write `*_na_reasons_long.csv.gz` (default `FALSE`) |
| `cfg$skip_dedup_stage2` | Whether Module 10 skips Stage 2 patient-level deduplication. `TRUE` for `infections` and `neolab`; `FALSE` for all others. |
| `cfg$resolve_neolab_datebct` | Whether Module 14a attempts to resolve NA `datebct` values by joining to the raw admissions file. Only has any effect when `cfg$dataset == "neolab"`. Default `TRUE`. |

---

## Output file flags

Five boolean flags in the User Configuration block control optional output files. All default to the values below and can be overridden at the top of `run_all.r` for batch runs.

| Flag | Default | Controls |
|------|---------|----------|
| `SAVE_DEIDENTIFIED` | `FALSE` | `*_deidentified.csv` -- raw data with PII removed (Module 00a) |
| `SAVE_STAGE1_CHECKPOINT` | `FALSE` | `*_cleaned_stage1.rds` -- mid-pipeline checkpoint after Module 10 |
| `SAVE_HARMONISED` | `FALSE` | `*_cleaned_harmonised.csv` + `.rds` -- snake_case column names (Module 00b) |
| `SAVE_NA_CODED` | `TRUE` | `*_na_coded.csv` -- cleaned data with NA cells replaced by reason codes |
| `SAVE_NA_REASONS_LONG` | `FALSE` | `*_na_reasons_long.csv.gz` -- long-format NA reasons, one row per NA cell |
| `SKIP_DEDUP_STAGE2` | auto | Skip Stage 2 (patient-level) deduplication in Module 10. Auto-set to `TRUE` for `infections` and `neolab` (longitudinal datasets where multiple rows per patient are by design); `FALSE` for all other datasets. Override explicitly in `run_all.r` if needed. |
| `RESOLVE_NEOLAB_DATEBCT` | `TRUE` | Resolve NA `datebct` values in the `neolab` dataset by joining to the raw admissions file on `uid + facility` and using `datetimeadmission` as a proxy date (Module 14a). Adds `datebct_resolved` and `datebct_source` columns. No effect for non-neolab datasets. |

PII removal always runs in-memory regardless of `SAVE_DEIDENTIFIED`; the flag only controls whether the de-identified copy is written to disk.

---

## Supported DATASET values

| Value | Description | Available for |
|-------|-------------|---------------|
| `admissions` | Standard neonatal admissions | MWI, ZIM |
| `discharges` | Standard neonatal discharges | MWI, ZIM |
| `maternal_outcomes` | Birth / maternal outcomes | MWI, ZIM |
| `phc_admissions` | Primary Health Care admissions | MWI |
| `phc_discharges` | Primary Health Care discharges | MWI |
| `combined_maternity_outcomes` | All three maternal source files merged | MWI |
| `dhis2_maternal_outcomes` | DHIS2-linked maternal source only | MWI |
| `maternity_completeness` | Maternity completeness source only | MWI |
| `joined_admissions_discharges` | Admissions + discharges joined for analysis (uses admissions dictionary) | MWI, ZIM |
| `neolab` | Blood culture / laboratory dataset | MWI, ZIM |
| `baseline` | Retrospective baseline (combined admission+discharge form) | ZIM |
| `infections` | Longitudinal infection follow-up form | ZIM |
| `twenty_8_day_follow_up` | 28-day post-discharge follow-up | ZIM |

---

## Notes

- All feature lists are derived dynamically from the dictionary -- they do not need to be updated manually when the data keys change.
- Column names in `cfg$num`, `cfg$bool`, `cfg$cat`, `cfg$obj`, `cfg$dt` are in the normalised lowercase form used after Module 01 (e.g. `"babycry.value"`). Validation modules use `intersect(cfg$num, names(df))` to match against the actual data frame.
- Logging is configured here: each run writes its log to `output/<file_stem>/<file_stem>.log` (alongside the run's output files) and simultaneously to the console.

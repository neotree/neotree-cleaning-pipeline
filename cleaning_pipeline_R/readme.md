# Neotree Data Cleaning Pipeline -- R Implementation

## Overview

This pipeline cleans and validates raw Neotree clinical data exported from a
PostgreSQL database (directly or via Metabase).  It covers neonatal birth
records and newborn admissions from hospitals in **Malawi** and **Zimbabwe**,
including both standard hospital data and Primary Health Care (PHC) data.

The pipeline is structured as numbered modules, each in its own folder.
Modules run sequentially; each sources the shared configuration from
`00_setup/00_setup.R` and operates on the data frame (`df`) passed down from
the previous step.

---

## Pipeline Architecture

```
neotree_cleaning_pipeline/
|
+-- run_pipeline.R                       <- Master script: runs all modules in order
|
+-- 00_setup/                            <- Configuration, file paths, feature lists
+-- 00a_pii_detection_removal/           <- PII removal (runs FIRST, on raw data)
+-- 00b_rename_harmonised_columns/       <- Optional post-processing (rename to snake_case)
+-- 00_build_dictionary/                 <- Build v8 data dictionaries from DOWNLOADED keys
|
|   -- FIRST-STAGE CLEANING --
+-- 01_standardise_column_headers/
+-- 02_frame_shift_correction/
+-- 03_duplicate_column_merging/
+-- 04_dictionary_value_cleaning/
+-- 05_forward_fill_placeholders/
+-- 06_forward_fill_numeric_datetime/
+-- 07_drop_label_columns/
+-- 08_drop_autopopulated_columns/
+-- 09_data_type_assignment/
+-- 10_remove_duplicate_rows/
|
|   -- VALIDATION --
+-- 11_numeric_validation/
+-- 12_boolean_validation/
+-- 13_categorical_object_validation/
+-- 14_datetime_validation/
+-- 14a_resolve_neolab_datebct/       <- Neolab-only: resolve missing datebct from admissions
|
|   -- OUTPUT --
+-- 15_final_merge_output/
|
|   -- POST-PROCESSING --
+-- 00b_rename_harmonised_columns/   <- Optional (rename to snake_case)
\-- 16_na_reason_coding/             <- NA reason coding (runs last, automatically)
```

### Validation philosophy: definitional bounds vs. clinical plausibility

The pipeline applies two distinct levels of value checking, deliberately kept separate:

**Definitional bounds (this pipeline -- Module 11)**
A value is rejected only if it is structurally impossible by the definition of the measurement instrument. The three cases currently covered are:
- Apgar scores (`apgar1/5/10`): defined on a fixed 0-10 scale. A value of 11 cannot exist.
- Thompson HIE score (`thompscore`): defined on a fixed 0-22 scale. A value of 23 cannot exist.
- Oxygen saturation (`satsair`, `satso2`): a percentage, defined on a 0-100 scale. A value of 101 cannot be a percentage.

All other numeric variables -- including continuous physiological measurements such as weight, gestation, temperature, heart rate, respiratory rate, and blood glucose -- carry no range check in this pipeline. Extreme values for these variables may be data entry errors, but they are not structurally impossible, so they are retained.

**Clinical plausibility (sample maker -- PLANNED, not yet implemented)**
The intended design is that, before sharing data with researchers, the sample maker applies a separate set of clinically agreed ranges. These reflect what is biologically plausible for the patient population, not what is definitionally possible for the instrument. For example, a SpO2 reading of 0% is a valid percentage (and therefore passes the cleaning pipeline) but is not a plausible clinical reading from a live admitted neonate (and should be replaced with NA before sharing). **Status (2026-06-24):** this clinical-plausibility step is NOT yet implemented in the sample maker -- there is no `plausibility_validator.R` and no `config_plausibility_ranges.csv`; the sample maker's `modules/filter_data.R` performs only date/facility filtering (see the neotree-sample-maker repository). It is the 30 April 2026 action plan's Action 4. The clinically agreed ranges already exist as the source of truth in this cleaning pipeline's dictionary build -- `00_build_dictionary/user_ranges.xlsx` and `00_build_dictionary/og_feature_validation_dict.xlsx`, surfaced as the `suggested_plausible_min` / `suggested_plausible_max` columns of the per-table dictionaries (and `MANUAL_RANGES` in `00_build_dictionary.r`) -- but the cleaning pipeline applies only definitional bounds (Module 11), never these clinical ranges. When Action 4 is built, the sample maker should read those ranges (from the cleaned dictionaries' `suggested_plausible_min/max`) and replace out-of-range values with NA.

This separation ensures that the master cleaned dataset is a faithful representation of the recorded data, while the shared research datasets are filtered to clinically agreed plausible values.

### Weight variables: three distinct concepts and canonical derived columns

Weight is the variable most affected by Neotree form/script evolution and must be handled carefully. There are **three distinct weight concepts** that must never be coalesced into one another:

- **Birth weight (g)** — weight at birth (the LBW measure). Stored under three column names depending on form/era: `birthweight`, `bwt`, and `bwtdis`. All three carry the **same** concept (question labels are all "Birth weight (g)"); they are mutually exclusive across versions, and identical where they overlap (ZIM discharges: 5,297 overlapping rows, max difference 0 g). **Naming trap:** `bwtdis` is birth weight, *not* discharge weight, despite the "Dis" suffix.
- **Admission weight (g)** — `admissionweight` (neonatal admission). Distinct measurement (MWI admissions: equals birth weight only ~18% of the time, mean abs diff ~193 g).
- **Discharge / last-recorded weight (g)** — `dischweight` (+ `datedischweight`). Distinct (vs birth weight ~10–66% equal, mean diff 75–237 g).

**Form-version handovers.** MWI moved birth weight from `bwtdis` (≤2024) to `birthweight` (2025+) in the combined maternity / DHIS2 maternal streams (`bwt` is near-empty); MWI `discharges` did not capture birth weight before ~`script_version` 137 (2023), so `birthweight` is legitimately empty pre-2023 (value was in `dischweight`). ZIM is stable but keeps maternal birth weight in `bwtdis` while neonatal forms use `birthweight` — so the canonical birth-weight column differs by country and cross-country work must coalesce.

**Canonical derived columns (implemented — Module 15, `derive_weight_columns()`).** The original columns are kept untouched and three derived columns are added: `birthweight_g = coalesce(birthweight, bwt, bwtdis)`, `admission_weight_g = admissionweight`, and `discharge_weight_g = dischweight` (with `datedischweight` kept alongside). `birthweight_g` is emitted in every file (NA where the form never captured it); admission/discharge weight columns appear only where that concept is captured. The NA convention is unchanged — empty in origin → empty in `*_cleaned.csv`, missing-code in `*_cleaned_na_coded.csv` (except join-induced blanks, left blank). The function logs a disagreement warning if two birth-weight sources are both present and differ by >1 g (verified 0 on the 10 June extract), and applies an idempotent defensive kg→g guard (values ≤20 treated as kg). Clinical plausibility bounds (~300–7000 g) remain in the sample maker, never here. **Dictionary:** the three derived columns are registered via `DERIVED_VARIABLES` in `00_build_dictionary.r` (documentation-only rows; `raw_value_column` = NA keeps them out of the cleaning feature lists), so they are documented in the per-table dictionaries and the 00d user dictionary on the next rebuild. **Note for the sample maker:** `prob_matcher.R` keys on the literal `birthweight` column name, which is preserved (originals untouched), so the probabilistic join is unaffected; if the project ever renames it, update `PROB_CANDIDATE_VARS` in the neotree-sample-maker repository.

---

### Maternal age: harmonising `matageyrs` and `matagedate` into one variable

Maternal age is captured on the deliveries / maternal-outcomes form in two different fields, and no single column holds a clean value:

- **`matageyrs`** — "Age of Mother (yrs)", manually entered whole years. Present in **both** SMCH (ZIM) and KCH (MWI) files. Dictionary plausible range **9–60** (harmonised name `mat_age_yrs`).
- **`matagedate`** — "Mother's Age (auto-calculated from DOB)", raw type `period`. **KCH/MWI only.** Critically, it is stored **in hours, not years** (e.g. `164990 → 18.8 yrs`); divide by **8766** (= 365.25 × 24) to get years (harmonised name `mat_age_date`). The form instructs collectors to leave `matageyrs` blank when the auto-calculated value is used, so the two fields are partly complementary and, where both are filled, may disagree.

**Two-part implementation (originals kept untouched):**

1. **Module 11 (`11_numeric_validation.r`) — put both sources into clean years and filter implausibles in one place.** A new block derives **`mat_age_date_years` = `round(matagedate / 8766)`** and applies the *same* 9–60 plausibility window as `matageyrs`, setting out-of-range values to NA and counting them in the Module 11 report. Raw `matagedate` is left as-is (still hours). `matageyrs` is unchanged: it is already range-validated 9–60 here, and its long-standing hours-contamination rescue (values > 200 ÷ hours-per-year) now uses **8766** for consistency (previously 8760). Because both sources are filtered by the module that owns implausible-value handling, any implausible maternal age is subsequently NA-reason-coded by Module 16 (**-8, invalid/removed**) exactly like every other removed numeric.

2. **Module 15 (`15_final_merge_output.r`, `derive_maternal_age_columns()`) — coalesce into one variable with provenance.** After suffix stripping (so both inputs are already clean years), it adds:
   - **`mat_age_years_combined` = `coalesce(matageyrs, mat_age_date_years)`** — `matageyrs` (manual) takes priority; `mat_age_date_years` (auto) fills the gaps.
   - **`mat_age_source` ∈ `{"matageyrs", "matagedate_derived", "none"}`** — records which field supplied each value.

   Emitted only when at least one source column is present, so non-maternal datasets are not padded and **ZIM (matageyrs only) and MWI (both) share one combined schema**. **Disagreement guard:** where both sources are present and differ by **> 1 year**, the rows are *counted and logged* (never silently overwritten — `matageyrs` is kept), and the count + rate are written to **`15b_maternal_age_summary.txt`**.

**Verified on the 25 June extract.** SMCH/ZIM: `matageyrs` only → `mat_age_years_combined` = 25,816 non-missing (21.0%), all `mat_age_source = "matageyrs"`. KCH/MWI: `matageyrs` 3,009 + 627 filled from `matagedate_derived` (15 implausible values dropped by the 9–60 filter) → 3,636 non-missing (25.7% vs 21.3% from `matageyrs` alone); of the 24 rows where both fields are present, **16 (66.7%) disagree by > 1 year** and are flagged, not overwritten. High missingness overall (~74–85% across 2022–2025) is a data-collection-timing artefact: the maternal-age field was only added to the deliveries form partway through (first record 12 Nov 2024 KCH, 3 Jul 2025 SMCH), so it is truly absent before then. **NA convention** matches the weight columns: the accurate cell-level reason for a removed/absent age lives on the source columns (`matageyrs`, `mat_age_date_years`) via Module 16; for the derived combined column, treat `mat_age_source == "none"` plus the two reports as the authoritative accounting. Clinical (as opposed to definitional 9–60) plausibility bounds, if any, remain the sample maker's responsibility, never here.

---

## Execution Order

| Step | Module | Description |
|------|--------|-------------|
| 0    | `00_setup` | Load libraries, set file paths and source format, derive feature lists from v8 dictionary |
| **00a** | `00a_pii_detection_removal` | **Remove PII from raw data -- runs BEFORE any cleaning** |
| 1    | `01_standardise_column_headers` | Lowercase, strip whitespace, normalise dots |
| 2    | `02_frame_shift_correction` | Remove rows with misaligned UIDs |
| 3    | `03_duplicate_column_merging` | Merge duplicate columns, keep most complete |
| 4    | `04_dictionary_value_cleaning` | Harmonise categorical values to dictionary **canonical codes** (case-insensitive code/label match, legacy boolean on yes/no fields, multi-select case-folding); unresolved values left untouched and logged (see module README + Changelog) |
| 5    | `05_forward_fill_placeholders` | Recover None/Normal/Norm from `.label` into `.value` |
| 6    | `06_forward_fill_numeric_datetime` | Recover numeric/datetime values from `.label` |
| 7    | `07_drop_label_columns` | Drop redundant `.label` columns |
| 8    | `08_drop_autopopulated_columns` | Preserve DC columns as independent discharge-form entries (no-op -- see module README) |
| 9    | `09_data_type_assignment` | Convert columns to correct R data types |
| 10   | `10_remove_duplicate_rows` | Final deduplication -- end of first-stage cleaning |
| 11   | `11_numeric_validation` | Non-numeric removal, unit conversion (kg->g), definitional bound checks (Apgar, Thompson, SpO2), maternal-age unit handling (`matageyrs` hours-rescue ÷8766; derive `mat_age_date_years` from `matagedate` hours ÷8766 with 9–60 filter), deduplication |
| 12   | `12_boolean_validation` | Standardise Yes/No/TRUE/FALSE -> logical |
| 13   | `13_categorical_object_validation` | Map aliases, remove disallowed values |
| 14   | `14_datetime_validation` | Parse and validate all date/time columns |
| **14a** | `14a_resolve_neolab_datebct` | **Neolab only:** join raw admissions on `uid + facility` to resolve NA `datebct` values; adds `datebct_resolved` (POSIXct) and `datebct_source` columns. Skips instantly for all other datasets. |
| 15   | `15_final_merge_output` | Merge sub-frames, final dedup, strip `.value` suffixes, derive canonical weight columns and the harmonised maternal-age variable (`mat_age_years_combined` + `mat_age_source`, with >1yr disagreement guard → `15b_maternal_age_summary.txt`), save CSV + RDS |
| 00b  | `00b_rename_harmonised_columns` | Rename columns to `snake_case` harmonised names (optional) |
| 16   | `16_na_reason_coding` | Classify every NA cell with a reason code (-6 to -9); write wide, long, and summary companion files |

> **Note:** The PII module is numbered `00a` because it runs immediately after
> setup (00) and before column harmonisation (00b).  It was previously numbered
> `16_pii_detection_removal`, then briefly `00c_pii_detection_removal`.

---

## Data Sources

The pipeline accepts CSV files from two source formats.

### Format 1 -- Direct PostgreSQL export (`DATA_SOURCE = "database"`)

Files exported directly from the Neotree PostgreSQL database.

| Property | Example |
|----------|---------|
| System column names | `facility`, `unique_key`, `uid`, `started_at`, `completed_at`, `ingested_at` |
| Data column names | `BabyCryTriage.value`, `Temperature.value` (CamelCase with dot suffix) |
| `.label` column content | Full question text (e.g. `"Respiratory Rate (breaths/min)"`) |
| Datetime format | ISO 8601 (`"2021-10-08 13:51:01"`) |
| Example files | `admissions_202603121319.csv`, `discharges_202603121212.csv` |

### Format 2 -- Metabase export (`DATA_SOURCE = "metabase"`)

Files exported via Metabase, which is connected to the same PostgreSQL database.

| Property | Example |
|----------|---------|
| System column names | `Facility`, `Unique Key`, `UID`, `Started At`, `Completed At`, `Ingested At` |
| Data column names | `Baby Cry Tria Ge. Value`, `Tempera Tur E. Value` (fragmented CamelCase) |
| `.label` column content | Display label / coded value (same as `.value` for numerics) |
| Datetime format | Human-readable (`"March 2, 2026, 12:33 AM"`) |
| Example files | `admissions_2026-03-12T15_21_00.csv` |

**Both formats produce identical column structures after normalisation** --
Modules 00a and 01 normalise all names to compact lowercase (e.g.
`babycryptriage.value`) before any processing begins.  Set `DATA_SOURCE` in
`00_setup/00_setup.R` to tell the pipeline which format you are using.

---

## Input File Folder Structure

All raw CSV files sit directly in `input/` and must follow the naming convention:

```
input/
+-- {country}_{source}_{dataset}_{date}.csv
+-- ...
```

Where `country` is `mwi` or `zim`, `source` is `db` (PostgreSQL export) or `mb`
(Metabase export), `dataset` is one of the supported types above, and `date` is
`YYYYMMDD` (database) or `YYYY-MM-DD` (metabase).

`run_all.r` auto-discovers and processes every file in `input/` that matches this
pattern.  Files that don't match — or whose dataset name is not in `KNOWN_DATASETS` —
are reported in the skip list.

---

## Supported Dataset Types

| DATASET value | Description | Countries | Extra metadata columns |
|---------------|-------------|-----------|------------------------|
| `admissions` | Standard neonatal admissions | MWI, ZIM | -- |
| `discharges` | Standard neonatal discharges | MWI, ZIM | -- |
| `maternal_outcomes` | Birth / maternal outcomes | MWI, ZIM | -- |
| `phc_admissions` | Primary Health Care admissions | MWI, ZIM | `script_version` |
| `phc_discharges` | Primary Health Care discharges | MWI, ZIM | `script_version` |
| `combined_maternity_outcomes` | Combined maternity (DHIS2 + maternal + completeness) | MWI | `script_version`, `scriptid` |
| `dhis2_maternal_outcomes` | DHIS2-linked maternal source only | MWI | `script_version`, `scriptid` |
| `maternity_completeness` | Maternity completeness source only | MWI | `script_version`, `scriptid` |
| `joined_admissions_discharges` | Admissions + discharges joined (uses admissions dict) | MWI, ZIM | -- |
| `neolab` | Blood culture / laboratory dataset | MWI, ZIM | `script_version`, `scriptid` |
| `baseline` | Retrospective baseline (combined admission+discharge form) | ZIM | `script_version`, `scriptid` |
| `infections` | Longitudinal infection follow-up form | ZIM | `script_version`, `scriptid` |
| `twenty_8_day_follow_up` | 28-day post-discharge follow-up | ZIM | `script_version`, `scriptid` |

### Combined maternity outcomes

The `combined_maternity_outcomes` file is assembled from three source files:

- `dhis2_maternal_outcomes_*.csv`
- `maternal_outcomes_*.csv`
- `maternity_completeness_*.csv`

These are combined **before** running the pipeline.  The resulting file has
extra metadata columns (`scriptid`, `script_version`) which the
pipeline preserves as-is via `cfg$extra_meta_cols`.

### Zimbabwe-specific extended datasets

`baseline`, `infections`, and `twenty_8_day_follow_up` are Zimbabwe-specific forms
that were not previously supported by the pipeline.  Each carries `script_version` and
`scriptid` as trailing metadata columns (same handling as neolab).  Dedicated
dictionaries are generated by `00_build_dictionary_v8.r` when the ZIM data-key export
contains scripts whose titles match the corresponding regex in `DATASET_FILTERS`.

---

## Data Dictionaries

Dictionaries are built by `00_build_dictionary/00_build_dictionary_v8.R`
directly from the official Neotree web-editor data-key exports in
`NEOTREE_DATA_KEYS/DOWNLOADED/`.  No ChatGPT-derived or manually assembled
files are required.

### Supported country x dataset combinations

#### Standard (both countries)

| Dictionary file | Variables | ValueMaps | ReviewNeeded |
|-----------------|-----------|-----------|--------------|
| `Dictionary_ZIM_admissions_v8.xlsx` | 482 | 1,880 | 117 |
| `Dictionary_ZIM_discharges_v8.xlsx` | 420 | 1,272 | 134 |
| `Dictionary_ZIM_maternal_outcomes_v8.xlsx` | 15 | 45 | 0 |
| `Dictionary_MWI_admissions_v8.xlsx` | 260 | 991 | 73 |
| `Dictionary_MWI_discharges_v8.xlsx` | 141 | 837 | 7 |
| `Dictionary_MWI_maternal_outcomes_v8.xlsx` | 24 | 142 | 1 |

#### Neolab (both countries)

| Dictionary file | Description |
|-----------------|-------------|
| `Dictionary_ZIM_neolab_v8.xlsx` | Zimbabwe blood culture / laboratory dataset |
| `Dictionary_MWI_neolab_v8.xlsx` | Malawi blood culture / laboratory dataset |

#### Extended (PHC + Combined Maternity -- generated on next dictionary rebuild)

| Dictionary file | Description |
|-----------------|-------------|
| `dictionary_zim_phc_admissions.xlsx` | Zimbabwe PHC admissions |
| `dictionary_zim_phc_discharges.xlsx` | Zimbabwe PHC discharges |
| `dictionary_mwi_phc_admissions.xlsx` | Malawi PHC admissions |
| `dictionary_mwi_phc_discharges.xlsx` | Malawi PHC discharges |
| `dictionary_mwi_combined_maternity_outcomes.xlsx` | Malawi combined maternity |
| `dictionary_mwi_dhis2_maternal_outcomes.xlsx` | Malawi DHIS2-linked maternal source |
| `dictionary_mwi_maternity_completeness.xlsx` | Malawi maternity completeness source |

#### Extended (Zimbabwe-specific longitudinal & follow-up forms -- generated on next dictionary rebuild)

| Dictionary file | Description |
|-----------------|-------------|
| `dictionary_zim_baseline.xlsx` | Zimbabwe retrospective baseline form |
| `dictionary_zim_infections.xlsx` | Zimbabwe longitudinal infection follow-up |
| `dictionary_zim_twenty_8_day_follow_up.xlsx` | Zimbabwe 28-day post-discharge follow-up |

> **Note:** A dictionary is only generated if the country's data-key export contains
> scripts whose titles match the regex in `DATASET_FILTERS` (in
> `00_build_dictionary/00_build_dictionary_v8.r`).  If a dictionary cannot be built
> (no matching scripts), `00_setup.r` applies the fallback in `DICT_FALLBACK`:
> `baseline` → `admissions` dict; `infections` and `twenty_8_day_follow_up` have no
> fallback and require their own dictionaries.

### Dictionary sheets

| Sheet | Description |
|-------|-------------|
| `Variables` | One row per unique key: `r_type`, `use_in_analysis`, `confidential`, plausible ranges, harmonised name, ... |
| `ValueMaps` | One row per allowed option code with its display label and `canonical_code` |
| `ReviewNeeded` | Items flagged for manual QA -- categoricals with no value map, numerics without ranges |

> **ReviewNeeded** is informational and does not block the pipeline.
> See `00_build_dictionary/00_build_dictionary_v8.R` for details on each category.

### Rebuilding the dictionaries

Run whenever the web-editor keys are updated:

```r
source("00_build_dictionary/00_build_dictionary_v8.R")
```

Alternatively, validate existing dictionaries without rebuilding:

```r
source("00_build_dictionary/validate_dictionaries.r")
# or from the command line:
Rscript 00_build_dictionary/validate_dictionaries.r
```

---

## Quick Start

### Step 1 -- Build the dictionaries (once, or after web-editor key updates)

```r
# Run from cleaning_pipeline_4DSH/
source("00_build_dictionary/00_build_dictionary_v8.r")
```

### Step 2A -- Run all input files automatically (recommended)

```r
source("run_all.r")
```

`run_all.r` scans `input/`, parses every filename, and runs the full pipeline for each
recognised file.  No configuration required — country, dataset, and source format are
all derived from the filename.  Optional filters at the top of `run_all.r` let you
restrict to a subset of files if needed.

### Step 2B -- Run a single file manually

Edit the **User Configuration** section at the top of `00_setup/00_setup.r`:

```r
COUNTRY      <- "ZIM"          # "ZIM" (Zimbabwe) | "MWI" (Malawi)
DATASET      <- "admissions"   # see Supported Dataset Types table above
DATA_SOURCE  <- "database"     # "database" (PostgreSQL export) | "metabase" (Metabase export)
CSV_FILEPATH <- "input/zim_db_admissions_20260501.csv"
DICT_FILEPATH <- NULL          # NULL = auto-resolve dictionaries/dictionary_{country}_{dataset}.xlsx
OUTPUT_CSV   <- NULL           # NULL = auto-named from CSV_FILEPATH
OUTPUT_RDS   <- NULL           # NULL = auto-named from CSV_FILEPATH
REPORT_DIR   <- NULL           # NULL = auto-named; FALSE = suppress all reports
```

Then run:

```r
source("run_pipeline.r")

# Or run modules individually for debugging:
source("00_setup/00_setup.r")
source("00a_pii_detection_removal/00a_pii_detection_removal.r")
source("01_standardise_column_headers/01_standardise_column_headers.r")
# ... etc.
```

---

## Outputs

Each pipeline run creates a dedicated subfolder inside `output/`, named after the
input file stem.  All outputs — cleaned files, reports, and the run log — land there.

```
output/
└── zim_db_admissions_20260501/
    ├── zim_db_admissions_20260501.log
    ├── zim_db_admissions_20260501_cleaned.csv
    ├── zim_db_admissions_20260501_cleaned.rds
    ├── zim_db_admissions_20260501_na_reasons.csv.gz
    ├── zim_db_admissions_20260501_na_reasons_summary.csv
    ├── zim_db_admissions_20260501_na_coded.csv
    └── reports/
```

Optional outputs are controlled by flags in `00_setup/00_setup.r` (see
`how_to_run.md` → **Output file flags** for the full table).

| File | Default | Description |
|------|---------|-------------|
| `*_cleaned.csv` | always | Final clean dataset — bare variable names (no `.value` suffix) |
| `*_cleaned.rds` | always | Final clean dataset (R binary format) |
| `*_na_reasons.csv.gz` | always | Wide-format NA reason codes — same shape as cleaned dataset. **Gzip-compressed** (Module 16) |
| `*_na_reasons_summary.csv` | always | Per-variable completeness summary, sorted by n_missing. Plain CSV (Module 16) |
| `*.log` | always | Pipeline log for this run |
| `*_na_coded.csv` | **on** | Cleaned data with NA cells replaced by reason codes (-6/-7/-8/-9) (Module 16) |
| `*_deidentified.csv` | off | Raw data with PII removed (Module 00a) |
| `*_cleaned_stage1.rds` | off | Checkpoint after first-stage cleaning (Module 10) |
| `*_cleaned_harmonised.csv` | off | Final clean dataset with snake_case harmonised column names (Module 00b) |
| `*_cleaned_harmonised.rds` | off | Harmonised dataset in R binary format (Module 00b) |
| `*_na_reasons_long.csv.gz` | off | Long-format NA reasons — one row per NA cell. **Gzip-compressed** (Module 16) |
| `reports/` | always | Per-module text reports |

---

## PII Policy

Module 00a (`00a_pii_detection_removal`) **must run immediately after setup**,
before any data cleaning.  It operates in three tiers:

1. **Removes** columns flagged as `confidential = TRUE` in the v8 dictionary
2. **Removes** any remaining columns matching known PII name patterns
   (names, phone numbers, addresses, healthcare worker IDs, hospital numbers)
3. **Flags** quasi-identifiers (district, village, tribe, ethnicity, religion,
   address) in the audit report -- these are **not** automatically removed

The original raw CSV is never modified.  PII removal always runs in-memory;
a `*_deidentified.csv` copy is optionally written to disk (controlled by the
`SAVE_DEIDENTIFIED` flag, default `FALSE`).

**Review `reports/00a_pii_audit_report.txt` before sharing any dataset.**

---

## Dependencies

Install required R packages with:

```r
install.packages(c(
  "jsonlite", "readr", "readxl", "writexl",
  "dplyr", "tidyr", "stringr", "lubridate",
  "purrr", "logger", "janitor"
))
```

Dictionary validation uses R (no extra packages beyond those already required by the pipeline):

```r
source("00_build_dictionary/validate_dictionaries.r")
```

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| v8 | 2026-07-10 | **Harmonised maternal-age variable implemented (Modules 11 + 15).** Maternal age is captured on the deliveries form in two fields that no single column cleans: `matageyrs` (manual whole years, both sites, range 9–60) and `matagedate` (auto-calculated from DOB, KCH/MWI only, **stored in hours** — divide by 8766 = 365.25×24 for years). **Module 11** now derives `mat_age_date_years = round(matagedate / 8766)` and applies the same 9–60 plausibility filter (out-of-range → NA, counted in the Module 11 report), leaving raw `matagedate` untouched; the existing `matageyrs` hours-rescue divisor was standardised 8760 → **8766** to match. **Module 15** `derive_maternal_age_columns()` (after suffix stripping, before output, mirroring `derive_weight_columns()`) adds **`mat_age_years_combined = coalesce(matageyrs, mat_age_date_years)`** (manual field wins) and provenance **`mat_age_source ∈ {matageyrs, matagedate_derived, none}`**, emitted only where a source column is present so ZIM (matageyrs only) and MWI (both) share one schema. **Disagreement guard:** rows where both fields are present and differ by >1 year are counted and logged (never overwritten) → `15b_maternal_age_summary.txt`. Implausible ages flow through the standard machinery: filtered in Module 11, NA-reason-coded **-8 (invalid/removed)** by Module 16 on the source columns. **Verified (25 June extract):** SMCH/ZIM combined 25,816 (21.0%, all `matageyrs`); KCH/MWI combined 3,636 (25.7%) = 3,009 `matageyrs` + 627 `matagedate_derived` (15 implausible dropped), with 16/24 overlapping rows (66.7%) disagreeing >1yr and flagged. High baseline missingness (~74–85%) is a collection-timing artefact (field added to the form 12 Nov 2024 KCH / 3 Jul 2025 SMCH). **NB:** verified by logic checks + a Python dry-run on the cleaned extracts; run `Rscript` end-to-end before a production run. See `readme.md` → "Maternal age". |
| v8 | 2026-06-24 | **Canonical weight columns implemented (Module 15).** Investigation of the apparent KCH 2025 birth-weight "collapse" found it was a form-version column handover, not data loss. Three distinct weight concepts and their column mappings were established: birth weight = `birthweight`/`bwt`/`bwtdis` (same concept; `bwtdis` is birth weight despite its name; identical where overlapping, max diff 0 g); admission weight = `admissionweight` (distinct); discharge/last-recorded weight = `dischweight` + `datedischweight` (distinct). MWI moved maternal birth weight from `bwtdis` to `birthweight` at 2025; MWI discharges lacked a birth-weight field before ~`script_version` 137 (2023); ZIM keeps maternal birth weight in `bwtdis`. **Implemented:** `derive_weight_columns()` in Module 15 (after suffix stripping, before output) adds `birthweight_g = coalesce(birthweight, bwt, bwtdis)` (always emitted, NA where no source), `admission_weight_g`, and `discharge_weight_g` (emitted where their source is present), keeping originals untouched. Includes a >1 g disagreement guard (warns; verified 0 disagreements on the 10 June extract) and an idempotent defensive kg→g guard (values ≤20 treated as kg). Verified: combined maternity `birthweight_g` coverage 12,215/14,090 vs ~3,514 from `birthweight` alone. **Dictionary registration done:** the three derived columns are registered via `DERIVED_VARIABLES` in `00_build_dictionary.r` (documentation-only rows; `raw_value_column` = NA keeps them out of the cleaning feature lists), so they appear in the per-table dictionaries and the 00d user dictionary on the next rebuild. **Sample-maker dependency unchanged:** `prob_matcher.R` keys on the literal `birthweight` column — preserved (originals untouched), so the probabilistic join is unaffected. See `readme.md` → "Weight variables". |
| v8 | 2026-06-12 | **Categorical value harmonisation (decision-free layer).** Audit of the 10 June 2026 extract found 292 categorical variables emitting values that were not reduced to dictionary canonical codes (~1.12M cell values; case variants, legacy booleans, multi-select case, and historical codes from older form versions). Record-level split vs the full multi-version data-key option set: **51.7% mechanical / 42.7% unresolved legacy / 5.6% semantic.** Changes: (1) **Module 04** `clean_values_using_dict` rewritten to emit canonical codes via case-insensitive code/label matching, raw->canonical conversion, legacy boolean->`Y`/`N` on yes/no fields, and multi-select token case-folding -- **unresolved values are left untouched (never guessed) and logged**. (2) **`00_setup.r`** `value_map_list` gained `canonical_codes` and `code_to_canonical`. (3) **`00_build_dictionary.r`** ValueMaps now augmented with the **union of option codes/labels across all non-deleted data-key versions** (rescues legacy options such as `fontanelle Flat`, `resus` interventions, `ttv` dose codes). (4) **`og_dictionaries` dependency removed** from `00d_build_user_dictionary.r`; the dictionary chain now builds solely from the downloaded web-editor data keys. **Information-preservation guarantee (two protections):** the harmonisation is lossless -- it never merges distinct categories -- because (a) **exact existing codes are always preserved** before any case logic runs (so e.g. `curprob` `PN`=Pneumonia and `Pn`=Pain are never folded together), and (b) a **per-key ambiguity guard** disables case-folding for the 15 variables whose codes/labels differ only by case but mean different things (`tribe`, `curprob`, `hcwsig`, `plan`, ...), leaving stray-case values unresolved rather than guessed (the guard removed zero legitimate changes). The ~239,000 cell changes are all representational normalisations (encoding/case/label->code/multi-select case) of the same value. **Caveat:** these protections guarantee no *merging* of distinct categories, but the *correctness* of each mapping rests on the `ValueMaps` dictionary being right -- a wrong dictionary row is faithfully propagated, so the dictionaries (especially union- and `VALUEMAP_PATCHES`-added rows) should be reviewed as release QA. Genuinely ambiguous legacy values (e.g. `inorout` yes/no vs `In`/`Out`, `modedelivery` numeric `1`, `admittedfrom` `ER`) are parked for clinical-team confirmation -- the per-run Module 04 report lists them under "Unresolved values left untouched", and `MANUAL.txt` (Appendix: Variable Issues Catalogue) records the known cases. **NB:** these edits were verified by static/logic checks but not yet executed in R -- validate with `Rscript` before a production run. |
| v8 | May 2026 | **Dictionary: `hivtestresult` column retention fix (MWI).** `hivtestresult` was incorrectly classified as `confidential = TRUE / pii_tier = 1 / direct_identifier` in both MWI admissions and discharges dictionaries, causing Module 00a (PII removal) to drop the column before any cleaning ran. HIV test result is a clinical outcome, not a direct identifier. Fixed: `confidential` set to `FALSE` in `dictionary_mwi_admissions.xlsx` and `dictionary_mwi_discharges.xlsx` (including `hivtestresultdc`). ZIM was unaffected — `hivtestresult` was absent from the ZIM dictionary and passed through the non-validated passthrough. `hivtestresult` added to `dictionary_zim_admissions.xlsx` as `categorical` so Module 04 value cleaning now applies. |
| v8 | May 2026 | **Dictionary: `hivtestresult` value standardisation (MWI + ZIM).** KCH (MWI) raw data uses a mix of short codes (`R`, `NR`, `U`) and full labels (`Reactive`, `Non Reactive`); ZIM raw data uses `R`/`NR`/`U` and long-form variants (`Positive`, `Negative`, `Unknown`). Target codes: `R` (reactive), `NR` (non-reactive), `U` (unknown/indeterminate). MWI ValueMaps already contained correct `option_label → canonical_code` mappings (Reactive→R, Non Reactive→NR, Unknown→U); these now apply because the column survives PII removal. ZIM admissions ValueMaps added: Positive→R, Negative→NR, Unknown→U with allowed codes R/NR/U. |
| v8 | May 2026 | **Dictionary: PII misclassification audit — four additional MWI fields unblocked.** A systematic review of all `confidential = TRUE` fields across MWI and ZIM dictionaries identified four MWI clinical-outcome fields incorrectly classified as `direct_identifier`: `datehivtest` (date of HIV test, datetime), `haart` (mother on HAART, categorical Y/N), `lengthhaart` (HAART treatment timing, categorical), and `mathivstat` (mother's HIV status, categorical). None of these identify a person in isolation. ZIM has `mathivstat` as `confidential = FALSE`; the other three are absent from ZIM dictionaries and pass through the pipeline untouched. All four have `confidential` set to `FALSE` in `dictionary_mwi_admissions.xlsx` (all four) and `dictionary_mwi_discharges.xlsx` (datehivtest, haart, lengthhaart). Existing ValueMaps for haart, lengthhaart and mathivstat were already correct. |
| v8 | May 2026 | **Dictionary: `mecpresent` and `mecthickthin` canonical code alignment (ZIM discharges).** `mecpresent` raw codes in ZIM discharges were N/U/Y with identical canonical codes, diverging from the No/UNK/Yes canonical codes used in MWI adm, MWI dis, and ZIM adm. `mecthickthin` had raw code `U` mapping to canonical `U` in ZIM discharges, vs `UNK` in all other dicts. Fixed: ZIM discharges ValueMaps updated so `mecpresent` canonical_code → No/No/UNK/Yes (N→No, U→UNK, Y→Yes) and `mecthickthin` canonical U→UNK. |
| v8 | May 2026 | **Dictionary: `lengthhaart` duplicate ValueMaps row removed (MWI adm + dis).** Both MWI dictionaries had `3rdTrim` appearing twice in the ValueMaps for `lengthhaart` — once with label "3rd Trimester more than 1 month before delivery" and once with label "3rd Trimester". The shorter duplicate row was removed from `dictionary_mwi_admissions.xlsx` and `dictionary_mwi_discharges.xlsx`. |
| v8 | May 2026 | **Dictionary: 7 boolean fields reclassified to categorical in MWI dicts.** Seven fields typed `boolean` in MWI were typed `categorical` in ZIM, producing `TRUE`/`FALSE` from Module 12 in MWI vs `Y`/`N`/`U` from Module 13 in ZIM — preventing cross-site alignment. Fields reclassified in MWI admissions: `mathivtest`, `birthplacesame`, `dysmorphic`, `feversr`, `ortolani`. Fields reclassified in MWI discharges: `mathivtest`, `birthplacesame`, `inorout`, `phototherapy`. ValueMaps added for each field — Y/N/U (with Unknown option where ZIM uses it); `inorout` uses In/Out matching MWI adm and ZIM. Note: `ortolani` uses Y/N in MWI (raw data) vs ZIM's YesOrto/NoOrto — both are now categorical but codes differ by site. `dysmorphic` adds only Y/N in MWI; ZIM carries an extended set of specific dysmorphic features not present on the MWI form. |
| v8 | May 2026 | **Per-run output subfolders**: all outputs for a given input file now land in `output/<file_stem>/` (e.g. `output/zim_db_admissions_20260501/`). The per-run log is written there as `<file_stem>.log`. Reports go into `output/<file_stem>/reports/`. |
| v8 | May 2026 | **Output file flags added**: five boolean flags (`SAVE_DEIDENTIFIED`, `SAVE_STAGE1_CHECKPOINT`, `SAVE_HARMONISED`, `SAVE_NA_CODED`, `SAVE_NA_REASONS_LONG`) added to the User Configuration block in `00_setup.r`. Defaults: deidentified=off, stage1=off, harmonised=off, na_coded=on, na_reasons_long=off. The `*_clean_coded.csv` output is renamed to `*_na_coded.csv` for clarity. PII removal always runs in-memory regardless of `SAVE_DEIDENTIFIED`. |
| v8 | May 2026 | **Three new ZIM dataset types added**: `baseline` (retrospective combined admission+discharge form), `infections` (longitudinal infection follow-up), `twenty_8_day_follow_up` (28-day post-discharge follow-up). All three added to `VALID_DATASETS` in `00_setup.r`, with correct `EXTRA_META_COLS` (`script_version`, `scriptid`) and standard `TIMESTAMP_COLS`. Dictionary filters added to `00_build_dictionary_v8.r`; ZIM `BUILD_PLAN` updated. `baseline` falls back to the `admissions` dictionary if no dedicated dictionary has been built. |
| v8 | May 2026 | **Batch runner `run_all.r` added**: scans `input/`, parses every CSV filename (convention: `{country}_{source}_{dataset}_{date}.csv`), and runs the full pipeline for each recognised file automatically. Handles multi-word dataset names (`twenty_8_day_follow_up`, `combined_maternity_outcomes`, etc.) correctly. Files with unrecognised names or dataset types are reported in a skip list. |
| v8 | May 2026 | **`00_setup.r` made injectable**: all user-configuration variables (`COUNTRY`, `DATASET`, `DATA_SOURCE`, `CSV_FILEPATH`, etc.) are now guarded with `if (!exists(...))` checks, so `run_all.r` (or any other calling script) can pre-set them before sourcing `00_setup.r` without having them overwritten by defaults. |
| v8 | April 2026 | **Module 08** reclassified as a no-op. DC-suffix columns (`apgar1dc`, `gestationdc`, `hivtestresultdc`, etc.) are now retained as independent discharge-form entries alongside their admission counterparts. Investigation confirmed zero row overlap between DC and admission versions in MWI discharges, and `hivtestresultdc` is the primary HIV result source for 16,109 records. See `08_drop_autopopulated_columns/README.md` for full rationale. |
| v8 | April 2026 | **Module 15** now strips `.value` and `.valuedischarge` suffixes from all column names before saving, aligning output column names with the Jupyter pipeline (`remove_suffixes()` step). Final CSV/RDS now uses bare variable names (e.g. `age`, `birthweight`). Module 00b (`rename_harmonised_columns`) is unaffected. |
| v8 | March 2026 | Dictionary rebuilt from DOWNLOADED web-editor keys only (no ChatGPT dependencies). Malawi-specific type `mwi_edliz_summary_table` mapped. Python validation script added. |
| v8 | March 2026 | `DATA_SOURCE` option added to `00_setup.R` -- supports both direct PostgreSQL exports and Metabase exports. |
| v8 | March 2026 | PII module renumbered `16_pii_detection_removal` -> `00c_pii_detection_removal` -> `00a_pii_detection_removal` to reflect true execution order (before `00b` column harmonisation). |
| v8 | March 2026 | New dataset types added: `phc_admissions`, `phc_discharges` (both countries), `combined_maternity_outcomes` (Malawi only). PHC files carry extra `script_version` / `script_id` metadata columns tracked via `cfg$extra_meta_cols`. |
| v8 | March 2026 | `joined_admissions_discharges` dataset type added (analysis-time join; falls back to admissions dictionary). |
| v8 | March 2026 | Dictionary fallback logic added to `00_setup.R`: PHC datasets fall back to admissions/discharges dict if no PHC-specific dict is available. |
| v8 | March 2026 | Input file folder structure updated to `2026-03-20_for_cleaning_pipeline/` with ZIM/MWI x DB/METABASE subfolders. |
| v8 | April 2026 | **Module 16** (NA reason coding) integrated into `run_pipeline.R` -- runs automatically after Module 00b as the final pipeline step. No longer needs to be sourced separately. Outputs: `*_na_reasons.csv.gz`, `*_na_reasons_long.csv.gz`, `*_na_reasons_summary.csv`. |
| v8 | April 2026 | **Module 16 output format**: the two large NA reason files are now written as gzip-compressed CSV (`.csv.gz`), reducing combined size by ~85-90% (~420 MB -> ~50 MB). Lossless compression. Read with `readr::read_csv()` (R) or `pandas.read_csv()` (Python) -- no manual decompression needed. The summary file remains plain CSV. |
| v8 | May 2026 | **Module 14a added (`14a_resolve_neolab_datebct`):** for the `neolab` dataset, rows with missing or unparseable `datebct` (date blood culture taken) are now resolved by joining to the raw admissions file on `uid + facility` and using `datetimeadmission` as a proxy date. Two new columns are added to the cleaned neolab output: `datebct_resolved` (POSIXct -- best available blood culture date) and `datebct_source` (character: `"original"` / `"from_admission"` / `NA`). The original `datebct` column is never modified. Controlled by the `RESOLVE_NEOLAB_DATEBCT` flag in `00_setup.r` (default `TRUE`). The module exits immediately for all non-neolab datasets. |
| v8 | April 2026 | `neolab` dataset type added (blood culture / laboratory data, both countries). Dictionaries `Dictionary_ZIM_neolab_v8.xlsx` and `Dictionary_MWI_neolab_v8.xlsx` generated on next dictionary rebuild. |

---

*Pipeline developed for the Neotree research programme.*
*Countries: Malawi (MWI) . Zimbabwe (ZIM)*

# Module 16 -- NA Reason Coding

## Purpose

Every blank cell in the cleaned output file is an `NA` in R terms.  But not
all NAs are equal: a field that was never shown to the data-entry user is
very different from a field that was shown but left blank, or a field whose
value the pipeline removed because it was out of range.

Module 16 examines every NA cell in the cleaned dataset and assigns a reason
code explaining *why* it is missing.  The codes are written to companion files
alongside the cleaned CSV -- the cleaned data itself is never modified.

---

## Why the codes are not written into the cleaned file

The reason codes are integers (-6, -7, -8, -9).  If they were written into a
column that otherwise contains, for example, hours or a categorical blood
culture result, that column would have to become character type.  Every
downstream analysis would then need to strip the negative codes before
calculating means, fitting models, or producing plots -- a significant and
error-prone burden on every analyst who uses the data.

The standard epidemiological approach is to keep the analysis file clean and
type-correct, and provide the missingness information as companion files that
can be joined when needed.

---

## Output files

Three files are written to the `output/` folder for every pipeline run.

The two large files (`*_na_reasons` and `*_na_reasons_long`) are written as
**gzip-compressed CSV** (`.csv.gz`).  The compression is lossless -- no
information is lost -- and reduces file sizes by approximately 85-90%
(typically from ~40 MB and ~380 MB down to ~5 MB and ~45 MB respectively).
All standard analysis tools handle `.csv.gz` natively; see *Reading the output
files* below.

### 1. `*_na_reasons.csv.gz`  (wide format)

Same shape as the cleaned dataset -- same rows, same columns.  Every cell
that is NA in the cleaned output is replaced with a reason code.  Cells that
are NOT NA in the cleaned output are left blank.

Use this file when you want to add missingness information back to the cleaned
data column by column.  Join on the record identifier (`uid`).

### 2. `*_na_reasons_long.csv.gz`  (long format)

One row per NA cell, with columns:

| Column | Description |
|--------|-------------|
| `uid` | Record identifier -- links back to the cleaned dataset |
| `facility` | Facility name |
| `variable` | Name of the variable that is NA |
| `na_reason` | Reason code (see table below) |
| `raw_value` | The value that was present in the raw data (blank if the field was empty to begin with) |

Use this file for auditing, completeness analysis, or feature engineering
where you need to know the raw value that was removed.

### 3. `*_na_reasons_summary.csv`  (per-variable summary)

One row per variable in the cleaned dataset, sorted by `n_missing` descending
so the most-problematic variables appear first.

| Column | Description |
|--------|-------------|
| `variable` | Variable name |
| `n_total` | Total number of records |
| `n_present` | Number of records where this variable is not NA |
| `n_missing` | Total number of NA cells for this variable |
| `pct_missing` | Percentage missing (0-100) |
| `n_not_applicable` | Count of -7 codes (field was skipped by form logic) |
| `n_invalid` | Count of -8 codes (value existed but was removed by pipeline) |
| `n_unknown` | Count of -9 codes (field was shown but left blank) |
| `n_redacted` | Count of -6 codes (value existed but was removed as PII) |

This is the most useful file for a quick overview of data completeness.  A
condensed version (top 20 most-missing variables) also appears in the text
report at `output/*_reports/16_na_reason_coding_summary.txt`.

---

## NA reason codes

| Code | Label | Meaning |
|------|-------|---------|
| `-6` | Redacted (PII) | A value was present in the raw data but was removed by Module 00a because it matched a PII pattern (e.g. a name or identifier). |
| `-7` | Not applicable | The field was not shown to the data-entry user because the form's conditional skip logic determined it was not relevant for this record (e.g. a "culture sensitivity" result field that only appears when the culture was positive). This is expected missingness and should not be treated as a data quality problem. |
| `-8` | Invalid / removed | A value was present in the raw data but was removed by the pipeline because it failed a validation check -- typically an out-of-range numeric (Module 11), a disallowed categorical code (Module 13), or a type mismatch (Module 09). |
| `-9` | Unknown | The field was present in the form and shown to the user, but was simply not filled in.  This is uninformative missingness: we do not know whether the information was unavailable, forgotten, or not applicable in a way the form logic did not capture. |

---

## Reading the output files

The `.csv.gz` files are read identically to plain `.csv` files in all common
analysis tools -- no decompression step is needed.

**In R (readr):**

```r
library(readr)
reasons_long <- read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons_long.csv.gz")
reasons_wide <- read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons.csv.gz")
```

**In Python (pandas):**

```python
import pandas as pd
reasons_long = pd.read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons_long.csv.gz")
reasons_wide = pd.read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons.csv.gz")
```

The uncompressed summary file (`*_na_reasons_summary.csv`) is small and
remains uncompressed for convenience.

---

## How to use the files in analysis

**To distinguish expected from uninformative missingness:**

```r
library(dplyr)
library(readr)

clean   <- read_csv("output/zim_db_admissions_20260331_cleaned.csv")
reasons <- read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons_long.csv.gz")

# How many records had bcreturntime genuinely not entered (vs skipped)?
reasons %>%
  filter(variable == "bcreturntime") %>%
  count(na_reason)
# -7 = form logic skipped it (expected)
# -9 = shown but not filled in (completeness problem)
```

**To get an overview of completeness for all variables:**

```r
summary <- read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons_summary.csv")
head(summary, 20)   # top 20 most-missing variables
```

**To add reason codes back to the cleaned data for a specific variable:**

```r
wide <- read_csv("output/zim_db_admissions_20260331_cleaned_na_reasons.csv.gz")
# wide has the same columns as clean; NA cells contain reason codes

# Find all records where bcreturntime was removed as invalid
invalid_bc <- wide[!is.na(wide$bcreturntime) & wide$bcreturntime == -8, "uid"]
```

---

## Note on database vs metabase source format

When running the pipeline on the **database** format, values that fail numeric
or type validation are flagged as `-8 Invalid/removed`.

When running on the **metabase** format, the same values may already have been
coerced to strings by the Metabase export, so the pipeline does not detect
them as type-invalid.  Those cells end up as `-9 Unknown` instead of `-8`.

This means the **database format gives more informative missingness
classification** and is recommended for primary analysis.  If the two formats
produce identical row counts and variable distributions after cleaning, the
database output should be used.

---

## Technical notes

- Module 16 reads the raw input CSV directly (before any pipeline
  modifications) to recover the original values for the `raw_value` column
  and for evaluating form skip conditions.
- Skip conditions are evaluated using the Neotree JSON script files in
  `neotree_scripts/`.  If a script cannot be matched to a record, skip-logic
  classification falls back to `-9 Unknown` for that record.
- The module requires `df_clean` (output of Module 15 or 00b) to be present
  in the R session before it runs.

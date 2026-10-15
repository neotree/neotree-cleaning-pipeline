# Module 15: Final Merge and Output

## Purpose

Joins the validated sub-frames into one dataset, strips the column-name suffixes, derives the combined weight and maternal-age columns, checks that no personal information is present, and writes the cleaned CSV and RDS files.

## When it runs

After Modules 11 to 14 and 14a.

## What it does

### 1. Pass-through sub-frame

Columns of `df` that are in none of the type lists (`cfg$num`, `cfg$bool`, `cfg$cat`, `cfg$obj`, `cfg$dt`) are collected into `df_non_validated` and converted to character. A column counts as listed when its name, its name without the `.value` or `.valuedischarge` suffix, or that base name with `.value` added appears in a type list. The key columns are always included.

### 2. Deduplication

Each sub-frame is reduced to one row per key, keeping the row with the fewest missing values. The same rule is applied again to the merged result.

| `cfg$skip_dedup_stage2` | Key |
|-------------------------|-----|
| `FALSE` | `uid`, `facility` |
| `TRUE` | `uid`, `facility`, `uniquekey` |

### 3. Merge

Starting from `df_numeric`, the other sub-frames are left-joined on `facility`, `uid` and `uniquekey` in this order: boolean, categorical, datetime, pass-through. At each join only columns not already present are added.

### 4. Column names

The suffixes `.value` and `.valuedischarge` are removed from all column names.

### 5. Derived weight columns

Source columns are not changed. In the derived columns a value above 0 and up to 20 is multiplied by 1000, so that the result is in grams.

| Column | Content | Added |
|--------|---------|-------|
| `birthweight_g` | First non-missing of `birthweight`, `bwt`, `bwtdis`, in that order | Always; `NA` when none of the three is present |
| `admission_weight_g` | `admissionweight` | When `admissionweight` is present |
| `discharge_weight_g` | `dischweight` | When `dischweight` is present |

When two birth-weight sources are present on the same row and differ by more than 1 g, the number of such rows is logged as a warning.

### 6. Derived maternal-age columns

Added when `matageyrs` or `mat_age_date_years` (from Module 11) is present. Source columns are not changed.

| Column | Content |
|--------|---------|
| `mat_age_years_combined` | `matageyrs` where present; otherwise `mat_age_date_years` |
| `mat_age_source` | `"matageyrs"`, `"matagedate_derived"` or `"none"` |

When both sources are present on the same row and differ by more than 1 year, `matageyrs` is used and the number of such rows is logged and reported.

### 7. Output

For the CSV, date-time columns are written as `YYYY-MM-DD HH:MM:SS` (UTC), a trailing `.000` is removed from text values, and `NA` is written as an empty field. The RDS keeps the typed columns.

Before anything is written, `assert_pii_removed()` (`00_setup.r`) checks the data frame prepared for the CSV. It stops the run if the completion marker of Module 00a is missing or does not match the current input file and dictionary, if a column name matches a variable flagged confidential in the dictionary or a personal-information name pattern, or if a value matches a personal-information value pattern. A failure to write the CSV or the RDS is logged as a warning.

## Inputs

| Object | Description |
|--------|-------------|
| `df_numeric`, `df_boolean`, `df_categorical`, `df_datetime` | Sub-frames from Modules 11 to 14 and 14a |
| `df` | Data frame from Module 10, used for the pass-through sub-frame |
| `cfg` | Configuration list: type lists, `$skip_dedup_stage2`, `$output_csv`, `$output_rds`, `$report_dir` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_clean` | Merged data frame |
| `cfg$output_csv` | Cleaned CSV; by default `<file_stem>_cleaned.csv` in the run output folder |
| `cfg$output_rds` | Cleaned RDS; by default `<file_stem>_cleaned.rds` in the run output folder |
| `reports/15_final_merge_summary.txt` | Input and output paths, final numbers of rows and columns, number of pass-through columns |
| `reports/15b_maternal_age_summary.txt` | Written when the maternal-age columns are derived: rows per `mat_age_source`, rows with both sources, rows that disagree. Counts only. |

## Functions

| Function | Returns |
|----------|---------|
| `merge_and_output(df_numeric, df_boolean, df_categorical, df_datetime, df_full, cfg)` | The merged data frame, after writing the output files |
| `dedup_keep_most_complete(df, key_cols)` | `df` with one row per key, the most complete |
| `build_non_validated(df_full, cfg)` | The pass-through sub-frame, or `NULL` when there are no such columns |
| `derive_weight_columns(df, cfg)` | `df` with the derived weight columns |
| `derive_maternal_age_columns(df, cfg)` | `df` with the derived maternal-age columns |
| `format_datetimes_for_csv(df)` | `df` with date-time columns as text |

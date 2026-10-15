# Module 11: Numeric Validation

## Purpose

Checks every numeric column: removes values that are not numbers, puts weights in grams and maternal age in years, and sets values outside the dictionary range to `NA`. Produces the numeric sub-frame used in the final merge.

## When it runs

After Module 10. Modules 11 to 14 each read the same data frame from Module 10 and each produce one sub-frame for Module 15.

## What it does

The sub-frame holds the key columns `facility`, `uid` and `uniquekey` and the columns of `cfg$num` present in `df`. Each numeric column goes through the steps below, in this order. A column is matched to the dictionary by its name without the `.value` or `.valuedischarge` suffix.

| Step | Applies to | Rule |
|------|-----------|------|
| 1. Non-numeric values | every numeric column | A value that `as.numeric()` cannot read becomes `NA`. |
| 2. Kilograms to grams | columns listed in `cfg$weight_cols` | A value of 20 or less is multiplied by 1000, e.g. `3.5` becomes `3500`. |
| 3. Hours to years | `matageyrs` | A value above 200 is divided by 8766 (hours in a year of 365.25 days) and rounded to one decimal place. |
| 4. Dictionary range | columns with an entry in `cfg$range_lookup` | A value below the minimum or above the maximum becomes `NA`. A missing minimum or maximum is not checked. |

After step 2, weight values below 100 g or above 5000 g are counted and reported as a warning. They are not changed.

### Derived column `mat_age_date_years`

`matagedate` holds maternal age in hours. When `matagedate.value` or `matagedate` is among the numeric columns, a new column is added:

`mat_age_date_years` = `matagedate` / 8766, rounded to a whole number of years.

Derived values below 9 or above 60 become `NA`. The `matagedate` column is not changed by this step.

### Duplicate keys

The first row for each key is kept. The key is `uid` and `facility`; for datasets that keep every visit (`cfg$skip_dedup_stage2` is `TRUE`) it is `uid`, `facility` and `uniquekey`.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 10 |
| `cfg$num` | Names of the numeric columns |
| `cfg$weight_cols` | Dictionary variables whose `weight_unit` is grams |
| `cfg$range_lookup` | Table of `question_key`, `min`, `max`, taken from `suggested_plausible_min` and `suggested_plausible_max` of the numeric dictionary variables |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_numeric` | Key columns and validated numeric columns, plus `mat_age_date_years` where `matagedate` is present |
| `reports/11_numeric_validation_report.txt` | Number of values changed at each step, out-of-range counts per column with the range applied, the weight columns, the maternal-age conversions, and the weight warning. Counts and column names only. |

## Function

`validate_numeric(df, cfg, report_filepath = NULL)` returns the numeric sub-frame.

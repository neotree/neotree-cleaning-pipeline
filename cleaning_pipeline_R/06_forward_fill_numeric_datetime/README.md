# Module 06: Forward Fill Numeric and Datetime Values

## Purpose

Fills missing values from the paired label column where the label is a number or a datetime, then drops the paired label columns.

## When it runs

After Module 05.

## What it does

Columns are paired by name: each `.value` column with the `.label` column of the same variable, and each `.valuedischarge` column with its `.labeldischarge` column. Every pair is processed, whatever the variable's dictionary type.

In each pair, the rows where the value is `NA` and the label is not are examined in two passes.

### Numbers

A label is read as a number when it holds only digits, `.`, `,`, `+`, `-` and spaces, and `parse_numeric_by_shape()` in `00_setup.r` returns a number for it.

| Label | Written to the value column |
|-------|-----------------------------|
| `3500`, `3.5`, `-2` | the number |
| `3,500`, `1,234,567.8` | 3500, 1234567.8 (thousands separators removed) |
| `3,5` | 3.5 (decimal comma) |

A label holding any letter or other character is not filled in this pass. The number is written as text, using `as.character()`.

### Datetimes

Rows still `NA` after the first pass are read by `parse_datetime_by_shape()` in `00_setup.r`, which accepts ISO, day-first and month-name values and reads them as described for Module 09. A label that parses is written to the value column as text, using `as.character()` on the parsed date-time. A label that fits no shape is not used, and the value stays `NA`.

### Label columns

A pair whose field is listed in `cfg$label_value_rules` is not examined in either pass, because Module 05 has already read it. The label column of every pair is dropped, whether or not anything was filled. Label columns with no paired value column are left in place.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 05 |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with values filled and paired label columns removed |
| `reports/06_forward_fill_numeric_datetime_report.txt` | Number of value columns with a fill, total number of values filled and the number filled in each of those columns. |

## Function

`forward_fill_numeric_datetime(df, report_filepath = NULL)` returns the updated data frame.

# Module 12: Boolean Validation

## Purpose

Sets every boolean column to `TRUE`, `FALSE` or `NA`. Produces the boolean sub-frame used in the final merge.

## When it runs

After Module 10. Modules 11 to 14 each read the same data frame from Module 10 and each produce one sub-frame for Module 15.

## What it does

The sub-frame holds the key columns `facility`, `uid` and `uniquekey` and the columns of `cfg$bool` present in `df`.

Each value is trimmed, put in lower case and compared with two lists defined in `00_setup.r` and shared with Module 09.

| List | Values | Result |
|------|--------|--------|
| `NEOTREE_TRUE_TOKENS` | `true`, `yes`, `y`, `1`, `t` | `TRUE` |
| `NEOTREE_FALSE_TOKENS` | `false`, `no`, `n`, `0`, `f` | `FALSE` |
| neither | anything else | `NA` |

The number of values set to `NA` is logged per column, as a count only.

The first row for each key is then kept. The key is `uid` and `facility`; for datasets that keep every visit (`cfg$skip_dedup_stage2` is `TRUE`) it is `uid`, `facility` and `uniquekey`.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 10 |
| `cfg$bool` | Names of the boolean columns |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_boolean` | Key columns and validated boolean columns |
| `reports/12_boolean_validation_report.txt` | Number of values set to `TRUE` or `FALSE`, number set to `NA`, duplicate rows removed, final row count |

## Function

`validate_boolean(df, cfg, report_filepath = NULL)` returns the boolean sub-frame.

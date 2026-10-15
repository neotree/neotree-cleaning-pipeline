# Module 14: Datetime Validation

## Purpose

Reads every datetime column as a date-time, sets values that are not a recognised datetime to `NA`, and derives `hepbdate_date`. Produces the datetime sub-frame used in the final merge.

## When it runs

After Module 10. Modules 11 to 14 each read the same data frame from Module 10 and each produce one sub-frame for Module 15. Module 14a runs next and adds columns to the sub-frame produced here.

## What it does

The sub-frame holds the key columns `facility`, `uid` and `uniquekey` and the columns of `cfg$dt` present in `df`.

Each value is read by `parse_datetime_by_shape()` in `00_setup.r`, the parser also used by Module 09. Each value is parsed by the rule for its own shape, and the result is POSIXct in UTC.

| Shape | Examples | Read as |
|-------|----------|---------|
| ISO | `2023-10-19 22:00:00`, `2023-10-19T22:00:00Z`, `2023-10-19` | Year, month, day. A trailing `Z` or UTC offset is dropped; the time is kept as written. |
| Day first | `19/10/2023`, `19-10-2023`, `19.10.2023` | Day, month, year. A two-digit year is read as 20yy. A value that is only valid as month/day/year becomes `NA`. |
| Month name | `March 2, 2026, 12:33 AM`, `2 March 2026`, `19-Oct-2023` | Full or abbreviated English month names; 12-hour or 24-hour time. |
| Anything else | free text, digits without separators | `NA` |

The number of values set to `NA` is logged per column, as a count only.

### Derived column `hepbdate_date`

The `hepbdate` column can hold yes/no answers and dates in the same column. When `hepbdate.value` or `hepbdate` is present in `df` and is not itself a datetime column, a new datetime column `hepbdate_date` is added. It holds the values of `hepbdate` that the parser reads as dates; every other value, including the yes/no answers, is `NA`. The `hepbdate` column is not changed here.

### Duplicate keys

The first row for each key is kept. The key is `uid` and `facility`; for datasets that keep every visit (`cfg$skip_dedup_stage2` is `TRUE`) it is `uid`, `facility` and `uniquekey`.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 10 |
| `cfg$dt` | Names of the datetime columns |
| `cfg$data_source` | Written to the report; does not affect parsing |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_datetime` | Key columns and validated datetime columns, plus `hepbdate_date` where a `hepbdate` column is present |
| `reports/14_datetime_validation_report.txt` | Number of columns checked, values parsed, values set to `NA`, duplicate rows removed, final row count, and the number of dates placed in `hepbdate_date`. Counts only. |

## Function

`validate_datetime(df, cfg, report_filepath = NULL)` returns the datetime sub-frame.

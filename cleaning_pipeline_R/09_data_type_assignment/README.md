# Module 09: Data Type Assignment

## Purpose

Converts every column from text to its R type, using the type each variable has in the data dictionary.

## When it runs

After Module 08. All columns are still character at this point.

## What it does

Each column is matched to a dictionary type by its name, with or without the `.value` suffix.

| Dictionary type | Result |
|-----------------|--------|
| numeric | Number. See *Numbers* below. |
| boolean | `TRUE`/`FALSE`. Accepts `true`, `yes`, `y`, `1`, `t` and `false`, `no`, `n`, `0`, `f`, in any case. Anything else becomes `NA`. |
| categorical | Factor. |
| object | Character. |
| datetime | Date-time (POSIXct, UTC). See *Datetimes* below. |

Columns with no dictionary type stay as character. The key columns `facility`, `uid` and `uniquekey` are never converted.

### Numbers

Values are read one by one, by `parse_numeric_by_shape()` in `00_setup.r`.

| Value | Read as |
|-------|---------|
| `3500`, `3.5`, `-2` | the number |
| `3,500`, `1,234,567.8` | 3500, 1234567.8 (thousands separators removed) |
| `3,5` | 3.5 (decimal comma) |
| text holding one number, e.g. `ANC4`, `36.5 C` | that number |
| text holding several numbers, e.g. a date or `10-12` | `NA` |
| text with no number | `NA` |

Exponent and hexadecimal notation (`1e5`, `0x1A`) is not read as a number.

### Datetimes

Values are read one by one, by `parse_datetime_by_shape()` in `00_setup.r`. Each value is parsed by the rule for its own shape.

| Shape | Examples | Read as |
|-------|----------|---------|
| ISO | `2023-10-19 22:00:00`, `2023-10-19T22:00:00Z`, `2023-10-19` | Year, month, day. A trailing `Z` or UTC offset is dropped; the time is kept as written. |
| Day first | `19/10/2023`, `19-10-2023`, `19.10.2023` | Day, month, year. A two-digit year is read as 20yy. A value that is only valid as month/day/year becomes `NA`. |
| Month name | `March 2, 2026, 12:33 AM`, `2 March 2026`, `19-Oct-2023` | Full or abbreviated English month names; 12-hour or 24-hour time. |
| Anything else | free text, digits without separators | `NA` |

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 08 |
| `cfg` | Configuration list with the type lists `$num`, `$bool`, `$cat`, `$obj`, `$dt` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with typed columns |
| `reports/09_data_type_assignment_report.txt` | Number of columns per type; number of values read by each numeric and datetime rule; the columns holding values other than plain numbers or ISO datetimes. Counts and column names only. |

## Function

`assign_data_types(df, cfg, report_filepath = NULL)` returns the typed data frame.

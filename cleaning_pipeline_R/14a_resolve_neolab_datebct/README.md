# Module 14a: Resolve Missing Neolab `datebct` from Admissions

## Purpose

For the `neolab` dataset, fills missing blood-culture dates with the admission date-time of the same patient, in a new column. The original `datebct.value` column is not changed.

## When it runs

After Module 14 and before Module 15. It adds columns to `df_datetime`, which Module 15 then merges. For any dataset other than `neolab`, or when `cfg$resolve_neolab_datebct` is not `TRUE`, it returns `df_datetime` unchanged.

## What it does

Two columns are added to `df_datetime`.

| Column | Type | Content |
|--------|------|---------|
| `datebct_resolved` | POSIXct | `datebct.value` where present; otherwise the admission date-time; otherwise `NA` |
| `datebct_source` | character | `"original"`, `"from_admission"`, or `NA` when no date is available |

The steps are:

1. If no `datebct.value` is missing, `datebct_resolved` is a copy of `datebct.value` and `datebct_source` is `"original"` on every row. The admissions file is not read.
2. Otherwise the path of the admissions file is taken from `cfg$csv_filepath` by replacing `neolab` with `admissions` in the file name, e.g. `xxx_neolab_YYYYMMDD.csv` gives `xxx_admissions_YYYYMMDD.csv`.
3. Three columns are read from that file: `uid`, `facility` and `datetimeadmission.value` (or `datetimeadmission`). Column names are matched in lower case with spaces removed.
4. The admission date-time is parsed with `parse_datetime_by_shape()` (`00_setup.r`), as in Modules 09 and 14.
5. One row is kept per `uid` and `facility`: the one with the earliest admission date-time.
6. The result is joined to `df_datetime` on `uid` and `facility`, and the two columns are filled.

### When the lookup is not possible

| Situation | Result |
|-----------|--------|
| `datebct.value` is not in `df_datetime` | Both columns are added and are `NA` on every row. A warning is logged. |
| Admissions file not found or not readable, or it lacks `uid`, `facility` or the admission date-time column | `datebct_resolved` is a copy of `datebct.value`; `datebct_source` is `"original"` where a date is present and `NA` elsewhere. A warning is logged. |

## Inputs

| Object | Description |
|--------|-------------|
| `df_datetime` | Datetime sub-frame from Module 14 |
| `cfg$dataset` | The module acts only when this is `"neolab"` |
| `cfg$resolve_neolab_datebct` | See *Configuration* |
| `cfg$csv_filepath` | Path of the neolab input file, from which the admissions path is taken |
| Admissions input file | Read for the three columns named above |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_datetime` | The same sub-frame with `datebct_resolved` and `datebct_source` added |
| `reports/14a_resolve_neolab_datebct_report.txt` | Paths of the two input files, rows in the sub-frame, number of missing `datebct.value`, and the number of rows per `datebct_source`. Written when no value is missing, when the admissions file is not found, and when the lookup completes. |

## Function

`resolve_neolab_datebct(df_datetime, cfg, report_filepath = NULL)` returns `df_datetime`, with the two columns added when the module acts.

## Configuration

| Setting | Effect |
|---------|--------|
| `RESOLVE_NEOLAB_DATEBCT` (`cfg$resolve_neolab_datebct`) | `TRUE` (default) runs the module for the `neolab` dataset. `FALSE` skips it; no columns are added. |

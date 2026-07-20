# Module 12: Boolean Validation

## Purpose
Standardises all boolean columns to R's native `TRUE` / `FALSE` / `NA`. The raw data may contain a variety of representations -- text, numeric, or mixed case -- all of which are normalised to a single consistent form. Produces the `df_boolean` sub-frame.

---

## When It Runs
After Module 10 (duplicate row removal). Second of four parallel validation streams (Modules 11-14).

---

## Logic

For each boolean column in `cfg$bool` that is present in the data frame:

1. Every value is lowercased and stripped of whitespace.
2. It is mapped against two lookup sets:

| Mapped to `TRUE` | Mapped to `FALSE` |
|-----------------|-------------------|
| `"true"`, `"yes"`, `"y"`, `"1"`, `"t"` | `"false"`, `"no"`, `"n"`, `"0"`, `"f"` |

3. Any value not in either set is set to `NA`. No forced or approximate conversions are made.

After column-level validation, `dplyr::distinct()` on (`uid`, `facility`) is applied to deduplicate the boolean sub-frame.

The sub-frame includes the three primary key columns (`facility`, `uid`, `uniquekey`) plus all boolean feature columns.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Stage-1 data frame from Module 10 |
| `cfg$bool` | Character vector of boolean column names |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_boolean` | Validated boolean sub-frame: primary keys + boolean columns, all values as `TRUE`/`FALSE`/`NA` |
| `reports/12_boolean_validation_report.txt` | Count of standardised and invalid values (optional) |

---

## Key Function

**`validate_boolean(df, cfg, report_filepath = NULL)`**

- Selects primary key columns + all boolean feature columns present in `df`.
- Applies the TRUE/FALSE lookup table per column.
- Deduplicates and returns the validated sub-frame as `df_boolean`.

---

## Notes

- Values that were already correctly typed as `TRUE`/`FALSE` (from Module 09) pass through without modification.
- Invalid values (e.g. a free-text string in a boolean column) are set to `NA` and logged.
- The standardisation here ensures that all downstream analysis sees consistent logical values rather than a mix of `"Yes"`, `"1"`, `"TRUE"` etc.

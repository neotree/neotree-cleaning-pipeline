# Module 09: Data Type Assignment

## Purpose
Converts every column to its correct R data type based on the feature lists derived from the data dictionary. After all structural cleaning (Modules 01-08), every column is still stored as character. This module applies the first-pass type coercion so that validation modules (11-14) operate on correctly typed data.

---

## When It Runs
After Module 08 (auto-populated column drop). Type assignment must precede validation, which is type-specific.

---

## Logic

The module uses a helper `in_list(col, lst)` that checks whether a column matches a feature list by its exact name, its base name (without `.value`/`.valuedischarge`), or its base name with `.value` appended -- making the lookup robust to both bare and suffixed column names.

For each column:

| Feature list | Conversion applied |
|-------------|-------------------|
| `cfg$num` (numeric) | `as.numeric()` -- non-numeric values become `NA`. For Metabase exports, thousands-separator commas are stripped first (e.g. `"3,500"` -> `3500`). |
| `cfg$bool` (boolean) | Mapped to `TRUE`/`FALSE`/`NA` via a lookup table: `"true"`, `"yes"`, `"y"`, `"1"` -> `TRUE`; `"false"`, `"no"`, `"n"`, `"0"` -> `FALSE`; anything else -> `NA`. |
| `cfg$cat` (categorical) | `as.factor()` |
| `cfg$obj` (object/free-text) | `as.character()` |
| `cfg$dt` (datetime) | `lubridate::parse_date_time()` with a broad set of format patterns. Unparseable values become `NA`. |

Columns not matched by any feature list are kept as character.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 08 with all columns as character strings |
| `cfg` | Configuration list with feature vectors `$num`, `$bool`, `$cat`, `$obj`, `$dt` |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with correctly typed columns |
| `reports/09_data_type_assignment_report.txt` | Count of columns converted per type (optional) |

---

## Key Function

**`assign_data_types(df, cfg, report_filepath = NULL)`**

- Iterates over all columns and coerces each to the appropriate R type.
- Strips thousands-separator commas for numeric columns in Metabase-format exports.
- Leaves primary key columns (`facility`, `uid`, `uniquekey`) as character regardless.
- Returns the typed data frame.

---

## Notes

- Type failures are silent -- a value that cannot be coerced to the target type becomes `NA` rather than raising an error.
- Thousands-separator stripping (`cfg$data_source == "metabase"`) only applies to numeric columns and only removes commas that appear within a number (e.g. `"3,500"` -> `3500`). This is needed because Metabase formats large numbers with commas.
- The primary key columns (`facility`, `uid`, `uniquekey`) are explicitly excluded from type coercion -- they remain as character strings.
